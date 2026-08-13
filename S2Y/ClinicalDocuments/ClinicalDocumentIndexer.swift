//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation
@preconcurrency import PDFKit

enum ClinicalDocumentIndexer {
    static let schemaVersion = 1
    private static let maximumChunkCharacters = 1_200
    private static let overlapWordCount = 30

    static func makeIndex(
        for document: ClinicalDocument,
        data: Data,
        at date: Date = .now
    ) throws -> ClinicalDocumentIndex {
        let pages = try extractedPages(from: data, mediaType: document.mediaType)
        let indexedChunks = pages.flatMap { pageNumber, text in
            chunks(from: text, documentID: document.id, pageNumber: pageNumber)
        }
        guard !indexedChunks.isEmpty else {
            throw ClinicalDocumentStoreError.noReadableText
        }
        return ClinicalDocumentIndex(
            schemaVersion: schemaVersion,
            documentID: document.id,
            indexedAt: date,
            chunks: indexedChunks
        )
    }

    private static func extractedPages(
        from data: Data,
        mediaType: ClinicalDocumentMediaType
    ) throws -> [(Int?, String)] {
        switch mediaType {
        case .pdf:
            guard let pdf = PDFDocument(data: data) else {
                throw ClinicalDocumentStoreError.invalidFile
            }
            return (0..<pdf.pageCount).compactMap { index in
                guard let text = pdf.page(at: index)?.string else {
                    return nil
                }
                return (index + 1, text)
            }
        case .plainText:
            guard let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .utf16) else {
                throw ClinicalDocumentStoreError.invalidTextEncoding
            }
            return [(nil, text)]
        }
    }

    private static func chunks(
        from text: String,
        documentID: UUID,
        pageNumber: Int?
    ) -> [ClinicalDocumentChunk] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else {
            return []
        }
        var result: [ClinicalDocumentChunk] = []
        var start = 0
        while start < words.count {
            var end = start
            var characterCount = 0
            while end < words.count {
                let nextCount = characterCount + words[end].count + (end == start ? 0 : 1)
                guard nextCount <= maximumChunkCharacters || end == start else {
                    break
                }
                characterCount = nextCount
                end += 1
            }
            let sectionNumber = result.count + 1
            let chunkText = words[start..<end].joined(separator: " ")
            result.append(ClinicalDocumentChunk(
                id: "\(documentID.uuidString.lowercased())-\(pageNumber ?? 0)-\(sectionNumber)",
                documentID: documentID,
                pageNumber: pageNumber,
                sectionNumber: sectionNumber,
                text: chunkText
            ))
            guard end < words.count else {
                break
            }
            start = max(start + 1, end - overlapWordCount)
        }
        return result
    }
}
