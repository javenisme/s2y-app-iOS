//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable closure_body_length

import Security
import SwiftUI
import OSLog

// Simple Keychain wrapper
struct Keychain {
    func get(key: String) -> String? {
        let query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ] as [String: Any]
        
        var dataTypeRef: AnyObject?
        let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == noErr {
            if let data = dataTypeRef as? Data {
                return String(data: data, encoding: .utf8)
            }
            return nil
        } else {
            return nil
        }
    }
}

enum HealthAssistantError: Error, LocalizedError {
    case llmNotConfigured
    case processingFailed
    
    var errorDescription: String? {
        switch self {
        case .llmNotConfigured:
            return "LLM 服务未配置"
        case .processingFailed:
            return "处理请求失败"
        }
    }
}

struct HealthAssistantView: View {
    @State private var inputText: String = ""
    @State private var messages: [ChatMessage] = []
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showingSettings = false
    @State private var showingModelDownload = false
    @AppStorage("PreferLocalModel") private var preferLocalModel = false
    
    private let healthService = HealthKitService.shared
    private let enhancedProvider = EnhancedLLMProvider.shared
    private let logger = Logger(subsystem: "com.s2y.app", category: "HealthAssistantView")
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if messages.isEmpty {
                    welcomeView
                } else {
                    messagesScrollView
                }
                
                if let errorMessage {
                    errorBanner(errorMessage)
                }
                
                inputBar
            }
            .navigationTitle("健康助手")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            preferLocalModel.toggle()
                        } label: {
                            Image(systemName: preferLocalModel ? "brain.head.profile.fill" : "cloud.fill")
                                .accessibilityLabel(preferLocalModel ? "本地模式" : "云端模式")
                        }
                        Button {
                            showingModelDownload = true
                        } label: {
                            Image(systemName: "arrow.down.circle")
                                .accessibilityLabel("下载本地模型")
                        }
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gear")
                                .accessibilityLabel("设置")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                HealthAssistantSettingsView()
            }
            .sheet(isPresented: $showingModelDownload) {
                ModelDownloadView()
            }
        }
        .task {
            await initializeHealthKit()
        }
    }
    
    private var welcomeView: some View {
        ScrollView {
            welcomeContent
        }
    }
    
    private var welcomeContent: some View {
        VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                        .accessibilityLabel("健康助手图标")
                    
                    Text("健康助手")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("通过自然语言查询您的健康数据，获得个性化洞察和建议")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                    QuickQueryCard(
                        icon: "figure.walk",
                        title: "步数趋势",
                        query: "我过去7天的步数趋势如何？",
                        action: { inputText = "我过去7天的步数趋势如何？" }
                    )
                    
                    QuickQueryCard(
                        icon: "heart.fill",
                        title: "心率对比",
                        query: "对比我本周和上周的平均心率",
                        action: { inputText = "对比我本周和上周的平均心率" }
                    )
                    
                    QuickQueryCard(
                        icon: "bed.double.fill",
                        title: "睡眠分析",
                        query: "我最近的睡眠质量怎么样？",
                        action: { inputText = "我最近的睡眠质量怎么样？" }
                    )
                    
                    QuickQueryCard(
                        icon: "flame.fill",
                        title: "活动能量",
                        query: "我过去30天的活动能量变化",
                        action: { inputText = "我过去30天的活动能量变化" }
                    )
                }
                .padding(.horizontal)
                
                Spacer(minLength: 100)
        }
        .padding(.top, 32)
    }
    
    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    
                    if isProcessing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("正在分析您的健康数据...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _ in
                if let lastMessage = messages.last {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 12) {
                TextField("询问您的健康数据...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(isProcessing)
                
                Button {
                    Task { await sendMessage() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(inputText.isEmpty ? Color.gray : Color.blue)
                        .clipShape(Circle())
                        .accessibilityLabel("发送消息")
                }
                .disabled(inputText.isEmpty || isProcessing)
            }
            .padding()
        }
    }
    
    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
                .accessibilityLabel("警告")
            Text(message)
                .font(.caption)
            Spacer()
            Button("关闭") {
                errorMessage = nil
            }
            .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }
    
    private func initializeHealthKit() async {
        do {
            try await healthService.requestAuthorization()
        } catch {
            errorMessage = "HealthKit 授权失败: \(error.localizedDescription)"
        }
    }
    
    private func sendMessage() async {
        let userMessage = ChatMessage(role: .user, content: inputText.trimmingCharacters(in: .whitespacesAndNewlines))
        messages.append(userMessage)
        
        let query = inputText
        inputText = ""
        isProcessing = true
        errorMessage = nil
        
        do {
            let response = try await processHealthQuery(query)
            let assistantMessage = ChatMessage(role: .assistant, content: response)
            messages.append(assistantMessage)
        } catch {
            let errorResponse = ChatMessage(
                role: .assistant,
                content: "抱歉，处理您的请求时遇到了错误：\(error.localizedDescription)"
            )
            messages.append(errorResponse)
        }
        
        isProcessing = false
    }
    
    private func processHealthQuery(_ query: String) async throws -> String {
        // Always route to Cloudflare LLM (Omer)
        return try await processWithLLM(query)
    }
    
    private func processWithLLM(_ query: String) async throws -> String {
        if preferLocalModel {
            return await enhancedProvider.sendMessageLocal(query)
        } else {
            return await enhancedProvider.sendMessageIntelligent(query)
        }
    }
}

struct ChatMessage: Identifiable, Sendable {
    let id = UUID()
    let role: Role
    let content: String
    
    enum Role {
        case user
        case assistant
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(message.role == .user ? Color.blue : Color.gray.opacity(0.2))
                    )
                    .foregroundColor(message.role == .user ? .white : .primary)
            }
            
            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }
}

struct QuickQueryCard: View {
    let icon: String
    let title: String
    let query: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .accessibilityLabel(title)
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(query)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding()
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}