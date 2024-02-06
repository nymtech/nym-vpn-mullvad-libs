use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;
use test_rpc::net::SocksHandleId;

static SERVERS: Lazy<Mutex<HashMap<SocksHandleId, socks_server::Handle>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

pub async fn start_server(
    bind_addr: SocketAddr,
) -> Result<(SocksHandleId, SocketAddr), test_rpc::Error> {
    let next_nonce = {
        static NONCE: AtomicUsize = AtomicUsize::new(0);
        || NONCE.fetch_add(1, Ordering::Relaxed)
    };
    let id = SocksHandleId(next_nonce());

    let handle = socks_server::spawn(bind_addr).await.map_err(|error| {
        log::error!("Failed to spawn SOCKS server: {error}");
        test_rpc::Error::SocksServer
    })?;

    let bind_addr = handle.bind_addr();

    let mut servers = SERVERS.lock().unwrap();
    servers.insert(id, handle);

    Ok((id, bind_addr))
}

pub async fn stop_server(id: SocksHandleId) -> Result<(), test_rpc::Error> {
    let handle = {
        let mut servers = SERVERS.lock().unwrap();
        servers.remove(&id)
    };

    if let Some(handle) = handle {
        handle.close();
    }
    Ok(())
}
