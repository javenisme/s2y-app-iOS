//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

@_spi(TestingSupport) import SpeziAccount
import SwiftUI


struct HomeView: View {
    enum Tabs: String, CaseIterable {
        case healthAssistant
        case schedule
        case contact
        case settings

        var title: String {
            switch self {
            case .healthAssistant:
                return String(localized: "Health Assistant")
            case .schedule:
                return String(localized: "Schedule")
            case .contact:
                return String(localized: "Account")
            case .settings:
                return String(localized: "Settings")
            }
        }

        var systemImage: String {
            switch self {
            case .healthAssistant:
                return "heart.text.square"
            case .schedule:
                return "list.clipboard"
            case .contact:
                return "person.crop.circle"
            case .settings:
                return "gearshape"
            }
        }

    }


    @AppStorage(StorageKeys.homeTabSelection) private var selectedTab = Tabs.healthAssistant
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var presentingAccount = false
    @State private var isDrawerOpen = false
    @State private var drawerChatHistory: [OmerChatSummary] = []
    @State private var requestedConversationID: UUID?
    @State private var newChatRequestID = UUID()
    @State private var isRefreshingChatHistory = false
    @State private var chatPendingDeletion: OmerChatSummary?
    @State private var chatDeletionError: String?
    @State private var isDeletingChat = false


    var body: some View {
        GeometryReader { geometry in
            let drawerWidth = dynamicTypeSize.isAccessibilitySize
                ? min(geometry.size.width * 0.92, 420)
                : min(geometry.size.width * 0.82, 320)

            ZStack(alignment: .leading) {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                drawer(width: drawerWidth)

                contentLayer(drawerWidth: drawerWidth)
            }
            .animation(
                accessibilityReduceMotion ? nil : .snappy(duration: 0.28, extraBounce: 0),
                value: isDrawerOpen
            )
        }
        .sheet(isPresented: $presentingAccount) {
            AccountSheet(dismissAfterSignIn: false) // presentation was user initiated, do not automatically dismiss
        }
        .accountRequired(!FeatureFlags.disableFirebase && !FeatureFlags.skipOnboarding) {
            AccountSheet()
        }
        .task {
            await loadDrawerChatHistory()
            await CrossDeviceSyncCoordinator.shared.start()
        }
        .onChange(of: isDrawerOpen) {
            guard isDrawerOpen else { return }
            Task { await loadDrawerChatHistory() }
        }
        .confirmationDialog(
            "Delete this Omer conversation?",
            isPresented: Binding(
                get: { chatPendingDeletion != nil },
                set: { if !$0 { chatPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete from Omer", role: .destructive) {
                guard let chat = chatPendingDeletion else { return }
                chatPendingDeletion = nil
                Task { await deleteChat(chat) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the conversation from Omer and from this iPhone's chat cache. It cannot be undone.")
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .healthAssistant:
            HealthAssistantView(
                requestedConversationID: $requestedConversationID,
                newChatRequestID: newChatRequestID,
                onHistoryChanged: {
                    Task { await loadDrawerChatHistory() }
                }
            )
        case .schedule:
            ScheduleView(presentingAccount: $presentingAccount)
        case .contact:
            ProfileView()
        case .settings:
            ShowcaseView()
        }
    }

    private func contentLayer(drawerWidth: CGFloat) -> some View {
        let drawerProgress = isDrawerOpen ? 1.0 : 0.0

        return selectedContent
            .environment(\.homeDrawerProgress, drawerProgress)
            .accessibilityHidden(isDrawerOpen)
            .overlay {
                if isDrawerOpen {
                    Color.black
                        .opacity(0.16)
                        .ignoresSafeArea()
                        .onTapGesture {
                            closeDrawer()
                        }
                }
            }
            .overlay(alignment: .topLeading) {
                drawerToggleButton
            }
            .clipShape(
                RoundedRectangle(cornerRadius: isDrawerOpen ? 32 : 0, style: .continuous)
            )
            .shadow(color: Color.black.opacity(isDrawerOpen ? 0.14 : 0), radius: 28, x: 0, y: 18)
            .offset(x: isDrawerOpen ? drawerWidth * 0.78 : 0)
            .scaleEffect(isDrawerOpen ? 0.96 : 1, anchor: .trailing)
    }

    private func drawer(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            drawerHeader

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if let chatDeletionError {
                        Text(chatDeletionError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 18)
                            .padding(.bottom, 8)
                            .accessibilityIdentifier("drawer.chat-delete-error")
                    }

                    if drawerChatHistory.isEmpty {
                        Text("Recent chats")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 18)
                            .padding(.top, 8)

                        Text(isRefreshingChatHistory ? "Loading conversations…" : "Your Omer and on-device chats will appear here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(chatHistorySections) { section in
                            Text(section.title)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 18)
                                .padding(.top, 14)
                                .padding(.bottom, 4)

                            ForEach(section.chats) { chat in
                                drawerChatRow(chat)
                            }
                        }
                    }

                    Divider()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                    ForEach([Tabs.schedule, Tabs.settings], id: \.self) { tab in
                        drawerRow(for: tab)
                    }
                }
                .padding(.bottom, 12)
            }

            drawerFooter
        }
        .frame(width: width, alignment: .leading)
        .accessibilityHidden(!isDrawerOpen)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(
            Color(uiColor: .secondarySystemBackground)
                .ignoresSafeArea()
        )
    }

    private var drawerHeader: some View {
        HStack(spacing: 10) {
            Text("Chats")
                .font(.headline.weight(.semibold))

            Spacer()

            if isRefreshingChatHistory {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading conversations")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var newChatButton: some View {
        Button {
            selectedTab = .healthAssistant
            requestedConversationID = nil
            newChatRequestID = UUID()
            closeDrawer()
        } label: {
            drawerFooterLabel("New chat", systemImage: "square.and.pencil")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("drawer.new-chat")
    }

    private var accountButton: some View {
        Button {
            selectedTab = .contact
            closeDrawer()
        } label: {
            drawerFooterLabel("Account", systemImage: "person.crop.circle")
                .background(
                    selectedTab == .contact ? Color.primary.opacity(0.07) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityValue(selectedTab == .contact ? "Selected" : "")
        .accessibilityAddTraits(selectedTab == .contact ? .isSelected : [])
        .accessibilityIdentifier("drawer.account")
    }

    private var drawerFooter: some View {
        VStack(spacing: 2) {
            Divider()
                .padding(.bottom, 6)

            newChatButton
            accountButton
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func drawerFooterLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer()
        }
        .foregroundStyle(.primary)
        .frame(minHeight: 46)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
    }

    private func drawerChatRow(_ chat: OmerChatSummary) -> some View {
        HStack(spacing: 8) {
            Button {
                selectedTab = .healthAssistant
                requestedConversationID = chat.id
                closeDrawer()
            } label: {
                HStack(spacing: 8) {
                    Text(chat.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("drawer.chat.\(chat.id.uuidString)")

            Button {
                chatPendingDeletion = chat
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDeletingChat)
            .accessibilityLabel("Conversation actions for \(chat.title)")
            .accessibilityIdentifier("drawer.chat-actions.\(chat.id.uuidString)")
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .frame(minHeight: 44)
    }

    private func drawerRow(for tab: Tabs) -> some View {
        Button {
            selectedTab = tab
            closeDrawer()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: tab.systemImage)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                Text(tab.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                if selectedTab == tab {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        selectedTab == tab
                            ? Color.primary.opacity(0.07)
                            : Color.clear
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityValue(selectedTab == tab ? "Selected" : "")
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
        .accessibilityIdentifier("drawer.\(tab.rawValue)")
        .padding(.horizontal, 10)
    }

    private var drawerToggleButton: some View {
        Button {
            isDrawerOpen.toggle()
        } label: {
            Image(systemName: isDrawerOpen ? "xmark" : "sidebar.leading")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 42, height: 42)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
        }
        .padding(.leading, 16)
        .padding(.top, 8)
        .accessibilityLabel(isDrawerOpen ? "Close Navigation Drawer" : "Open Navigation Drawer")
        .accessibilityIdentifier("home.drawer.toggle")
    }

    private func closeDrawer() {
        isDrawerOpen = false
    }

    private var chatHistorySections: [OmerChatHistorySection] {
        OmerChatHistorySection.grouped(Array(drawerChatHistory.prefix(20)))
    }

    @MainActor
    private func loadDrawerChatHistory() async {
        drawerChatHistory = await OmerChatService.shared.cachedChats()
        isRefreshingChatHistory = true
        defer { isRefreshingChatHistory = false }
        if let remoteChats = try? await OmerChatService.shared.fetchChats(limit: 50).chats {
            drawerChatHistory = remoteChats
        }
    }

    @MainActor
    private func deleteChat(_ chat: OmerChatSummary) async {
        isDeletingChat = true
        chatDeletionError = nil
        defer { isDeletingChat = false }

        do {
            try await OmerChatService.shared.deleteChat(id: chat.id)
            drawerChatHistory.removeAll { $0.id == chat.id }
            if requestedConversationID == chat.id {
                requestedConversationID = nil
                newChatRequestID = UUID()
            }
        } catch {
            chatDeletionError = "\(chat.title) was not deleted from Omer. Check your connection and try again."
        }
    }
}


#Preview {
    HomeView()
        .previewWith(standard: S2YApplicationStandard()) {
            S2YApplicationScheduler()
            AccountConfiguration(
                service: InMemoryAccountService(),
                activeDetails: {
                    var d = AccountDetails()
                    d.userId = "lelandstanford@stanford.edu"
                    d.name = PersonNameComponents(givenName: "Leland", familyName: "Stanford")
                    return d
                }()
            )
        }
}


private struct HomeDrawerProgressKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}


extension EnvironmentValues {
    var homeDrawerProgress: CGFloat {
        get { self[HomeDrawerProgressKey.self] }
        set { self[HomeDrawerProgressKey.self] = newValue }
    }
}
