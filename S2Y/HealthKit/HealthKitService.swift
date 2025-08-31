//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT

// swiftlint:disable function_body_length type_body_length conditional_returns_on_newline deployment_target force_unwrapping missing_docs trailing_newline type_contents_order
//

import Foundation
import HealthKit
import OSLog

public enum HealthKitError: Error, LocalizedError {
    case notAvailable
    case authorizationFailed
    case noData
    case queryFailed(any Error)
    
    public var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Health data is not available on this device"
        case .authorizationFailed:
            return "Health data authorization failed"
        case .noData:
            return "No relevant health data found"
        case .queryFailed(let error):
            return "Data query failed: \(error.localizedDescription)"
        }
    }
}

@MainActor
public final class HealthKitService {
    public static let shared = HealthKitService()

    private let healthStore = HKHealthStore()
    private let logger = Logger(subsystem: "com.s2y.app", category: "HealthKit")

    private init() {}

    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { 
            logger.error("HealthKit not available on this device")
            throw HealthKitError.notAvailable
        }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            logger.info("HealthKit authorization successful")
        } catch {
            logger.error("HealthKit authorization failed: \(error.localizedDescription)")
            throw HealthKitError.authorizationFailed
        }
    }

    // MARK: - Daily metrics

    public struct DailyMetric: Sendable, Codable {
        public let date: Date
        public let value: Double
    }

    public enum MetricKind: Sendable, Codable, CaseIterable {
        case steps
        case heartRateAverage
        case restingHeartRate
        case activeEnergy
        case bodyMass
        case sleepDurationHours
        
        /// Get localized display name for this metric
        public var displayName: String {
            HealthMetricsDictionary.displayName(for: self)
        }
        
        /// Get localized unit for this metric
        public var unit: String {
            HealthMetricsDictionary.unit(for: self)
        }
        
        /// Get category for this metric
        public var category: HealthMetricsDictionary.MetricCategory {
            HealthMetricsDictionary.info(for: self)?.category ?? .activity
        }
        
        /// Format a value with appropriate unit
        public func formatValue(_ value: Double) -> String {
            HealthMetricsDictionary.formatValue(value, for: self)
        }
        
        /// Get health assessment for a value
        public func healthAssessment(for value: Double) -> String {
            HealthMetricsDictionary.healthAssessment(value: value, for: self)
        }
    }

    // Explicit aggregation control for generic quantity metrics
    public enum Aggregation: Sendable { case sum, average }

    public func fetchDailyMetrics(kind: MetricKind, start: Date, end: Date, useCache: Bool = true) async throws -> [DailyMetric] {
        let cache = HealthKitCache.shared
        let cacheKey = cache.cacheKey(kind: kind, start: start, end: end)
        
        // Check cache first
        if useCache, let cached = cache.get(key: cacheKey, type: [DailyMetric].self) {
            logger.debug("Using cached data for \(String(describing: kind)) from \(start) to \(end)")
            return cached
        }
        do {
            let result: [DailyMetric]
            
            if kind == .sleepDurationHours {
                result = try await fetchDailySleepHours(start: start, end: end)
            } else {
                let quantityDescriptor = try descriptor(for: kind)

                let calendar = Calendar.current
                let anchorComponents = calendar.dateComponents([.day, .month, .year], from: start)
                guard let anchorDate = calendar.date(from: anchorComponents) else { 
                    throw HealthKitError.noData
                }

                var interval = DateComponents()
                interval.day = 1

                let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

                result = try await withCheckedThrowingContinuation { cont in
                    let query = HKStatisticsCollectionQuery(
                        quantityType: quantityDescriptor.type,
                        quantitySamplePredicate: predicate,
                        options: quantityDescriptor.options,
                        anchorDate: anchorDate,
                        intervalComponents: interval
                    )
                    query.initialResultsHandler = { _, results, error in
                        if let error { 
                            self.logger.error("HealthKit query failed: \(error.localizedDescription)")
                            cont.resume(throwing: HealthKitError.queryFailed(error))
                            return
                        }
                        guard let results else { 
                            cont.resume(throwing: HealthKitError.noData)
                            return
                        }
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
            
            // Cache the result
            if useCache {
                cache.set(result, forKey: cacheKey)
                logger.debug("Cached \(result.count) data points for \(String(describing: kind))")
            }
            
            return result
        } catch {
            logger.error("Failed to fetch daily metrics for \(String(describing: kind)): \(error.localizedDescription)")
            throw error
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

    public struct Trend: Sendable, Codable {
        public let windowDays: Int
        public let points: [DailyMetric]
        public let average: Double
        public let changeRate: Double // last vs first
    }

    public func trend(kind: MetricKind, days: Int, endingAt end: Date = Date(), useCache: Bool = true) async throws -> Trend {
        let cache = HealthKitCache.shared
        let cacheKey = cache.trendCacheKey(kind: kind, days: days, endDate: end)
        
        // Check cache first
        if useCache, let cached = cache.get(key: cacheKey, type: Trend.self) {
            logger.debug("Using cached trend data for \(String(describing: kind)) \(days) days")
            return cached
        }
        
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -days + 1, to: calendar.startOfDay(for: end)) ?? end
        let series = try await fetchDailyMetrics(kind: kind, start: start, end: end, useCache: useCache)
        let values = series.map { $0.value }
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let change = (values.last ?? 0) - (values.first ?? 0)
        let base = max(1e-9, abs(values.first ?? 0))
        let changeRate = change / base
        let result = Trend(windowDays: days, points: series, average: avg, changeRate: changeRate)
        
        // Cache the result
        if useCache {
            cache.set(result, forKey: cacheKey)
            logger.debug("Cached trend data for \(String(describing: kind)) \(days) days")
        }
        
        return result
    }

    public struct Comparison: Sendable, Codable {
        public let currentWindowDays: Int
        public let previousWindowDays: Int
        public let currentAverage: Double
        public let previousAverage: Double
        public let delta: Double
        public let deltaRate: Double
    }

    public func compare(kind: MetricKind, windowDays: Int, endingAt end: Date = Date(), useCache: Bool = true) async throws -> Comparison {
        let cache = HealthKitCache.shared
        let cacheKey = cache.comparisonCacheKey(kind: kind, windowDays: windowDays, endDate: end)
        
        // Check cache first
        if useCache, let cached = cache.get(key: cacheKey, type: Comparison.self) {
            logger.debug("Using cached comparison data for \(String(describing: kind)) \(windowDays) days")
            return cached
        }
        
        let calendar = Calendar.current
        let endOfDay = calendar.startOfDay(for: end)
        let startCurrent = calendar.date(byAdding: .day, value: -windowDays + 1, to: endOfDay) ?? endOfDay
        let endPrev = calendar.date(byAdding: .day, value: -windowDays, to: startCurrent) ?? startCurrent
        let startPrev = calendar.date(byAdding: .day, value: -windowDays + 1, to: endPrev) ?? endPrev

        async let current = fetchDailyMetrics(kind: kind, start: startCurrent, end: endOfDay, useCache: useCache)
        async let previous = fetchDailyMetrics(kind: kind, start: startPrev, end: endPrev, useCache: useCache)

        let (curSeries, prevSeries) = try await (current, previous)
        let curAvg = curSeries.map { $0.value }.average()
        let prevAvg = prevSeries.map { $0.value }.average()
        let delta = curAvg - prevAvg
        let base = max(1e-9, abs(prevAvg))
        let deltaRate = delta / base
        let result = Comparison(
            currentWindowDays: windowDays,
            previousWindowDays: windowDays,
            currentAverage: curAvg,
            previousAverage: prevAvg,
            delta: delta,
            deltaRate: deltaRate
        )
        
        // Cache the result
        if useCache {
            cache.set(result, forKey: cacheKey)
            logger.debug("Cached comparison data for \(String(describing: kind)) \(windowDays) days")
        }
        
        return result
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
