QuotaGlance @VERSION@ macOS 14 完整版安装说明

系统要求
- Apple Silicon Mac（M1 或更新）
- macOS 14 或更高版本

版本范围
- 支持菜单栏余额、用量、账户切换、手动刷新、定时刷新和开机启动。
- 包含可选择全部账户或指定账户的桌面小组件。

安装
1. 将 QuotaGlance.app 拖到 Applications。
2. 推出 QuotaGlance 磁盘映像。
3. 打开“应用程序”，按住 Control 点击 QuotaGlance，然后选择“打开”。
4. 如果 macOS 仍然阻止启动，请打开“系统设置 > 隐私与安全性”，选择“仍要打开”。

初次使用
1. 启动 QuotaGlance，在设置窗口添加自己的 API Info 账户名称和 key。
2. key 只保存在本机 Keychain，不会写入源码或安装包。
3. 成功刷新一次后，在桌面小组件库中搜索 QuotaGlance。
4. 添加 QuotaGlance 小组件；右键“编辑小组件”可以选择全部账户或指定账户。

说明
- 此版本仅支持 API Info 和 Apple Silicon Mac。
- 此版本使用临时签名，未经过 Apple Developer ID 签名或 Apple 公证，因此首次启动需要手动批准。
- 安装包不包含制作者的 API key、账户、余额或用量数据。
- 安装包为纯净发布，不附带源码压缩包或额外仓库文件。
- macOS 12 兼容版和 macOS 14 完整版使用相同 bundle ID，请勿同时安装。
