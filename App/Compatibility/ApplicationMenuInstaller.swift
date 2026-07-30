import AppKit

@MainActor
enum ApplicationMenuInstaller {
    /// Accessory apps still need an Edit menu so key equivalents and SwiftUI
    /// pasteboard commands resolve through the responder chain.
    static func installMainMenuIfNeeded() {
        if hasPasteboardEditMenu(NSApp.mainMenu) {
            return
        }

        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "Quit QuotaGlance",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(
            withTitle: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        NSApp.mainMenu = mainMenu
    }

    private static func hasPasteboardEditMenu(_ menu: NSMenu?) -> Bool {
        guard let menu else { return false }
        return menu.items.contains { item in
            guard let submenu = item.submenu else { return false }
            let actions = Set(
                submenu.items.compactMap { $0.action?.description }
            )
            return actions.contains("paste:")
                && actions.contains("copy:")
                && actions.contains("cut:")
        }
    }
}
