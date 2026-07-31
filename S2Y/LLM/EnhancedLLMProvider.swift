//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT

// swiftlint:disable line_length force_cast

import FirebaseAuth
import Foundation
import Network
import OSLog
import Security

/// Enhanced LLM provider with robust error handling and fallback mechanisms
@MainActor
public final class EnhancedLLMProvider: ObservableObject {
    public static let shared = EnhancedLLMProvider()
    
    private let logger = Logger(subsystem: "com.s2y.app", category: "EnhancedLLM")
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    
    @Published public private(set) var isOnline = true
    @Published public private(set) var lastError: LLMError?
    @Published public private(set) var retryCount = 0
    
    private let maxRetries = 2
    private let baseRetryDelay: TimeInterval = 1.0
    private let contextManager = ConversationContextManager.shared
    
    private init() {
        setupNetworkMonitoring()
    }
    
    /// Send message with comprehensive error handling and fallbacks
    public func sendMessage(
        _ message: String,
        includeContext: Bool = true
    ) async throws -> LLMResponse {
        logger.info("Sending message to LLM with enhanced error handling")
        
        // Reset retry count for new requests
        retryCount = 0
        lastError = nil

        if includeContext && UserDefaults.standard.bool(forKey: StorageKeys.shareHealthDataWithOmer) {
            await refreshRelevantHealthContext(for: message)
        }
        
        // Add message to context
        let contextMessage = ContextMessage(role: .user, content: message)
        contextManager.addMessage(contextMessage)
        
        do {
            let response = try await sendMessageWithRetry(message, includeContext: includeContext)
            
            // Add successful response to context
            let responseMessage = ContextMessage(role: .assistant, content: response.content)
            contextManager.addMessage(responseMessage)
            
            return response
        } catch let error as LLMError {
            lastError = error
            logger.error("LLM request failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func sendMessageWithRetry(
        _ message: String,
        includeContext: Bool,
        attempt: Int = 1,
        requestID: UUID = UUID()
    ) async throws -> LLMResponse {
        retryCount = attempt - 1
        
        do {
            // Check network connectivity
            guard isOnline else {
                throw LLMError.networkUnavailable
            }
            
            // Perform real LLM request via provider with retry
            let responseText = try await performLLMRequest(
                message,
                includeContext: includeContext,
                requestID: requestID
            )

            return LLMResponse(
                content: responseText,
                timestamp: Date(),
                source: .llm,
                confidence: 0.9,
                contextUsed: includeContext
            )
            
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            if let urlError = error as? URLError, urlError.code == .cancelled {
                throw CancellationError()
            }
            let mappedError = mapToLLMError(error)
            logger.warning("LLM request attempt \(attempt) failed: \(mappedError.localizedDescription)")
            
            // Determine if we should retry
            if attempt < maxRetries && shouldRetry(error: mappedError) {
                let delay = baseRetryDelay * pow(2.0, Double(attempt - 1)) // Exponential backoff
                logger.info("Retrying LLM request after \(delay) seconds (attempt \(attempt + 1)/\(self.maxRetries))")
                
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await sendMessageWithRetry(
                    message,
                    includeContext: includeContext,
                    attempt: attempt + 1,
                    requestID: requestID
                )
            }
            throw mappedError
        }
    }
    
    // MARK: - Provider integration

    private func refreshRelevantHealthContext(for message: String) async {
        guard let intent = QueryPlanner.parse(message) else { return }
        let metric: HealthKitService.MetricKind
        switch intent {
        case .compare(let kind, _), .trend(let kind, _):
            metric = kind
        }

        do {
            let summary = try await QueryPlanner.run(intent: intent)
            contextManager.updateHealthContext(metric: metric, value: summary)
        } catch {
            logger.info("No shareable HealthKit summary was available for this request")
        }
    }
    
    private func performLLMRequest(_ message: String, includeContext: Bool, requestID: UUID) async throws -> String {
        let (gatewayURL, modelPath, transport) = try loadServiceConfig()
        let token = try await loadAccessToken(for: transport)

        let client = OmerAPIClient(
            configuration: .init(
                gatewayURL: gatewayURL,
                modelPath: modelPath,
                bearerToken: token,
                transport: transport
            )
        )

        let messages = includeContext ? contextManager.currentContext.messages.map { contextMessage in
            LLMMessage(
                role: contextMessage.role == .assistant ? .assistant : .user,
                content: contextMessage.content
            )
        } : [.init(role: .user, content: message)]
        let response = try await client.complete(
            query: message,
            messages: messages,
            healthContext: includeContext && UserDefaults.standard.bool(forKey: StorageKeys.shareHealthDataWithOmer)
                ? contextManager.getRelevantHealthContext()
                : [:],
            conversationID: contextManager.currentContext.sessionId,
            requestID: requestID
        )
        return formatOmerResponse(response)
    }

    private func formatOmerResponse(_ response: OmerAPIClient.Response) -> String {
        var content = response.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = content.lowercased()

        if !lowercased.contains("medical diagnosis")
            && !lowercased.contains("医疗诊断")
            && !lowercased.contains("clinical diagnosis") {
            content += "\n\n基于科学研究的健康建议，不构成医疗诊断。"
        }

        let citations = response.citations.prefix(3)
        if !citations.isEmpty {
            let sourceLines = citations.enumerated().map { index, citation in
                let label = citation.title ?? citation.source ?? "Source \(index + 1)"
                if let url = citation.url {
                    return "\(index + 1). \(label) - \(url)"
                }
                return "\(index + 1). \(label)"
            }
            content += "\n\nSources:\n" + sourceLines.joined(separator: "\n")
        }

        return content
    }
    
    private func loadServiceConfig() throws -> (String, String, OmerTransport) {
        let defaults = UserDefaults.standard
        let bundledTransport = Bundle.main.object(forInfoDictionaryKey: "Omer.Transport") as? String
        let transportValue = defaults.string(forKey: StorageKeys.omerTransport) ?? bundledTransport
        let transport = OmerTransport(rawValue: transportValue ?? "") ?? .legacyAutoRAG
        let keys: (gateway: String, path: String, bundledGateway: String, bundledPath: String) = switch transport {
        case .mobileV1:
            (
                StorageKeys.omerMobileGatewayURL,
                StorageKeys.omerMobileModelPath,
                "Omer.MobileGatewayURL",
                "Omer.MobileModelPath"
            )
        case .legacyAutoRAG:
            (
                StorageKeys.cloudflareGatewayURL,
                StorageKeys.cloudflareModelPath,
                "CFWorkersAI.GatewayURL",
                "CFWorkersAI.ModelPath"
            )
        }
        let bundledGatewayURL = (Bundle.main.object(forInfoDictionaryKey: keys.bundledGateway) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bundledModelPath = (Bundle.main.object(forInfoDictionaryKey: keys.bundledPath) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedGatewayURL = defaults.string(forKey: keys.gateway)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedModelPath = defaults.string(forKey: keys.path)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let gatewayURL = storedGatewayURL.isEmpty ? bundledGatewayURL : storedGatewayURL
        let modelPath = storedModelPath.isEmpty ? bundledModelPath : storedModelPath
        guard !gatewayURL.isEmpty else { throw LLMError.apiKeyMissing }
        return (gatewayURL, modelPath, transport)
    }

    private func loadAccessToken(for transport: OmerTransport) async throws -> String {
        switch transport {
        case .mobileV1:
            guard let user = Auth.auth().currentUser else { throw LLMError.authenticationFailed }
            do {
                return try await user.getIDToken(forcingRefresh: false)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw LLMError.authenticationFailed
            }
        case .legacyAutoRAG:
            return try loadBearerToken()
        }
    }
    
    private func loadBearerToken() throws -> String {
        // Prefer the service-scoped item written by current settings.
        if let token = readKeychain(service: "ai.cloudflare", account: "gateway.token"), !token.isEmpty {
            return token
        }
        // Preserve compatibility with older app builds.
        if let token = readKeychainAccountOnly(account: "gateway.token"), !token.isEmpty {
            return token
        }
        throw LLMError.apiKeyMissing
    }
    
    private func readKeychainAccountOnly(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }
    
    private func readKeychain(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }
    
    private func generateFallbackResponse(for message: String, error: LLMError) -> LLMResponse {
        let fallbackContent: String
        
        switch error {
        case .networkUnavailable:
            fallbackContent = generateOfflineFallback(for: message)
        case .rateLimited:
            fallbackContent = "I'm experiencing high demand right now. Let me try to help based on what I know about your health data."
        case .invalidResponse:
            fallbackContent = generateLocalAnalysisFallback(for: message)
        case .apiKeyMissing, .authenticationFailed:
            fallbackContent = "I'm having trouble connecting to my AI service. Let me provide some basic health guidance."
        case .requestTimeout:
            fallbackContent = "My response is taking longer than expected. Here's what I can tell you based on your local health data."
        case .serverError:
            fallbackContent = "My AI service is temporarily unavailable. I can still help analyze your health data locally."
        case .unknown:
            fallbackContent = generateLocalAnalysisFallback(for: message)
        }
        
        return LLMResponse(
            content: fallbackContent,
            timestamp: Date(),
            source: .fallback,
            confidence: 0.7,
            contextUsed: true
        )
    }
    
    private func generateOfflineFallback(for message: String) -> String {
        // Analyze message for health-related queries offline
        let lowered = message.lowercased()
        
        if lowered.contains("step") || lowered.contains("步数") {
            return "I notice you're asking about steps. While I can't access my AI service right now, I can tell you that the recommended daily step goal is 8,000-10,000 steps. You can check your recent step data in the Health app."
        }
        
        if lowered.contains("heart") || lowered.contains("心率") {
            return "You're asking about heart rate. A normal resting heart rate is typically 60-100 bpm for adults. For exercise, aim for 50-85% of your maximum heart rate (220 minus your age)."
        }
        
        if lowered.contains("sleep") || lowered.contains("睡眠") {
            return "Regarding sleep, most adults need 7-9 hours per night. Good sleep hygiene includes consistent sleep schedules and limiting screens before bedtime."
        }
        
        if lowered.contains("weight") || lowered.contains("体重") {
            return "For weight management, focus on balanced nutrition and regular physical activity. Small, consistent changes often lead to sustainable results."
        }
        
        return "I'm currently offline, but I can still help! Could you check your health data in the app and let me know what specific information you'd like to discuss? I have some general health guidance available."
    }
    
    private func generateLocalAnalysisFallback(for message: String) -> String {
        // Try to provide helpful response using local health context
        let healthContext = contextManager.getRelevantHealthContext()
        
        if !healthContext.isEmpty {
            let metrics = healthContext.keys.joined(separator: ", ")
            return "Based on your recent health data (\(metrics)), I can see you're tracking your wellness actively. While I can't provide my full AI analysis right now, I encourage you to keep monitoring these metrics. What specific aspect would you like to focus on?"
        }
        
        return "I'm having trouble with my AI service, but I'm still here to help! Could you be more specific about what health information you're looking for? I can provide general guidance and help you interpret your health data."
    }
    
    private func shouldRetry(error: any Error) -> Bool {
        // Don't retry certain types of errors
        if let llmError = error as? LLMError {
            switch llmError {
            case .apiKeyMissing, .authenticationFailed, .invalidResponse, .rateLimited:
                return false
            case .networkUnavailable, .requestTimeout, .serverError:
                return true
            case .unknown:
                return false
            }
        }
        
        // For other errors, retry if it might be transient
        return true
    }
    
    private func mapToLLMError(_ error: any Error) -> LLMError {
        if let llmError = error as? LLMError {
            return llmError
        }
        
        if let providerError = error as? LLMProviderError {
            switch providerError {
            case .badURL:
                return .invalidResponse
            case .decodingFailed:
                return .invalidResponse
            case .httpStatus(let code, _):
                if code == 401 || code == 403 { return .authenticationFailed }
                if code == 408 { return .requestTimeout }
                if code == 429 { return .rateLimited }
                if (500..<600).contains(code) { return .serverError(code) }
                return .invalidResponse
            }
        }
        
        // Map common errors
        if error is URLError {
            let urlError = error as! URLError
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .networkUnavailable
            case .timedOut:
                return .requestTimeout
            default:
                return .unknown(error)
            }
        }
        
        return .unknown(error)
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
                if path.status == .satisfied {
                    self?.logger.info("Network connection restored")
                } else {
                    self?.logger.warning("Network connection lost")
                }
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }
}

/// Enhanced LLM errors with detailed categorization
public enum LLMError: Error, LocalizedError {
    case networkUnavailable
    case requestTimeout
    case rateLimited
    case apiKeyMissing
    case authenticationFailed
    case invalidResponse
    case serverError(Int)
    case unknown(Error)
    
    public var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "No internet connection available"
        case .requestTimeout:
            return "Request timed out. Please try again."
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .apiKeyMissing:
            return "API configuration is missing"
        case .authenticationFailed:
            return "Authentication failed. Please check your settings."
        case .invalidResponse:
            return "Received an invalid response from the server"
        case .serverError(let code):
            return "Server error (\(code)). Please try again later."
        case .unknown(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }
    
    public var recoveryGuidance: String {
        switch self {
        case .networkUnavailable:
            return "Check your internet connection and try again."
        case .requestTimeout:
            return "The request is taking longer than usual. Try again in a moment."
        case .rateLimited:
            return "Please wait a few minutes before sending another message."
        case .apiKeyMissing, .authenticationFailed:
            return "Please check your AI service settings."
        case .invalidResponse:
            return "Try rephrasing your question or ask something different."
        case .serverError:
            return "The AI service is temporarily unavailable. Try again later."
        case .unknown:
            return "Try restarting the app or contact support if the issue persists."
        }
    }
}

/// Enhanced LLM response with metadata
public struct LLMResponse {
    public let content: String
    public let timestamp: Date
    public let source: ResponseSource
    public let confidence: Double
    public let contextUsed: Bool
    
    public enum ResponseSource {
        case llm
        case fallback
        case cache
    }
}
