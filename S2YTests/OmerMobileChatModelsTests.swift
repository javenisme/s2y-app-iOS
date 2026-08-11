//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT

@testable import S2Y
import XCTest

final class OmerMobileChatModelsTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func testChatRequestMatchesFirebaseMobileAPIContract() throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let conversationID = try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let messageID = try XCTUnwrap(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let request = OmerMobileChatRequest(
            requestId: requestID,
            conversationId: conversationID,
            agentId: "health-assistant",
            message: .init(id: messageID, text: "I feel dizzy"),
            locale: "en_US",
            healthContext: ["recentSymptoms": "dizziness"],
            client: .init(platform: "ios", version: "1.0")
        )

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any])
        XCTAssertEqual(json["requestId"] as? String, requestID.uuidString)
        XCTAssertEqual(json["conversationId"] as? String, conversationID.uuidString)
        XCTAssertEqual(json["agentId"] as? String, "health-assistant")
        XCTAssertEqual((json["message"] as? [String: Any])?["text"] as? String, "I feel dizzy")
        XCTAssertEqual((json["client"] as? [String: Any])?["platform"] as? String, "ios")
    }

    func testChatResponseDecodesApprovalAndToolResult() throws {
        let data = Data(#"""
        {
          "answer": "I can log that symptom after you approve.",
          "conversationId": "22222222-2222-2222-2222-222222222222",
          "requestId": "11111111-1111-1111-1111-111111111111",
          "agentId": "health-assistant",
          "toolEvents": [
            {
              "type": "approval-required",
              "approvalId": "approval-1",
              "toolCallId": "tool-1",
              "toolName": "logSymptoms"
            },
            {
              "type": "result",
              "toolCallId": "tool-2",
              "toolName": "getCommonSymptoms"
            }
          ]
        }
        """#.utf8)

        let response = try decoder.decode(OmerMobileChatResponse.self, from: data)
        XCTAssertEqual(response.agentId, "health-assistant")
        XCTAssertEqual(response.toolEvents.count, 2)
        XCTAssertEqual(response.toolEvents[0].approvalId, "approval-1")
        XCTAssertEqual(response.toolEvents[0].toolName, "logSymptoms")
        XCTAssertEqual(response.toolEvents[1].type, "result")
    }

    func testAgentRegistryResponseDecodesRiskAndApprovalMetadata() throws {
        let data = Data(#"""
        {
          "agents": [{
            "id": "health-assistant",
            "name": "Health Assistant",
            "description": "Health-aware support",
            "capabilities": ["health-chat"],
            "tools": [{
              "id": "logSymptoms",
              "risk": "write",
              "requiresApproval": true
            }]
          }]
        }
        """#.utf8)

        let response = try decoder.decode(OmerAgentsResponse.self, from: data)
        let agent = try XCTUnwrap(response.agents.first)
        let tool = try XCTUnwrap(agent.tools.first)
        XCTAssertEqual(agent.id, "health-assistant")
        XCTAssertEqual(tool.risk, "write")
        XCTAssertTrue(tool.requiresApproval)
    }

    func testToolDecisionEncodesOnlyExplicitApproval() throws {
        let data = try encoder.encode(OmerToolDecisionRequest(approved: false))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json.count, 1)
        XCTAssertEqual(json["approved"] as? Bool, false)
    }
}
