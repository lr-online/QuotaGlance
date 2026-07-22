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
- Apple Command Line Tools。缺少时执行：`xcode-select --install`。
- [ripgrep](https://github.com/BurntSushi/ripgrep)：`brew install ripgrep`。
- 完整版 Xcode 和 XcodeGen 仅在需要用 Xcode 打开工程时使用，不是本地构建、安装或 Widget 运行的前置条件。

如果使用完整版 Xcode，首次使用后仍需由你接受许可并完成组件安装：

  ```bash
  sudo xcodebuild -license accept
  sudo xcodebuild -runFirstLaunch
  ```

- Xcode 工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 生成：`brew install xcodegen`。

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

默认构建使用 Command Line Tools 和稳定的本地临时签名，不需要 App Store、Apple Developer 证书或已接受许可的完整版 Xcode。安装器会将应用放到 `~/Applications/QuotaGlance.app`。若已有同 bundle ID 的版本，会先移动到 `~/Library/Application Support/QuotaGlance/Backups`；若目标路径属于其他 bundle ID，安装器会拒绝覆盖。

## 添加账户

1. 点击菜单栏中的 QuotaGlance 图标，打开 Settings。
2. 添加账户名称和 API Info key，点击验证后保存。
3. 重复添加第二个账户；当前设计最多支持五个。
4. 在菜单栏面板切换 All Accounts 或单个账户，使用刷新按钮立即更新。

不要把真实 key 写入源码、提交记录或仓库内的 `.env`。QuotaGlance 不会从 `.env` 导入 key；请只通过应用内的安全编辑器录入。

## 添加桌面小组件

1. 先启动 QuotaGlance 并至少成功刷新一次。
2. 在桌面空白处右键，选择 Edit Widgets。
3. 搜索 QuotaGlance，添加小、中或大尺寸组件。
4. 右键已添加的组件并选择 Edit Widget，可切换 All Accounts 或某个账户。

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
- 组件显示过期：打开菜单栏面板手动刷新，并检查账户 key 的验证状态和网络连接。失败时旧余额会保留，不会被清空。
- App Group 读取失败：确认宿主与 Widget 使用同一个签名 Team、同一个 App Group entitlement，并重新生成 Xcode 项目后安装。
