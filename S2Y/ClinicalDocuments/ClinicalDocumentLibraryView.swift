//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import SwiftUI
import UniformTypeIdentifiers

struct ClinicalDocumentLibraryView: View {
    @StateObject private var store = ClinicalDocumentStore.shared
    @State private var isImporting = false
    @State private var isWorking = false
    @State private var documentPendingDeletion: ClinicalDocument?
    @State private var statusMessage: String?

    var body: some View {
        List {
            importSection
            documentSection

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }

            privacySection
        }
        .navigationTitle("Clinical Documents")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.pdf, .plainText],
            allowsMultipleSelection: false
        ) { result in
            importSelection(result)
        }
        .confirmationDialog(
            "Delete \(documentPendingDeletion?.displayName ?? "this document")?",
            isPresented: Binding(
                get: { documentPendingDeletion != nil },
                set: {
                    if !$0 {
                        documentPendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete from this iPhone", role: .destructive) {
                guard let document = documentPendingDeletion else {
                    return
                }
                documentPendingDeletion = nil
                delete(document)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The local file and search index will be deleted. This cannot be undone.")
        }
    }

    private var importSection: some View {
        Section {
            Button {
                isImporting = true
            } label: {
                Label("Import Document", systemImage: "doc.badge.plus")
            }
            .disabled(isWorking)
        } footer: {
            Text(
                "PDF, plain-text, and Markdown files up to 20 MB. "
                    + "Files and their search index stay on this iPhone by default."
            )
        }
    }

    @ViewBuilder private var documentSection: some View {
        Section("On this iPhone") {
            if store.documents.isEmpty {
                ContentUnavailableView(
                    "No Imported Documents",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Import a document to use relevant excerpts in Health Assistant answers.")
                )
            } else {
                ForEach(store.documents) { document in
                    documentRow(document)
                }
            }
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            Text(
                "S2Y retrieves only a few matching excerpts for each question. "
                    + "Omer receives those excerpts only when the separate sharing choice "
                    + "is enabled in Health Assistant settings."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func documentRow(_ document: ClinicalDocument) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: document.mediaType == .pdf ? "doc.richtext" : "doc.text")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(document.displayName)
                Text(documentMetadata(document))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                documentPendingDeletion = document
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete \(document.displayName)")
        }
    }

    private func documentMetadata(_ document: ClinicalDocument) -> String {
        let date = document.importedAt.formatted(date: .abbreviated, time: .omitted)
        let size = ByteCountFormatter.string(fromByteCount: Int64(document.byteCount), countStyle: .file)
        return "Imported \(date) · \(size)"
    }

    private func importSelection(_ result: Result<[URL], any Error>) {
        isWorking = true
        statusMessage = nil
        defer { isWorking = false }
        do {
            guard let url = try result.get().first else {
                return
            }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let document = try store.importDocument(from: url)
            try store.indexDocument(document)
            statusMessage = "\(document.displayName) is ready for local questions."
        } catch {
            statusMessage = "The document could not be imported: \(error.localizedDescription)"
        }
    }

    private func delete(_ document: ClinicalDocument) {
        do {
            try store.remove(document)
            statusMessage = "\(document.displayName) was deleted from this iPhone."
        } catch {
            statusMessage = "The document could not be deleted: \(error.localizedDescription)"
        }
    }
}
