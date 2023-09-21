#[cfg(not(target_os = "ios"))]
use std::net::Ipv4Addr;
use std::{
    io,
    net::{IpAddr, SocketAddr},
};

use boringtun::noise::{errors::WireGuardError, Tunn, TunnResult};

// #[cfg(target_os = "ios")]
pub mod ios;
#[cfg(all(unix, not(target_os = "ios")))]
pub mod unix;

pub struct WgInstance<S, T> {
    peers: Vec<Peer>,
    udp_transport: S,
    tunnel_transport: T,
    send_buf: Box<[u8; u16::MAX as usize]>,
}

impl<S, T> WgInstance<S, T> {
    pub fn new(config: Config, udp_transport: S, tunnel_transport: T) -> Self {
        let peers = config.create_peers();

        Self {
            peers,
            udp_transport,
            tunnel_transport,
            send_buf: new_send_buf(),
        }
    }

    pub fn tunnel_transport(&mut self) -> &mut T {
        &mut self.tunnel_transport
    }

    pub fn udp_transport(&mut self) -> &mut S {
        &mut self.udp_transport
    }
}

impl<S: UdpTransport, T> WgInstance<S, T> {
    pub fn handle_host_traffic(&mut self, packet: &[u8]) {
        // best not to store u16::MAX bytes on the stack if we want to run on iOS
        let mut send_buf = vec![0u8; 2400];

        match self.peers[0].tun.encapsulate(packet, &mut send_buf) {
            TunnResult::WriteToNetwork(buf) => {
                if let Err(err) = self.udp_transport.send_packet(self.peers[0].endpoint, buf) {
                    log::error!("Failed to send UDP packet: {err}");
                }
            }
            TunnResult::Err(e) => {
                log::error!("Failed to encapsulate IP packet: {e:?}");
            }
            TunnResult::Done => {}
            other => {
                log::error!("Unexpected WireGuard state during encapsulation: {other:?}");
            }
        }
        std::mem::drop(send_buf);
    }

    pub fn handle_timer_tick(&mut self) {
        let mut send_buf = new_send_buf();
        let tun_result = self.peers[0].tun.update_timers(send_buf.as_mut_slice());
        self.inner_handle_timer_tick(tun_result);
    }

    fn inner_handle_timer_tick<'a>(&mut self, first_result: TunnResult<'a>) {
        let mut send_buf;
        let mut current_result;
        current_result = first_result;
        loop {
            match current_result {
                TunnResult::Err(WireGuardError::ConnectionExpired) => {
                    log::warn!("WireGuard handshake has expired");
                    send_buf = new_send_buf();
                    current_result = self.peers[0]
                        .tun
                        .format_handshake_initiation(send_buf.as_mut_slice(), false);
                }

                TunnResult::Err(e) => {
                    log::error!("Failed to prepare routine packet for WireGuard: {e:?}");
                    break;
                }

                TunnResult::WriteToNetwork(packet) => {
                    let _ = self
                        .udp_transport
                        .send_packet(self.peers[0].endpoint, packet);
                    break;
                }

                TunnResult::Done => {
                    break;
                }
                other => {
                    log::error!("Unexpected WireGuard state {other:?}");
                    break;
                }
            }
        }
    }
}

impl<S: UdpTransport, T: TunnelTransport> WgInstance<S, T> {
    pub fn handle_tunnel_traffic(&mut self, packet: &[u8]) {
        match self.peers[0]
            .tun
            .decapsulate(None, packet, self.send_buf.as_mut_slice())
        {
            TunnResult::WriteToNetwork(data) => {
                if let Err(err) = self.udp_transport.send_packet(self.peers[0].endpoint, data) {
                    log::error!("Failed to send packet to peer {err}");
                }

                match self.peers[0]
                    .tun
                    .decapsulate(None, &[], self.send_buf.as_mut_slice())
                {
                    TunnResult::WriteToNetwork(data) => {
                        if let Err(err) =
                            self.udp_transport.send_packet(self.peers[0].endpoint, data)
                        {
                            log::error!("Failed to send packet to peer {err}");
                        }
                    }
                    _ => {}
                }
            }
            TunnResult::WriteToTunnelV4(clear_packet, _addr) => {
                if let Err(err) = self.tunnel_transport.send_v4_packet(clear_packet) {
                    log::error!("Failed to send packet to tunnel interface: {err}");
                }
            }
            TunnResult::WriteToTunnelV6(clear_packet, _addr) => {
                if let Err(err) = self.tunnel_transport.send_v6_packet(clear_packet) {
                    log::error!("Failed to send packet to tunnel interface: {err}");
                }
            }
            anything_else => {
                log::error!("Unexpected WireGuard result: {anything_else:?}");
            }
        }
    }
}

struct Peer {
    endpoint: SocketAddr,
    tun: Tunn,
}

pub struct Config {
    pub private_key: [u8; 32],
    #[cfg(not(target_os = "ios"))]
    pub address: Ipv4Addr,
    pub peers: Vec<PeerConfig>,
}

impl Config {
    fn create_peers(&self) -> Vec<Peer> {
        self.peers
            .iter()
            .enumerate()
            .map(|(idx, peer)| {
                let tun = *Tunn::new(
                    x25519_dalek::StaticSecret::from(self.private_key),
                    x25519_dalek::PublicKey::from(peer.pub_key),
                    None,
                    None,
                    idx.try_into().expect("more than u32::MAX peers"),
                    None,
                )
                .expect("in practice this should never fail");
                Peer {
                    endpoint: peer.endpoint,
                    tun,
                }
            })
            .collect()
    }
}

pub struct PeerConfig {
    pub endpoint: SocketAddr,
    pub pub_key: [u8; 32],
}

pub trait UdpTransport {
    /// This method should return immediately
    fn send_packet(&mut self, addr: SocketAddr, buffer: &[u8]) -> io::Result<()>;
    // /// Should return immediately
    // fn receive_packet(&self, addr: IpAddr, buffer: &[u8]) -> io::Result<()>;
}

pub trait TunnelTransport {
    fn send_v4_packet(&mut self, buffer: &[u8]) -> io::Result<()>;
    fn send_v6_packet(&mut self, buffer: &[u8]) -> io::Result<()>;
}

#[async_trait::async_trait]
pub trait AsyncUdpTransport {
    async fn send_packet(&self, addr: IpAddr, buffer: &[u8]) -> io::Result<()>;
    async fn receive_packet(&self, addr: IpAddr, buffer: &[u8]) -> io::Result<()>;
}

fn new_send_buf() -> Box<[u8; u16::MAX as usize]> {
    Box::<[u8; u16::MAX as usize]>::try_from(vec![0u8; u16::MAX as usize]).unwrap()
}
