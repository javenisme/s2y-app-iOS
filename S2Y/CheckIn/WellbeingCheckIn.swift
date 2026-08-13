//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

public struct WellbeingCheckInSnapshot: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let recordedAt: Date
    public let questionnaireIdentifier: String
    public let overallWellbeing: String?
    public let energyLevel: String?
    public let sleepQuality: String?
    public let sleepHours: Double?
    public let stressLevel: String?
    public let physicalActivity: String?
    public let mood: String?
    public let reportedSymptoms: [String]
    public let goalFocus: String?

    public init(
        id: UUID = UUID(),
        recordedAt: Date = .now,
        questionnaireIdentifier: String,
        overallWellbeing: String? = nil,
        energyLevel: String? = nil,
        sleepQuality: String? = nil,
        sleepHours: Double? = nil,
        stressLevel: String? = nil,
        physicalActivity: String? = nil,
        mood: String? = nil,
        reportedSymptoms: [String] = [],
        goalFocus: String? = nil
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.questionnaireIdentifier = Self.sanitized(questionnaireIdentifier, limit: 80)
        self.overallWellbeing = Self.sanitizedOptional(overallWellbeing)
        self.energyLevel = Self.sanitizedOptional(energyLevel)
        self.sleepQuality = Self.sanitizedOptional(sleepQuality)
        self.sleepHours = sleepHours.flatMap { (0...24).contains($0) ? $0 : nil }
        self.stressLevel = Self.sanitizedOptional(stressLevel)
        self.physicalActivity = Self.sanitizedOptional(physicalActivity)
        self.mood = Self.sanitizedOptional(mood)
        self.reportedSymptoms = Array(
            reportedSymptoms
                .map { Self.sanitized($0, limit: 80) }
                .filter { !$0.isEmpty }
                .prefix(8)
        )
        self.goalFocus = Self.sanitizedOptional(goalFocus)
    }

    private static func sanitizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = sanitized(value, limit: 80)
        return result.isEmpty ? nil : result
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

public enum WellbeingCheckInSnapshotBuilder {
    public static func build(
        responseData: Data,
        questionnaireIdentifier: String,
        id: UUID = UUID(),
        recordedAt: Date = .now
    ) throws -> WellbeingCheckInSnapshot {
        let object = try JSONSerialization.jsonObject(with: responseData)
        guard let response = object as? [String: Any] else {
            throw WellbeingCheckInSnapshotError.invalidResponse
        }
        let answers = flattenedAnswers(from: response["item"])

        return WellbeingCheckInSnapshot(
            id: id,
            recordedAt: recordedAt,
            questionnaireIdentifier: questionnaireIdentifier,
            overallWellbeing: answers["overall-wellness"]?.first,
            energyLevel: answers["energy-level"]?.first,
            sleepQuality: answers["sleep-quality"]?.first,
            sleepHours: answers["sleep-hours"]?.first.flatMap(Double.init),
            stressLevel: answers["stress-level"]?.first,
            physicalActivity: answers["physical-activity"]?.first,
            mood: answers["mood"]?.first,
            reportedSymptoms: answers["symptoms"] ?? [],
            goalFocus: answers["goals-today"]?.first
        )
    }

    private static func flattenedAnswers(from rawItems: Any?) -> [String: [String]] {
        guard let items = rawItems as? [[String: Any]] else {
            return [:]
        }
        var result: [String: [String]] = [:]
        for item in items {
            if let linkID = item["linkId"] as? String {
                result[linkID, default: []].append(contentsOf: answerValues(from: item["answer"]))
            }
            let nested = flattenedAnswers(from: item["item"])
            for (linkID, values) in nested {
                result[linkID, default: []].append(contentsOf: values)
            }
        }
        return result
    }

    private static func answerValues(from rawAnswers: Any?) -> [String] {
        guard let answers = rawAnswers as? [[String: Any]] else {
            return []
        }
        return answers.compactMap { answer in
            if let coding = answer["valueCoding"] as? [String: Any] {
                return coding["code"] as? String
            }
            if let string = answer["valueString"] as? String {
                return string
            }
            if let decimal = answer["valueDecimal"] as? NSNumber {
                return decimal.stringValue
            }
            if let integer = answer["valueInteger"] as? NSNumber {
                return integer.stringValue
            }
            if let boolean = answer["valueBoolean"] as? Bool {
                return boolean ? "true" : "false"
            }
            return nil
        }
    }
}

public enum WellbeingCheckInSnapshotError: LocalizedError, Sendable, Equatable {
    case invalidResponse

    public var errorDescription: String? {
        "The completed wellbeing check-in could not be summarized."
    }
}

public enum WellbeingCheckInContextBuilder {
    public static func build(
        from snapshots: [WellbeingCheckInSnapshot],
        maximumSnapshotCount: Int = 3,
        maximumCharacterCount: Int = 1_200
    ) -> String? {
        let snapshotLimit = max(1, maximumSnapshotCount)
        let characterLimit = max(1, maximumCharacterCount)
        var lines: [String] = []

        for snapshot in snapshots
            .sorted(by: { $0.recordedAt > $1.recordedAt })
            .prefix(snapshotLimit) {
            var fields = [
                "date=\(snapshot.recordedAt.formatted(.iso8601.year().month().day()))"
            ]
            append("overall", snapshot.overallWellbeing, to: &fields)
            append("energy", snapshot.energyLevel, to: &fields)
            append("sleep", snapshot.sleepQuality, to: &fields)
            append("stress", snapshot.stressLevel, to: &fields)
            append("mood", snapshot.mood, to: &fields)
            if !snapshot.reportedSymptoms.isEmpty {
                fields.append("symptoms=\(snapshot.reportedSymptoms.joined(separator: ","))")
            }
            append("goal", snapshot.goalFocus, to: &fields)

            let line = fields.joined(separator: "; ")
            let candidate = (lines + [line]).joined(separator: "\n")
            guard candidate.count <= characterLimit else {
                break
            }
            lines.append(line)
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func append(_ label: String, _ value: String?, to fields: inout [String]) {
        if let value {
            fields.append("\(label)=\(value)")
        }
    }
}
