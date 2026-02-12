//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SwiftUI
import OSLog

/// 本地模型状态显示组件
struct LocalModelStatusView: View {
    // Use singleton/typealias, works in both MLX and simplified builds
    private var modelManager: LocalHealthModelManager { LocalHealthModelManager.shared }
    @State private var memoryMonitor = ModelMemoryMonitor()
    @State private var memoryStatus: MemoryStatus?
    @State private var showingMemoryDetails = false
    
    private let logger = Logger(subsystem: "S2Y", category: "ModelStatusUI")
    
    var body: some View {
        HStack(spacing: 12) {
            statusIcon
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(statusText)
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    if case .loading = modelManager.modelStatus {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    
                    Button(action: { showingMemoryDetails.toggle() }) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                if case .loading = modelManager.modelStatus {
                    ProgressView(value: modelManager.loadingProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                        .animation(.easeInOut(duration: 0.3), value: modelManager.loadingProgress)
                }
                
                if let error = modelManager.lastError {
                    Text(error.localizedDescription)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundCard)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .onAppear {
            startMemoryMonitoring()
        }
        .sheet(isPresented: $showingMemoryDetails) {
            MemoryDetailsView(memoryStatus: memoryStatus)
        }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(iconBackgroundColor)
                .frame(width: 32, height: 32)
            
            Image(systemName: iconSystemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(iconColor)
        }
    }
    
    private var backgroundCard: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(cardBackgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
    
    // MARK: - Computed Properties
    
    private var statusText: String {
        switch modelManager.modelStatus {
        case .loaded:
            return "🧠 Local AI is ready"
        case .loading:
            let progress = Int(modelManager.loadingProgress * 100)
            return "⏳ Loading AI... \(progress)%"
        case .error:
            return "⚠️ Local AI unavailable"
        case .notLoaded:
            return "💤 Local AI disabled"
        }
    }
    
    private var iconSystemName: String {
        switch modelManager.modelStatus {
        case .loaded:
            return "brain.head.profile"
        case .loading:
            return "brain.head.profile"
        case .error:
            return "exclamationmark.triangle"
        case .notLoaded:
            return "brain.head.profile"
        }
    }
    
    private var iconColor: Color {
        switch modelManager.modelStatus {
        case .loaded:
            return .green
        case .loading:
            return .orange
        case .error:
            return .red
        case .notLoaded:
            return .secondary
        }
    }
    
    private var iconBackgroundColor: Color {
        switch modelManager.modelStatus {
        case .loaded:
            return .green.opacity(0.1)
        case .loading:
            return .orange.opacity(0.1)
        case .error:
            return .red.opacity(0.1)
        case .notLoaded:
            return .secondary.opacity(0.1)
        }
    }
    
    private var cardBackgroundColor: Color {
        Color(.systemBackground)
    }
    
    private var borderColor: Color {
        switch modelManager.modelStatus {
        case .loaded:
            return .green.opacity(0.3)
        case .loading:
            return .orange.opacity(0.3)
        case .error:
            return .red.opacity(0.3)
        case .notLoaded:
            return Color(.systemGray5)
        }
    }
    
    // MARK: - Private Methods
    
    private func startMemoryMonitoring() {
        memoryMonitor.startMemoryMonitoring(interval: 10.0) { status in
            DispatchQueue.main.async {
                self.memoryStatus = status
            }
        }
    }
}

// MARK: - Memory Details View

private struct MemoryDetailsView: View {
    let memoryStatus: MemoryStatus?
    @Environment(\.dismiss) private var dismiss
    @State private var memoryMonitor = ModelMemoryMonitor()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let status = memoryStatus {
                        memoryOverviewSection(status)
                        memoryRecommendationSection(status)
                    } else {
                        noMemoryDataView
                    }
                    
                    aboutLocalAISection
                }
                .padding()
            }
            .navigationTitle("Local AI Status")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    @ViewBuilder
    private func memoryOverviewSection(_ status: MemoryStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Memory Usage")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                memoryUsageRow("Total Memory", value: "\(status.totalMB)MB", color: .primary)
                memoryUsageRow("Used", value: "\(status.usedMB)MB", color: .secondary)
                memoryUsageRow("Available", value: "\(status.availableMB)MB", color: .green)
                memoryUsageRow("App Usage", value: "\(status.appUsageMB)MB", color: .blue)
                
                Divider()
                
                HStack {
                    Text("Usage")
                        .fontWeight(.medium)
                    Spacer()
                    Text(String(format: "%.1f%%", status.usagePercentage))
                        .foregroundColor(usagePercentageColor(status.usagePercentage))
                        .fontWeight(.semibold)
                }
                
                ProgressView(value: status.usagePercentage / 100.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: usagePercentageColor(status.usagePercentage)))
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    @ViewBuilder
    private func memoryRecommendationSection(_ status: MemoryStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Model Recommendation")
                .font(.headline)
                .fontWeight(.semibold)
            
            let recommendation = memoryMonitor.recommendedModelConfiguration()
            
            HStack {
                Image(systemName: recommendationIcon(recommendation))
                    .foregroundColor(recommendationColor(recommendation))
                VStack(alignment: .leading) {
                    Text(recommendation.description)
                        .fontWeight(.medium)
                    Text(status.pressureLevel.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(recommendationColor(recommendation).opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private var noMemoryDataView: some View {
        VStack(spacing: 16) {
            Image(systemName: "memorychip")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No memory data yet")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Collecting device memory details...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 40)
    }
    
    private var aboutLocalAISection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About Local AI")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                infoRow("Model", value: "Phi-3.5 Mini")
                infoRow("Size", value: "About 1.5 GB")
                infoRow("Privacy", value: "Fully on-device processing")
                infoRow("Network", value: "Offline supported")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    @ViewBuilder
    private func memoryUsageRow(_ title: String, value: String, color: Color) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
    
    @ViewBuilder
    private func infoRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
    
    // MARK: - Helper Functions
    
    private func usagePercentageColor(_ percentage: Double) -> Color {
        switch percentage {
        case 0..<60:
            return .green
        case 60..<80:
            return .orange
        default:
            return .red
        }
    }
    
    private func recommendationIcon(_ recommendation: ModelSizeRecommendation) -> String {
        switch recommendation {
        case .large, .medium:
            return "checkmark.circle.fill"
        case .small:
            return "exclamationmark.triangle.fill"
        case .unavailable:
            return "xmark.circle.fill"
        }
    }
    
    private func recommendationColor(_ recommendation: ModelSizeRecommendation) -> Color {
        switch recommendation {
        case .large, .medium:
            return .green
        case .small:
            return .orange
        case .unavailable:
            return .red
        }
    }
}

// MARK: - Preview

#if DEBUG
struct LocalModelStatusView_Previews: PreviewProvider {
    static var previews: some View {
        LocalModelStatusView()
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
#endif
