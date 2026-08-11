//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT

import FirebaseAuth
import Foundation
import OSLog

actor OmerChatService {
    static let shared = OmerChatService()

    private static let defaultBaseURL = "https://chat.s2y.us"
    private static let defaultAgentID = "health-assistant"

    private let logger = Logger(subsystem: "com.s2y.app", category: "OmerChatService")
    private let sessionStore = OmerSessionStore.shared
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private init() {}

    func sendMessage(
        message: String,
        includeHealthContext: Bool,
        onEvent: @escaping @Sendable (OmerChatStreamEvent) -> Void
    ) async throws {
        let serviceURL = try configuredServiceURL()
        let sessionKey = "\(serviceURL.absoluteString)|firebase-v1"
        let conversationID = await existingOrNewConversationID(sessionKey: sessionKey)
        let requestID = UUID()
        let healthContext = await OmerHealthContextBuilder.buildSummary(
            for: message,
            includeHealthContext: includeHealthContext
        )
        let body = OmerMobileChatRequest(
            requestId: requestID,
            conversationId: conversationID,
            agentId: Self.defaultAgentID,
            message: .init(id: UUID(), text: message),
            locale: Locale.current.identifier,
            healthContext: healthContext,
            client: .init(
                platform: "ios",
                version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            )
        )

        let response: OmerMobileChatResponse
        do {
            response = try await performChatRequest(
                body,
                serviceURL: serviceURL,
                forceTokenRefresh: false
            )
        } catch OmerChatServiceError.unauthorized {
            logger.info("Refreshing expired Firebase ID token for Omer")
            response = try await performChatRequest(
                body,
                serviceURL: serviceURL,
                forceTokenRefresh: true
            )
        }

        let assistantMessageID = UUID().uuidString
        onEvent(.started(.init(
            chatId: response.conversationId.uuidString,
            userMessageId: body.message.id.uuidString,
            assistantMessageId: assistantMessageID
        )))
        onEvent(.delta(response.answer))
        for toolEvent in response.toolEvents {
            if toolEvent.type == "approval-required", let approvalID = toolEvent.approvalId {
                onEvent(.toolApprovalRequired(.init(
                    approvalId: approvalID,
                    toolCallId: toolEvent.toolCallId,
                    toolName: toolEvent.toolName
                )))
            } else if toolEvent.type == "result" {
                onEvent(.toolResult(toolEvent.toolName))
            }
        }
        await sessionStore.saveLastChatId(response.conversationId.uuidString, sessionKey: sessionKey)
        onEvent(.completed(.init(
            chatId: response.conversationId.uuidString,
            assistantMessageId: assistantMessageID
        )))
    }

    func decideTool(approvalId: String, approved: Bool) async throws -> OmerToolDecisionResponse {
        let serviceURL = try configuredServiceURL()
        let token = try await firebaseIDToken(forceRefresh: false)
        var request = URLRequest(
            url: serviceURL
                .appendingPathComponent("api/mobile/v1/tool-calls")
                .appendingPathComponent(approvalId)
                .appendingPathComponent("decision")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(OmerToolDecisionRequest(approved: approved))
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(OmerToolDecisionResponse.self, from: data)
    }

    func fetchAgents() async throws -> [OmerAgent] {
        let serviceURL = try configuredServiceURL()
        let token = try await firebaseIDToken(forceRefresh: false)
        var request = URLRequest(url: serviceURL.appendingPathComponent("api/mobile/v1/agents"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(OmerAgentsResponse.self, from: data).agents
    }

    private func configuredServiceURL() throws -> URL {
        let configuredBaseURL = Bundle.main.object(forInfoDictionaryKey: "OmerChat.BaseURL") as? String
        let normalizedBaseURL = (configuredBaseURL ?? Self.defaultBaseURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalizedBaseURL) else {
            throw OmerChatServiceError.invalidBaseURL
        }
        return url
    }

    private func existingOrNewConversationID(sessionKey: String) async -> UUID {
        if let storedID = await sessionStore.lastChatId(sessionKey: sessionKey),
           let conversationID = UUID(uuidString: storedID) {
            return conversationID
        }
        return UUID()
    }

    private func performChatRequest(
        _ body: OmerMobileChatRequest,
        serviceURL: URL,
        forceTokenRefresh: Bool
    ) async throws -> OmerMobileChatResponse {
        let token = try await firebaseIDToken(forceRefresh: forceTokenRefresh)
        var request = URLRequest(url: serviceURL.appendingPathComponent("api/mobile/v1/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(body.requestId.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(OmerMobileChatResponse.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OmerChatServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw OmerChatServiceError.unauthorized
            }
            let apiMessage = (try? decoder.decode(OmerAPIErrorResponse.self, from: data))?.error.message
            throw OmerChatServiceError.api(statusCode: httpResponse.statusCode, message: apiMessage)
        }
    }

    private func firebaseIDToken(forceRefresh: Bool) async throws -> String {
        guard !FeatureFlags.disableFirebase else {
            throw OmerChatServiceError.firebaseUnavailable
        }
        guard let user = Auth.auth().currentUser else {
            throw OmerChatServiceError.firebaseNotAuthenticated
        }

        return try await withCheckedThrowingContinuation { continuation in
            user.getIDTokenForcingRefresh(forceRefresh) { token, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let token, !token.isEmpty {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: OmerChatServiceError.firebaseNotAuthenticated)
                }
            }
        }
    }
}
