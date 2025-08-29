//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

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
    private let defaultExpiryInterval: TimeInterval = 300 // 5 minutes
    
    private init() {}
    
    /// Cache key for daily metrics
    public func cacheKey(kind: HealthKitService.MetricKind, start: Date, end: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return "daily_\(kind)_\(formatter.string(from: start))_\(formatter.string(from: end))"
    }
    
    /// Cache key for trends
    public func trendCacheKey(kind: HealthKitService.MetricKind, days: Int, endDate: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return "trend_\(kind)_\(days)_\(formatter.string(from: endDate))"
    }
    
    /// Cache key for comparisons
    public func comparisonCacheKey(kind: HealthKitService.MetricKind, windowDays: Int, endDate: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return "comparison_\(kind)_\(windowDays)_\(formatter.string(from: endDate))"
    }
    
    /// Get cached data
    public func get<T: Codable>(key: String, type: T.Type) -> T? {
        guard let cached = cache[key], !cached.isExpired else {
            cache.removeValue(forKey: key)
            return nil
        }
        
        do {
            return try JSONDecoder().decode(type, from: cached.data)
        } catch {
            cache.removeValue(forKey: key)
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
        for key in expired.keys {
            cache.removeValue(forKey: key)
        }
    }
    
    /// Clear all cache
    public func clearAll() {
        cache.removeAll()
    }
    
    /// Clear cache for specific metric
    public func clearMetric(_ kind: HealthKitService.MetricKind) {
        let keysToRemove = cache.keys.filter { $0.contains("_\(kind)_") }
        for key in keysToRemove {
            cache.removeValue(forKey: key)
        }
    }
}