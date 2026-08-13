//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SwiftUI

struct WellbeingCheckInHistoryView: View {
    @StateObject private var store = WellbeingCheckInStore.shared
    @State private var showingClearConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if store.snapshots.isEmpty {
                ContentUnavailableView(
                    "No check-ins yet",
                    systemImage: "checkmark.circle",
                    description: Text("Complete Daily Health Check-in from Schedule to build a private local history.")
                )
            } else {
                Section {
                    ForEach(store.snapshots) { snapshot in
                        snapshotRow(snapshot)
                    }
                } header: {
                    Text("On this iPhone")
                } footer: {
                    Text("These are minimized wellbeing summaries, not diagnoses or medical records.")
                }

                Section {
                    Button("Clear local check-in history", role: .destructive) {
                        showingClearConfirmation = true
                    }
                } footer: {
                    Text("This does not alter Apple Health, provider records, or previously uploaded data.")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Daily Check-ins")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Clear local check-in history?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear from this iPhone", role: .destructive) {
                clearHistory()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func snapshotRow(_ snapshot: WellbeingCheckInSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snapshot.recordedAt, format: .dateTime.weekday(.wide).month().day().year())
                .font(.headline)

            if let overallWellbeing = snapshot.overallWellbeing {
                LabeledContent("Overall", value: displayValue(overallWellbeing))
            }
            if let energyLevel = snapshot.energyLevel {
                LabeledContent("Energy", value: displayValue(energyLevel))
            }
            if let sleepQuality = snapshot.sleepQuality {
                LabeledContent("Sleep", value: displayValue(sleepQuality))
            }
            if let stressLevel = snapshot.stressLevel {
                LabeledContent("Stress", value: displayValue(stressLevel))
            }
            if let mood = snapshot.mood {
                LabeledContent("Mood", value: displayValue(mood))
            }
            if !snapshot.reportedSymptoms.isEmpty {
                LabeledContent(
                    "Noted symptoms",
                    value: snapshot.reportedSymptoms.map(displayValue).joined(separator: ", ")
                )
            }
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }

    private func displayValue(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func clearHistory() {
        do {
            try store.clear()
        } catch {
            errorMessage = "Local check-in history could not be cleared: \(error.localizedDescription)"
        }
    }
}
