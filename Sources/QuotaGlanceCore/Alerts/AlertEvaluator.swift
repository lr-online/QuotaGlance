import Foundation

public enum AlertAction: Equatable, Sendable {
    case none
    case notify
    case reset
}

public enum AlertEvaluator {
    public static func evaluate(
        account: inout Account,
        freshRemaining: Decimal?
    ) -> AlertAction {
        guard account.isEnabled,
              let threshold = account.lowBalanceThreshold,
              let freshRemaining
        else {
            return .none
        }

        if freshRemaining <= threshold {
            guard !account.alertEpisodeActive else { return .none }
            account.alertEpisodeActive = true
            return .notify
        }

        guard account.alertEpisodeActive else { return .none }
        account.alertEpisodeActive = false
        return .reset
    }
}
