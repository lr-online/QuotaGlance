# AGENTS.md — QuotaGlance 协作准则

读者是接手本仓库的 AI agent。本文只写架构地图、不可违反的约束和可执行操作；
实现细节一律以代码和 `Contracts/README.md` 为准。HarmonyOS 端的专项说明见
`HarmonyOS/AGENTS.md`。

## 项目一句话

macOS 菜单栏 + 桌面小组件应用，集中查看多个 AI API provider 的余额/配额；
HarmonyOS（ArkTS）端是同一套领域逻辑的镜像实现，双端通过 `Contracts/` 下的
共享 spec 与契约 fixture 防止行为漂移。

## 架构地图

Swift 包：`Package.swift`，核心库 `QuotaGlanceCore`（`Sources/QuotaGlanceCore/`），按层分目录：

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

- `App/` — macOS 菜单栏主应用（SwiftUI）。
- `Widget/` — 桌面 Widget（WidgetKit，小/中/大）。
- `NCWidget/` — 通知中心 Widget（macOS 12 兼容路径）。
- `NCIntents/` — Widget 账户选择的 App Intent 共享代码。

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
   `Sources/QuotaGlanceCore/Domain/Provider.swift`（enum + 显式覆盖的 `allCases`
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
3. **三处副本的同步纪律。** `Contracts/` 是唯一权威源，改动后必须重跑：
   `bash scripts/sync-specs-to-core.sh`（→ `Sources/QuotaGlanceCore/Resources/ProviderSpecs/`）、
   `bash scripts/sync-specs-to-harmonyos.sh`（→ `HarmonyOS/entry/src/main/resources/rawfile/providerspecs/`）、
   `bash scripts/sync-contracts-to-harmonyos.sh`（→ `HarmonyOS/entry/src/ohosTest/resources/rawfile/contracts/`，
   仅同步 `Contracts/Providers/`）。随后 `bash scripts/verify-provider-parity.sh`
   必须全绿。同步产物禁止手改。
4. **双端语义镜像。** provider / 聚合 / 告警的行为改动必须双端对应提交；确实
   无法一致的，显式登记进 `HarmonyOS/AGENTS.md` 的平台差异白名单，不允许静默
   漂移。注意现状：聚合/告警契约 fixture 目前只被 Swift 套件消费（ArkTS 尚无
   对应引擎模块），这是已记录的待办而非镜像破坏。
5. **错误 token 表是双端契约。** spec 只允许引用 `Contracts/README.md`
   "Error tokens" 一节列出的稳定 token；同一张表镜像在 ArkTS
   `UsageProvider.ets` 头注释与 Swift `ProviderError`（`UsageProvider.swift`）。
   新增/修改 token 必须三处同改。`httpStatus` 携带实际状态码（Swift
   `httpStatus(Int)`，ArkTS `"httpStatus:<code>"`）；`providerUnavailable` 与
   `network:<detail>` 是框架级错误，永不出现在 spec 中。

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
   - Swift：新建 `Tests/QuotaGlanceCoreTests/<Name>ProviderTests.swift`，参照
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
| 同步契约 fixture → ohosTest rawfile | `bash scripts/sync-contracts-to-harmonyos.sh` |
| 双端 parity 校验（改 Contracts 后必跑） | `bash scripts/verify-provider-parity.sh` |
| HarmonyOS 构建 HAP | `bash scripts/build-harmonyos.sh`（需 `DEVECO_SDK_HOME` 或 `HOS_SDK_HOME`，ohpm 与 hvigorw 在 PATH；DevEco 本地环境另需 `JAVA_HOME` 指向 DevEco JBR） |

CI 现状：`.github/workflows/ci.yml`（macos-14 + Xcode 16.2）跑 `swift test` +
五个 ScriptTests；`.github/workflows/harmonyos.yml`（ubuntu +
ErBWs/setup-ohos 6.1.1.280）只做契约同步 + 构建 HAP，**不跑 ohosTest**
（需要模拟器/真机）。

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
