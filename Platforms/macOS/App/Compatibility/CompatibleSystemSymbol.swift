import AppKit
import QuotaGlanceCore
import SwiftUI

enum CompatibleSystemSymbol {
    static let statusBar = CompatibleSystemSymbolNames.statusBar
    static let emptyState = CompatibleSystemSymbolNames.emptyState

    static func firstAvailable(in names: [String]) -> String {
        for name in names {
            if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
                return name
            }
        }
        return names.last ?? "questionmark.circle"
    }
}

extension NSImage {
    static func compatibleSystemSymbol(
        names: [String],
        accessibilityDescription: String? = nil
    ) -> NSImage? {
        for name in names {
            if let image = NSImage(
                systemSymbolName: name,
                accessibilityDescription: accessibilityDescription
            ) {
                image.isTemplate = true
                return image
            }
        }
        return nil
    }
}

extension Image {
    init(compatibleSystemName names: [String]) {
        self.init(systemName: CompatibleSystemSymbol.firstAvailable(in: names))
    }
}
