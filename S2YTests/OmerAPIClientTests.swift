//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

@testable import S2Y
import Foundation
import Testing


@Suite("Omer API Client Tests")
struct OmerAPIClientTests {
    @Test("Decodes Cloudflare AutoRAG response")
    func decodesCloudflareAutoRAGResponse() throws {
        let data = try #require("""
        {
          "success": true,
          "result": {
            "response": "Pacing can help reduce post-exertional symptom flares.",
            "data": [
              {
                "title": "Long COVID pacing guide",
                "url": "https://example.com/pacing",
                "content": "Use an energy envelope and rest before symptoms worsen."
              }
            ]
          }
        }
        """.data(using: .utf8))

        let response = try OmerAPIClient.decodeLegacyResponse(data)

        #expect(response.answer == "Pacing can help reduce post-exertional symptom flares.")
        #expect(response.citations.first?.title == "Long COVID pacing guide")
        #expect(response.citations.first?.url == "https://example.com/pacing")
    }

    @Test("Rejects unsuccessful AutoRAG response")
    func rejectsUnsuccessfulAutoRAGResponse() throws {
        let data = try #require("""
        { "success": false, "result": { "response": "not an answer" } }
        """.data(using: .utf8))

        #expect(throws: LLMProviderError.self) {
            try OmerAPIClient.decodeLegacyResponse(data)
        }
    }

    @Test("Encodes Mobile API request and authentication")
    func encodesMobileAPIRequest() throws {
        let requestID = try #require(UUID(uuidString: "B931A06B-137F-4CD0-A984-7E37029F7F21"))
        let conversationID = try #require(UUID(uuidString: "DE9D8062-7285-451A-BF99-6329E79038F7"))
        let request = try OmerAPIClient.makeRequest(
            configuration: .init(
                gatewayURL: "https://omer.example.com",
                modelPath: "/api/mobile/v1/chat",
                bearerToken: "firebase-id-token",
                transport: .mobileV1
            ),
            query: "What helps with PEM?",
            messages: [
                .init(role: .system, content: "untrusted system prompt"),
                .init(role: .user, content: "Earlier question"),
                .init(role: .assistant, content: "Earlier answer"),
                .init(role: .user, content: "What helps with PEM?")
            ],
            healthContext: ["restingHeartRate": "88 bpm"],
            conversationID: conversationID,
            requestID: requestID
        )

        #expect(request.url?.absoluteString == "https://omer.example.com/api/mobile/v1/chat")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer firebase-id-token")
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == requestID.uuidString)

        let data = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["requestId"] as? String == requestID.uuidString.uppercased())
        #expect(object["conversationId"] as? String == conversationID.uuidString.uppercased())
        #expect((object["history"] as? [[String: Any]])?.count == 2)
        #expect((object["history"] as? [[String: Any]])?.contains { $0["role"] as? String == "system" } == false)
        #expect((object["healthContext"] as? [String: String])?["restingHeartRate"] == "88 bpm")
    }

    @Test("Decodes strict Mobile API response")
    func decodesMobileAPIResponse() throws {
        let requestID = try #require(UUID(uuidString: "B931A06B-137F-4CD0-A984-7E37029F7F21"))
        let data = try #require("""
        {
          "requestId": "B931A06B-137F-4CD0-A984-7E37029F7F21",
          "conversationId": "DE9D8062-7285-451A-BF99-6329E79038F7",
          "answer": "Use pacing and stay within your energy envelope.",
          "citations": [{"title":"Pacing guide","url":"https://example.com/pacing"}]
        }
        """.data(using: .utf8))

        let response = try OmerAPIClient.decodeMobileResponse(data, expectedRequestID: requestID)

        #expect(response.requestID == requestID)
        #expect(response.answer.contains("energy envelope"))
        #expect(response.citations.first?.title == "Pacing guide")
    }

    @Test("Rejects Mobile API response for another request")
    func rejectsMismatchedMobileResponse() throws {
        let data = try #require("""
        {
          "requestId": "B931A06B-137F-4CD0-A984-7E37029F7F21",
          "conversationId": "DE9D8062-7285-451A-BF99-6329E79038F7",
          "answer": "Answer",
          "citations": []
        }
        """.data(using: .utf8))

        #expect(throws: LLMProviderError.self) {
            try OmerAPIClient.decodeMobileResponse(data, expectedRequestID: UUID())
        }
    }

    @Test("Encodes legacy AutoRAG as query only")
    func encodesLegacyAutoRAGRequest() throws {
        let request = try OmerAPIClient.makeRequest(
            configuration: .init(
                gatewayURL: "https://api.cloudflare.com/client/v4/accounts/example/autorag/rags/s2y-ai-omer/ai-search",
                modelPath: "",
                bearerToken: "token",
                transport: .legacyAutoRAG
            ),
            query: "What helps with PEM?",
            messages: [.init(role: .user, content: "ignored")],
            healthContext: ["heartRate": "88 bpm"],
            conversationID: UUID(),
            requestID: UUID()
        )

        let data = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(object == ["query": "What helps with PEM?"])
    }

    @Test("Mobile API requires HTTPS and authentication")
    func validatesMobileSecurityRequirements() throws {
        let insecureConfiguration = OmerAPIClient.Configuration(
            gatewayURL: "http://omer.example.com",
            modelPath: "/api/mobile/v1/chat",
            bearerToken: "token",
            transport: .mobileV1
        )
        #expect(throws: LLMProviderError.self) {
            try OmerAPIClient.makeRequest(
                configuration: insecureConfiguration,
                query: "Question",
                messages: [],
                healthContext: [:],
                conversationID: UUID(),
                requestID: UUID()
            )
        }

        let unauthenticatedConfiguration = OmerAPIClient.Configuration(
            gatewayURL: "https://omer.example.com",
            modelPath: "/api/mobile/v1/chat",
            bearerToken: "",
            transport: .mobileV1
        )
        #expect(throws: LLMError.self) {
            try OmerAPIClient.makeRequest(
                configuration: unauthenticatedConfiguration,
                query: "Question",
                messages: [],
                healthContext: [:],
                conversationID: UUID(),
                requestID: UUID()
            )
        }
    }
}
