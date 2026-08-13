//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation
@testable import S2Y
import XCTest

final class ClinicalDocumentIndexerTests: XCTestCase {
    @MainActor
    func testPlainTextIndexReturnsTraceableRelevantCitation() throws {
        let fixture = try fixtureDirectory()
        let source = fixture.appendingPathComponent("Discharge Notes.txt")
        try Data("Sleep routine discussed. Follow up with primary care in two weeks.".utf8).write(to: source)
        let store = ClinicalDocumentStore(rootURL: fixture.appendingPathComponent("Library"))
        let document = try store.importDocument(from: source)

        let index = try store.indexDocument(document)
        let results = store.search(query: "What did the notes say about my sleep routine?")

        XCTAssertEqual(index.documentID, document.id)
        XCTAssertEqual(results.first?.marker, "D1")
        XCTAssertEqual(results.first?.documentName, "Discharge Notes")
        XCTAssertEqual(results.first?.locator, "section 1")
        XCTAssertTrue(try XCTUnwrap(results.first?.excerpt).contains("Sleep routine"))
    }

    @MainActor
    func testContextIsBoundedAndContainsOnlyMatchingChunks() throws {
        let fixture = try fixtureDirectory()
        let source = fixture.appendingPathComponent("Records.md")
        let content = "Medication list includes Example A.\n\n" + String(repeating: "Unrelated history. ", count: 300)
        try Data(content.utf8).write(to: source)
        let store = ClinicalDocumentStore(rootURL: fixture.appendingPathComponent("Library"))
        let document = try store.importDocument(from: source)
        try store.indexDocument(document)

        let context = ClinicalDocumentContextBuilder.build(
            for: "medication list",
            store: store,
            maximumCharacterCount: 1_000
        )

        XCTAssertLessThanOrEqual(try XCTUnwrap(context).prompt.count, 1_000)
        XCTAssertEqual(context?.citations.count, 1)
        XCTAssertTrue(try XCTUnwrap(context).prompt.contains("[D1]"))
    }

    @MainActor
    func testInvalidPDFAndUnrelatedQueryFailClosed() throws {
        let fixture = try fixtureDirectory()
        let invalidPDF = fixture.appendingPathComponent("Scan.pdf")
        try Data("not a pdf".utf8).write(to: invalidPDF)
        let store = ClinicalDocumentStore(rootURL: fixture.appendingPathComponent("Library"))
        let document = try store.importDocument(from: invalidPDF)

        XCTAssertThrowsError(try store.indexDocument(document)) { error in
            XCTAssertEqual(error as? ClinicalDocumentStoreError, .invalidFile)
        }
        XCTAssertTrue(store.search(query: "sleep").isEmpty)
    }

    private func fixtureDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClinicalDocumentIndexerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
