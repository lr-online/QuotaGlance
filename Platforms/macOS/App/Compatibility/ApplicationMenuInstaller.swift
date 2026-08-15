import AppKit
import QuotaGlanceCore

@MainActor
enum ApplicationMenuInstaller {
    /// Accessory apps still need an Edit menu so key equivalents and SwiftUI
    /// pasteboard commands resolve through the responder chain.
    static func installMainMenuIfNeeded(
        language: AppLanguage = .english,
        force: Bool = false
    ) {
        if !force, hasPasteboardEditMenu(NSApp.mainMenu) {
            return
        }

        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(
            withTitle: L10n.string(.quitQuotaGlance, language: language),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: L10n.string(.edit, language: language))
        editMenuItem.submenu = editMenu

        editMenu.addItem(
            withTitle: L10n.string(.cut, language: language),
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: L10n.string(.copy, language: language),
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: L10n.string(.paste, language: language),
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: L10n.string(.selectAll, language: language),
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
