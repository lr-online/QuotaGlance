# QuotaGlance Phase-One Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, locally install, and verify a native macOS menu bar app plus WidgetKit extension that displays live aggregate and per-account API Info balances for two to five keys.

**Architecture:** A Swift package contains all credential-independent domain, API, aggregation, persistence, refresh, and alert logic so it can be built and tested with Command Line Tools. A SwiftUI menu bar host owns Keychain, network scheduling, notifications, and atomic App Group snapshots; a WidgetKit extension reads those snapshots only. XcodeGen creates the host and extension project, and a local installer builds and places the signed app in `~/Applications`.

**Tech Stack:** Swift 6.3, Swift Package Manager, SwiftUI, Observation, WidgetKit, AppIntents, URLSession, Security/Keychain, UserNotifications, ServiceManagement, XcodeGen, XCTest.

---

## Delivery Constraints

- The current machine has macOS 26.5 and Swift 6.3.1 Command Line Tools.
- Full Xcode is not currently installed. `mas install 497799835` reaches an
  administrator-password prompt, so the user must complete that installation
  before Tasks 8-12 can be built and system-verified.
- No valid code-signing identity is currently installed. Xcode development
  signing must be configured before App Group verification.
- Tasks 1-7 must remain runnable with `swift test` before Xcode is available.
- No real API key may enter a source file, fixture, command output, or commit.

## Planned File Map

Core package:

- `Package.swift`: Swift package manifest.
- `Sources/QuotaGlanceCore/Domain/Account.swift`: account metadata and settings.
- `Sources/QuotaGlanceCore/Domain/UsageSnapshot.swift`: normalized provider,
  aggregate, and widget snapshots.
- `Sources/QuotaGlanceCore/Providers/UsageProvider.swift`: provider and HTTP
  contracts.
- `Sources/QuotaGlanceCore/Providers/APIInfoProvider.swift`: API Info request,
  DTO decoding, and error mapping.
- `Sources/QuotaGlanceCore/Aggregation/SnapshotAggregator.swift`: multi-account
  aggregation and seven-day date grouping.
- `Sources/QuotaGlanceCore/Storage/AccountPreferencesStore.swift`: versioned
  non-secret account preferences.
- `Sources/QuotaGlanceCore/Storage/KeychainStore.swift`: host-only key storage.
- `Sources/QuotaGlanceCore/Storage/SharedSnapshotStore.swift`: atomic snapshot
  file storage.
- `Sources/QuotaGlanceCore/Refresh/RefreshCoordinator.swift`: refresh
  coalescing, partial success, and stale preservation.
- `Sources/QuotaGlanceCore/Alerts/AlertEvaluator.swift`: low-balance episode
  state machine.
- `Tests/QuotaGlanceCoreTests/**`: focused unit and integration tests.

Host app:

- `project.yml`: deterministic XcodeGen project definition.
- `App/QuotaGlanceApp.swift`: scenes and menu bar entry point.
- `App/AppModel.swift`: observable host state and service orchestration.
- `App/MenuBar/MenuBarDashboardView.swift`: balance-led menu bar panel.
- `App/MenuBar/UsageChartView.swift`: stable seven-day chart.
- `App/Settings/SettingsView.swift`: account and app preferences.
- `App/Settings/AccountEditorView.swift`: add/edit/validate account form.
- `App/Services/NotificationService.swift`: notification permission and send.
- `App/Services/LaunchAtLoginService.swift`: `SMAppService` wrapper.
- `App/Info.plist`: accessory app and deep-link configuration.
- `App/QuotaGlance.entitlements`: sandbox, outgoing network, and App Group.

Widget:

- `Widget/QuotaGlanceWidgetBundle.swift`: widget extension entry point.
- `Widget/QuotaGlanceWidget.swift`: configuration and timeline provider.
- `Widget/AccountSelectionIntent.swift`: aggregate/per-account App Intent.
- `Widget/WidgetViews.swift`: small, medium, and large presentations.
- `Widget/Info.plist`: WidgetKit extension declaration.
- `Widget/QuotaGlanceWidget.entitlements`: sandbox and App Group.

Delivery:

- `scripts/install-local.sh`: validated build/install/launch helper.
- `README.md`: local prerequisites, setup, account entry, and widget steps.

### Task 1: Create The Testable Core Package And Domain Types

**Files:**
- Create: `Package.swift`
- Create: `Sources/QuotaGlanceCore/Domain/Account.swift`
- Create: `Sources/QuotaGlanceCore/Domain/UsageSnapshot.swift`
- Create: `Tests/QuotaGlanceCoreTests/DomainModelTests.swift`

- [ ] **Step 1: Write the package manifest and failing domain tests**

Create a macOS 14 library package named `QuotaGlanceCore`. The first tests must
assert Decimal money round-tripping, account defaults, and versioned snapshot
round-tripping:

```swift
import XCTest
@testable import QuotaGlanceCore

final class DomainModelTests: XCTestCase {
    func testMoneyRoundTripsWithoutDoubleConversion() throws {
        let money = Money(amount: Decimal(string: "544.045471")!, currency: "USD")
        let data = try JSONEncoder.quotaGlance.encode(money)
        XCTAssertEqual(try JSONDecoder.quotaGlance.decode(Money.self, from: data), money)
    }

    func testNewAccountDefaultsToEnabledAndFiveMinuteRefresh() {
        let account = Account(displayName: "Primary")
        XCTAssertTrue(account.isEnabled)
        XCTAssertNil(account.lowBalanceThreshold)
        XCTAssertEqual(AppPreferences.default.refreshInterval, .fiveMinutes)
    }

    func testSnapshotEnvelopeRoundTripsSchemaVersion() throws {
        let envelope = WidgetSnapshotEnvelope.empty(capturedAt: Date(timeIntervalSince1970: 100))
        let data = try JSONEncoder.quotaGlance.encode(envelope)
        let decoded = try JSONDecoder.quotaGlance.decode(WidgetSnapshotEnvelope.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.capturedAt, envelope.capturedAt)
    }
}
```

- [ ] **Step 2: Run the tests and verify they fail**

Run: `swift test --filter DomainModelTests`

Expected: FAIL because `QuotaGlanceCore`, `Money`, `Account`,
`AppPreferences`, and `WidgetSnapshotEnvelope` do not exist.

- [ ] **Step 3: Implement the minimal domain model**

Implement:

```swift
public struct Money: Codable, Equatable, Sendable {
    public var amount: Decimal
    public var currency: String

    public init(amount: Decimal, currency: String) {
        self.amount = amount
        self.currency = currency
    }
}

public enum RefreshInterval: Int, Codable, CaseIterable, Sendable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1_800
    case sixtyMinutes = 3_600
}

public struct Account: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var displayName: String
    public var isEnabled: Bool
    public var sortOrder: Int
    public var lowBalanceThreshold: Decimal?
    public var alertEpisodeActive: Bool

    public init(
        id: UUID = UUID(),
        displayName: String,
        isEnabled: Bool = true,
        sortOrder: Int = 0,
        lowBalanceThreshold: Decimal? = nil,
        alertEpisodeActive: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.lowBalanceThreshold = lowBalanceThreshold
        self.alertEpisodeActive = alertEpisodeActive
    }
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public var refreshInterval: RefreshInterval
    public var launchAtLogin: Bool

    public init(refreshInterval: RefreshInterval, launchAtLogin: Bool) {
        self.refreshInterval = refreshInterval
        self.launchAtLogin = launchAtLogin
    }

    public static let `default` = AppPreferences(
        refreshInterval: .fiveMinutes,
        launchAtLogin: false
    )
}

public struct UsageCounters: Codable, Equatable, Sendable {
    public var actualCost: Money?
    public var requests: Int64?
    public var inputTokens: Int64?
    public var outputTokens: Int64?
    public var cacheReadTokens: Int64?
    public var cacheCreationTokens: Int64?
    public var totalTokens: Int64?
}

public struct DailyUsage: Codable, Equatable, Sendable {
    public var date: String
    public var actualCost: Money
    public var requests: Int64?
    public var totalTokens: Int64?
}

public struct ModelUsage: Codable, Equatable, Sendable {
    public var model: String
    public var actualCost: Money?
    public var requests: Int64?
    public var totalTokens: Int64?
}

public struct ProviderUsageSnapshot: Codable, Equatable, Sendable {
    public var remaining: Money
    public var quotaLimit: Money?
    public var quotaUsed: Money?
    public var today: UsageCounters?
    public var total: UsageCounters?
    public var dailyUsage: [DailyUsage]
    public var modelUsage: [ModelUsage]
    public var providerStatus: String?
    public var receivedAt: Date
}

public enum SnapshotFailure: String, Codable, Equatable, Sendable {
    case missingCredential
    case invalidCredential
    case rateLimited
    case offline
    case timeout
    case invalidResponse
    case providerError
}

public enum AccountHealth: Codable, Equatable, Sendable {
    case healthy
    case belowThreshold
    case stale(SnapshotFailure)
    case unavailable(SnapshotFailure)
}

public struct AccountSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { accountID }
    public var accountID: UUID
    public var displayName: String
    public var lowBalanceThreshold: Decimal?
    public var usage: ProviderUsageSnapshot?
    public var health: AccountHealth
    public var lastSuccessAt: Date?
}

public struct AggregateSnapshot: Codable, Equatable, Sendable {
    public var remaining: Money?
    public var todayActualCost: Money?
    public var todayRequests: Int64?
    public var dailyUsage: [DailyUsage]
    public var accounts: [AccountSnapshot]
    public var isPartial: Bool
}

public struct WidgetSnapshotEnvelope: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var capturedAt: Date
    public var aggregate: AggregateSnapshot
    public var accounts: [AccountSnapshot]

    public static func empty(capturedAt: Date) -> Self {
        Self(
            schemaVersion: 1,
            capturedAt: capturedAt,
            aggregate: AggregateSnapshot(
                remaining: nil,
                todayActualCost: nil,
                todayRequests: nil,
                dailyUsage: [],
                accounts: [],
                isPartial: false
            ),
            accounts: []
        )
    }
}

public extension JSONEncoder {
    static var quotaGlance: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var quotaGlance: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

- [ ] **Step 4: Run the focused and complete package tests**

Run: `swift test --filter DomainModelTests && swift test`

Expected: PASS with 3 focused tests and no package failures.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: add QuotaGlance core domain models"
```

### Task 2: Decode API Info Without Deriving Remaining Balance

**Files:**
- Create: `Sources/QuotaGlanceCore/Providers/UsageProvider.swift`
- Create: `Sources/QuotaGlanceCore/Providers/APIInfoProvider.swift`
- Create: `Tests/QuotaGlanceCoreTests/Fixtures/api-info-complete.json`
- Create: `Tests/QuotaGlanceCoreTests/APIInfoProviderTests.swift`

- [ ] **Step 1: Add sanitized response fixture and failing decoder tests**

The fixture must deliberately make `quota.limit - quota.used` differ from the
top-level `remaining`:

```json
{
  "isValid": true,
  "status": "active",
  "unit": "USD",
  "remaining": 544.045471,
  "quota": {"limit": 7200, "remaining": 544.045471, "used": 6655.90},
  "usage": {
    "today": {"actual_cost": 12.34, "requests": 42, "input_tokens": 1000, "output_tokens": 50, "cache_read_tokens": 5000, "cache_creation_tokens": 0, "total_tokens": 6050},
    "total": {"actual_cost": 6650.22, "requests": 37194, "input_tokens": 730313533, "output_tokens": 20860183, "cache_read_tokens": 4666258113, "cache_creation_tokens": 6765568, "total_tokens": 5424197397}
  },
  "daily_usage": [{"date": "2026-07-22", "actual_cost": 12.34, "requests": 42, "total_tokens": 6050}],
  "model_stats": [{"model": "gpt-test", "actual_cost": 10.0, "requests": 40, "total_tokens": 6000}]
}
```

Tests must use an injected HTTP client and assert:

```swift
func testFetchUsesTopLevelRemainingAsAuthoritative() async throws {
    let provider = APIInfoProvider(httpClient: StubHTTPClient.fixture("api-info-complete"))
    let snapshot = try await provider.fetch(apiKey: "redacted-test-key")
    XCTAssertEqual(snapshot.remaining.amount, Decimal(string: "544.045471"))
    XCTAssertNotEqual(snapshot.remaining.amount, snapshot.quotaLimit!.amount - snapshot.quotaUsed!.amount)
}

func testRequestUsesBearerHeaderAndExpectedEndpoint() async throws {
    let recorder = RecordingHTTPClient(response: fixtureData)
    _ = try await APIInfoProvider(httpClient: recorder).fetch(apiKey: "secret")
    XCTAssertEqual(recorder.lastRequest?.url?.absoluteString, "https://www.api-info.net/v1/usage")
    XCTAssertEqual(recorder.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
}
```

- [ ] **Step 2: Run tests and verify missing-provider failures**

Run: `swift test --filter APIInfoProviderTests`

Expected: FAIL because the HTTP and provider contracts are undefined.

- [ ] **Step 3: Implement provider, DTOs, and typed errors**

Define:

```swift
public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public protocol UsageProvider: Sendable {
    func fetch(apiKey: String) async throws -> ProviderUsageSnapshot
}

public enum ProviderError: Error, Equatable, Sendable {
    case invalidCredential
    case rateLimited
    case httpStatus(Int)
    case invalidResponse
    case providerInactive
}
```

`APIInfoProvider.fetch` must create the exact request, map 401/403 to
`invalidCredential`, 429 to `rateLimited`, reject non-2xx responses, reject
`isValid == false`, parse numeric money through `Decimal`, prefer
`actual_cost`, and record `Date.now` as received/last-success time. Never log the
request headers or response body.

- [ ] **Step 4: Run provider and full tests**

Run: `swift test --filter APIInfoProviderTests && swift test`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/QuotaGlanceCore/Providers Tests/QuotaGlanceCoreTests
git commit -m "feat: decode API Info usage responses"
```

### Task 3: Aggregate Two To Five Accounts And Preserve Partial State

**Files:**
- Create: `Sources/QuotaGlanceCore/Aggregation/SnapshotAggregator.swift`
- Create: `Tests/QuotaGlanceCoreTests/SnapshotAggregatorTests.swift`

- [ ] **Step 1: Write failing aggregate tests**

Cover two healthy accounts, missing dates, disabled accounts, one stale
account, and five-account ordering:

```swift
func testAggregateSumsMoneyAndFillsSevenCalendarDays() throws {
    let snapshots = [
        fixtureSnapshot(name: "A", remaining: "544.05", today: "12.00", dayOffset: 0),
        fixtureSnapshot(name: "B", remaining: "100.00", today: "3.00", dayOffset: -1)
    ]
    let aggregate = SnapshotAggregator(calendar: utcCalendar).aggregate(
        accounts: fixtureAccounts,
        snapshots: snapshots,
        now: fixedNow
    )
    XCTAssertEqual(aggregate.remaining?.amount, Decimal(string: "644.05"))
    XCTAssertEqual(aggregate.todayActualCost?.amount, Decimal(string: "15.00"))
    XCTAssertEqual(aggregate.dailyUsage.count, 7)
    XCTAssertFalse(aggregate.isPartial)
}

func testAggregateMarksPartialAndKeepsStaleAccountValue() {
    let aggregate = makeAggregate(withSecondAccountHealth: .stale(.offline))
    XCTAssertTrue(aggregate.isPartial)
    XCTAssertEqual(aggregate.accounts.count, 2)
    XCTAssertEqual(aggregate.remaining?.amount, Decimal(string: "644.05"))
}
```

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter SnapshotAggregatorTests`

Expected: FAIL because `SnapshotAggregator` does not exist.

- [ ] **Step 3: Implement deterministic aggregation**

Implement a pure `SnapshotAggregator` that:

- includes enabled accounts only;
- preserves account sort order;
- requires matching currency before adding values;
- sums request/token Int64 fields with overflow-safe reporting;
- groups provider `YYYY-MM-DD` daily entries using a fixed Gregorian calendar;
- emits exactly seven dates ending on the latest provider/local date;
- represents absent days as zero only inside the chart series;
- marks aggregate partial when any included account is stale or failed;
- never turns an absent provider metric into a domain zero.

- [ ] **Step 4: Run tests**

Run: `swift test --filter SnapshotAggregatorTests && swift test`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/QuotaGlanceCore/Aggregation Tests/QuotaGlanceCoreTests/SnapshotAggregatorTests.swift
git commit -m "feat: aggregate multi-account usage snapshots"
```

### Task 4: Persist Preferences, Keys, And Shared Snapshots Safely

**Files:**
- Create: `Sources/QuotaGlanceCore/Storage/AccountPreferencesStore.swift`
- Create: `Sources/QuotaGlanceCore/Storage/KeychainStore.swift`
- Create: `Sources/QuotaGlanceCore/Storage/SharedSnapshotStore.swift`
- Create: `Tests/QuotaGlanceCoreTests/StorageTests.swift`

- [ ] **Step 1: Write failing storage tests**

Use an isolated `UserDefaults` suite and temporary directory:

```swift
func testPreferencesRoundTripVersionedPayload() throws {
    let defaults = UserDefaults(suiteName: testSuite)!
    let store = AccountPreferencesStore(defaults: defaults)
    try store.save(accounts: [Account(displayName: "Primary")], preferences: .default)
    let loaded = try store.load()
    XCTAssertEqual(loaded.accounts.map(\.displayName), ["Primary"])
    XCTAssertEqual(loaded.schemaVersion, 1)
}

func testSharedSnapshotWriteReplacesWholeFile() throws {
    let url = temporaryDirectory.appending(path: "quota-snapshot-v1.json")
    let store = SharedSnapshotStore(fileURL: url)
    try store.write(.empty(capturedAt: firstDate))
    try store.write(.empty(capturedAt: secondDate))
    XCTAssertEqual(try store.read().capturedAt, secondDate)
}
```

Add a protocol-level test with `InMemoryCredentialStore` proving that account
UUIDs, not display names, are credential identifiers.

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter StorageTests`

Expected: FAIL because the stores are undefined.

- [ ] **Step 3: Implement stores**

Define `CredentialStore` with `read`, `save`, and `delete` operations.
`KeychainStore` uses `kSecClassGenericPassword`, service
`com.liangrui.QuotaGlance.api-info`, and the UUID string as `kSecAttrAccount`.
It maps item-not-found separately and zeroes temporary mutable key data after
SecItem calls when practical.

`AccountPreferencesStore` writes one schema-versioned Codable Data value to
injected `UserDefaults`. `SharedSnapshotStore` uses
`Data.write(to:options:.atomic)` and creates only the validated parent
directory.

- [ ] **Step 4: Run storage and full tests**

Run: `swift test --filter StorageTests && swift test`

Expected: PASS. No test touches the user's login Keychain.

- [ ] **Step 5: Commit**

```bash
git add Sources/QuotaGlanceCore/Storage Tests/QuotaGlanceCoreTests/StorageTests.swift
git commit -m "feat: persist accounts keys and widget snapshots"
```

### Task 5: Coordinate Refreshes And Preserve Last Success

**Files:**
- Create: `Sources/QuotaGlanceCore/Refresh/RefreshCoordinator.swift`
- Create: `Tests/QuotaGlanceCoreTests/RefreshCoordinatorTests.swift`

- [ ] **Step 1: Write failing concurrency and partial-success tests**

Use actor fakes to assert one provider call per account and coalescing:

```swift
func testConcurrentRefreshRequestsCoalesce() async throws {
    let provider = BlockingUsageProvider()
    let coordinator = makeCoordinator(provider: provider)
    async let first = coordinator.refresh(accounts: accounts)
    async let second = coordinator.refresh(accounts: accounts)
    await provider.release()
    _ = try await (first, second)
    XCTAssertEqual(await provider.callCount, accounts.count)
}

func testFailedAccountKeepsLastSuccessAndMarksAggregatePartial() async throws {
    let result = try await coordinatorWithOneFailure.refresh(accounts: accounts)
    XCTAssertEqual(result.accountSnapshots[failedID]?.usage?.remaining, previous.remaining)
    XCTAssertTrue(result.aggregate.isPartial)
    XCTAssertEqual(result.accountSnapshots[failedID]?.health, .stale(.offline))
}
```

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter RefreshCoordinatorTests`

Expected: FAIL because `RefreshCoordinator` is undefined.

- [ ] **Step 3: Implement the refresh actor**

`RefreshCoordinator` is an actor with one stored in-flight Task. It reads keys
through `CredentialStore`, uses a throwing task group capped by the maximum five
accounts, races each fetch against a 15-second clock timeout, maps failures to
`AccountHealth`, preserves the prior successful snapshot, aggregates the
result, writes the envelope, and returns a `RefreshResult` that distinguishes
fresh, partial, and all-failed outcomes.

No actor method logs or returns key strings. The in-flight Task is cleared with
`defer` after every terminal path.

- [ ] **Step 4: Run tests**

Run: `swift test --filter RefreshCoordinatorTests && swift test`

Expected: PASS, including the coalescing assertion.

- [ ] **Step 5: Commit**

```bash
git add Sources/QuotaGlanceCore/Refresh Tests/QuotaGlanceCoreTests/RefreshCoordinatorTests.swift
git commit -m "feat: coordinate resilient account refreshes"
```

### Task 6: Implement Low-Balance Episode Alerts

**Files:**
- Create: `Sources/QuotaGlanceCore/Alerts/AlertEvaluator.swift`
- Create: `Tests/QuotaGlanceCoreTests/AlertEvaluatorTests.swift`

- [ ] **Step 1: Write the state-machine tests**

```swift
func testAlertsOnceUntilBalanceRecovers() {
    var account = Account(displayName: "Primary", lowBalanceThreshold: 100)
    XCTAssertEqual(AlertEvaluator.evaluate(account: &account, freshRemaining: 90), .notify)
    XCTAssertEqual(AlertEvaluator.evaluate(account: &account, freshRemaining: 80), .none)
    XCTAssertEqual(AlertEvaluator.evaluate(account: &account, freshRemaining: 110), .reset)
    XCTAssertEqual(AlertEvaluator.evaluate(account: &account, freshRemaining: 95), .notify)
}

func testStaleOrFailedRefreshCannotAlert() {
    var account = Account(displayName: "Primary", lowBalanceThreshold: 100)
    XCTAssertEqual(AlertEvaluator.evaluate(account: &account, freshRemaining: nil), .none)
    XCTAssertFalse(account.alertEpisodeActive)
}
```

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter AlertEvaluatorTests`

Expected: FAIL because `AlertEvaluator` is undefined.

- [ ] **Step 3: Implement the pure evaluator**

Return `.notify` only for a fresh amount at/below threshold when no episode is
active, `.reset` only when a fresh amount rises above threshold, and `.none`
otherwise. Disabled/no-threshold accounts cannot alert. Persist the mutated
episode flag through the preferences store after refresh.

- [ ] **Step 4: Run tests and commit**

Run: `swift test --filter AlertEvaluatorTests && swift test`

Expected: PASS.

```bash
git add Sources/QuotaGlanceCore/Alerts Tests/QuotaGlanceCoreTests/AlertEvaluatorTests.swift
git commit -m "feat: evaluate low balance alert episodes"
```

### Task 7: Generate The macOS Host And Widget Project

**Files:**
- Create: `project.yml`
- Create: `App/Info.plist`
- Create: `App/QuotaGlance.entitlements`
- Create: `App/QuotaGlanceApp.swift`
- Create: `Widget/Info.plist`
- Create: `Widget/QuotaGlanceWidget.entitlements`
- Create: `Widget/QuotaGlanceWidgetBundle.swift`
- Create: `Widget/QuotaGlanceWidget.swift`
- Generate: `QuotaGlance.xcodeproj/**`

- [ ] **Step 1: Install XcodeGen and verify it**

Run: `brew install xcodegen && xcodegen --version`

Expected: XcodeGen version prints successfully without requiring Xcode.

- [ ] **Step 2: Write the deterministic project definition**

`project.yml` must define bundle IDs `com.liangrui.QuotaGlance` and
`com.liangrui.QuotaGlance.Widget`, macOS 14, Swift 6, local package dependency
`.`, an app target embedding the widget target, automatic signing, hardened
runtime, App Sandbox, and shared App Group
`group.com.liangrui.QuotaGlance`.

Use this target structure:

```yaml
name: QuotaGlance
options:
  bundleIdPrefix: com.liangrui
  createIntermediateGroups: true
  deploymentTarget:
    macOS: "14.0"
packages:
  QuotaGlanceCore:
    path: .
settings:
  base:
    SWIFT_VERSION: "6.0"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    CURRENT_PROJECT_VERSION: "1"
    MARKETING_VERSION: "0.1.0"
targets:
  QuotaGlance:
    type: application
    platform: macOS
    sources:
      - path: App
        excludes: [Info.plist, QuotaGlance.entitlements]
    dependencies:
      - package: QuotaGlanceCore
        product: QuotaGlanceCore
      - target: QuotaGlanceWidget
        embed: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.liangrui.QuotaGlance
        PRODUCT_NAME: QuotaGlance
        INFOPLIST_FILE: App/Info.plist
        CODE_SIGN_ENTITLEMENTS: App/QuotaGlance.entitlements
        CODE_SIGN_STYLE: Automatic
        ENABLE_HARDENED_RUNTIME: YES
  QuotaGlanceWidget:
    type: app-extension
    platform: macOS
    sources:
      - path: Widget
        excludes: [Info.plist, QuotaGlanceWidget.entitlements]
    dependencies:
      - package: QuotaGlanceCore
        product: QuotaGlanceCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.liangrui.QuotaGlance.Widget
        PRODUCT_NAME: QuotaGlanceWidget
        INFOPLIST_FILE: Widget/Info.plist
        CODE_SIGN_ENTITLEMENTS: Widget/QuotaGlanceWidget.entitlements
        CODE_SIGN_STYLE: Automatic
        APPLICATION_EXTENSION_API_ONLY: YES
        SKIP_INSTALL: YES
```

App `Info.plist` sets `LSUIElement = true` and URL scheme `quotaglance`.
Widget `Info.plist` sets extension point `com.apple.widgetkit-extension`.
Both entitlement files contain `com.apple.security.app-sandbox = true` and
`com.apple.security.application-groups = [group.com.liangrui.QuotaGlance]`; the
host additionally contains `com.apple.security.network.client = true`.

- [ ] **Step 3: Add minimal compileable entry points**

Host:

```swift
import SwiftUI
import QuotaGlanceCore

@main
struct QuotaGlanceApp: App {
    var body: some Scene {
        MenuBarExtra("QuotaGlance", systemImage: "gauge.with.dots.needle.50percent") {
            Text("QuotaGlance")
                .padding()
        }
        .menuBarExtraStyle(.window)

        Settings { Text("Settings").padding() }
    }
}
```

Widget:

```swift
import SwiftUI
import WidgetKit

@main
struct QuotaGlanceWidgetBundle: WidgetBundle {
    var body: some Widget { QuotaGlanceWidget() }
}
```

The minimal widget uses `StaticConfiguration`, a placeholder timeline, and all
three supported families before App Intent configuration is added.

- [ ] **Step 4: Generate and inspect the project**

Run: `xcodegen generate && find QuotaGlance.xcodeproj -maxdepth 3 -type f -print`

Expected: `QuotaGlance.xcodeproj/project.pbxproj` exists and references both
targets, the local package, and the embedded extension.

- [ ] **Step 5: Re-run package tests and commit**

Run: `swift test`

Expected: PASS even though full Xcode is still absent.

```bash
git add project.yml QuotaGlance.xcodeproj App Widget
git commit -m "build: scaffold macOS app and widget targets"
```

### Task 8: Build Host App State And Account Management

**Prerequisite:** Install Xcode 26.6 from the Mac App Store, launch it once to
finish components, select it with
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`, accept the
license, and configure a development team capable of the App Group entitlement.

**Files:**
- Create: `App/AppModel.swift`
- Create: `App/Settings/SettingsView.swift`
- Create: `App/Settings/AccountEditorView.swift`
- Modify: `App/QuotaGlanceApp.swift`
- Create: `Tests/QuotaGlanceCoreTests/AccountValidationTests.swift`

- [ ] **Step 1: Verify Xcode and signing prerequisites**

Run:

```bash
xcodebuild -version
xcodebuild -project QuotaGlance.xcodeproj -list
security find-identity -v -p codesigning
```

Expected: Xcode 26.6, both schemes listed, and at least one valid Apple
Development identity or a confirmed Sign to Run Locally path that preserves
the App Group entitlement.

- [ ] **Step 2: Write failing account-validation tests**

Test trimmed non-empty display names, maximum five accounts, duplicate names,
non-negative Decimal thresholds, and validation failure preserving draft data.

- [ ] **Step 3: Implement `AppModel` and Settings UI**

`@MainActor @Observable AppModel` loads accounts/preferences, constructs the
real Keychain/provider/refresh services, starts immediate and scheduled refresh,
exposes add/update/delete operations, and never publishes key strings.

`AccountEditorView` uses `SecureField`, validates through the provider before
committing metadata and Keychain, and keeps the draft intact on error.
`SettingsView` uses a list of at most five accounts, refresh interval picker,
launch-at-login toggle, notification status, delete confirmation, and native
toolbar add/edit controls.

- [ ] **Step 4: Run tests and build the app target**

Run:

```bash
swift test
xcodebuild -project QuotaGlance.xcodeproj -scheme QuotaGlance -configuration Debug build
```

Expected: tests PASS and `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add App Tests/QuotaGlanceCoreTests/AccountValidationTests.swift
git commit -m "feat: add account management and app state"
```

### Task 9: Build The Balance-Led Menu Bar Dashboard

**Files:**
- Create: `App/MenuBar/MenuBarDashboardView.swift`
- Create: `App/MenuBar/UsageChartView.swift`
- Modify: `App/QuotaGlanceApp.swift`
- Create: `Tests/QuotaGlanceCoreTests/DashboardPresentationTests.swift`

- [ ] **Step 1: Write failing presentation-model tests**

Test aggregate/account selection, healthy/partial/stale labels, seven stable
chart buckets, and currency formatting that keeps Decimal precision.

- [ ] **Step 2: Implement presentation mapping and run tests**

Run: `swift test --filter DashboardPresentationTests`

Expected before implementation: FAIL. Expected after implementation: PASS.

- [ ] **Step 3: Implement the approved panel**

Build a fixed-width, layout-stable panel with account picker, large remaining
balance, today/request metrics, seven-day bars, attention rows, freshness text,
manual refresh icon button with tooltip, Settings link, progress state, empty
state, and actionable error state. Use semantic system colors and no gradients.
The selected-account view also shows quota limit/used and a compact model usage
table when those optional fields exist. The longest account or model name must
truncate without resizing the panel.

- [ ] **Step 4: Build and visually inspect light/dark previews**

Run:

```bash
xcodebuild -project QuotaGlance.xcodeproj -scheme QuotaGlance -configuration Debug build
```

Expected: `** BUILD SUCCEEDED **`; SwiftUI previews render healthy, partial,
stale, and empty fixtures in light and dark appearance.

- [ ] **Step 5: Commit**

```bash
git add App/MenuBar App/QuotaGlanceApp.swift Tests/QuotaGlanceCoreTests/DashboardPresentationTests.swift
git commit -m "feat: add balance led menu bar dashboard"
```

### Task 10: Implement Configurable Small Medium And Large Widgets

**Files:**
- Create: `Widget/AccountSelectionIntent.swift`
- Modify: `Widget/QuotaGlanceWidget.swift`
- Create: `Widget/WidgetViews.swift`
- Create: `Tests/QuotaGlanceCoreTests/WidgetPresentationTests.swift`

- [ ] **Step 1: Write failing widget entry tests**

Test aggregate selection, valid account selection, deleted account, stale
snapshot, and no snapshot. Expected entries must never fabricate zero money.

- [ ] **Step 2: Implement account App Intent and timeline provider**

`AccountEntity` contains local UUID and display name only. Its query reads the
shared snapshot. `WidgetConfigurationIntent` has an optional account so nil
means All Accounts. `AppIntentTimelineProvider` reads
`quota-snapshot-v1.json`, produces a neutral placeholder when absent, and asks
for a conservative future refresh without calling the network.

- [ ] **Step 3: Implement all three stable widget families**

- Small: remaining, today, freshness.
- Medium: remaining, today, requests, seven bars.
- Large: aggregate metrics, seven bars, and up to five status rows.

Use `containerBackground(for:.widget)`, system typography, semantic status
colors, fixed chart dimensions, `widgetURL` deep links, and no nested cards.

- [ ] **Step 4: Run tests and build widget scheme**

Run:

```bash
swift test --filter WidgetPresentationTests
xcodebuild -project QuotaGlance.xcodeproj -scheme QuotaGlanceWidget -configuration Debug build
```

Expected: tests PASS and `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Widget Tests/QuotaGlanceCoreTests/WidgetPresentationTests.swift
git commit -m "feat: add configurable QuotaGlance widgets"
```

### Task 11: Wire Notifications Launch At Login And Widget Reloads

**Files:**
- Create: `App/Services/NotificationService.swift`
- Create: `App/Services/LaunchAtLoginService.swift`
- Modify: `App/AppModel.swift`
- Modify: `App/QuotaGlanceApp.swift`
- Create: `Tests/QuotaGlanceCoreTests/DeepLinkRouterTests.swift`

- [ ] **Step 1: Write failing deep-link and refresh-event tests**

Test `quotaglance://account/<uuid>` routing, unknown/deleted account fallback,
and that a successful/partial refresh emits one widget-reload event while an
all-failed no-change refresh does not overwrite the shared snapshot.

- [ ] **Step 2: Implement system service wrappers**

`NotificationService` requests authorization only when a threshold becomes
enabled and sends account-specific local notifications for `.notify` events.
`LaunchAtLoginService` wraps `SMAppService.mainApp` and reconciles UI state with
the system status. `AppModel` schedules the selected interval, persists alert
episode mutations, writes snapshots, and calls
`WidgetCenter.shared.reloadAllTimelines()` after writes.

- [ ] **Step 3: Implement deep-link selection**

Parse only the `quotaglance` scheme and `account` host, validate UUIDs against
known accounts, update selected account, and activate the app. Invalid URLs do
not crash or change selection.

- [ ] **Step 4: Run tests and app build**

Run: `swift test && xcodebuild -project QuotaGlance.xcodeproj -scheme QuotaGlance -configuration Debug build`

Expected: tests PASS and `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add App Tests/QuotaGlanceCoreTests/DeepLinkRouterTests.swift
git commit -m "feat: integrate macOS system services"
```

### Task 12: Install Locally And Prove Desktop Widget Delivery

**Files:**
- Create: `scripts/install-local.sh`
- Create: `scripts/verify-no-secret.sh`
- Create: `README.md`
- Modify: `.gitignore`

- [ ] **Step 1: Write the validated local installer**

The script uses `set -euo pipefail`, resolves its repository root, generates the
project, builds Release into a repository-local DerivedData path, validates the
built bundle ID and embedded widget before installation, creates
`~/Applications`, moves an existing matching QuotaGlance bundle to a timestamped
backup, copies with `ditto`, launches with `open`, and verifies the widget
extension with `pluginkit`. It must refuse to replace any destination whose
bundle ID is not `com.liangrui.QuotaGlance`.

- [ ] **Step 2: Document local setup**

`README.md` includes exact steps for full Xcode, signing team/App Group,
`xcodegen generate`, `swift test`, installer execution, adding the widget from
the macOS widget gallery, entering keys manually in the secure editor, and
troubleshooting stale WidgetKit registration. It explicitly says not to put
keys in `.env` inside the repository.

- [ ] **Step 3: Run all automated verification**

Run:

```bash
swift test
xcodegen generate
xcodebuild -project QuotaGlance.xcodeproj -scheme QuotaGlance -configuration Release build
git diff --check
```

Expected: all tests PASS, Release build succeeds, and no whitespace errors.

- [ ] **Step 4: Install and verify bundle/extension registration**

Run:

```bash
./scripts/install-local.sh
codesign -d --entitlements :- "$HOME/Applications/QuotaGlance.app" 2>&1
pluginkit -m -A -D | rg 'com\.liangrui\.QuotaGlance\.Widget'
```

Expected: installed app launches, signatures show the App Group entitlement,
and `pluginkit` lists the WidgetKit extension.

- [ ] **Step 5: Verify live behavior on the desktop**

Manually add two API Info accounts in Settings, confirm aggregate and
per-account values, perform a manual refresh, add all three widget sizes from
the widget gallery, configure aggregate and account-specific variants, and
capture desktop screenshots proving nonblank live data with visible freshness.
Temporarily disconnect networking and confirm the widget retains values with a
stale state. Test one threshold without exposing the key.

- [ ] **Step 6: Scan for secrets**

Create `scripts/verify-no-secret.sh`. It must require `LAOGE_KEY`, write that
value without a newline to a mode-600 file inside a `mktemp -d` directory,
remove the directory with a trap, and use pattern-file modes so the key does not
appear in command arguments or output:

```bash
git grep -q -F -f "$secret_pattern_file" -- . && {
  echo "Secret bytes found in tracked files" >&2
  exit 1
}
rg -a -q -F -f "$secret_pattern_file" "$HOME/Applications/QuotaGlance.app" && {
  echo "Secret bytes found in installed app" >&2
  exit 1
}
echo "No configured API key bytes found"
```

Run: `./scripts/verify-no-secret.sh`

Expected: `No configured API key bytes found`. The key itself is never printed.

- [ ] **Step 7: Commit delivery files**

```bash
git add .gitignore README.md scripts/install-local.sh scripts/verify-no-secret.sh
git commit -m "docs: add local install and widget verification"
```

## Completion Gate

Do not call the project complete based only on `swift test`, an Xcode build, a
SwiftUI preview, or `pluginkit`. Completion requires all acceptance criteria in
`docs/superpowers/specs/2026-07-22-quota-glance-phase-one-design.md`, including
an installed host app, actual widget-gallery discovery, a widget visibly added
to the user's desktop, live API Info data, stale-state behavior, and secret
scans.
