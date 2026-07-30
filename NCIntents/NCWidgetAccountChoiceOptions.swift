import Foundation
import QuotaGlanceCore

/// Builds the list of account choices offered when a user configures the
/// QuotaGlance Notification Center widget. Moved here (from a dead handler
/// that used to live in the `QuotaGlanceNCWidget` appex) because this Intents
/// extension is the process the system actually invokes for dynamic intent
/// parameter options.
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
