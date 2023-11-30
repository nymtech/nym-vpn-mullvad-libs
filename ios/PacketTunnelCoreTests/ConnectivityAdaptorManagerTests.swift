//
//  ConnectivityAdaptorManagerTests.swift
//  PacketTunnelCoreTests
//
//  Created by Mojgan on 2023-11-23.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
import MullvadTypes
@testable import PacketTunnelCore
import XCTest

final class ConnectivityAdaptorManagerTests: XCTestCase {
    func testThrottlingAfterOneMinute() throws {
        let throttlingExpectation = self.expectation(description: "Did receive throttling after one minute")

        let retryStrategy = PacketTunnelActor.RetryStrategy(initial: 5, delay: .exponentialBackoffWithJitter(
            initial: .seconds(5),
            multiplier: 2,
            maxDelay: nil
        ), timeout: .minutes(1))

        let connectivityAdaptorManager = ConnectivityAdaptorManager(retryStrategy: retryStrategy)
        var retryAttempts = 0
        var isTrying = true

        while isTrying {
            connectivityAdaptorManager.handle {
                retryAttempts += 1
            } onThrottling: {
                throttlingExpectation.fulfill()
                isTrying = false
            }
        }

        wait(for: [throttlingExpectation], timeout: retryStrategy.timeout.timeInterval)
    }

    func testThrottlingAfterFiveMinutes() throws {
        let throttlingExpectation = self.expectation(description: "Did receive throttling after five minutes")

        let retryStrategy = PacketTunnelActor.RetryStrategy(initial: 2, delay: .exponentialBackoff(
            initial: .seconds(15),
            multiplier: 2,
            maxDelay: .seconds(60)
        ), timeout: .minutes(5))

        let connectivityAdaptorManager = ConnectivityAdaptorManager(retryStrategy: retryStrategy)
        var retryAttempts = 0
        var isTrying = true

        while isTrying {
            connectivityAdaptorManager.handle {
                retryAttempts += 1
            } onThrottling: {
                throttlingExpectation.fulfill()
                isTrying = false
            }
        }

        wait(for: [throttlingExpectation], timeout: retryStrategy.timeout.timeInterval)
    }

    func testReconnectingBeforeFiveTimes() throws {
        let reconnectingExpectation = self.expectation(description: "Did receive reconnecting before five times")
        reconnectingExpectation.expectedFulfillmentCount = 5

        let throttlingExpectation = self.expectation(description: "Didn't receive throttling after five times")

        let retryStrategy = PacketTunnelActor.RetryStrategy(initial: 5, delay: .never, timeout: .seconds(30))

        let connectivityAdaptorManager = ConnectivityAdaptorManager(retryStrategy: retryStrategy)
        var isTrying = true

        while isTrying {
            connectivityAdaptorManager.handle {
                reconnectingExpectation.fulfill()
            } onThrottling: {
                throttlingExpectation.fulfill()
                isTrying = false
            }
        }

        wait(for: [throttlingExpectation, reconnectingExpectation], timeout: retryStrategy.timeout.timeInterval)
    }
}
