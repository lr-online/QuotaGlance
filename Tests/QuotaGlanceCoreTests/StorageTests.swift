import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Storage")
struct StorageTests {
    @Test("Certificate-free snapshots use the local shared directory")
    func certificateFreeSnapshotsUseLocalSharedDirectory() {
        let store = QuotaGlanceShared.certificateFreeSnapshotStore()

        #expect(
            store.fileURL
                == URL(
                    fileURLWithPath: "/Users/Shared/QuotaGlance/quota-snapshot-v1.json"
                )
        )
    }

    @Test("Preferences round-trip a versioned payload")
    func preferencesRoundTripVersionedPayload() throws {
        let suiteName = "QuotaGlanceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AccountPreferencesStore(defaults: defaults)
        let accounts = [Account(displayName: "Primary")]

        try store.save(accounts: accounts, preferences: .default)
        let loaded = try store.load()

        #expect(loaded.schemaVersion == 1)
        #expect(loaded.accounts == accounts)
        #expect(loaded.preferences == .default)
    }

    @Test("Credential storage identifies same-name accounts by UUID")
    func credentialStorageUsesAccountUUID() async throws {
        let first = Account(displayName: "Personal")
        let second = Account(displayName: "Personal")
        let store: any CredentialStore = InMemoryCredentialStore()

        try await store.save("first-key", for: first.id)
        try await store.save("second-key", for: second.id)

        #expect(try await store.read(for: first.id) == "first-key")
        #expect(try await store.read(for: second.id) == "second-key")

        try await store.delete(for: first.id)
        await #expect(throws: TestCredentialError.notFound) {
            try await store.read(for: first.id)
        }
        #expect(try await store.read(for: second.id) == "second-key")
    }

    @Test("Shared snapshot writes replace the whole file atomically")
    func sharedSnapshotWriteReplacesWholeFile() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "QuotaGlanceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "quota-snapshot-v1.json")
        let store = SharedSnapshotStore(fileURL: fileURL)
        let firstDate = Date(timeIntervalSince1970: 100)
        let secondDate = Date(timeIntervalSince1970: 200)

        try store.write(.empty(capturedAt: firstDate))
        try store.write(.empty(capturedAt: secondDate))

        #expect(try store.read().capturedAt == secondDate)
    }

    @Test("Shared snapshot writes keep the file private")
    func sharedSnapshotWritesKeepFilePrivate() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "QuotaGlanceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "quota-snapshot-v1.json")
        let store = SharedSnapshotStore(fileURL: fileURL)

        try store.write(.empty(capturedAt: .now))

        let attributes = try FileManager.default.attributesOfItem(
            atPath: fileURL.path
        )
        let permissions = attributes[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }

    @Test("Shared snapshot temporary files stay beside the destination")
    func sharedSnapshotTemporaryFileUsesDestinationDirectory() {
        let fileURL = URL(
            fileURLWithPath: "/app-group/quota-snapshot-v1.json"
        )
        let temporaryURL = SharedSnapshotStore.temporaryFileURL(
            for: fileURL,
            identifier: "test-write"
        )

        #expect(
            temporaryURL.deletingLastPathComponent()
                == fileURL.deletingLastPathComponent()
        )
        #expect(temporaryURL.lastPathComponent == ".quota-snapshot-v1.json.test-write.tmp")
    }
}

private enum TestCredentialError: Error, Equatable {
    case notFound
}

private actor InMemoryCredentialStore: CredentialStore {
    private var values: [UUID: String] = [:]

    func read(for accountID: UUID) async throws -> String {
        guard let value = values[accountID] else {
            throw TestCredentialError.notFound
        }
        return value
    }

    func save(_ credential: String, for accountID: UUID) async throws {
        values[accountID] = credential
    }

    func delete(for accountID: UUID) async throws {
        guard values.removeValue(forKey: accountID) != nil else {
            throw TestCredentialError.notFound
        }
    }
}
