import Intents

/// Real SiriKit Intents extension (`com.apple.intents-service`) that resolves
/// the dynamic `accountChoice` options offered when a user configures the
/// QuotaGlance Notification Center widget (long-press → Edit Widget).
///
/// The widget's own WidgetKit appex is never invoked by the system to provide
/// these options — that call is routed to a dedicated Intents extension,
/// which is why this target exists separately from `QuotaGlanceNCWidget`.
final class IntentHandler: INExtension, NCWidgetAccountIntentHandling {
    override func handler(for intent: INIntent) -> Any {
        self
    }

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
