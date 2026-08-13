//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

struct LocalHealthDataExportPackage: Codable, Sendable {
    let formatVersion: Int
    let generatedAt: Date
    let inventory: LocalHealthDataInventorySnapshot
    let localChatCache: OmerChatCacheSnapshot
    let clinicalRecordSummaries: [ClinicalRecordSummary]
    let wellbeingCheckIns: [WellbeingCheckInSnapshot]
    let wellbeingPlans: [WellnessPlan]
    let wellbeingActionRecords: [WellnessActionRecord]
    let wellnessSessionActivity: [WellnessSessionAuditRecord]
    let safetyActivity: [HealthSafetyEvent]
    let sharingConsentReceipts: [HealthSharingConsentReceipt]

    init(
        generatedAt: Date,
        inventory: LocalHealthDataInventorySnapshot,
        localChatCache: OmerChatCacheSnapshot,
        clinicalRecordSummaries: [ClinicalRecordSummary] = [],
        wellbeingCheckIns: [WellbeingCheckInSnapshot] = [],
        wellbeingPlans: [WellnessPlan] = [],
        wellbeingActionRecords: [WellnessActionRecord] = [],
        wellnessSessionActivity: [WellnessSessionAuditRecord] = [],
        safetyActivity: [HealthSafetyEvent] = [],
        sharingConsentReceipts: [HealthSharingConsentReceipt] = []
    ) {
        self.formatVersion = 1
        self.generatedAt = generatedAt
        self.inventory = inventory
        self.localChatCache = localChatCache
        self.clinicalRecordSummaries = clinicalRecordSummaries
        self.wellbeingCheckIns = wellbeingCheckIns
        self.wellbeingPlans = wellbeingPlans
        self.wellbeingActionRecords = wellbeingActionRecords
        self.wellnessSessionActivity = wellnessSessionActivity
        self.safetyActivity = safetyActivity
        self.sharingConsentReceipts = sharingConsentReceipts
    }
}

@MainActor
enum LocalHealthDataExportService {
    static func makePackage(at date: Date = .now) async -> LocalHealthDataExportPackage {
        let inventory = await LocalHealthDataInventory.current(at: date)
        let chatCache = await OmerChatService.shared.localExportSnapshot()
        return LocalHealthDataExportPackage(
            generatedAt: date,
            inventory: inventory,
            localChatCache: chatCache,
            clinicalRecordSummaries: ClinicalRecordIndexStore.shared.index?.records ?? [],
            wellbeingCheckIns: WellbeingCheckInStore.shared.snapshots,
            wellbeingPlans: WellnessPlanStore.shared.plans,
            wellbeingActionRecords: WellnessActionRecordStore.shared.records,
            wellnessSessionActivity: WellnessSessionAuditStore.shared.log.records,
            safetyActivity: HealthSafetyEventStore.shared.log.events,
            sharingConsentReceipts: HealthSharingConsentStore.shared.ledger.receipts
        )
    }

    nonisolated static func encodedData(for package: LocalHealthDataExportPackage) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(package)
    }
}
