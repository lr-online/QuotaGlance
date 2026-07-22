import Foundation

public enum DeepLinkDestination: Equatable, Sendable {
    case allAccounts
    case account(UUID)
}

public enum DeepLinkRouter {
    public static func destination(
        for url: URL,
        knownAccountIDs: Set<UUID>
    ) -> DeepLinkDestination? {
        guard url.scheme?.lowercased() == "quotaglance" else {
            return nil
        }

        switch url.host?.lowercased() {
        case "all":
            guard url.path.isEmpty || url.path == "/" else { return nil }
            return .allAccounts

        case "account":
            let components = url.pathComponents.filter { $0 != "/" }
            guard components.count == 1,
                  let accountID = UUID(uuidString: components[0])
            else {
                return nil
            }
            return knownAccountIDs.contains(accountID)
                ? .account(accountID)
                : .allAccounts

        default:
            return nil
        }
    }
}
