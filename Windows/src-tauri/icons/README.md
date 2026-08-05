# Icons

This directory holds the icon files referenced by `tauri.conf.json`:

- `32x32.png`
- `128x128.png`
- `128x128@2x.png`
- `icon.ico` (Windows install + Explorer icon)
- `tray-icon.png` (system-tray icon, used by `app.trayIcon.iconPath`)

Generate them from the existing QuotaGlance app icon set:

- source: `App/Assets.xcassets/AppIcon.appiconset/icon-1024.png`
- command: `bash scripts/generate-windows-icons.sh`

Windows must reuse the same icon already used by the other clients. Do not
replace these files with placeholder artwork.
