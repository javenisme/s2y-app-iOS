//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

public struct WearableMeasurementInput: Sendable {
    public let id: String
    public let metricIdentifier: String
    public let value: Double
    public let unit: String
    public let startDate: Date
    public let endDate: Date
    public let timeZoneIdentifier: String
    public let sourceIdentifier: String
    public let sourceName: String
    public let deviceName: String?
    public let syncIdentifier: String?
    public let syncVersion: Int

    public init(
        id: String,
        metricIdentifier: String,
        value: Double,
        unit: String,
        startDate: Date,
        endDate: Date,
        timeZoneIdentifier: String,
        sourceIdentifier: String,
        sourceName: String,
        deviceName: String? = nil,
        syncIdentifier: String? = nil,
        syncVersion: Int = 0
    ) {
        self.id = id
        self.metricIdentifier = metricIdentifier
        self.value = value
        self.unit = unit
        self.startDate = startDate
        self.endDate = endDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.sourceIdentifier = sourceIdentifier
        self.sourceName = sourceName
        self.deviceName = deviceName
        self.syncIdentifier = syncIdentifier
        self.syncVersion = syncVersion
    }
}

public struct NormalizedWearableMeasurement: Identifiable, Sendable {
    public let id: String
    public let metricKind: HealthKitService.MetricKind
    public let value: Double
    public let unit: String
    public let originalValue: Double
    public let originalUnit: String
    public let startDate: Date
    public let endDate: Date
    public let timeZoneIdentifier: String
    public let sourceIdentifier: String
    public let sourceName: String
    public let deviceName: String?
    public let syncIdentifier: String?
    public let syncVersion: Int
}

public enum WearableMeasurementNormalizer {
    private struct Conversion {
        let kind: HealthKitService.MetricKind
        let canonicalUnit: String
        let convert: @Sendable (Double, String) -> Double?
    }

    /// Normalizes known HealthKit-compatible measurements and discards vendor-only scores.
    /// Measurements from different sources remain separate. A source's repeated sync identifier
    /// resolves deterministically to its highest sync version.
    public static func normalize(
        _ inputs: [WearableMeasurementInput]
    ) -> [NormalizedWearableMeasurement] {
        let deduplicated = inputs.reduce(into: [String: WearableMeasurementInput]()) { result, input in
            let key = input.syncIdentifier.map { "\(input.sourceIdentifier)|\($0)" }
                ?? "\(input.sourceIdentifier)|sample|\(input.id)"
            guard let current = result[key] else {
                result[key] = input
                return
            }
            if input.syncVersion > current.syncVersion {
                result[key] = input
            }
        }

        return deduplicated.values.compactMap(normalizeOne).sorted {
            if $0.startDate == $1.startDate {
                return $0.id < $1.id
            }
            return $0.startDate < $1.startDate
        }
    }

    private static func normalizeOne(
        _ input: WearableMeasurementInput
    ) -> NormalizedWearableMeasurement? {
        guard let conversion = conversions[input.metricIdentifier],
              let value = conversion.convert(input.value, normalizedUnit(input.unit)) else {
            return nil
        }
        let timeZone = TimeZone(identifier: input.timeZoneIdentifier)?.identifier ?? "UTC"
        return NormalizedWearableMeasurement(
            id: input.id,
            metricKind: conversion.kind,
            value: value,
            unit: conversion.canonicalUnit,
            originalValue: input.value,
            originalUnit: input.unit,
            startDate: input.startDate,
            endDate: input.endDate,
            timeZoneIdentifier: timeZone,
            sourceIdentifier: input.sourceIdentifier,
            sourceName: input.sourceName,
            deviceName: input.deviceName,
            syncIdentifier: input.syncIdentifier,
            syncVersion: input.syncVersion
        )
    }

    private static func normalizedUnit(_ unit: String) -> String {
        unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static let conversions: [String: Conversion] = [
        "HKQuantityTypeIdentifierStepCount": .init(kind: .steps, canonicalUnit: "count") { value, unit in
            ["count", "steps"].contains(unit) ? value : nil
        },
        "HKQuantityTypeIdentifierHeartRate": heartRateConversion(.heartRateAverage),
        "HKQuantityTypeIdentifierRestingHeartRate": heartRateConversion(.restingHeartRate),
        "HKQuantityTypeIdentifierWalkingHeartRateAverage": heartRateConversion(.walkingHeartRateAverage),
        "HKQuantityTypeIdentifierActiveEnergyBurned": .init(kind: .activeEnergy, canonicalUnit: "kcal") { value, unit in
            switch unit {
            case "kcal": value
            case "kj": value / 4.184
            default: nil
            }
        },
        "HKQuantityTypeIdentifierBodyMass": .init(kind: .bodyMass, canonicalUnit: "kg") { value, unit in
            switch unit {
            case "kg": value
            case "lb", "lbs": value * 0.453_592_37
            default: nil
            }
        },
        "HKCategoryTypeIdentifierSleepAnalysis": .init(kind: .sleepDurationHours, canonicalUnit: "h") { value, unit in
            switch unit {
            case "h", "hr", "hours": value
            case "min", "minutes": value / 60
            case "s", "sec", "seconds": value / 3_600
            default: nil
            }
        },
        "HKQuantityTypeIdentifierHeartRateVariabilitySDNN": .init(kind: .heartRateVariability, canonicalUnit: "ms") { value, unit in
            switch unit {
            case "ms": value
            case "s", "sec": value * 1_000
            default: nil
            }
        },
        "HKQuantityTypeIdentifierVO2Max": .init(kind: .vo2Max, canonicalUnit: "mL/kg/min") { value, unit in
            unit == "ml/kg/min" ? value : nil
        },
        "HKQuantityTypeIdentifierOxygenSaturation": .init(kind: .oxygenSaturation, canonicalUnit: "%") { value, unit in
            switch unit {
            case "%", "percent": value
            case "ratio": value * 100
            default: nil
            }
        },
        "HKQuantityTypeIdentifierBloodPressureSystolic": pressureConversion(.bloodPressureSystolic),
        "HKQuantityTypeIdentifierBloodPressureDiastolic": pressureConversion(.bloodPressureDiastolic),
        "HKQuantityTypeIdentifierBodyTemperature": .init(kind: .bodyTemperature, canonicalUnit: "°C") { value, unit in
            switch unit {
            case "°c", "c": value
            case "°f", "f": (value - 32) * 5 / 9
            default: nil
            }
        },
        "HKQuantityTypeIdentifierRespiratoryRate": .init(kind: .respiratoryRate, canonicalUnit: "breaths/min") { value, unit in
            ["breaths/min", "count/min"].contains(unit) ? value : nil
        }
    ]

    private static func heartRateConversion(_ kind: HealthKitService.MetricKind) -> Conversion {
        .init(kind: kind, canonicalUnit: "bpm") { value, unit in
            ["bpm", "count/min"].contains(unit) ? value : nil
        }
    }

    private static func pressureConversion(_ kind: HealthKitService.MetricKind) -> Conversion {
        .init(kind: kind, canonicalUnit: "mmHg") { value, unit in
            unit == "mmhg" ? value : nil
        }
    }
}
