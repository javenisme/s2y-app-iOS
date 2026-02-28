//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation

// ============================================================
// MARK: - Model Configuration
// ============================================================

/// Local LLM model configuration
public enum LocalModelConfig: String, CaseIterable, Codable, Identifiable, Sendable {
    case phi3_5Mini = "Phi-3.5-Mini"
    case phi4Mini = "Phi-4-Mini-3.8B"
    case llama3_8b = "Llama-3.1-8B-Instruct"
    case mistralNemo = "Mistral-Nemo-12B"
    case tinyLlama = "TinyLlama-1.1B"
    
    public var id: String { rawValue }
    
    /// Model quantization type
    public var quantization: String { "Q4_K_M" }
    
    /// Minimum RAM required in GB
    public var minRAM: Int {
        switch self {
        case .phi3_5Mini: return 2
        case .phi4Mini: return 4
        case .llama3_8b: return 8
        case .mistralNemo: return 12
        case .tinyLlama: return 1
        }
    }
    
    /// Model file extension
    public var fileExtension: String { "gguf" }
    
    /// HuggingFace model ID (placeholder)
    public var huggingFaceID: String {
        switch self {
        case .phi3_5Mini: return "microsoft/Phi-3.5-mini-instruct"
        case .phi4Mini: return "microsoft/Phi-4-mini-instruct"
        case .llama3_8b: return "meta-llama/Llama-3.1-8B-Instruct"
        case .mistralNemo: return "mistralai/Mistral-Nemo-Instruct-2407"
        case .tinyLlama: return "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
        }
    }
}

// ============================================================
// MARK: - Error Types
// ============================================================

/// Errors that can occur in LocalLLMService
public enum LocalLLMError: Error, LocalizedError, Sendable {
    case insufficientMemory(required: Int, available: Int)
    case modelNotLoaded
    case modelDownloadFailed(String)
    case modelLoadFailed(String)
    case generationFailed(String)
    case unsupportedModel
    
    public var errorDescription: String? {
        switch self {
        case .insufficientMemory(let required, let available):
            return "Insufficient memory: requires \(required)GB, available \(available)GB"
        case .modelNotLoaded:
            return "Model not loaded. Call loadModel() first."
        case .modelDownloadFailed(let message):
            return "Model download failed: \(message)"
        case .modelLoadFailed(let message):
            return "Model load failed: \(message)"
        case .generationFailed(let message):
            return "Generation failed: \(message)"
        case .unsupportedModel:
            return "Model not supported"
        }
    }
}

// ============================================================
// MARK: - Generation Parameters
// ============================================================

/// Parameters for LLM generation
public struct LocalGenerateParameters: Sendable {
    public var maxTokens: Int
    public var temperature: Double
    public var topP: Double
    public var topK: Int
    public var repeatPenalty: Double
    
    public init(
        maxTokens: Int = 1024,
        temperature: Double = 0.7,
        topP: Double = 0.9,
        topK: Int = 40,
        repeatPenalty: Double = 1.1
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.repeatPenalty = repeatPenalty
    }
}

// ============================================================
// MARK: - Model Container Protocol
// ============================================================

/// Protocol for underlying model implementation
/// Allows swapping between MLX, llama.cpp, CoreML backends
public protocol LLMModelContainer: Sendable {
    func generate(prompt: String, parameters: LocalGenerateParameters) -> AsyncThrowingStream<String, Error>
}

// ============================================================
// MARK: - Mock Container (Simulator-friendly placeholder)
// ============================================================

/// A lightweight mock container to validate the end-to-end pipeline in Simulator
public struct MockLLMContainer: LLMModelContainer {
    public init() {}
    public func generate(prompt: String, parameters: LocalGenerateParameters) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                // Simulate token-by-token streaming
                let prefix = "[Mock Phi-3.5] "
                let tokens = [
                    prefix,
                    "I read your request and ",
                    "here is a concise ",
                    "health-aware response. ",
                    "(This is a simulator mock.)"
                ]
                for token in tokens {
                    try? await Task.sleep(nanoseconds: 120_000_000) // 0.12s
                    continuation.yield(token)
                }
                continuation.finish()
            }
        }
    }
}

// ============================================================
// MARK: - Local LLM Service
// ============================================================

/// Local LLM service responsible for model loading and inference
/// This is the main interface for local LLM operations
@MainActor
public final class LocalLLMService: ObservableObject, @unchecked Sendable {
    
    // MARK: - Published Properties
    
    /// Whether a model is currently loaded
    @Published public private(set) var isModelLoaded: Bool = false
    
    /// Currently loaded model configuration
    @Published public private(set) var currentModel: LocalModelConfig?
    
    /// Whether generation is in progress
    @Published public private(set) var isGenerating: Bool = false
    
    /// Current loading progress (0.0 - 1.0)
    @Published public private(set) var loadingProgress: Double = 0.0
    
    /// Error message if any
    @Published public private(set) var lastError: LocalLLMError?
    
    // MARK: - Private Properties
    
    /// The underlying model container
    private var modelContainer: (any LLMModelContainer)?
    
    /// Memory cache for model containers
    private let containerCache = NSCache<NSString, NSMutableArray>()
    
    /// System prompt for health context
    private var systemPrompt: String = """
    You are a professional health assistant. You provide health information and suggestions \
    based on user's health data. Always remind users to consult healthcare professionals \
    for medical advice. Never provide definitive diagnoses.
    """
    
    // MARK: - Singleton
    
    public static let shared = LocalLLMService()
    
    private init() {}
    
    // MARK: - Public Interface
    
    /// Load a local model
    /// - Parameters:
    ///   - config: Model configuration to load
    ///   - progressHandler: Optional progress callback
    public func loadModel(
        _ config: LocalModelConfig,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws {
        // Check if already loaded
        if isModelLoaded, currentModel == config {
            return
        }
        
        // Unload previous model if different
        if currentModel != config {
            await unloadModel()
        }
        
        // Check available memory
        let availableRAM = getAvailableRAM()
        guard availableRAM >= config.minRAM else {
            let error = LocalLLMError.insufficientMemory(
                required: config.minRAM,
                available: availableRAM
            )
            lastError = error
            throw error
        }
        
        // Update loading progress
        loadingProgress = 0.1
        progressHandler?(0.1)
        
        // Try to load model from cache
        let cacheKey = config.rawValue as NSString
        if let cachedContainers = containerCache.object(forKey: cacheKey) {
            modelContainer = cachedContainers.first as? any LLMModelContainer
            if modelContainer != nil {
                loadingProgress = 1.0
                progressHandler?(1.0)
                isModelLoaded = true
                currentModel = config
                return
            }
        }
        
        // Load model (placeholder - actual implementation depends on backend)
        loadingProgress = 0.3
        progressHandler?(0.3)
        
        do {
            let container = try await loadModelContainer(config: config)
            loadingProgress = 0.9
            progressHandler?(0.9)
            
            modelContainer = container
            currentModel = config
            isModelLoaded = true
            loadingProgress = 1.0
            progressHandler?(1.0)
            lastError = nil
            
        } catch let error as LocalLLMError {
            lastError = error
            throw error
        } catch {
            let error = LocalLLMError.modelLoadFailed(error.localizedDescription)
            lastError = error
            throw error
        }
    }
    
    /// Unload the current model and free memory
    public func unloadModel() async {
        modelContainer = nil
        isModelLoaded = false
        currentModel = nil
        loadingProgress = 0.0
    }
    
    /// Generate a response using the loaded model
    /// - Parameters:
    ///   - prompt: User prompt
    ///   - parameters: Generation parameters
    /// - Returns: AsyncThrowingStream of generated tokens
    public func generate(
        prompt: String,
        parameters: LocalGenerateParameters = LocalGenerateParameters()
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { [weak self] continuation in
            Task { [weak self] in
                guard let self = self else {
                    continuation.finish(throwing: LocalLLMError.modelNotLoaded)
                    return
                }
                
                guard self.isModelLoaded, let container = self.modelContainer else {
                    continuation.finish(throwing: LocalLLMError.modelNotLoaded)
                    return
                }
                
                self.isGenerating = true
                defer { self.isGenerating = false }
                
                do {
                    // Build full prompt with system context
                    let fullPrompt = self.buildPrompt(userPrompt: prompt)
                    
                    // Generate
                    let stream = container.generate(prompt: fullPrompt, parameters: parameters)
                    
                    for try await token in stream {
                        continuation.yield(token)
                    }
                    
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Generate a complete response (non-streaming)
    /// - Parameters:
    ///   - prompt: User prompt
    ///   - parameters: Generation parameters
    /// - Returns: Complete generated string
    public func generateComplete(
        prompt: String,
        parameters: LocalGenerateParameters = LocalGenerateParameters()
    ) async throws -> String {
        var result = ""
        let stream = generate(prompt: prompt, parameters: parameters)
        
        for try await token in stream {
            result += token
        }
        
        return result
    }
    
    /// Quick smoke test to validate local model pipeline on Simulator/Device
    @discardableResult
    public func runSmokeTest(prompt: String = "Hello, how are my steps today?") async -> Result<String, Error> {
        do {
            try await loadModel(.phi3_5Mini)
            let output = try await generateComplete(prompt: prompt, parameters: LocalGenerateParameters(maxTokens: 64))
            return .success(output)
        } catch {
            return .failure(error)
        }
    }
    
    /// Set custom system prompt
    /// - Parameter prompt: Custom system prompt
    public func setSystemPrompt(_ prompt: String) {
        systemPrompt = prompt
    }
    
    /// Get available RAM in GB
    public func getAvailableRAM() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        let totalBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
        let bytesPerGB: UInt64 = 1_073_741_824 // 1024 * 1024 * 1024

        if result == KERN_SUCCESS {
            let usedBytes = UInt64(info.resident_size)
            let availableBytes = totalBytes > usedBytes ? (totalBytes - usedBytes) : 0
            return Int(availableBytes / bytesPerGB)
        }

#if targetEnvironment(simulator)
        return 8
#else
        return 4
#endif
    }
    
    // MARK: - Private Methods
    
    private func loadModelContainer(config: LocalModelConfig) async throws -> any LLMModelContainer {
#if DEBUG
        // In DEBUG builds, always return a mock container to enable simulator smoke tests
        return MockLLMContainer()
#else
    #if targetEnvironment(simulator)
        // On simulator in non-DEBUG, still provide mock to validate UI flows
        return MockLLMContainer()
    #else
        // TODO: Replace with actual MLX/llama.cpp/CoreML backend
        throw LocalLLMError.modelLoadFailed("MLX integration not yet implemented. Use GGUF backend for now.")
    #endif
#endif
    }
    
    private func buildPrompt(userPrompt: String) -> String {
        """
        <|system|>
        \(systemPrompt)
        <|user|>
        \(userPrompt)
        <|assistant|>
        """
    }
}

// MARK: - Preview Support

#if DEBUG
extension LocalLLMService {
    /// Create a preview instance with mock data
    public static func preview() -> LocalLLMService {
        let service = LocalLLMService()
        service.isModelLoaded = true
        service.currentModel = .phi4Mini
        return service
    }
}
#endif

