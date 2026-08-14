import Foundation

/// Plans the host-visible effects of one completed refresh run.
///
/// Provider fetches and snapshot construction remain owned by
/// `RefreshCoordinator`. Hosts use this value to persist alert episodes,
/// deliver notifications, and invalidate their quick-view adapter once.
public struct RefreshEffectPlan: Equatable, Sendable {
    public let accounts: [Account]
    public let alertEvaluation: AlertBatchEvaluation
    public let shouldInvalidateQuickView: Bool

    public init(
        accounts: [Account],
        alertEvaluation: AlertBatchEvaluation,
        shouldInvalidateQuickView: Bool
    ) {
        self.accounts = accounts
        self.alertEvaluation = alertEvaluation
        self.shouldInvalidateQuickView = shouldInvalidateQuickView
    }
}

public enum RefreshEffectPlanner {
    public static func plan(
        accounts: [Account],
        freshSnapshots: [UUID: AccountSnapshot],
        presentationChanged: Bool
    ) -> RefreshEffectPlan {
        var updatedAccounts = accounts
        let alertEvaluation = AlertEvaluator.evaluate(
            accounts: &updatedAccounts,
            freshSnapshots: freshSnapshots
        )
        return RefreshEffectPlan(
            accounts: updatedAccounts,
            alertEvaluation: alertEvaluation,
            shouldInvalidateQuickView: presentationChanged
        )
    }
}
