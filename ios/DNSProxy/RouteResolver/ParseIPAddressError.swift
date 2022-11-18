//
//  ParseIPAddressError.swift
//  DNSProxy
//
//  Created by pronebird on 18/11/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

struct ParseIPAddressError: LocalizedError {
    private var _socketaddr = sockaddr_storage()

    var errorDescription: String? {
        return "Failed to parse IP address."
    }

    var socketaddr: sockaddr_storage {
        return _socketaddr
    }

    init(sa: sockaddr_in) {
        self.init(buffer: withUnsafeBytes(of: sa) { Array($0) })
    }

    init(sa6: sockaddr_in6) {
        self.init(buffer: withUnsafeBytes(of: sa6) { Array($0) })
    }

    init(sa: sockaddr) {
        self.init(buffer: withUnsafeBytes(of: sa) { Array($0) })
    }

    private init(buffer: [UInt8]) {
        assert(buffer.count <= MemoryLayout<sockaddr_storage>.size)

        withUnsafeMutableBytes(of: &_socketaddr) { storageBuffer in
            _ = buffer.copyBytes(to: storageBuffer)
        }
    }
}
