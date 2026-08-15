import Foundation

public enum L10nKey: String, Sendable {
    // Language preference
    case languageSection
    case language
    case languageSystem
    case languageEnglish
    case languageChinese
    case languageFooter
    case appearanceSection
    case appearance
    case themeSystem
    case themeLight
    case themeDark
    case appearanceFooter

    // Settings window / sections
    case settingsWindowTitle
    case setupWindowTitle
    case dashboardWindowTitle
    case accounts
    case addAccount
    case refresh
    case interval
    case launchAtLogin
    case notificationCenterWidget
    case notificationCenterWidgetFooter
    case defaultAccount
    case allAccounts
    case notifications
    case notificationsFooter
    case lowBalanceAlerts
    case status
    case noAccounts
    case addProviderAccountHint
    case deleteAccountTitle
    case delete
    case cancel
    case save
    case editAccount
    case moveUp
    case moveDown
    case alertBelow
    case notRequested
    case notAllowed
    case allowed
    case minute1
    case minutes5
    case minutes15
    case minutes30
    case minutes60
    case savedSettingsUnreadable
    case keychainApprovalRequired
    case keychainApprovalRequiredSingular
    case someAccountsRefreshFailed
    case allAccountsRefreshFailed

    // Account editor
    case provider
    case name
    case apiKey
    case replacementAPIKey
    case paste
    case pasteAPIKeyHelp
    case threshold
    case thresholdCaption
    case openRouterThresholdCaption
    case enabled

    // Provider profile copy
    case notDetected
    case chinaCNY
    case internationalUSD
    case globalCredential
    case regionCredential
    case global
    case china
    case international
    case standardKey
    case managementKey
    case tokenPlan

    // Menu bar / dashboard
    case account
    case requestsToday
    case last7Days
    case balances
    case noMetric
    case connected
    case spentToday
    case requests
    case remaining
    case used
    case limit
    case spend
    case today
    case thisWeek
    case thisMonth
    case total
    case quotaWindows
    case resetsRelative
    case topModels
    case noData
    case retry
    case settings
    case openDashboard
    case quit
    case upToDate
    case lowBalance
    case partialData
    case keychainLocked
    case savedData
    case unavailable
    case percentUsed
    case providerOverview
    case oneAccount
    case accountCount
    case disabled
    case healthy
    case requestShare
    case todayMetrics
    case totalMetrics
    case inputTokens
    case outputTokens
    case cacheReadTokens
    case cacheCreationTokens
    case totalTokens
    case providerStatus
    case metricsUnavailable
    case lastSuccessfulRefresh
    case modelUsage

    case sevenDayUsage
    case currencyBalance

    // Primary metrics
    case balance
    case spentThisMonth
    case spentThisWeek
    case totalSpent

    // Widget
    case accountUnavailable

    // Notifications
    case lowBalanceTitle
    case lowBalanceBody

    // App menu
    case quitQuotaGlance
    case edit
    case cut
    case copy
    case selectAll

    // Errors
    case errorEmptyDisplayName
    case errorEmptyAPIKey
    case errorMaximumAccounts
    case errorDuplicateDisplayName
    case errorInvalidThreshold
    case errorReplacementKeyRequired
    case errorInvalidCredential
    case errorRateLimited
    case errorHTTPStatus
    case errorUnsupportedCredential
    case errorRegionDetectionFailed
    case errorProfileMismatch
    case errorInvalidResponse
    case errorProviderUnavailable
    case errorCredentialNotFound
    case errorCredentialInvalidData
    case errorCredentialInteractionRequired
    case errorKeychainMissingBuild
    case errorKeychainStatus
    case errorNoInternet
    case errorTimedOut
    case errorHostUnreachable
    case errorSecureConnectionFailed
    case errorCancelled
    case errorNetworkInterrupted
    case errorGeneric
}

public enum L10n {
    public static func string(
        _ key: L10nKey,
        language: AppLanguage,
        _ args: CVarArg...
    ) -> String {
        let template = table[key]?[language] ?? table[key]?[.english] ?? key.rawValue
        guard !args.isEmpty else { return template }
        return String(format: template, locale: language.locale, arguments: args)
    }

    public static func preferenceTitle(
        _ preference: AppLanguagePreference,
        language: AppLanguage
    ) -> String {
        switch preference {
        case .system:
            string(.languageSystem, language: language)
        case .english:
            string(.languageEnglish, language: language)
        case .chinese:
            string(.languageChinese, language: language)
        }
    }

    public static func themePreferenceTitle(
        _ preference: AppThemePreference,
        language: AppLanguage
    ) -> String {
        switch preference {
        case .system:
            string(.themeSystem, language: language)
        case .light:
            string(.themeLight, language: language)
        case .dark:
            string(.themeDark, language: language)
        }
    }

    private static let table: [L10nKey: [AppLanguage: String]] = [
        .languageSection: [
            .english: "General",
            .chinese: "通用",
        ],
        .language: [
            .english: "Language",
            .chinese: "语言",
        ],
        .languageSystem: [
            .english: "System",
            .chinese: "跟随系统",
        ],
        .languageEnglish: [
            .english: "English",
            .chinese: "English",
        ],
        .languageChinese: [
            .english: "中文",
            .chinese: "中文",
        ],
        .languageFooter: [
            .english: "Defaults to the macOS language. Override to keep QuotaGlance in English or Chinese.",
            .chinese: "默认跟随 macOS 系统语言。可强制使用英文或中文。",
        ],
        .appearanceSection: [
            .english: "Appearance",
            .chinese: "外观",
        ],
        .appearance: [
            .english: "Theme",
            .chinese: "主题",
        ],
        .themeSystem: [
            .english: "System",
            .chinese: "跟随系统",
        ],
        .themeLight: [
            .english: "Light",
            .chinese: "浅色",
        ],
        .themeDark: [
            .english: "Dark",
            .chinese: "深色",
        ],
        .appearanceFooter: [
            .english: "Applies to the menu bar, dashboard, and Settings. Widgets continue to follow macOS.",
            .chinese: "应用于菜单栏、仪表盘和设置。小组件仍跟随 macOS 系统外观。",
        ],
        .settingsWindowTitle: [
            .english: "QuotaGlance Settings",
            .chinese: "QuotaGlance 设置",
        ],
        .setupWindowTitle: [
            .english: "QuotaGlance Setup",
            .chinese: "QuotaGlance 初始设置",
        ],
        .dashboardWindowTitle: [
            .english: "QuotaGlance Dashboard",
            .chinese: "QuotaGlance 仪表盘",
        ],
        .accounts: [
            .english: "Accounts",
            .chinese: "账户",
        ],
        .addAccount: [
            .english: "Add Account",
            .chinese: "添加账户",
        ],
        .refresh: [
            .english: "Refresh",
            .chinese: "刷新",
        ],
        .interval: [
            .english: "Interval",
            .chinese: "间隔",
        ],
        .launchAtLogin: [
            .english: "Launch at Login",
            .chinese: "登录时打开",
        ],
        .notificationCenterWidget: [
            .english: "Notification Center Widget",
            .chinese: "通知中心小组件",
        ],
        .notificationCenterWidgetFooter: [
            .english: "Affects widgets still set to Use App Default; individually edited widgets are unchanged.",
            .chinese: "仅影响仍使用应用默认值的小组件；单独编辑过的小组件不受影响。",
        ],
        .defaultAccount: [
            .english: "Default Account",
            .chinese: "默认账户",
        ],
        .allAccounts: [
            .english: "All Accounts",
            .chinese: "全部账户",
        ],
        .notifications: [
            .english: "Notifications",
            .chinese: "通知",
        ],
        .notificationsFooter: [
            .english: "QuotaGlance notifies you when an account balance drops below its alert threshold.",
            .chinese: "当账户余额低于告警阈值时，QuotaGlance 会通知你。",
        ],
        .lowBalanceAlerts: [
            .english: "Low Balance Alerts",
            .chinese: "低余额告警",
        ],
        .status: [
            .english: "Status",
            .chinese: "状态",
        ],
        .noAccounts: [
            .english: "No Accounts",
            .chinese: "暂无账户",
        ],
        .addProviderAccountHint: [
            .english: "Add a provider account to begin.",
            .chinese: "添加服务商账户后开始使用。",
        ],
        .deleteAccountTitle: [
            .english: "Delete Account?",
            .chinese: "删除账户？",
        ],
        .delete: [
            .english: "Delete",
            .chinese: "删除",
        ],
        .cancel: [
            .english: "Cancel",
            .chinese: "取消",
        ],
        .save: [
            .english: "Save",
            .chinese: "保存",
        ],
        .editAccount: [
            .english: "Edit Account",
            .chinese: "编辑账户",
        ],
        .moveUp: [
            .english: "Move Up",
            .chinese: "上移",
        ],
        .moveDown: [
            .english: "Move Down",
            .chinese: "下移",
        ],
        .alertBelow: [
            .english: "Alert below %@",
            .chinese: "低于 %@ 时告警",
        ],
        .notRequested: [
            .english: "Not Requested",
            .chinese: "未请求",
        ],
        .notAllowed: [
            .english: "Not Allowed",
            .chinese: "未允许",
        ],
        .allowed: [
            .english: "Allowed",
            .chinese: "已允许",
        ],
        .minute1: [
            .english: "1 minute",
            .chinese: "1 分钟",
        ],
        .minutes5: [
            .english: "5 minutes",
            .chinese: "5 分钟",
        ],
        .minutes15: [
            .english: "15 minutes",
            .chinese: "15 分钟",
        ],
        .minutes30: [
            .english: "30 minutes",
            .chinese: "30 分钟",
        ],
        .minutes60: [
            .english: "60 minutes",
            .chinese: "60 分钟",
        ],
        .savedSettingsUnreadable: [
            .english: "Saved account settings could not be read.",
            .chinese: "无法读取已保存的账户设置。",
        ],
        .keychainApprovalRequired: [
            .english: "Keychain approval is required for %d saved keys. Click Refresh to unlock.",
            .chinese: "读取 %d 个已保存密钥需要钥匙串授权。点击刷新以解锁。",
        ],
        .keychainApprovalRequiredSingular: [
            .english: "Keychain approval is required for 1 saved key. Click Refresh to unlock.",
            .chinese: "读取 1 个已保存密钥需要钥匙串授权。点击刷新以解锁。",
        ],
        .someAccountsRefreshFailed: [
            .english: "Some accounts could not be refreshed.",
            .chinese: "部分账户刷新失败。",
        ],
        .allAccountsRefreshFailed: [
            .english: "No account could be refreshed.",
            .chinese: "所有账户都未能刷新。",
        ],
        .provider: [
            .english: "Provider",
            .chinese: "服务商",
        ],
        .name: [
            .english: "Name",
            .chinese: "名称",
        ],
        .apiKey: [
            .english: "API Key",
            .chinese: "API 密钥",
        ],
        .replacementAPIKey: [
            .english: "New API Key",
            .chinese: "新 API 密钥",
        ],
        .paste: [
            .english: "Paste",
            .chinese: "粘贴",
        ],
        .pasteAPIKeyHelp: [
            .english: "Paste API key from clipboard (⌘V)",
            .chinese: "从剪贴板粘贴 API 密钥（⌘V）",
        ],
        .threshold: [
            .english: "Threshold",
            .chinese: "阈值",
        ],
        .thresholdCaption: [
            .english: "Optional low-balance alert threshold.",
            .chinese: "可选的低余额告警阈值。",
        ],
        .openRouterThresholdCaption: [
            .english: "Optional management-key low-balance alert threshold.",
            .chinese: "可选的管理密钥低余额告警阈值。",
        ],
        .enabled: [
            .english: "Enabled",
            .chinese: "启用",
        ],
        .notDetected: [
            .english: "Not detected",
            .chinese: "未检测",
        ],
        .chinaCNY: [
            .english: "China / CNY",
            .chinese: "中国 / CNY",
        ],
        .internationalUSD: [
            .english: "International / USD",
            .chinese: "国际 / USD",
        ],
        .globalCredential: [
            .english: "Global / %@",
            .chinese: "全球 / %@",
        ],
        .regionCredential: [
            .english: "%@ / %@",
            .chinese: "%@ / %@",
        ],
        .global: [
            .english: "Global",
            .chinese: "全球",
        ],
        .china: [
            .english: "China",
            .chinese: "中国",
        ],
        .international: [
            .english: "International",
            .chinese: "国际",
        ],
        .standardKey: [
            .english: "Standard key",
            .chinese: "标准密钥",
        ],
        .managementKey: [
            .english: "Management key",
            .chinese: "管理密钥",
        ],
        .tokenPlan: [
            .english: "Token Plan",
            .chinese: "Token 套餐",
        ],
        .account: [
            .english: "Account",
            .chinese: "账户",
        ],
        .requestsToday: [
            .english: "Requests today",
            .chinese: "今日请求",
        ],
        .last7Days: [
            .english: "Last 7 Days",
            .chinese: "近 7 天",
        ],
        .balances: [
            .english: "Balances",
            .chinese: "余额",
        ],
        .noMetric: [
            .english: "No metric",
            .chinese: "暂无指标",
        ],
        .connected: [
            .english: "Connected",
            .chinese: "已连接",
        ],
        .spentToday: [
            .english: "Spent today",
            .chinese: "今日花费",
        ],
        .requests: [
            .english: "Requests",
            .chinese: "请求数",
        ],
        .remaining: [
            .english: "Remaining",
            .chinese: "剩余",
        ],
        .used: [
            .english: "Used",
            .chinese: "已用",
        ],
        .limit: [
            .english: "Limit",
            .chinese: "限额",
        ],
        .spend: [
            .english: "Spend",
            .chinese: "花费",
        ],
        .today: [
            .english: "Today",
            .chinese: "今天",
        ],
        .thisWeek: [
            .english: "This week",
            .chinese: "本周",
        ],
        .thisMonth: [
            .english: "This month",
            .chinese: "本月",
        ],
        .total: [
            .english: "Total",
            .chinese: "总计",
        ],
        .quotaWindows: [
            .english: "Quota Windows",
            .chinese: "配额窗口",
        ],
        .resetsRelative: [
            .english: "Resets %@",
            .chinese: "重置：%@",
        ],
        .topModels: [
            .english: "Top Models",
            .chinese: "热门模型",
        ],
        .noData: [
            .english: "No Data",
            .chinese: "暂无数据",
        ],
        .retry: [
            .english: "Retry",
            .chinese: "重试",
        ],
        .settings: [
            .english: "Settings",
            .chinese: "设置",
        ],
        .openDashboard: [
            .english: "Open Dashboard",
            .chinese: "打开仪表盘",
        ],
        .quit: [
            .english: "Quit",
            .chinese: "退出",
        ],
        .upToDate: [
            .english: "Up to Date",
            .chinese: "已是最新",
        ],
        .lowBalance: [
            .english: "Low Balance",
            .chinese: "余额不足",
        ],
        .partialData: [
            .english: "Partial Data",
            .chinese: "部分数据",
        ],
        .keychainLocked: [
            .english: "Keychain Locked",
            .chinese: "钥匙串已锁定",
        ],
        .savedData: [
            .english: "Saved Data",
            .chinese: "已保存数据",
        ],
        .unavailable: [
            .english: "Unavailable",
            .chinese: "不可用",
        ],
        .percentUsed: [
            .english: "% used",
            .chinese: "% 已用",
        ],
        .providerOverview: [
            .english: "Providers",
            .chinese: "服务商总览",
        ],
        .oneAccount: [
            .english: "1 account",
            .chinese: "1 个账户",
        ],
        .accountCount: [
            .english: "%d accounts",
            .chinese: "%d 个账户",
        ],
        .disabled: [
            .english: "Disabled",
            .chinese: "已停用",
        ],
        .healthy: [
            .english: "Healthy",
            .chinese: "正常",
        ],
        .requestShare: [
            .english: "Request share",
            .chinese: "请求占比",
        ],
        .todayMetrics: [
            .english: "Today",
            .chinese: "今日指标",
        ],
        .totalMetrics: [
            .english: "All Time",
            .chinese: "累计指标",
        ],
        .inputTokens: [
            .english: "Input tokens",
            .chinese: "输入 Token",
        ],
        .outputTokens: [
            .english: "Output tokens",
            .chinese: "输出 Token",
        ],
        .cacheReadTokens: [
            .english: "Cache read tokens",
            .chinese: "缓存读取 Token",
        ],
        .cacheCreationTokens: [
            .english: "Cache creation tokens",
            .chinese: "缓存写入 Token",
        ],
        .totalTokens: [
            .english: "Total tokens",
            .chinese: "Token 总数",
        ],
        .providerStatus: [
            .english: "Provider status",
            .chinese: "服务商状态",
        ],
        .metricsUnavailable: [
            .english: "Metrics unavailable",
            .chinese: "指标不可用",
        ],
        .lastSuccessfulRefresh: [
            .english: "Last successful refresh",
            .chinese: "最近成功刷新",
        ],
        .modelUsage: [
            .english: "Model Usage",
            .chinese: "模型用量",
        ],
        .sevenDayUsage: [
            .english: "Seven day usage",
            .chinese: "近七天用量",
        ],
        .currencyBalance: [
            .english: "%@ balance",
            .chinese: "%@ 余额",
        ],
        .balance: [
            .english: "Balance",
            .chinese: "余额",
        ],
        .spentThisMonth: [
            .english: "Spent this month",
            .chinese: "本月花费",
        ],
        .spentThisWeek: [
            .english: "Spent this week",
            .chinese: "本周花费",
        ],
        .totalSpent: [
            .english: "Total spent",
            .chinese: "累计花费",
        ],
        .accountUnavailable: [
            .english: "Account Unavailable",
            .chinese: "账户不可用",
        ],
        .lowBalanceTitle: [
            .english: "Low Balance: %@",
            .chinese: "余额不足：%@",
        ],
        .lowBalanceBody: [
            .english: "Remaining balance is %@.",
            .chinese: "当前剩余余额为 %@。",
        ],
        .quitQuotaGlance: [
            .english: "Quit QuotaGlance",
            .chinese: "退出 QuotaGlance",
        ],
        .edit: [
            .english: "Edit",
            .chinese: "编辑",
        ],
        .cut: [
            .english: "Cut",
            .chinese: "剪切",
        ],
        .copy: [
            .english: "Copy",
            .chinese: "拷贝",
        ],
        .selectAll: [
            .english: "Select All",
            .chinese: "全选",
        ],
        .errorEmptyDisplayName: [
            .english: "Enter an account name.",
            .chinese: "请输入账户名称。",
        ],
        .errorEmptyAPIKey: [
            .english: "Enter an API key.",
            .chinese: "请输入 API 密钥。",
        ],
        .errorMaximumAccounts: [
            .english: "QuotaGlance supports up to %d accounts.",
            .chinese: "QuotaGlance 最多支持 %d 个账户。",
        ],
        .errorDuplicateDisplayName: [
            .english: "Account names must be unique.",
            .chinese: "账户名称不能重复。",
        ],
        .errorInvalidThreshold: [
            .english: "Enter a valid non-negative threshold.",
            .chinese: "请输入有效的非负阈值。",
        ],
        .errorReplacementKeyRequired: [
            .english: "Enter a replacement key when changing providers.",
            .chinese: "更换服务商时请输入新的密钥。",
        ],
        .errorInvalidCredential: [
            .english: "The provider rejected this key.",
            .chinese: "服务商拒绝了此密钥。",
        ],
        .errorRateLimited: [
            .english: "The provider is rate limiting requests. Try again later.",
            .chinese: "服务商正在限流，请稍后重试。",
        ],
        .errorHTTPStatus: [
            .english: "The provider returned HTTP %d. Try again later.",
            .chinese: "服务商返回 HTTP %d，请稍后重试。",
        ],
        .errorUnsupportedCredential: [
            .english: "MiniMax pay-as-you-go keys are not supported. Add a Token or Coding Plan subscription key.",
            .chinese: "不支持 MiniMax 按量计费密钥。请添加 Token 或 Coding Plan 订阅密钥。",
        ],
        .errorRegionDetectionFailed: [
            .english: "Neither official regional endpoint accepted this key. Check the key and try again.",
            .chinese: "官方区域节点均未接受此密钥，请检查后重试。",
        ],
        .errorProfileMismatch: [
            .english: "The saved key type no longer matches this account. Replace the key to detect it again.",
            .chinese: "已保存的密钥类型与此账户不匹配，请更换密钥以重新检测。",
        ],
        .errorInvalidResponse: [
            .english: "The provider returned an unexpected response.",
            .chinese: "服务商返回了意外响应。",
        ],
        .errorProviderUnavailable: [
            .english: "This provider is not available in this build.",
            .chinese: "此构建不包含该服务商。",
        ],
        .errorCredentialNotFound: [
            .english: "The API key is missing from Keychain.",
            .chinese: "钥匙串中缺少 API 密钥。",
        ],
        .errorCredentialInvalidData: [
            .english: "The saved API key in Keychain is invalid. Replace the key and try again.",
            .chinese: "钥匙串中保存的 API 密钥无效，请更换后重试。",
        ],
        .errorCredentialInteractionRequired: [
            .english: "Keychain approval is required for saved API keys. Click Refresh to unlock them.",
            .chinese: "读取已保存的 API 密钥需要钥匙串授权。点击刷新以解锁。",
        ],
        .errorKeychainMissingBuild: [
            .english: "QuotaGlance could not access Keychain because this app build is no longer on disk. Quit and reopen the installed app, then try again.",
            .chinese: "无法访问钥匙串，因为当前应用构建已不在磁盘上。请退出并重新打开已安装的应用后再试。",
        ],
        .errorKeychainStatus: [
            .english: "QuotaGlance could not access Keychain (status %d). Reopen the app and try again.",
            .chinese: "无法访问钥匙串（状态 %d）。请重新打开应用后再试。",
        ],
        .errorNoInternet: [
            .english: "No internet connection is available. Check the network and try again.",
            .chinese: "当前无网络连接，请检查网络后重试。",
        ],
        .errorTimedOut: [
            .english: "The provider request timed out. Try again later.",
            .chinese: "请求服务商超时，请稍后重试。",
        ],
        .errorHostUnreachable: [
            .english: "The provider host could not be reached. Check the network and try again.",
            .chinese: "无法连接服务商主机，请检查网络后重试。",
        ],
        .errorSecureConnectionFailed: [
            .english: "A secure connection to the provider could not be established.",
            .chinese: "无法与服务商建立安全连接。",
        ],
        .errorCancelled: [
            .english: "The provider request was cancelled. Try again.",
            .chinese: "服务商请求已取消，请重试。",
        ],
        .errorNetworkInterrupted: [
            .english: "A network error interrupted the provider request (%d). Try again.",
            .chinese: "网络错误中断了服务商请求（%d），请重试。",
        ],
        .errorGeneric: [
            .english: "The operation could not be completed.",
            .chinese: "无法完成此操作。",
        ],
    ]
}
