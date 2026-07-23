import Foundation

public enum DashboardSelection: Hashable, Sendable {
    case allAccounts
    case account(UUID)
}

public enum DashboardStatus: Equatable, Sendable {
    case healthy
    case belowThreshold
    case partial
    case stale(SnapshotFailure)
    case unavailable(SnapshotFailure)
    case empty
}

public struct DashboardPresentation: Equatable, Sendable {
    public var title: String
    public var remaining: Money?
    public var todayActualCost: Money?
    public var todayRequests: Int64?
    public var dailyUsage: [DailyUsage]
    public var accountRows: [AccountSnapshot]
    public var usage: ProviderUsageSnapshot?
    public var status: DashboardStatus
    public var lastSuccessAt: Date?

    public init(
        title: String,
        remaining: Money?,
        todayActualCost: Money?,
        todayRequests: Int64?,
        dailyUsage: [DailyUsage],
        accountRows: [AccountSnapshot],
        usage: ProviderUsageSnapshot?,
        status: DashboardStatus,
        lastSuccessAt: Date?
    ) {
        self.title = title
        self.remaining = remaining
        self.todayActualCost = todayActualCost
        self.todayRequests = todayRequests
        self.dailyUsage = dailyUsage
        self.accountRows = accountRows
        self.usage = usage
        self.status = status
        self.lastSuccessAt = lastSuccessAt
    }
}

public enum DashboardPresenter {
    public static func make(
        selection: DashboardSelection,
        envelope: WidgetSnapshotEnvelope
    ) -> DashboardPresentation? {
        switch selection {
        case .allAccounts:
            let aggregate = envelope.aggregate
            return DashboardPresentation(
                title: "All Accounts",
                remaining: aggregate.remaining,
                todayActualCost: aggregate.todayActualCost,
                todayRequests: aggregate.todayRequests,
                dailyUsage: aggregate.dailyUsage,
                accountRows: aggregate.accounts,
                usage: nil,
                status: aggregate.accounts.isEmpty
                    ? .empty
                    : aggregate.isPartial ? .partial : .healthy,
                lastSuccessAt: aggregate.accounts.compactMap(\.lastSuccessAt).max()
            )

        case let .account(accountID):
            guard let account = envelope.accounts.first(where: {
                $0.accountID == accountID
            }) else {
                return nil
            }
            return DashboardPresentation(
                title: account.displayName,
                remaining: account.usage?.remaining,
                todayActualCost: account.usage?.today?.actualCost,
                todayRequests: account.usage?.today?.requests,
                dailyUsage: account.usage?.dailyUsage ?? [],
                accountRows: [],
                usage: account.usage,
                status: status(for: account.health),
                lastSuccessAt: account.lastSuccessAt
            )
        }
    }

    private static func status(for health: AccountHealth) -> DashboardStatus {
        switch health {
        case .healthy:
            .healthy
        case .belowThreshold:
            .belowThreshold
        case let .stale(failure):
            .stale(failure)
        case let .unavailable(failure):
            .unavailable(failure)
        }
    }
}

public enum MoneyFormatter {
    public static func string(
        _ money: Money,
        locale: Locale = .current
    ) -> String {
        format(
            money,
            locale: locale,
            minimumFractionDigits: 2,
            maximumFractionDigits: 8
        )
    }

    public static func dashboardString(
        _ money: Money,
        locale: Locale = .current
    ) -> String {
        format(
            money,
            locale: locale,
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        )
    }

    public static func widgetString(
        _ money: Money,
        locale: Locale = .current
    ) -> String {
        format(
            money,
            locale: locale,
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        )
    }

    private static func format(
        _ money: Money,
        locale: Locale,
        minimumFractionDigits: Int,
        maximumFractionDigits: Int
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = money.currency
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.roundingMode = .halfEven
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSDecimalNumber(decimal: money.amount))
            ?? "\(money.currency) \(NSDecimalNumber(decimal: money.amount).stringValue)"
    }
}
