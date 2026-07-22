import QuotaGlanceCore
import SwiftUI

@main
struct QuotaGlanceApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        Task { @MainActor in
            await model.start()
        }
    }

    var body: some Scene {
        MenuBarExtra(
            "QuotaGlance",
            systemImage: "gauge.with.dots.needle.50percent"
        ) {
            MenuBarDashboardView(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
