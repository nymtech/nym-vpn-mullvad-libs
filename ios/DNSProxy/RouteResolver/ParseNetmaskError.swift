//
//  ParseNetmaskError.swift
//  DNSProxy
//
//  Created by pronebird on 18/11/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

struct ParseNetmaskError: LocalizedError {
    private var _socketaddr = sockaddr_storage()

    var errorDescription: String? {
        return "Failed to parse netmask."
    }

    let family: sa_family_t
    var socketaddr: sockaddr_storage {
        return _socketaddr
    }

    init(sa: sockaddr_in, family: sa_family_t) {
        self.init(buffer: withUnsafeBytes(of: sa) { Array($0) }, family: family)
    }

    init(sa6: sockaddr_in6, family: sa_family_t) {
        self.init(buffer: withUnsafeBytes(of: sa6) { Array($0) }, family: family)
    }

    init(sa: sockaddr, family: sa_family_t) {
        self.init(buffer: withUnsafeBytes(of: sa) { Array($0) }, family: family)
    }

    private init(buffer: [UInt8], family: sa_family_t) {
        assert(buffer.count <= MemoryLayout<sockaddr_storage>.size)

        self.family = family

        withUnsafeMutableBytes(of: &_socketaddr) { storageBuffer in
            _ = buffer.copyBytes(to: storageBuffer)
        }
    }
}
