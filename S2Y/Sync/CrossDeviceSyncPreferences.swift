//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation
import SwiftUI

enum CrossDeviceSyncCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case conversations
    case appPreferences
    case wellnessPlans

    var id: String { rawValue }

    var title: String {
        switch self {
        case .conversations:
            String(localized: "Conversations")
        case .appPreferences:
            String(localized: "App preferences")
        case .wellnessPlans:
            String(localized: "Wellbeing plans")
        }
    }

    var detail: String {
        switch self {
        case .conversations:
            String(localized: "Keep explicitly synchronized on-device chats in your private Omer history.")
        case .appPreferences:
            String(localized: "Keep AI provider and voice preferences consistent across signed-in devices.")
        case .wellnessPlans:
            String(localized: "Keep user-confirmed goals, actions, and plan status in your S2Y account.")
        }
    }

    var systemImage: String {
        switch self {
        case .conversations: "bubble.left.and.bubble.right"
        case .appPreferences: "slider.horizontal.3"
        case .wellnessPlans: "list.bullet.clipboard"
        }
    }

    var serviceDescription: String {
        switch self {
        case .conversations: "Omer"
        case .appPreferences, .wellnessPlans: "Firebase"
        }
    }
}

struct CrossDeviceSyncAuthorization: Codable, Equatable, Sendable {
    var enabledCategories: Set<CrossDeviceSyncCategory> = []
}

enum CrossDeviceSyncChange: String, Codable, Sendable {
    case enabled
    case disabled
}

struct CrossDeviceSyncReceipt: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let policyVersion: String
    let category: CrossDeviceSyncCategory
    let change: CrossDeviceSyncChange
    let recordedAt: Date
}

struct CrossDeviceSyncLedger: Codable, Equatable, Sendable {
    private(set) var receipts: [CrossDeviceSyncReceipt]
    let maximumReceiptCount: Int

    init(receipts: [CrossDeviceSyncReceipt] = [], maximumReceiptCount: Int = 30) {
        self.maximumReceiptCount = max(1, maximumReceiptCount)
        self.receipts = Array(receipts.prefix(self.maximumReceiptCount))
    }

    func authorization(policyVersion: String = CrossDeviceSyncPolicy.currentVersion) -> CrossDeviceSyncAuthorization {
        var enabled: Set<CrossDeviceSyncCategory> = []
        for receipt in receipts.reversed() where receipt.policyVersion == policyVersion {
            switch receipt.change {
            case .enabled:
                enabled.insert(receipt.category)
            case .disabled:
                enabled.remove(receipt.category)
            }
        }
        return CrossDeviceSyncAuthorization(enabledCategories: enabled)
    }

    mutating func set(
        _ category: CrossDeviceSyncCategory,
        enabled: Bool,
        at date: Date = .now
    ) {
        guard authorization().enabledCategories.contains(category) != enabled else {
            return
        }
        receipts.insert(
            CrossDeviceSyncReceipt(
                id: UUID(),
                policyVersion: CrossDeviceSyncPolicy.currentVersion,
                category: category,
                change: enabled ? .enabled : .disabled,
                recordedAt: date
            ),
            at: 0
        )
        receipts = Array(receipts.prefix(maximumReceiptCount))
    }
}

enum CrossDeviceSyncPolicy {
    static let currentVersion = "2026-08-13"

    static func permits(
        _ category: CrossDeviceSyncCategory,
        authorization: CrossDeviceSyncAuthorization
    ) -> Bool {
        authorization.enabledCategories.contains(category)
    }
}

@MainActor
final class CrossDeviceSyncPreferenceStore: ObservableObject {
    static let shared = CrossDeviceSyncPreferenceStore()

    @Published private(set) var ledger: CrossDeviceSyncLedger

    private let defaults: UserDefaults
    private let storageKey = "crossDeviceSync.preferences.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var authorization: CrossDeviceSyncAuthorization {
        var value = ledger.authorization()
        let conversationConsent = HealthSharingConsentPolicy.permits(
            .onDeviceConversationSync,
            authorization: HealthSharingConsentStore.shared.authorization
        )
        if conversationConsent {
            value.enabledCategories.insert(.conversations)
        } else {
            value.enabledCategories.remove(.conversations)
        }
        return value
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoder = JSONDecoder()
        self.ledger = defaults.data(forKey: storageKey)
            .flatMap { try? decoder.decode(CrossDeviceSyncLedger.self, from: $0) }
            ?? CrossDeviceSyncLedger()
    }

    func isEnabled(_ category: CrossDeviceSyncCategory) -> Bool {
        CrossDeviceSyncPolicy.permits(category, authorization: authorization)
    }

    func set(_ category: CrossDeviceSyncCategory, enabled: Bool, at date: Date = .now) {
        ledger.set(category, enabled: enabled, at: date)
        if category == .conversations {
            HealthSharingConsentStore.shared.set(.onDeviceConversationSync, granted: enabled, at: date)
        }
        persist()
    }

    func clear() {
        ledger = CrossDeviceSyncLedger()
        HealthSharingConsentStore.shared.set(.onDeviceConversationSync, granted: false)
        defaults.removeObject(forKey: storageKey)
    }

    private func persist() {
        guard let data = try? encoder.encode(ledger) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}
