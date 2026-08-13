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
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding private var requestedConversationID: UUID?

    @State private var inputText: String = ""
    @State private var messages: [ChatMessage] = []
    @State private var isProcessing = false
    @State private var notice: AssistantNotice?
    @State private var showingSettings = false
    @State private var streamTick = 0
    @State private var pendingToolApproval: OmerToolApprovalPayload?
    @State private var pendingClarification: AssistantClarification?
    @State private var availableSuggestionMetrics: Set<HealthKitService.MetricKind> = []
    @State private var didLoadSuggestionAvailability = false
    @State private var responseTask: Task<Void, Never>?
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
            await stopAndWaitForResponse()
            await openConversation(id: requestedConversationID)
            self.requestedConversationID = nil
        }
        .onChange(of: newChatRequestID) {
            Task { await beginNewConversation() }
        }
        .onDisappear(perform: stopResponse)
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
        pendingClarification = nil
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
        await stopAndWaitForResponse()
        do {
            try await omerChatService.startNewChat()
            messages = []
            notice = nil
            pendingClarification = nil
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

                    if let pendingClarification {
                        clarificationOptions(for: pendingClarification)
                    }
                    
                    if isProcessing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                                .accessibilityHidden(true)
                            Text("Analyzing your health data...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Assistant is analyzing your health data")
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
                    if accessibilityReduceMotion {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    } else {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            .onChange(of: streamTick) {
                if let lastMessage = messages.last {
                    if accessibilityReduceMotion {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
    
    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
            
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(spacing: 8))) {
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
                .accessibilityValue(selectedAIMode.title)
                .accessibilityHint("Opens a menu to choose on-device or Omer online AI")
                .accessibilityIdentifier("health-assistant-ai-mode")
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer()
                }
                Text(selectedAIMode.dataBoundaryDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal)
            .padding(.top, 6)
            
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 12))) {
                TextField("Ask about your health data...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(isProcessing)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isProcessing else { return }
                        startSending()
                    }
                    .accessibilityIdentifier("health-assistant-input")
                
                Button {
                    if isProcessing {
                        stopResponse()
                    } else {
                        startSending()
                    }
                } label: {
                    Image(systemName: isProcessing ? "stop.fill" : "paperplane.fill")
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(isProcessing ? Color.red : (inputText.isEmpty ? Color.gray : Color.blue))
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                }
                .disabled(!isProcessing && inputText.isEmpty)
                .accessibilityLabel(isProcessing ? "Stop Response" : "Send Message")
                .accessibilityHint(isProcessing ? "Stops the current AI response" : "Sends your health question")
                .accessibilityIdentifier(isProcessing ? "health-assistant-stop" : "health-assistant-send")
            }
            .padding()
        }
        .background(.bar)
        .offset(y: homeDrawerProgress * 84)
        .animation(
            accessibilityReduceMotion ? nil : .snappy(duration: 0.28, extraBounce: 0),
            value: homeDrawerProgress
        )
    }
    
    private func noticeCard(notice: AssistantNotice) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notice.tone.systemImage)
                .foregroundColor(notice.tone.tint)
                .accessibilityHidden(true)

            Text(notice.message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .accessibilityLabel("\(notice.tone.accessibilityLabel): \(notice.message)")
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

    private func clarificationOptions(for clarification: AssistantClarification) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose an option")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(clarification.options) { option in
                Button {
                    applyClarification(option, to: clarification)
                } label: {
                    Label(option.title, systemImage: option.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("health-assistant-clarification-\(option.id)")
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("health-assistant-clarification-options")
    }

    private func applyClarification(
        _ option: AssistantClarificationOption,
        to clarification: AssistantClarification
    ) {
        pendingClarification = nil
        inputText = AssistantConversationPolicy.applying(option, to: clarification)
        startSending()
    }

    @MainActor
    private func startSending() {
        guard responseTask == nil else { return }
        responseTask = Task { @MainActor in
            await sendMessage()
            responseTask = nil
        }
    }

    @MainActor
    private func stopResponse() {
        responseTask?.cancel()
    }

    @MainActor
    private func stopAndWaitForResponse() async {
        let activeResponse = responseTask
        activeResponse?.cancel()
        await activeResponse?.value
        responseTask = nil
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

        let previousUserMessages = messages.compactMap { message in
            message.role == .user ? message.content : nil
        }
        let userMessage = ChatMessage(role: .user, content: trimmedInput)
        messages.append(userMessage)

        var query = trimmedInput
        inputText = ""
        isInputFocused = false
        pendingClarification = nil
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

        switch AssistantConversationPolicy.resolve(
            query: query,
            recentUserMessages: previousUserMessages
        ) {
        case .ready(let resolvedQuery):
            query = resolvedQuery
        case .needsClarification(let clarification):
            messages.append(
                ChatMessage(
                    role: .assistant,
                    content: clarification.prompt,
                    communicationKind: .healthObservation
                )
            )
            pendingClarification = clarification
            isProcessing = false
            return
        }

        isProcessing = true
        notice = nil
        let requestedAIMode = selectedAIMode
        let sharingAuthorization = HealthSharingConsentStore.shared.authorization
        let localDocumentContext = ClinicalDocumentContextBuilder.build(for: query)
        let documentContext = ClinicalDocumentSharingPolicy.context(
            localDocumentContext,
            for: requestedAIMode,
            authorization: sharingAuthorization
        )

        let assistantPlaceholder = ChatMessage(
            role: .assistant,
            content: "",
            documentCitations: documentContext?.citations ?? []
        )
        messages.append(assistantPlaceholder)

        var healthContext = await OmerHealthContextBuilder.buildSummary(
            for: query,
            includeHealthContext: requestedAIMode == .onDevice
        )
        if requestedAIMode == .onDevice, let documentContext {
            healthContext = (healthContext ?? [:]).merging(
                ["userImportedClinicalDocumentExcerpts": documentContext.prompt],
                uniquingKeysWith: { _, imported in imported }
            )
        }
        guard !Task.isCancelled else {
            updateAssistantMessage(id: assistantPlaceholder.id, content: "Response stopped.")
            notice = AssistantNotice(message: "You stopped this response.", tone: .info)
            isProcessing = false
            return
        }
        let chartAttachment = await HealthChatVisualizationLoader.load(for: query)
        updateAssistantAttachment(id: assistantPlaceholder.id, attachment: chartAttachment)

        if requestedAIMode == .onDevice, appleModelService.availability.isAvailable {
            let measurement = AssistantRequestMeasurement()
            do {
                try await appleModelService.streamResponse(
                    to: query,
                    healthContext: healthContext
                ) { snapshot in
                    measurement.markFirstResponse()
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

                    let permitsDocumentDerivedSync = ClinicalDocumentSharingPolicy.permitsConversationSync(
                        using: documentContext,
                        authorization: authorization
                    )
                    if HealthSharingConsentPolicy.permits(.onDeviceConversationSync, authorization: authorization),
                       permitsDocumentDerivedSync {
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
                    } else if documentContext != nil,
                              HealthSharingConsentPolicy.permits(.onDeviceConversationSync, authorization: authorization) {
                        notice = AssistantNotice(
                            message: "This document-based answer stays on this iPhone until imported document sharing is allowed.",
                            tone: .info
                        )
                    }
                }
                await AssistantPerformanceMonitor.shared.record(measurement.event(
                    provider: .appleOnDevice,
                    outcome: .completed,
                    usedHealthContext: healthContext?.isEmpty == false
                ))
                onHistoryChanged()
                isProcessing = false
                return
            } catch is CancellationError {
                await AssistantPerformanceMonitor.shared.record(measurement.event(
                    provider: .appleOnDevice,
                    outcome: .cancelled,
                    usedHealthContext: healthContext?.isEmpty == false
                ))
                if messages.first(where: { $0.id == assistantPlaceholder.id })?.content.isEmpty != false {
                    updateAssistantMessage(id: assistantPlaceholder.id, content: "Response stopped.")
                }
                notice = AssistantNotice(message: "You stopped this response.", tone: .info)
                isProcessing = false
                return
            } catch {
                await AssistantPerformanceMonitor.shared.record(measurement.event(
                    provider: .appleOnDevice,
                    outcome: .failed,
                    usedHealthContext: healthContext?.isEmpty == false
                ))
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
        } else if requestedAIMode == .onDevice {
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

        await sendWithOmer(
            query,
            assistantMessageID: assistantPlaceholder.id,
            documentContext: documentContext?.prompt
        )
        onHistoryChanged()
        isProcessing = false
    }

    private func sendWithOmer(
        _ query: String,
        assistantMessageID: UUID,
        documentContext: String?
    ) async {
        let measurement = AssistantRequestMeasurement()
        let usedHealthContext = documentContext != nil || HealthSharingConsentPolicy.permits(
            .relevantHealthSummary,
            authorization: HealthSharingConsentStore.shared.authorization
        )
        do {
            try await omerChatService.sendMessage(
                message: query,
                authorization: HealthSharingConsentStore.shared.authorization,
                includeHealthContext: true,
                importedDocumentContext: documentContext
            ) { event in
                Task { @MainActor in
                    self.handleOmerEvent(event, assistantMessageID: assistantMessageID)
                }
            }
            measurement.markFirstResponse()
            await AssistantPerformanceMonitor.shared.record(measurement.event(
                provider: .omerOnline,
                outcome: .completed,
                usedHealthContext: usedHealthContext
            ))
        } catch is CancellationError {
            await AssistantPerformanceMonitor.shared.record(measurement.event(
                provider: .omerOnline,
                outcome: .cancelled,
                usedHealthContext: usedHealthContext
            ))
            if messages.first(where: { $0.id == assistantMessageID })?.content.isEmpty != false {
                updateAssistantMessage(id: assistantMessageID, content: "Response stopped.")
            }
            notice = AssistantNotice(message: "You stopped this response.", tone: .info)
        } catch let error as HealthSharingConsentFailure {
            await AssistantPerformanceMonitor.shared.record(measurement.event(
                provider: .omerOnline,
                outcome: .failed,
                usedHealthContext: usedHealthContext
            ))
            updateAssistantMessage(
                id: assistantMessageID,
                content: error.localizedDescription
            )
            notice = AssistantNotice(message: error.localizedDescription, tone: .warning)
        } catch {
            await AssistantPerformanceMonitor.shared.record(measurement.event(
                provider: .omerOnline,
                outcome: .failed,
                usedHealthContext: usedHealthContext
            ))
            let underlyingError = error as NSError
            logger.error(
                "Omer generation failed [\(underlyingError.domain, privacy: .public):\(underlyingError.code)]: \(error.localizedDescription, privacy: .public)"
            )
            updateAssistantMessage(
                id: assistantMessageID,
                content: "Omer Online is unavailable right now: \(error.localizedDescription)"
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
            communicationKind: existingMessage.communicationKind,
            documentCitations: existingMessage.documentCitations
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
            communicationKind: existingMessage.communicationKind,
            documentCitations: existingMessage.documentCitations
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
            communicationKind: .healthObservation,
            documentCitations: existingMessage.documentCitations
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
                .accessibilityHidden(true)

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
                title: String(localized: "Step Trends"),
                query: String(localized: "How have my step counts trended over the past 7 days?")
            ),
            HealthQuickQuerySuggestion(
                id: "heart-rate",
                metricKind: .heartRateAverage,
                icon: "heart.fill",
                title: String(localized: "Heart Rate"),
                query: String(localized: "Compare my average heart rate this week versus last week.")
            ),
            HealthQuickQuerySuggestion(
                id: "sleep",
                metricKind: .sleepDurationHours,
                icon: "bed.double.fill",
                title: String(localized: "Sleep Quality"),
                query: String(localized: "How has my sleep quality been over the past 7 days?")
            ),
            HealthQuickQuerySuggestion(
                id: "active-energy",
                metricKind: .activeEnergy,
                icon: "flame.fill",
                title: String(localized: "Active Energy"),
                query: String(localized: "How has my active energy changed over the past 30 days?")
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
    let documentCitations: [ClinicalDocumentCitation]
    
    enum Role {
        case user
        case assistant
    }

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        chartAttachment: HealthChartAttachment? = nil,
        communicationKind: HealthCommunicationKind? = nil,
        documentCitations: [ClinicalDocumentCitation] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.chartAttachment = chartAttachment
        self.communicationKind = communicationKind ?? (role == .assistant ? .wellnessGuidance : nil)
        self.documentCitations = documentCitations
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsDocumentSources = false
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 12 : 60)
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

                if !message.documentCitations.isEmpty {
                    DisclosureGroup(
                        "Imported document sources (\(message.documentCitations.count))",
                        isExpanded: $showsDocumentSources
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(message.documentCitations) { citation in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("[\(citation.marker)] \(citation.documentName) · \(citation.locator)")
                                        .font(.caption.weight(.semibold))
                                    Text(citation.excerpt)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                    .font(.caption)
                    .accessibilityHint("Shows the local excerpts used for this answer")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(message.role == .user ? "Your message" : "Assistant response")
            
            if message.role == .assistant {
                Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 12 : 60)
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
        .accessibilityLabel(suggestion.title)
        .accessibilityHint("Places this question in the message field")
    }
}
