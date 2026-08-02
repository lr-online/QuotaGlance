# QuotaGlance Roadmap

Last updated: 2026-08-02

## Current delivery track

### 1. App icon polish

- Add a production macOS app icon asset set.
- Keep the visual direction quiet and utility-focused rather than mascot or marketing-led.

### 2. GitHub Actions automation

- Add a CI workflow for pull requests and pushes to `main`.
- Run the existing repository verification commands:
  - `swift test`
  - `Tests/ScriptTests/BuildEditionTests.sh`
  - `Tests/ScriptTests/DMGPackagingTests.sh`
  - `Tests/ScriptTests/LocalInstallSafetyTests.sh`
- Add a release workflow that packages DMGs from version tags and publishes the artifacts.

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

### Provider architecture migration to spec-driven engines (2026-08)

- Provider implementations on both platforms are now spec-driven: `Contracts/Providers/<provider>/spec.json` is the single source of truth, executed by one generic engine per platform (Swift `SpecDrivenProvider` + `ProviderSpec`; ArkTS `SpecDrivenProvider` + `SpecEngine`). All hand-written per-provider code was deleted except the named `miniMaxModelRemains` parse strategy; the spec schema in `Contracts/README.md` is now normative.
- Provider contract fixtures now pin the HTTP request sequence (`<case>-requests.json`) in addition to the parsed snapshot, and the same fixture mechanism was extended to aggregation (`Contracts/Aggregation/`) and alerts (`Contracts/Alerts/`) — currently asserted by the Swift suite only; mirroring them into an ArkTS aggregation/alert engine remains open.
- The `UsageProvider` interface was narrowed to `id` + `descriptor` + `detect(apiKey:)` + `fetch(apiKey:profile:)`, with provider metadata carried by `ProviderDescriptor` and assembly centralized in `ProviderCatalog` (both platforms build providers from the synced specs).
- Sync discipline: `scripts/sync-specs-to-core.sh`, `scripts/sync-specs-to-harmonyos.sh`, `scripts/sync-contracts-to-harmonyos.sh`, gated by `scripts/verify-provider-parity.sh`. Working agreements for future agents: `AGENTS.md` (root) and `HarmonyOS/AGENTS.md`.
