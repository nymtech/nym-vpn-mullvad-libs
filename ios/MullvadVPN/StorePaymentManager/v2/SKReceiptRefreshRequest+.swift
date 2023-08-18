//
//  SKReceiptRefreshRequest+.swift
//  MullvadVPN
//
//  Created by pronebird on 18/08/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
import StoreKit

extension SKReceiptRefreshRequest {
    static func execute(receiptProperties: [String: Any]? = nil) async throws {
        let request = SKReceiptRefreshRequestExecutor(receiptProperties: receiptProperties)

        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { continuation in
                request.completionHandler = { error in
                    continuation.resume(with: error.map { .failure($0) } ?? .success(()))
                }
                request.start()
            }
        } onCancel: {
            request.cancel()
        }
    }
}

private final class SKReceiptRefreshRequestExecutor: NSObject, SKRequestDelegate {
    private let request: SKReceiptRefreshRequest

    var completionHandler: ((Error?) -> Void)?

    init(receiptProperties: [String: Any]?) {
        request = SKReceiptRefreshRequest(receiptProperties: receiptProperties)

        super.init()

        request.delegate = self
    }

    func start() {
        request.start()
    }

    func cancel() {
        request.cancel()
    }

    // - MARK: SKRequestDelegate

    func requestDidFinish(_ request: SKRequest) {
        completionHandler?(nil)
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        completionHandler?(error)
    }
}
