//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation

struct HealthQueryToolRequest: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    enum Operation: String, Codable, CaseIterable, Sendable {
        case trend
        case comparePeriods = "compare_periods"
    }

    let version: Int
    let operation: Operation
    let metric: String
    let windowDays: Int

    init(
        version: Int = schemaVersion,
        operation: Operation,
        metric: HealthKitService.MetricKind,
        windowDays: Int
    ) {
        self.version = version
        self.operation = operation
        self.metric = metric.rawValue
        self.windowDays = windowDays
    }

    var metricKind: HealthKitService.MetricKind? {
        HealthKitService.MetricKind(rawValue: metric)
    }

    func validated() throws -> ValidatedHealthQueryToolRequest {
        guard version == Self.schemaVersion else {
            throw HealthQueryToolRequestError.unsupportedVersion(version)
        }
        guard let metricKind else {
            throw HealthQueryToolRequestError.unknownMetric(metric)
        }
        guard Self.allowedWindowDays.contains(windowDays) else {
            throw HealthQueryToolRequestError.windowOutOfRange(windowDays)
        }
        return ValidatedHealthQueryToolRequest(
            operation: operation,
            metric: metricKind,
            windowDays: windowDays
        )
    }

    private static let allowedWindowDays = 1...90
}

struct ValidatedHealthQueryToolRequest: Equatable, Sendable {
    let operation: HealthQueryToolRequest.Operation
    let metric: HealthKitService.MetricKind
    let windowDays: Int
}

enum HealthQueryToolRequestError: LocalizedError, Equatable, Sendable {
    case unsupportedVersion(Int)
    case unknownMetric(String)
    case windowOutOfRange(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "Unsupported health tool schema version: \(version)."
        case .unknownMetric:
            "That health metric is not supported."
        case .windowOutOfRange:
            "Choose a time window from 1 to 90 days."
        }
    }
}
