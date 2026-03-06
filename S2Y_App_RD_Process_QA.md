# S2Y Health App - 研发流程与质量保证

> 版本: v1.0
> 日期: 2026-02-26
> 分类: 03_Specs

---

## 1. 研发流程 (基于 Orchestrator Design)

### 1.1 任务生命周期

```
┌─────────────────────────────────────────────────────────────────┐
│                     任务生命周期                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    │
│  │  Spec   │───→│  Dev    │───→│  Test   │───→│ Review  │    │
│  │  编写   │    │  开发   │    │  测试   │    │  审查   │    │
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘    │
│       ↑                                                 │       │
│       └────────────────────── 循环 ←─────────────────────┘       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 任务来源

| 来源 | 处理方式 |
|------|----------|
| **PRD/用户故事** | 从 00_User_Stories 提取 |
| **Tech Spec** | 从 03_Specs 提取 |
| **Bug 修复** | GitHub Issues |
| **技术优化** | 定期技术债务清理 |

### 1.3 任务创建流程

```yaml
任务创建:
  1. 从用户故事提取需求
  2. 编写 Tech Spec (如需要)
  3. 拆解为可执行任务
  4. 登记到 04_Tasks/tasks.json
  5. 分配 Agent (Claude Code / Codex / Gemini)
```

---

## 2. Agent 任务分配策略

### 2.1 Agent 选择规则

| 任务类型 | Agent | 理由 |
|----------|-------|------|
| **SwiftUI 界面开发** | Claude Code | 轻量改动，快速迭代 |
| **复杂逻辑/多文件** | Codex | 强代码理解 |
| **UI/视觉 Spec** | Gemini | 设计稿生成 |
| **文档/研究** | Gemini | 调研能力强 |
| **测试编写** | Claude Code | 与实现配套 |

### 2.2 任务模板

```json
{
  "id": "P1.1-local-llm-service",
  "title": "创建 LocalLLMService 基础框架",
  "description": "实现本地 LLM 加载与推理服务",
  "repo": "s2y-app-iOS",
  "agent": "claude-code",
  "priority": "P0",
  "dependencies": [],
  "spec": "03_Specs/S2Y_App_Phase1_Local_LLM_Architecture.md",
  "status": "todo",
  "definitionOfDone": [
    "LocalLLMService.swift 已创建",
    "支持模型加载/卸载",
    "支持流式生成",
    "单元测试覆盖 > 80%"
  ]
}
```

---

## 3. 代码质量标准

### 3.1 Swift 代码规范

| 规范 | 工具 | 规则 |
|------|------|------|
| **格式** | SwiftFormat | .swiftformat 配置 |
| **Lint** | SwiftLint | .swiftlint.yml (已有) |
| **类型检查** | Swift Compiler | strict 模式 |
| **文档** | SwiftDoc | 公共 API 必须 |

### 3.2 必须遵循的原则

```swift
// ✅ 正确示例
class LocalLLMService {
    /// 本地 LLM 服务 - 负责模型加载与推理
    /// - Parameter config: 模型配置
    /// - Throws: LocalLLMError 错误
    func loadModel(_ config: ModelConfig) async throws {
        // ...
    }
}

// ❌ 错误示例
class LocalLLMService {
    func loadModel(_ config: ModelConfig) async throws {
        // 没有文档
    }
}
```

### 3.3 代码审查清单

| 类别 | 检查项 |
|------|--------|
| **功能** | 实现符合 Spec？功能完整？ |
| **性能** | 无内存泄漏？无性能瓶颈？ |
| **安全** | 无敏感数据泄露？加密正确？ |
| **测试** | 有单元测试？覆盖关键路径？ |
| **文档** | API 文档完整？README 更新？ |

---

## 4. 测试要求

### 4.1 测试金字塔

```
           ┌─────────┐
           │   E2E   │  ← 关键用户路径 (3-5 个)
           ├─────────┤
           │集成测试 │  ← 模块间协作 (10-15 个)
           ├─────────┤
           │单元测试 │  ← 核心逻辑 (>50 个)
           └─────────┘
```

### 4.2 测试覆盖率要求

| 类型 | 覆盖率目标 |
|------|-----------|
| **单元测试** | > 80% |
| **集成测试** | > 60% |
| **E2E 测试** | 关键路径 100% |

### 4.3 测试命名规范

```swift
// ✅ 正确
class LocalLLMServiceTests: XCTestCase {
    func testLoadModel_Success() async throws { ... }
    func testLoadModel_InsufficientMemory_ThrowsError() async throws { ... }
    func testGenerate_StreamOutput() async throws { ... }
}

// ❌ 错误
class LocalLLMServiceTests: XCTestCase {
    func testLoad() async throws { ... }  // 不明确
    func testSomething() async throws { ... }  // 无意义
}
```

### 4.4 自动化测试场景

| 场景 | 类型 | 执行时机 |
|------|------|----------|
| 模型加载成功 | 单元 | 每次 PR |
| 内存不足处理 | 单元 | 每次 PR |
| 隐私路由正确 | 集成 | 每次 PR |
| 完整对话流程 | E2E | 每日构建 |

---

## 5. 代码审查流程

### 5.1 Pull Request 要求

```yaml
PR 标题格式:
  [模块] 简短描述
  
  示例:
  [LLM] 实现 LocalLLMService 基础框架
  [Privacy] 添加 OrchestratorRouter 路由逻辑

PR 描述必须包含:
  - 实现了什么功能
  - 如何测试 (截图/步骤)
  - 相关 Spec 链接
  - 是否需要特殊权限
```

### 5.2 Review 检查点

| 检查项 | 必须 | 说明 |
|--------|------|------|
| 功能完整 | ✅ | 符合 Spec |
| 代码规范 | ✅ | 通过 SwiftLint |
| 测试覆盖 | ✅ | 新增测试 |
| 文档更新 | ⚠️ | 如有 API 变更 |
| 性能影响 | ⚠️ | 显著变化需说明 |

### 5.3 Reviewer 分配

| 模块 | Reviewer |
|------|----------|
| LLM/AI 模块 | Javen (主要) |
| UI/SwiftUI | Javen (主要) |
| HealthKit | Javen (主要) |
| 基础设施 | Claude Code (auto) |

---

## 6. 持续集成 (CI)

### 6.1 CI 流水线

```
┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
│  Push    │──→│  Build   │──→│  Test    │──→│  Review  │
│          │   │  编译    │   │  测试    │   │  人工    │
└──────────┘   └──────────┘   └──────────┘   └──────────┘
                    │             │             │
                    ▼             ▼             ▼
               [失败: 修复]  [失败: 修复]   [失败: 修复]
```

### 6.2 CI 检查项

| 检查项 | 工具 | 失败处理 |
|--------|------|----------|
| 编译成功 | Xcode | 阻止合并 |
| 单元测试 | XCTest | 阻止合并 |
| 覆盖率 | xcov | 警告 |
| SwiftLint | swiftlint | 警告 |
| SwiftFormat | swiftformat | 自动修复 |

### 6.3 本地预检查 (Before Commit)

```bash
# 必须通过才能 commit
make pre-commit

# 包含:
# 1. swiftformat --recursive S2Y/
# 2. swiftlint --strict S2Y/
# 3. xcodebuild test (仅修改的 target)
```

---

## 7. 版本发布

### 7.1 版本号规范

```
Major.Minor.Patch
  │    │    └── Bug 修复
  │    └───── 新功能 (向后兼容)
  └─────────── 重大变更 (不兼容)

示例:
v1.0.0 - 初始发布
v1.1.0 - 添加本地 LLM 功能
v1.1.1 - 修复本地 LLM 内存泄漏
v2.0.0 - 重大架构变更
```

### 7.2 发布检查清单

| 检查项 | 说明 |
|--------|------|
| 所有测试通过 | 包括 E2E |
| 性能达标 | TTFT < 500ms, 内存 < 4GB |
| 安全审计 | 无敏感数据泄露 |
| 文档更新 | CHANGELOG, README |
| TestFlight | 构建成功 |

---

## 8. 缺陷管理

### 8.1 Bug 优先级

| 优先级 | 定义 | 响应时间 |
|--------|------|----------|
| **P0** | 崩溃、数据丢失 | 24h |
| **P1** | 功能失效 | 72h |
| **P2** | 体验问题 | 1 周 |
| **P3** | 优化建议 | 下一版本 |

### 8.2 Bug 模板

```markdown
## [P1] 本地模型加载失败

**复现步骤:**
1. 打开 App
2. 进入 Health Assistant
3. 等待模型加载

**期望结果:**
模型成功加载，显示在界面

**实际结果:**
显示加载失败弹窗

**日志:**
[附上相关日志]

**环境:**
- iOS 版本:
- 设备:
- 内存:
```

---

## 9. 文档管理

### 9.1 文档类型

| 类型 | 位置 | 更新时机 |
|------|------|----------|
| **用户故事** | 00_User_Stories | 新需求 |
| **技术 Spec** | 03_Specs | 新功能 |
| **API 文档** | 代码内 (SwiftDoc) | API 变更 |
| **README** | 项目根目录 | 重要变更 |
| **CHANGELOG** | CHANGELOG.md | 每次发布 |

### 9.2 Spec 编写要求

```yaml
每个 Tech Spec 必须包含:
  1. 目标 - 实现什么
  2. 架构 - 组件关系
  3. 接口 - API 定义
  4. 实现 - 核心代码
  5. 测试 - 验证方案
  6. 风险 - 已知问题
```

---

## 10. 总结

### 流程概览

```
需求 → Spec → 任务 → 开发 → 测试 → Review → 合并 → 发布
                              ↑
                         (循环迭代)
```

### 关键指标

| 指标 | 目标 |
|------|------|
| 代码覆盖率 | > 80% |
| PR 平均处理时间 | < 2 天 |
| Bug 修复时间 | P0 < 24h |
| 部署频率 | 每周 1 次 |

---

*研发流程与质量保证 - v1.0*
