//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SwiftUI

struct WellnessWeeklyReview: Sendable, Equatable {
    enum Adjustment: String, Sendable {
        case considerSimplifying
        case keepFlexible
        case maintain
    }

    let scheduledCount: Int
    let completedCount: Int
    let skippedCount: Int
    let unrecordedCount: Int
    let adjustment: Adjustment

    var completionRate: Double? {
        guard scheduledCount > 0 else { return nil }
        return Double(completedCount) / Double(scheduledCount)
    }
}

enum WellnessWeeklyReviewBuilder {
    static func build(
        plan: WellnessPlan,
        records: [WellnessActionRecord],
        endingAt end: Date = .now,
        calendar: Calendar = .current
    ) -> WellnessWeeklyReview {
        guard plan.status == .active || plan.status == .paused else {
            return WellnessWeeklyReview(
                scheduledCount: 0,
                completedCount: 0,
                skippedCount: 0,
                unrecordedCount: 0,
                adjustment: .keepFlexible
            )
        }
        let endDay = calendar.startOfDay(for: end)
        let startDay = calendar.date(byAdding: .day, value: -6, to: endDay) ?? endDay
        var scheduledKeys: Set<String> = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else { continue }
            for action in WellnessDailySchedule.actions(for: plan, on: day, calendar: calendar) {
                scheduledKeys.insert(key(actionID: action.id, day: day, calendar: calendar))
            }
        }

        let relevantRecords = records.filter { record in
            let recordDay = calendar.startOfDay(for: record.day)
            return record.planID == plan.id && recordDay >= startDay && recordDay <= endDay
                && scheduledKeys.contains(key(actionID: record.actionID, day: recordDay, calendar: calendar))
        }
        let latestByKey = Dictionary(grouping: relevantRecords) { record in
            key(actionID: record.actionID, day: record.day, calendar: calendar)
        }.compactMapValues { $0.max(by: { $0.recordedAt < $1.recordedAt }) }
        let completed = latestByKey.values.filter { $0.outcome == .completed }.count
        let skipped = latestByKey.values.filter { $0.outcome == .skipped }.count
        let unrecorded = max(0, scheduledKeys.count - latestByKey.count)
        let rate = scheduledKeys.isEmpty ? nil : Double(completed) / Double(scheduledKeys.count)
        let adjustment: WellnessWeeklyReview.Adjustment
        if let rate, rate < 0.5 {
            adjustment = .considerSimplifying
        } else if unrecorded > completed + skipped {
            adjustment = .keepFlexible
        } else {
            adjustment = .maintain
        }
        return WellnessWeeklyReview(
            scheduledCount: scheduledKeys.count,
            completedCount: completed,
            skippedCount: skipped,
            unrecordedCount: unrecorded,
            adjustment: adjustment
        )
    }

    private static func key(actionID: UUID, day: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        return "\(actionID.uuidString)|\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

struct WellnessWeeklyReviewView: View {
    @StateObject private var planStore = WellnessPlanStore.shared
    @StateObject private var recordStore = WellnessActionRecordStore.shared

    var body: some View {
        List {
            if let plan = planStore.currentPlan {
                let review = WellnessWeeklyReviewBuilder.build(plan: plan, records: recordStore.records)
                Section("Last 7 Days") {
                    LabeledContent("Planned", value: "\(review.scheduledCount)")
                    LabeledContent("Completed", value: "\(review.completedCount)")
                    LabeledContent("Skipped", value: "\(review.skippedCount)")
                    LabeledContent("Not recorded", value: "\(review.unrecordedCount)")
                }
                Section("Reflection") {
                    Text(reflection(for: review))
                    Text("Not recorded does not mean failed. Use this review only to decide what feels realistic for the next week.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Your Choice") {
                    if plan.status == .active {
                        Button("Pause for now") { transition(plan, to: .paused) }
                        Button("Mark plan complete") { transition(plan, to: .completed) }
                    } else if plan.status == .paused {
                        Button("Resume plan") { transition(plan, to: .active) }
                    }
                    Button("End and archive plan", role: .destructive) { transition(plan, to: .archived) }
                }
            } else {
                ContentUnavailableView("No plan to review", systemImage: "calendar.badge.clock")
            }
        }
        .navigationTitle("Weekly Review")
    }

    private func reflection(for review: WellnessWeeklyReview) -> String {
        switch review.adjustment {
        case .considerSimplifying:
            "The current plan may be asking for too much. Consider fewer days or shorter actions; no change is made automatically."
        case .keepFlexible:
            "There are several days without records. Keep the plan flexible and record only what is useful to you."
        case .maintain:
            "The current rhythm appears workable from the records available. You can keep it or change it at any time."
        }
    }

    private func transition(_ plan: WellnessPlan, to status: WellnessPlan.Status) {
        if let updated = try? WellnessPlanLifecycle.transition(plan, to: status) {
            planStore.save(updated)
        }
    }
}
