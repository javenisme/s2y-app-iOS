//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SwiftUI

struct ClinicalRecordsSettingsView: View {
    @State private var selectedCategories: Set<ClinicalRecordCategory> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingClearConfirmation = false
    @StateObject private var indexStore = ClinicalRecordIndexStore.shared

    private let healthService = HealthKitService.shared

    var body: some View {
        List {
            selectionSection
            statusSection
            recordsSection

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            if indexStore.index != nil {
                Section {
                    Button("Clear saved clinical summaries", role: .destructive) {
                        showingClearConfirmation = true
                    }
                } footer: {
                    Text(
                        "This removes S2Y's summary index from this iPhone. "
                            + "It does not delete records from Apple Health or your provider."
                    )
                }
            }
        }
        .navigationTitle("Clinical Records")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedCategories.isEmpty {
                selectedCategories = indexStore.index?.selectedCategories ?? []
            }
        }
        .confirmationDialog(
            "Clear saved clinical summaries?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear from this iPhone", role: .destructive) {
                clearSavedSummaries()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Apple Health and provider records will not be changed.")
        }
    }

    private var selectionSection: some View {
        Section {
            ForEach(ClinicalRecordCategory.allCases) { category in
                Toggle(category.title, isOn: selectionBinding(for: category))
            }

            Button("Review Access and Refresh") {
                _Concurrency.Task { await requestAndLoadRecords() }
            }
            .disabled(selectedCategories.isEmpty || isLoading)
        } header: {
            Text("Records to read")
        } footer: {
            Text(
                "S2Y reads only the categories you select after Apple's permission sheet. "
                    + "Only bounded summaries are saved locally; raw FHIR resources are not copied."
            )
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if isLoading {
            Section {
                ProgressView("Reading selected records…")
            }
        } else if let index = indexStore.index {
            Section("Local summary index") {
                LabeledContent("Readable summaries", value: index.assessment.totalRecordCount.formatted())
                LabeledContent("Sources", value: index.assessment.sourceCount.formatted())
                LabeledContent("Last refreshed") {
                    Text(index.refreshedAt, format: .relative(presentation: .named))
                }

                if !index.assessment.selectedCategoriesWithoutReadableRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No readable summaries")
                        Text(
                            index.assessment.selectedCategoriesWithoutReadableRecords
                                .map(\.title)
                                .sorted()
                                .joined(separator: ", ")
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Section {
                Text("No clinical summaries are saved on this iPhone.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var recordsSection: some View {
        if let records = indexStore.index?.records, !records.isEmpty {
            Section("Saved summaries") {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.displayName)
                        Text("\(record.category.title) · \(record.sourceName)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        HStack {
                            Text(record.recordedAt, format: .dateTime.year().month().day())
                            Text("·")
                            Text(record.recency().rawValue.capitalized)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .accessibilityHint("Summary from a clinical record in Apple Health")
                }
            }
        }
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
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await healthService.requestClinicalRecordAuthorization(for: selectedCategories)
            var records: [ClinicalRecordSummary] = []
            for category in ClinicalRecordCategory.allCases where selectedCategories.contains(category) {
                records.append(contentsOf: try await healthService.fetchClinicalRecordSummaries(for: category))
            }
            try indexStore.replace(with: ClinicalRecordIndex(
                records: records,
                selectedCategories: selectedCategories
            ))
        } catch {
            errorMessage = "Clinical records could not be read: \(error.localizedDescription)"
        }
    }

    private func clearSavedSummaries() {
        do {
            try indexStore.clear()
        } catch {
            errorMessage = "Saved clinical summaries could not be cleared: \(error.localizedDescription)"
        }
    }
}
