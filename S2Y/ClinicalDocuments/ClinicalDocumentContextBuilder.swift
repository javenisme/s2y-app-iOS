//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation

@MainActor
enum ClinicalDocumentContextBuilder {
    static func build(
        for query: String,
        store: ClinicalDocumentStore = .shared,
        maximumResults: Int = 4,
        maximumCharacterCount: Int = 4_000
    ) -> ClinicalDocumentQuestionContext? {
        let citations = store.search(query: query, maximumResults: maximumResults)
        guard !citations.isEmpty else {
            return nil
        }
        let header = "User-imported document excerpts. Cite their markers and do not infer beyond them."
        var lines = [header]
        var included: [ClinicalDocumentCitation] = []
        for citation in citations {
            let line = "[\(citation.marker)] \(citation.documentName), \(citation.locator): \(citation.excerpt)"
            let candidate = (lines + [line]).joined(separator: "\n")
            guard candidate.count <= maximumCharacterCount else {
                break
            }
            lines.append(line)
            included.append(citation)
        }
        guard !included.isEmpty else {
            return nil
        }
        return ClinicalDocumentQuestionContext(prompt: lines.joined(separator: "\n"), citations: included)
    }
}
