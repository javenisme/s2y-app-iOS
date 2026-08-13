//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable closure_body_length line_length sorted_imports
import Charts
import SwiftUI

struct HealthTrendChart: View {
    let trend: HealthKitService.Trend
    let metricKind: HealthKitService.MetricKind

    private var title: String {
        metricKind.displayName
    }

    private var unit: String {
        metricKind.unit
    }

    private var observedPoints: [HealthKitService.DailyMetric] {
        trend.points.filter(\.isObserved)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(title) · \(trend.windowDays) days")
                        .font(.headline)
                    Spacer()
                    HealthDataQualityBadge(quality: trend.dataQuality)
                }

                Text("\(trend.observedDays) of \(trend.expectedDays) days include data")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline) {
                    Text(metricKind.formatValue(trend.average))
                        .font(.title3.weight(.semibold))
                    Text("average")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Label(
                        "\(abs(trend.changeRate * 100).formatted(.number.precision(.fractionLength(1))))%",
                        systemImage: trend.changeRate >= 0 ? "arrow.up.right" : "arrow.down.right"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        "First to last observed value changed \(trend.changeRate >= 0 ? "up" : "down") by \(abs(trend.changeRate * 100).formatted(.number.precision(.fractionLength(1)))) percent"
                    )
                }
            }

            if observedPoints.isEmpty {
                ContentUnavailableView(
                    "No data in this period",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Connect or sync a health data source, then try again.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart {
                    ForEach(observedPoints, id: \.date) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value(title, point.value)
                        )
                        .foregroundStyle(.tint)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value(title, point.value)
                        )
                        .foregroundStyle(.tint)
                        .symbolSize(24)
                    }

                    RuleMark(y: .value("Average", trend.average))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .frame(height: 200)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, trend.windowDays / 6))) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .accessibilityLabel("\(title), \(trend.windowDays)-day trend chart")
                .accessibilityValue(
                    "Average \(trend.average.formatted(.number.precision(.fractionLength(1)))) \(unit), based on \(trend.observedDays) observed days"
                )
            }

            if trend.dataQuality == .limited {
                Label(
                    "Treat this trend cautiously because fewer than half of the days contain data.",
                    systemImage: "exclamationmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct HealthComparisonChart: View {
    let comparison: HealthKitService.Comparison
    let metricKind: HealthKitService.MetricKind

    private struct PeriodAverage: Identifiable {
        let id: String
        let title: String
        let value: Double
    }

    private var periodAverages: [PeriodAverage] {
        [
            PeriodAverage(id: "previous", title: "Previous", value: comparison.previousAverage),
            PeriodAverage(id: "current", title: "Current", value: comparison.currentAverage)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(metricKind.displayName) comparison")
                    .font(.headline)
                Spacer()
                HealthDataQualityBadge(quality: comparison.dataQuality)
            }

            Text("Two adjacent \(comparison.currentWindowDays)-day periods")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart(periodAverages) { period in
                BarMark(
                    x: .value("Period", period.title),
                    y: .value(metricKind.displayName, period.value)
                )
                .foregroundStyle(period.id == "current" ? Color.accentColor : Color.secondary.opacity(0.55))
                .annotation(position: .top) {
                    Text(metricKind.formatValue(period.value))
                        .font(.caption2.weight(.medium))
                }
            }
            .frame(height: 180)
            .accessibilityLabel("\(metricKind.displayName), period comparison chart")
            .accessibilityValue(
                "Current average \(metricKind.formatValue(comparison.currentAverage)); previous average \(metricKind.formatValue(comparison.previousAverage))"
            )

            Label {
                Text(interpretComparison())
            } icon: {
                Image(systemName: comparison.delta >= 0 ? "arrow.up.right" : "arrow.down.right")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(
                "Current: \(comparison.currentObservedDays)/\(comparison.currentWindowDays) days · Previous: \(comparison.previousObservedDays)/\(comparison.previousWindowDays) days"
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)

            if comparison.dataQuality == .limited {
                Label(
                    "This comparison has limited coverage in at least one period.",
                    systemImage: "exclamationmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func interpretComparison() -> String {
        let change = abs(comparison.deltaRate * 100)
        let direction = comparison.delta >= 0 ? "higher" : "lower"

        if change < 5 {
            return "The two period averages are similar."
        }
        return "The current average is \(change.formatted(.number.precision(.fractionLength(1))))% \(direction) than the previous period. This describes a change, not whether it is medically good or bad."
    }
}

private struct HealthDataQualityBadge: View {
    let quality: HealthKitService.DataQuality

    private var title: String {
        switch quality {
        case .unavailable: "No data"
        case .limited: "Limited"
        case .sufficient: "Good coverage"
        case .complete: "Complete"
        }
    }

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .accessibilityLabel("Data coverage: \(title)")
    }
}

struct PersonalHealthInsightCard: View {
    let report: PersonalHealthInsightReport

    private var notableDeviations: [PersonalMetricDeviation] {
        report.deviations.filter { $0.direction != .undetermined }
    }

    private var availableRelationships: [DescriptiveHealthRelationship] {
        report.relationships.filter { $0.availability == .available }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Your recent patterns", systemImage: "sparkles")
                .font(.headline)

            Text("Based on observed days from the last \(report.windowDays) days")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(notableDeviations, id: \.metricKind) { deviation in
                VStack(alignment: .leading, spacing: 3) {
                    Text(deviation.metricKind.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(deviationText(deviation))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(availableRelationships.indices, id: \.self) { index in
                Text(availableRelationships[index].explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !report.hasUsableInsight {
                Text("More overlapping days are needed before S2Y can describe a personal pattern.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text(coverageText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel("Personal health insight summary")
    }

    private var coverageText: String {
        report.coverage.map { coverage in
            "\(coverage.metricKind.displayName): \(coverage.observedDays)/\(coverage.expectedDays) days"
        }.joined(separator: " · ")
    }

    private func deviationText(_ deviation: PersonalMetricDeviation) -> String {
        switch deviation.direction {
        case .lower:
            "Recent values are lower than your own earlier baseline."
        case .higher:
            "Recent values are higher than your own earlier baseline."
        case .typical:
            "Recent values are within your typical personal range."
        case .undetermined:
            "There is not enough data to compare with your personal baseline."
        }
    }
}

struct HealthMetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    let trend: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)
                
                Spacer()
                
                if let trend {
                    Text(trend)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(alignment: .bottom, spacing: 4) {
                    Text(value)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .offset(y: -2)
                }
            }
        }
        .padding()
        .frame(height: 80)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

struct HealthInsightCard: View {
    let title: String
    let insight: String
    let recommendation: String?
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            Text(insight)
                .font(.body)
                .foregroundColor(.primary)
            
            if let recommendation {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recommendation")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    Text(recommendation)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}
