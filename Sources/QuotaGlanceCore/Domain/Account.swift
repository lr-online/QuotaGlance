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
    public var isEnabled: Bool
    public var sortOrder: Int
    public var lowBalanceThreshold: Decimal?
    public var alertEpisodeActive: Bool

    public init(
        id: UUID = UUID(),
        displayName: String,
        isEnabled: Bool = true,
        sortOrder: Int = 0,
        lowBalanceThreshold: Decimal? = nil,
        alertEpisodeActive: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.lowBalanceThreshold = lowBalanceThreshold
        self.alertEpisodeActive = alertEpisodeActive
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
