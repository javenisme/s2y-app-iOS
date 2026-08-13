//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SwiftUI

public struct HealthSafetyEvent: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let occurredAt: Date
    public let level: HealthSafetyEscalationLevel
    public let signalCategories: [String]
    public let aiProviderContacted: Bool

    public init(escalation: HealthSafetyEscalation, occurredAt: Date = .now) {
        self.id = UUID()
        self.occurredAt = occurredAt
        self.level = escalation.level
        self.signalCategories = escalation.signalCategories.sorted()
        self.aiProviderContacted = false
    }
}

public struct HealthSafetyEventLog: Codable, Sendable, Equatable {
    public private(set) var events: [HealthSafetyEvent]
    public let maximumEventCount: Int

    public init(events: [HealthSafetyEvent] = [], maximumEventCount: Int = 50) {
        self.maximumEventCount = max(1, maximumEventCount)
        self.events = Array(events.prefix(self.maximumEventCount))
    }

    public mutating func record(_ event: HealthSafetyEvent) {
        events.insert(event, at: 0)
        events = Array(events.prefix(maximumEventCount))
    }

    public mutating func clear() {
        events.removeAll()
    }
}

@MainActor
final class HealthSafetyEventStore: ObservableObject {
    static let shared = HealthSafetyEventStore()

    @Published private(set) var log: HealthSafetyEventLog

    private let defaults: UserDefaults
    private let storageKey = "healthSafetyEvents.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? decoder.decode(HealthSafetyEventLog.self, from: data) {
            self.log = decoded
        } else {
            self.log = HealthSafetyEventLog()
        }
    }

    func record(_ escalation: HealthSafetyEscalation, at date: Date = .now) {
        log.record(HealthSafetyEvent(escalation: escalation, occurredAt: date))
        persist()
    }

    func clear() {
        log.clear()
        defaults.removeObject(forKey: storageKey)
    }

    private func persist() {
        guard let data = try? encoder.encode(log) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct HealthSafetyActivityView: View {
    @StateObject private var store = HealthSafetyEventStore.shared

    var body: some View {
        List {
            if store.log.events.isEmpty {
                ContentUnavailableView(
                    "No Safety Events",
                    systemImage: "shield.checkered",
                    description: Text("Urgent safety routing will be summarized here without saving your message text.")
                )
            } else {
                Section("On this iPhone") {
                    ForEach(store.log.events) { event in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(event.level.displayName, systemImage: "shield.checkered")
                                .font(.headline)
                            Text(event.occurredAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(event.signalCategories.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Section {
                    Button("Clear Safety Activity", role: .destructive) {
                        store.clear()
                    }
                }
            }
        }
        .navigationTitle("Safety Activity")
    }
}

private extension HealthSafetyEscalationLevel {
    var displayName: String {
        switch self {
        case .emergency: "Emergency guidance shown"
        case .selfHarmCrisis: "Crisis guidance shown"
        }
    }
}
