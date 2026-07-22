import AppIntents
import QuotaGlanceCore
import SwiftUI
import WidgetKit

struct QuotaGlanceWidgetEntry: TimelineEntry {
    let date: Date
    let presentation: WidgetPresentation
}

struct QuotaGlanceTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuotaGlanceWidgetEntry {
        QuotaGlanceWidgetEntry(
            date: .now,
            presentation: WidgetPresenter.make(
                selection: .allAccounts,
                envelope: nil
            )
        )
    }

    func snapshot(
        for configuration: QuotaGlanceWidgetConfigurationIntent,
        in context: Context,
    ) async -> QuotaGlanceWidgetEntry {
        makeEntry(configuration: configuration)
    }

    func timeline(
        for configuration: QuotaGlanceWidgetConfigurationIntent,
        in context: Context,
    ) async -> Timeline<QuotaGlanceWidgetEntry> {
        let entry = makeEntry(configuration: configuration)
        let nextCheck = Calendar.current.date(
            byAdding: .minute,
            value: 30,
            to: entry.date
        ) ?? entry.date.addingTimeInterval(1_800)
        return Timeline(entries: [entry], policy: .after(nextCheck))
    }

    private func makeEntry(
        configuration: QuotaGlanceWidgetConfigurationIntent
    ) -> QuotaGlanceWidgetEntry {
        let envelope = QuotaGlanceShared.snapshotStore().flatMap { try? $0.read() }
        let selection = configuration.account.map {
            WidgetSelection.account($0.id)
        } ?? .allAccounts
        return QuotaGlanceWidgetEntry(
            date: .now,
            presentation: WidgetPresenter.make(
                selection: selection,
                envelope: envelope
            )
        )
    }
}

struct QuotaGlanceWidget: Widget {
    static let kind = "QuotaGlanceWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: QuotaGlanceWidgetConfigurationIntent.self,
            provider: QuotaGlanceTimelineProvider()
        ) { entry in
            QuotaGlanceWidgetView(entry: entry)
        }
        .configurationDisplayName("QuotaGlance")
        .description("API Info balance and usage at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
