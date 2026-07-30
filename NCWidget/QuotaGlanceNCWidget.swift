import SwiftUI
import WidgetKit

struct NCWidgetEntry: TimelineEntry {
    let date: Date
}

struct NCWidgetPlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> NCWidgetEntry {
        NCWidgetEntry(date: .now)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (NCWidgetEntry) -> Void
    ) {
        completion(NCWidgetEntry(date: .now))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<NCWidgetEntry>) -> Void
    ) {
        let entry = NCWidgetEntry(date: .now)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct QuotaGlanceNCWidget: Widget {
    static let kind = "QuotaGlanceNCWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: Self.kind,
            provider: NCWidgetPlaceholderProvider()
        ) { entry in
            Text(entry.date, style: .time)
        }
        .configurationDisplayName("QuotaGlance")
        .description("Notification Center balance overview.")
        .supportedFamilies([.systemMedium])
    }
}
