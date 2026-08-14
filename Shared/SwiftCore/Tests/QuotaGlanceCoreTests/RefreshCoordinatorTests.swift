import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Refresh coordination")
struct RefreshCoordinatorTests {
    @Test("Non-interactive refresh reports credentials that need Keychain approval")
    func nonInteractiveRefreshReportsKeychainApproval() async throws {
        let account = testAccounts()[0]
        let credentials = InteractionRequiredCredentialStore()
        let coordinator = RefreshCoordinator(
            credentialStore: credentials,
            provider: RoutingUsageProvider(
                id: .apiInfo,
                snapshot: usage(remaining: "10")
            ),
            aggregator: SnapshotAggregator(calendar: utcCalendar),
            timeout: 1,
            now: { Date(timeIntervalSince1970: 100) }
        )

        let result = try await coordinator.refresh(
            accounts: [account],
            credentialAccessMode: .nonInteractive
        )

        #expect(await credentials.accessModes == [.nonInteractive])
        #expect(
            result.accountSnapshots[account.id]?.health
                == .unavailable(.keychainAccessRequired)
        )
    }

    @Test("Each account routes through its provider with the persisted profile")
    func accountsRouteThroughProviderRegistry() async throws {
        let kimiAccount = Account(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            displayName: "Kimi China",
            provider: .kimi,
            detectedProfile: ProviderProfile(
                region: .china,
                credentialKind: .standard
            ),
            sortOrder: 0
        )
        let openRouterAccount = Account(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            displayName: "OpenRouter Admin",
            provider: .openRouter,
            detectedProfile: ProviderProfile(
                region: .global,
                credentialKind: .management
            ),
            sortOrder: 1
        )
        let credentials = MemoryCredentialStore(values: [
            kimiAccount.id: "kimi-key",
            openRouterAccount.id: "openrouter-key",
        ])
        let kimi = RoutingUsageProvider(id: .kimi, snapshot: usage(remaining: "10"))
        let openRouter = RoutingUsageProvider(
            id: .openRouter,
            snapshot: usage(remaining: "20")
        )
        let coordinator = RefreshCoordinator(
            credentialStore: credentials,
            registry: ProviderRegistry(providers: [kimi, openRouter]),
            aggregator: SnapshotAggregator(calendar: utcCalendar),
            timeout: 1,
            now: { Date(timeIntervalSince1970: 200) }
        )

        let result = try await coordinator.refresh(
            accounts: [kimiAccount, openRouterAccount]
        )

        #expect(await kimi.calls == [
            ProviderFetchCall(
                apiKey: "kimi-key",
                profile: ProviderProfile(region: .china, credentialKind: .standard)
            ),
        ])
        #expect(await openRouter.calls == [
            ProviderFetchCall(
                apiKey: "openrouter-key",
                profile: ProviderProfile(region: .global, credentialKind: .management)
            ),
        ])
        #expect(result.accountSnapshots[kimiAccount.id]?.provider == .kimi)
        #expect(
            result.accountSnapshots[openRouterAccount.id]?.detectedProfile
                == openRouterAccount.detectedProfile
        )
    }

    @Test("Concurrent refresh requests coalesce into one provider call per account")
    func concurrentRefreshesCoalesce() async throws {
        let accounts = testAccounts()
        let credentials = MemoryCredentialStore(values: [
            accounts[0].id: "first-key",
            accounts[1].id: "second-key",
        ])
        let provider = BlockingUsageProvider(snapshot: usage(remaining: "10"))
        let coordinator = RefreshCoordinator(
            credentialStore: credentials,
            provider: provider,
            aggregator: SnapshotAggregator(calendar: utcCalendar),
            timeout: 1,
            now: { Date(timeIntervalSince1970: 100) }
        )

        async let first = coordinator.refresh(accounts: accounts)
        async let second = coordinator.refresh(accounts: accounts)
        await provider.waitForCallCount(accounts.count)
        await provider.release()
        let (firstResult, secondResult) = try await (first, second)

        #expect(await provider.callCount == accounts.count)
        #expect(firstResult == secondResult)
        #expect(firstResult.outcome == .fresh)
    }

    @Test("A changed account configuration supersedes an in-flight refresh")
    func changedAccountConfigurationSupersedesInFlightRefresh() async throws {
        let oldAccount = testAccounts()[0]
        var renamedAccount = oldAccount
        renamedAccount.displayName = "Renamed"
        let provider = BlockingUsageProvider(snapshot: usage(remaining: "10"))
        let coordinator = RefreshCoordinator(
            credentialStore: MemoryCredentialStore(values: [oldAccount.id: "key"]),
            provider: provider,
            aggregator: SnapshotAggregator(calendar: utcCalendar),
            timeout: 1,
            now: { Date(timeIntervalSince1970: 100) }
        )

        let oldRefresh = Task {
            try await coordinator.refresh(accounts: [oldAccount])
        }
        await provider.waitForCallCount(1)
        let renamedRefresh = Task {
            try await coordinator.refresh(accounts: [renamedAccount])
        }
        let startedSecondCall = await provider.reachesCallCount(2)
        await provider.release()

        let oldRefreshWasSuperseded: Bool
        do {
            _ = try await oldRefresh.value
            oldRefreshWasSuperseded = false
        } catch {
            oldRefreshWasSuperseded = true
        }
        let renamedResult = try await renamedRefresh.value

        #expect(startedSecondCall)
        #expect(oldRefreshWasSuperseded)
        #expect(await provider.callCount == 2)
        #expect(renamedResult.accountSnapshots[oldAccount.id]?.displayName == "Renamed")
    }

    @Test("A failed account keeps its last success and marks the aggregate partial")
    func failedAccountKeepsLastSuccess() async throws {
        let accounts = testAccounts()
        let previous = accountSnapshot(
            account: accounts[1],
            usage: usage(remaining: "100"),
            health: .healthy
        )
        let credentials = MemoryCredentialStore(values: [
            accounts[0].id: "fresh-key",
            accounts[1].id: "failing-key",
        ])
        let provider = ScriptedUsageProvider(
            successes: ["fresh-key": usage(remaining: "10")],
            failures: ["failing-key": .rateLimited]
        )
        let recorder = SnapshotRecorder()
        let coordinator = RefreshCoordinator(
            credentialStore: credentials,
            provider: provider,
            aggregator: SnapshotAggregator(calendar: utcCalendar),
            initialSnapshots: [previous],
            timeout: 1,
            now: { Date(timeIntervalSince1970: 200) },
            snapshotWriter: { snapshot in
                await recorder.write(snapshot)
            }
        )

        let result = try await coordinator.refresh(accounts: accounts)
        let failed = try #require(result.accountSnapshots[accounts[1].id])

        #expect(failed.usage == previous.usage)
        #expect(failed.lastSuccessAt == previous.lastSuccessAt)
        #expect(failed.health == .stale(.rateLimited))
        #expect(result.aggregate.remaining == usd("110"))
        #expect(result.aggregate.isPartial)
        #expect(result.outcome == .partial)
        #expect(await recorder.snapshots == [result.envelope])
    }

    @Test("A detected replacement snapshot becomes the refresh failure fallback")
    func detectedReplacementSnapshotBecomesFailureFallback() async throws {
        let accountID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
        let oldAccount = Account(
            id: accountID,
            displayName: "Old API Info",
            provider: .apiInfo
        )
        let replacementAccount = Account(
            id: accountID,
            displayName: "Kimi China",
            provider: .kimi,
            detectedProfile: ProviderProfile(
                region: .china,
                credentialKind: .standard
            )
        )
        let oldSnapshot = accountSnapshot(
            account: oldAccount,
            usage: usage(remaining: "100"),
            health: .healthy
        )
        let detectedUsage = ProviderUsageSnapshot(
            remaining: Money(amount: 25, currency: "CNY"),
            receivedAt: Date(timeIntervalSince1970: 150)
        )
        let detectedSnapshot = accountSnapshot(
            account: replacementAccount,
            usage: detectedUsage,
            health: .healthy
        )
        let coordinator = RefreshCoordinator(
            credentialStore: MemoryCredentialStore(values: [accountID: "replacement-key"]),
            registry: ProviderRegistry(providers: [
                FailingUsageProvider(id: .kimi, error: .rateLimited),
            ]),
            aggregator: SnapshotAggregator(calendar: utcCalendar),
            initialSnapshots: [oldSnapshot],
            timeout: 1,
            now: { Date(timeIntervalSince1970: 200) }
        )

        await coordinator.recordSuccessfulSnapshot(detectedSnapshot)
        let result = try await coordinator.refresh(accounts: [replacementAccount])
        let fallback = try #require(result.accountSnapshots[accountID])

        #expect(fallback.provider == .kimi)
        #expect(fallback.detectedProfile == replacementAccount.detectedProfile)
        #expect(fallback.usage == detectedUsage)
        #expect(fallback.health == .stale(.rateLimited))
    }

    @Test("Recording a detected snapshot supersedes an in-flight refresh")
    func detectedSnapshotSupersedesInFlightRefresh() async throws {
        let account = testAccounts()[0]
        let provider = BlockingThenFailingUsageProvider(
            firstSnapshot: usage(remaining: "100")
        )
        let coordinator = RefreshCoordinator(
            credentialStore: MemoryCredentialStore(values: [account.id: "key"]),
            provider: provider,
            aggregator: SnapshotAggregator(calendar: utcCalendar),
            timeout: 1,
            now: { Date(timeIntervalSince1970: 200) }
        )
        let detectedUsage = usage(remaining: "25")
        let detectedSnapshot = accountSnapshot(
            account: account,
            usage: detectedUsage,
            health: .healthy
        )

        let oldRefresh = Task {
            try await coordinator.refresh(accounts: [account])
        }
        await provider.waitForFirstCall()
        await coordinator.recordSuccessfulSnapshot(detectedSnapshot)
        await provider.releaseFirstCall()

        let oldRefreshWasSuperseded: Bool
        do {
            _ = try await oldRefresh.value
            oldRefreshWasSuperseded = false
        } catch {
            oldRefreshWasSuperseded = true
        }
        #expect(oldRefreshWasSuperseded)

        let nextRefresh = try await coordinator.refresh(accounts: [account])
        let fallback = try #require(nextRefresh.accountSnapshots[account.id])
        #expect(fallback.usage == detectedUsage)
        #expect(fallback.health == .stale(.rateLimited))
    }

    @Test("Removing an account also removes its refresh failure fallback")
    func removingAccountRemovesFailureFallback() async throws {
        let account = testAccounts()[0]
        let previous = accountSnapshot(
            account: account,
            usage: usage(remaining: "100"),
            health: .healthy
        )
        let coordinator = RefreshCoordinator(
            credentialStore: MemoryCredentialStore(values: [:]),
            provider: FailingUsageProvider(id: .apiInfo, error: .invalidCredential),
            aggregator: SnapshotAggregator(calendar: utcCalendar),
            initialSnapshots: [previous],
            timeout: 1,
            now: { Date(timeIntervalSince1970: 200) }
        )

        await coordinator.removeSnapshot(for: account.id)
        let result = try await coordinator.refresh(accounts: [account])
        let fallback = try #require(result.accountSnapshots[account.id])

        #expect(fallback.usage == nil)
        #expect(fallback.health == .unavailable(.missingCredential))
    }

    @Test("Removing a snapshot supersedes an in-flight refresh")
    func removingSnapshotSupersedesInFlightRefresh() async throws {
        let account = testAccounts()[0]
        let provider = BlockingThenFailingUsageProvider(
            firstSnapshot: usage(remaining: "100")
        )
        let coordinator = RefreshCoordinator(
            credentialStore: MemoryCredentialStore(values: [account.id: "key"]),
            provider: provider,
            aggregator: SnapshotAggregator(calendar: utcCalendar),
            timeout: 1,
            now: { Date(timeIntervalSince1970: 200) }
        )

        let oldRefresh = Task {
            try await coordinator.refresh(accounts: [account])
        }
        await provider.waitForFirstCall()
        await coordinator.removeSnapshot(for: account.id)
        await provider.releaseFirstCall()

        let oldRefreshWasSuperseded: Bool
        do {
            _ = try await oldRefresh.value
            oldRefreshWasSuperseded = false
        } catch {
            oldRefreshWasSuperseded = true
        }
        #expect(oldRefreshWasSuperseded)

        let nextRefresh = try await coordinator.refresh(accounts: [account])
        let fallback = try #require(nextRefresh.accountSnapshots[account.id])
        #expect(fallback.usage == nil)
        #expect(fallback.health == .unavailable(.rateLimited))
    }

    @Test("A provider call exceeding its deadline is marked timed out")
    func providerDeadlineIsEnforced() async throws {
        let account = testAccounts()[0]
        let credentials = MemoryCredentialStore(values: [account.id: "slow-key"])
        let provider = DelayedUsageProvider(
            delayNanoseconds: 20_000_000,
            snapshot: usage(remaining: "10")
        )
        let recorder = SnapshotRecorder()
        let coordinator = RefreshCoordinator(
            credentialStore: credentials,
            provider: provider,
            aggregator: SnapshotAggregator(calendar: utcCalendar),
            timeout: 0.001,
            now: { Date(timeIntervalSince1970: 200) },
            snapshotWriter: { snapshot in
                await recorder.write(snapshot)
            }
        )

        let result = try await coordinator.refresh(accounts: [account])

        #expect(result.outcome == .allFailed)
        #expect(result.accountSnapshots[account.id]?.health == .unavailable(.timeout))
        #expect(result.accountSnapshots[account.id]?.usage == nil)
        #expect(await recorder.snapshots.isEmpty)
    }
}

private func testAccounts() -> [Account] {
    [
        Account(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            displayName: "Primary",
            sortOrder: 0
        ),
        Account(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            displayName: "Backup",
            sortOrder: 1
        ),
    ]
}

private func usd(_ amount: String) -> Money {
    Money(amount: Decimal(string: amount)!, currency: "USD")
}

private func usage(remaining: String) -> ProviderUsageSnapshot {
    ProviderUsageSnapshot(
        remaining: usd(remaining),
        receivedAt: Date(timeIntervalSince1970: 100)
    )
}

private func accountSnapshot(
    account: Account,
    usage: ProviderUsageSnapshot,
    health: AccountHealth
) -> AccountSnapshot {
    AccountSnapshot(
        accountID: account.id,
        displayName: account.displayName,
        lowBalanceThreshold: account.lowBalanceThreshold,
        usage: usage,
        health: health,
        lastSuccessAt: usage.receivedAt
    )
}

private actor MemoryCredentialStore: CredentialStore {
    private let values: [UUID: String]

    init(values: [UUID: String]) {
        self.values = values
    }

    func read(for accountID: UUID) async throws -> String {
        guard let value = values[accountID] else {
            throw CredentialStoreError.notFound
        }
        return value
    }

    func save(_ credential: String, for accountID: UUID) async throws {}

    func delete(for accountID: UUID) async throws {}
}

private actor InteractionRequiredCredentialStore: CredentialStore {
    private(set) var accessModes: [CredentialAccessMode] = []

    func read(for accountID: UUID) async throws -> String {
        throw CredentialStoreError.interactionRequired
    }

    func read(
        for accountID: UUID,
        accessMode: CredentialAccessMode
    ) async throws -> String {
        accessModes.append(accessMode)
        throw CredentialStoreError.interactionRequired
    }

    func save(_ credential: String, for accountID: UUID) async throws {}

    func delete(for accountID: UUID) async throws {}
}

private actor BlockingUsageProvider: UsageProvider {
    nonisolated let id = ProviderID.apiInfo
    private let snapshot: ProviderUsageSnapshot
    private var isReleased = false
    private var blocked: [CheckedContinuation<Void, Never>] = []
    private var callWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var callCount = 0

    nonisolated var descriptor: ProviderDescriptor {
        ProviderCatalog.descriptor(for: id)
    }

    init(snapshot: ProviderUsageSnapshot) {
        self.snapshot = snapshot
    }

    func detect(apiKey: String) async throws -> ProviderDetection {
        ProviderDetection(
            profile: .apiInfo,
            snapshot: try await fetch(apiKey: apiKey, profile: .apiInfo)
        )
    }

    func fetch(
        apiKey: String,
        profile: ProviderProfile
    ) async throws -> ProviderUsageSnapshot {
        callCount += 1
        resumeSatisfiedCallWaiters()
        if !isReleased {
            await withCheckedContinuation { continuation in
                blocked.append(continuation)
            }
        }
        return snapshot
    }

    func waitForCallCount(_ expected: Int) async {
        guard callCount < expected else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append((expected, continuation))
        }
    }

    func reachesCallCount(_ expected: Int) async -> Bool {
        for _ in 0..<50 {
            if callCount >= expected {
                return true
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return callCount >= expected
    }

    func release() {
        isReleased = true
        let continuations = blocked
        blocked.removeAll()
        continuations.forEach { $0.resume() }
    }

    private func resumeSatisfiedCallWaiters() {
        let satisfied = callWaiters.filter { $0.0 <= callCount }
        callWaiters.removeAll { $0.0 <= callCount }
        satisfied.forEach { $0.1.resume() }
    }
}

private actor BlockingThenFailingUsageProvider: UsageProvider {
    nonisolated let id = ProviderID.apiInfo
    private let firstSnapshot: ProviderUsageSnapshot
    private var firstCallContinuation: CheckedContinuation<Void, Never>?
    private var firstCallWaiters: [CheckedContinuation<Void, Never>] = []
    private var callCount = 0

    nonisolated var descriptor: ProviderDescriptor {
        ProviderCatalog.descriptor(for: id)
    }

    init(firstSnapshot: ProviderUsageSnapshot) {
        self.firstSnapshot = firstSnapshot
    }

    func detect(apiKey: String) async throws -> ProviderDetection {
        ProviderDetection(
            profile: .apiInfo,
            snapshot: try await fetch(apiKey: apiKey, profile: .apiInfo)
        )
    }

    func fetch(
        apiKey: String,
        profile: ProviderProfile
    ) async throws -> ProviderUsageSnapshot {
        callCount += 1
        if callCount == 1 {
            let waiters = firstCallWaiters
            firstCallWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                firstCallContinuation = continuation
            }
            return firstSnapshot
        }
        throw ProviderError.rateLimited
    }

    func waitForFirstCall() async {
        guard callCount == 0 else { return }
        await withCheckedContinuation { continuation in
            firstCallWaiters.append(continuation)
        }
    }

    func releaseFirstCall() {
        firstCallContinuation?.resume()
        firstCallContinuation = nil
    }
}

private actor ScriptedUsageProvider: UsageProvider {
    nonisolated let id = ProviderID.apiInfo
    private let successes: [String: ProviderUsageSnapshot]
    private let failures: [String: ProviderError]

    nonisolated var descriptor: ProviderDescriptor {
        ProviderCatalog.descriptor(for: id)
    }

    init(
        successes: [String: ProviderUsageSnapshot],
        failures: [String: ProviderError]
    ) {
        self.successes = successes
        self.failures = failures
    }

    func detect(apiKey: String) async throws -> ProviderDetection {
        ProviderDetection(
            profile: .apiInfo,
            snapshot: try await fetch(apiKey: apiKey, profile: .apiInfo)
        )
    }

    func fetch(
        apiKey: String,
        profile: ProviderProfile
    ) async throws -> ProviderUsageSnapshot {
        if let failure = failures[apiKey] {
            throw failure
        }
        return try #require(successes[apiKey])
    }
}

private struct FailingUsageProvider: UsageProvider {
    let id: ProviderID
    let error: ProviderError

    var descriptor: ProviderDescriptor {
        ProviderCatalog.descriptor(for: id)
    }

    func detect(apiKey: String) async throws -> ProviderDetection {
        throw error
    }

    func fetch(
        apiKey: String,
        profile: ProviderProfile
    ) async throws -> ProviderUsageSnapshot {
        throw error
    }
}

private struct DelayedUsageProvider: UsageProvider {
    let id = ProviderID.apiInfo
    let delayNanoseconds: UInt64
    let snapshot: ProviderUsageSnapshot

    var descriptor: ProviderDescriptor {
        ProviderCatalog.descriptor(for: id)
    }

    func detect(apiKey: String) async throws -> ProviderDetection {
        ProviderDetection(
            profile: .apiInfo,
            snapshot: try await fetch(apiKey: apiKey, profile: .apiInfo)
        )
    }

    func fetch(
        apiKey: String,
        profile: ProviderProfile
    ) async throws -> ProviderUsageSnapshot {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return snapshot
    }
}

private actor SnapshotRecorder {
    private(set) var snapshots: [WidgetSnapshotEnvelope] = []

    func write(_ snapshot: WidgetSnapshotEnvelope) {
        snapshots.append(snapshot)
    }
}

private struct ProviderFetchCall: Equatable, Sendable {
    let apiKey: String
    let profile: ProviderProfile
}

private actor RoutingUsageProvider: UsageProvider {
    nonisolated let id: ProviderID
    private let snapshot: ProviderUsageSnapshot
    private(set) var calls: [ProviderFetchCall] = []

    nonisolated var descriptor: ProviderDescriptor {
        ProviderCatalog.descriptor(for: id)
    }

    init(id: ProviderID, snapshot: ProviderUsageSnapshot) {
        self.id = id
        self.snapshot = snapshot
    }

    func detect(apiKey: String) async throws -> ProviderDetection {
        ProviderDetection(
            profile: .apiInfo,
            snapshot: snapshot
        )
    }

    func fetch(
        apiKey: String,
        profile: ProviderProfile
    ) async throws -> ProviderUsageSnapshot {
        calls.append(
            ProviderFetchCall(
                apiKey: apiKey,
                profile: profile
            )
        )
        return snapshot
    }
}

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()
