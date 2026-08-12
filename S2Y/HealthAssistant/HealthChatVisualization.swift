//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

enum HealthChartRequest: Equatable, Sendable {
    case trend(kind: HealthKitService.MetricKind, days: Int)
    case comparison(kind: HealthKitService.MetricKind, days: Int)

    static func parse(_ query: String) -> HealthChartRequest? {
        guard let intent = QueryPlanner.parse(query) else {
            return nil
        }
        switch intent {
        case .trend(let kind, let days):
            return .trend(kind: kind, days: days)
        case .compare(let kind, let windowDays):
            return .comparison(kind: kind, days: windowDays)
        }
    }
}

enum HealthChartAttachment: Sendable {
    case trend(HealthKitService.Trend, HealthKitService.MetricKind)
    case comparison(HealthKitService.Comparison, HealthKitService.MetricKind)
}

enum HealthChatVisualizationLoader {
    /// Loads only data that is already readable. It never triggers a permission prompt from chat.
    @MainActor
    static func load(for query: String) async -> HealthChartAttachment? {
        guard let request = HealthChartRequest.parse(query) else {
            return nil
        }
        do {
            switch request {
            case .trend(let kind, let days):
                let trend = try await HealthKitService.shared.trend(kind: kind, days: days)
                guard trend.dataQuality != .unavailable else { return nil }
                return .trend(trend, kind)
            case .comparison(let kind, let days):
                let comparison = try await HealthKitService.shared.compare(kind: kind, windowDays: days)
                guard comparison.dataQuality != .unavailable else { return nil }
                return .comparison(comparison, kind)
            }
        } catch {
            return nil
        }
    }
}
