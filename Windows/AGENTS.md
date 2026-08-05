# Windows/AGENTS.md - mirror of HarmonyOS/AGENTS.md and Android/AGENTS.md.

# AGENTS.md - QuotaGlance Windows portable client

This directory is the native Windows portable client for QuotaGlance. It is
built with Tauri 2 + WebView2 (Rust main process + HTML/TS front end) and
is intended to be a faithful fourth-platform peer of the existing Swift
(macOS), ArkTS (HarmonyOS), and Kotlin (Android) clients.

The repository-root `AGENTS.md` defines the cross-platform invariants. Read
that file first. The HarmonyOS mirror is documented in
`HarmonyOS/AGENTS.md`; the Android mirror in `Android/AGENTS.md`. This
file only describes what is specific to Windows.

## Layout

```
Windows/
+-- src/                       Front end (React + TypeScript + Vite + Tailwind)
|   +-- main.tsx               Main window entry
|   +-- popover-entry.tsx      Tray popover entry
|   +-- widget-entry.tsx       Desktop widget entry
|   +-- App.tsx                HashRouter shell for the main window
|   +-- components/ui/         shadcn-style primitives (Button, Card, Input,
|   |                          Switch, Badge)
|   +-- i18n/                  English + zh-CN translations + bootstrap
|   +-- pages/                 Overview, AccountDetail, AccountEdit,
|   |                          Settings, AddProvider, Widget, Popover
|   +-- storage/types.ts       Mirrors Preferences locale + widget target
|   +-- lib/cn.ts + tauri-bindings.ts
|   +-- styles/index.css       Tailwind + QG colour tokens + qg-pill utility
+-- src-tauri/                 Rust main process (Tauri 2 host)
|   +-- Cargo.toml             `quotaglance-tauri` crate
|   +-- build.rs               `tauri-build` invocation
|   +-- tauri.conf.json        Three windows (main, widget, popover) + tray
|                              + portable zip + deep-link scheme
|   +-- capabilities/default.json
|   +-- icons/ + assets/       See READMEs
|   +-- src/
|   |   +-- main.rs            Process entry
|   |   +-- lib.rs             Tauri builder + plugin registration
|   |   +-- domain.rs          Mirror of Domain/
|   |   +-- providers/         Mirror of Providers/
|   |   +-- storage/           Mirror of Storage/
|   |   +-- refresh/           Mirror of Refresh/
|   |   +-- aggregation/       Mirror of Aggregation/
|   |   +-- alerts/            Mirror of Alerts/
|   |   +-- tray/mod.rs        Tray icon + popover + context menu
|   |   +-- commands.rs        Tauri command surface
+-- package.json               React + Vite + Tailwind + shadcn/ui primitives
+-- vite.config.ts             Multi-page input for the three HTML entries
+-- tsconfig*.json
+-- postcss.config.js
+-- tailwind.config.js         QG macOS-mirrored colour tokens
+-- index.html / popover.html / widget.html
+-- AGENTS.md                  This file
+-- .gitignore
```

## Mirror relationship

| Rust (Windows/src-tauri/src)                            | Swift (Sources/QuotaGlanceCore/)          | ArkTS (HarmonyOS/entry/src/main/ets/) | Kotlin (Android/app/src/main/java)               |
| ---                                                     | ---                                         | --- | --- |
| `domain.rs`                                              | `Domain/Provider.swift` / `UsageSnapshot.swift` | `Domain/` | `core/ProviderId.kt` / `UsageSnapshot.kt` |
| `providers/usage_provider.rs`                            | `Providers/UsageProvider.swift`              | `providers/UsageProvider.ets` | `core/UsageProvider.kt` |
| `providers/provider_error.rs`                            | `Providers/UsageProvider.swift` (errors)     | `providers/UsageProvider.ets` (header) | `core/ProviderError.kt` |
| `providers/provider_spec.rs`                             | `Providers/ProviderSpec.swift`               | `providers/SpecDrivenProvider.ets` + `SpecEngine.ets` | `core/ProviderSpec.kt` |
| `providers/spec_engine.rs`                               | `Providers/ProviderSpec.swift` (parser)      | `providers/SpecDrivenProvider.ets` | `core/SpecEngine.kt` |
| `providers/spec_driven_provider.rs`                      | `Providers/SpecDrivenProvider.swift`         | `providers/SpecDrivenProvider.ets` | `core/SpecDrivenProvider.kt` |
| `providers/minimax_model_remains_strategy.rs`            | `Providers/MiniMaxModelRemainsStrategy.swift` | `providers/MiniMaxModelRemainsStrategy.ets` | `core/MiniMaxModelRemainsStrategy.kt` |
| `aggregation/snapshot_aggregator.rs`                     | `Aggregation/SnapshotAggregator.swift`       | `aggregation/SnapshotAggregator.ets` | `aggregation/SnapshotAggregator.kt` |
| `alerts/alert_evaluator.rs`                              | `Alerts/AlertEvaluator.swift`                | `alerts/AlertEvaluator.ets` | `alerts/AlertEvaluator.kt` |
| `storage/credential_vault.rs`                            | `Storage/KeychainStore.swift`                | `storage/` (Asset Store Kit) | `data/CredentialVault.kt` |
| `storage/account_store.rs` + `snapshot_store.rs`         | `Storage/Account*.swift` + `SnapshotStore.swift` | `storage/` | `data/` (DataStore) |
| `storage/preferences.rs`                                  | `Storage/Preferences.swift`                  | `storage/` | `data/Preferences.kt` |
| `storage/path_layout.rs`                                  | `Storage/PathLayout.swift`                   | `storage/` | `data/PathLayout.kt` |
| `refresh/refresh_coordinator.rs`                         | `Refresh/RefreshCoordinator.swift`           | `services/LaunchRefresh.ets` | `refresh/` |

Tauri-specific (no peer): `tray/mod.rs`, `commands.rs`, `lib.rs`'s plugin
chain, `tauri.conf.json`, the front-end React shell.

## Sync sources

- `scripts/sync-specs-to-windows.sh` -> `Windows/src-tauri/assets/providerspecs/`
- `scripts/sync-contracts-to-windows.sh` -> `Windows/src-tauri/assets/contracts/`
- `scripts/verify-windows-parity.sh` -> parity gate (Swift enum, KNOWN_*
  allow-lists, spec_version, fixture triples, byte-identical sync)
- `scripts/verify-provider-parity.sh` -> cross-platform four-end parity
  (now includes Rust enum + KNOWN_ERROR_TOKENS mirror)

## Platform-differences allowlist

This section mirrors `HarmonyOS/AGENTS.md #7` and `Android/AGENTS.md #1-#3`.
Initial entries — extend as decisions land:

1. **Login-item launch is opt-in, not automatic.** Portable-app ethos
   forbids silent writes to the user's machine; the user has to flip the
   preference in Settings before the registry entry under
   `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` is created.

2. **Desktop widget is a Tauri subprocess window, not a Win11 Widget
   Board entry.** The Widget Board requires Win11 App Identity
   registration that Tauri does not yet provide; the v1 deliverable is a
   decorationless, always-on-top `WebviewWindow` (240×160, `label:
   "widget"`) that re-renders on snapshot writes. Win11 Widget Board
   support is a v2 task and tracked in `Windows/AGENTS.md` until
   `tauri-plugin-win11-widget` lands or we hand-roll the WinAppSDK
   binding.

3. **UI interactions follow Windows Fluent conventions.** Right-click
   context menu instead of macOS long-press, system-tray left-click to
   toggle the popover (mirroring macOS), Win11-style flyout for
   dropdowns.

4. **DPAPI is the cross-platform equivalent of Keychain.** Storage in
   `Windows/src-tauri/src/storage/credential_vault.rs` calls
   `CryptProtectData`/`CryptUnprotectData` per-call; ciphertext is
   stored at `<root>/credentials.bin`. Trust boundary matches macOS
   Keychain / Android Keystore (per-user OS account).

5. **No menu bar (macOS uses NSStatusBar).** Windows uses the system
   notification area (`tauri-plugin-tray`); the popover window is
   centred on the primary monitor instead of anchored to the tray
   because Tauri 2 does not expose a per-monitor pointer to the tray
   position. This is documented and not a degradation, only a
   positional difference.

6. **`PORTABLE=1` env var** redirects the path layout to the executable's
   parent directory instead of `%LOCALAPPDATA%\QuotaGlance\`. The user
   opt-in choice lives in the start script or shortcut, not in the
   persisted preferences.

## Build prerequisites

- Rust stable (>= 1.77), `rustup target add x86_64-pc-windows-msvc`.
- Microsoft Visual C++ Build Tools (linker for `windows-msvc` target).
- Node.js 20.x and pnpm 9.x (see `package.json` `engines`).
- WebView2 Runtime: Windows 11 ships it; Windows 10 users get it via the
  Evergreen Bootstrapper that auto-runs on first launch of the Tauri
  app if the bundle is configured to do so (default: yes).

Local build:
```
bash scripts/build-windows.sh
```

Local dev loop:
```
bash scripts/dev-windows.sh
```

CI: `.github/workflows/windows.yml` runs `windows-latest` and uploads the
portable zip as a build artifact.
