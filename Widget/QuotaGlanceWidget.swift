import SwiftUI
import WidgetKit

struct QuotaGlanceEntry: TimelineEntry {
    let date: Date
}

struct QuotaGlanceTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaGlanceEntry {
        QuotaGlanceEntry(date: .now)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (QuotaGlanceEntry) -> Void
    ) {
        completion(QuotaGlanceEntry(date: .now))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<QuotaGlanceEntry>) -> Void
    ) {
        let entry = QuotaGlanceEntry(date: .now)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct QuotaGlanceWidget: Widget {
    static let kind = "QuotaGlanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: Self.kind,
            provider: QuotaGlanceTimelineProvider()
        ) { _ in
            VStack(alignment: .leading, spacing: 6) {
                Text("QuotaGlance")
                    .font(.headline)
                Text("Open the app to add an account")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) {
                Color.clear
            }
        }
        .configurationDisplayName("QuotaGlance")
        .description("API Info balance and usage at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
