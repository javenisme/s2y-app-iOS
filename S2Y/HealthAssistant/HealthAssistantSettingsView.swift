//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SwiftUI

struct HealthAssistantSettingsView: View {
    let showsDismissButton: Bool

    @Environment(\.dismiss) private var dismiss
    @StateObject private var sharingConsentStore = HealthSharingConsentStore.shared
    @State private var consentSyncMessage: String?
    @State private var omerAuthorization: HealthSharingAuthorization?
    @State private var isCheckingOmerAuthorization = false
    @State private var consentSyncRequestID = UUID()

    private var appleModelAvailability: AppleFoundationModelAvailability {
        AppleFoundationModelService.shared.availability
    }

    init(showsDismissButton: Bool = false) {
        self.showsDismissButton = showsDismissButton
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(
                    "On-device AI",
                    value: appleModelAvailability.statusTitle
                )

                LabeledContent("AI provider", value: "Choose in chat")
            } header: {
                Text("AI")
            } footer: {
                Text(
                    appleModelAvailability.recoveryGuidance
                        + " S2Y never changes providers without your selection."
                )
            }

            Section {
                Toggle(
                    "Send questions to Omer Online",
                    isOn: consentBinding(for: .omerChatText)
                )

                Toggle(
                    "Share relevant Health summary",
                    isOn: consentBinding(for: .relevantHealthSummary)
                )

                Toggle(
                    "Share selected clinical record summaries",
                    isOn: consentBinding(for: .clinicalRecordSummary)
                )

                Toggle(
                    "Share relevant imported document excerpts with Omer",
                    isOn: consentBinding(for: .importedClinicalDocumentExcerpts)
                )

                Toggle(
                    "Back up completed check-ins to S2Y account",
                    isOn: consentBinding(for: .wellbeingCheckInCloudBackup)
                )

                Toggle(
                    "Share recent check-in summaries with Omer",
                    isOn: consentBinding(for: .wellbeingCheckInSummary)
                )

                LabeledContent("Omer confirmation") {
                    Label(cloudConfirmation.title, systemImage: cloudConfirmation.systemImage)
                        .foregroundStyle(cloudConfirmation.color)
                }
                .accessibilityIdentifier("health-sharing-cloud-status")

                Button("Refresh Omer confirmation", systemImage: "arrow.clockwise") {
                    startConsentSynchronization()
                }
                .disabled(isCheckingOmerAuthorization)
                .accessibilityIdentifier("health-sharing-cloud-refresh")

                NavigationLink {
                    HealthSafetyActivityView()
                } label: {
                    Label("Safety Activity", systemImage: "shield.checkered")
                }

                NavigationLink {
                    CrossDeviceSyncSettingsView()
                } label: {
                    Label("Cross-Device Sync", systemImage: "arrow.triangle.2.circlepath.icloud")
                }
            } header: {
                Text("Privacy")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        "Each sharing choice is independent and can be withdrawn immediately. "
                        + "Clinical record summaries are never included under the general Health summary choice. "
                        + "Imported document excerpts have their own sharing choice. "
                        + "Check-in account backup and Omer analysis are separate choices. "
                        + "On-device analysis stays on this iPhone unless conversation sync is enabled."
                    )
                    if let consentSyncMessage {
                        Text(consentSyncMessage)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("Plan") {
                NavigationLink {
                    WellnessPlanSettingsView()
                } label: {
                    Label("Wellbeing Plan", systemImage: "list.bullet.clipboard")
                }
            }

            Section {
                NavigationLink {
                    HealthSummaryExportView()
                } label: {
                    Label("Health Summary PDF", systemImage: "doc.richtext")
                }

                NavigationLink {
                    LocalHealthDataControlsView()
                } label: {
                    Label("Data Controls", systemImage: "externaldrive.badge.checkmark")
                }

                NavigationLink {
                    WellbeingCheckInHistoryView()
                } label: {
                    Label("Daily Check-in History", systemImage: "checkmark.circle")
                }

                NavigationLink {
                    ClinicalRecordsSettingsView()
                } label: {
                    Label("Clinical Record Summaries", systemImage: "cross.case")
                }

                NavigationLink {
                    ClinicalDocumentLibraryView()
                } label: {
                    Label("Imported Clinical Documents", systemImage: "doc.text.magnifyingglass")
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Review, export, or delete S2Y's local copies. Apple Health and cloud data remain separate.")
            }
        }
        .navigationTitle("Health Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            startConsentSynchronization()
        }
    }

    private var cloudConfirmation: HealthSharingCloudConfirmation {
        HealthSharingCloudConfirmation(
            localAuthorization: sharingConsentStore.authorization,
            omerAuthorization: omerAuthorization,
            isChecking: isCheckingOmerAuthorization
        )
    }

    private func consentBinding(for scope: HealthSharingScope) -> Binding<Bool> {
        Binding(
            get: {
                HealthSharingConsentPolicy.permits(
                    scope,
                    authorization: sharingConsentStore.authorization
                )
            },
            set: { granted in
                sharingConsentStore.set(scope, granted: granted)
                startConsentSynchronization()
            }
        )
    }

    private func startConsentSynchronization() {
        let requestID = UUID()
        consentSyncRequestID = requestID
        consentSyncMessage = nil
        isCheckingOmerAuthorization = true
        Task {
            do {
                try await OmerChatService.shared.syncHealthSharingConsentReceipts()
                let authorization = try await OmerChatService.shared.fetchHealthSharingAuthorization()
                guard consentSyncRequestID == requestID else { return }
                omerAuthorization = authorization
                isCheckingOmerAuthorization = false
            } catch {
                guard consentSyncRequestID == requestID else { return }
                isCheckingOmerAuthorization = false
                consentSyncMessage = "This choice is applied on this iPhone. Cloud confirmation is pending until Omer is reachable."
            }
        }
    }
}

private extension HealthSharingCloudConfirmation {
    var title: String {
        switch self {
        case .checking: "Checking"
        case .confirmed: "Confirmed"
        case .pending: "Pending"
        }
    }

    var systemImage: String {
        switch self {
        case .checking: "arrow.triangle.2.circlepath"
        case .confirmed: "checkmark.seal.fill"
        case .pending: "exclamationmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .checking: .secondary
        case .confirmed: .green
        case .pending: .orange
        }
    }
}
