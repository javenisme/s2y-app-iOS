//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT

// swiftlint:disable file_length type_body_length

import Foundation

enum OmerTransport: String, CaseIterable, Sendable {
    case mobileV1 = "omer-mobile-v1"
    case legacyAutoRAG = "legacy-autorag"
}

struct OmerAPIClient: Sendable {
    struct Configuration: Sendable {
        let gatewayURL: String
        let modelPath: String
        let bearerToken: String
        let transport: OmerTransport
        let timeout: TimeInterval

        init(
            gatewayURL: String,
            modelPath: String,
            bearerToken: String,
            transport: OmerTransport = .legacyAutoRAG,
            timeout: TimeInterval = 45
        ) {
            self.gatewayURL = gatewayURL
            self.modelPath = modelPath
            self.bearerToken = bearerToken
            self.transport = transport
            self.timeout = timeout
        }
    }

    struct Response: Sendable, Equatable {
        let answer: String
        let citations: [Citation]
        let conversationID: UUID?
        let requestID: UUID?

        init(answer: String, citations: [Citation], conversationID: UUID? = nil, requestID: UUID? = nil) {
            self.answer = answer
            self.citations = citations
            self.conversationID = conversationID
            self.requestID = requestID
        }
    }

    struct Citation: Codable, Sendable, Equatable {
        let title: String?
        let url: String?
        let source: String?
        let snippet: String?

        init(title: String? = nil, url: String? = nil, source: String? = nil, snippet: String? = nil) {
            self.title = title?.nilIfBlank
            self.url = url?.nilIfBlank
            self.source = source?.nilIfBlank
            self.snippet = snippet?.nilIfBlank
        }
    }

    private struct MobileChatRequest: Encodable {
        struct Message: Encodable {
            let id: UUID
            let text: String
        }

        struct HistoryMessage: Encodable {
            let role: String
            let content: String
        }

        struct Client: Encodable {
            let platform: String
            let version: String
        }

        let requestId: UUID
        let conversationId: UUID
        let message: Message
        let history: [HistoryMessage]
        let locale: String
        let healthContext: [String: String]?
        let client: Client
    }

    private struct MobileChatResponse: Decodable {
        let requestId: UUID
        let conversationId: UUID
        let answer: String
        let citations: [Citation]
    }

    private let configuration: Configuration
    private let session: URLSession

    init(configuration: Configuration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func complete(
        query: String,
        messages: [LLMMessage],
        healthContext: [String: String] = [:],
        conversationID: UUID = UUID(),
        requestID: UUID = UUID()
    ) async throws -> Response {
        let request = try Self.makeRequest(
            configuration: configuration,
            query: query,
            messages: messages,
            healthContext: healthContext,
            conversationID: conversationID,
            requestID: requestID
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data.prefix(8_192), encoding: .utf8) ?? ""
            throw LLMProviderError.httpStatus(code: http.statusCode, body: text)
        }

        switch configuration.transport {
        case .mobileV1:
            return try Self.decodeMobileResponse(data, expectedRequestID: requestID)
        case .legacyAutoRAG:
            return try Self.decodeLegacyResponse(data)
        }
    }

    static func makeRequest(
        configuration: Configuration,
        query: String,
        messages: [LLMMessage],
        healthContext: [String: String],
        conversationID: UUID,
        requestID: UUID
    ) throws -> URLRequest {
        let url = try buildURL(gatewayURL: configuration.gatewayURL, modelPath: configuration.modelPath)
        if configuration.transport == .mobileV1 {
            try validateMobileURL(url)
        }

        var request = URLRequest(url: url, timeoutInterval: configuration.timeout)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue(userAgent, forHTTPHeaderField: "User-Agent")

        let token = configuration.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        switch configuration.transport {
        case .mobileV1:
            guard !token.isEmpty else { throw LLMError.authenticationFailed }
            request.addValue(requestID.uuidString, forHTTPHeaderField: "Idempotency-Key")
            request.httpBody = try encodeMobileRequest(
                query: query,
                messages: messages,
                healthContext: healthContext,
                conversationID: conversationID,
                requestID: requestID
            )
        case .legacyAutoRAG:
            guard !token.isEmpty else { throw LLMError.apiKeyMissing }
            request.httpBody = try JSONEncoder().encode(["query": query])
        }
        return request
    }

    static func buildURL(gatewayURL: String, modelPath: String) throws -> URL {
        var base = gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") {
            base.removeLast()
        }

        var path = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("/") {
            path.removeFirst()
        }

        let fullURL = path.isEmpty ? base : "\(base)/\(path)"
        guard let url = URL(string: fullURL), url.host != nil else { throw LLMProviderError.badURL }
        return url
    }

    static func encodeMobileRequest(
        query: String,
        messages: [LLMMessage],
        healthContext: [String: String],
        conversationID: UUID,
        requestID: UUID
    ) throws -> Data {
        let history = messages
            .filter { $0.role == .user || $0.role == .assistant }
            .dropLast(messages.last?.role == .user ? 1 : 0)
            .suffix(10)
            .map { MobileChatRequest.HistoryMessage(role: $0.role.rawValue, content: String($0.content.prefix(2_000))) }
        let context = healthContext.isEmpty ? nil : Dictionary(
            uniqueKeysWithValues: healthContext.prefix(10).map { key, value in
                (String(key.prefix(64)), String(value.prefix(200)))
            }
        )
        let payload = MobileChatRequest(
            requestId: requestID,
            conversationId: conversationID,
            message: .init(id: requestID, text: String(query.prefix(2_000))),
            history: history,
            locale: Locale.current.identifier,
            healthContext: context,
            client: .init(platform: "ios", version: appVersion)
        )
        return try JSONEncoder().encode(payload)
    }

    static func decodeMobileResponse(_ data: Data, expectedRequestID: UUID) throws -> Response {
        guard data.count <= 1_048_576,
              let decoded = try? JSONDecoder().decode(MobileChatResponse.self, from: data),
              decoded.requestId == expectedRequestID,
              let answer = decoded.answer.nilIfBlank else {
            throw LLMProviderError.decodingFailed
        }
        return Response(
            answer: answer,
            citations: Array(decoded.citations.prefix(5)),
            conversationID: decoded.conversationId,
            requestID: decoded.requestId
        )
    }

    static func decodeLegacyResponse(_ data: Data) throws -> Response {
        guard data.count <= 1_048_576,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["success"] as? Bool != false,
              let answer = findAnswer(in: object)?.nilIfBlank else {
            throw LLMProviderError.decodingFailed
        }
        return Response(answer: answer, citations: findCitations(in: object))
    }

    private static func validateMobileURL(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https" else { throw LLMProviderError.badURL }
    }

    private static var userAgent: String {
        "S2Y-iOS/\(appVersion)"
    }

    private static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let components = [version, build].compactMap { $0?.nilIfBlank }
        return components.joined(separator: ".").nilIfBlank ?? "unknown"
    }

    private static func findAnswer(in dictionary: [String: Any]) -> String? {
        if let result = dictionary["result"] as? [String: Any] {
            return stringValue(in: result, keys: ["response", "answer", "text", "output_text"])
        }
        return stringValue(in: dictionary, keys: ["response", "answer", "text", "output_text"])
    }

    private static func findCitations(in dictionary: [String: Any]) -> [Citation] {
        let result = dictionary["result"] as? [String: Any]
        let values = result?["data"] ?? result?["citations"] ?? dictionary["citations"]
        return Array(decodeCitations(from: values).prefix(5))
    }

    private static func decodeCitations(from value: Any?) -> [Citation] {
        guard let values = value as? [[String: Any]] else { return [] }
        return values.compactMap { dictionary in
            let citation = Citation(
                title: stringValue(in: dictionary, keys: ["title", "name"]),
                url: stringValue(in: dictionary, keys: ["url", "href", "link"]),
                source: stringValue(in: dictionary, keys: ["source", "file", "document"]),
                snippet: stringValue(in: dictionary, keys: ["snippet", "summary", "content", "text"])
            )
            return citation.title == nil && citation.url == nil && citation.source == nil && citation.snippet == nil ? nil : citation
        }
    }

    private static func stringValue(in dictionary: [String: Any], keys: [String]) -> String? {
        keys.lazy.compactMap { (dictionary[$0] as? String)?.nilIfBlank }.first
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
