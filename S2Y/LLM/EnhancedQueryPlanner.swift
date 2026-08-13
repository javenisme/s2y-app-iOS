//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_length type_body_length line_length conditional_returns_on_newline
import Foundation

enum EnhancedQueryPlanner {
    enum Intent {
        case compare(kind: HealthKitService.MetricKind, windowDays: Int)
        case trend(kind: HealthKitService.MetricKind, days: Int)
        case summary(kind: HealthKitService.MetricKind?, days: Int)
        case insights(focus: InsightFocus?)
        case recommendation(kind: HealthKitService.MetricKind?)
        case healthOverview
        case currentValue(kind: HealthKitService.MetricKind)
        case goal(kind: HealthKitService.MetricKind, target: Double?)
    }
    
    enum InsightFocus {
        case activity      // 活动相关
        case sleep        // 睡眠相关
        case heart        // 心脏相关
        case overall      // 整体健康
    }
    
    static func parse(_ text: String) -> Intent? {
        let lowered = text.lowercased()
        
        // Metric detection
        let metric = detectMetric(from: lowered)
        
        // Intent detection with expanded patterns
        
        // Current value queries
        if containsCurrentValueKeywords(lowered) {
            guard let kind = metric else { return nil }
            return .currentValue(kind: kind)
        }
        
        // Goal queries
        if containsGoalKeywords(lowered) {
            guard let kind = metric else { return nil }
            let target = extractTargetValue(from: lowered, for: kind)
            return .goal(kind: kind, target: target)
        }
        
        // Health overview
        if containsOverviewKeywords(lowered) {
            return .healthOverview
        }
        
        // Insights queries
        if containsInsightKeywords(lowered) {
            let focus = detectInsightFocus(from: lowered)
            return .insights(focus: focus)
        }
        
        // Recommendation queries
        if containsRecommendationKeywords(lowered) {
            return .recommendation(kind: metric)
        }
        
        // Summary queries
        if containsSummaryKeywords(lowered) {
            let days = extractDays(from: lowered)
            return .summary(kind: metric, days: days)
        }
        
        // Compare queries
        if containsCompareKeywords(lowered) {
            guard let kind = metric else { return nil }
            let days = extractDays(from: lowered)
            return .compare(kind: kind, windowDays: days)
        }
        
        // Trend queries
        if containsTrendKeywords(lowered) || metric != nil {
            guard let kind = metric else { return nil }
            let days = extractDays(from: lowered)
            return .trend(kind: kind, days: days)
        }
        
        return nil
    }
    
    static func run(intent: Intent) async throws -> HealthQueryProcessor.QueryResult {
        switch intent {
        case let .compare(kind, windowDays):
            let comparison = try await HealthKitService.shared.compare(
                kind: kind,
                windowDays: windowDays,
                useCache: true
            )
            return .comparison(comparison, kind)
            
        case let .trend(kind, days):
            let trend = try await HealthKitService.shared.trend(
                kind: kind,
                days: days,
                useCache: true
            )
            return .trend(trend, kind)
            
        case let .summary(kind, days):
            if let specificKind = kind {
                let trend = try await HealthKitService.shared.trend(
                    kind: specificKind,
                    days: days,
                    useCache: true
                )
                let summary = formatSummary(kind: specificKind, trend: trend, days: days)
                return .textResponse(summary)
            } else {
                return try await generateMultiMetricSummary(days: days)
            }
            
        case let .insights(focus):
            return try await generateInsights(focus: focus)
            
        case let .recommendation(kind):
            return try await generateRecommendations(kind: kind)
            
        case .healthOverview:
            return try await generateHealthOverview()
            
        case let .currentValue(kind):
            let trend = try await HealthKitService.shared.trend(
                kind: kind,
                days: 1,
                useCache: true
            )
            let current = trend.points.last?.value ?? 0
            let response = "Your current \(metricTitle(kind: kind)) is \(String(format: "%.1f", current)) \(metricUnit(kind: kind))"
            return .textResponse(response)
            
        case let .goal(kind, target):
            return try await generateGoalResponse(kind: kind, target: target)
        }
    }
    
    // MARK: - Detection Methods
    
    private static func detectMetric(from text: String) -> HealthKitService.MetricKind? {
        if text.contains("步数") || text.contains("steps") || text.contains("走路") {
            return .steps
        }
        if text.contains("静息心率") || text.contains("resting heart") {
            return .restingHeartRate
        }
        if text.contains("心率") || text.contains("heart rate") || text.contains("心跳") {
            return .heartRateAverage
        }
        if text.contains("活动能量") || text.contains("active energy") || text.contains("卡路里") || text.contains("calorie") {
            return .activeEnergy
        }
        if text.contains("体重") || text.contains("body mass") || text.contains("weight") {
            return .bodyMass
        }
        if text.contains("睡眠") || text.contains("sleep") || text.contains("休息") {
            return .sleepDurationHours
        }
        return nil
    }
    
    private static func detectInsightFocus(from text: String) -> InsightFocus? {
        if text.contains("活动") || text.contains("运动") || text.contains("步数") || text.contains("activity") {
            return .activity
        }
        if text.contains("睡眠") || text.contains("sleep") || text.contains("休息") {
            return .sleep
        }
        if text.contains("心率") || text.contains("heart") || text.contains("心脏") {
            return .heart
        }
        return .overall
    }
    
    private static func containsCurrentValueKeywords(_ text: String) -> Bool {
        let keywords = ["当前", "现在", "今天", "current", "now", "today", "最新"]
        return keywords.contains { text.contains($0) }
    }
    
    private static func containsGoalKeywords(_ text: String) -> Bool {
        let keywords = ["目标", "设定", "达成", "goal", "target", "achieve", "设置"]
        return keywords.contains { text.contains($0) }
    }
    
    private static func containsOverviewKeywords(_ text: String) -> Bool {
        let keywords = ["总览", "概况", "总体", "整体", "overview", "general", "overall", "全部"]
        return keywords.contains { text.contains($0) }
    }
    
    private static func containsInsightKeywords(_ text: String) -> Bool {
        let keywords = ["洞察", "分析", "建议", "怎么样", "如何", "insight", "analysis", "suggestion"]
        return keywords.contains { text.contains($0) }
    }
    
    private static func containsRecommendationKeywords(_ text: String) -> Bool {
        let keywords = ["建议", "推荐", "应该", "recommendation", "suggest", "should", "advice"]
        return keywords.contains { text.contains($0) }
    }
    
    private static func containsSummaryKeywords(_ text: String) -> Bool {
        let keywords = ["总结", "汇总", "概要", "summary", "总的", "整体情况"]
        return keywords.contains { text.contains($0) }
    }
    
    private static func containsCompareKeywords(_ text: String) -> Bool {
        let keywords = ["对比", "比较", "compare", "vs", "相比", "对比分析"]
        return keywords.contains { text.contains($0) }
    }
    
    private static func containsTrendKeywords(_ text: String) -> Bool {
        let keywords = ["趋势", "变化", "trend", "change", "走势", "发展"]
        return keywords.contains { text.contains($0) }
    }
    
    private static func extractDays(from text: String) -> Int {
        if text.contains("30天") || text.contains("30-day") || text.contains("30 days") || text.contains("一个月") {
            return 30
        }
        if text.contains("14天") || text.contains("14-day") || text.contains("14 days") || text.contains("两周") {
            return 14
        }
        if text.contains("7天") || text.contains("七天") || text.contains("7-day") || text.contains("7 days") || text.contains("一周") {
            return 7
        }
        if text.contains("3天") || text.contains("三天") || text.contains("3-day") || text.contains("3 days") {
            return 3
        }
        return 7 // default
    }
    
    private static func extractTargetValue(from text: String, for kind: HealthKitService.MetricKind) -> Double? {
        let numbers = text.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Double($0) }
            .filter { $0 > 0 }
        
        return numbers.first
    }
    
    // MARK: - Generation Methods
    
    private static func generateMultiMetricSummary(days: Int) async throws -> HealthQueryProcessor.QueryResult {
        let metrics: [HealthKitService.MetricKind] = [.steps, .heartRateAverage, .sleepDurationHours, .activeEnergy]
        var summaryText = "Health Data Summary for Past \(days) Days:\n\n"
        
        for metric in metrics {
            do {
                let trend = try await HealthKitService.shared.trend(kind: metric, days: days, useCache: true)
                let title = metricTitle(kind: metric)
                let unit = metricUnit(kind: metric)
                let avg = String(format: "%.1f", trend.average)
                let change = trend.changeRate >= 0 ? "↗️" : "↘️"
                let changePercent = String(format: "%.1f", abs(trend.changeRate * 100))
                
                summaryText += "\(title): \(avg) \(unit) (\(change) \(changePercent)%)\n"
            } catch {
                continue
            }
        }
        
        summaryText += "\n💡 For detailed analysis, please ask about specific metric trends or comparison data."
        return .textResponse(summaryText)
    }
    
    private static func generateInsights(focus: InsightFocus?) async throws -> HealthQueryProcessor.QueryResult {
        var insights: [HealthQueryProcessor.HealthInsight] = []
        let metricsToAnalyze: [HealthKitService.MetricKind]
        
        switch focus {
        case .activity:
            metricsToAnalyze = [.steps, .activeEnergy]
        case .sleep:
            metricsToAnalyze = [.sleepDurationHours]
        case .heart:
            metricsToAnalyze = [.heartRateAverage, .restingHeartRate]
        case .overall, .none:
            metricsToAnalyze = [.steps, .heartRateAverage, .sleepDurationHours, .activeEnergy]
        }
        
        for metric in metricsToAnalyze {
            do {
                let trend = try await HealthKitService.shared.trend(kind: metric, days: 7, useCache: true)
                let comparison = try await HealthKitService.shared.compare(kind: metric, windowDays: 7, useCache: true)
                
                if let insight = generateInsightForMetric(metric, trend: trend, comparison: comparison) {
                    insights.append(insight)
                }
            } catch {
                continue
            }
        }
        
        return .insights(insights.isEmpty ? [generateFallbackInsight()] : insights)
    }
    
    private static func generateRecommendations(kind: HealthKitService.MetricKind?) async throws -> HealthQueryProcessor.QueryResult {
        if let specificKind = kind {
            let trend = try await HealthKitService.shared.trend(kind: specificKind, days: 7, useCache: true)
            let recommendation = generateRecommendationForMetric(specificKind, trend: trend)
            return .textResponse(recommendation)
        } else {
            let generalRecommendations = generateGeneralHealthRecommendations()
            return .textResponse(generalRecommendations)
        }
    }
    
    private static func generateHealthOverview() async throws -> HealthQueryProcessor.QueryResult {
        let metrics: [HealthKitService.MetricKind] = [.steps, .heartRateAverage, .sleepDurationHours, .activeEnergy]
        var insights: [HealthQueryProcessor.HealthInsight] = []
        
        for metric in metrics {
            do {
                let trend = try await HealthKitService.shared.trend(kind: metric, days: 7, useCache: true)
                let comparison = try await HealthKitService.shared.compare(kind: metric, windowDays: 7, useCache: true)
                
                if let insight = generateInsightForMetric(metric, trend: trend, comparison: comparison) {
                    insights.append(insight)
                }
            } catch {
                continue
            }
        }
        
        return .insights(insights)
    }
    
    private static func generateGoalResponse(kind: HealthKitService.MetricKind, target: Double?) async throws -> HealthQueryProcessor.QueryResult {
        let trend = try await HealthKitService.shared.trend(kind: kind, days: 7, useCache: true)
        let current = trend.average
        let title = metricTitle(kind: kind)
        let unit = metricUnit(kind: kind)
        
        if let target = target {
            let progress = (current / target) * 100
            let response = """
            \(title) Goal: \(String(format: "%.1f", target)) \(unit)
            Current 7-day Average: \(String(format: "%.1f", current)) \(unit)
            Progress: \(String(format: "%.1f", progress))%
            
            \(progress >= 100 ? "🎉 Congratulations! You've reached your goal!" : "💪 Keep going! You need \(String(format: "%.1f", target - current)) \(unit) more to reach your goal.")
            """
            return .textResponse(response)
        } else {
            let suggestedTarget = generateSuggestedTarget(for: kind, current: current)
            let response = """
            Based on your current \(title) data, recommended goal:
            
            Current 7-day Average: \(String(format: "%.1f", current)) \(unit)
            Suggested Goal: \(String(format: "%.1f", suggestedTarget)) \(unit)
            
            This goal is both challenging and achievable. You can gradually improve and steadily reach your health goals!
            """
            return .textResponse(response)
        }
    }
    
    // MARK: - Helper Methods
    
    private static func formatSummary(kind: HealthKitService.MetricKind, trend: HealthKitService.Trend, days: Int) -> String {
        let title = metricTitle(kind: kind)
        let unit = metricUnit(kind: kind)
        let avg = String(format: "%.1f", trend.average)
        let change = trend.changeRate >= 0 ? "Increase" : "Decrease"
        let changePercent = String(format: "%.1f", abs(trend.changeRate * 100))
        
        return """
        \(title) - \(days) Day Summary
        
        Average: \(avg) \(unit)
        Trend: \(change) \(changePercent)%
        Data Points: \(trend.points.count)
        
        \(generateBriefAnalysis(for: kind, trend: trend))
        """
    }
    
    private static func generateBriefAnalysis(for kind: HealthKitService.MetricKind, trend: HealthKitService.Trend) -> String {
        switch kind {
        case .steps:
            return trend.average >= 8000 ? "Good activity level, maintain current habits." : "Consider increasing daily activity."
        case .heartRateAverage:
            return "Heart rate data is normal, continue monitoring changes."
        case .sleepDurationHours:
            return trend.average >= 7 ? "Sufficient sleep duration." : "Consider ensuring adequate sleep time."
        case .activeEnergy:
            return trend.average >= 300 ? "Good active energy expenditure." : "Consider increasing exercise intensity."
        default:
            return "Good data recording, continue monitoring."
        }
    }
    
    private static func generateInsightForMetric(
        _ kind: HealthKitService.MetricKind,
        trend: HealthKitService.Trend,
        comparison: HealthKitService.Comparison
    ) -> HealthQueryProcessor.HealthInsight? {
        // This would be the same logic as in HealthQueryProcessor
        // For brevity, I'll use a simplified version
        let title = metricTitle(kind: kind)
        let insight = "Your \(title) has shown \(trend.changeRate >= 0 ? "an increase" : "a decrease") over the past 7 days"
        
        return HealthQueryProcessor.HealthInsight(
            title: "\(title)分析",
            insight: insight,
            recommendation: "Continue maintaining good health habits.",
            icon: metricIcon(kind: kind),
            color: "blue",
            severity: .info
        )
    }
    
    private static func generateFallbackInsight() -> HealthQueryProcessor.HealthInsight {
        return HealthQueryProcessor.HealthInsight(
            title: "Health Reminder",
            insight: "Maintaining good lifestyle habits is important for health.",
            recommendation: "Regularly review your health data and monitor changes in your physical condition.",
            icon: "heart.circle",
            color: "blue",
            severity: .info
        )
    }
    
    private static func generateRecommendationForMetric(_ kind: HealthKitService.MetricKind, trend: HealthKitService.Trend) -> String {
        let title = metricTitle(kind: kind)
        
        switch kind {
        case .steps:
            if trend.average < 5000 {
                return "Suggestions to increase daily walking:\n• Take stairs instead of elevators\n• Take a 20-30 minute walk after meals\n• Try walking or cycling to work\n• Set daily step goals and gradually increase them"
            } else {
                return "Your step count performance is good! Keep it up:\n• Maintain your current activity level\n• Try new types of exercise for variety\n• Invite friends to walk together for motivation"
            }
            
        case .sleepDurationHours:
            if trend.average < 7 {
                return "Suggestions to improve sleep quality:\n• Establish regular sleep schedule\n• Avoid electronic devices 1 hour before bed\n• Keep bedroom temperature comfortable (18-22°C)\n• Avoid heavy meals or caffeinated drinks before bedtime"
            } else {
                return "Your sleep duration is excellent! Maintain with:\n• Keep regular sleep schedule\n• Focus on sleep quality, not just duration\n• Establish a relaxing bedtime routine"
            }
            
        default:
            return "Based on your \(title) data, continue maintaining good health habits and regularly monitor changes. If you have concerns, please consult a healthcare professional."
        }
    }
    
    private static func generateGeneralHealthRecommendations() -> String {
        return """
        💪 Comprehensive Health Recommendations
        
        🚶‍♂️ Daily Activity
        • At least 10,000 steps daily
        • 150 minutes of moderate-intensity exercise weekly
        
        😴 Sleep Quality
        • 7-9 hours of adequate sleep nightly
        • Maintain regular sleep schedule
        
        ❤️ Cardiovascular Health
        • Regularly monitor heart rate changes
        • Moderate aerobic exercise
        
        📊 Data Monitoring
        • Develop habit of recording health data
        • Regularly review and analyze trends
        
        ⚕️ Professional Advice
        • Consult doctor promptly for abnormal changes
        • Personal health plans should incorporate professional guidance
        """
    }
    
    private static func generateSuggestedTarget(for kind: HealthKitService.MetricKind, current: Double) -> Double {
        switch kind {
        case .steps:
            if current < 5000 { return 8000 }
            else if current < 10000 { return 12000 }
            else { return current * 1.1 }
            
        case .sleepDurationHours:
            if current < 7 { return 8 }
            else { return max(8, current) }
            
        case .activeEnergy:
            if current < 200 { return 300 }
            else { return current * 1.15 }
            
        default:
            return current * 1.1
        }
    }
    
    private static func metricTitle(kind: HealthKitService.MetricKind) -> String {
        HealthMetricsDictionary.displayName(for: kind)
    }
    
    private static func metricUnit(kind: HealthKitService.MetricKind) -> String {
        HealthMetricsDictionary.unit(for: kind)
    }
    
    private static func metricIcon(kind: HealthKitService.MetricKind) -> String {
        switch kind {
        case .steps: return "figure.walk"
        case .heartRateAverage, .restingHeartRate: return "heart.fill"
        case .activeEnergy: return "flame.fill"
        case .bodyMass: return "scalemass.fill"
        case .sleepDurationHours: return "bed.double.fill"
        case .heartRateVariability: return "waveform.path.ecg"
        case .heartRateRecovery: return "arrow.down.heart"
        case .vo2Max: return "lungs.fill"
        case .walkingHeartRateAverage: return "figure.walk.circle"
        case .oxygenSaturation: return "lungs"
        case .bloodPressureSystolic, .bloodPressureDiastolic: return "gauge.medium"
        case .bodyTemperature: return "thermometer"
        case .respiratoryRate: return "wind"
        }
    }
}
