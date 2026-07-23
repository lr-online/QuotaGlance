import QuotaGlanceCore
import SwiftUI
import WidgetKit

#if !QUOTAGLANCE_CERTIFICATE_FREE
import AppIntents
#endif

struct QuotaGlanceWidgetEntry: TimelineEntry {
    let date: Date
    let presentation: WidgetPresentation
}

#if QUOTAGLANCE_CERTIFICATE_FREE
struct QuotaGlanceTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaGlanceWidgetEntry {
        makeWidgetEntry(envelope: nil, selection: .allAccounts)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (QuotaGlanceWidgetEntry) -> Void
    ) {
        completion(makeWidgetEntry(selection: .allAccounts))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<QuotaGlanceWidgetEntry>) -> Void
    ) {
        let entry = makeWidgetEntry(selection: .allAccounts)
        completion(
            Timeline(
                entries: [entry],
                policy: .after(nextCheck(for: entry))
            )
        )
    }
}
#else
struct QuotaGlanceTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuotaGlanceWidgetEntry {
        makeWidgetEntry(envelope: nil, selection: .allAccounts)
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
        return Timeline(entries: [entry], policy: .after(nextCheck(for: entry)))
    }

    private func makeEntry(
        configuration: QuotaGlanceWidgetConfigurationIntent
    ) -> QuotaGlanceWidgetEntry {
        let selection = configuration.account.map {
            WidgetSelection.account($0.id)
        } ?? .allAccounts
        return makeWidgetEntry(selection: selection)
    }
}
#endif

private func makeWidgetEntry(
    envelope: WidgetSnapshotEnvelope? = QuotaGlanceShared.snapshotStore()
        .flatMap { try? $0.read() },
    selection: WidgetSelection
) -> QuotaGlanceWidgetEntry {
    QuotaGlanceWidgetEntry(
        date: .now,
        presentation: WidgetPresenter.make(
            selection: selection,
            envelope: envelope
        )
    )
}

private func nextCheck(for entry: QuotaGlanceWidgetEntry) -> Date {
    Calendar.current.date(
        byAdding: .minute,
        value: 30,
        to: entry.date
    ) ?? entry.date.addingTimeInterval(1_800)
}

struct QuotaGlanceWidget: Widget {
    static let kind = "QuotaGlanceWidget"

    var body: some WidgetConfiguration {
#if QUOTAGLANCE_CERTIFICATE_FREE
        StaticConfiguration(
            kind: Self.kind,
            provider: QuotaGlanceTimelineProvider()
        ) { entry in
            QuotaGlanceWidgetView(entry: entry)
        }
        .configurationDisplayName("QuotaGlance")
        .description("API Info balance and usage at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
#else
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
#endif
    }
}
