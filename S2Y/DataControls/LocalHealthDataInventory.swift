//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

public enum LocalHealthDataCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case chatCopies
    case clinicalSummaries
    case importedClinicalDocuments
    case wellbeingCheckIns
    case wellbeingPlans
    case wellbeingActionRecords
    case wellnessSessionActivity
    case safetyActivity
    case sharingConsentReceipts
    case temporaryHealthCache

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chatCopies: "Local chat copies"
        case .clinicalSummaries: "Clinical record summaries"
        case .importedClinicalDocuments: "Imported clinical documents"
        case .wellbeingCheckIns: "Daily wellbeing check-ins"
        case .wellbeingPlans: "Wellbeing plans"
        case .wellbeingActionRecords: "Plan action history"
        case .wellnessSessionActivity: "Connected wellness session activity"
        case .safetyActivity: "Safety routing activity"
        case .sharingConsentReceipts: "Sharing consent receipts"
        case .temporaryHealthCache: "Temporary Health data cache"
        }
    }

    public var storageDescription: String {
        switch self {
        case .temporaryHealthCache:
            "Memory only; expires automatically"
        default:
            "Stored on this iPhone"
        }
    }
}

public struct LocalHealthDataInventoryItem: Codable, Identifiable, Sendable, Equatable {
    public let category: LocalHealthDataCategory
    public let itemCount: Int
    public let storageDescription: String

    public var id: LocalHealthDataCategory { category }

    public init(category: LocalHealthDataCategory, itemCount: Int) {
        self.category = category
        self.itemCount = max(0, itemCount)
        self.storageDescription = category.storageDescription
    }
}

public struct LocalHealthDataInventorySnapshot: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let items: [LocalHealthDataInventoryItem]

    public init(generatedAt: Date = .now, counts: [LocalHealthDataCategory: Int]) {
        self.generatedAt = generatedAt
        self.items = LocalHealthDataCategory.allCases.map { category in
            LocalHealthDataInventoryItem(category: category, itemCount: counts[category] ?? 0)
        }
    }
}

@MainActor
enum LocalHealthDataInventory {
    static func current(at date: Date = .now) async -> LocalHealthDataInventorySnapshot {
        let chatCount = await OmerChatService.shared.cachedChats(limit: 50).count
        return LocalHealthDataInventorySnapshot(generatedAt: date, counts: [
            .chatCopies: chatCount,
            .clinicalSummaries: ClinicalRecordIndexStore.shared.index?.records.count ?? 0,
            .importedClinicalDocuments: ClinicalDocumentStore.shared.documents.count,
            .wellbeingCheckIns: WellbeingCheckInStore.shared.snapshots.count,
            .wellbeingPlans: WellnessPlanStore.shared.plans.count,
            .wellbeingActionRecords: WellnessActionRecordStore.shared.records.count,
            .wellnessSessionActivity: WellnessSessionAuditStore.shared.log.records.count,
            .safetyActivity: HealthSafetyEventStore.shared.log.events.count,
            .sharingConsentReceipts: HealthSharingConsentStore.shared.ledger.receipts.count,
            .temporaryHealthCache: HealthKitCache.shared.entryCount
        ])
    }
}
