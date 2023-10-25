//
//  AppStore.swift
//  MullvadVPN
//
//  Created by pronebird on 18/08/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import MullvadLogging
import StoreKit
import UIKit
import MullvadREST

actor AppStore {
    private let logger = Logger(label: "AppStore")

    private let application: UIApplication
    private let paymentQueue: SKPaymentQueue
    private let apiService: AppStoreAPIServiceProtocol

    private var paymentObserverTask: Task<Void, Never>?
    private var productFetchTask: Task<[SKProduct], Error>?
    private var sendReceiptTask: Task<REST.CreateApplePaymentResponse, Error>?

    private var pendingPayments: [PendingPayment] = []

    /// Returns true if the device is able to make payments.
    nonisolated static var canMakePayments: Bool {
        SKPaymentQueue.canMakePayments()
    }

    init(application: UIApplication, paymentQueue: SKPaymentQueue, apiService: AppStoreAPIServiceProtocol) {
        self.application = application
        self.paymentQueue = paymentQueue
        self.apiService = apiService
    }

    func startPaymentHandling() async {
        paymentObserverTask?.cancel()

        paymentObserverTask = Task {
            logger.debug("Start payment queue monitoring")

            for await event in paymentQueue.events {
                switch event {
                case let .updatedTransactions(transactions):
                    await self.handleTransactions(transactions)

                case .restoredCompletedTransactions, .removedTransactions:
                    break
                }
            }
        }
    }

    func stopPaymentHandling() async {
        paymentObserverTask?.cancel()
        paymentObserverTask = nil
    }

    func fetchProducts(products: Set<StoreSubscription>) async throws -> [AppStoreProduct] {
        let currentFetchTask = productFetchTask

        let newFetchTask = Task {
            // Wait for previous task to complete.
            try? await currentFetchTask?.value

            return try await application.withBackgroundTask {
                let fetcher = ProductFetcher(productIdentifiers: products.productIdentifiersSet)
                let response = try await fetcher.execute()

                return response.products
            }
        }

        productFetchTask = newFetchTask

        let products = try await newFetchTask.value

        return products.map { AppStoreProduct($0) }
    }

    func purchase(product: AppStoreProduct, for accountNumber: String) async throws {
        try await application.withBackgroundTask {
            // Make sure that account number is valid before making a payment.
            try await self.apiService.validateAccount(accountNumber: accountNumber)

            let payment = SKPayment(product: product.skProduct)

            self.pendingPayments.append(PendingPayment(accountNumber: accountNumber, payment: payment))
            self.paymentQueue.add(payment)
        }

        // TODO: notify the client when transaction is finished and return `REST.CreateApplePaymentResponse`.
    }

    func restorePurchases(accountNumber: String) async throws {
        do {
            try await sendReceipt(accountNumber: accountNumber, forceRefresh: true)
        } catch {
            logger.error(error: error, message: "Failed to send receipt when restoring purchases.")

            throw error
        }
    }

    // MARK: - Transactions handling

    private func handleTransactions(_ transactions: [SKPaymentTransaction]) async {
        for transaction in transactions {
            await handleTransaction(transaction)
        }
    }

    private func handleTransaction(_ transaction: SKPaymentTransaction) async {
        switch transaction.transactionState {
        case .deferred:
            logger.info("Deferred \(transaction.payment.productIdentifier)")

        case .failed:
            logger.error(
                "Failed to purchase \(transaction.payment.productIdentifier): \(transaction.error?.localizedDescription ?? "No error")"
            )

            await handleFailedTransaction(transaction)

        case .purchased:
            logger.info("Purchased \(transaction.payment.productIdentifier)")

            await handleSuccessfulTransaction(transaction)

        case .purchasing:
            logger.info("Purchasing \(transaction.payment.productIdentifier)")

        case .restored:
            logger.info("Restored \(transaction.payment.productIdentifier)")

            await handleSuccessfulTransaction(transaction)

        @unknown default:
            logger.warning("Unknown transactionState = \(transaction.transactionState.rawValue)")
        }
    }

    private func handleFailedTransaction(_ transaction: SKPaymentTransaction) async {
        finishTransaction(transaction)
    }

    private func handleSuccessfulTransaction(_ transaction: SKPaymentTransaction) async {
        // Find pending payment by SKPayment
        let pendingPayment = pendingPayments.first { $0.payment == transaction.payment }

        // If pending payment is not found, call delegate to get current account number because we need to credit time
        // somewhere.
        let accountNumber = pendingPayment?.accountNumber ?? apiService.accountNumberForUnknownPayment()

        guard let accountNumber else {
            logger.warning("Cannot find account number associated with transaction.")
            return
        }

        do {
            try await sendReceipt(accountNumber: accountNumber, forceRefresh: false)

            finishTransaction(transaction)
        } catch {
            logger.error(error: error, message: "Failed to send receipt when handling a successful transaction.")
        }
    }

    private func finishTransaction(_ transaction: SKPaymentTransaction) {
        paymentQueue.finishTransaction(transaction)
        pendingPayments.removeAll { $0.payment == transaction.payment }
    }

    // MARK: - Receipt handling

    /// Reads AppStore receipt from disk and sends it to our backend.
    private func sendReceipt(accountNumber: String, forceRefresh: Bool) async throws {
        let currentTask = sendReceiptTask

        sendReceiptTask = Task {
            // Wait for previous task to complete to avoid races
            await currentTask?.waitForCompletion()

            return try await application.withBackgroundTask {
                let receiptFetcher = ReceiptFetcher(receiptProperties: nil, forceRefresh: forceRefresh)
                let data = try await receiptFetcher.execute()

                return try await self.apiService.createApplePayment(accountNumber: accountNumber, receipt: data)
            }
        }
    }
}

private struct PendingPayment {
    var accountNumber: String
    var payment: SKPayment
}

struct AppStoreProduct {
    var productIdentifier: String {
        skProduct.productIdentifier
    }

    var localizedTitle: String {
        skProduct.localizedTitle
    }

    var price: NSDecimalNumber {
        skProduct.price
    }

    var localizedPrice: String? {
        skProduct.localizedPrice
    }

    fileprivate let skProduct: SKProduct

    fileprivate init(_ skProduct: SKProduct) {
        self.skProduct = skProduct
    }
}
