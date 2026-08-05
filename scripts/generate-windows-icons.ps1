$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$windowsDir = Join-Path $repoRoot "Windows"
$sourceIcon = Join-Path $repoRoot "App\Assets.xcassets\AppIcon.appiconset\icon-1024.png"
Set-Location (Join-Path $windowsDir "src-tauri")
cargo tauri icon $sourceIcon -o icons
