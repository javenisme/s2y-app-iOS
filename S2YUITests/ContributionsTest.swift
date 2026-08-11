//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


final class ContributionsTest: XCTestCase {
    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
        
        let app = XCUIApplication()
        app.launchArguments = ["--setupTestAccount", "--skipOnboarding"]
        app.launch()
    }
    
    @MainActor
    func testLicenseInformationPage() {
        let app = XCUIApplication()
        
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2.0))
        
        // Waiting until the setup test accounts actions have been finished & sheets are dismissed.
        sleep(for: .seconds(5))
        
        app.openHomeDrawer()
        XCTAssertTrue(app.buttons["drawer.account"].waitForExistence(timeout: 6.0))
        app.buttons["drawer.account"].tap()
        
        XCTAssertTrue(app.buttons["profile.licenses"].waitForExistence(timeout: 4))
        app.buttons["profile.licenses"].tap()
        XCTAssertTrue(app.navigationBars["Open-Source Licenses"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Spezi")).firstMatch.waitForExistence(timeout: 4))
    }
}


final class HealthAssistantChatUITests: XCTestCase {
    @MainActor
    func testOmerFallbackRespondsInSimulator() {
        let app = XCUIApplication()
        app.launchArguments = ["--setupTestAccount", "--skipOnboarding"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Omer fallback"].waitForExistence(timeout: 10))

        let input = app.textFields["health-assistant-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Reply briefly: simulator chat connectivity check.")

        let sendButton = app.buttons["health-assistant-send"]
        XCTAssertTrue(sendButton.isEnabled)
        sendButton.tap()

        let response = app.staticTexts
            .matching(identifier: "health-assistant-response")
            .matching(NSPredicate(format: "label != ''"))
            .firstMatch
        XCTAssertTrue(response.waitForExistence(timeout: 60))
        XCTAssertFalse(
            response.label.contains("neither on-device AI nor Omer"),
            "Unexpected fallback failure: \(response.label)"
        )
        XCTAssertFalse(
            response.label.contains("Omer backend returned an error"),
            "Unexpected Omer failure: \(response.label)"
        )
    }
}
