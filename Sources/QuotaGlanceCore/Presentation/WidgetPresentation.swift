import Foundation

public enum WidgetSelection: Hashable, Sendable {
    case allAccounts
    case account(UUID)
}

public enum WidgetPresentationState: Equatable, Sendable {
    case available(DashboardStatus)
    case noSnapshot
    case deletedAccount
}

public struct WidgetPresentation: Equatable, Sendable {
    public var title: String
    public var balances: [Money]
    public var remaining: Money?
    public var primaryMetric: PrimaryMetric?
    public var todayActualCost: Money?
    public var todayRequests: Int64?
    public var dailyUsage: [DailyUsage]
    public var accountRows: [CompactAccountPresentation]
    public var metricsUnavailableReason: String?
    public var state: WidgetPresentationState
    public var lastSuccessAt: Date?
    public var capturedAt: Date?
    public var deepLink: URL?

    public init(
        title: String,
        balances: [Money] = [],
        remaining: Money? = nil,
        primaryMetric: PrimaryMetric? = nil,
        todayActualCost: Money? = nil,
        todayRequests: Int64? = nil,
        dailyUsage: [DailyUsage] = [],
        accountRows: [CompactAccountPresentation] = [],
        metricsUnavailableReason: String? = nil,
        state: WidgetPresentationState,
        lastSuccessAt: Date? = nil,
        capturedAt: Date? = nil,
        deepLink: URL? = nil
    ) {
        self.title = title
        self.balances = balances
        self.remaining = remaining
        self.primaryMetric = primaryMetric
        self.todayActualCost = todayActualCost
        self.todayRequests = todayRequests
        self.dailyUsage = dailyUsage
        self.accountRows = accountRows
        self.metricsUnavailableReason = metricsUnavailableReason
        self.state = state
        self.lastSuccessAt = lastSuccessAt
        self.capturedAt = capturedAt
        self.deepLink = deepLink
    }
}

public enum WidgetPresenter {
    public static func make(
        selection: WidgetSelection,
        envelope: WidgetSnapshotEnvelope?
    ) -> WidgetPresentation {
        guard let envelope else {
            return WidgetPresentation(
                title: "QuotaGlance",
                state: .noSnapshot,
                deepLink: URL(string: "quotaglance://all")
            )
        }

        let dashboardSelection: DashboardSelection
        let deepLink: URL?
        switch selection {
        case .allAccounts:
            dashboardSelection = .allAccounts
            deepLink = URL(string: "quotaglance://all")
        case let .account(accountID):
            dashboardSelection = .account(accountID)
            deepLink = URL(string: "quotaglance://account/\(accountID.uuidString)")
        }

        guard let dashboard = DashboardPresenter.make(
            selection: dashboardSelection,
            envelope: envelope
        ) else {
            return WidgetPresentation(
                title: "Account Unavailable",
                state: .deletedAccount,
                capturedAt: envelope.capturedAt,
                deepLink: deepLink
            )
        }

        let accountRows = dashboard.accountRows.map {
            CompactAccountPresentation(account: $0)
        }
        let primaryMetric: PrimaryMetric?
        switch selection {
        case .allAccounts:
            primaryMetric = dashboard.primaryMetric
                ?? accountRows.compactMap(\.primaryMetric).first
        case .account:
            primaryMetric = dashboard.primaryMetric
        }

        return WidgetPresentation(
            title: dashboard.title,
            balances: Array(dashboard.balances.prefix(2)),
            remaining: dashboard.remaining,
            primaryMetric: primaryMetric,
            todayActualCost: dashboard.todayActualCost,
            todayRequests: dashboard.todayRequests,
            dailyUsage: dashboard.dailyUsage,
            accountRows: accountRows,
            metricsUnavailableReason: dashboard.metricsUnavailableReason
                ?? accountRows.compactMap(\.metricsUnavailableReason).first,
            state: .available(dashboard.status),
            lastSuccessAt: dashboard.lastSuccessAt,
            capturedAt: envelope.capturedAt,
            deepLink: deepLink
        )
    }
}
