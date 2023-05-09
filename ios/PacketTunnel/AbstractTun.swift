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
import WireGuardKitC

// Wrapper class around AbstractTun to provide an interface similar to WireGuardAdapter.
class AbstractTunAdapter {
    private let abstractTun: AbstractTun
    init(queue: DispatchQueue, packetTunnel: PacketTunnelProvider, logClosure: @escaping (String) -> Void) {
        
        self.abstractTun = AbstractTun(queue: queue, packetTunnel: packetTunnel, logClosure: logClosure)
    }
    
    public func start(tunnelConfiguration: PacketTunnelConfiguration) -> Result<(), AbstractTunError> {
        return self.abstractTun.start(tunnelConfig: tunnelConfiguration)
    }
    
    public func update(tunnelConfiguration: PacketTunnelConfiguration) -> Result<(), AbstractTunError> {
        return self.abstractTun.update(tunnelConfiguration: tunnelConfiguration)
    }
    
    public func stop(completionHandler: @escaping (WireGuardAdapterError?) -> Void)  {
        self.abstractTun.stop()
        completionHandler(nil)
    }
    
    public func stats() -> WgStats {
        WgStats(rx: abstractTun.bytesReceived, tx: abstractTun.bytesSent)
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
    
    private var wgTaskTimer: DispatchSourceTimer?
    private let logClosure: (String) -> Void
    
    private (set) var bytesReceived: UInt64 = 0
    private (set) var bytesSent: UInt64 = 0
    
    init(queue: DispatchQueue, packetTunnel: PacketTunnelProvider, logClosure: @escaping (String) -> Void) {
        dispatchQueue = queue;
        packetTunnelProvider = packetTunnel
        self.logClosure = logClosure
        wgTaskTimer = DispatchSource.makeTimerSource(queue: dispatchQueue)
        
    }
    
    
    
    deinit {
        self.wgTaskTimer?.cancel()
        abstract_tun_drop(self.tunRef)
    }
    
    func stop() {
        self.wgTaskTimer?.cancel()
        abstract_tun_drop(self.tunRef)
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
        
        withUnsafePointer(to: params) {
            tunRef = abstract_tun_init_instance($0)
        }
        if tunRef == nil {
            return .failure(AbstractTunError.initializationError)
        }
        packetTunnelProvider.packetFlow.readPackets(completionHandler: {[ weak self] (data, ipv) in
            self?.readPacketTunnelBytes(data, ipversion: ipv)
        })
        
        wgTaskTimer = DispatchSource.makeTimerSource(queue: dispatchQueue)
        wgTaskTimer?.setEventHandler(handler: {
            [weak self] in
            self?.handleTimerEvent()
        })
        wgTaskTimer?.schedule(deadline: .now(), repeating: 0.25)
        return .success(())
    }
    
    func readPacketTunnelBytes(_ traffic: [Data], ipversion: [NSNumber]) {
        dispatchQueue.async {
            do {
                
            for (traffic, _) in zip(traffic, ipversion) {
                try self.receiveTunnelTraffic(traffic)
            }
            
            } catch {
               // TODO: catch the error properly here.
            }
            self.packetTunnelProvider.packetFlow.readPackets(completionHandler: {[ weak self] (data, ipv) in
            self?.readPacketTunnelBytes(data, ipversion: ipv)
        })
        }
    }
    
    func receiveTunnelTraffic(_ data: Data) throws {
        guard let tunPtr = self.tunRef else {
            return
        }
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
        
        abstractTun.dispatchQueue.sync {
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
                }, maxDatagrams: 1024)
            }

            
            socket.writeDatagram(packetBytes, completionHandler: {
                error in
            })
                            
            abstractTun.dispatchQueue.async {
                abstractTun.bytesSent += UInt64(size)
            }
        }
        
        

        
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
    
}


enum AbstractTunError: Error {
    case initializationError
    case noPeers
}
