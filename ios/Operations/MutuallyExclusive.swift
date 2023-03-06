//
//  MutuallyExclusive.swift
//  Operations
//
//  Created by pronebird on 25/09/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

public final class MutuallyExclusive: OperationCondition {
    public let name: String
    public let mutuallyExclusiveCategories: Set<String>
    public let exclusivityBehaviour: ExclusivityBehaviour

    public convenience init(
        category: String,
        exclusivityBehaviour: ExclusivityBehaviour = .default
    ) {
        self.init(categories: [category], exclusivityBehaviour: exclusivityBehaviour)
    }

    public init(categories: Set<String>, exclusivityBehaviour: ExclusivityBehaviour = .default) {
        name = "MutuallyExclusive<\(categories.joined(separator: ", "))>"
        mutuallyExclusiveCategories = categories
        self.exclusivityBehaviour = exclusivityBehaviour
    }

    public func evaluate(for operation: Operation, completion: @escaping (Bool) -> Void) {
        completion(true)
    }
}
