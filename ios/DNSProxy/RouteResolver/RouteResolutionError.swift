//
//  RouteResolutionError.swift
//  DNSProxy
//
//  Created by pronebird on 18/11/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

enum RouteResolutionError: LocalizedError {
    /// Failure to open routing sockete.
    case openSocket(POSIXError)

    /// Failure to read from routing socket.
    case readError(POSIXError)

    /// Failure to write to routing socket.
    case writeError(POSIXError)

    /// Unsupported IP address was given. Only IPv4 and IPv6 addresses are supported.
    case unsupportedIPAddress

    /// Failure to parse destionation IP address.
    case parseDestinationIP(ParseIPAddressError)

    /// Failure to parse gateway IP address.
    case parseGatewayIP(ParseIPAddressError)

    /// Failure to parse netmask.
    case parseNetmask(ParseNetmaskError)

    /// Invalid message version.
    case invalidVersion

    /// Invalid message length.
    case invalidMessageLength

    /// Reply message contains error.
    case messageWithError(Int32)

    /// No addresses were found in reply message.
    case noAddresses

    var errorDescription: String? {
        switch self {
        case .openSocket:
            return "Failed to open routing socket."

        case .readError:
            return "Failed to read from routing socket."

        case .writeError:
            return "Failed to write into routing socket."

        case .unsupportedIPAddress:
            return "Unsupported IP address was passed for routing request."

        case .parseDestinationIP:
            return "Cannot parse destination IP."

        case .parseGatewayIP:
            return "Cannot parse gateway IP."

        case .parseNetmask:
            return "Cannot parse netmask."

        case .invalidVersion:
            return "Invalid message version."

        case .invalidMessageLength:
            return "Invalid message length."

        case let .messageWithError(code):
            return "Reply contains errno: \(code)."

        case .noAddresses:
            return "No addresses returned with reply."
        }
    }
}
