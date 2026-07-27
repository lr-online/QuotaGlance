import Foundation

public struct MenuBarDayPresentation: Equatable, Identifiable, Sendable {
    public var id: String { date }
    public let date: String
    public let label: String
    public let actualCost: Money
}

public struct MenuBarQuotaPresentation: Equatable, Sendable {
    public let used: Money?
    public let limit: Money?
    public let fraction: Double?
}

public struct MenuBarPresentation: Equatable, Sendable {
    public let title: String
    public let balances: [Money]
    public let remaining: Money?
    public let primaryMetric: PrimaryMetric?
    public let todayActualCost: Money?
    public let todayRequests: Int64?
    public let days: [MenuBarDayPresentation]
    public let accountRows: [CompactAccountPresentation]
    public let balanceRows: [MonetaryBalance]
    public let spendingLimit: SpendingLimit?
    public let spend: SpendSummary
    public let quotaWindows: [QuotaWindow]
    public let quota: MenuBarQuotaPresentation?
    public let modelRows: [ModelUsage]
    public let status: DashboardStatus
    public let lastSuccessAt: Date?
}

public struct MenuBarPanelSize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public enum MenuBarPanelLayout {
    public static let fixedContentSize = MenuBarPanelSize(
        width: 360,
        height: 500
    )
}

public enum MenuBarPresenter {
    public static func make(
        selection: DashboardSelection,
        envelope: WidgetSnapshotEnvelope
    ) -> MenuBarPresentation? {
        guard let dashboard = DashboardPresenter.make(
            selection: selection,
            envelope: envelope
        ) else {
            return nil
        }

        return MenuBarPresentation(
            title: dashboard.title,
            balances: dashboard.balances,
            remaining: dashboard.remaining,
            primaryMetric: dashboard.primaryMetric,
            todayActualCost: dashboard.todayActualCost,
            todayRequests: dashboard.todayRequests,
            days: makeDays(dashboard.dailyUsage),
            accountRows: dashboard.accountRows.prefix(5).map {
                CompactAccountPresentation(account: $0)
            },
            balanceRows: dashboard.usage?.balances ?? [],
            spendingLimit: dashboard.usage?.spendingLimit,
            spend: dashboard.usage?.spend ?? SpendSummary(),
            quotaWindows: dashboard.usage?.quotaWindows ?? [],
            quota: makeQuota(dashboard.usage),
            modelRows: makeModelRows(dashboard.usage?.modelUsage ?? []),
            status: dashboard.status,
            lastSuccessAt: dashboard.lastSuccessAt
        )
    }

    private static func makeDays(
        _ dailyUsage: [DailyUsage]
    ) -> [MenuBarDayPresentation] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false

        let indexed = dailyUsage.enumerated().map { index, usage in
            (index: index, usage: usage, date: formatter.date(from: usage.date))
        }
        let ordered: [DailyUsage]
        if indexed.allSatisfy({ $0.date != nil }) {
            ordered = indexed.sorted { lhs, rhs in
                guard lhs.date != rhs.date else { return lhs.index < rhs.index }
                return lhs.date! < rhs.date!
            }.map(\.usage)
        } else {
            ordered = dailyUsage
        }

        return ordered.suffix(7).map { usage in
            MenuBarDayPresentation(
                date: usage.date,
                label: dayLabel(usage.date, formatter: formatter),
                actualCost: usage.actualCost
            )
        }
    }

    private static func dayLabel(
        _ value: String,
        formatter: DateFormatter
    ) -> String {
        if formatter.date(from: value) != nil,
           let component = value.split(separator: "-").last,
           let day = Int(component) {
            return String(day)
        }
        let fallback = String(value.prefix(3))
        return fallback.isEmpty ? "--" : fallback
    }

    private static func makeQuota(
        _ usage: ProviderUsageSnapshot?
    ) -> MenuBarQuotaPresentation? {
        guard let usage,
              usage.quotaUsed != nil || usage.quotaLimit != nil else {
            return nil
        }

        var fraction: Double?
        if let used = usage.quotaUsed,
           let limit = usage.quotaLimit,
           used.currency == limit.currency,
           limit.amount > 0 {
            let raw = NSDecimalNumber(
                decimal: used.amount / limit.amount
            ).doubleValue
            fraction = min(max(raw, 0), 1)
        }

        return MenuBarQuotaPresentation(
            used: usage.quotaUsed,
            limit: usage.quotaLimit,
            fraction: fraction
        )
    }

    private static func makeModelRows(
        _ models: [ModelUsage]
    ) -> [ModelUsage] {
        models.enumerated().sorted { lhs, rhs in
            switch (lhs.element.actualCost, rhs.element.actualCost) {
            case let (left?, right?) where left.amount != right.amount:
                return left.amount > right.amount
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.offset < rhs.offset
            }
        }
        .prefix(2)
        .map(\.element)
    }
}
