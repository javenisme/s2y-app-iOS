//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT

import Foundation
import OSLog

/// Engine for handling conversation clarifications and ambiguous user queries
@MainActor
public final class ConversationClarificationEngine {
    public static let shared = ConversationClarificationEngine()
    
    private let logger = Logger(subsystem: "com.s2y.app", category: "Clarification")
    private let contextManager = ConversationContextManager.shared
    
    private init() {}
    
    /// Analyze user message for ambiguity and generate clarification if needed
    public func analyzeMessage(_ message: String) -> ClarificationResult {
        logger.debug("Analyzing message for clarification needs: \(message.prefix(50))...")
        
        let analysis = MessageAnalysis(message: message)
        
        // Check for various types of ambiguity
        if let clarification = checkForAmbiguousHealthMetric(analysis) {
            return .needsClarification(clarification)
        }
        
        if let clarification = checkForAmbiguousTimeframe(analysis) {
            return .needsClarification(clarification)
        }
        
        if let clarification = checkForVagueQuestion(analysis) {
            return .needsClarification(clarification)
        }
        
        if let clarification = checkForMissingContext(analysis) {
            return .needsClarification(clarification)
        }
        
        // Message is clear enough to process
        return .canProceed
    }
    
    /// Generate contextual clarification questions
    public func generateClarificationQuestion(for ambiguity: AmbiguityType) -> ClarificationQuestion {
        switch ambiguity {
        case .ambiguousHealthMetric(let candidates):
            return ClarificationQuestion(
                text: "I can help you with several health metrics. Which one are you interested in?",
                textCN: "我可以帮您查看多个健康指标。您想了解哪一个？",
                options: candidates.map { metric in
                    ClarificationOption(
                        text: HealthMetricsDictionary.displayName(for: metric),
                        value: metric.rawValue,
                        icon: getIconForMetric(metric)
                    )
                },
                type: .multipleChoice
            )
            
        case .ambiguousTimeframe(let message):
            let options = generateTimeframeOptions(for: message)
            return ClarificationQuestion(
                text: "What time period would you like me to analyze?",
                textCN: "您想分析哪个时间段的数据？",
                options: options,
                type: .multipleChoice
            )
            
        case .vagueQuestion(let intent):
            return generateVagueQuestionClarification(for: intent)
            
        case .missingContext(let contextType):
            return generateMissingContextClarification(for: contextType)
            
        case .multipleIntents(let intents):
            return ClarificationQuestion(
                text: "I can help with several things. What would you like to focus on first?",
                textCN: "我可以帮您处理几个方面。您想先关注哪个？",
                options: intents.map { intent in
                    ClarificationOption(
                        text: intent.description,
                        value: intent.rawValue,
                        icon: intent.icon
                    )
                },
                type: .multipleChoice
            )
        }
    }
    
    private func checkForAmbiguousHealthMetric(_ analysis: MessageAnalysis) -> AmbiguityType? {
        let message = analysis.message.lowercased()
        
        // Check for generic health terms that could match multiple metrics
        var potentialMetrics: [HealthKitService.MetricKind] = []
        
        if message.contains("health") || message.contains("健康") {
            potentialMetrics = HealthKitService.MetricKind.allCases
        } else if message.contains("activity") || message.contains("运动") || message.contains("活动") {
            potentialMetrics = [.steps, .activeEnergy]
        } else if message.contains("heart") || message.contains("心") {
            potentialMetrics = [.heartRateAverage, .restingHeartRate]
        }
        
        // If multiple metrics could match, ask for clarification
        if potentialMetrics.count > 1 {
            return .ambiguousHealthMetric(potentialMetrics)
        }
        
        return nil
    }
    
    private func checkForAmbiguousTimeframe(_ analysis: MessageAnalysis) -> AmbiguityType? {
        let message = analysis.message.lowercased()
        
        // Check for vague time references
        let vagueTimeIndicators = [
            "recently", "lately", "past", "recent", "这段时间", "最近", "前段时间"
        ]
        
        let hasVagueTime = vagueTimeIndicators.contains { message.contains($0) }
        let hasSpecificTime = message.contains(where: { "0123456789".contains($0) }) ||
                             ["today", "yesterday", "week", "month", "今天", "昨天", "周", "月"].contains { message.contains($0) }
        
        if hasVagueTime && !hasSpecificTime {
            return .ambiguousTimeframe(analysis.message)
        }
        
        return nil
    }
    
    private func checkForVagueQuestion(_ analysis: MessageAnalysis) -> AmbiguityType? {
        let message = analysis.message.lowercased()
        
        // Very short or vague questions
        if message.count < 10 {
            let vaguePatterns = ["how", "what", "tell me", "show me", "怎么", "什么", "告诉我", "显示"]
            if vaguePatterns.contains(where: { message.contains($0) }) {
                return .vagueQuestion(.general)
            }
        }
        
        return nil
    }
    
    private func checkForMissingContext(_ analysis: MessageAnalysis) -> AmbiguityType? {
        let context = contextManager.currentContext
        
        // Check if user is referring to "it", "that", "this" without clear antecedent
        let message = analysis.message.lowercased()
        let pronouns = ["it", "that", "this", "them", "它", "这个", "那个"]
        
        if pronouns.contains(where: { message.contains($0) }) && context.messages.count < 2 {
            return .missingContext(.previousReference)
        }
        
        return nil
    }
    
    private func generateTimeframeOptions(for message: String) -> [ClarificationOption] {
        [
            ClarificationOption(text: "Today", value: "today", icon: "calendar.badge.clock"),
            ClarificationOption(text: "Past 3 days", value: "3days", icon: "calendar.badge.minus"),
            ClarificationOption(text: "Past week", value: "7days", icon: "calendar"),
            ClarificationOption(text: "Past month", value: "30days", icon: "calendar.badge.plus")
        ]
    }
    
    private func generateVagueQuestionClarification(for intent: VagueIntent) -> ClarificationQuestion {
        let options = [
            ClarificationOption(text: "Check my recent health data", value: "recent_data", icon: "heart.text.square"),
            ClarificationOption(text: "Get health recommendations", value: "recommendations", icon: "lightbulb"),
            ClarificationOption(text: "Compare my progress", value: "compare", icon: "chart.line.uptrend.xyaxis"),
            ClarificationOption(text: "Set health goals", value: "goals", icon: "target")
        ]
        
        return ClarificationQuestion(
            text: "I'd be happy to help! What would you like to know about your health?",
            textCN: "我很乐意帮助您！您想了解健康方面的什么信息？",
            options: options,
            type: .multipleChoice
        )
    }
    
    private func generateMissingContextClarification(for contextType: MissingContextType) -> ClarificationQuestion {
        switch contextType {
        case .previousReference:
            return ClarificationQuestion(
                text: "Could you be more specific about what you're referring to?",
                textCN: "您能更具体地说明您指的是什么吗？",
                options: [],
                type: .freeText
            )
        case .missingMetric:
            let options = HealthKitService.MetricKind.allCases.map { metric in
                ClarificationOption(
                    text: HealthMetricsDictionary.displayName(for: metric),
                    value: metric.rawValue,
                    icon: getIconForMetric(metric)
                )
            }
            return ClarificationQuestion(
                text: "Which health metric would you like to discuss?",
                textCN: "您想讨论哪个健康指标？",
                options: options,
                type: .multipleChoice
            )
        }
    }
    
    private func getIconForMetric(_ metric: HealthKitService.MetricKind) -> String {
        switch metric {
        case .steps: return "figure.walk"
        case .heartRateAverage, .restingHeartRate: return "heart.fill"
        case .activeEnergy: return "flame.fill"
        case .bodyMass: return "scalemass.fill"
        case .sleepDurationHours: return "bed.double.fill"
        }
    }
}

/// Result of message analysis for clarification needs
public enum ClarificationResult {
    case canProceed
    case needsClarification(AmbiguityType)
}

/// Types of ambiguity that require clarification
public enum AmbiguityType {
    case ambiguousHealthMetric([HealthKitService.MetricKind])
    case ambiguousTimeframe(String)
    case vagueQuestion(VagueIntent)
    case missingContext(MissingContextType)
    case multipleIntents([ConversationIntent])
}

/// Intent classifications for vague questions
public enum VagueIntent {
    case general
    case health
    case comparison
    case recommendation
}

/// Types of missing context
public enum MissingContextType {
    case previousReference
    case missingMetric
}

/// Conversation intent classification
public enum ConversationIntent: String {
    case dataQuery = "data_query"
    case recommendation = "recommendation" 
    case comparison = "comparison"
    case goalSetting = "goal_setting"
    case general = "general"
    
    var description: String {
        switch self {
        case .dataQuery: return "Check my health data"
        case .recommendation: return "Get health recommendations"
        case .comparison: return "Compare my progress"
        case .goalSetting: return "Set health goals"
        case .general: return "General health questions"
        }
    }
    
    var icon: String {
        switch self {
        case .dataQuery: return "chart.bar"
        case .recommendation: return "lightbulb"
        case .comparison: return "arrow.left.arrow.right"
        case .goalSetting: return "target"
        case .general: return "questionmark.circle"
        }
    }
}

/// Structured clarification question
public struct ClarificationQuestion {
    public let text: String
    public let textCN: String
    public let options: [ClarificationOption]
    public let type: ClarificationType
    
    public enum ClarificationType {
        case multipleChoice
        case freeText
        case yesNo
    }
}

/// Option for clarification questions
public struct ClarificationOption: Identifiable {
    public let id = UUID()
    public let text: String
    public let value: String
    public let icon: String
}

/// Internal message analysis structure
private struct MessageAnalysis {
    let message: String
    let tokens: [String]
    let length: Int
    
    init(message: String) {
        self.message = message
        self.tokens = message.lowercased().components(separatedBy: .whitespacesAndNewlines)
        self.length = message.count
    }
}