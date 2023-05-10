//
//  AbstractTun.swift
//  PacketTunnel
//
//  Created by Emils on 17/03/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
import WireGuardKitTypes
import Network
import NetworkExtension
import WireGuardKit
import WireGuardKitTypes
import WireGuardKitC

// Wrapper class around AbstractTun to provide an interface similar to WireGuardAdapter.
class AbstractTunAdapter {
    private let abstractTun: AbstractTun
    private let queue: DispatchQueue
    init(queue: DispatchQueue, packetTunnel: PacketTunnelProvider, logClosure: @escaping (String) -> Void) {
        
        self.queue = queue
        abstractTun = AbstractTun(queue: queue, packetTunnel: packetTunnel, logClosure: logClosure)
    }
    
    public func start(tunnelConfiguration: PacketTunnelConfiguration) -> Result<(), AbstractTunError> {
        return self.abstractTun.start(tunnelConfig: tunnelConfiguration)
    }
    
    public func block(tunnelConfiguration: TunnelConfiguration) -> Result<(), AbstractTunError> {
        return self.abstractTun.block(tunnelConfiguration: tunnelConfiguration)
    }
    
    public func update(tunnelConfiguration: PacketTunnelConfiguration) -> Result<(), AbstractTunError> {
        return self.abstractTun.update(tunnelConfiguration: tunnelConfiguration)
    }
    
    public func stop(completionHandler: @escaping (WireGuardAdapterError?) -> Void)  {
        self.abstractTun.stop()
        completionHandler(nil)
    }
    
    public func stats() -> WgStats {
        return queue.sync {
            return WgStats(rx: abstractTun.bytesReceived, tx: abstractTun.bytesSent)
        }
    }
    
    /// Returns the tunnel device interface name, or nil on error.
    /// - Returns: String.
    public var interfaceName: String? {
        guard let tunnelFileDescriptor = self.tunnelFileDescriptor else { return nil }
        
        var buffer = [UInt8](repeating: 0, count: Int(IFNAMSIZ))
        
        return buffer.withUnsafeMutableBufferPointer { mutableBufferPointer in
            guard let baseAddress = mutableBufferPointer.baseAddress else { return nil }
            
            var ifnameSize = socklen_t(IFNAMSIZ)
            let result = getsockopt(
                tunnelFileDescriptor,
                2 /* SYSPROTO_CONTROL */,
                2 /* UTUN_OPT_IFNAME */,
                baseAddress,
                &ifnameSize)
            
            if result == 0 {
                return String(cString: baseAddress)
            } else {
                return nil
            }
        }
    }
    
    /// Tunnel device file descriptor.
    private var tunnelFileDescriptor: Int32? {
        var ctlInfo = ctl_info()
        withUnsafeMutablePointer(to: &ctlInfo.ctl_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: $0.pointee)) {
                _ = strcpy($0, "com.apple.net.utun_control")
            }
        }
        for fd: Int32 in 0...1024 {
            var addr = sockaddr_ctl()
            var ret: Int32 = -1
            var len = socklen_t(MemoryLayout.size(ofValue: addr))
            withUnsafeMutablePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    ret = getpeername(fd, $0, &len)
                }
            }
            if ret != 0 || addr.sc_family != AF_SYSTEM {
                continue
            }
            if ctlInfo.ctl_id == 0 {
                ret = ioctl(fd, CTLIOCGINFO, &ctlInfo)
                if ret != 0 {
                    continue
                }
            }
            if addr.sc_id == ctlInfo.ctl_id {
                return fd
            }
        }
        return nil
    }
    
    
    
    
}

class AbstractTun {
    private var tunRef: OpaquePointer?
    private var dispatchQueue: DispatchQueue
    
    private var unmanagedSelf: Unmanaged<AbstractTun>?
    private let packetTunnelProvider: PacketTunnelProvider
    
    private var v4SessionMap: [UInt32: NWUDPSession] = [UInt32: NWUDPSession]()
    private var v6SessionMap: [[UInt16]: NWUDPSession] = [[UInt16]: NWUDPSession]()
    
    private let tunQueue = DispatchQueue(label: "AbstractTun", qos: .userInitiated)
    
    private var wgTaskTimer: DispatchSourceTimer
    private let logClosure: (String) -> Void
    
    private (set) var bytesReceived: UInt64 = 0
    private (set) var bytesSent: UInt64 = 0
    
    init(queue: DispatchQueue, packetTunnel: PacketTunnelProvider, logClosure: @escaping (String) -> Void) {
        dispatchQueue = queue;
        packetTunnelProvider = packetTunnel
        self.logClosure = logClosure
        wgTaskTimer = DispatchSource.makeTimerSource(queue: queue)
        wgTaskTimer.setEventHandler(handler: {
            [weak self] in
            self?.handleTimerEvent()
        })
        wgTaskTimer.schedule(deadline: .now() + .milliseconds(10), repeating: .milliseconds(250))
        
    }
    
    
    
    deinit {
        self.stop()
    }
    
    func stopAbstractTun() {
        abstract_tun_drop(self.tunRef)
        self.tunRef = nil
    }
    
    func stop() {
        self.wgTaskTimer.suspend()
        stopAbstractTun()
    }
    
    func update(tunnelConfiguration: PacketTunnelConfiguration) -> Result<(), AbstractTunError> {
        stop()
        bytesSent = 0
        bytesReceived = 0
        return start(tunnelConfig: tunnelConfiguration)
    }
    
    func start(tunnelConfig: PacketTunnelConfiguration) -> Result<(), AbstractTunError> {
        let singlePeer = tunnelConfig.wgTunnelConfig.peers[0];
        
        let privateKey = tunnelConfig.wgTunnelConfig.interface.privateKey.rawValue;
        guard let peerEndpoint = singlePeer.endpoint else {
            return .failure(AbstractTunError.noPeers)
        }
        let peerAddr = peerEndpoint.host
        
        
        var addrBytes = Data(count: 16)
        var addressKind = UInt8(2)
        switch peerAddr {
        case .ipv4(let addr) :
            addrBytes[0...3] = addr.rawValue[0...3]
            addressKind = 0;
        case .ipv6(let addr) :
            addrBytes[0...16] = addr.rawValue[0...16]
            addressKind = 1;
        default :
            break;
        };
        
        var iosContext = IOSContext();
        iosContext.ctx = UnsafeRawPointer(Unmanaged.passRetained(self).toOpaque())
        iosContext.send_udp_ipv4 = {
            (ctx, addr, port, buffer, bufSize) in
            AbstractTun.handleUdpSendV4(ctx: ctx, addr: addr, port: port, buffer: buffer, size: bufSize)
        }
        iosContext.send_udp_ipv6 = {
            (ctx, addr, port, buffer, bufSize) in
        }
        
        iosContext.tun_v4_callback = {
            (ctx, buffer, bufSize) in
            AbstractTun.handleTunSendV4(ctx: ctx, data: buffer, size: bufSize)
        }
        
        iosContext.tun_v6_callback = {
            (ctx, buffer, bufSize) in
        }
        var params = IOSTunParams()
        params.ctx = iosContext
        params.peer_addr_version = addressKind
        params.peer_port = singlePeer.endpoint?.port.rawValue ?? UInt16(0)
        
        withUnsafeMutableBytes(of: &params.peer_key) {
            let _ = singlePeer.publicKey.rawValue.copyBytes(to:$0)
        }
        
        withUnsafeMutableBytes(of: &params.private_key) {
            let _ = privateKey.copyBytes(to: $0)
        }
        
        withUnsafeMutableBytes(of: &params.peer_addr_bytes) {
            let _ = addrBytes.copyBytes(to: $0)
        }
        
        withUnsafePointer(to: params) {
            tunRef = abstract_tun_init_instance($0)
        }
        if tunRef == nil {
            return .failure(AbstractTunError.initializationError)
        }
        packetTunnelProvider.packetFlow.readPackets(completionHandler: {[ weak self] (data, ipv) in
            self?.readPacketTunnelBytes(data, ipversion: ipv)
        })
        
        wgTaskTimer.resume()
        
        return setConfiguration(tunnelConfig.wgTunnelConfig)
    }
    
    func setConfiguration(_ config: TunnelConfiguration) -> Result<(), AbstractTunError> {
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        var systemError: Error?
        
        self.packetTunnelProvider.setTunnelNetworkSettings(generateNetworkSettings(tunnelConfiguration: config)) { error in
            systemError = error
            dispatchGroup.leave()
        }
        
        let setNetworkSettingsTimeout: Int = 5
        switch dispatchGroup.wait(wallTimeout: .now() + .seconds(setNetworkSettingsTimeout)) {
        case .success:
            if let error = systemError {
                return .failure(AbstractTunError.setNetworkSettings(error))
            }
            return .success(())
        case .timedOut:
            return .success(())
            
        }
    }
    
    func readPacketTunnelBytes(_ traffic: [Data], ipversion: [NSNumber]) {
        dispatchQueue.async {
            do {
                
                for (traffic, _) in zip(traffic, ipversion) {
                    try self.receiveHostTraffic(traffic)
                }
                
            } catch {
                // TODO: catch the error properly here.
            }
            self.packetTunnelProvider.packetFlow.readPackets(completionHandler: self.readPacketTunnelBytes)
        }
    }
    
    func receiveTunnelTraffic(_ data: Data) throws {
        guard let tunPtr = self.tunRef else {
            return
        }
        self.bytesReceived += UInt64(data.count)
        try data.withUnsafeBytes<Void> {
            ptr in
            abstract_tun_handle_tunnel_traffic(tunPtr, ptr, UInt(data.count))
        }
    }
    
    func receiveHostTraffic(_ data: Data) throws {
        guard let tunPtr = self.tunRef else {
            return
        }
        
        try data.withUnsafeBytes<Void> {
            ptr in
            abstract_tun_handle_host_traffic(tunPtr, ptr, UInt(data.count))
        }
    }
    
    func handleTimerEvent() {
        guard let tunPtr = self.tunRef else {
            return
        }
        
        abstract_tun_handle_timer_event(tunPtr)
    }
    
    private static func handleUdpSendV4(
        ctx: UnsafeRawPointer?,
        addr: UInt32,
        port: UInt16,
        buffer: UnsafePointer<UInt8>?,
        size: UInt
    ) {
        guard let ctx = ctx else { return }
        guard let buffer = buffer else { return }
        
        let unmanagedInstance = Unmanaged<AbstractTun>.fromOpaque(ctx)
        let abstractTun = unmanagedInstance.takeRetainedValue()
        let rawPtr = UnsafeMutableRawPointer(mutating: buffer)
        let packetBytes = Data(bytesNoCopy: rawPtr, count: Int(size), deallocator: .none)
        
        var addr = addr;
        
        // abstractTun.dispatchQueue.sync {
        var socket: NWUDPSession;
        if let existingSocket = abstractTun.v4SessionMap[addr] {
            socket = existingSocket
        } else {
            guard let address = IPv4Address(Data(bytes: &addr, count: MemoryLayout<UInt32>.size), nil) else {
                return
            }
            let endpoint = NWHostEndpoint(hostname: "\(address)", port: "\(port)")
            let newSocket = abstractTun.packetTunnelProvider.createUDPSession(to: endpoint, from: nil )
            
            
            socket = newSocket
            abstractTun.v4SessionMap[addr] = newSocket
            
            newSocket.setReadHandler( {
                [weak abstractTun] (traffic, error) in
                
                guard let tun = abstractTun else { return }
                tun.dispatchQueue.async {
                    if let error = error {
                        // TODO: log error
                        return;
                    }
                    guard let tun = abstractTun  else  { return }
                    for data in traffic ?? [] {
                        do {
                            try tun.receiveTunnelTraffic(data)
                        } catch {
                            // TODO: log error
                        }
                    }
                }
                
            }, maxDatagrams: 1024)
        }
        
        
        socket.writeDatagram(packetBytes, completionHandler: {
            [weak abstractTun]
            error in
            if let error = error {
                // TODO: handle error
            } else {
                abstractTun?.dispatchQueue.async {
                    abstractTun?.bytesSent += UInt64(size)
                }
            }
        })
       
        _ = socket.observe(\.state) { udpSession, newState in
            print(newState.newValue ?? "no new value: \(newState.oldValue)")
        }
        
        // abstractTun.bytesSent += UInt64(size)
        // }
        
    }
    
    private static func handleUdpSendV6(
        ctx: UnsafeMutableRawPointer?,
        addr: UInt32,
        port: UInt16,
        buffer: UnsafePointer<UInt8>?,
        size: UInt
    ) {
        
    }
    
    
    private static func handleTunSendV4(
        ctx: UnsafeRawPointer?,
        data: UnsafePointer<UInt8>?,
        size: UInt
    ) {
        guard let ctx = ctx else { return }
        guard let data = data else { return }
        
        let unmanagedInstance = Unmanaged<AbstractTun>.fromOpaque(ctx)
        let abstractTun = unmanagedInstance.takeRetainedValue()
        
        let packetBytes = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: data), count: Int(size), deallocator: .none)
        
        abstractTun.packetTunnelProvider.packetFlow.writePackets([packetBytes], withProtocols: [NSNumber(value:AF_INET)])
        
        abstractTun.dispatchQueue.async {
            abstractTun.bytesReceived += UInt64(size)
        }
    }
    
    func block(tunnelConfiguration: TunnelConfiguration) -> Result<(), AbstractTunError> {
        return setConfiguration(tunnelConfiguration)
    }
    
}
func generateNetworkSettings(tunnelConfiguration: TunnelConfiguration) -> NEPacketTunnelNetworkSettings {
    /* iOS requires a tunnel endpoint, whereas in WireGuard it's valid for
     * a tunnel to have no endpoint, or for there to be many endpoints, in
     * which case, displaying a single one in settings doesn't really
     * make sense. So, we fill it in with this placeholder, which is not
     * a valid IP address that will actually route over the Internet.
     */
    let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
    
    if !tunnelConfiguration.interface.dnsSearch.isEmpty || !tunnelConfiguration.interface.dns.isEmpty {
        let dnsServerStrings = tunnelConfiguration.interface.dns.map { $0.stringRepresentation }
        let dnsSettings = NEDNSSettings(servers: dnsServerStrings)
        dnsSettings.searchDomains = tunnelConfiguration.interface.dnsSearch
        if !tunnelConfiguration.interface.dns.isEmpty {
            dnsSettings.matchDomains = [""] // All DNS queries must first go through the tunnel's DNS
        }
        networkSettings.dnsSettings = dnsSettings
    }
    
    let mtu = tunnelConfiguration.interface.mtu ?? 0
    
    /* 0 means automatic MTU. In theory, we should just do
     * `networkSettings.tunnelOverheadBytes = 80` but in
     * practice there are too many broken networks out there.
     * Instead set it to 1280. Boohoo. Maybe someday we'll
     * add a nob, maybe, or iOS will do probing for us.
     */
    if mtu == 0 {
#if os(iOS)
        networkSettings.mtu = NSNumber(value: 1280)
#elseif os(macOS)
        networkSettings.tunnelOverheadBytes = 80
#else
#error("Unimplemented")
#endif
    } else {
        networkSettings.mtu = NSNumber(value: mtu)
    }
    
    let (ipv4Addresses, ipv6Addresses) = addresses(tunnelConfiguration: tunnelConfiguration)
    let (ipv4IncludedRoutes, ipv6IncludedRoutes) = includedRoutes(tunnelConfiguration: tunnelConfiguration)
    
    let ipv4Settings = NEIPv4Settings(addresses: ipv4Addresses.map { $0.destinationAddress }, subnetMasks: ipv4Addresses.map { $0.destinationSubnetMask })
    ipv4Settings.includedRoutes = ipv4IncludedRoutes
    networkSettings.ipv4Settings = ipv4Settings
    
    let ipv6Settings = NEIPv6Settings(addresses: ipv6Addresses.map { $0.destinationAddress }, networkPrefixLengths: ipv6Addresses.map { $0.destinationNetworkPrefixLength })
    ipv6Settings.includedRoutes = ipv6IncludedRoutes
    networkSettings.ipv6Settings = ipv6Settings
    
    return networkSettings
}

private func addresses(tunnelConfiguration: TunnelConfiguration) -> ([NEIPv4Route], [NEIPv6Route]) {
    var ipv4Routes = [NEIPv4Route]()
    var ipv6Routes = [NEIPv6Route]()
    for addressRange in tunnelConfiguration.interface.addresses {
        if addressRange.address is IPv4Address {
            ipv4Routes.append(NEIPv4Route(destinationAddress: "\(addressRange.address)", subnetMask: "\(addressRange.subnetMask())"))
        } else if addressRange.address is IPv6Address {
            /* Big fat ugly hack for broken iOS networking stack: the smallest prefix that will have
             * any effect on iOS is a /120, so we clamp everything above to /120. This is potentially
             * very bad, if various network parameters were actually relying on that subnet being
             * intentionally small. TODO: talk about this with upstream iOS devs.
             */
            ipv6Routes.append(NEIPv6Route(destinationAddress: "\(addressRange.address)", networkPrefixLength: NSNumber(value: min(120, addressRange.networkPrefixLength))))
        }
    }
    return (ipv4Routes, ipv6Routes)
}

private func includedRoutes(tunnelConfiguration: TunnelConfiguration) -> ([NEIPv4Route], [NEIPv6Route]) {
    var ipv4IncludedRoutes = [NEIPv4Route]()
    var ipv6IncludedRoutes = [NEIPv6Route]()
    
    for addressRange in tunnelConfiguration.interface.addresses {
        if addressRange.address is IPv4Address {
            let route = NEIPv4Route(destinationAddress: "\(addressRange.maskedAddress())", subnetMask: "\(addressRange.subnetMask())")
            route.gatewayAddress = "\(addressRange.address)"
            ipv4IncludedRoutes.append(route)
        } else if addressRange.address is IPv6Address {
            let route = NEIPv6Route(destinationAddress: "\(addressRange.maskedAddress())", networkPrefixLength: NSNumber(value: addressRange.networkPrefixLength))
            route.gatewayAddress = "\(addressRange.address)"
            ipv6IncludedRoutes.append(route)
        }
    }
    
    for peer in tunnelConfiguration.peers {
        for addressRange in peer.allowedIPs {
            if addressRange.address is IPv4Address {
                ipv4IncludedRoutes.append(NEIPv4Route(destinationAddress: "\(addressRange.address)", subnetMask: "\(addressRange.subnetMask())"))
            } else if addressRange.address is IPv6Address {
                ipv6IncludedRoutes.append(NEIPv6Route(destinationAddress: "\(addressRange.address)", networkPrefixLength: NSNumber(value: addressRange.networkPrefixLength)))
            }
        }
    }
    return (ipv4IncludedRoutes, ipv6IncludedRoutes)
}




enum AbstractTunError: Error {
    case initializationError
    case noPeers
    case setNetworkSettings(Error)
}
