import Intents

/// Hand-written stand-in for Xcode's SiriKit intent codegen.
///
/// `NCWidgetAccountIntent.intentdefinition` documents this intent for Xcode's
/// Intent editor, but it is included in both extension targets with
/// `buildPhase: resources` (see `project.yml`) so Xcode never runs codegen
/// against it. That keeps this hand-written class as the single source of
/// truth for the intent's shape and avoids duplicate-symbol conflicts if the
/// project is ever opened and built through Xcode's own codegen pipeline.
///
/// Compiled into both `QuotaGlanceNCWidget` (which reads `accountChoice` to
/// render a timeline) and `QuotaGlanceNCIntents` (which resolves the dynamic
/// `accountChoice` options offered in the widget's configuration UI).
@objc(NCWidgetAccountIntent)
final class NCWidgetAccountIntent: INIntent {
    @objc dynamic var accountChoice: String?
}

/// Minimal hand-written substitute for the `NCWidgetAccountIntentHandling`
/// protocol Xcode would otherwise generate from the intent definition.
@objc(NCWidgetAccountIntentHandling)
protocol NCWidgetAccountIntentHandling: NSObjectProtocol {
    @objc optional func provideAccountChoiceOptionsCollection(
        for intent: NCWidgetAccountIntent,
        with completion: @escaping (INObjectCollection<NSString>?, Error?) -> Void
    )
}
