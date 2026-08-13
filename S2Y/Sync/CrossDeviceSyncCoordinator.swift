//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import OSLog

enum CrossDeviceSyncState: Equatable, Sendable {
    case disabled
    case needsSignIn
    case syncing
    case saved(Date)
    case failed(String)

    var title: String {
        switch self {
        case .disabled: String(localized: "Off")
        case .needsSignIn: String(localized: "Sign in required")
        case .syncing: String(localized: "Syncing…")
        case .saved: String(localized: "Saved for sync")
        case .failed: String(localized: "Needs attention")
        }
    }
}

enum CrossDeviceSyncCloudError: LocalizedError {
    case invalidPayload
    case payloadTooLarge
    case firebaseUnavailable
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidPayload: "The synchronized data could not be decoded safely."
        case .payloadTooLarge: "The synchronized data is too large for one account record."
        case .firebaseUnavailable: "Firebase account sync is unavailable in this app session."
        case .notAuthenticated: "Sign in to your S2Y account before enabling cross-device sync."
        }
    }
}

private struct CrossDeviceSyncCloudStore {
    private let maximumPayloadBytes = 700_000

    func read<Payload: Codable & Equatable & Sendable>(
        category: CrossDeviceSyncCategory,
        userID: String
    ) async throws -> [CrossDeviceSyncRecord<Payload>] {
        let snapshot = try await document(category: category, userID: userID).getDocument(source: .default)
        guard snapshot.exists else {
            return []
        }
        guard let encoded = snapshot.data()?["payload"] as? String,
              let data = Data(base64Encoded: encoded),
              data.count <= maximumPayloadBytes else {
            throw CrossDeviceSyncCloudError.invalidPayload
        }
        return try JSONDecoder().decode([CrossDeviceSyncRecord<Payload>].self, from: data)
    }

    func write<Payload: Codable & Equatable & Sendable>(
        _ records: [CrossDeviceSyncRecord<Payload>],
        category: CrossDeviceSyncCategory,
        userID: String,
        deviceID: String
    ) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(records)
        guard data.count <= maximumPayloadBytes else {
            throw CrossDeviceSyncCloudError.payloadTooLarge
        }
        try await document(category: category, userID: userID).setData([
            "schemaVersion": 1,
            "category": category.rawValue,
            "payload": data.base64EncodedString(),
            "clientUpdatedAt": Timestamp(date: .now),
            "modifiedBy": deviceID
        ])
    }

    private func document(category: CrossDeviceSyncCategory, userID: String) -> DocumentReference {
        FirebaseConfiguration.userCollection
            .document(userID)
            .collection("sync")
            .document(category.rawValue)
    }
}

@MainActor
final class CrossDeviceSyncCoordinator: ObservableObject {
    static let shared = CrossDeviceSyncCoordinator()

    @Published private(set) var states: [CrossDeviceSyncCategory: CrossDeviceSyncState] = [:]

    private let preferences = CrossDeviceSyncPreferenceStore.shared
    private let appPreferences = CrossDeviceAppPreferenceStore.shared
    private let plans = WellnessPlanStore.shared
    private let cloud = CrossDeviceSyncCloudStore()
    private let deviceID = CrossDeviceDeviceIdentity().id
    private let logger = Logger(subsystem: "com.s2y.app", category: "CrossDeviceSync")
    private var observers: [any NSObjectProtocol] = []
    private var syncTasks: [CrossDeviceSyncCategory: Task<Void, Never>] = [:]
    private var syncGenerations: [CrossDeviceSyncCategory: UUID] = [:]
    private var started = false

    private init() {
        for category in CrossDeviceSyncCategory.allCases {
            states[category] = .disabled
        }
    }

    func start() async {
        guard !started else {
            await reconcileEnabledCategories()
            return
        }
        started = true
        observeLocalChanges()
        await reconcileEnabledCategories()
    }

    func isEnabled(_ category: CrossDeviceSyncCategory) -> Bool {
        preferences.isEnabled(category)
    }

    func set(_ category: CrossDeviceSyncCategory, enabled: Bool) {
        preferences.set(category, enabled: enabled)
        syncTasks[category]?.cancel()
        syncTasks[category] = nil
        syncGenerations[category] = nil
        guard enabled else {
            states[category] = .disabled
            return
        }
        schedule(category, delayNanoseconds: 0)
    }

    func retry(_ category: CrossDeviceSyncCategory) {
        guard isEnabled(category) else {
            return
        }
        schedule(category, delayNanoseconds: 0)
    }

    private func reconcileEnabledCategories() async {
        for category in CrossDeviceSyncCategory.allCases {
            if isEnabled(category) {
                await synchronize(category)
            } else {
                states[category] = .disabled
            }
        }
    }

    private func observeLocalChanges() {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: UserDefaults.standard,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    guard CrossDeviceSyncCoordinator.shared.isEnabled(.appPreferences) else {
                        return
                    }
                    CrossDeviceSyncCoordinator.shared.schedule(.appPreferences)
                }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .wellnessPlansDidChange,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    guard CrossDeviceSyncCoordinator.shared.isEnabled(.wellnessPlans) else {
                        return
                    }
                    CrossDeviceSyncCoordinator.shared.schedule(.wellnessPlans)
                }
            }
        )
    }

    private func schedule(
        _ category: CrossDeviceSyncCategory,
        delayNanoseconds: UInt64 = 500_000_000
    ) {
        syncTasks[category]?.cancel()
        let generation = UUID()
        syncGenerations[category] = generation
        syncTasks[category] = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled, syncGenerations[category] == generation else {
                return
            }
            await synchronize(category, generation: generation)
            if syncGenerations[category] == generation {
                syncTasks[category] = nil
                syncGenerations[category] = nil
            }
        }
    }

    private func synchronize(_ category: CrossDeviceSyncCategory, generation: UUID? = nil) async {
        guard isCurrent(category, generation: generation) else {
            return
        }
        guard isEnabled(category) else {
            states[category] = .disabled
            return
        }
        guard !FeatureFlags.disableFirebase, FirebaseApp.app() != nil else {
            states[category] = .failed(CrossDeviceSyncCloudError.firebaseUnavailable.localizedDescription)
            return
        }
        guard let userID = Auth.auth().currentUser?.uid else {
            states[category] = .needsSignIn
            return
        }

        states[category] = .syncing
        do {
            try await performSynchronization(category, userID: userID)
            guard isCurrent(category, generation: generation) else {
                return
            }
            guard isEnabled(category) else {
                states[category] = .disabled
                return
            }
            states[category] = .saved(.now)
        } catch {
            guard isCurrent(category, generation: generation) else {
                return
            }
            logger.error("Sync failed for \(category.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            states[category] = .failed(error.localizedDescription)
        }
    }

    private func performSynchronization(_ category: CrossDeviceSyncCategory, userID: String) async throws {
        switch category {
        case .conversations:
            _ = try await OmerChatService.shared.syncPendingOnDeviceChats(
                authorization: HealthSharingConsentStore.shared.authorization
            )
        case .appPreferences:
            try await synchronizeAppPreferences(userID: userID)
        case .wellnessPlans:
            try await synchronizeWellnessPlans(userID: userID)
        }
    }

    private func isCurrent(_ category: CrossDeviceSyncCategory, generation: UUID?) -> Bool {
        generation.map { syncGenerations[category] == $0 } ?? true
    }

    private func synchronizeAppPreferences(userID: String) async throws {
        let remote: [CrossDeviceSyncRecord<CrossDevicePreferenceValue>] = try await cloud.read(
            category: .appPreferences,
            userID: userID
        )
        if appPreferences.records.isEmpty, !remote.isEmpty {
            appPreferences.merge(remote)
        } else {
            _ = appPreferences.recordCurrentValues()
            appPreferences.merge(remote)
        }
        guard isEnabled(.appPreferences) else {
            return
        }
        try await cloud.write(
            appPreferences.records,
            category: .appPreferences,
            userID: userID,
            deviceID: deviceID
        )
    }

    private func synchronizeWellnessPlans(userID: String) async throws {
        let remote: [CrossDeviceSyncRecord<WellnessPlan>] = try await cloud.read(
            category: .wellnessPlans,
            userID: userID
        )
        plans.mergeCrossDeviceSyncRecords(remote)
        guard isEnabled(.wellnessPlans) else {
            return
        }
        try await cloud.write(
            plans.crossDeviceSyncRecords(),
            category: .wellnessPlans,
            userID: userID,
            deviceID: deviceID
        )
    }
}
