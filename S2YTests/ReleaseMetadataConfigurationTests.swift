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
}
