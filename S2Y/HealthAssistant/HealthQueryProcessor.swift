//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable function_body_length line_length cyclomatic_complexity
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
        // Structured HealthKit operations always use the validated tool contract.
        switch QueryPlanner.parseResult(query) {
        case .valid(let intent):
            return try await processStructuredQuery(intent)
        case .invalid(let error):
            return .textResponse(error.localizedDescription)
        case .noMatch:
            break
        }

        // Broader summaries and guidance use the enhanced planner.
        if let intent = EnhancedQueryPlanner.parse(query) {
            return try await EnhancedQueryPlanner.run(intent: intent)
        }
        
        // Check for insight-related queries
        if containsInsightKeywords(query) {
            return try await generateHealthInsights(query)
        }
        
        // Final fallback
        return .textResponse("I can help you analyze your health data. Try asking about your step trends, heart rate comparisons, or health insights.")
    }
    
    private static func processStructuredQuery(_ intent: QueryPlanner.Intent) async throws -> QueryResult {
        switch intent.operation {
        case .trend:
            let trend = try await HealthKitService.shared.trend(
                kind: intent.metric,
                days: intent.windowDays,
                useCache: true
            )
            return .trend(trend, intent.metric)
            
        case .comparePeriods:
            let comparison = try await HealthKitService.shared.compare(
                kind: intent.metric,
                windowDays: intent.windowDays,
                useCache: true
            )
            return .comparison(comparison, intent.metric)
        }
    }
    
    private static func containsInsightKeywords(_ query: String) -> Bool {
        let lowered = query.lowercased()
        let insightKeywords = ["insight", "recommendation", "analysis", "suggestions", "advice", "how", "improve", "enhance"]
        return insightKeywords.contains { lowered.contains($0) }
    }
    
    private static func generateHealthInsights(_ query: String) async throws -> QueryResult {
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
        let insight = [
            HealthInterpretationPolicy.trendContext(trend, kind: kind),
            HealthInterpretationPolicy.comparisonContext(comparison, kind: kind)
        ].joined(separator: "\n\n")
        
        return HealthInsight(
            title: metricName + " Observation",
            insight: insight,
            recommendation: HealthInterpretationPolicy.optionalWellnessActions(for: kind),
            icon: metricIcon(kind: kind),
            color: "blue",
            severity: .info
        )
    }
    
    private static func generateFallbackInsight() -> HealthInsight {
        HealthInsight(
            title: "Health Data Unavailable",
            insight: "There is not enough readable data to describe these trends. \(HealthInterpretationPolicy.wellnessBoundary)",
            recommendation: nil,
            icon: "heart.circle",
            color: "blue",
            severity: .info
        )
    }
    
    // Helper functions
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
