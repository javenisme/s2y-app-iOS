//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

@testable import S2Y
import XCTest

final class CrossDeviceSyncPreferencesTests: XCTestCase {
    func testSyncCategoriesDefaultToDisabled() {
        let ledger = CrossDeviceSyncLedger()

        XCTAssertTrue(ledger.authorization().enabledCategories.isEmpty)
        for category in CrossDeviceSyncCategory.allCases {
            XCTAssertFalse(CrossDeviceSyncPolicy.permits(category, authorization: ledger.authorization()))
        }
    }

    func testCategoriesCanBeEnabledAndRevokedIndependently() {
        var ledger = CrossDeviceSyncLedger()
        ledger.set(.appPreferences, enabled: true, at: Date(timeIntervalSince1970: 10))
        ledger.set(.wellnessPlans, enabled: true, at: Date(timeIntervalSince1970: 20))
        ledger.set(.appPreferences, enabled: false, at: Date(timeIntervalSince1970: 30))

        XCTAssertFalse(ledger.authorization().enabledCategories.contains(.appPreferences))
        XCTAssertTrue(ledger.authorization().enabledCategories.contains(.wellnessPlans))
        XCTAssertFalse(ledger.authorization().enabledCategories.contains(.conversations))
    }

    func testOldPolicyReceiptsFailClosed() {
        let receipt = CrossDeviceSyncReceipt(
            id: UUID(),
            policyVersion: "expired-policy",
            category: .wellnessPlans,
            change: .enabled,
            recordedAt: .now
        )
        let ledger = CrossDeviceSyncLedger(receipts: [receipt])

        XCTAssertTrue(ledger.authorization().enabledCategories.isEmpty)
    }

    func testRepeatedSettingDoesNotCreateDuplicateReceipt() {
        var ledger = CrossDeviceSyncLedger()
        ledger.set(.appPreferences, enabled: true)
        ledger.set(.appPreferences, enabled: true)

        XCTAssertEqual(ledger.receipts.count, 1)
    }
}
