import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Widget presentation")
struct WidgetPresentationTests {
    @Test("Aggregate selection maps the aggregate snapshot")
    func aggregateSelection() {
        let fixture = widgetFixture()
        let presentation = WidgetPresenter.make(
            selection: .allAccounts,
            envelope: fixture.envelope
        )

        #expect(presentation.title == "All Accounts")
        #expect(presentation.balances == [usd("125")])
        #expect(presentation.remaining == usd("125"))
        #expect(presentation.state == .available(.partial))
        #expect(presentation.accountRows.count == 2)
    }

    @Test("Aggregate widgets expose at most two currency totals")
    func aggregateWidgetsExposeAtMostTwoCurrencyTotals() {
        let envelope = WidgetSnapshotEnvelope(
            capturedAt: Date(timeIntervalSince1970: 100),
            aggregate: AggregateSnapshot(
                balances: [
                    Money(amount: 30, currency: "CNY"),
                    Money(amount: 20, currency: "EUR"),
                    Money(amount: 10, currency: "USD"),
                ]
            ),
            accounts: []
        )

        let presentation = WidgetPresenter.make(
            selection: .allAccounts,
            envelope: envelope
        )

        #expect(presentation.balances == [
            Money(amount: 30, currency: "CNY"),
            Money(amount: 20, currency: "EUR"),
        ])
    }

    @Test("A quota-only account has an explicitly labeled primary metric")
    func quotaOnlyAccountHasLabeledPrimaryMetric() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let usage = ProviderUsageSnapshot(
            quotaWindows: [
                QuotaWindow(label: "5-hour quota", remaining: 900, unit: "requests"),
            ],
            receivedAt: Date(timeIntervalSince1970: 100)
        )
        let account = AccountSnapshot(
            accountID: id,
            displayName: "MiniMax",
            provider: .miniMax,
            detectedProfile: ProviderProfile(
                region: .international,
                credentialKind: .tokenPlan
            ),
            usage: usage,
            health: .healthy
        )
        let envelope = WidgetSnapshotEnvelope(
            capturedAt: usage.receivedAt,
            aggregate: AggregateSnapshot(accounts: [account]),
            accounts: [account]
        )

        let presentation = WidgetPresenter.make(
            selection: .account(id),
            envelope: envelope
        )

        #expect(presentation.remaining == nil)
        #expect(
            presentation.primaryMetric
                == PrimaryMetric(
                    label: "5-hour quota",
                    value: .quantity(900, unit: "requests")
                )
        )
    }

    @Test("A valid account selection maps only that account")
    func validAccountSelection() {
        let fixture = widgetFixture()
        let presentation = WidgetPresenter.make(
            selection: .account(fixture.primaryID),
            envelope: fixture.envelope
        )

        #expect(presentation.title == "Primary")
        #expect(presentation.remaining == usd("100"))
        #expect(presentation.todayActualCost == usd("2"))
        #expect(presentation.accountRows.isEmpty)
        #expect(presentation.deepLink == URL(string: "quotaglance://account/\(fixture.primaryID.uuidString)"))
    }

    @Test("A deleted account selection is explicitly unavailable")
    func deletedAccountSelection() {
        let fixture = widgetFixture()
        let presentation = WidgetPresenter.make(
            selection: .account(UUID()),
            envelope: fixture.envelope
        )

        #expect(presentation.state == .deletedAccount)
        #expect(presentation.remaining == nil)
        #expect(presentation.todayActualCost == nil)
    }

    @Test("A stale account retains value and stale state")
    func staleAccountRetainsValue() {
        let fixture = widgetFixture()
        let presentation = WidgetPresenter.make(
            selection: .account(fixture.staleID),
            envelope: fixture.envelope
        )

        #expect(presentation.remaining == usd("25"))
        #expect(presentation.state == .available(.stale(.offline)))
        #expect(presentation.lastSuccessAt == Date(timeIntervalSince1970: 100))
    }

    @Test("No snapshot produces a neutral unavailable entry without zero money")
    func noSnapshotDoesNotFabricateZero() {
        let presentation = WidgetPresenter.make(
            selection: .allAccounts,
            envelope: nil
        )

        #expect(presentation.state == .noSnapshot)
        #expect(presentation.remaining == nil)
        #expect(presentation.todayActualCost == nil)
        #expect(presentation.todayRequests == nil)
        #expect(presentation.dailyUsage.isEmpty)
    }
}

private struct WidgetFixture {
    let envelope: WidgetSnapshotEnvelope
    let primaryID: UUID
    let staleID: UUID
}

private func widgetFixture() -> WidgetFixture {
    let primaryID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let staleID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let primaryUsage = ProviderUsageSnapshot(
        remaining: usd("100"),
        today: UsageCounters(actualCost: usd("2"), requests: 10),
        receivedAt: Date(timeIntervalSince1970: 200)
    )
    let staleUsage = ProviderUsageSnapshot(
        remaining: usd("25"),
        today: UsageCounters(actualCost: usd("1"), requests: 2),
        receivedAt: Date(timeIntervalSince1970: 100)
    )
    let primary = AccountSnapshot(
        accountID: primaryID,
        displayName: "Primary",
        usage: primaryUsage,
        health: .healthy,
        lastSuccessAt: primaryUsage.receivedAt
    )
    let stale = AccountSnapshot(
        accountID: staleID,
        displayName: "Backup",
        usage: staleUsage,
        health: .stale(.offline),
        lastSuccessAt: staleUsage.receivedAt
    )
    let days = (16...22).map { day in
        DailyUsage(
            date: String(format: "2026-07-%02d", day),
            actualCost: usd(day == 22 ? "3" : "0")
        )
    }
    let aggregate = AggregateSnapshot(
        remaining: usd("125"),
        todayActualCost: usd("3"),
        todayRequests: 12,
        dailyUsage: days,
        accounts: [primary, stale],
        isPartial: true
    )
    return WidgetFixture(
        envelope: WidgetSnapshotEnvelope(
            capturedAt: Date(timeIntervalSince1970: 200),
            aggregate: aggregate,
            accounts: [primary, stale]
        ),
        primaryID: primaryID,
        staleID: staleID
    )
}

private func usd(_ amount: String) -> Money {
    Money(amount: Decimal(string: amount)!, currency: "USD")
}
