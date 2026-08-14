import Foundation

public enum NCWidgetAccountChoice: Equatable, Sendable {
    case useAppDefault
    case allAccounts
    case account(UUID)
}

public enum NCWidgetSelectionResolver {
    public static func selection(
        choice: NCWidgetAccountChoice,
        defaultAccountID: UUID?
    ) -> WidgetSelection {
        switch choice {
        case .useAppDefault:
            if let defaultAccountID {
                return .account(defaultAccountID)
            }
            return .allAccounts
        case .allAccounts:
            return .allAccounts
        case let .account(accountID):
            return .account(accountID)
        }
    }
}
