import AppKit

/// Accessory / LSUIElement apps have no visible app menu, so macOS will not
/// deliver Cmd+X/C/V/A unless the application itself routes those key events
/// into the responder chain.
@objc(QuotaGlanceApplication)
final class QuotaGlanceApplication: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           EditKeyEquivalentRouter.perform(event) {
            return
        }
        super.sendEvent(event)
    }
}

enum EditKeyEquivalentRouter {
    static func perform(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let key = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        switch (flags, key) {
        case (.command, "x"):
            return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
        case (.command, "c"):
            return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
        case (.command, "v"):
            return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        case (.command, "a"):
            return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        case (.command, "z"):
            return NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
        case ([.command, .shift], "z"):
            return NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
        default:
            return false
        }
    }
}
