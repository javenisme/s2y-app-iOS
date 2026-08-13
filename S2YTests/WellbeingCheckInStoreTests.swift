//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT
//

@testable import S2Y
import XCTest

final class WellbeingCheckInStoreTests: XCTestCase {
    @MainActor
    func testRetriesAreIdempotentForTheSameSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("snapshots.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = WellbeingCheckInSnapshot(
            questionnaireIdentifier: "DailyHealth",
            overallWellbeing: "good"
        )
        let store = WellbeingCheckInStore(fileURL: fileURL)

        try store.save(snapshot)
        try store.save(snapshot)

        XCTAssertEqual(store.snapshots, [snapshot])
    }
}
