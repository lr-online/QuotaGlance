# AGENTS.md — QuotaGlance 协作准则

读者是接手本仓库的 AI agent。本文只写架构地图、不可违反的约束和可执行操作；
实现细节一律以代码和 `Contracts/README.md` 为准。HarmonyOS 端的专项说明见
`HarmonyOS/AGENTS.md`。

## 发布

当开发者要求发布、release、打 tag 或分发 QuotaGlance 时，先读取并遵循仓库中的
`skills/releasing-quotaglance/SKILL.md`。在开发者选定版本且再次明确批准前，不得创建
或推送 tag，也不得触发 GitHub Release。

## 项目一句话

macOS 菜单栏 + 桌面小组件应用，集中查看多个 AI API provider 的余额/配额；
HarmonyOS（ArkTS）端是同一套领域逻辑的镜像实现，双端通过 `Contracts/` 下的
共享 spec 与契约 fixture 防止行为漂移。

## 架构地图

仓库目录的目标归属、迁移期兼容策略和路径验证见
[`docs/repository-topology.md`](docs/repository-topology.md)。`Contracts/` 始终保留在
仓库顶层，是跨平台行为的权威源。

Swift 包：`Shared/SwiftCore/Package.swift`，核心库 `QuotaGlanceCore`（`Shared/SwiftCore/Sources/QuotaGlanceCore/`），按层分目录：

- `Domain/` — 纯领域模型：`Account`、`UsageSnapshot`、`Provider.swift`（`ProviderID`
  / `ProviderRegion` / `ProviderCredentialKind` / `ProviderProfile`）。无 I/O。
- `Providers/` — provider 层。`UsageProvider.swift` 定义收窄后的接口
  （`id` + `descriptor` + `detect(apiKey:)` + `fetch(apiKey:profile:)`）、
  `HTTPClient` 协议、`ProviderError` 错误枚举；`ProviderDescriptor.swift` 是静态
  元知识（displayName、低余额阈值支持、profile 描述）；`SpecDrivenProvider.swift`
  + `ProviderSpec.swift` 是通用 spec 引擎（**唯一**的 provider 实现，含 SpecEngine /
  SpecSnapshotAssembly / SpecDecimal）；`MiniMaxModelRemainsStrategy.swift` 是唯一的
  named parse strategy；`ProviderCatalog.swift` 从打包的 spec 资源装配全部 provider。
- `Refresh/` — `RefreshCoordinator`，按账户调度 detect/fetch、写入快照存储。
- `Aggregation/` — `SnapshotAggregator`，跨账户汇总（余额、今日指标、7 天窗口）。
- `Alerts/` — `AlertEvaluator`，低余额告警的批量评估与 episode 去抖。
- `Storage/` — Keychain（`KeychainStore`）、账户偏好、共享快照存储（App Group）。
- `Presentation/` — 菜单栏/Widget 展示模型、`L10n`、深链路由、错误文案。
- `Validation/` — `AccountValidator`，新增账户时的 key 校验编排。
- `Resources/ProviderSpecs/` — spec 副本（由 `scripts/sync-specs-to-core.sh` 从
  `Contracts/` 同步，**不要手改**）。

应用目标（xcodeproj，由 `project.yml` 生成）：

- `Platforms/macOS/App/` — macOS 菜单栏主应用（SwiftUI）。
- `Platforms/macOS/Widget/` — 桌面 Widget（WidgetKit，小/中/大）。
- `Platforms/macOS/NCWidget/` — 通知中心 Widget（macOS 12 兼容路径）。
- `Platforms/macOS/NCIntents/` — Widget 账户选择的 App Intent 共享代码。

HarmonyOS 镜像：`HarmonyOS/entry/src/main/ets/`，`providers/` 目录与 Swift
`Providers/` 一一对应，映射表和平台差异白名单见 `HarmonyOS/AGENTS.md`。

`Contracts/` — 双端共享契约的**权威源**：

- `Contracts/Providers/<provider>/spec.json` — provider 的数据驱动定义（schema 权威
  文档是 `Contracts/README.md` 的 "Provider spec schema" 一节）。
- `Contracts/Providers/<provider>/<case>-{response,expected,requests}.json` —
  解析三件套 fixture（多步流程加 `-response2.json`…）。
- `Contracts/Aggregation/`、`Contracts/Alerts/` — 聚合与告警的行为契约 fixture
  （input/expected 对）。

## 硬约束（不变量）

1. **`ProviderID` raw value append-only。** raw value 进入持久化（账户记录、Widget
   配置），已发布的值禁止改名、复用或删除；新增只能追加。双端声明点：Swift
   `Shared/SwiftCore/Sources/QuotaGlanceCore/Domain/Provider.swift`（enum + 显式覆盖的 `allCases`
   数组）与 ArkTS `HarmonyOS/entry/src/main/ets/providers/UsageProvider.ets`
   （union type + `ALL_PROVIDER_IDS`）。
2. **Contract-first。** 任何 provider 行为改动必须先改 spec/fixture，再改引擎；
   禁止绕过 spec 手写 provider 逻辑。spec 表达不了时的升级路径（按优先级，判定
   标准见 `Contracts/README.md` "When a hand-written adapter is allowed"）：
   ① named parse strategy（仅限响应形状复杂度，双端各实现一次、fixture 钉住）；
   ② 仅当*编排*本身不适配（非 GET、非静态 header 鉴权、分页、非 JSON 负载等）
   才允许全手写 provider——此时省略 spec.json 但 fixture 必须保留。为单个
   provider 扩 schema 是 anti-pattern；确需扩 schema 时，schema + README +
   双端引擎必须同改。
3. **四处副本的同步纪律。** `Contracts/` 是唯一权威源，改动后必须重跑：
   `bash scripts/sync-specs-to-core.sh`（→ `Shared/SwiftCore/Sources/QuotaGlanceCore/Resources/ProviderSpecs/`）、
   `bash scripts/sync-specs-to-harmonyos.sh`（→ `HarmonyOS/entry/src/main/resources/rawfile/providerspecs/`）、
   `bash scripts/sync-specs-to-android.sh`（→ Android 对应资源目录）、
   `bash scripts/sync-specs-to-windows.sh`（→ `Windows/src-tauri/assets/providerspecs/`）、
   `bash scripts/sync-contracts-to-harmonyos.sh`（→ `HarmonyOS/entry/src/ohosTest/resources/rawfile/contracts/`，
   同步 `Contracts/Providers/`、`Contracts/Aggregation/`、`Contracts/Alerts/`）、
   `bash scripts/sync-contracts-to-android.sh`（→ Android 对应测试资源目录）、
   `bash scripts/sync-contracts-to-windows.sh`（→ `Windows/src-tauri/assets/contracts/`）。随后
   `bash scripts/verify-provider-parity.sh` 必须全绿；该脚本还要求每个 provider fixture
   case 都在 ArkTS `CONTRACT_CASES` 中登记，且各 step URL 与 `*-requests.json`
   一致，并包含跨四端（Swift/ArkTS/Kotlin/Rust）的 ProviderID 与错误 token 同步校验。
   各平台单独的 parity 脚本：`bash scripts/verify-android-parity.sh`、
   `bash scripts/verify-windows-parity.sh`。同步产物禁止手改。
4. **双端语义镜像。** provider / 聚合 / 告警的行为改动必须双端对应提交；确实
   无法一致的，显式登记进 `HarmonyOS/AGENTS.md` 的平台差异白名单，不允许静默
   漂移。现状是 ArkTS 已镜像 provider / aggregation / alerts 引擎，并消费对应契约
   fixture；任何后续共享行为改动都必须双端一起改并附测试。Windows 端的 Rust
   镜像增加了 provider / aggregation / alerts 三引擎 + DPAPI 凭据存储 + 同名
   平台差异白名单（见 `Windows/AGENTS.md`），同样不允许在不更新合同与四端
   实现的情况下静默改动行为。
5. **错误 token 表是双端契约。** spec 只允许引用 `Contracts/README.md`
   "Error tokens" 一节列出的稳定 token；同一张表镜像在 ArkTS
   `UsageProvider.ets` 头注释与 Swift `ProviderError`（`UsageProvider.swift`）。
   新增/修改 token 必须三处同改。`httpStatus` 携带实际状态码（Swift
   `httpStatus(Int)`，ArkTS `"httpStatus:<code>"`）；`providerUnavailable` 与
   `network:<detail>` 是框架级错误，永不出现在 spec 中。
6. **新增平台必须做功能缺失检查。** 任何新增或大幅扩展平台支持的改动，都必须逐项
   对照下方“平台支持功能基线”，在任务/PR 说明中标记每项状态：已实现、平台不适用
   或已登记平台差异。平台不适用/差异必须写清原因、用户可见降级、测试覆盖和补齐计划；
   未完成该检查的改动不得视为平台支持完成。若平台没有菜单栏、Widget、后台刷新等同名
   宿主能力，必须提供等价入口/能力，或登记进对应平台 `AGENTS.md` 的差异白名单。

## 平台支持功能基线（新增平台对照清单）

新增平台不是“能跑 provider”即可完成；必须覆盖 QuotaGlance 的产品能力闭环。后续
agent 添加平台支持时，按本清单逐项检查功能缺失，除非明确登记为平台差异。

- **Provider / spec 契约**：支持完整 `ProviderID` 集合、provider displayName、
  credential kind、profile/region 描述、低余额阈值能力声明；从 `Contracts/Providers/`
  加载 spec，保持 detect/fetch 请求顺序、region fallback、fixed profile、named parse
  strategy、十进制/日期解析和 error token 映射与 Swift 核心一致。
- **账户与凭据生命周期**：支持账户列表排序、添加、编辑、删除、启用/停用、最多 20 个账户、
  display name 去空白与重复校验、API key 空值/替换校验、provider profile 探测与持久化、
  低余额阈值编辑；凭据必须进入平台安全存储，删除账户时同步清理凭据与快照。
- **用户偏好**：支持刷新间隔、开机/启动时自动运行的等价设置、首选语言（system / English /
  Chinese）、通知中心/小组件默认账户或平台等价的快速入口默认选择。
- **刷新与快照存储**：支持单账户刷新、全部账户刷新、启动/前台进入时刷新、按间隔刷新或平台
  等价调度；失败账户不得阻断其他账户刷新；持久化最新快照、失败原因、`receivedAt`、
  `capturedAt`、`lastSuccessAt`，失败时保留可展示的旧数据并标记 stale/unavailable/partial。
- **聚合与指标语义**：按 `SnapshotAggregator` 语义过滤 disabled 账户并按 `sortOrder` 排序；
  按币种汇总余额；仅在所有启用账户都有同币种今日花费时汇总 today cost；today requests 要有
  溢出保护；生成最近 7 天 daily usage；正确处理混合币种、缺失指标、stale/unavailable 与
  partial 状态。
- **账户级明细展示**：展示余额及 breakdown、spending limit、spend today/week/month/total、
  quota windows、today/total counters、daily usage、model usage、providerStatus、
  metricsUnavailableReason，并保留 provider 不提供某些字段时的空态/降级文案。
- **告警与通知**：实现低余额阈值批量评估、belowThreshold 状态、episode 去抖、恢复后重置；
  支持通知权限状态展示（未请求/未允许/已允许或平台等价）、本地通知发送、失败/不可用时不误报。
- **主界面与快速查看入口**：支持全账户概览和单账户详情；展示 empty/healthy/belowThreshold/
  partial/stale/unavailable 状态、主指标、今日请求、最近 7 天趋势、账户行、错误文案；
  macOS 的菜单栏、桌面 Widget、通知中心 Widget 在其他平台必须映射为该平台的等价快速查看入口，
  不支持时登记差异。
- **账户编辑与设置体验**：支持 provider 选择、名称、API key 粘贴/输入、启用开关、阈值、
  刷新间隔、语言、通知、默认快速入口账户、启动项等设置；错误信息必须走统一错误呈现和本地化。
- **深链路与选择解析**：支持 `quotaglance://all`、`quotaglance://account/<uuid>` 或平台等价
  路由；快速入口可选择全部账户、指定账户、使用应用默认账户；已删除账户选择必须降级到全账户。
- **本地化与格式化**：支持 English / Chinese 文案、系统语言解析、Money 大小写币种规范化、
  金额/数量格式化、日期展示和 provider profile 文案；新增文案不得只落单端。
- **平台工程与质量门禁**：新增平台必须有构建脚本/CI 路径、资源同步路径、契约 fixture 消费方式、
  provider parity 校验或等价检查；共享 provider / aggregation / alerts 行为改动必须附平台测试，
  无法自动化的 UI/通知/后台能力需记录人工验证步骤。

## Windows 端 baseline 状态（本次新增）

逐项对照上方 12 项：

| # | 能力 | 状态 | 备注 |
|---|---|---|---|
| 1 | Provider / spec 契约 | ✅ Implemented | Rust `domain.rs` + `providers/{spec_engine, spec_driven_provider, minimax_model_remains_strategy}` 镜像 Swift；`KNOWN_*` allow-list 与 Swift/Kotlin/ArkTS 对齐；`scripts/sync-specs-to-windows.sh` + `verify-windows-parity.sh` + `verify-provider-parity.sh` 四端守护 |
| 2 | 账户与凭据生命周期 | ✅ Implemented | `storage/account_store.rs` 20 上限 + 去空白/重复校验；DPAPI `credential_vault.rs` 加密 API key；删除账户级联清凭据 + 快照；API key 空值校验 |
| 3 | 用户偏好 | ✅ Implemented（+ 启动项差异） | `storage/preferences.rs`：interval 1/5/15/30/60、locale、notifications、launch_at_login opt-in、widget target。**启动项差异**：默认关闭，写 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` 等用户主动开启 |
| 4 | 刷新与快照存储 | ✅ Implemented | `refresh/refresh_coordinator.rs` 单/全部/间隔/启动/前台触发 + 失败隔离；`storage/snapshot_store.rs` per-UUID JSON + 失败保留 stale/unavailable 标记 |
| 5 | 聚合与指标语义 | ✅ Implemented | `aggregation/snapshot_aggregator.rs` 镜像 Swift；7 天窗口 + 货币求和 + Int64 溢出 isPartial |
| 6 | 账户级明细展示 | ✅ Implemented | React `AccountDetail.tsx` + breakdown + spend today/week/month/total + quota windows + daily/model + providerStatus + metricsUnavailableReason |
| 7 | 告警与通知 | ✅ Implemented | `alerts/alert_evaluator.rs` 镜像 + episode 去抖 + recovery reset；`tauri-plugin-notification` 发本地 Toast |
| 8 | 主界面 + Quick View | ✅ Implemented（+ Widget Board 差异） | 系统托盘 + popover + 主窗口 + widget 子进程。**Widget Board 差异**：v1 用 `WebviewWindow(label=widget)`；Win11 Widget Board App Identity 接入为 v2 待办 |
| 9 | 账户编辑与设置 | ✅ Implemented | `AccountEdit.tsx` + `Settings.tsx` 走 settings 与 command 桥 |
| 10 | 深链路 + 选择解析 | ✅ Implemented | `quotaglance://` scheme + `tauri-plugin-deep-link` + `tauri-plugin-single-instance` 锁进程；`getIntentPayload` 路由到前端 |
| 11 | 本地化与格式化 | ✅ Implemented | `src/i18n/{en,zh-CN}.json`；`resolveLocale` 跟随 navigator.language；Rust `Money.amount` 字符串序列化对齐 ArkTS canonical |
| 12 | 平台工程 + 质量门禁 | ✅ Implemented | `.github/workflows/windows.yml` 在 windows-latest 跑 sync → 跨端 verify-provider-parity.sh → verify-windows-parity.sh → cargo test → `cargo tauri build --bundles zip` + 上传 portable zip 产物；3 个新同步脚本加入常用命令 |

**未做（明确登记）**：
- 真实网络环境跑通 provider 端到端（本地 macOS/iOS runner 不存在，需要在 macOS 上手测；CI 只能跑单元/契约层）
- 桌面小组件首次启动后被 DWM 截获导致无法被拖动的极端情况 — Windows 11 / 10 行为差异，登记为差异 v2 待补
- Tauri 2 的 `tauri-plugin-clipboard-manager` 暂不接入（依赖 API key 复制场景），未来添加

## 新增一个 provider（操作清单）

1. **写 spec**：新建 `Contracts/Providers/<lowercased-id>/spec.json`（目录名 =
   `ProviderID` raw value 全小写），按 `Contracts/README.md` "Provider spec
   schema" 填写 `descriptor` / `credential` / `profiles` / `detect` / `fetch`。
   `spec.id` 用 camelCase raw value。
2. **写 fixture 三件套**：同目录 `<case>-response.json`、`<case>-expected.json`、
   `<case>-requests.json`（多步流程补 `-response2.json`…，顺序即请求顺序）。
   `expected` 只钉要断言的字段子集；`Money.amount` 钉 ArkTS 引擎产出的 canonical
   十进制字符串。
3. **声明新 id（三处，缺一不可）**：
   - Swift `Domain/Provider.swift`：enum 追加 case，**并**把它加进显式覆盖的
     `allCases` 数组（该数组是手维护的，新 case 不会自动出现）。
   - ArkTS `providers/UsageProvider.ets`：`ProviderID` union type +
     `ALL_PROVIDER_IDS` 数组。
   - ArkTS `providers/SpecDrivenProvider.ets` 顶部 `KNOWN_PROVIDER_IDS`（spec
     加载时校验 id，不在白名单直接 specError）。
4. **跑同步**：依次执行第 3 条约束里的三个 sync 脚本。
5. **注册是自动的，不用写装配代码**：Swift `ProviderCatalog` 对
   `ProviderID.allCases` 逐个加载 `Resources/ProviderSpecs/<id>.json`（缺失即
   fatalError，fail-fast）；ArkTS `createProviderRegistry` 对 `ALL_PROVIDER_IDS`
   读 rawfile `providerspecs/<id>.json`。
6. **登记测试用例（harness 不自动发现 fixture）**：
   - Swift：新建 `Shared/SwiftCore/Tests/QuotaGlanceCoreTests/<Name>ProviderTests.swift`，参照
     `DeepSeekProviderTests.swift`，复用 `ContractTests.swift` 里的
     `contractProvider` / `expectRequests` helper。
   - ArkTS：在 `HarmonyOS/entry/src/ohosTest/ets/test/Contract.test.ets` 的
     `CONTRACT_CASES` 数组手工加条目（provider、case 名、profile、每步
     URL/file/HTTP status）。
7. **验证**：`swift test` 全绿；`bash scripts/verify-provider-parity.sh` 全绿；
   `bash scripts/build-harmonyos.sh` 构建通过；有条件时在模拟器/真机跑 ohosTest。

## 常用命令

| 目的 | 命令 |
| --- | --- |
| Swift 全部测试（含契约/引擎/聚合/告警） | `swift test` |
| 脚本测试（单个） | `bash Tests/ScriptTests/<X>.sh`（AppIconTests / BuildEditionTests / DMGPackagingTests / GitHubActionsTests / LocalInstallSafetyTests） |
| 同步 spec → Swift 资源 | `bash scripts/sync-specs-to-core.sh` |
| 同步 spec → HarmonyOS rawfile | `bash scripts/sync-specs-to-harmonyos.sh` |
| 同步 spec → Android 资源 | `bash scripts/sync-specs-to-android.sh` |
| 同步 spec → Windows rawfile | `bash scripts/sync-specs-to-windows.sh` |
| 同步契约 fixture → ohosTest rawfile | `bash scripts/sync-contracts-to-harmonyos.sh` |
| 同步契约 fixture → Android 测试资源 | `bash scripts/sync-contracts-to-android.sh` |
| 同步契约 fixture → Windows 测试资源 | `bash scripts/sync-contracts-to-windows.sh` |
| 四端 parity 校验（改 Contracts 后必跑） | `bash scripts/verify-provider-parity.sh` |
| Android 端单平台 parity | `bash scripts/verify-android-parity.sh` |
| Windows 端单平台 parity | `bash scripts/verify-windows-parity.sh` |
| HarmonyOS 构建 HAP | `bash scripts/build-harmonyos.sh`（需 `DEVECO_SDK_HOME` 或 `HOS_SDK_HOME`，ohpm 与 hvigorw 在 PATH；DevEco 本地环境另需 `JAVA_HOME` 指向 DevEco JBR） |

CI 现状：`.github/workflows/ci.yml`（macos-14 + Xcode 16.2）跑 `swift test` +
五个 ScriptTests；`.github/workflows/harmonyos.yml`（ubuntu +
ErBWs/setup-ohos 6.1.1.280）只做契约同步 + 构建 HAP，**不跑 ohosTest**
（需要模拟器/真机）。

本地验证依赖宿主机工具链：macOS 侧若缺少 Xcode / XCTest，`swift test` 与打包脚本可能
无法运行；HarmonyOS 侧若缺少 DevEco SDK、`ohpm`、`hvigorw` 或签名环境，
`bash scripts/build-harmonyos.sh` / ohosTest 也可能无法运行。遇到这类环境缺口时，
必须在任务或 PR 中明确说明，并以 GitHub Actions 作为构建/打包验证路径：至少查看
`.github/workflows/ci.yml` 与 `.github/workflows/harmonyos.yml`，涉及安装包/
发布流程时再补充对应 workflow 的产物与日志。

## 术语约定

本仓库使用 deep-module 词汇，写文档和讨论设计时保持一致：

- **module（模块）**：一个有明确职责的单元（如 `SnapshotAggregator`、spec 引擎），
  追求"深"——小接口、大实现。
- **interface（接口）**：模块对外暴露的最小面，如 `UsageProvider` 的四个成员；
  收窄接口优先于增加参数。
- **seam（接缝）**：可替换的注入点，如 `HTTPClient` 协议、spec 引擎的
  `now`/`preferredRegion` 注入；测试通过 seam 替换实现，不 mock 具体类。
- **adapter（适配器）**：把外部形状翻译成模块接口的薄层，如 named parse
  strategy 之于 spec 引擎；适配器不含业务规则，规则归 spec 或领域层。
