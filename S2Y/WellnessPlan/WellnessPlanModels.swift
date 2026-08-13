//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

public struct WellnessGoal: Codable, Identifiable, Sendable, Equatable {
    public enum Direction: String, Codable, Sendable {
        case increase
        case decrease
        case maintain
        case consistency
    }

    public let id: UUID
    public let metricKind: HealthKitService.MetricKind
    public var direction: Direction
    public var targetValue: Double?
    public var targetUnit: String
    public var reviewDate: Date
    public var confirmedAt: Date?

    public init(
        id: UUID = UUID(),
        metricKind: HealthKitService.MetricKind,
        direction: Direction,
        targetValue: Double?,
        targetUnit: String,
        reviewDate: Date,
        confirmedAt: Date? = nil
    ) {
        self.id = id
        self.metricKind = metricKind
        self.direction = direction
        self.targetValue = targetValue
        self.targetUnit = targetUnit
        self.reviewDate = reviewDate
        self.confirmedAt = confirmedAt
    }

    public static func userSelected(
        metricKind: HealthKitService.MetricKind,
        direction: Direction,
        targetValue: Double?,
        reviewDate: Date,
        confirmedAt: Date = .now
    ) -> WellnessGoal {
        WellnessGoal(
            metricKind: metricKind,
            direction: direction,
            targetValue: targetValue,
            targetUnit: metricKind.unit,
            reviewDate: reviewDate,
            confirmedAt: confirmedAt
        )
    }
}

public struct WellnessAction: Codable, Identifiable, Sendable, Equatable {
    public enum Category: String, Codable, Sendable, CaseIterable {
        case movement
        case sleepRoutine
        case recovery
        case mindfulness
        case checkIn
    }

    public let id: UUID
    public var title: String
    public var detail: String
    public var category: Category
    public var daysPerWeek: Int
    public var estimatedMinutes: Int
    public var isOptional: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        category: Category,
        daysPerWeek: Int,
        estimatedMinutes: Int,
        isOptional: Bool = false
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.category = category
        self.daysPerWeek = min(7, max(1, daysPerWeek))
        self.estimatedMinutes = max(1, estimatedMinutes)
        self.isOptional = isOptional
    }
}

public struct WellnessPlan: Codable, Identifiable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case draft
        case active
        case paused
        case completed
        case archived
    }

    public enum Origin: String, Codable, Sendable {
        case userCreated
        case assistantDraft
    }

    public let id: UUID
    public var title: String
    public var summary: String
    public var status: Status
    public var origin: Origin
    public var goals: [WellnessGoal]
    public var actions: [WellnessAction]
    public let createdAt: Date
    public var updatedAt: Date
    public var activatedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        status: Status = .draft,
        origin: Origin,
        goals: [WellnessGoal],
        actions: [WellnessAction],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        activatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.status = status
        self.origin = origin
        self.goals = goals
        self.actions = actions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.activatedAt = activatedAt
    }
}

public enum WellnessPlanTransitionError: Error, Equatable {
    case invalidTransition
    case emptyPlan
    case unconfirmedGoal
    case invalidGoal
}

public enum WellnessPlanLifecycle {
    public static func transition(
        _ plan: WellnessPlan,
        to status: WellnessPlan.Status,
        at date: Date = .now
    ) throws -> WellnessPlan {
        if status == .active, plan.goals.isEmpty || plan.actions.isEmpty {
            throw WellnessPlanTransitionError.emptyPlan
        }
        if status == .active, plan.goals.contains(where: { $0.confirmedAt == nil }) {
            throw WellnessPlanTransitionError.unconfirmedGoal
        }
        if status == .active, plan.goals.contains(where: { goal in
            goal.targetUnit != goal.metricKind.unit
                || goal.targetValue.map { !$0.isFinite || $0 <= 0 } == true
                || goal.confirmedAt.map { goal.reviewDate < $0 } == true
        }) {
            throw WellnessPlanTransitionError.invalidGoal
        }
        let allowed: Set<WellnessPlan.Status>
        switch plan.status {
        case .draft:
            allowed = [.active, .archived]
        case .active:
            allowed = [.paused, .completed, .archived]
        case .paused:
            allowed = [.active, .archived]
        case .completed:
            allowed = [.archived]
        case .archived:
            allowed = []
        }
        guard allowed.contains(status) else {
            throw WellnessPlanTransitionError.invalidTransition
        }
        var updated = plan
        updated.status = status
        updated.updatedAt = date
        if status == .active, updated.activatedAt == nil {
            updated.activatedAt = date
        }
        return updated
    }
}

@MainActor
final class WellnessPlanStore: ObservableObject {
    static let shared = WellnessPlanStore()

    @Published private(set) var plans: [WellnessPlan] = []

    private let defaults: UserDefaults
    private let storageKey = "wellnessPlans.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    var currentPlan: WellnessPlan? {
        plans.first { $0.status == .active || $0.status == .paused || $0.status == .draft }
    }

    func save(_ plan: WellnessPlan) {
        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[index] = plan
        } else {
            plans.insert(plan, at: 0)
        }
        persist()
    }

    func removeArchivedPlans() {
        plans.removeAll { $0.status == .archived }
        persist()
    }

    func clear() {
        plans = []
        defaults.removeObject(forKey: storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? decoder.decode([WellnessPlan].self, from: data) else {
            return
        }
        plans = decoded
    }

    private func persist() {
        guard let data = try? encoder.encode(plans) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
