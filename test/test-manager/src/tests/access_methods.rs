//! Integration tests for API access methods.
use super::{Error, TestContext};
use mullvad_management_interface::MullvadProxyClient;
use talpid_types::net::proxy::CustomProxy;
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
    mullvad_client: MullvadProxyClient,
) -> Result<(), Error> {
    log::info!("Testing Shadowsocks access method");
    test_shadowsocks(mullvad_client.clone()).await?;
    log::info!("Testing SOCKS5 (Remote) access method");
    test_socks_remote(mullvad_client.clone()).await?;
    Ok(())
}

async fn test_shadowsocks(mut mullvad_client: MullvadProxyClient) -> Result<(), Error> {
    use mullvad_types::relay_list::RelayEndpointData;
    // Set up all the parameters needed to create a custom Shadowsocks access method.
    //
    // Since Mullvad host's Shadowsocks relays on their bridge servers, we can
    // simply select a bridge server to derive all the needed parameters.
    // mullvad_client
    let relay_list = mullvad_client.get_relay_locations().await.unwrap();
    let bridge = relay_list
        .relays()
        .filter(|relay| matches!(relay.endpoint_data, RelayEndpointData::Bridge))
        .nth(0)
        .expect("`test_shadowsocks` needs at least one shadowsocks relay to execute. Found non in relay list.");

    let access_method: CustomProxy = relay_list
        .bridge
        .shadowsocks
        .first()
        .map(|shadowsocks| {
            shadowsocks.to_proxy_settings(bridge.ipv4_addr_in.into())
        })
        .expect("`test_shadowsocks` needs at least one shadowsocks relay to execute. Found non in relay list.");

    assert_access_method_works(mullvad_client, access_method.clone()).await?;

    Ok(())
}

async fn test_socks_remote(mut mullvad_client: MullvadProxyClient) -> Result<(), Error> {
    use talpid_types::net::proxy::Socks5Remote;
    // Set up all the parameters needed to create a custom SOCKS5 access method.
    //
    // The remote SOCKS5 proxy is assumed to be running on the test manager.
    // On which port it listens to is defined in the test config.
    let endpoint = todo!();
    let access_method = Socks5Remote {
        endpoint: todo!(),
        auth: None,
    };

    assert_access_method_works(mullvad_client, access_method.into()).await?;

    Ok(())
}

async fn assert_access_method_works(
    mut mullvad_client: MullvadProxyClient,
    access_method: CustomProxy,
) -> Result<(), Error> {
    let successful = mullvad_client
        .test_custom_api_access_method(access_method.clone().into())
        .await?;

    assert!(
        successful,
        "Failed while testing access method - {access_method:?}"
    );

    Ok(())
}
