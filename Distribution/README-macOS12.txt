QuotaGlance @VERSION@ macOS 12 兼容版安装说明

系统要求
- Apple Silicon Mac（M1 或更新）
- macOS 12 或更高版本

版本范围
- 支持菜单栏余额、用量、账户切换、手动刷新和定时刷新。
- 此兼容版不包含桌面小组件，也不提供开机启动选项。
- 包含可在通知中心添加的中号小组件，可选择全部账户或指定账户；也可在设置中配置默认账户。
- macOS 14 或更高版本如需桌面小组件，请改用 macOS 14 完整版。

安装
1. 将 QuotaGlance.app 拖到 Applications。
2. 推出 QuotaGlance 磁盘映像。
3. 打开“应用程序”，按住 Control 点击 QuotaGlance，然后选择“打开”。
4. 如果 macOS 仍然阻止启动，请打开“系统偏好设置 > 安全性与隐私 > 通用”，选择“仍要打开”。

初次使用
1. 启动 QuotaGlance，在设置窗口添加自己的 API Info 账户名称和 key。
2. key 只保存在本机 Keychain，不会写入源码或安装包。
3. 点击菜单栏的 QuotaGlance 图标，可切换全部账户或指定账户并刷新数据。
4. 打开通知中心，添加 QuotaGlance 中号小组件；可编辑为全部账户、指定账户，或使用设置中的默认账户。

说明
- 此版本仅支持 API Info 和 Apple Silicon Mac。
- 此版本使用临时签名，未经过 Apple Developer ID 签名或 Apple 公证，因此首次启动需要手动批准。
- 安装包不包含制作者的 API key、账户、余额或用量数据。
- 安装包为纯净发布，不附带源码压缩包或额外仓库文件。
- macOS 12 兼容版和 macOS 14 完整版使用相同 bundle ID，请勿同时安装。
