
use talpid_core::tunnel::TunnelMetadata;
use futures::stream::TryStreamExt;
use parity_tokio_ipc::Endpoint as IpcEndpoint;
use std::{
    collections::HashMap,
    pin::Pin,
    task::{Context, Poll},
};
#[cfg(any(target_os = "linux", windows))]
use talpid_types::ErrorExt;
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tonic::{
    self,
    transport::{server::Connected, Server},
    Request, Response,
};

mod proto {
    tonic::include_proto!("talpid_openvpn_plugin");
}
pub use proto::{
    openvpn_event_proxy_server::{OpenvpnEventProxy, OpenvpnEventProxyServer},
    EventDetails,
};

#[derive(err_derive::Error, Debug)]
pub enum Error {
    /// Failure to set up the IPC server.
    #[error(display = "Failed to create pipe or Unix socket")]
    StartServer(#[error(source)] std::io::Error),

    /// An error occurred while the server was running.
    #[error(display = "Tonic error")]
    TonicError(#[error(source)] tonic::transport::Error),
}

/// Implements a gRPC service used to process events sent to by OpenVPN.
pub struct OpenvpnEventProxyImpl<
    L: (Fn() -> std::pin::Pin<Box<dyn std::future::Future<Output = ()> + Send>>)
        + Send
        + Sync
        + 'static,
> {
    pub on_event: L,
    pub user_pass_file_path: super::PathBuf,
    pub proxy_auth_file_path: Option<super::PathBuf>,
    pub abort_server_tx: triggered::Trigger,
    #[cfg(target_os = "linux")]
    pub route_manager_handle: super::routing::RouteManagerHandle,
    #[cfg(target_os = "linux")]
    pub ipv6_enabled: bool,
}

impl<
        L: (Fn() -> std::pin::Pin<Box<dyn std::future::Future<Output = ()> + Send>>)
            + Send
            + Sync
            + 'static,
    > OpenvpnEventProxyImpl<L>
{
    async fn up_inner(
        &self,
        request: Request<EventDetails>,
    ) -> std::result::Result<Response<()>, tonic::Status> {
        let env = request.into_inner().env;
        // (self.on_event)(super::TunnelEvent::InterfaceUp(
        //     Self::get_tunnel_metadata(&env)?,
        //     talpid_types::net::AllowedTunnelTraffic::All,
        // ))
        // .await;
        Ok(Response::new(()))
    }

    async fn route_up_inner(
        &self,
        request: Request<EventDetails>,
    ) -> std::result::Result<Response<()>, tonic::Status> {
        let env = request.into_inner().env;

        let _ = tokio::fs::remove_file(&self.user_pass_file_path).await;
        if let Some(ref file_path) = &self.proxy_auth_file_path {
            let _ = tokio::fs::remove_file(file_path).await;
        }

        #[cfg(target_os = "linux")]
        {
            let route_handle = self.route_manager_handle.clone();
            let ipv6_enabled = self.ipv6_enabled;

            let routes = super::extract_routes(&env)
                .map_err(|err| {
                    log::error!("{}", err.display_chain_with_msg("Failed to obtain routes"));
                    tonic::Status::failed_precondition("Failed to obtain routes")
                })?
                .into_iter()
                .filter(|route| route.prefix.is_ipv4() || ipv6_enabled)
                .collect();

            if let Err(error) = route_handle.add_routes(routes).await {
                log::error!("{}", error.display_chain());
                return Err(tonic::Status::failed_precondition("Failed to add routes"));
            }
            if let Err(error) = route_handle.create_routing_rules(ipv6_enabled).await {
                log::error!("{}", error.display_chain());
                return Err(tonic::Status::failed_precondition("Failed to add routes"));
            }
        }

        let metadata = Self::get_tunnel_metadata(&env)?;

        #[cfg(windows)]
        {
            let tunnel_device = metadata.interface.clone();
            let luid = crate::windows::luid_from_alias(tunnel_device).map_err(|error| {
                log::error!("{}", error.display_chain_with_msg("luid_from_alias failed"));
                tonic::Status::unavailable("failed to obtain interface luid")
            })?;
            crate::windows::wait_for_addresses(luid)
                .await
                .map_err(|error| {
                    log::error!(
                        "{}",
                        error.display_chain_with_msg("wait_for_addresses failed")
                    );
                    tonic::Status::unavailable("wait_for_addresses failed")
                })?;
        }

        // (self.on_event)(super::TunnelEvent::Up(metadata)).await;

        Ok(Response::new(()))
    }

    fn get_tunnel_metadata(
        env: &HashMap<String, String>,
    ) -> std::result::Result<TunnelMetadata, tonic::Status> {
        let tunnel_alias = env
            .get("dev")
            .ok_or_else(|| tonic::Status::invalid_argument("missing tunnel alias"))?
            .to_string();

        let mut ips = vec![env
            .get("ifconfig_local")
            .ok_or_else(|| {
                tonic::Status::invalid_argument("missing \"ifconfig_local\" in up event")
            })?
            .parse()
            .map_err(|_| tonic::Status::invalid_argument("Invalid tunnel IPv4 address"))?];
        if let Some(ipv6_address) = env.get("ifconfig_ipv6_local") {
            ips.push(
                ipv6_address.parse().map_err(|_| {
                    tonic::Status::invalid_argument("Invalid tunnel IPv6 address")
                })?,
            );
        }
        let ipv4_gateway = env
            .get("route_vpn_gateway")
            .ok_or_else(|| {
                tonic::Status::invalid_argument("No \"route_vpn_gateway\" in tunnel up event")
            })?
            .parse()
            .map_err(|_| {
                tonic::Status::invalid_argument("Invalid tunnel gateway IPv4 address")
            })?;
        let ipv6_gateway = if let Some(ipv6_address) = env.get("route_ipv6_gateway_1") {
            Some(ipv6_address.parse().map_err(|_| {
                tonic::Status::invalid_argument("Invalid tunnel gateway IPv6 address")
            })?)
        } else {
            None
        };

        Ok(TunnelMetadata {
            interface: tunnel_alias,
            ips,
            ipv4_gateway,
            ipv6_gateway,
        })
    }
}

#[tonic::async_trait]
impl<
        L: (Fn() -> std::pin::Pin<Box<dyn std::future::Future<Output = ()> + Send>>)
            + Send
            + Sync
            + 'static,
    > OpenvpnEventProxy for OpenvpnEventProxyImpl<L>
{
    async fn auth_failed(
        &self,
        request: Request<EventDetails>,
    ) -> std::result::Result<Response<()>, tonic::Status> {
        let env = request.into_inner().env;
        (self.on_event)(super::TunnelEvent::AuthFailed(
            env.get("auth_failed_reason").cloned(),
        ))
        .await;
        Ok(Response::new(()))
    }

    async fn up(
        &self,
        request: Request<EventDetails>,
    ) -> std::result::Result<Response<()>, tonic::Status> {
        self.up_inner(request).await.map_err(|error| {
            self.abort_server_tx.trigger();
            error
        })
    }

    async fn route_up(
        &self,
        request: Request<EventDetails>,
    ) -> std::result::Result<Response<()>, tonic::Status> {
        self.route_up_inner(request).await.map_err(|error| {
            self.abort_server_tx.trigger();
            error
        })
    }

    async fn route_predown(
        &self,
        _request: Request<EventDetails>,
    ) -> std::result::Result<Response<()>, tonic::Status> {
        // (self.on_event)(super::TunnelEvent::Down).await;
        Ok(Response::new(()))
    }
}

pub async fn start<L>(
    event_proxy: L,
    abort_rx: triggered::Listener,
) -> std::result::Result<(tokio::task::JoinHandle<Result<(), Error>>, String), Error>
where
    L: OpenvpnEventProxy + Sync + Send + 'static,
{
    let uuid = uuid::Uuid::new_v4().to_string();
    let ipc_path = if cfg!(windows) {
        format!("//./pipe/talpid-openvpn-{}", uuid)
    } else {
        format!("/tmp/talpid-openvpn-{}", uuid)
    };

    let endpoint = IpcEndpoint::new(ipc_path.clone());
    let incoming = endpoint.incoming().map_err(Error::StartServer)?;
    Ok((
        tokio::spawn(async move {
            Server::builder()
                .add_service(OpenvpnEventProxyServer::new(event_proxy))
                .serve_with_incoming_shutdown(incoming.map_ok(StreamBox), abort_rx)
                .await
                .map_err(Error::TonicError)
        }),
        ipc_path,
    ))
}

#[derive(Debug)]
pub struct StreamBox<T: AsyncRead + AsyncWrite>(pub T);
impl<T: AsyncRead + AsyncWrite> Connected for StreamBox<T> {
    type ConnectInfo = Option<()>;

    fn connect_info(&self) -> Self::ConnectInfo {
        None
    }
}
impl<T: AsyncRead + AsyncWrite + Unpin> AsyncRead for StreamBox<T> {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.0).poll_read(cx, buf)
    }
}
impl<T: AsyncRead + AsyncWrite + Unpin> AsyncWrite for StreamBox<T> {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        Pin::new(&mut self.0).poll_write(cx, buf)
    }

    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.0).poll_flush(cx)
    }

    fn poll_shutdown(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
    ) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.0).poll_shutdown(cx)
    }
}
