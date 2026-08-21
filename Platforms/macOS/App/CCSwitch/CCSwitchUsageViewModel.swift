import Foundation
import QuotaGlanceCore

@MainActor
final class CCSwitchUsageViewModel: ObservableObject {
    @Published private(set) var dashboard: CCSwitchUsageDashboard?
    @Published private(set) var databaseURL: URL?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isSelectingDatabase = false
    @Published var range = CCSwitchTimeRange.oneHour
    @Published var selectedApp: String?

    private let databaseAccess: CCSwitchDatabaseAccess

    init(databaseAccess: CCSwitchDatabaseAccess = CCSwitchDatabaseAccess()) {
        self.databaseAccess = databaseAccess
        databaseURL = databaseAccess.restoredURL()
    }

    func start(requestAccess: Bool = true) {
        if databaseURL == nil {
            // The sandbox may hide the file until the user grants a security
            // scope, so keep the conventional path even when fileExists is
            // unavailable to the process.
            databaseURL = CCSwitchDatabaseLocator.firstExistingURL()
                ?? databaseAccess.defaultDatabaseURL
        }
        if requestAccess && !databaseAccess.hasSavedPermission {
            selectDatabase()
            return
        }
        refresh()
    }

    func selectDatabase() {
        guard !isSelectingDatabase else { return }
        isSelectingDatabase = true
        databaseAccess.selectDatabase { [weak self] result in
            guard let self else { return }
            self.isSelectingDatabase = false
            switch result {
            case let .success(url):
                guard let url else { return }
                self.databaseURL = url
                self.selectedApp = nil
                self.dashboard = nil
                self.refresh()
            case let .failure(error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func refresh() {
        guard let databaseURL else { return }
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        let range = range
        let selectedApp = selectedApp
        let securityScopeURL = databaseAccess.restoredSecurityScopeURL() ?? databaseURL

        Task.detached(priority: .userInitiated) { [weak self] in
            let didAccess = securityScopeURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess { securityScopeURL.stopAccessingSecurityScopedResource() }
            }
            let result = Result {
                try CCSwitchUsageReader(databaseURL: databaseURL).load(
                    range: range,
                    app: selectedApp
                )
            }
            await MainActor.run {
                guard let self else { return }
                self.isLoading = false
                switch result {
                case let .success(dashboard):
                    self.dashboard = dashboard
                    if let selectedApp, !dashboard.knownApps.contains(selectedApp) {
                        self.selectedApp = nil
                    }
                case let .failure(error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
