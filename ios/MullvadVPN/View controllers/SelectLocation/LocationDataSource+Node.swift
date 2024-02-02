//
//  SelectLocationNode.swift
//  MullvadVPN
//
//  Created by Mojgan on 2024-02-01.
//  Copyright © 2024 Mullvad VPN AB. All rights reserved.
//

import Foundation
import MullvadTypes

extension LocationDataSource {
    enum NodeType: Int {
        case root
        case country
        case city
        case relay
    }

    class Node: LocationDataSourceItemProtocol {
        let nodeType: NodeType
        var location: RelayLocation
        var displayName: String
        var showsChildren: Bool
        var isActive: Bool
        var children: [Node]

        var isCollapsible: Bool {
            switch nodeType {
            case .relay:
                return false
            default:
                return true
            }
        }

        var indentationLevel: Int {
            switch nodeType {
            case .root:
                return 0
            case .country:
                return 1
            case .city:
                return 2
            case .relay:
                return 3
            }
        }

        init(
            type: NodeType,
            location: RelayLocation,
            displayName: String,
            showsChildren: Bool,
            isActive: Bool,
            children: [Node]
        ) {
            nodeType = type
            self.location = location
            self.displayName = displayName
            self.showsChildren = showsChildren
            self.isActive = isActive
            self.children = children
        }

        func addChild(_ child: Node) {
            children.append(child)
        }

        func sortChildrenRecursive() {
            sortChildren()
            children.forEach { node in
                node.sortChildrenRecursive()
            }
        }

        func computeActiveChildrenRecursive() {
            switch nodeType {
            case .root, .country:
                for node in children {
                    node.computeActiveChildrenRecursive()
                }
                fallthrough
            case .city:
                isActive = children.contains(where: { node -> Bool in
                    node.isActive
                })
            case .relay:
                break
            }
        }

        func flatRelayLocationList(includeHiddenChildren: Bool = false) -> [RelayLocation] {
            children.reduce(into: []) { array, node in
                Self.flatten(node: node, into: &array, includeHiddenChildren: includeHiddenChildren)
            }
        }

        private func sortChildren() {
            switch nodeType {
            case .root, .country:
                children.sort { a, b -> Bool in
                    a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
                }
            case .city:
                children.sort { a, b -> Bool in
                    a.location.stringRepresentation
                        .localizedStandardCompare(b.location.stringRepresentation) == .orderedAscending
                }
            case .relay:
                break
            }
        }

        private class func flatten(node: Node, into array: inout [RelayLocation], includeHiddenChildren: Bool) {
            array.append(node.location)
            if includeHiddenChildren || node.showsChildren {
                for child in node.children {
                    Self.flatten(node: child, into: &array, includeHiddenChildren: includeHiddenChildren)
                }
            }
        }
    }
}
