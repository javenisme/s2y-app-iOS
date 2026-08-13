//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import SwiftUI

struct CrossDeviceSyncSettingsView: View {
    @StateObject private var coordinator = CrossDeviceSyncCoordinator.shared

    var body: some View {
        Form {
            Section {
                ForEach(CrossDeviceSyncCategory.allCases) { category in
                    categoryRow(category)
                }
            } header: {
                Text("Choose what to sync")
            } footer: {
                Text(
                    "Every category starts off. Turning a category off stops new synchronization immediately. "
                        + "It does not silently delete a copy already stored in your account."
                )
            }

            Section("Never synchronized here") {
                Label("Raw Apple Health samples", systemImage: "heart.slash")
                Label("Health permissions and sharing consent", systemImage: "hand.raised")
                Label("API keys, tokens, and service addresses", systemImage: "key.slash")
            }

            Section {
                NavigationLink {
                    CloudHealthDataLifecycleView()
                } label: {
                    Label("Review Cloud Data and Deletion", systemImage: "cloud")
                }
            } footer: {
                Text(
                    "Conversations use your private Omer history. App preferences and wellbeing plans use your Firebase-backed S2Y account. "
                        + "Deleting cloud copies remains a separate, explicit account action."
                )
            }
        }
        .navigationTitle("Cross-Device Sync")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await coordinator.start()
        }
    }

    private func categoryRow(_ category: CrossDeviceSyncCategory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: binding(for: category)) {
                Label(category.title, systemImage: category.systemImage)
            }

            Text(category.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                statusLabel(category)
                Spacer()
                if case .failed = coordinator.states[category], coordinator.isEnabled(category) {
                    Button("Retry") {
                        coordinator.retry(category)
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private func binding(for category: CrossDeviceSyncCategory) -> Binding<Bool> {
        Binding(
            get: { coordinator.isEnabled(category) },
            set: { coordinator.set(category, enabled: $0) }
        )
    }

    @ViewBuilder
    private func statusLabel(_ category: CrossDeviceSyncCategory) -> some View {
        let state = coordinator.states[category] ?? .disabled
        switch state {
        case .saved(let date):
            Label(
                "\(state.title) · \(date.formatted(date: .omitted, time: .shortened))",
                systemImage: "checkmark.circle"
            )
            .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .syncing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text(state.title)
            }
            .foregroundStyle(.secondary)
        case .needsSignIn:
            Label(state.title, systemImage: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(.secondary)
        case .disabled:
            Label(state.title, systemImage: "pause.circle")
                .foregroundStyle(.secondary)
        }
    }
}
