//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

public enum HealthSafetyEscalationLevel: String, Codable, Sendable, Equatable {
    case emergency
    case selfHarmCrisis
}

public struct HealthSafetyEscalation: Sendable, Equatable {
    public let level: HealthSafetyEscalationLevel
    public let signalCategories: Set<String>
    public let userMessage: String

    public init(
        level: HealthSafetyEscalationLevel,
        signalCategories: Set<String>,
        userMessage: String
    ) {
        self.level = level
        self.signalCategories = signalCategories
        self.userMessage = userMessage
    }
}

/// A small deterministic first-pass safety net that runs before any AI provider.
/// It does not diagnose or infer risk from HealthKit values.
public enum HealthSafetyTriage {
    private struct Signal {
        let category: String
        let phrases: [String]
    }

    private static let emergencySignals = [
        Signal(category: "breathing", phrases: [
            "can't breathe", "cannot breathe", "severe difficulty breathing", "无法呼吸", "呼吸非常困难"
        ]),
        Signal(category: "chest-pain", phrases: [
            "chest pain", "chest pressure", "胸痛", "胸口剧痛"
        ]),
        Signal(category: "stroke-signs", phrases: [
            "face drooping", "slurred speech", "one-sided weakness", "半边无力", "口齿不清", "脸歪"
        ]),
        Signal(category: "unresponsive", phrases: [
            "unconscious", "not waking up", "passed out and won't wake", "昏迷", "叫不醒"
        ]),
        Signal(category: "severe-bleeding", phrases: [
            "severe bleeding", "bleeding won't stop", "大量出血", "止不住血"
        ]),
        Signal(category: "overdose", phrases: [
            "overdose", "took too many pills", "药物过量", "吃了过量的药"
        ])
    ]

    private static let selfHarmSignals = [
        Signal(category: "self-harm", phrases: [
            "kill myself", "end my life", "suicide", "hurt myself", "自杀", "不想活了", "伤害自己"
        ])
    ]

    private static let negations = [
        "no ", "not ", "don't ", "do not ", "without ", "denies ", "没有", "并无", "不是"
    ]

    private static let clauseBoundaries = [
        " but ", " however ", ";", ".", ",", "但是", "但", "，", "。"
    ]

    public static func evaluate(_ text: String) -> HealthSafetyEscalation? {
        let normalized = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        let selfHarmCategories = matchedCategories(in: normalized, signals: selfHarmSignals)
        if !selfHarmCategories.isEmpty {
            return HealthSafetyEscalation(
                level: .selfHarmCrisis,
                signalCategories: selfHarmCategories,
                userMessage: "Your immediate safety matters. If you may act on these thoughts, call your local emergency number now. In the U.S. or Canada, call or text 988. If possible, move away from anything you could use to hurt yourself and contact someone you trust to stay with you."
            )
        }

        let emergencyCategories = matchedCategories(in: normalized, signals: emergencySignals)
        if !emergencyCategories.isEmpty {
            return HealthSafetyEscalation(
                level: .emergency,
                signalCategories: emergencyCategories,
                userMessage: "These symptoms may need urgent in-person help. Call your local emergency number now (911 in the U.S. or Canada). Do not drive yourself. If you can, ask someone nearby to stay with you and follow the dispatcher’s instructions."
            )
        }
        return nil
    }

    private static func matchedCategories(in text: String, signals: [Signal]) -> Set<String> {
        Set(signals.compactMap { signal in
            signal.phrases.contains { phrase in
                unnegatedRange(of: phrase, in: text) != nil
            } ? signal.category : nil
        })
    }

    private static func unnegatedRange(of phrase: String, in text: String) -> Range<String.Index>? {
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: phrase, range: searchStart ..< text.endIndex) {
            let contextStart = text.index(range.lowerBound, offsetBy: -32, limitedBy: text.startIndex) ?? text.startIndex
            let prefix = String(text[contextStart ..< range.lowerBound])
            let clausePrefix = clauseBoundaries.reduce(prefix) { current, boundary in
                current.components(separatedBy: boundary).last ?? current
            }
            if !negations.contains(where: clausePrefix.contains) {
                return range
            }
            searchStart = range.upperBound
        }
        return nil
    }
}
