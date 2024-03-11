use std::net::Ipv4Addr;

#[derive(err_derive::Error, Debug)]
pub enum Error {}

pub struct Pinger {}

impl Pinger {
    pub fn new(_addr: Ipv4Addr) -> Result<Self, Error> {
        Ok(Pinger {})
    }
}

impl super::Pinger for Pinger {
    fn send_icmp(&mut self) -> Result<(), Error> {
        Ok(())
    }
    fn reset(&mut self) {}
}
