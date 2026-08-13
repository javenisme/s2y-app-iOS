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
}
