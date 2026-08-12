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
                HealthAccessSettingsView()
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

private struct HealthAccessSettingsView: View {
    @State private var requestingGroup: HealthPermissionGroup?
    @State private var requestStates: [HealthPermissionGroup: HealthPermissionRequestState] = [:]
    @State private var errorMessage: String?

    private let healthService = HealthKitService.shared

    var body: some View {
        List {
            Section {
                ForEach(HealthPermissionGroup.allCases) { group in
                    permissionRow(for: group)
                }

                NavigationLink {
                    HealthDataSourcesView()
                } label: {
                    Label("Data Sources & Freshness", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }

                NavigationLink {
                    ClinicalRecordsSettingsView()
                } label: {
                    Label("Clinical Records", systemImage: "cross.case")
                }
            } footer: {
                Text("S2Y requests each category only when you choose it. Apple does not reveal whether read access was allowed or denied, so S2Y never labels a category as Allowed.")
            }

            if requestingGroup != nil {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Requesting Health access…")
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Health Permissions")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshRequestStates()
        }
    }

    private func permissionRow(for group: HealthPermissionGroup) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: group.systemImage)
                .foregroundStyle(.red)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.title)
                    .font(.headline)
                Text(group.purpose)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(buttonTitle(for: group)) {
                _Concurrency.Task { await requestAuthorization(for: group) }
            }
            .buttonStyle(.bordered)
            .disabled(requestingGroup != nil || requestStates[group] == .unavailable)
            .accessibilityIdentifier("health-permission-\(group.rawValue)")
        }
        .padding(.vertical, 6)
    }

    private func buttonTitle(for group: HealthPermissionGroup) -> String {
        switch requestStates[group] {
        case .requested:
            "Requested"
        case .unavailable:
            "Unavailable"
        case .review, .none:
            "Review"
        }
    }

    @MainActor
    private func requestAuthorization(for group: HealthPermissionGroup) async {
        requestingGroup = group
        errorMessage = nil
        defer { requestingGroup = nil }

        do {
            try await healthService.requestAuthorization(for: [group])
            requestStates[group] = await healthService.permissionRequestState(for: group)
        } catch {
            errorMessage = "Health access could not be updated: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func refreshRequestStates() async {
        for group in HealthPermissionGroup.allCases {
            requestStates[group] = await healthService.permissionRequestState(for: group)
        }
    }
}

private struct ClinicalRecordsSettingsView: View {
    @State private var selectedCategories: Set<ClinicalRecordCategory> = []
    @State private var records: [ClinicalRecordSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let healthService = HealthKitService.shared

    var body: some View {
        List {
            Section {
                ForEach(ClinicalRecordCategory.allCases) { category in
                    Toggle(category.title, isOn: selectionBinding(for: category))
                }

                Button("Review Selected Access") {
                    _Concurrency.Task { await requestAndLoadRecords() }
                }
                .disabled(selectedCategories.isEmpty || isLoading)
            } footer: {
                Text("Clinical records are read-only. Select only the record types you want S2Y to display, then review Apple's permission sheet.")
            }

            if isLoading {
                Section {
                    ProgressView("Reading selected records…")
                }
            } else if records.isEmpty, errorMessage == nil {
                Section {
                    Text("No selected clinical records are currently readable.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Records") {
                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.displayName)
                            Text("\(record.category.title) · \(record.sourceName)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(record.recordedAt, format: .dateTime.year().month().day())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityHint("Linked to the original Health clinical record")
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Clinical Records")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func selectionBinding(for category: ClinicalRecordCategory) -> Binding<Bool> {
        Binding(
            get: { selectedCategories.contains(category) },
            set: { selected in
                if selected {
                    selectedCategories.insert(category)
                } else {
                    selectedCategories.remove(category)
                }
            }
        )
    }

    @MainActor
    private func requestAndLoadRecords() async {
        isLoading = true
        records = []
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await healthService.requestClinicalRecordAuthorization(for: selectedCategories)
            for category in ClinicalRecordCategory.allCases where selectedCategories.contains(category) {
                records.append(contentsOf: try await healthService.fetchClinicalRecordSummaries(for: category))
            }
            records.sort { $0.recordedAt > $1.recordedAt }
        } catch {
            errorMessage = "Clinical records could not be read: \(error.localizedDescription)"
        }
    }
}

private struct HealthDataSourcesView: View {
    @State private var provenance: [HealthKitService.MetricKind: HealthMetricProvenance] = [:]
    @State private var isLoading = true

    private let healthService = HealthKitService.shared

    var body: some View {
        List {
            ForEach(HealthPermissionGroup.allCases) { group in
                Section(group.title) {
                    ForEach(group.metricKinds, id: \.self) { kind in
                        provenanceRow(for: kind)
                    }
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView("Checking Health data…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .navigationTitle("Health Data Sources")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadProvenance()
        }
    }

    @ViewBuilder
    private func provenanceRow(for kind: HealthKitService.MetricKind) -> some View {
        if let item = provenance[kind] {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(kind.displayName)
                    Spacer()
                    Text(item.freshness.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(freshnessColor(item.freshness))
                }
                Text(sourceDescription(item))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(item.updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else if !isLoading {
            LabeledContent(kind.displayName, value: "No recent readable data")
                .foregroundStyle(.secondary)
        }
    }

    private func sourceDescription(_ item: HealthMetricProvenance) -> String {
        guard let deviceName = item.deviceName, deviceName != item.sourceName else {
            return item.sourceName
        }
        return "\(item.sourceName) · \(deviceName)"
    }

    private func freshnessColor(_ freshness: HealthMetricProvenance.Freshness) -> Color {
        switch freshness {
        case .current: .green
        case .aging: .orange
        case .stale: .secondary
        }
    }

    @MainActor
    private func loadProvenance() async {
        isLoading = true
        defer { isLoading = false }

        for kind in HealthKitService.MetricKind.allCases {
            if let item = try? await healthService.latestProvenance(for: kind) {
                provenance[kind] = item
            }
        }
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
