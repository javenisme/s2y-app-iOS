//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

struct PersonalHealthInsightReport: Sendable {
    let windowDays: Int
    let generatedAt: Date
    let coverage: [LongitudinalMetricCoverage]
    let deviations: [PersonalMetricDeviation]
    let relationships: [DescriptiveHealthRelationship]

    var hasUsableInsight: Bool {
        deviations.contains { $0.direction != .undetermined }
            || relationships.contains { $0.availability == .available }
    }
}

enum PersonalHealthInsightBuilder {
    static func build(
        dataset: LongitudinalHealthDataset,
        generatedAt: Date = .now
    ) -> PersonalHealthInsightReport {
        let metricKinds = dataset.coverage.map(\.metricKind)
        let deviations = metricKinds.map { metricKind in
            let values = dataset.values(for: metricKind).map(\.value)
            let currentCount = min(7, values.count)
            let current = Array(values.suffix(currentCount))
            let baseline = Array(values.dropLast(currentCount))
            return PersonalHealthBaselineAnalyzer.deviation(
                baselineValues: baseline,
                currentValues: current,
                metricKind: metricKind
            )
        }

        let relationshipPairs: [(HealthKitService.MetricKind, HealthKitService.MetricKind)] = [
            (.steps, .sleepDurationHours),
            (.steps, .restingHeartRate),
            (.sleepDurationHours, .restingHeartRate),
            (.steps, .activeEnergy)
        ]
        let availableKinds = Set(metricKinds)
        var relationships: [DescriptiveHealthRelationship] = []
        for (first, second) in relationshipPairs
            where availableKinds.contains(first) && availableKinds.contains(second) {
            relationships.append(DescriptiveHealthRelationshipAnalyzer.analyze(
                dataset: dataset,
                first: first,
                second: second
            ))
        }

        return PersonalHealthInsightReport(
            windowDays: dataset.expectedDays,
            generatedAt: generatedAt,
            coverage: dataset.coverage,
            deviations: deviations,
            relationships: relationships
        )
    }
}

enum PersonalHealthInsightLoader {
    private static let supportedMetrics: [HealthKitService.MetricKind] = [
        .steps,
        .sleepDurationHours,
        .restingHeartRate,
        .activeEnergy
    ]

    static func matches(_ query: String) -> Bool {
        let lowered = query.lowercased()
        return ["insight", "pattern", "correlation", "relationship", "洞察", "模式", "关联"]
            .contains { lowered.contains($0) }
    }

    @MainActor
    static func load(for query: String, endingAt end: Date = .now) async -> PersonalHealthInsightReport? {
        guard matches(query) else { return nil }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: end)) ?? end
        var series: [HealthKitService.MetricKind: [HealthKitService.DailyMetric]] = [:]
        for metricKind in supportedMetrics {
            if let points = try? await HealthKitService.shared.fetchDailyMetrics(
                kind: metricKind,
                start: start,
                end: end
            ), points.contains(where: \.isObserved) {
                series[metricKind] = points
            }
        }
        guard !series.isEmpty else { return nil }
        let dataset = LongitudinalHealthAligner.align(
            series: series,
            expectedDays: 30,
            calendar: calendar
        )
        return PersonalHealthInsightBuilder.build(dataset: dataset)
    }
}
