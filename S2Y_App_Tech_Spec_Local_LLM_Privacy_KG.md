# S2Y Health App - Technical Specification (v0.1)

> 基于 Gemini Research - 2026-02-26
> 属于: S2Y_App_Health_Assistant_Transformation_Plan

---

## 1. 本地 LLM 架构

### 1.1 框架对比 (2026)

| 框架 | 格式 | 核心优势 | 推荐场景 |
|------|------|----------|----------|
| **MLX Swift** | MLX | 最高吞吐量，利用统一内存架构 | 实时健康对话 |
| **llama.cpp** | GGUF | 社区模型丰富 (Llama 4, Gemma 3) | 快速原型 |
| **CoreML** | .mlpackage | 电池效率最优，利用 ANE | 后台任务 |

### 1.2 性能基准 (iPhone 17 Pro / A19 Pro)

| 模型 | 量化 | 速度 |
|------|------|------|
| Phi-4 Mini (3.8B) | Q4_K_M | ~35-50 tok/s |
| Llama 3.1 8B | Q4_K_M | ~12-18 tok/s |
| 提示处理 (TTFT) | 4k context | <100ms |

### 1.3 推荐架构

```swift
// LocalHealthAnalysisUseCase.swift
import MLX
import MLXLLM

class LocalHealthAnalysisUseCase {
    private let modelContainer = LLMModelFactory.shared
    
    func analyzeSymptomTrend(data: [HealthData]) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                let prompt = "Analyze these HRV trends: \(data.map { $0.description })"
                for try await token in modelContainer.generate(prompt: prompt) {
                    continuation.yield(token)
                }
                continuation.finish()
            }
        }
    }
}
```

---

## 2. 隐私与安全架构

### 2.1 HIPAA 合规策略

| 要求 | 实现方式 |
|------|----------|
| **零信任身份** | 身份层与临床层分离，使用匿名 UUID |
| **审计日志** | 每次 HealthData 访问必须记录 |
| **数据最小化** | AI 仅请求当前任务需要的特定指标 |
| **BAA** | 云端服务必须签署商业合作协议 |

### 2.2 iOS 加密最佳实践

```swift
// 安全数据存储
let data = try JSONEncoder().encode(timeSeries)
try data.write(to: fileURL, options: .completeFileProtection)
```

| 加密层 | 技术 |
|--------|------|
| 传输 | TLS 1.3 |
| 存储 | AES-256 + Data Protection API |
| 密钥 | Keychain (kSecAttrAccessibleWhenUnlocked) |
| ML 模型 | Xcode 加密，运行时解密到内存 |

### 2.3 差分隐私 (Differential Privacy)

- **本地 DP**: 数据在离开设备前添加噪声
- **隐私预算 (ε)**: 每日建议 2-8
- **实现**: 使用 Laplace Mechanism 添加数学噪声

```swift
protocol PrivacyProvider {
    func privatize(_ value: Double, epsilon: Double) -> Double
}
```

### 2.4 Apple Private Cloud Compute (PCC)

- ** stateless 计算**: 处理后立即删除数据
- **公开审计**: 软件镜像公开日志
- **集成方式**: 通过 App Intents 定义

---

## 3. 知识图谱与向量搜索

### 3.1 组件选择

| 功能 | 推荐工具 | 理由 |
|------|----------|------|
| **向量数据库** | `sqlite-vec` | 轻量，基于原生 SQLite，SIMD 加速 |
| **图数据库** | SwiftData | 原生 Apple 框架，支持 iCloud 同步 |
| **图算法** | SwiftGraph | 纯 Swift 实现，无 Python 开销 |
| **Embeddings** | MLX-Swift | Apple Silicon 优化 |
| **远程 LLM** | Minimax 2.5 | 复杂推理 |

### 3.2 本地优先架构

```
Layer 1: 数据获取
  ├── HealthKit Service (步数、睡眠、生命体征)
  └── Journaling/Symptoms (用户输入)

Layer 2: Cognify Pipeline (本地)
  ├── Embedding Engine (MLX-Swift 生成向量)
  ├── Vector Store (sqlite嵌入)
  └── Knowledge Graph (SwiftData-vec 存储 存储关系)

Layer 3: 智能引擎 (混合)
  ├── Local Planner (Swift 路由)
  │   ├── 简单查询 → 本地 SQL
  │   ├── 模式发现 → 本地 KG + 向量搜索
  │   └── 复杂合成 → 匿名化后发送到云端
  └── Minimax 2.5 (高层推理)

Layer 4: 远程合成
  └── 生成结构化健康洞察
```

### 3.3 实现示例

```swift
// SwiftData 知识图谱模型
@Model
class MedicalKnowledge {
    @Attribute(.unique) var id: UUID
    var symptom: String
    var relatedFactors: [String]
    var confidence: Double
    var lastUpdated: Date
}
```

---

## 4. 混合 AI 策略

### 4.1 分层推理

| 层级 | 处理方式 | 数据位置 |
|------|----------|----------|
| **Tier 1** | Core ML 实时推理 (心率异常检测) | 设备 ANE |
| **Tier 2** | PCC (Apple Intelligence) 复杂推理 | Apple 安全云 |
| **Tier 3** | HIPAA 合规 VPC (研究分析) | 脱敏数据 |

### 4.2 路由逻辑

```swift
enum InferenceTier {
    case local      // 隐私敏感，完全本地
    case hybrid     // 本地向量搜索 + 云端推理
    case cloud      // 纯云端 (非敏感查询)
}

func routeQuery(_ query: String, context: HealthContext) -> InferenceTier {
    if context.containsSensitiveData {
        return .local
    } else if query.requiresComplexReasoning {
        return .hybrid
    } else {
        return .cloud
    }
}
```

---

## 5. 下一步行动

### Phase 1: 基础架构
- [ ] 集成 MLX Swift (通过 SPM)
- [ ] 实现 `LocalHealthAnalysisUseCase`
- [ ] 搭建 `sqlite-vec` 向量存储

### Phase 2: 知识图谱
- [ ] 设计 SwiftData MedicalKnowledge 模型
- [ ] 实现 "Cognify" Pipeline (文档 → 向量 + 图关系)
- [ ] 集成 SwiftGraph 算法

### Phase 3: 混合推理
- [ ] 实现 Query Router (Tier 1/2/3 路由)
- [ ] 集成 Minimax 2.5 作为云端推理
- [ ] 添加差分隐私模块

---

*基于 Gemini Research 2026-02-26*
