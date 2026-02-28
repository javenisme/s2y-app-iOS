# S2Y Health App - Phase 1: 基础架构详细设计

> 版本: v1.0
> 日期: 2026-02-26
> 状态: Spec Draft

---

## 1. Phase 1 目标

实现本地 LLM 推理核心能力，为后续的混合 AI 架构打下基础。

### 1.1 交付物

| 交付物 | 描述 |
|--------|------|
| MLX Swift 集成 | 本地 LLM 加载与推理 |
| LocalHealthAnalysisUseCase | 健康数据分析用例 |
| Query Router | 简单的本地/云端路由 |
| 本地模型下载管理 | 支持多模型选择与缓存 |

---

## 2. 技术架构

### 2.1 组件关系

```
┌─────────────────────────────────────────────────────────────────┐
│                        HealthAssistantView                      │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    HealthIntelligenceEngine                       │
│  (现有 - 保持不变)                                               │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      OrchestratorRouter                          │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐    ┌──────────────────┐                  │
│  │ LocalLLMService  │    │ CloudLLMService  │                  │
│  │   (MLX Swift)    │    │   (s2y-omer)    │                  │
│  └──────────────────┘    └──────────────────┘                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. 核心模块详细设计

### 3.1 LocalLLMService

```swift
// S2Y/LLM/LocalLLMService.swift
import Foundation
import MLX
import MLXLLM

/// 本地 LLM 服务 - 负责模型加载与推理
@MainActor
class LocalLLMService: ObservableObject {
    
    // MARK: - Published Properties
    @Published private(set) var isModelLoaded = false
    @Published private(set) var currentModel: ModelConfig?
    @Published private(set) var isGenerating = false
    
    // MARK: - Private Properties
    private var modelContainer: MLXLLMModelContainer?
    private let modelCache = NSCache<NSString, MLXLLMModelContainer>()
    
    // MARK: - Supported Models
    enum ModelConfig: String, CaseIterable, Codable {
        case phi4Mini = "Phi-4-Mini-3.8B"
        case llama3_8b = "Llama-3.1-8B-Instruct"
        case mistralNemo = "Mistral-Nemo-12B"
        
        var quantization: String { "Q4_K_M" }
        var minRAM: Int {  // GB
            switch self {
            case .phi4Mini: return 4
            case .llama3_8b: return 8
            case .mistralNemo: return 12
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// 加载模型
    func loadModel(_ config: ModelConfig) async throws {
        guard !isModelLoaded else { return }
        
        isGenerating = true
        defer { isGenerating = false }
        
        // 检查可用内存
        let availableRAM = getAvailableRAM()
        guard availableRAM >= config.minRAM else {
            throw LocalLLMError.insufficientMemory(
                required: config.minRAM,
                available: availableRAM
            )
        }
        
        // 加载模型
        let params = MLXLLMModelParameters(
            maxMemory: [
                "gpu": "\(availableRAM - 2)GB"  // 保留 2GB 给系统
            ],
            tokenLimit: 4096,
            temperature: 0.7
        )
        
        modelContainer = try await MLXLLMModelContainer.load(
            modelPath: config.modelPath,
            parameters: params
        )
        
        currentModel = config
        isModelLoaded = true
    }
    
    /// 生成回复 (流式)
    func generate(
        prompt: String,
        systemPrompt: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let container = self.modelContainer else {
                        throw LocalLLMError.modelNotLoaded
                    }
                    
                    let input = MLXLLMMLXLMInput(
                        prompt: prompt,
                        systemPrompt: systemPrompt,
                        context: []
                    )
                    
                    for try await token in try await container.generate(
                        prompt: input,
                        parameters: MLXLLMGenerateParameters(
                            temperature: 0.7,
                            maxTokens: 1024
                        )
                    ) {
                        continuation.yield(token)
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// 卸载模型
    func unloadModel() {
        modelContainer = nil
        currentModel = nil
        isModelLoaded = false
    }
    
    // MARK: - Private Methods
    
    private func getAvailableRAM() -> Int {
        // 获取可用内存的逻辑
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let usedMB = Int(info.resident_size) / 1024 / 1024
            let totalMB = ProcessInfo.processInfo.physicalMemory / 1024 / 1024
            return totalMB - usedMB
        }
        return 4  // 默认假设 4GB 可用
    }
}

// MARK: - Error Types

enum LocalLLMError: LocalizedError {
    case insufficientMemory(required: Int, available: Int)
    case modelNotLoaded
    case downloadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .insufficientMemory(let required, let available):
            return "内存不足: 需要 \(required)GB, 可用 \(available)GB"
        case .modelNotLoaded:
            return "模型未加载"
        case .downloadFailed(let message):
            return "模型下载失败: \(message)"
        }
    }
}
```

---

### 3.2 OrchestratorRouter

```swift
// S2Y/LLM/OrchestratorRouter.swift
import Foundation

/// 路由决策器 - 决定使用本地还是云端 LLM
class OrchestratorRouter {
    
    // MARK: - Dependencies
    private let localLLM: LocalLLMService
    private let cloudLLM: CloudLLMService  // 复用现有的 LLMProvider
    
    // MARK: - Routing Rules
    private let privacyRules: [PrivacyRule] = [
        // 完全本地处理
        .alwaysLocal([:]),  // 症状描述
        .alwaysLocal([:]),  // 医疗记录
        .alwaysLocal([:]),  // 健康指标
        
        // 可以云端处理
        .alwaysCloud([:]),  // 通用健康知识
        .alwaysCloud([:]),  // 天气/位置
    ]
    
    // MARK: - Public Interface
    
    /// 路由查询到合适的 LLM
    func route(query: String, context: QueryContext) async -> LLMResponse {
        let decision = await decideRoute(query: query, context: context)
        
        switch decision.destination {
        case .local:
            return await processLocal(query: query, context: context)
        case .cloud:
            return await processCloud(query: query, context: context)
        case .hybrid:
            return await processHybrid(query: query, context: context)
        }
    }
    
    // MARK: - Private Methods
    
    private func decideRoute(query: String, context: QueryContext) async -> RouteDecision {
        // 检查隐私级别
        let privacyLevel = classifyPrivacy(query: query, context: context)
        
        // 检查复杂度
        let complexity = classifyComplexity(query: query)
        
        // 检查网络状态
        let isOnline = await checkNetworkStatus()
        
        // 决策逻辑
        if privacyLevel == .sensitive {
            return RouteDecision(destination: .local, confidence: 1.0)
        }
        
        if !isOnline {
            return RouteDecision(destination: .local, confidence: 0.9)
        }
        
        if complexity == .simple && privacyLevel == .public {
            return RouteDecision(destination: .cloud, confidence: 0.8)
        }
        
        return RouteDecision(destination: .hybrid, confidence: 0.7)
    }
    
    private func processLocal(query: String, context: QueryContext) async -> LLMResponse {
        let systemPrompt = buildSystemPrompt(for: context)
        
        let stream = localLLM.generate(prompt: query, systemPrompt: systemPrompt)
        
        return LLMResponse(
            source: .local,
            stream: stream
        )
    }
    
    private func processCloud(query: String, context: QueryContext) async -> LLMResponse {
        // 调用现有的 CloudLLMService
        return await cloudLLM.chat(query: query, context: context)
    }
    
    private func processHybrid(query: String, context: QueryContext) async -> LLMResponse {
        // 本地向量搜索 + 云端推理
        let localContext = await retrieveLocalContext(query: query)
        let enhancedQuery = "\(localContext)\n\n用户问题: \(query)"
        
        return await cloudLLM.chat(query: enhancedQuery, context: context)
    }
    
    // MARK: - Classification Helpers
    
    private func classifyPrivacy(query: String, context: QueryContext) -> PrivacyLevel {
        // 简单的关键词检测
        let sensitiveKeywords = ["心率", "血压", "症状", "医疗", "健康记录", "HRV"]
        
        for keyword in sensitiveKeywords {
            if query.contains(keyword) {
                return .sensitive
            }
        }
        
        return .public
    }
    
    private func classifyComplexity(query: String) -> QueryComplexity {
        let simpleKeywords = ["什么是", "如何", "怎么", "告诉我"]
        
        for keyword in simpleKeywords {
            if query.contains(keyword) {
                return .simple
            }
        }
        
        return .complex
    }
    
    private func checkNetworkStatus() async -> Bool {
        // 简单的网络检查
        return true
    }
    
    private func buildSystemPrompt(for context: QueryContext) -> String {
        var prompt = "你是一个专业的健康助手。"
        
        if let userProfile = context.userProfile {
            prompt += "\n用户信息: \(userProfile)"
        }
        
        if let recentData = context.recentHealthData {
            prompt += "\n最近健康数据: \(recentData)"
        }
        
        return prompt
    }
    
    private func retrieveLocalContext(query: String) async -> String {
        // TODO: 实现本地向量搜索
        return ""
    }
}

// MARK: - Supporting Types

enum PrivacyLevel {
    case sensitive  // 敏感 - 必须本地
    case internal   // 内部 - 混合
    case public     // 公开 - 可以云端
}

enum QueryComplexity {
    case simple
    case complex
}

enum LLMDestination {
    case local
    case cloud
    case hybrid
}

struct RouteDecision {
    let destination: LLMDestination
    let confidence: Double
}

struct QueryContext {
    var userProfile: String?
    var recentHealthData: String?
    var conversationHistory: [String]?
}

struct LLMResponse {
    let source: LLMDestination
    let stream: AsyncThrowingStream<String, Error>?
    var cached: String?
}
```

---

### 3.3 ModelDownloadManager 扩展

复用现有的 `ModelDownloadManager`，添加 MLX 模型支持。

```swift
// S2Y/LocalModel/MLXModelDownloadManager.swift
extension ModelDownloadManager {
    
    /// 下载 MLX 模型
    func downloadMLXModel(_ config: LocalLLMService.ModelConfig) async throws -> URL {
        let destination = getModelDestination(for: config)
        
        // 检查是否已存在
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }
        
        // 下载模型
        let sourceURL = config.downloadURL
        
        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: sourceURL) { tempURL, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let tempURL = tempURL else {
                    continuation.resume(throwing: DownloadError.noData)
                    return
                }
                
                do {
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            task.resume()
        }
    }
    
    private func getModelDestination(for config: LocalLLMService.ModelConfig) -> URL {
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        
        return documentsPath
            .appendingPathComponent("MLXModels")
            .appendingPathComponent(config.rawValue)
    }
}

enum DownloadError: Error {
    case noData
    case invalidResponse
}
```

---

## 4. 任务拆解

### Phase 1 任务列表

| 任务 ID | 任务描述 | Agent | 依赖 | 状态 |
|---------|----------|-------|------|------|
| **P1.1** | 创建 `LocalLLMService` 基础框架 | Claude Code | - | ⬜ |
| **P1.2** | 集成 MLX Swift via SPM | Claude Code | P1.1 | ⬜ |
| **P1.3** | 实现 `OrchestratorRouter` 核心逻辑 | Claude Code | P1.1 | ⬜ |
| **P1.4** | 扩展 `ModelDownloadManager` 支持 MLX | Claude Code | - | ⬜ |
| **P1.5** | 集成测试与性能基准 | Claude Code | P1.1, P1.2 | ⬜ |
| **P1.6** | 文档编写 | - | 所有任务 | ⬜ |

---

## 5. 验收标准

### 功能验收

- [ ] 应用启动后能自动加载默认模型 (Phi-4 Mini)
- [ ] 用户查询能根据隐私级别正确路由到本地/云端
- [ ] 本地生成响应时间 < 2秒 (对于简单查询)
- [ ] 模型能在后台正确卸载以释放内存

### 性能验收

| 指标 | 目标 | 测试方法 |
|------|------|----------|
| 首 token 时间 (TTFT) | < 500ms | Instruments Time Profiler |
| 吞吐量 | > 30 tok/s | 基准测试 |
| 内存占用 | < 4GB | Memory Graph |
| 电池影响 | < 10%/小时 | Battery Monitor |

### 稳定性验收

- [ ] 连续运行 30 分钟无崩溃
- [ ] 内存警告时能正确降级
- [ ] 网络切换时能正确处理

---

## 6. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| MLX SPM 集成问题 | 高 | 准备 fallback: 使用 GGUF + llama.cpp |
| 内存不足 | 中 | 实现模型动态加载/卸载 |
| 性能不达标 | 中 | 降级到更小的模型 |

---

## 7. 后续 Phase 预告

### Phase 2: 知识图谱
- 集成 sqlite-vec
- 实现本地向量搜索
- 构建 MedicalKnowledge SwiftData 模型

### Phase 3: 混合推理
- 实现 RAG Pipeline
- 集成 s2y-omer 作为云端大脑
- 添加差分隐私模块

---

*Phase 1 详细设计 - v1.0*
