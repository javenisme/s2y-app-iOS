//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import XCTest
import XCTestExtensions

final class HealthAssistantChatUITests: XCTestCase {
    @MainActor
    func testChatControlsAndDrawer() {
        let app = XCUIApplication()
        app.launchArguments = ["--setupTestAccount", "--skipOnboarding"]
        app.launch()

        app.openHomeDrawer()
        let initialNewChat = app.buttons["drawer.new-chat"]
        XCTAssertTrue(initialNewChat.waitForExistence(timeout: 5))
        initialNewChat.tap()

        let localTab = app.buttons["health-assistant-mode-local"]
        let omerTab = app.buttons["health-assistant-mode-omer"]
        XCTAssertTrue(localTab.waitForExistence(timeout: 10))
        XCTAssertTrue(omerTab.waitForExistence(timeout: 3))
        localTab.tap()
        XCTAssertEqual(localTab.value as? String, "Selected")
        omerTab.tap()
        XCTAssertEqual(omerTab.value as? String, "Selected")
        XCTAssertFalse(app.buttons["health-assistant-ai-mode"].exists)
        XCTAssertTrue(app.buttons["health-assistant-settings"].exists)
        XCTAssertTrue(app.buttons["health-assistant-actions"].exists)
        XCTAssertTrue(app.buttons["health-assistant-dictation"].exists)
        XCTAssertTrue(app.buttons["health-assistant-voice"].exists)

        let input = app.textFields["health-assistant-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("How has my sleep quality been recently?")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.toolbars.buttons["Done"].waitForExistence(timeout: 3))
        app.toolbars.buttons["Done"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))

        app.openHomeDrawer()
        let newChat = app.buttons["drawer.new-chat"]
        let account = app.buttons["drawer.account"]
        XCTAssertTrue(newChat.waitForExistence(timeout: 5))
        XCTAssertTrue(account.waitForExistence(timeout: 3))
        XCTAssertTrue(newChat.isHittable)
        XCTAssertTrue(account.isHittable)
        XCTAssertLessThan(newChat.frame.minY, account.frame.minY)
        let expectedChatSectionLabels = ["Recent chats", "Today", "Yesterday", "Previous 7 days", "Earlier"]
        XCTAssertTrue(expectedChatSectionLabels.contains { app.staticTexts[$0].exists })
        XCTAssertEqual(app.buttons.matching(identifier: "drawer.account").count, 1)
    }

    @MainActor
    func testOmerOnlineRespondsInSimulator() {
        let app = XCUIApplication()
        app.launchArguments = ["--setupTestAccount", "--skipOnboarding"]
        app.launch()

        app.openHomeDrawer()
        let newChat = app.buttons["drawer.new-chat"]
        XCTAssertTrue(newChat.waitForExistence(timeout: 5))
        newChat.tap()

        let omerTab = app.buttons["health-assistant-mode-omer"]
        XCTAssertTrue(omerTab.waitForExistence(timeout: 10))
        omerTab.tap()

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
