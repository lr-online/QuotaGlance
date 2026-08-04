#!/usr/bin/env bash
# Local development loop for the Windows client. Mirrors `cargo tauri dev`
# but additionally syncs spec + contract fixtures into the run-time tree
# first so the spec engine reads the latest spec changes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$REPO_ROOT"
bash scripts/sync-specs-to-windows.sh
bash scripts/sync-contracts-to-windows.sh

cd "$REPO_ROOT/Windows/src-tauri"
exec cargo tauri dev "$@"
