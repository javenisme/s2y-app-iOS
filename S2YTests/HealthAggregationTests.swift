//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

@testable import S2Y
import XCTest

final class HealthAggregationTests: XCTestCase {
    func testDistributionUsesObservedFiniteValuesOnly() {
        let points = [
            HealthKitService.DailyMetric(date: .now, value: 1, isObserved: true),
            HealthKitService.DailyMetric(date: .now, value: 2, isObserved: true),
            HealthKitService.DailyMetric(date: .now, value: 100, isObserved: true),
            HealthKitService.DailyMetric(date: .now, value: 0, isObserved: false),
            HealthKitService.DailyMetric(date: .now, value: .nan, isObserved: true)
        ]
        let trend = HealthKitService.Trend.summarize(windowDays: 5, points: points)
        let distribution = trend.distribution

        XCTAssertEqual(distribution?.observedCount, 3)
        XCTAssertEqual(distribution?.minimum, 1)
        XCTAssertEqual(distribution?.firstQuartile, 1.5)
        XCTAssertEqual(distribution?.median, 2)
        XCTAssertEqual(distribution?.thirdQuartile, 51)
        XCTAssertEqual(distribution?.maximum, 100)
    }

    func testDistributionIsUnavailableWithoutObservedValues() {
        let trend = HealthKitService.Trend.summarize(
            windowDays: 1,
            points: [.init(date: .now, value: 0, isObserved: false)]
        )

        XCTAssertNil(trend.distribution)
    }

    func testMovingAverageDoesNotImputeMissingDaysAsZero() {
        let start = Date(timeIntervalSince1970: 0)
        let trend = HealthKitService.Trend.summarize(
            windowDays: 3,
            points: [
                .init(date: start, value: 2, isObserved: true),
                .init(date: start.addingTimeInterval(86_400), value: 0, isObserved: false),
                .init(date: start.addingTimeInterval(172_800), value: 4, isObserved: true)
            ]
        )

        let movingAverage = trend.movingAverage(windowDays: 3)

        XCTAssertEqual(movingAverage.map(\.value), [2, 2, 3])
        XCTAssertEqual(movingAverage.map(\.observedDays), [1, 1, 2])
        XCTAssertEqual(movingAverage.map(\.windowDays), [1, 2, 3])
        XCTAssertEqual(movingAverage.last?.coverageRate, 2.0 / 3.0)
    }

    func testMovingAverageRepresentsEmptyWindowAsMissing() {
        let trend = HealthKitService.Trend.summarize(
            windowDays: 1,
            points: [.init(date: .now, value: 0, isObserved: false)]
        )

        XCTAssertNil(trend.movingAverage(windowDays: 7).first?.value)
    }

    func testComparisonWindowsAreAdjacentAndEqualLength() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let end = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-12T18:00:00Z"))

        let windows = HealthKitService.comparisonDateWindows(
            windowDays: 7,
            endingAt: end,
            calendar: calendar
        )

        XCTAssertEqual(windows.currentStart, try XCTUnwrap(date("2026-08-06T00:00:00Z")))
        XCTAssertEqual(windows.currentEnd, try XCTUnwrap(date("2026-08-12T00:00:00Z")))
        XCTAssertEqual(windows.previousStart, try XCTUnwrap(date("2026-07-30T00:00:00Z")))
        XCTAssertEqual(windows.previousEnd, try XCTUnwrap(date("2026-08-05T00:00:00Z")))
        XCTAssertEqual(
            calendar.date(byAdding: .day, value: 1, to: windows.previousEnd),
            windows.currentStart
        )
    }

    func testTrendContextIncludesRobustAndSmoothedStatistics() {
        let start = Date(timeIntervalSince1970: 0)
        let trend = HealthKitService.Trend.summarize(
            windowDays: 3,
            points: [
                .init(date: start, value: 6, isObserved: true),
                .init(date: start.addingTimeInterval(86_400), value: 7, isObserved: true),
                .init(date: start.addingTimeInterval(172_800), value: 8, isObserved: true)
            ]
        )

        let context = HealthInterpretationPolicy.trendContext(trend, kind: .sleepDurationHours)

        XCTAssertTrue(context.contains("Observed median: 7.0 hours"))
        XCTAssertTrue(context.contains("middle 50%: 6.5 hours to 7.5 hours"))
        XCTAssertTrue(context.contains("Latest 3-day moving average: 7.0 hours from 3/3 observed days"))
    }

    private func date(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}
