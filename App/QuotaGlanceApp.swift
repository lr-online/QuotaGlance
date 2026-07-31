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
                    title: L10n.string(
                        .settingsWindowTitle,
                        language: self.model.resolvedLanguage
                    )
                )
            }
        )

        Task {
            await model.start()
            ApplicationMenuInstaller.installMainMenuIfNeeded(
                language: model.resolvedLanguage,
                force: true
            )
            if model.accounts.isEmpty {
                settingsWindowPresenter.show(
                    model: model,
                    title: L10n.string(
                        .setupWindowTitle,
                        language: model.resolvedLanguage
                    )
                )
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            model.handle(url: url)
        }
    }
}
