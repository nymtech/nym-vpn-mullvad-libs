//
//  RelayTests.swift
//  MullvadVPNUITests
//
//  Created by Niklas Berglund on 2024-01-11.
//  Copyright © 2024 Mullvad VPN AB. All rights reserved.
//

import Foundation
import XCTest

class RelayTests: LoggedInWithTimeUITestCase {
    func testAdBlockingViaDNS() throws {
        TunnelControlPage(app)
            .tapSelectLocationButton()

        SelectLocationPage(app)
            .tapLocationCellExpandButton(withName: "Sweden")
            .tapLocationCellExpandButton(withName: "Gothenburg")
            .tapLocationCell(withName: "se-got-wg-001")

        allowAddVPNConfigurations() // Allow adding VPN configurations iOS permission

        TunnelControlPage(app) // Make sure we're taken back to tunnel control page again

        NetworkTester.verifyCanReachAdServingDomain()

        HeaderBar(app)
            .tapSettingsButton()

        SettingsPage(app)
            .tapVPNSettingsCell()
            .tapDNSSettingsCell()
            .tapDNSContentBlockingHeaderExpandButton()
            .tapBlockAdsSwitch()

        NetworkTester.verifyCannotReachAdServingDomain()
    }
}
