//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

struct WellnessPlanDraft: Sendable, Equatable {
    let plan: WellnessPlan
    let rationale: [String]
    let limitations: [String]
}

enum WellnessPlanDraftBuilder {
    static func build(
        from report: PersonalHealthInsightReport,
        now: Date = .now
    ) -> WellnessPlanDraft {
        var actions: [WellnessAction] = []
        var rationale: [String] = []

        for deviation in report.deviations where deviation.direction != .undetermined {
            switch deviation.metricKind {
            case .sleepDurationHours:
                actions.append(WellnessAction(
                    title: "Keep a consistent wind-down window",
                    detail: "Choose a realistic bedtime routine and adjust it whenever it no longer fits.",
                    category: .sleepRoutine,
                    daysPerWeek: 5,
                    estimatedMinutes: 20
                ))
                rationale.append("Recent sleep was compared with your own earlier baseline using \(deviation.currentObservedDays) recent and \(deviation.baselineObservedDays) baseline days.")
            case .steps, .activeEnergy:
                actions.append(WellnessAction(
                    title: "Choose a comfortable movement break",
                    detail: "Try a short walk or another comfortable activity. Stop or adjust if it does not feel right.",
                    category: .movement,
                    daysPerWeek: 4,
                    estimatedMinutes: 10
                ))
                rationale.append("Recent \(deviation.metricKind.displayName.lowercased()) was compared with your own earlier baseline, not a population target.")
            case .restingHeartRate, .heartRateAverage, .heartRateVariability:
                actions.append(WellnessAction(
                    title: "Add a quiet recovery check-in",
                    detail: "Pause for slow breathing or a brief reflection. This is for general wellbeing, not treatment.",
                    category: .recovery,
                    daysPerWeek: 5,
                    estimatedMinutes: 5
                ))
                rationale.append("Recent \(deviation.metricKind.displayName.lowercased()) differed from your personal baseline; the plan does not interpret the change medically.")
            default:
                continue
            }
        }

        if actions.isEmpty {
            actions = [WellnessAction(
                title: "Complete a brief wellbeing check-in",
                detail: "Record how you feel so future summaries have more context.",
                category: .checkIn,
                daysPerWeek: 3,
                estimatedMinutes: 2,
                isOptional: true
            )]
            rationale.append("There is not enough personal baseline data for a metric-specific draft yet.")
        }

        let plan = WellnessPlan(
            title: "My two-week wellbeing plan",
            summary: "A flexible health-management draft based on your observed data. Review and edit it before activation.",
            status: .draft,
            origin: .assistantDraft,
            goals: [],
            actions: deduplicate(actions),
            createdAt: now,
            updatedAt: now
        )
        return WellnessPlanDraft(
            plan: plan,
            rationale: rationale,
            limitations: [
                "This draft is for general wellbeing and health management, not diagnosis or treatment.",
                "Associations in your data do not show that one behavior caused another outcome.",
                "S2Y does not choose a personal target. Add and confirm your own goal before activation.",
                "Nothing is scheduled or activated until you confirm the draft."
            ]
        )
    }

    private static func deduplicate(_ actions: [WellnessAction]) -> [WellnessAction] {
        var categories: Set<WellnessAction.Category> = []
        return actions.filter { categories.insert($0.category).inserted }
    }
}
