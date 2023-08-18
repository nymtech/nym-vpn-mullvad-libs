//
//  AppStoreAPIServiceProtocol.swift
//  MullvadVPN
//
//  Created by pronebird on 18/08/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
import MullvadREST

protocol AppStoreAPIServiceProtocol {
    /// Validate user account.
    /// Throws an error if it cannot complete validation or if account is invalid.
    func validateAccount(accountNumber: String) async throws

    /// Send AppStore receipt to backend for bookkeeping.
    /// Returns response with amount of time added to account.
    func createApplePayment(accountNumber: String, receipt: Data) async throws -> REST.CreateApplePaymentResponse

    /// Account number to use when unable to match payment with account number.
    /// Eventually this should be solved by using `SKPayment.applicationUsername` and using it to credit time to account instead of relying on account
    /// numbers.
    func accountNumberForUnknownPayment() -> String?
}
