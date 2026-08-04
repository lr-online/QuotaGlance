# Android HarmonyOS Alignment Design

## Goal

Bring the Android client closer to the HarmonyOS client while preserving Android
platform conventions and all shared provider, aggregation, alert, storage, and
widget semantics. The resulting app uses the HarmonyOS information hierarchy:
a compact top bar, provider-level overview, account tabs, and separate
management/settings surfaces.

## Accepted Decisions

- Android uses the HarmonyOS-style top-level structure rather than retaining
  the existing three-section navigation as the primary interaction model.
- On every activity launch, Android immediately requests every declared runtime
  permission that is not granted. At present this is only Android 13+
  `POST_NOTIFICATIONS`; the request does not depend on an account existing.
- The app exposes persisted `System`, `Light`, and `Dark` theme choices.
- Android-specific work does not alter `Contracts/`, provider specs, shared
  aggregation semantics, or HarmonyOS code.

## UI Structure

`QuotaGlanceApp` becomes a state-driven shell with these surfaces:

1. **Overview**: a fixed application bar with refresh, theme, language, and
   account-management actions. When accounts exist, it shows a provider
   overview panel followed by a fixed account tab bar and the selected account
   detail. When no accounts exist, it shows a focused onboarding state and an
   add-account action.
2. **Provider overview**: reads cached account snapshots only. It displays
   aggregate today cost/request metrics, partial-data status, and one compact
   row per provider. A row reports its enabled state, balance or quota, stale
   state, and a today-request share when that metric is available.
3. **Account detail**: retains every currently rendered snapshot field:
   balance and breakdown, spending limit, spending windows, counters, daily
   usage, model usage, provider status, unavailable reason, and timestamps.
   Account tabs are stable by account ID and disabled accounts are visually
   dimmed.
4. **Account management**: moves the add/edit form and the account list into a
   dedicated surface. Existing validation, profile detection, credential
   storage, enablement, threshold editing, and deletion behavior remain
   unchanged.
5. **Settings**: contains refresh cadence, language, theme, default widget
   quick view, notification status, and Android background-scheduling context.

Material 3 components, the existing teal/amber/error semantic colors, compact
8dp-or-smaller framed surfaces, and icon actions with content descriptions are
used throughout. No provider-specific UI logic is introduced.

## Architecture and Data Flow

- `MainActivity` owns the Activity Result permission launcher. Its launch path
  checks the SDK and notification grant, asks immediately when needed, and
  pushes the result into Compose state. It still refreshes and starts/stops the
  foreground scheduler on the existing lifecycle boundaries.
- `AppThemeMode` joins `AppLanguage` and `RefreshInterval` in
  `AppPreferences`. `DataStorePreferencesRepository` reads/writes its stable
  raw value; `QuotaGlanceTheme` consumes it instead of always following the
  system.
- A pure `ProviderOverviewPresenter` in `ui/Presentation.kt` groups ordered
  accounts and cached snapshots by `ProviderId`. It derives visible values from
  the existing domain models and does not reimplement `SnapshotAggregator`.
  The global header continues to use `DashboardPresenter` and
  `SnapshotAggregator`, retaining their stale, partial, currency, and overflow
  behavior.
- `QuotaGlanceViewModel` remains the mutation and refresh seam. It exposes the
  selected surface, account tab selection, and persisted preference updates;
  Compose owns only transient menus and in-progress text-field values.

## Error Handling and Accessibility

- Existing provider and validation tokens continue through `localizedError`.
  A failed refresh keeps stale snapshots visible, as it does today.
- A declined notification permission is reflected in Settings and blocks only
  delivery, never refresh or alert-episode persistence.
- Toolbar actions have content descriptions and disabled/busy states. Provider
  rows, account tabs, and management commands retain sufficiently distinct
  textual labels alongside semantic colors.

## Tests and Verification

Before production changes, add focused JVM tests that fail for the desired
behavior:

- permission-request eligibility for pre-33, granted, and denied states;
- app-theme raw-value fallback and preference persistence;
- provider overview ordering, disabled/no-data/stale states, totals, and
  request-share calculation;
- presentation selection fallback when an account disappears.

Then run the Android unit tests, lint, debug/release assembly, Android parity,
and `git diff --check`. Device/emulator verification covers first-launch
permission prompting, denial/grant state, theme persistence, tab switching,
account management, refresh, and low-balance notification delivery.

## Non-Goals

- Replacing Android's Glance widget or WorkManager policy.
- Adding unsupported Android runtime permissions.
- Altering provider contracts, credentials, shared decimal behavior, or
  HarmonyOS implementation.
