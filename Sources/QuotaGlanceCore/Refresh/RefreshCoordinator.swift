import Foundation

public enum RefreshOutcome: Equatable, Sendable {
    case fresh
    case partial
    case allFailed
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
    private let credentialStore: any CredentialStore
    private let provider: any UsageProvider
    private let aggregator: SnapshotAggregator
    private let timeout: TimeInterval
    private let now: @Sendable () -> Date
    private let snapshotWriter: (@Sendable (WidgetSnapshotEnvelope) async throws -> Void)?

    private var previousSnapshots: [UUID: AccountSnapshot]
    private var inFlight: Task<RefreshResult, Error>?

    public init(
        credentialStore: any CredentialStore,
        provider: any UsageProvider,
        aggregator: SnapshotAggregator = SnapshotAggregator(),
        initialSnapshots: [AccountSnapshot] = [],
        timeout: TimeInterval = 15,
        now: @escaping @Sendable () -> Date = { .now },
        snapshotWriter: (@Sendable (WidgetSnapshotEnvelope) async throws -> Void)? = nil
    ) {
        self.credentialStore = credentialStore
        self.provider = provider
        self.aggregator = aggregator
        self.previousSnapshots = Dictionary(
            initialSnapshots.map { ($0.accountID, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        self.timeout = timeout
        self.now = now
        self.snapshotWriter = snapshotWriter
    }

    public func refresh(accounts: [Account]) async throws -> RefreshResult {
        if let inFlight {
            return try await inFlight.value
        }

        let task = Task { try await self.performRefresh(accounts: accounts) }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}

private extension RefreshCoordinator {
    enum AccountRefresh: Sendable {
        case success(Account, ProviderUsageSnapshot)
        case failure(Account, SnapshotFailure)
    }

    func performRefresh(accounts: [Account]) async throws -> RefreshResult {
        let enabledAccounts = accounts.filter(\.isEnabled)
        let credentialStore = credentialStore
        let provider = provider
        let timeout = timeout

        let refreshes = await withTaskGroup(
            of: AccountRefresh.self,
            returning: [AccountRefresh].self
        ) { group in
            for account in enabledAccounts {
                group.addTask {
                    do {
                        let apiKey = try await credentialStore.read(for: account.id)
                        let usage = try await Self.fetch(
                            provider: provider,
                            apiKey: apiKey,
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

        var accountSnapshots: [UUID: AccountSnapshot] = [:]
        var successCount = 0
        for refresh in refreshes {
            switch refresh {
            case let .success(account, usage):
                successCount += 1
                let snapshot = AccountSnapshot(
                    accountID: account.id,
                    displayName: account.displayName,
                    lowBalanceThreshold: account.lowBalanceThreshold,
                    usage: usage,
                    health: health(account: account, remaining: usage.remaining.amount),
                    lastSuccessAt: usage.receivedAt
                )
                accountSnapshots[account.id] = snapshot
                previousSnapshots[account.id] = snapshot

            case let .failure(account, failure):
                let snapshot: AccountSnapshot
                if var previous = previousSnapshots[account.id], previous.usage != nil {
                    previous.displayName = account.displayName
                    previous.lowBalanceThreshold = account.lowBalanceThreshold
                    previous.health = .stale(failure)
                    snapshot = previous
                } else {
                    snapshot = AccountSnapshot(
                        accountID: account.id,
                        displayName: account.displayName,
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

        return RefreshResult(
            outcome: outcome,
            accountSnapshots: accountSnapshots,
            aggregate: aggregate,
            envelope: envelope
        )
    }

    func health(account: Account, remaining: Decimal) -> AccountHealth {
        if let threshold = account.lowBalanceThreshold, remaining <= threshold {
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
        timeout: TimeInterval
    ) async throws -> ProviderUsageSnapshot {
        try await withThrowingTaskGroup(
            of: ProviderUsageSnapshot.self,
            returning: ProviderUsageSnapshot.self
        ) { group in
            group.addTask {
                try await provider.fetch(apiKey: apiKey)
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
