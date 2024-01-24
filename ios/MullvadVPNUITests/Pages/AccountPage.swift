//
//  AccountPage.swift
//  MullvadVPNUITests
//
//  Created by Niklas Berglund on 2024-01-23.
//  Copyright © 2024 Mullvad VPN AB. All rights reserved.
//

import Foundation
import XCTest

class AccountPage: Page {
    @discardableResult override init(_ app: XCUIApplication) {
        super.init(app)

        self.pageAccessibilityIdentifier = .accountView
        waitForPageToBeShown()
    }

    func tapRedeemVoucherButton() {
        app.buttons[AccessibilityIdentifier.redeemVoucherButton.rawValue].tap()
    }

    func tapAdd30DaysTimeButton() {
        app.buttons[AccessibilityIdentifier.purchaseButton.rawValue].tap()
    }

    func tapRestorePurchasesButton() {
        app.buttons[AccessibilityIdentifier.restorePurchasesButton.rawValue].tap()
    }

    func tapLogOutButton() {
        app.buttons[AccessibilityIdentifier.logoutButton.rawValue].tap()
    }

    func tapDeleteAccountButton() {
        app.buttons[AccessibilityIdentifier.deleteButton.rawValue].tap()
    }
}
