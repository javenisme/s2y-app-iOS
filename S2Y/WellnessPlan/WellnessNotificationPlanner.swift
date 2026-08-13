//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation

struct WellnessNotificationRequest: Sendable, Equatable {
    let identifier: String
    let title: String
    let body: String
    let dateComponents: DateComponents
}

enum WellnessNotificationPlanner {
    private static let identifierPrefix = "s2y.wellness"

    static func requests(for plan: WellnessPlan) -> [WellnessNotificationRequest] {
        guard plan.status == .active else { return [] }
        return plan.actions.flatMap { action -> [WellnessNotificationRequest] in
            guard let hour = action.reminderHour,
                  let minute = action.reminderMinute,
                  (0...23).contains(hour),
                  (0...59).contains(minute) else {
                return []
            }
            return action.effectiveWeekdays.sorted().map { weekday in
                WellnessNotificationRequest(
                    identifier: identifier(planID: plan.id, actionID: action.id, weekday: weekday),
                    title: "Wellbeing plan reminder",
                    body: "You have a wellbeing action you chose for today.",
                    dateComponents: DateComponents(
                        calendar: Calendar.current,
                        hour: hour,
                        minute: minute,
                        weekday: weekday
                    )
                )
            }
        }
    }

    static func identifierPrefix(for planID: UUID) -> String {
        "\(identifierPrefix).\(planID.uuidString)."
    }

    private static func identifier(planID: UUID, actionID: UUID, weekday: Int) -> String {
        "\(identifierPrefix(for: planID))\(actionID.uuidString).\(weekday)"
    }
}
