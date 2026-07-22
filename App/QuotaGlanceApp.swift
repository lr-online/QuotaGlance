import QuotaGlanceCore
import SwiftUI

@main
struct QuotaGlanceApp: App {
    var body: some Scene {
        MenuBarExtra(
            "QuotaGlance",
            systemImage: "gauge.with.dots.needle.50percent"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("QuotaGlance")
                    .font(.headline)
                Text("No accounts configured")
                    .foregroundStyle(.secondary)
                Divider()
                SettingsLink()
            }
            .padding(12)
        }
        .menuBarExtraStyle(.window)

        Settings {
            Text("Settings")
                .padding(24)
        }
    }
}
