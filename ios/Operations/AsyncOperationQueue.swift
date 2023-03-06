//
//  AsyncOperationQueue.swift
//  Operations
//
//  Created by pronebird on 30/05/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

public final class AsyncOperationQueue: OperationQueue {
    override public func addOperation(_ operation: Operation) {
        if let operation = operation as? AsyncOperation {
            applyExclusivityRules(operation)

            super.addOperation(operation)

            operation.didEnqueue()
        } else {
            super.addOperation(operation)
        }
    }

    override public func addOperations(_ operations: [Operation], waitUntilFinished wait: Bool) {
        for case let operation as AsyncOperation in operations {
            applyExclusivityRules(operation)
        }

        super.addOperations(operations, waitUntilFinished: false)

        for case let operation as AsyncOperation in operations {
            operation.didEnqueue()
        }

        if wait {
            for operation in operations {
                operation.waitUntilFinished()
            }
        }
    }

    public static func makeSerial() -> AsyncOperationQueue {
        let queue = AsyncOperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }

    private func applyExclusivityRules(_ operation: AsyncOperation) {
        let exclusivityRules = operation.conditions
            .filter { condition in
                return condition.isMutuallyExclusive
            }
            .map { condition in
                return ExclusivityRule(
                    categories: condition.mutuallyExclusiveCategories,
                    behaviour: condition.exclusivityBehaviour
                )
            }

        if !exclusivityRules.isEmpty {
            ExclusivityManager.shared.addOperation(
                operation,
                exclusivityRules: exclusivityRules
            )
        }
    }
}

private struct ExclusivityRule {
    var categories: Set<String>
    var behaviour: ExclusivityBehaviour
}

private final class ExclusivityManager {
    static let shared = ExclusivityManager()

    private var operationsByCategory = [String: [Operation]]()
    private let nslock = NSLock()

    private init() {}

    func addOperation(_ operation: AsyncOperation, exclusivityRules: [ExclusivityRule]) {
        nslock.lock()
        defer { nslock.unlock() }

        let operationsToCancel = NSMutableOrderedSet()

        for exclusivityRule in exclusivityRules {
            for category in exclusivityRule.categories {
                var operations = operationsByCategory[category] ?? []

                switch exclusivityRule.behaviour {
                case .cancelPreceding:
                    operationsToCancel.addObjects(from: operations)

                case .default:
                    break
                }

                if !operations.contains(operation) {
                    operations.last.flatMap { operation.addDependency($0) }
                    operations.append(operation)

                    operationsByCategory[category] = operations
                }
            }

            let blockObserver = OperationBlockObserver(didFinish: { [weak self] op, error in
                self?.removeOperation(op, categories: exclusivityRule.categories)
            })

            operation.addObserver(blockObserver)
        }

        operationsToCancel.remove(operation)

        for operationToCancel in operationsToCancel.array as! [Operation] {
            operationToCancel.cancel()
        }
    }

    private func removeOperation(_ operation: Operation, categories: Set<String>) {
        nslock.lock()
        defer { nslock.unlock() }

        for category in categories {
            guard var operations = operationsByCategory[category] else {
                continue
            }

            operations.removeAll { $0 == operation }

            if operations.isEmpty {
                operationsByCategory.removeValue(forKey: category)
            } else {
                operationsByCategory[category] = operations
            }
        }
    }
}
