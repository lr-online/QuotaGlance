import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Refresh effect planning")
struct RefreshEffectPlannerTests {
    @Test("A completed run evaluates each fresh account once and publishes once")
    func completedRunPlansOneAlertEvaluationAndPublication() {
        let account = Account(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!,
            displayName: "Primary",
            lowBalanceThreshold: Decimal(string: "10")!
        )
        let snapshot = AccountSnapshot(
            accountID: account.id,
            displayName: account.displayName,
            lowBalanceThreshold: account.lowBalanceThreshold,
            usage: ProviderUsageSnapshot(
                remaining: Money(amount: Decimal(string: "5")!, currency: "USD"),
                receivedAt: Date(timeIntervalSince1970: 100)
            ),
            health: .belowThreshold,
            lastSuccessAt: Date(timeIntervalSince1970: 100)
        )

        let plan = RefreshEffectPlanner.plan(
            accounts: [account],
            freshSnapshots: [account.id: snapshot],
            presentationChanged: true
        )

        #expect(plan.shouldInvalidateQuickView)
        #expect(plan.alertEvaluation.notifications.count == 1)
        #expect(plan.accounts[0].alertEpisodeActive)
    }

    @Test("A failed-only run publishes changed stale state without changing alert episodes")
    func failedOnlyRunDoesNotEvaluateAlerts() {
        let account = Account(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000112")!,
            displayName: "Primary",
            lowBalanceThreshold: Decimal(string: "10")!,
            alertEpisodeActive: true
        )

        let plan = RefreshEffectPlanner.plan(
            accounts: [account],
            freshSnapshots: [:],
            presentationChanged: true
        )

        #expect(plan.shouldInvalidateQuickView)
        #expect(!plan.alertEvaluation.didChange)
        #expect(plan.alertEvaluation.notifications.isEmpty)
        #expect(plan.accounts[0].alertEpisodeActive)
    }
}
