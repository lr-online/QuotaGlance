#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/QuotaGlance-dmg-tests.XXXXXX)"
trap '/bin/chmod -R u+rwX "$TEST_ROOT"; /bin/rm -rf "$TEST_ROOT"' EXIT
PACKAGE_SCRIPT="$ROOT_DIR/scripts/package-dmg.sh"
VERIFY_SCRIPT="$ROOT_DIR/scripts/verify-dmg.sh"

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

test_distribution_contract() {
  [[ -f "$ROOT_DIR/Distribution/README.txt" ]] \
    || fail "distribution README is missing"
  rg -q '未经过 Apple Developer ID 签名或 Apple 公证' \
    "$ROOT_DIR/Distribution/README.txt" \
    || fail "distribution README does not disclose Gatekeeper limitations"
  rg -q 'QuotaGlance-0.1.0-source.zip' \
    "$ROOT_DIR/Distribution/README.txt" \
    || fail "distribution README does not identify the source archive"
  rg -q '^dist/$' "$ROOT_DIR/.gitignore" \
    || fail "dist directory is not ignored"
  [[ -x "$PACKAGE_SCRIPT" ]] || fail "package script is missing"
  [[ -x "$VERIFY_SCRIPT" ]] || fail "DMG verifier is missing"
}

test_secret_scan_accepts_an_artifact_path
test_distribution_contract
echo "DMG packaging tests passed"
