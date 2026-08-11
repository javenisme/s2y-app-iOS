//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT

import Foundation

struct OmerMobileChatRequest: Encodable {
    struct Message: Encodable {
        let id: UUID
        let text: String
    }

    struct Client: Encodable {
        let platform: String
        let version: String
    }

    let requestId: UUID
    let conversationId: UUID
    let agentId: String
    let message: Message
    let locale: String
    let healthContext: [String: String]?
    let client: Client
}

struct OmerMobileChatResponse: Decodable {
    struct ToolEvent: Decodable {
        let type: String
        let approvalId: String?
        let toolCallId: String
        let toolName: String
    }

    let answer: String
    let conversationId: UUID
    let requestId: UUID
    let agentId: String
    let toolEvents: [ToolEvent]
}

struct OmerToolDecisionRequest: Encodable {
    let approved: Bool
}

struct OmerToolDecisionResponse: Decodable {
    let type: String
    let toolName: String
}

struct OmerAgent: Decodable, Identifiable, Sendable {
    struct Tool: Decodable, Sendable {
        let id: String
        let risk: String
        let requiresApproval: Bool
    }

    let id: String
    let name: String
    let description: String
    let capabilities: [String]
    let tools: [Tool]
}

struct OmerAgentsResponse: Decodable {
    let agents: [OmerAgent]
}

struct OmerAPIErrorResponse: Decodable {
    struct APIError: Decodable {
        let code: String
        let message: String
    }

    let error: APIError
}

struct OmerStartedPayload: Decodable, Sendable {
    let chatId: String
    let userMessageId: String
    let assistantMessageId: String
}

struct OmerCompletedPayload: Decodable, Sendable {
    let chatId: String
    let assistantMessageId: String
}

struct OmerToolApprovalPayload: Equatable, Identifiable, Sendable {
    var id: String { approvalId }
    let approvalId: String
    let toolCallId: String
    let toolName: String
}

enum OmerChatStreamEvent: Equatable, Sendable {
    case started(OmerStartedPayload)
    case delta(String)
    case completed(OmerCompletedPayload)
    case toolApprovalRequired(OmerToolApprovalPayload)
    case toolResult(String)
    case error(String)
}

extension OmerStartedPayload: Equatable {}
extension OmerCompletedPayload: Equatable {}

enum OmerChatServiceError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case unauthorized
    case api(statusCode: Int, message: String?)
    case firebaseUnavailable
    case firebaseNotAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Omer backend URL is invalid."
        case .invalidResponse:
            return "Omer backend returned an invalid response."
        case .unauthorized:
            return "Omer session is unauthorized. Please refresh the session and try again."
        case .api(let statusCode, let message):
            return message ?? "Omer backend returned an error (\(statusCode))."
        case .firebaseUnavailable:
            return "Firebase authentication is not available in this app session."
        case .firebaseNotAuthenticated:
            return "Sign in before using Firebase authentication for Omer chat."
        }
    }
}
