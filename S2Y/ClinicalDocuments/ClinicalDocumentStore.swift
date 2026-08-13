//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import CryptoKit
import Foundation

@MainActor
final class ClinicalDocumentStore: ObservableObject {
    static let shared = ClinicalDocumentStore()
    static let maximumDocumentBytes = 20_000_000

    @Published private(set) var documents: [ClinicalDocument]

    private let fileManager: FileManager
    private let rootURL: URL
    private let manifestURL: URL
    private let encoder = JSONEncoder()

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? URL.applicationSupportDirectory
            .appendingPathComponent("ClinicalDocuments", isDirectory: true)
        self.manifestURL = self.rootURL.appendingPathComponent("manifest.json")
        self.documents = (try? Data(contentsOf: self.manifestURL))
            .flatMap { try? JSONDecoder().decode([ClinicalDocument].self, from: $0) }
            ?? []
    }

    private static func searchTerms(in query: String) -> [String] {
        let ignored = Set([
            "about", "after", "before", "could", "from", "have", "that", "the",
            "this", "what", "when", "where", "which", "with", "would"
        ])
        let normalizedQuery = normalized(query)
        var terms = normalizedQuery
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 2 && !ignored.contains($0) }
        if normalizedQuery.count >= 2 {
            terms.append(normalizedQuery)
        }
        return Array(Set(terms)).sorted()
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    @discardableResult
    func importDocument(from sourceURL: URL, at date: Date = .now) throws -> ClinicalDocument {
        let media = try mediaType(for: sourceURL)
        let resourceValues = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard resourceValues.isRegularFile != false else {
            throw ClinicalDocumentStoreError.invalidFile
        }
        guard let byteCount = resourceValues.fileSize, byteCount > 0 else {
            throw ClinicalDocumentStoreError.emptyFile
        }
        guard byteCount <= Self.maximumDocumentBytes else {
            throw ClinicalDocumentStoreError.fileTooLarge(maximumBytes: Self.maximumDocumentBytes)
        }

        let data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
        guard data.count == byteCount else {
            throw ClinicalDocumentStoreError.invalidFile
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let existing = documents.first(where: { $0.contentDigest == digest }) {
            return existing
        }

        let document = ClinicalDocument(
            id: UUID(),
            displayName: displayName(for: sourceURL),
            mediaType: media.type,
            fileExtension: media.fileExtension,
            importedAt: date,
            byteCount: data.count,
            contentDigest: digest
        )
        try prepareRootDirectory()
        let destination = storedFileURL(for: document)
        do {
            try data.write(to: destination, options: [.atomic, .completeFileProtection])
            documents.append(document)
            documents.sort { $0.importedAt > $1.importedAt }
            try persistManifest()
        } catch {
            documents.removeAll { $0.id == document.id }
            try? fileManager.removeItem(at: destination)
            throw error
        }
        return document
    }

    func fileURL(for document: ClinicalDocument) throws -> URL {
        let url = storedFileURL(for: document)
        guard fileManager.fileExists(atPath: url.path) else {
            throw ClinicalDocumentStoreError.missingFile
        }
        return url
    }

    @discardableResult
    func indexDocument(_ document: ClinicalDocument, at date: Date = .now) throws -> ClinicalDocumentIndex {
        let data = try Data(contentsOf: fileURL(for: document), options: .mappedIfSafe)
        let index = try ClinicalDocumentIndexer.makeIndex(for: document, data: data, at: date)
        try encoder.encode(index).write(
            to: indexURL(for: document.id),
            options: [.atomic, .completeFileProtection]
        )
        return index
    }

    func search(query: String, maximumResults: Int = 4) -> [ClinicalDocumentCitation] {
        let terms = Self.searchTerms(in: query)
        guard !terms.isEmpty, maximumResults > 0 else {
            return []
        }
        let ranked = documents.flatMap { document -> [RankedClinicalDocumentChunk] in
            guard let data = try? Data(contentsOf: indexURL(for: document.id)),
                  let index = try? JSONDecoder().decode(ClinicalDocumentIndex.self, from: data),
                  index.schemaVersion == ClinicalDocumentIndexer.schemaVersion,
                  index.documentID == document.id else {
                return []
            }
            return index.chunks.compactMap { chunk in
                let normalized = Self.normalized(chunk.text)
                let score = terms.reduce(0) { partial, term in
                    partial + (normalized.contains(term) ? 1 : 0)
                }
                return score > 0
                    ? RankedClinicalDocumentChunk(document: document, chunk: chunk, score: score)
                    : nil
            }
        }
        return ranked
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                if lhs.document.importedAt != rhs.document.importedAt {
                    return lhs.document.importedAt > rhs.document.importedAt
                }
                return lhs.chunk.id < rhs.chunk.id
            }
            .prefix(maximumResults)
            .enumerated()
            .map { offset, item in
                ClinicalDocumentCitation(
                    id: item.chunk.id,
                    marker: "D\(offset + 1)",
                    documentID: item.document.id,
                    documentName: item.document.displayName,
                    locator: item.chunk.pageNumber.map { "page \($0)" } ?? "section \(item.chunk.sectionNumber)",
                    excerpt: String(item.chunk.text.prefix(700))
                )
            }
    }

    func remove(_ document: ClinicalDocument) throws {
        guard documents.contains(where: { $0.id == document.id }) else {
            return
        }
        let originalURL = storedFileURL(for: document)
        let documentIndexURL = indexURL(for: document.id)
        if fileManager.fileExists(atPath: originalURL.path) {
            try fileManager.removeItem(at: originalURL)
        }
        if fileManager.fileExists(atPath: documentIndexURL.path) {
            try fileManager.removeItem(at: documentIndexURL)
        }
        documents.removeAll { $0.id == document.id }
        try persistManifest()
    }

    func clear() throws {
        if fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.removeItem(at: rootURL)
        }
        documents = []
    }

    private func mediaType(for url: URL) throws -> (type: ClinicalDocumentMediaType, fileExtension: String) {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return (.pdf, "pdf")
        case "txt":
            return (.plainText, "txt")
        case "md", "markdown":
            return (.plainText, "md")
        default:
            throw ClinicalDocumentStoreError.unsupportedType
        }
    }

    private func displayName(for url: URL) -> String {
        let normalized = url.deletingPathExtension().lastPathComponent
            .components(separatedBy: .controlCharacters)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((normalized.isEmpty ? "Imported document" : normalized).prefix(160))
    }

    private func prepareRootDirectory() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRootURL = rootURL
        try? mutableRootURL.setResourceValues(values)
    }

    private func storedFileURL(for document: ClinicalDocument) -> URL {
        rootURL.appendingPathComponent("\(document.id.uuidString.lowercased()).\(document.fileExtension)")
    }

    private func indexURL(for documentID: UUID) -> URL {
        rootURL.appendingPathComponent("\(documentID.uuidString.lowercased()).index.json")
    }

    private func persistManifest() throws {
        try encoder.encode(documents).write(
            to: manifestURL,
            options: [.atomic, .completeFileProtection]
        )
    }
}
