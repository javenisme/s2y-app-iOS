//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT

import Foundation
import OSLog

/// Manages conversation context and memory for multi-turn dialogues
@MainActor
public final class ConversationContextManager: ObservableObject {
    public static let shared = ConversationContextManager()
    
    private let logger = Logger(subsystem: "com.s2y.app", category: "ConversationContext")
    private let maxContextMessages = 10 // Keep last 10 messages for context
    private let maxContextAge: TimeInterval = 3600 // 1 hour context retention
    
    @Published public private(set) var currentContext: ConversationContext
    
    private init() {
        self.currentContext = ConversationContext()
    }
    
    /// Add a message to the conversation context
    public func addMessage(_ message: ContextMessage) {
        currentContext.messages.append(message)
        
        // Clean up old messages
        cleanupOldMessages()
        
        // Update context metadata
        updateContextMetadata(for: message)
        
        logger.debug("Added message to context: \(message.role.rawValue) - \(message.content.prefix(50))...")
    }
    
    /// Get conversation context for LLM
    public func getContextForLLM() -> String {
        let recentMessages = currentContext.messages.suffix(maxContextMessages)
        let contextString = recentMessages.map { message in
            "\(message.role.rawValue): \(message.content)"
        }.joined(separator: "\n")
        
        // Add health context if available
        var fullContext = contextString
        if !currentContext.healthContext.isEmpty {
            let healthSummary = currentContext.healthContext.map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
            fullContext += "\n\nHealth Context: \(healthSummary)"
        }
        
        return fullContext
    }
    
    /// Update health context with latest data
    public func updateHealthContext(metric: HealthKitService.MetricKind, value: String) {
        currentContext.healthContext[metric.rawValue] = value
        currentContext.lastHealthUpdate = Date()
        logger.debug("Updated health context: \(metric.rawValue) = \(value)")
    }
    
    /// Get relevant health context for current conversation
    public func getRelevantHealthContext() -> [String: String] {
        // Return health context that's still relevant (within last hour)
        guard let lastUpdate = currentContext.lastHealthUpdate,
              Date().timeIntervalSince(lastUpdate) < maxContextAge else {
            return [:]
        }
        return currentContext.healthContext
    }
    
    /// Clear conversation context
    public func clearContext() {
        currentContext = ConversationContext()
        logger.info("Cleared conversation context")
    }
    
    /// Get conversation summary for persistence
    public func getConversationSummary() -> ConversationSummary {
        ConversationSummary(
            id: currentContext.sessionId,
            startTime: currentContext.startTime,
            lastActivity: currentContext.messages.last?.timestamp ?? Date(),
            messageCount: currentContext.messages.count,
            topics: extractTopics(),
            healthMetricsDiscussed: Array(currentContext.healthContext.keys)
        )
    }
    
    private func cleanupOldMessages() {
        let cutoffTime = Date().addingTimeInterval(-maxContextAge)
        currentContext.messages.removeAll { $0.timestamp < cutoffTime }
        
        // Keep at least the last few messages even if old
        if currentContext.messages.count > maxContextMessages {
            currentContext.messages = Array(currentContext.messages.suffix(maxContextMessages))
        }
    }
    
    private func updateContextMetadata(for message: ContextMessage) {
        currentContext.lastActivity = message.timestamp
        
        // Extract and track topics/entities
        if message.role == .user {
            extractAndUpdateTopics(from: message.content)
        }
    }
    
    private func extractTopics() -> [String] {
        let messages = currentContext.messages.filter { $0.role == .user }
        let content = messages.map { $0.content }.joined(separator: " ").lowercased()
        
        var topics: Set<String> = []
        
        // Health-related topics
        let healthKeywords = [
            "steps": "步数", "heart": "心率", "sleep": "睡眠", "weight": "体重",
            "blood pressure": "血压", "exercise": "运动", "calories": "卡路里"
        ]
        
        for (english, chinese) in healthKeywords {
            if content.contains(english) || content.contains(chinese) {
                topics.insert(english)
            }
        }
        
        return Array(topics)
    }
    
    private func extractAndUpdateTopics(from content: String) {
        // Simple topic extraction - can be enhanced with NLP later
        let topics = extractTopics()
        currentContext.discussedTopics = Set(topics)
    }
}

/// Represents the current conversation context
public struct ConversationContext {
    public let sessionId: UUID
    public let startTime: Date
    public var lastActivity: Date
    public var messages: [ContextMessage]
    public var healthContext: [String: String] // metric -> latest value
    public var lastHealthUpdate: Date?
    public var discussedTopics: Set<String>
    
    public init() {
        self.sessionId = UUID()
        self.startTime = Date()
        self.lastActivity = Date()
        self.messages = []
        self.healthContext = [:]
        self.lastHealthUpdate = nil
        self.discussedTopics = []
    }
}

/// A message with context information
public struct ContextMessage: Identifiable, Codable {
    public let id: UUID
    public let role: MessageRole
    public let content: String
    public let timestamp: Date
    public let metadata: MessageMetadata?
    
    public init(role: MessageRole, content: String, metadata: MessageMetadata? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.metadata = metadata
    }
}

/// Message roles for context tracking
public enum MessageRole: String, Codable, CaseIterable {
    case user = "user"
    case assistant = "assistant"
    case system = "system"
}

/// Additional metadata for messages
public struct MessageMetadata: Codable {
    public let intent: String?
    public let healthMetrics: [String]?
    public let confidence: Double?
    
    public init(intent: String? = nil, healthMetrics: [String]? = nil, confidence: Double? = nil) {
        self.intent = intent
        self.healthMetrics = healthMetrics
        self.confidence = confidence
    }
}

/// Summary of a conversation for history
public struct ConversationSummary: Identifiable, Codable {
    public let id: UUID
    public let startTime: Date
    public let lastActivity: Date
    public let messageCount: Int
    public let topics: [String]
    public let healthMetricsDiscussed: [String]
    
    public var title: String {
        if !topics.isEmpty {
            return topics.prefix(2).joined(separator: ", ").capitalized
        } else if !healthMetricsDiscussed.isEmpty {
            return "Health: \(healthMetricsDiscussed.prefix(2).joined(separator: ", "))"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return "Chat \(formatter.string(from: startTime))"
        }
    }
    
    public var duration: TimeInterval {
        lastActivity.timeIntervalSince(startTime)
    }
}