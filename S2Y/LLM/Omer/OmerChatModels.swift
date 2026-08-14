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
    let consentPolicyVersion: String
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
    let billing: OmerBillingStatus?
    let toolEvents: [ToolEvent]
}

struct OmerBillingStatus: Decodable, Equatable, Sendable {
    let plan: String
    let usedTokens: Int
    let monthlyTokenLimit: Int
    let remainingTokens: Int
}

struct OmerMembershipStatus: Decodable, Equatable, Sendable {
    struct AIUsage: Decodable, Equatable, Sendable {
        let usedTokens: Int
        let monthlyTokenLimit: Int
        let remainingTokens: Int
    }

    struct Rewards: Decodable, Equatable, Sendable {
        let points: Int
        let qualifiedReferrals: Int
        let referralCode: String
        let shareUrl: URL
    }

    let plan: String
    let subscriptionStatus: String
    let billingInterval: String?
    let currentPeriodEnd: String?
    let ai: AIUsage
    let rewards: Rewards
    let manageUrl: URL
}

struct OmerLocalChatSyncRequest: Encodable {
    struct Message: Encodable {
        let id: UUID
        let role: String
        let content: String
    }

    let requestId: UUID
    let conversationId: UUID
    let source: String
    let consentPolicyVersion: String
    let messages: [Message]
}

struct OmerHealthSharingConsentReceiptRequest: Encodable {
    let id: UUID
    let policyVersion: String
    let change: String
    let changedScopes: [String]
    let resultingScopes: [String]
    let recordedAt: String

    init(receipt: HealthSharingConsentReceipt) {
        self.id = receipt.id
        self.policyVersion = receipt.policyVersion
        self.change = receipt.change.rawValue
        self.changedScopes = receipt.changedScopes.map(\.rawValue).sorted()
        self.resultingScopes = receipt.resultingAuthorization.grantedScopes.map(\.rawValue).sorted()
        self.recordedAt = ISO8601DateFormatter().string(from: receipt.recordedAt)
    }
}

struct OmerHealthSharingAuthorizationResponse: Decodable, Equatable, Sendable {
    let grantedScopes: [String]

    var recognizedGrantedScopes: Set<HealthSharingScope> {
        Set(grantedScopes.compactMap(HealthSharingScope.init(rawValue:)))
    }
}

struct OmerLocalChatSyncResponse: Decodable {
    let requestId: UUID
    let conversationId: UUID
    let synced: Bool
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

struct OmerChatSummary: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let createdAt: String
    let title: String
    let visibility: String
}

struct OmerChatHistorySection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let chats: [OmerChatSummary]

    static func grouped(
        _ chats: [OmerChatSummary],
        relativeTo now: Date = .now,
        calendar: Calendar = .current
    ) -> [OmerChatHistorySection] {
        let buckets = Dictionary(grouping: chats) { chat in
            section(for: chat.createdAt, relativeTo: now, calendar: calendar)
        }

        return Section.allCases.compactMap { section in
            guard let sectionChats = buckets[section], !sectionChats.isEmpty else {
                return nil
            }
            return OmerChatHistorySection(
                id: section.rawValue,
                title: section.title,
                chats: sectionChats
            )
        }
    }

    private static func section(
        for timestamp: String,
        relativeTo now: Date,
        calendar: Calendar
    ) -> Section {
        guard let date = ISO8601DateFormatter.s2yDate(from: timestamp) else {
            return .earlier
        }

        if calendar.isDate(date, inSameDayAs: now) {
            return .today
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), date >= weekAgo {
            return .previousSevenDays
        }
        return .earlier
    }

    private enum Section: String, CaseIterable {
        case today
        case yesterday
        case previousSevenDays
        case earlier

        var title: String {
            switch self {
            case .today: "Today"
            case .yesterday: "Yesterday"
            case .previousSevenDays: "Previous 7 days"
            case .earlier: "Earlier"
            }
        }
    }
}

private extension ISO8601DateFormatter {
    static func s2yDate(from timestamp: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: timestamp) {
            return date
        }
        return ISO8601DateFormatter().date(from: timestamp)
    }
}

struct OmerChatListResponse: Decodable, Sendable {
    let chats: [OmerChatSummary]
    let hasMore: Bool
}

struct OmerChatHistoryMessage: Codable, Identifiable, Sendable {
    let id: UUID
    let role: String
    let content: String
    let createdAt: String
}

struct OmerChatDetailResponse: Codable, Sendable {
    let chat: OmerChatSummary
    let messages: [OmerChatHistoryMessage]
}

struct OmerChatCacheSnapshot: Codable, Sendable {
    var chats: [OmerChatSummary]
    var details: [OmerChatDetailResponse]

    mutating func removeChat(id: UUID) {
        chats.removeAll { $0.id == id }
        details.removeAll { $0.chat.id == id }
    }
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
    case billing(OmerBillingStatus)
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
        case let .api(statusCode, message):
            return message ?? "Omer backend returned an error (\(statusCode))."
        case .firebaseUnavailable:
            return "Firebase authentication is not available in this app session."
        case .firebaseNotAuthenticated:
            return "Sign in before using Firebase authentication for Omer chat."
        }
    }
}
