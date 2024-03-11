use super::TunConfig;

#[derive(Debug, err_derive::Error)]
#[error(no_from)]
pub enum Error {}

pub struct StubTun {}

impl StubTun {
    pub fn interface_name(&self) -> &str {
        "stubtun"
    }
}

pub struct StubTunProvider;

impl StubTunProvider {
    pub fn new() -> Self {
        StubTunProvider
    }

    pub fn get_tun(&mut self, _: TunConfig) -> Result<(), Error> {
        unimplemented!();
    }
}
