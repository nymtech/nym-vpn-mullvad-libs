#[cfg(target_os = "android")]
use crate::{DaemonCommand, DaemonEventSender};
use futures::{
    channel::{mpsc, oneshot},
    SinkExt, StreamExt,
};
use mullvad_api::{
    availability::ApiAvailabilityHandle,
    proxy::{ApiConnectionMode, ProxyConfig},
    AddressCache, ConnectionModeActorHandle,
};
use mullvad_relay_selector::RelaySelector;
use mullvad_types::access_method::{AccessMethod, AccessMethodSetting, BuiltInAccessMethod};
#[cfg(target_os = "android")]
use talpid_core::mpsc::Sender;
use talpid_core::tunnel_state_machine::TunnelCommand;
use talpid_types::net::{openvpn::ProxySettings, AllowedEndpoint, Endpoint, TransportProtocol};
use tokio::sync::broadcast;

/// A (tiny) ator listening for broadcasts when the currently active [`AccessMethodSetting`] changes.
/// When such a change is broadcasted, the daemon should punch an appropriate hole
/// in the firewall
///
/// Notifies the tunnel state machine that the API (real or proxied) endpoint has
/// changed.
pub(super) struct ApiEndpointUpdateListener {
    cmd_rx: mpsc::UnboundedReceiver<Message>,
    rx: broadcast::Receiver<AccessMethodSetting>,
    tunnel_cmd_tx: Option<mpsc::UnboundedSender<TunnelCommand>>,
    relay_selector: RelaySelector,
    address_cache: AddressCache,
}

#[derive(Clone)]
pub(super) struct ApiEndpointUpdateListenerHandle {
    cmd_tx: mpsc::UnboundedSender<Message>,
}

pub(super) enum Message {
    UpdateTunnelCommandChannel(mpsc::UnboundedSender<TunnelCommand>),
}

impl ApiEndpointUpdateListenerHandle {
    pub async fn set_tunnel_command_tx(
        &mut self,
        tunnel_cmd_tx: mpsc::UnboundedSender<TunnelCommand>,
    ) {
        log::info!("Updating `tunnel_cmd_tx`!");
        let _ = self
            .cmd_tx
            .send(Message::UpdateTunnelCommandChannel(tunnel_cmd_tx))
            .await;
    }
}

impl ApiEndpointUpdateListener {
    pub fn new(
        connection_mode_actor: ConnectionModeActorHandle,
        relay_selector: RelaySelector,
        address_cache: AddressCache,
    ) -> ApiEndpointUpdateListenerHandle {
        let (cmd_tx, cmd_rx) = mpsc::unbounded();
        tokio::spawn(
            ApiEndpointUpdateListener {
                cmd_rx,
                rx: connection_mode_actor.subscribe(),
                tunnel_cmd_tx: None,
                relay_selector,
                address_cache,
            }
            .run(),
        );
        ApiEndpointUpdateListenerHandle { cmd_tx }
    }

    async fn run(mut self) {
        log::trace!("Starting a new `ApiEndpointUpdateListener` agent");
        loop {
            tokio::select! {
                next = self.rx.recv() => {
                    match next {
                        Ok(new_access_method) => self.handle_subscription_event(new_access_method).await,
                        Err(broadcast::error::RecvError::Closed) => {
                            log::error!("Sender was unexpectedly dropped");
                            break;
                        }
                        Err(broadcast::error::RecvError::Lagged(num_skipped)) => {
                            log::warn!("Skipped {num_skipped} connection mode broadcast events");
                        }
                    }
                }
                cmd = self.cmd_rx.next() => {
                    match cmd {
                        Some(msg) => self.handle_command(msg).await,
                        None => break,
                    }
                }
            }
        }
    }

    async fn handle_subscription_event(&mut self, new_access_method: AccessMethodSetting) {
        match self.update_firewall(new_access_method).await {
            Some(true) => {
                log::info!("Firewall updated!");
            }
            Some(false) => {
                log::error!("Tunnel state machine is not running")
            }
            None => {
                log::error!("Could not communicate with the Tunnel State Machine");
            }
        }
    }

    async fn handle_command(&mut self, message: Message) {
        match message {
            Message::UpdateTunnelCommandChannel(tunnel_cmd_tx) => {
                self.tunnel_cmd_tx = Some(tunnel_cmd_tx)
            }
        }
    }

    /// Tell the daemon to update the firewall to accomodate the new [`AccessMethodSetting`].
    async fn update_firewall(&self, access_method: AccessMethodSetting) -> Option<bool> {
        let tunnel_tx = self.tunnel_cmd_tx.clone()?;
        // TODO(markus): these two bindings could be done in a more succint way.
        let connection_mode = access_method_to_api_connection_mode(
            access_method.access_method,
            self.relay_selector.clone(),
        );
        let allowed_endpoint = get_allowed_endpoint(match connection_mode.get_endpoint() {
            Some(endpoint) => endpoint,
            None => Endpoint::from_socket_address(
                self.address_cache.get_address().await,
                TransportProtocol::Tcp,
            ),
        });

        let (result_tx, result_rx) = oneshot::channel();
        let _ = tunnel_tx.unbounded_send(TunnelCommand::AllowEndpoint(
            allowed_endpoint.clone(),
            result_tx,
        ));
        // Wait for the firewall policy to be updated.
        let _ = result_rx.await;
        log::debug!(
            "API endpoint: {endpoint}",
            endpoint = allowed_endpoint.endpoint
        );

        Some(true)
    }
}

/// Ad-hoc version of [`std::convert::From::from`], but since some
/// [`AccessMethod`]s require extra logic/data from [`RelaySelector`] before
/// they may be mapped to a [`ApiConnectionMode`], the standard
/// [`std::convert::From`] trait can not be implemented.
fn access_method_to_api_connection_mode(
    access_method: AccessMethod,
    relay_selector: RelaySelector,
) -> ApiConnectionMode {
    use mullvad_types::access_method;
    match access_method {
        AccessMethod::BuiltIn(access_method) => match access_method {
            BuiltInAccessMethod::Direct => ApiConnectionMode::Direct,
            BuiltInAccessMethod::Bridge => relay_selector
                .get_bridge_forced()
                .and_then(|settings| match settings {
                    ProxySettings::Shadowsocks(ss_settings) => {
                        let ss_settings: access_method::Shadowsocks =
                            access_method::Shadowsocks::new(
                                ss_settings.peer,
                                ss_settings.cipher,
                                ss_settings.password,
                            );
                        Some(ApiConnectionMode::Proxied(ProxyConfig::Shadowsocks(
                            ss_settings,
                        )))
                    }
                    _ => {
                        log::error!("Received unexpected proxy settings type");
                        None
                    }
                })
                .unwrap_or(ApiConnectionMode::Direct),
        },
        AccessMethod::Custom(access_method) => match access_method {
            access_method::CustomAccessMethod::Shadowsocks(shadowsocks_config) => {
                ApiConnectionMode::Proxied(ProxyConfig::Shadowsocks(shadowsocks_config))
            }
            access_method::CustomAccessMethod::Socks5(socks_config) => {
                ApiConnectionMode::Proxied(ProxyConfig::Socks(socks_config))
            }
        },
    }
}

pub(super) fn get_allowed_endpoint(endpoint: Endpoint) -> AllowedEndpoint {
    #[cfg(unix)]
    let clients = talpid_types::net::AllowedClients::Root;
    #[cfg(windows)]
    let clients = {
        let daemon_exe = std::env::current_exe().expect("failed to obtain executable path");
        vec![
            daemon_exe
                .parent()
                .expect("missing executable parent directory")
                .join("mullvad-problem-report.exe"),
            daemon_exe,
        ]
        .into()
    };

    AllowedEndpoint { endpoint, clients }
}

pub(crate) fn forward_offline_state(
    api_availability: ApiAvailabilityHandle,
    mut offline_state_rx: mpsc::UnboundedReceiver<bool>,
) {
    tokio::spawn(async move {
        let initial_state = offline_state_rx
            .next()
            .await
            .expect("missing initial offline state");
        api_availability.set_offline(initial_state);
        while let Some(is_offline) = offline_state_rx.next().await {
            api_availability.set_offline(is_offline);
        }
    });
}

#[cfg(target_os = "android")]
pub(crate) fn create_bypass_tx(
    event_sender: &DaemonEventSender,
) -> Option<mpsc::Sender<mullvad_api::SocketBypassRequest>> {
    let (bypass_tx, mut bypass_rx) = mpsc::channel(1);
    let daemon_tx = event_sender.to_specialized_sender();
    tokio::spawn(async move {
        while let Some((raw_fd, done_tx)) = bypass_rx.next().await {
            if daemon_tx
                .send(DaemonCommand::BypassSocket(raw_fd, done_tx))
                .is_err()
            {
                log::error!("Can't send socket bypass request to daemon");
                break;
            }
        }
    });
    Some(bypass_tx)
}

/// An iterator which will always produce an [`AccessMethod`].
///
/// Safety: It is always safe to [`unwrap`] after calling [`next`] on a
/// [`std::iter::Cycle`], so thereby it is safe to always call [`unwrap`] on a
/// [`ConnectionModesIterator`].
///
/// [`unwrap`]: Option::unwrap
/// [`next`]: std::iter::Iterator::next
pub struct ConnectionModesIterator {
    available_modes: Box<dyn Iterator<Item = AccessMethodSetting> + Send>,
    next: Option<AccessMethodSetting>,
    current: AccessMethodSetting,
}

impl mullvad_api::connection_mode::ConnectionModesIterator for ConnectionModesIterator {
    fn set_access_method(&mut self, next: AccessMethodSetting) {
        self.next = Some(next);
    }

    fn update_access_methods(&mut self, access_methods: Vec<AccessMethodSetting>) {
        self.available_modes = Self::cycle(access_methods)
    }

    fn peek(&self) -> AccessMethodSetting {
        self.current.clone()
    }

    fn rotate(&mut self) -> Option<AccessMethodSetting> {
        let next = self
            .next
            .take()
            .or_else(|| self.available_modes.next())
            .unwrap();
        self.current = next.clone();
        Some(next)
    }
}

impl ConnectionModesIterator {
    pub fn new(access_methods: Vec<AccessMethodSetting>) -> ConnectionModesIterator {
        let mut iterator = Self::cycle(access_methods);
        Self {
            next: None,
            current: iterator
                .next()
                .expect("At least 1 `AccessMethodSetting` should exist"),
            available_modes: iterator,
        }
    }

    fn cycle(
        access_methods: Vec<AccessMethodSetting>,
    ) -> Box<dyn Iterator<Item = AccessMethodSetting> + Send> {
        Box::new(access_methods.into_iter().cycle())
    }
}

// TODO(markus): Do we need to resubscribe when cloning something here?
/*
impl Clone for PowerManagementListener {
    fn clone(&self) -> Self {
        Self {
            _window: self._window.clone(),
            rx: self.rx.resubscribe(),
        }
    }
} */
