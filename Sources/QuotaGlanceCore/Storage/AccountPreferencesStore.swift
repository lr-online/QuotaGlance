import Foundation

public struct StoredAccountPreferences: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

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
        do {
            return try JSONDecoder.quotaGlance.decode(
                StoredAccountPreferences.self,
                from: data
            )
        } catch {
            guard let sanitizedData = try sanitizedStoredPreferencesData(from: data)
            else {
                throw error
            }
            let sanitized = try JSONDecoder.quotaGlance.decode(
                StoredAccountPreferences.self,
                from: sanitizedData
            )
            defaults.set(sanitizedData, forKey: storageKey)
            return sanitized
        }
    }

    private func sanitizedStoredPreferencesData(from data: Data) throws -> Data? {
        guard var payload = try JSONSerialization.jsonObject(with: data)
            as? [String: Any],
            let accounts = payload["accounts"] as? [[String: Any]]
        else {
            return nil
        }

        let supportedProviders = Set(ProviderID.allCases.map(\.rawValue))
        let filteredAccounts = accounts.filter { account in
            guard let provider = account["provider"] as? String else {
                return true
            }
            return supportedProviders.contains(provider)
        }
        guard filteredAccounts.count != accounts.count else {
            return nil
        }
        payload["accounts"] = filteredAccounts
        return try JSONSerialization.data(withJSONObject: payload)
    }
}
