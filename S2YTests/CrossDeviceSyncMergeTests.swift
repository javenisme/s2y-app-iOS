//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

@testable import S2Y
import XCTest

final class CrossDeviceSyncMergeTests: XCTestCase {
    private struct Value: Codable, Equatable, Sendable {
        let text: String
    }

    func testNewestRecordWinsPerIdentifier() throws {
        let older = record("plan-a", "old", at: 10, device: "a")
        let newer = record("plan-a", "new", at: 20, device: "b")

        let merged = CrossDeviceSyncMerge.records(local: [older], remote: [newer])

        XCTAssertEqual(try XCTUnwrap(merged.first?.payload).text, "new")
    }

    func testEqualTimestampUsesStableDeviceIdentifier() throws {
        let first = record("plan-a", "first", at: 10, device: "device-a")
        let second = record("plan-a", "second", at: 10, device: "device-b")

        let forward = CrossDeviceSyncMerge.records(local: [first], remote: [second])
        let reverse = CrossDeviceSyncMerge.records(local: [second], remote: [first])

        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(try XCTUnwrap(forward.first?.payload).text, "second")
    }

    func testDeletionTombstonePreventsOlderRecordResurrection() {
        let value = record("plan-a", "active", at: 10, device: "a")
        let deletion = CrossDeviceSyncRecord<Value>(
            id: "plan-a",
            payload: nil,
            modifiedAt: Date(timeIntervalSince1970: 20),
            modifiedBy: "b"
        )

        let merged = CrossDeviceSyncMerge.records(local: [deletion], remote: [value])

        XCTAssertEqual(merged, [deletion])
        XCTAssertTrue(merged[0].isDeletion)
    }

    func testMergeIsIdempotentAndSorted() {
        let second = record("b", "second", at: 10, device: "a")
        let first = record("a", "first", at: 10, device: "a")
        let once = CrossDeviceSyncMerge.records(local: [second, first], remote: [])
        let twice = CrossDeviceSyncMerge.records(local: once, remote: once)

        XCTAssertEqual(once.map(\.id), ["a", "b"])
        XCTAssertEqual(once, twice)
    }

    private func record(
        _ id: String,
        _ text: String,
        at timestamp: TimeInterval,
        device: String
    ) -> CrossDeviceSyncRecord<Value> {
        CrossDeviceSyncRecord(
            id: id,
            payload: Value(text: text),
            modifiedAt: Date(timeIntervalSince1970: timestamp),
            modifiedBy: device
        )
    }
}
