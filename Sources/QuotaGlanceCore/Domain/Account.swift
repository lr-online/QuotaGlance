import Foundation

public struct Money: Codable, Equatable, Hashable, Sendable {
    public var amount: Decimal
    public var currency: String

    public init(amount: Decimal, currency: String) {
        self.amount = amount
        self.currency = currency.uppercased()
    }
}

public enum RefreshInterval: Int, Codable, CaseIterable, Identifiable, Sendable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1_800
    case sixtyMinutes = 3_600

    public var id: Int { rawValue }

    public var seconds: TimeInterval {
        TimeInterval(rawValue)
    }
}

public struct Account: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var displayName: String
    public var provider: ProviderID
    public var detectedProfile: ProviderProfile?
    public var providerConfiguration: ProviderConfiguration?
    public var isEnabled: Bool
    public var sortOrder: Int
    public var lowBalanceThreshold: Decimal?
    public var alertEpisodeActive: Bool

    public init(
        id: UUID = UUID(),
        displayName: String,
        provider: ProviderID = .apiInfo,
        detectedProfile: ProviderProfile? = nil,
        providerConfiguration: ProviderConfiguration? = nil,
        isEnabled: Bool = true,
        sortOrder: Int = 0,
        lowBalanceThreshold: Decimal? = nil,
        alertEpisodeActive: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.provider = provider
        self.detectedProfile = detectedProfile ?? (provider == .apiInfo ? .apiInfo : nil)
        self.providerConfiguration = providerConfiguration
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.lowBalanceThreshold = lowBalanceThreshold
        self.alertEpisodeActive = alertEpisodeActive
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case provider
        case detectedProfile
        case providerConfiguration
        case isEnabled
        case sortOrder
        case lowBalanceThreshold
        case alertEpisodeActive
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        provider = try container.decodeIfPresent(ProviderID.self, forKey: .provider)
            ?? .apiInfo
        detectedProfile = try container.decodeIfPresent(
            ProviderProfile.self,
            forKey: .detectedProfile
        ) ?? (provider == .apiInfo ? .apiInfo : nil)
        providerConfiguration = try container.decodeIfPresent(
            ProviderConfiguration.self,
            forKey: .providerConfiguration
        )
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        lowBalanceThreshold = try container.decodeIfPresent(
            Decimal.self,
            forKey: .lowBalanceThreshold
        )
        alertEpisodeActive = try container.decodeIfPresent(
            Bool.self,
            forKey: .alertEpisodeActive
        ) ?? false
    }
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public var refreshInterval: RefreshInterval
    public var launchAtLogin: Bool

    public init(refreshInterval: RefreshInterval, launchAtLogin: Bool) {
        self.refreshInterval = refreshInterval
        self.launchAtLogin = launchAtLogin
    }

    public static let `default` = AppPreferences(
        refreshInterval: .fiveMinutes,
        launchAtLogin: false
    )
}
