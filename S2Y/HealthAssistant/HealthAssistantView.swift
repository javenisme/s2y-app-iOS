//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable closure_body_length

import HealthKit
import OSLog
import Security
import SwiftUI

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
    @Environment(\.homeDrawerProgress) private var homeDrawerProgress

    @State private var inputText: String = ""
    @State private var messages: [ChatMessage] = []
    @State private var isProcessing = false
    @State private var notice: AssistantNotice?
    @State private var showingSettings = false
    @State private var showingModelDownload = false
    @AppStorage("PreferLocalModel") private var preferLocalModel = false
    
    private let healthService = HealthKitService.shared
    private let enhancedProvider = EnhancedLLMProvider.shared
    private let logger = Logger(subsystem: "com.s2y.app", category: "HealthAssistantView")
    private let isRunningInSimulator = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if messages.isEmpty {
                    welcomeView
                } else {
                    messagesScrollView
                }

                inputBar
            }
            .blur(radius: homeDrawerProgress * 2)
            .navigationTitle("Health Assistant")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showingModelDownload = true
                        } label: {
                            Image(systemName: "arrow.down.circle")
                                .accessibilityLabel("Download Local Model")
                        }
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
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
        VStack(alignment: .leading, spacing: 16) {
            welcomeHero

            if let notice {
                noticeCard(notice: notice)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Suggested Questions")
                    .font(.headline)
                    .padding(.horizontal, 4)

                ForEach(quickQuerySuggestions) { suggestion in
                    QuickQueryRow(suggestion: suggestion) {
                        inputText = suggestion.query
                    }
                }
            }

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }
    
    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if let notice {
                        noticeCard(notice: notice)
                    }

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
            .onChange(of: messages.count) {
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
                    Label("Local AI enabled", systemImage: "brain.head.profile")
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
        .background(.bar)
        .offset(y: homeDrawerProgress * 84)
        .animation(.snappy(duration: 0.28, extraBounce: 0), value: homeDrawerProgress)
    }
    
    private func noticeCard(notice: AssistantNotice) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notice.tone.systemImage)
                .foregroundColor(notice.tone.tint)
                .accessibilityLabel(notice.tone.accessibilityLabel)

            Text(notice.message)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()

            Button("Dismiss") {
                self.notice = nil
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(notice.tone.tint.opacity(0.12))
        )
    }
    
    private func initializeHealthKit() async {
        if isRunningInSimulator {
            notice = AssistantNotice(
                message: "Simulator preview: use a physical iPhone for live Health data.",
                tone: .info
            )
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            notice = AssistantNotice(
                message: "Health data is not available on this device yet. Open the app on an iPhone with Health access enabled to test live queries.",
                tone: .warning
            )
            return
        }

        do {
            try await healthService.requestAuthorization()
        } catch {
            notice = AssistantNotice(
                message: "HealthKit authorization failed: \(error.localizedDescription)",
                tone: .warning
            )
        }
    }
    
    private func sendMessage() async {
        let userMessage = ChatMessage(role: .user, content: inputText.trimmingCharacters(in: .whitespacesAndNewlines))
        messages.append(userMessage)
        
        let query = inputText
        inputText = ""
        isProcessing = true
        notice = nil
        
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

    private var welcomeHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 54, height: 54)

                    Image(systemName: "heart.text.square.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                        .accessibilityLabel("Health Assistant Icon")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ask about your health in plain language")
                        .font(.title3.weight(.semibold))

                    Text("Explore steps, heart rate, sleep, and activity trends without digging through charts first.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                modeChip(
                    title: preferLocalModel ? "Local AI" : "Cloud AI",
                    systemImage: preferLocalModel ? "brain.head.profile" : "icloud",
                    tint: preferLocalModel ? .green : .blue
                ) {
                    preferLocalModel.toggle()
                }

                statusChip(
                    title: isRunningInSimulator ? "Simulator Preview" : (HKHealthStore.isHealthDataAvailable() ? "HealthKit Ready" : "Unavailable"),
                    systemImage: isRunningInSimulator ? "iphone" : (HKHealthStore.isHealthDataAvailable() ? "heart.circle" : "exclamationmark.circle"),
                    tint: isRunningInSimulator ? .orange : (HKHealthStore.isHealthDataAvailable() ? .pink : .orange)
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func modeChip(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func statusChip(title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
    }

    private var quickQuerySuggestions: [QuickQuerySuggestion] {
        [
            QuickQuerySuggestion(
                icon: "figure.walk",
                title: "Step Trends",
                subtitle: "7-day movement snapshot",
                query: "How have my step counts trended over the past 7 days?"
            ),
            QuickQuerySuggestion(
                icon: "heart.fill",
                title: "Heart Rate Comparison",
                subtitle: "This week versus last week",
                query: "Compare my average heart rate this week versus last week."
            ),
            QuickQuerySuggestion(
                icon: "bed.double.fill",
                title: "Sleep Analysis",
                subtitle: "Recent rest and recovery",
                query: "How has my sleep quality been recently?"
            ),
            QuickQuerySuggestion(
                icon: "flame.fill",
                title: "Active Energy",
                subtitle: "30-day activity change",
                query: "How has my active energy changed over the past 30 days?"
            )
        ]
    }
}

private struct AssistantNotice {
    let message: String
    let tone: Tone

    enum Tone {
        case info
        case warning

        var systemImage: String {
            switch self {
            case .info:
                return "info.circle"
            case .warning:
                return "exclamationmark.triangle"
            }
        }

        var tint: Color {
            switch self {
            case .info:
                return .blue
            case .warning:
                return .orange
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .info:
                return "Information"
            case .warning:
                return "Warning"
            }
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

private struct QuickQuerySuggestion: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let query: String
}

private struct QuickQueryRow: View {
    let suggestion: QuickQuerySuggestion
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 48, height: 48)

                    Image(systemName: suggestion.icon)
                        .font(.title3)
                        .foregroundColor(.blue)
                        .accessibilityLabel(suggestion.title)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(suggestion.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(suggestion.query)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Image(systemName: "arrow.up.left.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }
}
