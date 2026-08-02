# QuotaGlance macOS 12 Compatibility Design

## Goal

Ship QuotaGlance to Apple Silicon users on macOS 12.2.1 without weakening the
existing macOS 14 experience.

- macOS 12 edition: menu bar balance, usage, account selection, settings, and
  manual or scheduled refresh.
- macOS 14 edition: the same menu bar app plus the configurable WidgetKit
  extension.
- Both editions come from one source commit and include that source archive in
  the DMG.

## Why Two Artifacts

The Widget extension uses `AppIntentConfiguration` and widget container APIs
whose minimum supported system is macOS 14. Embedding that extension in the
macOS 12 package would make install and registration behavior dependent on
unsupported system behavior. A dedicated host-only target is therefore the
smallest reliable compatibility boundary.

The two artifacts are:

- `QuotaGlance-<version>-macOS12-arm64.dmg`, containing only the host app.
- `QuotaGlance-<version>-macOS14-arm64.dmg`, containing the host app and Widget.

Both apps keep the same bundle identifier so preferences and Keychain entries
survive switching editions. Users must install only one edition at a time.

## Application Architecture

The shared host source has a macOS 12 deployment target and avoids unavailable
top-level APIs:

- `NSStatusItem` and `NSPopover` replace `MenuBarExtra` for the menu bar entry.
- `ObservableObject` and `@Published` replace Observation's `@Observable`.
- Settings buttons send the appropriate SwiftUI settings-window action through
  AppKit instead of using `SettingsLink`.
- A small native empty-state view replaces `ContentUnavailableView`.
- `LaunchAtLoginService` uses `SMAppService` only on macOS 13 or newer. The
  launch-at-login setting is hidden on macOS 12 because adding a deprecated
  login-item implementation is outside phase one.
- Scheduled refresh uses the nanosecond form of `Task.sleep`, available on the
  deployment target.

The Xcode project contains two host targets over the same `App/` sources:

- `QuotaGlance`, minimum macOS 14, embeds `QuotaGlanceWidget`.
- `QuotaGlanceLegacy`, product name `QuotaGlance`, minimum macOS 12, has no
  Widget dependency or embedded extension.

The Swift package core moves to macOS 12 because it contains domain, network,
storage, and presentation logic needed by both hosts. The Widget target remains
macOS 14.

## Distribution And Verification

`build-local.sh` accepts an explicit edition and selects the corresponding
scheme. `package-dmg.sh` packages one or both editions from a detached temporary
clone of the selected commit. Building and archiving from that clone prevents a
changing caller worktree from producing binary and source artifacts from
different states.

The verifier receives the expected edition and checks:

- checksum content names the exact DMG basename passed to the verifier;
- only regular top-level payloads are accepted, except the exact Applications
  shortcut;
- source ZIP paths are relative, stay below their single prefix, and exclude
  local configuration, logs, build output, snapshots, preferences, and Keychain
  exports;
- host bundle identifier, arm64 architecture, ad hoc signature, source commit,
  README version, and minimum system version;
- macOS 12 edition has no desktop Widget extension, includes the Notification Center widget and Intents service, and has minimum version 12.0;
- macOS 14 edition has the expected Widget extension and minimum version 14.0;
- Gatekeeper is accepted only when it returns the documented ad hoc rejection,
  not for arbitrary `spctl` failures.

Artifacts are assembled inside the output directory and published with
non-overwriting filesystem operations. This removes cross-filesystem moves and
narrows the final-name race. Existing final paths always cause packaging to
fail.

Secret scanning treats scanner errors as failures. Source input is a committed
Git tree, and the archive path policy is defense in depth against accidentally
tracked local or sensitive material.

## Compatibility Contract

The macOS 12 edition intentionally does not provide desktop Widgets or launch
at login. All account data, API behavior, two-decimal money formatting, Keychain
storage, refresh intervals, and menu bar account switching remain identical.

The macOS 14 edition retains all current Widget sizes and per-account Widget
configuration. No provider expansion is included in this work.
