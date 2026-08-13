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

public enum HealthPermissionGroup: String, CaseIterable, Identifiable, Sendable {
    case activity
    case sleep
    case heart
    case vitals
    case body

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .activity: "Activity"
        case .sleep: "Sleep"
        case .heart: "Heart & Fitness"
        case .vitals: "Vitals"
        case .body: "Body Measurements"
        }
    }

    public var purpose: String {
        switch self {
        case .activity:
            "Understand movement, exercise, and energy trends."
        case .sleep:
            "Summarize sleep duration and consistency."
        case .heart:
            "Explain heart-rate, recovery, and cardio-fitness trends."
        case .vitals:
            "Review blood pressure, temperature, breathing, and oxygen trends."
        case .body:
            "Track changes in body measurements over time."
        }
    }

    public var systemImage: String {
        switch self {
        case .activity: "figure.walk"
        case .sleep: "bed.double"
        case .heart: "heart"
        case .vitals: "waveform.path.ecg"
        case .body: "scalemass"
        }
    }

    public var metricKinds: [HealthKitService.MetricKind] {
        switch self {
        case .activity:
            [.steps, .activeEnergy]
        case .sleep:
            [.sleepDurationHours]
        case .heart:
            [
                .heartRateAverage,
                .restingHeartRate,
                .heartRateVariability,
                .heartRateRecovery,
                .vo2Max,
                .walkingHeartRateAverage
            ]
        case .vitals:
            [
                .oxygenSaturation,
                .bloodPressureSystolic,
                .bloodPressureDiastolic,
                .bodyTemperature,
                .respiratoryRate
            ]
        case .body:
            [.bodyMass]
        }
    }
}

public enum HealthPermissionRequestState: Sendable {
    case review
    case requested
    case unavailable
}

public struct HealthMetricProvenance: Identifiable, Sendable {
    public enum Freshness: String, Sendable {
        case current = "Current"
        case aging = "Getting old"
        case stale = "Out of date"
    }

    public let metricKind: HealthKitService.MetricKind
    public let sourceName: String
    public let deviceName: String?
    public let updatedAt: Date
    public let freshness: Freshness

    public var id: HealthKitService.MetricKind { metricKind }

    public static func freshness(
        for updatedAt: Date,
        relativeTo now: Date = .now
    ) -> Freshness {
        let age = max(0, now.timeIntervalSince(updatedAt))
        if age <= 48 * 60 * 60 {
            return .current
        }
        if age <= 7 * 24 * 60 * 60 {
            return .aging
        }
        return .stale
    }
}

@MainActor
public final class HealthKitService {
    public static let shared = HealthKitService()

    // Internal so focused HealthKit extensions (for example, clinical records)
    // can share the same store without exposing it outside the app module.
    let healthStore = HKHealthStore()
    private let logger = Logger(subsystem: "com.s2y.app", category: "HealthKit")

    private init() {}

    public func requestAuthorization() async throws {
        try await requestAuthorization(for: Set(HealthPermissionGroup.allCases))
    }

    public func requestAuthorization(for groups: Set<HealthPermissionGroup>) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { 
            logger.error("HealthKit not available on this device")
            throw HealthKitError.notAvailable
        }

        let readTypes = readTypes(for: groups)
        guard !readTypes.isEmpty else {
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            logger.info("HealthKit authorization successful")
        } catch {
            logger.error("HealthKit authorization failed: \(error.localizedDescription)")
            throw HealthKitError.authorizationFailed
        }
    }

    public func permissionRequestState(for group: HealthPermissionGroup) async -> HealthPermissionRequestState {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailable
        }

        do {
            let status = try await healthStore.statusForAuthorizationRequest(
                toShare: [],
                read: readTypes(for: [group])
            )
            switch status {
            case .shouldRequest:
                return .review
            case .unnecessary:
                return .requested
            case .unknown:
                return .review
            @unknown default:
                return .review
            }
        } catch {
            logger.error("Could not determine Health authorization request state: \(error.localizedDescription)")
            return .review
        }
    }

    public func latestProvenance(for kind: MetricKind) async throws -> HealthMetricProvenance? {
        guard let sampleType = healthObjectType(for: kind) as? HKSampleType else {
            return nil
        }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }
                continuation.resume(returning: samples ?? [])
            }
            healthStore.execute(query)
        }

        guard let sample = samples.first else {
            return nil
        }
        return HealthMetricProvenance(
            metricKind: kind,
            sourceName: sample.sourceRevision.source.name,
            deviceName: sample.device?.name ?? sample.device?.model,
            updatedAt: sample.endDate,
            freshness: HealthMetricProvenance.freshness(for: sample.endDate)
        )
    }

    private func readTypes(for groups: Set<HealthPermissionGroup>) -> Set<HKObjectType> {
        Set(groups.flatMap(\.metricKinds).compactMap(healthObjectType(for:)))
    }

    private func healthObjectType(for kind: MetricKind) -> HKObjectType? {
        switch kind {
        case .steps:
            HKObjectType.quantityType(forIdentifier: .stepCount)
        case .heartRateAverage:
            HKObjectType.quantityType(forIdentifier: .heartRate)
        case .restingHeartRate:
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)
        case .activeEnergy:
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        case .bodyMass:
            HKObjectType.quantityType(forIdentifier: .bodyMass)
        case .sleepDurationHours:
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case .heartRateVariability:
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        case .heartRateRecovery:
            HKObjectType.quantityType(forIdentifier: .heartRateRecoveryOneMinute)
        case .vo2Max:
            HKObjectType.quantityType(forIdentifier: .vo2Max)
        case .walkingHeartRateAverage:
            HKObjectType.quantityType(forIdentifier: .walkingHeartRateAverage)
        case .oxygenSaturation:
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)
        case .bloodPressureSystolic:
            HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)
        case .bloodPressureDiastolic:
            HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)
        case .bodyTemperature:
            HKObjectType.quantityType(forIdentifier: .bodyTemperature)
        case .respiratoryRate:
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)
        }
    }

    // MARK: - Daily metrics

    public struct DailyMetric: Sendable, Codable {
        public let date: Date
        public let value: Double
        public let isObserved: Bool

        public init(date: Date, value: Double, isObserved: Bool = true) {
            self.date = date
            self.value = value
            self.isObserved = isObserved
        }
    }

    public enum MetricKind: Sendable, Codable, CaseIterable, Hashable {
        case steps
        case heartRateAverage
        case restingHeartRate
        case activeEnergy
        case bodyMass
        case sleepDurationHours
        
        // Advanced Cardiac Metrics
        case heartRateVariability      // HRV SDNN
        case heartRateRecovery         // Post-exercise recovery
        case vo2Max                    // Cardiovascular fitness
        case walkingHeartRateAverage   // Heart rate during walking
        case oxygenSaturation          // Blood oxygen level
        
        // Additional Vitals
        case bloodPressureSystolic
        case bloodPressureDiastolic
        case bodyTemperature
        case respiratoryRate
        
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
                            output.append(.init(date: date, value: value, isObserved: quantity != nil))
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
        case .heartRateVariability:
            return .init(
                type: HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
                unit: HKUnit.secondUnit(with: .milli),
                options: .discreteAverage
            )
        case .heartRateRecovery:
            return .init(
                type: HKObjectType.quantityType(forIdentifier: .heartRateRecoveryOneMinute)!,
                unit: HKUnit.count().unitDivided(by: .minute()),
                options: .discreteAverage
            )
        case .vo2Max:
            return .init(
                type: HKObjectType.quantityType(forIdentifier: .vo2Max)!,
                unit: HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo)).unitDivided(by: .minute()),
                options: .discreteAverage
            )
        case .walkingHeartRateAverage:
            return .init(
                type: HKObjectType.quantityType(forIdentifier: .walkingHeartRateAverage)!,
                unit: HKUnit.count().unitDivided(by: .minute()),
                options: .discreteAverage
            )
        case .oxygenSaturation:
            return .init(
                type: HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
                unit: HKUnit.percent(),
                options: .discreteAverage
            )
        case .bloodPressureSystolic:
            return .init(
                type: HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)!,
                unit: HKUnit.millimeterOfMercury(),
                options: .discreteAverage
            )
        case .bloodPressureDiastolic:
            return .init(
                type: HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)!,
                unit: HKUnit.millimeterOfMercury(),
                options: .discreteAverage
            )
        case .bodyTemperature:
            return .init(
                type: HKObjectType.quantityType(forIdentifier: .bodyTemperature)!,
                unit: HKUnit.degreeCelsius(),
                options: .discreteAverage
            )
        case .respiratoryRate:
            return .init(
                type: HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
                unit: HKUnit.count().unitDivided(by: .minute()),
                options: .discreteAverage
            )
        case .sleepDurationHours:
            throw NSError(domain: "HealthKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "Sleep duration handled separately."])
        }
    }

    // MARK: - Aggregations

    public enum DataQuality: String, Sendable, Codable {
        case unavailable
        case limited
        case sufficient
        case complete

        public static func classify(observedDays: Int, expectedDays: Int) -> DataQuality {
            guard observedDays > 0, expectedDays > 0 else {
                return .unavailable
            }
            let coverage = Double(observedDays) / Double(expectedDays)
            if coverage >= 0.9 {
                return .complete
            }
            if coverage >= 0.5 {
                return .sufficient
            }
            return .limited
        }
    }

    public struct Distribution: Sendable, Codable, Equatable {
        public let observedCount: Int
        public let minimum: Double
        public let firstQuartile: Double
        public let median: Double
        public let thirdQuartile: Double
        public let maximum: Double

        static func summarize(_ values: [Double]) -> Distribution? {
            let sorted = values.filter(\.isFinite).sorted()
            guard let minimum = sorted.first, let maximum = sorted.last else {
                return nil
            }
            return Distribution(
                observedCount: sorted.count,
                minimum: minimum,
                firstQuartile: sorted.quantile(0.25),
                median: sorted.quantile(0.5),
                thirdQuartile: sorted.quantile(0.75),
                maximum: maximum
            )
        }
    }

    public struct Trend: Sendable, Codable {
        public let windowDays: Int
        public let points: [DailyMetric]
        public let average: Double
        public let changeRate: Double // last vs first
        public let observedDays: Int
        public let expectedDays: Int
        public let dataQuality: DataQuality

        public var coverageRate: Double {
            guard expectedDays > 0 else { return 0 }
            return Double(observedDays) / Double(expectedDays)
        }

        public var distribution: Distribution? {
            Distribution.summarize(points.filter(\.isObserved).map(\.value))
        }

        static func summarize(windowDays: Int, points: [DailyMetric]) -> Trend {
            let observed = points.filter { $0.isObserved && $0.value.isFinite }
            let values = observed.map(\.value)
            let average = values.average()
            let changeRate: Double
            if let first = values.first, let last = values.last, abs(first) > 1e-9 {
                changeRate = (last - first) / abs(first)
            } else {
                changeRate = 0
            }
            return Trend(
                windowDays: windowDays,
                points: points,
                average: average,
                changeRate: changeRate,
                observedDays: observed.count,
                expectedDays: windowDays,
                dataQuality: .classify(observedDays: observed.count, expectedDays: windowDays)
            )
        }
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
        let result = Trend.summarize(windowDays: days, points: series)
        
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
        public let currentObservedDays: Int
        public let previousObservedDays: Int
        public let dataQuality: DataQuality

        static func summarize(
            windowDays: Int,
            current: [DailyMetric],
            previous: [DailyMetric]
        ) -> Comparison {
            let currentValues = current.filter(\.isObserved).map(\.value)
            let previousValues = previous.filter(\.isObserved).map(\.value)
            let currentAverage = currentValues.average()
            let previousAverage = previousValues.average()
            let delta = currentAverage - previousAverage
            let deltaRate = abs(previousAverage) > 1e-9 ? delta / abs(previousAverage) : 0
            let observedDays = min(currentValues.count, previousValues.count)
            return Comparison(
                currentWindowDays: windowDays,
                previousWindowDays: windowDays,
                currentAverage: currentAverage,
                previousAverage: previousAverage,
                delta: delta,
                deltaRate: deltaRate,
                currentObservedDays: currentValues.count,
                previousObservedDays: previousValues.count,
                dataQuality: .classify(observedDays: observedDays, expectedDays: windowDays)
            )
        }
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
        let result = Comparison.summarize(
            windowDays: windowDays,
            current: curSeries,
            previous: prevSeries
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
        var observedDays: Set<Date> = []
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
                observedDays.insert(dayStart)
                segStart = intervalEnd
            }
        }

        return dayBuckets.keys.sorted().map { day in
            .init(
                date: day,
                value: dayBuckets[day, default: 0] / 3600.0,
                isObserved: observedDays.contains(day)
            )
        }
    }
}

extension Array where Element == Double {
    func average() -> Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }

    func quantile(_ probability: Double) -> Double {
        guard !isEmpty else { return 0 }
        let boundedProbability = Swift.min(Swift.max(probability, 0), 1)
        let position = boundedProbability * Double(count - 1)
        let lowerIndex = Int(position.rounded(FloatingPointRoundingRule.down))
        let upperIndex = Int(position.rounded(FloatingPointRoundingRule.up))
        guard lowerIndex != upperIndex else { return self[lowerIndex] }
        let fraction = position - Double(lowerIndex)
        return self[lowerIndex] + ((self[upperIndex] - self[lowerIndex]) * fraction)
    }
}
