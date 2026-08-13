//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import XCTest
@testable import S2Y

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
}
