import Foundation

public enum ProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case apiInfo
    case deepSeek
    case kimi
    case openRouter
    case miniMax
    case bioMapCoding

    public static let allCases: [ProviderID] = [
        .apiInfo,
        .deepSeek,
        .kimi,
        .openRouter,
        .miniMax,
        .bioMapCoding,
    ]

    public var id: String { rawValue }

    public var displayName: String {
        return switch self {
        case .apiInfo: "API Info"
        case .deepSeek: "DeepSeek"
        case .kimi: "Kimi"
        case .openRouter: "OpenRouter"
        case .miniMax: "MiniMax"
        case .bioMapCoding: "BioMap Coding"
        }
    }

    public func profileDescription(
        for profile: ProviderProfile?,
        language: AppLanguage = .english
    ) -> String {
        guard let profile else {
            return L10n.string(.notDetected, language: language)
        }

        return switch self {
        case .kimi:
            switch profile.region {
            case .china:
                L10n.string(.chinaCNY, language: language)
            case .international:
                L10n.string(.internationalUSD, language: language)
            case .global:
                L10n.string(
                    .globalCredential,
                    language: language,
                    profile.credentialKind.displayName(language: language)
                )
            }
        case .openRouter:
            profile.credentialKind.displayName(language: language)
        case .miniMax:
            L10n.string(
                .regionCredential,
                language: language,
                profile.region.displayName(language: language),
                profile.credentialKind.displayName(language: language)
            )
        case .apiInfo, .deepSeek, .bioMapCoding:
            L10n.string(
                .regionCredential,
                language: language,
                profile.region.displayName(language: language),
                profile.credentialKind.displayName(language: language)
            )
        }
    }

    public func supportsLowBalanceThreshold(
        profile: ProviderProfile?
    ) -> Bool {
        return switch self {
        case .miniMax, .bioMapCoding:
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
        displayName(language: .english)
    }

    public func displayName(language: AppLanguage) -> String {
        switch self {
        case .global:
            L10n.string(.global, language: language)
        case .china:
            L10n.string(.china, language: language)
        case .international:
            L10n.string(.international, language: language)
        }
    }
}

public enum ProviderCredentialKind: String, Codable, Sendable {
    case standard
    case management
    case tokenPlan

    public var displayName: String {
        displayName(language: .english)
    }

    public func displayName(language: AppLanguage) -> String {
        switch self {
        case .standard:
            L10n.string(.standardKey, language: language)
        case .management:
            L10n.string(.managementKey, language: language)
        case .tokenPlan:
            L10n.string(.tokenPlan, language: language)
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
