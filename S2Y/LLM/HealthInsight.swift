//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT
//

import Foundation

/// A persisted, descriptive observation saved from a health conversation.
public struct HealthInsight: Identifiable {
    public let id = UUID()
    let title: String
    let titleCN: String
    let description: String
    let descriptionCN: String
    let type: InsightType
    let importance: Double
    let metric: HealthKitService.MetricKind?

    init(
        title: String,
        titleCN: String,
        description: String,
        descriptionCN: String,
        type: InsightType,
        importance: Double,
        metric: HealthKitService.MetricKind? = nil
    ) {
        self.title = title
        self.titleCN = titleCN
        self.description = description
        self.descriptionCN = descriptionCN
        self.type = type
        self.importance = importance
        self.metric = metric
    }
}

public enum InsightType: Codable {
    case trend
    case alert
    case achievement
    case recommendation
    case correlation
    case goal
}
