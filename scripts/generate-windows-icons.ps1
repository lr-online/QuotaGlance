$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$windowsDir = Join-Path $repoRoot "Windows"
$sourceIcon = Join-Path $repoRoot "App\Assets.xcassets\AppIcon.appiconset\icon-1024.png"
Set-Location (Join-Path $windowsDir "src-tauri")
$localTauri = Join-Path $windowsDir "node_modules\.bin\tauri.cmd"

if (Test-Path -LiteralPath $localTauri) {
  & $localTauri icon $sourceIcon -o icons
} else {
  cargo tauri icon $sourceIcon -o icons
}

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
