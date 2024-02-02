//
//  LocationDataSourceItemProtocol.swift
//  MullvadVPN
//
//  Created by Mojgan on 2024-02-01.
//  Copyright © 2024 Mullvad VPN AB. All rights reserved.
//

import Foundation
import MullvadTypes

protocol LocationDataSourceItemProtocol {
    var location: RelayLocation { get }
    var displayName: String { get }
    var showsChildren: Bool { get }
    var isActive: Bool { get }
    var isCollapsible: Bool { get }
    var indentationLevel: Int { get }
}
