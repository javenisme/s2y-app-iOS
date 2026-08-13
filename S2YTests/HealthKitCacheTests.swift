//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import XCTest
@testable import S2Y

final class HealthKitCacheTests: XCTestCase {
    @MainActor
    func testCacheReportsHitsMissesAndInvalidationWithoutHealthValues() {
        let cache = HealthKitCache()
        let key = "daily_steps_test"

        XCTAssertNil(cache.get(key: key, type: [Int].self))
        cache.set([1, 2], forKey: key)
        XCTAssertEqual(cache.get(key: key, type: [Int].self), [1, 2])
        cache.clearMetric(.steps)

        XCTAssertEqual(
            cache.statistics,
            HealthKitCacheStatistics(hits: 1, misses: 1, expiredEntries: 0, invalidatedEntries: 1)
        )
    }

    @MainActor
    func testTrendAndComparisonKeysUseStableDayBoundary() {
        let cache = HealthKitCache()
        let morning = Date(timeIntervalSince1970: 1_800_000_000)
        let evening = morning.addingTimeInterval(60 * 60 * 8)

        XCTAssertEqual(
            cache.trendCacheKey(kind: .steps, days: 7, endDate: morning),
            cache.trendCacheKey(kind: .steps, days: 7, endDate: evening)
        )
        XCTAssertEqual(
            cache.comparisonCacheKey(kind: .steps, windowDays: 7, endDate: morning),
            cache.comparisonCacheKey(kind: .steps, windowDays: 7, endDate: evening)
        )
    }
}
