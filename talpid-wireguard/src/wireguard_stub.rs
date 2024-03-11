use crate::stats::StatsMap;
use ipnetwork::IpNetwork;
use std::{
    future::Future,
    path::Path,
    pin::Pin,
    sync::{Arc, Mutex},
};
use talpid_tunnel::tun_provider::TunProvider;

pub struct WgGoTunnel {}

impl WgGoTunnel {
    pub fn start_tunnel(
        _config: &crate::config::Config,
        _log_path: Option<&Path>,
        _tun_provider: Arc<Mutex<TunProvider>>,
        _routes: impl Iterator<Item = IpNetwork>,
    ) -> Result<Self, super::TunnelError> {
        Ok(WgGoTunnel {})
    }
}

impl crate::Tunnel for WgGoTunnel {
    fn get_interface_name(&self) -> String {
        String::new()
    }

    fn get_tunnel_stats(&self) -> Result<StatsMap, super::TunnelError> {
        Ok(StatsMap::new())
    }

    fn stop(mut self: Box<Self>) -> Result<(), super::TunnelError> {
        Ok(())
    }

    fn set_config(
        &self,
        _config: crate::config::Config,
    ) -> Pin<Box<dyn Future<Output = std::result::Result<(), super::TunnelError>> + Send>> {
        Box::pin(async move { Ok(()) })
    }
}
