import Foundation

public struct SnapshotAggregator: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func aggregate(
        accounts: [Account],
        snapshots: [AccountSnapshot],
        now: Date
    ) -> AggregateSnapshot {
        let enabledAccounts = accounts
            .filter(\.isEnabled)
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.id.uuidString < $1.id.uuidString
            }
        let snapshotsByID = Dictionary(
            snapshots.map { ($0.accountID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let orderedSnapshots: [AccountSnapshot] = enabledAccounts.compactMap { account in
            guard var snapshot = snapshotsByID[account.id] else { return nil }
            snapshot.displayName = account.displayName
            snapshot.provider = account.provider
            snapshot.detectedProfile = account.detectedProfile
            snapshot.lowBalanceThreshold = account.lowBalanceThreshold
            return snapshot
        }

        let balanceValues = orderedSnapshots.flatMap { snapshot in
            snapshot.usage?.balances.map(\.available) ?? []
        }
        let balances = sumMoneyByCurrency(balanceValues)
        let todayCostValues = orderedSnapshots.compactMap { snapshot in
            snapshot.usage?.spend.today ?? snapshot.usage?.today?.actualCost
        }
        let todayCost = todayCostValues.count == orderedSnapshots.count
            ? sumMoney(todayCostValues)
            : nil
        let todayRequestValues = orderedSnapshots.compactMap(\.usage?.today?.requests)
        let hasAllTodayRequests = todayRequestValues.count == orderedSnapshots.count
        let todayRequests = hasAllTodayRequests
            ? sumIntegers(todayRequestValues)
            : nil
        let todayRequestsOverflowed = hasAllTodayRequests
            && !todayRequestValues.isEmpty
            && todayRequests == nil
        let dailyUsage = makeDailyUsage(
            snapshots: orderedSnapshots,
            fallbackCurrency: balances.count == 1 ? balances[0].currency : nil,
            now: now
        )
        let isPartial = orderedSnapshots.count != enabledAccounts.count
            || todayRequestsOverflowed
            || orderedSnapshots.contains { snapshot in
                switch snapshot.health {
                case .stale, .unavailable:
                    true
                case .healthy, .belowThreshold:
                    false
                }
            }

        return AggregateSnapshot(
            balances: balances,
            todayActualCost: todayCost,
            todayRequests: todayRequests,
            dailyUsage: dailyUsage,
            accounts: orderedSnapshots,
            isPartial: isPartial
        )
    }
}

private extension SnapshotAggregator {
    func sumMoneyByCurrency(_ values: [Money]) -> [Money] {
        Dictionary(grouping: values, by: \.currency)
            .keys
            .sorted()
            .compactMap { currency in
                sumMoney(values.filter { $0.currency == currency })
            }
    }

    func sumMoney(_ values: [Money]) -> Money? {
        guard let first = values.first else { return nil }
        guard values.allSatisfy({ $0.currency == first.currency }) else {
            return nil
        }
        return Money(
            amount: values.reduce(Decimal.zero) { $0 + $1.amount },
            currency: first.currency
        )
    }

    func sumIntegers(_ values: [Int64]) -> Int64? {
        guard !values.isEmpty else { return nil }
        var total: Int64 = 0
        for value in values {
            let result = total.addingReportingOverflow(value)
            guard !result.overflow else { return nil }
            total = result.partialValue
        }
        return total
    }

    func makeDailyUsage(
        snapshots: [AccountSnapshot],
        fallbackCurrency: String?,
        now: Date
    ) -> [DailyUsage] {
        let entries = snapshots.flatMap { $0.usage?.dailyUsage ?? [] }
        guard !entries.isEmpty else { return [] }
        let currency = entries.first?.actualCost.currency ?? fallbackCurrency
        guard let currency else { return [] }
        guard entries.allSatisfy({ $0.actualCost.currency == currency }) else {
            return []
        }

        let formatter = providerDateFormatter()
        let parsedEntries = entries.compactMap { entry -> (Date, DailyUsage)? in
            guard let date = formatter.date(from: entry.date) else { return nil }
            return (calendar.startOfDay(for: date), entry)
        }
        guard !parsedEntries.isEmpty else { return [] }

        let localDay = calendar.startOfDay(for: now)
        let endDay = parsedEntries.map(\.0).max().map { max($0, localDay) } ?? localDay
        var grouped: [Date: [DailyUsage]] = [:]
        for (date, entry) in parsedEntries {
            grouped[date, default: []].append(entry)
        }

        return (0..<7).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index - 6, to: endDay) else {
                return nil
            }
            let values = grouped[date] ?? []
            return DailyUsage(
                date: formatter.string(from: date),
                actualCost: Money(
                    amount: values.reduce(Decimal.zero) { $0 + $1.actualCost.amount },
                    currency: currency
                ),
                requests: sumIntegers(values.compactMap(\.requests)),
                totalTokens: sumIntegers(values.compactMap(\.totalTokens))
            )
        }
    }

    func providerDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
