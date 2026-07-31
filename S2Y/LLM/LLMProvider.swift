//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT

// swiftlint:disable file_types_order missing_docs type_contents_order multiline_function_chains trailing_newline discouraged_optional_boolean
//

import Foundation


public struct LLMMessage: Sendable {
    public enum Role: String, Sendable { case system, user, assistant }
    public let role: Role
    public let content: String
    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}


public protocol LLMProvider: Sendable {
    func complete(messages: [LLMMessage]) async throws -> String
}


public enum LLMProviderError: Error, LocalizedError {
    case badURL
    case httpStatus(code: Int, body: String)
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .badURL:
            return "Invalid service URL."
        case let .httpStatus(code, _):
            return "Service returned an error (\(code))."
        case .decodingFailed:
            return "Unable to parse service response."
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
        let lastUser = messages.last(where: { $0.role == .user })?.content ?? messages.last?.content ?? ""
        let client = OmerAPIClient(
            configuration: .init(
                gatewayURL: gatewayURL,
                modelPath: modelPath,
                bearerToken: token
            )
        )
        return try await client.complete(query: lastUser, messages: messages).answer
    }
}
