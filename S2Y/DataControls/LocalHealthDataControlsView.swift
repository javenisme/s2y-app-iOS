//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SwiftUI

struct LocalHealthDataControlsView: View {
    @State private var inventory: LocalHealthDataInventorySnapshot?
    @State private var categoryPendingDeletion: LocalHealthDataCategory?
    @State private var showingDeleteAllConfirmation = false
    @State private var exportURL: URL?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            inventorySection
            exportSection
            deletionSection
            cloudBoundarySection

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Data Controls")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshInventory()
        }
        .onDisappear {
            removeTemporaryExport()
        }
        .confirmationDialog(
            "Clear \(categoryPendingDeletion?.title ?? "this category")?",
            isPresented: Binding(
                get: { categoryPendingDeletion != nil },
                set: { if !$0 { categoryPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Clear from this iPhone", role: .destructive) {
                guard let category = categoryPendingDeletion else { return }
                categoryPendingDeletion = nil
                Task { await clear(category) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Cloud copies are not affected.")
        }
        .confirmationDialog(
            "Clear all local Health Assistant data?",
            isPresented: $showingDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear all from this iPhone", role: .destructive) {
                Task { await clearAll() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone. Apple Health and cloud copies are not affected.")
        }
    }

    @ViewBuilder
    private var inventorySection: some View {
        Section {
            if let inventory {
                ForEach(inventory.items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.category.title)
                            Text(item.storageDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.itemCount.formatted())
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } else {
                ProgressView("Checking local data…")
            }
        } header: {
            Text("On this iPhone")
        } footer: {
            Text("Counts describe S2Y's local copies. They do not count data in Apple Health, Firebase, or Omer.")
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                Task { await prepareExport() }
            } label: {
                Label("Prepare Local Data Export", systemImage: "square.and.arrow.up")
            }
            .disabled(isWorking)

            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share Prepared Export", systemImage: "doc")
                }
            }
        } header: {
            Text("Export")
        } footer: {
            Text(
                "The JSON export can include chat text and sensitive health-related summaries. "
                    + "Store and share it securely."
            )
        }
    }

    @ViewBuilder
    private var deletionSection: some View {
        Section {
            if let inventory {
                ForEach(inventory.items.filter { $0.itemCount > 0 }) { item in
                    Button("Clear \(item.category.title)", role: .destructive) {
                        categoryPendingDeletion = item.category
                    }
                    .disabled(isWorking)
                }
            }

            Button("Clear All Local Health Assistant Data", role: .destructive) {
                showingDeleteAllConfirmation = true
            }
            .disabled(isWorking || inventory?.items.allSatisfy { $0.itemCount == 0 } == true)
        } header: {
            Text("Delete local data")
        } footer: {
            Text("Clearing sharing receipts also returns every outbound sharing choice to off.")
        }
    }

    private var cloudBoundarySection: some View {
        Section("Cloud data") {
            NavigationLink {
                CloudHealthDataLifecycleView()
            } label: {
                Label("Review Cloud Data and Deletion", systemImage: "cloud")
            }

            Text(
                "Local deletion never sends a remote deletion request. "
                    + "Cloud data must be deleted through the corresponding account service."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func refreshInventory() async {
        inventory = await LocalHealthDataInventory.current()
    }

    @MainActor
    private func prepareExport() async {
        isWorking = true
        errorMessage = nil
        removeTemporaryExport()
        defer { isWorking = false }

        do {
            let package = await LocalHealthDataExportService.makePackage()
            let data = try LocalHealthDataExportService.encodedData(for: package)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("S2Y-Local-Health-Data.json")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            exportURL = url
        } catch {
            errorMessage = "The local data export could not be prepared: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func clear(_ category: LocalHealthDataCategory) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await LocalHealthDataDeletionService.clear(category)
            await refreshInventory()
        } catch {
            errorMessage = "\(category.title) could not be cleared: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func clearAll() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await LocalHealthDataDeletionService.clearAll()
            removeTemporaryExport()
            await refreshInventory()
        } catch {
            errorMessage = "Local Health Assistant data could not be cleared: \(error.localizedDescription)"
        }
    }

    private func removeTemporaryExport() {
        guard let exportURL else { return }
        try? FileManager.default.removeItem(at: exportURL)
        self.exportURL = nil
    }
}
