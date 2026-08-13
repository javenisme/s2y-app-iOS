//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation
@testable import S2Y
import XCTest

final class ClinicalDocumentStoreTests: XCTestCase {
    @MainActor
    func testImportCopiesSupportedDocumentAndPersistsManifest() throws {
        let fixture = try fixtureDirectory()
        let source = fixture.appendingPathComponent("Visit Notes.txt")
        try Data("Follow-up notes".utf8).write(to: source)
        let library = fixture.appendingPathComponent("Library", isDirectory: true)
        let store = ClinicalDocumentStore(rootURL: library)

        let imported = try store.importDocument(from: source, at: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(imported.displayName, "Visit Notes")
        XCTAssertEqual(imported.mediaType, .plainText)
        XCTAssertEqual(try Data(contentsOf: store.fileURL(for: imported)), Data("Follow-up notes".utf8))
        XCTAssertEqual(ClinicalDocumentStore(rootURL: library).documents, [imported])
    }

    @MainActor
    func testImportDeduplicatesIdenticalContent() throws {
        let fixture = try fixtureDirectory()
        let firstURL = fixture.appendingPathComponent("First.md")
        let secondURL = fixture.appendingPathComponent("Second.txt")
        try Data("same content".utf8).write(to: firstURL)
        try Data("same content".utf8).write(to: secondURL)
        let store = ClinicalDocumentStore(rootURL: fixture.appendingPathComponent("Library"))

        let first = try store.importDocument(from: firstURL)
        let second = try store.importDocument(from: secondURL)

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(store.documents.count, 1)
    }

    @MainActor
    func testImportRejectsUnsupportedAndOversizedFiles() throws {
        let fixture = try fixtureDirectory()
        let unsupported = fixture.appendingPathComponent("record.docx")
        try Data("not a document".utf8).write(to: unsupported)
        let oversized = fixture.appendingPathComponent("large.txt")
        try Data(repeating: 0, count: ClinicalDocumentStore.maximumDocumentBytes + 1).write(to: oversized)
        let store = ClinicalDocumentStore(rootURL: fixture.appendingPathComponent("Library"))

        XCTAssertThrowsError(try store.importDocument(from: unsupported)) { error in
            XCTAssertEqual(error as? ClinicalDocumentStoreError, .unsupportedType)
        }
        XCTAssertThrowsError(try store.importDocument(from: oversized)) { error in
            XCTAssertEqual(
                error as? ClinicalDocumentStoreError,
                .fileTooLarge(maximumBytes: ClinicalDocumentStore.maximumDocumentBytes)
            )
        }
        XCTAssertTrue(store.documents.isEmpty)
    }

    private func fixtureDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClinicalDocumentStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
