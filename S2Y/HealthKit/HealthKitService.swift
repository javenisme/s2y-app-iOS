//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import HealthKit

@MainActor
public final class HealthKitService {
    public static let shared = HealthKitService()

    private let healthStore = HKHealthStore()

    private init() {}

    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw NSError(domain: "HealthKit", code: 1) }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: - Daily metrics

    public struct DailyMetric: Sendable {
        public let date: Date
        public let value: Double
    }

    public enum MetricKind: Sendable {
        case steps
        case heartRateAverage
        case restingHeartRate
        case activeEnergy
        case bodyMass
        case sleepDurationHours
    }

    // Explicit aggregation control for generic quantity metrics
    public enum Aggregation: Sendable { case sum, average }

    public func fetchDailyMetrics(kind: MetricKind, start: Date, end: Date) async throws -> [DailyMetric] {
        if kind == .sleepDurationHours {
            return try await fetchDailySleepHours(start: start, end: end)
        }

        let quantityDescriptor = try descriptor(for: kind)

        let calendar = Calendar.current
        let anchorComponents = calendar.dateComponents([.day, .month, .year], from: start)
        guard let anchorDate = calendar.date(from: anchorComponents) else { return [] }

        var interval = DateComponents()
        interval.day = 1

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { cont in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityDescriptor.type,
                quantitySamplePredicate: predicate,
                options: quantityDescriptor.options,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, error in
                if let error { cont.resume(throwing: error) ; return }
                guard let results else { cont.resume(returning: []) ; return }
                var output: [DailyMetric] = []
                results.enumerateStatistics(from: start, to: end) { stat, _ in
                    let date = stat.startDate
                    let quantity: HKQuantity?
                    switch quantityDescriptor.options {
                    case .cumulativeSum:
                        quantity = stat.sumQuantity()
                    case .discreteAverage:
                        quantity = stat.averageQuantity()
                    default:
                        quantity = nil
                    }
                    let value = quantity?.doubleValue(for: quantityDescriptor.unit) ?? 0
                    output.append(.init(date: date, value: value))
                }
                cont.resume(returning: output)
            }
            self.healthStore.execute(query)
        }
    }

    // MARK: - Helpers

    private struct QuantityDescriptor {
        let type: HKQuantityType
        let unit: HKUnit
        let options: HKStatisticsOptions
    }

    private func descriptor(for kind: MetricKind) throws -> QuantityDescriptor {
        switch kind {
        case .steps:
            return .init(
                type: HKObjectType.quantityType(forIdentifier: .stepCount)!,
                unit: .count(),
                options: .cumulativeSum
            )
        case .heartRateAverage:
            return .init(
                type: HKObjectType.quantityType(forIdentifier: .heartRate)!,
                unit: HKUnit.count().unitDivided(by: .minute()),
                options: .discreteAverage
            )
        case .restingHeartRate:
            return .init(
                type: HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
                unit: HKUnit.count().unitDivided(by: .minute()),
                options: .discreteAverage
            )
        case .activeEnergy:
            return .init(
                type: HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
                unit: .kilocalorie(),
                options: .cumulativeSum
            )
        case .bodyMass:
            return .init(
                type: HKObjectType.quantityType(forIdentifier: .bodyMass)!,
                unit: .gramUnit(with: .kilo),
                options: .discreteAverage
            )
        case .sleepDurationHours:
            throw NSError(domain: "HealthKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "Sleep duration handled separately."])
        }
    }

    // MARK: - Aggregations

    public struct Trend: Sendable {
        public let windowDays: Int
        public let points: [DailyMetric]
        public let average: Double
        public let changeRate: Double // last vs first
    }

    public func trend(kind: MetricKind, days: Int, endingAt end: Date = Date()) async throws -> Trend {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -days + 1, to: calendar.startOfDay(for: end)) ?? end
        let series = try await fetchDailyMetrics(kind: kind, start: start, end: end)
        let values = series.map { $0.value }
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let change = (values.last ?? 0) - (values.first ?? 0)
        let base = max(1e-9, abs(values.first ?? 0))
        let changeRate = change / base
        return .init(windowDays: days, points: series, average: avg, changeRate: changeRate)
    }

    public struct Comparison: Sendable {
        public let currentWindowDays: Int
        public let previousWindowDays: Int
        public let currentAverage: Double
        public let previousAverage: Double
        public let delta: Double
        public let deltaRate: Double
    }

    public func compare(kind: MetricKind, windowDays: Int, endingAt end: Date = Date()) async throws -> Comparison {
        let calendar = Calendar.current
        let endOfDay = calendar.startOfDay(for: end)
        let startCurrent = calendar.date(byAdding: .day, value: -windowDays + 1, to: endOfDay) ?? endOfDay
        let endPrev = calendar.date(byAdding: .day, value: -windowDays, to: startCurrent) ?? startCurrent
        let startPrev = calendar.date(byAdding: .day, value: -windowDays + 1, to: endPrev) ?? endPrev

        async let current = fetchDailyMetrics(kind: kind, start: startCurrent, end: endOfDay)
        async let previous = fetchDailyMetrics(kind: kind, start: startPrev, end: endPrev)

        let (curSeries, prevSeries) = try await (current, previous)
        let curAvg = curSeries.map { $0.value }.average()
        let prevAvg = prevSeries.map { $0.value }.average()
        let delta = curAvg - prevAvg
        let base = max(1e-9, abs(prevAvg))
        let deltaRate = delta / base
        return .init(
            currentWindowDays: windowDays,
            previousWindowDays: windowDays,
            currentAverage: curAvg,
            previousAverage: prevAvg,
            delta: delta,
            deltaRate: deltaRate
        )
    }
    private func fetchDailySleepHours(start: Date, end: Date) async throws -> [DailyMetric] {
        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, error in
                if let error { cont.resume(throwing: error) ; return }
                let list = (results as? [HKCategorySample]) ?? []
                cont.resume(returning: list)
            }
            self.healthStore.execute(query)
        }

        let calendar = Calendar.current
        var dayBuckets: [Date: TimeInterval] = [:]
        var cur = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        while cur <= endDay {
            dayBuckets[cur] = 0
            guard let next = calendar.date(byAdding: .day, value: 1, to: cur) else { break }
            cur = next
        }

        for sample in samples {
            // Count only asleep segments
            let value = sample.value
            let isAsleep: Bool
            if #available(iOS 16.0, *) {
                isAsleep = value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                    || value == HKCategoryValueSleepAnalysis.asleepCore.rawValue
                    || value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                    || value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
            } else {
                isAsleep = value == HKCategoryValueSleepAnalysis.asleep.rawValue
            }
            guard isAsleep else { continue }

            var segStart = sample.startDate
            let segEnd = sample.endDate
            while segStart < segEnd {
                let dayStart = calendar.startOfDay(for: segStart)
                guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
                let intervalEnd = min(dayEnd, segEnd)
                let overlap = intervalEnd.timeIntervalSince(segStart)
                dayBuckets[dayStart, default: 0] += max(0, overlap)
                segStart = intervalEnd
            }
        }

        return dayBuckets.keys.sorted().map { day in
            .init(date: day, value: dayBuckets[day, default: 0] / 3600.0)
        }
    }
}

extension Array where Element == Double {
    func average() -> Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}


