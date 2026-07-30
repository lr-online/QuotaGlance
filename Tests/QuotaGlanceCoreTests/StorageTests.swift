import Foundation
import LocalAuthentication
import Security
import Testing
@testable import QuotaGlanceCore

@Suite("Storage")
struct StorageTests {
    @Test("Non-interactive Keychain reads disable authentication UI")
    func nonInteractiveKeychainReadsDisableAuthenticationUI() throws {
        let accountID = UUID()

        let backgroundQuery = KeychainStore.readQuery(
            for: accountID,
            accessMode: .nonInteractive
        )
        let context = try #require(
            backgroundQuery[kSecUseAuthenticationContext as String] as? LAContext
        )
        #expect(context.interactionNotAllowed)

        let interactiveQuery = KeychainStore.readQuery(
            for: accountID,
            accessMode: .interactive
        )
        #expect(interactiveQuery[kSecUseAuthenticationContext as String] == nil)
    }

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

        #expect(loaded.schemaVersion == 2)
        #expect(loaded.accounts == accounts)
        #expect(loaded.preferences == .default)
    }

    @Test("Loading removes persisted unsupported provider accounts and keeps the rest")
    func loadingRemovesPersistedUnsupportedProviderAccounts() throws {
        let suiteName = "QuotaGlanceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AccountPreferencesStore(defaults: defaults)
        let payload = Data(#"""
        {
          "schemaVersion": 2,
          "accounts": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "displayName": "Primary",
              "provider": "apiInfo",
              "detectedProfile": {
                "region": "global",
                "credentialKind": "standard"
              },
              "isEnabled": true,
              "sortOrder": 0,
              "alertEpisodeActive": false
            },
            {
              "id": "00000000-0000-0000-0000-000000000002",
              "displayName": "Ali",
              "provider": "bailian",
              "providerConfiguration": {
                "baseURL": "https://dashscope.aliyuncs.com/compatible-mode/v1"
              },
              "isEnabled": true,
              "sortOrder": 1,
              "alertEpisodeActive": false
            }
          ],
          "preferences": {
            "refreshInterval": 300,
            "launchAtLogin": true
          }
        }
        """#.utf8)

        defaults.set(payload, forKey: AccountPreferencesStore.storageKey)

        let loaded = try store.load()

        #expect(loaded.accounts.map { $0.displayName } == ["Primary"])
        #expect(loaded.accounts.map { $0.provider } == [ProviderID.apiInfo])
        #expect(loaded.preferences == AppPreferences(
            refreshInterval: .fiveMinutes,
            launchAtLogin: true
        ))

        let persistedData = try #require(
            defaults.data(forKey: AccountPreferencesStore.storageKey)
        )
        let persisted = try JSONDecoder.quotaGlance.decode(
            StoredAccountPreferences.self,
            from: persistedData
        )
        #expect(persisted == loaded)
    }

    @Test("Notification Center default account preference round-trips")
    func notificationCenterDefaultAccountPreferenceRoundTrips() throws {
        let suiteName = "QuotaGlanceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AccountPreferencesStore(defaults: defaults)
        let accountID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        let legacyPayload = Data(#"""
        {
          "schemaVersion": 2,
          "accounts": [],
          "preferences": {
            "refreshInterval": 300,
            "launchAtLogin": false
          }
        }
        """#.utf8)
        defaults.set(legacyPayload, forKey: AccountPreferencesStore.storageKey)
        let loadedLegacy = try store.load()
        #expect(loadedLegacy.preferences.notificationCenterDefaultAccountID == nil)

        let preferences = AppPreferences(
            refreshInterval: .fiveMinutes,
            launchAtLogin: false,
            notificationCenterDefaultAccountID: accountID
        )
        try store.save(accounts: [], preferences: preferences)
        let reloaded = try store.load()
        #expect(reloaded.preferences.notificationCenterDefaultAccountID == accountID)
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

    @Test("Reading removes unsupported provider snapshots and keeps the rest")
    func readingRemovesUnsupportedProviderSnapshots() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "QuotaGlanceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "quota-snapshot-v1.json")
        let store = SharedSnapshotStore(fileURL: fileURL)
        let payload = Data(#"""
        {
          "schemaVersion": 2,
          "capturedAt": "1970-01-01T00:01:40Z",
          "aggregate": {
            "balances": [],
            "dailyUsage": [],
            "accounts": [
              {
                "accountID": "00000000-0000-0000-0000-000000000001",
                "displayName": "Primary",
                "provider": "apiInfo",
                "detectedProfile": {
                  "region": "global",
                  "credentialKind": "standard"
                },
                "health": {
                  "healthy": {}
                }
              },
              {
                "accountID": "00000000-0000-0000-0000-000000000002",
                "displayName": "Ali",
                "provider": "bailian",
                "health": {
                  "healthy": {}
                }
              }
            ],
            "isPartial": false
          },
          "accounts": [
            {
              "accountID": "00000000-0000-0000-0000-000000000001",
              "displayName": "Primary",
              "provider": "apiInfo",
              "detectedProfile": {
                "region": "global",
                "credentialKind": "standard"
              },
              "health": {
                "healthy": {}
              }
            },
            {
              "accountID": "00000000-0000-0000-0000-000000000002",
              "displayName": "Ali",
              "provider": "bailian",
              "health": {
                "healthy": {}
              }
            }
          ]
        }
        """#.utf8)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try payload.write(to: fileURL, options: .withoutOverwriting)

        let loaded = try store.read()

        #expect(loaded.accounts.map { $0.displayName } == ["Primary"])
        #expect(loaded.aggregate.accounts.map { $0.displayName } == ["Primary"])

        let persisted = try store.read()
        #expect(persisted.accounts == loaded.accounts)
        #expect(persisted.aggregate.accounts == loaded.aggregate.accounts)
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
