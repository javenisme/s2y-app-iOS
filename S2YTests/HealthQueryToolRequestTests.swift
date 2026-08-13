//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import XCTest
@testable import S2Y

final class HealthQueryToolRequestTests: XCTestCase {
    func testToolRequestRoundTripsAsStableJSONSchema() throws {
        let request = HealthQueryToolRequest(
            operation: .comparePeriods,
            metric: .sleepDurationHours,
            windowDays: 7
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(object["operation"] as? String, "compare_periods")
        XCTAssertEqual(object["metric"] as? String, "sleepDurationHours")
        XCTAssertEqual(object["windowDays"] as? Int, 7)
        XCTAssertEqual(try JSONDecoder().decode(HealthQueryToolRequest.self, from: data), request)
        XCTAssertEqual(request.metricKind, .sleepDurationHours)
    }

    func testToolOperationsRemainExplicitAndFinite() {
        XCTAssertEqual(HealthQueryToolRequest.Operation.allCases, [.trend, .comparePeriods])
    }
}
