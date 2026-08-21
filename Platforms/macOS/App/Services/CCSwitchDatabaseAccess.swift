import AppKit
import Darwin
import Foundation

enum CCSwitchDatabaseAccessError: LocalizedError {
    case bookmarkCreationFailed

    var errorDescription: String? {
        switch self {
        case .bookmarkCreationFailed:
            "QuotaGlance could not keep access to the selected cc-switch database."
        }
    }
}

@MainActor
final class CCSwitchDatabaseAccess {
    private let bookmarkKey = "ccSwitchDatabaseBookmark"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// cc-switch's primary macOS location. The sandbox still needs the user to
    /// select this file once before it may be read, so this is used to seed the
    /// native open panel instead of attempting an unauthorized direct read.
    var defaultDatabaseURL: URL {
        loginHomeDirectory
            .appendingPathComponent(".cc-switch", isDirectory: true)
            .appendingPathComponent("cc-switch.db")
    }

    var hasSavedPermission: Bool {
        restoredSecurityScopeURL() != nil
    }

    func restoredURL() -> URL? {
        guard let scopeURL = restoredSecurityScopeURL() else { return nil }
        if scopeURL.hasDirectoryPath {
            return scopeURL.appendingPathComponent("cc-switch.db")
        }
        return scopeURL
    }

    /// The URL represented by the security-scoped bookmark. This may be the
    /// `.cc-switch` directory even though callers read `cc-switch.db` inside it.
    func restoredSecurityScopeURL() -> URL? {
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            defaults.removeObject(forKey: bookmarkKey)
            return nil
        }
        if isStale, let refreshed = try? bookmarkData(for: url) {
            defaults.set(refreshed, forKey: bookmarkKey)
        }
        return url
    }

    func selectDatabase(
        completion: @escaping (Result<URL?, Error>) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = "Allow cc-switch database access"
        panel.message = "Choose the cc-switch folder to grant QuotaGlance read-only access"
        panel.prompt = "Allow Access"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = defaultDatabaseURL.deletingLastPathComponent()

        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else {
                completion(.success(nil))
                return
            }
            let scopeURL = url.hasDirectoryPath ? url : url
            let databaseURL = url.hasDirectoryPath
                ? url.appendingPathComponent("cc-switch.db")
                : url
            do {
                let data = try self.bookmarkData(for: scopeURL)
                self.defaults.set(data, forKey: self.bookmarkKey)
                completion(.success(databaseURL))
            } catch {
                completion(.failure(error))
            }
        }

        // Attaching the picker to the dashboard window avoids a detached panel
        // being hidden behind the menu-bar accessory app.
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    private func bookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private var loginHomeDirectory: URL {
        guard let record = getpwuid(getuid()) else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: String(cString: record.pointee.pw_dir), isDirectory: true)
    }
}
