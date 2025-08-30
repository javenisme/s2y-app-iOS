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
        metricTitle(kind: metricKind)
    }
    
    private var unit: String {
        metricUnit(kind: metricKind)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(title) - \(trend.windowDays) Day Trend")
                    .font(.headline)
                
                HStack {
                    Text("Average: \(String(format: "%.1f", trend.average)) \(unit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    HStack {
                        Image(systemName: trend.changeRate >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .foregroundColor(trend.changeRate >= 0 ? .green : .red)
                        Text("\(String(format: "%.1f", abs(trend.changeRate * 100)))%")
                            .foregroundColor(trend.changeRate >= 0 ? .green : .red)
                    }
                    .font(.caption)
                }
            }
            
            Chart {
                ForEach(trend.points, id: \.date) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(title, point.value)
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value(title, point.value)
                    )
                    .foregroundStyle(.blue)
                    .symbolSize(30)
                }
                
                // Average line
                RuleMark(y: .value("Average", trend.average))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("Avg")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(4)
                    }
            }
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: max(1, trend.windowDays / 7))) { _ in
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
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func metricUnit(kind: HealthKitService.MetricKind) -> String {
        switch kind {
        case .steps: return "steps"
        case .heartRateAverage, .restingHeartRate: return "bpm"
        case .activeEnergy: return "kcal"
        case .bodyMass: return "kg"
        case .sleepDurationHours: return "hours"
        }
    }
    
    private func metricTitle(kind: HealthKitService.MetricKind) -> String {
        switch kind {
        case .steps: return "Steps"
        case .heartRateAverage: return "Average Heart Rate"
        case .restingHeartRate: return "Resting Heart Rate"
        case .activeEnergy: return "Active Energy"
        case .bodyMass: return "Body Mass"
        case .sleepDurationHours: return "Sleep Duration"
        }
    }
}

struct HealthComparisonChart: View {
    let comparison: HealthKitService.Comparison
    let metricKind: HealthKitService.MetricKind
    
    private var title: String {
        metricTitle(kind: metricKind)
    }
    
    private var unit: String {
        metricUnit(kind: metricKind)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(title) - Comparison Analysis")
                    .font(.headline)
                
                Text("\(comparison.currentWindowDays) Day Window Comparison")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 20) {
                // Bar Chart
                HStack(spacing: 12) {
                    VStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.blue.opacity(0.7))
                            .frame(width: 40, height: max(20, CGFloat(comparison.previousAverage / max(comparison.currentAverage, comparison.previousAverage, 1) * 120)))
                        Text("Previous")
                            .font(.caption2)
                    }
                    
                    VStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.blue)
                            .frame(width: 40, height: max(20, CGFloat(comparison.currentAverage / max(comparison.currentAverage, comparison.previousAverage, 1) * 120)))
                        Text("Current")
                            .font(.caption2)
                    }
                }
                
                Spacer()
                
                // Statistics
                VStack(alignment: .trailing, spacing: 8) {
                    HStack {
                        Text("Current Avg:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(String(format: "%.1f", comparison.currentAverage)) \(unit)")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text("Previous Avg:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(String(format: "%.1f", comparison.previousAverage)) \(unit)")
                            .font(.caption)
                    }
                    
                    Divider()
                        .frame(width: 80)
                    
                    HStack {
                        Text("Change:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            Image(systemName: comparison.delta >= 0 ? "arrow.up" : "arrow.down")
                                .font(.caption2)
                            Text("\(String(format: "%.1f", abs(comparison.deltaRate * 100)))%")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(comparison.delta >= 0 ? .green : .red)
                    }
                }
            }
            
            // Interpretation
            VStack(alignment: .leading, spacing: 4) {
                Text("Analysis")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Text(interpretComparison())
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func interpretComparison() -> String {
        let change = abs(comparison.deltaRate * 100)
        let direction = comparison.delta >= 0 ? "increase" : "decrease"
        
        if change < 5 {
            return "Data remains relatively stable with minimal changes."
        } else if change < 15 {
            return "Shows a \(direction) of \(String(format: "%.1f", change))%, indicating minor changes."
        } else if change < 30 {
            return "Shows a \(direction) of \(String(format: "%.1f", change))%, indicating noticeable changes."
        } else {
            return "Shows a \(direction) of \(String(format: "%.1f", change))%, indicating significant changes that warrant attention."
        }
    }
    
    private func metricUnit(kind: HealthKitService.MetricKind) -> String {
        switch kind {
        case .steps: return "steps"
        case .heartRateAverage, .restingHeartRate: return "bpm"
        case .activeEnergy: return "kcal"
        case .bodyMass: return "kg"
        case .sleepDurationHours: return "hours"
        }
    }
    
    private func metricTitle(kind: HealthKitService.MetricKind) -> String {
        switch kind {
        case .steps: return "Steps"
        case .heartRateAverage: return "Average Heart Rate"
        case .restingHeartRate: return "Resting Heart Rate"
        case .activeEnergy: return "Active Energy"
        case .bodyMass: return "Body Mass"
        case .sleepDurationHours: return "Sleep Duration"
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