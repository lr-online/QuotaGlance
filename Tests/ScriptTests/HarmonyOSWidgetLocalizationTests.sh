#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SNAPSHOT_STORE="$ROOT_DIR/Platforms/HarmonyOS/entry/src/main/ets/storage/SnapshotStore.ets"
CARD_UPDATER="$ROOT_DIR/Platforms/HarmonyOS/entry/src/main/ets/services/CardUpdater.ets"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local needle="$1"
  local file="$2"
  rg -Fq "$needle" "$file" || fail "$file missing: $needle"
}

assert_contains "formatSnapshotTexts(context: common.Context, stored: StoredSnapshot | null)" "$SNAPSHOT_STORE"
for key in widget_balance_unconfigured widget_status_prompt_key widget_status_ok \
  stale_text widget_status_unavailable updated_prefix; do
  assert_contains "\$r('app.string.$key').id" "$SNAPSHOT_STORE"
done

assert_contains "formatSnapshotTexts(context, stored)" "$CARD_UPDATER"

echo "OK: HarmonyOS widget snapshot strings use localized resources"
