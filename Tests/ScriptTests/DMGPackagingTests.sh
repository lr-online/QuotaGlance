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

test_real_dmg_round_trip() {
  local clean_repo="$TEST_ROOT/clean-repository"
  local clean_output="$TEST_ROOT/output"
  local clean_package
  local clean_verify
  local current_commit

  current_commit="$(/usr/bin/git -C "$ROOT_DIR" rev-parse HEAD)"
  /usr/bin/git clone --quiet --no-local --no-checkout \
    "$ROOT_DIR" "$clean_repo"
  /usr/bin/git -C "$clean_repo" checkout --quiet --detach "$current_commit"
  /usr/bin/ditto "$PACKAGE_SCRIPT" "$clean_repo/scripts/package-dmg.sh"
  /usr/bin/ditto "$VERIFY_SCRIPT" "$clean_repo/scripts/verify-dmg.sh"
  /usr/bin/git -C "$clean_repo" add scripts/package-dmg.sh scripts/verify-dmg.sh
  /usr/bin/git -C "$clean_repo" \
    -c user.name='QuotaGlance Tests' \
    -c user.email='tests@localhost' \
    commit --quiet -m 'test fixture: add dmg packaging scripts'

  clean_package="$clean_repo/scripts/package-dmg.sh"
  clean_verify="$clean_repo/scripts/verify-dmg.sh"
  /bin/mkdir -p "$clean_output"
  "$clean_package" "$clean_output" >/dev/null

  local dmg="$clean_output/QuotaGlance-0.1.0-arm64.dmg"
  local checksum="$dmg.sha256"
  [[ -f "$dmg" ]] || fail "DMG was not created"
  [[ -f "$checksum" ]] || fail "DMG checksum was not created"
  "$clean_verify" "$dmg" "$checksum" >/dev/null

  assert_fails "$clean_package" "$clean_output"
}

test_secret_scan_accepts_an_artifact_path
test_distribution_contract
test_real_dmg_round_trip
echo "DMG packaging tests passed"
