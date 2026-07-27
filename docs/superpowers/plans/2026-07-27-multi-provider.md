# Multi-Provider Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add capability-aware API Info, DeepSeek, Kimi, OpenRouter, and MiniMax accounts with automatic region and credential detection.

**Architecture:** Store a stable provider family plus a detected profile on each account, route refreshes through a provider registry, and normalize vendor responses into independent balance, spending-limit, spend-period, and quota-window capabilities. Aggregate only real balances by currency and let menu bar and Widget presenters select explicitly labeled compact metrics.

**Tech Stack:** Swift 6, Swift Package Manager, Swift Testing, SwiftUI, WidgetKit, Foundation URL loading, Security Keychain, XcodeGen.

---

## File Map

- Create `Sources/QuotaGlanceCore/Domain/Provider.swift`: provider identity, region, credential kind, detected profile, and display metadata.
- Modify `Sources/QuotaGlanceCore/Domain/Account.swift`: persist provider/profile with version-1 decoding defaults.
- Modify `Sources/QuotaGlanceCore/Domain/UsageSnapshot.swift`: capability-based provider and aggregate snapshots.
- Modify `Sources/QuotaGlanceCore/Validation/AccountValidator.swift`: validate provider changes and carry provider in validated drafts.
- Modify `Sources/QuotaGlanceCore/Providers/UsageProvider.swift`: detection contract, registry, shared HTTP status mapping, and provider errors.
- Modify `Sources/QuotaGlanceCore/Providers/APIInfoProvider.swift`: map API Info into capability values.
- Create `Sources/QuotaGlanceCore/Providers/DeepSeekProvider.swift`: official balance adapter.
- Create `Sources/QuotaGlanceCore/Providers/KimiProvider.swift`: regional balance detection and refresh.
- Create `Sources/QuotaGlanceCore/Providers/OpenRouterProvider.swift`: key-type detection, spend, cap, and credit mapping.
- Create `Sources/QuotaGlanceCore/Providers/MiniMaxProvider.swift`: regional Token Plan detection and quota mapping.
- Modify `Sources/QuotaGlanceCore/Refresh/RefreshCoordinator.swift`: route each account through the registry.
- Modify `Sources/QuotaGlanceCore/Aggregation/SnapshotAggregator.swift`: group real balances by currency.
- Modify presentation files under `Sources/QuotaGlanceCore/Presentation`: derive capability-aware dashboard, menu bar, and Widget values.
- Modify `App/AppModel.swift`: detect on save, persist profiles, and emit provider-specific messages.
- Modify `App/Settings/AccountEditorView.swift` and `App/Settings/SettingsView.swift`: provider picker and detected-profile feedback.
- Modify `App/MenuBar/MenuBarDashboardView.swift` and `Widget/WidgetViews.swift`: capability-driven sections.
- Add provider and migration tests under `Tests/QuotaGlanceCoreTests` and JSON fixtures under `Tests/QuotaGlanceCoreTests/Fixtures`.
- Modify `README.md` and `docs/research/provider-capabilities.md`: document supported behavior and limits.

### Task 1: Provider Identity, Capabilities, and Migration

**Files:**
- Create: `Sources/QuotaGlanceCore/Domain/Provider.swift`
- Modify: `Sources/QuotaGlanceCore/Domain/Account.swift`
- Modify: `Sources/QuotaGlanceCore/Domain/UsageSnapshot.swift`
- Modify: `Sources/QuotaGlanceCore/Storage/AccountPreferencesStore.swift`
- Test: `Tests/QuotaGlanceCoreTests/DomainModelTests.swift`
- Test: `Tests/QuotaGlanceCoreTests/StorageTests.swift`

- [ ] **Step 1: Write failing provider and migration tests**

Cover all provider cases, profile round-trips, legacy account JSON without
provider/profile fields, version-2 storage, primary metric precedence, and
version-2 Widget envelopes.

```swift
let legacy = #"{"id":"00000000-0000-0000-0000-000000000001","displayName":"Legacy","isEnabled":true,"sortOrder":0,"lowBalanceThreshold":10,"alertEpisodeActive":false}"#
let account = try JSONDecoder.quotaGlance.decode(Account.self, from: Data(legacy.utf8))
#expect(account.provider == .apiInfo)
#expect(account.detectedProfile == .apiInfo)
```

- [ ] **Step 2: Run focused tests and verify the new symbols are missing**

Run: `swift test --filter 'Domain models|Storage'`
Expected: FAIL because provider and capability types do not exist.

- [ ] **Step 3: Implement provider identity and capability values**

```swift
public enum ProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case apiInfo, deepSeek, kimi, openRouter, miniMax
    public var id: String { rawValue }
}

public struct ProviderProfile: Codable, Equatable, Sendable {
    public var region: ProviderRegion
    public var credentialKind: ProviderCredentialKind
    public static let apiInfo = Self(region: .global, credentialKind: .standard)
}

public struct MonetaryBalance: Codable, Equatable, Sendable {
    public var label: String
    public var available: Money
    public var breakdown: [MonetaryValue]
}

public struct QuotaWindow: Codable, Equatable, Sendable {
    public var label: String
    public var used: Decimal?
    public var limit: Decimal?
    public var remaining: Decimal?
    public var unit: String
    public var resetsAt: Date?
}
```

Implement custom `Account.init(from:)` so missing provider data maps to API Info.
Set `StoredAccountPreferences.currentSchemaVersion` and
`WidgetSnapshotEnvelope.currentSchemaVersion` to 2 while retaining the existing
UserDefaults key.

- [ ] **Step 4: Run focused and full core tests**

Run: `swift test --filter 'Domain models|Storage' && swift test`
Expected: PASS.

- [ ] **Step 5: Commit the domain migration**

```bash
git add Sources/QuotaGlanceCore/Domain Sources/QuotaGlanceCore/Storage Tests/QuotaGlanceCoreTests/DomainModelTests.swift Tests/QuotaGlanceCoreTests/StorageTests.swift
git commit -m "feat: add provider capability domain model"
```

### Task 2: Provider Contract, Registry, and API Info Compatibility

**Files:**
- Modify: `Sources/QuotaGlanceCore/Providers/UsageProvider.swift`
- Modify: `Sources/QuotaGlanceCore/Providers/APIInfoProvider.swift`
- Test: `Tests/QuotaGlanceCoreTests/APIInfoProviderTests.swift`
- Create: `Tests/QuotaGlanceCoreTests/ProviderRegistryTests.swift`

- [ ] **Step 1: Write failing detection and registry tests**

```swift
let result = try await APIInfoProvider(httpClient: client).detect(apiKey: "redacted")
#expect(result.profile == .apiInfo)
#expect(result.snapshot.balances.first?.available.currency == "USD")
#expect(registry.provider(for: .apiInfo) is APIInfoProvider)
```

Also assert that API Info `remaining` stays authoritative and its quota becomes
a non-aggregate spending-limit capability.

- [ ] **Step 2: Run the focused tests and verify contract failures**

Run: `swift test --filter 'API Info provider|Provider registry'`
Expected: FAIL because detection and registry APIs are absent.

- [ ] **Step 3: Implement the contract and migrate API Info**

```swift
public struct ProviderDetection: Equatable, Sendable {
    public let profile: ProviderProfile
    public let snapshot: ProviderUsageSnapshot
}

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func detect(apiKey: String) async throws -> ProviderDetection
    func fetch(apiKey: String, profile: ProviderProfile) async throws -> ProviderUsageSnapshot
}

public struct ProviderRegistry: Sendable {
    public func provider(for id: ProviderID) -> any UsageProvider
}
```

Centralize HTTP 401/403, 429, and other status mapping. Keep the legacy
`fetch(apiKey:)` convenience on API Info only if existing tests need it during
the transition.

- [ ] **Step 4: Run provider and full tests**

Run: `swift test --filter 'API Info provider|Provider registry' && swift test`
Expected: PASS.

- [ ] **Step 5: Commit provider infrastructure**

```bash
git add Sources/QuotaGlanceCore/Providers Tests/QuotaGlanceCoreTests/APIInfoProviderTests.swift Tests/QuotaGlanceCoreTests/ProviderRegistryTests.swift
git commit -m "feat: add provider detection registry"
```

### Task 3: DeepSeek and Kimi Balance Providers

**Files:**
- Create: `Sources/QuotaGlanceCore/Providers/DeepSeekProvider.swift`
- Create: `Sources/QuotaGlanceCore/Providers/KimiProvider.swift`
- Create: `Tests/QuotaGlanceCoreTests/DeepSeekProviderTests.swift`
- Create: `Tests/QuotaGlanceCoreTests/KimiProviderTests.swift`

- [ ] **Step 1: Write failing DeepSeek contract tests**

Use inline redacted payloads to verify CNY and USD entries, granted/topped-up
breakdowns, request headers, unavailable balances, and typed HTTP failures.

```swift
#expect(snapshot.balances.map(\.available.currency) == ["CNY", "USD"])
#expect(snapshot.balances[0].breakdown.map(\.label) == ["Granted", "Topped up"])
```

- [ ] **Step 2: Implement DeepSeek and make its tests pass**

Run: `swift test --filter 'DeepSeek provider'`
Expected before implementation: FAIL. Expected after implementation: PASS.

- [ ] **Step 3: Write failing Kimi region tests**

Use a sequenced HTTP client to assert China-first detection on a China locale,
fallback only after 401/403, no fallback after 429/5xx/transport errors, CNY and
USD mapping, and single-endpoint refresh with a stored profile.

```swift
let detection = try await provider.detect(apiKey: "redacted")
#expect(detection.profile == ProviderProfile(region: .international, credentialKind: .standard))
#expect(detection.snapshot.balances[0].available.currency == "USD")
```

- [ ] **Step 4: Implement Kimi regional detection and make tests pass**

Decode `code == 0`, `status == true`, and all three balance fields. Retry the
other official region only for `ProviderError.invalidCredential`.

Run: `swift test --filter 'Kimi provider'`
Expected: PASS.

- [ ] **Step 5: Run the full suite and commit both balance providers**

Run: `swift test`
Expected: PASS.

```bash
git add Sources/QuotaGlanceCore/Providers/DeepSeekProvider.swift Sources/QuotaGlanceCore/Providers/KimiProvider.swift Tests/QuotaGlanceCoreTests/DeepSeekProviderTests.swift Tests/QuotaGlanceCoreTests/KimiProviderTests.swift
git commit -m "feat: add DeepSeek and Kimi providers"
```

### Task 4: OpenRouter and MiniMax Capability Providers

**Files:**
- Create: `Sources/QuotaGlanceCore/Providers/OpenRouterProvider.swift`
- Create: `Sources/QuotaGlanceCore/Providers/MiniMaxProvider.swift`
- Create: `Tests/QuotaGlanceCoreTests/OpenRouterProviderTests.swift`
- Create: `Tests/QuotaGlanceCoreTests/MiniMaxProviderTests.swift`

- [ ] **Step 1: Write failing OpenRouter tests**

Cover capped standard keys, uncapped standard keys, management keys plus the
credits endpoint, negative credit balances, period spend, and typed errors.

```swift
#expect(standard.profile.credentialKind == .standard)
#expect(standard.snapshot.spendingLimit?.remaining == Money(amount: 74.5, currency: "USD"))
#expect(management.snapshot.balances[0].available == Money(amount: 74.75, currency: "USD"))
```

- [ ] **Step 2: Implement OpenRouter and make its tests pass**

Always fetch `/key`; fetch `/credits` only for `is_management_key == true`.
Ignore deprecated `rate_limit`.

Run: `swift test --filter 'OpenRouter provider'`
Expected: PASS.

- [ ] **Step 3: Write failing MiniMax tests**

Cover immediate rejection of `sk-api-`, China/international fallback,
HTTP-200 embedded `base_resp.status_code` errors, stored-region refresh,
`model_remains` mapping, and a success payload with no buckets.

```swift
await #expect(throws: ProviderError.unsupportedCredential) {
    try await provider.detect(apiKey: "sk-api-redacted")
}
#expect(snapshot.quotaWindows[0].remaining == 900)
#expect(snapshot.quotaWindows[0].limit == 1000)
```

- [ ] **Step 4: Implement MiniMax and make its tests pass**

Decode known numeric and string number forms without defaulting missing values
to zero. Retry a second region only for definitive authentication rejection.

Run: `swift test --filter 'MiniMax provider'`
Expected: PASS.

- [ ] **Step 5: Run the full suite and commit both providers**

Run: `swift test`
Expected: PASS.

```bash
git add Sources/QuotaGlanceCore/Providers/OpenRouterProvider.swift Sources/QuotaGlanceCore/Providers/MiniMaxProvider.swift Tests/QuotaGlanceCoreTests/OpenRouterProviderTests.swift Tests/QuotaGlanceCoreTests/MiniMaxProviderTests.swift
git commit -m "feat: add OpenRouter and MiniMax providers"
```

### Task 5: Mixed-Provider Save and Refresh Routing

**Files:**
- Modify: `Sources/QuotaGlanceCore/Validation/AccountValidator.swift`
- Modify: `Sources/QuotaGlanceCore/Refresh/RefreshCoordinator.swift`
- Modify: `App/AppModel.swift`
- Modify: `Tests/QuotaGlanceCoreTests/AccountValidationTests.swift`
- Modify: `Tests/QuotaGlanceCoreTests/RefreshCoordinatorTests.swift`

- [ ] **Step 1: Write failing account and coordinator tests**

Assert provider is carried through drafts, changing a provider requires a
replacement key, different accounts call different registry adapters, stored
profiles reach `fetch`, and stale results retain provider metadata.

```swift
let accounts = [
    Account(displayName: "CN", provider: .kimi, detectedProfile: .init(region: .china, credentialKind: .standard)),
    Account(displayName: "OR", provider: .openRouter, detectedProfile: .init(region: .global, credentialKind: .management)),
]
#expect(await registry.calls.map(\.provider) == [.kimi, .openRouter])
```

- [ ] **Step 2: Run focused tests and verify routing failures**

Run: `swift test --filter 'Account validation|Refresh coordination'`
Expected: FAIL against the old fixed-provider coordinator.

- [ ] **Step 3: Implement validation, registry routing, and save detection**

`AppModel.saveAccount` selects the provider from the registry, runs detection
when a new key is supplied, persists the returned profile, and publishes the
returned snapshot. Blank-key edits retain the existing profile. Provider
changes with blank keys fail validation.

- [ ] **Step 4: Add provider-specific user messages**

Map unsupported MiniMax pay-as-you-go, regional rejection, invalid credential,
rate limit, and malformed payload errors without embedding credentials or raw
responses.

- [ ] **Step 5: Run tests and commit mixed-provider routing**

Run: `swift test`
Expected: PASS.

```bash
git add Sources/QuotaGlanceCore/Validation Sources/QuotaGlanceCore/Refresh App/AppModel.swift Tests/QuotaGlanceCoreTests/AccountValidationTests.swift Tests/QuotaGlanceCoreTests/RefreshCoordinatorTests.swift
git commit -m "feat: route accounts by provider"
```

### Task 6: Currency Aggregation and Capability Presenters

**Files:**
- Modify: `Sources/QuotaGlanceCore/Aggregation/SnapshotAggregator.swift`
- Modify: `Sources/QuotaGlanceCore/Alerts/AlertEvaluator.swift`
- Modify: `Sources/QuotaGlanceCore/Presentation/DashboardPresentation.swift`
- Modify: `Sources/QuotaGlanceCore/Presentation/MenuBarPresentation.swift`
- Modify: `Sources/QuotaGlanceCore/Presentation/WidgetPresentation.swift`
- Modify tests for aggregation, alerts, dashboard, menu bar, and Widget presentation.

- [ ] **Step 1: Write failing multi-currency and capability tests**

Assert CNY and USD totals remain separate, mixed currencies are not partial,
spending limits and quota windows are excluded, account presentations select
the documented primary metric order, and spend is labeled as spend.

```swift
#expect(aggregate.balances == [
    Money(amount: 30, currency: "CNY"),
    Money(amount: 12, currency: "USD"),
])
#expect(presentation.primaryMetric?.label == "Key limit")
```

- [ ] **Step 2: Implement aggregation and presentation derivation**

Sort aggregate balances by currency code for deterministic UI and tests. Keep
alerts limited to `usage.balances.first?.available` and never evaluate stale
data, caps, or windows.

- [ ] **Step 3: Run all presenter tests and the full suite**

Run: `swift test --filter 'aggregation|presentation|alerts' && swift test`
Expected: PASS.

- [ ] **Step 4: Commit presentation domain changes**

```bash
git add Sources/QuotaGlanceCore/Aggregation Sources/QuotaGlanceCore/Alerts Sources/QuotaGlanceCore/Presentation Tests/QuotaGlanceCoreTests
git commit -m "feat: present provider capabilities"
```

### Task 7: Provider-Aware Settings, Menu Bar, and Widgets

**Files:**
- Modify: `App/Settings/AccountEditorView.swift`
- Modify: `App/Settings/SettingsView.swift`
- Modify: `App/MenuBar/MenuBarDashboardView.swift`
- Modify: `Widget/WidgetViews.swift`
- Modify: `Widget/QuotaGlanceWidget.swift`

- [ ] **Step 1: Add the native provider picker and detected-profile labels**

Bind the picker to `AccountDraft.provider`, require a replacement key when an
existing provider changes, and show provider plus detected profile in Settings
rows. Keep the editor width stable and increase height only as needed for the
new row and feedback.

- [ ] **Step 2: Render menu bar capability sections**

All Accounts shows separate currency balances. Account details conditionally
show balance breakdowns, spending-limit progress, period spend, quota windows,
daily history, and models. Put the variable body in a scroll view inside the
existing 360 by 500 content size.

- [ ] **Step 3: Render compact Widget primary metrics**

Display both value and semantic label. All Accounts shows up to two currency
totals and preserves configurable account selection and deep links.

- [ ] **Step 4: Regenerate and build both editions**

Run:

```bash
xcodegen generate
xcodebuild -project QuotaGlance.xcodeproj -scheme QuotaGlanceLegacy -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project QuotaGlance.xcodeproj -scheme QuotaGlance -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: both builds succeed.

- [ ] **Step 5: Commit UI integration**

```bash
git add App Widget QuotaGlance.xcodeproj
git commit -m "feat: add provider-aware account UI"
```

### Task 8: Documentation, Script Tests, and End-to-End Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/research/provider-capabilities.md`
- Modify provider descriptions in Widget configuration where API Info is named directly.

- [ ] **Step 1: Update user and provider documentation**

Describe the five provider choices, automatic regional detection, CNY/USD
grouping, OpenRouter key behavior, MiniMax Token Plan-only support, account-wide
duplicate-balance caveat, and unchanged Keychain handling.

- [ ] **Step 2: Run the complete automated gate**

Run:

```bash
swift test
bash Tests/ScriptTests/BuildEditionTests.sh
bash Tests/ScriptTests/DMGPackagingTests.sh
bash Tests/ScriptTests/LocalInstallSafetyTests.sh
./scripts/distribution-validation.sh
git diff --check
```

Expected: every command exits 0.

- [ ] **Step 3: Run macOS builds and inspect the app**

Build both schemes with signing disabled, launch the debug app, and inspect
Settings and the menu bar at the fixed panel size. Confirm labels fit, mixed
CNY/USD totals remain separate, empty capabilities do not leave blank cards,
and error text wraps without overlap.

- [ ] **Step 4: Verify secret safety**

Run repository scans for credential-like files and ensure provider fixtures use
only explicit redacted test keys. Confirm no request logging was added.

- [ ] **Step 5: Commit documentation and final adjustments**

```bash
git add README.md docs/research/provider-capabilities.md Widget App Sources Tests QuotaGlance.xcodeproj
git commit -m "docs: explain multi-provider support"
```

- [ ] **Step 6: Verify repository state**

Run: `git status -sb && git log -10 --oneline`
Expected: the branch contains the design and implementation commits with no
uncommitted feature files.
