//
//  RetryDelay.swift
//  MullvadTypes
//
//  Created by Mojgan on 2023-11-22.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation

public enum RetryDelay: Equatable {
    /// Never wait to retry.
    case never

    /// Constant delay.
    case constant(Duration)

    /// Exponential backoff.
    case exponentialBackoff(initial: Duration, multiplier: UInt64, maxDelay: Duration?)

    /// Exponential backoff with Jitter
    case exponentialBackoffWithJitter(initial: Duration, multiplier: UInt64, maxDelay: Duration?)

    public func makeIterator() -> AnyIterator<Duration> {
        switch self {
        case .never:
            return AnyIterator {
                nil
            }

        case let .constant(duration):
            return AnyIterator {
                duration
            }

        case let .exponentialBackoff(initial, multiplier, maxDelay):
            return AnyIterator(ExponentialBackoffDelay(
                initial: initial,
                multiplier: multiplier,
                maxDelay: maxDelay
            ))

        case let .exponentialBackoffWithJitter(initial, multiplier, maxDelay):
            return AnyIterator(Jittered(ExponentialBackoffDelay(
                initial: initial,
                multiplier: multiplier,
                maxDelay: maxDelay
            )))
        }
    }
}
