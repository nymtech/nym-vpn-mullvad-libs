use std::{
    io,
    net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr},
    slice,
    sync::Once,
};

use crate::{Config, PeerConfig, TunnelTransport, UdpTransport, WgInstance};

mod data;
use data::SwiftDataArray;
mod udp_session;

const INIT_LOGGING: Once = Once::new();

pub struct IOSTun {
    wg: super::WgInstance<IOSUdpSender, IOSTunWriter>,
}

#[repr(C)]
pub struct IOSTunParams {
    private_key: [u8; 32],
    peer_key: [u8; 32],
    peer_addr_version: u8,
    peer_addr_bytes: [u8; 16],
    peer_port: u16,
}

impl IOSTunParams {
    fn peer_addr(&self) -> Option<IpAddr> {
        match self.peer_addr_version as i32 {
            libc::AF_INET => Some(
                Ipv4Addr::new(
                    self.peer_addr_bytes[0],
                    self.peer_addr_bytes[1],
                    self.peer_addr_bytes[2],
                    self.peer_addr_bytes[3],
                )
                .into(),
            ),
            libc::AF_INET6 => Some(Ipv6Addr::from(self.peer_addr_bytes).into()),
            _other => None,
        }
    }
}


pub struct IOSUdpSender {
    // current assumption is that we only send data to a single endpoint.
    v4_buffer: Option<SwiftDataArray>,
    v6_buffer: Option<SwiftDataArray>,
}

impl IOSUdpSender {
    fn new() -> Self {
        Self {
            v4_buffer: None,
            v6_buffer: None,
        }
    }
}

impl UdpTransport for IOSUdpSender {
    fn send_packet(&mut self, addr: SocketAddr, packet: &[u8]) -> io::Result<()> {
        match (addr, &mut self.v4_buffer, &mut self.v6_buffer) {
            (SocketAddr::V4(_addr), Some(buffer), _) => {
                buffer.append(packet);
            }

            (SocketAddr::V6(_addr), _, Some(buffer)) => {
                buffer.append(packet);
            }
            _ => {
                log::trace!("No buffer assigned");
            }
        };
        Ok(())
    }
}

pub struct IOSTunWriter {
    v4_buffer: Option<SwiftDataArray>,
    v6_buffer: Option<SwiftDataArray>,
}

impl IOSTunWriter {
    fn new() -> Self {
        Self {
            v4_buffer: None,
            v6_buffer: None,
        }
    }
}

impl TunnelTransport for IOSTunWriter {
    fn send_v4_packet(&mut self, packet: &[u8]) -> io::Result<()> {
        if let Some(buf) = &mut self.v4_buffer {
            buf.append(packet);
        }

        Ok(())
    }

    fn send_v6_packet(&mut self, packet: &[u8]) -> io::Result<()> {
        if let Some(buf) = &mut self.v6_buffer {
            buf.append(packet);
        }

        Ok(())
    }
}

#[no_mangle]
pub extern "C" fn abstract_tun_size() -> usize {
    std::mem::size_of::<IOSTun>()
}

#[no_mangle]
pub extern "C" fn abstract_tun_init_instance(params: *const IOSTunParams) -> *mut IOSTun {
    INIT_LOGGING.call_once(|| {
        let _ = oslog::OsLogger::new("net.mullvad.MullvadVPN.ShadowSocks")
            .level_filter(log::LevelFilter::Error)
            .init();
    });

    let params = unsafe { &*params };
    let peer_addr = match params.peer_addr() {
        Some(addr) => addr,
        None => {
            return std::ptr::null_mut();
        }
    };

    let config = Config {
        // TODO: Use real address
        #[cfg(not(target_os = "ios"))]
        address: Ipv4Addr::UNSPECIFIED,
        private_key: params.private_key,
        peers: vec![PeerConfig {
            endpoint: SocketAddr::new(peer_addr, params.peer_port),
            pub_key: params.peer_key,
        }],
    };

    let udp_transport = IOSUdpSender::new();
    let tunnel_writer = IOSTunWriter::new();

    // SAFETY:
    let ptr = Box::into_raw(Box::new(IOSTun {
        wg: WgInstance::new(config, udp_transport, tunnel_writer),
    }));

    ptr
}

#[no_mangle]
pub extern "C" fn abstract_tun_handle_host_traffic(
    tun: *mut IOSTun,
    packets: *mut SwiftDataArray,
    v4_output_buffer: *mut SwiftDataArray,
    v6_output_buffer: *mut SwiftDataArray,
) {
    let tun: &mut IOSTun = unsafe { &mut *(tun) };
    let (mut packets, v4_output_buffer, v6_output_buffer) = unsafe {
        (
            SwiftDataArray::from_ptr(packets),
            SwiftDataArray::from_ptr(v4_output_buffer),
            SwiftDataArray::from_ptr(v6_output_buffer),
        )
    };
    tun.wg.udp_transport().v4_buffer = Some(v4_output_buffer);
    tun.wg.udp_transport().v6_buffer = Some(v6_output_buffer);
    for mut packet in packets.iter() {
        tun.wg.handle_host_traffic(packet.as_mut());
    }

    let _output_buffer = tun.wg.udp_transport().v4_buffer.take();
    let _output_buffer = tun.wg.udp_transport().v6_buffer.take();
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
pub extern "C" fn abstract_tun_handle_timer_event(tun: *mut IOSTun) {
    let tun: &mut IOSTun = unsafe { &mut *(tun as *mut _) };
    tun.wg.handle_timer_tick();
}

#[no_mangle]
pub extern "C" fn abstract_tun_drop(tun: *mut IOSTun) {
    if tun.is_null() {
        return;
    }
    let tun: Box<IOSTun> = unsafe { Box::from_raw(tun) };
    std::mem::drop(tun);
}
