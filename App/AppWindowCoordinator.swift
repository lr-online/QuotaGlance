import AppKit
import QuotaGlanceCore
import SwiftUI

@MainActor
final class AppWindowCoordinator {
    private let model: AppModel
    private var dashboardWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?

    init(model: AppModel) {
        self.model = model
    }

    func showDashboard(selection: DashboardSelection) {
        model.selectDashboard(selection)
        ApplicationMenuInstaller.installMainMenuIfNeeded()

        if let dashboardWindowController = dashboardWindowController {
            dashboardWindowController.window?.title = dashboardTitle
            present(dashboardWindowController)
            return
        }

        let hostingController = NSHostingController(
            rootView: DashboardView(
                model: model,
                openSettings: { [weak self] in
                    self?.showSettings()
                }
            )
        )
        let window = makeWindow(
            contentViewController: hostingController,
            title: dashboardTitle,
            size: NSSize(width: 1_040, height: 700),
            minimumSize: NSSize(width: 900, height: 580)
        )
        let controller = NSWindowController(window: window)
        dashboardWindowController = controller
        present(controller)
    }

    func showSettings() {
        ApplicationMenuInstaller.installMainMenuIfNeeded()

        if let settingsWindowController = settingsWindowController {
            settingsWindowController.window?.title = settingsTitle
            present(settingsWindowController)
            return
        }

        let hostingController = NSHostingController(
            rootView: SettingsView(model: model)
        )
        let window = makeWindow(
            contentViewController: hostingController,
            title: settingsTitle,
            size: NSSize(width: 620, height: 600),
            minimumSize: NSSize(width: 560, height: 460)
        )
        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        present(controller)
    }

    private var dashboardTitle: String {
        L10n.string(.dashboardWindowTitle, language: model.resolvedLanguage)
    }

    private var settingsTitle: String {
        L10n.string(
            model.accounts.isEmpty ? .setupWindowTitle : .settingsWindowTitle,
            language: model.resolvedLanguage
        )
    }

    private func makeWindow(
        contentViewController: NSViewController,
        title: String,
        size: NSSize,
        minimumSize: NSSize
    ) -> NSWindow {
        let window = NSWindow(contentViewController: contentViewController)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(size)
        window.minSize = minimumSize
        window.center()
        window.isReleasedWhenClosed = false
        return window
    }

    private func present(_ controller: NSWindowController) {
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
