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
            return "LLM service is not configured"
        case .processingFailed:
            return "Failed to process the request"
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
            .navigationTitle("Health Assistant")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            preferLocalModel.toggle()
                        } label: {
                            Image(systemName: preferLocalModel ? "brain.head.profile.fill" : "cloud.fill")
                                .accessibilityLabel(preferLocalModel ? "Local Mode" : "Cloud Mode")
                        }
                        Button {
                            showingModelDownload = true
                        } label: {
                            Image(systemName: "arrow.down.circle")
                                .accessibilityLabel("Download Local Model")
                        }
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gear")
                                .accessibilityLabel("Settings")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    HealthAssistantSettingsView(showsDismissButton: true)
                }
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
                        .accessibilityLabel("Health Assistant Icon")
                    
                    Text("Health Assistant")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Ask natural language questions about your health data to get personalized insights and guidance.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                    QuickQueryCard(
                        icon: "figure.walk",
                        title: "Step Trends",
                        query: "How have my step counts trended over the past 7 days?",
                        action: { inputText = "How have my step counts trended over the past 7 days?" }
                    )
                    
                    QuickQueryCard(
                        icon: "heart.fill",
                        title: "Heart Rate Comparison",
                        query: "Compare my average heart rate this week versus last week.",
                        action: { inputText = "Compare my average heart rate this week versus last week." }
                    )
                    
                    QuickQueryCard(
                        icon: "bed.double.fill",
                        title: "Sleep Analysis",
                        query: "How has my sleep quality been recently?",
                        action: { inputText = "How has my sleep quality been recently?" }
                    )
                    
                    QuickQueryCard(
                        icon: "flame.fill",
                        title: "Active Energy",
                        query: "How has my active energy changed over the past 30 days?",
                        action: { inputText = "How has my active energy changed over the past 30 days?" }
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
                            Text("Analyzing your health data...")
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
            
            if preferLocalModel {
                HStack {
                    Image(systemName: "brain.head.profile.fill")
                        .foregroundColor(.green)
                    Text("Local AI Mode - Fully Private")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 6)
            }
            
            HStack(spacing: 12) {
                TextField("Ask about your health data...", text: $inputText, axis: .vertical)
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
                        .accessibilityLabel("Send Message")
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
                .accessibilityLabel("Warning")
            Text(message)
                .font(.caption)
            Spacer()
            Button("Dismiss") {
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
            errorMessage = "HealthKit authorization failed: \(error.localizedDescription)"
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
                content: "Sorry, I ran into an error while processing your request: \(error.localizedDescription)"
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
            do {
                try await LocalLLMService.shared.loadModel(.phi3_5Mini)
                let mockText = try await LocalLLMService.shared.generateComplete(
                    prompt: query,
                    parameters: LocalGenerateParameters(maxTokens: 128)
                )
                return mockText
            } catch {
                logger.error("LocalLLMService failed: \(error.localizedDescription). Falling back to EnhancedLLMProvider.")
                return await enhancedProvider.sendMessageLocal(query)
            }
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
