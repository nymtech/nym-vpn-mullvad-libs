#[cfg(not(target_os = "windows"))]
use std::os::fd::{AsRawFd, RawFd};
use super::TunConfig;

#[derive(Debug, err_derive::Error)]
#[error(no_from)]
pub enum Error {}

pub struct StubTun {}

impl StubTun {
    pub fn interface_name(&self) -> &str {
        "stubtun"
    }

    #[cfg(target_os = "android")]
    pub fn bypass(&mut self, fd : RawFd) -> Result<(), Error> {
        Ok(())
    }
}

#[cfg(not(target_os = "windows"))]
impl AsRawFd for StubTun {

    fn as_raw_fd(&self) -> RawFd {
        RawFd::from(-1)
    }
}

pub struct StubTunProvider;

impl StubTunProvider {
    pub fn new() -> Self {
        StubTunProvider
    }

    pub fn get_tun(&mut self, _: TunConfig) -> Result<StubTun, Error> {
        unimplemented!();
    }
}
