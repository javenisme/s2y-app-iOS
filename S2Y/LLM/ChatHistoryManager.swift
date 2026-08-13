//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT

import CryptoKit
import Foundation
import OSLog

/// Manages chat history persistence and retrieval
@MainActor
public final class ChatHistoryManager: ObservableObject {
    public static let shared = ChatHistoryManager()
    
    private let logger = Logger(subsystem: "com.s2y.app", category: "ChatHistory")
    private let maxStoredConversations = 100
    private let maxConversationAge: TimeInterval = 30 * 24 * 3600 // 30 days
    
    @Published public private(set) var conversations: [StoredConversation] = []
    @Published public private(set) var favoriteInsights: [FavoriteInsight] = []
    
    private let storageURL: URL
    private let favoritesURL: URL
    
    private init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.storageURL = documentsPath.appendingPathComponent("chat_history.json")
        self.favoritesURL = documentsPath.appendingPathComponent("favorite_insights.json")
        
        loadStoredData()
    }
    
    /// Save current conversation to history
    public func saveConversation(_ context: ConversationContext) async {
        logger.info("Saving conversation to history")
        
        let summary = ConversationContextManager.shared.getConversationSummary()
        let messages = context.messages.map { message in
            StoredMessage(
                role: message.role,
                content: message.content,
                timestamp: message.timestamp,
                metadata: message.metadata
            )
        }
        
        let storedConversation = StoredConversation(
            id: summary.id,
            title: summary.title,
            startTime: summary.startTime,
            lastActivity: summary.lastActivity,
            messageCount: summary.messageCount,
            messages: messages,
            topics: summary.topics,
            healthMetricsDiscussed: summary.healthMetricsDiscussed,
            insights: extractImportantInsights(from: messages)
        )
        
        // Add to conversations list
        if let existingIndex = conversations.firstIndex(where: { $0.id == storedConversation.id }) {
            conversations[existingIndex] = storedConversation
        } else {
            conversations.insert(storedConversation, at: 0)
        }
        
        // Maintain storage limits
        cleanupOldConversations()
        
        // Persist to disk
        await saveToFile()
    }
    
    /// Load conversation history
    public func loadConversation(_ conversationId: UUID) -> StoredConversation? {
        return conversations.first { $0.id == conversationId }
    }
    
    /// Search conversations by query
    public func searchConversations(_ query: String) -> [StoredConversation] {
        let lowercaseQuery = query.lowercased()
        
        return conversations.filter { conversation in
            conversation.title.lowercased().contains(lowercaseQuery) ||
            conversation.topics.contains { $0.lowercased().contains(lowercaseQuery) } ||
            conversation.healthMetricsDiscussed.contains { $0.lowercased().contains(lowercaseQuery) } ||
            conversation.messages.contains { $0.content.lowercased().contains(lowercaseQuery) }
        }
    }
    
    /// Get conversations by health metric
    public func getConversationsByMetric(_ metric: HealthKitService.MetricKind) -> [StoredConversation] {
        return conversations.filter { conversation in
            conversation.healthMetricsDiscussed.contains(metric.rawValue)
        }
    }
    
    /// Get conversations by date range
    public func getConversationsByDateRange(from startDate: Date, to endDate: Date) -> [StoredConversation] {
        return conversations.filter { conversation in
            conversation.startTime >= startDate && conversation.startTime <= endDate
        }
    }
    
    /// Add insight to favorites
    public func addToFavorites(_ insight: HealthInsight, from conversationId: UUID) {
        let favorite = FavoriteInsight(
            insight: insight,
            conversationId: conversationId,
            savedAt: Date()
        )
        
        favoriteInsights.insert(favorite, at: 0)
        
        // Limit favorites
        if favoriteInsights.count > 50 {
            favoriteInsights = Array(favoriteInsights.prefix(50))
        }
        
        Task {
            await saveFavoritesToFile()
        }
        
        logger.info("Added insight to favorites: \(insight.title)")
    }
    
    /// Remove insight from favorites
    public func removeFromFavorites(_ favoriteId: UUID) {
        favoriteInsights.removeAll { $0.id == favoriteId }
        
        Task {
            await saveFavoritesToFile()
        }
        
        logger.info("Removed insight from favorites")
    }
    
    /// Delete conversation
    public func deleteConversation(_ conversationId: UUID) {
        conversations.removeAll { $0.id == conversationId }
        
        // Also remove related favorites
        favoriteInsights.removeAll { $0.conversationId == conversationId }
        
        Task {
            await saveToFile()
            await saveFavoritesToFile()
        }
        
        logger.info("Deleted conversation and related favorites")
    }
    
    /// Get conversation statistics
    public func getStatistics() -> ChatStatistics {
        let totalMessages = conversations.reduce(0) { $0 + $1.messageCount }
        let totalInsights = conversations.reduce(0) { $0 + $1.insights.count }
        
        let metricsDiscussed = Set(conversations.flatMap { $0.healthMetricsDiscussed })
        let topicsDiscussed = Set(conversations.flatMap { $0.topics })
        
        let averageConversationLength = conversations.isEmpty ? 0 : 
            conversations.map { $0.duration }.reduce(0, +) / Double(conversations.count)
        
        return ChatStatistics(
            totalConversations: conversations.count,
            totalMessages: totalMessages,
            totalInsights: totalInsights,
            favoriteInsights: favoriteInsights.count,
            uniqueMetricsDiscussed: metricsDiscussed.count,
            uniqueTopicsDiscussed: topicsDiscussed.count,
            averageConversationDuration: averageConversationLength,
            oldestConversation: conversations.last?.startTime,
            mostRecentConversation: conversations.first?.startTime
        )
    }
    
    /// Export conversation data
    public func exportConversationData() -> Data? {
        let exportData = ChatExportData(
            conversations: conversations,
            favoriteInsights: favoriteInsights,
            exportDate: Date(),
            version: "1.0"
        )
        
        do {
            return try JSONEncoder().encode(exportData)
        } catch {
            logger.error("Failed to export chat data: \(error)")
            return nil
        }
    }
    
    /// Import conversation data
    public func importConversationData(_ data: Data) async throws {
        let importData = try JSONDecoder().decode(ChatExportData.self, from: data)
        
        // Merge imported conversations (avoid duplicates)
        for importedConv in importData.conversations {
            if !conversations.contains(where: { $0.id == importedConv.id }) {
                conversations.append(importedConv)
            }
        }
        
        // Merge imported favorites
        for importedFav in importData.favoriteInsights {
            if !favoriteInsights.contains(where: { $0.id == importedFav.id }) {
                favoriteInsights.append(importedFav)
            }
        }
        
        // Sort by date
        conversations.sort { $0.lastActivity > $1.lastActivity }
        favoriteInsights.sort { $0.savedAt > $1.savedAt }
        
        // Apply limits
        cleanupOldConversations()
        
        await saveToFile()
        await saveFavoritesToFile()
        
        logger.info("Successfully imported chat data: \(importData.conversations.count) conversations, \(importData.favoriteInsights.count) favorites")
    }
    
    private func extractImportantInsights(from messages: [StoredMessage]) -> [StoredInsight] {
        // Extract insights from assistant messages that contain recommendations or important information
        return messages.compactMap { message in
            guard message.role == .assistant,
                  let metadata = message.metadata,
                  let intent = metadata.intent,
                  ["recommendation", "insight", "alert"].contains(intent) else {
                return nil
            }
            
            return StoredInsight(
                content: message.content,
                type: intent,
                timestamp: message.timestamp,
                confidence: metadata.confidence ?? 0.7
            )
        }
    }
    
    private func cleanupOldConversations() {
        let cutoffDate = Date().addingTimeInterval(-maxConversationAge)
        
        // Remove old conversations
        conversations.removeAll { $0.lastActivity < cutoffDate }
        
        // Limit number of conversations
        if conversations.count > maxStoredConversations {
            conversations = Array(conversations.prefix(maxStoredConversations))
        }
        
        logger.debug("Cleaned up old conversations. Current count: \(self.conversations.count)")
    }
    
    private func loadStoredData() {
        Task {
            await loadConversationsFromFile()
            await loadFavoritesFromFile()
        }
    }
    
    private func loadConversationsFromFile() async {
        do {
            if FileManager.default.fileExists(atPath: storageURL.path) {
                let data = try Data(contentsOf: storageURL)
                let loadedConversations = try JSONDecoder().decode([StoredConversation].self, from: data)
                
                await MainActor.run {
                    self.conversations = loadedConversations
                    self.cleanupOldConversations()
                }
                
                logger.info("Loaded \(loadedConversations.count) conversations from storage")
            }
        } catch {
            logger.error("Failed to load conversations: \(error)")
        }
    }
    
    private func loadFavoritesFromFile() async {
        do {
            if FileManager.default.fileExists(atPath: favoritesURL.path) {
                let data = try Data(contentsOf: favoritesURL)
                let loadedFavorites = try JSONDecoder().decode([FavoriteInsight].self, from: data)
                
                await MainActor.run {
                    self.favoriteInsights = loadedFavorites
                }
                
                logger.info("Loaded \(loadedFavorites.count) favorite insights from storage")
            }
        } catch {
            logger.error("Failed to load favorite insights: \(error)")
        }
    }
    
    private func saveToFile() async {
        do {
            let data = try JSONEncoder().encode(conversations)
            try data.write(to: storageURL)
            logger.debug("Saved \(self.conversations.count) conversations to file")
        } catch {
            logger.error("Failed to save conversations: \(error)")
        }
    }
    
    private func saveFavoritesToFile() async {
        do {
            let data = try JSONEncoder().encode(favoriteInsights)
            try data.write(to: favoritesURL)
            logger.debug("Saved \(self.favoriteInsights.count) favorite insights to file")
        } catch {
            logger.error("Failed to save favorite insights: \(error)")
        }
    }
}

// MARK: - Data Models

public struct StoredConversation: Identifiable, Codable {
    public let id: UUID
    public let title: String
    public let startTime: Date
    public let lastActivity: Date
    public let messageCount: Int
    public let messages: [StoredMessage]
    public let topics: [String]
    public let healthMetricsDiscussed: [String]
    public let insights: [StoredInsight]
    
    public var duration: TimeInterval {
        lastActivity.timeIntervalSince(startTime)
    }
    
    public var preview: String {
        // Return first user message as preview
        return messages.first(where: { $0.role == .user })?.content.prefix(100).description ?? "Health conversation"
    }
}

public struct StoredMessage: Identifiable, Codable {
    public let id: UUID
    public let role: MessageRole
    public let content: String
    public let timestamp: Date
    public let metadata: MessageMetadata?

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date,
        metadata: MessageMetadata?
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, metadata
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(MessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        metadata = try container.decodeIfPresent(MessageMetadata.self, forKey: .metadata)
        id = try container.decodeIfPresent(UUID.self, forKey: .id)
            ?? LegacyChatHistoryIdentifier.make(
                namespace: "message",
                components: [role.rawValue, content, timestamp.timeIntervalSince1970.description]
            )
    }
}

public struct StoredInsight: Identifiable, Codable {
    public let id: UUID
    public let content: String
    public let type: String
    public let timestamp: Date
    public let confidence: Double

    public init(
        id: UUID = UUID(),
        content: String,
        type: String,
        timestamp: Date,
        confidence: Double
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.timestamp = timestamp
        self.confidence = confidence
    }

    private enum CodingKeys: String, CodingKey {
        case id, content, type, timestamp, confidence
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decode(String.self, forKey: .content)
        type = try container.decode(String.self, forKey: .type)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        confidence = try container.decode(Double.self, forKey: .confidence)
        id = try container.decodeIfPresent(UUID.self, forKey: .id)
            ?? LegacyChatHistoryIdentifier.make(
                namespace: "insight",
                components: [content, type, timestamp.timeIntervalSince1970.description]
            )
    }
}

public struct FavoriteInsight: Identifiable, Codable {
    public let id: UUID
    public let insight: HealthInsight
    public let conversationId: UUID
    public let savedAt: Date

    public init(
        id: UUID = UUID(),
        insight: HealthInsight,
        conversationId: UUID,
        savedAt: Date
    ) {
        self.id = id
        self.insight = insight
        self.conversationId = conversationId
        self.savedAt = savedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, insight, conversationId, savedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        insight = try container.decode(HealthInsight.self, forKey: .insight)
        conversationId = try container.decode(UUID.self, forKey: .conversationId)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        id = try container.decodeIfPresent(UUID.self, forKey: .id)
            ?? LegacyChatHistoryIdentifier.make(
                namespace: "favorite",
                components: [conversationId.uuidString, insight.title, savedAt.timeIntervalSince1970.description]
            )
    }
}

private enum LegacyChatHistoryIdentifier {
    static func make(namespace: String, components: [String]) -> UUID {
        let digest = SHA256.hash(data: Data(([namespace] + components).joined(separator: "\u{1F}").utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

public struct ChatStatistics {
    public let totalConversations: Int
    public let totalMessages: Int
    public let totalInsights: Int
    public let favoriteInsights: Int
    public let uniqueMetricsDiscussed: Int
    public let uniqueTopicsDiscussed: Int
    public let averageConversationDuration: TimeInterval
    public let oldestConversation: Date?
    public let mostRecentConversation: Date?
}

public struct ChatExportData: Codable {
    public let conversations: [StoredConversation]
    public let favoriteInsights: [FavoriteInsight]
    public let exportDate: Date
    public let version: String
}

// MARK: - Extensions for Codable Support

extension HealthInsight: Codable {
    enum CodingKeys: String, CodingKey {
        case title, titleCN, description, descriptionCN, type, importance, metric
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        titleCN = try container.decode(String.self, forKey: .titleCN)
        description = try container.decode(String.self, forKey: .description)
        descriptionCN = try container.decode(String.self, forKey: .descriptionCN)
        type = try container.decode(InsightType.self, forKey: .type)
        importance = try container.decode(Double.self, forKey: .importance)
        metric = try container.decodeIfPresent(HealthKitService.MetricKind.self, forKey: .metric)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(titleCN, forKey: .titleCN)
        try container.encode(description, forKey: .description)
        try container.encode(descriptionCN, forKey: .descriptionCN)
        try container.encode(type, forKey: .type)
        try container.encode(importance, forKey: .importance)
        try container.encodeIfPresent(metric, forKey: .metric)
    }
}

// Moved Codable conformance to the enum declaration file to avoid cross-file synthesis issues
