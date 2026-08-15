import Foundation

public struct ProviderDescriptor: Sendable {
    public var id: ProviderID
    public var displayName: String
    public var supportsLowBalanceThreshold: @Sendable (ProviderProfile?) -> Bool
    public var profileDescription: @Sendable (ProviderProfile?, AppLanguage) -> String

    public init(
        id: ProviderID,
        displayName: String,
        supportsLowBalanceThreshold: @escaping @Sendable (ProviderProfile?) -> Bool,
        profileDescription: @escaping @Sendable (ProviderProfile?, AppLanguage) -> String
    ) {
        self.id = id
        self.displayName = displayName
        self.supportsLowBalanceThreshold = supportsLowBalanceThreshold
        self.profileDescription = profileDescription
    }

    public func normalizedLowBalanceThreshold(
        _ threshold: Decimal?,
        profile: ProviderProfile?
    ) -> Decimal? {
        supportsLowBalanceThreshold(profile) ? threshold : nil
    }
}
