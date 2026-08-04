# Icons

This directory holds the icon files referenced by `tauri.conf.json`:

- `32x32.png`
- `128x128.png`
- `128x128@2x.png`
- `icon.ico` (Windows install + Explorer icon)
- `tray-icon.png` (system-tray icon, used by `app.trayIcon.iconPath`)

The files are intentionally not committed (see `Windows/.gitignore`). They
are produced by the icon-generation script that lands in a follow-up
milestone, mirroring the existing `scripts/generate-app-icon.swift` (which
generates the macOS `.appiconset`) and `scripts/generate-harmonyos-icon.swift`.

Until that script lands, local builds need placeholder files:
- run `cargo tauri icon path/to/source.png` against any 1024x1024 source PNG
  to populate this directory with the correct size set;
- or supply a single `icon.ico` (multi-resolution) and a 256x256 `tray-icon.png`
  by hand before running `cargo tauri build`.

The contract is: do not commit binary icon files, the script owns them.
