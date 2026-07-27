import AppIntents
import QuotaGlanceCore
import SwiftUI
import WidgetKit

struct QuotaGlanceWidgetEntry: TimelineEntry {
    let date: Date
    let presentation: WidgetPresentation
}

#if QUOTAGLANCE_CERTIFICATE_FREE_STORAGE
struct LegacyQuotaGlanceTimelineProvider: TimelineProvider {
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
#endif

struct QuotaGlanceTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuotaGlanceWidgetEntry {
        makeWidgetEntry(envelope: nil, selection: .allAccounts)
    }

    func snapshot(
        for configuration: QuotaGlanceWidgetConfigurationIntent,
        in context: Context
    ) async -> QuotaGlanceWidgetEntry {
        makeEntry(configuration: configuration)
    }

    func timeline(
        for configuration: QuotaGlanceWidgetConfigurationIntent,
        in context: Context
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
#if QUOTAGLANCE_CERTIFICATE_FREE_STORAGE
    static let kind = "QuotaGlanceConfigurableWidget"
#else
    static let kind = "QuotaGlanceWidget"
#endif

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: QuotaGlanceWidgetConfigurationIntent.self,
            provider: QuotaGlanceTimelineProvider()
        ) { entry in
            QuotaGlanceWidgetView(entry: entry)
        }
        .configurationDisplayName("QuotaGlance")
        .description("Choose an account or show all accounts.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .containerBackgroundRemovable(false)
    }
}

#if QUOTAGLANCE_CERTIFICATE_FREE_STORAGE
struct LegacyQuotaGlanceWidget: Widget {
    static let kind = "QuotaGlanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: Self.kind,
            provider: LegacyQuotaGlanceTimelineProvider()
        ) { entry in
            QuotaGlanceWidgetView(entry: entry)
        }
        .configurationDisplayName("All Accounts")
        .description("Combined provider balances and usage.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .containerBackgroundRemovable(false)
    }
}
#endif
