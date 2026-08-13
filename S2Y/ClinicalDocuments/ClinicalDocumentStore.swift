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

    private func persistManifest() throws {
        try encoder.encode(documents).write(
            to: manifestURL,
            options: [.atomic, .completeFileProtection]
        )
    }
}
