#[cfg(target_os = "ios")]
fn main() {}

use std::{
    net::{Ipv4Addr, SocketAddr},
    sync, thread,
    time::Duration,
};

use base64::Engine;

struct Args {
    private_addr: Ipv4Addr,
    private_key: [u8; 32],
    listen_addr: SocketAddr,
    peer_endpoint: SocketAddr,
    peer_private_addr: Ipv4Addr,
    peer_key: [u8; 32],
}

fn read_args() -> Args {
    let mut args = std::env::args();
    // drop first arg always
    let _ = args.next();

    let private_addr = args.next().unwrap().parse().unwrap();

    let mut private_key = [0u8; 32];
    private_key.copy_from_slice(
        base64::prelude::BASE64_STANDARD
            .decode(args.next().unwrap())
            .unwrap()
            .as_slice(),
    );

    let listen_addr = args.next().unwrap().parse().unwrap();

    let peer_private_addr = args.next().unwrap().parse().unwrap();
    let peer_endpoint = args.next().unwrap().parse().unwrap();

    let mut peer_key = [0u8; 32];
    peer_key.copy_from_slice(
        base64::prelude::BASE64_STANDARD
            .decode(args.next().unwrap())
            .unwrap()
            .as_slice(),
    );

    return Args {
        private_addr,
        private_key,
        listen_addr,
        peer_private_addr,
        peer_endpoint,
        peer_key,
    };
}

#[cfg(not(target_os = "ios"))]
fn main() {
    use abstract_tun::{
        unix::{TunWriteHandle, UdpTransport},
        Config, PeerConfig, WgInstance,
    };
    use base64::Engine;
    use std::{net::Ipv4Addr, sync, thread, time::Duration};

    const IDLE_INTERVAL: Duration = Duration::from_millis(250);

    enum WgRx {
        NewTunTraffic(Vec<u8>),
        NewRelayTraffic(Vec<u8>),
        IdleInterval,
    }

    env_logger::init();
    let args = read_args();
    // let mut private_key = [0u8; 32];
    // private_key.copy_from_slice(
    //     base64::prelude::BASE64_STANDARD
    //         .decode("aFDGUbzpkW2yNVK5SMEwK8JuOsKup29D4JUTXlNbHn0=")
    //         .unwrap()
    //         .as_slice(),
    // );
    // let address: Ipv4Addr = "10.66.104.187".parse().unwrap();
    // let mut pub_key = [0u8; 32];
    // pub_key.copy_from_slice(
    //     base64::prelude::BASE64_STANDARD
    //         .decode("gSLSfY2zNFRczxHndeda258z+ayMvd7DqTlKYlKWJUo=")
    //         .unwrap()
    //         .as_slice(),
    // );
    // let peer = PeerConfig {
    //     endpoint: "46.19.136.226:51820".parse().unwrap(),
    //     pub_key,
    // };

    // let conf = Config {
    //     private_key,
    //     address,
    //     peers: vec![peer],
    // };
    //
    log::error!("Will listen on {}, send traffic to {}, with private address {}", args.listen_addr, args.peer_endpoint, args.private_addr);
    let peer = PeerConfig {
        endpoint: args.peer_endpoint,
        pub_key: args.peer_key,
    };

    let conf = Config {
        private_key: args.private_key,
        address: args.private_addr,
        peers: vec![peer],
    };

    let udp_transport = UdpTransport::with_listen_addr(args.listen_addr).unwrap();
    let udp_receiver = udp_transport.clone();
    let tun = TunWriteHandle::new(args.private_addr).unwrap();
    let tun_reader = tun.read_handle();

    let (tun_incoming_tx, tun_incoming_rx) = sync::mpsc::channel::<WgRx>();
    log::error!("Will listen on {}, send traffic to {}", args.listen_addr, args.peer_endpoint);

    let interval_tx = tun_incoming_tx.clone();
    thread::spawn(move || loop {
        thread::sleep(IDLE_INTERVAL);
        if interval_tx.send(WgRx::IdleInterval).is_err() {
            return;
        }
    });

    let udp_tx = tun_incoming_tx.clone();
    thread::spawn(move || {
        let mut buffer = vec![0u8; u16::MAX as usize];
        loop {
            if let Ok(size) = udp_receiver.receive_packet(buffer.as_mut_slice()) {
                let packet = buffer[..size].to_vec();
                if udp_tx.send(WgRx::NewRelayTraffic(packet)).is_err() {
                    return;
                }
            }
        }
    });

    thread::spawn(move || {
        let mut buffer = vec![0u8; u16::MAX as usize];
        loop {
            if let Ok(size) = tun_reader.read(buffer.as_mut_slice()) {
                let packet = buffer[..size].to_vec();
                if tun_incoming_tx.send(WgRx::NewTunTraffic(packet)).is_err() {
                    return;
                }
            }
        }
    });

    let mut wg = WgInstance::new(conf, udp_transport, tun);
    while let Ok(msg) = tun_incoming_rx.recv() {
        match msg {
            WgRx::NewRelayTraffic(traffic) => {
                wg.handle_tunnel_traffic(&traffic);
            }
            WgRx::IdleInterval => {
                wg.handle_timer_tick();
            }
            WgRx::NewTunTraffic(traffic) => {
                wg.handle_host_traffic(&traffic);
            }
        }
    }
}
