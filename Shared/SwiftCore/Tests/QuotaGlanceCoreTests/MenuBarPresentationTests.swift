import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Menu bar presentation")
struct MenuBarPresentationTests {
    @Test("Menu bar panel has one fixed content size")
    func menuBarPanelHasOneFixedContentSize() {
        let size = MenuBarPanelLayout.fixedContentSize

        #expect(size.width == 360)
        #expect(size.height == 500)
    }

    @Test("Latest seven days are chronological and have bounded labels")
    func latestSevenDaysAreChronological() throws {
        let account = account(
            dailyUsage: [23, 16, 22, 15, 21, 20, 19, 18, 17].map {
                day($0)
            }
        )
        let presentation = try #require(makePresentation(account: account))

        #expect(presentation.days.map(\.date) == [
            "2026-07-17", "2026-07-18", "2026-07-19",
            "2026-07-20", "2026-07-21", "2026-07-22", "2026-07-23"
        ])
        #expect(presentation.days.map(\.label) == [
            "17", "18", "19", "20", "21", "22", "23"
        ])
    }

    @Test("Malformed dates preserve provider order and use bounded labels")
    func malformedDatesPreserveProviderOrder() throws {
        let usage = [
            DailyUsage(date: "bad-date-a", actualCost: usd("1")),
            DailyUsage(date: "bad-date-b", actualCost: usd("2"))
        ]
        let presentation = try #require(
            makePresentation(account: account(dailyUsage: usage))
        )

        #expect(presentation.days.map(\.date) == ["bad-date-a", "bad-date-b"])
        #expect(presentation.days.map(\.label) == ["bad", "bad"])
    }

    @Test("Models are cost-descending, stable for ties, and nil costs are last")
    func modelsAreCostDescending() throws {
        let models = [
            ModelUsage(model: "first-tie", actualCost: usd("10")),
            ModelUsage(model: "missing"),
            ModelUsage(model: "highest", actualCost: usd("12")),
            ModelUsage(model: "second-tie", actualCost: usd("10"))
        ]
        let presentation = try #require(
            makePresentation(account: account(modelUsage: models))
        )

        #expect(presentation.modelRows.map(\.model) == ["highest", "first-tie"])
    }

    @Test(
        "Quota progress handles normal, over-limit, zero-limit, and missing values",
        arguments: [
            (used: "50", limit: "100", fraction: 0.5),
            (used: "125", limit: "100", fraction: 1.0),
            (used: "50", limit: "0", fraction: nil),
            (used: nil, limit: "100", fraction: nil)
        ]
    )
    func quotaProgress(
        used: String?,
        limit: String?,
        fraction: Double?
    ) throws {
        let presentation = try #require(
            makePresentation(
                account: account(
                    quotaUsed: used.map(usd),
                    quotaLimit: limit.map(usd)
                )
            )
        )

        #expect(presentation.quota?.fraction == fraction)
    }

    @Test("All Accounts exposes at most five healthy and unhealthy rows")
    func allAccountsShowsFiveRows() throws {
        let accounts = (0..<6).map { index in
            AccountSnapshot(
                accountID: UUID(),
                displayName: "Account \(index)",
                usage: ProviderUsageSnapshot(
                    remaining: usd("100"),
                    receivedAt: Date(timeIntervalSince1970: 200)
                ),
                health: index == 1 ? .stale(.offline) : .healthy,
                lastSuccessAt: Date(timeIntervalSince1970: 200)
            )
        }
        let envelope = WidgetSnapshotEnvelope(
            capturedAt: Date(timeIntervalSince1970: 200),
            aggregate: AggregateSnapshot(
                remaining: usd("600"),
                accounts: accounts,
                isPartial: true
            ),
            accounts: accounts
        )
        let presentation = try #require(
            MenuBarPresenter.make(selection: .allAccounts, envelope: envelope)
        )

        #expect(presentation.accountRows.count == 5)
        #expect(presentation.accountRows[0].health == .healthy)
        #expect(presentation.accountRows[1].health == .stale(.offline))
        #expect(
            presentation.accountRows[0].primaryMetric
                == PrimaryMetric(label: "Balance", value: .money(usd("100")))
        )
        #expect(presentation.status == .partial)
    }

    @Test("Account presentation exposes each available capability section")
    func accountPresentationExposesCapabilitySections() throws {
        let usage = ProviderUsageSnapshot(
            balances: [
                MonetaryBalance(
                    label: "Balance",
                    available: usd("12"),
                    breakdown: [
                        MonetaryValue(label: "Voucher", value: usd("2")),
                    ]
                ),
            ],
            spendingLimit: SpendingLimit(
                label: "Key limit",
                used: usd("5"),
                limit: usd("20"),
                remaining: usd("15")
            ),
            spend: SpendSummary(today: usd("1"), month: usd("4")),
            quotaWindows: [
                QuotaWindow(label: "5-hour quota", remaining: 90, unit: "%"),
            ],
            receivedAt: Date(timeIntervalSince1970: 200)
        )
        let snapshot = AccountSnapshot(
            accountID: UUID(),
            displayName: "Capabilities",
            usage: usage,
            health: .healthy
        )

        let presentation = try #require(makePresentation(account: snapshot))

        #expect(presentation.balanceRows == usage.balances)
        #expect(presentation.spendingLimit == usage.spendingLimit)
        #expect(presentation.spend == usage.spend)
        #expect(presentation.quotaWindows == usage.quotaWindows)
        #expect(
            presentation.primaryMetric
                == PrimaryMetric(label: "Balance", value: .money(usd("12")))
        )
    }
}

private func makePresentation(
    account: AccountSnapshot
) -> MenuBarPresentation? {
    let aggregate = AggregateSnapshot(
        remaining: account.remaining,
        todayActualCost: account.usage?.today?.actualCost,
        todayRequests: account.usage?.today?.requests,
        dailyUsage: account.usage?.dailyUsage ?? [],
        accounts: [account]
    )
    let envelope = WidgetSnapshotEnvelope(
        capturedAt: Date(timeIntervalSince1970: 200),
        aggregate: aggregate,
        accounts: [account]
    )
    return MenuBarPresenter.make(
        selection: .account(account.accountID),
        envelope: envelope
    )
}

private func account(
    quotaUsed: Money? = usd("50"),
    quotaLimit: Money? = usd("100"),
    dailyUsage: [DailyUsage] = [],
    modelUsage: [ModelUsage] = []
) -> AccountSnapshot {
    let receivedAt = Date(timeIntervalSince1970: 200)
    return AccountSnapshot(
        accountID: UUID(),
        displayName: "Primary",
        usage: ProviderUsageSnapshot(
            remaining: usd("50"),
            quotaLimit: quotaLimit,
            quotaUsed: quotaUsed,
            today: UsageCounters(actualCost: usd("2"), requests: 4),
            dailyUsage: dailyUsage,
            modelUsage: modelUsage,
            receivedAt: receivedAt
        ),
        health: .healthy,
        lastSuccessAt: receivedAt
    )
}

private func day(_ value: Int) -> DailyUsage {
    DailyUsage(
        date: String(format: "2026-07-%02d", value),
        actualCost: usd(String(value))
    )
}

private func usd(_ amount: String) -> Money {
    Money(amount: Decimal(string: amount)!, currency: "USD")
}
