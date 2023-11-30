//
//  BackOffStrategy.swift
//  PacketTunnelCore
//
//  Created by Mojgan on 2023-11-22.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
import MullvadREST
import MullvadTypes

extension PacketTunnelActor {
    public struct RetryStrategy {
        let initial: Int
        let delay: RetryDelay
        let timeout: Duration

        public init(initial: Int, delay: RetryDelay, timeout: Duration) {
            self.initial = initial
            self.delay = delay
            self.timeout = timeout
        }

        func makeDelayIterator() -> AnyIterator<Duration> {
            let inner = delay.makeIterator()
            return AnyIterator(inner)
        }
    }
}
