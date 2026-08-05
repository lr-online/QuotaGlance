---
name: windows-portable-client
overview: 为 QuotaGlance 新增 Windows 11 便携客户端：使用 Tauri 2 + WebView2 双进程框架，完整镜像 macOS/HarmonyOS/Android 端的契约驱动架构(spec 引擎、aggregation、alerts、error tokens、ProviderID)。落地为 Windows/ 子目录:Rust 后端镜像 QuotaGlanceCore 的领域/引擎/刷新/聚合/告警/存储层;前端 HTML/TS 重建系统托盘、主窗口、账户编辑/概览/详情/设置面板、系统通知和深链路由,视觉色板/图标沿用 macOS 现有设计资源但交互遵循 Windows 习惯。Windows 11 桌面 Widget/启动项等差异登记进平台差异白名单。同步脚本(sync-specs-to-windows.sh、sync-contracts-to-windows.sh、verify-windows-parity.sh)与 verify-provider-parity.sh(扩展为四端)接入根 AGENTS.md 硬约束;.github/workflows/windows.yml 在 windows-latest runner 上跑 parity、cargo test 与单 exe portable 构建并上传产物。DPAPI(Windows CryptProtectData)替代 Keychain 存储 API key;自包含 .exe 通过 cargo tauri build --bundles zip 输出便携包。
design:
  architecture:
    framework: react
    component: shadcn
  styleKeywords:
    - macOS 设计语言
    - Windows Fluent 习惯
    - 系统托盘 popover
    - 桌面小组件
    - 深色/浅色主题
    - 高密度信息布局
    - 微动画反馈
  fontSystem:
    fontFamily: Helvetica Neue
    heading:
      size: 18px
      weight: 600
    subheading:
      size: 14px
      weight: 500
    body:
      size: 13px
      weight: 400
  colorSystem:
    primary:
      - "#007AFF"
      - "#0A84FF"
      - "#5E5CE6"
    background:
      - "#FFFFFF"
      - "#F2F2F7"
      - "#1E1E1E"
      - "#2C2C2E"
    text:
      - "#000000"
      - "#3C3C43"
      - "#FFFFFF"
      - "#EBEBF5"
    functional:
      - "#34C759"
      - "#FF9500"
      - "#FF3B30"
      - "#8E8E93"
todos:
  - id: scaffold-tauri-project
    content: 搭建 Windows/ Tauri 2 项目骨架:Cargo.toml、tauri.conf.json、package.json、目录结构与 AGENTS 占位
    status: completed
  - id: rust-core-engine
    content: 实现 Rust 后端核心引擎层:domain/error/spec engine/aggregation/alerts,镜像 Swift 引擎,使用 [subagent:code-explorer] 验证
    status: completed
    dependencies:
      - scaffold-tauri-project
  - id: storage-and-refresh
    content: 实现存储层(DPAPI 凭据/账户/快照/偏好/路径)与 RefreshCoordinator(单/全部/启动/前台/间隔/失败隔离)
    status: completed
    dependencies:
      - rust-core-engine
  - id: tauri-integration
    content: Tauri 2 集成:tray+popover+右键、widget 子进程、notification、deep-link、single-instance、commands
    status: completed
    dependencies:
      - rust-core-engine
  - id: frontend-ui
    content: 前端 UI:React+TS+Vite+Tailwind+shadcn,六页 + i18n + 色板 token,使用 [skill:playwright-cli] 冒烟
    status: completed
    dependencies:
      - tauri-integration
  - id: sync-verify-scripts
    content: 新增 sync-specs/contracts-to-windows 与 verify-windows-parity.sh;扩展 verify-provider-parity.sh 为四端
    status: completed
    dependencies:
      - rust-core-engine
  - id: ci-and-constraints
    content: 新增 .github/workflows/windows.yml;更新根 AGENTS.md 硬约束 + 平台基线表;初始化 Windows/AGENTS.md 平台差异白名单
    status: completed
    dependencies:
      - frontend-ui
      - sync-verify-scripts
---

## Product Overview

Windows 11 便携版 QuotaGlance 客户端,与 macOS / HarmonyOS / Android 三端镜像同一套 AI API provider 余额/配额查看能力。基于 Tauri 2 + WebView2 双进程架构:Rust 主进程执行 provider spec 引擎、aggregation、alerts 与刷新调度,Web 前端渲染系统托盘 popover、主窗口与桌面小组件子进程。完整覆盖 12 项平台能力基线(Provider 契约、账户与凭据生命周期、用户偏好、刷新与快照、聚合、告警、主界面、账户编辑、深链、本地化、平台工程质量、Quick View 等价入口),API key 走 DPAPI(`CryptProtectData`/`CryptUnprotectData`)加密,产物为自包含单 exe portable + 资源 zip。所有 provider / aggregation / alerts 行为改动仍以 `Contracts/` 为唯一权威源,通过扩展为四端的 `verify-provider-parity.sh` 与新增 `verify-windows-parity.sh` 锁定行为一致;Windows 端不允许手写 provider adapter。

## Core Features

- **Provider 契约镜像**:完整支持 `ProviderID`(`apiInfo / deepSeek / kimi / openRouter / miniMax / bioMapCoding`),通过 Rust spec 引擎执行 `Contracts/Providers/<id>/spec.json`,detect/fetch 语义、region fallback、`credentialKindDetection`、named parse strategy 与 Swift/ArkTS/Kotlin 完全一致。
- **账户与凭据生命周期**:增删改账户、20 账户上限、displayName 去空白/重复校验、API key 空值/替换校验、provider profile 探测与持久化、低余额阈值编辑;凭据走 DPAPI 加密落 `%LOCALAPPDATA%\QuotaGlance\credentials.bin`,删除账户级联清理凭据与快照。
- **用户偏好**:刷新间隔(1/5/15/30/60 min)、首选语言(System/English/Chinese)、通知开关、启动项(可选写注册表)、默认桌面小组件账户选择。
- **刷新与快照**:单账户 / 全部账户刷新、启动与前台进入时刷新、按间隔后台刷新、单账户失败不阻断其他、保留 stale/unavailable/partial 标记与失败原因、持久化 `receivedAt` / `capturedAt` / `lastSuccessAt`。
- **聚合与指标语义**:镜像 `SnapshotAggregator` 行为(disabled 过滤、sortOrder、币种求和、today 仅全有同币种、Int64 溢出、7 天窗口、isPartial);money 用 `rust_decimal::Decimal` 求和后 canonical 字符串序列化,与 ArkTS 引擎产出形态一致。
- **告警与通知**:镜像 `AlertEvaluator`(`<=` 触发、episode 去抖、recovery reset、stale 静默、disabled/无阈值不告警),通过 `tauri-plugin-notification` 发送本地 Toast,失败/不可用时不误报。
- **主界面 + Quick View 等价入口**:系统托盘 + popover 菜单(全局账户缩略)、主窗口(账户网格 + 详情 + 编辑 + 设置)、独立桌面小组件子进程窗口(All / 指定 / 默认 三种选择;Win11 Widget Board 缺失登记差异 v1,v2 待办)。
- **账户编辑 / 设置**:provider 选择、名称、API key 粘贴、启用、阈值、刷新间隔、语言、通知、默认小组件、启动项;错误信息统一走 L10n 呈现。
- **深链与选择解析**:`quotaglance://all`、`quotaglance://account/<uuid>`,通过 `tauri-plugin-single-instance` 强制单实例,删除账户时降级到 All Accounts。
- **本地化与格式化**:English / Chinese 文案、系统语言解析、Money 币种大小写规范化、十进制字符串输出;新增文案必须 Swift/ArkTS/Kotlin/Rust 四端同登记。
- **工程与质量门禁**:`Windows/AGENTS.md` + `scripts/sync-specs-to-windows.sh` + `scripts/sync-contracts-to-windows.sh` + `scripts/verify-windows-parity.sh`,`scripts/verify-provider-parity.sh` 扩展为四端,`.github/workflows/windows.yml` 在 windows-latest runner 跑 parity + cargo test + portable 构建并上传 zip 产物。

## 技术栈选型

- **后端框架**:Tauri 2.x(双进程:Rust 主进程 + WebView2 多窗口)
- **后端语言**:Rust 2021 edition
- **关键 crate**:`tauri` 2.x,`tauri-plugin-tray` 2.x,`tauri-plugin-notification` 2.x,`tauri-plugin-single-instance` 2.x,`tauri-plugin-deep-link` 2.x,`tauri-plugin-window-state` 2.x,`tauri-plugin-store` 2.x,`serde`,`serde_json`,`reqwest`,`tokio`,`rust_decimal`,`chrono`,`uuid`,`tracing`,`thiserror`,`windows` crate(DPAPI),`tauri-build`
- **前端**:HTML + TypeScript + React 18 + Vite + Tailwind CSS + shadcn/ui
- **图标与字体**:沿用 `App/Assets.xcassets/AppIcon.appiconset/`,生成 `.ico`(多分辨率)与 `.png`;字体 `Helvetica Neue` fallback 到 `Segoe UI Variable` / `Microsoft YaHei UI`
- **测试**:`cargo test` 覆盖 spec 引擎 / aggregation / alerts / DPAPI round-trip / 契约 fixture;前端 `vitest` 单测 + `playwright` 端到端
- **构建**:`cargo tauri build --target x86_64-pc-windows-msvc --bundles zip` 生成 `QuotaGlance_<ver>_x64-portable.zip`(单 exe + 资源 + WebView2 bootstrapper 提示);保留 `msi/nsis` 旁路产物
- **CI**:`.github/workflows/windows.yml` 在 `windows-latest` runner 上跑 `cargo test` + `verify-windows-parity.sh` + 扩展后的 `verify-provider-parity.sh` + portable zip 构建并上传产物

## 架构设计

```mermaid
flowchart TB
  subgraph WindowsHost[Windows 进程]
    direction TB
    T2[Tauri 2 主进程 - Rust]
    WV2[WebView2 - 多窗口]
    subgraph WV2Windows
      Tray[系统托盘 popover 窗口]
      Main[主窗口 - 账户/详情/编辑/设置]
      Widget[桌面小组件子进程窗口]
    end
    T2 -->|创建/管理| WV2Windows
  end

  subgraph RustCore[quotaglance-tauri - 镜像 QuotaGlanceCore]
    direction TB
    Domain[domain.rs - ProviderID/Region/CredentialKind/Profile/Account/UsageSnapshot]
    Providers[providers/* - UsageProvider trait + SpecDrivenProvider + MiniMaxModelRemainsStrategy + ProviderCatalog]
    Aggregation[aggregation - SnapshotAggregator]
    Alerts[alerts - AlertEvaluator]
    Refresh[refresh - RefreshCoordinator]
    Storage[storage - CredentialVault DPAPI + AccountStore + SnapshotStore + Preferences + PathLayout]
    Commands[commands.rs - Tauri command 桥]
    TrayMod[tray - 系统托盘菜单与 popover 生命周期]
  end

  subgraph Contracts[Contracts/ 权威源]
    Specs[Providers/<id>/spec.json]
    FixProv[Providers/<id>/{case}-{response,expected,requests}.json]
    FixAgg[Aggregation/<case>-{input,expected}.json]
    FixAlt[Alerts/<case>-{input,expected}.json]
  end

  Contracts -->|sync-specs-to-windows.sh| Providers
  Contracts -->|sync-contracts-to-windows.sh| RustTest[src-tauri/tests/contracts/*]

  RustCore -->|注册 tray/popover 事件| T2
  Commands -->|invoke| WV2
```

## 关键实现要点

### 引擎镜像(Rust)

- `domain.rs` 完整镜像 Swift `Domain/`:`ProviderID` enum 显式覆盖 `allCases`(`apiInfo / deepSeek / kimi / openRouter / miniMax / bioMapCoding` 顺序固定),`ProviderRegion { global | china | international }`,`ProviderCredentialKind { standard | management | tokenPlan }`,`ProviderProfile`,`Account`,`UsageSnapshot`,`Money { amount: String, currency: String }`。
- `providers/provider_spec.rs` 实现 `SpecEngine / SpecSnapshotAssembly / SpecDecimal`,覆盖 dot-path、值表达式、条件、`checks`、snapshot builder、decimal canonical 化(JSON number 最短往返、JSON string trim 后原样保留、`subtract` 用 canonical 渲染)。
- `providers/spec_driven_provider.rs` 实现 spec 加载与 detect/fetch 语义,`KnownProviderId` 白名单在加载时校验。
- `providers/minimax_model_remains_strategy.rs` 实现唯一 named parse strategy,行为完全镜像 Swift/ArkTS/Kotlin 实现。
- `aggregation/snapshot_aggregator.rs` 镜像 `SnapshotAggregator`(enabled 过滤、sortOrder、币种求和、today 仅全有同币种、Int64 溢出检测、7 天窗口、isPartial)。
- `alerts/alert_evaluator.rs` 镜像 `AlertEvaluator`(`&lt;=` 触发、episode 去抖、recovery reset、stale 静默、disabled/无阈值不告警)。
- `providers/provider_error.rs` 错误 token 与 Swift `ProviderError` 同字表:`invalidCredential | rateLimited | httpStatus | invalidResponse | providerInactive | unsupportedCredential | regionDetectionFailed | profileMismatch`(Rust 用 enum + `http_status: Option<u16>` 字段对齐 Swift 形态;`providerUnavailable` 与 `network:<detail>` 是框架级,永不出现在 spec)。

### 存储层

- `storage/credential_vault.rs` 使用 `windows` crate 的 `CryptProtectData(CRYPTPROTECT_LOCAL_MACHINE)` 加密 API key,落盘 `%LOCALAPPDATA%\QuotaGlance\credentials.bin`(账户 UUID → ciphertext),解密仅在该进程内;`PORTABLE=1` 切换到 exe 同目录模式并写入 `Windows/AGENTS.md` 差异登记。
- `storage/account_store.rs`、`snapshot_store.rs`、`preferences.rs` 镜像 Swift `Storage/` 行为,使用 JSON 文件 + 原子写(`temp + rename`)。
- `storage/path_layout.rs` 集中路径常量,首次启动创建目录。

### RefreshCoordinator 与 Tauri 集成

- `refresh/refresh_coordinator.rs` 调度单账户 detect/fetch、写 snapshot、按账户 isolate 失败,启动 + 前台 + 间隔触发。
- `tray/mod.rs` 用 `tauri-plugin-tray` 创建托盘图标 + 左键 popover 窗口 + 右键菜单(打开主窗口 / 退出 / 关于),popover 内显示账户缩略。
- `widget/` 子进程是独立 `tauri::WebviewWindow`(常驻、可隐藏),`tauri-plugin-window-state` 记忆位置。
- `commands.rs` 暴露给前端:`list_accounts / add_account / update_account / delete_account / refresh_all / refresh_one / get_snapshot / set_preference / open_widget / open_main / quit / show_notification / get_alert_status` 等。
- `tauri-plugin-deep-link` 注册 `quotaglance://` 协议,`tauri-plugin-single-instance` 锁进程把深链路由到主窗口。

### 前端

- React + TS + Vite + Tailwind + shadcn/ui;`src/pages/`:`Overview.tsx`(账户网格 + 主指标 + 7 天趋势)、`AccountDetail.tsx`(余额 / spend / quota / daily / model)、`AccountEdit.tsx`(provider + key + 阈值 + 启用)、`Settings.tsx`(间隔 / 语言 / 通知 / 启动项 / 默认小组件)、`AddProvider.tsx`(provider 选择 + paste + detect)、`Widget.tsx`(精简版,只在 widget 窗口加载)。
- `src/i18n/{en,zh-CN}.json` 镜像 Swift `L10n` key,新增 key 必须四端同登记;`src/i18n/index.ts` 解析系统语言 → `zh-CN` / `en`。
- `src/tauri-bindings.ts` 通过 `tauri-cli generate` 自动生成命令类型。
- `src/styles/tokens.css` 定义 macOS 色板 token(`--qg-blue: #007AFF`、`--qg-bg-light: #FFFFFF`、`--qg-bg-dark: #1E1E1E`、`--qg-success: #34C759`、`--qg-warning: #FF9500`、`--qg-danger: #FF3B30`),通过 Tailwind config 暴露给组件。

### 同步与校验脚本

- `scripts/sync-specs-to-windows.sh`:`Contracts/Providers/*/spec.json` → `Windows/src-tauri/assets/providerspecs/<camelId>.json`,与 `sync-specs-to-android.sh` 同形。
- `scripts/sync-contracts-to-windows.sh`:`Contracts/Providers/**` + `Contracts/Aggregation/**` + `Contracts/Alerts/**` → `Windows/src-tauri/assets/contracts/`,供 `cargo test` 中契约 fixture 测试消费。
- `scripts/verify-windows-parity.sh`:类比 `verify-android-parity.sh`,校验 Windows 端 `ProviderID` enum 与 Swift `allCases` 一致、spec 副本 byte-identical、Contracts 三件套完整、spec 引擎版本号一致。
- `scripts/verify-provider-parity.sh` 扩展:新增 Rust 端提取(`ProviderID` enum 从 `Windows/src-tauri/src/providers/provider_id.rs` 提取 `UPPER_SNAKE_CASE` 形态的 id,与 Swift allCases 对比),保证四端集合与顺序严格一致。

### CI 与文档

- `.github/workflows/windows.yml`:`windows-latest` runner,装 Rust stable + Node 20 + pnpm + WebView2 Evergreen Bootstrapper 可选,步骤:`setup-tauri` → `sync-specs/contracts-to-windows` → `cargo test --manifest-path Windows/Cargo.toml` → `verify-windows-parity.sh` → `verify-provider-parity.sh`(必须四端全绿)→ `cargo tauri build --target x86_64-pc-windows-msvc --bundles zip` → 上传 `QuotaGlance_*_x64-portable.zip` 到 artifacts。
- 根 `AGENTS.md` 第 1 条(`ProviderID` raw value append-only)增补 Rust enum 声明点;第 3 条(三处副本同步纪律)增补 Windows 端同步脚本名;平台支持功能基线 12 项按 Android 形态填"Implemented / N/A / 差异"列。
- `Windows/AGENTS.md` 初始化:镜像 `HarmonyOS/AGENTS.md` 与 `Android/AGENTS.md` 形态;镜像对应表(Rust 文件 ↔ Swift/ArkTS/Kotlin 文件)、同步脚本事实、平台差异白名单初始四条:启动项可选注册表写入 vs macOS Login Items;Win11 Widget Board 缺失 → v1 改用桌面小组件子进程窗口,v2 待办登记;UI 交互接受 Windows 习惯(flyout、托盘右键);DPAPI `CryptProtectData` 是 Keychain 等价。

## 关键约束(不可违反)

1. `ProviderID` raw value 仍 append-only,Rust enum 顺序与 Swift `allCases` 严格一致。
2. Contract-first:Provider 行为改动只走 spec + fixture,严禁在 Rust 端手写 provider adapter。
3. 同步与 parity:`sync-specs-to-{core,harmonyos,android,windows}.sh`、`sync-contracts-to-{harmonyos,android,windows}.sh`、`verify-provider-parity.sh`(扩展为四端)、`verify-{android,windows}-parity.sh` 必须全绿。
4. 错误 token 表四端同字表,Rust 端 token 字符串与 Swift/ArkTS/Kotlin 完全一致。
5. Decimal canonical 规则(Rust `rust_decimal` 序列化)必须与 ArkTS 引擎产出形态一致,fixture 测试覆盖。
6. Windows 平台差异必须显式登记进 `Windows/AGENTS.md` 平台差异白名单。

## 设计风格

保留 macOS 设计语言(色板 / 图标 / 留白 / 字号 / 微动画),交互接受 Windows 习惯(Fluent 风格的 flyout、托盘原生右键菜单、深链/单实例锁)。深色 / 浅色主题跟随系统,色板 token 集中定义在 `src/styles/tokens.css` 并通过 Tailwind config 暴露给组件。shadcn/ui 提供基础组件(Button / Dialog / Dropdown / Form / Toast / Tabs / Table / Input / Switch),在其上构建 QuotaGlance 专用面板。WebView2 渲染保证视觉与 macOS 一致,字体在 Windows 上 fallback 到 Segoe UI Variable / Microsoft YaHei UI。

## 主要页面

1. **托盘 popover 窗口**(300×420):全局账户缩略 + 主指标,默认紧贴托盘图标,左键弹出。
2. **主窗口 - 总览**(960×720):账户网格(健康 / 低余额 / 禁用 / 错误状态着色)、今日指标、7 天趋势、刷新按钮。
3. **主窗口 - 账户详情**(720×640):余额 / breakdown / spending limit / spend today-week-month-total / quota windows / 今日+总数 / dailyUsage / modelUsage / providerStatus / 错误信息。
4. **主窗口 - 账户编辑**(520×560):provider select / displayName / API key 粘贴(threshold + enabled)/ validation 错误统一呈现。
5. **主窗口 - 设置**(640×520):刷新间隔 / 语言 / 通知 / 启动项 / 默认小组件账户 / 关于。
6. **桌面小组件子进程窗口**(240×160):精简版只显示账户余额或主指标,Three States(All / 指定 / 默认账户)由 preferences 决定。

## Agent Extensions

### Skill

- **playwright-cli**
- 用途:在 Tauri 开发模式下用 Playwright 自动化驱动 WebView 前端,做端到端冒烟测试(账户添加 / 编辑 / 删除 / 刷新、深链 `quotaglance://all` 跳总览、托盘 popover 渲染)。
- 期望产出:每次改动前端后能在 windows-latest runner 与本地手动验证时拿到可视截图或交互通过的 evidence,作为 CI 的可选 verification step。

### SubAgent

- **code-explorer**
- 用途:在 Rust 后端实现阶段,深度探索 Swift `Sources/QuotaGlanceCore/` 与 ArkTS `HarmonyOS/entry/src/main/ets/providers/` 的 SpecEngine / aggregation / alerts 内部细节,保证 Rust 镜像与现有引擎逐字段一致。
- 期望产出:在 Rust 模块实现每个 milestone 时输出"Swift/ArkTS 端对应源文件 + 行为细节引用",供编写 fixture 测试与 reference 文档使用。