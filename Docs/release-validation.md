# S2Y iOS 发布验收记录

本记录只保存可公开、可复核的结果，不保存账号、Team ID、证书指纹、profile 内容、
Firebase ID Token、健康数据或聊天正文。仓库检查通过不等于 App Store/TestFlight 已通过。

## 2026-08-13 基线

| Gate | 状态 | 已验证事实 | 尚缺证据 |
|---|---|---|---|
| 仓库配置 | 通过 | Bundle ID、Firebase 项目、Omer 生产域名一致；未引用废弃 `chat-bak.s2y.us` | 无 |
| 公开生产端点 | 通过 | 登录页可达；Omer mobile API 拒绝未认证请求 | 登录后 Firebase/Omer 链路 |
| iOS 工程 | 通过 | 完整 `S2YTests`、模拟器 build 和 build-for-testing 通过 | 签名真机 UI 遍历 |
| 静态质量 | 增量通过 | 10 条已知问题已修复；493 条历史债务进入版本化 SwiftLint baseline；新增问题仍失败 | 分批消减历史 baseline |
| 签名 Archive | 阻塞 | 工程 Bundle ID、entitlements、自动签名设置可读取；存在有效 Apple Development identity | Xcode 账户凭据不可用；profile 缺少 Verifiable Health Records 能力 |
| 合资格 iPhone | 未开始 | 本次检查没有发现已连接设备 | US-202 全部真机证据 |
| 真实 S2Y 设备 | 未开始 | 无真实硬件证据 | US-203 握手、停止与审计证据 |
| TestFlight/App Store | 未开始 | 未上传构建 | 分发、安装、回滚与审核证据 |

## 签名阻塞的正确处理

1. 在 Xcode Accounts 中重新登录具备该 App 权限的 Apple Developer 账户。
2. 在 Apple Developer 的 App ID/团队能力中取得 HealthKit Access（Verifiable Health Records）资格。
3. 重新生成包含 `health-records` entitlement 的 distribution provisioning profile。
4. 重新运行签名 Archive；不得通过删除临床记录 entitlement 来绕过。

## 每个候选版本必须记录

- Git commit、版本号、build number 和 UTC 时间；
- CI URL 及每个 required check 的最终结论；
- Archive 的 App ID、签名类型和 entitlement 验证结论（只写结论，不附 profile）；
- TestFlight 安装、启动、登录、Apple/Omer provider、权限撤回、删除与回滚结果；
- H28/H29 的机型/系统版本、固件版本和失败恢复结果；
- 生产 Omer/Firebase 使用测试账号产生的请求 ID 或脱敏时间戳。
