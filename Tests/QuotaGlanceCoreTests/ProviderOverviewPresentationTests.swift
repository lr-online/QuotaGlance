import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Provider overview presentation")
struct ProviderOverviewPresentationTests {
    @Test("Groups preserve account order and sum currencies exactly")
    func groupsAndSumsCurrencies() throws {
        let deepSeekA = account(1, provider: .deepSeek, sortOrder: 4)
        let deepSeekB = account(2, provider: .deepSeek, sortOrder: 1)
        let disabledKimi = account(
            3,
            provider: .kimi,
            sortOrder: 0,
            isEnabled: false
        )
        let presentation = ProviderOverviewPresenter.make(
            accounts: [deepSeekA, deepSeekB, disabledKimi],
            envelope: envelope([
                snapshot(
                    deepSeekA,
                    usage: usage(
                        balances: [money("0.1", "USD"), money("5", "CNY")],
                        todayCost: money("0.2", "USD"),
                        requests: 2
                    )
                ),
                snapshot(
                    deepSeekB,
                    usage: usage(
                        balances: [money("0.2", "USD")],
                        todayCost: money("0.1", "USD"),
                        requests: 1
                    )
                ),
                snapshot(
                    disabledKimi,
                    usage: usage(
                        balances: [money("999", "USD")],
                        todayCost: money("999", "USD"),
                        requests: 999
                    )
                ),
            ])
        )

        #expect(presentation.rows.map(\.provider) == [.kimi, .deepSeek])
        let kimi = try #require(presentation.rows.first)
        #expect(kimi.status == .disabled)
        #expect(kimi.balances.isEmpty)
        #expect(kimi.todayActualCosts.isEmpty)
        #expect(kimi.accountCountText == "1 account")

        let deepSeek = try #require(presentation.rows.last)
        #expect(
            deepSeek.balances
                == [money("5", "CNY"), money("0.3", "USD")]
        )
        #expect(deepSeek.todayActualCosts == [money("0.3", "USD")])
        #expect(deepSeek.todayRequests == 3)
        #expect(deepSeek.requestShare == 1)
        #expect(deepSeek.status == .healthy)
        #expect(deepSeek.accountCountText == "2 accounts")
    }

    @Test("Stale values remain visible while unavailable and disabled states stay distinct")
    func staleUnavailableAndDisabledStates() throws {
        let stale = account(1, provider: .deepSeek, sortOrder: 0)
        let unavailable = account(2, provider: .kimi, sortOrder: 1)
        let disabled = account(
            3,
            provider: .openRouter,
            sortOrder: 2,
            isEnabled: false
        )
        let presentation = ProviderOverviewPresenter.make(
            accounts: [stale, unavailable, disabled],
            envelope: envelope([
                snapshot(
                    stale,
                    usage: usage(
                        balances: [money("8.5", "USD")],
                        todayCost: money("1.25", "USD"),
                        requests: 7
                    ),
                    health: .stale(.offline)
                ),
                snapshot(
                    unavailable,
                    usage: nil,
                    health: .unavailable(.timeout)
                ),
            ])
        )

        let staleRow = try #require(presentation.rows.first)
        #expect(staleRow.status == .partial)
        #expect(staleRow.balances == [money("8.5", "USD")])
        #expect(staleRow.todayActualCosts == [money("1.25", "USD")])
        #expect(staleRow.todayRequests == nil)
        #expect(presentation.rows[1].status == .unavailable)
        #expect(presentation.rows[2].status == .disabled)
        #expect(presentation.totalRequests == nil)
        #expect(presentation.rows.allSatisfy { $0.requestShare == nil })
    }

    @Test("Request shares require fresh complete provider totals")
    func requestSharesRequireCompleteFreshTotals() throws {
        let deepSeek = account(1, provider: .deepSeek, sortOrder: 0)
        let kimi = account(2, provider: .kimi, sortOrder: 1)
        let complete = ProviderOverviewPresenter.make(
            accounts: [deepSeek, kimi],
            envelope: envelope([
                snapshot(deepSeek, usage: usage(requests: 10)),
                snapshot(kimi, usage: usage(requests: 30)),
            ])
        )

        #expect(complete.totalRequests == 40)
        #expect(complete.rows[0].requestShare == Decimal(string: "0.25"))
        #expect(complete.rows[1].requestShare == Decimal(string: "0.75"))

        let incomplete = ProviderOverviewPresenter.make(
            accounts: [deepSeek, kimi],
            envelope: envelope([
                snapshot(deepSeek, usage: usage(requests: 10)),
                snapshot(kimi, usage: usage()),
            ])
        )
        #expect(incomplete.totalRequests == nil)
        #expect(incomplete.rows.allSatisfy { $0.requestShare == nil })
    }

    @Test("Request overflow suppresses every share")
    func requestOverflowSuppressesShares() {
        let deepSeek = account(1, provider: .deepSeek, sortOrder: 0)
        let kimi = account(2, provider: .kimi, sortOrder: 1)
        let presentation = ProviderOverviewPresenter.make(
            accounts: [deepSeek, kimi],
            envelope: envelope([
                snapshot(deepSeek, usage: usage(requests: .max)),
                snapshot(kimi, usage: usage(requests: 1)),
            ])
        )

        #expect(presentation.totalRequests == nil)
        #expect(presentation.rows.allSatisfy { $0.requestShare == nil })
    }

    @Test("Only a single pure quota account exposes a provider primary metric")
    func pureQuotaPrimaryMetric() throws {
        let first = account(1, provider: .miniMax, sortOrder: 0)
        let second = account(2, provider: .miniMax, sortOrder: 1)
        let quotaUsage = ProviderUsageSnapshot(
            quotaWindows: [
                QuotaWindow(
                    label: "5-hour quota",
                    remaining: 900,
                    unit: "requests"
                ),
            ],
            receivedAt: Date(timeIntervalSince1970: 100)
        )
        let single = ProviderOverviewPresenter.make(
            accounts: [first],
            envelope: envelope([snapshot(first, usage: quotaUsage)])
        )
        #expect(
            try #require(single.rows.first).primaryMetric
                == PrimaryMetric(
                    label: "5-hour quota",
                    value: .quantity(900, unit: "requests")
                )
        )

        let multiple = ProviderOverviewPresenter.make(
            accounts: [first, second],
            envelope: envelope([
                snapshot(first, usage: quotaUsage),
                snapshot(second, usage: quotaUsage),
            ])
        )
        #expect(multiple.rows.first?.primaryMetric == nil)
        #expect(multiple.rows.first?.accountCount == 2)
    }
}

private func account(
    _ suffix: Int,
    provider: ProviderID,
    sortOrder: Int,
    isEnabled: Bool = true
) -> Account {
    Account(
        id: UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                suffix
            )
        )!,
        displayName: "Account \(suffix)",
        provider: provider,
        isEnabled: isEnabled,
        sortOrder: sortOrder
    )
}

private func snapshot(
    _ account: Account,
    usage: ProviderUsageSnapshot?,
    health: AccountHealth = .healthy
) -> AccountSnapshot {
    AccountSnapshot(
        accountID: account.id,
        displayName: account.displayName,
        provider: account.provider,
        detectedProfile: account.detectedProfile,
        lowBalanceThreshold: account.lowBalanceThreshold,
        usage: usage,
        health: health,
        lastSuccessAt: usage?.receivedAt
    )
}

private func usage(
    balances: [Money] = [],
    todayCost: Money? = nil,
    requests: Int64? = nil
) -> ProviderUsageSnapshot {
    ProviderUsageSnapshot(
        balances: balances.map {
            MonetaryBalance(label: "Balance", available: $0)
        },
        spend: SpendSummary(today: todayCost),
        today: requests == nil && todayCost == nil
            ? nil
            : UsageCounters(actualCost: todayCost, requests: requests),
        receivedAt: Date(timeIntervalSince1970: 100)
    )
}

private func envelope(_ snapshots: [AccountSnapshot]) -> WidgetSnapshotEnvelope {
    WidgetSnapshotEnvelope(
        capturedAt: Date(timeIntervalSince1970: 100),
        aggregate: AggregateSnapshot(accounts: snapshots),
        accounts: snapshots
    )
}

private func money(_ amount: String, _ currency: String) -> Money {
    Money(amount: Decimal(string: amount)!, currency: currency)
}
