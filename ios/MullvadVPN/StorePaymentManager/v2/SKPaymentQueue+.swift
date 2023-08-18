//
//  SKPaymentQueue+.swift
//  MullvadVPN
//
//  Created by pronebird on 18/08/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
import StoreKit

extension SKPaymentQueue {
    enum Event {
        case updatedTransactions([SKPaymentTransaction])
        case removedTransactions([SKPaymentTransaction])
        case restoredCompletedTransactions(Error?)
    }

    var events: AsyncStream<Event> {
        return AsyncStream { continuation in
            let transactionObserver = TransactionObserver(paymentQueue: self)

            transactionObserver.onEvent = { event in
                continuation.yield(event)
            }

            continuation.onTermination = { _ in
                transactionObserver.stop()
            }

            transactionObserver.start()
        }
    }
}

private final class TransactionObserver: NSObject, SKPaymentTransactionObserver {
    let paymentQueue: SKPaymentQueue
    var onEvent: ((SKPaymentQueue.Event) -> Void)?

    init(paymentQueue: SKPaymentQueue) {
        self.paymentQueue = paymentQueue
    }

    deinit {
        stop()
    }

    func start() {
        paymentQueue.add(self)
    }

    func stop() {
        paymentQueue.remove(self)
    }

    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        onEvent?(.updatedTransactions(transactions))
    }

    func paymentQueue(_ queue: SKPaymentQueue, removedTransactions transactions: [SKPaymentTransaction]) {
        onEvent?(.removedTransactions(transactions))
    }

    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        onEvent?(.restoredCompletedTransactions(error))
    }

    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        onEvent?(.restoredCompletedTransactions(nil))
    }
}
