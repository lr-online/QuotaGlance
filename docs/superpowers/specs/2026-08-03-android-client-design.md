# Android Client Design

## Goal

Deliver a native Android client that preserves QuotaGlance's local-first
credential model and executes the existing provider, aggregation and alert
contracts without changing the macOS or HarmonyOS implementations.

## Decision

The Android app is a Kotlin/Jetpack Compose client. API keys stay on-device in
an Android Keystore-backed encrypted repository; provider calls go directly
from the device. A backend is explicitly out of scope because it would change
the product's key-custody and zero-telemetry guarantees.

Kotlin is a third implementation of the shared domain semantics. `Contracts/`
remains authoritative. The Android provider engine loads synced `spec.json`
assets, executes the same closed spec schema, and replays the provider request
fixtures. Kotlin `BigDecimal` is used for monetary and threshold arithmetic;
all persisted/fixture money keeps the contract canonical decimal string.

## Modules

`Platforms/Android/app` contains four deep modules:

1. `core` owns domain models, exact decimal helpers, the spec engine,
   `ProviderRegistry`, aggregation and alert evaluation. Its seams are a
   `RawHttpClient`, `Clock`, and `ProviderSpecSource`.
2. `data` owns account/preferences, encrypted credentials and snapshot cache.
   Account deletion is a single orchestration operation that removes all three
   records.
3. `refresh` owns foreground and WorkManager scheduling. It refreshes enabled
   accounts independently, preserves the last successful snapshot on failure,
   then evaluates alert episodes and requests widget refresh.
4. `ui` owns Compose screens, a Glance widget, notification permission/UI and
   Android intent deep links. It consumes presentation state rather than
   executing provider logic.

## Product Behaviour

The app supports the six append-only `ProviderID` values, up to 20 ordered
accounts, add/edit/delete/re-detect, enablement, duplicate trimmed-name
validation, replacement keys, threshold settings, 1/5/15/30/60-minute refresh
preferences, English/Chinese/system language, manual/startup refresh, exact
low-balance notification episodes, account/all-account dashboard views, and
`quotaglance://all` / `quotaglance://account/<uuid>` routes.

The Glance widget offers all accounts, one account, or application-default
selection. Deleted selections fall back to all accounts. Android's launcher
has no direct equivalent to macOS launch-at-login; normal cold-start and
WorkManager refresh replace that host-specific preference.

## Contract and Build Discipline

`scripts/sync-specs-to-android.sh` copies provider specs to production assets;
`scripts/sync-contracts-to-android.sh` copies all provider, aggregation and
alert fixtures to test resources. `scripts/verify-android-parity.sh` checks
the Kotlin provider-id set, synced specs, and fixture completeness. Android
JVM tests replay every fixture and assert status, request order, URL and
header patterns.

The app compiles with JDK 17, Android Gradle Plugin and compile SDK 35 on
Linux. GitHub Actions runs parity verification, sync, JVM tests, lint and
`assembleRelease`, then publishes the universal APK as a workflow artifact;
the release workflow additionally attaches it to version-tag GitHub releases.

## Deliberate Platform Differences

Android uses WorkManager's operating-system scheduling rather than pretending
to guarantee the macOS timer interval. It records the selected interval and
uses it for foreground scheduling; periodic background work uses the platform
minimum and network/battery constraints. This difference, its user-visible
effect, and device-test coverage will be recorded in the capability matrix.

