//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT

// swiftlint:disable file_length type_body_length line_length identifier_name

import Foundation
import OSLog

/// Advanced health intelligence engine for specialized health conversations
@MainActor
public final class HealthIntelligenceEngine: ObservableObject {
    public static let shared = HealthIntelligenceEngine()
    
    private let logger = Logger(subsystem: "com.s2y.app", category: "HealthIntelligence")
    private let healthService = HealthKitService.shared
    private let contextManager = ConversationContextManager.shared
    
    @Published public private(set) var lastAnalysis: HealthAnalysis?
    @Published public private(set) var currentInsights: [HealthInsight] = []
    
    private init() {}
    
    /// Generate intelligent health response with context and data analysis
    public func generateHealthResponse(for query: String) async -> HealthIntelligentResponse {
        logger.info("Generating intelligent health response for query")
        
        // Analyze the query intent and extract health context
        let queryAnalysis = await analyzeHealthQuery(query)
        
        // Gather relevant health data
        let healthData = await gatherRelevantHealthData(for: queryAnalysis)
        
        // Generate insights and recommendations
        let insights = generateHealthInsights(from: healthData, context: queryAnalysis)
        
        // Create intelligent response
        let response = createIntelligentResponse(
            query: query,
            analysis: queryAnalysis,
            data: healthData,
            insights: insights
        )
        
        // Update current state
        currentInsights = insights
        lastAnalysis = HealthAnalysis(
            queryType: queryAnalysis.primaryIntent,
            metricsAnalyzed: healthData.keys.map { $0 },
            insightsGenerated: insights.count,
            timestamp: Date()
        )
        
        return response
    }
    
    /// Analyze health query for intent and context
    private func analyzeHealthQuery(_ query: String) async -> HealthQueryAnalysis {
        let lowered = query.lowercased()
        
        // Detect primary intent
        let primaryIntent = detectPrimaryHealthIntent(lowered)
        
        // Extract metrics of interest
        let metrics = extractRelevantMetrics(lowered)
        
        // Determine time scope
        let timeScope = extractTimeScope(lowered)
        
        // Detect comparison request
        let comparisonType = detectComparisonType(lowered)
        
        return HealthQueryAnalysis(
            originalQuery: query,
            primaryIntent: primaryIntent,
            relevantMetrics: metrics,
            timeScope: timeScope,
            comparisonType: comparisonType,
            sentiment: analyzeSentiment(query)
        )
    }
    
    private func detectPrimaryHealthIntent(_ query: String) -> HealthIntent {
        // Trend analysis
        if query.contains(anyOf: ["trend", "progress", "improve", "趋势", "进展", "改善"]) {
            return .trendAnalysis
        }
        
        // Comparison
        if query.contains(anyOf: ["compare", "vs", "versus", "better", "worse", "比较", "对比"]) {
            return .comparison
        }
        
        // Current status
        if query.contains(anyOf: ["current", "now", "today", "latest", "目前", "现在", "今天", "最新"]) {
            return .currentStatus
        }
        
        // Recommendations
        if query.contains(anyOf: ["recommend", "suggest", "advice", "improve", "建议", "推荐", "改进"]) {
            return .recommendation
        }
        
        // Goal setting
        if query.contains(anyOf: ["goal", "target", "aim", "achieve", "目标", "达成"]) {
            return .goalSetting
        }
        
        // Insights and patterns
        if query.contains(anyOf: ["insight", "pattern", "correlation", "洞察", "模式", "关联"]) {
            return .insights
        }
        
        return .general
    }
    
    private func extractRelevantMetrics(_ query: String) -> [HealthKitService.MetricKind] {
        var metrics: [HealthKitService.MetricKind] = []
        
        if query.contains(anyOf: ["step", "walk", "步数", "走路"]) {
            metrics.append(.steps)
        }
        
        if query.contains(anyOf: ["heart", "pulse", "心率", "脉搏"]) {
            metrics.append(contentsOf: [.heartRateAverage, .restingHeartRate])
        }
        
        if query.contains(anyOf: ["sleep", "rest", "睡眠", "休息"]) {
            metrics.append(.sleepDurationHours)
        }
        
        if query.contains(anyOf: ["weight", "mass", "体重", "重量"]) {
            metrics.append(.bodyMass)
        }
        
        if query.contains(anyOf: ["energy", "calorie", "burn", "能量", "卡路里", "消耗"]) {
            metrics.append(.activeEnergy)
        }
        
        // If no specific metrics found, include all for general queries
        if metrics.isEmpty {
            metrics = HealthKitService.MetricKind.allCases
        }
        
        return metrics
    }
    
    private func extractTimeScope(_ query: String) -> TimeScope {
        if query.contains(anyOf: ["today", "今天"]) {
            return .today
        }
        if query.contains(anyOf: ["yesterday", "昨天"]) {
            return .yesterday
        }
        if query.contains(anyOf: ["week", "7 day", "周", "星期"]) {
            return .week
        }
        if query.contains(anyOf: ["month", "30 day", "月", "个月"]) {
            return .month
        }
        if query.contains(anyOf: ["year", "年"]) {
            return .year
        }
        
        return .week // Default to week
    }
    
    private func detectComparisonType(_ query: String) -> ComparisonType? {
        if query.contains(anyOf: ["last week", "previous", "before", "上周", "之前", "以前"]) {
            return .periodToPeriod
        }
        if query.contains(anyOf: ["average", "normal", "typical", "平均", "正常", "一般"]) {
            return .toAverage
        }
        if query.contains(anyOf: ["goal", "target", "目标"]) {
            return .toGoal
        }
        
        return nil
    }
    
    private func analyzeSentiment(_ query: String) -> Sentiment {
        let lowered = query.lowercased()
        
        let positiveWords = ["good", "great", "excellent", "improve", "better", "好", "很好", "优秀", "改善", "更好"]
        let negativeWords = ["bad", "worse", "terrible", "decline", "poor", "不好", "更差", "糟糕", "下降", "差"]
        let concernWords = ["worried", "concern", "problem", "issue", "担心", "问题", "困扰"]
        
        if positiveWords.contains(where: { lowered.contains($0) }) {
            return .positive
        }
        if negativeWords.contains(where: { lowered.contains($0) }) {
            return .negative
        }
        if concernWords.contains(where: { lowered.contains($0) }) {
            return .concerned
        }
        
        return .neutral
    }
    
    private func gatherRelevantHealthData(for analysis: HealthQueryAnalysis) async -> [HealthKitService.MetricKind: HealthDataSummary] {
        var healthData: [HealthKitService.MetricKind: HealthDataSummary] = [:]
        
        for metric in analysis.relevantMetrics {
            do {
                let days = analysis.timeScope.days
                let trend = try await healthService.trend(kind: metric, days: days)
                let comparison = try await healthService.compare(kind: metric, windowDays: days)
                
                let summary = HealthDataSummary(
                    metric: metric,
                    currentValue: trend.points.last?.value ?? 0,
                    averageValue: trend.average,
                    changeRate: trend.changeRate,
                    comparisonToPrevious: comparison.deltaRate,
                    trend: trend,
                    assessment: assessHealthValue(metric: metric, value: trend.average)
                )
                
                healthData[metric] = summary
                
                // Update context manager with latest data
                contextManager.updateHealthContext(
                    metric: metric,
                    value: metric.formatValue(summary.currentValue)
                )
                
            } catch {
                logger.error("Failed to gather health data for \(metric.rawValue): \(error)")
            }
        }
        
        return healthData
    }
    
    private func assessHealthValue(metric: HealthKitService.MetricKind, value: Double) -> HealthAssessment {
        if let isNormal = HealthMetricsDictionary.isNormalRange(value: value, for: metric) {
            return isNormal ? .normal : .outOfRange
        }
        return .unknown
    }
    
    private func generateHealthInsights(
        from healthData: [HealthKitService.MetricKind: HealthDataSummary],
        context: HealthQueryAnalysis
    ) -> [HealthInsight] {
        var insights: [HealthInsight] = []
        
        // Generate metric-specific insights
        for (metric, data) in healthData {
            insights.append(contentsOf: generateMetricInsights(metric: metric, data: data))
        }
        
        // Generate cross-metric insights
        insights.append(contentsOf: generateCrossMetricInsights(from: healthData))
        
        // Generate contextual insights based on query intent
        insights.append(contentsOf: generateContextualInsights(context: context, data: healthData))
        
        // Sort by importance and relevance
        return insights.sorted { $0.importance > $1.importance }.prefix(5).map { $0 }
    }
    
    private func generateMetricInsights(metric: HealthKitService.MetricKind, data: HealthDataSummary) -> [HealthInsight] {
        var insights: [HealthInsight] = []
        
        // Trend insights
        if abs(data.changeRate) > 0.1 {
            let direction = data.changeRate > 0 ? "increasing" : "decreasing"
            let directionCN = data.changeRate > 0 ? "增长" : "下降"
            
            insights.append(HealthInsight(
                title: "\(metric.displayName) is \(direction)",
                titleCN: "\(metric.displayName)\(directionCN)趋势",
                description: "Your \(metric.displayName.lowercased()) has \(direction) by \(String(format: "%.1f", abs(data.changeRate * 100)))% recently",
                descriptionCN: "您的\(metric.displayName)最近\(directionCN)了\(String(format: "%.1f", abs(data.changeRate * 100)))%",
                type: .trend,
                importance: 0.8,
                metric: metric
            ))
        }
        
        // Assessment insights
        if data.assessment == .outOfRange {
            insights.append(HealthInsight(
                title: "\(metric.displayName) needs attention",
                titleCN: "\(metric.displayName)需要关注",
                description: "Your recent \(metric.displayName.lowercased()) is outside the typical healthy range",
                descriptionCN: "您最近的\(metric.displayName)超出了健康范围",
                type: .alert,
                importance: 0.9,
                metric: metric
            ))
        }
        
        return insights
    }
    
    private func generateCrossMetricInsights(from healthData: [HealthKitService.MetricKind: HealthDataSummary]) -> [HealthInsight] {
        var insights: [HealthInsight] = []
        
        // Activity correlation insights
        if let steps = healthData[.steps], let energy = healthData[.activeEnergy] {
            let activityCorrelation = calculateCorrelation(steps.trend.points, energy.trend.points)
            if activityCorrelation > 0.7 {
                insights.append(HealthInsight(
                    title: "Strong activity pattern",
                    titleCN: "活动模式良好",
                    description: "Your step count and energy burn are well correlated, showing consistent activity levels",
                    descriptionCN: "您的步数和能量消耗关联性很好，显示了稳定的活动水平",
                    type: .correlation,
                    importance: 0.7
                ))
            }
        }
        
        // Sleep and heart rate insights
        if let sleep = healthData[.sleepDurationHours], let restingHR = healthData[.restingHeartRate] {
            if sleep.averageValue < 7 && restingHR.averageValue > 70 {
                insights.append(HealthInsight(
                    title: "Sleep may affect heart health",
                    titleCN: "睡眠可能影响心脏健康",
                    description: "Your shorter sleep duration might be contributing to elevated resting heart rate",
                    descriptionCN: "您的睡眠时间较短可能导致静息心率偏高",
                    type: .correlation,
                    importance: 0.8
                ))
            }
        }
        
        return insights
    }
    
    private func generateContextualInsights(
        context: HealthQueryAnalysis,
        data: [HealthKitService.MetricKind: HealthDataSummary]
    ) -> [HealthInsight] {
        var insights: [HealthInsight] = []
        
        // Intent-specific insights
        switch context.primaryIntent {
        case .recommendation:
            insights.append(contentsOf: generateRecommendationInsights(from: data))
        case .goalSetting:
            insights.append(contentsOf: generateGoalInsights(from: data))
        case .trendAnalysis:
            insights.append(contentsOf: generateProgressInsights(from: data))
        default:
            break
        }
        
        return insights
    }
    
    private func generateRecommendationInsights(from data: [HealthKitService.MetricKind: HealthDataSummary]) -> [HealthInsight] {
        var insights: [HealthInsight] = []
        
        // Find the metric that needs most improvement
        let improvementNeeded = data.values.filter { $0.assessment == .outOfRange || $0.changeRate < -0.1 }
        if let needsImprovement = improvementNeeded.first {
            insights.append(HealthInsight(
                title: "Focus on \(needsImprovement.metric.displayName)",
                titleCN: "重点关注\(needsImprovement.metric.displayName)",
                description: "This metric could benefit from targeted improvement efforts",
                descriptionCN: "这个指标可以通过针对性的改进获得提升",
                type: .recommendation,
                importance: 0.9,
                metric: needsImprovement.metric
            ))
        }
        
        return insights
    }
    
    private func generateGoalInsights(from data: [HealthKitService.MetricKind: HealthDataSummary]) -> [HealthInsight] {
        var insights: [HealthInsight] = []
        
        // Suggest realistic goals based on current performance
        for (metric, summary) in data {
            let currentAvg = summary.averageValue
            let suggestedGoal = calculateRealisticGoal(for: metric, currentValue: currentAvg)
            
            insights.append(HealthInsight(
                title: "Suggested \(metric.displayName) goal",
                titleCN: "建议的\(metric.displayName)目标",
                description: "Based on your current level, aim for \(metric.formatValue(suggestedGoal))",
                descriptionCN: "基于您当前的水平，建议目标为\(metric.formatValue(suggestedGoal))",
                type: .goal,
                importance: 0.7,
                metric: metric
            ))
        }
        
        return insights
    }
    
    private func generateProgressInsights(from data: [HealthKitService.MetricKind: HealthDataSummary]) -> [HealthInsight] {
        var insights: [HealthInsight] = []
        
        // Highlight most improved metric
        let sortedByImprovement = data.values.sorted { $0.changeRate > $1.changeRate }
        if let mostImproved = sortedByImprovement.first, mostImproved.changeRate > 0.05 {
            insights.append(HealthInsight(
                title: "Great progress in \(mostImproved.metric.displayName)",
                titleCN: "\(mostImproved.metric.displayName)进展良好",
                description: "You've made significant improvement in this area",
                descriptionCN: "您在这个方面取得了显著的进步",
                type: .achievement,
                importance: 0.8,
                metric: mostImproved.metric
            ))
        }
        
        return insights
    }
    
    private func createIntelligentResponse(
        query: String,
        analysis: HealthQueryAnalysis,
        data: [HealthKitService.MetricKind: HealthDataSummary],
        insights: [HealthInsight]
    ) -> HealthIntelligentResponse {
        // Generate personalized response based on analysis
        let responseText = generateResponseText(analysis: analysis, data: data, insights: insights)
        
        // Create structured data for UI
        let structuredData = HealthStructuredData(
            summary: data,
            insights: insights,
            recommendations: generateRecommendations(from: insights),
            followUpQuestions: generateFollowUpQuestions(analysis: analysis, data: data)
        )
        
        return HealthIntelligentResponse(
            query: query,
            responseText: responseText,
            structuredData: structuredData,
            confidence: calculateConfidence(data: data),
            processingTime: Date()
        )
    }
    
    private func generateResponseText(
        analysis: HealthQueryAnalysis,
        data: [HealthKitService.MetricKind: HealthDataSummary],
        insights: [HealthInsight]
    ) -> String {
        var response = ""
        
        // Add contextual greeting based on sentiment
        switch analysis.sentiment {
        case .positive:
            response += "I'm glad you're staying engaged with your health! "
        case .concerned:
            response += "I understand your concern. Let me help you understand your health data. "
        default:
            response += "Here's what I found about your health data: "
        }
        
        // Add data summary
        if !data.isEmpty {
            response += "Looking at your \(analysis.timeScope.description), "
            
            let improvements = data.values.filter { $0.changeRate > 0.05 }
            let declines = data.values.filter { $0.changeRate < -0.05 }
            
            if !improvements.isEmpty {
                let improved = improvements.map { $0.metric.displayName }.joined(separator: " and ")
                response += "your \(improved) has improved. "
            }
            
            if !declines.isEmpty {
                let declined = declines.map { $0.metric.displayName }.joined(separator: " and ")
                response += "Your \(declined) shows some decline that we should address. "
            }
        }
        
        // Add top insights
        if !insights.isEmpty {
            response += "\n\nKey insights: "
            for insight in insights.prefix(3) {
                response += "• \(insight.description) "
            }
        }
        
        return response
    }
    
    private func generateRecommendations(from insights: [HealthInsight]) -> [String] {
        insights.compactMap { insight in
            if insight.type == .recommendation || insight.type == .alert {
                return generateActionableRecommendation(for: insight)
            }
            return nil
        }
    }
    
    private func generateActionableRecommendation(for insight: HealthInsight) -> String {
        guard let metric = insight.metric else { return insight.description }
        
        switch metric {
        case .steps:
            return "Try taking short walks throughout the day or using stairs instead of elevators"
        case .sleepDurationHours:
            return "Aim for consistent bedtime and limit screen time before sleep"
        case .heartRateAverage, .restingHeartRate:
            return "Consider regular cardio exercise and stress management techniques"
        case .activeEnergy:
            return "Incorporate more physical activities like dancing, gardening, or sports"
        case .bodyMass:
            return "Focus on balanced nutrition and gradual, sustainable changes"
        }
    }
    
    private func generateFollowUpQuestions(
        analysis: HealthQueryAnalysis,
        data: [HealthKitService.MetricKind: HealthDataSummary]
    ) -> [String] {
        var questions: [String] = []
        
        switch analysis.primaryIntent {
        case .trendAnalysis:
            questions.append("Would you like to see how this compares to previous months?")
            questions.append("Are there any specific patterns you've noticed?")
        case .recommendation:
            questions.append("Would you like specific exercise recommendations?")
            questions.append("Should we set up some health goals together?")
        case .currentStatus:
            questions.append("Would you like to track any of these metrics more closely?")
            questions.append("Are you curious about how these compare to healthy ranges?")
        default:
            questions.append("Is there a specific health goal you're working towards?")
            questions.append("Would you like recommendations for improvement?")
        }
        
        return questions
    }
    
    private func calculateConfidence(data: [HealthKitService.MetricKind: HealthDataSummary]) -> Double {
        // Base confidence on data availability and recency
        let dataPoints = data.values.map { $0.trend.points.count }.reduce(0, +)
        let maxPossiblePoints = data.count * 7 // Assume 7 days of data per metric
        
        return min(1.0, Double(dataPoints) / Double(maxPossiblePoints))
    }
    
    private func calculateCorrelation(_ series1: [HealthKitService.DailyMetric], _ series2: [HealthKitService.DailyMetric]) -> Double {
        // Simple correlation calculation
        let values1 = series1.map { $0.value }
        let values2 = series2.map { $0.value }
        
        guard values1.count == values2.count, !values1.isEmpty else { return 0 }
        
        let mean1 = values1.reduce(0, +) / Double(values1.count)
        let mean2 = values2.reduce(0, +) / Double(values2.count)
        
        let numerator = zip(values1, values2).map { (x, y) in
            (x - mean1) * (y - mean2)
        }.reduce(0, +)
        
        let denominator1 = values1.map { pow($0 - mean1, 2) }.reduce(0, +)
        let denominator2 = values2.map { pow($0 - mean2, 2) }.reduce(0, +)
        
        let denominator = sqrt(denominator1 * denominator2)
        
        return denominator > 0 ? numerator / denominator : 0
    }
    
    private func calculateRealisticGoal(for metric: HealthKitService.MetricKind, currentValue: Double) -> Double {
        // Calculate realistic improvement goal (5-15% increase)
        let improvementFactor = 1.1
        
        switch metric {
        case .steps:
            return max(8000, currentValue * improvementFactor)
        case .sleepDurationHours:
            return min(9, max(7, currentValue * 1.05))
        case .activeEnergy:
            return currentValue * improvementFactor
        case .heartRateAverage, .restingHeartRate:
            return currentValue * 0.95 // Lower is better for heart rate
        case .bodyMass:
            return currentValue // Weight goals need more context
        }
    }
}

// MARK: - Supporting Types

public struct HealthQueryAnalysis {
    let originalQuery: String
    let primaryIntent: HealthIntent
    let relevantMetrics: [HealthKitService.MetricKind]
    let timeScope: TimeScope
    let comparisonType: ComparisonType?
    let sentiment: Sentiment
}

public enum HealthIntent {
    case trendAnalysis
    case comparison
    case currentStatus
    case recommendation
    case goalSetting
    case insights
    case general
}

public enum TimeScope {
    case today
    case yesterday
    case week
    case month
    case year
    
    var days: Int {
        switch self {
        case .today: return 1
        case .yesterday: return 1
        case .week: return 7
        case .month: return 30
        case .year: return 365
        }
    }
    
    var description: String {
        switch self {
        case .today: return "today"
        case .yesterday: return "yesterday"
        case .week: return "past week"
        case .month: return "past month"
        case .year: return "past year"
        }
    }
}

public enum ComparisonType {
    case periodToPeriod
    case toAverage
    case toGoal
}

public enum Sentiment {
    case positive
    case negative
    case concerned
    case neutral
}

public struct HealthDataSummary {
    let metric: HealthKitService.MetricKind
    let currentValue: Double
    let averageValue: Double
    let changeRate: Double
    let comparisonToPrevious: Double
    let trend: HealthKitService.Trend
    let assessment: HealthAssessment
}

public enum HealthAssessment {
    case normal
    case outOfRange
    case unknown
}

public struct HealthInsight: Identifiable {
    public let id = UUID()
    let title: String
    let titleCN: String
    let description: String
    let descriptionCN: String
    let type: InsightType
    let importance: Double // 0.0 to 1.0
    let metric: HealthKitService.MetricKind?
    
    init(title: String, titleCN: String, description: String, descriptionCN: String, type: InsightType, importance: Double, metric: HealthKitService.MetricKind? = nil) {
        self.title = title
        self.titleCN = titleCN
        self.description = description
        self.descriptionCN = descriptionCN
        self.type = type
        self.importance = importance
        self.metric = metric
    }
}

public enum InsightType {
    case trend
    case alert
    case achievement
    case recommendation
    case correlation
    case goal
}

public struct HealthStructuredData {
    let summary: [HealthKitService.MetricKind: HealthDataSummary]
    let insights: [HealthInsight]
    let recommendations: [String]
    let followUpQuestions: [String]
}

public struct HealthIntelligentResponse {
    let query: String
    let responseText: String
    let structuredData: HealthStructuredData
    let confidence: Double
    let processingTime: Date
}

public struct HealthAnalysis {
    let queryType: HealthIntent
    let metricsAnalyzed: [HealthKitService.MetricKind]
    let insightsGenerated: Int
    let timestamp: Date
}

// MARK: - Extensions

extension String {
    func contains(anyOf strings: [String]) -> Bool {
        return strings.contains { self.contains($0) }
    }
}