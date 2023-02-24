use std::{
    io,
    net::{Ipv4Addr, SocketAddr},
    slice,
};

use crate::{Config, PeerConfig, TunnelTransport, UdpTransport, WgInstance};

pub struct IOSTun {
    wg: super::WgInstance<IOSUdpSender, IOSTunWriter>,
}

#[repr(C)]
pub struct IOSTunParams {
    private_key: [u8; 32],
    peer_key: [u8; 32],
    peer_addr_v4: u32,
    peer_port: u32,

    udp_ctx: *const libc::c_void,
    udp_v4_callback: UdpV4Callback,
    udp_v6_callback: UdpV6Callback,

    tun_ctx: *const libc::c_void,
    tun_v4_callback: TunCallbackV4,
    tun_v6_callback: TunCallbackV6,
}

type UdpV4Callback = extern "C" fn(
    ctx: *const libc::c_void,
    addr: u32,
    port: u16,
    buffer: *const u8,
    buf_size: usize,
) -> libc::c_int;

type UdpV6Callback = extern "C" fn(
    ctx: *const libc::c_void,
    addr: [u8; 16],
    port: u16,
    buffer: *const u8,
    buf_size: usize,
) -> libc::c_int;

pub struct IOSUdpSender {
    ctx: *const libc::c_void,
    send_ipv4_udp: UdpV4Callback,
    send_ipv6_udp: UdpV6Callback,
}

impl UdpTransport for IOSUdpSender {
    fn send_packet(&self, addr: SocketAddr, buffer: &[u8]) -> io::Result<()> {
        let result = match addr {
            SocketAddr::V4(addr) => (self.send_ipv4_udp)(
                self.ctx,
                u32::from(*addr.ip()),
                addr.port(),
                buffer.as_ptr(),
                buffer.len(),
            ),
            SocketAddr::V6(addr) => {
                let octets = addr.ip().octets();
                (self.send_ipv6_udp)(self.ctx, octets, addr.port(), buffer.as_ptr(), buffer.len())
            }
        };
        if result != 0 {
            return Err(std::io::Error::from_raw_os_error(0));
        }
        Ok(())
    }
}

impl From<&IOSTunParams> for IOSUdpSender {
    fn from(params: &IOSTunParams) -> Self {
        Self {
            ctx: params.udp_ctx,
            send_ipv4_udp: params.udp_v4_callback,
            send_ipv6_udp: params.udp_v6_callback,
        }
    }
}

type TunCallbackV4 =
    Option<extern "C" fn(ctx: *const libc::c_void, buffer: *const u8, buf_size: usize)>;
type TunCallbackV6 =
    Option<extern "C" fn(ctx: *const libc::c_void, buffer: *const u8, buf_size: usize)>;
pub struct IOSTunWriter {
    ctx: *const libc::c_void,
    send_v4_traffic: TunCallbackV4,
    send_v6_traffic: TunCallbackV6,
}

impl TunnelTransport for IOSTunWriter {
    fn send_v4_packet(&self, buffer: &[u8]) -> io::Result<()> {
        let size = buffer.len();
        let ptr = buffer.as_ptr();
        match self.send_v4_traffic.as_ref() {
            Some(cb) => (cb)(self.ctx, ptr, size),
            None => return Err(io::Error::new(io::ErrorKind::InvalidData, "no v4 callback").into()),
        }

        Ok(())
    }

    fn send_v6_packet(&self, buffer: &[u8]) -> io::Result<()> {
        let size = buffer.len();
        let ptr = buffer.as_ptr();
        match self.send_v6_traffic.as_ref() {
            Some(cb) => (cb)(self.ctx, ptr, size),
            None => return Err(io::Error::new(io::ErrorKind::InvalidData, "no v6 callback").into()),
        }
        Ok(())
    }
}

impl From<&IOSTunParams> for IOSTunWriter {
    fn from(params: &IOSTunParams) -> Self {
        Self {
            ctx: params.tun_ctx,
            send_v4_traffic: params.tun_v4_callback,
            send_v6_traffic: params.tun_v6_callback,
        }
    }
}

#[no_mangle]
pub extern "C" fn abstract_tun_size() -> usize {
    std::mem::size_of::<IOSTun>()
}

#[no_mangle]
pub extern "C" fn abstract_tun_init_instance(
    params: *const IOSTunParams,
    object: *mut *mut IOSTun,
) -> libc::c_int {
    let params = unsafe { &*params };
    let peer_addr = Ipv4Addr::from(params.peer_addr_v4);

    let config = Config {
        private_key: params.private_key,
        peers: vec![PeerConfig {
            endpoint: SocketAddr::new(
                peer_addr.into(),
                params
                    .peer_port
                    .try_into()
                    .expect("port number higher than u16::MAX"),
            ),
            pub_key: params.peer_key,
        }],
    };

    let udp_transport = IOSUdpSender::from(params);
    let tunnel_writer = IOSTunWriter::from(params);

    // SAFETY:
    let ptr = Box::into_raw(Box::new(IOSTun {
        wg: WgInstance::new(config, udp_transport, tunnel_writer),
    }));

    // SAFETY: it's assumed that the provided object pointer can hold a whole pointer
    unsafe { *object = ptr };

    0
}

#[no_mangle]
pub extern "C" fn abstract_tun_handle_tunnel_traffic(
    tun: *mut IOSTun,
    packet: *const u8,
    packet_size: usize,
) {
    let tun: &mut IOSTun = unsafe { &mut *(tun as *mut _) };
    let packet = unsafe { slice::from_raw_parts(packet, packet_size) };
    tun.wg.handle_tunnel_traffic(packet);
}

#[no_mangle]
pub extern "C" fn abstract_tun_handle_udp_packet(
    tun: *mut IOSTun,
    packet: *const u8,
    packet_size: usize,
) {
    let tun: &mut IOSTun = unsafe { &mut *(tun as *mut _) };
    let packet = unsafe { slice::from_raw_parts(packet, packet_size) };
    tun.wg.handle_incoming_tunnel_traffic(packet);
}

#[no_mangle]
pub extern "C" fn abstract_tun_handle_timer_event(tun: *mut IOSTun) {
    let tun: &mut IOSTun = unsafe { &mut *(tun as *mut _) };
    tun.wg.handle_timer_tick();
}

#[no_mangle]
pub extern "C" fn abstract_tun_drop(tun: *mut IOSTun) {
    let tun: Box<IOSTun> = unsafe { std::ptr::read(tun as *mut _) };
    std::mem::drop(tun);
}

#[no_mangle]
pub extern "C" fn abstract_test_fp(fp: extern "C" fn (i32) -> i32, num: i32) -> i32{
    fp(num) + 5
}
