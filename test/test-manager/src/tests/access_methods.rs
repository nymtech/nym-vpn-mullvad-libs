//! Integration tests for API access methods.
use super::{Error, TestContext};
use mullvad_management_interface::MullvadProxyClient;
use test_macro::test_function;
use test_rpc::ServiceClient;

/// Assert that custom access methods may be used to access the Mullvad API.
///
/// The tested access methods are:
/// * Shadowsocks
/// * Socks5 in remote mode
///
/// # Note
///
/// This tests assume that there exists working proxies *somewhere* for all
/// tested protocols. If the proxies themselves are bad/not running, this test
/// will fail due to issues that are out of the test manager's control.
///
///
#[test_function]
pub async fn test_custom_access_methods(
    _: TestContext,
    _rpc: ServiceClient,
    _mullvad_client: MullvadProxyClient,
) -> Result<(), Error> {
    log::info!("Testing Shadowsocks access method");
    test_shadowsocks().await?;
    log::info!("Testing SOCKS5 (Remote) access method");
    test_socks_remote().await?;
    Ok(())
}

async fn test_shadowsocks() -> Result<(), Error> {
    panic!("Testing Shadowsocks access method has not been fully implemented yet!")
}

#[allow(clippy::unused_async)]
async fn test_socks_remote() -> Result<(), Error> {
    unimplemented!("Testing SOCKS5 (Remote) access method is not implemented")
}
