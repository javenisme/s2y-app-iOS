//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation
import OSLog

enum AssistantPerformanceProvider: String, Codable, Sendable {
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
