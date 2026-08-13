//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation
import OSLog

enum AssistantPerformanceProvider: String, Codable, CaseIterable, Sendable {
    case appleOnDevice = "apple-on-device"
    case omerOnline = "omer-online"
}

enum AssistantPerformanceOutcome: String, Codable, Sendable {
    case completed
    case cancelled
    case failed
}

struct AssistantPerformanceEvent: Codable, Equatable, Sendable {
    let provider: AssistantPerformanceProvider
    let outcome: AssistantPerformanceOutcome
    let firstResponseMilliseconds: Int?
    let totalMilliseconds: Int
    let usedHealthContext: Bool
}

struct AssistantPerformanceSummary: Equatable, Sendable {
    let provider: AssistantPerformanceProvider
    let completedSamples: Int
    let firstResponseP95Milliseconds: Int?
    let totalP95Milliseconds: Int?

    static func make(
        provider: AssistantPerformanceProvider,
        events: [AssistantPerformanceEvent]
    ) -> AssistantPerformanceSummary {
        let completed = events.filter { $0.provider == provider && $0.outcome == .completed }
        return AssistantPerformanceSummary(
            provider: provider,
            completedSamples: completed.count,
            firstResponseP95Milliseconds: percentile95(completed.compactMap(\.firstResponseMilliseconds)),
            totalP95Milliseconds: percentile95(completed.map(\.totalMilliseconds))
        )
    }

    private static func percentile95(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let nearestRank = Int(ceil(Double(sorted.count) * 0.95))
        return sorted[max(0, nearestRank - 1)]
    }
}

/// A privacy-minimized, process-local performance trail. It deliberately excludes
/// prompts, responses, user identifiers, health values, and conversation IDs.
actor AssistantPerformanceMonitor {
    static let shared = AssistantPerformanceMonitor()

    private let logger = Logger(subsystem: "com.s2y.app", category: "AssistantPerformance")
    private var recentEvents: [AssistantPerformanceEvent] = []
    private let maximumEventCount = 50

    func record(_ event: AssistantPerformanceEvent) {
        recentEvents.append(event)
        recentEvents = Array(recentEvents.suffix(maximumEventCount))
        logger.info(
            "provider=\(event.provider.rawValue, privacy: .public) outcome=\(event.outcome.rawValue, privacy: .public) first_ms=\(event.firstResponseMilliseconds ?? -1) total_ms=\(event.totalMilliseconds) health_context=\(event.usedHealthContext)"
        )
    }

    func snapshot() -> [AssistantPerformanceEvent] {
        recentEvents
    }

    func summaries() -> [AssistantPerformanceSummary] {
        AssistantPerformanceProvider.allCases.map { provider in
            AssistantPerformanceSummary.make(provider: provider, events: recentEvents)
        }
    }

    func clear() {
        recentEvents.removeAll()
    }
}

struct AssistantRequestTimer: Sendable {
    private let startedAt: TimeInterval
    private(set) var firstResponseMilliseconds: Int?

    init(startedAt: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.startedAt = startedAt
    }

    mutating func markFirstResponse(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard firstResponseMilliseconds == nil else { return }
        firstResponseMilliseconds = elapsedMilliseconds(at: uptime)
    }

    func event(
        provider: AssistantPerformanceProvider,
        outcome: AssistantPerformanceOutcome,
        usedHealthContext: Bool,
        endedAt: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> AssistantPerformanceEvent {
        AssistantPerformanceEvent(
            provider: provider,
            outcome: outcome,
            firstResponseMilliseconds: firstResponseMilliseconds,
            totalMilliseconds: elapsedMilliseconds(at: endedAt),
            usedHealthContext: usedHealthContext
        )
    }

    private func elapsedMilliseconds(at uptime: TimeInterval) -> Int {
        max(0, Int(((uptime - startedAt) * 1_000).rounded()))
    }
}

@MainActor
final class AssistantRequestMeasurement {
    private var timer: AssistantRequestTimer

    init(startedAt: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        timer = AssistantRequestTimer(startedAt: startedAt)
    }

    func markFirstResponse(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        timer.markFirstResponse(at: uptime)
    }

    func event(
        provider: AssistantPerformanceProvider,
        outcome: AssistantPerformanceOutcome,
        usedHealthContext: Bool,
        endedAt: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> AssistantPerformanceEvent {
        timer.event(
            provider: provider,
            outcome: outcome,
            usedHealthContext: usedHealthContext,
            endedAt: endedAt
        )
    }
}
