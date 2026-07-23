import SwiftUI

extension View {
    @ViewBuilder
    func compatibleGroupedFormStyle() -> some View {
        if #available(macOS 13.0, *) {
            formStyle(.grouped)
        } else {
            self
        }
    }
}
