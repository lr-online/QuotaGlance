import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Low-balance alerts")
struct AlertEvaluatorTests {
    @Test("A fresh detected snapshot can begin a low-balance alert episode")
    func freshDetectedSnapshotCanBeginAlertEpisode() {
        let accountID = UUID()
        var account = Account(
            id: accountID,
            displayName: "Detected",
            lowBalanceThreshold: 10
        )
        let snapshot = AccountSnapshot(
            accountID: accountID,
            displayName: account.displayName,
            lowBalanceThreshold: account.lowBalanceThreshold,
            usage: ProviderUsageSnapshot(
                remaining: alertUSD("5"),
                receivedAt: Date(timeIntervalSince1970: 100)
            ),
            health: .belowThreshold
        )

        #expect(AlertEvaluator.evaluate(account: &account, freshSnapshot: snapshot) == .notify)
        #expect(account.alertEpisodeActive)
    }

    @Test("A stale detected snapshot cannot change an alert episode")
    func staleDetectedSnapshotCannotChangeAlertEpisode() {
        let accountID = UUID()
        var account = Account(
            id: accountID,
            displayName: "Stale",
            lowBalanceThreshold: 10
        )
        let snapshot = AccountSnapshot(
            accountID: accountID,
            displayName: account.displayName,
            lowBalanceThreshold: account.lowBalanceThreshold,
            usage: ProviderUsageSnapshot(
                remaining: alertUSD("5"),
                receivedAt: Date(timeIntervalSince1970: 100)
            ),
            health: .stale(.offline)
        )

        #expect(AlertEvaluator.evaluate(account: &account, freshSnapshot: snapshot) == .none)
        #expect(!account.alertEpisodeActive)
    }

    @Test("Batch evaluation captures notifications before asynchronous delivery")
    func batchEvaluationCapturesNotifications() {
        let lowID = UUID()
        let recoveredID = UUID()
        var accounts = [
            Account(
                id: lowID,
                displayName: "Low",
                lowBalanceThreshold: 10
            ),
            Account(
                id: recoveredID,
                displayName: "Recovered",
                lowBalanceThreshold: 10,
                alertEpisodeActive: true
            ),
        ]
        let snapshots = [
            lowID: AccountSnapshot(
                accountID: lowID,
                displayName: "Low",
                usage: ProviderUsageSnapshot(
                    remaining: alertUSD("5"),
                    receivedAt: Date(timeIntervalSince1970: 100)
                ),
                health: .belowThreshold
            ),
            recoveredID: AccountSnapshot(
                accountID: recoveredID,
                displayName: "Recovered",
                usage: ProviderUsageSnapshot(
                    remaining: alertUSD("20"),
                    receivedAt: Date(timeIntervalSince1970: 100)
                ),
                health: .healthy
            ),
        ]

        let result = AlertEvaluator.evaluate(
            accounts: &accounts,
            freshSnapshots: snapshots
        )

        #expect(result.didChange)
        #expect(accounts[0].alertEpisodeActive)
        #expect(!accounts[1].alertEpisodeActive)
        #expect(result.notifications.count == 1)
        #expect(result.notifications[0].account.id == lowID)
        #expect(result.notifications[0].remaining == alertUSD("5"))
    }

    @Test("An account alerts once until its fresh balance recovers")
    func alertsOnceUntilBalanceRecovers() {
        var account = Account(
            displayName: "Primary",
            lowBalanceThreshold: 100
        )

        #expect(AlertEvaluator.evaluate(account: &account, freshRemaining: 90) == .notify)
        #expect(account.alertEpisodeActive)
        #expect(AlertEvaluator.evaluate(account: &account, freshRemaining: 80) == .none)
        #expect(AlertEvaluator.evaluate(account: &account, freshRemaining: 110) == .reset)
        #expect(!account.alertEpisodeActive)
        #expect(AlertEvaluator.evaluate(account: &account, freshRemaining: 95) == .notify)
    }

    @Test("A stale or failed refresh cannot start or reset an alert episode")
    func staleOrFailedRefreshCannotChangeEpisode() {
        var inactive = Account(
            displayName: "Primary",
            lowBalanceThreshold: 100
        )
        var active = Account(
            displayName: "Backup",
            lowBalanceThreshold: 100,
            alertEpisodeActive: true
        )

        #expect(AlertEvaluator.evaluate(account: &inactive, freshRemaining: nil) == .none)
        #expect(!inactive.alertEpisodeActive)
        #expect(AlertEvaluator.evaluate(account: &active, freshRemaining: nil) == .none)
        #expect(active.alertEpisodeActive)
    }

    @Test("Disabled accounts and accounts without a threshold cannot alert")
    func disabledOrThresholdlessAccountsCannotAlert() {
        var disabled = Account(
            displayName: "Disabled",
            isEnabled: false,
            lowBalanceThreshold: 100
        )
        var thresholdless = Account(displayName: "No Threshold")

        #expect(AlertEvaluator.evaluate(account: &disabled, freshRemaining: 10) == .none)
        #expect(!disabled.alertEpisodeActive)
        #expect(AlertEvaluator.evaluate(account: &thresholdless, freshRemaining: 0) == .none)
        #expect(!thresholdless.alertEpisodeActive)
    }
}

private func alertUSD(_ amount: String) -> Money {
    Money(amount: Decimal(string: amount)!, currency: "USD")
}
