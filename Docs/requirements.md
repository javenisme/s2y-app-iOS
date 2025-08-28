# S2Y 需求文档（Requirements）

- 版本：v0.1
- 最近更新：2025-08-28
- 参考：Docs/epic-health-assistant.md

## 1. 业务目标
- 提升用户对自身健康数据的理解与行动力
- 打造智能健康助手体验（对话式查询 + 洞察 + 目标）

## 2. 用户与场景
- 用户：关注运动/睡眠/心率的普通用户
- 场景：
  - 查询近 7/30 天步数、心率、睡眠趋势
  - 获取解释、建议与可执行微目标
  - 每日问卷与提醒，形成习惯闭环

## 3. 关键功能
- 账号与身份管理（Email/Password、Sign in with Apple）
- HealthKit 数据接入与本地展示；FHIR 映射与（可选）上传
- 调度（每日任务、问卷、通知）
- 问卷：社会支持量表示例（FHIR Questionnaire）
- LLM 聊天：通用问答（后续接入健康数据工具）
- 设置（Showcase）：模块演示与快捷入口

## 4. 非功能性需求
- 隐私：最小化上传、Keychain 存储敏感
- 可靠性：关键链路错误处理与降级
- 性能：LLM P95 ≤ 5s；页面切换/数据加载流畅
- 可运维：Fastlane 发布、崩溃/日志可追踪（后续）

## 5. 数据与权限
- HealthKit（步数、心率等）：显式授权、可撤销
- 通知（本地）：提醒任务
- 蓝牙：后续设备对接预留
- Firebase：Auth/Firestore/Storage（可选 Emulator/生产）

## 6. 平台与兼容
- iOS 18+；Xcode 16+
- SpeziOnboarding 2.x；与 SpeziLLM 版本兼容

## 7. 验收标准（首版）
- 登录/注册成功；问卷展示与提交成功
- 日程页展示每日任务；通知可触达
- LLM 聊天可流畅往返，错误可读
- Fastlane 可投递 TestFlight

## 8. 风险与依赖
- LLM 合规风险（不做诊断与处方）
- Firebase 项目与 Bundle ID 对齐
- Spezi 包版本兼容
