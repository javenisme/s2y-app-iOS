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
| 签名 Archive | 阻塞 | 工程 Bundle ID、entitlements、自动签名设置可读取；Xcode 已登录有效个人团队并存在 Apple Development identity | 个人团队不支持 HealthKit Access（Verifiable Health Records）；profile 缺少该能力 |
| 合资格 iPhone | 部分 | 已检测到 iPhone 16e（iOS 26.6），设备已配对且 Developer Mode 开启；设备标识未记录 | 签名安装、Apple Intelligence 开关/模型下载状态、端侧推理及 HealthKit 验收 |
| 真实 S2Y 设备 | 未开始 | 无真实硬件证据 | US-203 握手、停止与审计证据 |
| TestFlight/App Store | 延期 | 未上传构建；当前产品决定暂不外测 | 合资格团队签名、分发、安装、回滚与审核证据 |

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
| 同意与数据生命周期 | 最小授权 grant/revoke、策略版本强制门已在生产验证；删除实现已部署，正文生命周期待验收 | OMR-017～025 已部署；H54 从已登录 iOS 模拟器产生 `omerChatText` 授权并由 Omer 回查确认；H55 补齐移动端聊天数据库与 AI 记忆删除顺序及失败关闭；H59 移除缺少策略版本的旧客户端兼容路径。尚需验证撤回后健康正文停止新增和真实账号删除行为 |

验证没有读取浏览器 cookie、local storage、Firebase ID Token、数据库内容或环境变量值，
也没有把个人健康数据或聊天正文复制进本记录。

## 2026-08-13 当前目标收口

- HLT-177 对账当前路线图、Epic、开放 Issues 与已合并 PR。用户故事与 Epic 的仓库实现、
  自动化验证和已有生产安全切换已完成当前目标范围；没有未合并的实现 PR。
- Issue #3 保留撤回后停止新增和真实账号删除的生产证据；Issue #7 保留延期的 TestFlight
  证据。二者调整为非阻塞外部验收，不再阻止当前 goal 完成，也没有被错误关闭。
- 真机 Apple AI/HealthKit 仍需支持 Verifiable Health Records 的合资格 Apple 团队；真实
  S2Y 设备闭环仍需硬件。没有删除 entitlement、伪造设备结果或绕过签名能力。
- 本次收口不执行真实数据删除，不读取凭据、健康数据、聊天正文或数据库业务行。后续若
  执行不可逆云端删除，必须在操作时取得明确确认。

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
- H54 使用已登录 iOS 模拟器和同一 Firebase 身份执行最小 `omerChatText` grant/revoke：
  开启时 iOS 从 Omer 回查为 `Confirmed`；撤销后六项均关闭且空授权仍为 `Confirmed`；
  最后恢复用户明确选择的最小范围，其余五项保持关闭。
- 本次没有发送聊天正文或健康上下文，也未读取账号凭据、Firebase ID Token、数据库业务
  行或回执标识。本节仍不证明撤回后健康正文停止新增、云端历史删除或旧客户端强制门，
  US-201 继续保持外部验收状态。

## 2026-08-13 iOS 跨端同意确认

- HLT-171 增加已认证的 `GET /api/mobile/v1/consents` 回查，并忽略服务端未来新增的未知
  范围，避免客户端因协议向前演进而无法确认现有授权。
- HLT-172 在 Health Assistant 隐私设置展示 Checking、Confirmed 或 Pending；切换后先
  同步版本化回执，再回查 Omer，失败时保留本机选择并明确提示云确认待完成。
- 相关 5 项模型与状态测试通过；带本地签名和模拟器 entitlement 的 Debug 构建成功，
  覆盖安装后保留既有登录状态。
- 生产运行验收确认最小授权开启、撤销为空、恢复开启三个状态均获 Omer `Confirmed`；
  其他健康摘要、临床记录、导入文档、问卷备份和问卷摘要范围始终关闭。

## 2026-08-13 Omer 云端聊天删除安全

- Omer PR #22 以 OMR-024 单一故事提交组成；Vercel Preview 成功后以普通权限合并，
  Production 部署检查成功。
- 已认证移动端用户删除自己的聊天时，服务端先取得该聊天的消息标识并清理匹配的 Cognee
  AI 记忆，再删除数据库聊天；所有权校验发生在读取消息和删除之前。
- Cognee 清理不完整或抛错时返回 503，数据库聊天保持不变，允许后续重试；Cognee 未启用
  时维持原数据库删除行为。专项 6 项、完整 465 项单元测试通过，8 项数据库集成测试按
  默认配置跳过；TypeScript 与改动文件格式检查通过。
- 部署后使用不存在的聊天标识进行匿名 `DELETE` 烟测，Production 返回 401 并要求
  Firebase Bearer ID Token，证明路由仍失败关闭。没有读取或删除任何既有生产聊天、
  健康正文、凭据或数据库业务行，因此真实账号删除和撤回后停止新增仍属于 US-201 验收。

## 2026-08-13 跨平台发布预检

- HLT-175 定位最近连续失败的 Deployment：Ubuntu `releaseconfiguration` job 在调用仅
  macOS 提供的 `plutil` 时退出，尚未进入构建、签名或 TestFlight 阶段。
- 隐私清单校验改用 Python 标准库 `plistlib`，保持无追踪、精确数据类型、数据关联状态和
  Required Reason API 的原失败关闭规则；错误只报告配置类别，不打印清单内容或凭据。
- 7 项正反向测试覆盖已审核清单、追踪开启、未知/缺失数据类型、错误 Required Reason、
  缺失 API 类型和畸形 plist；完整发布配置预检与差异检查通过。
- GitHub 只读元数据确认仓库与 `staging` 环境没有发布密钥或变量，`production` 环境尚未
  建立。本主题不创建环境、不写入凭据，也不宣称 Archive 或 TestFlight 已可用。

## 2026-08-13 同意策略强制切换

- HLT-176 采用两阶段发布，避免直接收紧 Omer 导致仍在使用中的 Web 客户端中断：Home
  PR #27（HOME-005）先在已认证聊天请求中发送当前策略版本，Vercel Preview 与
  Production 均成功；随后 Omer PR #23（OMR-025）以普通权限合并并部署到 Production。
- Omer 的移动聊天和端侧对话同步现在都要求当前策略版本；缺少或过期版本返回 400。
  授权范围检查不再是可选路径，并分别发生在计费与模型调用前、数据库写入前。
- Omer 的改动文件格式、TypeScript、32 项专项测试与完整测试均通过；完整结果为 469 项
  通过、8 项数据库集成测试按默认配置跳过。Production 对两个匿名端点的烟测均返回 401，
  证明认证边界仍优先失败关闭。
- iOS 主线此前已发送当前策略版本。本次未读取身份令牌、浏览器凭据、健康数据、聊天正文
  或数据库业务行，也未以真实账号尝试缺少版本的请求；该行为由已认证单元测试覆盖。
- 这完成旧客户端强制门，不证明撤回后健康正文停止新增或真实账号云端删除；这两项继续
  留在 US-201。TestFlight 按当前产品决定延期，不作为本主题的发布门槛。

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

## 2026-08-13 Omer 账号健康分享控制

- Omer PR #20 由 OMR-020～022 三个独立故事提交组成，Vercel Preview 成功后以普通权限
  合并并进入 Production。
- 已认证普通账号可在 Settings 查看当前策略版本和友好范围名称；页面不展示回执 ID、时间、
  健康内容或聊天正文。新授权只能在 iOS 发起，Web 端不能扩大数据范围。
- 统一撤回要求同源请求与二次确认，写入当前策略的完整空授权快照；它阻止后续受保护写入，
  不暗示已存数据已删除。匿名与 guest 账号失败关闭。
- 路由、组件和完整单元测试共 461 项通过，8 项数据库集成测试按默认配置跳过；TypeScript、
  改动文件格式与 Vercel Production build 通过。
- 本节只证明控制面代码和部署；生产账号当时的权限读取仍因同意账本缺失返回 503，根因与
  修复记录在后续 HLT-160，不能把本节误记为已完成生产撤回。

## 2026-08-13 Omer 同意账本生产恢复

- 只读数据库元数据检查确认 Production 缺少 `UserConsent` 表；Drizzle 快照包含该表，
  但历史 SQL 迁移从未创建它。这是账号权限读取 503 和移动端回执无法持久化的根因。
- Omer PR #21 以 OMR-023 单一故事提交组成；新增幂等建表与外键迁移及回归测试，Vercel
  Preview 成功后以普通权限合并。Production 构建执行迁移并进入 Ready，`chat.s2y.us`
  已指向该部署。
- 专项 8 项与完整 462 项单元测试通过，8 项数据库集成测试按默认配置跳过；TypeScript、
  Drizzle 一致性、Biome 与差异检查通过。
- 部署后，既有已认证账号的 Settings 权限读取由 503 恢复为成功，并展示当前策略下无
  有效授权；刷新后结果保持一致。这证明表已建立、读取链路和默认拒绝生效。
- 当前账号没有既有授权，因此没有执行统一撤回，也没有绕过 iOS 直接插入授权。未读取
  浏览器 token、cookie、数据库业务行、健康数据或聊天正文；实际授权后的停止新增与删除
  仍属于 US-201 外部验收。

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
- 测试启动日志显示无签名模拟器 App 没有 Keychain entitlement；测试未因此失败。通知后台模式与
  Spezi 调度声明的两项真实工程缺口已由后续 H43 修复，不可将模拟器结果当作真机签名或推送验收通过。
- PR #69、#70 的 SwiftLint 与 REUSE 检查成功；依赖自托管执行器的 Build、CodeQL、
  Periphery、DocC 和链接检查仍处于 queued，未将排队状态记录为通过或代码失败。

## 2026-08-13 通知运行时配置验收

- HLT-154 在应用声明中补齐 `remote-notification` 后台模式，使既有远程通知回调与系统能力一致；
  同时允许 Spezi Scheduler 使用其固定后台刷新任务标识，避免启用 `fetch` 后注册被系统拒绝。
- 新增 2 项运行时配置回归测试，直接读取构建后的 App 信息声明；专项测试 2 项、0 失败。
- 完整 `S2YTests` 实际运行通过：159 项 XCTest 与 6 项 Swift Testing，共 165 项、0 失败；
  `build-for-testing`、Info.plist 语法和完整 SwiftLint（124 个 Swift 文件、0 违规）通过。
- 修复后的测试启动日志不再出现远程通知后台模式或 Spezi 调度任务未声明警告。仍存在的
  Keychain entitlement 提示来自 `CODE_SIGNING_ALLOWED=NO` 的隔离模拟器构建，不代表签名真机验收。
- 本主题只修复声明与回归保护，不证明 APNs 生产送达、后台唤醒时限、签名或 TestFlight 行为。

## 2026-08-13 发布元数据完整性验收

- HLT-156 将主屏显示名从上游模板名 `Spezi` 改为产品名 `S2Y`，不改变底层 Spezi 框架依赖。
- HLT-157 替换相机、位置、麦克风、运动和语音识别的模板占位权限说明；语音输入明确由用户选择，
  ResearchKit 问卷能力明确只在用户选择对应任务时使用，不在弹窗中暗示默认采集。
- 新增 2 项构建产物回归测试，校验产品显示名、六项敏感权限说明均为 S2Y 文案且不含模板提示；
  专项测试 2 项、0 失败。
- 完整 `S2YTests` 实际运行通过：161 项 XCTest 与 6 项 Swift Testing，共 167 项、0 失败；
  `build-for-testing`、Info.plist 语法和完整 SwiftLint（125 个 Swift 文件、0 违规）通过。
- 本主题不证明 ResearchKit 的所有可选任务已投入产品，也不扩大采集范围；App Store 权限申报、
  本地化权限文案、签名 Archive 与 TestFlight 弹窗仍须在发布渠道验收。

## 2026-08-13 账户入口产品化验收

- iPhone 16e 模拟器的实际账户页截图发现仍展示 “Template Application” 和 Firebase
  模块演示说明；该问题不属于框架依赖名称，而是直接面向用户的遗留产品文案。
- HLT-161 将账户副标题改为 S2Y Health Assistant 与 Omer Online 的真实用途，登录说明
  不再描述示例应用；同时补齐账户标题、未登录说明和已登录说明的简体中文。
- 新增账户中英文回归断言，并明确阻止 `template`/`module` 再进入英文副标题。专项本地化
  测试 3 项、0 失败；完整 `S2YTests` 为 162 项 XCTest 与 6 项 Swift Testing，共
  168 项、0 失败；带本地签名的模拟器构建成功并启动到 Health Assistant。
- Mac 锁定期间无法重新导航到账户页进行修复后截图，因此当前证据证明编译产物、自动化测试
  和 App 启动，不声称登录操作已完成。Firebase 登录及生产同意授权继续属于 US-201。

## 2026-08-13 产品入口与公开支持面验收

- HLT-162 将引导从模板功能陈列改为 Apple Health、Apple/Omer AI 处理选择、账户同步与
  健康管理边界；分享默认关闭，登录不等于授权健康数据分享，且不作诊断或治疗宣称。
- HLT-163 将 About、账户和设置中的项目、问题反馈、隐私政策、服务条款及消费者健康数据
  隐私入口统一到当前 S2Y 网站和代码库；发布前以网络请求确认六个产品/支持链接均返回 200。
- 引导关键文案提供英文、德文、瑞典文和简体中文；自动化测试保护引导边界、公开链接 HTTPS
  与 S2Y/GitHub 域名。完整 `S2YTests` 为 164 项 XCTest 与 6 项 Swift Testing，共
  170 项、0 失败；带本地签名的模拟器构建成功并启动。
- 代码库仍保留未挂载的 Stanford 示例联系人、仅用于预览的示例身份，以及作为 FHIR
  标识符使用的 Stanford 命名空间；它们不属于当前用户入口。后续清理不得直接改写 FHIR
  标识符，必须先完成数据兼容性评估。
- Mac 锁定使本轮无法人工逐页截图或执行 Firebase 登录、iOS 同意授权与 Omer 撤回闭环；
  因此本主题只证明代码、链接、测试和应用启动，不把生产认证或真实健康分享标记为通过。

## 2026-08-13 权威 Backlog 对账

- HLT-165 逐项审计 17 个开放 iOS Issues 和 5 个跨仓库旧 PR，不以标题相似或代码搜索
  代替验收；每项均映射到当前用户故事、Epic 或明确外部门槛。
- 12 个旧 Issues 的原始目标已交付或被更安全的 S2Y 方案取代；Firebase、每日问卷、
  TestFlight、问卷体验和周期报告 5 项因证据不足继续开放。
- iOS #21、#22、#28，Omer #2 与 Home #14 已被当前产品结构、版本化 API、同意门、
  生产内容边界或后续回归证据取代，可关闭但不可描述为生产外部验收完成。
- 对账只修复项目状态与可追溯性，不发送健康/聊天数据，不读取密钥或账号 token，也不
  解除 US-201～204 的生产、签名、真机和真实设备门槛。

## 2026-08-13 公开链接编译热修

- H49 为消除隐私链接强制解包引入的 URL 常量通过 SwiftLint，但当前 Swift 工具链不支持
  该字符串字面量转换；依赖自托管执行器的 Build 仍排队，因而在本地完整构建中才暴露。
- HLT-166 改用可编译且无强制解包的 URL 构造，公开地址不变；专项测试 1 项通过，带本地
  签名的模拟器构建成功。PR #78 在 SwiftLint 与 REUSE 通过后普通合并。
- 此热修说明静态检查不能替代编译；后续主题在合并前继续要求本地签名模拟器构建。

## 2026-08-13 每日问卷可靠闭环验收

- HLT-167 在 Schedule 工具栏提供明确的“每日记录历史”入口；历史只显示受保护的最小化
  本机摘要，并保留既有清除与本地/云端边界说明。
- HLT-168 让可选账户备份错误回传到 UI：本地保存与任务完成不因云失败而丢失，用户可
  重试账户备份或明确选择仅保留此 iPhone 副本；重试不会为同一 snapshot 生成重复记录。
- HLT-169 为入口、恢复标题、操作与说明补齐简体中文，并记录自动化证据。完整
  `S2YTests` 为 165 项 XCTest 与 6 项 Swift Testing，共 171 项、0 失败；带本地签名的
  模拟器构建成功。
- Mac 锁定期间未人工完成一份真实问卷或强制制造 Firebase 网络失败，因此运行证据覆盖
  编译、持久化幂等、全量测试和启动，不声称生产 Firestore 备份已实际成功。

## 2026-08-13 本地 Backlog 收口

- HLT-170 复核旧 Issue #15 的四个混合目标：用户自选目标由 H23 交付，周复盘由 H05
  交付，7/30/90 天本地 PDF 由 H30 交付，订阅权限与失败关闭映射由 H41 交付。
- “月报”以用户主动生成的 30 天摘要实现，不新增后台自动健康报告或默认上传；这与当前
  用户控制和最小化分享边界一致。
- Production 缺少 Stripe 服务端密钥、Webhook 与价格映射的事实不被旧 iOS 工单掩盖，
  继续归入 US-201；关闭 #15 不代表付费购买已可用。
- 对账后 iOS GitHub 仅保留 #3 Firebase 生产连通性与 #7 TestFlight 两个外部门槛工单。

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
