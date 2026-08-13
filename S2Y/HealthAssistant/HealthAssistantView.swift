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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding private var requestedConversationID: UUID?

    @State private var inputText: String = ""
    @State private var messages: [ChatMessage] = []
    @State private var isProcessing = false
    @State private var notice: AssistantNotice?
    @State private var showingSettings = false
    @State private var streamTick = 0
    @State private var pendingToolApproval: OmerToolApprovalPayload?
    @State private var availableSuggestionMetrics: Set<HealthKitService.MetricKind> = []
    @State private var didLoadSuggestionAvailability = false
    @FocusState private var isInputFocused: Bool
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
                ToolbarItem(placement: .navigationBarTrailing) {
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

    @MainActor
    private func openConversation(id: UUID) async {
        do {
            let detail = try await omerChatService.fetchChat(id: id)
            try await omerChatService.selectChat(id: id)
            displayConversation(detail)
        } catch {
            if let cached = await omerChatService.cachedChat(id: id) {
                try? await omerChatService.selectChat(id: id)
                displayConversation(cached)
                notice = AssistantNotice(message: "Showing the locally saved copy of this chat.", tone: .info)
            } else {
                notice = AssistantNotice(message: "This conversation could not be opened. Try again when you're online.", tone: .warning)
            }
        }
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
            onHistoryChanged()
        } catch {
            notice = AssistantNotice(message: "A new conversation could not be started. Please try again.", tone: .warning)
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
                Text("Try asking")
                    .font(.headline)
                    .padding(.horizontal, 4)

                LazyVGrid(columns: suggestionColumns, spacing: 10) {
                    ForEach(quickQuerySuggestions) { suggestion in
                        QuickQueryRow(suggestion: suggestion) {
                            inputText = suggestion.query
                            isInputFocused = true
                        }
                    }
                }

                if didLoadSuggestionAvailability, quickQuerySuggestions.isEmpty {
                    ContentUnavailableView(
                        "No recent Health data",
                        systemImage: "heart.text.clipboard",
                        description: Text("Connect Health data to see questions tailored to the information available on this iPhone.")
                    )
                    .frame(maxWidth: .infinity)
                } else if !didLoadSuggestionAvailability {
                    ProgressView("Checking available Health data…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
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
            didLoadSuggestionAvailability = true
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            notice = AssistantNotice(
                message: "Health data is not available on this device yet. Open the app on an iPhone with Health access enabled to test live queries.",
                tone: .warning
            )
            return
        }

        await loadQuickQueryAvailability()
    }

    private func loadQuickQueryAvailability() async {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: end) ?? end
        var available: Set<HealthKitService.MetricKind> = []

        for suggestion in HealthQuickQuerySuggestion.catalog {
            guard !available.contains(suggestion.metricKind) else { continue }
            if let metrics = try? await healthService.fetchDailyMetrics(
                kind: suggestion.metricKind,
                start: start,
                end: end
            ), metrics.contains(where: { $0.value > 0 }) {
                available.insert(suggestion.metricKind)
            }
        }

        availableSuggestionMetrics = available
        didLoadSuggestionAvailability = true
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
        if let escalation = HealthSafetyTriage.evaluate(query) {
            HealthSafetyEventStore.shared.record(escalation)
            messages.append(
                ChatMessage(
                    role: .assistant,
                    content: escalation.userMessage,
                    communicationKind: .urgentAction
                )
            )
            notice = AssistantNotice(
                message: "This safety guidance was generated on this iPhone without contacting an AI provider.",
                tone: .warning
            )
            isProcessing = false
            return
        }

        isProcessing = true
        notice = nil

        let assistantPlaceholder = ChatMessage(role: .assistant, content: "")
        messages.append(assistantPlaceholder)

        let healthContext = await OmerHealthContextBuilder.buildSummary(
            for: query,
            includeHealthContext: selectedAIMode == .onDevice
        )
        let chartAttachment = await HealthChatVisualizationLoader.load(for: query)
        updateAssistantAttachment(id: assistantPlaceholder.id, attachment: chartAttachment)

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
                    let authorization = HealthSharingConsentStore.shared.authorization
                    do {
                        try await omerChatService.saveOnDeviceExchangeLocally(
                            userMessageID: userMessage.id,
                            userText: query,
                            assistantMessageID: assistantPlaceholder.id,
                            assistantText: assistantText
                        )
                    } catch {
                        logger.error("Local on-device chat save failed: \(error.localizedDescription)")
                        notice = AssistantNotice(
                            message: "The answer is visible now, but could not be added to local history.",
                            tone: .warning
                        )
                    }

                    if HealthSharingConsentPolicy.permits(.onDeviceConversationSync, authorization: authorization) {
                        do {
                            _ = try await omerChatService.syncOnDeviceExchange(
                                userMessageID: userMessage.id,
                                userText: query,
                                assistantMessageID: assistantPlaceholder.id,
                                assistantText: assistantText,
                                authorization: authorization
                            )
                        } catch {
                            logger.error("On-device chat sync failed: \(error.localizedDescription)")
                            notice = AssistantNotice(
                                message: "The answer is saved on this iPhone, but could not sync to your S2Y account yet.",
                                tone: .warning
                            )
                        }
                    }
                }
                onHistoryChanged()
                isProcessing = false
                return
            } catch {
                logger.error("Apple on-device generation failed: \(error.localizedDescription)")
                notice = AssistantNotice(
                    message: "The on-device response stopped. Your question was not sent online. You can retry or manually choose Omer Online.",
                    tone: .warning
                )
                updateAssistantMessage(
                    id: assistantPlaceholder.id,
                    content: "On-device Apple AI could not finish this response. Your question stayed on this iPhone."
                )
                isProcessing = false
                return
            }
        } else if selectedAIMode == .onDevice {
            notice = AssistantNotice(
                message: appleModelService.availability.recoveryGuidance,
                tone: .warning
            )
            updateAssistantMessage(
                id: assistantPlaceholder.id,
                content: "On-device Apple AI is not ready. Your question was not sent online. \(appleModelService.availability.recoveryGuidance)"
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
                authorization: HealthSharingConsentStore.shared.authorization,
                includeHealthContext: true
            ) { event in
                Task { @MainActor in
                    self.handleOmerEvent(event, assistantMessageID: assistantMessageID)
                }
            }
        } catch let error as HealthSharingConsentFailure {
            updateAssistantMessage(
                id: assistantMessageID,
                content: error.localizedDescription
            )
            notice = AssistantNotice(message: error.localizedDescription, tone: .warning)
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
        case .billing:
            break
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
            content: existingMessage.content + delta,
            chartAttachment: existingMessage.chartAttachment,
            communicationKind: existingMessage.communicationKind
        )
        streamTick += 1
    }

    @MainActor
    private func updateAssistantMessage(id: UUID, content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            return
        }

        let existingMessage = messages[index]
        messages[index] = ChatMessage(
            id: id,
            role: existingMessage.role,
            content: content,
            chartAttachment: existingMessage.chartAttachment,
            communicationKind: existingMessage.communicationKind
        )
        streamTick += 1
    }

    @MainActor
    private func updateAssistantAttachment(id: UUID, attachment: HealthChartAttachment?) {
        guard let attachment,
              let index = messages.firstIndex(where: { $0.id == id }) else {
            return
        }
        let existingMessage = messages[index]
        messages[index] = ChatMessage(
            id: id,
            role: existingMessage.role,
            content: existingMessage.content,
            chartAttachment: attachment,
            communicationKind: .healthObservation
        )
        streamTick += 1
    }

    private var welcomeHero: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "heart.text.square.fill")
                .font(.title2)
                .foregroundStyle(.red)
                .frame(width: 44, height: 44)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("Health Assistant Icon")

            VStack(alignment: .leading, spacing: 5) {
                Text("Ask about your health")
                    .font(.title3.weight(.semibold))

                Text("Get a clear summary of your sleep, activity, heart rate, and other Health data.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var quickQuerySuggestions: [HealthQuickQuerySuggestion] {
        HealthQuickQuerySuggestion.catalog.filter { availableSuggestionMetrics.contains($0.metricKind) }
    }
}

struct HealthQuickQuerySuggestion: Identifiable, Equatable, Sendable {
    let id: String
    let metricKind: HealthKitService.MetricKind
    let icon: String
    let title: String
    let query: String

    static let catalog: [HealthQuickQuerySuggestion] = [
            HealthQuickQuerySuggestion(
                id: "steps",
                metricKind: .steps,
                icon: "figure.walk",
                title: "Step Trends",
                query: "How have my step counts trended over the past 7 days?"
            ),
            HealthQuickQuerySuggestion(
                id: "heart-rate",
                metricKind: .heartRateAverage,
                icon: "heart.fill",
                title: "Heart Rate",
                query: "Compare my average heart rate this week versus last week."
            ),
            HealthQuickQuerySuggestion(
                id: "sleep",
                metricKind: .sleepDurationHours,
                icon: "bed.double.fill",
                title: "Sleep Quality",
                query: "How has my sleep quality been recently?"
            ),
            HealthQuickQuerySuggestion(
                id: "active-energy",
                metricKind: .activeEnergy,
                icon: "flame.fill",
                title: "Active Energy",
                query: "How has my active energy changed over the past 30 days?"
            )
        ]

    static func available(for metrics: Set<HealthKitService.MetricKind>) -> [HealthQuickQuerySuggestion] {
        catalog.filter { metrics.contains($0.metricKind) }
    }
}

private extension HealthAssistantView {
    var suggestionColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.flexible()), GridItem(.flexible())]
    }

    var selectedAIMode: AssistantAIMode {
        AssistantAIMode(rawValue: aiModeRawValue) ?? .onDevice
    }

    var aiModeBinding: Binding<AssistantAIMode> {
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
    let chartAttachment: HealthChartAttachment?
    let communicationKind: HealthCommunicationKind?
    
    enum Role {
        case user
        case assistant
    }

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        chartAttachment: HealthChartAttachment? = nil,
        communicationKind: HealthCommunicationKind? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.chartAttachment = chartAttachment
        self.communicationKind = communicationKind ?? (role == .assistant ? .wellnessGuidance : nil)
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

    static func blocks(from source: String) -> [ChatMarkdownBlock] {
        var blocks: [ChatMarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var isInsideCodeBlock = false

        func appendParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let paragraph = paragraphLines.joined(separator: "\n")
            blocks.append(ChatMarkdownBlock(kind: .paragraph, content: inline(paragraph)))
            paragraphLines.removeAll()
        }

        for line in source.components(separatedBy: .newlines) {
            if line.hasPrefix("```") {
                if isInsideCodeBlock {
                    blocks.append(ChatMarkdownBlock(kind: .code, content: AttributedString(codeLines.joined(separator: "\n"))))
                    codeLines.removeAll()
                } else {
                    appendParagraph()
                }
                isInsideCodeBlock.toggle()
                continue
            }

            if isInsideCodeBlock {
                codeLines.append(line)
                continue
            }

            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendParagraph()
                continue
            }

            if let heading = heading(from: line) {
                appendParagraph()
                blocks.append(ChatMarkdownBlock(kind: .heading(heading.level), content: inline(heading.text)))
            } else if let item = unorderedListItem(from: line) {
                appendParagraph()
                blocks.append(ChatMarkdownBlock(kind: .unorderedListItem, content: inline(item)))
            } else if let item = orderedListItem(from: line) {
                appendParagraph()
                blocks.append(ChatMarkdownBlock(kind: .orderedListItem(item.number), content: inline(item.text)))
            } else if line.hasPrefix("> ") {
                appendParagraph()
                blocks.append(ChatMarkdownBlock(kind: .quote, content: inline(String(line.dropFirst(2)))))
            } else {
                paragraphLines.append(line)
            }
        }

        appendParagraph()
        if !codeLines.isEmpty {
            blocks.append(ChatMarkdownBlock(kind: .code, content: AttributedString(codeLines.joined(separator: "\n"))))
        }
        return blocks
    }

    private static func inline(_ source: String) -> AttributedString {
        attributedString(from: source) ?? AttributedString(source)
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level), line.dropFirst(level).hasPrefix(" ") else { return nil }
        return (level, String(line.dropFirst(level + 1)))
    }

    private static func unorderedListItem(from line: String) -> String? {
        guard line.count > 2 else { return nil }
        let marker = line.prefix(2)
        guard marker == "- " || marker == "* " || marker == "+ " else { return nil }
        return String(line.dropFirst(2))
    }

    private static func orderedListItem(from line: String) -> (number: Int, text: String)? {
        guard let separator = line.firstIndex(of: "."), separator < line.endIndex else { return nil }
        let numberText = line[..<separator]
        let contentStart = line.index(after: separator)
        guard let number = Int(numberText), contentStart < line.endIndex, line[contentStart] == " " else { return nil }
        return (number, String(line[line.index(after: contentStart)...]))
    }
}

struct ChatMarkdownBlock: Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case heading(Int)
        case unorderedListItem
        case orderedListItem(Int)
        case quote
        case code
        case paragraph
    }

    let id = UUID()
    let kind: Kind
    let content: AttributedString
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

                if let communicationKind = message.communicationKind {
                    Label(communicationKind.title, systemImage: communicationKind.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(communicationKind.tint)
                    Text(communicationKind.disclosure)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let chartAttachment = message.chartAttachment {
                    VStack(alignment: .leading, spacing: 6) {
                        chart(attachment: chartAttachment)
                            .accessibilityIdentifier("health-assistant-chart")
                        Label(HealthInterpretationPolicy.wellnessBoundary, systemImage: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }

    @ViewBuilder
    private func chart(attachment: HealthChartAttachment) -> some View {
        switch attachment {
        case .trend(let trend, let kind):
            HealthTrendChart(trend: trend, metricKind: kind)
        case .comparison(let comparison, let kind):
            HealthComparisonChart(comparison: comparison, metricKind: kind)
        case .personalInsights(let report):
            PersonalHealthInsightCard(report: report)
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        if message.role == .assistant {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ChatMarkdownRenderer.blocks(from: message.content)) { block in
                    markdownBlock(block)
                }
            }
            .textSelection(.enabled)
        } else {
            Text(message.content)
        }
    }

    @ViewBuilder
    private func markdownBlock(_ block: ChatMarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(block.content)
                .font(level <= 2 ? .headline : .subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
        case .unorderedListItem:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .accessibilityHidden(true)
                Text(block.content)
            }
        case .orderedListItem(let number):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .accessibilityHidden(true)
                Text(block.content)
            }
        case .quote:
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 3)
                    .accessibilityHidden(true)
                Text(block.content)
                    .foregroundStyle(.secondary)
            }
        case .code:
            ScrollView(.horizontal) {
                Text(block.content)
                    .font(.system(.footnote, design: .monospaced))
                    .padding(8)
            }
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        case .paragraph:
            Text(block.content)
        }
    }
}

private extension HealthCommunicationKind {
    var systemImage: String {
        switch self {
        case .healthObservation: "chart.xyaxis.line"
        case .wellnessGuidance: "leaf"
        case .urgentAction: "cross.case.fill"
        }
    }

    var tint: Color {
        switch self {
        case .healthObservation: .blue
        case .wellnessGuidance: .green
        case .urgentAction: .red
        }
    }
}

private struct QuickQueryRow: View {
    let suggestion: HealthQuickQuerySuggestion
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: suggestion.icon)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                Text(suggestion.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }
}
