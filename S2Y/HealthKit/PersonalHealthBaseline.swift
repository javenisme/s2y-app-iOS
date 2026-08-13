//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

public struct PersonalMetricBaseline: Sendable, Equatable {
    public enum Availability: String, Sendable, Equatable {
        case insufficientData
        case available
    }

    public let metricKind: HealthKitService.MetricKind
    public let availability: Availability
    public let observedDays: Int
    public let baselineMedian: Double?
    public let medianAbsoluteDeviation: Double?
}

public struct PersonalMetricDeviation: Sendable, Equatable {
    public enum Direction: String, Sendable, Equatable {
        case lower
        case typical
        case higher
        case undetermined
    }

    public let metricKind: HealthKitService.MetricKind
    public let currentMedian: Double?
    public let baselineMedian: Double?
    public let robustDistance: Double?
    public let direction: Direction
    public let baselineObservedDays: Int
    public let currentObservedDays: Int
}

public enum PersonalHealthBaselineAnalyzer {
    public static let minimumBaselineDays = 14
    public static let minimumCurrentDays = 3

    public static func baseline(
        for metricKind: HealthKitService.MetricKind,
        values: [Double]
    ) -> PersonalMetricBaseline {
        let finiteValues = values.filter(\.isFinite)
        guard finiteValues.count >= minimumBaselineDays,
              let median = finiteValues.median else {
            return PersonalMetricBaseline(
                metricKind: metricKind,
                availability: .insufficientData,
                observedDays: finiteValues.count,
                baselineMedian: nil,
                medianAbsoluteDeviation: nil
            )
        }
        let absoluteDeviations = finiteValues.map { abs($0 - median) }
        return PersonalMetricBaseline(
            metricKind: metricKind,
            availability: .available,
            observedDays: finiteValues.count,
            baselineMedian: median,
            medianAbsoluteDeviation: absoluteDeviations.median ?? 0
        )
    }

    public static func deviation(
        baselineValues: [Double],
        currentValues: [Double],
        metricKind: HealthKitService.MetricKind
    ) -> PersonalMetricDeviation {
        let baseline = baseline(for: metricKind, values: baselineValues)
        let finiteCurrent = currentValues.filter(\.isFinite)
        guard baseline.availability == .available,
              finiteCurrent.count >= minimumCurrentDays,
              let baselineMedian = baseline.baselineMedian,
              let currentMedian = finiteCurrent.median,
              let medianAbsoluteDeviation = baseline.medianAbsoluteDeviation else {
            return PersonalMetricDeviation(
                metricKind: metricKind,
                currentMedian: finiteCurrent.median,
                baselineMedian: baseline.baselineMedian,
                robustDistance: nil,
                direction: .undetermined,
                baselineObservedDays: baseline.observedDays,
                currentObservedDays: finiteCurrent.count
            )
        }

        // 1.4826 makes MAD comparable to standard deviation for normally distributed data.
        let robustScale = medianAbsoluteDeviation * 1.4826
        let minimumScale = max(abs(baselineMedian) * 0.05, 1e-9)
        let distance = (currentMedian - baselineMedian) / max(robustScale, minimumScale)
        let direction: PersonalMetricDeviation.Direction
        if distance > 2.5 {
            direction = .higher
        } else if distance < -2.5 {
            direction = .lower
        } else {
            direction = .typical
        }

        return PersonalMetricDeviation(
            metricKind: metricKind,
            currentMedian: currentMedian,
            baselineMedian: baselineMedian,
            robustDistance: distance,
            direction: direction,
            baselineObservedDays: baseline.observedDays,
            currentObservedDays: finiteCurrent.count
        )
    }
}

private extension Array where Element == Double {
    var median: Double? {
        guard !isEmpty else { return nil }
        let sortedValues = sorted()
        let middle = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middle - 1] + sortedValues[middle]) / 2
        }
        return sortedValues[middle]
    }
}
