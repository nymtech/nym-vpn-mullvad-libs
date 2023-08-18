//
//  AppStoreAPIService.swift
//  MullvadVPN
//
//  Created by pronebird on 18/08/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
import MullvadREST

struct AppStoreAPIService: AppStoreAPIServiceProtocol {
    let apiProxy: REST.APIProxy
    let accountsProxy: REST.AccountsProxy
    let tunnelManager: TunnelManager

    func validateAccount(accountNumber: String) async throws {
        _ = try await withCheckedThrowingContinuation { continuation in
            // TODO: support cancellation
            _ = accountsProxy.getAccountData(accountNumber: accountNumber, retryStrategy: .default) { result in
                continuation.resume(with: result)
            }
        }
    }

    func createApplePayment(accountNumber: String, receipt: Data) async throws -> REST.CreateApplePaymentResponse {
        try await withCheckedThrowingContinuation { continuation in
            // TODO: support cancellation
            _ = apiProxy.createApplePayment(
                accountNumber: accountNumber,
                receiptString: receipt,
                retryStrategy: .noRetry
            ) { result in
                continuation.resume(with: result)
            }
        }
    }

    func accountNumberForUnknownPayment() -> String? {
        // Since we do not persist the relation between payment and account number between the
        // app launches, we assume that all successful purchases belong to the active account
        // number.
        return tunnelManager.deviceState.accountData?.number
    }
}
