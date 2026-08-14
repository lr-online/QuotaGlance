import Foundation

public enum AlertAction: Equatable, Sendable {
    case none
    case notify
    case reset
}

public struct PendingLowBalanceNotification: Equatable, Sendable {
    public let account: Account
    public let remaining: Money

    public init(account: Account, remaining: Money) {
        self.account = account
        self.remaining = remaining
    }
}

public struct AlertBatchEvaluation: Equatable, Sendable {
    public let didChange: Bool
    public let notifications: [PendingLowBalanceNotification]

    public init(
        didChange: Bool,
        notifications: [PendingLowBalanceNotification]
    ) {
        self.didChange = didChange
        self.notifications = notifications
    }
}

public enum AlertEvaluator {
    public static func evaluate(
        accounts: inout [Account],
        freshSnapshots: [UUID: AccountSnapshot]
    ) -> AlertBatchEvaluation {
        var didChange = false
        var notifications: [PendingLowBalanceNotification] = []

        for index in accounts.indices {
            guard let snapshot = freshSnapshots[accounts[index].id],
                  let remaining = snapshot.remaining else {
                continue
            }
            let action = evaluate(
                account: &accounts[index],
                freshSnapshot: snapshot
            )
            guard action != .none else { continue }
            didChange = true
            if action == .notify {
                notifications.append(
                    PendingLowBalanceNotification(
                        account: accounts[index],
                        remaining: remaining
                    )
                )
            }
        }

        return AlertBatchEvaluation(
            didChange: didChange,
            notifications: notifications
        )
    }

    public static func evaluate(
        account: inout Account,
        freshSnapshot: AccountSnapshot
    ) -> AlertAction {
        guard freshSnapshot.accountID == account.id else { return .none }
        switch freshSnapshot.health {
        case .healthy, .belowThreshold:
            return evaluate(
                account: &account,
                freshRemaining: freshSnapshot.remaining?.amount
            )
        case .stale, .unavailable:
            return .none
        }
    }

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
