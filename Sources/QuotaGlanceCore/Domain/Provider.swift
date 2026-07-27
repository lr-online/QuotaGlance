import Foundation

public enum ProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case apiInfo
    case deepSeek
    case kimi
    case openRouter
    case miniMax

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .apiInfo: "API Info"
        case .deepSeek: "DeepSeek"
        case .kimi: "Kimi"
        case .openRouter: "OpenRouter"
        case .miniMax: "MiniMax"
        }
    }
}

public enum ProviderRegion: String, Codable, Sendable {
    case global
    case china
    case international
}

public enum ProviderCredentialKind: String, Codable, Sendable {
    case standard
    case management
    case tokenPlan
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
