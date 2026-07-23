# QuotaGlance

QuotaGlance 是一个个人使用的 macOS 菜单栏应用和桌面小组件，用于查看多个 API Info key 的剩余额度与近期用量。

一期只支持 API Info。OpenRouter、DeepSeek、Kimi 和 MiniMax 的官方接口能力与后续接入边界记录在 [`docs/research/provider-capabilities.md`](docs/research/provider-capabilities.md)，当前版本不显示未实现的服务商选项。

## 功能

- 管理 2-5 个具名 API Info 账户，key 只保存在 macOS Keychain。
- 菜单栏查看总余额、单账户余额、今日花费和最近七天趋势。
- 刷新间隔可选 1、5、15、30 或 60 分钟，默认 5 分钟。
- 支持小、中、大三种 Widget，并可配置为全部账户或指定账户。
- 网络或接口失败时保留上次成功数据并标记为过期。
- 可选低余额通知和开机启动。

## 本地要求

- macOS 14 或更高版本。
- 完整版 Xcode，安装在 `/Applications/Xcode.app`。本地构建依赖 Xcode 生成 Widget 的 App Intent 元数据。
- Xcode Command Line Tools。缺少时执行：`xcode-select --install`。
- [ripgrep](https://github.com/BurntSushi/ripgrep)：`brew install ripgrep`。

首次使用 Xcode 后，需接受许可并完成组件安装：

  ```bash
  sudo xcodebuild -license accept
  sudo xcodebuild -runFirstLaunch
  ```

- Xcode 工程已包含在仓库中。仅在修改 `project.yml` 后需要 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`。

## 可选的 Xcode 签名

1. 执行 `xcodegen generate`，然后打开 `QuotaGlance.xcodeproj`。
2. 在 `QuotaGlance` 和 `QuotaGlanceWidget` 两个 target 的 Signing & Capabilities 中选择同一个 Team，并保持 Automatically manage signing 开启。
3. 确认两个 target 都包含 App Groups capability，且组名均为 `group.com.liangrui.QuotaGlance`。
4. 若该 App Group 已被其他开发者账号占用，请在 `project.yml`、两个 entitlements 文件和 `Sources/QuotaGlanceCore/Storage/SharedSnapshotStore.swift` 中统一改成属于你的唯一标识，然后重新执行 `xcodegen generate`。

## 构建与安装

先运行核心测试：

```bash
swift test
```

开发构建并启动：

```bash
./script/build_and_run.sh
```

Release 构建、本地安装并注册 Widget：

```bash
./scripts/install-local.sh
```

默认构建使用完整版 Xcode 生成可配置 Widget 所需的 App Intent 元数据，然后使用稳定的本地临时签名；不需要 App Store 或 Apple Developer 证书。安装器会将应用放到 `~/Applications/QuotaGlance.app`。若已有同 bundle ID 的版本，会先移动到 `~/Library/Application Support/QuotaGlance/Backups`；若目标路径属于其他 bundle ID，安装器会拒绝覆盖。

## 生成分享版 DMG

当前分享版仅支持 Apple Silicon，使用临时签名且未经过 Apple 公证：

```bash
./scripts/package-dmg.sh
```

产物位于 `dist/QuotaGlance-0.1.0-arm64.dmg`，相邻的 `.sha256` 文件用于校验下载或传输完整性。DMG 同时包含 `QuotaGlance-0.1.0-source.zip` 和 `SOURCE-COMMIT.txt`，供接收者核对并审查对应源码。

接收者需将应用拖入 Applications，并在首次启动时按住 Control 点击应用后选择“打开”；如果仍被拦截，请在“系统设置 > 隐私与安全性”中选择“仍要打开”。这是临时签名版本的已知限制，不代表 DMG 损坏。

## 添加账户

1. 点击菜单栏中的 QuotaGlance 图标，打开 Settings。
2. 添加账户名称和 API Info key，点击验证后保存。
3. 重复添加第二个账户；当前设计最多支持五个。
4. 在菜单栏面板切换 All Accounts 或单个账户，使用刷新按钮立即更新。

不要把真实 key 写入源码、提交记录或仓库内的 `.env`。QuotaGlance 不会从 `.env` 导入 key；请只通过应用内的安全编辑器录入。

## 添加桌面小组件

1. 先启动 QuotaGlance 并至少成功刷新一次。
2. 在桌面空白处右键，选择 Edit Widgets。
3. 搜索 QuotaGlance，选择名为 `QuotaGlance` 的可配置组件，再添加小、中或大尺寸。
4. 右键该组件并选择 Edit Widget，可切换 All Accounts 或某个账户。

升级前已经放在桌面的组件会继续作为固定的 `All Accounts` 总览运行，以避免 WidgetKit 迁移时白屏；需要显示指定账户时，请从 Gallery 新增 `QuotaGlance` 可配置组件。

WidgetKit 的后台时间线由系统调度，菜单栏应用会按设置的间隔请求数据，并在写入共享快照后通知所有组件刷新。

## 验证密钥未进入产物

应用安装后，可使用当前 shell 中的 API Info key 检查 Git 跟踪文件和已安装 app。脚本不会打印 key，也不会把 key 放在进程参数中：

```bash
export LAOGE_KEY='你的 key'
./scripts/verify-no-secret.sh
```

多个 key 可分别执行一次。

## Widget 故障排查

- Gallery 中找不到 QuotaGlance：启动安装后的应用一次，再执行 `pluginkit -a "$HOME/Applications/QuotaGlance.app/Contents/PlugIns/QuotaGlanceWidget.appex"`，随后重新打开 Gallery。
- 组件仍显示旧版本：移除桌面组件，结束 QuotaGlance 后重新执行 `./scripts/install-local.sh`，再重新添加组件；必要时注销并重新登录 macOS。
- 深色桌面下组件发灰或模糊：macOS 会统一调暗桌面组件。若需要始终保持完整对比度，在 System Settings → Desktop & Dock → Widgets 中将 Dim widgets on desktop 改为 Never。
- 组件显示过期：打开菜单栏面板手动刷新，并检查账户 key 的验证状态和网络连接。失败时旧余额会保留，不会被清空。
- App Group 读取失败：确认宿主与 Widget 使用同一个签名 Team、同一个 App Group entitlement，并重新生成 Xcode 项目后安装。
