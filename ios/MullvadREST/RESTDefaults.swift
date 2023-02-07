//
//  RESTDefaults.swift
//  MullvadREST
//
//  Created by Sajad Vishkai on 2022-10-17.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation
import MullvadTypes

extension REST {
    /// Default API hostname.
    public static let defaultAPIHostname = "api.devmole.eu"

    /// Default API endpoint.
    public static let defaultAPIEndpoint = AnyIPEndpoint(string: "85.203.53.75:443")!

    /// Default network timeout for API requests.
    public static let defaultAPINetworkTimeout: TimeInterval = 10
}
