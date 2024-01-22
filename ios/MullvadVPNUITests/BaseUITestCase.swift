//
//  BaseTestCase.swift
//  MullvadVPNUITests
//
//  Created by Niklas Berglund on 2024-01-12.
//  Copyright © 2024 Mullvad VPN AB. All rights reserved.
//

import Foundation
import XCTest

class BaseUITestCase: XCTestCase {
    let app = XCUIApplication()

    // swiftlint:disable force_cast
    let displayName = Bundle(for: BaseUITestCase.self)
        .infoDictionary?["MullvadDisplayName"] as! String
    let noTimeAccountNumber = Bundle(for: BaseUITestCase.self)
        .infoDictionary?["MullvadNoTimeAccountNumber"] as! String
    let hasTimeAccountNumber = Bundle(for: BaseUITestCase.self)
        .infoDictionary?["MullvadHasTimeAccountNumber"] as! String
    let fiveWireGuardKeysAccountNumber = Bundle(for: BaseUITestCase.self)
        .infoDictionary?["MullvadFiveWireGuardKeysAccountNumber"] as! String
    let iOSDevicePinCode = Bundle(for: BaseUITestCase.self)
        .infoDictionary?["MullvadIOSDevicePinCode"] as! String
    let adServingDomain = Bundle(for: BaseUITestCase.self)
        .infoDictionary?["MullvadAdServingDomain"] as! String
    // swiftlint:enable force_cast

    /// Handle iOS add VPN configuration permission alert - allow and enter device PIN code
    func allowAddVPNConfigurations() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        let alertAllowButton = springboard.buttons.element(boundBy: 0)
        if alertAllowButton.waitForExistence(timeout: Self.defaultTimeout) {
            alertAllowButton.tap()
        }

        _ = springboard.buttons["1"].waitForExistence(timeout: Self.defaultTimeout)
        springboard.typeText(iOSDevicePinCode)
    }
    
    override func tearDown() {
        self.uninstallApp(app)
    }

    /// Check if currently logged on to an account. Note that it is assumed that we are logged in if login view isn't currently shown.
    func isLoggedIn() -> Bool {
        return !app
            .otherElements[AccessibilityIdentifier.loginView.rawValue]
            .waitForExistence(timeout: 1.0)
    }

    func uninstallApp(_ app: XCUIApplication) {
        let appName = "Mullvad VPN"
        
        app.terminate()

        let timeout = TimeInterval(5)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let spotlight = XCUIApplication(bundleIdentifier: "com.apple.Spotlight")

        springboard.swipeDown()
        spotlight.textFields["SpotlightSearchField"].typeText(appName)
        
        let appIcon = spotlight.icons[appName].firstMatch
        if appIcon.waitForExistence(timeout: timeout) {
            appIcon.press(forDuration: 2)
        } else {
            XCTFail("Failed to find app icon named \(appName)")
        }

        let deleteAppButton = spotlight.buttons["Delete App"]
        if deleteAppButton.waitForExistence(timeout: timeout) {
            deleteAppButton.tap()
        } else {
            XCTFail("Failed to find 'Delete App'")
        }

        let finalDeleteButton = springboard.alerts.buttons["Delete"]
        if finalDeleteButton.waitForExistence(timeout: timeout) {
            finalDeleteButton.tap()
        } else {
            XCTFail("Failed to find 'Delete'")
        }
    }
}
