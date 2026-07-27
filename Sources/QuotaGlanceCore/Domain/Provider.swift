import Foundation

public enum ProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case apiInfo
    case deepSeek
    case kimi
    case openRouter
    case miniMax
    case bailian

    public var id: String { rawValue }

    public var displayName: String {
        return switch self {
        case .apiInfo: "API Info"
        case .deepSeek: "DeepSeek"
        case .kimi: "Kimi"
        case .openRouter: "OpenRouter"
        case .miniMax: "MiniMax"
        case .bailian: "Alibaba Cloud Model Studio"
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
        case .bailian:
            switch profile.region {
            case .china: "China endpoint"
            case .international: "International endpoint"
            case .global: "Global endpoint"
            }
        case .apiInfo, .deepSeek:
            "\(profile.region.displayName) / \(profile.credentialKind.displayName)"
        }
    }

    public func supportsLowBalanceThreshold(
        profile: ProviderProfile?
    ) -> Bool {
        return switch self {
        case .miniMax, .bailian:
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

public struct ProviderConfiguration: Codable, Equatable, Sendable {
    public var baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }
}

public enum BailianEndpoint {
    public static let defaultBaseURL = URL(
        string: "https://dashscope.aliyuncs.com/compatible-mode/v1"
    )!

    public static func normalizedBaseURL(from value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? defaultBaseURL.absoluteString : trimmed
        guard let components = URLComponents(string: source),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              isAllowed(host: host),
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil else {
            throw ProviderError.invalidEndpoint
        }

        let path = components.percentEncodedPath
        guard path.isEmpty || path == "/" || path == "/compatible-mode/v1"
            || path == "/compatible-mode/v1/" else {
            throw ProviderError.invalidEndpoint
        }

        var normalized = URLComponents()
        normalized.scheme = "https"
        normalized.host = host
        normalized.path = "/compatible-mode/v1"
        guard let url = normalized.url else {
            throw ProviderError.invalidEndpoint
        }
        return url
    }

    public static func region(for baseURL: URL) throws -> ProviderRegion {
        guard let host = baseURL.host?.lowercased(), isAllowed(host: host) else {
            throw ProviderError.invalidEndpoint
        }
        if host == "dashscope.aliyuncs.com"
            || host.hasSuffix(".cn-beijing.maas.aliyuncs.com") {
            return .china
        }
        return .international
    }

    private static func isAllowed(host: String) -> Bool {
        if [
            "dashscope.aliyuncs.com",
            "dashscope-intl.aliyuncs.com",
            "dashscope-us.aliyuncs.com",
        ].contains(host) {
            return true
        }

        let suffixes = [
            ".cn-beijing.maas.aliyuncs.com",
            ".ap-southeast-1.maas.aliyuncs.com",
            ".ap-northeast-1.maas.aliyuncs.com",
        ]
        return suffixes.contains { suffix in
            guard host.hasSuffix(suffix) else { return false }
            let workspace = String(host.dropLast(suffix.count))
            return !workspace.isEmpty && !workspace.contains(".")
        }
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
