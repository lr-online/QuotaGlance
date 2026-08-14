import AppKit
import QuotaGlanceCore
import SwiftUI

@main
struct QuotaGlanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(model: appDelegate.model)
        }
        .commands {
            PasteboardCommands()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    private lazy var windowCoordinator = AppWindowCoordinator(model: model)
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ApplicationMenuInstaller.installMainMenuIfNeeded()
        statusBarController = StatusBarController(
            model: model,
            openDashboard: { [weak self] in
                guard let self else { return }
                self.windowCoordinator.showDashboard(
                    selection: self.model.selectedAccountID.map(
                        DashboardSelection.account
                    ) ?? .allAccounts
                )
            },
            openSettings: { [weak self] in
                guard let self else { return }
                self.windowCoordinator.showSettings()
            }
        )

        Task {
            await model.start()
            ApplicationMenuInstaller.installMainMenuIfNeeded(
                language: model.resolvedLanguage,
                force: true
            )
            if model.accounts.isEmpty {
                windowCoordinator.showSettings()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let selection = model.handle(url: url) else { continue }
            windowCoordinator.showDashboard(selection: selection)
        }
    }
}
