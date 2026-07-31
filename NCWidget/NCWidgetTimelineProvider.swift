import Foundation
import QuotaGlanceCore
import WidgetKit

struct NCWidgetEntry: TimelineEntry {
    let date: Date
    let presentation: WidgetPresentation
    let language: AppLanguage
}

/// Certificate-free / ad-hoc builds cannot reliably drive SiriKit
/// `IntentConfiguration` timelines (same constraint that forced the desktop
/// widget onto `StaticConfiguration`). Account selection comes from the
/// Settings default mirrored in `NCWidgetPreferencesStore`.
struct NCWidgetTimelineProvider: TimelineProvider {
    typealias Entry = NCWidgetEntry

    func placeholder(in context: Context) -> Entry {
        makeEntry(envelope: nil, selection: .allAccounts)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (Entry) -> Void
    ) {
        completion(makeEntry())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<Entry>) -> Void
    ) {
        let entry = makeEntry()
        completion(
            Timeline(
                entries: [entry],
                policy: .after(entry.date.addingTimeInterval(1_800))
            )
        )
    }

    private func makeEntry() -> Entry {
        let defaultAccountID = try? QuotaGlanceShared.ncWidgetPreferencesStore()?.read()
            .defaultAccountID
        let selection = NCWidgetSelectionResolver.selection(
            choice: .useAppDefault,
            defaultAccountID: defaultAccountID
        )
        return makeEntry(selection: selection)
    }

    private func makeEntry(selection: WidgetSelection) -> Entry {
        makeEntry(
            envelope: QuotaGlanceShared.snapshotStore().flatMap { try? $0.read() },
            selection: selection
        )
    }

    private func makeEntry(
        envelope: WidgetSnapshotEnvelope?,
        selection: WidgetSelection
    ) -> Entry {
        let language = AppLanguage.resolve(
            preference: (try? QuotaGlanceShared.ncWidgetPreferencesStore()?.read())?
                .preferredLanguage ?? .system
        )
        return NCWidgetEntry(
            date: .now,
            presentation: WidgetPresenter.make(
                selection: selection,
                envelope: envelope,
                language: language
            ),
            language: language
        )
    }
}
