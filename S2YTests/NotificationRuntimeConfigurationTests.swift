//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import XCTest

final class NotificationRuntimeConfigurationTests: XCTestCase {
    func testBackgroundNotificationModesMatchRuntimeCallbacks() throws {
        let backgroundModes = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])

        XCTAssertTrue(backgroundModes.contains("fetch"))
        XCTAssertTrue(backgroundModes.contains("remote-notification"))
    }

    func testSpeziSchedulerBackgroundTaskIsPermitted() throws {
        let identifiers = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        )

        XCTAssertTrue(identifiers.contains("edu.stanford.spezi.scheduler.notifications-scheduling"))
    }
}
