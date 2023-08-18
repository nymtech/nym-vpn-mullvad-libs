//
//  ReceiptFetcher.swift
//  MullvadVPN
//
//  Created by pronebird on 18/08/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
import StoreKit

struct ReceiptFetcher {
    let receiptProperties: [String: Any]?
    let forceRefresh: Bool

    func execute() async throws -> Data {
        if forceRefresh {
            try await refreshReceipt()
        }

        do {
            return try readReceiptFromDisk()
        } catch is StoreReceiptNotFound {
            try await refreshReceipt()

            return try readReceiptFromDisk()
        }
    }

    private func refreshReceipt() async throws {
        try await SKReceiptRefreshRequest.execute(receiptProperties: receiptProperties)
    }

    private func readReceiptFromDisk() throws -> Data {
        guard let appStoreReceiptURL = Bundle.main.appStoreReceiptURL else { throw StoreReceiptNotFound() }

        do {
            return try Data(contentsOf: appStoreReceiptURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            throw StoreReceiptNotFound()
        }
    }
}
