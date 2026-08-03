import Foundation

public enum ProviderOverviewStatus: Equatable, Sendable {
    case disabled
    case unavailable
    case partial
    case belowThreshold
    case healthy
}

public struct ProviderOverviewRow: Equatable, Identifiable, Sendable {
    public var id: ProviderID { provider }
    public let provider: ProviderID
    public let displayName: String
    public let accountCount: Int
    public let enabledAccountCount: Int
    public let accountCountText: String
    public let balances: [Money]
    public let todayActualCosts: [Money]
    public let todayRequests: Int64?
    public var requestShare: Decimal?
    public let primaryMetric: PrimaryMetric?
    public let status: ProviderOverviewStatus

    public init(
        provider: ProviderID,
        displayName: String,
        accountCount: Int,
        enabledAccountCount: Int,
        accountCountText: String,
        balances: [Money],
        todayActualCosts: [Money],
        todayRequests: Int64?,
        requestShare: Decimal?,
        primaryMetric: PrimaryMetric?,
        status: ProviderOverviewStatus
    ) {
        self.provider = provider
        self.displayName = displayName
        self.accountCount = accountCount
        self.enabledAccountCount = enabledAccountCount
        self.accountCountText = accountCountText
        self.balances = balances
        self.todayActualCosts = todayActualCosts
        self.todayRequests = todayRequests
        self.requestShare = requestShare
        self.primaryMetric = primaryMetric
        self.status = status
    }
}

public struct ProviderOverviewPresentation: Equatable, Sendable {
    public let rows: [ProviderOverviewRow]
    public let totalRequests: Int64?

    public init(rows: [ProviderOverviewRow], totalRequests: Int64?) {
        self.rows = rows
        self.totalRequests = totalRequests
    }
}

public enum ProviderOverviewPresenter {
    public static func make(
        accounts: [Account],
        envelope: WidgetSnapshotEnvelope?,
        language: AppLanguage = .english
    ) -> ProviderOverviewPresentation {
        let snapshotsByID = (envelope?.accounts ?? []).reduce(
            into: [UUID: AccountSnapshot]()
        ) { result, snapshot in
            result[snapshot.accountID] = snapshot
        }
        let grouped = Dictionary(grouping: accounts, by: \.provider)
        let orderedGroups = grouped.sorted { left, right in
            let leftOrder = left.value.map(\.sortOrder).min() ?? .max
            let rightOrder = right.value.map(\.sortOrder).min() ?? .max
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            return left.key.rawValue < right.key.rawValue
        }

        var rows = orderedGroups.map { provider, providerAccounts in
            makeRow(
                provider: provider,
                accounts: providerAccounts,
                snapshotsByID: snapshotsByID,
                language: language
            )
        }

        let enabledIndices = rows.indices.filter {
            rows[$0].enabledAccountCount > 0
        }
        guard !enabledIndices.isEmpty,
              enabledIndices.allSatisfy({ rows[$0].todayRequests != nil }) else {
            return ProviderOverviewPresentation(rows: rows, totalRequests: nil)
        }

        var totalRequests: Int64 = 0
        for index in enabledIndices {
            guard let requests = rows[index].todayRequests,
                  requests >= 0 else {
                return ProviderOverviewPresentation(rows: rows, totalRequests: nil)
            }
            let addition = totalRequests.addingReportingOverflow(requests)
            guard !addition.overflow else {
                return ProviderOverviewPresentation(rows: rows, totalRequests: nil)
            }
            totalRequests = addition.partialValue
        }
        guard totalRequests > 0 else {
            return ProviderOverviewPresentation(rows: rows, totalRequests: nil)
        }

        for index in enabledIndices {
            guard let requests = rows[index].todayRequests else { continue }
            rows[index].requestShare = Decimal(requests) / Decimal(totalRequests)
        }
        return ProviderOverviewPresentation(
            rows: rows,
            totalRequests: totalRequests
        )
    }

    private static func makeRow(
        provider: ProviderID,
        accounts: [Account],
        snapshotsByID: [UUID: AccountSnapshot],
        language: AppLanguage
    ) -> ProviderOverviewRow {
        let enabledAccounts = accounts.filter(\.isEnabled)
        let snapshots = enabledAccounts.compactMap { snapshotsByID[$0.id] }
        let balances = sumMoney(
            snapshots.flatMap { $0.usage?.balances.map(\.available) ?? [] }
        )
        let todayActualCosts = sumMoney(
            snapshots.compactMap { snapshot in
                snapshot.usage?.spend.today ?? snapshot.usage?.today?.actualCost
            }
        )
        let todayRequests = completeRequestTotal(
            accounts: enabledAccounts,
            snapshotsByID: snapshotsByID
        )
        let primaryMetric: PrimaryMetric?
        if enabledAccounts.count == 1,
           let snapshot = snapshotsByID[enabledAccounts[0].id],
           isPureQuota(snapshot.usage) {
            primaryMetric = DashboardPresenter.primaryMetric(
                for: snapshot.usage,
                language: language
            )
        } else {
            primaryMetric = nil
        }

        return ProviderOverviewRow(
            provider: provider,
            displayName: ProviderCatalog.descriptor(for: provider).displayName,
            accountCount: accounts.count,
            enabledAccountCount: enabledAccounts.count,
            accountCountText: accountCountText(accounts.count, language: language),
            balances: balances,
            todayActualCosts: todayActualCosts,
            todayRequests: todayRequests,
            requestShare: nil,
            primaryMetric: primaryMetric,
            status: status(
                accounts: enabledAccounts,
                snapshotsByID: snapshotsByID
            )
        )
    }

    private static func status(
        accounts: [Account],
        snapshotsByID: [UUID: AccountSnapshot]
    ) -> ProviderOverviewStatus {
        guard !accounts.isEmpty else { return .disabled }
        let snapshots = accounts.map { snapshotsByID[$0.id] }
        let unavailableCount = snapshots.filter { snapshot in
            guard let snapshot = snapshot else { return true }
            if case .unavailable = snapshot.health { return true }
            return false
        }.count
        if unavailableCount == accounts.count { return .unavailable }
        if snapshots.contains(where: { snapshot in
            guard let snapshot = snapshot, snapshot.usage != nil else { return true }
            switch snapshot.health {
            case .stale, .unavailable:
                return true
            case .healthy, .belowThreshold:
                return false
            }
        }) {
            return .partial
        }
        if snapshots.contains(where: { $0?.health == .belowThreshold }) {
            return .belowThreshold
        }
        return .healthy
    }

    private static func completeRequestTotal(
        accounts: [Account],
        snapshotsByID: [UUID: AccountSnapshot]
    ) -> Int64? {
        guard !accounts.isEmpty else { return nil }
        var total: Int64 = 0
        for account in accounts {
            guard let snapshot = snapshotsByID[account.id],
                  isFresh(snapshot.health),
                  let requests = snapshot.usage?.today?.requests,
                  requests >= 0 else {
                return nil
            }
            let addition = total.addingReportingOverflow(requests)
            guard !addition.overflow else { return nil }
            total = addition.partialValue
        }
        return total
    }

    private static func isFresh(_ health: AccountHealth) -> Bool {
        switch health {
        case .healthy, .belowThreshold:
            true
        case .stale, .unavailable:
            false
        }
    }

    private static func isPureQuota(_ usage: ProviderUsageSnapshot?) -> Bool {
        guard let usage = usage else { return false }
        return usage.balances.isEmpty
            && usage.spendingLimit == nil
            && usage.spend.isEmpty
            && usage.today?.actualCost == nil
            && !usage.quotaWindows.isEmpty
    }

    private static func sumMoney(_ values: [Money]) -> [Money] {
        var totals: [String: Decimal] = [:]
        for value in values {
            totals[value.currency, default: 0] += value.amount
        }
        return totals.keys.sorted().map { currency in
            Money(amount: totals[currency] ?? 0, currency: currency)
        }
    }

    private static func accountCountText(
        _ count: Int,
        language: AppLanguage
    ) -> String {
        if count == 1 {
            return L10n.string(.oneAccount, language: language)
        }
        return L10n.string(.accountCount, language: language, count)
    }
}
