//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT

import Foundation

enum OmerHealthContextBuilder {
    @MainActor
    static func buildSummary(
        for query: String,
        includeHealthContext: Bool
    ) async -> [String: String]? {
        guard includeHealthContext else {
            return nil
        }

        let allowedMetricKeys = Set(HealthKitService.MetricKind.allCases.map(\.rawValue))
        var context = Dictionary(
            uniqueKeysWithValues: ConversationContextManager.shared
                .getRelevantHealthContext()
                .filter { allowedMetricKeys.contains($0.key) }
                .sorted { $0.key < $1.key }
                .prefix(9)
                .compactMap { key, value -> (String, String)? in
                    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !normalized.isEmpty else { return nil }
                    return (key, String(normalized.prefix(200)))
                }
        )
        context["interpretationBoundary"] = HealthInterpretationPolicy.wellnessBoundary

        do {
            let result = try await HealthQueryProcessor.processQuery(query)
            let queryResult = format(result).trimmingCharacters(in: .whitespacesAndNewlines)
            if !queryResult.isEmpty {
                context["queryResult"] = String(queryResult.prefix(500))
            }
        } catch {
            // Health data can be unavailable or partially authorized. Existing context,
            // if any, remains useful and the assistant can still answer generally.
        }

        return context.isEmpty ? nil : context
    }

    private static func format(_ result: HealthQueryProcessor.QueryResult) -> String {
        switch result {
        case .textResponse(let text):
            return text
        case let .trend(trend, kind):
            return HealthInterpretationPolicy.trendContext(trend, kind: kind)
        case let .comparison(comparison, kind):
            return HealthInterpretationPolicy.comparisonContext(comparison, kind: kind)
        case .insights(let insights):
            return insights.map { insight in
                var parts = [insight.title, insight.insight]
                if let recommendation = insight.recommendation {
                    parts.append(recommendation)
                }
                return parts.joined(separator: " ")
            }
            .joined(separator: "\n")
        }
    }
}
