pub mod client;
pub mod types;

#[cfg(unix)]
use std::{env, os::unix::fs::PermissionsExt};
use std::{future::Future, io, path::Path};
#[cfg(windows)]
use tokio::net::windows::named_pipe::{NamedPipeServer, ServerOptions};
#[cfg(unix)]
use tokio::{
    fs,
    net::{UnixListener, UnixStream},
};
#[cfg(unix)]
use tokio_stream::wrappers::UnixListenerStream;
use tonic::transport::{Endpoint, Server, Uri};
use tower::service_fn;

pub use tonic::{async_trait, transport::Channel, Code, Request, Response, Status};

pub type ManagementServiceClient =
    types::management_service_client::ManagementServiceClient<Channel>;
pub use types::management_service_server::{ManagementService, ManagementServiceServer};

#[cfg(unix)]
use once_cell::sync::Lazy;
#[cfg(unix)]
static MULLVAD_MANAGEMENT_SOCKET_GROUP: Lazy<Option<String>> =
    Lazy::new(|| env::var("MULLVAD_MANAGEMENT_SOCKET_GROUP").ok());

pub const CUSTOM_LIST_LIST_NOT_FOUND_DETAILS: &[u8] = b"custom_list_list_not_found";
pub const CUSTOM_LIST_LIST_EXISTS_DETAILS: &[u8] = b"custom_list_list_exists";

#[derive(err_derive::Error, Debug)]
#[error(no_from)]
pub enum Error {
    #[error(display = "Management RPC server or client error")]
    GrpcTransportError(#[error(source)] tonic::transport::Error),

    #[error(display = "Failed to open IPC pipe/socket")]
    StartServerError(#[error(source)] io::Error),

    #[error(display = "Failed to initialize pipe/socket security attributes")]
    SecurityAttributes(#[error(source)] io::Error),

    #[error(display = "Unable to set permissions for IPC endpoint")]
    PermissionsError(#[error(source)] io::Error),

    #[cfg(unix)]
    #[error(display = "Group not found")]
    NoGidError,

    #[cfg(unix)]
    #[error(display = "Failed to obtain group ID")]
    ObtainGidError(#[error(source)] nix::Error),

    #[cfg(unix)]
    #[error(display = "Failed to set group ID")]
    SetGidError(#[error(source)] nix::Error),

    #[error(display = "gRPC call returned error")]
    Rpc(#[error(source)] tonic::Status),

    #[error(display = "Failed to parse gRPC response")]
    InvalidResponse(#[error(source)] types::FromProtobufTypeError),

    #[error(display = "Duration is too large")]
    DurationTooLarge,

    #[error(display = "Unexpected non-UTF8 string")]
    PathMustBeUtf8,

    #[error(display = "Missing daemon event")]
    MissingDaemonEvent,

    #[error(display = "This voucher code is invalid")]
    InvalidVoucher,

    #[error(display = "This voucher code has already been used")]
    UsedVoucher,

    #[error(display = "There are too many devices on the account. One must be revoked to log in")]
    TooManyDevices,

    #[error(display = "You are already logged in. Log out to create a new account")]
    AlreadyLoggedIn,

    #[error(display = "The account does not exist")]
    InvalidAccount,

    #[error(display = "There is no such device")]
    DeviceNotFound,

    #[error(display = "Location data is unavailable")]
    NoLocationData,

    #[error(display = "A custom list with that name already exists")]
    CustomListExists,

    #[error(display = "A custom list with that name does not exist")]
    CustomListListNotFound,

    #[error(display = "Location already exists in the custom list")]
    LocationExistsInCustomList,

    #[error(display = "Location was not found in the custom list")]
    LocationNotFoundInCustomlist,

    #[error(display = "Could not retrieve API access methods from settings")]
    ApiAccessMethodSettingsNotFound,

    #[error(display = "An access method with that id does not exist")]
    ApiAccessMethodNotFound,
}

#[deprecated(note = "Prefer MullvadProxyClient")]
pub async fn new_rpc_client() -> Result<ManagementServiceClient, Error> {
    // The URI will be ignored
    Endpoint::from_static("lttp://[::]:50051")
        .connect_with_connector(service_fn(move |_: Uri| {
            UnixStream::connect(mullvad_paths::get_rpc_socket_path())
        }))
        .await
        .map(ManagementServiceClient::new)
        .map_err(Error::GrpcTransportError)
}

pub use client::MullvadProxyClient;

pub type ServerJoinHandle = tokio::task::JoinHandle<Result<(), Error>>;

pub async fn spawn_rpc_server<T: ManagementService, F: Future<Output = ()> + Send + 'static>(
    service: T,
    abort_rx: F,
) -> std::result::Result<ServerJoinHandle, Error> {
    let socket_path = mullvad_paths::get_rpc_socket_path();

    let clients = server_transport(&socket_path).await?;

    Ok(tokio::spawn(async move {
        let result = Server::builder()
            .add_service(ManagementServiceServer::new(service))
            .serve_with_incoming_shutdown(clients, abort_rx)
            .await
            .map_err(Error::GrpcTransportError);

        if let Err(err) = fs::remove_file(socket_path).await {
            log::error!("Failed to remove IPC socket: {}", err);
        }

        result
    }))
}

#[cfg(unix)]
async fn server_transport(socket_path: &Path) -> Result<UnixListenerStream, Error> {
    let clients =
        UnixListenerStream::new(UnixListener::bind(socket_path).map_err(Error::StartServerError)?);

    let mode = if let Some(group_name) = &*MULLVAD_MANAGEMENT_SOCKET_GROUP {
        let group = nix::unistd::Group::from_name(group_name)
            .map_err(Error::ObtainGidError)?
            .ok_or(Error::NoGidError)?;
        nix::unistd::chown(socket_path, None, Some(group.gid)).map_err(Error::SetGidError)?;
        0o760
    } else {
        0o766
    };
    fs::set_permissions(socket_path, PermissionsExt::from_mode(mode))
        .await
        .map_err(Error::PermissionsError)?;

    Ok(clients)
}

#[cfg(windows)]
async fn server_transport(socket_path: &Path) -> Result<NamedPipeServer, Error> {
    // FIXME: allow everyone access
    ServerOptions::new()
        .reject_remote_clients(true)
        .first_pipe_instance(true)
        .access_inbound(true)
        .access_outbound(true)
        .create(socket_path)
        .map_err(Error::StartServerError)
}
