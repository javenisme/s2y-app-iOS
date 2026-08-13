//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SwiftUI

struct WellnessActionRecord: Codable, Identifiable, Sendable, Equatable {
    enum Outcome: String, Codable, Sendable {
        case completed
        case skipped
    }

    let id: UUID
    let planID: UUID
    let actionID: UUID
    let day: Date
    let outcome: Outcome
    let recordedAt: Date
}

enum WellnessDailySchedule {
    static func actions(
        for plan: WellnessPlan,
        on date: Date,
        calendar: Calendar = .current
    ) -> [WellnessAction] {
        guard plan.status == .active else { return [] }
        let weekday = calendar.component(.weekday, from: date)
        return plan.actions.filter { action in
            action.daysPerWeek >= 7 || weekday <= action.daysPerWeek
        }
    }
}

@MainActor
final class WellnessActionRecordStore: ObservableObject {
    static let shared = WellnessActionRecordStore()

    @Published private(set) var records: [WellnessActionRecord] = []

    private let defaults: UserDefaults
    private let storageKey = "wellnessActionRecords.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([WellnessActionRecord].self, from: data) {
            records = decoded
        }
    }

    func record(
        planID: UUID,
        actionID: UUID,
        outcome: WellnessActionRecord.Outcome,
        on date: Date = .now,
        calendar: Calendar = .current
    ) {
        let day = calendar.startOfDay(for: date)
        records.removeAll { $0.planID == planID && $0.actionID == actionID && calendar.isDate($0.day, inSameDayAs: day) }
        records.append(WellnessActionRecord(
            id: UUID(),
            planID: planID,
            actionID: actionID,
            day: day,
            outcome: outcome,
            recordedAt: date
        ))
        persist()
    }

    func outcome(
        planID: UUID,
        actionID: UUID,
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> WellnessActionRecord.Outcome? {
        records.last { record in
            record.planID == planID
                && record.actionID == actionID
                && calendar.isDate(record.day, inSameDayAs: date)
        }?.outcome
    }

    func undo(planID: UUID, actionID: UUID, on date: Date = .now, calendar: Calendar = .current) {
        records.removeAll { record in
            record.planID == planID
                && record.actionID == actionID
                && calendar.isDate(record.day, inSameDayAs: date)
        }
        persist()
    }

    func clear() {
        records = []
        defaults.removeObject(forKey: storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct WellnessPlanSettingsView: View {
    @StateObject private var planStore = WellnessPlanStore.shared
    @StateObject private var recordStore = WellnessActionRecordStore.shared
    @State private var isCreatingDraft = false
    @State private var isAddingGoal = false
    @State private var goalMetric: HealthKitService.MetricKind = .steps
    @State private var goalDirection: WellnessGoal.Direction = .consistency
    @State private var goalTargetText = ""
    @State private var goalReviewDate = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let plan = planStore.currentPlan {
                planSection(plan)
                if plan.status == .active {
                    todaySection(plan)
                }
                Section {
                    NavigationLink {
                        WellnessWeeklyReviewView()
                    } label: {
                        Label("Weekly Review", systemImage: "calendar.badge.clock")
                    }
                }
            } else {
                ContentUnavailableView(
                    "No wellbeing plan",
                    systemImage: "list.bullet.clipboard",
                    description: Text("Create a draft from your recent personal patterns, then review it before activation.")
                )
            }

            Section {
                Button {
                    Task { await createDraft() }
                } label: {
                    if isCreatingDraft {
                        ProgressView()
                    } else {
                        Label("Create draft from recent data", systemImage: "sparkles")
                    }
                }
                .disabled(isCreatingDraft || planStore.currentPlan?.status == .active)
            } footer: {
                Text("S2Y creates an editable health-management draft. It never activates a plan or schedules an intervention without your confirmation.")
            }
        }
        .navigationTitle("Wellbeing Plan")
        .alert("Plan unavailable", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $isAddingGoal) {
            goalEditor
        }
    }

    @ViewBuilder
    private func planSection(_ plan: WellnessPlan) -> some View {
        Section("Current Plan") {
            VStack(alignment: .leading, spacing: 6) {
                Text(plan.title).font(.headline)
                Text(plan.summary).font(.caption).foregroundStyle(.secondary)
                LabeledContent("Status", value: plan.status.rawValue.capitalized)
            }
            if plan.goals.isEmpty {
                Text("No personal goal selected yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(plan.goals) { goal in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(goal.metricKind.displayName)
                            .font(.subheadline.weight(.semibold))
                        Text(goalDescription(goal))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    removeGoals(at: offsets, from: plan)
                }
            }
            if plan.status == .draft {
                Button {
                    prepareGoalEditor()
                } label: {
                    Label("Add my goal", systemImage: "plus.circle")
                }
            }
            ForEach(plan.actions) { action in
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title).font(.subheadline.weight(.semibold))
                    Text(action.detail).font(.caption).foregroundStyle(.secondary)
                    Text("\(action.daysPerWeek) days/week · about \(action.estimatedMinutes) min")
                        .font(.caption2).foregroundStyle(.tertiary)
                    if plan.status == .draft {
                        Button(action.confirmedAt == nil ? "Include this action" : "Included") {
                            toggleActionConfirmation(action, in: plan)
                        }
                        .font(.caption)
                    }
                }
            }
            .onDelete { offsets in
                removeActions(at: offsets, from: plan)
            }
            if plan.status == .draft {
                Button("Review complete — activate plan") {
                    do {
                        planStore.save(try WellnessPlanLifecycle.transition(plan, to: .active))
                    } catch WellnessPlanTransitionError.unconfirmedGoal {
                        errorMessage = "Review and confirm every personal goal before activation."
                    } catch WellnessPlanTransitionError.invalidGoal {
                        errorMessage = "A goal has an invalid value, unit, or review date. Edit it before activation."
                    } catch WellnessPlanTransitionError.unconfirmedAction {
                        errorMessage = "Choose which suggested actions to include before activation."
                    } catch {
                        errorMessage = "Add at least one personal goal and keep at least one optional action before activation."
                    }
                }
            } else if plan.status == .active {
                Button("Pause plan") {
                    if let updated = try? WellnessPlanLifecycle.transition(plan, to: .paused) {
                        planStore.save(updated)
                    }
                }
            } else if plan.status == .paused {
                Button("Resume plan") {
                    if let updated = try? WellnessPlanLifecycle.transition(plan, to: .active) {
                        planStore.save(updated)
                    }
                }
            }
            if plan.status != .archived {
                Button("Archive plan", role: .destructive) {
                    if let updated = try? WellnessPlanLifecycle.transition(plan, to: .archived) {
                        planStore.save(updated)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func todaySection(_ plan: WellnessPlan) -> some View {
        let actions = WellnessDailySchedule.actions(for: plan, on: .now)
        Section("Today") {
            if actions.isEmpty {
                Text("No actions scheduled today.").foregroundStyle(.secondary)
            }
            ForEach(actions) { action in
                let outcome = recordStore.outcome(planID: plan.id, actionID: action.id)
                VStack(alignment: .leading, spacing: 8) {
                    Text(action.title)
                    if let outcome {
                        Label(outcome == .completed ? "Completed" : "Skipped", systemImage: outcome == .completed ? "checkmark.circle.fill" : "forward.circle")
                            .foregroundStyle(.secondary)
                        Button("Undo") {
                            recordStore.undo(planID: plan.id, actionID: action.id)
                        }
                        .font(.caption)
                    } else {
                        HStack {
                            Button("Complete") {
                                recordStore.record(planID: plan.id, actionID: action.id, outcome: .completed)
                            }
                            Button("Skip") {
                                recordStore.record(planID: plan.id, actionID: action.id, outcome: .skipped)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func createDraft() async {
        isCreatingDraft = true
        defer { isCreatingDraft = false }
        guard let report = await PersonalHealthInsightLoader.load(for: "Show my health patterns") else {
            errorMessage = "More readable Health data is needed before S2Y can create a personalized draft."
            return
        }
        planStore.save(WellnessPlanDraftBuilder.build(from: report).plan)
    }

    private var goalEditor: some View {
        NavigationStack {
            Form {
                Picker("Metric", selection: $goalMetric) {
                    ForEach(HealthKitService.MetricKind.allCases, id: \.self) { metric in
                        Text(metric.displayName).tag(metric)
                    }
                }
                Picker("Direction", selection: $goalDirection) {
                    ForEach(WellnessGoal.Direction.allCases, id: \.self) { direction in
                        Text(directionLabel(direction)).tag(direction)
                    }
                }
                TextField("Optional numeric target", text: $goalTargetText)
                    .keyboardType(.decimalPad)
                Text("Unit: \(goalMetric.unit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DatePicker(
                    "Review date",
                    selection: $goalReviewDate,
                    in: Date.now...,
                    displayedComponents: .date
                )
                Section {
                    Text("This is the target you chose. S2Y records progress but does not assess whether the target is medically appropriate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("My Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isAddingGoal = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addGoal() }
                        .disabled(!isGoalTargetValid)
                }
            }
        }
    }

    private var parsedGoalTarget: Double? {
        let trimmed = goalTargetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private var isGoalTargetValid: Bool {
        let trimmed = goalTargetText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || parsedGoalTarget.map { $0.isFinite && $0 > 0 } == true
    }

    private func prepareGoalEditor() {
        goalMetric = .steps
        goalDirection = .consistency
        goalTargetText = ""
        goalReviewDate = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
        isAddingGoal = true
    }

    private func addGoal() {
        guard var plan = planStore.currentPlan, plan.status == .draft, isGoalTargetValid else { return }
        let goal = WellnessGoal.userSelected(
            metricKind: goalMetric,
            direction: goalDirection,
            targetValue: parsedGoalTarget,
            reviewDate: goalReviewDate
        )
        plan.goals.removeAll { $0.metricKind == goalMetric }
        plan.goals.append(goal)
        plan.updatedAt = .now
        planStore.save(plan)
        isAddingGoal = false
    }

    private func removeGoals(at offsets: IndexSet, from plan: WellnessPlan) {
        guard plan.status == .draft else { return }
        var updated = plan
        updated.goals = updated.goals.enumerated().compactMap { index, goal in
            offsets.contains(index) ? nil : goal
        }
        updated.updatedAt = .now
        planStore.save(updated)
    }

    private func toggleActionConfirmation(_ action: WellnessAction, in plan: WellnessPlan) {
        guard plan.status == .draft,
              let index = plan.actions.firstIndex(where: { $0.id == action.id }) else { return }
        var updated = plan
        updated.actions[index].confirmedAt = action.confirmedAt == nil ? .now : nil
        updated.updatedAt = .now
        planStore.save(updated)
    }

    private func removeActions(at offsets: IndexSet, from plan: WellnessPlan) {
        guard plan.status == .draft else { return }
        var updated = plan
        updated.actions = updated.actions.enumerated().compactMap { index, action in
            offsets.contains(index) ? nil : action
        }
        updated.updatedAt = .now
        planStore.save(updated)
    }

    private func goalDescription(_ goal: WellnessGoal) -> String {
        let target = goal.targetValue.map { goal.metricKind.formatValue($0) } ?? "no numeric target"
        return "\(directionLabel(goal.direction)) · \(target) · review \(goal.reviewDate.formatted(date: .abbreviated, time: .omitted))"
    }

    private func directionLabel(_ direction: WellnessGoal.Direction) -> String {
        switch direction {
        case .increase: "Increase"
        case .decrease: "Decrease"
        case .maintain: "Maintain"
        case .consistency: "Consistency"
        }
    }
}
