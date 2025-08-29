//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SwiftUI


private enum LLMKeychain {
    static let service = "ai.cloudflare"
    static let account = "gateway.token"
}


private struct ChatMessage: Identifiable, Hashable, Sendable {
    enum Role: String { case user, assistant }
    let id = UUID()
    let role: Role
    let content: String
}


struct LLMChatDemoView: View {
    @AppStorage("cf.gatewayURL") private var gatewayURL: String = Bundle.main.object(forInfoDictionaryKey: "CFWorkersAI.GatewayURL") as? String ?? ""
    @State private var modelPath: String = Bundle.main.object(forInfoDictionaryKey: "CFWorkersAI.ModelPath") as? String ?? ""
    @State private var cfToken: String = (Bundle.main.object(forInfoDictionaryKey: "CFWorkersAI.BearerToken") as? String) ?? ""
    @State private var inputText: String = ""
    @State private var isSending = false
    @State private var messages: [ChatMessage] = [
        .init(role: .assistant, content: "你好，我是 OpenAI 模型示例。请输入你的问题。")
    ]
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            messagesView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let errorText { errorBanner(errorText) }
            inputBar
        }
        .navigationTitle("Chat")
        .onAppear(perform: loadKey)
    }

    // Removed settings form per request; values now come from Info.plist and Keychain.

    @ViewBuilder
    private var messagesView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(messages) { message in
                    messageRow(message)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        HStack(alignment: .top) {
            if message.role == .assistant {
                Text("🤖").accessibilityHidden(true)
            } else {
                Text("🧑").accessibilityHidden(true)
            }
            Text(message.content)
                .padding(10)
                .background(message.role == .assistant ? Color.gray.opacity(0.15) : Color.blue.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.red)
            .font(.footnote)
            .padding(.horizontal)
    }

    @ViewBuilder
    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Type a message...", text: $inputText, axis: .vertical)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .lineLimit(1...4)
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Button(action: send) {
                if isSending {
                    ProgressView()
                } else {
                    Image(systemName: "paperplane.fill").accessibilityLabel("Send message")
                }
            }
            .disabled(isSending || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }

    private func loadKey() {
        if let data = readKeychain(service: LLMKeychain.service, account: LLMKeychain.account),
           let key = String(data: data, encoding: .utf8), !key.isEmpty {
            cfToken = key
        }
    }

    private func saveToken() {
        guard let data = cfToken.data(using: .utf8) else { return }
        _ = writeKeychain(service: LLMKeychain.service, account: LLMKeychain.account, data: data)
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !cfToken.isEmpty else {
            errorText = "缺少访问令牌。请在系统设置或 Keychain 中配置。"
            return
        }
        guard !gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorText = "缺少服务地址。请在 Info.plist 配置 CFWorkersAI.GatewayURL。"
            return
        }
        // modelPath 允许为空（当 gatewayURL 已为完整终端点时）

        errorText = nil
        isSending = true
        let userMsg = ChatMessage(role: .user, content: text)
        messages.append(userMsg)
        inputText = ""

        Task {
            defer { isSending = false }
            do {
                if let toolReply = try await handleNLQueryWithTools(text: text) {
                    messages.append(.init(role: .assistant, content: toolReply))
                    return
                }
                let provider = CloudflareLLMProvider(gatewayURL: gatewayURL, modelPath: modelPath, token: cfToken)
                let reply = try await retrying(times: 2, initialDelayMs: 400) {
                    try await provider.complete(messages: messages.map { .init(role: $0.role == .user ? .user : .assistant, content: $0.content) })
                }
                messages.append(.init(role: .assistant, content: reply))
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    // MARK: - Minimal NL → Tool orchestration (demo)

    private func handleNLQueryWithTools(text: String) async throws -> String? {
        guard let intent = QueryPlanner.parse(text) else { return nil }
        return try await QueryPlanner.run(intent: intent)
    }

    private func retrying<T: Sendable>(
        times: Int,
        initialDelayMs: UInt64,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var delay = initialDelayMs
        while true {
            do { return try await operation() } catch {
                attempt += 1
                if attempt > times { throw error }
                try? await Task.sleep(nanoseconds: delay * 1_000_000)
                delay *= 2
            }
        }
    }
}


// MARK: - Minimal Keychain helpers

import Security

private func writeKeychain(service: String, account: String, data: Data) -> Bool {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account
    ]
    SecItemDelete(query as CFDictionary)
    let addQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecValueData as String: data
    ]
    let status = SecItemAdd(addQuery as CFDictionary, nil)
    return status == errSecSuccess
}

private func readKeychain(service: String, account: String) -> Data? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return data
}


