//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

public struct DescriptiveHealthRelationship: Sendable, Equatable {
    public enum Availability: String, Sendable, Equatable {
        case insufficientData
        case available
    }

    public enum Direction: String, Sendable, Equatable {
        case movesTogether
        case movesOppositely
        case noClearPattern
        case undetermined
    }

    public enum Strength: String, Sendable, Equatable {
        case weak
        case moderate
        case strong
        case undetermined
    }

    public let firstMetric: HealthKitService.MetricKind
    public let secondMetric: HealthKitService.MetricKind
    public let pairedDays: Int
    public let availability: Availability
    public let coefficient: Double?
    public let direction: Direction
    public let strength: Strength

    public var explanation: String {
        guard availability == .available else {
            return "There are not enough days where both metrics were observed to describe a relationship."
        }
        let pattern: String
        switch direction {
        case .movesTogether:
            pattern = "often moved in the same direction"
        case .movesOppositely:
            pattern = "often moved in opposite directions"
        case .noClearPattern:
            pattern = "did not show a clear linear pattern"
        case .undetermined:
            pattern = "could not be evaluated"
        }
        return "Across \(pairedDays) paired days, \(firstMetric.displayName) and \(secondMetric.displayName) \(pattern). This is a descriptive association, not evidence that one caused the other."
    }
}

public enum DescriptiveHealthRelationshipAnalyzer {
    public static let minimumPairedDays = 7

    public static func analyze(
        dataset: LongitudinalHealthDataset,
        first: HealthKitService.MetricKind,
        second: HealthKitService.MetricKind
    ) -> DescriptiveHealthRelationship {
        let pairs = dataset.pairedValues(first, second)
        guard pairs.count >= minimumPairedDays else {
            return unavailable(first: first, second: second, pairedDays: pairs.count)
        }

        let firstValues = pairs.map(\.first)
        let secondValues = pairs.map(\.second)
        guard let coefficient = pearson(firstValues, secondValues) else {
            return DescriptiveHealthRelationship(
                firstMetric: first,
                secondMetric: second,
                pairedDays: pairs.count,
                availability: .available,
                coefficient: 0,
                direction: .noClearPattern,
                strength: .weak
            )
        }

        let magnitude = abs(coefficient)
        let strength: DescriptiveHealthRelationship.Strength
        if magnitude >= 0.7 {
            strength = .strong
        } else if magnitude >= 0.4 {
            strength = .moderate
        } else {
            strength = .weak
        }

        let direction: DescriptiveHealthRelationship.Direction
        if magnitude < 0.2 {
            direction = .noClearPattern
        } else if coefficient > 0 {
            direction = .movesTogether
        } else {
            direction = .movesOppositely
        }

        return DescriptiveHealthRelationship(
            firstMetric: first,
            secondMetric: second,
            pairedDays: pairs.count,
            availability: .available,
            coefficient: coefficient,
            direction: direction,
            strength: strength
        )
    }

    private static func unavailable(
        first: HealthKitService.MetricKind,
        second: HealthKitService.MetricKind,
        pairedDays: Int
    ) -> DescriptiveHealthRelationship {
        DescriptiveHealthRelationship(
            firstMetric: first,
            secondMetric: second,
            pairedDays: pairedDays,
            availability: .insufficientData,
            coefficient: nil,
            direction: .undetermined,
            strength: .undetermined
        )
    }

    private static func pearson(_ first: [Double], _ second: [Double]) -> Double? {
        guard first.count == second.count, !first.isEmpty else { return nil }
        let count = Double(first.count)
        let firstMean = first.reduce(0, +) / count
        let secondMean = second.reduce(0, +) / count
        var numerator = 0.0
        var firstSquared = 0.0
        var secondSquared = 0.0
        for index in first.indices {
            let firstDelta = first[index] - firstMean
            let secondDelta = second[index] - secondMean
            numerator += firstDelta * secondDelta
            firstSquared += firstDelta * firstDelta
            secondSquared += secondDelta * secondDelta
        }
        let denominator = sqrt(firstSquared * secondSquared)
        guard denominator > 1e-9 else { return nil }
        return min(1, max(-1, numerator / denominator))
    }
}
