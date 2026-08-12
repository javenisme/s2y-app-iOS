//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import HealthKit

public enum ClinicalRecordCategory: String, CaseIterable, Identifiable, Sendable {
    case allergies
    case conditions
    case immunizations
    case labResults
    case medications
    case procedures
    case vitalSigns

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .allergies: "Allergies"
        case .conditions: "Conditions"
        case .immunizations: "Immunizations"
        case .labResults: "Lab Results"
        case .medications: "Medications"
        case .procedures: "Procedures"
        case .vitalSigns: "Clinical Vital Signs"
        }
    }

    var clinicalType: HKClinicalType? {
        switch self {
        case .allergies:
            HKObjectType.clinicalType(forIdentifier: .allergyRecord)
        case .conditions:
            HKObjectType.clinicalType(forIdentifier: .conditionRecord)
        case .immunizations:
            HKObjectType.clinicalType(forIdentifier: .immunizationRecord)
        case .labResults:
            HKObjectType.clinicalType(forIdentifier: .labResultRecord)
        case .medications:
            HKObjectType.clinicalType(forIdentifier: .medicationRecord)
        case .procedures:
            HKObjectType.clinicalType(forIdentifier: .procedureRecord)
        case .vitalSigns:
            HKObjectType.clinicalType(forIdentifier: .vitalSignRecord)
        }
    }
}

public struct ClinicalRecordSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let category: ClinicalRecordCategory
    public let displayName: String
    public let recordedAt: Date
    public let sourceName: String
    public let fhirResourceIdentifier: String?
}

extension ClinicalRecordCategory: Codable {}

extension HealthKitService {
    public func requestClinicalRecordAuthorization(
        for categories: Set<ClinicalRecordCategory>
    ) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        let readTypes = Set(categories.compactMap(\.clinicalType))
        guard !readTypes.isEmpty else {
            return
        }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            throw HealthKitError.authorizationFailed
        }
    }

    public func fetchClinicalRecordSummaries(
        for category: ClinicalRecordCategory,
        limit: Int = 50
    ) async throws -> [ClinicalRecordSummary] {
        guard let clinicalType = category.clinicalType else {
            return []
        }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let records: [HKClinicalRecord] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: clinicalType,
                predicate: nil,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }
                continuation.resume(returning: samples as? [HKClinicalRecord] ?? [])
            }
            healthStore.execute(query)
        }

        return records.map { record in
            ClinicalRecordSummary(
                id: record.uuid,
                category: category,
                displayName: record.displayName,
                recordedAt: record.startDate,
                sourceName: record.sourceRevision.source.name,
                fhirResourceIdentifier: record.fhirResource?.identifier
            )
        }
    }
}
