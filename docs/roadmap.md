# QuotaGlance Roadmap

Last updated: 2026-08-02

## Current delivery track

### 1. App icon polish

- Add a production macOS app icon asset set.
- Keep the visual direction quiet and utility-focused rather than mascot or marketing-led.

### 2. HarmonyOS internationalization

- Add System / English / 简体中文 language preference on HarmonyOS, mirroring macOS `AppLanguage`.
- Localize pages, service-card widget copy, error toasts, and provider profile descriptions via resource qualifiers.
- Implementation plan: `docs/superpowers/plans/2026-08-02-harmonyos-i18n.md` (Part A of `docs/superpowers/specs/2026-08-02-harmonyos-i18n-and-verification-design.md`).

## Required next milestone before store release

### 3. Internationalization foundation

- Support three language modes in Settings:
  - `Follow System`
  - `简体中文`
  - `English`
- Default to `Follow System`.
- Localize App, Widget, notifications, and App Intent strings together.
- Treat localization as a prerequisite for both macOS and iOS store release work.

## Store release track

### 4. Mac App Store release

- Prepare a Mac App Store-compatible signing and entitlement path.
- Add release metadata, screenshots, privacy disclosures, and review notes.
- Keep this separate from direct DMG distribution.

### 5. iOS product definition

- Define the first iOS scope before implementation.
- Reuse `QuotaGlanceCore` where practical, but design an iOS-specific UI and storage model explicitly.

### 6. iOS App Store release

- Treat iOS store delivery as its own release track.
- Prepare iPhone/iPad screenshots, review notes, privacy answers, and distribution settings separately from macOS.

## Multi-platform expansion

### 7. watchOS companion

- Revisit after iOS exists.
- Prefer a companion design over an independent first release.

### 8. Android / Windows / HarmonyOS evaluation

- Do not commit to a direct port yet.
- First decide whether the product should remain client-only or move provider refresh to a shared backend service.
- Use that decision to choose the cross-platform architecture.
- HarmonyOS capability findings and the lightest-integration recommendation: `docs/research/harmonyos-integration.md`.
- HarmonyOS direction is decided (client-only, per-platform UI and core, shared contract fixtures, personal-use minimal loop first); see the Architecture decisions section of the same document. Android/Windows remain open under the bullets above.

## Completed

### GitHub Actions + Quality CI (2026-08)

- CI workflow (`ci.yml`, macos-14): `swift test`, `scripts/verify-provider-parity.sh`, and ScriptTests including `GitHubActionsTests.sh`, on pull requests and pushes to `main`.
- Package workflow (`package.yml`): DMG packaging and artifact upload on PRs, pushes to `main`, and manual dispatch.
- Release workflow (`release.yml`): version-tag DMG packaging and GitHub release publication.
- HarmonyOS workflow (`harmonyos.yml`, ubuntu + OHOS SDK): contract sync, provider parity check, unsigned HAP build; path filters include `Contracts/**`, `HarmonyOS/**`, and parity scripts.
- Quality workflow (`quality.yml`, ubuntu): actionlint, zizmor, ShellCheck on `scripts/` and `Tests/**/*.sh`, gitleaks, and a dedicated provider-contract job running `verify-provider-parity.sh` + `ProviderParityTests.sh` on PRs, pushes to `main`, and merge queue.
- Dependabot for GitHub Actions; workflows pin third-party actions to commit SHAs and use read-only `contents` permissions where applicable.

### HarmonyOS verification loop (2026-08)

- ArkTS contract harness (`Contract.test.ets`) records and asserts full request triples (method, URL, header patterns) with the same semantics as Swift `expectRequests`.
- `scripts/verify-provider-parity.sh` gates `CONTRACT_CASES` coverage against contract fixture cases and step URL sync with `<case>-requests.json`.
- `Tests/ScriptTests/ProviderParityTests.sh` includes a red-path case when coverage is incomplete.
- Device-side ohosTest remains out of CI; local / DevEco runs still required for Hypium contract execution.
- Implementation plan: `docs/superpowers/plans/2026-08-02-harmonyos-verification-loop.md`.

### Provider architecture migration to spec-driven engines (2026-08)

- Provider implementations on both platforms are now spec-driven: `Contracts/Providers/<provider>/spec.json` is the single source of truth, executed by one generic engine per platform (Swift `SpecDrivenProvider` + `ProviderSpec`; ArkTS `SpecDrivenProvider` + `SpecEngine`). All hand-written per-provider code was deleted except the named `miniMaxModelRemains` parse strategy; the spec schema in `Contracts/README.md` is now normative.
- Provider contract fixtures now pin the HTTP request sequence (`<case>-requests.json`) in addition to the parsed snapshot, and the same fixture mechanism was extended to aggregation (`Contracts/Aggregation/`) and alerts (`Contracts/Alerts/`) — currently asserted by the Swift suite only; mirroring them into an ArkTS aggregation/alert engine remains open.
- The `UsageProvider` interface was narrowed to `id` + `descriptor` + `detect(apiKey:)` + `fetch(apiKey:profile:)`, with provider metadata carried by `ProviderDescriptor` and assembly centralized in `ProviderCatalog` (both platforms build providers from the synced specs).
- Sync discipline: `scripts/sync-specs-to-core.sh`, `scripts/sync-specs-to-harmonyos.sh`, `scripts/sync-contracts-to-harmonyos.sh`, gated by `scripts/verify-provider-parity.sh`. Working agreements for future agents: `AGENTS.md` (root) and `HarmonyOS/AGENTS.md`.
