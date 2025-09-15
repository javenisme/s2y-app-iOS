//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//
import Foundation

// Guard MLX-only implementation behind availability flags
#if canImport(MLX) && canImport(MLXNN) && canImport(MLXRandom)
import MLX
import MLXNN
import MLXRandom
import Foundation
import SwiftUI
import OSLog

/// 本地健康模型管理器 - Phi-3.5 Mini集成
@MainActor
class LocalHealthModelManager {
    static let shared = LocalHealthModelManager()
    
    // MARK: - Public Properties
    private(set) var isModelLoaded = false
    private(set) var loadingProgress: Double = 0.0
    private(set) var modelStatus: ModelStatus = .notLoaded
    private(set) var lastError: LocalizedError?
    
    // MARK: - Private Properties
    private var model: LMModel?
    private var tokenizer: Tokenizer?
    private let logger = Logger(subsystem: "S2Y", category: "LocalModel")
    private let memoryMonitor = ModelMemoryMonitor()
    private let config = ModelConfiguration()
    
    private init() {
        setupMemoryWarningObserver()
    }
    
    enum ModelStatus: Equatable {
        case notLoaded
        case loading
        case loaded
        case error(String)
        
        static func == (lhs: ModelStatus, rhs: ModelStatus) -> Bool {
            switch (lhs, rhs) {
            case (.notLoaded, .notLoaded), (.loading, .loading), (.loaded, .loaded):
                return true
            case let (.error(lhsMessage), .error(rhsMessage)):
                return lhsMessage == rhsMessage
            default:
                return false
            }
        }
    }
    
    // MARK: - Public API
    
    /// 按需加载模型
    func loadModelIfNeeded() async {
        guard !isModelLoaded && modelStatus != .loading else { return }
        await loadModel()
    }
    
    /// 生成健康相关响应
    func generateHealthResponse(
        for query: String,
        with healthData: [String: Any] = [:]
    ) async throws -> String {
        try await ensureModelLoaded()
        
        let prompt = HealthPromptBuilder.buildPrompt(
            query: query,
            healthData: healthData
        )
        
        logger.info("Generating response for health query")
        return try await generateText(prompt: prompt)
    }
    
    /// 卸载模型释放内存
    func unloadModel() {
        logger.info("Unloading local health model")
        
        model = nil
        tokenizer = nil
        isModelLoaded = false
        modelStatus = .notLoaded
        
        // 清理MLX缓存
        MLX.clearCache()
    }
    
    // MARK: - Private Implementation
    
    private func loadModel() async {
        logger.info("Starting to load Phi-3.5 Mini model")
        modelStatus = .loading
        loadingProgress = 0.0
        lastError = nil
        
        do {
            // 检查内存可用性
            guard memoryMonitor.hasEnoughMemory(requiredMB: config.maxMemoryMB) else {
                throw ModelError.insufficientMemory
            }
            
            // 检查模型文件存在性
            guard let modelURL = config.modelURL,
                  let tokenizerURL = config.tokenizerURL else {
                throw ModelError.modelFilesNotFound
            }
            
            // 加载模型
            loadingProgress = 0.1
            logger.info("Loading model from: \(modelURL.path)")
            
            model = try await LMModel.load(path: modelURL.path) { progress in
                Task { @MainActor in
                    self.loadingProgress = 0.1 + (progress * 0.7) // 10%-80%
                    self.logger.debug("Model loading progress: \(Int(progress * 100))%")
                }
            }
            
            // 加载分词器
            loadingProgress = 0.85
            logger.info("Loading tokenizer from: \(tokenizerURL.path)")
            tokenizer = try await Tokenizer.load(path: tokenizerURL.path)
            
            loadingProgress = 1.0
            isModelLoaded = true
            modelStatus = .loaded
            
            logger.info("✅ Phi-3.5 Mini model loaded successfully")
            
        } catch {
            logger.error("❌ Failed to load model: \(error.localizedDescription)")
            lastError = error as? LocalizedError ?? ModelError.loadingFailed(error.localizedDescription)
            modelStatus = .error(error.localizedDescription)
            throw error
        }
    }
    
    private func ensureModelLoaded() async throws {
        if !isModelLoaded {
            await loadModel()
        }
        
        guard isModelLoaded, case .loaded = modelStatus else {
            throw ModelError.modelNotLoaded
        }
    }
    
    private func generateText(prompt: String) async throws -> String {
        guard let model = model, let tokenizer = tokenizer else {
            throw ModelError.modelNotLoaded
        }
        
        do {
            // 编码输入
            let inputTokens = tokenizer.encode(text: prompt)
            logger.debug("Input tokens count: \(inputTokens.count)")
            
            // 配置生成参数
            let generateParams = GenerateParameters(
                temperature: config.temperature,
                topP: config.topP,
                maxTokens: config.maxTokens
            )
            
            // 生成文本
            let outputTokens = try await model.generate(
                inputTokens: inputTokens,
                parameters: generateParams
            )
            
            // 解码输出
            let generatedText = tokenizer.decode(tokens: outputTokens)
            logger.debug("Generated text length: \(generatedText.count) characters")
            
            // 清理和格式化输出
            return cleanGeneratedText(generatedText, originalPrompt: prompt)
            
        } catch {
            logger.error("Text generation failed: \(error.localizedDescription)")
            throw ModelError.generationFailed(error.localizedDescription)
        }
    }
    
    private func cleanGeneratedText(_ text: String, originalPrompt: String) -> String {
        // 移除输入提示部分，只保留生成的响应
        var cleanedText = text
        
        // 查找响应开始标记
        if let responseStartRange = text.range(of: "请提供分析和建议：") {
            let responseStart = responseStartRange.upperBound
            cleanedText = String(text[responseStart...])
        }
        
        // 移除多余的换行和空白
        cleanedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 确保响应不为空
        if cleanedText.isEmpty {
            return "抱歉，我无法为您的健康查询生成合适的回复。请尝试重新提问或稍后再试。"
        }
        
        return cleanedText
    }
    
    private func setupMemoryWarningObserver() {
        memoryMonitor.registerMemoryWarningObserver { [weak self] in
            Task { @MainActor in
                self?.handleMemoryWarning()
            }
        }
    }
    
    private func handleMemoryWarning() {
        logger.warning("Memory warning received, considering model unload")
        
        // 如果内存压力大且模型已加载，卸载模型
        if isModelLoaded && memoryMonitor.getAvailableMemoryMB() < config.minRequiredMemoryMB {
            unloadModel()
        }
    }
}

#else

// Fallback shim when MLX is not available: alias to simplified manager
typealias LocalHealthModelManager = LocalHealthModelManager_Simplified

#endif

// MARK: - Configuration

private struct ModelConfiguration {
    // 模型参数
    let maxTokens = 512
    let temperature: Float = 0.7
    let topP: Float = 0.9
    
    // 内存限制
    let maxMemoryMB = 1536     // 1.5GB 最大内存使用
    let minRequiredMemoryMB = 768  // 768MB 最小内存要求
    
    // 模型文件路径
    var modelURL: URL? {
        Bundle.main.url(forResource: "phi-3.5-mini-4bit", withExtension: "mlx")
    }
    
    var tokenizerURL: URL? {
        Bundle.main.url(forResource: "tokenizer", withExtension: "json")
    }
}

// MARK: - Generate Parameters

private struct GenerateParameters {
    let temperature: Float
    let topP: Float
    let maxTokens: Int
}

// MARK: - Error Types

enum ModelError: LocalizedError {
    case modelNotLoaded
    case insufficientMemory
    case modelFilesNotFound
    case loadingFailed(String)
    case generationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "本地健康AI模型未加载"
        case .insufficientMemory:
            return "设备内存不足，无法加载AI模型"
        case .modelFilesNotFound:
            return "未找到AI模型文件，请检查应用安装"
        case .loadingFailed(let reason):
            return "AI模型加载失败: \(reason)"
        case .generationFailed(let reason):
            return "AI响应生成失败: \(reason)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .modelNotLoaded:
            return "请稍等片刻让AI模型加载完成"
        case .insufficientMemory:
            return "请关闭其他应用释放内存后重试"
        case .modelFilesNotFound:
            return "请重新安装应用或联系技术支持"
        case .loadingFailed, .generationFailed:
            return "请重试，如果问题持续请联系技术支持"
        }
    }
}
