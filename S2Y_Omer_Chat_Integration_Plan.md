# S2Y App 接入 s2y-omer 聊天能力计划

> 版本: v0.1
> 日期: 2026-03-22
> 范围: `~/workspace/s2y-app-iOS` + `~/workspace/s2y-omer`

---

## 1. 目标

让当前 iOS App 具备接入 `s2y-omer` 聊天能力的基础设施，并分阶段演进到可支持:

- 原生聊天会话
- 流式回复
- 历史会话
- HealthKit 摘要上下文注入
- 后续扩展到量表、恢复计划、症状记录等 Omer 工具能力

本计划优先保证:

- iOS 侧原生体验
- 后端协议稳定
- 身份与隐私边界清晰
- MVP 可快速落地

---

## 2. 现状结论

### 2.1 iOS App 当前状态

当前聊天入口是本地 SwiftUI 视图，发送文本后等待整段结果返回，再追加到消息列表:

- `S2Y/HealthAssistant/HealthAssistantView.swift`
- `S2Y/LLM/EnhancedLLMProvider.swift`

当前特征:

- UI 是原生简易聊天 UI
- provider 以纯文本问答为主
- 已有本地模型和云端 provider 路由逻辑
- 已有设置页可配置云端 URL / model path / token
- 账号体系主要围绕 Firebase / Spezi

### 2.2 s2y-omer 当前状态

`s2y-omer` 已经是完整 Web 聊天平台，不只是一个单纯 LLM API:

- `app/(chat)/api/chat/route.ts`
- `app/(auth)/auth.ts`
- `lib/db/schema.ts`

当前特征:

- 依赖 Auth.js session
- 依赖 PostgreSQL 保存 `User / Chat / Message / Stream`
- 返回的是 UI message stream，不是简单 `text/plain`
- 内部集成大量 tools
- 有 guest/regular 用户概念和额度控制

### 2.3 关键判断

不建议让 iOS 直接复用 Web 聊天接口。

原因:

- Web 接口和 Auth.js cookie session 强绑定
- Web 消息结构比 iOS 当前需求复杂很多
- tool approval / artifact / resume stream 都是 Web 视图协议的一部分
- iOS 直接“模拟前端”成本高且后续脆弱

结论:

**推荐在 `s2y-omer` 增加一层 Mobile API façade，iOS 只对接这层稳定接口。**

---

## 3. 推荐架构

### 3.1 总体方案

```text
S2Y iOS App
  ├─ HealthAssistantView
  ├─ OmerChatViewModel
  ├─ OmerChatService
  ├─ OmerSessionStore
  └─ HealthContextBuilder
          |
          v
   s2y-omer Mobile API Façade
  ├─ /api/mobile/session
  ├─ /api/mobile/chat
  ├─ /api/mobile/chats/:id
  └─ /api/mobile/chats/:id/messages
          |
          v
   Existing Omer Chat Core
  ├─ prompt / model selection
  ├─ persistence
  ├─ selected tools
  └─ streaming
```

### 3.2 设计原则

- iOS 只消费移动端协议，不耦合 Web UI message 协议
- 后端内部继续复用 Omer 现有模型路由、DB、工具和 prompt
- 移动端首版协议只支持文本和简单元数据
- 复杂工具能力按白名单逐步开放
- 健康数据默认最小化上传，只传摘要，不传原始全量数据

---

## 4. 核心架构决策

### 4.1 决策 A: 是否直接调用现有 `/api/chat`

不推荐。

原因:

- 需要复刻 Web 的 `message.parts` 协议
- 需要处理 Auth.js cookie session
- 需要适配 SSE resumable stream
- 需要理解 tool approval continuation 语义

### 4.2 决策 B: 身份怎么打通

有两条路径:

#### 方案 B1: Mobile Guest Session

MVP 推荐方案。

做法:

- `s2y-omer` 提供移动端匿名 session 创建接口
- iOS 首次打开聊天时换取 `mobileSessionToken`
- 后续请求走 Bearer token
- Omer 侧继续映射到 guest user

优点:

- 快
- 对现有 App 登录体系侵入小
- 能尽快打通端到端链路

缺点:

- 与 Firebase 用户不统一
- 跨设备/跨端数据关联能力弱

#### 方案 B2: Firebase Identity Exchange

正式版推荐方案。

做法:

- iOS 传 Firebase ID token
- `s2y-omer` 校验 token
- 创建或绑定 Omer user
- 返回移动端访问 token

优点:

- 用户身份统一
- 会话归属清晰
- 后续健康档案、量表、计划、订单都更容易对齐

缺点:

- 后端改造更大
- 需要明确账号主键映射策略

### 4.3 推荐采用

- Phase 1: 先做 `B1 Mobile Guest Session`
- Phase 3: 演进到 `B2 Firebase Identity Exchange`

---

## 5. MVP 边界

### 5.1 Phase 1 必做

- iOS 原生文本聊天
- Omer 流式文本回复
- 会话创建
- 历史消息拉取
- 基础错误处理
- 后端额度限制和基本审计

### 5.2 Phase 1 不做

- 图片上传
- tool approval UI
- artifact UI
- resume stream 恢复机制
- 购物结算
- 多模态输入
- 复杂结构化卡片

### 5.3 Phase 2 增量

- HealthKit 摘要上下文
- 量表类工具
- 恢复计划类工具
- 更好的会话列表与标题生成

### 5.4 Phase 3 增量

- Firebase 身份打通
- 附件上传
- 结构化结果卡片
- 更精细的隐私/权限控制

---

## 6. 后端实施计划 (`s2y-omer`)

### 6.1 新增移动端 API 层

建议新增目录:

```text
app/api/mobile/session/route.ts
app/api/mobile/chat/route.ts
app/api/mobile/chats/[id]/route.ts
app/api/mobile/chats/[id]/messages/route.ts
lib/mobile-auth/
lib/mobile-chat/
lib/mobile-types.ts
```

### 6.2 API 草案

#### `POST /api/mobile/session`

用途:

- 创建移动端匿名 session
- 或使用 Firebase token 换取 mobile token

请求体:

```json
{
  "mode": "guest"
}
```

或:

```json
{
  "mode": "firebase",
  "firebaseIdToken": "<token>"
}
```

响应:

```json
{
  "accessToken": "<mobile-token>",
  "user": {
    "id": "uuid",
    "type": "guest"
  }
}
```

#### `POST /api/mobile/chat`

用途:

- 发送一条用户消息
- 返回流式文本 delta

请求体:

```json
{
  "chatId": "optional-uuid",
  "message": "最近睡眠很差，帮我分析一下",
  "selectedModel": "xai/grok-3-mini",
  "healthContext": {
    "steps7dAvg": 5234,
    "sleep7dAvgHours": 5.8,
    "restingHeartRate7dAvg": 74
  },
  "client": {
    "platform": "ios",
    "appVersion": "1.0.0"
  }
}
```

响应:

- `Content-Type: text/event-stream`
- 事件建议简化为:

```text
event: chat.started
data: {"chatId":"...","messageId":"..."}

event: chat.delta
data: {"text":"最近"}

event: chat.delta
data: {"text":"你的睡眠..."}

event: chat.completed
data: {"chatId":"...","assistantMessageId":"..."}
```

#### `GET /api/mobile/chats/:id`

用途:

- 获取会话元信息

响应:

```json
{
  "id": "uuid",
  "title": "睡眠分析",
  "createdAt": "2026-03-22T12:00:00Z"
}
```

#### `GET /api/mobile/chats/:id/messages`

用途:

- 获取历史消息

响应:

```json
{
  "messages": [
    {
      "id": "uuid",
      "role": "user",
      "text": "最近睡眠很差"
    },
    {
      "id": "uuid",
      "role": "assistant",
      "text": "我们先从近7天睡眠和心率趋势看..."
    }
  ]
}
```

### 6.3 后端内部复用策略

移动端 API 不应重新发明聊天核心逻辑，而是提炼现有能力:

- 复用模型选择逻辑
- 复用 title 生成逻辑
- 复用 DB `Chat / Message` 存储
- 复用限额控制
- 复用部分 tool 注册能力

建议抽出:

```text
lib/chat-core/
  create-chat-session.ts
  run-chat-turn.ts
  persist-chat-turn.ts
  build-system-prompt.ts
  select-mobile-tools.ts
```

### 6.4 工具能力白名单

Phase 1:

- 无工具，纯文本

Phase 2:

- PHQ-9 / GAD-7 / LC-ANS-12
- `updateHealthProfile`
- `generateRecoveryPlan`
- `getRecoveryPlan`
- `logSymptoms`
- `symptomTrends`

Phase 3 以后再考虑:

- document / artifact
- checkout
- 富交互 approval 类工具

### 6.5 后端数据模型建议

已有 `User / Chat / Message_v2 / Stream` 足够支撑 MVP:

- 继续使用现有 `Chat`
- 继续使用现有 `Message_v2`
- 移动端消息内容在存储前转换成 Omer 内部 `parts` 结构

建议新增:

```text
MobileSession
  id
  userId
  tokenHash
  createdAt
  expiresAt
  lastUsedAt
  clientPlatform
```

如果暂时不想加表，也可以先用 JWT，但长期建议落表，便于失效控制和审计。

---

## 7. iOS 实施计划 (`s2y-app-iOS`)

### 7.1 新增模块建议

```text
S2Y/LLM/Omer/
  OmerChatService.swift
  OmerChatModels.swift
  OmerChatStreamParser.swift
  OmerSessionStore.swift
  OmerHealthContextBuilder.swift
  OmerChatViewModel.swift
```

### 7.2 iOS 侧职责拆分

#### `OmerChatService`

负责:

- 创建 session
- 发起聊天请求
- 解析 SSE
- 拉取历史消息
- 错误映射

#### `OmerSessionStore`

负责:

- 本地保存 `accessToken`
- 本地保存最近 `chatId`
- token 过期清理

建议存储方式:

- Keychain: `accessToken`
- UserDefaults/AppStorage: `chatId`, `baseURL`, feature flag

#### `OmerHealthContextBuilder`

负责:

- 从 HealthKit/缓存构造最小健康摘要
- 不上传原始样本
- 支持用户关闭上传健康摘要

#### `OmerChatViewModel`

负责:

- 管理消息数组
- 管理 streaming 状态
- 将 delta 逐步拼接到 assistant 占位消息
- 处理重试、取消、错误态

### 7.3 iOS UI 改造点

当前 `HealthAssistantView` 是“提交后等待完整响应”模式。

需要改造成:

1. 用户发消息后立即 append 用户消息
2. append 一个空的 assistant 占位消息
3. 收到每个 delta 时更新最后一条 assistant 文本
4. 完成后将消息持久化到本地上下文

### 7.4 设置页扩展

在现有设置页基础上新增移动端接入相关项:

- Backend Mode: `Direct Cloudflare / Omer`
- Omer Base URL
- Auth Mode: `Guest / Firebase`
- Include Health Summary 开关
- Reset Omer Session

### 7.5 与现有 provider 的关系

不要把 `Omer` 强塞进当前 `CloudflareLLMProvider` 协议实现里。

建议:

- 保留现有 `CloudflareLLMProvider` 作为直连 provider
- 新增 `OmerChatService` 作为独立聊天后端
- 在上层做路由:
  - 本地模型
  - 直连 Cloudflare
  - Omer Chat Backend

---

## 8. HealthKit 上下文策略

### 8.1 原则

- 只上传摘要，不上传原始样本序列
- 只上传当前问题相关的指标
- 用户可关闭
- 默认对用户透明展示“将共享哪些摘要字段”

### 8.2 首版摘要字段建议

```json
{
  "steps7dAvg": 5234,
  "stepsTrend": "down",
  "sleep7dAvgHours": 5.8,
  "sleepTrend": "down",
  "restingHeartRate7dAvg": 74,
  "restingHeartRateTrend": "up",
  "activeEnergy7dAvg": 412
}
```

### 8.3 上下文触发策略

- 默认只在用户显式问“健康趋势/睡眠/心率/活动”时携带
- 通用闲聊不带
- 对敏感场景保留本地处理选项

---

## 9. 分阶段里程碑

### Phase 0: 契约与骨架

目标:

- 确认 API 契约
- 确认身份方案
- 搭建移动端基础目录

交付:

- 本计划文档
- Mobile API schema 草案
- iOS 模块 skeleton

验收标准:

- 团队对 guest/Firebase 两阶段方案达成一致
- 已确定 Phase 1 的非目标范围

### Phase 1: 文本聊天 MVP

目标:

- iOS 能通过 Omer 完成原生文本流式聊天

后端任务:

- 新增 `/api/mobile/session`
- 新增 `/api/mobile/chat`
- 新增移动端 token 校验
- 复用持久化逻辑

iOS 任务:

- 新增 `OmerChatService`
- 新增流解析器
- UI 改成 assistant 占位 + delta 拼接
- 设置页增加 Omer backend 开关

验收标准:

- 新会话可发送消息
- 回复可流式显示
- 刷新后能重新拉取历史
- 失败时能展示明确错误

### Phase 2: 健康上下文与基础工具

目标:

- 把 S2Y 的健康数据优势接进 Omer

后端任务:

- 增加 `healthContext` 入参
- 增加移动端工具白名单
- 增加针对健康摘要的 prompt 规范

iOS 任务:

- 实现 `OmerHealthContextBuilder`
- 增加“共享健康摘要”开关
- 对健康类问题自动带摘要

验收标准:

- 睡眠/步数/心率类问题能引用摘要回答
- 用户可关闭摘要上传
- 不上传原始 HealthKit 样本

### Phase 3: 身份打通

目标:

- 与 Firebase 用户体系对齐

后端任务:

- 支持 Firebase token 校验
- 建立 Firebase user -> Omer user 映射
- guest 会话迁移或合并策略

iOS 任务:

- 登录状态下自动换取正式 session
- 游客与登录用户切换策略

验收标准:

- 登录后会话归属稳定
- 同一用户跨端数据一致

### Phase 4: 富能力扩展

目标:

- 逐步开放结构化工具和富结果

候选能力:

- 量表问卷
- 症状记录
- 恢复计划
- 结构化卡片
- 附件上传

---

## 10. 任务拆解

### 10.1 `s2y-omer` 任务清单

#### T1. Mobile auth

- 新增 mobile session token 生成与校验
- 定义 guest 模式 token 生命周期
- 增加中间件或 helper

#### T2. Mobile chat API

- 新增移动端聊天 route
- 复用 DB 持久化
- 复用模型选择
- 生成简化 SSE 事件

#### T3. Chat core 抽象

- 抽离 Web route 中可复用逻辑
- 将移动端与 Web route 都指向同一核心服务

#### T4. Mobile history API

- 查询 chat metadata
- 查询 messages
- 可选查询会话列表

#### T5. Tool gating

- 设计 `selectMobileTools`
- 明确哪些工具可在移动端启用

### 10.2 `s2y-app-iOS` 任务清单

#### T6. Omer service 层

- 新增 models
- 新增 HTTP client
- 新增 SSE parser
- 新增 session store

#### T7. 聊天 UI 升级

- 支持 streaming
- 支持错误态
- 支持重新发送

#### T8. 配置与开关

- 设置页增加 backend mode
- 支持 base URL 配置
- 支持 reset session

#### T9. 健康摘要

- 构建摘要
- 用户权限与开关
- 与 query intent 做最小耦合

#### T10. 回退路径

- Omer 故障时回退到本地或直连 provider

---

## 11. 风险与应对

### 风险 1: 身份体系冲突

描述:

- iOS 是 Firebase/Spezi
- Omer 是 Auth.js + Postgres user

应对:

- 先 guest，后 identity exchange
- 明确用户主键映射表

### 风险 2: 直接复用 Web 协议导致移动端复杂度失控

描述:

- message.parts / tool approval / resumable stream 对 iOS 不友好

应对:

- 建移动端 façade
- 保持协议简单稳定

### 风险 3: 健康数据上云的隐私边界不清晰

描述:

- 用户可能不接受上传原始健康数据

应对:

- 只传摘要
- 明示字段
- 可随时关闭

### 风险 4: 后端工具能力过多，移动端首版难以承载

描述:

- Omer tools 很多，但 iOS UI 还没有承载结构化交互的组件

应对:

- 先纯文本
- 工具按白名单逐步开放

### 风险 5: 流式协议调试成本高

描述:

- iOS SSE 解析和取消/重试处理容易出边界问题

应对:

- 协议事件最小化
- 先只支持 `started / delta / completed / error`

---

## 12. 验收标准

### MVP 验收

- iOS 发送文本后 1 秒内进入 streaming 状态
- Omer 返回内容能逐步显示
- 新会话与历史会话都可用
- 移动端 session 失效后可自动重建
- 错误时不会丢失用户刚发送的问题

### Phase 2 验收

- 健康类问题可带摘要上下文
- 用户可关闭摘要共享
- 回答中可体现对趋势摘要的理解

### Phase 3 验收

- 登录用户与游客行为边界清晰
- 同一身份的聊天数据可持续追踪

---

## 13. 推荐实施顺序

1. 先在 `s2y-omer` 定 Mobile API 契约
2. 先做 guest session，不等 Firebase 打通
3. iOS 接入文本流式 MVP
4. 打通历史消息
5. 接入健康摘要
6. 再做身份统一
7. 最后开放结构化工具

---

## 14. 近期最值得马上执行的 5 个具体动作

1. 在 `s2y-omer` 新建 `lib/mobile-types.ts`，冻结移动端请求/响应模型
2. 在 `s2y-omer` 新建 `POST /api/mobile/session`
3. 在 `s2y-omer` 新建 `POST /api/mobile/chat`，先只支持纯文本 streaming
4. 在 iOS 新建 `S2Y/LLM/Omer/OmerChatService.swift`
5. 把 `HealthAssistantView` 改成支持 assistant 占位消息 + delta 拼接

---

## 15. 最终建议

这次接入不要定义成“把 iOS 接到 Web 聊天接口”，而要定义成:

**“把 `s2y-omer` 沉淀为 S2Y iOS 可复用的聊天后端能力。”**

这样做的收益更长期:

- 移动端协议稳定
- Web 和 iOS 可共享核心聊天能力
- 后续 Android 或其他客户端也能复用
- 身份、隐私、工具能力可以逐步演进，而不是一次性耦死
