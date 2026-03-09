//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import FirebaseFirestore
import FirebaseStorage
import Spezi
import SpeziAccount
import SpeziHealthKit
import SpeziNotifications
#if canImport(SpeziLLM)
import SpeziLLM
#endif
#if canImport(SpeziLLMOpenAI)
import SpeziLLMOpenAI
#endif
#if canImport(SpeziBluetooth)
import SpeziBluetooth
#endif
#if canImport(SpeziDevices)
import SpeziDevices
#endif
import SpeziOnboarding
import SpeziQuestionnaire
import SpeziScheduler
import SpeziSchedulerUI
import SpeziViews
import SpeziLicense
import SwiftUI


struct ShowcaseView: View {
    @Environment(Account.self) private var account: Account?
    @Environment(HealthKit.self) private var healthKit
    @Environment(\.notificationSettings) private var notificationSettings

    @AppStorage(StorageKeys.onboardingFlowComplete) private var completedOnboardingFlow = false
    @AppStorage(StorageKeys.disableScheduler) private var disableScheduler = false
    @AppStorage(StorageKeys.disableBluetooth) private var disableBluetooth = false

    @State private var showingAccountSheet = false
    @State private var showingQuestionnaire = false
    @State private var showingOnboarding = false
    @State private var notificationAuthorized = false
    @State private var viewState: ViewState = .idle

    private var isHealthAuthorized: Bool {
        if ProcessInfo.processInfo.isPreviewSimulator {
            return false
        }
        return healthKit.isFullyAuthorized
    }

    var body: some View {
        NavigationStack {
            contentList
                .navigationTitle("Settings")
                .viewStateAlert(state: $viewState)
                .sheet(isPresented: $showingAccountSheet) { AccountSheet(dismissAfterSignIn: false) }
                .sheet(isPresented: $showingQuestionnaire) { questionnaireSheet }
                .fullScreenCover(isPresented: $showingOnboarding) { OnboardingFlow() }
                .task { await refreshNotificationAuthorization() }
        }
    }

    @ViewBuilder
    private var contentList: some View {
        List {
            assistantSection
            permissionsSection
            appSection
            supportSection
            developerSection
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var assistantSection: some View {
        Section("Health Assistant") {
            NavigationLink {
                HealthAssistantSettingsView()
            } label: {
                settingsRow(
                    title: "Assistant Preferences",
                    subtitle: "Voice, cloud gateway, cache, and runtime overrides",
                    systemImage: "heart.text.square"
                )
            }

            if !disableBluetooth {
                NavigationLink {
                    BluetoothDevicesView()
                        .navigationTitle("Bluetooth Devices")
                } label: {
                    settingsRow(
                        title: "Connected Devices",
                        subtitle: "Manage Bluetooth health accessories",
                        systemImage: "wave.3.right.circle",
                        value: "Bluetooth"
                    )
                }
            }

            if !disableScheduler {
                NavigationLink {
                    ScheduleView(presentingAccount: .constant(false))
                        .navigationTitle("Schedule")
                } label: {
                    settingsRow(
                        title: "Reminders & Schedule",
                        subtitle: "Review scheduled tasks and questionnaires",
                        systemImage: "calendar.badge.clock"
                    )
                }
            } else {
                settingsRow(
                    title: "Reminders & Schedule",
                    subtitle: "Scheduling is currently disabled by a developer override",
                    systemImage: "calendar.badge.exclamationmark",
                    value: "Off"
                )
            }
        }
    }

    @ViewBuilder
    private var permissionsSection: some View {
        Section("Permissions") {
            NavigationLink {
                HealthKitPermissions()
                    .navigationTitle("Health Permissions")
            } label: {
                settingsRow(
                    title: "Health Access",
                    subtitle: isHealthAuthorized ? "Permissions are already granted" : "Review what health data the assistant can access",
                    systemImage: "heart.circle",
                    value: isHealthAuthorized ? "Allowed" : "Review"
                )
            }

            Button(action: openAppSettings) {
                settingsRow(
                    title: "Notifications",
                    subtitle: "Manage alerts and time-sensitive notifications in the Settings app",
                    systemImage: "bell.badge",
                    value: notificationAuthorized ? "On" : "Off"
                )
            }
            .buttonStyle(.plain)

            Button(action: openAppSettings) {
                settingsRow(
                    title: "App Permissions",
                    subtitle: disableBluetooth ? "Bluetooth features are currently disabled by a developer override" : "Review Bluetooth and other system permissions in the Settings app",
                    systemImage: "switch.2",
                    value: disableBluetooth ? "Debug Off" : nil
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var appSection: some View {
        Section("App") {
            Button {
                showingQuestionnaire = true
            } label: {
                settingsRow(
                    title: "Social Support Questionnaire",
                    subtitle: "Preview the in-app questionnaire experience",
                    systemImage: "list.bullet.clipboard"
                )
            }
            .buttonStyle(.plain)

            Button {
                completedOnboardingFlow = false
                showingOnboarding = true
            } label: {
                settingsRow(
                    title: "Run Onboarding Again",
                    subtitle: "Revisit permissions and setup guidance",
                    systemImage: "figure.walk.motion"
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var supportSection: some View {
        Section("About & Support") {
            NavigationLink("Privacy Policy") {
                WebLinkView(title: "Privacy Policy", url: URL(string: "https://www.stanford.edu/site/privacy/")!)
            }
            NavigationLink("Open-Source Licenses") { ContributionsList(projectLicense: .mit) }
            NavigationLink("About") { AboutView() }
            if let url = URL(string: "https://github.com/StanfordBDHG/S2Y/issues/new") {
                Link("Report a Bug", destination: url)
            }
            if let url = URL(string: "https://github.com/StanfordBDHG/S2Y") {
                Link("Help Center", destination: url)
            }
        }
    }

    @ViewBuilder
    private var developerSection: some View {
        #if DEBUG
        Section {
            if !FeatureFlags.disableFirebase {
                Button("Write Sample Firestore Document") { writeSampleFirestore() }
                Button("Upload Sample to Storage") { uploadSampleStorage() }
            }

            if let account, let details = account.details {
                NavigationLink {
                    ProfileView()
                } label: {
                    settingsRow(
                        title: "Account",
                        subtitle: details.userId,
                        systemImage: "person.crop.circle"
                    )
                }
            } else if account != nil {
                Button("Manage Account") { showingAccountSheet = true }
            }

            #if canImport(SpeziLLMOpenAI)
            NavigationLink {
                LLMChatDemoView()
            } label: {
                settingsRow(
                    title: "LLM Chat Demo",
                    subtitle: "Internal test surface for the Cloudflare gateway",
                    systemImage: "sparkles.rectangle.stack"
                )
            }
            #endif
        } header: {
            Text("Developer")
        } footer: {
            Text("Developer tools are separated from day-to-day settings so the main experience stays focused.")
        }
        #endif
    }

    @ViewBuilder
    private func settingsRow(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        value: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 24)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            if let value {
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var questionnaireSheet: some View {
        QuestionnaireView(questionnaire: Bundle.main.questionnaire(withName: "SocialSupportQuestionnaire")) { result in
            showingQuestionnaire = false
        }
    }

    private func refreshNotificationAuthorization() async {
        notificationAuthorized = await notificationSettings().authorizationStatus == .authorized
    }

    private func writeSampleFirestore() {
        guard let accountId = account?.details?.accountId else {
            viewState = .error(AnyLocalizedError(error: FirebaseConfiguration.ConfigurationError.userNotAuthenticatedYet))
            return
        }
        let doc = FirebaseConfiguration.userCollection.document(accountId)
        doc.setData(["updatedAt": Timestamp(date: Date()), "demo": true], merge: true) { error in
            if let error {
                DispatchQueue.main.async {
                    viewState = .error(AnyLocalizedError(error: error))
                }
            }
        }
    }

    private func uploadSampleStorage() {
        guard let accountId = account?.details?.accountId else {
            viewState = .error(AnyLocalizedError(error: FirebaseConfiguration.ConfigurationError.userNotAuthenticatedYet))
            return
        }
        let ref = Storage.storage().reference().child("users/\(accountId)/demo.txt")
        let data = Data("Hello S2Y".utf8)
        ref.putData(data) { _, error in
            if let error {
                DispatchQueue.main.async {
                    viewState = .error(AnyLocalizedError(error: error))
                }
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}


#if DEBUG
#Preview {
    ShowcaseView()
        .previewWith(standard: S2YApplicationStandard()) {
            AccountConfiguration(service: InMemoryAccountService(), configuration: AccountValueConfiguration())
            HealthKit()
        }
}
#endif
