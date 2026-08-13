//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import PDFKit
@testable import S2Y
import XCTest

final class HealthSummaryPDFRendererTests: XCTestCase {
    @MainActor
    func testPDFContainsSelectedMetricsCoverageSourcesAndBoundary() throws {
        let report = HealthSummaryReport(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            startDate: Date(timeIntervalSince1970: 1_799_395_200),
            endDate: Date(timeIntervalSince1970: 1_800_000_000),
            metrics: [
                HealthSummaryMetric(
                    kind: .steps,
                    average: 8_000,
                    observedDays: 6,
                    expectedDays: 7,
                    sourceName: "Apple Watch",
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
                )
            ]
        )

        let data = HealthSummaryPDFRenderer.render(report)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "com.adobe.pdf")
        attachment.name = "S2Y-H30-Visual-QA.pdf"
        attachment.lifetime = .keepAlways
        add(attachment)
        let document = try XCTUnwrap(PDFDocument(data: data))
        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")

        XCTAssertGreaterThan(document.pageCount, 0)
        XCTAssertTrue(text.contains("S2Y Health Summary"))
        XCTAssertTrue(text.contains("Steps"))
        XCTAssertTrue(text.contains("Coverage: 6/7 days"))
        XCTAssertTrue(text.contains("Apple Watch via Apple Health"))
        XCTAssertTrue(text.contains("diagnosis, medical advice"))
    }

    @MainActor
    func testLongReportCreatesAdditionalPagesWithoutDroppingMetrics() throws {
        let metrics = HealthKitService.MetricKind.allCases.map { kind in
            HealthSummaryMetric(
                kind: kind,
                average: 10,
                observedDays: 30,
                expectedDays: 30,
                sourceName: "Apple Health",
                updatedAt: nil
            )
        }
        let report = HealthSummaryReport(
            generatedAt: .now,
            startDate: .now.addingTimeInterval(-29 * 86_400),
            endDate: .now,
            metrics: metrics
        )

        let document = try XCTUnwrap(PDFDocument(data: HealthSummaryPDFRenderer.render(report)))
        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")

        XCTAssertGreaterThan(document.pageCount, 1)
        for metric in metrics {
            XCTAssertTrue(text.contains(metric.kind.displayName))
        }
    }
}
