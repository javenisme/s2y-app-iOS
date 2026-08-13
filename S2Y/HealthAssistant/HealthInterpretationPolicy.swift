//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

enum HealthInterpretationPolicy {
    static let wellnessBoundary = "Health trends are wellness information, not a diagnosis or treatment recommendation."

    static func trendContext(
        _ trend: HealthKitService.Trend,
        kind: HealthKitService.MetricKind
    ) -> String {
        let change = trend.changeRate * 100
        return [
            "\(kind.displayName), \(trend.windowDays)-day average: \(kind.formatValue(trend.average)).",
            "First-to-last observed change: \(change.formatted(.number.precision(.fractionLength(1))))%.",
            coverageDescription(
                quality: trend.dataQuality,
                observedDays: trend.observedDays,
                expectedDays: trend.expectedDays
            ),
            wellnessBoundary
        ].joined(separator: " ")
    }

    static func comparisonContext(
        _ comparison: HealthKitService.Comparison,
        kind: HealthKitService.MetricKind
    ) -> String {
        let change = comparison.deltaRate * 100
        return [
            "\(kind.displayName), current \(comparison.currentWindowDays)-day average: \(kind.formatValue(comparison.currentAverage)); previous average: \(kind.formatValue(comparison.previousAverage)).",
            "Descriptive change: \(change.formatted(.number.precision(.fractionLength(1))))%.",
            "Coverage: current \(comparison.currentObservedDays)/\(comparison.currentWindowDays) days; previous \(comparison.previousObservedDays)/\(comparison.previousWindowDays) days.",
            qualityCaution(comparison.dataQuality),
            wellnessBoundary
        ].joined(separator: " ")
    }

    static func coverageDescription(
        quality: HealthKitService.DataQuality,
        observedDays: Int,
        expectedDays: Int
    ) -> String {
        "Coverage: \(observedDays)/\(expectedDays) days. \(qualityCaution(quality))"
    }

    private static func qualityCaution(_ quality: HealthKitService.DataQuality) -> String {
        switch quality {
        case .unavailable:
            "There is not enough readable data to describe a trend."
        case .limited:
            "Coverage is limited, so avoid drawing a conclusion from this period."
        case .sufficient:
            "Coverage is sufficient for a descriptive trend, but gaps remain."
        case .complete:
            "Coverage is complete for this period."
        }
    }
}
