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
    private let provider: any UsageProvider
    private let refreshCoordinator: RefreshCoordinator
    private let sharedSnapshotStore: SharedSnapshotStore?
    private let notificationService: NotificationService
    private let launchAtLoginService: LaunchAtLoginService
    private var scheduleTask: Task<Void, Never>?
    private var hasStarted = false

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
        let provider = APIInfoProvider()
        let sharedStore = QuotaGlanceShared.snapshotStore()
        let notificationService = NotificationService()
        let launchAtLoginService = LaunchAtLoginService()
        let cachedEnvelope = sharedStore.flatMap { try? $0.read() }
        let snapshotWriter: (@Sendable (WidgetSnapshotEnvelope) async throws -> Void)?
        if let sharedStore {
            snapshotWriter = { snapshot in
                try sharedStore.write(snapshot)
                WidgetCenter.shared.reloadAllTimelines()
            }
        } else {
            snapshotWriter = nil
        }

        self.accounts = stored.accounts.sorted { $0.sortOrder < $1.sortOrder }
        self.preferences = stored.preferences
        self.latestEnvelope = cachedEnvelope
        self.lastErrorMessage = loadError
        self.preferencesStore = preferencesStore
        self.credentialStore = credentialStore
        self.provider = provider
        self.sharedSnapshotStore = sharedStore
        self.notificationService = notificationService
        self.launchAtLoginService = launchAtLoginService
        self.refreshCoordinator = RefreshCoordinator(
            credentialStore: credentialStore,
            provider: provider,
            initialSnapshots: cachedEnvelope?.accounts ?? [],
            snapshotWriter: snapshotWriter
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
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let result = try await refreshCoordinator.refresh(accounts: accounts)
            latestEnvelope = result.envelope
            await evaluateAlerts(result: result)
            switch result.outcome {
            case .fresh:
                lastErrorMessage = nil
            case .partial:
                lastErrorMessage = "Some accounts could not be refreshed."
            case .allFailed:
                lastErrorMessage = "No account could be refreshed."
            }
        } catch {
            lastErrorMessage = message(for: error)
        }
    }

    func saveAccount(draft: AccountDraft, editing accountID: UUID?) async throws {
        let previouslyHadThreshold = accountID.flatMap { id in
            accounts.first(where: { $0.id == id })?.lowBalanceThreshold
        } != nil
        let validated = try AccountValidator.validate(
            draft: draft,
            existingAccounts: accounts,
            editingAccountID: accountID
        )

        if let apiKey = validated.apiKey {
            _ = try await provider.fetch(apiKey: apiKey)
        }

        if let accountID {
            try await updateAccount(
                id: accountID,
                validated: validated
            )
        } else {
            try await addAccount(validated: validated)
        }

        try persist()
        publishCachedState()
        if !previouslyHadThreshold, validated.lowBalanceThreshold != nil {
            notificationPermission = await notificationService.requestAuthorization()
        }
        await refresh()
    }

    func deleteAccount(id: UUID) async {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        let removed = accounts.remove(at: index)
        do {
            try await credentialStore.delete(for: id)
        } catch CredentialStoreError.notFound {
            // The metadata should still be removed when the Keychain item is already gone.
        } catch {
            accounts.insert(removed, at: index)
            lastErrorMessage = message(for: error)
            return
        }

        if selectedAccountID == id {
            selectedAccountID = nil
        }
        normalizeSortOrder()
        do {
            try persist()
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
        persistReportingErrors()
        publishCachedState()
        Task { await refresh() }
    }

    func moveAccount(id: UUID, offset: Int) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard accounts.indices.contains(destination) else { return }
        accounts.swapAt(index, destination)
        normalizeSortOrder()
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
        switch error {
        case AccountValidationError.emptyDisplayName:
            "Enter an account name."
        case AccountValidationError.emptyAPIKey:
            "Enter an API key."
        case AccountValidationError.maximumAccountsReached:
            "QuotaGlance supports up to five accounts."
        case AccountValidationError.duplicateDisplayName:
            "Account names must be unique."
        case AccountValidationError.invalidThreshold:
            "Enter a valid non-negative threshold."
        case ProviderError.invalidCredential, ProviderError.providerInactive:
            "API Info rejected this key."
        case ProviderError.rateLimited:
            "API Info is rate limiting this key. Try again later."
        case CredentialStoreError.notFound:
            "The API key is missing from Keychain."
        default:
            "The operation could not be completed."
        }
    }
}

private extension AppModel {
    func addAccount(validated: ValidatedAccountDraft) async throws {
        guard let apiKey = validated.apiKey else {
            throw AccountValidationError.emptyAPIKey
        }
        let account = Account(
            displayName: validated.displayName,
            isEnabled: validated.isEnabled,
            sortOrder: accounts.count,
            lowBalanceThreshold: validated.lowBalanceThreshold
        )
        try await credentialStore.save(apiKey, for: account.id)
        accounts.append(account)
    }

    func updateAccount(
        id: UUID,
        validated: ValidatedAccountDraft
    ) async throws {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            return
        }
        if let apiKey = validated.apiKey {
            try await credentialStore.save(apiKey, for: id)
        }
        accounts[index].displayName = validated.displayName
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

    func evaluateAlerts(result: RefreshResult) async {
        var changed = false
        for index in accounts.indices {
            guard let snapshot = result.accountSnapshots[accounts[index].id],
                  let remaining = snapshot.remaining
            else {
                continue
            }
            switch snapshot.health {
            case .healthy, .belowThreshold:
                break
            case .stale, .unavailable:
                continue
            }

            let action = AlertEvaluator.evaluate(
                account: &accounts[index],
                freshRemaining: remaining.amount
            )
            guard action != .none else { continue }
            changed = true
            if action == .notify, notificationPermission == .authorized {
                do {
                    try await notificationService.sendLowBalance(
                        account: accounts[index],
                        remaining: remaining
                    )
                } catch {
                    lastErrorMessage = message(for: error)
                }
            }
        }
        if changed {
            persistReportingErrors()
        }
    }

    func publishCachedState() {
        let capturedAt = Date.now
        let aggregate = SnapshotAggregator().aggregate(
            accounts: accounts,
            snapshots: latestEnvelope?.accounts ?? [],
            now: capturedAt
        )
        let envelope = WidgetSnapshotEnvelope(
            capturedAt: capturedAt,
            aggregate: aggregate,
            accounts: aggregate.accounts
        )
        latestEnvelope = envelope
        guard let sharedSnapshotStore else { return }
        do {
            try sharedSnapshotStore.write(envelope)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            lastErrorMessage = message(for: error)
        }
    }
}
