//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

enum QueryPlanner {
    typealias Intent = ValidatedHealthQueryToolRequest

    static func parse(_ text: String) -> Intent? {
        let lowered = text.lowercased()

        // metric detection
        let metric: HealthKitService.MetricKind? = {
            if lowered.contains("步数") || lowered.contains("steps") {
                return .steps
            }
            if lowered.contains("静息心率") || lowered.contains("resting heart") {
                return .restingHeartRate
            }
            if lowered.contains("心率") || lowered.contains("heart rate") {
                return .heartRateAverage
            }
            if lowered.contains("活动能量") || lowered.contains("active energy") || lowered.contains("calorie") {
                return .activeEnergy
            }
            if lowered.contains("体重") || lowered.contains("body mass") || lowered.contains("weight") {
                return .bodyMass
            }
            if lowered.contains("睡眠") || lowered.contains("sleep") {
                return .sleepDurationHours
            }
            return nil
        }()

        guard let kind = metric else { return nil }

        let days: Int = {
            if let explicitDays = extractExplicitDays(from: lowered) {
                return explicitDays
            }
            if lowered.contains("30天") || lowered.contains("30-day") || lowered.contains("30 days") {
                return 30
            }
            if lowered.contains("7天") || lowered.contains("七天") || lowered.contains("7-day") || lowered.contains("7 days") {
                return 7
            }
            return 7
        }()

        // intent detection
        let isCompare = lowered.contains("对比") || lowered.contains("compare") || lowered.contains("vs")
        if isCompare {
            return validatedRequest(operation: .comparePeriods, metric: kind, windowDays: days)
        }

        let isTrend = lowered.contains("趋势") || lowered.contains("trend") || lowered.contains("变化")
        if isTrend {
            return validatedRequest(operation: .trend, metric: kind, windowDays: days)
        }

        // default to compare for common phrasing like "过去7天 ... vs 上周"
        if lowered.contains("上周") || lowered.contains("last week") {
            return validatedRequest(operation: .comparePeriods, metric: kind, windowDays: days)
        }

        return nil
    }

    static func run(intent: Intent) async throws -> String {
        switch intent.operation {
        case .comparePeriods:
            let comparison = try await HealthKitService.shared.compare(
                kind: intent.metric,
                windowDays: intent.windowDays,
                useCache: true
            )
            return formatComparison(kind: intent.metric, comparison: comparison)

        case .trend:
            let trendResult = try await HealthKitService.shared.trend(
                kind: intent.metric,
                days: intent.windowDays,
                useCache: true
            )
            return formatTrend(kind: intent.metric, trend: trendResult)
        }
    }

    private static func validatedRequest(
        operation: HealthQueryToolRequest.Operation,
        metric: HealthKitService.MetricKind,
        windowDays: Int
    ) -> Intent? {
        try? HealthQueryToolRequest(
            operation: operation,
            metric: metric,
            windowDays: windowDays
        ).validated()
    }

    private static func extractExplicitDays(from text: String) -> Int? {
        guard let expression = try? NSRegularExpression(pattern: #"(\d{1,4})\s*(?:days?|天)"#),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[range])
    }

    private static func metricUnit(kind: HealthKitService.MetricKind) -> String {
        // Use dictionary to avoid non-exhaustive switches
        return HealthMetricsDictionary.unit(for: kind, locale: Locale(identifier: "zh_CN"))
    }

    private static func metricTitle(kind: HealthKitService.MetricKind) -> String {
        return HealthMetricsDictionary.displayName(for: kind, locale: Locale(identifier: "zh_CN"))
    }

    private static func formatComparison(
        kind: HealthKitService.MetricKind,
        comparison: HealthKitService.Comparison
    ) -> String {
        let unit = metricUnit(kind: kind)
        let title = "过去\(comparison.currentWindowDays)天\(metricTitle(kind: kind)) vs 上期"
        let cur = comparison.currentAverage
        let prev = comparison.previousAverage
        let delta = comparison.delta
        let rate = comparison.deltaRate * 100
        let arrow = delta >= 0 ? "⬆️" : "⬇️"
        return "\(title)\n当前平均：\(String(format: "%.2f", cur)) \(unit)\n上期平均：\(String(format: "%.2f", prev)) \(unit)\n变化：\(arrow) \(String(format: "%.1f", abs(rate)))% (\(String(format: "%.2f", abs(delta))) \(unit))\n建议：稳步改善，关注作息与活动一致性。"
    }

    private static func formatTrend(
        kind: HealthKitService.MetricKind,
        trend: HealthKitService.Trend
    ) -> String {
        let unit = metricUnit(kind: kind)
        let title = "过去\(trend.windowDays)天\(metricTitle(kind: kind))趋势"
        let avg = trend.average
        let rate = trend.changeRate * 100
        let arrow = rate >= 0 ? "⬆️" : "⬇️"
        return "\(title)\n窗口平均：\(String(format: "%.2f", avg)) \(unit)\n首末变化：\(arrow) \(String(format: "%.1f", abs(rate)))%\n建议：保持良好习惯，必要时逐步调整计划。"
    }
}
