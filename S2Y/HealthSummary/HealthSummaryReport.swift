//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation

struct HealthSummaryReport: Equatable, Sendable {
    let generatedAt: Date
    let startDate: Date
    let endDate: Date
    let metrics: [HealthSummaryMetric]

    var windowDays: Int {
        max(1, Calendar.current.dateComponents([.day], from: startDate, to: endDate).day.map { $0 + 1 } ?? 1)
    }
}

struct HealthSummaryMetric: Equatable, Identifiable, Sendable {
    let kind: HealthKitService.MetricKind
    let average: Double?
    let observedDays: Int
    let expectedDays: Int
    let sourceName: String?
    let updatedAt: Date?

    var id: HealthKitService.MetricKind { kind }

    var coverageRate: Double {
        guard expectedDays > 0 else { return 0 }
        return Double(observedDays) / Double(expectedDays)
    }

    var formattedAverage: String {
        guard let average, observedDays > 0 else { return "No observed data" }
        return kind.formatValue(average)
    }
}

@MainActor
enum HealthSummaryReportBuilder {
    static func build(
        metrics: Set<HealthKitService.MetricKind>,
        days: Int,
        endingAt endDate: Date = .now,
        healthService: HealthKitService = .shared
    ) async -> HealthSummaryReport {
        let boundedDays = min(max(days, 1), 90)
        let end = Calendar.current.startOfDay(for: endDate)
        let start = Calendar.current.date(byAdding: .day, value: -boundedDays + 1, to: end) ?? end

        var summaries: [HealthSummaryMetric] = []
        for kind in metrics.sorted(by: { $0.displayName < $1.displayName }) {
            let trend = try? await healthService.trend(kind: kind, days: boundedDays, endingAt: end)
            let provenance = try? await healthService.latestProvenance(for: kind)
            summaries.append(
                HealthSummaryMetric(
                    kind: kind,
                    average: trend.flatMap { $0.observedDays > 0 ? $0.average : nil },
                    observedDays: trend?.observedDays ?? 0,
                    expectedDays: trend?.expectedDays ?? boundedDays,
                    sourceName: provenance?.sourceName,
                    updatedAt: provenance?.updatedAt
                )
            )
        }

        return HealthSummaryReport(
            generatedAt: .now,
            startDate: start,
            endDate: end,
            metrics: summaries
        )
    }
}
