//
//  LocationDataSource.swift
//  MullvadVPN
//
//  Created by pronebird on 11/03/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import MullvadLogging
import MullvadREST
import MullvadSettings
import MullvadTypes
import UIKit

class LocationDataSource: UITableViewDiffableDataSource<String, LocationCellViewModel> {
    private let tableView: UITableView
    private let locationCellFactory: LocationCellFactory

    private var customListRepository: CustomListRepositoryProtocol

    var selectedRelayLocation: LocationCellViewModel?
    var didSelectRelayLocation: ((RelayLocation) -> Void)?

    private var list: [LocationTableGroupViewModel] = []
    private var nodeByLocation = [LocationCellViewModel: Node]()
    private var currentSearchString = ""
    private var isEditing = false

    init(customListRepository: CustomListRepositoryProtocol = CustomListStub(), tableView: UITableView) {
        self.customListRepository = customListRepository
        self.tableView = tableView

        let identifier = SelectLocationCell.reuseIdentifier
        let locationCellFactory = LocationCellFactory(
            tableView: tableView,
            identifier: identifier,
            nodeByLocation: nodeByLocation
        )
        self.locationCellFactory = locationCellFactory

        super.init(tableView: tableView) { _, indexPath, itemIdentifier in
            locationCellFactory.makeCell(for: itemIdentifier, indexPath: indexPath)
        }

        tableView.register(
            SelectLocationCell.self,
            forCellReuseIdentifier: identifier
        )

        locationCellFactory.delegate = self
        tableView.delegate = self
    }

    func setRelays(_ response: REST.ServerRelaysResponse, filter: RelayFilter) {
        nodeByLocation.removeAll()
        let relays = response.wireguard.relays.filter { relay in
            return RelaySelector.relayMatchesFilter(relay, filter: filter)
        }
        makeAddCustomList()
        makeCustomLists(response, relays: relays)
        makeAllLocations(response, relays: relays)
        filterRelays(by: currentSearchString)
    }

    func filterRelays(by searchString: String) {
        currentSearchString = searchString

        if currentSearchString.isEmpty {
            resetLocationList()
        } else {}
        //
        //        var filteredLocations = [RelayLocation]()
        //
        //        locationList.forEach { location in
        //            guard let countryNode = nodeByLocation[location] else { return }
        //            countryNode.showsChildren = false
        //
        //            if searchString.isEmpty || countryNode.displayName.fuzzyMatch(searchString) {
        //                filteredLocations.append(countryNode.location)
        //            }
        //
        //            for cityNode in countryNode.children {
        //                cityNode.showsChildren = false
        //
        //                let relaysContainSearchString = cityNode.children.contains(where: { node in
        //                    node.displayName.fuzzyMatch(searchString)
        //                })
        //
        //                if cityNode.displayName.fuzzyMatch(searchString) || relaysContainSearchString {
        //                    if !filteredLocations.contains(countryNode.location) {
        //                        filteredLocations.append(countryNode.location)
        //                    }
        //
        //                    filteredLocations.append(cityNode.location)
        //                    countryNode.showsChildren = true
        //
        //                    if relaysContainSearchString {
        //                        filteredLocations.append(contentsOf: cityNode.children.map { $0.location })
        //                        cityNode.showsChildren = true
        //                    }
        //                }
        //            }
    }

    func indexPathForSelectedRelay() -> IndexPath? {
        selectedRelayLocation.flatMap { indexPath(for: $0) }
    }

    // MARK: - private function

    private func makeAddCustomList() {
        let group = SelectLocationGroup.customList.description
        list.append(LocationTableGroupViewModel(group: group, list: []))
    }

    private func makeAllLocations(_ response: REST.ServerRelaysResponse, relays: [REST.ServerRelay]) {
        let group = SelectLocationGroup.allLocations.description
        let rootNode = makeRootNode(name: SelectLocationGroup.allLocations.description)
        for relay in relays {
            guard case let .city(countryCode, cityCode) = RelayLocation(dashSeparatedString: relay.location),
                  let serverLocation = response.locations[relay.location] else { continue }

            let relayLocation = RelayLocation.hostname(countryCode, cityCode, relay.hostname)

            for ascendantOrSelf in relayLocation.ascendants + [relayLocation] {
                guard !nodeByLocation.keys
                    .contains(where: { $0.group == group && $0.location == ascendantOrSelf }) else {
                    continue
                }

                // Maintain the `showsChildren` state when transitioning between relay lists
                let wasShowingChildren = nodeByLocation[LocationCellViewModel(group: group, location: ascendantOrSelf)]?
                    .showsChildren ?? false

                let node = createNode(
                    group: group,
                    ascendantOrSelf: ascendantOrSelf,
                    serverLocation: serverLocation,
                    relay: relay,
                    rootNode: rootNode,
                    wasShowingChildren: wasShowingChildren
                )
                nodeByLocation[LocationCellViewModel(group: group, location: ascendantOrSelf)] = node
            }
        }

        rootNode.sortChildrenRecursive()
        rootNode.computeActiveChildrenRecursive()

        list.append(LocationTableGroupViewModel(group: group, list: rootNode.flatRelayLocationList().map {
            LocationCellViewModel(group: group, location: $0)
        }))
    }

    private func makeCustomLists(_ response: REST.ServerRelaysResponse, relays: [REST.ServerRelay]) {
        for item in customListRepository.fetchAll() {
            let group = item.name
            let rootNode = makeRootNode(name: group)

            for relayLocation in item.list {
                guard case .city = relayLocation,
                      let relay = relays.first(where: { $0.location == relayLocation.stringRepresentation }),
                      let serverLocation = response.locations[relay.location] else {
                    continue
                }

                for ascendantOrSelf in relayLocation.ascendants + [relayLocation] {
                    guard !nodeByLocation.keys
                        .contains(where: { $0.group == group && $0.location == ascendantOrSelf }) else {
                        continue
                    }

                    // Maintain the `showsChildren` state when transitioning between relay lists
                    let wasShowingChildren = nodeByLocation[LocationCellViewModel(
                        group: group,
                        location: ascendantOrSelf
                    )]?
                        .showsChildren ?? false

                    let node = createNode(
                        group: group,
                        ascendantOrSelf: ascendantOrSelf,
                        serverLocation: serverLocation,
                        relay: relay,
                        rootNode: rootNode,
                        wasShowingChildren: wasShowingChildren
                    )
                    nodeByLocation[LocationCellViewModel(group: group, location: ascendantOrSelf)] = node
                }

                rootNode.sortChildrenRecursive()
                rootNode.computeActiveChildrenRecursive()
            }

            list.append(LocationTableGroupViewModel(group: group, list: rootNode.flatRelayLocationList().map {
                LocationCellViewModel(group: group, location: $0)
            }))
        }
    }

    private func makeRootNode(name: String) -> Node {
        Node(
            type: .root,
            location: .country("#root"),
            displayName: name,
            showsChildren: true,
            isActive: true,
            children: []
        )
    }

    private func createNode(
        group: String,
        ascendantOrSelf: RelayLocation,
        serverLocation: REST.ServerLocation,
        relay: REST.ServerRelay,
        rootNode: Node,
        wasShowingChildren: Bool
    ) -> Node {
        let node: Node

        switch ascendantOrSelf {
        case .country:
            node = Node(
                type: .country,
                location: ascendantOrSelf,
                displayName: serverLocation.country,
                showsChildren: wasShowingChildren,
                isActive: true,
                children: []
            )
            rootNode.addChild(node)

        case let .city(countryCode, _):
            node = Node(
                type: .city,
                location: ascendantOrSelf,
                displayName: serverLocation.city,
                showsChildren: wasShowingChildren,
                isActive: true,
                children: []
            )
            nodeByLocation[LocationCellViewModel(group: group, location: .country(countryCode))]!.addChild(node)

        case let .hostname(countryCode, cityCode, _):
            node = Node(
                type: .relay,
                location: ascendantOrSelf,
                displayName: relay.hostname,
                showsChildren: false,
                isActive: relay.active,
                children: []
            )
            nodeByLocation[LocationCellViewModel(group: group, location: .city(countryCode, cityCode))]!.addChild(node)
        }

        return node
    }

    private func resetLocationList() {
        nodeByLocation.values.forEach { $0.showsChildren = false }

        updateDataSnapshot(with: list, reloadExisting: true)
        //        setSelectedRelayLocation(selectedRelayLocation, animated: false)

        if let indexPath = indexPathForSelectedRelay() {
            tableView.scrollToRow(at: indexPath, at: .middle, animated: false)
        }
    }

    private func updateDataSnapshot(
        with items: [LocationTableGroupViewModel],
        reloadExisting: Bool = false,
        animated: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        updateCellFactory(with: nodeByLocation)

        var snapshot = NSDiffableDataSourceSnapshot<String, LocationCellViewModel>()
        let sections = items.map { $0.group }

        snapshot.appendSections(sections)

        for item in items {
            snapshot.appendItems(item.list, toSection: item.group)
        }

        if reloadExisting {
            snapshot.reloadSections(sections)
        }

        apply(snapshot, animatingDifferences: animated, completion: completion)
    }

    private func updateCellFactory(with nodeByLocation: [LocationCellViewModel: Node]) {
        locationCellFactory.nodeByLocation = nodeByLocation
    }

    private func item(for indexPath: IndexPath) -> LocationDataSourceItemProtocol? {
        itemIdentifier(for: indexPath).flatMap { nodeByLocation[$0] }
    }

    private func toggleChildren(
        _ locationCellViewModel: LocationCellViewModel,
        show: Bool,
        animated: Bool
    ) {
        guard let node = nodeByLocation[locationCellViewModel],
              let indexPath = indexPath(for: locationCellViewModel),
              let cell = tableView.cellForRow(at: indexPath) else { return }

        node.showsChildren = show
        locationCellFactory.configureCell(
            cell,
            item: LocationCellViewModel(
                group: locationCellViewModel.group,
                location: node.location
            ),
            indexPath: indexPath
        )

        var locationList = snapshot().itemIdentifiers(inSection: locationCellViewModel.group)
        let locationsToEdit = node.flatRelayLocationList().map { LocationCellViewModel(
            group: locationCellViewModel.group,
            location: $0
        ) }

        if show {
            locationList.addLocations(locationsToEdit, at: indexPath.row + 1)
        } else {
            locationsToEdit.forEach { nodeByLocation[$0]?.showsChildren = false }
            locationList.removeLocations(locationsToEdit)
        }
        let sectionIndex = list.firstIndex(where: { $0.group == locationCellViewModel.group })!
        list[sectionIndex].list = locationList

        updateDataSnapshot(with: list, reloadExisting: animated) { [weak self] in
            guard let visibleIndexPaths = self?.tableView.indexPathsForVisibleRows else { return }
            if node.children.count > visibleIndexPaths.count {
//                if let firstInsertedIndexPath = self?.indexPath(for: node.location) {
//                    self?.tableView.scrollToRow(
//                        at: firstInsertedIndexPath,
//                        at: .top,
//                        animated: animated
//                    )
//                }

            } else {}
        }
        //
        //        updateDataSnapshot(with: .init(allLists: locationList,customLists: locationList), animated: animated) { [weak self] in
        //            guard let visibleIndexPaths = self?.tableView.indexPathsForVisibleRows else { return }
        //
        //            let scrollToNodeTop = {
//                        if let firstInsertedIndexPath = self?.indexPath(for: node.location) {
//                            self?.tableView.scrollToRow(
//                                at: firstInsertedIndexPath,
//                                at: .top,
//                                animated: animated
//                            )
//                        }
        //            }
        //
        //            let scrollToNodeBottom = {
        //                if let location = node.children.last?.location,
        //                   let lastInsertedIndexPath = self?.indexPath(for: location),
        //                   let lastVisibleIndexPath = visibleIndexPaths.last,
        //                   lastInsertedIndexPath >= lastVisibleIndexPath {
        //                    self?.tableView.scrollToRow(
        //                        at: lastInsertedIndexPath,
        //                        at: .bottom,
        //                        animated: animated
        //                    )
        //                }
        //            }
        //
        //            if node.children.count > visibleIndexPaths.count {
        //                scrollToNodeTop()
        //            } else {
        //                scrollToNodeBottom()
        //            }
        //        }
    }
}

// final class LocationDataSource: LocationDiffableDataSource {

//
//    private var nodeByLocation = [LocationViewModel: Node]()
//    private var locationList = LocationTableViewModel()
//    private var currentSearchString = ""
//    private var isEditing = false
//    private var customListRepository: CustomListRepositoryProtocol
//
//    private let tableView: UITableView
//    private let locationCellFactory: LocationCellFactory
//
//    private class func makeRootNode(name: String) -> Node {
//        Node(
//            type: .root,
//            location: RelayLocation.country(name),
//            displayName: name,
//            showsChildren: true,
//            isActive: true,
//            children: []
//        )
//    }
//
//    var selectedRelayLocation: RelayLocation?
//    var didSelectRelayLocation: ((RelayLocation) -> Void)?
//
//    init(
//        tableView: UITableView,
//        customList: CustomListRepositoryProtocol = CustomListStub()
//    ) {
//        self.tableView = tableView
//        self.customListRepository = customList
//
//        let locationCellFactory = LocationCellFactory(
//            tableView: tableView,
//            nodeByLocation: nodeByLocation
//        )
//        self.locationCellFactory = locationCellFactory
//
//        super.init(tableView: tableView) { _, indexPath, itemIdentifier in
//            locationCellFactory.makeCell(for: itemIdentifier, indexPath: indexPath)
//        }
//
//        tableView.delegate = self
//        locationCellFactory.delegate = self
//
//        defaultRowAnimation = .fade
//        registerClasses()
//    }
//
//    func setRelays(_ response: REST.ServerRelaysResponse, filter: RelayFilter) {
//        let relays = response.wireguard.relays.filter { relay in
//            return RelaySelector.relayMatchesFilter(relay, filter: filter)
//        }
//
//        let rootNode = Self.makeRootNode(name: SelectLocationCategory.allLocations.description)
//        nodeByLocation.removeAll()
//
//        for relay in relays {
//            guard case let .city(countryCode, cityCode) = RelayLocation(dashSeparatedString: relay.location),
//                  let serverLocation = response.locations[relay.location] else { continue }
//
//            let relayLocation = RelayLocation.hostname(countryCode, cityCode, relay.hostname)
//
//            for ascendantOrSelf in relayLocation.ascendants + [relayLocation] {
//                guard !nodeByLocation.keys
//                    .contains(where: { $0.group == .allLocations && $0.location == ascendantOrSelf }) else {
//                    continue
//                }
//
//                // Maintain the `showsChildren` state when transitioning between relay lists
//                let wasShowingChildren = nodeByLocation[.init(group: .allLocations, location: ascendantOrSelf)]?
//                    .showsChildren ?? false
//
//                let node = createNode(
//                    for: .allLocations,
//                    ascendantOrSelf: ascendantOrSelf,
//                    serverLocation: serverLocation,
//                    relay: relay,
//                    rootNode: rootNode,
//                    wasShowingChildren: wasShowingChildren
//                )
//                nodeByLocation[.init(group: .allLocations, location: ascendantOrSelf)] = node
//            }
//        }
//
//        rootNode.sortChildrenRecursive()
//        rootNode.computeActiveChildrenRecursive()
//        locationList.allLists = rootNode.flatRelayLocationList().map { .init(
//            group: .allLocations,
//            location: $0
//        ) }
//
//        setCustomList(response, relays: relays)
//        filterRelays(by: currentSearchString)
//    }
//
//    func setCustomList(_ response: REST.ServerRelaysResponse, relays: [REST.ServerRelay]) {
//        let rootNode = Self.makeRootNode(name: SelectLocationCategory.customList.description)
//        for item in customListRepository.fetchAll() {
//            let customListNode = Self.makeRootNode(name: item.name)
//            rootNode.addChild(customListNode)
//            nodeByLocation[.init(group: .customList, location: .country(item.name))] = customListNode
//
//            for relayLocation in item.list {
//                guard case .city = relayLocation,
//                      let relay = relays.first(where: { $0.location == relayLocation.stringRepresentation }),
//                      let serverLocation = response.locations[relay.location] else {
//                    continue
//                }
//
//                for ascendantOrSelf in relayLocation.ascendants + [relayLocation] {
//                    guard !nodeByLocation.keys
//                        .contains(where: { $0.group == .customList && $0.location == ascendantOrSelf }) else {
//                        continue
//                    }
//
//                    let wasShowingChildren = nodeByLocation[LocationViewModel(
//                        group: .customList,
//                        location: relayLocation
//                    )]?.showsChildren ?? false
//
//                    let node = createNode(
//                        for: .customList,
//                        ascendantOrSelf: ascendantOrSelf,
//                        serverLocation: serverLocation,
//                        relay: relay,
//                        rootNode: customListNode,
//                        wasShowingChildren: wasShowingChildren
//                    )
//
//                    nodeByLocation[.init(group: .customList, location: ascendantOrSelf)] = node
//                }
//
//                customListNode.sortChildrenRecursive()
//                customListNode.computeActiveChildrenRecursive()
//            }
//        }
//
//        locationList.customLists.append(contentsOf: rootNode.flatRelayLocationList().map { LocationViewModel(
//            group: .customList,
//            location: $0
//        ) })
//    }
//
////    func setCustomList(_ response: REST.ServerRelaysResponse, relays: [REST.ServerRelay]) {
////        let rootNode = Self.makeRootNode(name: SelectLocationCategory.customList.description)
////        for item in customListRepository.fetchAll() {
////            let customListNode = Self.makeRootNode(name: item.name)
////
////            for relayLocation in item.list {
////
////                guard case .city = relayLocation,
////                      let relay = relays.first(where: { $0.location == relayLocation.stringRepresentation }),
////                      let serverLocation = response.locations[relay.location] else {
////                    continue
////                }
////
////                for ascendantOrSelf in relayLocation.ascendants + [relayLocation] {
////                    guard !nodeByLocation.keys
////                        .contains(where: { $0.category == .customList && $0.location == ascendantOrSelf }) else {
////                        continue
////                    }
////
////                    let wasShowingChildren = nodeByLocation[LocationViewModel(
////                        category: .customList,
////                        location: relayLocation
////                    )]?.showsChildren ?? false
////
////                    let node = createNode(
////                        for: .customList,
////                        ascendantOrSelf: ascendantOrSelf,
////                        serverLocation: serverLocation,
////                        relay: relay,
////                        rootNode: customListNode,
////                        wasShowingChildren: wasShowingChildren
////                    )
////
////                    nodeByLocation[.init(category: .customList, location: ascendantOrSelf)] = node
////                }
////
////                print(rootNode.flatRelayLocationList(includeHiddenChildren: false).map { $0.stringRepresentation })
////
////                customListNode.sortChildrenRecursive()
////                customListNode.computeActiveChildrenRecursive()
////
////
//    ////                locationList.customLists.append(contentsOf: rootNode.flatRelayLocationList().map { LocationViewModel(
//    ////                    category: .customList,
//    ////                    location: $0
//    ////                ) })
////            }
////
////            locationList.customLists.append(contentsOf: rootNode.flatRelayLocationList().map { LocationViewModel(
////                category: .customList,
////                location: $0
////            ) })
////        }
////    }
//
//    func indexPathForSelectedRelay() -> IndexPath? {
//        nil // selectedRelayLocation.flatMap { indexPath(for: $0) }
//    }
//
//    func filterRelays(by searchString: String) {
//        currentSearchString = searchString
//
//        if currentSearchString.isEmpty {
//            return resetLocationList()
//        }
////
////        var filteredLocations = [RelayLocation]()
////
////        locationList.forEach { location in
////            guard let countryNode = nodeByLocation[location] else { return }
////            countryNode.showsChildren = false
////
////            if searchString.isEmpty || countryNode.displayName.fuzzyMatch(searchString) {
////                filteredLocations.append(countryNode.location)
////            }
////
////            for cityNode in countryNode.children {
////                cityNode.showsChildren = false
////
////                let relaysContainSearchString = cityNode.children.contains(where: { node in
////                    node.displayName.fuzzyMatch(searchString)
////                })
////
////                if cityNode.displayName.fuzzyMatch(searchString) || relaysContainSearchString {
////                    if !filteredLocations.contains(countryNode.location) {
////                        filteredLocations.append(countryNode.location)
////                    }
////
////                    filteredLocations.append(cityNode.location)
////                    countryNode.showsChildren = true
////
////                    if relaysContainSearchString {
////                        filteredLocations.append(contentsOf: cityNode.children.map { $0.location })
////                        cityNode.showsChildren = true
////                    }
////                }
////            }
////        }
////
////        updateDataSnapshot(with: filteredLocations, reloadExisting: true) { [weak self] in
////            self?.scrollToTop(animated: false)
////        }
//    }
//
//    private func createNode(
//        for category: SelectLocationCategory,
//        ascendantOrSelf: RelayLocation,
//        serverLocation: REST.ServerLocation,
//        relay: REST.ServerRelay,
//        rootNode: Node,
//        wasShowingChildren: Bool
//    ) -> Node {
//        let node: Node
//
//        switch ascendantOrSelf {
//        case .country:
//            node = Node(
//                type: .country,
//                location: ascendantOrSelf,
//                displayName: serverLocation.country,
//                showsChildren: wasShowingChildren,
//                isActive: true,
//                children: []
//            )
//            rootNode.addChild(node)
//
//        case let .city(countryCode, _):
//            node = Node(
//                type: .city,
//                location: ascendantOrSelf,
//                displayName: serverLocation.city,
//                showsChildren: wasShowingChildren,
//                isActive: true,
//                children: []
//            )
//            nodeByLocation[.init(group: category, location: .country(countryCode))]!.addChild(node)
//
//        case let .hostname(countryCode, cityCode, _):
//            node = Node(
//                type: .relay,
//                location: ascendantOrSelf,
//                displayName: relay.hostname,
//                showsChildren: false,
//                isActive: relay.active,
//                children: []
//            )
//            nodeByLocation[.init(group: category, location: .city(countryCode, cityCode))]!.addChild(node)
//        }
//
//        return node
//    }
//
//    private func updateDataSnapshot(
//        with locations: LocationTableViewModel,
//        reloadExisting: Bool = false,
//        animated: Bool = false,
//        completion: (() -> Void)? = nil
//    ) {
//        updateCellFactory(with: nodeByLocation)
//
//        var snapshot = NSDiffableDataSourceSnapshot<SelectLocationCategory, LocationViewModel>()
//        snapshot.appendSections(SelectLocationCategory.allCases)
//        snapshot.appendItems(locations.customLists, toSection: .customList)
//        snapshot.appendItems(locations.allLists, toSection: .allLocations)
//
////        if reloadExisting {
////            snapshot.reloadItems(locations)
////        }
//
//        apply(snapshot, animatingDifferences: animated, completion: completion)
//    }
//
//    private func registerClasses() {
//        CellReuseIdentifiers.allCases.forEach { enumCase in
//            tableView.register(
//                enumCase.reusableViewClass,
//                forCellReuseIdentifier: enumCase.rawValue
//            )
//        }
//    }
//
//    private func updateCellFactory(with nodeByLocation: [LocationViewModel: Node]) {
//        locationCellFactory.nodeByLocation = nodeByLocation
//    }
//
//    private func setSelectedRelayLocation(
//        _ relayLocation: RelayLocation?,
//        animated: Bool,
//        completion: (() -> Void)? = nil
//    ) {
////        selectedRelayLocation = relayLocation
////        var locationList = snapshot().itemIdentifiers
////
////        guard let selectedRelayLocation,
////              !locationList.contains(selectedRelayLocation) else { return }
////
////        let selectedLocationTree = selectedRelayLocation.ascendants + [selectedRelayLocation]
////
////        guard let topLocation = selectedLocationTree.first,
////              let topNode = nodeByLocation[topLocation],
////              let indexPath = indexPath(for: topLocation)
////        else {
////            return
////        }
////
////        selectedLocationTree.forEach { location in
////            nodeByLocation[location]?.showsChildren = true
////        }
////
////        locationList.addLocations(topNode.flatRelayLocationList(), at: indexPath.row + 1)
////        updateDataSnapshot(with: locationList, reloadExisting: true, animated: animated, completion: completion)
//    }
//
//    private func toggleChildren(
//        _ relayLocation: LocationViewModel,
//        show: Bool,
//        animated: Bool
//    ) {
////        guard let node = nodeByLocation[relayLocation],
////              let indexPath = indexPath(for: relayLocation),
////              let cell = tableView.cellForRow(at: indexPath) else { return }
////
////        node.showsChildren = show
////        locationCellFactory.configureCell(cell, item: .init(category: relayLocation.category, location: node.location), indexPath: indexPath)
////
////        var locationList = snapshot().itemIdentifiers
////        let locationsToEdit = node.flatRelayLocationList().map({LocationViewModel(category: relayLocation.category, location: $0)})
////
////        if show {
////            locationList.addLocations(locationsToEdit, at: indexPath.row + 1)
////        } else {
////            locationsToEdit.forEach { nodeByLocation[$0]?.showsChildren = false }
////            locationList.removeLocations(locationsToEdit)
////        }
////
////        updateDataSnapshot(with: .init(allLists: locationList,customLists: locationList), animated: animated) { [weak self] in
////            guard let visibleIndexPaths = self?.tableView.indexPathsForVisibleRows else { return }
////
////            let scrollToNodeTop = {
////                if let firstInsertedIndexPath = self?.indexPath(for: node.location) {
////                    self?.tableView.scrollToRow(
////                        at: firstInsertedIndexPath,
////                        at: .top,
////                        animated: animated
////                    )
////                }
////            }
////
////            let scrollToNodeBottom = {
////                if let location = node.children.last?.location,
////                   let lastInsertedIndexPath = self?.indexPath(for: location),
////                   let lastVisibleIndexPath = visibleIndexPaths.last,
////                   lastInsertedIndexPath >= lastVisibleIndexPath {
////                    self?.tableView.scrollToRow(
////                        at: lastInsertedIndexPath,
////                        at: .bottom,
////                        animated: animated
////                    )
////                }
////            }
////
////            if node.children.count > visibleIndexPaths.count {
////                scrollToNodeTop()
////            } else {
////                scrollToNodeBottom()
////            }
////        }
//    }
//
//    private func resetLocationList() {
//        nodeByLocation.values.forEach { $0.showsChildren = false }
//
//        updateDataSnapshot(with: locationList, reloadExisting: true)
//        setSelectedRelayLocation(selectedRelayLocation, animated: false)
//
//        if let indexPath = indexPathForSelectedRelay() {
//            tableView.scrollToRow(at: indexPath, at: .middle, animated: false)
//        }
//    }
//
//    private func item(for indexPath: IndexPath) -> LocationDataSourceItemProtocol? {
//        itemIdentifier(for: indexPath).flatMap { nodeByLocation[$0] }
//    }
//
//    private func scrollToTop(animated: Bool) {
//        tableView.setContentOffset(.zero, animated: animated)
//    }
// }
//
// extension LocationDataSource: UITableViewDelegate {
//    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
//        item(for: indexPath)?.isActive ?? false
//    }
//
//    func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
//        item(for: indexPath)?.indentationLevel ?? 0
//    }
//
//    func tableView(
//        _ tableView: UITableView,
//        willDisplay cell: UITableViewCell,
//        forRowAt indexPath: IndexPath
//    ) {
//        if let item = item(for: indexPath),
//           item.location == selectedRelayLocation {
//            cell.setSelected(true, animated: false)
//        }
//    }
//
//    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
//        guard let item = item(for: indexPath),
//              item.location != selectedRelayLocation
//        else {
//            return
//        }
//
//        if let indexPath = indexPathForSelectedRelay(),
//           let cell = tableView.cellForRow(at: indexPath) {
//            cell.setSelected(false, animated: false)
//        }
//
//        setSelectedRelayLocation(
//            item.location,
//            animated: false
//        )
//
//        didSelectRelayLocation?(item.location)
//    }
//

extension LocationDataSource: UITableViewDelegate {
    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        item(for: indexPath)?.isActive ?? false
    }

    func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
        item(for: indexPath)?.indentationLevel ?? 0
    }

    func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        if let item = item(for: indexPath),
           item.location == selectedRelayLocation?.location {
            cell.setSelected(true, animated: false)
        }
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        switch section {
        case tableView.numberOfSections - 2:
            return isEditing
                ? AddCustomRelayListView(
                    configuration: AddCustomRelayListView
                        .Configuration(primaryAction: UIAction(handler: { action in

                        }))
                )
                : nil
        default:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch section {
        case 0: return SelectLocationHeaderView(configuration: SelectLocationHeaderView.Configuration(
                name: list[section].group,
                primaryAction: UIAction(handler: { [weak self] action in
                    self?.isEditing = true
                    tableView.reloadData()
                })
            ))
        case let section where section < tableView.numberOfSections - 1:
            return nil
        default:
            return SelectLocationHeaderView(configuration: SelectLocationHeaderView.Configuration(
                name: list[section].group,
                primaryAction: nil
            ))
        }
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        switch section {
        case tableView.numberOfSections - 2:
            return isEditing ? 87.0 : 20.0
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch section {
        case 0, tableView.numberOfSections - 1:
            return 44.0
        default:
            return 0
        }
    }
}

extension LocationDataSource: LocationCellEventHandler {
    func collapseCell(for item: LocationCellViewModel) {
        guard let node = nodeByLocation[item] else { return }
        toggleChildren(
            item,
            show: !node.showsChildren,
            animated: true
        )
    }
}

private extension [LocationCellViewModel] {
    mutating func addLocations(_ locations: [LocationCellViewModel], at index: Int) {
        if index < count {
            insert(contentsOf: locations, at: index)
        } else {
            append(contentsOf: locations)
        }
    }

    mutating func removeLocations(_ locations: [LocationCellViewModel]) {
        removeAll(where: { location in
            locations.contains(location)
        })
    }
}
