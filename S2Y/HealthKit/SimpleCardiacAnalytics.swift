//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT

// swiftlint:disable function_body_length type_body_length

import Foundation
import HealthKit
import OSLog

/// Simple cardiac health analytics and insights
@MainActor
public final class SimpleCardiacAnalytics {
    public static let shared = SimpleCardiacAnalytics()
    
    private let healthKit = HealthKitService.shared
    private let logger = Logger(subsystem: "com.s2y.app", category: "SimpleCardiacAnalytics")
    
    private init() {}
    
    // MARK: - Basic Cardiac Assessment
    
    public struct CardiacScore: Sendable, Codable {
        public let date: Date
        public let overallScore: Double // 0-100
        public let restingHeartRate: Double?
        public let heartRateVariability: Double?
        public let vo2Max: Double?
        public let riskLevel: String
        
        public init(date: Date = Date(), overallScore: Double, restingHeartRate: Double? = nil, heartRateVariability: Double? = nil, vo2Max: Double? = nil, riskLevel: String) {
            self.date = date
            self.overallScore = overallScore
            self.restingHeartRate = restingHeartRate
            self.heartRateVariability = heartRateVariability
            self.vo2Max = vo2Max
            self.riskLevel = riskLevel
        }
    }
    
    public struct HRVInsight: Sendable, Codable {
        public let date: Date
        public let averageHRV: Double
        public let trend: String
        public let stressLevel: String
        public let recommendation: String
        
        public init(date: Date = Date(), averageHRV: Double, trend: String, stressLevel: String, recommendation: String) {
            self.date = date
            self.averageHRV = averageHRV
            self.trend = trend
            self.stressLevel = stressLevel
            self.recommendation = recommendation
        }
    }
    
    /// Generate basic cardiac health score
    public func generateCardiacScore(windowDays: Int = 30) async throws -> CardiacScore {
        logger.info("Generating cardiac score for \(windowDays) days")
        
        // Get recent metrics
        let restingHR = try? await getLatestMetric(.restingHeartRate, days: windowDays)
        let hrv = try? await getLatestMetric(.heartRateVariability, days: windowDays)  
        let vo2 = try? await getLatestMetric(.vo2Max, days: windowDays)
        
        // Calculate overall score (simplified)
        var score = 50.0 // baseline
        var components = 0
        
        if let rhr = restingHR {
            let rhrScore = max(0, min(100, 100 - (rhr - 50) * 2))
            score += rhrScore * 0.3
            components += 1
        }
        
        if let hrvValue = hrv {
            let hrvScore = min(100, hrvValue * 2)
            score += hrvScore * 0.4
            components += 1
        }
        
        if let vo2Value = vo2 {
            let vo2Score = min(100, vo2Value * 2)
            score += vo2Score * 0.3
            components += 1
        }
        
        let finalScore = components > 0 ? score / Double(components + 1) * 2 : 50
        
        // Determine risk level
        let riskLevel: String
        if finalScore >= 80 { riskLevel = "Low Risk" }
        else if finalScore >= 60 { riskLevel = "Moderate Risk" }
        else if finalScore >= 40 { riskLevel = "High Risk" }
        else { riskLevel = "Very High Risk" }
        
        return CardiacScore(
            overallScore: finalScore,
            restingHeartRate: restingHR,
            heartRateVariability: hrv,
            vo2Max: vo2,
            riskLevel: riskLevel
        )
    }
    
    /// Analyze Heart Rate Variability
    public func analyzeHRV(days: Int = 7) async throws -> HRVInsight {
        logger.info("Analyzing HRV for \(days) days")
        
        let trend = try await healthKit.trend(kind: .heartRateVariability, days: days)
        let average = trend.average
        
        // Determine trend direction
        let trendDirection: String
        if trend.changeRate > 0.1 { trendDirection = "Improving" }
        else if trend.changeRate < -0.1 { trendDirection = "Declining" }
        else { trendDirection = "Stable" }
        
        // Assess stress level
        let stressLevel: String
        if average > 40 { stressLevel = "Low Stress" }
        else if average > 30 { stressLevel = "Moderate Stress" }
        else if average > 20 { stressLevel = "High Stress" }
        else { stressLevel = "Very High Stress" }
        
        // Generate recommendation
        let recommendation: String
        if average < 25 {
            recommendation = "Focus on stress management techniques like deep breathing and meditation."
        } else if average > 45 {
            recommendation = "Excellent HRV! Maintain your current lifestyle and recovery practices."
        } else {
            recommendation = "Consider improving sleep quality and managing stress for better HRV."
        }
        
        return HRVInsight(
            averageHRV: average,
            trend: trendDirection,
            stressLevel: stressLevel,
            recommendation: recommendation
        )
    }
    
    /// Get cardiac fitness level based on VO2 Max
    public func getCardiacFitnessLevel(days: Int = 30) async throws -> String {
        guard let vo2Max = try? await getLatestMetric(.vo2Max, days: days) else {
            return "Unable to assess - no VO2 Max data available"
        }
        
        // Age-adjusted fitness levels (simplified for 25-45 age range)
        if vo2Max > 50 { return "Excellent" }
        else if vo2Max > 42 { return "Very Good" }
        else if vo2Max > 35 { return "Good" }
        else if vo2Max > 28 { return "Fair" }
        else { return "Poor" }
    }
    
    // MARK: - Helper Methods
    
    private func getLatestMetric(_ kind: HealthKitService.MetricKind, days: Int) async throws -> Double? {
        let trend = try await healthKit.trend(kind: kind, days: days)
        return trend.points.last?.value
    }
}