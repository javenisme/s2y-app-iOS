//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

@MainActor
enum LocalHealthDataDeletionService {
    static func clear(_ category: LocalHealthDataCategory) async throws {
        switch category {
        case .chatCopies:
            await OmerChatService.shared.clearLocalChatCache()
        case .clinicalSummaries:
            try ClinicalRecordIndexStore.shared.clear()
        case .wellbeingCheckIns:
            try WellbeingCheckInStore.shared.clear()
        case .wellbeingPlans:
            WellnessPlanStore.shared.clear()
        case .wellbeingActionRecords:
            WellnessActionRecordStore.shared.clear()
        case .wellnessSessionActivity:
            WellnessSessionAuditStore.shared.clear()
        case .safetyActivity:
            HealthSafetyEventStore.shared.clear()
        case .sharingConsentReceipts:
            HealthSharingConsentStore.shared.clear()
        case .temporaryHealthCache:
            HealthKitCache.shared.clearAll()
        }
    }

    static func clearAll() async throws {
        for category in LocalHealthDataCategory.allCases {
            try await clear(category)
        }
    }
}
