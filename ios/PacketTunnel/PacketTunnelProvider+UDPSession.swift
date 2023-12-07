//
//  PacketTunnelProvider+UDPSession.swift
//  PacketTunnel
//
//  Created by Marco Nikic on 2023-12-06.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
import NetworkExtension

enum UDPSessionInformation: UInt64 {
    case betterPathAvailable
    case canReadOrWriteData
    case cannotReadOrWriteData
    case readHandlerError
    case failedReadingData
}

class UDPSession: Hashable, Equatable {
    let uniqueIdentifier = UUID().uuidString
    let dispatchQueue: DispatchQueue
    var localUDPSession: NWUDPSession?
    var sessionIsReady = false

    var stateObserver: NSKeyValueObservation?
    var betterPathObserver: NSKeyValueObservation?
    var isViableObserver: NSKeyValueObservation?

    init(hostname: String, port: String) {
        dispatchQueue = DispatchQueue(label: "com.UDPSession.to-\(hostname)-\(port)")
    }

    static func == (lhs: UDPSession, rhs: UDPSession) -> Bool { lhs.uniqueIdentifier == rhs.uniqueIdentifier }
    var hashValue: Int { uniqueIdentifier.hashValue }
    func hash(into hasher: inout Hasher) {
        hasher.combine(uniqueIdentifier.hash)
    }
}

// Creates a UDP session
// `addr` is pointer to a valid UTF-8 string representing the socket address
// `addrLen` is representing the length of the `addr` string in bytes
// `rustContext` is a pointer to the Rust context.
@_cdecl("swift_nw_udp_session_create")
func udpSessionCreate(
    addr: UnsafeMutableRawPointer,
    addrLen: UInt64,
    port: UInt16,
    packetTunnelContext: UnsafeMutableRawPointer,
    rustContext: UnsafeMutableRawPointer
) -> UnsafeMutableRawPointer {
    let unalignedAddr = addr.loadUnaligned(as: UnsafePointer<UInt8>.self)
    let unsafeAddr = UnsafeBufferPointer(start: unalignedAddr, count: Int(addrLen))
    let address = String(bytes: unsafeAddr, encoding: .utf8)!

    let portString = "\(port)"
    let endpoint = NWHostEndpoint(hostname: address, port: portString)
    let sessionBox = UDPSession(hostname: address, port: portString)

    let packetTunnel = Unmanaged<PacketTunnelProvider>.fromOpaque(packetTunnelContext).takeUnretainedValue()
    let session = packetTunnel.createUDPSession(to: endpoint, from: nil)
    sessionBox.dispatchQueue.sync {
        setupSessionObservers(for: session, in: sessionBox, rustContext: rustContext)
    }
    sessionBox.localUDPSession = session

    return Unmanaged.passRetained(sessionBox).toOpaque()
}

func setupSessionObservers(
    for session: NWUDPSession,
    in sessionBox: UDPSession,
    rustContext: UnsafeMutableRawPointer
) {
    dispatchPrecondition(condition: .onQueue(sessionBox.dispatchQueue))
    // Clear previous observers
    sessionBox.stateObserver = nil
    sessionBox.betterPathObserver = nil
    sessionBox.isViableObserver = nil

    let stateObserver = session.observe(\.state, options: [.new]) { session, _ in
        if session.state == .ready {
            sessionBox.dispatchQueue.async { [weak sessionBox] in
                guard let sessionBox else { return }
                guard sessionBox.sessionIsReady == false else { return }
                udp_session_ready(rustContext: rustContext)
                sessionBox.sessionIsReady = true
            }
        }

        if session.state == .cancelled || session.state == .failed {
            sessionBox.dispatchQueue.async { [weak sessionBox] in sessionBox?.sessionIsReady = false }
        }
    }
    sessionBox.stateObserver = stateObserver

    let pathObserver = session.observe(\.hasBetterPath, options: [.new]) { session, _ in
        if session.hasBetterPath {
            sessionBox.dispatchQueue.async { [weak sessionBox] in
                guard let sessionBox else { return }
                let upgradedSession = NWUDPSession(upgradeFor: session)
                setupSessionObservers(for: upgradedSession, in: sessionBox, rustContext: rustContext)
                sessionBox.localUDPSession = upgradedSession
                let rawSession = Unmanaged.passUnretained(upgradedSession).toOpaque()
                udp_session_upgrade(rustContext: rustContext, newSession: rawSession)
            }
        }
    }
    sessionBox.betterPathObserver = pathObserver

    let isViableObserver = session.observe(\.isViable, options: [.new]) { session, _ in
        let isViable: UDPSessionInformation = session.isViable ? .canReadOrWriteData : .cannotReadOrWriteData
        udp_session_error(rustContext: rustContext, status: isViable.rawValue)
    }
    sessionBox.isViableObserver = isViableObserver

    session.setReadHandler({ readData, maybeError in
        if let maybeError {
            NSLog("\(maybeError.localizedDescription)")
            udp_session_error(rustContext: rustContext, status: UDPSessionInformation.readHandlerError.rawValue)
            return
        }
        guard let readData else {
            NSLog("No data was read")
            udp_session_error(rustContext: rustContext, status: UDPSessionInformation.failedReadingData.rawValue)
            return
        }
        let rawData = DataArray(readData).toRaw()
        udp_session_recv(rustContext: rustContext, data: rawData)
    }, maxDatagrams: 2000)
}

// Will be called from the Rust side to send data.
// `session` is a pointer to Self
// `data` is a pointer to a DataArray (AbstractTunData.swift)
@_cdecl("swift_nw_udp_session_send")
func udpSessionSend(session: UnsafeMutableRawPointer, data: UnsafeMutableRawPointer) {
    let udpSession = Unmanaged<UDPSession>.fromOpaque(session).takeUnretainedValue()
    let dataArray = Unmanaged<DataArray>.fromOpaque(data).takeUnretainedValue()

    // If `dispatchQueue` were to be concurrent, the `.barrier` flag should be passed here
    // to guarantee that only one call to `writeMultipleDatagrams` can happen at a time.
    udpSession.dispatchQueue.async { [weak udpSession] in
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        udpSession?.localUDPSession?.writeMultipleDatagrams(dataArray.arr) { maybeError in
            if let maybeError {
                NSLog("\(maybeError.localizedDescription)")
                // TODO: maybe get a rust context here in case of error ?
            }
            dispatchGroup.leave()
        }

        dispatchGroup.wait()
    }
}

// Should destroy current UDP session
// After this call, no callbacks into rust should be made with the rustContext pointer.
@_cdecl("swift_nw_udp_session_destroy")
func udpSessionDestroy(rawSession: UnsafeMutableRawPointer) {
    let udpSession = Unmanaged<UDPSession>.fromOpaque(rawSession).takeRetainedValue()
    udpSession.dispatchQueue.async { [udpSession] in
        guard let session = udpSession.localUDPSession else { return }
        udpSession.betterPathObserver = nil
        udpSession.stateObserver = nil
        udpSession.isViableObserver = nil
        session.cancel()
    }
}

// TODO: Remove these once the rust code is in place
// Callback into Rust when new data is received.
func udp_session_recv(rustContext: UnsafeMutableRawPointer, data: UnsafeMutableRawPointer) {}
// Callback to call when UDP session state changes to `ready`. Only expected to be called once.
func udp_session_ready(rustContext: UnsafeMutableRawPointer) {}
// An error callback to be called when non-transient errors are present,
// i.e. state of session changes, or if the session has a better path
func udp_session_error(rustContext: UnsafeMutableRawPointer, status: UInt64) {}
// Callback into rust when a better path is available.
func udp_session_upgrade(rustContext: UnsafeMutableRawPointer, newSession: UnsafeMutableRawPointer) {}
