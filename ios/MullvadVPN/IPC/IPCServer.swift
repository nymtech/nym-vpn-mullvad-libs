//
//  IPCServer.swift
//  PacketTunnel
//
//  Created by Marco Nikic on 2023-11-02.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation

class IPCServer {
    typealias IPCCompletionHandler = (Data?) -> Void
    private let commandQueue = DispatchQueue(label: "com.mullvadIPC.serverQueue")

    var bufferedCommands: [IPCCommand<IPCAction>: IPCCompletionHandler] = [:]

    func start(_ completionHandler: IPCCompletionHandler?) {
        dispatchPrecondition(condition: .onQueue(commandQueue))
        bufferedCommands.removeAll()
        completionHandler?(encodeReply(IPCCommand.serverStartedAction))
    }

    func buffer(_ command: IPCCommand<IPCAction>, _ completionHandler: IPCCompletionHandler?) {
        dispatchPrecondition(condition: .onQueue(commandQueue))
        NSLog("XXXX buffering command")
        bufferedCommands[command] = completionHandler
    }

    func stop() {
        NSLog("XXXX Removing buffer commands")
        bufferedCommands.removeAll()
    }

    func sendReconnectedTo(_ endpoint: String) {
        commandQueue.async { [weak self] in
            guard let self else { return }
            let completionHandler = dequeueCommand()
            completionHandler(encodeReply(IPCCommand(uniqueIdentifier: UUID(), action: .reconnected(endpoint))))
        }
    }

    func requestBuffer() {
        dispatchPrecondition(condition: .onQueue(commandQueue))
        if let bufferedAction = bufferedCommands.popFirst() {
            bufferedAction.value(encodeReply(IPCCommand.needBufferAction))
        }
    }

    func dequeueCommand() -> IPCCompletionHandler {
        dispatchPrecondition(condition: .onQueue(commandQueue))
        guard let bufferedAction = bufferedCommands.popFirst() else {
            fatalError("Tried to dequeue but no buffered commands")
        }

        if bufferedCommands.count == 1 {
            requestBuffer()
        }

        return bufferedAction.value
    }

    func encodeReply(_ reply: IPCCommand<IPCReply>) -> Data? {
        do {
            return try JSONEncoder().encode(reply)
        } catch {
            NSLog("XXXX \(error)")
        }
        return nil
    }

    func handle(_ message: IPCCommand<IPCAction>, completionHandler: IPCCompletionHandler?) {
        commandQueue.async { [weak self] in
            guard let self else { return }
            NSLog("XXXX Received command \(message.action)")
            switch message.action {
            case .start:
                start(completionHandler)
            case .fillBuffer:
                buffer(message, completionHandler)
            }
        }
    }
}

/*
 - Always running
 - When it receives a "start" command, drops all the previous commands
 - Stores a future with a custom IPC Response to communicate with the host
 */
