//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

enum HealthCommunicationKind: String, Codable, Sendable, Equatable {
    case healthObservation
    case wellnessGuidance
    case urgentAction

    var title: String {
        switch self {
        case .healthObservation: "Health data observation"
        case .wellnessGuidance: "General wellness guidance"
        case .urgentAction: "Urgent safety guidance"
        }
    }

    var disclosure: String {
        switch self {
        case .healthObservation:
            "Describes available data and coverage; it is not a medical conclusion."
        case .wellnessGuidance:
            "For general wellbeing and health management, not diagnosis or treatment."
        case .urgentAction:
            "Local safety guidance only; contact emergency or crisis services now."
        }
    }
}

enum HealthInterpretationPolicy {
    static let wellnessBoundary = "Health trends are wellness information, not a diagnosis or treatment recommendation."

    static func trendContext(
        _ trend: HealthKitService.Trend,
        kind: HealthKitService.MetricKind
    ) -> String {
        let change = trend.changeRate * 100
        var parts = [
            "\(kind.displayName), \(trend.windowDays)-day average: \(kind.formatValue(trend.average)).",
            "First-to-last observed change: \(change.formatted(.number.precision(.fractionLength(1))))%.",
        ]
        if let distribution = trend.distribution {
            parts.append(
                "Observed median: \(kind.formatValue(distribution.median)); middle 50%: "
                    + "\(kind.formatValue(distribution.firstQuartile)) to "
                    + "\(kind.formatValue(distribution.thirdQuartile))."
            )
        }
        let movingWindowDays = min(7, trend.windowDays)
        if let latestMovingAverage = trend.movingAverage(windowDays: movingWindowDays).last,
           let value = latestMovingAverage.value {
            parts.append(
                "Latest \(movingWindowDays)-day moving average: \(kind.formatValue(value)) "
                    + "from \(latestMovingAverage.observedDays)/\(latestMovingAverage.windowDays) observed days."
            )
        }
        parts.append(
            coverageDescription(
                quality: trend.dataQuality,
                observedDays: trend.observedDays,
                expectedDays: trend.expectedDays
            )
        )
        parts.append(wellnessBoundary)
        return parts.joined(separator: " ")
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
