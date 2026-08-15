# Android HarmonyOS Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (recommended) or superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the Android client with the selected HarmonyOS information hierarchy and automatically request its declared runtime permission at app launch.

**Architecture:** Keep provider, aggregation, alert, refresh, credential, and widget seams intact. Add pure presentation/policy functions for notification permission, theme decoding, and provider summaries; then make the Compose shell render a HarmonyOS-style overview, account tabs, and separate management/settings surfaces from the existing `QuotaGlanceViewModel` state.

**Tech Stack:** Kotlin 2.0.21, Jetpack Compose Material 3, DataStore Preferences, Activity Result API, Glance, JUnit, Gradle/AGP 8.8.2.

---

## File Map

- Modify `Platforms/Android/app/src/main/java/com/liangrui/quotaglance/MainActivity.kt`: launch-time notification permission request and result state.
- Modify `Platforms/Android/app/src/main/java/com/liangrui/quotaglance/data/PreferencesRepository.kt`: persisted `AppThemeMode` and preference codec.
- Modify `Platforms/Android/app/src/main/java/com/liangrui/quotaglance/ui/Theme.kt`: light/dark/system selection.
- Create `Platforms/Android/app/src/main/java/com/liangrui/quotaglance/ui/PermissionPolicy.kt`: pure SDK/grant decision seam.
- Create `Platforms/Android/app/src/main/java/com/liangrui/quotaglance/ui/OverviewPresentation.kt`: provider summary model and presenter.
- Modify `Platforms/Android/app/src/main/java/com/liangrui/quotaglance/ui/Presentation.kt`: account-selection helpers used by the overview and tab detail.
- Modify `Platforms/Android/app/src/main/java/com/liangrui/quotaglance/ui/QuotaGlanceApp.kt`: HarmonyOS-style app bar, overview panel, account tabs, onboarding, management/settings entry and localized copy.
- Modify `Platforms/Android/app/src/main/java/com/liangrui/quotaglance/widget/QuotaGlanceWidget.kt`: pass the persisted theme mode to Compose previews/configuration.
- Modify `Platforms/Android/app/build.gradle.kts`: add the Material icon dependency used by accessible toolbar actions.
- Create `Platforms/Android/app/src/test/java/com/liangrui/quotaglance/ui/PermissionPolicyTest.kt`: permission decision tests.
- Modify `Platforms/Android/app/src/test/java/com/liangrui/quotaglance/data/StorageCodecTest.kt`: theme raw-value round-trip/fallback tests.
- Create `Platforms/Android/app/src/test/java/com/liangrui/quotaglance/ui/OverviewPresentationTest.kt`: provider grouping and status tests.
- Modify `Platforms/Android/app/src/test/java/com/liangrui/quotaglance/ui/PresentationContractTest.kt`: account-tab/deleted-route selection tests.

### Task 1: Automatic Permission and Theme Preference

**Files:** Create `PermissionPolicy.kt` and `PermissionPolicyTest.kt`; modify `MainActivity.kt`, `PreferencesRepository.kt`, `Theme.kt`, `StorageCodecTest.kt`, and `QuotaGlanceApp.kt` to pass the persisted theme mode into the app shell.

- [ ] **Step 1: Write the failing permission-policy tests.**

  Add a pure function with this intended contract:

  ```kotlin
  internal fun shouldRequestNotificationPermission(sdk: Int, granted: Boolean): Boolean =
      sdk >= 33 && !granted
  ```

  Test all three cases in `PermissionPolicyTest.kt`:

  ```kotlin
  @Test fun `pre Android 13 never requests`() = assertFalse(shouldRequestNotificationPermission(32, false))
  @Test fun `granted notification permission never requests`() = assertFalse(shouldRequestNotificationPermission(35, true))
  @Test fun `denied Android 13 permission requests`() = assertTrue(shouldRequestNotificationPermission(33, false))
  ```

- [ ] **Step 2: Run the focused test and verify it fails for the missing function.**

  Run `cd Platforms/Android && ./gradlew --no-daemon :app:testDebugUnitTest --tests com.liangrui.quotaglance.ui.PermissionPolicyTest`.
  Expected: compilation failure because `PermissionPolicy.kt` and the function do not exist.

- [ ] **Step 3: Implement the permission seam and launch request.**

  Add the function above. In `MainActivity.onCreate`, set the initial grant state, call `setContent`, then call a private `requestNotificationPermissionIfNeeded()` that checks `Build.VERSION.SDK_INT`, `ContextCompat.checkSelfPermission`, and the pure policy before launching `Manifest.permission.POST_NOTIFICATIONS`. Keep the existing Activity Result callback as the sole state update after the system dialog. Do not gate this call on account count or Settings navigation.

- [ ] **Step 4: Add theme preference tests before changing storage.**

  Add `AppThemeMode` with raw values `system`, `light`, and `dark`, and test its decoder in `StorageCodecTest`:

  ```kotlin
  @Test fun `unknown theme value falls back to system`() {
      assertEquals(AppThemeMode.System, AppThemeMode.fromRaw("unknown"))
  }

  @Test fun `theme raw values are stable`() {
      assertEquals(listOf("system", "light", "dark"), AppThemeMode.entries.map { it.raw })
  }
  ```

  Run `cd Platforms/Android && ./gradlew --no-daemon :app:testDebugUnitTest --tests com.liangrui.quotaglance.data.StorageCodecTest`; expected failure until the enum exists.

- [ ] **Step 5: Implement preference persistence and theme selection.**

  Add `themeMode: AppThemeMode = AppThemeMode.System` to `AppPreferences`; read/write a `stringPreferencesKey("themeMode")` in `DataStorePreferencesRepository`. Change `QuotaGlanceTheme` to accept `themeMode` and choose `isSystemInDarkTheme()` only for `System`, `DarkColors` for `Dark`, and `LightColors` for `Light`. Pass `state.preferences.themeMode` from the app shell and the current widget configuration. Keep the existing default color tokens.

- [ ] **Step 6: Run the focused tests and commit this task.**

  Run `cd Platforms/Android && ./gradlew --no-daemon :app:testDebugUnitTest --tests com.liangrui.quotaglance.ui.PermissionPolicyTest --tests com.liangrui.quotaglance.data.StorageCodecTest`.
  Expected: PASS. Commit with `git add Platforms/Android/app/src/main/java/com/liangrui/quotaglance/MainActivity.kt Platforms/Android/app/src/main/java/com/liangrui/quotaglance/data/PreferencesRepository.kt Platforms/Android/app/src/main/java/com/liangrui/quotaglance/ui/PermissionPolicy.kt Platforms/Android/app/src/main/java/com/liangrui/quotaglance/ui/Theme.kt Platforms/Android/app/src/test && git commit -m "feat(android): request notification permission and persist theme"`.

### Task 2: Provider Overview Presentation

**Files:** Create `OverviewPresentation.kt` and `OverviewPresentationTest.kt`; modify `Presentation.kt` only for shared account selection helpers.

- [ ] **Step 1: Write failing provider-summary tests.**

  Define the expected pure API:

  ```kotlin
  data class ProviderOverview(
      val provider: ProviderId,
      val displayName: String,
      val enabledAccountCount: Int,
      val balances: List<Money>,
      val todayCosts: List<Money>,
      val todayRequests: Long?,
      val quotaWindows: List<QuotaWindow>,
      val hasData: Boolean,
      val isStale: Boolean,
      val requestFraction: Double,
  )

  object ProviderOverviewPresenter {
      fun present(accounts: List<QuotaAccount>, snapshots: List<AccountSnapshot>): List<ProviderOverview>
  }
  ```

  Tests must cover: provider ordering follows first account `sortOrder`, disabled accounts remain visible but contribute no totals, same-currency balances are summed exactly, missing/stale snapshots set `hasData`/`isStale`, and request fractions sum to 1 only when at least one request count exists. Use `Money.fromString` and `BigDecimal`/`Long` fixtures instead of floating-point money assertions.

- [ ] **Step 2: Run `OverviewPresentationTest` and verify the missing presenter fails.**

  Run `cd Platforms/Android && ./gradlew --no-daemon :app:testDebugUnitTest --tests com.liangrui.quotaglance.ui.OverviewPresentationTest`.
  Expected: compilation failure for the missing model/presenter.

- [ ] **Step 3: Implement the minimal provider grouping.**

  Group accounts by `ProviderId` in sorted account order. For enabled accounts, read the matching snapshot, skip unavailable/stale values from fresh totals while retaining stale state, and sum `Money` by currency with `BigDecimal`. Use a local stable display-name map for the six existing `ProviderId` values; do not load provider specs or make network calls in this presenter. Derive a `QuotaWindow` list from the first available usage snapshot and calculate request fractions with `0.0` when no requests exist.

- [ ] **Step 4: Run the focused presenter tests and commit.**

  Run `cd Platforms/Android && ./gradlew --no-daemon :app:testDebugUnitTest --tests com.liangrui.quotaglance.ui.OverviewPresentationTest --tests com.liangrui.quotaglance.ui.PresentationContractTest`.
  Expected: PASS. Commit with `git add Platforms/Android/app/src/main/java/com/liangrui/quotaglance/ui/OverviewPresentation.kt Platforms/Android/app/src/main/java/com/liangrui/quotaglance/ui/Presentation.kt Platforms/Android/app/src/test/java/com/liangrui/quotaglance/ui && git commit -m "feat(android): add provider overview presentation"`.

### Task 3: HarmonyOS-Style Overview and Account Tabs

**Files:** Modify `QuotaGlanceApp.kt`, `Presentation.kt`, and `Theme.kt` call sites; modify `Platforms/Android/app/build.gradle.kts` for `androidx.compose.material:material-icons-extended`.

- [ ] **Step 1: Add the route-selection regression test before UI wiring.**

  Extend `PresentationContractTest` with assertions for a new pure helper:

  ```kotlin
  internal fun selectedAccountForRoute(route: AppRoute, accounts: List<QuotaAccount>): QuotaAccount?
  ```

  Assert that `selectedAccountForRoute(AppRoute.Account("one"), accounts)` returns the matching account, `selectedAccountForRoute(AppRoute.Account("deleted"), accounts)` returns null, and `selectedAccountForRoute(AppRoute.All, accounts)` returns the first enabled account or the first account when all are disabled. Run the test and confirm it fails before adding the helper.

- [ ] **Step 2: Implement the shell navigation state.**

  Keep `AppSection` for `Overview`, `Accounts`, and `Settings`, but remove the always-visible `TabRow`. The top app bar shows title/back action for management/settings and, on Overview, refresh, theme, language, manage-accounts, and settings actions. Use Material icons with content descriptions and `DropdownMenu` for theme/language. `viewModel.routeTo` remains the deep-link seam and always returns to Overview.

- [ ] **Step 3: Replace the overview body with the selected structure.**

  Render a single scrollable page with:

  ```kotlin
  val overview = DashboardPresenter.present(state.accounts, state.snapshots, now, AppRoute.All)
  val summaries = ProviderOverviewPresenter.present(state.accounts, state.snapshots)
  val selectedAccount = selectedAccountForRoute(state.route, state.accounts)
  ```

  Show HarmonyOS-style status/partial header, today's aggregate, provider rows with balance/quota/request-share/stale indicators, a horizontally scrollable account `TabRow`, then the selected account's full detail. Use a centered onboarding body with Add account when no accounts exist. Keep old snapshots visible for stale/unavailable accounts and preserve all existing `AccountDetail` fields.

- [ ] **Step 4: Run JVM presentation tests and compile the UI.**

  Run `cd Platforms/Android && ./gradlew --no-daemon :app:testDebugUnitTest :app:lintDebug`.
  Expected: all JVM tests and lint pass; no Compose compilation errors.

- [ ] **Step 5: Commit the overview shell.**

  Run `git diff --check`, then commit with `git add Platforms/Android/app/build.gradle.kts Platforms/Android/app/src/main/java/com/liangrui/quotaglance/ui && git commit -m "feat(android): align overview with HarmonyOS layout"`.

### Task 4: Account Management and Settings Surfaces

**Files:** Modify `QuotaGlanceApp.kt`, `QuotaGlanceViewModel.kt`, `PreferencesRepository.kt`, `Theme.kt`, and `QuotaGlanceWidget.kt`; extend `AppCopy` strings.

- [ ] **Step 1: Add interaction tests for existing mutation seams.**

  Extend `PresentationContractTest` to call `selectedAccountForRoute` for a live and deleted account. Extend the preference tests to assert that `AppPreferences(defaultQuickViewAccountId = null)` removes the stored choice through the repository test seam. Run the focused tests and confirm the new assertions fail before wiring the screens.

- [ ] **Step 2: Move the editor/list into a dedicated Accounts surface.**

  Preserve the existing `saveAccount`, `deleteAccount`, `setEnabled`, provider detection, replacement-key requirement, threshold parsing, and localized error tokens. Give the surface an app-bar back action, an explicit Add account button, a list sorted by `sortOrder`, and edit/delete/enable controls. On save/delete, keep the existing snapshot reload and deleted-default cleanup.

- [ ] **Step 3: Complete Settings with theme and permission state.**

  Add three theme chips/menu entries using `AppThemeMode.entries`, keep refresh interval/language/default quick-view controls, show the current notification grant, and retain the Android WorkManager 15-minute minimum explanation. The Settings request button remains as a recovery action after a denial, but launch-time requesting is the primary path.

- [ ] **Step 4: Use the persisted theme in Glance configuration.**

  Pass `preferences.themeMode` to `QuotaGlanceTheme` in `QuotaGlanceWidgetConfigurationActivity`; keep the actual Glance color surface stable because Glance does not consume the full Compose theme. Ensure deleted widget account selections still resolve to All through the existing route helper.

- [ ] **Step 5: Run the full JVM suite and commit.**

  Run `cd Platforms/Android && ./gradlew --no-daemon :app:testDebugUnitTest :app:lintDebug`.
  Expected: PASS. Commit with `git add Platforms/Android/app/src/main/java/com/liangrui/quotaglance/ui Platforms/Android/app/src/main/java/com/liangrui/quotaglance/data Platforms/Android/app/src/main/java/com/liangrui/quotaglance/widget && git commit -m "feat(android): complete account and settings surfaces"`.

### Task 5: Verification and Device Handoff

**Files:** Android source/tests only; no Contracts or HarmonyOS files.

- [ ] **Step 1: Run parity and all Android checks.**

  From the repository root run:

  ```bash
  bash scripts/verify-provider-parity.sh
  bash scripts/verify-android-parity.sh
  cd Platforms/Android
  ./gradlew --no-daemon :app:testDebugUnitTest :app:lint :app:assembleDebug :app:assembleRelease
  ```

  Expected: parity scripts, JVM tests, lint, debug APK, and release APK all succeed.

- [ ] **Step 2: Check packaging and source hygiene.**

  Run `git diff --check`; inspect `Platforms/Android/app/build/outputs/apk/release/*.apk` with `apksigner verify --verbose` when available; run `git status --short` and confirm no credentials, generated assets, or build outputs are tracked.

- [ ] **Step 3: Perform device/emulator checks.**

  Install the debug APK on Android 13+ with notifications disabled. Launch the app and confirm the system permission prompt appears before account setup; deny it and confirm Settings reports the denial; grant it from the recovery action and confirm the state updates. Add an account, refresh, switch account tabs, edit/delete an account, switch System/Light/Dark themes, configure the widget, and verify low-balance notification delivery/deep link.

- [ ] **Step 4: Record the verification result and make the delivery commit.**

  Record any unavailable device-only checks in the task handoff, run `git diff --check` again, and commit the final Android changes with `git status --short` clean except for intentional user worktree changes.

## Self-Review

- The automatic permission requirement is covered by Task 1 and does not depend on account state.
- Theme persistence is covered by Task 1 and consumed by both the app and widget configuration.
- Provider overview, partial/stale states, and exact money/request semantics are covered by Task 2 and rendered in Task 3.
- HarmonyOS-style overview, account tabs, onboarding, management, and settings are covered by Tasks 3 and 4.
- Existing provider/aggregation/alert contracts are deliberately not modified; Task 5 runs parity gates to enforce that boundary.
- All plan steps have concrete files, commands, expected results, and no unresolved placeholders.
