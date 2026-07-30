import AppKit
import QuotaGlanceCore
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    init(model: AppModel, openSettings: @escaping () -> Void) {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        popover = NSPopover()
        super.init()

        if let button = statusItem.button {
            button.image = NSImage.compatibleSystemSymbol(
                names: CompatibleSystemSymbol.statusBar,
                accessibilityDescription: "QuotaGlance"
            )
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "QuotaGlance"
        }

        let panelSize = MenuBarPanelLayout.fixedContentSize
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(
            width: panelSize.width,
            height: panelSize.height
        )
        popover.contentViewController = NSHostingController(
            rootView: MenuBarDashboardView(
                model: model,
                openSettings: { [weak self] in
                    self?.closePopover()
                    openSettings()
                }
            )
        )
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover()
            return
        }
        guard let button = statusItem.button else { return }
        // Accessory apps must activate before a transient popover can dismiss
        // on outside clicks.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        popover.performClose(nil)
    }
}
