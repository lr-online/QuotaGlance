import Foundation

public struct StoredAccountPreferences: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var accounts: [Account]
    public var preferences: AppPreferences

    public init(
        schemaVersion: Int = currentSchemaVersion,
        accounts: [Account],
        preferences: AppPreferences
    ) {
        self.schemaVersion = schemaVersion
        self.accounts = accounts
        self.preferences = preferences
    }
}

public struct AccountPreferencesStore {
    public static let storageKey = "account-preferences-v1"

    private let defaults: UserDefaults
    private let storageKey: String

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = Self.storageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    public func save(accounts: [Account], preferences: AppPreferences) throws {
        let payload = StoredAccountPreferences(
            accounts: accounts,
            preferences: preferences
        )
        defaults.set(try JSONEncoder.quotaGlance.encode(payload), forKey: storageKey)
    }

    public func load() throws -> StoredAccountPreferences {
        guard let data = defaults.data(forKey: storageKey) else {
            return StoredAccountPreferences(accounts: [], preferences: .default)
        }
        return try JSONDecoder.quotaGlance.decode(
            StoredAccountPreferences.self,
            from: data
        )
    }
}
