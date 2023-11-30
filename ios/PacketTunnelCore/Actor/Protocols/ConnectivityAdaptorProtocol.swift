//
//  ConnectivityAdaptorProtocol.swift
//  PacketTunnelCore
//
//  Created by Mojgan on 2023-11-23.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation

public protocol ConnectivityAdaptorProtocol {
    var retryStrategy: PacketTunnelActor.RetryStrategy { get }

    func handle(
        onReconnecting: () -> Void,
        onThrottling: () -> Void
    )

    func reset()
}
