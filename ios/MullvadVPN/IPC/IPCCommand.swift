//
//  IPCCommand.swift
//  MullvadVPN
//
//  Created by Marco Nikic on 2023-11-02.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation

enum IPCConstants {
    static let serverBufferSize = 5
}

enum IPCAction: Sendable, Codable {
    case start
    case fillBuffer
}

enum IPCReply: Sendable, Codable {
    case serverStarted
    case needBuffer
    case reconnected(String)
}

struct IPCCommand<ActionType: Sendable & Codable>: Sendable, Codable, Hashable {
    static func == (lhs: IPCCommand<ActionType>, rhs: IPCCommand<ActionType>) -> Bool {
        lhs.uniqueIdentifier == rhs.uniqueIdentifier
    }

    let uniqueIdentifier: UUID
    let action: ActionType

    func hash(into hasher: inout Hasher) {
        hasher.combine(uniqueIdentifier.uuidString)
    }
}

extension IPCCommand where ActionType == IPCAction {
    static var startAction: Self {
        IPCCommand(uniqueIdentifier: UUID(), action: .start)
    }

    static var fillBuffer: Self {
        IPCCommand(uniqueIdentifier: UUID(), action: .fillBuffer)
    }
}

extension IPCCommand where ActionType == IPCReply {
    static var serverStartedAction: Self {
        IPCCommand(uniqueIdentifier: UUID(), action: .serverStarted)
    }

    static var needBufferAction: Self {
        IPCCommand(uniqueIdentifier: UUID(), action: .needBuffer)
    }
}
