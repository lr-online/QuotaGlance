import QuotaGlanceCore
import SwiftUI

@main
struct QuotaGlanceApp: App {
    @State private var model: AppModel
    private let setupWindowPresenter: SetupWindowPresenter

    init() {
        let model = AppModel()
        let setupWindowPresenter = SetupWindowPresenter()
        _model = State(initialValue: model)
        self.setupWindowPresenter = setupWindowPresenter
        Task { @MainActor in
            await model.start()
            if model.accounts.isEmpty {
                setupWindowPresenter.show(model: model)
            }
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
