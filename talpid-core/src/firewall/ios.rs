use super::{FirewallArguments, FirewallPolicy};

/// Stub error type for Firewall errors on iOS.
#[derive(Debug, err_derive::Error)]
#[error(display = "Unknown iOS Firewall error")]
pub struct Error;

/// The iOS stub implementation for the firewall.
pub struct Firewall;

impl Firewall {
    pub fn from_args(_args: FirewallArguments) -> Result<Self, Error> {
        Ok(Firewall)
    }

    pub fn new() -> Result<Self, Error> {
        Ok(Firewall)
    }

    pub fn apply_policy(&mut self, _policy: FirewallPolicy) -> Result<(), Error> {
        Ok(())
    }

    pub fn reset_policy(&mut self) -> Result<(), Error> {
        Ok(())
    }
}
