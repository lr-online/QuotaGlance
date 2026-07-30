import Foundation
import Intents
import QuotaGlanceCore
import WidgetKit

struct NCWidgetEntry: TimelineEntry {
    let date: Date
    let presentation: WidgetPresentation
}

struct NCWidgetTimelineProvider: IntentTimelineProvider {
    typealias Intent = NCWidgetAccountIntent
    typealias Entry = NCWidgetEntry

    func placeholder(in context: Context) -> Entry {
        makeEntry(envelope: nil, choice: .allAccounts)
    }

    func getSnapshot(
        for intent: Intent,
        in context: Context,
        completion: @escaping (Entry) -> Void
    ) {
        completion(makeEntry(for: intent))
    }

    func getTimeline(
        for intent: Intent,
        in context: Context,
        completion: @escaping (Timeline<Entry>) -> Void
    ) {
        let entry = makeEntry(for: intent)
        completion(
            Timeline(
                entries: [entry],
                policy: .after(entry.date.addingTimeInterval(1_800))
            )
        )
    }

    private func makeEntry(for intent: Intent) -> Entry {
        let defaultAccountID = try? QuotaGlanceShared.ncWidgetPreferencesStore()?.read()
            .defaultAccountID
        let selection = NCWidgetSelectionResolver.selection(
            choice: ncWidgetAccountChoice(from: intent),
            defaultAccountID: defaultAccountID
        )
        return makeEntry(selection: selection)
    }

    private func makeEntry(
        envelope: WidgetSnapshotEnvelope? = QuotaGlanceShared.snapshotStore()
            .flatMap { try? $0.read() },
        choice: NCWidgetAccountChoice
    ) -> Entry {
        let defaultAccountID = try? QuotaGlanceShared.ncWidgetPreferencesStore()?.read()
            .defaultAccountID
        let selection = NCWidgetSelectionResolver.selection(
            choice: choice,
            defaultAccountID: defaultAccountID
        )
        return makeEntry(envelope: envelope, selection: selection)
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
        NCWidgetEntry(
            date: .now,
            presentation: WidgetPresenter.make(selection: selection, envelope: envelope)
        )
    }
}

func ncWidgetAccountChoice(from intent: NCWidgetAccountIntent) -> NCWidgetAccountChoice {
    switch intent.accountChoice {
    case nil, NCWidgetAccountIntentChoice.useAppDefault:
        return .useAppDefault
    case NCWidgetAccountIntentChoice.allAccounts:
        return .allAccounts
    case let value?:
        if value.hasPrefix("account:"),
           let id = UUID(uuidString: String(value.dropFirst("account:".count))) {
            return .account(id)
        }
        return .useAppDefault
    }
}
