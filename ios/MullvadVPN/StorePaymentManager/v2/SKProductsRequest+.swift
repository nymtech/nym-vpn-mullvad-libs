//
//  SKProductsRequest+.swift
//  MullvadVPN
//
//  Created by pronebird on 18/08/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
import StoreKit

extension SKProductsRequest {
    static func execute(productIdentifiers: Set<String>) async throws -> SKProductsResponse {
        let request = SKProductsRequestExecutor(productIdentifiers: productIdentifiers)

        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { continuation in
                request.completionHandler = { result in
                    continuation.resume(with: result)
                }
                request.start()
            }
        } onCancel: {
            request.cancel()
        }
    }
}

private final class SKProductsRequestExecutor: NSObject, SKProductsRequestDelegate {
    private let request: SKProductsRequest

    var completionHandler: ((Result<SKProductsResponse, Error>) -> Void)?

    init(productIdentifiers: Set<String>) {
        request = SKProductsRequest(productIdentifiers: productIdentifiers)

        super.init()

        request.delegate = self
    }

    func start() {
        request.start()
    }

    func cancel() {
        request.cancel()
    }

    // - MARK: SKProductsRequestDelegate

    func requestDidFinish(_ request: SKRequest) {}

    func request(_ request: SKRequest, didFailWithError error: Error) {
        completionHandler?(.failure(error))
    }

    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        completionHandler?(.success(response))
    }
}
