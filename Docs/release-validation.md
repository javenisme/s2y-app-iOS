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
| 合资格 iPhone | 部分 | 已检测到 iPhone 16e（iOS 26.6），设备已配对且 Developer Mode 开启；设备标识未记录 | 签名安装、Apple Intelligence 开关/模型下载状态、端侧推理及 HealthKit 验收 |
| 真实 S2Y 设备 | 未开始 | 无真实硬件证据 | US-203 握手、停止与审计证据 |
| TestFlight/App Store | 未开始 | 未上传构建 | 分发、安装、回滚与审核证据 |

## 2026-08-13 生产认证读取验证

| 检查 | 结果 | 证据边界 |
|---|---|---|
| Omer 主线 | 通过 | 统一权限/用量与 Home 认证兼容改动已由 Omer PR #8～#10 合并；质量整理由 PR #12 合并；运行时健康管理边界由 PR #13 合并；公开产品文案边界由 PR #14 合并 |
| Omer Production | 通过 | Vercel Production 为 Ready，`chat.s2y.us` 指向 PR #14 的最新 `main` 部署；未记录部署 ID 或环境变量值 |
| 已认证读取 | 通过 | 部署后刷新既有生产对话成功，历史用户问题与 Omer 回复可见，页面控制台无错误 |
| 健康管理边界 | 通过 | 生产版本不再从问卷自动生成 tVNS 参数、运动处方、补充剂剂量或诊断表型；历史计划读取时过滤设备、药物与剂量内容 |
| Home 登录入口 | 通过 | `www.s2y.us/auth/login` 展示 Google、邮箱登录入口，Firebase 配置不再显示 incomplete/internal-error，页面控制台无错误 |
| Home 公开边界 | 通过 | Home PR #25、#26 已正常合并；生产首页、Omer、StVNS、企业与复核页均采用健康教育/用户控制措辞，旧高风险文章不再公开 |
| 新消息与计费 | 部分通过 | 已登录测试账号的最小非健康消息及 AI 回复可读取；Omer PR #15 部署后，订阅状态接口的 Free 用量由 0 增长为正数且剩余额度同步减少；未读取数据库明细，付费档位仍未验收 |
| 付费订阅映射 | 代码通过，生产阻塞 | OMR-019 已部署并失败关闭冲突用户映射、多价格项、异常数量与未知计划；Production 缺少 Stripe 密钥、订阅 Webhook 密钥和四个价格映射，本地密钥已失效 |
| 同意与数据生命周期 | 代码门已通过，生产行为待验收 | OMR-017～018 已部署；新版请求缺少范围授权时会在模型、计费或会话写入前拒绝。尚需测试账号逐范围 grant/revoke，并用脱敏服务端证据确认生产停止新增与删除行为 |

验证没有读取浏览器 cookie、local storage、Firebase ID Token、数据库内容或环境变量值，
也没有把个人健康数据或聊天正文复制进本记录。

## 2026-08-13 Omer 用量账本生产验证

- Omer PR #15 以 OMR-015 单一故事提交组成；Vercel Preview 成功后以普通权限合并，
  Production 为 Ready，`chat.s2y.us` 已指向该部署。
- 网关提供非零计数时保持其结果；缺失或为零时，服务端仅用请求/回复字节数估算保守的
  非零用量。回退文本只参与内存计算，不写入用量账本。
- 改动文件格式、TypeScript 与 440 项单元测试通过，8 项显式数据库集成测试按默认配置
  跳过。webpack 构建编译成功后，被主线已有的 Pricing 页面额外导出类型错误阻塞；
  Vercel 生产构建通过，因此未绕过检查。
- 部署前，已认证 Free 测试账号的用量聚合为 0。部署后发送一条最小非健康消息并收到
  回复，接口显示用量变为正数、剩余额度相应下降，证明生产聚合账本已实际移动。
- 本次没有读取数据库行、浏览器凭据、环境变量、健康数据或既有聊天正文；该证据不证明
  付费订阅映射、逐范围同意撤回或删除生命周期。

## 2026-08-13 跨端健康分享同意回执

- Omer PR #17（OMR-017）和 PR #18（OMR-018）均在 Vercel Preview 成功后以普通权限
  合并并进入 Production。生产 `GET/POST /api/mobile/v1/consents` 对未认证请求均返回
  401；该 smoke check 只证明路由存在且拒绝匿名访问。
- 服务端只保存策略版本、范围、授予/撤销状态、回执 ID 与时间，不在同意账本中保存
  健康数据或聊天正文。回执以完整授权快照对账，因此设备长期离线并裁剪旧回执后仍能
  恢复当前状态，重复上传由确定性行 ID 去重。
- 携带当前策略版本的在线聊天会在计费及模型调用前验证 `omerChatText` 和实际健康上下文
  范围；端侧对话同步会在数据库写入前验证 `onDeviceConversationSync`。缺少授权返回
  `CONSENT_REQUIRED`；旧版客户端暂时保持迁移兼容，后续发布覆盖后再收紧。
- OMR-017 完整测试为 449 项通过、8 项按默认配置跳过；OMR-018 为 450 项通过、8 项
  跳过。两次 TypeScript、格式检查与 Production build 均通过。
- iOS HLT-150 已把本地版本化回执按时间顺序同步至 Omer，请求携带策略版本；设置撤回
  本地立即生效，云确认失败会保留回执供重试。模拟器 `build-for-testing` 与完整
  SwiftLint 基线检查通过；后续 H42 使用独立无头模拟器解决图形会话的 worker 阻塞，
  H40 四项专项测试与完整 `S2YTests` 均已实际运行通过。
- 尚未使用生产测试账号读取数据库或执行逐范围 grant/revoke；本节不证明生产数据库
  状态变化、云端历史删除或旧客户端强制门，US-201 继续保持外部验收状态。

## 2026-08-13 Omer 订阅权限映射安全

- Omer PR #19 以 OMR-019 单一故事提交组成，Vercel Preview 成功后以普通权限合并，
  Production 部署检查成功。
- Webhook 现在要求订阅元数据、Checkout 与已有记录指向同一用户；冲突时返回处理失败并
  由 Stripe 重试，不会把权限授予另一账户。每个订阅只允许一个价格项且数量必须为 1。
- 数据库出现未定义计划时，AI 权限降级到 Free，不再通过类型断言构造未定义配额。
- 完整单元测试 454 项通过，8 项数据库集成测试按默认配置跳过；TypeScript、改动文件
  格式检查与 Production build 均通过。
- 只读配置检查确认 Vercel Production 尚无 `STRIPE_SECRET_KEY`、订阅 Webhook 密钥及
  Basic/Pro 月付和年付四个价格映射；本地 Stripe 密钥认证也已失效。因此未读取 Stripe
  产品、价格或 Webhook，未创建外部资源，生产 Checkout/升级/降级仍未验收。

## 2026-08-13 隔离模拟器运行验收

- 新建并启动一个临时 iOS 26.2、iPhone 16e 无头模拟器，避开已有图形模拟器会话导致的
  “waiting for workers to materialize”。该临时设备不使用真机数据、Apple 账户或生产凭据。
- H40 四项契约测试全部运行通过：在线聊天请求策略版本、端侧会话同步策略版本、Omer
  同意回执编码、统一撤回回执；共 4 项、0 失败。
- 完整 `S2YTests` 实际运行通过：157 项 XCTest 与 6 项 Swift Testing，共 163 项、
  0 失败。结果不再只是 `build-for-testing` 编译证据。
- Debug 模拟器 App 安装并启动成功；等待初始化后进入 S2Y Health Assistant onboarding。
  该 smoke check 证明应用可启动，不证明 Firebase 登录、HealthKit 真机数据或 Apple
  Foundation Models 端侧推理。
- 测试启动日志仍显示模拟器没有 Keychain entitlement、通知后台模式及 Spezi 调度声明；
  测试未因此失败。这些属于模拟器/应用配置提示，不可当作真机签名或推送验收通过。
- PR #69、#70 的 SwiftLint 与 REUSE 检查成功；依赖自托管执行器的 Build、CodeQL、
  Periphery、DocC 和链接检查仍处于 queued，未将排队状态记录为通过或代码失败。

## 2026-08-13 Omer 健康管理安全验证

- Omer PR #13 以 7 个独立故事提交合并，Vercel Preview 检查通过后正常进入
  Production，未绕过检查。
- Omer 完整单元测试为 431 项通过；8 项需要隔离 PostgreSQL 的测试明确归类为
  数据库集成测试，默认单元测试不会连接本机或生产数据库。
- TypeScript 检查、Next.js Production build、改动文件格式检查和敏感信息模式扫描通过。
- 生产 `chat.s2y.us` 已指向该合并部署；既有已认证会话可读取，页面控制台无错误。
- 本次验证未发送新消息，因此不构成新写入、token 账本、订阅映射或同意撤回证据。

## 2026-08-13 Omer 公开健康管理边界验证

- Omer PR #14 以 OMR-012～014 三个独立故事提交合并，Vercel Preview 通过后正常
  进入 Production，未绕过检查。
- 定价页、能力目录、站点标题、SEO/分享元数据、页脚和设置页均已移除公开的
  “Digital Therapy”、诊断、治疗、运动处方、补充剂剂量及 tVNS 参数承诺。
- 完整单元测试 438 项通过，8 项数据库集成测试按显式开关跳过；TypeScript、纯
  Next.js Production build、改动文件格式和敏感信息模式扫描通过。
- 生产浏览器复验确认 `chat.s2y.us` 标题为 Health Management Platform，定价页明确
  非诊断/非治疗边界，能力目录不再展示四个运行时禁用工具。
- 既有最小非健康测试对话证明生产写入、AI 回复和刷新后读取；订阅状态接口返回 200。
  未读取环境变量、Firebase token、数据库内容或 token 账本明细。

## 2026-08-13 Home 公开健康管理边界验证

- Home PR #25 由 HOME-001～003 三个独立故事提交组成，PR #26 由生产浏览器补漏发现的
  HOME-004 组成；两者均在 Vercel Preview 成功后以普通权限合并，未使用管理员绕过。
- 首页、多语言入口、Omer、StVNS、企业、移动端、HOCl、使命和案例页面已移除未经
  证明的疗效百分比、康复故事、零幻觉、自动调参、监管认证、隐私合规及产品性能承诺。
- 14 篇包含设备治疗、HOCl 疗法或监管状态宣称的旧文章已设为草稿；POTS、RTM 和
  案例页在来源、同意与合规复核完成前不进入搜索索引。
- 公开宣称回归检查、国际化审计、目标文件 ESLint 与 Astro 类型检查通过；Astro 为
  0 错误，保留的提示属于既有工程债务。
- Production 构建为 Ready；Cloudflare Pages 成功后，内建浏览器确认 `www.s2y.us`
  使用健康教育/用户控制标题，Omer、StVNS、企业及复核页均返回新版边界内容。
- 本次只验证公开内容与部署，不读取密钥、账号 token、健康数据、聊天正文、数据库或
  计费账本，也不构成 Firebase/Omer 同意撤回与删除证据。

## 签名阻塞的正确处理

1. 在 Xcode Accounts 中重新登录具备该 App 权限的 Apple Developer 账户。
2. 在 Apple Developer 的 App ID/团队能力中取得 HealthKit Access（Verifiable Health Records）资格。
3. 重新生成包含 `health-records` entitlement 的 distribution provisioning profile。
4. 重新运行签名 Archive；不得通过删除临床记录 entitlement 来绕过。

## 2026-08-13 真机安装尝试

- Mac 已通过 Xcode 工具链检测到一台运行 iOS 26.6 的真实 iPhone；记录中不保存
  UDID、设备名称或其他持久设备标识。
- Debug 真机构建首先被三个锁定版本 Spezi 依赖的宏信任门拦截；使用 Xcode 提供的
  `-skipMacroValidation` 后已越过该门，未修改依赖或工程源码。
- 随后构建在签名阶段按预期失败：Xcode 没有可用开发者账户，且现有 profile 不包含
  HealthKit Access（Verifiable Health Records）能力。
- 因 `.app` 未生成，尚未执行安装或启动；本次构建尝试本身不能判断该 iPhone 是否支持
  Apple Foundation Models。后续 HLT-147 只读确认硬件资格，US-202 与 US-204 仍待外部验证。

## 2026-08-13 合资格 iPhone 硬件证据

- Xcode `devicectl` 只读检测确认设备为 iPhone 16e、iOS 26.6，配对状态正常且
  Developer Mode 已开启；未记录 UDID、序列号、设备名称或其他持久标识。
- Apple 官方将 iPhone 16 系列列入 Apple Intelligence 支持范围；iPhone 16e 官方规格
  也明确支持 Apple Intelligence。参考 [Apple Intelligence 要求](https://support.apple.com/en-euro/121115)
  与 [iPhone 16e 技术规格](https://support.apple.com/en-us/122208)。
- 硬件资格不等于系统模型可用。Apple 要求运行时检查 `SystemLanguageModel.availability`；
  Apple Intelligence 未开启或模型尚未下载时仍会不可用。参考
  [Foundation Models 可用性说明](https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models)。
- 因签名 profile 仍缺失，尚未安装 App，也未读取设备上的 Apple Intelligence 设置；
  H28 只能记录“硬件资格已确认”，不能标记端侧 AI 验收完成。

## 每个候选版本必须记录

- Git commit、版本号、build number 和 UTC 时间；
- CI URL 及每个 required check 的最终结论；
- Archive 的 App ID、签名类型和 entitlement 验证结论（只写结论，不附 profile）；
- TestFlight 安装、启动、登录、Apple/Omer provider、权限撤回、删除与回滚结果；
- H28/H29 的机型/系统版本、固件版本和失败恢复结果；
- 生产 Omer/Firebase 使用测试账号产生的请求 ID 或脱敏时间戳。
