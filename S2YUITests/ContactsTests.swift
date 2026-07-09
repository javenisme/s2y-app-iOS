//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


final class ContactsTests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
        
        let app = XCUIApplication()
        app.launchArguments = ["--skipOnboarding"]
        app.deleteAndLaunch(withSpringboardAppName: "Spezi")
    }
    
    
    @MainActor
    func testContacts() {
        let app = XCUIApplication()
        
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2.0))
        
        // Waiting until the setup test accounts actions have been finished & sheets are dismissed.
        sleep(for: .seconds(5))
        
        app.buttons["Open Navigation Drawer"].tap()
        
        XCTAssertTrue(app.buttons["Open account"].waitForExistence(timeout: 2))
        app.buttons["Open account"].tap()
        
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Welcome"].exists)
        XCTAssertTrue(app.staticTexts["Not signed in"].exists)
        XCTAssertTrue(app.buttons["About"].exists)
        XCTAssertTrue(app.buttons["Open-Source Licenses"].exists)
    }
}
