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
    @AppStorage(StorageKeys.omerIncludeHealthContext) private var omerIncludeHealthContext = true

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
                Toggle("Share Health summary with Omer", isOn: $omerIncludeHealthContext)
            } header: {
                Text("Privacy")
            } footer: {
                Text("When Omer Online is selected, this allows a short summary of relevant Health data to be included with your question. On-device analysis stays on your iPhone, while chat history may still sync to your S2Y account.")
            }

            Section("Plan") {
                NavigationLink {
                    WellnessPlanSettingsView()
                } label: {
                    Label("Wellbeing Plan", systemImage: "list.bullet.clipboard")
                }
            }

            Section {
                Button("Clear Health data cache", role: .destructive) {
                    HealthKitCache.shared.clearAll()
                    showingCacheClearedAlert = true
                }
            } header: {
                Text("Data")
            } footer: {
                Text("This removes cached Health summaries from this iPhone. It does not delete data from Apple Health.")
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
    }
}
