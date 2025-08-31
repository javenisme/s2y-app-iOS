//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT

import Foundation
import OSLog

/// Main controller that orchestrates all enhanced chat features
@MainActor
public final class EnhancedHealthChatController: ObservableObject {
    public static let shared = EnhancedHealthChatController()
    
    private let logger = Logger(subsystem: "com.s2y.app", category: "EnhancedChat")
    
    // Core components
    private let contextManager = ConversationContextManager.shared
    private let llmProvider = EnhancedLLMProvider.shared
    private let clarificationEngine = ConversationClarificationEngine.shared
    private let healthIntelligence = HealthIntelligenceEngine.shared
    private let historyManager = ChatHistoryManager.shared
    
    @Published public private(set) var isProcessing = false
    @Published public private(set) var needsClarification = false
    @Published public private(set) var clarificationQuestion: ClarificationQuestion?
    @Published public private(set) var lastResponse: EnhancedChatResponse?
    @Published public private(set) var currentError: LLMError?
    
    private init() {}
    
    /// Process user message with full enhanced capabilities
    public func processMessage(_ message: String) async -> EnhancedChatResponse {
        logger.info("Processing enhanced chat message")
        isProcessing = true
        needsClarification = false
        clarificationQuestion = nil
        currentError = nil
        
        defer {
            isProcessing = false
        }
        
        do {
            // Step 1: Check if clarification is needed
            let clarificationResult = clarificationEngine.analyzeMessage(message)
            
            switch clarificationResult {
            case .needsClarification(let ambiguityType):
                return handleClarificationNeeded(ambiguityType, originalMessage: message)
                
            case .canProceed:
                // Step 2: Generate intelligent health response
                let healthResponse = await healthIntelligence.generateHealthResponse(for: message)
                
                // Step 3: Enhance with LLM if available
                let enhancedResponse = try await enhanceWithLLM(healthResponse)
                
                // Step 4: Save to history
                await saveCurrentConversation()
                
                return enhancedResponse
            }
        } catch let error as LLMError {
            currentError = error
            logger.error("Enhanced chat processing failed: \(error.localizedDescription)")
            
            // Return fallback response
            return createFallbackResponse(for: message, error: error)
        } catch {
            let llmError = LLMError.unknown(error)
            currentError = llmError
            return createFallbackResponse(for: message, error: llmError)
        }
    }
    
    /// Handle clarification response from user
    public func processClarificationResponse(_ response: String, originalMessage: String) async -> EnhancedChatResponse {
        logger.info("Processing clarification response")
        
        // Construct enhanced message with clarification context
        let enhancedMessage = "\(originalMessage) (clarification: \(response))"
        
        // Process with clarification context
        return await processMessage(enhancedMessage)
    }
    
    /// Start new conversation
    public func startNewConversation() {
        logger.info("Starting new conversation")
        
        // Save current conversation if it has content
        if !contextManager.currentContext.messages.isEmpty {
            Task {
                await saveCurrentConversation()
            }
        }
        
        // Clear context for new conversation
        contextManager.clearContext()
        
        // Reset state
        needsClarification = false
        clarificationQuestion = nil
        lastResponse = nil
        currentError = nil
    }
    
    /// Get conversation suggestions based on context
    public func getConversationSuggestions() -> [ChatSuggestion] {
        let context = contextManager.currentContext
        var suggestions: [ChatSuggestion] = []
        
        // Base suggestions
        suggestions.append(contentsOf: [
            ChatSuggestion(
                text: "How are my health trends looking?",
                textCN: "我的健康趋势如何？",
                icon: "chart.line.uptrend.xyaxis"
            ),
            ChatSuggestion(
                text: "Give me health recommendations",
                textCN: "给我一些健康建议",
                icon: "lightbulb"
            ),
            ChatSuggestion(
                text: "Compare my recent activity",
                textCN: "比较我最近的活动",
                icon: "arrow.left.arrow.right"
            )
        ])
        
        // Context-based suggestions
        if !context.healthContext.isEmpty {
            let metrics = Array(context.healthContext.keys).prefix(2).joined(separator: " and ")
            suggestions.append(ChatSuggestion(
                text: "Analyze my \(metrics) patterns",
                textCN: "分析我的\(metrics)模式",
                icon: "magnifyingglass.circle"
            ))
        }
        
        // Follow-up suggestions from last response
        if let lastResponse = lastResponse,
           let followUps = lastResponse.structuredData?.followUpQuestions {
            for followUp in followUps.prefix(2) {
                suggestions.append(ChatSuggestion(
                    text: followUp,
                    textCN: followUp, // Could be enhanced with translation
                    icon: "questionmark.circle"
                ))
            }
        }
        
        return suggestions
    }
    
    private func handleClarificationNeeded(_ ambiguityType: AmbiguityType, originalMessage: String) -> EnhancedChatResponse {
        let question = clarificationEngine.generateClarificationQuestion(for: ambiguityType)
        
        needsClarification = true
        clarificationQuestion = question
        
        return EnhancedChatResponse(
            content: question.text,
            contentCN: question.textCN,
            source: .clarification,
            confidence: 1.0,
            structuredData: EnhancedStructuredData(
                clarificationOptions: question.options,
                clarificationType: question.type
            ),
            processingMetadata: ProcessingMetadata(
                needsClarification: true,
                clarificationReason: ambiguityType.description
            )
        )
    }
    
    private func enhanceWithLLM(_ healthResponse: HealthIntelligentResponse) async throws -> EnhancedChatResponse {
        // Prepare enhanced prompt with health intelligence
        let enhancedPrompt = createEnhancedPrompt(from: healthResponse)
        
        // Get LLM response with fallback handling
        let llmResponse = try await llmProvider.sendMessage(enhancedPrompt, includeContext: true)
        
        // Combine LLM response with health intelligence
        return EnhancedChatResponse(
            content: llmResponse.content,
            contentCN: translateToSimplifiedChinese(llmResponse.content),
            source: .enhanced,
            confidence: llmResponse.confidence,
            structuredData: EnhancedStructuredData(
                healthSummary: healthResponse.structuredData.summary,
                insights: healthResponse.structuredData.insights,
                recommendations: healthResponse.structuredData.recommendations,
                followUpQuestions: healthResponse.structuredData.followUpQuestions
            ),
            processingMetadata: ProcessingMetadata(
                healthAnalysisUsed: true,
                llmSource: llmResponse.source,
                contextUsed: llmResponse.contextUsed
            )
        )
    }
    
    private func createEnhancedPrompt(from healthResponse: HealthIntelligentResponse) -> String {
        var prompt = """
        User Query: \(healthResponse.query)
        
        Health Data Analysis:
        \(healthResponse.responseText)
        
        Key Insights:
        """
        
        for insight in healthResponse.structuredData.insights.prefix(3) {
            prompt += "\n- \(insight.description)"
        }
        
        if !healthResponse.structuredData.recommendations.isEmpty {
            prompt += "\n\nRecommendations:"
            for rec in healthResponse.structuredData.recommendations {
                prompt += "\n- \(rec)"
            }
        }
        
        prompt += """
        
        Please provide a conversational, empathetic response that:
        1. Acknowledges the user's health data and trends
        2. Explains insights in simple, encouraging language
        3. Provides actionable, personalized advice
        4. Maintains a supportive, professional tone
        
        Keep the response concise but comprehensive, focusing on what matters most to the user.
        """
        
        return prompt
    }
    
    private func createFallbackResponse(for message: String, error: LLMError) -> EnhancedChatResponse {
        // Use health intelligence for local fallback
        let fallbackContent: String
        let structuredData: EnhancedStructuredData?
        
        if let lastAnalysis = healthIntelligence.lastAnalysis {
            fallbackContent = """
            I'm having trouble connecting to my AI service, but I can still help with your health data locally.
            
            Based on my analysis of your recent health metrics, I can see some patterns worth discussing.
            What specific aspect of your health would you like to focus on?
            """
            
            structuredData = EnhancedStructuredData(
                insights: healthIntelligence.currentInsights
            )
        } else {
            fallbackContent = """
            I'm currently experiencing technical difficulties, but I'm still here to help!
            
            I can assist with:
            • Analyzing your health data trends
            • Providing general health guidance
            • Setting health goals
            
            What would you like to explore?
            """
            
            structuredData = nil
        }
        
        return EnhancedChatResponse(
            content: fallbackContent,
            contentCN: "我目前遇到技术问题，但仍然可以帮助您！",
            source: .fallback,
            confidence: 0.6,
            structuredData: structuredData,
            processingMetadata: ProcessingMetadata(
                error: error,
                fallbackUsed: true
            )
        )
    }
    
    private func translateToSimplifiedChinese(_ text: String) -> String {
        // Basic translation placeholder - could be enhanced with translation service
        // For now, return simplified version or key phrases in Chinese
        if text.contains("trend") {
            return text.replacingOccurrences(of: "trend", with: "趋势")
        }
        if text.contains("health") {
            return text.replacingOccurrences(of: "health", with: "健康")
        }
        return text // Return original if no translation available
    }
    
    private func saveCurrentConversation() async {
        let context = contextManager.currentContext
        if !context.messages.isEmpty {
            await historyManager.saveConversation(context)
            logger.debug("Saved conversation with \(context.messages.count) messages")
        }
    }
}

// MARK: - Enhanced Response Types

public struct EnhancedChatResponse {
    public let content: String
    public let contentCN: String
    public let source: ResponseSource
    public let confidence: Double
    public let structuredData: EnhancedStructuredData?
    public let processingMetadata: ProcessingMetadata
    
    public enum ResponseSource {
        case enhanced    // Full LLM + Health Intelligence
        case healthOnly  // Health Intelligence only
        case clarification // Needs user clarification
        case fallback    // Error fallback
    }
}

public struct EnhancedStructuredData {
    public let healthSummary: [HealthKitService.MetricKind: HealthDataSummary]?
    public let insights: [HealthInsight]?
    public let recommendations: [String]?
    public let followUpQuestions: [String]?
    public let clarificationOptions: [ClarificationOption]?
    public let clarificationType: ClarificationQuestion.ClarificationType?
    
    public init(
        healthSummary: [HealthKitService.MetricKind: HealthDataSummary]? = nil,
        insights: [HealthInsight]? = nil,
        recommendations: [String]? = nil,
        followUpQuestions: [String]? = nil,
        clarificationOptions: [ClarificationOption]? = nil,
        clarificationType: ClarificationQuestion.ClarificationType? = nil
    ) {
        self.healthSummary = healthSummary
        self.insights = insights
        self.recommendations = recommendations
        self.followUpQuestions = followUpQuestions
        self.clarificationOptions = clarificationOptions
        self.clarificationType = clarificationType
    }
}

public struct ProcessingMetadata {
    public let needsClarification: Bool
    public let clarificationReason: String?
    public let healthAnalysisUsed: Bool
    public let llmSource: LLMResponse.ResponseSource?
    public let contextUsed: Bool
    public let error: LLMError?
    public let fallbackUsed: Bool
    
    public init(
        needsClarification: Bool = false,
        clarificationReason: String? = nil,
        healthAnalysisUsed: Bool = false,
        llmSource: LLMResponse.ResponseSource? = nil,
        contextUsed: Bool = false,
        error: LLMError? = nil,
        fallbackUsed: Bool = false
    ) {
        self.needsClarification = needsClarification
        self.clarificationReason = clarificationReason
        self.healthAnalysisUsed = healthAnalysisUsed
        self.llmSource = llmSource
        self.contextUsed = contextUsed
        self.error = error
        self.fallbackUsed = fallbackUsed
    }
}

public struct ChatSuggestion: Identifiable {
    public let id = UUID()
    public let text: String
    public let textCN: String
    public let icon: String
}

// MARK: - Extensions

extension AmbiguityType {
    var description: String {
        switch self {
        case .ambiguousHealthMetric:
            return "Multiple health metrics could match your query"
        case .ambiguousTimeframe:
            return "Time period needs clarification"
        case .vagueQuestion:
            return "Question needs more specificity"
        case .missingContext:
            return "Missing context from previous conversation"
        case .multipleIntents:
            return "Multiple possible intentions detected"
        }
    }
}