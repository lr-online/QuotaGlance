#!/usr/bin/env bash
# Prepare every generated contract/spec copy consumed by parity checks.
# Contracts/ is authoritative; generated trees must never be edited directly.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run() {
  echo "+ $*"
  "$@"
}

run bash "$REPO_ROOT/scripts/sync-specs-to-core.sh"
run bash "$REPO_ROOT/scripts/sync-specs-to-harmonyos.sh"
run bash "$REPO_ROOT/scripts/sync-specs-to-android.sh"
run bash "$REPO_ROOT/scripts/sync-specs-to-windows.sh"
run bash "$REPO_ROOT/scripts/sync-contracts-to-harmonyos.sh"
run bash "$REPO_ROOT/scripts/sync-contracts-to-android.sh"
run bash "$REPO_ROOT/scripts/sync-contracts-to-windows.sh"

echo "Parity resources prepared for Swift, HarmonyOS, Android, and Windows."
