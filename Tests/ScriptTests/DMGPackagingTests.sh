#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/QuotaGlance-dmg-tests.XXXXXX)"
trap '/bin/chmod -R u+rwX "$TEST_ROOT"; /bin/rm -rf "$TEST_ROOT"' EXIT
PACKAGE_SCRIPT="$ROOT_DIR/scripts/package-dmg.sh"
VERIFY_SCRIPT="$ROOT_DIR/scripts/verify-dmg.sh"
VALIDATION_SCRIPT="$ROOT_DIR/scripts/distribution-validation.sh"
LEGACY_README="$ROOT_DIR/Distribution/README-macOS12.txt"
FULL_README="$ROOT_DIR/Distribution/README-macOS14.txt"
VERSION="$(/usr/bin/sed -n \
  's/^[[:space:]]*MARKETING_VERSION: "\([^"]*\)"/\1/p' \
  "$ROOT_DIR/project.yml")"
[[ -n "$VERSION" ]] || {
  echo "FAIL: project version is missing" >&2
  exit 1
}

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

test_secret_scan_fails_closed_when_scanners_error() {
  local sentinel
  local no_git_root="$TEST_ROOT/no-git-root"
  local no_git_app="$no_git_root/Clean.app"
  local stub_root="$TEST_ROOT/stub-root"
  local stub_app="$stub_root/Clean.app"
  local stub_bin="$TEST_ROOT/stub-bin"
  sentinel="$(printf '%s%s' 'quota-glance-scanner-' 'sentinel')"

  /bin/mkdir -p "$no_git_root/scripts" "$no_git_app"
  /usr/bin/ditto \
    "$ROOT_DIR/scripts/verify-no-secret.sh" \
    "$no_git_root/scripts/verify-no-secret.sh"
  assert_fails env LAOGE_KEY="$sentinel" \
    "$no_git_root/scripts/verify-no-secret.sh" "$no_git_app"

  /bin/mkdir -p "$stub_root/scripts" "$stub_app" "$stub_bin"
  /usr/bin/ditto \
    "$ROOT_DIR/scripts/verify-no-secret.sh" \
    "$stub_root/scripts/verify-no-secret.sh"
  /usr/bin/git -C "$stub_root" init --quiet
  printf '%s\n' '#!/usr/bin/env bash' 'exit 2' > "$stub_bin/rg"
  /bin/chmod +x "$stub_bin/rg"
  assert_fails env PATH="$stub_bin:/usr/bin:/bin" LAOGE_KEY="$sentinel" \
    "$stub_root/scripts/verify-no-secret.sh" "$stub_app"
}

test_distribution_path_policy() {
  local prefix="QuotaGlance-$VERSION-source"
  local safe_items
  local unsafe_items
  local mount_root="$TEST_ROOT/mounted-payload"
  local attach_plist="$TEST_ROOT/attach.plist"
  local mount_info
  local index

  source "$ROOT_DIR/scripts/distribution-validation.sh"

  safe_items="$(printf '%s\n' \
    "$prefix/" \
    "$prefix/README.md" \
    "$prefix/App/Info.plist" \
    "$prefix/Sources/QuotaGlanceCore/Storage/SharedSnapshotStore.swift" \
    "$prefix/Tests/Fixtures/usage.json")"
  quota_glance_validate_source_items "$safe_items" "$prefix"

  for unsafe_items in \
    "/absolute/path" \
    "$prefix/../outside" \
    "$prefix/.env.local" \
    "$prefix/Logs/build.txt" \
    "$prefix/build.log" \
    "$prefix/quota-snapshot-v1.json" \
    "$prefix/Library/Preferences/com.liangrui.QuotaGlance.plist" \
    "$prefix/export.keychain-db" \
    "$prefix/signing.p12" \
    "AnotherPrefix/README.md"; do
    assert_fails quota_glance_validate_source_items "$unsafe_items" "$prefix"
  done

  /bin/mkdir -p "$mount_root/QuotaGlance.app/Contents/MacOS"
  /usr/bin/touch \
    "$mount_root/QuotaGlance.app/Contents/MacOS/QuotaGlance" \
    "$mount_root/README.txt" \
    "$mount_root/SOURCE-COMMIT.txt" \
    "$mount_root/QuotaGlance-$VERSION-source.zip"
  /bin/ln -s /Applications "$mount_root/Applications"
  quota_glance_validate_mounted_payload \
    "$mount_root" \
    "QuotaGlance-$VERSION-source.zip"

  /bin/mv "$mount_root/README.txt" "$mount_root/README.real"
  /bin/ln -s "$mount_root/README.real" "$mount_root/README.txt"
  assert_fails quota_glance_validate_mounted_payload \
    "$mount_root" \
    "QuotaGlance-$VERSION-source.zip"

  quota_glance_validate_gatekeeper_rejection \
    3 \
    "$mount_root/QuotaGlance.app: rejected"
  for index in 0 1 2 4; do
    assert_fails quota_glance_validate_gatekeeper_rejection \
      "$index" \
      "$mount_root/QuotaGlance.app: rejected"
  done
  assert_fails quota_glance_validate_gatekeeper_rejection 3 "assessment error"

  /usr/bin/plutil -create xml1 "$attach_plist"
  /usr/libexec/PlistBuddy -c 'Add :system-entities array' "$attach_plist"
  for index in {0..16}; do
    /usr/libexec/PlistBuddy \
      -c "Add :system-entities:$index dict" \
      "$attach_plist"
  done
  /usr/libexec/PlistBuddy \
    -c 'Add :system-entities:16:dev-entry string /dev/disk-test' \
    -c 'Add :system-entities:16:mount-point string /Volumes/QuotaGlance-Test' \
    "$attach_plist"
  mount_info="$(quota_glance_mount_info "$attach_plist")"
  [[ "$(/usr/bin/sed -n '1p' <<< "$mount_info")" == "/dev/disk-test" ]] \
    || fail "device node after plist item 15 was not found"
  [[ "$(/usr/bin/sed -n '2p' <<< "$mount_info")" == "/Volumes/QuotaGlance-Test" ]] \
    || fail "mount point after plist item 15 was not found"
}

test_distribution_contract() {
  local readme

  for readme in \
    "$ROOT_DIR/Distribution/README-macOS12.txt" \
    "$ROOT_DIR/Distribution/README-macOS14.txt"; do
    [[ -f "$readme" ]] || fail "distribution README is missing: $readme"
    rg -q '未经过 Apple Developer ID 签名或 Apple 公证' "$readme" \
      || fail "distribution README does not disclose Gatekeeper limitations"
    rg -q '@VERSION@' "$readme" \
      || fail "distribution README does not use the version placeholder"
    rg -q '@SOURCE_ARCHIVE@' "$readme" \
      || fail "distribution README does not identify the source archive"
  done
  rg -q '不包含桌面小组件' "$ROOT_DIR/Distribution/README-macOS12.txt" \
    || fail "macOS 12 README does not explain the Widget limitation"
  rg -q '桌面小组件' "$ROOT_DIR/Distribution/README-macOS14.txt" \
    || fail "macOS 14 README does not explain Widget setup"
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
  /usr/bin/ditto \
    "$VALIDATION_SCRIPT" \
    "$clean_repo/scripts/distribution-validation.sh"
  /usr/bin/ditto \
    "$LEGACY_README" \
    "$clean_repo/Distribution/README-macOS12.txt"
  /usr/bin/ditto \
    "$FULL_README" \
    "$clean_repo/Distribution/README-macOS14.txt"
  /usr/bin/git -C "$clean_repo" rm --quiet --ignore-unmatch \
    Distribution/README.txt
  /bin/mv \
    "$clean_repo/scripts/build-local.sh" \
    "$clean_repo/scripts/build-local-real.sh"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"' \
    '[[ "$SCRIPT_ROOT" != "${QUOTAGLANCE_PACKAGING_CALLER_ROOT:?}" ]] || {' \
    '  echo "build ran in the packaging caller worktree" >&2' \
    '  exit 91' \
    '}' \
    'exec "$SCRIPT_ROOT/scripts/build-local-real.sh" "$@"' \
    > "$clean_repo/scripts/build-local.sh"
  /bin/chmod +x "$clean_repo/scripts/build-local.sh"
  /usr/bin/git -C "$clean_repo" add \
    scripts/build-local.sh \
    scripts/build-local-real.sh \
    scripts/package-dmg.sh \
    scripts/verify-dmg.sh \
    scripts/distribution-validation.sh \
    Distribution/README-macOS12.txt \
    Distribution/README-macOS14.txt
  if ! /usr/bin/git -C "$clean_repo" diff --cached --quiet; then
    /usr/bin/git -C "$clean_repo" \
      -c user.name='QuotaGlance Tests' \
      -c user.email='tests@localhost' \
      commit --quiet -m 'test fixture: update dmg packaging scripts'
  fi

  clean_package="$clean_repo/scripts/package-dmg.sh"
  clean_verify="$clean_repo/scripts/verify-dmg.sh"
  /bin/mkdir -p "$clean_output"
  QUOTAGLANCE_PACKAGING_CALLER_ROOT="$clean_repo" \
    "$clean_package" "$clean_output" >/dev/null

  local legacy_dmg="$clean_output/QuotaGlance-$VERSION-macOS12-arm64.dmg"
  local full_dmg="$clean_output/QuotaGlance-$VERSION-macOS14-arm64.dmg"
  local legacy_checksum="$legacy_dmg.sha256"
  local full_checksum="$full_dmg.sha256"
  [[ -f "$legacy_dmg" ]] || fail "macOS 12 DMG was not created"
  [[ -f "$full_dmg" ]] || fail "macOS 14 DMG was not created"
  [[ -f "$legacy_checksum" ]] || fail "macOS 12 checksum was not created"
  [[ -f "$full_checksum" ]] || fail "macOS 14 checksum was not created"
  "$clean_verify" "$legacy_dmg" "$legacy_checksum" legacy >/dev/null
  "$clean_verify" "$full_dmg" "$full_checksum" full >/dev/null

  printf '%s\n' 'not the dmg' > "$clean_output/unrelated.bin"
  (
    cd "$clean_output"
    /usr/bin/shasum -a 256 unrelated.bin > mismatched.sha256
  )
  assert_fails \
    "$clean_verify" \
    "$legacy_dmg" \
    "$clean_output/mismatched.sha256" \
    legacy

  assert_fails env QUOTAGLANCE_PACKAGING_CALLER_ROOT="$clean_repo" \
    "$clean_package" "$clean_output"
}

test_secret_scan_accepts_an_artifact_path
test_secret_scan_fails_closed_when_scanners_error
test_distribution_path_policy
test_distribution_contract
test_real_dmg_round_trip
echo "DMG packaging tests passed"
