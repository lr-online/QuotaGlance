# Android Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a contract-compliant native Android application and publish its APK from GitHub Actions without changing macOS or HarmonyOS source modules.

**Architecture:** Kotlin/Compose supplies platform UI while a Kotlin spec engine mirrors the existing Swift and ArkTS engines. Synced contract resources are exercised by JVM tests; data, refresh, notification and widget adapters stay behind narrow Android seams.

**Tech Stack:** Kotlin 2.x, Android Gradle Plugin, Jetpack Compose, Coroutines, DataStore, Android Keystore, WorkManager, Glance, OkHttp, kotlinx.serialization, JUnit.

---

### Task 1: Bootstrap the reproducible Android build

**Files:** create `Platforms/Android/settings.gradle.kts`, `Platforms/Android/build.gradle.kts`, `Platforms/Android/gradle.properties`, `Platforms/Android/gradlew`, `Platforms/Android/app/build.gradle.kts`, `Platforms/Android/app/src/main/AndroidManifest.xml`.

- [ ] Add a JDK-17/compileSdk-35 Kotlin Android application with Compose, unit-test and release APK variants.
- [ ] Run `Platforms/Android/gradlew :app:assembleDebug` and confirm Gradle resolves all build inputs.
- [ ] Commit the bootstrapped build and wrapper with the first Android source slice.

### Task 2: Establish contract resources and parity guard

**Files:** create `scripts/sync-specs-to-android.sh`, `scripts/sync-contracts-to-android.sh`, `scripts/verify-android-parity.sh`, `Platforms/Android/app/src/main/assets/providerspecs/`, `Platforms/Android/app/src/test/resources/contracts/`.

- [ ] Write failing shell assertions for a missing Kotlin provider id and stale synced spec.
- [ ] Implement the three scripts so every provider spec and all fixture sets are copied and checked byte-for-byte.
- [ ] Run the scripts and preserve generated assets as sync output.

### Task 3: Implement and test the pure Kotlin contract core

**Files:** create `Platforms/Android/app/src/main/java/com/liangrui/quotaglance/core/**`, `Platforms/Android/app/src/test/java/com/liangrui/quotaglance/core/**`.

- [ ] Write failing fixture tests for every provider response/request triple plus aggregation and alerts.
- [ ] Port provider ids, profiles, error tokens, exact decimal handling, spec validation/evaluation, snapshot assembly, MiniMax strategy, aggregation and alert episode semantics.
- [ ] Run `:app:testDebugUnitTest`; assert every copied contract fixture is replayed rather than selectively registered.

### Task 4: Add encrypted storage and refresh orchestration

**Files:** create `Platforms/Android/app/src/main/java/com/liangrui/quotaglance/data/**`, `Platforms/Android/app/src/main/java/com/liangrui/quotaglance/refresh/**`, corresponding unit tests.

- [ ] Write failing tests for account-name/key validation, delete cascade, stale snapshot retention, per-account refresh isolation and episode persistence.
- [ ] Implement DataStore metadata/snapshot stores, Keystore-backed credentials, account repository and coroutine refresh coordinator.
- [ ] Add WorkManager scheduling, foreground startup/manual refresh, notification dispatch seam and widget-refresh seam.

### Task 5: Deliver Compose, widget and deep-link product surfaces

**Files:** create `Platforms/Android/app/src/main/java/com/liangrui/quotaglance/ui/**`, `Platforms/Android/app/src/main/java/com/liangrui/quotaglance/widget/**`, `Platforms/Android/app/src/main/res/**`.

- [ ] Write JVM tests for route parsing, widget selection fallback and presentation states.
- [ ] Implement dashboard, account detail/editor, settings, empty/partial/stale/unavailable states, bilingual strings, notification permission state and Glance selection.
- [ ] Add manifest deep-link intent filters and verified fallback for deleted accounts.

### Task 6: Wire CI and release delivery

**Files:** create `.github/workflows/android.yml`; modify `.github/workflows/release.yml`, `docs/platform-capability-matrix.md`, `README.md`.

- [ ] Add a GitHub Actions job that installs JDK/SDK, runs sync/parity/tests/lint/release build, and uploads a named APK artifact.
- [ ] Attach the release APK to `v*` GitHub Releases without affecting existing macOS/HarmonyOS jobs.
- [ ] Document Android capability status, platform scheduling difference, local compile command and artifact download path.

### Task 7: Final verification and delivery commit

**Files:** all Android-only/new CI and documentation changes above.

- [ ] Run `bash scripts/verify-provider-parity.sh`, `bash scripts/verify-android-parity.sh`, Android JVM tests, lint and release assembly.
- [ ] Inspect the APK with `aapt`/`apkanalyzer` when available; check that no credentials or ignored build output are tracked.
- [ ] Commit the complete Android client in coherent implementation-sized commits, push the branch, and open a draft PR so GitHub builds the downloadable artifact.

