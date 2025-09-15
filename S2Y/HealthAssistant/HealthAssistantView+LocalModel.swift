//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SwiftUI
import OSLog

/// HealthAssistantView 本地模型集成扩展
extension HealthAssistantView {
    
    /// 增强的健康助手视图，集成本地AI模型
    struct EnhancedHealthAssistantView: View {
        @State private var inputText: String = ""
        @State private var messages: [ChatMessage] = []
        @State private var isProcessing = false
        @State private var errorMessage: String?
        @State private var showingSettings = false
        @State private var useLocalModel = false
        
        // 本地模型相关状态
        @State private var localModelManager = LocalHealthModelManager.shared
        @State private var downloadManager = ModelDownloadManager.shared
        @State private var showingModelDownload = false
        
        private let healthService = HealthKitService.shared
        private let enhancedProvider = EnhancedLLMProvider.shared
        private let logger = Logger(subsystem: "com.s2y.app", category: "EnhancedHealthAssistant")
        
        var body: some View {
            NavigationView {
                VStack(spacing: 0) {
                    // 本地模型状态指示器
                    if localModelManager.isModelLoaded || localModelManager.modelStatus == .loading {
                        LocalModelStatusView()
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }
                    
                    if messages.isEmpty {
                        enhancedWelcomeView
                    } else {
                        enhancedMessagesScrollView
                    }
                    
                    if let errorMessage {
                        errorBanner(errorMessage)
                    }
                    
                    enhancedInputBar
                }
                .navigationTitle("智能健康助手")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        localModelToggle
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack {
                            downloadModelButton
                            settingsButton
                        }
                    }
                }
                .sheet(isPresented: $showingSettings) {
                    HealthAssistantSettingsView()
                }
                .sheet(isPresented: $showingModelDownload) {
                    ModelDownloadView()
                }
            }
            .task {
                await initializeEnhancedAssistant()
            }
        }
        
        // MARK: - UI Components
        
        private var enhancedWelcomeView: some View {
            VStack(spacing: 24) {
                // AI图标和标题
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [.blue.opacity(0.1), .purple.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    }
                    
                    VStack(spacing: 4) {
                        Text("智能健康助手")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(localModelStatusText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 功能介绍
                VStack(alignment: .leading, spacing: 12) {
                    featureRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "数据分析",
                        description: "分析您的健康趋势和模式"
                    )
                    
                    featureRow(
                        icon: "lightbulb.max",
                        title: "个性化建议",
                        description: "基于您的数据提供定制建议"
                    )
                    
                    featureRow(
                        icon: "shield.lefthalf.filled",
                        title: "隐私保护",
                        description: useLocalModel ? "完全本地处理，数据不外泄" : "遵守严格的隐私保护政策"
                    )
                }
                .padding(.horizontal)
                
                // 快速查询按钮
                quickQueryButtons
                
                Spacer(minLength: 20)
            }
            .padding()
        }
        
        private var quickQueryButtons: some View {
            VStack(spacing: 12) {
                Text("快速查询")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                    quickQueryButton("我今天的步数如何？", icon: "figure.walk")
                    quickQueryButton("最近的睡眠质量怎样？", icon: "bed.double")
                    quickQueryButton("心率变化有什么趋势？", icon: "heart.fill")
                    quickQueryButton("本周的活动能量消耗", icon: "flame.fill")
                }
            }
        }
        
        private func quickQueryButton(_ query: String, icon: String) -> some View {
            Button(action: {
                processQuickQuery(query)
            }) {
                VStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    
                    Text(query)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
        }
        
        private var enhancedMessagesScrollView: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(messages) { message in
                            EnhancedChatMessageView(message: message)
                                .id(message.id)
                        }
                        
                        if isProcessing {
                            typingIndicator
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastMessage = messages.last {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        
        private var typingIndicator: some View {
            HStack {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 8, height: 8)
                            .scaleEffect(isProcessing ? 1.0 : 0.5)
                            .animation(
                                .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                                value: isProcessing
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray5))
                .cornerRadius(16)
                
                Spacer()
            }
        }
        
        private var enhancedInputBar: some View {
            VStack(spacing: 8) {
                // 模式指示器
                if useLocalModel {
                    HStack {
                        Image(systemName: "brain.head.profile.fill")
                            .foregroundColor(.green)
                        Text("本地AI模式 - 完全隐私保护")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                }
                
                HStack(spacing: 12) {
                    TextField("询问关于您健康数据的问题...", text: $inputText, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .lineLimit(1...4)
                        .disabled(isProcessing)
                    
                    Button(action: sendMessage) {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
                    .buttonStyle(.borderedProminent)
                    .frame(width: 44, height: 44)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .background(Color(.systemBackground))
        }
        
        private var localModelToggle: some View {
            Button(action: {
                useLocalModel.toggle()
                logger.info("Switched to \(useLocalModel ? "local" : "cloud") model")
            }) {
                HStack(spacing: 4) {
                    Image(systemName: useLocalModel ? "brain.head.profile.fill" : "cloud.fill")
                        .font(.caption)
                    Text(useLocalModel ? "本地" : "云端")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundColor(useLocalModel ? .green : .blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(useLocalModel ? .green.opacity(0.1) : .blue.opacity(0.1))
                )
            }
        }
        
        private var downloadModelButton: some View {
            Button(action: {
                showingModelDownload = true
            }) {
                Image(systemName: "arrow.down.circle")
                    .foregroundColor(.accentColor)
            }
        }
        
        private var settingsButton: some View {
            Button(action: {
                showingSettings = true
            }) {
                Image(systemName: "gear")
                    .accessibilityLabel("设置")
            }
        }
        
        // MARK: - Helper Methods
        
        private func featureRow(icon: String, title: String, description: String) -> some View {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
        
        private var localModelStatusText: String {
            switch localModelManager.modelStatus {
            case .loaded:
                return "本地AI已就绪 • 完全隐私保护"
            case .loading:
                return "本地AI加载中..."
            case .error:
                return "本地AI暂不可用 • 将使用云端服务"
            case .notLoaded:
                return "支持云端和本地AI模式"
            }
        }
        
        private func errorBanner(_ message: String) -> some View {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer()
                Button("关闭") {
                    errorMessage = nil
                }
                .font(.subheadline)
                .foregroundColor(.accentColor)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)
        }
        
        // MARK: - Business Logic
        
        private func initializeEnhancedAssistant() async {
            logger.info("Initializing enhanced health assistant")
            
            // 检查是否需要下载本地模型
            if UserDefaults.standard.bool(forKey: "AutoDownloadLocalModel") {
                do {
                    try await downloadManager.downloadModelIfNeeded()
                    await localModelManager.loadModelIfNeeded()
                } catch {
                    logger.error("Failed to initialize local model: \(error)")
                }
            }
            
            // 预加载云端服务
            await enhancedProvider.preloadLocalModel()
        }
        
        private func processQuickQuery(_ query: String) {
            inputText = query
            sendMessage()
        }
        
        private func sendMessage() {
            let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { return }
            
            // 添加用户消息
            let userMessage = ChatMessage(role: .user, content: trimmedText)
            messages.append(userMessage)
            
            // 清空输入
            inputText = ""
            isProcessing = true
            errorMessage = nil
            
            Task {
                await processUserMessage(trimmedText)
            }
        }
        
        private func processUserMessage(_ message: String) async {
            logger.info("Processing user message with enhanced provider")
            
            do {
                let response: String
                
                if useLocalModel {
                    // 强制使用本地模型
                    response = await enhancedProvider.sendMessageLocal(message)
                } else {
                    // 智能路由选择
                    response = await enhancedProvider.sendMessageIntelligent(message)
                }
                
                await MainActor.run {
                    let assistantMessage = ChatMessage(role: .assistant, content: response)
                    messages.append(assistantMessage)
                    isProcessing = false
                }
                
                logger.info("Successfully processed user message")
                
            } catch {
                await MainActor.run {
                    errorMessage = "处理消息时出现错误：\(error.localizedDescription)"
                    isProcessing = false
                }
                
                logger.error("Failed to process message: \(error)")
            }
        }
    }
}

// MARK: - Enhanced Chat Message View

private struct EnhancedChatMessageView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role != .user {
                // AI Avatar
                Circle()
                    .fill(LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                    )
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(message.role == .user ? 
                                  Color.accentColor : 
                                  Color(.systemGray5)
                            )
                    )
                    .foregroundColor(message.role == .user ? .white : .primary)
                
                // If ChatMessage has timestamp, display; otherwise skip
                // Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if message.role == .user {
                // User Avatar
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.accentColor)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

// MARK: - Model Download View

struct ModelDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var downloadManager = ModelDownloadManager.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 48))
                        .foregroundStyle(LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    
                    VStack(spacing: 8) {
                        Text("本地AI模型")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("下载后可完全离线使用，保护您的隐私")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                
                // 下载状态
                downloadStatusView
                
                Spacer()
                
                // 行动按钮
                downloadActionButton
            }
            .padding()
            .navigationTitle("本地AI模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
    
    @ViewBuilder
    private var downloadStatusView: some View {
        VStack(spacing: 16) {
            Text(downloadManager.downloadState.description)
                .font(.headline)
            
            if case .downloading = downloadManager.downloadState {
                VStack(spacing: 8) {
                    ProgressView(value: downloadManager.downloadProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    HStack {
                        Text(String(format: "%.0f%%", downloadManager.downloadProgress * 100))
                            .font(.subheadline)
                        Spacer()
                        if !downloadManager.downloadSpeed.isEmpty {
                            Text(downloadManager.downloadSpeed)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if !downloadManager.estimatedTimeRemaining.isEmpty {
                        Text("剩余时间: \(downloadManager.estimatedTimeRemaining)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var downloadActionButton: some View {
        switch downloadManager.downloadState {
        case .idle, .failed:
            Button("下载本地AI模型") {
                Task {
                    try await downloadManager.downloadModelIfNeeded()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
        case .downloading:
            Button("取消下载") {
                downloadManager.cancelDownload()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            
        case .completed:
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.green)
                
                Text("本地AI模型已就绪！")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
            }
            
        default:
            EmptyView()
        }
    }
}