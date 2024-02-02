//
//  SelectLocationGroup.swift
//  MullvadVPN
//
//  Created by Mojgan on 2024-02-01.
//  Copyright © 2024 Mullvad VPN AB. All rights reserved.
//

import Foundation
import UIKit

enum SelectLocationGroup: CustomStringConvertible {
    case customList
    case allLocations
    case custom(String)

    var description: String {
        switch self {
        case .customList:
            return NSLocalizedString(
                "SELECT_LOCATION_CUSTOM_LISTS",
                value: "Custom lists",
                comment: ""
            )
        case .allLocations:
            return NSLocalizedString(
                "SELECT_LOCATION_ALL_LOCATIONS",
                value: "All locations",
                comment: ""
            )
        case let .custom(name):
            return name
        }
    }
}
