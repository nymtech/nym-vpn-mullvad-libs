//
//  ProductFetcher.swift
//  MullvadVPN
//
//  Created by pronebird on 18/08/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
import StoreKit

struct ProductFetcher {
    let productIdentifiers: Set<String>
    let maxAttempts: UInt = 10
    let retryDelay: TimeInterval = 2

    func execute() async throws -> SKProductsResponse {
        var lastError: Error = CancellationError()

        for attempt in 0 ..< maxAttempts {
            do {
                if attempt > 0 {
                    try await Task.sleep(seconds: retryDelay)
                }
                return try await SKProductsRequest.execute(productIdentifiers: productIdentifiers)
            } catch {
                lastError = error
            }
        }

        throw lastError
    }
}
