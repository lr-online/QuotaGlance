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
            let image = NSImage(
                systemSymbolName: "gauge.with.dots.needle.50percent",
                accessibilityDescription: "QuotaGlance"
            )
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(togglePopover)
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
                    self?.popover.performClose(nil)
                    openSettings()
                }
            )
        )
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
    }
}
