//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import HealthKit
import SwiftUI

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
    public let hasLinkedFHIRResource: Bool

    public func recency(relativeTo referenceDate: Date = .now) -> ClinicalRecordRecency {
        let age = max(0, referenceDate.timeIntervalSince(recordedAt))
        if age <= 90 * 24 * 60 * 60 {
            return .recent
        }
        if age <= 365 * 24 * 60 * 60 {
            return .older
        }
        return .historical
    }
}

public enum ClinicalRecordRecency: String, Codable, Sendable, Equatable {
    case recent
    case older
    case historical
}

public struct ClinicalRecordIndexAssessment: Sendable, Equatable {
    public let totalRecordCount: Int
    public let sourceCount: Int
    public let categoryCounts: [ClinicalRecordCategory: Int]
    public let selectedCategoriesWithoutReadableRecords: Set<ClinicalRecordCategory>
    public let newestRecordedAt: Date?
    public let oldestRecordedAt: Date?
}

public struct ClinicalRecordIndex: Codable, Sendable, Equatable {
    public private(set) var records: [ClinicalRecordSummary]
    public let selectedCategories: Set<ClinicalRecordCategory>
    public let refreshedAt: Date
    public let maximumRecordCount: Int

    public init(
        records: [ClinicalRecordSummary],
        selectedCategories: Set<ClinicalRecordCategory>,
        refreshedAt: Date = .now,
        maximumRecordCount: Int = 200
    ) {
        self.maximumRecordCount = max(1, maximumRecordCount)
        self.selectedCategories = selectedCategories
        self.refreshedAt = refreshedAt

        var seenIDs = Set<UUID>()
        self.records = records
            .filter { selectedCategories.contains($0.category) }
            .sorted { $0.recordedAt > $1.recordedAt }
            .filter { seenIDs.insert($0.id).inserted }
        self.records = Array(self.records.prefix(self.maximumRecordCount))
    }

    public var assessment: ClinicalRecordIndexAssessment {
        let categoryCounts = Dictionary(grouping: records, by: \.category)
            .mapValues(\.count)
        return ClinicalRecordIndexAssessment(
            totalRecordCount: records.count,
            sourceCount: Set(records.map(\.sourceName)).count,
            categoryCounts: categoryCounts,
            selectedCategoriesWithoutReadableRecords: selectedCategories.subtracting(categoryCounts.keys),
            newestRecordedAt: records.map(\.recordedAt).max(),
            oldestRecordedAt: records.map(\.recordedAt).min()
        )
    }
}

public enum ClinicalRecordContextBuilder {
    public static func build(
        from index: ClinicalRecordIndex?,
        maximumRecordCount: Int = 10,
        maximumCharacterCount: Int = 2_000
    ) -> String? {
        guard let index, !index.records.isEmpty else {
            return nil
        }
        let recordLimit = max(1, maximumRecordCount)
        let characterLimit = max(1, maximumCharacterCount)
        var lines: [String] = []

        for record in index.records.prefix(recordLimit) {
            let line = [
                "category=\(record.category.title)",
                "name=\(sanitized(record.displayName, limit: 120))",
                "date=\(record.recordedAt.formatted(.iso8601.year().month().day()))",
                "source=\(sanitized(record.sourceName, limit: 80))"
            ].joined(separator: "; ")
            let candidate = (lines + [line]).joined(separator: "\n")
            guard candidate.count <= characterLimit else {
                break
            }
            lines.append(line)
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func sanitized(_ value: String, limit: Int) -> String {
        String(
            value
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
                .prefix(limit)
        )
    }
}

@MainActor
final class ClinicalRecordIndexStore: ObservableObject {
    static let shared = ClinicalRecordIndexStore()

    @Published private(set) var index: ClinicalRecordIndex?

    private let fileManager: FileManager
    private let fileURL: URL
    private let encoder = JSONEncoder()

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.fileURL = fileURL ?? supportDirectory
            .appendingPathComponent("ClinicalRecords", isDirectory: true)
            .appendingPathComponent("summary-index.json")
        self.index = (try? Data(contentsOf: self.fileURL))
            .flatMap { try? JSONDecoder().decode(ClinicalRecordIndex.self, from: $0) }
    }

    func replace(with index: ClinicalRecordIndex) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(resourceValues)
        try encoder.encode(index).write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        self.index = index
    }

    func clear() throws {
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        index = nil
    }
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
                hasLinkedFHIRResource: record.fhirResource != nil
            )
        }
    }
}
