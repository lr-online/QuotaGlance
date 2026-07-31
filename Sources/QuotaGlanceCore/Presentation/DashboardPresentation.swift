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

public enum PrimaryMetricValue: Equatable, Sendable {
    case money(Money)
    case quantity(Decimal, unit: String)
}

public struct PrimaryMetric: Equatable, Sendable {
    public var label: String
    public var value: PrimaryMetricValue

    public init(label: String, value: PrimaryMetricValue) {
        self.label = label
        self.value = value
    }
}

public struct CompactAccountPresentation: Equatable, Identifiable, Sendable {
    public var id: UUID { accountID }
    public let accountID: UUID
    public let displayName: String
    public let health: AccountHealth
    public let primaryMetric: PrimaryMetric?
    public let metricsUnavailableReason: String?

    public init(account: AccountSnapshot, language: AppLanguage = .english) {
        accountID = account.accountID
        displayName = account.displayName
        health = account.health
        primaryMetric = DashboardPresenter.primaryMetric(
            for: account.usage,
            language: language
        )
        metricsUnavailableReason = account.usage?.metricsUnavailableReason
    }
}

public enum PrimaryMetricFormatter {
    public static func string(
        _ value: PrimaryMetricValue,
        locale: Locale = .current
    ) -> String {
        switch value {
        case let .money(money):
            return MoneyFormatter.dashboardString(money, locale: locale)
        case let .quantity(quantity, unit):
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.locale = locale
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 2
            formatter.roundingMode = .halfEven
            let number = formatter.string(
                from: NSDecimalNumber(decimal: quantity)
            ) ?? NSDecimalNumber(decimal: quantity).stringValue
            if unit.isEmpty {
                return number
            }
            if unit.hasPrefix("%") {
                return number + unit
            }
            return "\(number) \(unit)"
        }
    }
}

public struct DashboardPresentation: Equatable, Sendable {
    public var title: String
    public var balances: [Money]
    public var remaining: Money?
    public var primaryMetric: PrimaryMetric?
    public var todayActualCost: Money?
    public var todayRequests: Int64?
    public var dailyUsage: [DailyUsage]
    public var accountRows: [AccountSnapshot]
    public var usage: ProviderUsageSnapshot?
    public var metricsUnavailableReason: String?
    public var status: DashboardStatus
    public var lastSuccessAt: Date?

    public init(
        title: String,
        balances: [Money],
        remaining: Money?,
        primaryMetric: PrimaryMetric?,
        todayActualCost: Money?,
        todayRequests: Int64?,
        dailyUsage: [DailyUsage],
        accountRows: [AccountSnapshot],
        usage: ProviderUsageSnapshot?,
        metricsUnavailableReason: String? = nil,
        status: DashboardStatus,
        lastSuccessAt: Date?
    ) {
        self.title = title
        self.balances = balances
        self.remaining = remaining
        self.primaryMetric = primaryMetric
        self.todayActualCost = todayActualCost
        self.todayRequests = todayRequests
        self.dailyUsage = dailyUsage
        self.accountRows = accountRows
        self.usage = usage
        self.metricsUnavailableReason = metricsUnavailableReason
        self.status = status
        self.lastSuccessAt = lastSuccessAt
    }
}

public enum DashboardPresenter {
    public static func make(
        selection: DashboardSelection,
        envelope: WidgetSnapshotEnvelope,
        language: AppLanguage = .english
    ) -> DashboardPresentation? {
        switch selection {
        case .allAccounts:
            let aggregate = envelope.aggregate
            return DashboardPresentation(
                title: L10n.string(.allAccounts, language: language),
                balances: aggregate.balances,
                remaining: aggregate.remaining,
                primaryMetric: aggregate.remaining.map {
                    PrimaryMetric(
                        label: L10n.string(.balance, language: language),
                        value: .money($0)
                    )
                },
                todayActualCost: aggregate.todayActualCost,
                todayRequests: aggregate.todayRequests,
                dailyUsage: aggregate.dailyUsage,
                accountRows: aggregate.accounts,
                usage: nil,
                metricsUnavailableReason: aggregate.accounts.compactMap {
                    $0.usage?.metricsUnavailableReason
                }.first,
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
                balances: account.usage?.balances.map(\.available) ?? [],
                remaining: account.usage?.remaining,
                primaryMetric: primaryMetric(for: account.usage, language: language),
                todayActualCost: account.usage?.spend.today
                    ?? account.usage?.today?.actualCost,
                todayRequests: account.usage?.today?.requests,
                dailyUsage: account.usage?.dailyUsage ?? [],
                accountRows: [],
                usage: account.usage,
                metricsUnavailableReason: account.usage?.metricsUnavailableReason,
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

    public static func primaryMetric(
        for usage: ProviderUsageSnapshot?,
        language: AppLanguage = .english
    ) -> PrimaryMetric? {
        guard let usage else { return nil }
        if let balance = usage.primaryBalance {
            return PrimaryMetric(
                label: balance.label,
                value: .money(balance.available)
            )
        }
        if let spendingLimit = usage.spendingLimit,
           let remaining = spendingLimit.remaining {
            return PrimaryMetric(
                label: spendingLimit.label,
                value: .money(remaining)
            )
        }
        if let quota = usage.quotaWindows.first {
            if let remaining = quota.remaining {
                return PrimaryMetric(
                    label: quota.label,
                    value: .quantity(remaining, unit: quota.unit)
                )
            }
            if let used = quota.used, let limit = quota.limit, limit > 0 {
                return PrimaryMetric(
                    label: quota.label,
                    value: .quantity(
                        used / limit * 100,
                        unit: L10n.string(.percentUsed, language: language)
                    )
                )
            }
        }
        if let month = usage.spend.month {
            return PrimaryMetric(
                label: L10n.string(.spentThisMonth, language: language),
                value: .money(month)
            )
        }
        if let week = usage.spend.week {
            return PrimaryMetric(
                label: L10n.string(.spentThisWeek, language: language),
                value: .money(week)
            )
        }
        if let today = usage.spend.today {
            return PrimaryMetric(
                label: L10n.string(.spentToday, language: language),
                value: .money(today)
            )
        }
        if let total = usage.spend.total {
            return PrimaryMetric(
                label: L10n.string(.totalSpent, language: language),
                value: .money(total)
            )
        }
        return nil
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
