import Foundation
import Intents
import QuotaGlanceCore

final class NCWidgetAccountIntentHandler: NSObject, NCWidgetAccountIntentHandling {
    func provideAccountChoiceOptionsCollection(
        for intent: NCWidgetAccountIntent,
        with completion: @escaping (INObjectCollection<NSString>?, Error?) -> Void
    ) {
        completion(
            INObjectCollection(items: ncWidgetAccountChoiceOptions() as [NSString]),
            nil
        )
    }
}

func ncWidgetAccountChoiceOptions(
    envelope: WidgetSnapshotEnvelope? = QuotaGlanceShared.snapshotStore()
        .flatMap { try? $0.read() }
) -> [String] {
    var options = [
        NCWidgetAccountIntentChoice.useAppDefault,
        NCWidgetAccountIntentChoice.allAccounts
    ]

    options.append(
        contentsOf: (envelope?.accounts ?? []).map {
            "account:\($0.accountID.uuidString)"
        }
    )
    return options
}
