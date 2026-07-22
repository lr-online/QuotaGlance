import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Low-balance alerts")
struct AlertEvaluatorTests {
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
