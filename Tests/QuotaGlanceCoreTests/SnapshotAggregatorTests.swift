import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Snapshot aggregation")
struct SnapshotAggregatorTests {
    @Test("Two healthy accounts sum money and fill seven calendar days")
    func healthyAccountsSumAndFillSevenDays() throws {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let accounts = [
            Account(id: first, displayName: "Primary", sortOrder: 0),
            Account(id: second, displayName: "Backup", sortOrder: 1),
        ]
        let snapshots = [
            accountSnapshot(
                id: first,
                name: "Primary",
                remaining: "544.05",
                todayCost: "12.00",
                todayRequests: 40,
                daily: [("2026-07-22", "12.00")]
            ),
            accountSnapshot(
                id: second,
                name: "Backup",
                remaining: "100.00",
                todayCost: "3.00",
                todayRequests: 2,
                daily: [("2026-07-21", "3.00")]
            ),
        ]

        let aggregate = SnapshotAggregator(calendar: utcCalendar).aggregate(
            accounts: accounts,
            snapshots: snapshots,
            now: try #require(utcDate("2026-07-22T12:00:00Z"))
        )

        #expect(aggregate.remaining == usd("644.05"))
        #expect(aggregate.todayActualCost == usd("15.00"))
        #expect(aggregate.todayRequests == 42)
        #expect(aggregate.dailyUsage.map(\.date) == [
            "2026-07-16", "2026-07-17", "2026-07-18", "2026-07-19",
            "2026-07-20", "2026-07-21", "2026-07-22",
        ])
        #expect(aggregate.dailyUsage.map(\.actualCost.amount) == [
            0, 0, 0, 0, 0, Decimal(string: "3.00")!, Decimal(string: "12.00")!,
        ])
        #expect(aggregate.accounts.map(\.accountID) == [first, second])
        #expect(!aggregate.isPartial)
    }

    @Test("A stale account keeps its last value and marks the aggregate partial")
    func staleAccountKeepsValueAndMarksPartial() {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let accounts = [
            Account(id: first, displayName: "Primary", sortOrder: 0),
            Account(id: second, displayName: "Backup", sortOrder: 1),
        ]
        let snapshots = [
            accountSnapshot(id: first, name: "Primary", remaining: "544.05"),
            accountSnapshot(
                id: second,
                name: "Backup",
                remaining: "100.00",
                health: .stale(.offline)
            ),
        ]

        let aggregate = SnapshotAggregator(calendar: utcCalendar).aggregate(
            accounts: accounts,
            snapshots: snapshots,
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(aggregate.remaining == usd("644.05"))
        #expect(aggregate.accounts.count == 2)
        #expect(aggregate.isPartial)
    }

    @Test("Disabled accounts are excluded from aggregate values and rows")
    func disabledAccountsAreExcluded() {
        let enabled = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let disabled = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let accounts = [
            Account(id: enabled, displayName: "Enabled", sortOrder: 0),
            Account(
                id: disabled,
                displayName: "Disabled",
                isEnabled: false,
                sortOrder: 1
            ),
        ]
        let snapshots = [
            accountSnapshot(id: enabled, name: "Enabled", remaining: "100"),
            accountSnapshot(id: disabled, name: "Disabled", remaining: "900"),
        ]

        let aggregate = SnapshotAggregator(calendar: utcCalendar).aggregate(
            accounts: accounts,
            snapshots: snapshots,
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(aggregate.remaining == usd("100"))
        #expect(aggregate.accounts.map(\.accountID) == [enabled])
        #expect(!aggregate.isPartial)
    }

    @Test("Five accounts follow configured sort order")
    func fiveAccountsFollowSortOrder() {
        let ids = (1...5).map {
            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))!
        }
        let inputOrder = [4, 2, 0, 3, 1]
        let accounts = inputOrder.map { index in
            Account(
                id: ids[index],
                displayName: "Account \(index + 1)",
                sortOrder: index
            )
        }
        let snapshots = inputOrder.reversed().map { index in
            accountSnapshot(
                id: ids[index],
                name: "Account \(index + 1)",
                remaining: "1"
            )
        }

        let aggregate = SnapshotAggregator(calendar: utcCalendar).aggregate(
            accounts: accounts,
            snapshots: snapshots,
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(aggregate.accounts.map(\.accountID) == ids)
        #expect(aggregate.remaining == usd("5"))
    }

    @Test("Different currencies are never added together")
    func differentCurrenciesAreNotAdded() {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let accounts = [
            Account(id: first, displayName: "USD", sortOrder: 0),
            Account(id: second, displayName: "CNY", sortOrder: 1),
        ]
        let snapshots = [
            accountSnapshot(id: first, name: "USD", remaining: "10", currency: "USD"),
            accountSnapshot(id: second, name: "CNY", remaining: "20", currency: "CNY"),
        ]

        let aggregate = SnapshotAggregator(calendar: utcCalendar).aggregate(
            accounts: accounts,
            snapshots: snapshots,
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(aggregate.remaining == nil)
        #expect(aggregate.isPartial)
    }

    @Test("Missing provider metrics remain absent instead of becoming zero")
    func missingMetricsRemainAbsent() {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let accounts = [
            Account(id: first, displayName: "Complete", sortOrder: 0),
            Account(id: second, displayName: "Sparse", sortOrder: 1),
        ]
        let snapshots = [
            accountSnapshot(
                id: first,
                name: "Complete",
                remaining: "10",
                todayCost: "1",
                todayRequests: 5
            ),
            accountSnapshot(id: second, name: "Sparse", remaining: "20"),
        ]

        let aggregate = SnapshotAggregator(calendar: utcCalendar).aggregate(
            accounts: accounts,
            snapshots: snapshots,
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(aggregate.remaining == usd("30"))
        #expect(aggregate.todayActualCost == nil)
        #expect(aggregate.todayRequests == nil)
    }

    @Test("Current account metadata replaces cached snapshot metadata")
    func currentAccountMetadataReplacesCachedMetadata() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let accounts = [
            Account(
                id: id,
                displayName: "Renamed",
                lowBalanceThreshold: 50
            ),
        ]
        let snapshots = [
            accountSnapshot(id: id, name: "Old Name", remaining: "100"),
        ]

        let aggregate = SnapshotAggregator(calendar: utcCalendar).aggregate(
            accounts: accounts,
            snapshots: snapshots,
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(aggregate.accounts.first?.displayName == "Renamed")
        #expect(aggregate.accounts.first?.lowBalanceThreshold == 50)
    }

    @Test("Request count overflow is reported as a partial absent metric")
    func requestCountOverflowIsReported() {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let accounts = [
            Account(id: first, displayName: "Primary", sortOrder: 0),
            Account(id: second, displayName: "Backup", sortOrder: 1),
        ]
        let snapshots = [
            accountSnapshot(
                id: first,
                name: "Primary",
                remaining: "10",
                todayRequests: .max
            ),
            accountSnapshot(
                id: second,
                name: "Backup",
                remaining: "20",
                todayRequests: 1
            ),
        ]

        let aggregate = SnapshotAggregator(calendar: utcCalendar).aggregate(
            accounts: accounts,
            snapshots: snapshots,
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(aggregate.todayRequests == nil)
        #expect(aggregate.isPartial)
    }
}

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func utcDate(_ value: String) -> Date? {
    ISO8601DateFormatter().date(from: value)
}

private func usd(_ amount: String) -> Money {
    Money(amount: Decimal(string: amount)!, currency: "USD")
}

private func accountSnapshot(
    id: UUID,
    name: String,
    remaining: String,
    todayCost: String? = nil,
    todayRequests: Int64? = nil,
    daily: [(String, String)] = [],
    currency: String = "USD",
    health: AccountHealth = .healthy
) -> AccountSnapshot {
    let usage = ProviderUsageSnapshot(
        remaining: Money(amount: Decimal(string: remaining)!, currency: currency),
        today: UsageCounters(
            actualCost: todayCost.map {
                Money(amount: Decimal(string: $0)!, currency: currency)
            },
            requests: todayRequests
        ),
        dailyUsage: daily.map { date, cost in
            DailyUsage(
                date: date,
                actualCost: Money(amount: Decimal(string: cost)!, currency: currency)
            )
        },
        receivedAt: Date(timeIntervalSince1970: 100)
    )
    return AccountSnapshot(
        accountID: id,
        displayName: name,
        usage: usage,
        health: health,
        lastSuccessAt: usage.receivedAt
    )
}
