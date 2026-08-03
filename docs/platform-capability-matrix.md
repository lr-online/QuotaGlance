# Platform Capability Matrix

Last updated: 2026-08-03

QuotaGlance shares Provider, Aggregation, and Alerts contract semantics across Swift and
ArkTS. Product entry points, lifecycle integration, persistence detail, and presentation
remain platform-specific. This matrix records those differences instead of treating
contract parity as complete product parity.

| Capability | macOS / Swift | HarmonyOS / ArkTS | User-visible difference | Coverage | Follow-up |
| --- | --- | --- | --- | --- | --- |
| Provider and spec contracts | Complete ProviderID set; specs loaded by `QuotaGlanceCore` | Same ProviderID set; synced specs loaded by the ArkTS engine | No intended provider parsing difference | Shared provider fixtures, Swift contract tests, ArkTS `CONTRACT_CASES`, `verify-provider-parity.sh` | Keep shared behavior contract-first and mirrored |
| Aggregation semantics | `SnapshotAggregator` is the production implementation | ArkTS mirror consumes the same aggregation fixtures | No intended aggregation difference | `AggregationContractTests` and HarmonyOS aggregation contract suite | Keep fixture changes dual-platform |
| Alert evaluation semantics | `AlertEvaluator` drives notification episodes | ArkTS mirror consumes the same alert fixtures | Threshold evaluation is intended to match at the engine level | `AlertContractTests` and HarmonyOS alerts contract suite | Keep fixture changes dual-platform |
| Account lifecycle | Add, edit, delete, enable/disable, sort, duplicate-name validation, and replacement-key detection | Add/delete and basic enablement are available; account editing, duplicate-name validation, and replacement-key detection are missing | HarmonyOS users must recreate an account to replace or re-detect a key; duplicate display names can be accepted | Swift `AccountValidationTests`, storage tests, and account editor flows; HarmonyOS page tests are manual | Add an ArkTS edit flow and validation parity tests |
| Credential storage | Keychain item per account UUID; replacement keys are detected before persistence | Asset Store alias per account | Both are secure platform stores; replacement UX differs | Swift Keychain query/storage tests; HarmonyOS device verification | Preserve aliases and add HarmonyOS replacement migration tests |
| Refresh interval and scheduling | User-selectable 1/5/15/30/60 minutes plus startup refresh | Fixed background/foreground refresh behavior | HarmonyOS users cannot choose the refresh cadence | Swift scheduler behavior is exercised through `AppModel` manually; provider refresh has unit coverage | Add a HarmonyOS preference or document platform scheduler limits in-product |
| Snapshot failure state | Persists and presents failure reason, `unavailable`, `capturedAt`, and `lastSuccessAt`; stale data remains visible | Does not currently preserve or expose the full failure/freshness metadata set | HarmonyOS can show less precise freshness and recovery information | Swift refresh, storage, dashboard, menu bar, and widget tests; HarmonyOS manual verification | Extend the ArkTS snapshot model without changing `WidgetSnapshotEnvelope` |
| Notifications and episodes | Displays authorization state, requests permission when a threshold is first configured, and clears episodes for disabled accounts | Authorization presentation and request timing differ; disabled-account episode cleanup is missing | Notification prompts and recovery behavior are not identical | Swift `AlertEvaluatorTests`, alert fixtures, notification manual checks; HarmonyOS alert contract tests | Add permission-state UI and disabled-account cleanup on HarmonyOS |
| External deep links | Supports `quotaglance://all` and account UUID routes; deleted accounts fall back to All Accounts and open the dashboard | External route coverage is incomplete | Links and deleted-account recovery are more predictable on macOS | Swift `DeepLinkRouterTests`; HarmonyOS routing is manually checked | Define and test the HarmonyOS equivalent external route contract |
| Quick-view default selection | Desktop Widget and Notification Center Widget can use All Accounts, an explicit account, or the app default; deleted selections fall back | Service-card default-account selection and deletion fallback are incomplete | HarmonyOS cards can retain less useful selection state | Swift NCWidget policy/resolver and Widget presentation tests; HarmonyOS card manual checks | Add persisted default selection and deletion fallback to the ArkTS card |
| Localization | English/Chinese/system language across app, dashboard, settings, notifications, and Widgets | Main app is localized, but some service-card strings remain hard-coded Chinese | Some HarmonyOS card text ignores the selected language | Swift `AppLanguageTests`; HarmonyOS string parity and manual card checks | Move remaining card copy into HarmonyOS resources |
| Low-balance presentation threshold | macOS presentation and alert evaluation use `remaining <= threshold` | One HarmonyOS card path still renders low balance with `< threshold` | At exactly the threshold, the card can disagree with the app/contract state | Shared alert fixtures cover engine semantics; the HarmonyOS card comparison is not fixture-driven | Change the card presentation comparison to `<=` and add a boundary UI test |
| Main and quick-view surfaces | Menu bar remains primary; independent dashboard, desktop Widget, and Notification Center Widget are available | Main pages and service card are available | Each platform uses its native quick-view hosts | Swift presentation tests plus manual macOS 12/14 checks; HarmonyOS page/card manual checks | Maintain equivalent outcomes rather than identical host UI |
| Appearance | System/Light/Dark applies to menu bar, dashboard, and Settings; Widgets follow macOS | App language/theme capabilities are platform-owned | Widget appearance is intentionally not overridden by the app theme | Swift preference migration and round-trip tests plus manual appearance checks | Keep Widget behavior system-owned |
| Provider overview | Swift-only `ProviderOverviewPresenter` groups accounts with exact `Decimal` sums and strict freshness/completeness rules | HarmonyOS computes its page overview independently | Ordering, request-share eligibility, stale handling, and numeric precision may differ | Swift Provider overview tests; HarmonyOS page tests are independent | Do not create a shared contract until both products require identical presentation semantics |
| Screensaver / ambient mode | Not available | HarmonyOS provides a screensaver mode | macOS has no ambient full-screen view | HarmonyOS manual verification | Revisit only as a separate macOS product feature |
| Build and quality gates | `swift test`, five ScriptTests, parity verification, macOS 12/14 builds | Contract sync, parity verification, and HAP build; ohosTest requires device/emulator | Automated UI/device confidence differs | GitHub `ci.yml` and `harmonyos.yml` | Add device-side ohosTest CI when infrastructure permits |

## Interpretation

- A row marked as different is not permission for shared engine semantics to drift.
- Any Provider, Aggregation, or Alerts behavior change still requires Contracts-first work
  and matching Swift/ArkTS implementation and tests.
- Presentation-only additions may stay platform-specific when they do not alter shared
  domain or contract behavior. Their visible differences must remain recorded here.

## Android Baseline

Android is a third native client, not a wrapper around either existing host. The table
below records the required new-platform capability audit for `Android/`. “Implemented”
means the current Kotlin source and listed automated coverage support the behavior;
device-only items remain an explicit manual-verification gap rather than an implied
equivalence claim.

| Capability | Android status | Evidence / user-visible difference |
| --- | --- | --- |
| Provider / spec contract | Implemented | Kotlin spec engine loads synced assets; every provider, aggregation, and alert fixture is exercised by JVM tests and `verify-android-parity.sh`. |
| Accounts and credentials | Implemented | Ordered 20-account DataStore metadata, trimmed duplicate-name checks, provider-change key requirement, Keystore-backed key vault, detect-before-save, and delete cascade. |
| Preferences | Implemented / platform N/A | Refresh interval, language, and default quick view persist. Android has no launch-at-login; launch and foreground resume are its equivalent entry points. |
| Refresh and snapshots | Implemented | Manual, launch, foreground interval, and WorkManager refresh; failure retains old usage and records stale/unavailable state, timestamps, and reason. |
| Aggregation and metric semantics | Implemented | Kotlin mirrors currency grouping, all-or-nothing today metrics, overflow behavior, disabled filtering, and seven-day output from shared fixtures. |
| Account-level details | Implemented | Balances/breakdown, limit, spend, quota windows, counters, daily/model usage, provider status, unavailable reason, and update time are rendered when supplied. |
| Alerts and local notifications | Implemented | Shared episode fixtures, persisted episodes, permission status/action, and Android notification dispatch. Device permission dialogs require manual verification. |
| Main and quick-view surfaces | Implemented | Compose all-account/account detail states and Glance widget support All, Default, and explicit account with deleted selection fallback. |
| Editing and settings | Implemented | Provider/name/key/enabled/threshold editing; interval, language, notification, and default-quick-view preferences; English/Chinese validation errors. |
| Deep links and quick-view selection | Implemented | `quotaglance://all` and `quotaglance://account/<uuid>` parse into a route; missing accounts resolve to All Accounts. |
| Localization and formatting | Implemented | System/English/Chinese main UI and widget labels; monetary values preserve canonical amount/currency form. |
| Build and quality gates | Implemented with device-test gap | `android.yml` syncs contracts, runs parity/JVM/lint, builds both APKs, uploads artifacts, and attaches tag-release APKs. Emulator/physical-device checks for Glance, notification, deep links, WorkManager, and encrypted storage remain manual until device CI is added. |

Android background refresh is intentionally different from macOS' application timer:
the selected 1/5/15/30/60 minute interval runs only while an Activity is visible.
WorkManager background requests require a network and non-low battery, and Android can
defer periodic work beyond its 15-minute minimum. The app states this in Settings so a
short interval is not presented as a guaranteed background service level.
