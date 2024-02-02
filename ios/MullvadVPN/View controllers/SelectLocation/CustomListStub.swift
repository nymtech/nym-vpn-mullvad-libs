//
//  CustomListStub.swift
//  MullvadVPN
//
//  Created by Mojgan on 2024-01-31.
//  Copyright © 2024 Mullvad VPN AB. All rights reserved.
//

import Combine
import Foundation
import MullvadSettings

class CustomListStub: CustomListRepositoryProtocol {
    var publisher: AnyPublisher<[CustomRelayList], Never> {
        passthroughSubject.eraseToAnyPublisher()
    }

    private var customRelayLists: [CustomRelayList] = [
        CustomRelayList(id: UUID(), name: "Netflix", list: [.city("al", "tia")]),
        CustomRelayList(id: UUID(), name: "Streaming", list: [
            .city("us", "dal"),
            .country("se"),
            .city("se", "got"),
        ]),
    ]

    private let passthroughSubject = PassthroughSubject<[CustomRelayList], Never>()

    func update(_ list: CustomRelayList) {
        if let index = customRelayLists.firstIndex(where: { $0.id == list.id }) {
            customRelayLists[index] = list
        }
    }

    func delete(id: UUID) {
        if let index = customRelayLists.firstIndex(where: { $0.id == id }) {
            customRelayLists.remove(at: index)
        }
    }

    func fetch(by id: UUID) -> CustomRelayList? {
        return customRelayLists.first(where: { $0.id == id })
    }

    func create(_ name: String) throws -> CustomRelayList {
        let item = CustomRelayList(id: UUID(), name: name, list: [])
        customRelayLists.append(item)
        return item
    }

    func fetchAll() -> [CustomRelayList] {
        customRelayLists
    }
}
