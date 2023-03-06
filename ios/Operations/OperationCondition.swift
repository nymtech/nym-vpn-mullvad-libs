//
//  OperationCondition.swift
//  Operations
//
//  Created by pronebird on 30/05/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

/**
 Exclusivity behaviour applied to operations.
 */
public enum ExclusivityBehaviour {
    /**
     Only one operation with a particular exclusive category can execute at a time.
     */
    case `default`

    /**
     Same as `default` but also cancels preceding operations within a particular exclusive category.
     */
    case cancelPreceding
}

public protocol OperationCondition {
    /**
     Name of condition used for debugging purposes.
     */
    var name: String { get }

    /**
     Mutually exclusive categories to apply to osperation.
     */
    var mutuallyExclusiveCategories: Set<String> { get }

    /**
     Defines how mutual exclusivity should be handled.
     This only applies to operations that have mutually exclusive categories set.
     */
    var exclusivityBehaviour: ExclusivityBehaviour { get }

    /**
     Automatically called by operation queue to evaluate condition for operation.

     Implementation should always call `completion` passing `true` upon success, otherwise `false`.
     */
    func evaluate(for operation: Operation, completion: @escaping (Bool) -> Void)
}

public extension OperationCondition {
    var mutuallyExclusiveCategories: Set<String> {
        return []
    }

    var exclusivityBehaviour: ExclusivityBehaviour {
        return .default
    }

    var isMutuallyExclusive: Bool {
        return !mutuallyExclusiveCategories.isEmpty
    }
}
