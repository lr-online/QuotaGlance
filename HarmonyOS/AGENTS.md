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
| `network/HttpClient.ets` | Swift `HTTPClient` 协议（生产实现 `URLSessionHTTPClient`） | `getJsonWithStatus(url, headers)` 原样发送引擎构造的 header 表；传输失败抛 `network:<BusinessError code>` |

App 层（非镜像，平台自有）：`pages/`（UI，含 `Index.ets` 内联的缓存快照汇总）、
`services/`（`AccountService`、`LaunchRefresh`）、`storage/`（`AccountStore` /
`KeyRepository` / `SnapshotStore`，密钥用 Asset Store Kit）、`widget/`（服务卡片）。

## 平台差异白名单（已登记，不算漂移）

1. **`profileDescription` 返回 L10n key token 而非文案。** Swift 侧
   `(profile?, AppLanguage) -> String` 直接查 L10n 表返回本地化文案；ArkTS 侧
   `(profile?) -> string` 返回稳定 key token（需要参数时以冒号分隔附加
   region/credentialKind），因为 ArkTS UI 尚未渲染 profile 描述、也没有这些
   key 的 L10n 表（见 `UsageProvider.ets` 中 `ProviderDescriptor` 的注释）。
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
   `assertRequests`）均断言请求数量、顺序、method、url 和 header 模式（`"Bearer"`
   等）。双端语义与 `Contracts/README.md` Requests-fixture schema 一致。
5. **传输错误形状。** Swift 透传 `URLError`；ArkTS 抛 `network:<BusinessError
   code>`。两者都在 spec 错误模型之外。

## 同步脚本与 rawfile 布局

- `scripts/sync-specs-to-harmonyos.sh`：`Contracts/Providers/<dir>/spec.json` →
  `entry/src/main/resources/rawfile/providerspecs/<camelId>.json`（运行时资源，
  `ProviderCatalog.ets` 经 `resourceManager.getRawFileContentSync` 读取）。
- `scripts/sync-contracts-to-harmonyos.sh`：`Contracts/Providers/**` →
  `entry/src/ohosTest/resources/rawfile/contracts/`（测试资源，ohosTest 的
  `Contract.test.ets` 读取）。**只同步 Providers**；`Contracts/Aggregation/` 与
  `Contracts/Alerts/` 目前仅被 Swift 套件消费（ArkTS 无聚合/告警引擎模块，
  `Index.ets` 的汇总是页面内联逻辑，不受契约钉住）。
- 两处 rawfile 都是同步产物，禁止手改；改完 `Contracts/` 必须重跑脚本并跑
  `bash scripts/verify-provider-parity.sh`。

## 构建与测试前提

- 构建：`bash scripts/build-harmonyos.sh`。需要 `DEVECO_SDK_HOME`（或 CI 的
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
