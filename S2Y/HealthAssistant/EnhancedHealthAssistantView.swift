//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable closure_body_length
import Security
import SwiftUI

struct EnhancedHealthAssistantView: View {
    @State private var inputText: String = ""
    @State private var messages: [EnhancedChatMessage] = []
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showingSettings = false
    
    private let healthService = HealthKitService.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if messages.isEmpty {
                    welcomeView
                } else {
                    messagesScrollView
                }
                
                if let errorMessage {
                    errorBanner(errorMessage)
                }
                
                inputBar
            }
            .navigationTitle("Health Assistant")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                HealthAssistantSettingsView()
            }
        }
        .task {
            await initializeHealthKit()
        }
    }
    
    private var welcomeView: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    
                    Text("Health Assistant")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Query your health data using natural language and get personalized insights and recommendations")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                    EnhancedQuickQueryCard(
                        icon: "figure.walk",
                        title: "Step Trends",
                        query: "How are my step trends over the past 7 days?",
                        action: { inputText = "How are my step trends over the past 7 days?" }
                    )
                    
                    EnhancedQuickQueryCard(
                        icon: "heart.fill",
                        title: "Heart Rate Comparison",
                        query: "Compare my average heart rate this week vs last week",
                        action: { inputText = "Compare my average heart rate this week vs last week" }
                    )
                    
                    EnhancedQuickQueryCard(
                        icon: "bed.double.fill",
                        title: "Sleep Analysis",
                        query: "How is my recent sleep quality?",
                        action: { inputText = "How is my recent sleep quality?" }
                    )
                    
                    EnhancedQuickQueryCard(
                        icon: "lightbulb.fill",
                        title: "Health Insights",
                        query: "Give me some health recommendations and insights",
                        action: { inputText = "Give me some health recommendations and insights" }
                    )
                }
                .padding(.horizontal)
                
                Spacer(minLength: 100)
            }
            .padding(.top, 32)
        }
    }
    
    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(messages) { message in
                        EnhancedMessageBubble(message: message)
                            .id(message.id)
                    }
                    
                    if isProcessing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Analyzing your health data...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _ in
                if let lastMessage = messages.last {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 12) {
                TextField("Ask about your health data...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(isProcessing)
                
                Button {
                    Task { await sendMessage() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(inputText.isEmpty ? Color.gray : Color.blue)
                        .clipShape(Circle())
                }
                .disabled(inputText.isEmpty || isProcessing)
            }
            .padding()
        }
    }
    
    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
            Spacer()
            Button("Close") {
                errorMessage = nil
            }
            .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }
    
    private func initializeHealthKit() async {
        do {
            try await healthService.requestAuthorization()
        } catch {
            errorMessage = "HealthKit authorization failed: \(error.localizedDescription)"
        }
    }
    
    private func sendMessage() async {
        let userMessage = EnhancedChatMessage(role: .user, content: .text(inputText.trimmingCharacters(in: .whitespacesAndNewlines)))
        messages.append(userMessage)
        
        let query = inputText
        inputText = ""
        isProcessing = true
        errorMessage = nil
        
        do {
            let result = try await HealthQueryProcessor.processQuery(query)
            let assistantMessage = EnhancedChatMessage(role: .assistant, content: contentFromResult(result))
            messages.append(assistantMessage)
        } catch {
            let errorResponse = EnhancedChatMessage(
                role: .assistant,
                content: .text("Sorry, an error occurred while processing your request: \(error.localizedDescription)")
            )
            messages.append(errorResponse)
        }
        
        isProcessing = false
    }
    
    private func contentFromResult(_ result: HealthQueryProcessor.QueryResult) -> EnhancedChatMessage.MessageContent {
        switch result {
        case .textResponse(let text):
            return .text(text)
        case .trend(let trend, let kind):
            return .trend(trend, kind)
        case .comparison(let comparison, let kind):
            return .comparison(comparison, kind)
        case .insights(let insights):
            return .insights(insights)
        }
    }
}

struct EnhancedChatMessage: Identifiable, Sendable {
    let id = UUID()
    let role: Role
    let content: MessageContent
    
    enum Role {
        case user
        case assistant
    }
    
    enum MessageContent {
        case text(String)
        case trend(HealthKitService.Trend, HealthKitService.MetricKind)
        case comparison(HealthKitService.Comparison, HealthKitService.MetricKind)
        case insights([HealthQueryProcessor.HealthInsight])
    }
}

struct EnhancedMessageBubble: View {
    let message: EnhancedChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                switch message.content {
                case .text(let text):
                    Text(text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(message.role == .user ? Color.blue : Color.gray.opacity(0.2))
                        )
                        .foregroundColor(message.role == .user ? .white : .primary)
                
                case .trend(let trend, let kind):
                    HealthTrendChart(trend: trend, metricKind: kind)
                        .frame(maxWidth: .infinity)
                
                case .comparison(let comparison, let kind):
                    HealthComparisonChart(comparison: comparison, metricKind: kind)
                        .frame(maxWidth: .infinity)
                
                case .insights(let insights):
                    VStack(spacing: 12) {
                        ForEach(Array(insights.enumerated()), id: \.offset) { _, insight in
                            HealthInsightCard(
                                title: insight.title,
                                insight: insight.insight,
                                recommendation: insight.recommendation,
                                icon: insight.icon,
                                color: colorFromString(insight.color)
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            
            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }
    
    private func colorFromString(_ colorName: String) -> Color {
        switch colorName.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        default: return .blue
        }
    }
}

private struct EnhancedQuickQueryCard: View {
    let icon: String
    let title: String
    let query: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(query)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding()
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}