//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation

enum CrossDevicePreferenceValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case double(Double)
    case string(String)
}

@MainActor
final class CrossDeviceAppPreferenceStore {
    private enum ValueType {
        case bool(defaultValue: Bool)
        case double(defaultValue: Double)
        case string(defaultValue: String)
    }

    static let shared = CrossDeviceAppPreferenceStore()

    private static let allowedKeys: [(key: String, type: ValueType)] = [
        (StorageKeys.healthAssistantAIMode, .string(defaultValue: AssistantAIMode.onDevice.rawValue)),
        (StorageKeys.voiceEnabled, .bool(defaultValue: false)),
        (StorageKeys.voiceSpeakResponses, .bool(defaultValue: false)),
        (StorageKeys.voiceInputLanguageCode, .string(defaultValue: "")),
        (StorageKeys.voiceOutputLanguageCode, .string(defaultValue: "")),
        (StorageKeys.voiceSpeechRate, .double(defaultValue: 0.5))
    ]

    private let defaults: UserDefaults
    private let storageKey = "crossDeviceSync.appPreferenceRecords.v1"
    private let deviceIdentity: CrossDeviceDeviceIdentity
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private(set) var records: [CrossDeviceSyncRecord<CrossDevicePreferenceValue>]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.deviceIdentity = CrossDeviceDeviceIdentity(defaults: defaults)
        let decoder = JSONDecoder()
        self.records = defaults.data(forKey: storageKey)
            .flatMap { try? decoder.decode([CrossDeviceSyncRecord<CrossDevicePreferenceValue>].self, from: $0) }
            ?? []
    }

    private static func accepts(_ record: CrossDeviceSyncRecord<CrossDevicePreferenceValue>) -> Bool {
        guard record.modifiedBy.count <= 64,
              record.modifiedAt <= Date.now.addingTimeInterval(5 * 60),
              let definition = allowedKeys.first(where: { $0.key == record.id }) else {
            return false
        }
        guard let payload = record.payload else {
            return true
        }
        switch (definition.type, payload) {
        case (.bool, .bool), (.double, .double), (.string, .string):
            return true
        default:
            return false
        }
    }

    func recordCurrentValues(at date: Date = .now) -> [CrossDeviceSyncRecord<CrossDevicePreferenceValue>] {
        var changed = false
        for definition in Self.allowedKeys {
            let current = value(for: definition)
            guard records.first(where: { $0.id == definition.key })?.payload != current else {
                continue
            }
            records.removeAll { $0.id == definition.key }
            records.append(
                CrossDeviceSyncRecord(
                    id: definition.key,
                    payload: current,
                    modifiedAt: date,
                    modifiedBy: deviceIdentity.id
                )
            )
            changed = true
        }
        if changed {
            persist()
        }
        return records
    }

    func merge(_ remote: [CrossDeviceSyncRecord<CrossDevicePreferenceValue>]) {
        let safeRemote = remote.filter(Self.accepts)
        let merged = CrossDeviceSyncMerge.records(local: records, remote: safeRemote)
        guard merged != records else {
            return
        }
        records = merged
        apply(merged)
        persist()
    }

    private func value(for definition: (key: String, type: ValueType)) -> CrossDevicePreferenceValue {
        switch definition.type {
        case .bool(let defaultValue):
            return .bool(defaults.object(forKey: definition.key).map { _ in defaults.bool(forKey: definition.key) } ?? defaultValue)
        case .double(let defaultValue):
            return .double(defaults.object(forKey: definition.key).map { _ in defaults.double(forKey: definition.key) } ?? defaultValue)
        case .string(let defaultValue):
            return .string(defaults.string(forKey: definition.key) ?? defaultValue)
        }
    }

    private func apply(_ values: [CrossDeviceSyncRecord<CrossDevicePreferenceValue>]) {
        for record in values {
            guard let payload = record.payload else {
                defaults.removeObject(forKey: record.id)
                continue
            }
            switch payload {
            case .bool(let value):
                defaults.set(value, forKey: record.id)
            case .double(let value):
                defaults.set(value, forKey: record.id)
            case .string(let value):
                defaults.set(value, forKey: record.id)
            }
        }
    }

    private func persist() {
        guard let data = try? encoder.encode(records) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}
