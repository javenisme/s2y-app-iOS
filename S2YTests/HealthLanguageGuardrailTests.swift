//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Testing
@testable import S2Y

struct HealthLanguageGuardrailTests {
    @Test("Trend direction stays descriptive")
    func descriptiveDirection() {
        #expect(HealthInterpretationPolicy.descriptiveDirection(changeRate: 0.2) == "higher than the start of the observed period")
        #expect(HealthInterpretationPolicy.descriptiveDirection(changeRate: -0.2) == "lower than the start of the observed period")
        #expect(HealthInterpretationPolicy.descriptiveDirection(changeRate: 0.01) == "similar to the start of the observed period")
    }

    @Test("Wellness actions are optional and non-clinical")
    func optionalActions() {
        let actions = HealthInterpretationPolicy.optionalWellnessActions(for: .sleepDurationHours)

        #expect(actions.contains("If you want"))
        #expect(actions.contains("optional general wellness guidance"))
        #expect(!actions.lowercased().contains("diagnose"))
        #expect(!actions.lowercased().contains("treat"))
    }

    @Test("Goals require user selection")
    func userSelectedGoal() {
        #expect(HealthInterpretationPolicy.userSelectedGoalBoundary.contains("does not choose"))
        #expect(HealthInterpretationPolicy.userSelectedGoalBoundary.contains("target you want"))
    }
}
