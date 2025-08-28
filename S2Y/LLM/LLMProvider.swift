//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation


public struct LLMMessage: Sendable {
    public enum Role: String, Sendable { case user, assistant }
    public let role: Role
    public let content: String
    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}


public protocol LLMProvider {
    func complete(messages: [LLMMessage]) async throws -> String
}


public enum LLMProviderError: Error, LocalizedError {
    case badURL
    case httpStatus(code: Int, body: String)
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .badURL:
            return "无效的服务地址。"
        case let .httpStatus(code, _):
            return "服务返回错误（\(code)）。"
        case .decodingFailed:
            return "无法解析返回结果。"
        }
    }
}


public struct CloudflareLLMProvider: LLMProvider, Sendable {
    private let gatewayURL: String
    private let modelPath: String
    private let token: String

    public init(gatewayURL: String, modelPath: String, token: String) {
        self.gatewayURL = gatewayURL
        self.modelPath = modelPath
        self.token = token
    }

    public func complete(messages: [LLMMessage]) async throws -> String {
        let (url, useQueryField) = try buildURL(gatewayURL: gatewayURL, modelPath: modelPath)
        let (prompt, lastUser) = composePrompts(messages)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encodeBody(useQueryField: useQueryField, prompt: prompt, lastUserMessage: lastUser)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw LLMProviderError.httpStatus(code: http.statusCode, body: text)
        }
        return try parseReply(data)
    }

    private func buildURL(gatewayURL: String, modelPath: String) throws -> (URL, Bool) {
        var base = gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base.removeLast() }
        var path = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("/") { path.removeFirst() }
        let full = path.isEmpty ? base : (base + "/" + path)
        guard let url = URL(string: full) else { throw LLMProviderError.badURL }
        return (url, full.contains("ai-search"))
    }

    private func composePrompts(_ messages: [LLMMessage]) -> (prompt: String, lastUser: String) {
        let lastUser = messages.last(where: { $0.role == .user })?.content ?? messages.last?.content ?? ""
        let prompt = messages.map { msg in
            switch msg.role {
            case .user: return "User: \(msg.content)"
            case .assistant: return "Assistant: \(msg.content)"
            }
        }.joined(separator: "\n")
        return (prompt, lastUser)
    }

    private func encodeBody(useQueryField: Bool, prompt: String, lastUserMessage: String) throws -> Data {
        struct CFPayloadPrompt: Codable { let prompt: String }
        struct CFPayloadQuery: Codable { let query: String }
        if useQueryField {
            return try JSONEncoder().encode(CFPayloadQuery(query: lastUserMessage))
        } else {
            return try JSONEncoder().encode(CFPayloadPrompt(prompt: prompt))
        }
    }

    private func parseReply(_ data: Data) throws -> String {
        struct CFResult: Codable {
            let response: String?
            let text: String?
            let outputText: String?
            let answer: String?
            enum CodingKeys: String, CodingKey {
                case response
                case text
                case outputText = "output_text"
                case answer
            }
        }
        struct CFResponse: Codable { let result: CFResult?; let success: Bool? }

        guard let decoded = try? JSONDecoder().decode(CFResponse.self, from: data) else {
            throw LLMProviderError.decodingFailed
        }
        let reply = decoded.result?.response
            ?? decoded.result?.text
            ?? decoded.result?.outputText
            ?? decoded.result?.answer
            ?? ""
        return reply.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


