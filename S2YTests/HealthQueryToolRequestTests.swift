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

    func testValidationResolvesKnownMetric() throws {
        let request = HealthQueryToolRequest(
            operation: .trend,
            metric: .heartRateAverage,
            windowDays: 30
        )

        XCTAssertEqual(
            try request.validated(),
            ValidatedHealthQueryToolRequest(
                operation: .trend,
                metric: .heartRateAverage,
                windowDays: 30
            )
        )
    }

    func testValidationRejectsUnknownMetricFromDecodedPayload() throws {
        let data = try XCTUnwrap(
            #"{"version":1,"operation":"trend","metric":"readinessScore","windowDays":7}"#
                .data(using: .utf8)
        )
        let request = try JSONDecoder().decode(HealthQueryToolRequest.self, from: data)

        XCTAssertThrowsError(try request.validated()) { error in
            XCTAssertEqual(error as? HealthQueryToolRequestError, .unknownMetric("readinessScore"))
        }
    }

    func testValidationRejectsUnsupportedVersionAndUnsafeWindows() throws {
        let futureVersion = HealthQueryToolRequest(
            version: 2,
            operation: .trend,
            metric: .steps,
            windowDays: 7
        )
        let oversized = HealthQueryToolRequest(
            operation: .trend,
            metric: .steps,
            windowDays: 365
        )

        XCTAssertThrowsError(try futureVersion.validated()) { error in
            XCTAssertEqual(error as? HealthQueryToolRequestError, .unsupportedVersion(2))
        }
        XCTAssertThrowsError(try oversized.validated()) { error in
            XCTAssertEqual(error as? HealthQueryToolRequestError, .windowOutOfRange(365))
        }
    }
}
