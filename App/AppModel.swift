import AppKit
import Combine
import Foundation
import QuotaGlanceCore
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var accounts: [Account]
    @Published private(set) var preferences: AppPreferences
    @Published private(set) var latestEnvelope: WidgetSnapshotEnvelope?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var notificationPermission: NotificationPermissionState = .notDetermined
    @Published var selectedAccountID: UUID?

    private let preferencesStore: AccountPreferencesStore
    private let credentialStore: any CredentialStore
    private let registry: ProviderRegistry
    private let refreshCoordinator: RefreshCoordinator
    private let sharedSnapshotStore: SharedSnapshotStore?
    private let notificationService: NotificationService
    private let launchAtLoginService: LaunchAtLoginService
    private var scheduleTask: Task<Void, Never>?
    private var hasStarted = false
    private var accountStateRevision: UInt64 = 0
    private var activeRefreshCount = 0

    init() {
        let preferencesStore = AccountPreferencesStore()
        let stored: StoredAccountPreferences
        let loadError: String?
        do {
            stored = try preferencesStore.load()
            loadError = nil
        } catch {
            stored = StoredAccountPreferences(accounts: [], preferences: .default)
            loadError = "Saved account settings could not be read."
        }

        let credentialStore = KeychainStore()
        let registry = ProviderRegistry(providers: [
            APIInfoProvider(),
            DeepSeekProvider(),
            KimiProvider(),
            OpenRouterProvider(),
            MiniMaxProvider(),
            BioMapCodingProvider(),
        ])
        let sharedStore = QuotaGlanceShared.snapshotStore()
        let notificationService = NotificationService()
        let launchAtLoginService = LaunchAtLoginService()
        let cachedEnvelope = sharedStore.flatMap { try? $0.read() }

        self.accounts = stored.accounts.sorted { $0.sortOrder < $1.sortOrder }
        self.preferences = stored.preferences
        self.latestEnvelope = cachedEnvelope
        self.lastErrorMessage = loadError
        self.preferencesStore = preferencesStore
        self.credentialStore = credentialStore
        self.registry = registry
        self.sharedSnapshotStore = sharedStore
        self.notificationService = notificationService
        self.launchAtLoginService = launchAtLoginService
        self.refreshCoordinator = RefreshCoordinator(
            credentialStore: credentialStore,
            registry: registry,
            initialSnapshots: cachedEnvelope?.accounts ?? []
        )
    }

    var selectedSnapshot: AccountSnapshot? {
        guard let selectedAccountID else { return nil }
        return latestEnvelope?.accounts.first { $0.accountID == selectedAccountID }
    }

    var aggregate: AggregateSnapshot? {
        latestEnvelope?.aggregate
    }

    var supportsLaunchAtLogin: Bool {
        launchAtLoginService.isSupported
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        notificationPermission = await notificationService.permissionState()
        preferences.launchAtLogin = launchAtLoginService.isEnabled
        persistReportingErrors()
        restartSchedule()
        if accounts.contains(where: \.isEnabled) {
            await refresh()
        }
    }

    func refresh() async {
        guard accounts.contains(where: \.isEnabled) else {
            publishCachedState()
            return
        }
        let expectedAccountStateRevision = accountStateRevision
        activeRefreshCount += 1
        isRefreshing = true
        defer {
            activeRefreshCount -= 1
            isRefreshing = activeRefreshCount > 0
        }

        do {
            let result = try await refreshCoordinator.refresh(accounts: accounts)
            guard accountStateRevision == expectedAccountStateRevision else { return }
            if result.outcome != .allFailed {
                try writeSharedSnapshot(result.envelope)
            }
            latestEnvelope = result.envelope
            await evaluateAlerts(snapshots: result.accountSnapshots)
            guard accountStateRevision == expectedAccountStateRevision else { return }
            switch result.outcome {
            case .fresh:
                lastErrorMessage = nil
            case .partial:
                lastErrorMessage = "Some accounts could not be refreshed."
            case .allFailed:
                lastErrorMessage = "No account could be refreshed."
            }
        } catch RefreshCoordinatorError.superseded {
            return
        } catch {
            guard accountStateRevision == expectedAccountStateRevision else { return }
            lastErrorMessage = message(for: error)
        }
    }

    func saveAccount(draft: AccountDraft, editing accountID: UUID?) async throws {
        let previouslyHadThreshold = accountID.flatMap { id in
            accounts.first(where: { $0.id == id })?.lowBalanceThreshold
        } != nil
        var validated = try AccountValidator.validate(
            draft: draft,
            existingAccounts: accounts,
            editingAccountID: accountID
        )

        let detectionKey: String?
        if let apiKey = validated.apiKey {
            detectionKey = apiKey
        } else {
            detectionKey = nil
        }

        let detection: ProviderDetection?
        if let detectionKey {
            let provider = try registry.provider(for: validated.provider)
            detection = try await provider.detect(apiKey: detectionKey)
        } else {
            detection = nil
        }

        let existingProfile = accountID.flatMap { id in
            accounts.first(where: { $0.id == id })?.detectedProfile
        }
        let effectiveProfile = detection?.profile ?? existingProfile
        validated.lowBalanceThreshold = validated.provider
            .normalizedLowBalanceThreshold(
                validated.lowBalanceThreshold,
                profile: effectiveProfile
            )

        let savedAccountID: UUID
        if let accountID {
            try await updateAccount(
                id: accountID,
                validated: validated,
                detectedProfile: detection?.profile
            )
            savedAccountID = accountID
        } else {
            savedAccountID = try await addAccount(
                validated: validated,
                detectedProfile: detection?.profile
            )
        }
        markAccountStateChanged()

        try persist()
        let detectedSnapshot: AccountSnapshot?
        if let detection {
            detectedSnapshot = publishDetectedSnapshot(
                accountID: savedAccountID,
                usage: detection.snapshot
            )
            if let detectedSnapshot {
                await refreshCoordinator.recordSuccessfulSnapshot(detectedSnapshot)
            }
        } else {
            detectedSnapshot = nil
            await refreshCoordinator.invalidateActiveRefresh()
            publishCachedState()
        }
        if !previouslyHadThreshold, validated.lowBalanceThreshold != nil {
            notificationPermission = await notificationService.requestAuthorization()
        }
        if let detectedSnapshot {
            await evaluateAlerts(snapshots: [savedAccountID: detectedSnapshot])
        } else {
            await refresh()
        }
    }

    func deleteAccount(id: UUID) async {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        let removed = accounts.remove(at: index)
        markAccountStateChanged()
        do {
            try await credentialStore.delete(for: id)
        } catch CredentialStoreError.notFound {
            // The metadata should still be removed when the Keychain item is already gone.
        } catch {
            accounts.insert(removed, at: index)
            markAccountStateChanged()
            lastErrorMessage = message(for: error)
            return
        }

        if selectedAccountID == id {
            selectedAccountID = nil
        }
        normalizeSortOrder()
        do {
            try persist()
            await refreshCoordinator.removeSnapshot(for: id)
            publishCachedState()
            await refresh()
        } catch {
            lastErrorMessage = message(for: error)
        }
    }

    func setAccountEnabled(id: UUID, isEnabled: Bool) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].isEnabled = isEnabled
        if !isEnabled {
            accounts[index].alertEpisodeActive = false
        }
        markAccountStateChanged()
        persistReportingErrors()
        publishCachedState()
        Task {
            await refreshCoordinator.invalidateActiveRefresh()
            await refresh()
        }
    }

    func moveAccount(id: UUID, offset: Int) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard accounts.indices.contains(destination) else { return }
        accounts.swapAt(index, destination)
        normalizeSortOrder()
        markAccountStateChanged()
        persistReportingErrors()
        publishCachedState()
    }

    func setRefreshInterval(_ interval: RefreshInterval) {
        preferences.refreshInterval = interval
        persistReportingErrors()
        restartSchedule()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        Task {
            do {
                try launchAtLoginService.setEnabled(enabled)
                preferences.launchAtLogin = launchAtLoginService.isEnabled
                try persist()
            } catch {
                preferences.launchAtLogin = launchAtLoginService.isEnabled
                lastErrorMessage = message(for: error)
            }
        }
    }

    func handle(url: URL) {
        let destination = DeepLinkRouter.destination(
            for: url,
            knownAccountIDs: Set(accounts.map(\.id))
        )
        switch destination {
        case .allAccounts:
            selectedAccountID = nil
        case let .account(accountID):
            selectedAccountID = accountID
        case nil:
            return
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func message(for error: any Error) -> String {
        ErrorPresenter.message(for: error)
    }
}

private extension AppModel {
    func addAccount(
        validated: ValidatedAccountDraft,
        detectedProfile: ProviderProfile?
    ) async throws -> UUID {
        guard let apiKey = validated.apiKey else {
            throw AccountValidationError.emptyAPIKey
        }
        guard let detectedProfile else {
            throw ProviderError.profileMismatch
        }
        let account = Account(
            displayName: validated.displayName,
            provider: validated.provider,
            detectedProfile: detectedProfile,
            isEnabled: validated.isEnabled,
            sortOrder: accounts.count,
            lowBalanceThreshold: validated.lowBalanceThreshold
        )
        try await credentialStore.save(apiKey, for: account.id)
        accounts.append(account)
        return account.id
    }

    func updateAccount(
        id: UUID,
        validated: ValidatedAccountDraft,
        detectedProfile: ProviderProfile?
    ) async throws {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            return
        }
        if let apiKey = validated.apiKey {
            try await credentialStore.save(apiKey, for: id)
        }
        accounts[index].displayName = validated.displayName
        accounts[index].provider = validated.provider
        if let detectedProfile {
            accounts[index].detectedProfile = detectedProfile
        }
        accounts[index].isEnabled = validated.isEnabled
        accounts[index].lowBalanceThreshold = validated.lowBalanceThreshold
        if !validated.isEnabled || validated.lowBalanceThreshold == nil {
            accounts[index].alertEpisodeActive = false
        }
    }

    func normalizeSortOrder() {
        for index in accounts.indices {
            accounts[index].sortOrder = index
        }
    }

    func markAccountStateChanged() {
        accountStateRevision &+= 1
    }

    func persist() throws {
        try preferencesStore.save(
            accounts: accounts,
            preferences: preferences
        )
    }

    func persistReportingErrors() {
        do {
            try persist()
        } catch {
            lastErrorMessage = message(for: error)
        }
    }

    func restartSchedule() {
        scheduleTask?.cancel()
        let interval = UInt64(preferences.refreshInterval.rawValue) * 1_000_000_000
        scheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }
                guard let self else { return }
                await self.refresh()
            }
        }
    }

    func evaluateAlerts(snapshots: [UUID: AccountSnapshot]) async {
        let expectedAccountStateRevision = accountStateRevision
        let evaluation = AlertEvaluator.evaluate(
            accounts: &accounts,
            freshSnapshots: snapshots
        )
        if evaluation.didChange {
            persistReportingErrors()
        }
        guard notificationPermission == .authorized else { return }

        for notification in evaluation.notifications {
            guard accountStateRevision == expectedAccountStateRevision,
                  accounts.contains(where: { $0.id == notification.account.id }) else {
                return
            }
            do {
                try await notificationService.sendLowBalance(
                    account: notification.account,
                    remaining: notification.remaining
                )
            } catch {
                lastErrorMessage = message(for: error)
            }
        }
    }

    func publishDetectedSnapshot(
        accountID: UUID,
        usage: ProviderUsageSnapshot
    ) -> AccountSnapshot? {
        guard let account = accounts.first(where: { $0.id == accountID }) else {
            publishCachedState()
            return nil
        }
        let health: AccountHealth
        if let remaining = usage.primaryBalance?.available.amount,
           let threshold = account.lowBalanceThreshold,
           remaining <= threshold {
            health = .belowThreshold
        } else {
            health = .healthy
        }
        var snapshots = latestEnvelope?.accounts ?? []
        snapshots.removeAll { $0.accountID == accountID }
        let detectedSnapshot = AccountSnapshot(
            accountID: account.id,
            displayName: account.displayName,
            provider: account.provider,
            detectedProfile: account.detectedProfile,
            lowBalanceThreshold: account.lowBalanceThreshold,
            usage: usage,
            health: health,
            lastSuccessAt: usage.receivedAt
        )
        snapshots.append(detectedSnapshot)
        publish(snapshots: snapshots, capturedAt: usage.receivedAt)
        return detectedSnapshot
    }

    func publishCachedState() {
        publish(
            snapshots: latestEnvelope?.accounts ?? [],
            capturedAt: .now
        )
    }

    func publish(snapshots: [AccountSnapshot], capturedAt: Date) {
        let aggregate = SnapshotAggregator().aggregate(
            accounts: accounts,
            snapshots: snapshots,
            now: capturedAt
        )
        let envelope = WidgetSnapshotEnvelope(
            capturedAt: capturedAt,
            aggregate: aggregate,
            accounts: aggregate.accounts
        )
        latestEnvelope = envelope
        do {
            try writeSharedSnapshot(envelope)
        } catch {
            lastErrorMessage = message(for: error)
        }
    }

    func writeSharedSnapshot(_ envelope: WidgetSnapshotEnvelope) throws {
        guard let sharedSnapshotStore else { return }
        try sharedSnapshotStore.write(envelope)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
