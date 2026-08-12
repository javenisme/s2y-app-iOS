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

private enum AssistantAIMode: String, CaseIterable, Identifiable {
    case onDevice
    case omer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDevice: "On-device"
        case .omer: "Omer Online"
        }
    }

    var systemImage: String {
        switch self {
        case .onDevice: "apple.intelligence"
        case .omer: "icloud"
        }
    }
}

struct HealthAssistantView: View {
    @Environment(\.homeDrawerProgress) private var homeDrawerProgress
    @Binding private var requestedConversationID: UUID?

    @State private var inputText: String = ""
    @State private var messages: [ChatMessage] = []
    @State private var isProcessing = false
    @State private var notice: AssistantNotice?
    @State private var showingSettings = false
    @State private var showingHistory = false
    @State private var chatHistory: [OmerChatSummary] = []
    @State private var isLoadingHistory = false
    @State private var historyError: String?
    @State private var streamTick = 0
    @State private var pendingToolApproval: OmerToolApprovalPayload?
    @FocusState private var isInputFocused: Bool
    @AppStorage(StorageKeys.omerIncludeHealthContext) private var omerIncludeHealthContext = true
    @AppStorage(StorageKeys.healthAssistantAIMode) private var aiModeRawValue = AssistantAIMode.onDevice.rawValue

    private let newChatRequestID: UUID
    private let onHistoryChanged: () -> Void
    
    private let healthService = HealthKitService.shared
    private let appleModelService = AppleFoundationModelService.shared
    private let omerChatService = OmerChatService.shared
    private let logger = Logger(subsystem: "com.s2y.app", category: "HealthAssistantView")
    private let isRunningInSimulator = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil

    init(
        requestedConversationID: Binding<UUID?> = .constant(nil),
        newChatRequestID: UUID = UUID(),
        onHistoryChanged: @escaping () -> Void = {}
    ) {
        self._requestedConversationID = requestedConversationID
        self.newChatRequestID = newChatRequestID
        self.onHistoryChanged = onHistoryChanged
    }
    
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
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showingHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .accessibilityLabel("Conversation History")
                    }

                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .accessibilityLabel("Settings")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isInputFocused = false
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    HealthAssistantSettingsView(showsDismissButton: true)
                }
            }
            .sheet(isPresented: $showingHistory) {
                conversationHistorySheet
                    .task {
                        await loadConversationHistory()
                    }
            }
        }
        .task {
            await initializeHealthKit()
        }
        .task(id: requestedConversationID) {
            guard let requestedConversationID else { return }
            await openConversation(id: requestedConversationID)
            self.requestedConversationID = nil
        }
        .onChange(of: newChatRequestID) {
            Task { await beginNewConversation() }
        }
        .alert(item: $pendingToolApproval) { approval in
            Alert(
                title: Text("Allow Omer action?"),
                message: Text("Omer wants to run \(approval.toolName). This can change your stored health data."),
                primaryButton: .default(Text("Allow")) {
                    Task { await decideTool(approval, approved: true) }
                },
                secondaryButton: .cancel(Text("Don't Allow")) {
                    Task { await decideTool(approval, approved: false) }
                }
            )
        }
    }

    private var conversationHistorySheet: some View {
        NavigationStack {
            Group {
                if isLoadingHistory && chatHistory.isEmpty {
                    ProgressView("Loading conversations…")
                } else if let historyError, chatHistory.isEmpty {
                    ContentUnavailableView(
                        "History Unavailable",
                        systemImage: "exclamationmark.bubble",
                        description: Text(historyError)
                    )
                } else if chatHistory.isEmpty {
                    ContentUnavailableView(
                        "No Conversations Yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Chats from S2Y Home and this iPhone will appear here.")
                    )
                } else {
                    List(chatHistory) { chat in
                        Button {
                            Task { await openConversation(chat) }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(chat.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text("Synced with S2Y")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .refreshable {
                        await loadConversationHistory()
                    }
                }
            }
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingHistory = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await beginNewConversation() }
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                }
            }
        }
    }

    @MainActor
    private func loadConversationHistory() async {
        isLoadingHistory = true
        historyError = nil
        defer { isLoadingHistory = false }
        chatHistory = await omerChatService.cachedChats()
        do {
            chatHistory = try await omerChatService.fetchChats().chats
        } catch {
            if chatHistory.isEmpty {
                historyError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func openConversation(_ chat: OmerChatSummary) async {
        await openConversation(id: chat.id)
    }

    @MainActor
    private func openConversation(id: UUID) async {
        isLoadingHistory = true
        historyError = nil
        do {
            let detail = try await omerChatService.fetchChat(id: id)
            try await omerChatService.selectChat(id: id)
            displayConversation(detail)
            showingHistory = false
        } catch {
            if let cached = await omerChatService.cachedChat(id: id) {
                try? await omerChatService.selectChat(id: id)
                displayConversation(cached)
                showingHistory = false
                notice = AssistantNotice(message: "Showing the locally saved copy of this chat.", tone: .info)
            } else {
                historyError = error.localizedDescription
            }
        }
        isLoadingHistory = false
    }

    @MainActor
    private func displayConversation(_ detail: OmerChatDetailResponse) {
        messages = detail.messages.compactMap { message in
            guard !message.content.isEmpty else { return nil }
            return ChatMessage(
                id: message.id,
                role: message.role == "user" ? .user : .assistant,
                content: message.content
            )
        }
    }

    @MainActor
    private func beginNewConversation() async {
        do {
            try await omerChatService.startNewChat()
            messages = []
            notice = nil
            showingHistory = false
            onHistoryChanged()
        } catch {
            historyError = error.localizedDescription
        }
    }

    private var welcomeView: some View {
        ScrollView {
            welcomeContent
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            isInputFocused = false
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
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                isInputFocused = false
            }
            .onChange(of: messages.count) {
                if let lastMessage = messages.last {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: streamTick) {
                if let lastMessage = messages.last {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack {
                Menu {
                    Picker("AI provider", selection: aiModeBinding) {
                        ForEach(AssistantAIMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                } label: {
                    Label(selectedAIMode.title, systemImage: selectedAIMode.systemImage)
                        .font(.caption.weight(.semibold))
                }
                .accessibilityLabel("AI provider")
                .accessibilityIdentifier("health-assistant-ai-mode")
                Spacer()
                Text(selectedAIMode == .onDevice ? "Runs on this iPhone" : "Uses Omer online")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 6)
            
            HStack(spacing: 12) {
                TextField("Ask about your health data...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(isProcessing)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isProcessing else { return }
                        Task { await sendMessage() }
                    }
                    .accessibilityIdentifier("health-assistant-input")
                
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
                .accessibilityIdentifier("health-assistant-send")
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
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            return
        }

        let userMessage = ChatMessage(role: .user, content: trimmedInput)
        messages.append(userMessage)
        
        let query = trimmedInput
        inputText = ""
        isInputFocused = false
        isProcessing = true
        notice = nil

        let assistantPlaceholder = ChatMessage(role: .assistant, content: "")
        messages.append(assistantPlaceholder)

        let healthContext = await OmerHealthContextBuilder.buildSummary(
            for: query,
            includeHealthContext: omerIncludeHealthContext
        )

        if selectedAIMode == .onDevice, appleModelService.availability.isAvailable {
            do {
                try await appleModelService.streamResponse(
                    to: query,
                    healthContext: healthContext
                ) { snapshot in
                    updateAssistantMessage(id: assistantPlaceholder.id, content: snapshot)
                }
                if let assistantText = messages.first(where: { $0.id == assistantPlaceholder.id })?.content,
                   !assistantText.isEmpty {
                    do {
                        _ = try await omerChatService.syncOnDeviceExchange(
                            userMessageID: userMessage.id,
                            userText: query,
                            assistantMessageID: assistantPlaceholder.id,
                            assistantText: assistantText
                        )
                    } catch {
                        logger.error("On-device chat sync failed: \(error.localizedDescription)")
                        notice = AssistantNotice(
                            message: "The answer is available on this iPhone, but could not sync to your S2Y history yet.",
                            tone: .warning
                        )
                    }
                }
                onHistoryChanged()
                isProcessing = false
                return
            } catch {
                logger.error("Apple on-device generation failed: \(error.localizedDescription)")
                updateAssistantMessage(
                    id: assistantPlaceholder.id,
                    content: "On-device Apple AI could not finish this response: \(error.localizedDescription)"
                )
                isProcessing = false
                return
            }
        } else if selectedAIMode == .onDevice {
            notice = AssistantNotice(
                message: appleModelService.availability.fallbackExplanation.replacingOccurrences(of: "Using Omer instead.", with: "Choose Omer Online to continue."),
                tone: .warning
            )
            updateAssistantMessage(
                id: assistantPlaceholder.id,
                content: "On-device Apple AI is not available. Choose Omer Online from the provider menu to send this request online."
            )
            isProcessing = false
            return
        }

        await sendWithOmer(query, assistantMessageID: assistantPlaceholder.id)
        onHistoryChanged()
        isProcessing = false
    }

    private func sendWithOmer(_ query: String, assistantMessageID: UUID) async {
        do {
            try await omerChatService.sendMessage(
                message: query,
                includeHealthContext: omerIncludeHealthContext
            ) { event in
                Task { @MainActor in
                    self.handleOmerEvent(event, assistantMessageID: assistantMessageID)
                }
            }
        } catch {
            let underlyingError = error as NSError
            logger.error(
                "Omer generation failed [\(underlyingError.domain, privacy: .public):\(underlyingError.code)]: \(error.localizedDescription, privacy: .public)"
            )
            updateAssistantMessage(
                id: assistantMessageID,
                content: "Sorry, neither on-device AI nor Omer is available right now: \(error.localizedDescription)"
            )
        }
    }

    @MainActor
    private func handleOmerEvent(_ event: OmerChatStreamEvent, assistantMessageID: UUID) {
        switch event {
        case .started:
            break
        case .delta(let delta):
            appendAssistantDelta(id: assistantMessageID, delta: delta)
        case .completed:
            break
        case .toolApprovalRequired(let approval):
            pendingToolApproval = approval
        case .toolResult(let toolName):
            appendAssistantDelta(id: assistantMessageID, delta: "\n\n✓ \(toolName) completed.")
        case .billing(let billing):
            notice = AssistantNotice(
                message: "\(billing.plan.capitalized) plan · \(billing.remainingTokens.formatted()) AI tokens remaining this month.",
                tone: .info
            )
        case .error(let message):
            updateAssistantMessage(id: assistantMessageID, content: message)
        }
    }

    private func decideTool(_ approval: OmerToolApprovalPayload, approved: Bool) async {
        do {
            let result = try await omerChatService.decideTool(
                approvalId: approval.approvalId,
                approved: approved
            )
            notice = AssistantNotice(
                message: approved ? "\(result.toolName) completed." : "\(result.toolName) was not allowed.",
                tone: .info
            )
        } catch {
            notice = AssistantNotice(message: error.localizedDescription, tone: .warning)
        }
    }

    @MainActor
    private func appendAssistantDelta(id: UUID, delta: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            return
        }

        let existingMessage = messages[index]
        messages[index] = ChatMessage(
            id: id,
            role: existingMessage.role,
            content: existingMessage.content + delta
        )
        streamTick += 1
    }

    @MainActor
    private func updateAssistantMessage(id: UUID, content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            return
        }

        let existingMessage = messages[index]
        messages[index] = ChatMessage(id: id, role: existingMessage.role, content: content)
        streamTick += 1
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
                statusChip(
                    title: selectedAIMode.title,
                    systemImage: selectedAIMode.systemImage,
                    tint: selectedAIMode == .onDevice ? .green : .blue
                )

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

    private var selectedAIMode: AssistantAIMode {
        AssistantAIMode(rawValue: aiModeRawValue) ?? .onDevice
    }

    private var aiModeBinding: Binding<AssistantAIMode> {
        Binding(
            get: { selectedAIMode },
            set: { aiModeRawValue = $0.rawValue }
        )
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
    let id: UUID
    let role: Role
    let content: String
    
    enum Role {
        case user
        case assistant
    }

    init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

enum ChatMarkdownRenderer {
    static func attributedString(from source: String) -> AttributedString? {
        try? AttributedString(
            markdown: source,
            options: .init(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )
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
                messageContent
                    .accessibilityIdentifier(
                        message.role == .assistant
                            ? "health-assistant-response"
                            : "health-assistant-user-message"
                    )
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

    @ViewBuilder
    private var messageContent: some View {
        if message.role == .assistant,
           let attributed = ChatMarkdownRenderer.attributedString(from: message.content) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(message.content)
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
