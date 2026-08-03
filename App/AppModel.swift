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
            loadError = L10n.string(
                .savedSettingsUnreadable,
                language: AppLanguage.resolve(preference: .system)
            )
        }

        let credentialStore = KeychainStore()
        let registry = ProviderRegistry(providers: ProviderCatalog.all)
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

    var resolvedLanguage: AppLanguage {
        AppLanguage.resolve(preference: preferences.preferredLanguage)
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        notificationPermission = await notificationService.permissionState()
        preferences.launchAtLogin = launchAtLoginService.isEnabled
        do {
            try persist()
            try mirrorNCWidgetPreferences()
        } catch {
            lastErrorMessage = message(for: error)
        }
        restartSchedule()
        if accounts.contains(where: \.isEnabled) {
            await refresh(credentialAccessMode: .nonInteractive)
        }
    }

    func refresh() async {
        await refresh(credentialAccessMode: .interactive)
    }

    private func refresh(credentialAccessMode: CredentialAccessMode) async {
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
            let result = try await refreshCoordinator.refresh(
                accounts: accounts,
                credentialAccessMode: credentialAccessMode
            )
            guard accountStateRevision == expectedAccountStateRevision else { return }
            if result.outcome != .allFailed {
                try writeSharedSnapshot(result.envelope)
            }
            latestEnvelope = result.envelope
            await evaluateAlerts(snapshots: result.accountSnapshots)
            guard accountStateRevision == expectedAccountStateRevision else { return }
            let lockedCredentialCount = result.accountSnapshots.values.filter {
                switch $0.health {
                case .stale(.keychainAccessRequired),
                     .unavailable(.keychainAccessRequired):
                    true
                default:
                    false
                }
            }.count
            if lockedCredentialCount > 0 {
                if lockedCredentialCount == 1 {
                    lastErrorMessage = L10n.string(
                        .keychainApprovalRequiredSingular,
                        language: resolvedLanguage
                    )
                } else {
                    lastErrorMessage = L10n.string(
                        .keychainApprovalRequired,
                        language: resolvedLanguage,
                        lockedCredentialCount
                    )
                }
            } else {
                switch result.outcome {
                case .fresh:
                    lastErrorMessage = nil
                case .partial:
                    lastErrorMessage = L10n.string(
                        .someAccountsRefreshFailed,
                        language: resolvedLanguage
                    )
                case .allFailed:
                    lastErrorMessage = L10n.string(
                        .allAccountsRefreshFailed,
                        language: resolvedLanguage
                    )
                }
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
        validated.lowBalanceThreshold = ProviderCatalog
            .descriptor(for: validated.provider)
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
            await refresh(credentialAccessMode: .nonInteractive)
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
        let previousPreferences = preferences
        let updatedPreferences = NCWidgetDefaultAccountPolicy.clearingDefaultIfNeeded(
            preferences: preferences,
            deletedAccountID: id
        )
        let didClearNCWidgetDefault = updatedPreferences != previousPreferences
        preferences = updatedPreferences
        do {
            try persist()
            if didClearNCWidgetDefault {
                try mirrorNCWidgetPreferences()
            }
            await refreshCoordinator.removeSnapshot(for: id)
            publishCachedState()
            await refresh(credentialAccessMode: .nonInteractive)
        } catch {
            preferences = previousPreferences
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
            await refresh(credentialAccessMode: .nonInteractive)
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

    func setNotificationCenterDefaultAccountID(_ accountID: UUID?) {
        preferences.notificationCenterDefaultAccountID = accountID
        do {
            try persist()
            try mirrorNCWidgetPreferences()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            lastErrorMessage = message(for: error)
        }
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

    func setPreferredLanguage(_ preference: AppLanguagePreference) {
        preferences.preferredLanguage = preference
        do {
            try persist()
            try mirrorNCWidgetPreferences()
            ApplicationMenuInstaller.installMainMenuIfNeeded(
                language: resolvedLanguage,
                force: true
            )
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            lastErrorMessage = message(for: error)
        }
    }

    func setPreferredTheme(_ preference: AppThemePreference) {
        preferences.preferredTheme = preference
        persistReportingErrors()
    }

    @discardableResult
    func selectDashboard(_ selection: DashboardSelection) -> DashboardSelection {
        let resolved: DashboardSelection
        switch selection {
        case .allAccounts:
            resolved = .allAccounts
        case let .account(accountID):
            resolved = accounts.contains { $0.id == accountID }
                ? selection
                : .allAccounts
        }
        switch resolved {
        case .allAccounts:
            selectedAccountID = nil
        case let .account(accountID):
            selectedAccountID = accountID
        }
        return resolved
    }

    @discardableResult
    func handle(url: URL) -> DashboardSelection? {
        let destination = DeepLinkRouter.destination(
            for: url,
            knownAccountIDs: Set(accounts.map(\.id))
        )
        guard let destination else { return nil }
        let selection: DashboardSelection
        switch destination {
        case .allAccounts:
            selection = .allAccounts
        case let .account(accountID):
            selection = .account(accountID)
        }
        let resolved = selectDashboard(selection)
        NSApp.activate(ignoringOtherApps: true)
        return resolved
    }

    func message(for error: any Error) -> String {
        ErrorPresenter.message(for: error, language: resolvedLanguage)
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

    func mirrorNCWidgetPreferences() throws {
        guard let store = QuotaGlanceShared.ncWidgetPreferencesStore() else { return }
        try store.write(
            NCWidgetPreferences(
                schemaVersion: NCWidgetPreferences.currentSchemaVersion,
                defaultAccountID: preferences.notificationCenterDefaultAccountID,
                preferredLanguage: preferences.preferredLanguage
            )
        )
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
                await self.refresh(credentialAccessMode: .nonInteractive)
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
                    remaining: notification.remaining,
                    language: resolvedLanguage
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
