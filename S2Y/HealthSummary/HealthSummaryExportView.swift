//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import PDFKit
import SwiftUI

struct HealthSummaryExportView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedDays = 7
    @State private var selectedMetrics: Set<HealthKitService.MetricKind> = [
        .steps,
        .sleepDurationHours,
        .restingHeartRate
    ]
    @State private var generatedPDF: GeneratedHealthSummaryPDF?
    @State private var temporaryPDFURL: URL?
    @State private var isPreparing = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Time range") {
                if dynamicTypeSize.isAccessibilitySize {
                    periodPicker
                        .pickerStyle(.navigationLink)
                } else {
                    periodPicker
                        .pickerStyle(.segmented)
                }
            }

            Section {
                ForEach(HealthPermissionGroup.allCases) { group in
                    DisclosureGroup(group.title) {
                        ForEach(group.metricKinds, id: \.self) { metric in
                            Toggle(metric.displayName, isOn: metricBinding(metric))
                        }
                    }
                }
            } header: {
                Text("Metrics")
            } footer: {
                Text("Only the metrics you select are included. Missing days remain missing and are never shown as zero.")
            }

            Section {
                Button {
                    Task { await preparePDF() }
                } label: {
                    if isPreparing {
                        ProgressView()
                    } else {
                        Label("Prepare PDF Preview", systemImage: "doc.richtext")
                    }
                }
                .disabled(selectedMetrics.isEmpty || isPreparing)
            } footer: {
                Text(
                    "The PDF is generated locally and may contain sensitive health observations. "
                        + "S2Y shows a preview before the system share sheet becomes available."
                )
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("Health Summary PDF")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $generatedPDF, onDismiss: removeGeneratedPDF) { pdf in
            HealthSummaryPDFPreview(pdf: pdf)
        }
        .onDisappear {
            if generatedPDF == nil {
                removeGeneratedPDF()
            }
        }
    }

    private var periodPicker: some View {
        Picker("Period", selection: $selectedDays) {
            Text("Last 7 days").tag(7)
            Text("Last 30 days").tag(30)
            Text("Last 90 days").tag(90)
        }
    }

    private func metricBinding(_ metric: HealthKitService.MetricKind) -> Binding<Bool> {
        Binding(
            get: { selectedMetrics.contains(metric) },
            set: { selected in
                if selected {
                    selectedMetrics.insert(metric)
                } else {
                    selectedMetrics.remove(metric)
                }
            }
        )
    }

    @MainActor
    private func preparePDF() async {
        isPreparing = true
        errorMessage = nil
        removeGeneratedPDF()
        defer { isPreparing = false }

        let report = await HealthSummaryReportBuilder.build(
            metrics: selectedMetrics,
            days: selectedDays
        )
        let data = HealthSummaryPDFRenderer.render(report)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("S2Y-Health-Summary.pdf")
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            temporaryPDFURL = url
            generatedPDF = GeneratedHealthSummaryPDF(url: url, report: report)
        } catch {
            errorMessage = "The PDF preview could not be prepared: \(error.localizedDescription)"
        }
    }

    private func removeGeneratedPDF() {
        if let temporaryPDFURL {
            try? FileManager.default.removeItem(at: temporaryPDFURL)
        }
        temporaryPDFURL = nil
        generatedPDF = nil
    }
}

private struct GeneratedHealthSummaryPDF: Identifiable {
    let id = UUID()
    let url: URL
    let report: HealthSummaryReport
}

private struct HealthSummaryPDFPreview: View {
    let pdf: GeneratedHealthSummaryPDF

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HealthSummaryPDFView(url: pdf.url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        ShareLink(item: pdf.url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityHint("Opens the system share sheet for this health summary")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Text(previewNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
        }
    }

    private var previewNotice: String {
        let count = pdf.report.metrics.count
        let noun = count == 1 ? "metric" : "metrics"
        return "Review all pages before sharing. This file contains \(count) selected \(noun)."
    }
}

private struct HealthSummaryPDFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.accessibilityLabel = "Health summary PDF preview"
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
