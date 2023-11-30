//
//  ConnectivityAdaptorManager.swift
//  PacketTunnelCore
//
//  Created by Mojgan on 2023-11-23.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
import MullvadTypes

final public class ConnectivityAdaptorManager: ConnectivityAdaptorProtocol {
    public let retryStrategy: PacketTunnelActor.RetryStrategy
    private var retryAttempts = 0
    private var expiryTimeout: Date?
    private var nextFireDate: Date?
    private var delayIterator: AnyIterator<Duration>?

    public init(retryStrategy: PacketTunnelActor.RetryStrategy) {
        self.retryStrategy = retryStrategy
        self.delayIterator = retryStrategy.makeDelayIterator()
    }

    public func handle(
        onReconnecting: () -> Void,
        onThrottling: () -> Void
    ) {
        let now = Date()
        switch retryAttempts {
        case let counter where counter == 0:
            // capture expiry timeout after first connection loss occurrence
            expiryTimeout = now.addingTimeInterval(retryStrategy.timeout.timeInterval)
            fallthrough
        case let counter where counter < retryStrategy.initial:
            // try immediately
            nextFireDate = now
            fallthrough
        default:
            // throttle if the timeout is passed out
            guard let expiryTimeout, now <= expiryTimeout else {
                onThrottling()
                return
            }
            // reconnect if it's time
            guard var nextFireDate, now >= nextFireDate else {
                return
            }
            onReconnecting()
            retryAttempts += 1
            // put delay between retries if there is a back-off strategy for after the initial value retry in a raw
            guard retryAttempts >= retryStrategy.initial else {
                return
            }
            guard let nextDelay = delayIterator?.next() else {
                onThrottling()
                return
            }
            nextFireDate = now.addingTimeInterval(nextDelay.timeInterval)
        }
    }

    public func reset() {
        retryAttempts = 0
        expiryTimeout = nil
        nextFireDate = nil
        delayIterator = retryStrategy.makeDelayIterator()
    }
}
