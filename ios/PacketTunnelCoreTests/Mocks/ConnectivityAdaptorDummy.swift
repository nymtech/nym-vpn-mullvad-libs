//
//  ConnectivityAdaptorDummy.swift
//  PacketTunnelCoreTests
//
//  Created by Mojgan on 2023-11-28.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
import PacketTunnelCore
final class ConnectivityAdaptorDummy: ConnectivityAdaptorProtocol {
    private var counter: UInt8 = 0
    var retryStrategy: PacketTunnelCore.PacketTunnelActor.RetryStrategy {
        PacketTunnelCore.PacketTunnelActor.RetryStrategy(
            initial: 5,
            delay: .exponentialBackoff(
                initial: .milliseconds(500),
                multiplier: 2,
                maxDelay: nil
            ),
            timeout: .minutes(3)
        )
    }

    func handle(
        onReconnecting: () -> Void,
        onThrottling: () -> Void
    ) {
        counter += 1
    }

    func reset() {}
}
