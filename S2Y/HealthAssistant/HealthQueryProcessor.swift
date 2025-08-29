//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

/// Enhanced query processor that returns structured data for visualization
enum HealthQueryProcessor {
    enum QueryResult {
        case trend(HealthKitService.Trend, HealthKitService.MetricKind)
        case comparison(HealthKitService.Comparison, HealthKitService.MetricKind)
        case textResponse(String)
        case insights([HealthInsight])
    }
    
    struct HealthInsight {
        let title: String
        let insight: String
        let recommendation: String?
        let icon: String
        let color: String // Color name
        let severity: Severity
        
        enum Severity {
            case info, warning, critical
        }
    }
    
    static func processQuery(_ query: String) async throws -> QueryResult {
        // Use enhanced query planner for better processing
        if let intent = EnhancedQueryPlanner.parse(query) {
            return try await EnhancedQueryPlanner.run(intent: intent)
        }
        
        // Fall back to basic query processing
        if let intent = QueryPlanner.parse(query) {
            return try await processStructuredQuery(intent)
        }
        
        // Check for insight-related queries
        if containsInsightKeywords(query) {
            return try await generateHealthInsights(query)
        }
        
        // Final fallback
        return .textResponse("I can help you analyze your health data. Try asking about your step trends, heart rate comparisons, or health insights.")
    }
    
    private static func processStructuredQuery(_ intent: QueryPlanner.Intent) async throws -> QueryResult {
        try await HealthKitService.shared.requestAuthorization()
        
        switch intent {
        case let .trend(kind, days):
            let trend = try await HealthKitService.shared.trend(kind: kind, days: days, useCache: true)
            return .trend(trend, kind)
            
        case let .compare(kind, windowDays):
            let comparison = try await HealthKitService.shared.compare(kind: kind, windowDays: windowDays, useCache: true)
            return .comparison(comparison, kind)
        }
    }
    
    private static func containsInsightKeywords(_ query: String) -> Bool {
        let lowered = query.lowercased()
        let insightKeywords = ["insight", "recommendation", "analysis", "suggestions", "advice", "how", "improve", "enhance"]
        return insightKeywords.contains { lowered.contains($0) }
    }
    
    private static func generateHealthInsights(_ query: String) async throws -> QueryResult {
        try await HealthKitService.shared.requestAuthorization()
        
        var insights: [HealthInsight] = []
        
        // Generate insights for different metrics
        let metrics: [HealthKitService.MetricKind] = [.steps, .heartRateAverage, .sleepDurationHours, .activeEnergy]
        
        for metric in metrics {
            do {
                let trend = try await HealthKitService.shared.trend(kind: metric, days: 7, useCache: true)
                let comparison = try await HealthKitService.shared.compare(kind: metric, windowDays: 7, useCache: true)
                
                if let insight = generateInsightForMetric(metric, trend: trend, comparison: comparison) {
                    insights.append(insight)
                }
            } catch {
                // Continue with other metrics if one fails
                continue
            }
        }
        
        return .insights(insights.isEmpty ? [generateFallbackInsight()] : insights)
    }
    
    private static func generateInsightForMetric(
        _ kind: HealthKitService.MetricKind,
        trend: HealthKitService.Trend,
        comparison: HealthKitService.Comparison
    ) -> HealthInsight? {
        let metricName = metricTitle(kind: kind)
        let unit = metricUnit(kind: kind)
        
        // Analyze trend and comparison data
        let trendDirection = trend.changeRate >= 0.05 ? "Increase" : (trend.changeRate <= -0.05 ? "Decrease" : "Stable")
        let comparisonChange = abs(comparison.deltaRate * 100)
        
        var insight: String
        var recommendation: String?
        var severity: HealthInsight.Severity = .info
        
        switch kind {
        case .steps:
            if trend.average < 5000 {
                insight = "Your daily average steps is \(String(format: "%.0f", trend.average)) steps, below the recommended 10,000 steps per day."
                recommendation = "Consider increasing daily walking activities, try short walks, taking stairs, or evening strolls."
                severity = .warning
            } else if trend.average >= 10000 {
                insight = "Your daily average steps is \(String(format: "%.0f", trend.average)) steps, meeting health standards!"
                recommendation = "Maintain good activity habits and continue your daily step routine."
                severity = .info
            } else {
                insight = "Your daily average steps is \(String(format: "%.0f", trend.average)) steps, close to health standards."
                recommendation = "Keep it up! You're not far from the daily 10,000 steps goal."
                severity = .info
            }
            
        case .heartRateAverage:
            if comparisonChange > 15 {
                insight = "Your average heart rate shows significant \(trendDirection.lowercased()), with a change of \(String(format: "%.1f", comparisonChange))%."
                recommendation = "Large heart rate variations detected. Consider monitoring sleep patterns and stress management. Consult a doctor if you experience discomfort."
                severity = .warning
            } else {
                insight = "Your heart rate shows \(trendDirection.lowercased()), averaging \(String(format: "%.1f", trend.average)) bpm."
                recommendation = nil
                severity = .info
            }
            
        case .sleepDurationHours:
            if trend.average < 7 {
                insight = "Your average sleep duration is \(String(format: "%.1f", trend.average)) hours, slightly less than the recommended 7-9 hours."
                recommendation = "Consider adjusting your sleep schedule to ensure adequate rest for body recovery and health."
                severity = .warning
            } else if trend.average > 9 {
                insight = "Your average sleep duration is \(String(format: "%.1f", trend.average)) hours, which is sufficient."
                recommendation = "Your sleep quality is good. Focus on maintaining regular sleep schedule."
                severity = .info
            } else {
                insight = "Your sleep duration is \(String(format: "%.1f", trend.average)) hours, within healthy range."
                recommendation = nil
                severity = .info
            }
            
        case .activeEnergy:
            if trend.average < 200 {
                insight = "Your daily average active energy expenditure is \(String(format: "%.0f", trend.average)) kcal, which is relatively low."
                recommendation = "Consider increasing moderate-intensity physical activities such as brisk walking, swimming, or cycling."
                severity = .warning
            } else {
                insight = "Your daily average active energy expenditure is \(String(format: "%.0f", trend.average)) kcal, which is good."
                recommendation = "Maintain good exercise habits. Moderate exercise benefits your health."
                severity = .info
            }
            
        default:
            return nil
        }
        
        return HealthInsight(
            title: metricName + " Analysis",
            insight: insight,
            recommendation: recommendation,
            icon: metricIcon(kind: kind),
            color: severity == .warning ? "orange" : "blue",
            severity: severity
        )
    }
    
    private static func generateFallbackInsight() -> HealthInsight {
        HealthInsight(
            title: "Health Reminder",
            insight: "Maintaining good lifestyle habits is important for health.",
            recommendation: "Regularly review your health data and monitor changes in your physical condition.",
            icon: "heart.circle",
            color: "blue",
            severity: .info
        )
    }
    
    // Helper functions
    private static func metricTitle(kind: HealthKitService.MetricKind) -> String {
        switch kind {
        case .steps: return "Steps"
        case .heartRateAverage: return "Average Heart Rate"
        case .restingHeartRate: return "Resting Heart Rate"
        case .activeEnergy: return "Active Energy"
        case .bodyMass: return "Body Mass"
        case .sleepDurationHours: return "Sleep Duration"
        }
    }
    
    private static func metricUnit(kind: HealthKitService.MetricKind) -> String {
        switch kind {
        case .steps: return "steps"
        case .heartRateAverage, .restingHeartRate: return "bpm"
        case .activeEnergy: return "kcal"
        case .bodyMass: return "kg"
        case .sleepDurationHours: return "hours"
        }
    }
    
    private static func metricIcon(kind: HealthKitService.MetricKind) -> String {
        switch kind {
        case .steps: return "figure.walk"
        case .heartRateAverage, .restingHeartRate: return "heart.fill"
        case .activeEnergy: return "flame.fill"
        case .bodyMass: return "scalemass"
        case .sleepDurationHours: return "bed.double.fill"
        }
    }
}