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

    init(showsDismissButton: Bool = false) {
        self.showsDismissButton = showsDismissButton
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(
                    "On-device AI",
                    value: AppleFoundationModelService.shared.availability.isAvailable ? "Available" : "Unavailable"
                )

                LabeledContent("AI provider", value: "Choose in chat")
            } header: {
                Text("AI")
            } footer: {
                Text("Choose On-device or Omer Online above the chat input. S2Y never changes providers without your selection.")
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
                    "Sync on-device conversations",
                    isOn: consentBinding(for: .onDeviceConversationSync)
                )

                Toggle(
                    "Share selected clinical record summaries",
                    isOn: consentBinding(for: .clinicalRecordSummary)
                )

                Toggle(
                    "Back up completed check-ins to S2Y account",
                    isOn: consentBinding(for: .wellbeingCheckInCloudBackup)
                )

                Toggle(
                    "Share recent check-in summaries with Omer",
                    isOn: consentBinding(for: .wellbeingCheckInSummary)
                )

                NavigationLink {
                    HealthSafetyActivityView()
                } label: {
                    Label("Safety Activity", systemImage: "shield.checkered")
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text(
                    "Each sharing choice is independent and can be withdrawn immediately. "
                        + "Clinical record summaries are never included under the general Health summary choice. "
                        + "Check-in account backup and Omer analysis are separate choices. "
                        + "On-device analysis stays on this iPhone unless conversation sync is enabled."
                )
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
            }
        )
    }
}
