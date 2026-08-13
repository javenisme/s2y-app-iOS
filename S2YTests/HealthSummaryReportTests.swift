//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

@testable import S2Y
import XCTest

final class HealthSummaryReportTests: XCTestCase {
    func testMetricFormatsCoverageAndObservedAverage() {
        let metric = HealthSummaryMetric(
            kind: .steps,
            average: 7_654.4,
            observedDays: 5,
            expectedDays: 7,
            sourceName: "Apple Watch",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(metric.coverageRate, 5.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(metric.formattedAverage, "7654 steps")
        XCTAssertTrue(metric.formattedAverage.contains("steps"))
    }

    func testMetricDoesNotPresentMissingDaysAsZero() {
        let metric = HealthSummaryMetric(
            kind: .sleepDurationHours,
            average: nil,
            observedDays: 0,
            expectedDays: 30,
            sourceName: nil,
            updatedAt: nil
        )

        XCTAssertEqual(metric.formattedAverage, "No observed data")
        XCTAssertEqual(metric.coverageRate, 0)
    }

    func testReportUsesInclusiveWindow() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7)))
        let report = HealthSummaryReport(generatedAt: end, startDate: start, endDate: end, metrics: [])

        XCTAssertEqual(report.windowDays, 7)
    }
}
