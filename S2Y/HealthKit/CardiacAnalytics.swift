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

// MARK: - Supporting Types

/// Advanced cardiac health analytics and insights
@MainActor
public final class CardiacAnalytics {
    public static let shared = CardiacAnalytics()
    
    private let healthKit = HealthKitService.shared
    private let logger = Logger(subsystem: "com.s2y.app", category: "CardiacAnalytics")
    
    private init() {}
    
    // MARK: - Comprehensive Cardiac Assessment
    
    public struct CardiacHealthProfile: Sendable, Codable {
        public let assessmentDate: Date
        public let overallScore: Double // 0-100
        public let riskLevel: RiskLevel
        public let metrics: CardiacMetrics
        public let insights: [Insight]
        public let recommendations: [Recommendation]
        
        public enum RiskLevel: String, Sendable, Codable {
            case low = "low"
            case moderate = "moderate" 
            case high = "high"
            case veryHigh = "veryHigh"
            
            public var displayName: String {
                switch self {
                case .low: return "Low Risk"
                case .moderate: return "Moderate Risk"
                case .high: return "High Risk"
                case .veryHigh: return "Very High Risk"
                }
            }
            
            public var displayNameCN: String {
                switch self {
                case .low: return "低风险"
                case .moderate: return "中等风险"
                case .high: return "高风险"
                case .veryHigh: return "极高风险"
                }
            }
        }
    }
    
    public struct CardiacMetrics: Sendable, Codable {
        public let restingHeartRate: Double?
        public let heartRateVariability: Double?
        public let heartRateRecovery: Double?
        public let vo2Max: Double?
        public let walkingHeartRate: Double?
        public let oxygenSaturation: Double?
        public let systolicBP: Double?
        public let diastolicBP: Double?
        
        // Calculated metrics
        public let fitnessAge: Double?
        public let cardiacEfficiency: Double?
        public let autonomicBalance: Double?
    }
    
    public struct Insight: Sendable, Codable {
        public let type: InsightType
        public let severity: Severity
        public let title: String
        public let titleCN: String
        public let message: String
        public let messageCN: String
        public let relatedMetrics: [HealthKitService.MetricKind]
        
        public enum InsightType: String, Sendable, Codable {
            case trend = "trend"
            case anomaly = "anomaly"
            case improvement = "improvement"
            case warning = "warning"
        }
        
        public enum Severity: String, Sendable, Codable {
            case info = "info"
            case moderate = "moderate"
            case high = "high"
            case critical = "critical"
        }
    }
    
    public struct Recommendation: Sendable, Codable {
        public let category: Category
        public let priority: Priority
        public let title: String
        public let titleCN: String
        public let description: String
        public let descriptionCN: String
        public let actionable: Bool
        
        public enum Category: String, Sendable, Codable {
            case exercise = "exercise"
            case lifestyle = "lifestyle"
            case medical = "medical"
            case monitoring = "monitoring"
        }
        
        public enum Priority: String, Sendable, Codable {
            case low = "low"
            case medium = "medium"
            case high = "high"
            case urgent = "urgent"
        }
    }
    
    /// Generate comprehensive cardiac health profile
    public func generateCardiacProfile(windowDays: Int = 30) async throws -> CardiacHealthProfile {
        logger.info("Generating cardiac health profile for \(windowDays) days")
        
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -windowDays, to: endDate) ?? endDate
        
        // Gather cardiac metrics concurrently
        async let restingHR = fetchLatestMetric(.restingHeartRate, days: windowDays)
        async let hrv = fetchLatestMetric(.heartRateVariability, days: windowDays)
        async let recovery = fetchLatestMetric(.heartRateRecovery, days: windowDays)
        async let vo2 = fetchLatestMetric(.vo2Max, days: windowDays)
        async let walkingHR = fetchLatestMetric(.walkingHeartRateAverage, days: windowDays)
        async let oxygen = fetchLatestMetric(.oxygenSaturation, days: windowDays)
        async let systolic = fetchLatestMetric(.bloodPressureSystolic, days: windowDays)
        async let diastolic = fetchLatestMetric(.bloodPressureDiastolic, days: windowDays)
        
        let metrics = try await CardiacMetrics(
            restingHeartRate: restingHR,
            heartRateVariability: hrv,
            heartRateRecovery: recovery,
            vo2Max: vo2,
            walkingHeartRate: walkingHR,
            oxygenSaturation: oxygen,
            systolicBP: systolic,
            diastolicBP: diastolic,
            fitnessAge: calculateFitnessAge(vo2Max: vo2, age: 35), // TODO: Get actual age
            cardiacEfficiency: calculateCardiacEfficiency(restingHR: restingHR, vo2Max: vo2),
            autonomicBalance: calculateAutonomicBalance(hrv: hrv, restingHR: restingHR)
        )
        
        let overallScore = calculateOverallCardiacScore(metrics: metrics)
        let riskLevel = determineRiskLevel(score: overallScore, metrics: metrics)
        let insights = generateInsights(metrics: metrics, windowDays: windowDays)
        let recommendations = generateRecommendations(metrics: metrics, riskLevel: riskLevel)
        
        return CardiacHealthProfile(
            assessmentDate: Date(),
            overallScore: overallScore,
            riskLevel: riskLevel,
            metrics: metrics,
            insights: insights,
            recommendations: recommendations
        )
    }
    
    // MARK: - HRV Analysis
    
    public struct HRVAnalysis: Sendable, Codable {
        public let average: Double
        public let trend: TrendDirection
        public let stressLevel: StressLevel
        public let autonomicBalance: AutonomicBalance
        public let recovery: RecoveryStatus
        
        public enum TrendDirection: String, Sendable, Codable {
            case improving = "improving"
            case stable = "stable"
            case declining = "declining"
        }
        
        public enum StressLevel: String, Sendable, Codable {
            case low = "low"
            case moderate = "moderate"
            case high = "high"
            case veryHigh = "veryHigh"
        }
        
        public enum AutonomicBalance: String, Sendable, Codable {
            case balanced = "balanced"
            case sympatheticDominant = "sympatheticDominant"
            case parasympatheticDominant = "parasympatheticDominant"
        }
        
        public enum RecoveryStatus: String, Sendable, Codable {
            case excellent = "excellent"
            case good = "good"
            case fair = "fair"
            case poor = "poor"
        }
    }
    
    /// Analyze Heart Rate Variability patterns
    public func analyzeHRV(days: Int = 7) async throws -> HRVAnalysis {
        let trend = try await healthKit.trend(kind: .heartRateVariability, days: days)
        let average = trend.average
        
        let trendDirection: HRVAnalysis.TrendDirection = {
            if trend.changeRate > 0.1 { return .improving }
            if trend.changeRate < -0.1 { return .declining }
            return .stable
        }()
        
        let stressLevel: HRVAnalysis.StressLevel = {
            if average > 40 { return .low }
            if average > 30 { return .moderate }
            if average > 20 { return .high }
            return .veryHigh
        }()
        
        // Get resting HR for autonomic balance calculation
        let restingHR = try await fetchLatestMetric(.restingHeartRate, days: days) ?? 70
        let balance = calculateAutonomicBalanceEnum(hrv: average, restingHR: restingHR)
        
        let recovery: HRVAnalysis.RecoveryStatus = {
            if average > 45 { return .excellent }
            if average > 35 { return .good }
            if average > 25 { return .fair }
            return .poor
        }()
        
        return HRVAnalysis(
            average: average,
            trend: trendDirection,
            stressLevel: stressLevel,
            autonomicBalance: balance,
            recovery: recovery
        )
    }
    
    // MARK: - Private Helpers
    
    private func fetchLatestMetric(_ kind: HealthKitService.MetricKind, days: Int) async throws -> Double? {
        let trend = try await healthKit.trend(kind: kind, days: days)
        return trend.points.last?.value
    }
    
    private func calculateFitnessAge(vo2Max: Double?, age: Int) -> Double? {
        guard let vo2Max = vo2Max else { return nil }
        
        // Simplified fitness age calculation based on VO2 Max
        // Higher VO2 Max = younger fitness age
        let avgVO2ForAge = 35.0 // Baseline for a 35-year-old
        let vo2Difference = vo2Max - avgVO2ForAge
        let fitnessAge = Double(age) - (vo2Difference * 0.5)
        
        return max(18, min(80, fitnessAge)) // Clamp between 18-80
    }
    
    private func calculateCardiacEfficiency(restingHR: Double?, vo2Max: Double?) -> Double? {
        guard let restingHR = restingHR, let vo2Max = vo2Max else { return nil }
        
        // Cardiac efficiency = VO2 Max / Resting HR * 100
        // Higher is better
        return (vo2Max / restingHR) * 100
    }
    
    private func calculateAutonomicBalance(hrv: Double?, restingHR: Double?) -> Double? {
        guard let hrv = hrv, let restingHR = restingHR else { return nil }
        
        // Balance score: HRV inversely related to resting HR
        // Higher HRV + Lower RHR = Better balance
        let normalizedHRV = hrv / 50.0 // Normalize around 50ms
        let normalizedRHR = (100 - restingHR) / 40.0 // Normalize around 60bpm
        
        return (normalizedHRV + normalizedRHR) / 2.0 * 100
    }
    
    private func calculateAutonomicBalanceEnum(hrv: Double, restingHR: Double) -> HRVAnalysis.AutonomicBalance {
        let balanceScore = calculateAutonomicBalance(hrv: hrv, restingHR: restingHR) ?? 50
        
        if balanceScore > 70 { return .balanced }
        if restingHR > 70 { return .sympatheticDominant }
        return .parasympatheticDominant
    }
    
    private func calculateOverallCardiacScore(metrics: CardiacMetrics) -> Double {
        var score = 0.0
        var components = 0
        
        // Resting Heart Rate (weight: 0.2)
        if let rhr = metrics.restingHeartRate {
            let rhrScore = max(0, min(100, 100 - (rhr - 50) * 2))
            score += rhrScore * 0.2
            components += 1
        }
        
        // HRV (weight: 0.25)
        if let hrv = metrics.heartRateVariability {
            let hrvScore = min(100, hrv * 2)
            score += hrvScore * 0.25
            components += 1
        }
        
        // VO2 Max (weight: 0.3)
        if let vo2 = metrics.vo2Max {
            let vo2Score = min(100, vo2 * 2)
            score += vo2Score * 0.3
            components += 1
        }
        
        // Heart Rate Recovery (weight: 0.15)
        if let recovery = metrics.heartRateRecovery {
            let recoveryScore = min(100, recovery * 4)
            score += recoveryScore * 0.15
            components += 1
        }
        
        // Blood Pressure (weight: 0.1)
        if let systolic = metrics.systolicBP, let diastolic = metrics.diastolicBP {
            let bpScore = calculateBloodPressureScore(systolic: systolic, diastolic: diastolic)
            score += bpScore * 0.1
            components += 1
        }
        
        return components > 0 ? score : 50 // Default if no metrics
    }
    
    private func calculateBloodPressureScore(systolic: Double, diastolic: Double) -> Double {
        // Optimal: <120/80, Good: 120-129/80-84, Elevated: 130-139/85-89, High: >140/90
        if systolic < 120 && diastolic < 80 { return 100 }
        if systolic < 130 && diastolic < 85 { return 85 }
        if systolic < 140 && diastolic < 90 { return 70 }
        return 40
    }
    
    private func determineRiskLevel(score: Double, metrics: CardiacMetrics) -> CardiacHealthProfile.RiskLevel {
        // High-priority risk factors
        if let systolic = metrics.systolicBP, systolic > 160 { return .veryHigh }
        if let diastolic = metrics.diastolicBP, diastolic > 100 { return .veryHigh }
        if let rhr = metrics.restingHeartRate, rhr > 100 { return .high }
        
        // Score-based risk assessment
        if score >= 80 { return .low }
        if score >= 65 { return .moderate }
        if score >= 50 { return .high }
        return .veryHigh
    }
    
    private func generateInsights(metrics: CardiacMetrics, windowDays: Int) -> [Insight] {
        var insights: [Insight] = []
        
        // HRV Insights
        if let hrv = metrics.heartRateVariability {
            if hrv < 20 {
                insights.append(Insight(
                    type: .warning,
                    severity: .high,
                    title: "Low Heart Rate Variability",
                    titleCN: "心率变异性偏低",
                    message: "Your HRV is below optimal range, indicating potential stress or fatigue.",
                    messageCN: "您的心率变异性低于最佳范围，可能表示压力或疲劳。",
                    relatedMetrics: [.heartRateVariability]
                ))
            } else if hrv > 50 {
                insights.append(Insight(
                    type: .improvement,
                    severity: .info,
                    title: "Excellent Heart Rate Variability",
                    titleCN: "心率变异性优秀",
                    message: "Your HRV indicates good recovery and low stress levels.",
                    messageCN: "您的心率变异性表明恢复良好且压力水平较低。",
                    relatedMetrics: [.heartRateVariability]
                ))
            }
        }
        
        // VO2 Max Insights
        if let vo2 = metrics.vo2Max {
            if vo2 < 30 {
                insights.append(Insight(
                    type: .warning,
                    severity: .moderate,
                    title: "Below Average Cardiovascular Fitness",
                    titleCN: "心血管健康水平偏低",
                    message: "Your VO₂ Max suggests room for cardiovascular fitness improvement.",
                    messageCN: "您的最大摄氧量表明心血管健康有待提高。",
                    relatedMetrics: [.vo2Max]
                ))
            }
        }
        
        return insights
    }
    
    private func generateRecommendations(metrics: CardiacMetrics, riskLevel: CardiacHealthProfile.RiskLevel) -> [Recommendation] {
        var recommendations: [Recommendation] = []
        
        // General recommendations based on risk level
        if riskLevel == .high || riskLevel == .veryHigh {
            recommendations.append(Recommendation(
                category: .medical,
                priority: .high,
                title: "Consult Healthcare Provider",
                titleCN: "咨询医疗专业人员",
                description: "Your cardiac metrics suggest consulting with a healthcare provider for evaluation.",
                descriptionCN: "您的心脏指标建议咨询医疗专业人员进行评估。",
                actionable: true
            ))
        }
        
        // HRV-specific recommendations
        if let hrv = metrics.heartRateVariability, hrv < 30 {
            recommendations.append(Recommendation(
                category: .lifestyle,
                priority: .medium,
                title: "Stress Management",
                titleCN: "压力管理",
                description: "Consider meditation, yoga, or other stress-reduction techniques to improve HRV.",
                descriptionCN: "考虑冥想、瑜伽或其他减压技巧来改善心率变异性。",
                actionable: true
            ))
        }
        
        // Fitness recommendations
        if let vo2 = metrics.vo2Max, vo2 < 35 {
            recommendations.append(Recommendation(
                category: .exercise,
                priority: .medium,
                title: "Increase Aerobic Exercise",
                titleCN: "增加有氧运动",
                description: "Regular cardio exercise can improve your VO₂ Max and overall cardiac health.",
                descriptionCN: "规律的有氧运动可以提高您的最大摄氧量和整体心脏健康。",
                actionable: true
            ))
        }
        
        return recommendations
    }
}