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

        var subtitle: String {
            switch self {
            case .healthAssistant:
                return String(localized: "Chat, insights, and connected health tools")
            case .schedule:
                return String(localized: "Tasks, reminders, and care routines")
            case .contact:
                return String(localized: "Profile, sign-in, and personal details")
            case .settings:
                return String(localized: "Preferences, permissions, and support")
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

        var tint: Color {
            switch self {
            case .healthAssistant:
                return .red
            case .schedule:
                return .indigo
            case .contact:
                return .teal
            case .settings:
                return .orange
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
                VStack(alignment: .leading, spacing: 10) {
                    newChatButton

                    if let chatDeletionError {
                        Text(chatDeletionError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 24)
                            .accessibilityIdentifier("drawer.chat-delete-error")
                    }

                    if drawerChatHistory.isEmpty {
                        Text("Recent chats")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 24)
                            .padding(.top, 12)

                        Text(isRefreshingChatHistory ? "Loading conversations…" : "Your Omer and on-device chats will appear here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(chatHistorySections) { section in
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .padding(.horizontal, 24)
                                .padding(.top, 12)

                            ForEach(section.chats) { chat in
                                drawerChatRow(chat)
                            }
                        }
                    }

                    Divider()
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)

                    Text("Navigate")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 24)

                    ForEach(Tabs.allCases, id: \.self) { tab in
                        drawerRow(for: tab)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 18)
            }
        }
        .frame(width: width, alignment: .leading)
        .accessibilityHidden(!isDrawerOpen)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [
                        Color(uiColor: .secondarySystemBackground),
                        Color(uiColor: .systemGroupedBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color.red.opacity(0.08))
                    .frame(width: 220, height: 220)
                    .offset(x: -40, y: -60)
            }
            .ignoresSafeArea()
        )
    }

    private var drawerHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.red.opacity(0.14))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "heart.text.square.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("S2Y")
                        .font(.title2.weight(.semibold))
                    Text("Personal health navigation")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
    }

    private var newChatButton: some View {
        Button {
            selectedTab = .healthAssistant
            requestedConversationID = nil
            newChatRequestID = UUID()
            closeDrawer()
        } label: {
            Label("New chat", systemImage: "square.and.pencil")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .accessibilityIdentifier("drawer.new-chat")
    }

    private func drawerChatRow(_ chat: OmerChatSummary) -> some View {
        HStack(spacing: 8) {
            Button {
                selectedTab = .healthAssistant
                requestedConversationID = chat.id
                closeDrawer()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(chat.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
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
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .padding(.vertical, 4)
    }

    private func drawerRow(for tab: Tabs) -> some View {
        Button {
            selectedTab = tab
            closeDrawer()
        } label: {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tab.tint.opacity(selectedTab == tab ? 0.18 : 0.1))
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: tab.systemImage)
                            .font(.title3)
                            .foregroundStyle(tab.tint)
                            .accessibilityHidden(true)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(tab.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(tab.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if selectedTab == tab {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(tab.tint)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        selectedTab == tab
                            ? Color(uiColor: .secondarySystemGroupedBackground)
                            : Color.clear
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityValue(selectedTab == tab ? "Selected" : "")
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
        .accessibilityIdentifier(tab == .contact ? "drawer.account" : "drawer.\(tab.rawValue)")
        .padding(.horizontal, 14)
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
