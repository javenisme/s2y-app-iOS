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
    private let cacheURL: URL
    private var chatCache: OmerChatCacheSnapshot

    private init() {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cacheDirectory = applicationSupport.appendingPathComponent("OmerChatCache", isDirectory: true)
        let historyURL = cacheDirectory.appendingPathComponent("history.json")
        self.cacheURL = historyURL
        self.chatCache = (try? Data(contentsOf: historyURL))
            .flatMap { try? JSONDecoder().decode(OmerChatCacheSnapshot.self, from: $0) }
            ?? OmerChatCacheSnapshot(chats: [], details: [])
    }

    func sendMessage(
        message: String,
        authorization: HealthSharingAuthorization,
        includeHealthContext: Bool,
        onEvent: @escaping @Sendable (OmerChatStreamEvent) -> Void
    ) async throws {
        try HealthSharingConsentPolicy.require([.omerChatText], authorization: authorization)
        let serviceURL = try configuredServiceURL()
        let sessionKey = sessionKey(for: serviceURL)
        let conversationID = await existingOrNewConversationID(sessionKey: sessionKey)
        let requestID = UUID()
        let healthContext = await OmerHealthContextBuilder.buildSummary(
            for: message,
            includeHealthContext: includeHealthContext && HealthSharingConsentPolicy.permits(
                .relevantHealthSummary,
                authorization: authorization
            )
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

        let assistantMessageID = UUID()
        cacheExchange(
            conversationID: response.conversationId,
            userMessageID: body.message.id,
            userText: message,
            assistantMessageID: assistantMessageID,
            assistantText: response.answer,
            visibility: "private"
        )
        onEvent(.started(.init(
            chatId: response.conversationId.uuidString,
            userMessageId: body.message.id.uuidString,
            assistantMessageId: assistantMessageID.uuidString
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
        if let billing = response.billing {
            onEvent(.billing(billing))
        }
        await sessionStore.saveLastChatId(response.conversationId.uuidString, sessionKey: sessionKey)
        onEvent(.completed(.init(
            chatId: response.conversationId.uuidString,
            assistantMessageId: assistantMessageID.uuidString
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

    func fetchChats(limit: Int = 20, before: UUID? = nil) async throws -> OmerChatListResponse {
        let serviceURL = try configuredServiceURL()
        var components = URLComponents(
            url: serviceURL.appendingPathComponent("api/mobile/v1/chats"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50)))
        ] + (before.map { [URLQueryItem(name: "before", value: $0.uuidString)] } ?? [])
        guard let url = components?.url else {
            throw OmerChatServiceError.invalidBaseURL
        }
        let data = try await authenticatedGET(url: url)
        let response = try decoder.decode(OmerChatListResponse.self, from: data)
        mergeCachedSummaries(response.chats)
        return response
    }

    func fetchChat(id: UUID) async throws -> OmerChatDetailResponse {
        let serviceURL = try configuredServiceURL()
        let url = serviceURL
            .appendingPathComponent("api/mobile/v1/chats")
            .appendingPathComponent(id.uuidString)
        let data = try await authenticatedGET(url: url)
        let detail = try decoder.decode(OmerChatDetailResponse.self, from: data)
        cacheDetail(detail)
        return detail
    }

    func cachedChats(limit: Int = 50) -> [OmerChatSummary] {
        Array(chatCache.chats.prefix(max(1, limit)))
    }

    func cachedChat(id: UUID) -> OmerChatDetailResponse? {
        chatCache.details.first { $0.chat.id == id }
    }

    func selectChat(id: UUID) async throws {
        let serviceURL = try configuredServiceURL()
        await sessionStore.saveLastChatId(id.uuidString, sessionKey: sessionKey(for: serviceURL))
    }

    func startNewChat() async throws {
        let serviceURL = try configuredServiceURL()
        await sessionStore.saveLastChatId(nil, sessionKey: sessionKey(for: serviceURL))
    }

    func clearLocalChatCache() async {
        chatCache = OmerChatCacheSnapshot(chats: [], details: [])
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            do {
                try FileManager.default.removeItem(at: cacheURL)
            } catch {
                logger.error("Failed to clear local chat cache: \(error.localizedDescription, privacy: .public)")
            }
        }
        if let serviceURL = try? configuredServiceURL() {
            await sessionStore.saveLastChatId(nil, sessionKey: sessionKey(for: serviceURL))
        }
    }

    func syncOnDeviceExchange(
        userMessageID: UUID,
        userText: String,
        assistantMessageID: UUID,
        assistantText: String,
        authorization: HealthSharingAuthorization
    ) async throws -> OmerLocalChatSyncResponse {
        try HealthSharingConsentPolicy.require([.onDeviceConversationSync], authorization: authorization)
        let serviceURL = try configuredServiceURL()
        let key = sessionKey(for: serviceURL)
        let conversationID = await existingOrNewConversationID(sessionKey: key)
        let request = OmerLocalChatSyncRequest(
            requestId: UUID(),
            conversationId: conversationID,
            source: "ios-on-device",
            messages: [
                .init(id: userMessageID, role: "user", content: userText),
                .init(id: assistantMessageID, role: "assistant", content: assistantText)
            ]
        )
        let url = serviceURL.appendingPathComponent("api/mobile/v1/chats/sync")
        let response: OmerLocalChatSyncResponse
        do {
            response = try await performLocalSync(request, url: url, forceTokenRefresh: false)
        } catch OmerChatServiceError.unauthorized {
            response = try await performLocalSync(request, url: url, forceTokenRefresh: true)
        }
        cacheExchange(
            conversationID: response.conversationId,
            userMessageID: userMessageID,
            userText: userText,
            assistantMessageID: assistantMessageID,
            assistantText: assistantText,
            visibility: "private"
        )
        await sessionStore.saveLastChatId(response.conversationId.uuidString, sessionKey: key)
        return response
    }

    func saveOnDeviceExchangeLocally(
        userMessageID: UUID,
        userText: String,
        assistantMessageID: UUID,
        assistantText: String
    ) async throws {
        let serviceURL = try configuredServiceURL()
        let key = sessionKey(for: serviceURL)
        let conversationID = await existingOrNewConversationID(sessionKey: key)
        cacheExchange(
            conversationID: conversationID,
            userMessageID: userMessageID,
            userText: userText,
            assistantMessageID: assistantMessageID,
            assistantText: assistantText,
            visibility: "private-local"
        )
        await sessionStore.saveLastChatId(conversationID.uuidString, sessionKey: key)
    }

    private func cacheExchange(
        conversationID: UUID,
        userMessageID: UUID,
        userText: String,
        assistantMessageID: UUID,
        assistantText: String,
        visibility: String
    ) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let existingSummary = chatCache.chats.first { $0.id == conversationID }
        let title = existingSummary?.title ?? conversationTitle(from: userText)
        let summary = OmerChatSummary(
            id: conversationID,
            createdAt: existingSummary?.createdAt ?? timestamp,
            title: title,
            visibility: existingSummary?.visibility ?? visibility
        )
        let newMessages = [
            OmerChatHistoryMessage(id: userMessageID, role: "user", content: userText, createdAt: timestamp),
            OmerChatHistoryMessage(id: assistantMessageID, role: "assistant", content: assistantText, createdAt: timestamp)
        ]

        if let detailIndex = chatCache.details.firstIndex(where: { $0.chat.id == conversationID }) {
            let existing = chatCache.details[detailIndex]
            let uniqueMessages = (existing.messages + newMessages).reduce(into: [OmerChatHistoryMessage]()) { result, message in
                if !result.contains(where: { $0.id == message.id }) {
                    result.append(message)
                }
            }
            chatCache.details[detailIndex] = OmerChatDetailResponse(chat: summary, messages: Array(uniqueMessages.suffix(200)))
        } else {
            chatCache.details.insert(OmerChatDetailResponse(chat: summary, messages: newMessages), at: 0)
        }
        mergeCachedSummaries([summary])
    }

    private func cacheDetail(_ detail: OmerChatDetailResponse) {
        if let index = chatCache.details.firstIndex(where: { $0.chat.id == detail.chat.id }) {
            chatCache.details[index] = detail
        } else {
            chatCache.details.insert(detail, at: 0)
        }
        chatCache.details = Array(chatCache.details.prefix(50))
        mergeCachedSummaries([detail.chat])
    }

    private func mergeCachedSummaries(_ summaries: [OmerChatSummary]) {
        var merged = summaries
        merged.append(contentsOf: chatCache.chats.filter { cached in
            !summaries.contains(where: { $0.id == cached.id })
        })
        chatCache.chats = Array(merged.prefix(50))
        persistCache()
    }

    private func conversationTitle(from text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 64 ? String(trimmed.prefix(61)) + "…" : trimmed
    }

    private func persistCache() {
        do {
            let directory = cacheURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableDirectory = directory
            try? mutableDirectory.setResourceValues(resourceValues)
            let data = try encoder.encode(chatCache)
            try data.write(to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            logger.error("Failed to persist protected Omer chat cache: \(error.localizedDescription, privacy: .public)")
        }
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

    private func sessionKey(for serviceURL: URL) -> String {
        "\(serviceURL.absoluteString)|firebase-v1"
    }

    private func authenticatedGET(url: URL) async throws -> Data {
        do {
            return try await performAuthenticatedGET(url: url, forceTokenRefresh: false)
        } catch OmerChatServiceError.unauthorized {
            return try await performAuthenticatedGET(url: url, forceTokenRefresh: true)
        }
    }

    private func performAuthenticatedGET(url: URL, forceTokenRefresh: Bool) async throws -> Data {
        let token = try await firebaseIDToken(forceRefresh: forceTokenRefresh)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private func performLocalSync(
        _ body: OmerLocalChatSyncRequest,
        url: URL,
        forceTokenRefresh: Bool
    ) async throws -> OmerLocalChatSyncResponse {
        let token = try await firebaseIDToken(forceRefresh: forceTokenRefresh)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(body.requestId.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(OmerLocalChatSyncResponse.self, from: data)
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
