import Foundation
import OSLog

@MainActor
final class LLMOrchestrator: ObservableObject {
    static let shared = LLMOrchestrator()
    
    private let logger = Logger(subsystem: "com.s2y.app", category: "LLMOrchestrator")
    
    // Local and cloud providers
    private let localService = LocalLLMService.shared
    private let cloudProvider = EnhancedLLMProvider.shared
    
    // State (optional observables)
    @Published private(set) var isLocalLoaded: Bool = false
    @Published private(set) var currentLocalModel: LocalModelConfig?
    @Published private(set) var lastError: Error?
    
    private init() {}
    
    // MARK: - Public API
    
    /// Complete a message using local model if available, otherwise fall back to cloud.
    func complete(message: String, includeContext: Bool) async throws -> LLMResponse {
        // If we're in environments that only provide mock local backends, bypass local and use cloud
        #if DEBUG
        return try await cloudProvider.sendMessage(message, includeContext: includeContext)
        #else
        #if targetEnvironment(simulator)
        return try await cloudProvider.sendMessage(message, includeContext: includeContext)
        #endif
        #endif
        
        // Ensure local model is prepared (lazy)
        if !localService.isModelLoaded {
            await prepareLocalModelIfNeeded()
        }
        
        // Try local first if model is loaded
        if localService.isModelLoaded {
            do {
                let text = try await localService.generateComplete(prompt: message)
                logger.info("Local model responded successfully")
                return LLMResponse(
                    content: text,
                    timestamp: Date(),
                    source: .llm,
                    confidence: 0.85,
                    contextUsed: includeContext
                )
            } catch {
                self.lastError = error
                logger.warning("Local generation failed, falling back to cloud: \(error.localizedDescription)")
            }
        }
        
        // Fall back to cloud
        return try await cloudProvider.sendMessage(message, includeContext: includeContext)
    }
    
    /// Prepare a local model (optional preloading). Automatically selects a model based on available RAM.
    func prepareLocalModelIfNeeded() async {
        guard !localService.isModelLoaded else {
            await MainActor.run { self.isLocalLoaded = true }
            return
        }
        
        let target = selectModelForDevice()
        do {
            try await localService.loadModel(target)
            await MainActor.run {
                self.isLocalLoaded = self.localService.isModelLoaded
                self.currentLocalModel = target
                self.lastError = nil
            }
            logger.info("Local model loaded: \(target.rawValue)")
        } catch {
            await MainActor.run { self.lastError = error }
            logger.error("Failed to load local model: \(error.localizedDescription)")
        }
    }
    
    /// Unload local model to free memory
    func unloadLocalModel() async {
        await localService.unloadModel()
        await MainActor.run {
            self.isLocalLoaded = false
            self.currentLocalModel = nil
        }
    }
    
    // MARK: - Model selection
    
    private func selectModelForDevice() -> LocalModelConfig {
        let ramGB = localService.getAvailableRAM()
        if ramGB >= 12 { return .mistralNemo }
        if ramGB >= 8 { return .llama3_8b }
        return .phi4Mini
    }
}

