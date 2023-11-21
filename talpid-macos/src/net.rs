use ipnetwork::IpNetwork;
use once_cell::sync::Lazy;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use system_configuration::{
    core_foundation::{
        base::{CFType, TCFType, ToVoid},
        dictionary::CFDictionary,
        string::CFString,
    },
    dynamic_store::{SCDynamicStore, SCDynamicStoreBuilder},
    network_configuration::SCNetworkSet,
    preferences::SCPreferences,
    sys::schema_definitions::{
        kSCDynamicStorePropNetPrimaryInterface, kSCDynamicStorePropNetPrimaryService,
        kSCPropInterfaceName, kSCPropNetIPv4Router, kSCPropNetIPv6Router,
    },
};

const STATE_IPV4_KEY: &str = "State:/Network/Global/IPv4";
const STATE_IPV6_KEY: &str = "State:/Network/Global/IPv6";

static INTERFACE_MONITOR: Lazy<PrimaryInterfaceMonitor> =
    Lazy::new(|| PrimaryInterfaceMonitor::new());

/// Describes a network service
#[derive(Debug)]
pub struct NetworkService {
    /// Identifier
    pub id: String,
    /// Service name
    pub name: Option<String>,
    /// Router IP
    pub router_ip: Option<IpAddr>,
}

/// Return details about the primary network service
pub fn get_primary_interface(family: Family) -> Option<NetworkService> {
    INTERFACE_MONITOR.get_primary_interface(family)
}

/// Return a list of network services and select details
pub fn network_services(family: Family) -> Vec<NetworkService> {
    INTERFACE_MONITOR.network_services(family)
}

/// Describes an IP family
#[derive(Debug, PartialEq, Clone, Copy)]
pub enum Family {
    /// IPv4
    V4,
    /// IPv6
    V6,
}

impl std::fmt::Display for Family {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Family::V4 => f.write_str("V4"),
            Family::V6 => f.write_str("V6"),
        }
    }
}

impl Family {
    /// Returns the default network for the current family
    pub fn default_network(self) -> IpNetwork {
        match self {
            Family::V4 => IpNetwork::new(Ipv4Addr::UNSPECIFIED.into(), 0).unwrap(),
            Family::V6 => IpNetwork::new(Ipv6Addr::UNSPECIFIED.into(), 0).unwrap(),
        }
    }
}
struct PrimaryInterfaceMonitor {
    store: SCDynamicStore,
    prefs: SCPreferences,
}

// FIXME: Implement Send on SCDynamicStore, if it's safe
unsafe impl Send for PrimaryInterfaceMonitor {}
// FIXME: Implement Sync on SCDynamicStore, if it's safe
unsafe impl Sync for PrimaryInterfaceMonitor {}

impl PrimaryInterfaceMonitor {
    fn new() -> Self {
        let store = SCDynamicStoreBuilder::new("talpid-macos").build();
        let prefs = SCPreferences::default(&CFString::new("talpid-macos"));
        Self { store, prefs }
    }

    /// Return details about the primary network service
    pub fn get_primary_interface(&self, family: Family) -> Option<NetworkService> {
        let global_name = if family == Family::V4 {
            STATE_IPV4_KEY
        } else {
            STATE_IPV6_KEY
        };
        let global_dict = self
            .store
            .get(CFString::new(global_name))
            .and_then(|v| v.downcast_into::<CFDictionary>())?;

        let id = global_dict
            .find(unsafe { kSCDynamicStorePropNetPrimaryService }.to_void())
            .map(|s| unsafe { CFType::wrap_under_get_rule(*s) })
            .and_then(|s| s.downcast::<CFString>())
            .map(|s| s.to_string())?;
        let name = global_dict
            .find(unsafe { kSCDynamicStorePropNetPrimaryInterface }.to_void())
            .map(|s| unsafe { CFType::wrap_under_get_rule(*s) })
            .and_then(|s| s.downcast::<CFString>())
            .map(|s| s.to_string());

        let router_key = if family == Family::V4 {
            unsafe { kSCPropNetIPv4Router.to_void() }
        } else {
            unsafe { kSCPropNetIPv6Router.to_void() }
        };
        let router_ip = global_dict
            .find(router_key)
            .map(|s| unsafe { CFType::wrap_under_get_rule(*s) })
            .and_then(|s| s.downcast::<CFString>())
            .and_then(|ip| ip.to_string().parse().ok());

        Some(NetworkService {
            id,
            name,
            router_ip,
        })
    }

    /// Return a list of network services and select details
    pub fn network_services(&self, family: Family) -> Vec<NetworkService> {
        let router_key = if family == Family::V4 {
            unsafe { kSCPropNetIPv4Router.to_void() }
        } else {
            unsafe { kSCPropNetIPv6Router.to_void() }
        };

        SCNetworkSet::new(&self.prefs)
            .service_order()
            .iter()
            .map(|service_id| {
                let service_id_s = service_id.to_string();

                let key = if family == Family::V4 {
                    format!("State:/Network/Service/{service_id_s}/IPv4")
                } else {
                    format!("State:/Network/Service/{service_id_s}/IPv6")
                };
                let ip_dict = INTERFACE_MONITOR
                    .store
                    .get(CFString::new(&key))
                    .and_then(|v| v.downcast_into::<CFDictionary>());

                let (name, router_ip) = if let Some(ip_dict) = ip_dict {
                    let name = ip_dict
                        .find(unsafe { kSCPropInterfaceName }.to_void())
                        .map(|s| unsafe { CFType::wrap_under_get_rule(*s) })
                        .and_then(|s| s.downcast::<CFString>())
                        .map(|s| s.to_string());
                    let router_ip = ip_dict
                        .find(router_key)
                        .map(|s| unsafe { CFType::wrap_under_get_rule(*s) })
                        .and_then(|s| s.downcast::<CFString>())
                        .and_then(|ip| ip.to_string().parse().ok());
                    (name, router_ip)
                } else {
                    (None, None)
                };

                NetworkService {
                    id: service_id_s,
                    name,
                    router_ip,
                }
            })
            .collect::<Vec<_>>()
    }
}
