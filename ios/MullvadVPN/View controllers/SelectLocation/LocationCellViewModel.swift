//
//  LocationViewModel.swift
//  MullvadVPN
//
//  Created by Mojgan on 2024-01-30.
//  Copyright © 2024 Mullvad VPN AB. All rights reserved.
//

import Foundation
import MullvadTypes

struct LocationCellViewModel: Hashable {
    let group: String
    let location: RelayLocation
}

struct LocationTableGroupViewModel {
    let group: String
    var list: [LocationCellViewModel] = []
}
