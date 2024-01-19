//
//  Page.swift
//  MullvadVPNUITests
//
//  Created by Niklas Berglund on 2024-01-10.
//  Copyright © 2024 Mullvad VPN AB. All rights reserved.
//

import Foundation
import XCTest

class Page {
    let app: XCUIApplication
    var pageAccessibilityIdentifier: AccessibilityIdentifier?

    @discardableResult init(_ app: XCUIApplication) {
        self.app = app
    }

    func waitForPageToBeShown() {
        if let pageAccessibilityIdentifier = self.pageAccessibilityIdentifier {
            XCTAssert(
                self.app.otherElements[pageAccessibilityIdentifier]
                    .waitForExistence(timeout: BaseUITestCase.defaultTimeout)
            )
        }
    }

    @discardableResult func enterText(_ text: String) -> Self {
        app.typeText(text)
        return self
    }

    @discardableResult func tapKeyboardDoneButton() -> Self {
        app.toolbars.buttons["Done"].tap()
        return self
    }
}
