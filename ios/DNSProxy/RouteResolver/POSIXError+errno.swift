//
//  POSIXError+errno.swift
//  DNSProxy
//
//  Created by pronebird on 18/11/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

extension POSIXError {
    static var errno: POSIXError {
        let code = POSIXErrorCode(rawValue: Darwin.errno)!

        return POSIXError(code)
    }
}
