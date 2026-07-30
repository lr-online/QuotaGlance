# macOS 12 Notification Center Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a configurable medium Notification Center widget on macOS 12 and macOS 14 via a separate IntentConfiguration appex, with a Settings default account, without changing the shared menu bar popover or the existing macOS 14 desktop AppIntent widgets.

**Architecture:** Add `QuotaGlanceNCWidget` (min macOS 12) using SiriKit `IntentConfiguration`. Persist `notificationCenterDefaultAccountID` in host `AppPreferences`, mirror it to a shared sidecar next to the snapshot, and resolve Intent "Use App Default" through a Core helper. Embed the NC appex in both `QuotaGlance` and `QuotaGlanceLegacy`; leave `QuotaGlanceWidget` macOS 14-only.

**Tech Stack:** Swift 6, SwiftUI, WidgetKit, SiriKit Intents, AppKit, Swift Testing, XcodeGen, Bash packaging scripts.

## Global Constraints

- Menu bar popover (`MenuBarDashboardView` / `StatusBarController`) must not change behavior or layout.
- Existing `QuotaGlanceWidget` AppIntent desktop widgets remain macOS 14-only and must not lose sizes or configuration.
- NC widget supports `.systemMedium` only.
- NC widget has no network and no Keychain access; read-only shared snapshot + sidecar.
- App Group remains `group.com.liangrui.QuotaGlance`.
- Certificate-free builds continue using `/Users/Shared/QuotaGlance` for shared files.
- Both editions keep host bundle id `com.liangrui.QuotaGlance`.
- Spec: `docs/superpowers/specs/2026-07-30-macos12-notification-center-widget-design.md`.

## File Structure

| Path | Responsibility |
|------|----------------|
| `Sources/QuotaGlanceCore/Domain/Account.swift` | `AppPreferences.notificationCenterDefaultAccountID` |
| `Sources/QuotaGlanceCore/Storage/NCWidgetPreferencesStore.swift` | Shared sidecar read/write for NC default account |
| `Sources/QuotaGlanceCore/Presentation/NCWidgetSelectionResolver.swift` | Intent choice + sidecar → `WidgetSelection` |
| `App/AppModel.swift` | Setter, clear-on-delete, mirror sidecar, reload timelines |
| `App/Settings/SettingsView.swift` | Notification Center Widget picker section |
| `NCWidget/` | New IntentConfiguration extension sources |
| `project.yml` | Target + embed wiring |
| `scripts/*` + `Tests/ScriptTests/*` | Build/install/DMG contracts for NC appex |
| `Distribution/README-macOS12.txt`, `README-macOS14.txt`, `README.md` | User-facing edition wording |

---

### Task 1: Add Notification Center Default Preference

**Files:**
- Modify: `Sources/QuotaGlanceCore/Domain/Account.swift`
- Modify: `Tests/QuotaGlanceCoreTests/DomainModelTests.swift`
- Modify: `Tests/QuotaGlanceCoreTests/StorageTests.swift`

**Interfaces:**
- Produces: `AppPreferences.notificationCenterDefaultAccountID: UUID?` (nil = All Accounts)
- Produces: `AppPreferences.init(refreshInterval:launchAtLogin:notificationCenterDefaultAccountID:)` with default `nil`

- [ ] **Step 1: Write the failing preference default test**

In `DomainModelTests.swift`, add:

```swift
@Test("Notification Center widget default account starts unset")
func notificationCenterDefaultAccountStartsUnset() {
    #expect(AppPreferences.default.notificationCenterDefaultAccountID == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter notificationCenterDefaultAccountStartsUnset`
Expected: FAIL because the property does not exist.

- [ ] **Step 3: Extend `AppPreferences`**

Update `Sources/QuotaGlanceCore/Domain/Account.swift`:

```swift
public struct AppPreferences: Codable, Equatable, Sendable {
    public var refreshInterval: RefreshInterval
    public var launchAtLogin: Bool
    public var notificationCenterDefaultAccountID: UUID?

    public init(
        refreshInterval: RefreshInterval,
        launchAtLogin: Bool,
        notificationCenterDefaultAccountID: UUID? = nil
    ) {
        self.refreshInterval = refreshInterval
        self.launchAtLogin = launchAtLogin
        self.notificationCenterDefaultAccountID = notificationCenterDefaultAccountID
    }

    public static let `default` = AppPreferences(
        refreshInterval: .fiveMinutes,
        launchAtLogin: false,
        notificationCenterDefaultAccountID: nil
    )
}
```

- [ ] **Step 4: Add a storage round-trip test for missing and present keys**

In `StorageTests.swift`, add a test that:

1. Loads a v2 preferences JSON payload **without** `notificationCenterDefaultAccountID` and expects `nil`.
2. Saves preferences with a concrete UUID and reloads that UUID.

Keep the existing sanitized-provider test compiling by passing the new field (or relying on the default parameter) in `AppPreferences(...)` equality checks.

- [ ] **Step 5: Run Core preference tests**

Run: `swift test --filter DomainModelTests`
Run: `swift test --filter StorageTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/QuotaGlanceCore/Domain/Account.swift \
  Tests/QuotaGlanceCoreTests/DomainModelTests.swift \
  Tests/QuotaGlanceCoreTests/StorageTests.swift
git commit -m "$(cat <<'EOF'
Add Notification Center widget default account preference.

Persist an optional account UUID in AppPreferences so Settings can drive
Use App Default resolution for the macOS 12 Notification Center widget.
EOF
)"
```

---

### Task 2: Shared NC Preferences Sidecar

**Files:**
- Create: `Sources/QuotaGlanceCore/Storage/NCWidgetPreferencesStore.swift`
- Modify: `Sources/QuotaGlanceCore/Storage/SharedSnapshotStore.swift` (add shared filename constant helper if needed)
- Create: `Tests/QuotaGlanceCoreTests/NCWidgetPreferencesStoreTests.swift`

**Interfaces:**
- Produces:

```swift
public struct NCWidgetPreferences: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var defaultAccountID: UUID?
}

public struct NCWidgetPreferencesStore: Sendable {
    public static let fileName = "nc-widget-preferences-v1.json"
    public let fileURL: URL
    public init(fileURL: URL)
    public func write(_ preferences: NCWidgetPreferences) throws
    public func read() throws -> NCWidgetPreferences
}

public extension QuotaGlanceShared {
    public static func ncWidgetPreferencesStore() -> NCWidgetPreferencesStore?
}
```

`QuotaGlanceShared.ncWidgetPreferencesStore()` must use the same container policy as `snapshotStore()` (certificate-free directory vs App Group).

- [ ] **Step 1: Write failing sidecar tests**

```swift
import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("NC widget preferences store")
struct NCWidgetPreferencesStoreTests {
    @Test("Sidecar round-trips default account id")
    func sidecarRoundTripsDefaultAccountID() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = NCWidgetPreferencesStore(
            fileURL: directory.appendingPathComponent(NCWidgetPreferencesStore.fileName)
        )
        let accountID = UUID()
        try store.write(
            NCWidgetPreferences(schemaVersion: 1, defaultAccountID: accountID)
        )

        #expect(try store.read().defaultAccountID == accountID)
    }

    @Test("Missing sidecar reads as unset default")
    func missingSidecarReadsAsUnsetDefault() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = NCWidgetPreferencesStore(
            fileURL: directory.appendingPathComponent(NCWidgetPreferencesStore.fileName)
        )
        #expect(try store.read().defaultAccountID == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter NCWidgetPreferencesStoreTests`
Expected: FAIL because types are missing.

- [ ] **Step 3: Implement the store**

Mirror `SharedSnapshotStore` atomic write behavior (temp file + replace/move, mode `0o600`). For missing file, `read()` returns `NCWidgetPreferences(schemaVersion: 1, defaultAccountID: nil)` instead of throwing.

Wire:

```swift
public static func ncWidgetPreferencesStore() -> NCWidgetPreferencesStore? {
#if QUOTAGLANCE_CERTIFICATE_FREE_STORAGE
    return NCWidgetPreferencesStore(
        fileURL: certificateFreeSnapshotDirectory
            .appendingPathComponent(NCWidgetPreferencesStore.fileName)
    )
#else
    guard let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
        return nil
    }
    return NCWidgetPreferencesStore(
        fileURL: containerURL.appendingPathComponent(NCWidgetPreferencesStore.fileName)
    )
#endif
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter NCWidgetPreferencesStoreTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/QuotaGlanceCore/Storage/NCWidgetPreferencesStore.swift \
  Sources/QuotaGlanceCore/Storage/SharedSnapshotStore.swift \
  Tests/QuotaGlanceCoreTests/NCWidgetPreferencesStoreTests.swift
git commit -m "$(cat <<'EOF'
Add shared sidecar store for NC widget defaults.

Mirror the Notification Center default account beside the snapshot so the
extension can resolve Use App Default without host UserDefaults.
EOF
)"
```

---

### Task 3: Resolve Intent Selection To `WidgetSelection`

**Files:**
- Create: `Sources/QuotaGlanceCore/Presentation/NCWidgetSelectionResolver.swift`
- Create: `Tests/QuotaGlanceCoreTests/NCWidgetSelectionResolverTests.swift`

**Interfaces:**
- Produces:

```swift
public enum NCWidgetAccountChoice: Equatable, Sendable {
    case useAppDefault
    case allAccounts
    case account(UUID)
}

public enum NCWidgetSelectionResolver {
    public static func selection(
        choice: NCWidgetAccountChoice,
        defaultAccountID: UUID?
    ) -> WidgetSelection
}
```

Resolution table from the spec:

| Choice | `defaultAccountID` | Result |
|--------|--------------------|--------|
| `.useAppDefault` | `nil` | `.allAccounts` |
| `.useAppDefault` | `uuid` | `.account(uuid)` |
| `.allAccounts` | ignored | `.allAccounts` |
| `.account(uuid)` | ignored | `.account(uuid)` |

- [ ] **Step 1: Write failing resolver tests covering all four rows**

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter NCWidgetSelectionResolverTests`
Expected: FAIL

- [ ] **Step 3: Implement the resolver**

```swift
public enum NCWidgetSelectionResolver {
    public static func selection(
        choice: NCWidgetAccountChoice,
        defaultAccountID: UUID?
    ) -> WidgetSelection {
        switch choice {
        case .useAppDefault:
            if let defaultAccountID {
                return .account(defaultAccountID)
            }
            return .allAccounts
        case .allAccounts:
            return .allAccounts
        case let .account(accountID):
            return .account(accountID)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter NCWidgetSelectionResolverTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/QuotaGlanceCore/Presentation/NCWidgetSelectionResolver.swift \
  Tests/QuotaGlanceCoreTests/NCWidgetSelectionResolverTests.swift
git commit -m "$(cat <<'EOF'
Resolve NC widget Intent choices to WidgetSelection.

Centralize Use App Default, All Accounts, and per-account mapping so the
extension and tests share one selection contract.
EOF
)"
```

---

### Task 4: Host Persistence, Clear-On-Delete, And Settings Setter

**Files:**
- Modify: `App/AppModel.swift`
- Modify: `App/Settings/SettingsView.swift`
- Create: `Tests/QuotaGlanceCoreTests/NCWidgetDefaultAccountPolicyTests.swift` for pure policy helper if extracted; otherwise cover clear-on-delete via a small Core helper used by `AppModel`

**Interfaces:**
- Produces:

```swift
public enum NCWidgetDefaultAccountPolicy {
    public static func clearingDefaultIfNeeded(
        preferences: AppPreferences,
        deletedAccountID: UUID
    ) -> AppPreferences
}

// AppModel
func setNotificationCenterDefaultAccountID(_ accountID: UUID?)
```

`setNotificationCenterDefaultAccountID`:

1. Assign `preferences.notificationCenterDefaultAccountID`
2. `persist()`
3. Mirror sidecar via `QuotaGlanceShared.ncWidgetPreferencesStore()?.write(...)`
4. `WidgetCenter.shared.reloadAllTimelines()`

`deleteAccount(id:)` after successful removal:

1. Apply `NCWidgetDefaultAccountPolicy.clearingDefaultIfNeeded`
2. Persist + mirror sidecar when the default changed
3. Continue existing snapshot/publish/refresh flow

- [ ] **Step 1: Write failing policy test**

```swift
@Test("Deleting the default account clears the NC widget default")
func deletingDefaultAccountClearsNCWidgetDefault() {
    let accountID = UUID()
    let preferences = AppPreferences(
        refreshInterval: .fiveMinutes,
        launchAtLogin: false,
        notificationCenterDefaultAccountID: accountID
    )
    let cleared = NCWidgetDefaultAccountPolicy.clearingDefaultIfNeeded(
        preferences: preferences,
        deletedAccountID: accountID
    )
    #expect(cleared.notificationCenterDefaultAccountID == nil)
}

@Test("Deleting a different account keeps the NC widget default")
func deletingOtherAccountKeepsNCWidgetDefault() {
    let defaultID = UUID()
    let preferences = AppPreferences(
        refreshInterval: .fiveMinutes,
        launchAtLogin: false,
        notificationCenterDefaultAccountID: defaultID
    )
    let kept = NCWidgetDefaultAccountPolicy.clearingDefaultIfNeeded(
        preferences: preferences,
        deletedAccountID: UUID()
    )
    #expect(kept.notificationCenterDefaultAccountID == defaultID)
}
```

- [ ] **Step 2: Implement policy helper and wire `AppModel`**

Place the policy helper under `Sources/QuotaGlanceCore/Presentation/NCWidgetDefaultAccountPolicy.swift` (or next to the resolver). Update `deleteAccount` and add `setNotificationCenterDefaultAccountID`.

Extract a private `mirrorNCWidgetPreferences()` used by both setter and delete:

```swift
func mirrorNCWidgetPreferences() {
    guard let store = QuotaGlanceShared.ncWidgetPreferencesStore() else { return }
    try? store.write(
        NCWidgetPreferences(
            schemaVersion: NCWidgetPreferences.currentSchemaVersion,
            defaultAccountID: preferences.notificationCenterDefaultAccountID
        )
    )
}
```

Call `mirrorNCWidgetPreferences()` from `persist()` success paths that touch this preference, or explicitly after setter/delete. Prefer explicit calls from setter/delete to avoid rewriting the sidecar on every unrelated persist.

- [ ] **Step 3: Add Settings section**

In `SettingsView`, after the Refresh section, add:

```swift
Section("Notification Center Widget") {
    Picker(
        "Default Account",
        selection: Binding(
            get: { model.preferences.notificationCenterDefaultAccountID },
            set: { model.setNotificationCenterDefaultAccountID($0) }
        )
    ) {
        Text("All Accounts").tag(Optional<UUID>.none)
        ForEach(model.accounts) { account in
            Text(account.displayName).tag(Optional(account.id))
        }
    }
    Text("Applies to widgets still set to Use App Default. Widgets edited in Notification Center keep their own account.")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

Ensure `Account` is `Identifiable` (it already uses `id`).

- [ ] **Step 4: Run tests**

Run: `swift test --filter NCWidgetDefaultAccountPolicyTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add App/AppModel.swift App/Settings/SettingsView.swift \
  Sources/QuotaGlanceCore/Presentation/NCWidgetDefaultAccountPolicy.swift \
  Tests/QuotaGlanceCoreTests/NCWidgetDefaultAccountPolicyTests.swift
git commit -m "$(cat <<'EOF'
Wire Settings default account into host persistence.

Clear deleted defaults, mirror the shared sidecar, and reload widget
timelines when the Notification Center default account changes.
EOF
)"
```

---

### Task 5: Scaffold `QuotaGlanceNCWidget` Target

**Files:**
- Create: `NCWidget/Info.plist`
- Create: `NCWidget/QuotaGlanceNCWidget.entitlements`
- Create: `Config/Local/QuotaGlanceNCWidget.entitlements`
- Create: `NCWidget/QuotaGlanceNCWidgetBundle.swift` (stub)
- Create: `NCWidget/QuotaGlanceNCWidget.swift` (stub Widget)
- Create: `NCWidget/NCWidgetAccountIntent.intentdefinition`
- Modify: `project.yml`
- Regenerate: `QuotaGlance.xcodeproj`

**Interfaces:**
- Produces Xcode target `QuotaGlanceNCWidget`
- Bundle id: `com.liangrui.QuotaGlance.NCWidget`
- Min OS: `12.0`
- Embedded by both `QuotaGlance` and `QuotaGlanceLegacy`

- [ ] **Step 1: Add red BuildEdition contract assertions**

In `Tests/ScriptTests/BuildEditionTests.sh`, assert:

```bash
rg -q '^  QuotaGlanceNCWidget:$' "$ROOT_DIR/project.yml" \
  || fail "NC widget target is missing"
[[ "$(build_setting QuotaGlanceNCWidget MACOSX_DEPLOYMENT_TARGET)" == "12.0" ]] \
  || fail "NC widget deployment target is not macOS 12"

# Legacy host must depend on NC widget, must not depend on desktop Widget
# Full host must depend on both
```

Run the script and confirm it fails before `project.yml` changes.

- [ ] **Step 2: Create entitlements and Info.plist**

`NCWidget/Info.plist`: copy `Widget/Info.plist` with display name `QuotaGlance NC Widget` and the same `com.apple.widgetkit-extension` point.

`NCWidget/QuotaGlanceNCWidget.entitlements`: same App Group sandbox as `Widget/QuotaGlanceWidget.entitlements`.

`Config/Local/QuotaGlanceNCWidget.entitlements`: same certificate-free read-only `/Users/Shared/QuotaGlance/` exception as `Config/Local/QuotaGlanceWidget.entitlements`.

- [ ] **Step 3: Create Intent Definition**

Create `NCWidget/NCWidgetAccountIntent.intentdefinition` with:

- Custom Intent name: `NCWidgetAccount`
- Category: configure / widget-eligible (`INIntentCategory` configurable for widgets)
- Parameter: `accountChoice` of type String (or custom enum) with options that will be provided dynamically in code:
  - `useAppDefault`
  - `allAccounts`
  - account UUID strings for live accounts
- Mark the intent as eligible for widgets / IntentConfiguration

If XcodeGen/Xcode generation of Intent classes is awkward in this repo, implement an equivalent hand-written `INIntent` subclass named `NCWidgetAccountIntent` plus `NCWidgetAccountIntentHandling` in Swift under `NCWidget/`, and keep the `.intentdefinition` only if required by WidgetKit metadata. Prefer the approach that builds under the existing certificate-free local signing flow.

Minimum hand-written shape if definition codegen is skipped:

```swift
@objc(NCWidgetAccountIntent)
final class NCWidgetAccountIntent: INIntent {
    @NSManaged var accountChoice: String?
}

enum NCWidgetAccountIntentChoice {
    static let useAppDefault = "useAppDefault"
    static let allAccounts = "allAccounts"
    // account:<uuid>
}
```

- [ ] **Step 4: Update `project.yml`**

```yaml
  QuotaGlance:
    dependencies:
      - package: QuotaGlanceCore
        product: QuotaGlanceCore
      - target: QuotaGlanceWidget
        embed: true
      - target: QuotaGlanceNCWidget
        embed: true

  QuotaGlanceLegacy:
    dependencies:
      - package: QuotaGlanceCore
        product: QuotaGlanceCore
      - target: QuotaGlanceNCWidget
        embed: true

  QuotaGlanceNCWidget:
    type: app-extension
    platform: macOS
    sources:
      - path: NCWidget
        excludes:
          - Info.plist
          - QuotaGlanceNCWidget.entitlements
    dependencies:
      - package: QuotaGlanceCore
        product: QuotaGlanceCore
    settings:
      base:
        MACOSX_DEPLOYMENT_TARGET: "12.0"
        PRODUCT_BUNDLE_IDENTIFIER: com.liangrui.QuotaGlance.NCWidget
        PRODUCT_NAME: QuotaGlanceNCWidget
        INFOPLIST_FILE: NCWidget/Info.plist
        CODE_SIGN_ENTITLEMENTS: NCWidget/QuotaGlanceNCWidget.entitlements
        APPLICATION_EXTENSION_API_ONLY: YES
        SKIP_INSTALL: YES
```

Add scheme entry for `QuotaGlanceNCWidget` if useful for isolated builds.

- [ ] **Step 5: Add stub widget sources that compile**

```swift
import SwiftUI
import WidgetKit

@main
struct QuotaGlanceNCWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuotaGlanceNCWidget()
    }
}

struct QuotaGlanceNCWidget: Widget {
    static let kind = "QuotaGlanceNCWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: Self.kind,
            provider: NCWidgetPlaceholderProvider()
        ) { entry in
            Text(entry.date, style: .time)
        }
        .configurationDisplayName("QuotaGlance")
        .description("Notification Center balance overview.")
        .supportedFamilies([.systemMedium])
    }
}
```

Use a temporary `StaticConfiguration` stub only long enough to get the target compiling; Task 6 replaces it with `IntentConfiguration`.

- [ ] **Step 6: Regenerate and verify**

```bash
xcodegen generate
./Tests/ScriptTests/BuildEditionTests.sh
```

Expected: PASS for the new NC target assertions; legacy depends on NC, not desktop Widget.

- [ ] **Step 7: Commit**

```bash
git add project.yml QuotaGlance.xcodeproj NCWidget Config/Local/QuotaGlanceNCWidget.entitlements \
  Tests/ScriptTests/BuildEditionTests.sh
git commit -m "$(cat <<'EOF'
Scaffold macOS 12 Notification Center widget target.

Add QuotaGlanceNCWidget, embed it in both host editions, and lock the
deployment-target contract before IntentConfiguration work.
EOF
)"
```

---

### Task 6: Implement IntentConfiguration Medium Widget

**Files:**
- Modify: `NCWidget/QuotaGlanceNCWidget.swift`
- Create: `NCWidget/NCWidgetTimelineProvider.swift`
- Create: `NCWidget/NCWidgetViews.swift`
- Create: `NCWidget/NCWidgetAccountIntent+Options.swift` (dynamic options from snapshot)
- Delete or replace Task 5 stub provider

**Interfaces:**
- Consumes: `NCWidgetSelectionResolver`, `WidgetPresenter`, `QuotaGlanceShared.snapshotStore()`, `QuotaGlanceShared.ncWidgetPreferencesStore()`
- Produces: medium-only IntentConfiguration widget kind `QuotaGlanceNCWidget`

Important: do **not** use `.containerBackground(for:)` (macOS 14+). Use a macOS 12-safe background such as:

```swift
.background(Color(nsColor: .windowBackgroundColor))
```

Reuse medium information hierarchy from `Widget/WidgetViews.swift` (title, primary metric, today/requests, freshness), but keep the view in `NCWidget/` so the desktop Widget can keep its macOS 14 container APIs untouched.

- [ ] **Step 1: Map Intent → `NCWidgetAccountChoice`**

```swift
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
```

Dynamic options provider lists Use App Default, All Accounts, then `account:<uuid>` rows from `envelope.accounts`.

- [ ] **Step 2: Implement `IntentTimelineProvider`**

```swift
struct NCWidgetTimelineProvider: IntentTimelineProvider {
    typealias Intent = NCWidgetAccountIntent
    typealias Entry = QuotaGlanceWidgetEntry // or NC-local entry with WidgetPresentation

    func placeholder(in context: Context) -> Entry { ... }
    func getSnapshot(for intent: Intent, in context: Context, completion: @escaping (Entry) -> Void) { ... }
    func getTimeline(for intent: Intent, in context: Context, completion: @escaping (Timeline<Entry>) -> Void) { ... }
}
```

Entry construction:

```swift
let choice = ncWidgetAccountChoice(from: intent)
let defaultID = (try? QuotaGlanceShared.ncWidgetPreferencesStore()?.read())?.defaultAccountID
let selection = NCWidgetSelectionResolver.selection(
    choice: choice,
    defaultAccountID: defaultID
)
let envelope = try? QuotaGlanceShared.snapshotStore()?.read()
let presentation = WidgetPresenter.make(selection: selection, envelope: envelope)
```

Timeline policy: `.after(now + 30 minutes)`, matching the desktop widget.

- [ ] **Step 3: Replace stub configuration**

```swift
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
```

Do not call `.containerBackgroundRemovable`.

- [ ] **Step 4: Deep link**

Keep `.widgetURL(entry.presentation.deepLink)` so taps open the host.

- [ ] **Step 5: Build both editions**

```bash
./scripts/build-local.sh Release full
./scripts/build-local.sh Release legacy
```

Expected: both produce `Contents/PlugIns/QuotaGlanceNCWidget.appex`; only full also produces `QuotaGlanceWidget.appex`.

- [ ] **Step 6: Commit**

```bash
git add NCWidget
git commit -m "$(cat <<'EOF'
Implement IntentConfiguration Notification Center medium widget.

Resolve account choices through the shared sidecar and WidgetPresenter, with
macOS 12-safe SwiftUI chrome separate from the desktop Widget target.
EOF
)"
```

---

### Task 7: Packaging, Install, And Verifiers

**Files:**
- Modify: `scripts/build-local.sh`
- Modify: `scripts/install-local.sh`
- Create: `scripts/verify-nc-widget-bundle.sh`
- Modify: `scripts/package-dmg.sh`
- Modify: `scripts/verify-dmg.sh`
- Modify: `scripts/local-entitlement-validation.sh` if it hard-codes a single widget
- Modify: `Tests/ScriptTests/DMGPackagingTests.sh`
- Modify: `Tests/ScriptTests/BuildEditionTests.sh` (finish any remaining asserts)

**Interfaces:**
- Produces verifier that accepts legacy with **only** NC appex and full with NC + desktop Widget

- [ ] **Step 1: Update `build-local.sh`**

Introduce:

```bash
NC_WIDGET_NAME="QuotaGlanceNCWidget"
NC_WIDGET_BUNDLE_ID="com.liangrui.QuotaGlance.NCWidget"
```

For both editions, require `QuotaGlanceNCWidget.appex` and ad hoc sign it with `Config/Local/QuotaGlanceNCWidget.entitlements`.

Keep desktop Widget checks only for `full`.

- [ ] **Step 2: Create `scripts/verify-nc-widget-bundle.sh`**

Assert:

- bundle id `com.liangrui.QuotaGlance.NCWidget`
- extension point `com.apple.widgetkit-extension`
- executable exists and is arm64 when checked by callers
- strings/symbols indicate IntentConfiguration / `NCWidgetAccountIntent` path
- does **not** require AppIntent metadata
- medium-only kind string `QuotaGlanceNCWidget`

- [ ] **Step 3: Update `package-dmg.sh` / `verify-dmg.sh`**

Replace "legacy must have zero appex" with:

- legacy: exactly the NC appex, min version `12.0`
- full: NC appex min `12.0` + desktop Widget min `14.0`

Call `verify-nc-widget-bundle.sh` for both editions.

- [ ] **Step 4: Update `install-local.sh`**

Register both appexes when present. Accept an optional edition argument or always install full (current default) while still registering NC. For uninstall/replace, remove previous NC and desktop plugins before moving the old app aside.

- [ ] **Step 5: Update DMG packaging tests**

Change the macOS 12 README expectation from only "不包含桌面小组件" to also require wording that Notification Center medium widget is included. Update full README expectations to mention Notification Center as well as desktop widgets.

- [ ] **Step 6: Run script tests**

```bash
./Tests/ScriptTests/BuildEditionTests.sh
./Tests/ScriptTests/DMGPackagingTests.sh
./Tests/ScriptTests/LocalInstallSafetyTests.sh
```

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add scripts Tests/ScriptTests
git commit -m "$(cat <<'EOF'
Verify NC widget packaging for both editions.

Require the Notification Center appex in macOS 12 and macOS 14 builds while
keeping the desktop Widget macOS 14-only.
EOF
)"
```

---

### Task 8: Docs And Compatibility Contract Refresh

**Files:**
- Modify: `README.md`
- Modify: `Distribution/README-macOS12.txt`
- Modify: `Distribution/README-macOS14.txt`
- Modify: `docs/superpowers/specs/2026-07-23-macos-12-compatibility-design.md`

- [ ] **Step 1: Update macOS 12 distribution README**

Replace the "不包含桌面小组件" bullet set with:

- 不包含桌面小组件，也不提供开机启动选项
- 包含可在通知中心添加的中号小组件，可选择全部账户或指定账户
- Settings 可设置通知中心小组件的默认账户

Add a short "添加通知中心小组件" section with Notification Center steps for macOS 12.

- [ ] **Step 2: Update macOS 14 distribution README**

Keep desktop widget instructions. Add that the same Notification Center medium widget is also available, and Settings default account applies to Use App Default instances.

- [ ] **Step 3: Update root `README.md`**

Align edition feature bullets with the new contract.

- [ ] **Step 4: Patch the macOS 12 compatibility design contract**

Change "intentionally does not provide desktop Widgets" wording to note Notification Center medium widget inclusion, without rewriting the whole historical doc. Add a short pointer to `2026-07-30-macos12-notification-center-widget-design.md`.

- [ ] **Step 5: Commit**

```bash
git add README.md Distribution/README-macOS12.txt Distribution/README-macOS14.txt \
  docs/superpowers/specs/2026-07-23-macos-12-compatibility-design.md
git commit -m "$(cat <<'EOF'
Document Notification Center widget support by edition.

Update README and compatibility contract so macOS 12 advertises NC widgets
and macOS 14 keeps desktop widgets plus the shared NC widget.
EOF
)"
```

---

### Task 9: End-To-End Verification Gate

**Files:**
- No new production files required

- [ ] **Step 1: Run full Core tests**

```bash
swift test
```

Expected: PASS

- [ ] **Step 2: Build both editions locally**

```bash
./scripts/build-local.sh Release full
./scripts/build-local.sh Release legacy
```

Confirm PlugIns contents match the edition matrix.

- [ ] **Step 3: Manual checklist**

On an available Mac:

1. Install full or legacy build.
2. Add accounts and refresh once so the snapshot exists.
3. Set Settings → Notification Center Widget default account.
4. Add QuotaGlance medium widget in Notification Center.
5. Confirm Use App Default follows Settings.
6. Edit the widget to a specific account; change Settings; confirm the edited widget does not flip.
7. Delete the selected account; confirm Account Unavailable or All Accounts fallback per spec.
8. On macOS 14 full build only: confirm desktop AppIntent widgets still configure and render.

- [ ] **Step 4: Final commit only if verification found fixes**

If fixes were needed, commit them with a focused message. Otherwise stop after verification notes in the PR/summary.

---

## Self-Review Against Spec

| Spec requirement | Task |
|------------------|------|
| Separate NC appex min 12 | Task 5 |
| IntentConfiguration + configurable account | Task 6 |
| Medium only | Tasks 5–6 |
| Embed in Legacy + Full | Task 5 |
| Desktop AppIntent untouched / 14-only | Tasks 5, 7 |
| Menu bar unchanged | Global constraint; no menu bar tasks |
| Settings default account | Tasks 1, 4 |
| Shared sidecar for Use App Default | Task 2 |
| Resolver table | Task 3 |
| Clear default on delete | Task 4 |
| Packaging/verifier contract | Task 7 |
| README / compatibility docs | Task 8 |
| Automated + manual tests | Tasks 1–4, 7, 9 |
