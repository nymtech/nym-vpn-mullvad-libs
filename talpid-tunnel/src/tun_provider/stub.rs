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

    pub fn bypass(&mut self, fd : RawFd) -> Result<(), Error> {
        Ok(())
    }
}

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
