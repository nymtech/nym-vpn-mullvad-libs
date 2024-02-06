//
//  LocationDataSource.swift
//  MullvadVPN
//
//  Created by pronebird on 11/03/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Combine
import MullvadREST
import MullvadTypes
import UIKit

// swiftlint:disable file_length
final class LocationDataSource: UITableViewDiffableDataSource<SelectLocationSectionGroup, LocationCellViewModel> {
    private var nodeByLocation = [LocationCellViewModel: SelectLocationNode]()
    private var locationList = [SelectLocationSectionGroup: [LocationCellViewModel]]()
    private var currentSearchString = ""

    private let tableView: UITableView
    private let locationCellFactory: LocationCellFactory
    private let parallelRequestsMutex = NSLock()

    var selectedRelayLocation: LocationCellViewModel?
    var didSelectRelayLocation: ((RelayLocation) -> Void)?

    init(tableView: UITableView) {
        self.tableView = tableView

        let locationCellFactory = LocationCellFactory(
            tableView: tableView,
            nodeByLocation: nodeByLocation
        )
        self.locationCellFactory = locationCellFactory

        super.init(tableView: tableView) { _, indexPath, itemIdentifier in
            locationCellFactory.makeCell(for: itemIdentifier, indexPath: indexPath)
        }

        tableView.delegate = self
        locationCellFactory.delegate = self

        defaultRowAnimation = .fade
        registerClasses()
    }

    func setRelays(_ response: REST.ServerRelaysResponse, filter: RelayFilter) {
        parallelRequestsMutex.lock()
        defer { parallelRequestsMutex.unlock() }
        let relays = response.wireguard.relays.filter { relay in
            return RelaySelector.relayMatchesFilter(relay, filter: filter)
        }
        nodeByLocation.removeAll()

        makeAllLocations(response, relays: relays)

        filterRelays(by: currentSearchString)
    }

    func indexPathForSelectedRelay() -> IndexPath? {
        selectedRelayLocation.flatMap {
            return indexPath(for: $0)
        }
    }

    func filterRelays(by searchString: String) {
        currentSearchString = searchString
        if searchString.isEmpty {
            resetLocationList()
        } else {
            updateDataSnapshot(with: fuzzySearch(searchString), reloadExisting: true) { [weak self] in
                self?.scrollToTop(animated: false)
            }
        }
    }

    private func fuzzySearch(_ text: String) -> [SelectLocationSectionGroup: [LocationCellViewModel]] {
        var filteredLocations: [SelectLocationSectionGroup: [LocationCellViewModel]] = [
            .customLists: [],
            .allLocations: [],
        ]

        locationList.forEach { key, value in
            value.forEach { location in
                guard let countryNode = nodeByLocation[location] else { return }
                countryNode.showsChildren = false

                if text.isEmpty || countryNode.displayName.fuzzyMatch(text) {
                    filteredLocations[key]?.append(LocationCellViewModel(
                        group: key,
                        location: countryNode.location
                    ))
                }

                for cityNode in countryNode.children {
                    cityNode.showsChildren = false

                    let relaysContainSearchString = cityNode.children
                        .contains(where: { $0.displayName.fuzzyMatch(text) })

                    if cityNode.displayName.fuzzyMatch(text) || relaysContainSearchString {
                        if let values = filteredLocations[key],
                           !values.contains(where: { $0.location == countryNode.location }) {
                            filteredLocations[key]?.append(LocationCellViewModel(
                                group: key,
                                location: countryNode.location
                            ))
                        }

                        filteredLocations[key]?.append(LocationCellViewModel(
                            group: key,
                            location: cityNode.location
                        ))
                        countryNode.showsChildren = true

                        if relaysContainSearchString {
                            cityNode.children.map { $0.location }.forEach {
                                filteredLocations[key]?.append(LocationCellViewModel(group: key, location: $0))
                            }
                            cityNode.showsChildren = true
                        }
                    }
                }
            }
        }
        return filteredLocations
    }

    private func makeAllLocations(_ response: REST.ServerRelaysResponse, relays: [REST.ServerRelay]) {
        let group = SelectLocationSectionGroup.allLocations
        let rootNode = makeRootNode(name: group.description)
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
                    ascendantOrSelf: ascendantOrSelf,
                    serverLocation: serverLocation,
                    relay: relay,
                    wasShowingChildren: wasShowingChildren
                )
                let parent = getParent(group: group, location: ascendantOrSelf) ?? rootNode
                parent.addChild(node)
                nodeByLocation[LocationCellViewModel(group: group, location: ascendantOrSelf)] = node
            }
        }

        rootNode.sortChildrenRecursive()
        rootNode.computeActiveChildrenRecursive()

        locationList[group] = rootNode
            .flatRelayLocationList()
            .map { LocationCellViewModel(group: group, location: $0) }
    }

    private func makeRootNode(name: String) -> SelectLocationNode {
        SelectLocationNode(nodeType: .root, location: .country("#root"), displayName: name)
    }

    private func getParent(group: SelectLocationSectionGroup, location: RelayLocation) -> SelectLocationNode? {
        switch location {
        case .country:
            return nil
        case let .city(countryCode, _):
            return nodeByLocation[LocationCellViewModel(group: group, location: .country(countryCode))]
        case let .hostname(countryCode, cityCode, _):
            return nodeByLocation[LocationCellViewModel(group: group, location: .city(countryCode, cityCode))]
        }
    }

    private func createNode(
        ascendantOrSelf: RelayLocation,
        serverLocation: REST.ServerLocation,
        relay: REST.ServerRelay,
        wasShowingChildren: Bool
    ) -> SelectLocationNode {
        let node: SelectLocationNode

        switch ascendantOrSelf {
        case .country:
            node = SelectLocationNode(
                nodeType: .country,
                location: ascendantOrSelf,
                displayName: serverLocation.country,
                showsChildren: wasShowingChildren
            )

        case .city:
            node = SelectLocationNode(
                nodeType: .city,
                location: ascendantOrSelf,
                displayName: serverLocation.city,
                showsChildren: wasShowingChildren
            )

        case .hostname:
            node = SelectLocationNode(
                nodeType: .relay,
                location: ascendantOrSelf,
                displayName: relay.hostname,
                isActive: relay.active
            )
        }
        return node
    }

    private func updateDataSnapshot(
        with list: [SelectLocationSectionGroup: [LocationCellViewModel]],
        reloadExisting: Bool = false,
        animated: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        updateCellFactory(with: nodeByLocation)

        var snapshot = NSDiffableDataSourceSnapshot<SelectLocationSectionGroup, LocationCellViewModel>()

        snapshot.appendSections(SelectLocationSectionGroup.allCases)
        for key in list.keys {
            snapshot.appendItems(list[key] ?? [], toSection: key)
        }

        if reloadExisting {
            snapshot.reloadSections(SelectLocationSectionGroup.allCases)
        }

        apply(snapshot, animatingDifferences: animated, completion: completion)
    }

    private func registerClasses() {
        SelectLocationSectionGroup.allCases.forEach {
            tableView.register(
                $0.cell.reusableViewClass,
                forCellReuseIdentifier: $0.cell.reuseIdentifier
            )
        }
    }

    private func updateCellFactory(with nodeByLocation: [LocationCellViewModel: SelectLocationNode]) {
        locationCellFactory.nodeByLocation = nodeByLocation
    }

    private func setSelectedRelayLocation(
        _ relayLocation: LocationCellViewModel?,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        selectedRelayLocation = relayLocation

        selectedRelayLocation.flatMap { item in
            var locationList = snapshot().itemIdentifiers(inSection: item.group)
            guard !locationList.contains(item) else { return }

            let selectedLocationTree = item.location.ascendants + [item.location]

            guard let first = selectedLocationTree.first else { return }
            let topLocation = LocationCellViewModel(group: item.group, location: first)

            guard let topNode = nodeByLocation[topLocation],
                  let indexPath = indexPath(for: topLocation)
            else {
                return
            }

            selectedLocationTree.forEach { location in
                nodeByLocation[LocationCellViewModel(group: item.group, location: location)]?.showsChildren = true
            }

            locationList.addLocations(
                topNode.flatRelayLocationList().map { LocationCellViewModel(group: item.group, location: $0) },
                at: indexPath.row + 1
            )
            var copy = self.locationList
            copy[item.group] = locationList
            updateDataSnapshot(
                with: copy,
                reloadExisting: true,
                animated: animated,
                completion: completion
            )
        }
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
        var copy = self.locationList
        copy[locationCellViewModel.group] = locationList

        updateDataSnapshot(with: copy, reloadExisting: animated) { [weak self] in
            guard let self else { return }
            scroll(to: locationCellViewModel, animated: animated)
        }
    }

    private func resetLocationList() {
        nodeByLocation.values.forEach { $0.showsChildren = false }

        updateDataSnapshot(with: locationList, reloadExisting: true)
        setSelectedRelayLocation(selectedRelayLocation, animated: false)

        if let indexPath = indexPathForSelectedRelay() {
            tableView.scrollToRow(at: indexPath, at: .middle, animated: false)
        }
    }

    private func item(for indexPath: IndexPath) -> LocationCellViewModel? {
        itemIdentifier(for: indexPath)
    }

    private func scrollToTop(animated: Bool) {
        tableView.setContentOffset(.zero, animated: animated)
    }

    private func scroll(to location: LocationCellViewModel, animated: Bool) {
        guard let visibleIndexPaths = tableView.indexPathsForVisibleRows,
              let node = nodeByLocation[location] else { return }

        if node.children.count > visibleIndexPaths.count {
            indexPath(for: location).flatMap {
                tableView.scrollToRow(at: $0, at: .top, animated: animated)
            }
        } else {
            node.children.last.flatMap {
                if let lastInsertedIndexPath = indexPath(for: LocationCellViewModel(
                    group: location.group,
                    location: $0.location
                )),
                    let lastVisibleIndexPath = visibleIndexPaths.last,
                    lastInsertedIndexPath >= lastVisibleIndexPath {
                    tableView.scrollToRow(at: lastInsertedIndexPath, at: .bottom, animated: animated)
                }
            }
        }
    }
}

extension LocationDataSource: UITableViewDelegate {
    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        item(for: indexPath).flatMap { nodeByLocation[$0] }?.isActive ?? false
    }

    func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
        item(for: indexPath).flatMap { nodeByLocation[$0] }?.indentationLevel ?? 0
    }

    func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        if let item = item(for: indexPath),
           item == selectedRelayLocation {
            cell.setSelected(true, animated: false)
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = item(for: indexPath), item.location != selectedRelayLocation?.location else {
            return
        }

        if let indexPath = indexPathForSelectedRelay(),
           let cell = tableView.cellForRow(at: indexPath) {
            cell.setSelected(false, animated: false)
        }

        setSelectedRelayLocation(
            item,
            animated: false
        )

        didSelectRelayLocation?(item.location)
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
