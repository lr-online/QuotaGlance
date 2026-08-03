# AGENTS.md - Android client

This directory is the native Android client. Read the repository-root `AGENTS.md`
first: it defines provider IDs, `Contracts/` ownership, and the cross-platform
invariants. Do not modify `App/`, `Widget/`, `NCWidget/`, `NCIntents/`, or
`HarmonyOS/` while working on Android-only behavior.

## Architecture

- `app/src/main/java/.../core/` mirrors shared domain semantics in Kotlin:
  provider spec evaluation, exact decimal money, aggregation, and alerts.
- `data/` owns DataStore account/snapshot/preferences state and the Keystore-backed
  credential vault. API keys must never enter DataStore, assets, logs, fixtures,
  or exception messages.
- `refresh/` owns OkHttp transport, provider registry, account-save detection,
  foreground refresh, WorkManager, notifications, and widget invalidation.
- `ui/` owns Compose presentation and deep-link parsing. `widget/` owns Glance and
  its per-widget quick-view selection.

Keep platform work behind these modules. Provider behavior belongs in
`Contracts/` and the three platform engines, never in a Kotlin provider-specific
adapter. Android may only add a named parse strategy when the shared schema's
documented escape hatch permits it.

## Contract discipline

`Contracts/` is authoritative. After changing any provider, aggregation, or
alert contract, run all of the following from the repository root:

```bash
bash scripts/sync-specs-to-core.sh
bash scripts/sync-specs-to-harmonyos.sh
bash scripts/sync-contracts-to-harmonyos.sh
bash scripts/sync-specs-to-android.sh
bash scripts/sync-contracts-to-android.sh
bash scripts/verify-provider-parity.sh
bash scripts/verify-android-parity.sh
```

The two Android sync targets are generated copies:

- `app/src/main/assets/providerspecs/` is runtime input.
- `app/src/test/resources/contracts/` is JVM test input.

Do not edit either directly. New provider IDs are append-only and require the
Swift, ArkTS, and Kotlin declarations plus Android fixture registration.

## Build and validation

The Android app uses JDK 17, AGP 8.8.2, Kotlin 2.0.21, compile/target SDK 35,
and min SDK 26. Set `sdk.dir` in ignored `Android/local.properties`, or export
`ANDROID_HOME` / `ANDROID_SDK_ROOT`.

```bash
cd Android
./gradlew --no-daemon :app:testDebugUnitTest :app:lint :app:assembleDebug :app:assembleRelease
```

Required final checks are the two parity scripts, the Gradle command above,
`git diff --check`, and `apksigner verify --verbose` on the release APK. CI in
`.github/workflows/android.yml` repeats the contract sync, parity, tests, lint,
and both APK builds. It uploads debug/release artifacts for every PR and adds
the universal release APK plus SHA-256 to a `v*` GitHub Release.

The open-source release APK is signed with the Android debug certificate so it
can be installed without a private secret. It is appropriate for GitHub
distribution and testing, not Play Store or a long-lived production signing
identity. A production signing migration must use a protected release keystore
and increment `versionCode`.

## Android platform differences

1. Android has no launch-at-login equivalent. The app refreshes on launch and
   foreground resume; a visible Activity runs the user-selected 1/5/15/30/60
   minute cadence. Background work is WorkManager-owned, requires a network and
   a non-low battery, and is never promised more often than Android's 15-minute
   periodic minimum.
2. Glance is the quick-view equivalent of macOS desktop/Notification Center
   widgets. It supports All, app-default, and explicit-account choices; deleted
   accounts degrade to All Accounts.
3. JVM tests cover contracts and app seams. Notification prompts, WorkManager
   scheduling, Glance rendering, deep links, and encrypted storage require a
   physical device or compatible emulator manual verification. Record that
   verification in the PR until device CI exists.

## Platform support baseline

| Capability | Status | Android evidence / visible downgrade |
| --- | --- | --- |
| Provider/spec contracts | Implemented | Kotlin spec engine and all synced provider fixtures; `verify-android-parity.sh` and JVM contract tests. |
| Account and credential lifecycle | Implemented | Ordered DataStore accounts, 20-account/name/key validation, Keystore vault, detect-before-save, delete cascade, enablement and threshold editing. |
| Preferences | Implemented / N/A | Refresh interval, System/English/Chinese, default quick view. Launch-at-login is platform-inapplicable; see difference 1. |
| Refresh and snapshot persistence | Implemented | Manual/launch/foreground refresh, WorkManager, per-account isolation, old-data stale retention, timestamps and failure reason persistence. |
| Aggregation and metrics | Implemented | Shared aggregation fixtures and exact `BigDecimal` sums/overflow checks. |
| Account detail | Implemented | Balances/breakdown, limits, spend, quota windows, counters, daily/model usage, status, unavailable reason, and update time. |
| Alerts and notifications | Implemented | Shared alert fixtures, persisted episodes, permission status/action, and Android local notifications. |
| Main and quick-view surfaces | Implemented | Compose overview/details plus Glance widget with deleted-selection fallback. |
| Editing and settings | Implemented | Provider/name/key/enabled/threshold, interval/language/notification/default quick view; validation errors are localized. |
| Deep links and selection parsing | Implemented | `quotaglance://all` and `quotaglance://account/<uuid>`; stale selection resolves to All. |
| Localization and formatting | Implemented | System/English/Chinese UI and widget copy; money uses canonical currency strings. |
| Engineering quality gate | Implemented with device-test gap | CI covers sync/parity/JVM/lint/APK. Device-only behavior remains a documented manual verification item. |
