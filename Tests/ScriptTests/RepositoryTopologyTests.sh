#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY_SCRIPT="$ROOT_DIR/scripts/verify-repository-topology.sh"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quotaglance-topology.XXXXXX")"

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_failure() {
  if "$@" >/dev/null 2>&1; then
    fail "expected command to fail: $*"
  fi
}

[[ -x "$VERIFY_SCRIPT" ]] || fail "repository topology verifier is missing or not executable"

"$VERIFY_SCRIPT" "$ROOT_DIR"

mkdir -p \
  "$TEMP_ROOT/Contracts" \
  "$TEMP_ROOT/Sources/QuotaGlanceCore" \
  "$TEMP_ROOT/App" \
  "$TEMP_ROOT/Widget" \
  "$TEMP_ROOT/NCWidget" \
  "$TEMP_ROOT/NCIntents" \
  "$TEMP_ROOT/Config" \
  "$TEMP_ROOT/Distribution" \
  "$TEMP_ROOT/Android" \
  "$TEMP_ROOT/HarmonyOS" \
  "$TEMP_ROOT/Windows" \
  "$TEMP_ROOT/script" \
  "$TEMP_ROOT/scripts"
cp "$ROOT_DIR/script/build_and_run.sh" "$TEMP_ROOT/script/build_and_run.sh"

"$VERIFY_SCRIPT" "$TEMP_ROOT"

mkdir -p "$TEMP_ROOT/Platforms/Android"
expect_failure "$VERIFY_SCRIPT" "$TEMP_ROOT"
rmdir "$TEMP_ROOT/Platforms/Android"
rmdir "$TEMP_ROOT/Platforms"

touch "$TEMP_ROOT/script/unapproved.sh"
expect_failure "$VERIFY_SCRIPT" "$TEMP_ROOT"

echo "Repository topology tests passed."
