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
                return "Health Assistant"
            case .schedule:
                return "Schedule"
            case .contact:
                return "Account"
            case .settings:
                return "Settings"
            }
        }

        var subtitle: String {
            switch self {
            case .healthAssistant:
                return "Chat, insights, and connected health tools"
            case .schedule:
                return "Tasks, reminders, and care routines"
            case .contact:
                return "Profile, sign-in, and personal details"
            case .settings:
                return "Preferences, permissions, and support"
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

    @State private var presentingAccount = false
    @State private var isDrawerOpen = false


    var body: some View {
        GeometryReader { geometry in
            let drawerWidth = min(geometry.size.width * 0.82, 320)

            ZStack(alignment: .leading) {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                drawer(width: drawerWidth)

                contentLayer(drawerWidth: drawerWidth)
            }
            .animation(.snappy(duration: 0.28, extraBounce: 0), value: isDrawerOpen)
        }
        .sheet(isPresented: $presentingAccount) {
            AccountSheet(dismissAfterSignIn: false) // presentation was user initiated, do not automatically dismiss
        }
        .accountRequired(!FeatureFlags.disableFirebase && !FeatureFlags.skipOnboarding) {
            AccountSheet()
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .healthAssistant:
            HealthAssistantView()
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
            .allowsHitTesting(!isDrawerOpen)
    }

    private func drawer(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            drawerHeader

            VStack(alignment: .leading, spacing: 10) {
                Text("Navigate")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 6)

                ForEach(Tabs.allCases, id: \.self) { tab in
                    drawerRow(for: tab)
                }
            }
            .padding(.top, 10)

            Spacer(minLength: 20)

            drawerFooter
        }
        .frame(width: width, alignment: .leading)
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
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("S2Y")
                        .font(.title2.weight(.semibold))
                    Text("Personal health navigation")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                selectedTab = .contact
                closeDrawer()
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.teal.opacity(0.14))
                        .frame(width: 42, height: 42)
                        .overlay {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundStyle(.teal)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open account")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Manage sign-in and profile details")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.regularMaterial)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open account")
            .accessibilityIdentifier("drawer.account")
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
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
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(tab.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(tab.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                if selectedTab == tab {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(tab.tint)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(selectedTab == tab ? Color.white.opacity(0.9) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier("drawer.\(tab.rawValue)")
        .padding(.horizontal, 14)
    }

    private var drawerFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Note")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text("Use the drawer for major destinations, and keep feature settings deeper inside each area. This gives the app a cleaner hierarchy than the old bottom tab bar.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
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
