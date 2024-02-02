//
//  CustomListRepositoryProtocol.swift
//  MullvadVPN
//
//  Created by Mojgan on 2024-01-25.
//  Copyright © 2024 Mullvad VPN AB. All rights reserved.
//

import Combine
import Foundation
import MullvadTypes
public protocol CustomListRepositoryProtocol {
    /// Publisher that propagates a snapshot of persistent store upon modifications.
    var publisher: AnyPublisher<[CustomRelayList], Never> { get }

    /// Persist modified custom list locating existing entry by id.
    /// - Parameter list: persistent custom list model.
    func update(_ list: CustomRelayList)

    /// Delete access method by id.
    /// - Parameter id: an access method id.
    func delete(id: UUID)

    /// Fetch custom list  by id.
    /// - Parameter id: a custom list id.
    /// - Returns: a persistent custom list model upon success, otherwise `nil`.
    func fetch(by id: UUID) -> CustomRelayList?

    /// Create a custom list  by unique name.
    /// - Parameter name: a custom list name.
    /// - Returns: a persistent custom list model upon success, otherwise  throws `Error`.
    func create(_ name: String) throws -> CustomRelayList

    /// Fetch all  custom list.
    /// - Returns: all custom list model .
    func fetchAll() -> [CustomRelayList]
}
