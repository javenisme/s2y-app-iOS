//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import XCTest

final class ReleaseMetadataConfigurationTests: XCTestCase {
    func testDisplayNameUsesS2YBrand() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "S2Y")
    }

    func testSensitivePermissionCopyIsUserInitiatedAndContainsNoTemplatePlaceholders() throws {
        let keys = [
            "NSCameraUsageDescription",
            "NSLocationAlwaysAndWhenInUseUsageDescription",
            "NSLocationWhenInUseUsageDescription",
            "NSMicrophoneUsageDescription",
            "NSMotionUsageDescription",
            "NSSpeechRecognitionUsageDescription"
        ]

        for key in keys {
            let copy = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: key) as? String)
            XCTAssertTrue(copy.hasPrefix("S2Y "), key)
            XCTAssertTrue(copy.localizedCaseInsensitiveContains("only"), key)
            XCTAssertFalse(copy.localizedCaseInsensitiveContains("should never appear"), key)
            XCTAssertFalse(copy.localizedCaseInsensitiveContains("adjust this"), key)
        }
    }
}
