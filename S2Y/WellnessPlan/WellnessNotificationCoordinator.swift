//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation
import UserNotifications

@MainActor
enum WellnessNotificationCoordinator {
    static func reconcile(_ plan: WellnessPlan) async throws {
        let center = UNUserNotificationCenter.current()
        await removePendingRequests(for: plan.id, center: center)
        for plannedRequest in WellnessNotificationPlanner.requests(for: plan) {
            let content = UNMutableNotificationContent()
            content.title = plannedRequest.title
            content.body = plannedRequest.body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: plannedRequest.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: plannedRequest.dateComponents,
                    repeats: true
                )
            )
            try await center.add(request)
        }
    }

    static func removePendingRequests(for planID: UUID) async {
        await removePendingRequests(for: planID, center: .current())
    }

    private static func removePendingRequests(
        for planID: UUID,
        center: UNUserNotificationCenter
    ) async {
        let prefix = WellnessNotificationPlanner.identifierPrefix(for: planID)
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
