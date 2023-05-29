//
//  RedeemVoucherInteractor.swift
//  MullvadVPN
//
//  Created by Mojgan on 2023-05-24.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
import MullvadREST
import MullvadTypes

final class RedeemVoucherInteractor {
    let tunnelManager: TunnelManager

    init(tunnelManager: TunnelManager) {
        self.tunnelManager = tunnelManager
    }

    func redeem(
        code: String,
        completion: @escaping ((Result<REST.SubmitVoucherResponse, Error>) -> Void)
    ) -> Cancellable {
        tunnelManager
            .redeemVoucher(code, completion: completion)
    }
}
