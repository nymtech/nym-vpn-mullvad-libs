//
//  ObfuscationSettings.swift
//  MullvadTypes
//
//  Created by pronebird on 23/06/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation

public struct ObfuscationSettings: Codable, Equatable {
    /// Selected obfuscation type.
    public var selectedObfuscation: SelectedObfuscation

    /// Settings for UDP over TCP obfuscation.
    public var udpOverTcpSettings: UDPOverTCPSettings

    public init(
        selectedObfuscation: SelectedObfuscation = .off,
        udpOverTcpSettings: UDPOverTCPSettings = UDPOverTCPSettings()
    ) {
        self.selectedObfuscation = selectedObfuscation
        self.udpOverTcpSettings = udpOverTcpSettings
    }
}

public enum SelectedObfuscation: String, Codable, Equatable {
    /// Obfuscation is disabled.
    case off

    /// Obfuscation is managed automatically.
    case auto

    /// UDP over TCP.
    case udpOverTcp
}

/// Settings associated with `ObfuscationType.udpOverTcp`.
public struct UDPOverTCPSettings: Codable, Equatable {
    /// TCP port constraint used when selecting server port to connect to.
    public var port: RelayConstraint<UInt16>

    public init(port: RelayConstraint<UInt16> = .any) {
        self.port = port
    }
}
