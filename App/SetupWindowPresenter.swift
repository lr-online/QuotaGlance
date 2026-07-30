import AppKit
import SwiftUI

@MainActor
final class SetupWindowPresenter {
    private var windowController: NSWindowController?

    func show(model: AppModel, title: String = "QuotaGlance Setup") {
        ApplicationMenuInstaller.installMainMenuIfNeeded()

        if let windowController {
            windowController.window?.title = title
            windowController.showWindow(nil)
            windowController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(
            rootView: SettingsView(model: model)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 600, height: 520))
        window.center()
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
