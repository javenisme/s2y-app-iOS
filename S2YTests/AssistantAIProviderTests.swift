//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import XCTest
@testable import S2Y

final class AssistantAIProviderTests: XCTestCase {
    func testOnlyRealUserSelectableProvidersAreExposed() {
        XCTAssertEqual(AssistantAIMode.allCases, [.onDevice, .omer])
    }

    func testOnDeviceProviderNeverClaimsNetworkUse() {
        XCTAssertFalse(AssistantAIMode.onDevice.usesNetwork)
        XCTAssertEqual(AssistantAIMode.onDevice.dataBoundaryDescription, "Runs on this iPhone")
    }

    func testOmerProviderDeclaresItsNetworkBoundary() {
        XCTAssertTrue(AssistantAIMode.omer.usesNetwork)
        XCTAssertEqual(AssistantAIMode.omer.dataBoundaryDescription, "Uses Omer online")
    }
}
