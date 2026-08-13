//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

@testable import S2Y
import XCTest

final class CrossDeviceSyncPayloadTests: XCTestCase {
    @MainActor
    func testPreferenceMergeAppliesNewerAllowedValue() throws {
        let defaults = try isolatedDefaults()
        defaults.set(AssistantAIMode.omer.rawValue, forKey: StorageKeys.healthAssistantAIMode)
        let store = CrossDeviceAppPreferenceStore(defaults: defaults)
        _ = store.recordCurrentValues(at: Date(timeIntervalSince1970: 10))
        let remote = CrossDeviceSyncRecord(
            id: StorageKeys.healthAssistantAIMode,
            payload: CrossDevicePreferenceValue.string(AssistantAIMode.onDevice.rawValue),
            modifiedAt: Date(timeIntervalSince1970: 20),
            modifiedBy: "remote-device"
        )

        store.merge([remote])

        XCTAssertEqual(defaults.string(forKey: StorageKeys.healthAssistantAIMode), AssistantAIMode.onDevice.rawValue)
        XCTAssertEqual(try XCTUnwrap(store.records.first { $0.id == remote.id }), remote)
    }

    @MainActor
    func testPreferenceMergeRejectsUnknownKeys() throws {
        let defaults = try isolatedDefaults()
        let store = CrossDeviceAppPreferenceStore(defaults: defaults)
        let unsafe = CrossDeviceSyncRecord(
            id: "healthkit.raw.samples",
            payload: CrossDevicePreferenceValue.string("must-not-sync"),
            modifiedAt: .now,
            modifiedBy: "remote-device"
        )

        store.merge([unsafe])

        XCTAssertNil(defaults.object(forKey: unsafe.id))
        XCTAssertFalse(store.records.contains { $0.id == unsafe.id })
    }

    @MainActor
    func testPreferenceMergeRejectsWrongValueType() throws {
        let defaults = try isolatedDefaults()
        let store = CrossDeviceAppPreferenceStore(defaults: defaults)
        let unsafe = CrossDeviceSyncRecord(
            id: StorageKeys.voiceEnabled,
            payload: CrossDevicePreferenceValue.string("true"),
            modifiedAt: .now,
            modifiedBy: "remote-device"
        )

        store.merge([unsafe])

        XCTAssertNil(defaults.object(forKey: StorageKeys.voiceEnabled))
        XCTAssertFalse(store.records.contains { $0.id == unsafe.id })
    }

    @MainActor
    func testPlanMergeUsesNewerRemoteRecord() throws {
        let defaults = try isolatedDefaults()
        let store = WellnessPlanStore(defaults: defaults)
        let original = plan(title: "Local", updatedAt: Date(timeIntervalSince1970: 10))
        store.save(original)
        var remotePlan = original
        remotePlan.title = "Remote"
        remotePlan.updatedAt = Date.now.addingTimeInterval(10)
        let remote = CrossDeviceSyncRecord(
            id: original.id.uuidString,
            payload: remotePlan,
            modifiedAt: Date.now.addingTimeInterval(10),
            modifiedBy: "remote-device"
        )

        store.mergeCrossDeviceSyncRecords([remote])

        XCTAssertEqual(store.plans.first?.title, "Remote")
        XCTAssertEqual(store.crossDeviceSyncRecords().first, remote)
    }

    @MainActor
    func testPlanDeletionTombstoneSurvivesReloadAndRejectsOlderRemotePlan() throws {
        let defaults = try isolatedDefaults()
        let store = WellnessPlanStore(defaults: defaults)
        let value = plan(title: "Delete me", updatedAt: Date(timeIntervalSince1970: 10))
        store.save(value)
        store.clear()
        let tombstone = try XCTUnwrap(store.crossDeviceSyncRecords().first { $0.id == value.id.uuidString })
        let olderRemote = CrossDeviceSyncRecord(
            id: value.id.uuidString,
            payload: value,
            modifiedAt: tombstone.modifiedAt.addingTimeInterval(-1),
            modifiedBy: "remote-device"
        )

        let reloaded = WellnessPlanStore(defaults: defaults)
        reloaded.mergeCrossDeviceSyncRecords([olderRemote])

        XCTAssertTrue(reloaded.plans.isEmpty)
        XCTAssertTrue(try XCTUnwrap(reloaded.crossDeviceSyncRecords().first).isDeletion)
    }

    @MainActor
    func testPlanMergeRejectsMismatchedRecordIdentity() throws {
        let defaults = try isolatedDefaults()
        let store = WellnessPlanStore(defaults: defaults)
        let remotePlan = plan(title: "Unexpected", updatedAt: .now)
        let unsafe = CrossDeviceSyncRecord(
            id: UUID().uuidString,
            payload: remotePlan,
            modifiedAt: .now,
            modifiedBy: "remote-device"
        )

        store.mergeCrossDeviceSyncRecords([unsafe])

        XCTAssertTrue(store.plans.isEmpty)
        XCTAssertTrue(store.crossDeviceSyncRecords().isEmpty)
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "CrossDeviceSyncPayloadTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func plan(title: String, updatedAt: Date) -> WellnessPlan {
        WellnessPlan(
            title: title,
            summary: "User-created plan",
            origin: .userCreated,
            goals: [],
            actions: [],
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }
}
