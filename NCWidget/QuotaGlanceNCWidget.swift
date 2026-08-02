import Intents
import WidgetKit

struct QuotaGlanceNCWidget: Widget {
    static let kind = "QuotaGlanceNCWidget"

    var body: some WidgetConfiguration {
        IntentConfiguration(
            kind: Self.kind,
            intent: NCWidgetAccountIntent.self,
            provider: NCWidgetTimelineProvider()
        ) { entry in
            NCWidgetMediumView(entry: entry)
        }
        .configurationDisplayName("QuotaGlance")
        .description("Choose an account or show all accounts in Notification Center.")
        .supportedFamilies([.systemMedium])
    }
}
