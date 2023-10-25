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
    let apiProxy: APIQuerying
    let accountsProxy: RESTAccountHandling
    let tunnelManager: TunnelManager

    func validateAccount(accountNumber: String) async throws {
        _ = try await accountsProxy.getAccountData(accountNumber: accountNumber).execute(retryStrategy: .default)
    }

    func createApplePayment(accountNumber: String, receipt: Data) async throws -> REST.CreateApplePaymentResponse {
        return try await apiProxy.createApplePayment(accountNumber: accountNumber, receiptString: receipt).execute()
    }

    func accountNumberForUnknownPayment() -> String? {
        // Since we do not persist the relation between payment and account number between the
        // app launches, we assume that all successful purchases belong to the active account
        // number.
        return tunnelManager.deviceState.accountData?.number
    }
}
