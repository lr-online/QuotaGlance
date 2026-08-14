import SwiftUI
import WidgetKit

@main
struct QuotaGlanceWidgetBundle: WidgetBundle {
    var body: some Widget {
#if QUOTAGLANCE_CERTIFICATE_FREE_STORAGE
        LegacyQuotaGlanceWidget()
#endif
        QuotaGlanceWidget()
    }
}
