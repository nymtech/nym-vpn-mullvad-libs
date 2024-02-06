use futures::StreamExt;
use std::io;
use std::net::IpAddr;
use std::net::SocketAddr;

#[derive(err_derive::Error, Debug)]
#[error(no_from)]
pub enum Error {
    #[error(display = "Failed to start SOCKS5 server")]
    StartSocksServer(#[error(source)] io::Error),
    #[error(display = "Failed to bind temp socket")]
    BindTempSocket(#[error(source)] io::Error),
    #[error(display = "Failed to find free port")]
    GetTempAddress(#[error(source)] io::Error),
}

pub struct Handle {
    handle: tokio::task::JoinHandle<()>,
    bind_addr: SocketAddr,
}

pub async fn spawn(bind_addr: SocketAddr) -> Result<Handle, Error> {
    let bind_addr = match bind_addr.port() {
        0 => SocketAddr::new(bind_addr.ip(), find_free_port(bind_addr.ip())?),
        _ => bind_addr,
    };
    let socks_server: fast_socks5::server::Socks5Server =
        fast_socks5::server::Socks5Server::bind(bind_addr)
            .await
            .map_err(Error::StartSocksServer)?;

    let handle = tokio::spawn(async move {
        let mut incoming = socks_server.incoming();

        while let Some(new_client) = incoming.next().await {
            match new_client {
                Ok(socket) => {
                    let fut = socket.upgrade_to_socks5();
                    tokio::spawn(async move {
                        match fut.await {
                            Ok(_socket) => log::info!("socks client disconnected"),
                            Err(error) => log::error!("socks client failed: {error}"),
                        }
                    });
                }
                Err(error) => {
                    log::error!("failed to accept socks client: {error}");
                }
            }
        }
    });
    Ok(Handle { handle, bind_addr })
}

impl Handle {
    pub fn bind_addr(&self) -> SocketAddr {
        self.bind_addr
    }

    pub fn close(&self) {
        self.handle.abort();
    }
}

// hack to obtain a random port
fn find_free_port(addr: IpAddr) -> Result<u16, Error> {
    let port = std::net::TcpListener::bind(SocketAddr::new(addr, 0))
        .map_err(Error::BindTempSocket)?
        .local_addr()
        .map_err(Error::GetTempAddress)?
        .port();
    Ok(port)
}
