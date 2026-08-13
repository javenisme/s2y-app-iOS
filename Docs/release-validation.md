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

## 2026-08-13 生产认证读取验证

| 检查 | 结果 | 证据边界 |
|---|---|---|
| Omer 主线 | 通过 | 统一权限/用量与 Home 认证兼容改动已由 Omer PR #8～#10 合并；质量整理由 PR #12 合并，当前 `main` 为 `b41323c` |
| Omer Production | 通过 | Vercel Production 为 Ready，`chat.s2y.us` 指向该最新部署；未记录部署 ID 或环境变量值 |
| 已认证读取 | 通过 | 部署后刷新既有生产对话成功，历史用户问题与 Omer 回复可见，页面控制台无错误 |
| Home 登录入口 | 通过 | `www.s2y.us/auth/login` 展示 Google、邮箱登录入口，Firebase 配置不再显示 incomplete/internal-error，页面控制台无错误 |
| 新消息与计费 | 未验证 | 本轮未新增生产聊天记录；不能据此声称 token 账本、订阅映射或写入幂等已通过 |
| 同意与数据生命周期 | 未验证 | 尚需测试账号逐范围 grant/revoke，并用脱敏服务端证据确认停止新增与删除行为 |

验证没有读取浏览器 cookie、local storage、Firebase ID Token、数据库内容或环境变量值，
也没有把个人健康数据或聊天正文复制进本记录。

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
