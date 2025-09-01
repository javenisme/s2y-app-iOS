//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT

import Foundation
import OSLog

/// Specialized cardiac health insights engine with AI-driven analysis
@MainActor
public final class CardiacInsightsEngine {
    public static let shared = CardiacInsightsEngine()
    
    private let analytics = CardiacAnalytics.shared
    private let healthKit = HealthKitService.shared
    private let logger = Logger(subsystem: "com.s2y.app", category: "CardiacInsights")
    
    private init() {}
    
    // MARK: - Intelligent Cardiac Insights
    
    public struct SmartCardiacInsight: Sendable, Codable {
        public let id: UUID
        public let timestamp: Date
        public let category: InsightCategory
        public let priority: Priority
        public let confidence: Double // 0-1
        public let title: String
        public let titleCN: String
        public let summary: String
        public let summaryCN: String
        public let explanation: String
        public let explanationCN: String
        public let actionableSteps: [ActionStep]
        public let relatedMetrics: [MetricCorrelation]
        public let predictiveElements: [PredictiveElement]
        
        public enum InsightCategory: String, Sendable, Codable {
            case rhythmAnalysis = "rhythm"
            case fitnessOptimization = "fitness"
            case stressManagement = "stress"
            case recoveryOptimization = "recovery"
            case riskPrevention = "prevention"
            case performanceEnhancement = "performance"
        }
        
        public enum Priority: String, Sendable, Codable, CaseIterable {
            case low = "low"
            case medium = "medium"
            case high = "high"
            case critical = "critical"
        }
    }
    
    public struct ActionStep: Sendable, Codable {
        public let order: Int
        public let title: String
        public let titleCN: String
        public let description: String
        public let descriptionCN: String
        public let estimatedImpact: ImpactLevel
        public let timeframe: Timeframe
        public let trackable: Bool
        
        public enum ImpactLevel: String, Sendable, Codable {
            case minimal = "minimal"
            case moderate = "moderate"
            case significant = "significant"
            case transformative = "transformative"
        }
        
        public enum Timeframe: String, Sendable, Codable {
            case immediate = "immediate"        // 1-3 days
            case shortTerm = "shortTerm"       // 1-2 weeks
            case mediumTerm = "mediumTerm"     // 1-2 months
            case longTerm = "longTerm"         // 3+ months
        }
    }
    
    public struct MetricCorrelation: Sendable, Codable {
        public let metric: HealthKitService.MetricKind
        public let correlationStrength: Double // -1 to 1
        public let trendDirection: TrendDirection
        public let significance: Significance
        
        public enum TrendDirection: String, Sendable, Codable {
            case improving = "improving"
            case stable = "stable"
            case declining = "declining"
            case volatile = "volatile"
        }
        
        public enum Significance: String, Sendable, Codable {
            case low = "low"
            case medium = "medium"
            case high = "high"
            case critical = "critical"
        }
    }
    
    public struct PredictiveElement: Sendable, Codable {
        public let type: PredictionType
        public let timeframe: PredictionTimeframe
        public let probability: Double // 0-1
        public let description: String
        public let descriptionCN: String
        public let preventable: Bool
        
        public enum PredictionType: String, Sendable, Codable {
            case trendContinuation = "trendContinuation"
            case improvementPotential = "improvementPotential"
            case riskEscalation = "riskEscalation"
            case plateauPrediction = "plateauPrediction"
        }
        
        public enum PredictionTimeframe: String, Sendable, Codable {
            case oneWeek = "oneWeek"
            case oneMonth = "oneMonth"
            case threeMonths = "threeMonths"
            case sixMonths = "sixMonths"
        }
    }
    
    // MARK: - Core Insight Generation
    
    /// Generate comprehensive smart cardiac insights
    public func generateSmartInsights(lookbackDays: Int = 30) async throws -> [SmartCardiacInsight] {
        logger.info("Generating smart cardiac insights for \(lookbackDays) days")
        
        // Get cardiac profile
        let profile = try await analytics.generateCardiacProfile(windowDays: lookbackDays)
        
        // Get HRV analysis
        let hrvAnalysis = try await analytics.analyzeHRV(days: min(lookbackDays, 14))
        
        // Generate various insight types
        var insights: [SmartCardiacInsight] = []
        
        // HRV-based insights
        insights.append(contentsOf: await generateHRVInsights(analysis: hrvAnalysis, profile: profile))
        
        // Fitness optimization insights
        insights.append(contentsOf: await generateFitnessInsights(profile: profile))
        
        // Recovery optimization insights
        insights.append(contentsOf: await generateRecoveryInsights(profile: profile, hrvAnalysis: hrvAnalysis))
        
        // Risk prevention insights
        insights.append(contentsOf: await generateRiskInsights(profile: profile))
        
        // Performance enhancement insights
        insights.append(contentsOf: await generatePerformanceInsights(profile: profile))
        
        // Sort by priority and confidence
        return insights.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority.rawValue > rhs.priority.rawValue
            }
            return lhs.confidence > rhs.confidence
        }
    }
    
    // MARK: - Specialized Insight Generators
    
    private func generateHRVInsights(analysis: CardiacAnalytics.HRVAnalysis, profile: CardiacAnalytics.CardiacHealthProfile) async -> [SmartCardiacInsight] {
        var insights: [SmartCardiacInsight] = []
        
        // Stress level insight
        if analysis.stressLevel == .high || analysis.stressLevel == .veryHigh {
            let insight = SmartCardiacInsight(
                id: UUID(),
                timestamp: Date(),
                category: .stressManagement,
                priority: analysis.stressLevel == .veryHigh ? .high : .medium,
                confidence: 0.85,
                title: "Elevated Stress Detected via HRV",
                titleCN: "通过HRV检测到压力升高",
                summary: "Your heart rate variability indicates elevated stress levels.",
                summaryCN: "您的心率变异性表明压力水平升高。",
                explanation: "Low HRV (\(String(format: "%.1f", analysis.average))ms) suggests your autonomic nervous system is under stress. This can affect recovery, sleep quality, and overall health.",
                explanationCN: "低HRV（\(String(format: "%.1f", analysis.average))毫秒）表明您的自主神经系统处于压力状态。这可能影响恢复、睡眠质量和整体健康。",
                actionableSteps: [
                    ActionStep(
                        order: 1,
                        title: "Practice Deep Breathing",
                        titleCN: "练习深呼吸",
                        description: "Spend 10 minutes daily on 4-7-8 breathing technique to activate parasympathetic response.",
                        descriptionCN: "每天花10分钟练习4-7-8呼吸法，激活副交感神经反应。",
                        estimatedImpact: .moderate,
                        timeframe: .immediate,
                        trackable: true
                    ),
                    ActionStep(
                        order: 2,
                        title: "Improve Sleep Consistency",
                        titleCN: "改善睡眠一致性",
                        description: "Maintain consistent sleep and wake times to support HRV recovery.",
                        descriptionCN: "保持一致的睡眠和起床时间，支持HRV恢复。",
                        estimatedImpact: .significant,
                        timeframe: .shortTerm,
                        trackable: true
                    )
                ],
                relatedMetrics: [
                    MetricCorrelation(
                        metric: .heartRateVariability,
                        correlationStrength: -0.7,
                        trendDirection: analysis.trend == .declining ? .declining : .stable,
                        significance: .high
                    ),
                    MetricCorrelation(
                        metric: .restingHeartRate,
                        correlationStrength: -0.6,
                        trendDirection: .volatile,
                        significance: .medium
                    )
                ],
                predictiveElements: [
                    PredictiveElement(
                        type: .improvementPotential,
                        timeframe: .oneMonth,
                        probability: 0.75,
                        description: "With stress management techniques, HRV could improve by 15-25%.",
                        descriptionCN: "通过压力管理技巧，HRV可能提高15-25%。",
                        preventable: true
                    )
                ]
            )
            insights.append(insight)
        }
        
        // Autonomic balance insight
        if analysis.autonomicBalance != .balanced {
            let isSympatheticDominant = analysis.autonomicBalance == .sympatheticDominant
            let insight = SmartCardiacInsight(
                id: UUID(),
                timestamp: Date(),
                category: .recoveryOptimization,
                priority: .medium,
                confidence: 0.78,
                title: "Autonomic Nervous System Imbalance",
                titleCN: "自主神经系统失衡",
                summary: "Your autonomic nervous system shows \(isSympatheticDominant ? "sympathetic dominance" : "parasympathetic dominance").",
                summaryCN: "您的自主神经系统显示\(isSympatheticDominant ? "交感神经优势" : "副交感神经优势")。",
                explanation: "\(isSympatheticDominant ? "Sympathetic dominance suggests your body is in a heightened state, potentially affecting recovery." : "Parasympathetic dominance might indicate over-recovery or low arousal state.")",
                explanationCN: "\(isSympatheticDominant ? "交感神经优势表明您的身体处于兴奋状态，可能影响恢复。" : "副交感神经优势可能表明过度恢复或低唤醒状态。")",
                actionableSteps: generateAutonomicBalanceSteps(isSympatheticDominant: isSympatheticDominant),
                relatedMetrics: [
                    MetricCorrelation(
                        metric: .heartRateVariability,
                        correlationStrength: 0.8,
                        trendDirection: .stable,
                        significance: .high
                    ),
                    MetricCorrelation(
                        metric: .restingHeartRate,
                        correlationStrength: isSympatheticDominant ? 0.7 : -0.7,
                        trendDirection: .stable,
                        significance: .high
                    )
                ],
                predictiveElements: [
                    PredictiveElement(
                        type: .improvementPotential,
                        timeframe: .threeMonths,
                        probability: 0.68,
                        description: "Balance can be restored through targeted interventions.",
                        descriptionCN: "可以通过针对性干预恢复平衡。",
                        preventable: true
                    )
                ]
            )
            insights.append(insight)
        }
        
        return insights
    }
    
    private func generateFitnessInsights(profile: CardiacAnalytics.CardiacHealthProfile) async -> [SmartCardiacInsight] {
        var insights: [SmartCardiacInsight] = []
        
        // VO2 Max insights
        if let vo2Max = profile.metrics.vo2Max {
            if vo2Max < 35 {
                let insight = SmartCardiacInsight(
                    id: UUID(),
                    timestamp: Date(),
                    category: .fitnessOptimization,
                    priority: vo2Max < 25 ? .high : .medium,
                    confidence: 0.82,
                    title: "Cardiovascular Fitness Below Optimal",
                    titleCN: "心血管健康水平低于最佳",
                    summary: "Your VO₂ Max of \(String(format: "%.1f", vo2Max)) ml/kg/min suggests room for improvement.",
                    summaryCN: "您的最大摄氧量\(String(format: "%.1f", vo2Max))毫升/公斤/分钟有改善空间。",
                    explanation: "VO₂ Max is a key indicator of cardiovascular fitness. Higher values are associated with better heart health, longevity, and disease prevention.",
                    explanationCN: "最大摄氧量是心血管健康的关键指标。更高的数值与更好的心脏健康、长寿和疾病预防相关。",
                    actionableSteps: [
                        ActionStep(
                            order: 1,
                            title: "High-Intensity Interval Training",
                            titleCN: "高强度间歇训练",
                            description: "2-3 sessions per week of HIIT can significantly improve VO₂ Max.",
                            descriptionCN: "每周2-3次HIIT可显著提高最大摄氧量。",
                            estimatedImpact: .significant,
                            timeframe: .mediumTerm,
                            trackable: true
                        ),
                        ActionStep(
                            order: 2,
                            title: "Progressive Aerobic Base Building",
                            titleCN: "渐进式有氧基础建设",
                            description: "Gradually increase weekly aerobic exercise duration by 10%.",
                            descriptionCN: "每周有氧运动时间逐渐增加10%。",
                            estimatedImpact: .moderate,
                            timeframe: .longTerm,
                            trackable: true
                        )
                    ],
                    relatedMetrics: [
                        MetricCorrelation(
                            metric: .vo2Max,
                            correlationStrength: 1.0,
                            trendDirection: .stable,
                            significance: .critical
                        ),
                        MetricCorrelation(
                            metric: .activeEnergy,
                            correlationStrength: 0.65,
                            trendDirection: .stable,
                            significance: .medium
                        )
                    ],
                    predictiveElements: [
                        PredictiveElement(
                            type: .improvementPotential,
                            timeframe: .threeMonths,
                            probability: 0.85,
                            description: "With consistent training, VO₂ Max could improve by 15-20%.",
                            descriptionCN: "通过持续训练，最大摄氧量可能提高15-20%。",
                            preventable: true
                        )
                    ]
                )
                insights.append(insight)
            }
        }
        
        return insights
    }
    
    private func generateRecoveryInsights(profile: CardiacAnalytics.CardiacHealthProfile, hrvAnalysis: CardiacAnalytics.HRVAnalysis) async -> [SmartCardiacInsight] {
        var insights: [SmartCardiacInsight] = []
        
        // Heart Rate Recovery insights
        if let recovery = profile.metrics.heartRateRecovery {
            if recovery < 12 {
                let insight = SmartCardiacInsight(
                    id: UUID(),
                    timestamp: Date(),
                    category: .recoveryOptimization,
                    priority: .high,
                    confidence: 0.88,
                    title: "Poor Heart Rate Recovery Detected",
                    titleCN: "检测到心率恢复不良",
                    summary: "Your heart rate recovery of \(String(format: "%.0f", recovery)) bpm is below optimal range.",
                    summaryCN: "您的心率恢复\(String(format: "%.0f", recovery))次/分低于最佳范围。",
                    explanation: "Heart rate recovery measures how quickly your heart rate drops after exercise. Poor recovery can indicate cardiovascular issues or overtraining.",
                    explanationCN: "心率恢复测量运动后心率下降的速度。恢复不良可能表明心血管问题或过度训练。",
                    actionableSteps: [
                        ActionStep(
                            order: 1,
                            title: "Cool-down Protocol",
                            titleCN: "降温协议",
                            description: "Always include 5-10 minute active cool-down after exercise.",
                            descriptionCN: "运动后始终包括5-10分钟的主动降温。",
                            estimatedImpact: .moderate,
                            timeframe: .immediate,
                            trackable: true
                        ),
                        ActionStep(
                            order: 2,
                            title: "Recovery Monitoring",
                            titleCN: "恢复监测",
                            description: "Track heart rate recovery daily to optimize training intensity.",
                            descriptionCN: "每天跟踪心率恢复以优化训练强度。",
                            estimatedImpact: .significant,
                            timeframe: .shortTerm,
                            trackable: true
                        )
                    ],
                    relatedMetrics: [
                        MetricCorrelation(
                            metric: .heartRateRecovery,
                            correlationStrength: 1.0,
                            trendDirection: .stable,
                            significance: .critical
                        ),
                        MetricCorrelation(
                            metric: .restingHeartRate,
                            correlationStrength: -0.7,
                            trendDirection: .stable,
                            significance: .high
                        )
                    ],
                    predictiveElements: [
                        PredictiveElement(
                            type: .riskEscalation,
                            timeframe: .threeMonths,
                            probability: 0.45,
                            description: "Without intervention, cardiovascular efficiency may decline further.",
                            descriptionCN: "不采取干预措施，心血管效率可能进一步下降。",
                            preventable: true
                        )
                    ]
                )
                insights.append(insight)
            }
        }
        
        return insights
    }
    
    private func generateRiskInsights(profile: CardiacAnalytics.CardiacHealthProfile) async -> [SmartCardiacInsight] {
        var insights: [SmartCardiacInsight] = []
        
        // High-risk blood pressure
        if let systolic = profile.metrics.systolicBP, let diastolic = profile.metrics.diastolicBP {
            if systolic > 140 || diastolic > 90 {
                let insight = SmartCardiacInsight(
                    id: UUID(),
                    timestamp: Date(),
                    category: .riskPrevention,
                    priority: systolic > 160 || diastolic > 100 ? .critical : .high,
                    confidence: 0.95,
                    title: "Elevated Blood Pressure Detected",
                    titleCN: "检测到血压升高",
                    summary: "Your blood pressure (\(String(format: "%.0f", systolic))/\(String(format: "%.0f", diastolic))) is above normal range.",
                    summaryCN: "您的血压（\(String(format: "%.0f", systolic))/\(String(format: "%.0f", diastolic))）超出正常范围。",
                    explanation: "Elevated blood pressure increases risk of heart disease, stroke, and kidney problems. Early intervention is crucial.",
                    explanationCN: "血压升高增加心脏病、中风和肾脏问题的风险。早期干预至关重要。",
                    actionableSteps: [
                        ActionStep(
                            order: 1,
                            title: "Consult Healthcare Provider",
                            titleCN: "咨询医疗保健提供者",
                            description: "Schedule appointment for blood pressure evaluation and management plan.",
                            descriptionCN: "预约血压评估和管理计划。",
                            estimatedImpact: .transformative,
                            timeframe: .immediate,
                            trackable: true
                        ),
                        ActionStep(
                            order: 2,
                            title: "DASH Diet Implementation",
                            titleCN: "实施DASH饮食",
                            description: "Adopt DASH eating pattern to help lower blood pressure naturally.",
                            descriptionCN: "采用DASH饮食模式自然降低血压。",
                            estimatedImpact: .significant,
                            timeframe: .mediumTerm,
                            trackable: true
                        )
                    ],
                    relatedMetrics: [
                        MetricCorrelation(
                            metric: .bloodPressureSystolic,
                            correlationStrength: 1.0,
                            trendDirection: .stable,
                            significance: .critical
                        ),
                        MetricCorrelation(
                            metric: .bloodPressureDiastolic,
                            correlationStrength: 1.0,
                            trendDirection: .stable,
                            significance: .critical
                        )
                    ],
                    predictiveElements: [
                        PredictiveElement(
                            type: .riskEscalation,
                            timeframe: .sixMonths,
                            probability: 0.75,
                            description: "Without treatment, risk of cardiovascular events increases significantly.",
                            descriptionCN: "不治疗的话，心血管事件风险显著增加。",
                            preventable: true
                        )
                    ]
                )
                insights.append(insight)
            }
        }
        
        return insights
    }
    
    private func generatePerformanceInsights(profile: CardiacAnalytics.CardiacHealthProfile) async -> [SmartCardiacInsight] {
        var insights: [SmartCardiacInsight] = []
        
        // Performance optimization for high performers
        if profile.overallScore > 75 {
            let insight = SmartCardiacInsight(
                id: UUID(),
                timestamp: Date(),
                category: .performanceEnhancement,
                priority: .medium,
                confidence: 0.72,
                title: "Advanced Performance Optimization",
                titleCN: "高级性能优化",
                summary: "Your cardiac health is excellent. Focus on fine-tuning for peak performance.",
                summaryCN: "您的心脏健康状况极佳。专注于微调以达到巅峰表现。",
                explanation: "With a cardiac score of \(String(format: "%.1f", profile.overallScore)), you're in the top tier. Small optimizations can yield significant performance gains.",
                explanationCN: "心脏评分\(String(format: "%.1f", profile.overallScore))，您处于顶级水平。小的优化可以带来显著的性能提升。",
                actionableSteps: [
                    ActionStep(
                        order: 1,
                        title: "Periodization Training",
                        titleCN: "周期化训练",
                        description: "Implement structured training cycles to prevent plateaus and optimize adaptations.",
                        descriptionCN: "实施结构化训练周期以防止平台期并优化适应性。",
                        estimatedImpact: .moderate,
                        timeframe: .longTerm,
                        trackable: true
                    ),
                    ActionStep(
                        order: 2,
                        title: "HRV-Guided Training",
                        titleCN: "HRV指导训练",
                        description: "Use daily HRV measurements to optimize training intensity and recovery.",
                        descriptionCN: "使用每日HRV测量来优化训练强度和恢复。",
                        estimatedImpact: .significant,
                        timeframe: .shortTerm,
                        trackable: true
                    )
                ],
                relatedMetrics: [
                    MetricCorrelation(
                        metric: .heartRateVariability,
                        correlationStrength: 0.8,
                        trendDirection: .improving,
                        significance: .high
                    ),
                    MetricCorrelation(
                        metric: .vo2Max,
                        correlationStrength: 0.75,
                        trendDirection: .stable,
                        significance: .high
                    )
                ],
                predictiveElements: [
                    PredictiveElement(
                        type: .improvementPotential,
                        timeframe: .sixMonths,
                        probability: 0.65,
                        description: "Marginal gains could push your performance into elite territory.",
                        descriptionCN: "边际收益可能将您的表现推向精英水平。",
                        preventable: false
                    )
                ]
            )
            insights.append(insight)
        }
        
        return insights
    }
    
    // MARK: - Helper Functions
    
    private func generateAutonomicBalanceSteps(isSympatheticDominant: Bool) -> [ActionStep] {
        if isSympatheticDominant {
            return [
                ActionStep(
                    order: 1,
                    title: "Parasympathetic Activation",
                    titleCN: "激活副交感神经",
                    description: "Practice yoga, meditation, or gentle stretching to activate rest-and-digest response.",
                    descriptionCN: "练习瑜伽、冥想或轻柔伸展以激活休息消化反应。",
                    estimatedImpact: .moderate,
                    timeframe: .shortTerm,
                    trackable: true
                ),
                ActionStep(
                    order: 2,
                    title: "Reduce Training Intensity",
                    titleCN: "降低训练强度",
                    description: "Temporarily reduce high-intensity workouts to allow autonomic recovery.",
                    descriptionCN: "暂时减少高强度锻炼以允许自主神经恢复。",
                    estimatedImpact: .significant,
                    timeframe: .immediate,
                    trackable: true
                )
            ]
        } else {
            return [
                ActionStep(
                    order: 1,
                    title: "Gentle Activation",
                    titleCN: "温和激活",
                    description: "Incorporate light cardiovascular exercise to increase sympathetic activity.",
                    descriptionCN: "加入轻度心血管运动以增加交感神经活动。",
                    estimatedImpact: .moderate,
                    timeframe: .shortTerm,
                    trackable: true
                ),
                ActionStep(
                    order: 2,
                    title: "Cold Exposure",
                    titleCN: "寒冷暴露",
                    description: "Brief cold showers or ice baths can help balance autonomic function.",
                    descriptionCN: "短暂的冷水淋浴或冰浴可以帮助平衡自主神经功能。",
                    estimatedImpact: .moderate,
                    timeframe: .immediate,
                    trackable: true
                )
            ]
        }
    }
}