import AppKit
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

    private let settingsWindowPresenter = SetupWindowPresenter()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ApplicationMenuInstaller.installMainMenuIfNeeded()
        statusBarController = StatusBarController(
            model: model,
            openSettings: { [weak self] in
                guard let self else { return }
                self.settingsWindowPresenter.show(
                    model: self.model,
                    title: "QuotaGlance Settings"
                )
            }
        )

        Task {
            await model.start()
            if model.accounts.isEmpty {
                settingsWindowPresenter.show(model: model)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            model.handle(url: url)
        }
    }
}
