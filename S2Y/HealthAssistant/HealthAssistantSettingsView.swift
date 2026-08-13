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
    @State private var showingCacheClearedAlert = false
    @State private var showingChatCacheClearedAlert = false
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
                    ClinicalRecordsSettingsView()
                } label: {
                    Label("Clinical Record Summaries", systemImage: "cross.case")
                }

                Button("Clear locally saved chat history", role: .destructive) {
                    Task {
                        await OmerChatService.shared.clearLocalChatCache()
                        showingChatCacheClearedAlert = true
                    }
                }

                Button("Clear Health data cache", role: .destructive) {
                    HealthKitCache.shared.clearAll()
                    showingCacheClearedAlert = true
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Manage clinical summaries separately. Cache actions never delete data from Apple Health.")
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
        .alert("Cache cleared", isPresented: $showingCacheClearedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Cached Health summaries were removed from this iPhone.")
        }
        .alert("Local chat history cleared", isPresented: $showingChatCacheClearedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Locally saved chat copies were removed. This does not delete conversations already synced to your S2Y account.")
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
