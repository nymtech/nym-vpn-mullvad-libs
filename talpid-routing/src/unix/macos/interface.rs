use futures::channel::mpsc::{self, UnboundedReceiver, UnboundedSender};
use nix::{
    net::if_::{if_nametoindex, InterfaceFlags},
    sys::socket::{AddressFamily, SockaddrLike, SockaddrStorage},
};
use std::{
    collections::BTreeMap,
    io,
    net::{IpAddr, Ipv4Addr, Ipv6Addr},
};
use talpid_macos::net::{Family, NetworkService};

use super::data::{Destination, RouteMessage};
use system_configuration::{
    core_foundation::{
        array::CFArray,
        runloop::{kCFRunLoopCommonModes, CFRunLoop},
        string::CFString,
    },
    dynamic_store::{SCDynamicStore, SCDynamicStoreBuilder, SCDynamicStoreCallBackContext},
};

const STATE_IPV4_KEY: &str = "State:/Network/Global/IPv4";
const STATE_IPV6_KEY: &str = "State:/Network/Global/IPv6";
const STATE_SERVICE_PATTERN: &str = "State:/Network/Service/.*/IP.*";

#[derive(Debug)]
pub struct ActiveInterface {
    id: String,
    name: String,
    router_ip: IpAddr,
}

impl ActiveInterface {
    pub fn from_service(service: NetworkService) -> Option<ActiveInterface> {
        Some(ActiveInterface {
            id: service.id,
            name: service.name?,
            router_ip: service.router_ip?,
        })
    }
}

pub struct PrimaryInterfaceMonitor {}

// FIXME: Implement Send on SCDynamicStore, if it's safe
unsafe impl Send for PrimaryInterfaceMonitor {}

pub enum InterfaceEvent {
    Update,
}

impl PrimaryInterfaceMonitor {
    pub fn new() -> (Self, UnboundedReceiver<InterfaceEvent>) {
        let (tx, rx) = mpsc::unbounded();
        Self::start_listener(tx);

        (Self {}, rx)
    }

    fn start_listener(tx: UnboundedSender<InterfaceEvent>) {
        std::thread::spawn(|| {
            let listener_store = SCDynamicStoreBuilder::new("talpid-routing-listener")
                .callback_context(SCDynamicStoreCallBackContext {
                    callout: Self::store_change_handler,
                    info: tx,
                })
                .build();

            let watch_keys: CFArray<CFString> = CFArray::from_CFTypes(&[
                CFString::new(STATE_IPV4_KEY),
                CFString::new(STATE_IPV6_KEY),
            ]);
            let watch_patterns = CFArray::from_CFTypes(&[CFString::new(STATE_SERVICE_PATTERN)]);

            if !listener_store.set_notification_keys(&watch_keys, &watch_patterns) {
                log::error!("Failed to start interface listener");
                return;
            }

            let run_loop_source = listener_store.create_run_loop_source();
            CFRunLoop::get_current().add_source(&run_loop_source, unsafe { kCFRunLoopCommonModes });
            CFRunLoop::run_current();

            log::debug!("Interface listener exiting");
        });
    }

    fn store_change_handler(
        _store: SCDynamicStore,
        changed_keys: CFArray<CFString>,
        tx: &mut UnboundedSender<InterfaceEvent>,
    ) {
        for k in changed_keys.iter() {
            log::trace!("Interface change, key {}", k.to_string());
        }
        let _ = tx.unbounded_send(InterfaceEvent::Update);
    }

    /// Retrieve the best current default route. This is based on the primary interface, or else
    /// the first active interface in the network service order.
    pub fn get_route(&self, family: Family) -> Option<RouteMessage> {
        let ifaces = talpid_macos::net::get_primary_interface(family)
            .map(|iface| {
                log::debug!("Found primary interface for {family}");
                vec![iface]
            })
            .unwrap_or_else(|| {
                log::debug!("Found no primary interface for {family}");
                talpid_macos::net::network_services(family)
            });

        let (iface, index) = ifaces
            .into_iter()
            .filter_map(|iface| {
                let iface = ActiveInterface::from_service(iface)?;
                let index = if_nametoindex(iface.name.as_str()).map_err(|error| {
                    log::error!("Failed to retrieve interface index for \"{}\": {error}", iface.name);
                    error
                }).ok()?;

                let active = is_active_interface(&iface.name, family).unwrap_or_else(|error| {
                    log::error!("is_active_interface() returned an error for interface \"{}\", assuming active. Error: {error}", iface.name);
                    true
                });
                if !active {
                    log::debug!("Skipping inactive interface {}, router IP {}", iface.name, iface.router_ip);
                    return None;
                }
                Some((iface, index))
            })
            .next()?;

        // Synthesize a scoped route for the interface
        let msg = RouteMessage::new_route(Destination::Network(family.default_network()))
            .set_gateway_addr(iface.router_ip)
            .set_interface_index(u16::try_from(index).unwrap());
        Some(msg)
    }

    pub fn debug(&self) {
        for family in [Family::V4, Family::V6] {
            log::debug!(
                "Primary interface ({family}): {:?}",
                talpid_macos::net::get_primary_interface(family)
            );
            log::debug!(
                "Network services ({family}): {:?}",
                talpid_macos::net::network_services(family)
            );
        }
    }
}

/// Return a map from interface name to link addresses (AF_LINK)
pub fn get_interface_link_addresses() -> io::Result<BTreeMap<String, SockaddrStorage>> {
    let mut gateway_link_addrs = BTreeMap::new();
    let addrs = nix::ifaddrs::getifaddrs()?;
    for addr in addrs.into_iter() {
        if addr.address.and_then(|addr| addr.family()) != Some(AddressFamily::Link) {
            continue;
        }
        gateway_link_addrs.insert(addr.interface_name, addr.address.unwrap());
    }
    Ok(gateway_link_addrs)
}

/// Return whether the given interface has an assigned (unicast) IP address.
fn is_active_interface(interface_name: &str, family: Family) -> io::Result<bool> {
    let required_link_flags: InterfaceFlags = InterfaceFlags::IFF_UP | InterfaceFlags::IFF_RUNNING;
    let has_ip_addr = nix::ifaddrs::getifaddrs()?
        .filter(|addr| (addr.flags & required_link_flags) == required_link_flags)
        .filter(|addr| addr.interface_name == interface_name)
        .any(|addr| {
            if let Some(addr) = addr.address {
                // Check if family matches; ignore if link-local address
                match family {
                    Family::V4 => matches!(addr.as_sockaddr_in(), Some(addr_in) if is_routable_v4(&Ipv4Addr::from(addr_in.ip()))),
                    Family::V6 => {
                        matches!(addr.as_sockaddr_in6(), Some(addr_in) if is_routable_v6(&addr_in.ip()))
                    }
                }
            } else {
                false
            }
        });
    Ok(has_ip_addr)
}

fn is_routable_v4(addr: &Ipv4Addr) -> bool {
    !addr.is_unspecified() && !addr.is_loopback() && !addr.is_link_local()
}

fn is_routable_v6(addr: &Ipv6Addr) -> bool {
    !addr.is_unspecified()
    && !addr.is_loopback()
    // !(link local)
    && (addr.segments()[0] & 0xffc0) != 0xfe80
}
