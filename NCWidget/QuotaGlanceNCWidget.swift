import SwiftUI
import WidgetKit

struct QuotaGlanceNCWidget: Widget {
    static let kind = "QuotaGlanceNCWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: Self.kind,
            provider: NCWidgetTimelineProvider()
        ) { entry in
            NCWidgetMediumView(entry: entry)
        }
        .configurationDisplayName("QuotaGlance")
        .description("Shows the Notification Center default account from Settings.")
        .supportedFamilies([.systemMedium])
    }
}
