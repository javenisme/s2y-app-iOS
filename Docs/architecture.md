# S2Y 架构文档（Architecture）

- 版本：v0.1
- 最近更新：2025-08-28
- 参考：Docs/epic-health-assistant.md（HealthKit 智能分析与健康助手）

## 1. 概览
S2Y 是基于 SwiftUI + Spezi 的模块化健康应用模板，提供账号、HealthKit、问卷、调度、通知、LLM 聊天等能力，并通过 Firebase 实现账号与数据后端。项目将原 TemplateApplication 重构为 S2Y 命名与结构。

目标：
- 作为 S2Y 标准工程模版，快速启用并扩展业务模块
- 即插即用的 Spezi 模块生态与演示
- 为后续“健康助手/洞察”能力奠定数据与界面基础

## 2. 代码与目录结构
主要源代码（S2Y）：
- `S2Y/S2YApplication.swift`、`S2Y/S2YApplicationDelegate.swift`：应用入口与 Spezi 配置
- `S2Y/S2YApplicationStandard.swift`：应用标准（Standard），聚合 HealthKit、问卷等回调处理
- `S2Y/HomeView.swift`：主 Tab（Chat / Schedule / Contacts / Settings）
- `S2Y/Showcase/ShowcaseView.swift`：Settings（Spezi 能力演示区）
- `S2Y/Schedule/`：调度（`S2YApplicationScheduler.swift`、`ScheduleView.swift`、`EventView.swift`）
- `S2Y/Onboarding/`：Onboarding（已适配 SpeziOnboarding 2.x）
- `S2Y/Firestore/FirebaseConfiguration.swift`：用户文档/文件存储引用与测试账号逻辑
- `S2Y/LLM/LLMChatDemoView.swift`：聊天 Demo（Cloudflare/OpenAI，已 Keychain + Info.plist）
- `S2Y/SharedContext/FeatureFlags.swift`：运行参数开关
- `S2Y/Supporting Files/`：Info.plist、entitlements、文档资源

其他：
- 旧 `TemplateApplication*` 已迁移为 `S2Y*` 等价类型。
- `fastlane/`：TestFlight 与发布脚本。
- `Docs/epic-health-assistant.md`：健康助手 Epic。

## 3. 运行时架构与模块职责
- SwiftUI 界面层
  - `HomeView`：四个 Tab；`Chat`（LLM）、`Schedule`（任务）、`Contacts`、`Settings`（Showcase）
  - Onboarding：`OnboardingFlow` + 若干 Screen（2.x API）
- Spezi 模块层
  - Account（`SpeziAccount`/`SpeziFirebaseAccount`）：登录、用户详情、账户事件
  - HealthKit（`SpeziHealthKit`/`HealthKitOnFHIR`）：权限、采集、FHIR 映射
  - Scheduler（`SpeziScheduler`/`SpeziSchedulerUI`）：任务定义、日程视图、事件交互
  - Questionnaire（`SpeziQuestionnaire`）：FHIR 问卷展示与结果
  - Notifications（`SpeziNotifications`）：本地提醒
  - Firebase（`SpeziFirestore`/`SpeziFirebaseStorage`）：数据写入与存储
  - Bluetooth/Devices（`SpeziBluetooth`、`SpeziDevices`）：蓝牙与设备抽象（当前占位）
  - LLM（`SpeziLLM`/`SpeziLLMOpenAI` 可选）：当前 Chat Demo 走直连 API，已条件编译兜底
- 应用标准（Standard）
  - `S2YApplicationStandard`：
    - HealthKit 新样本/删除事件的处理与 Firebase 同步
    - 问卷回答存储（按问卷维度建集合）
  - `S2YApplicationScheduler`：
    - 任务定义（示例：每日问卷）与上下文属性

## 4. 配置与环境
- Info.plist：
  - `NSBluetoothAlwaysUsageDescription`、`NSBluetoothPeripheralUsageDescription`
  - 如集成 Cloudflare LLM Gateway：`CFWorkersAI.GatewayURL`、`CFWorkersAI.ModelPath`、`CFWorkersAI.BearerToken`
- Firebase：
  - `S2Y/Supporting Files/GoogleService-Info.plist`（确保 Bundle ID = `us.s2y.s2y-ios`）
- 运行参数（`FeatureFlags.swift`）：
  - `--disableFirebase` 关闭 Firebase
  - `--useFirebaseEmulator` 显式启用 Emulator（默认关闭）
  - `--setupTestAccount` 自动创建/登录测试账号
- Fastlane：`fastlane/Fastfile`
  - `deploy` lane（staging → TestFlight、production → App Store）

## 5. 数据与权限
- HealthKit：授权后采集步数、心率等 → 本地处理/上传 FHIR 资源
- Firebase：用户文档 `users/{accountId}` 以及问卷/观测数据集合
- 隐私与安全：Keychain 保存令牌；最小化数据上传

## 6. LLM 聊天
- `LLMChatDemoView`：全屏消息 + 输入；Cloudflare/OpenAI；Keychain 持久化
- 规划：LLM Provider 抽象、函数调用、提示模板管理、HealthKit 工具对接

## 7. 蓝牙与设备
- 依赖与权限已就绪；未实现扫描/连接/读写 UI
- 规划：扫描列表 → 连接 → GATT 读写/通知；与 `SpeziDevices` 插件打通

## 8. 构建与发布
- 本地：Xcode 运行（默认直连生产 Firebase）
- TestFlight：`bundle exec fastlane ios deploy environment:staging appidentifier:us.s2y.s2y-ios provisioningProfile:"<AppStore Profile>"`

## 9. 可观测性
- ViewState/Alert 提示；关键链路日志；失败回退

## 10. 依赖矩阵
- iOS 18+ / Xcode 16+
- Spezi 模块、Firebase、可选 LLM Provider

## 11. 风险与边界
- LLM 合规（不做医疗诊断/处方）；UI 明示
- 版本兼容：`SpeziOnboarding ≥ 2.0.2`
