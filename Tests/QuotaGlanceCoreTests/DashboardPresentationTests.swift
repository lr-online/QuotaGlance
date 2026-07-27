import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Dashboard presentation")
struct DashboardPresentationTests {
    @Test("All Accounts uses aggregate values and exposes partial state")
    func aggregateSelectionUsesAggregateValues() throws {
        let fixture = dashboardFixture()
        let presentation = try #require(
            DashboardPresenter.make(
                selection: .allAccounts,
                envelope: fixture.envelope
            )
        )

        #expect(presentation.title == "All Accounts")
        #expect(presentation.balances == [usd("150.25")])
        #expect(presentation.remaining == usd("150.25"))
        #expect(presentation.todayActualCost == usd("4.50"))
        #expect(presentation.todayRequests == 12)
        #expect(presentation.status == .partial)
        #expect(presentation.accountRows.count == 2)
    }

    @Test("Primary metrics follow balance limit quota then spend precedence")
    func primaryMetricsFollowCapabilityPrecedence() throws {
        let balance = ProviderUsageSnapshot(
            balances: [
                MonetaryBalance(label: "Credits", available: usd("20")),
            ],
            spendingLimit: SpendingLimit(
                label: "Key limit",
                remaining: usd("80")
            ),
            quotaWindows: [
                QuotaWindow(label: "5-hour quota", remaining: 900, unit: "requests"),
            ],
            receivedAt: Date(timeIntervalSince1970: 100)
        )
        #expect(
            try accountPresentation(balance).primaryMetric
                == PrimaryMetric(label: "Credits", value: .money(usd("20")))
        )

        let limit = ProviderUsageSnapshot(
            spendingLimit: SpendingLimit(
                label: "Key limit",
                remaining: usd("80")
            ),
            quotaWindows: [
                QuotaWindow(label: "5-hour quota", remaining: 900, unit: "requests"),
            ],
            receivedAt: Date(timeIntervalSince1970: 100)
        )
        #expect(
            try accountPresentation(limit).primaryMetric
                == PrimaryMetric(label: "Key limit", value: .money(usd("80")))
        )

        let quota = ProviderUsageSnapshot(
            spend: SpendSummary(month: usd("15")),
            quotaWindows: [
                QuotaWindow(label: "5-hour quota", remaining: 900, unit: "requests"),
            ],
            receivedAt: Date(timeIntervalSince1970: 100)
        )
        #expect(
            try accountPresentation(quota).primaryMetric
                == PrimaryMetric(
                    label: "5-hour quota",
                    value: .quantity(900, unit: "requests")
                )
        )

        let spend = ProviderUsageSnapshot(
            spend: SpendSummary(
                today: usd("1"),
                week: usd("5"),
                month: usd("15"),
                total: usd("50")
            ),
            receivedAt: Date(timeIntervalSince1970: 100)
        )
        #expect(
            try accountPresentation(spend).primaryMetric
                == PrimaryMetric(
                    label: "Spent this month",
                    value: .money(usd("15"))
                )
        )
        #expect(try accountPresentation(spend).todayActualCost == usd("1"))
    }

    @Test("An account selection uses its individual usage and stale state")
    func accountSelectionUsesIndividualUsage() throws {
        let fixture = dashboardFixture()
        let presentation = try #require(
            DashboardPresenter.make(
                selection: .account(fixture.staleAccountID),
                envelope: fixture.envelope
            )
        )

        #expect(presentation.title == "Backup")
        #expect(presentation.remaining == usd("50.25"))
        #expect(presentation.status == .stale(.offline))
        #expect(presentation.usage?.quotaLimit == usd("100"))
        #expect(presentation.usage?.modelUsage.map(\.model) == ["gpt-test"])
        #expect(presentation.accountRows.isEmpty)
    }

    @Test("Seven daily buckets remain stable across selection mapping")
    func dailyBucketsRemainStable() throws {
        let fixture = dashboardFixture()
        let presentation = try #require(
            DashboardPresenter.make(
                selection: .allAccounts,
                envelope: fixture.envelope
            )
        )

        #expect(presentation.dailyUsage.count == 7)
        #expect(presentation.dailyUsage.first?.date == "2026-07-16")
        #expect(presentation.dailyUsage.last?.date == "2026-07-22")
        #expect(presentation.dailyUsage.last?.actualCost == usd("4.50"))
    }

    @Test("Currency formatting preserves Decimal precision")
    func currencyFormattingPreservesDecimalPrecision() {
        let formatted = MoneyFormatter.string(
            Money(amount: Decimal(string: "544.045471")!, currency: "USD"),
            locale: Locale(identifier: "en_US")
        )

        #expect(formatted == "$544.045471")
    }

    @Test("Dashboard currency formatting rounds to two decimals")
    func dashboardCurrencyFormattingUsesTwoDecimals() {
        let formatted = MoneyFormatter.dashboardString(
            Money(
                amount: Decimal(string: "423.9753505")!,
                currency: "USD"
            ),
            locale: Locale(identifier: "en_US")
        )

        #expect(formatted == "$423.98")
    }

    @Test("Widget currency formatting rounds to two decimals")
    func widgetCurrencyFormattingUsesTwoDecimals() {
        let formatted = MoneyFormatter.widgetString(
            Money(
                amount: Decimal(string: "461.19583336")!,
                currency: "USD"
            ),
            locale: Locale(identifier: "en_US")
        )

        #expect(formatted == "$461.20")
    }
}

private struct DashboardFixture {
    let envelope: WidgetSnapshotEnvelope
    let staleAccountID: UUID
}

private func dashboardFixture() -> DashboardFixture {
    let primaryID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let backupID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let primaryUsage = ProviderUsageSnapshot(
        remaining: usd("100"),
        today: UsageCounters(actualCost: usd("3"), requests: 10),
        receivedAt: Date(timeIntervalSince1970: 200)
    )
    let backupUsage = ProviderUsageSnapshot(
        remaining: usd("50.25"),
        quotaLimit: usd("100"),
        quotaUsed: usd("49.75"),
        today: UsageCounters(actualCost: usd("1.50"), requests: 2),
        modelUsage: [
            ModelUsage(model: "gpt-test", actualCost: usd("1.50"), requests: 2)
        ],
        receivedAt: Date(timeIntervalSince1970: 100)
    )
    let primary = AccountSnapshot(
        accountID: primaryID,
        displayName: "Primary",
        usage: primaryUsage,
        health: .healthy,
        lastSuccessAt: primaryUsage.receivedAt
    )
    let backup = AccountSnapshot(
        accountID: backupID,
        displayName: "Backup",
        usage: backupUsage,
        health: .stale(.offline),
        lastSuccessAt: backupUsage.receivedAt
    )
    let days = (16...22).map { day in
        DailyUsage(
            date: String(format: "2026-07-%02d", day),
            actualCost: usd(day == 22 ? "4.50" : "0")
        )
    }
    let aggregate = AggregateSnapshot(
        remaining: usd("150.25"),
        todayActualCost: usd("4.50"),
        todayRequests: 12,
        dailyUsage: days,
        accounts: [primary, backup],
        isPartial: true
    )
    return DashboardFixture(
        envelope: WidgetSnapshotEnvelope(
            capturedAt: Date(timeIntervalSince1970: 200),
            aggregate: aggregate,
            accounts: [primary, backup]
        ),
        staleAccountID: backupID
    )
}

private func usd(_ amount: String) -> Money {
    Money(amount: Decimal(string: amount)!, currency: "USD")
}

private func accountPresentation(
    _ usage: ProviderUsageSnapshot
) throws -> DashboardPresentation {
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
    let account = AccountSnapshot(
        accountID: id,
        displayName: "Capability Account",
        provider: .miniMax,
        detectedProfile: ProviderProfile(
            region: .international,
            credentialKind: .tokenPlan
        ),
        usage: usage,
        health: .healthy,
        lastSuccessAt: usage.receivedAt
    )
    let envelope = WidgetSnapshotEnvelope(
        capturedAt: usage.receivedAt,
        aggregate: AggregateSnapshot(accounts: [account]),
        accounts: [account]
    )
    return try #require(
        DashboardPresenter.make(selection: .account(id), envelope: envelope)
    )
}
