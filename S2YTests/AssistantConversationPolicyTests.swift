//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import XCTest
@testable import S2Y

final class AssistantConversationPolicyTests: XCTestCase {
    func testSpecificMetricAndTimeframeProceedWithoutClarification() {
        XCTAssertEqual(
            AssistantConversationPolicy.resolve(query: "Compare my sleep over the past 7 days"),
            .ready("Compare my sleep over the past 7 days")
        )
    }

    func testBroadHealthQuestionRequestsMetric() throws {
        guard case .needsClarification(let clarification) = AssistantConversationPolicy.resolve(
            query: "How is my health data?"
        ) else {
            return XCTFail("Expected metric clarification")
        }

        XCTAssertEqual(clarification.kind, .metric)
        XCTAssertEqual(clarification.options.map(\.id), ["steps", "sleep", "heart-rate", "active-energy"])
    }

    func testVagueTimeRequestsTimeframeAfterMetricIsKnown() throws {
        guard case .needsClarification(let clarification) = AssistantConversationPolicy.resolve(
            query: "How has my sleep been recently?"
        ) else {
            return XCTFail("Expected timeframe clarification")
        }

        XCTAssertEqual(clarification.kind, .timeframe)
        XCTAssertEqual(clarification.options.map(\.id), ["today", "7-days", "30-days"])
    }

    func testApplyingChoiceProducesExplicitQuery() throws {
        guard case .needsClarification(let clarification) = AssistantConversationPolicy.resolve(
            query: "How is my activity?"
        ) else {
            return XCTFail("Expected metric clarification")
        }
        let steps = try XCTUnwrap(clarification.options.first)

        XCTAssertEqual(
            AssistantConversationPolicy.applying(steps, to: clarification),
            "How is my activity?\nHealth metric: step count."
        )
    }
}
