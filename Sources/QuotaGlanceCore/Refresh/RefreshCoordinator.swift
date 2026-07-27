import Foundation

public enum RefreshOutcome: Equatable, Sendable {
    case fresh
    case partial
    case allFailed
}

public enum RefreshCoordinatorError: Error, Equatable, Sendable {
    case superseded
}

public struct RefreshResult: Equatable, Sendable {
    public var outcome: RefreshOutcome
    public var accountSnapshots: [UUID: AccountSnapshot]
    public var aggregate: AggregateSnapshot
    public var envelope: WidgetSnapshotEnvelope

    public init(
        outcome: RefreshOutcome,
        accountSnapshots: [UUID: AccountSnapshot],
        aggregate: AggregateSnapshot,
        envelope: WidgetSnapshotEnvelope
    ) {
        self.outcome = outcome
        self.accountSnapshots = accountSnapshots
        self.aggregate = aggregate
        self.envelope = envelope
    }
}

public actor RefreshCoordinator {
    private struct InFlightRefresh {
        let id: UUID
        let accounts: [Account]
        let credentialAccessMode: CredentialAccessMode
        let task: Task<RefreshResult, Error>
    }

    private let credentialStore: any CredentialStore
    private let registry: ProviderRegistry
    private let aggregator: SnapshotAggregator
    private let timeout: TimeInterval
    private let now: @Sendable () -> Date
    private let snapshotWriter: (@Sendable (WidgetSnapshotEnvelope) async throws -> Void)?

    private var previousSnapshots: [UUID: AccountSnapshot]
    private var stateRevision: UInt64 = 0
    private var inFlight: InFlightRefresh?

    public init(
        credentialStore: any CredentialStore,
        registry: ProviderRegistry,
        aggregator: SnapshotAggregator = SnapshotAggregator(),
        initialSnapshots: [AccountSnapshot] = [],
        timeout: TimeInterval = 15,
        now: @escaping @Sendable () -> Date = { .now },
        snapshotWriter: (@Sendable (WidgetSnapshotEnvelope) async throws -> Void)? = nil
    ) {
        self.credentialStore = credentialStore
        self.registry = registry
        self.aggregator = aggregator
        self.previousSnapshots = Dictionary(
            initialSnapshots.map { ($0.accountID, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        self.timeout = timeout
        self.now = now
        self.snapshotWriter = snapshotWriter
    }

    public init(
        credentialStore: any CredentialStore,
        provider: any UsageProvider,
        aggregator: SnapshotAggregator = SnapshotAggregator(),
        initialSnapshots: [AccountSnapshot] = [],
        timeout: TimeInterval = 15,
        now: @escaping @Sendable () -> Date = { .now },
        snapshotWriter: (@Sendable (WidgetSnapshotEnvelope) async throws -> Void)? = nil
    ) {
        self.init(
            credentialStore: credentialStore,
            registry: ProviderRegistry(providers: [provider]),
            aggregator: aggregator,
            initialSnapshots: initialSnapshots,
            timeout: timeout,
            now: now,
            snapshotWriter: snapshotWriter
        )
    }

    public func refresh(
        accounts: [Account],
        credentialAccessMode: CredentialAccessMode = .interactive
    ) async throws -> RefreshResult {
        if let inFlight {
            if inFlight.accounts == accounts,
               inFlight.credentialAccessMode == credentialAccessMode {
                return try await inFlight.task.value
            }
            supersedeInFlightRefresh()
        }

        let refreshID = UUID()
        let expectedStateRevision = stateRevision
        let task = Task {
            try await self.performRefresh(
                accounts: accounts,
                credentialAccessMode: credentialAccessMode,
                expectedStateRevision: expectedStateRevision
            )
        }
        inFlight = InFlightRefresh(
            id: refreshID,
            accounts: accounts,
            credentialAccessMode: credentialAccessMode,
            task: task
        )
        defer {
            if inFlight?.id == refreshID {
                inFlight = nil
            }
        }
        return try await task.value
    }

    public func recordSuccessfulSnapshot(_ snapshot: AccountSnapshot) {
        guard snapshot.usage != nil else { return }
        switch snapshot.health {
        case .healthy, .belowThreshold:
            supersedeInFlightRefresh()
            previousSnapshots[snapshot.accountID] = snapshot
        case .stale, .unavailable:
            return
        }
    }

    public func removeSnapshot(for accountID: UUID) {
        supersedeInFlightRefresh()
        previousSnapshots.removeValue(forKey: accountID)
    }

    public func invalidateActiveRefresh() {
        supersedeInFlightRefresh()
    }
}

private extension RefreshCoordinator {
    enum AccountRefresh: Sendable {
        case success(Account, ProviderUsageSnapshot)
        case failure(Account, SnapshotFailure)
    }

    func performRefresh(
        accounts: [Account],
        credentialAccessMode: CredentialAccessMode,
        expectedStateRevision: UInt64
    ) async throws -> RefreshResult {
        let enabledAccounts = accounts.filter(\.isEnabled)
        let credentialStore = credentialStore
        let registry = registry
        let timeout = timeout

        let refreshes = await withTaskGroup(
            of: AccountRefresh.self,
            returning: [AccountRefresh].self
        ) { group in
            for account in enabledAccounts {
                group.addTask {
                    do {
                        let apiKey = try await credentialStore.read(
                            for: account.id,
                            accessMode: credentialAccessMode
                        )
                        let provider = try registry.provider(for: account.provider)
                        guard let profile = account.detectedProfile else {
                            throw ProviderError.profileMismatch
                        }
                        let usage = try await Self.fetch(
                            provider: provider,
                            apiKey: apiKey,
                            profile: profile,
                            timeout: timeout
                        )
                        return .success(account, usage)
                    } catch {
                        return .failure(account, Self.snapshotFailure(for: error))
                    }
                }
            }

            var results: [AccountRefresh] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        guard stateRevision == expectedStateRevision else {
            throw RefreshCoordinatorError.superseded
        }

        var accountSnapshots: [UUID: AccountSnapshot] = [:]
        var successCount = 0
        for refresh in refreshes {
            switch refresh {
            case let .success(account, usage):
                successCount += 1
                let snapshot = AccountSnapshot(
                    accountID: account.id,
                    displayName: account.displayName,
                    provider: account.provider,
                    detectedProfile: account.detectedProfile,
                    lowBalanceThreshold: account.lowBalanceThreshold,
                    usage: usage,
                    health: health(
                        account: account,
                        remaining: usage.primaryBalance?.available.amount
                    ),
                    lastSuccessAt: usage.receivedAt
                )
                accountSnapshots[account.id] = snapshot
                previousSnapshots[account.id] = snapshot

            case let .failure(account, failure):
                let snapshot: AccountSnapshot
                if var previous = previousSnapshots[account.id], previous.usage != nil {
                    previous.displayName = account.displayName
                    previous.provider = account.provider
                    previous.detectedProfile = account.detectedProfile
                    previous.lowBalanceThreshold = account.lowBalanceThreshold
                    previous.health = .stale(failure)
                    snapshot = previous
                } else {
                    snapshot = AccountSnapshot(
                        accountID: account.id,
                        displayName: account.displayName,
                        provider: account.provider,
                        detectedProfile: account.detectedProfile,
                        lowBalanceThreshold: account.lowBalanceThreshold,
                        health: .unavailable(failure)
                    )
                }
                accountSnapshots[account.id] = snapshot
                previousSnapshots[account.id] = snapshot
            }
        }

        let capturedAt = now()
        let orderedSnapshots = enabledAccounts.compactMap { accountSnapshots[$0.id] }
        let aggregate = aggregator.aggregate(
            accounts: enabledAccounts,
            snapshots: orderedSnapshots,
            now: capturedAt
        )
        let envelope = WidgetSnapshotEnvelope(
            capturedAt: capturedAt,
            aggregate: aggregate,
            accounts: aggregate.accounts
        )
        let outcome: RefreshOutcome
        if successCount == enabledAccounts.count {
            outcome = .fresh
        } else if successCount == 0 {
            outcome = .allFailed
        } else {
            outcome = .partial
        }
        if successCount > 0 {
            try await snapshotWriter?(envelope)
        }
        guard stateRevision == expectedStateRevision else {
            throw RefreshCoordinatorError.superseded
        }

        return RefreshResult(
            outcome: outcome,
            accountSnapshots: accountSnapshots,
            aggregate: aggregate,
            envelope: envelope
        )
    }

    func supersedeInFlightRefresh() {
        stateRevision &+= 1
        inFlight?.task.cancel()
        inFlight = nil
    }

    func health(account: Account, remaining: Decimal?) -> AccountHealth {
        if let remaining,
           let threshold = account.lowBalanceThreshold,
           remaining <= threshold {
            return .belowThreshold
        }
        return .healthy
    }

    nonisolated static func snapshotFailure(for error: any Error) -> SnapshotFailure {
        switch error {
        case is RefreshTimeoutError:
            .timeout
        case CredentialStoreError.notFound:
            .missingCredential
        case CredentialStoreError.interactionRequired:
            .keychainAccessRequired
        case ProviderError.invalidCredential, ProviderError.providerInactive:
            .invalidCredential
        case ProviderError.rateLimited:
            .rateLimited
        case ProviderError.invalidResponse:
            .invalidResponse
        case let urlError as URLError
            where urlError.code == .notConnectedToInternet
                || urlError.code == .networkConnectionLost:
            .offline
        case let urlError as URLError where urlError.code == .timedOut:
            .timeout
        default:
            .providerError
        }
    }

    nonisolated static func fetch(
        provider: any UsageProvider,
        apiKey: String,
        profile: ProviderProfile,
        timeout: TimeInterval
    ) async throws -> ProviderUsageSnapshot {
        try await withThrowingTaskGroup(
            of: ProviderUsageSnapshot.self,
            returning: ProviderUsageSnapshot.self
        ) { group in
            group.addTask {
                try await provider.fetch(apiKey: apiKey, profile: profile)
            }
            group.addTask {
                let maximumSeconds = Double(UInt64.max) / 1_000_000_000
                let seconds = timeout.isFinite
                    ? min(max(timeout, 0), maximumSeconds)
                    : maximumSeconds
                try await Task.sleep(
                    nanoseconds: UInt64(seconds * 1_000_000_000)
                )
                throw RefreshTimeoutError()
            }
            defer { group.cancelAll() }

            guard let first = try await group.next() else {
                throw RefreshTimeoutError()
            }
            return first
        }
    }

    struct RefreshTimeoutError: Error, Sendable {}
}
