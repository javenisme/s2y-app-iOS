//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

@testable import S2Y
import XCTest

final class AssistantPerformanceMetricsTests: XCTestCase {
    func testTimerRecordsFirstResponseAndTotalDuration() {
        var timer = AssistantRequestTimer(startedAt: 100)
        timer.markFirstResponse(at: 100.125)

        let event = timer.event(
            provider: .appleOnDevice,
            outcome: .completed,
            usedHealthContext: true,
            endedAt: 100.8
        )

        XCTAssertEqual(event.firstResponseMilliseconds, 125)
        XCTAssertEqual(event.totalMilliseconds, 800)
        XCTAssertEqual(event.provider, .appleOnDevice)
        XCTAssertTrue(event.usedHealthContext)
    }

    func testTimerOnlyRecordsFirstResponseOnce() {
        var timer = AssistantRequestTimer(startedAt: 20)
        timer.markFirstResponse(at: 20.4)
        timer.markFirstResponse(at: 20.9)

        XCTAssertEqual(timer.firstResponseMilliseconds, 400)
    }

    func testEventContainsNoMessageOrIdentityFields() throws {
        let event = AssistantPerformanceEvent(
            provider: .omerOnline,
            outcome: .failed,
            firstResponseMilliseconds: nil,
            totalMilliseconds: 250,
            usedHealthContext: false
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any]
        )
        XCTAssertEqual(
            Set(object.keys),
            Set(["provider", "outcome", "totalMilliseconds", "usedHealthContext"])
        )
    }

    @MainActor
    func testMeasurementCanBeUpdatedFromMainActorStreamingCallback() {
        let measurement = AssistantRequestMeasurement(startedAt: 10)
        measurement.markFirstResponse(at: 10.2)

        let event = measurement.event(
            provider: .appleOnDevice,
            outcome: .cancelled,
            usedHealthContext: false,
            endedAt: 10.5
        )

        XCTAssertEqual(event.firstResponseMilliseconds, 200)
        XCTAssertEqual(event.totalMilliseconds, 500)
        XCTAssertEqual(event.outcome, .cancelled)
    }

    func testSummarySeparatesProvidersAndUsesNearestRankP95() {
        let appleEvents = (1...20).map { sample in
            AssistantPerformanceEvent(
                provider: .appleOnDevice,
                outcome: .completed,
                firstResponseMilliseconds: sample * 10,
                totalMilliseconds: sample * 100,
                usedHealthContext: true
            )
        }
        let ignoredFailure = AssistantPerformanceEvent(
            provider: .appleOnDevice,
            outcome: .failed,
            firstResponseMilliseconds: 99_999,
            totalMilliseconds: 99_999,
            usedHealthContext: false
        )

        let summary = AssistantPerformanceSummary.make(
            provider: .appleOnDevice,
            events: appleEvents + [ignoredFailure]
        )

        XCTAssertEqual(summary.completedSamples, 20)
        XCTAssertEqual(summary.firstResponseP95Milliseconds, 190)
        XCTAssertEqual(summary.totalP95Milliseconds, 1_900)
    }
}
