//
//  IPCClient.swift
//  MullvadVPN
//
//  Created by Marco Nikic on 2023-11-02.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation

enum ClientState {
    case waitingForServerStart
    case fillingServerBuffer
    case stopped
    case standby
}

class IPCClient {
    let clientCommandQueue = DispatchQueue(label: "com.mullvadIPC.clientQueue")
    let serverReplyQueue = DispatchQueue(label: "com.mullvadIPC.replyQueue")
    let tunnel: any TunnelProtocol
    var state: ClientState = .stopped

    init(tunnel: any TunnelProtocol) {
        self.tunnel = tunnel
    }

    func start() {
        guard state == .stopped else { return }
        state = .waitingForServerStart
        send(.startAction)
    }

    func stop() {
        clientCommandQueue.async { [weak self] in
            self?.state = .stopped
        }
    }

    func handleReply(_ reply: IPCCommand<IPCReply>) {
        dispatchPrecondition(condition: .onQueue(serverReplyQueue))
        NSLog("XXXX Handling reply \(reply.action)")
        switch reply.action {
        case .serverStarted:
            clientCommandQueue.async { [weak self] in
                self?.serverDidStart()
            }
        case .needBuffer:
            clientCommandQueue.async { [weak self] in
                self?.fillServerBuffer()
            }
        case let .reconnected(endpoint):
            NSLog("VPN Reconnected to \(endpoint)")
        }
    }

    func serverDidStart() {
        dispatchPrecondition(condition: .onQueue(clientCommandQueue))
        guard state == .waitingForServerStart else {
            NSLog("XXXX Unexpected state transition from \(state) to \(ClientState.fillingServerBuffer). Ignoring")
            return
        }

        fillServerBuffer()
    }

    func serverStoppedOrGone() {
        dispatchPrecondition(condition: .onQueue(clientCommandQueue))
        NSLog("XXXX Server is gone or stopped")
        state = .stopped
    }

    func fillServerBuffer() {
        dispatchPrecondition(condition: .onQueue(clientCommandQueue))
        guard state != .stopped else { return }
        state = .fillingServerBuffer
        for _ in 0 ..< IPCConstants.serverBufferSize {
            send(.fillBuffer)
        }
        state = .standby
    }

    func send(_ command: IPCCommand<IPCAction>) {
        do {
            NSLog("XXXX Sending \(command.action) command")
            let rawPayload = try JSONEncoder().encode(command)
            try tunnel.sendProviderMessage(rawPayload) { [weak self] receivedData in
                guard let self else { return }
                guard let receivedData else {
                    clientCommandQueue.async {
                        self.serverStoppedOrGone()
                    }
                    return
                }
                if let reply = try? JSONDecoder().decode(IPCCommand<IPCReply>.self, from: receivedData) {
                    NSLog("\(reply.action)")
                    serverReplyQueue.async {
                        self.handleReply(reply)
                    }
                } else {
                    NSLog("XXXX Misunderstood reply \(String(data: receivedData, encoding: .utf8)!)")
                }
            }
        } catch {
            print(error)
        }
    }
}

/*
 - Send "start" messages until server is available
 - Once server is available, send a message that allows for a custom response
 - Callback will come when server needs to communicate

 */
