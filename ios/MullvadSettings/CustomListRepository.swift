//
//  CustomListRepository.swift
//  MullvadVPN
//
//  Created by Mojgan on 2024-01-25.
//  Copyright © 2024 Mullvad VPN AB. All rights reserved.
//

import Combine
import Foundation
import MullvadLogging
import MullvadTypes

public enum CustomRelayLists: LocalizedError {
    case duplicateName

    public var errorDescription: String? {
        switch self {
        case .duplicateName:
            "Name is already taken."
        }
    }
}

public struct CustomListRepository: CustomListRepositoryProtocol {
    public var publisher: AnyPublisher<[CustomRelayList], Never> {
        passthroughSubject.eraseToAnyPublisher()
    }

    private let logger = Logger(label: "CustomListRepository")
    private let passthroughSubject = PassthroughSubject<[CustomRelayList], Never>()

    private let settingsParser: SettingsParser = {
        SettingsParser(decoder: JSONDecoder(), encoder: JSONEncoder())
    }()

    public init() {}

    public func create(_ name: String) throws -> CustomRelayList {
        do {
            var lists = try read()
            if lists.contains(where: { $0.name == name }) {
                throw CustomRelayLists.duplicateName
            } else {
                let item = CustomRelayList(id: UUID(), name: name, list: [])
                lists.append(item)
                try write(lists)
                return item
            }
        } catch {
            throw error
        }
    }

    public func delete(id: UUID) {
        do {
            var lists = try read()
            if let index = lists.firstIndex(where: { $0.id == id }) {
                lists.remove(at: index)
                try write(lists)
            }
        } catch {
            logger.error(error: error)
        }
    }

    public func fetch(by id: UUID) -> CustomRelayList? {
        try? read().first(where: { $0.id == id })
    }

    public func fetchAll() -> [CustomRelayList] {
        (try? read()) ?? []
    }

    public func update(_ list: CustomRelayList) {
        do {
            var lists = try read()
            if let index = lists.firstIndex(where: { $0.id == list.id }) {
                lists[index] = list
                try write(lists)
            }
        } catch {
            logger.error(error: error)
        }
    }
}

extension CustomListRepository {
    private func read() throws -> [CustomRelayList] {
        let data = try SettingsManager.store.read(key: .customRelayLists)

        return try settingsParser.parseUnversionedPayload(as: [CustomRelayList].self, from: data)
    }

    private func write(_ list: [CustomRelayList]) throws {
        let data = try settingsParser.produceUnversionedPayload(list)

        try SettingsManager.store.write(data, for: .customRelayLists)

        passthroughSubject.send(list)
    }
}
