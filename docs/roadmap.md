# QuotaGlance Roadmap

Last updated: 2026-07-27

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
