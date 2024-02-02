//
//  PersistentCustomRelayList.swift
//  MullvadVPN
//
//  Created by Mojgan on 2024-01-25.
//  Copyright © 2024 Mullvad VPN AB. All rights reserved.
//

import Foundation
import MullvadTypes

public struct CustomRelayList: Identifiable, Codable {
    public var id: UUID
    public var name: String
    public var list: [RelayLocation]
    public init(id: UUID, name: String, list: [RelayLocation]) {
        self.id = id
        self.name = name
        self.list = list
    }
}
