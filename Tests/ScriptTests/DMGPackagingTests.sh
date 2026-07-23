#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/QuotaGlance-dmg-tests.XXXXXX)"
trap '/bin/chmod -R u+rwX "$TEST_ROOT"; /bin/rm -rf "$TEST_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_fails() {
  if "$@" >/dev/null 2>&1; then
    fail "command unexpectedly succeeded: $*"
  fi
}

test_secret_scan_accepts_an_artifact_path() {
  local clean_app="$TEST_ROOT/Clean.app"
  local contaminated_app="$TEST_ROOT/Contaminated.app"
  local sentinel
  sentinel="$(printf '%s%s' 'quota-glance-packaging-' 'sentinel')"

  /bin/mkdir -p "$clean_app" "$contaminated_app"
  LAOGE_KEY="$sentinel" \
    "$ROOT_DIR/scripts/verify-no-secret.sh" "$clean_app" >/dev/null

  printf '%s' "$sentinel" > "$contaminated_app/payload"
  assert_fails env LAOGE_KEY="$sentinel" \
    "$ROOT_DIR/scripts/verify-no-secret.sh" "$contaminated_app"
}

test_secret_scan_accepts_an_artifact_path
echo "DMG packaging tests passed"
