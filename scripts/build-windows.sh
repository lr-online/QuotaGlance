#!/usr/bin/env bash
# Build the Windows Tauri client and emit installer artifacts that match the
# checked-in Tauri bundle configuration (NSIS + MSI).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WINDOWS_DIR="$REPO_ROOT/Windows"
TAURI_DIR="$WINDOWS_DIR/src-tauri"

cd "$REPO_ROOT"
bash scripts/sync-specs-to-windows.sh
bash scripts/sync-contracts-to-windows.sh

cd "$WINDOWS_DIR"
if [[ "${SKIP_PNPM:-0}" != "1" ]]; then
  if [[ -f package-lock.json ]]; then
    npm ci || npm install
  else
    pnpm install --frozen-lockfile || pnpm install || npm install
  fi
  npm run build
fi

cd "$TAURI_DIR"
cargo tauri build --target x86_64-pc-windows-msvc --bundles nsis,msi "$@"

TARGET_DIR="$WINDOWS_DIR/target/x86_64-pc-windows-msvc/release/bundle"
NSIS_GLOB="$TARGET_DIR/nsis"/*.exe
MSI_GLOB="$TARGET_DIR/msi"/*.msi

if compgen -G "$NSIS_GLOB" >/dev/null; then
  echo "nsis installer produced:"
  ls -lh $NSIS_GLOB
else
  echo "warning: no NSIS installer produced" >&2
  exit 1
fi

if compgen -G "$MSI_GLOB" >/dev/null; then
  echo "msi installer produced:"
  ls -lh $MSI_GLOB
else
  echo "warning: no MSI installer produced" >&2
  exit 1
fi
