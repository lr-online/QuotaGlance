import Foundation
import Security

public protocol CredentialStore: Sendable {
    func read(for accountID: UUID) async throws -> String
    func save(_ credential: String, for accountID: UUID) async throws
    func delete(for accountID: UUID) async throws
}

public enum CredentialStoreError: Error, Equatable, Sendable {
    case notFound
    case invalidData
    case unexpectedStatus(OSStatus)
}

public actor KeychainStore: CredentialStore {
    public static let service = "com.liangrui.QuotaGlance.api-info"

    public init() {}

    public func read(for accountID: UUID) async throws -> String {
        var query = baseQuery(for: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else {
            throw CredentialStoreError.notFound
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

        let query = baseQuery(for: accountID)
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
        let status = SecItemDelete(baseQuery(for: accountID) as CFDictionary)
        guard status != errSecItemNotFound else {
            throw CredentialStoreError.notFound
        }
        guard status == errSecSuccess else {
            throw CredentialStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for accountID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: accountID.uuidString,
        ]
    }
}
