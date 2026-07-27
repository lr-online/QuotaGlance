# Alibaba Cloud Model Studio Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a secure Alibaba Cloud Model Studio provider that validates API keys at configurable official Base URLs and clearly presents its connection-only capability.

**Architecture:** Store an optional, non-secret `ProviderConfiguration` on each account and pass it through the existing provider protocol. The Bailian adapter allowlists and normalizes official endpoints, validates keys with `GET /models`, detects endpoint region, and returns a healthy snapshot with an explicit billing-unavailable notice rather than monetary data.

**Tech Stack:** Swift 6, Swift Testing, Foundation networking, SwiftUI, Keychain, WidgetKit

---

### Task 1: Domain And Endpoint Contract

**Files:**
- Modify: `Sources/QuotaGlanceCore/Domain/Provider.swift`
- Modify: `Sources/QuotaGlanceCore/Domain/Account.swift`
- Modify: `Sources/QuotaGlanceCore/Providers/UsageProvider.swift`
- Modify: `Sources/QuotaGlanceCore/Validation/AccountValidator.swift`
- Test: `Tests/QuotaGlanceCoreTests/DomainModelTests.swift`
- Test: `Tests/QuotaGlanceCoreTests/AccountValidationTests.swift`

- [ ] Add failing tests for the Bailian provider identity, disabled low-balance threshold, Base URL persistence, default URL, and invalid URL rejection.
- [ ] Run `swift test --filter 'DomainModelTests|AccountValidationTests'` and confirm failures are caused by missing Bailian types.
- [ ] Add `ProviderID.bailian`, `ProviderConfiguration.baseURL`, account/draft persistence, validation, and configuration-aware default protocol methods.
- [ ] Re-run the focused tests and confirm they pass.

### Task 2: Bailian Adapter

**Files:**
- Create: `Sources/QuotaGlanceCore/Providers/BailianProvider.swift`
- Create: `Tests/QuotaGlanceCoreTests/BailianProviderTests.swift`

- [ ] Add failing tests for official endpoint normalization, non-Aliyun rejection, `/models` request construction, China/international detection, response validation, typed HTTP errors, and profile mismatch.
- [ ] Run `swift test --filter BailianProviderTests` and confirm the adapter is missing.
- [ ] Implement the allowlisted endpoint parser and the OpenAI-compatible model-list request.
- [ ] Re-run `swift test --filter BailianProviderTests` and confirm it passes.

### Task 3: Account Flow And Refresh

**Files:**
- Modify: `Sources/QuotaGlanceCore/Refresh/RefreshCoordinator.swift`
- Modify: `App/AppModel.swift`
- Modify: `App/Settings/AccountEditorView.swift`
- Modify: `Tests/QuotaGlanceCoreTests/RefreshCoordinatorTests.swift`

- [ ] Add a failing refresh test proving account configuration reaches the provider.
- [ ] Run `swift test --filter RefreshCoordinatorTests` and confirm the new assertion fails.
- [ ] Forward configuration during detection and refresh, register `BailianProvider`, persist configuration, and show the Base URL editor only for Bailian.
- [ ] Re-run the focused test and build the app target.

### Task 4: Connection-Only Presentation

**Files:**
- Modify: `Sources/QuotaGlanceCore/Domain/UsageSnapshot.swift`
- Modify: `Sources/QuotaGlanceCore/Presentation/DashboardPresentation.swift`
- Modify: `Sources/QuotaGlanceCore/Presentation/MenuBarPresentation.swift`
- Modify: `Sources/QuotaGlanceCore/Presentation/WidgetPresentation.swift`
- Modify: `App/MenuBar/MenuBarDashboardView.swift`
- Modify: `Widget/WidgetViews.swift`
- Modify: `Tests/QuotaGlanceCoreTests/WidgetPresentationTests.swift`

- [ ] Add a failing presentation test for a healthy connection-only snapshot.
- [ ] Run `swift test --filter WidgetPresentationTests` and confirm the notice is missing.
- [ ] Add a snapshot metric-unavailability notice and render `Connected` plus the notice in menu bar and Widget metric fallbacks.
- [ ] Re-run focused presentation tests and build both app and Widget targets.

### Task 5: Documentation And Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/research/provider-capabilities.md`

- [ ] Document Base URL setup, regional endpoint behavior, live verification, and the billing API limitation.
- [ ] Run `swift test`.
- [ ] Run `xcodebuild -project QuotaGlance.xcodeproj -scheme QuotaGlance -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`.
- [ ] Run `./scripts/verify-no-secret.sh` with no live credential and scan tracked files for the tested key prefix only, never the full key.
- [ ] Inspect `git diff --check`, install the stable local Release build, commit, and push `main`.

