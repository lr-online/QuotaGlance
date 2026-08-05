# AGENTS.md — HarmonyOS 端（ArkTS）

本目录是 macOS Swift 核心（`Sources/QuotaGlanceCore/`）的 ArkTS 镜像。总则、
硬约束、新增 provider 清单见仓库根 `AGENTS.md`；本文件只写镜像对应关系、
已登记的平台差异和 HarmonyOS 特有的构建/同步事实。

## 与 Swift 的镜像关系

`entry/src/main/ets/` 下的文件与 Swift 侧的对应（各 ArkTS 文件头注释也自述了
镜像来源，改动一侧时另一侧必须同步）：

| ArkTS（`entry/src/main/ets/`） | Swift（`Sources/QuotaGlanceCore/`） | 说明 |
| --- | --- | --- |
| `providers/UsageProvider.ets` | `Providers/UsageProvider.swift` + `Providers/ProviderDescriptor.swift` + `Domain/Provider.swift` | 接口、错误 token 表（头注释）、`ProviderID` union type + `ALL_PROVIDER_IDS`、region/credentialKind/profile |
| `providers/SpecDrivenProvider.ets` | `Providers/SpecDrivenProvider.swift` + `Providers/ProviderSpec.swift` | spec 加载、load-time 校验（`KNOWN_*` 白名单）、detect/fetch 执行语义 |
| `providers/SpecEngine.ets` | 同上两文件内的 SpecEngine / SpecSnapshotAssembly / SpecDecimal | 求值核心：dot path、值表达式、条件、checks、snapshot builder、decimal canonical 化 |
| `providers/MiniMaxModelRemainsStrategy.ets` | `Providers/MiniMaxModelRemainsStrategy.swift` | 唯一 named parse strategy（`miniMaxModelRemains`） |
| `providers/ProviderCatalog.ets` | `Providers/ProviderCatalog.swift` | 从 spec 资源装配 registry；经 `resourceManager` 读 rawfile，带缓存 |
| `providers/UsageSnapshot.ets` | `Domain/UsageSnapshot.swift` | 快照模型；金额是十进制字符串 |
| `aggregation/SnapshotAggregator.ets` | `Aggregation/SnapshotAggregator.swift` | 跨账户聚合引擎：enabled 过滤 + sortOrder 排序、按币种求和、today 指标全有才算、Int64 溢出检测、7 天 daily 窗口、isPartial；金额求和是精确十进制字符串加法（保最宽小数位） |
| `alerts/AlertEvaluator.ets` | `Alerts/AlertEvaluator.swift` | 低余额告警批量评估引擎：`<=` 阈值触发 notify、episode 去抖与恢复 reset、stale/unavailable 不改 episode、disabled/无阈值不告警；episode 状态随账户传入就地变更（I/O-free）；阈值比较是精确十进制字符串比较 |
| `network/HttpClient.ets` | Swift `HTTPClient` 协议（生产实现 `URLSessionHTTPClient`） | `getJsonWithStatus(url, headers)` 原样发送引擎构造的 header 表；传输失败抛 `network:<BusinessError code>` |

App 层（非镜像，平台自有）：`pages/`（UI，含 `Index.ets` 内联的缓存快照汇总）、
`services/`（`AccountService`、`LaunchRefresh`）、`storage/`（`AccountStore` /
`KeyRepository` / `SnapshotStore`，密钥用 Asset Store Kit）、`widget/`（服务卡片）。

## 平台差异白名单（已登记，不算漂移）

1. **`profileDescription` 返回 L10n key token 而非文案。** Swift 侧
   `(profile?, AppLanguage) -> String` 直接查 L10n 表返回本地化文案；ArkTS 侧
   `(profile?) -> string` 返回稳定 key token（需要参数时以冒号分隔附加
   region/credentialKind），UI 再通过 `utils/ProfileDescriptionL10n.ets` 与
   string resource 解析。双端使用相同 key 集合并保持相同可见语义；差异只在
   Swift 于 descriptor 内解析、ArkTS 于 UI seam 解析（见 `UsageProvider.ets`
   中 `ProviderDescriptor` 的注释）。
2. **decimal 归一化的实现差异。** 规则是共享的（`Contracts/README.md`
   "Decimal and Money canonicalization"），但实现不同：Swift 用 `Decimal`
   数值比较；ArkTS 的 `SpecDecimal` 额外携带 `canonical` 字符串——JSON string
   源 trim 后原样保留，JSON number 源用 JS `String()` 的最短往返渲染。
   fixture 里 `Money.amount` 钉的是 ArkTS 产出的 canonical 形式。
3. **int64 精度判断。** Swift 是真 `Int64`（聚合求和用
   `addingReportingOverflow` 检测溢出）；ArkTS 整数是 IEEE-754 double，
   `SpecEngine.ets` 的 `jsonInt` 拒绝非整数和超出 Int64 范围的值，但范围比较
   本身是 double 近似（超过 2^53 即失去整数精度）。fixture 不要钉接近
   2^53 的整数值。
4. **请求断言粒度已对齐。** Swift 与 ArkTS harness（`Contract.test.ets` 的
   `assertRequests`）均断言请求数量、顺序、method、url 和 header 模式
   （`"Bearer"` 等）；双端语义与 `Contracts/README.md` 的 Requests-fixture
   schema 一致。
5. **传输错误形状。** Swift 透传 `URLError`；ArkTS 抛 `network:<BusinessError
   code>`。两者都在 spec 错误模型之外。
6. **“跟随系统”语言在进程内固定为选择时的系统语言。** 当前 SDK 没有清除
   app preferred language override 的 API；ArkTS 通过
   `setAppPreferredLanguage(getSystemLanguage())` 恢复当前系统语言。因此用户
   随后在系统设置中切换语言时，QuotaGlance 要到下次启动才会跟随。
7. **后台周期刷新由系统调度。** workScheduler 的最小周期间隔与触发条件由
   系统决定，无法对齐 Swift RefreshCoordinator 的定时器语义（前台
   手动/冷启动刷新语义一致，后台周期为系统调度）。
8. **服务卡片周期刷新受系统粒度限制。** `form_config.json` 的
   `updateDuration` 单位为 30 分钟，不能配置五分钟周期；卡片提供“刷新”按钮，
   通过 `onFormEvent` 触发当前账户或总览账户的即时刷新，三种卡片尺寸共用该入口。

## 同步脚本与 rawfile 布局

- `scripts/sync-specs-to-harmonyos.sh`：`Contracts/Providers/<dir>/spec.json` →
  `entry/src/main/resources/rawfile/providerspecs/<camelId>.json`（运行时资源，
  `ProviderCatalog.ets` 经 `resourceManager.getRawFileContentSync` 读取）。
- `scripts/sync-contracts-to-harmonyos.sh`：`Contracts/Providers/**`、
  `Contracts/Aggregation/**`、`Contracts/Alerts/**` →
  `entry/src/ohosTest/resources/rawfile/contracts/`（测试资源，分别由
  `Contract.test.ets`、`AggregationContract.test.ets`、`AlertsContract.test.ets`
  读取）。
- 两处 rawfile 都是同步产物，禁止手改；改完 `Contracts/` 必须重跑脚本并跑
  `bash scripts/verify-provider-parity.sh`。

## 构建与测试前提

- 构建：`bash scripts/build-harmonyos.sh`。顶层 `build-profile.json5` 是忽略的
  DevEco 本机配置；脚本在缺失时从受控的 `build-profile.template.json5` 初始化，
  禁止把签名路径、证书或口令写回模板。需要 `DEVECO_SDK_HOME`（或 CI 的
  `HOS_SDK_HOME`，脚本会据此派生 `DEVECO_SDK_HOME` 与 `local.properties`）、
  `ohpm` 和 `hvigorw` 在 PATH；DevEco Studio 本地安装时另需 `JAVA_HOME` 指向
  DevEco 自带 JBR。脚本强制 `entry/src/main/module.json5` 的 deviceTypes 含
  phone + tablet。`HARMONYOS_SKIP_SIGN=1` 可跳过签名（CI 用法）。
- ohosTest（`entry/src/ohosTest/ets/test/`：`Contract.test.ets`、
  `SpecEngine.test.ets` 等）**需要模拟器或真机**，本地经 DevEco 或 hvigor
  测试任务运行。CI（`.github/workflows/harmonyos.yml`，ubuntu-latest +
  ErBWs/setup-ohos 6.1.1.280）目前只做契约同步 + 构建 HAP + 上传产物，
  不跑 ohosTest；`verify-provider-parity.sh` 提供静态 coverage gate，要求每个
  provider fixture case 均登记到 `CONTRACT_CASES`，并校验 step URL 与 requests
  fixture 一致。provider 行为改动仍不能只靠 CI 兜底，本机有条件要跑 ohosTest。
- 本地若缺少 DevEco SDK、`ohpm`、`hvigorw`、签名材料或可用模拟器/真机，HarmonyOS
  构建与 ohosTest 可能无法执行；这类环境缺口要在任务/PR 中明确说明，并改用 GitHub
  Actions 做构建/打包验证。默认查看 `.github/workflows/harmonyos.yml` 的 HAP 构建
  结果；涉及安装包/发布流程时，补充对应 workflow 的产物与日志。
