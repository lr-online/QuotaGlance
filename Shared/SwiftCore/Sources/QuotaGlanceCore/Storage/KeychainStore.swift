import Foundation
import LocalAuthentication
import Security

public enum CredentialAccessMode: Equatable, Sendable {
    case interactive
    case nonInteractive
}

public protocol CredentialStore: Sendable {
    func read(for accountID: UUID) async throws -> String
    func read(
        for accountID: UUID,
        accessMode: CredentialAccessMode
    ) async throws -> String
    func save(_ credential: String, for accountID: UUID) async throws
    func delete(for accountID: UUID) async throws
}

public extension CredentialStore {
    func read(
        for accountID: UUID,
        accessMode: CredentialAccessMode
    ) async throws -> String {
        try await read(for: accountID)
    }
}

public enum CredentialStoreError: Error, Equatable, Sendable {
    case notFound
    case invalidData
    case interactionRequired
    case unexpectedStatus(OSStatus)
}

public actor KeychainStore: CredentialStore {
    public static let service = "com.liangrui.QuotaGlance.api-info"

    public init() {}

    public func read(for accountID: UUID) async throws -> String {
        try await read(for: accountID, accessMode: .interactive)
    }

    public func read(
        for accountID: UUID,
        accessMode: CredentialAccessMode
    ) async throws -> String {
        let query = Self.readQuery(for: accountID, accessMode: accessMode)

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else {
            throw CredentialStoreError.notFound
        }
        if status == errSecInteractionNotAllowed
            || status == errSecAuthFailed
            || status == errSecUserCanceled {
            throw CredentialStoreError.interactionRequired
        }
        guard status == errSecSuccess else {
            throw CredentialStoreError.unexpectedStatus(status)
        }
        guard var data = result as? Data else {
            throw CredentialStoreError.invalidData
        }
        defer { data.resetBytes(in: 0..<data.count) }
        guard let credential = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.invalidData
        }
        return credential
    }

    public func save(_ credential: String, for accountID: UUID) async throws {
        var data = Data(credential.utf8)
        defer { data.resetBytes(in: 0..<data.count) }

        let query = Self.baseQuery(for: accountID)
        let update = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            update as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialStoreError.unexpectedStatus(updateStatus)
        }

        var newItem = query
        newItem[kSecValueData as String] = data
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialStoreError.unexpectedStatus(addStatus)
        }
    }

    public func delete(for accountID: UUID) async throws {
        let status = SecItemDelete(Self.baseQuery(for: accountID) as CFDictionary)
        guard status != errSecItemNotFound else {
            throw CredentialStoreError.notFound
        }
        guard status == errSecSuccess else {
            throw CredentialStoreError.unexpectedStatus(status)
        }
    }

    static func readQuery(
        for accountID: UUID,
        accessMode: CredentialAccessMode
    ) -> [String: Any] {
        var query = baseQuery(for: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if accessMode == .nonInteractive {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        return query
    }

    private static func baseQuery(for accountID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: accountID.uuidString,
        ]
    }
}
