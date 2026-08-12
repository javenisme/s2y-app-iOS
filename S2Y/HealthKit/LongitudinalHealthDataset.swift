//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

public struct LongitudinalMetricCoverage: Sendable, Equatable {
    public let metricKind: HealthKitService.MetricKind
    public let observedDays: Int
    public let expectedDays: Int
    public let dataQuality: HealthKitService.DataQuality

    public var rate: Double {
        guard expectedDays > 0 else { return 0 }
        return Double(observedDays) / Double(expectedDays)
    }
}

public struct AlignedHealthDay: Identifiable, Sendable, Equatable {
    public let date: Date
    public let values: [HealthKitService.MetricKind: Double]

    public var id: Date { date }
}

public struct LongitudinalHealthDataset: Sendable, Equatable {
    public let expectedDays: Int
    public let days: [AlignedHealthDay]
    public let coverage: [LongitudinalMetricCoverage]

    public func values(
        for metricKind: HealthKitService.MetricKind
    ) -> [(date: Date, value: Double)] {
        days.compactMap { day in
            guard let value = day.values[metricKind] else { return nil }
            return (day.date, value)
        }
    }

    public func pairedValues(
        _ first: HealthKitService.MetricKind,
        _ second: HealthKitService.MetricKind
    ) -> [(date: Date, first: Double, second: Double)] {
        days.compactMap { day in
            guard let firstValue = day.values[first],
                  let secondValue = day.values[second] else {
                return nil
            }
            return (day.date, firstValue, secondValue)
        }
    }
}

public enum LongitudinalHealthAligner {
    /// Aligns only observed daily values. Missing days remain absent and are never imputed as zero.
    public static func align(
        series: [HealthKitService.MetricKind: [HealthKitService.DailyMetric]],
        expectedDays: Int,
        calendar: Calendar = .current
    ) -> LongitudinalHealthDataset {
        var buckets: [Date: [HealthKitService.MetricKind: [Double]]] = [:]

        for (kind, points) in series {
            for point in points where point.isObserved && point.value.isFinite {
                let day = calendar.startOfDay(for: point.date)
                buckets[day, default: [:]][kind, default: []].append(point.value)
            }
        }

        let days = buckets.keys.sorted().map { date in
            let values = buckets[date, default: [:]].mapValues { samples in
                samples.reduce(0, +) / Double(samples.count)
            }
            return AlignedHealthDay(date: date, values: values)
        }

        let normalizedExpectedDays = max(0, expectedDays)
        let coverage = series.keys.sorted { $0.rawValue < $1.rawValue }.map { kind in
            let observedDays = days.reduce(into: 0) { count, day in
                if day.values[kind] != nil {
                    count += 1
                }
            }
            return LongitudinalMetricCoverage(
                metricKind: kind,
                observedDays: observedDays,
                expectedDays: normalizedExpectedDays,
                dataQuality: .classify(
                    observedDays: observedDays,
                    expectedDays: normalizedExpectedDays
                )
            )
        }

        return LongitudinalHealthDataset(
            expectedDays: normalizedExpectedDays,
            days: days,
            coverage: coverage
        )
    }
}
