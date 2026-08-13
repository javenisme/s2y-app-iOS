//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import UIKit

enum HealthSummaryPDFRenderer {
    private static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
    private static let margin: CGFloat = 54

    static func render(_ report: HealthSummaryReport) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "S2Y Health Summary",
            kCGPDFContextAuthor as String: "S2Y Health"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        return renderer.pdfData { context in
            var pageNumber = 0
            var cursorY: CGFloat = 0

            func beginPage() {
                context.beginPage()
                pageNumber += 1
                cursorY = drawPageHeader(report: report)
            }

            func ensureSpace(_ height: CGFloat) {
                if cursorY + height > pageRect.height - 72 {
                    drawFooter(pageNumber: pageNumber)
                    beginPage()
                }
            }

            beginPage()
            for metric in report.metrics {
                ensureSpace(108)
                cursorY = drawMetric(metric, at: cursorY)
            }

            ensureSpace(146)
            cursorY = drawBoundary(at: cursorY)
            _ = cursorY
            drawFooter(pageNumber: pageNumber)
        }
    }

    private static func drawPageHeader(report: HealthSummaryReport) -> CGFloat {
        let title = NSAttributedString(
            string: "S2Y Health Summary",
            attributes: [
                .font: UIFont.systemFont(ofSize: 27, weight: .bold),
                .foregroundColor: UIColor.label
            ]
        )
        title.draw(at: CGPoint(x: margin, y: 48))

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let dateRange = "\(dateFormatter.string(from: report.startDate)) - \(dateFormatter.string(from: report.endDate))"
        drawText(
            dateRange,
            in: CGRect(x: margin, y: 88, width: pageRect.width - margin * 2, height: 22),
            font: .systemFont(ofSize: 13, weight: .medium),
            color: .secondaryLabel
        )
        let selectedMetricDescription = report.metrics.count == 1
            ? "1 selected metric"
            : "\(report.metrics.count) selected metrics"
        drawText(
            "Prepared locally on this device - \(selectedMetricDescription)",
            in: CGRect(x: margin, y: 110, width: pageRect.width - margin * 2, height: 22),
            font: .systemFont(ofSize: 11),
            color: .secondaryLabel
        )

        UIColor.systemBlue.setFill()
        UIBezierPath(rect: CGRect(x: margin, y: 142, width: pageRect.width - margin * 2, height: 3)).fill()
        return 164
    }

    private static func drawMetric(_ metric: HealthSummaryMetric, at y: CGFloat) -> CGFloat {
        let width = pageRect.width - margin * 2
        let rect = CGRect(x: margin, y: y, width: width, height: 92)
        UIColor.secondarySystemBackground.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()

        drawText(
            metric.kind.displayName,
            in: CGRect(x: rect.minX + 16, y: rect.minY + 13, width: width - 32, height: 22),
            font: .systemFont(ofSize: 15, weight: .semibold),
            color: .label
        )
        drawText(
            metric.formattedAverage,
            in: CGRect(x: rect.minX + 16, y: rect.minY + 38, width: width * 0.45, height: 25),
            font: .systemFont(ofSize: 18, weight: .bold),
            color: .systemBlue
        )

        let coverage = Int((metric.coverageRate * 100).rounded())
        drawText(
            "Coverage: \(metric.observedDays)/\(metric.expectedDays) days (\(coverage)%)",
            in: CGRect(x: rect.minX + width * 0.48, y: rect.minY + 40, width: width * 0.48 - 16, height: 20),
            font: .systemFont(ofSize: 11, weight: .medium),
            color: .label
        )
        drawText(
            sourceDescription(metric),
            in: CGRect(x: rect.minX + 16, y: rect.minY + 67, width: width - 32, height: 16),
            font: .systemFont(ofSize: 9),
            color: .secondaryLabel
        )
        return rect.maxY + 14
    }

    private static func drawBoundary(at y: CGFloat) -> CGFloat {
        let text = "Health management note\nThis summary describes selected Apple Health observations and data coverage. It is not a diagnosis, medical advice, or a treatment recommendation. Missing data is not shown as zero. For symptoms or health concerns, contact a qualified healthcare professional."
        let rect = CGRect(x: margin, y: y, width: pageRect.width - margin * 2, height: 128)
        UIColor.systemYellow.withAlphaComponent(0.14).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()
        drawText(
            text,
            in: rect.insetBy(dx: 16, dy: 13),
            font: .systemFont(ofSize: 10.5),
            color: .label
        )
        return rect.maxY
    }

    private static func sourceDescription(_ metric: HealthSummaryMetric) -> String {
        guard let sourceName = metric.sourceName else {
            return "Source: Apple Health - no recent source metadata available"
        }
        guard let updatedAt = metric.updatedAt else {
            return "Source: \(sourceName) via Apple Health"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Source: \(sourceName) via Apple Health - latest sample \(formatter.string(from: updatedAt))"
    }

    private static func drawFooter(pageNumber: Int) {
        drawText(
            "Generated locally by S2Y - Page \(pageNumber)",
            in: CGRect(x: margin, y: pageRect.height - 46, width: pageRect.width - margin * 2, height: 16),
            font: .systemFont(ofSize: 9),
            color: .tertiaryLabel,
            alignment: .center
        )
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        ).draw(in: rect)
    }
}
