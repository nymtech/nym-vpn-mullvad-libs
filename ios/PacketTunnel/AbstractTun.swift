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

class AbstractTun {
    private var tunRef: OpaquePointer?
    private var dispatchQueue: DispatchQueue
    
    private var singlePeer: PeerConfiguration
    private var unmanagedSelf: Unmanaged<AbstractTun>?
    private let packetTunnelProvider: PacketTunnelProvider
    
    private var v4SessionMap: [UInt32: NWUDPSession] = [UInt32: NWUDPSession]()
    private var v6SessionMap: [[UInt16]: NWUDPSession] = [[UInt16]: NWUDPSession]()
    
    private var wgTaskTimer: DispatchSourceTimer?
    
    init(queue: DispatchQueue, tunnelConfig: PacketTunnelConfiguration, packetTunnel: PacketTunnelProvider) throws {
        self.dispatchQueue = queue;
        self.packetTunnelProvider = packetTunnel
        
        singlePeer = tunnelConfig.wgTunnelConfig.peers[0];
        
        let privateKey = tunnelConfig.wgTunnelConfig.interface.privateKey.rawValue;
        guard let peerEndpoint = singlePeer.endpoint else {
            return
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
            throw AbstractTunError.initializationError
        }
        packetTunnelProvider.packetFlow.readPackets(completionHandler: {[ weak self] (data, ipv) in
            self?.readPacketTunnelBytes(data, ipversion: ipv)
        })
        
        wgTaskTimer = DispatchSource.makeTimerSource(queue: dispatchQueue)
        wgTaskTimer?.setEventHandler(handler: {
            [weak self] in
            self?.handleTimerEvent()
        })
        wgTaskTimer?.schedule(deadline: .now(), repeating: 0.001)
        
    }
    
    
    
    deinit {
        self.wgTaskTimer?.cancel()
        abstract_tun_drop(self.tunRef)
    }
    
    func readPacketTunnelBytes(_ traffic: [Data], ipversion: [NSNumber]) {
        dispatchQueue.async {
            for (traffic, _) in zip(traffic, ipversion) {
                self.receiveTunnelTraffic(traffic)
            }
            
            self.packetTunnelProvider.packetFlow.readPackets(completionHandler: {[ weak self] (data, ipv) in
        self?.readPacketTunnelBytes(data, ipversion: ipv)
        })
        }
    }
    
    func receiveTunnelTraffic(_ data: Data) {
        guard let tunPtr = self.tunRef else {
            return
        }
        data.withUnsafeBytes {
            ptr in
            abstract_tun_handle_tunnel_traffic(tunPtr, ptr, UInt(data.count))
        }
    }
    
    func receiveHostTraffic(_ data: Data) {
        guard let tunPtr = self.tunRef else {
            return
        }
        
        data.withUnsafeBytes {
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
                    /// TODO: log error
                    return;
                }
                guard let tun = abstractTun  else  { return }
                for data in traffic ?? [] {
                    tun.receiveTunnelTraffic(data)
                }
            }, maxDatagrams: 1024)
        }
        
        socket.writeDatagram(packetBytes, completionHandler: {
            error in
        })
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
    }
    
}


enum AbstractTunError: Error {
    case initializationError
}

