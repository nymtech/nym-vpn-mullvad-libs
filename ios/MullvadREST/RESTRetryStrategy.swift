//
//  RESTRetryStrategy.swift
//  MullvadREST
//
//  Created by pronebird on 09/12/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Foundation
import MullvadTypes

extension REST {
    public struct RetryStrategy {
        public var maxRetryCount: Int
        public var delay: RetryDelay

        public init(maxRetryCount: Int, delay: RetryDelay) {
            self.maxRetryCount = maxRetryCount
            self.delay = delay
        }

        public func makeDelayIterator() -> AnyIterator<Duration> {
            let inner = delay.makeIterator()
            return AnyIterator(inner)
        }

        /// Strategy configured to never retry.
        public static var noRetry = RetryStrategy(
            maxRetryCount: 0,
            delay: .never
        )

        /// Strategy configured with 2 retry attempts and exponential backoff.
        public static var `default` = RetryStrategy(
            maxRetryCount: 2,
            delay: defaultRetryDelay
        )

        /// Strategy configured with 10 retry attempts and exponential backoff.
        public static var aggressive = RetryStrategy(
            maxRetryCount: 10,
            delay: defaultRetryDelay
        )

        /// Default retry delay.
        public static var defaultRetryDelay: RetryDelay = .exponentialBackoffWithJitter(
            initial: .seconds(2),
            multiplier: 2,
            maxDelay: .seconds(8)
        )
    }
}
