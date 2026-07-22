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
            QuotaGlanceMenuContent(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}

private struct QuotaGlanceMenuContent: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("QuotaGlance")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.isRefreshing || model.accounts.isEmpty)
                .help("Refresh")
            }

            if let remaining = model.aggregate?.remaining {
                Text(NSDecimalNumber(decimal: remaining.amount).stringValue)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(remaining.currency)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No balance")
                    .foregroundStyle(.secondary)
            }

            if let error = model.lastErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
            SettingsLink()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
