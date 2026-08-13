//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

public struct HealthKitCacheStatistics: Equatable, Sendable {
    public let hits: Int
    public let misses: Int
    public let expiredEntries: Int
    public let invalidatedEntries: Int
}

/// In-memory cache for HealthKit data with automatic expiry
@MainActor
public final class HealthKitCache {
    public static let shared = HealthKitCache()
    
    private struct CachedResult: Sendable {
        let data: Data
        let timestamp: Date
        let expiryInterval: TimeInterval
        
        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > expiryInterval
        }
    }
    
    private var cache: [String: CachedResult] = [:]
    private let defaultExpiryInterval: TimeInterval
    private var hits = 0
    private var misses = 0
    private var expiredEntries = 0
    private var invalidatedEntries = 0

    public var entryCount: Int {
        cleanupExpired()
        return cache.count
    }
    
    init(defaultExpiryInterval: TimeInterval = 300) {
        self.defaultExpiryInterval = defaultExpiryInterval
    }

    public var statistics: HealthKitCacheStatistics {
        HealthKitCacheStatistics(
            hits: hits,
            misses: misses,
            expiredEntries: expiredEntries,
            invalidatedEntries: invalidatedEntries
        )
    }
    
    /// Cache key for daily metrics
    public func cacheKey(kind: HealthKitService.MetricKind, start: Date, end: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return "daily_\(kind)_\(formatter.string(from: start))_\(formatter.string(from: end))"
    }
    
    /// Cache key for trends
    public func trendCacheKey(kind: HealthKitService.MetricKind, days: Int, endDate: Date) -> String {
        let formatter = ISO8601DateFormatter()
        let dayBoundary = Calendar.current.startOfDay(for: endDate)
        return "trend_\(kind)_\(days)_\(formatter.string(from: dayBoundary))"
    }
    
    /// Cache key for comparisons
    public func comparisonCacheKey(kind: HealthKitService.MetricKind, windowDays: Int, endDate: Date) -> String {
        let formatter = ISO8601DateFormatter()
        let dayBoundary = Calendar.current.startOfDay(for: endDate)
        return "comparison_\(kind)_\(windowDays)_\(formatter.string(from: dayBoundary))"
    }
    
    /// Get cached data
    public func get<T: Codable>(key: String, type: T.Type) -> T? {
        guard let cached = cache[key] else {
            misses += 1
            return nil
        }
        guard !cached.isExpired else {
            cache.removeValue(forKey: key)
            misses += 1
            expiredEntries += 1
            return nil
        }
        
        do {
            let value = try JSONDecoder().decode(type, from: cached.data)
            hits += 1
            return value
        } catch {
            cache.removeValue(forKey: key)
            misses += 1
            invalidatedEntries += 1
            return nil
        }
    }
    
    /// Set cached data
    public func set<T: Codable>(_ value: T, forKey key: String, expiryInterval: TimeInterval? = nil) {
        do {
            let data = try JSONEncoder().encode(value)
            let expiry = expiryInterval ?? defaultExpiryInterval
            cache[key] = CachedResult(data: data, timestamp: Date(), expiryInterval: expiry)
        } catch {
            // Ignore encoding errors
        }
    }
    
    /// Clear expired entries
    public func cleanupExpired() {
        let expired = cache.filter { $0.value.isExpired }
        expiredEntries += expired.count
        for key in expired.keys {
            cache.removeValue(forKey: key)
        }
    }
    
    /// Clear all cache
    public func clearAll() {
        invalidatedEntries += cache.count
        cache.removeAll()
    }
    
    /// Clear cache for specific metric
    public func clearMetric(_ kind: HealthKitService.MetricKind) {
        let keysToRemove = cache.keys.filter { $0.contains("_\(kind)_") }
        invalidatedEntries += keysToRemove.count
        for key in keysToRemove {
            cache.removeValue(forKey: key)
        }
    }
}
