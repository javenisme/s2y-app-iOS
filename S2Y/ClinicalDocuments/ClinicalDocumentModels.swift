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

enum ClinicalDocumentStoreError: LocalizedError, Equatable {
    case emptyFile
    case fileTooLarge(maximumBytes: Int)
    case invalidFile
    case missingFile
    case unsupportedType

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The selected document is empty."
        case .fileTooLarge(let maximumBytes):
            return "Choose a document smaller than \(maximumBytes / 1_000_000) MB."
        case .invalidFile:
            return "The selected document could not be read safely."
        case .missingFile:
            return "The local document file is missing."
        case .unsupportedType:
            return "Choose a PDF, plain-text, or Markdown document."
        }
    }
}
