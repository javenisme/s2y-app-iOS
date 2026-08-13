//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation

enum ClinicalDocumentMediaType: String, Codable, Sendable {
    case pdf
    case plainText
}

struct ClinicalDocument: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let displayName: String
    let mediaType: ClinicalDocumentMediaType
    let fileExtension: String
    let importedAt: Date
    let byteCount: Int
    let contentDigest: String
}

struct ClinicalDocumentChunk: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let documentID: UUID
    let pageNumber: Int?
    let sectionNumber: Int
    let text: String
}

struct ClinicalDocumentIndex: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let documentID: UUID
    let indexedAt: Date
    let chunks: [ClinicalDocumentChunk]
}

struct ClinicalDocumentCitation: Equatable, Identifiable, Sendable {
    let id: String
    let marker: String
    let documentID: UUID
    let documentName: String
    let locator: String
    let excerpt: String
}

struct ClinicalDocumentQuestionContext: Equatable, Sendable {
    let prompt: String
    let citations: [ClinicalDocumentCitation]
}

struct RankedClinicalDocumentChunk: Sendable {
    let document: ClinicalDocument
    let chunk: ClinicalDocumentChunk
    let score: Int
}

enum ClinicalDocumentStoreError: LocalizedError, Equatable {
    case emptyFile
    case fileTooLarge(maximumBytes: Int)
    case invalidFile
    case invalidTextEncoding
    case missingFile
    case noReadableText
    case unsupportedType

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The selected document is empty."
        case .fileTooLarge(let maximumBytes):
            return "Choose a document smaller than \(maximumBytes / 1_000_000) MB."
        case .invalidFile:
            return "The selected document could not be read safely."
        case .invalidTextEncoding:
            return "The text document must use UTF-8 or UTF-16 encoding."
        case .missingFile:
            return "The local document file is missing."
        case .noReadableText:
            return "No selectable text was found. Scanned images require OCR, which is not enabled."
        case .unsupportedType:
            return "Choose a PDF, plain-text, or Markdown document."
        }
    }
}
