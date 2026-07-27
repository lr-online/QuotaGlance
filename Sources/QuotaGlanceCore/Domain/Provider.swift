import Foundation

public enum ProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case apiInfo
    case deepSeek
    case kimi
    case openRouter
    case miniMax

    public var id: String { rawValue }

    public var displayName: String {
        return switch self {
        case .apiInfo: "API Info"
        case .deepSeek: "DeepSeek"
        case .kimi: "Kimi"
        case .openRouter: "OpenRouter"
        case .miniMax: "MiniMax"
        }
    }

    public func profileDescription(for profile: ProviderProfile?) -> String {
        guard let profile else { return "Not detected" }

        return switch self {
        case .kimi:
            switch profile.region {
            case .china: "China / CNY"
            case .international: "International / USD"
            case .global: "Global / \(profile.credentialKind.displayName)"
            }
        case .openRouter:
            profile.credentialKind.displayName
        case .miniMax:
            "\(profile.region.displayName) / \(profile.credentialKind.displayName)"
        case .apiInfo, .deepSeek:
            "\(profile.region.displayName) / \(profile.credentialKind.displayName)"
        }
    }

    public func supportsLowBalanceThreshold(
        profile: ProviderProfile?
    ) -> Bool {
        return switch self {
        case .miniMax:
            false
        case .openRouter:
            profile == nil || profile?.credentialKind == .management
        case .apiInfo, .deepSeek, .kimi:
            true
        }
    }

    public func normalizedLowBalanceThreshold(
        _ threshold: Decimal?,
        profile: ProviderProfile?
    ) -> Decimal? {
        supportsLowBalanceThreshold(profile: profile) ? threshold : nil
    }
}

public enum ProviderRegion: String, Codable, Sendable {
    case global
    case china
    case international

    public var displayName: String {
        switch self {
        case .global: "Global"
        case .china: "China"
        case .international: "International"
        }
    }
}

public enum ProviderCredentialKind: String, Codable, Sendable {
    case standard
    case management
    case tokenPlan

    public var displayName: String {
        switch self {
        case .standard: "Standard key"
        case .management: "Management key"
        case .tokenPlan: "Token Plan"
        }
    }
}

public struct ProviderProfile: Codable, Equatable, Sendable {
    public var region: ProviderRegion
    public var credentialKind: ProviderCredentialKind

    public init(
        region: ProviderRegion,
        credentialKind: ProviderCredentialKind
    ) {
        self.region = region
        self.credentialKind = credentialKind
    }

    public static let apiInfo = ProviderProfile(
        region: .global,
        credentialKind: .standard
    )
}
