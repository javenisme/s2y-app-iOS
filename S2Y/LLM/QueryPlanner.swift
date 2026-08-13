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

    enum ParseResult: Equatable {
        case noMatch
        case valid(Intent)
        case invalid(HealthQueryToolRequestError)
    }

    static func parse(_ text: String) -> Intent? {
        guard case .valid(let intent) = parseResult(text) else { return nil }
        return intent
    }

    static func parseResult(_ text: String) -> ParseResult {
        let lowered = text.lowercased()
        guard let kind = detectMetric(in: lowered) else { return .noMatch }

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

        let operation: HealthQueryToolRequest.Operation
        let isCompare = lowered.contains("对比") || lowered.contains("compare") || lowered.contains("vs")
        if isCompare {
            operation = .comparePeriods
        } else if lowered.contains("趋势") || lowered.contains("trend") || lowered.contains("变化") {
            operation = .trend
        } else if lowered.contains("上周") || lowered.contains("last week") {
            operation = .comparePeriods
        } else {
            return .noMatch
        }

        let request = HealthQueryToolRequest(
            operation: operation,
            metric: kind,
            windowDays: days
        )
        do {
            return .valid(try request.validated())
        } catch let error as HealthQueryToolRequestError {
            return .invalid(error)
        } catch {
            return .noMatch
        }
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

    private static func detectMetric(in text: String) -> HealthKitService.MetricKind? {
        if text.contains("步数") || text.contains("step") { return .steps }
        if text.contains("静息心率") || text.contains("resting heart") { return .restingHeartRate }
        if text.contains("心率") || text.contains("heart rate") { return .heartRateAverage }
        if text.contains("活动能量") || text.contains("active energy") || text.contains("calorie") {
            return .activeEnergy
        }
        if text.contains("体重") || text.contains("body mass") || text.contains("weight") { return .bodyMass }
        if text.contains("睡眠") || text.contains("sleep") { return .sleepDurationHours }
        return nil
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
