//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation

struct AssistantClarification: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case metric
        case timeframe
    }

    let id: UUID
    let kind: Kind
    let originalQuery: String
    let prompt: String
    let options: [AssistantClarificationOption]

    init(
        id: UUID = UUID(),
        kind: Kind,
        originalQuery: String,
        prompt: String,
        options: [AssistantClarificationOption]
    ) {
        self.id = id
        self.kind = kind
        self.originalQuery = originalQuery
        self.prompt = prompt
        self.options = options
    }
}

struct AssistantClarificationOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let systemImage: String
    let queryDetail: String
}

enum AssistantConversationResolution: Equatable, Sendable {
    case ready(String)
    case needsClarification(AssistantClarification)
}

enum AssistantConversationPolicy {
    static func resolve(
        query: String,
        recentUserMessages: [String] = []
    ) -> AssistantConversationResolution {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        guard !trimmed.isEmpty else { return .ready(trimmed) }

        let inheritedQuery = inheritMetricIfNeeded(
            query: trimmed,
            normalized: normalized,
            recentUserMessages: recentUserMessages
        )
        let inheritedNormalized = inheritedQuery.lowercased()

        if needsMetricClarification(inheritedNormalized) {
            return .needsClarification(
                AssistantClarification(
                    kind: .metric,
                    originalQuery: inheritedQuery,
                    prompt: "Which health area would you like to focus on?",
                    options: metricOptions
                )
            )
        }

        if hasVagueTimeframe(inheritedNormalized), !hasSpecificTimeframe(inheritedNormalized) {
            return .needsClarification(
                AssistantClarification(
                    kind: .timeframe,
                    originalQuery: inheritedQuery,
                    prompt: "What time period should I analyze?",
                    options: timeframeOptions
                )
            )
        }

        return .ready(inheritedQuery)
    }

    static func applying(
        _ option: AssistantClarificationOption,
        to clarification: AssistantClarification
    ) -> String {
        clarification.originalQuery + "\n" + option.queryDetail
    }

    private static func inheritMetricIfNeeded(
        query: String,
        normalized: String,
        recentUserMessages: [String]
    ) -> String {
        guard isFollowUp(normalized), !containsSpecificMetric(normalized) else {
            return query
        }

        guard let priorMetric = recentUserMessages.reversed().compactMap(metricDetail(in:)).first else {
            return query
        }
        return query + "\n" + priorMetric
    }

    private static func needsMetricClarification(_ query: String) -> Bool {
        guard !containsSpecificMetric(query) else { return false }
        let broadTerms = [
            "my health", "health data", "activity", "heart health",
            "我的健康", "健康数据", "活动情况", "心脏情况"
        ]
        return broadTerms.contains { query.contains($0) }
    }

    private static func containsSpecificMetric(_ query: String) -> Bool {
        metricDetail(in: query) != nil
    }

    private static func metricDetail(in query: String) -> String? {
        let normalized = query.lowercased()
        let topics: [([String], String)] = [
            (["step", "步数"], "Health metric: step count."),
            (["sleep", "睡眠"], "Health metric: sleep duration and consistency."),
            (["active energy", "calorie", "活动能量", "卡路里"], "Health metric: active energy."),
            (["resting heart", "静息心率"], "Health metric: resting heart rate."),
            (["heart rate", "心率"], "Health metric: average heart rate."),
            (["weight", "body mass", "体重"], "Health metric: body weight."),
            (["blood pressure", "血压"], "Health metric: blood pressure.")
        ]
        return topics.first { terms, _ in terms.contains { normalized.contains($0) } }?.1
    }

    private static func isFollowUp(_ query: String) -> Bool {
        let indicators = [
            "what about", "how about", "and this", "and last", "compared with",
            "那", "呢", "上个月", "上周", "相比呢"
        ]
        return indicators.contains { query.contains($0) }
    }

    private static func hasVagueTimeframe(_ query: String) -> Bool {
        ["recently", "lately", "recent", "最近", "近期", "这段时间"].contains {
            query.contains($0)
        }
    }

    private static func hasSpecificTimeframe(_ query: String) -> Bool {
        query.contains(where: { $0.isNumber }) || [
            "today", "yesterday", "this week", "last week", "this month", "last month",
            "今天", "昨天", "本周", "上周", "本月", "上个月"
        ].contains { query.contains($0) }
    }

    private static let metricOptions = [
        AssistantClarificationOption(
            id: "steps",
            title: "Steps",
            systemImage: "figure.walk",
            queryDetail: "Health metric: step count."
        ),
        AssistantClarificationOption(
            id: "sleep",
            title: "Sleep",
            systemImage: "bed.double.fill",
            queryDetail: "Health metric: sleep duration and consistency."
        ),
        AssistantClarificationOption(
            id: "heart-rate",
            title: "Heart rate",
            systemImage: "heart.fill",
            queryDetail: "Health metric: average heart rate."
        ),
        AssistantClarificationOption(
            id: "active-energy",
            title: "Active energy",
            systemImage: "flame.fill",
            queryDetail: "Health metric: active energy."
        )
    ]

    private static let timeframeOptions = [
        AssistantClarificationOption(
            id: "today",
            title: "Today",
            systemImage: "calendar.badge.clock",
            queryDetail: "Time period: today."
        ),
        AssistantClarificationOption(
            id: "7-days",
            title: "Past 7 days",
            systemImage: "calendar",
            queryDetail: "Time period: past 7 days."
        ),
        AssistantClarificationOption(
            id: "30-days",
            title: "Past 30 days",
            systemImage: "calendar.badge.plus",
            queryDetail: "Time period: past 30 days."
        )
    ]
}
