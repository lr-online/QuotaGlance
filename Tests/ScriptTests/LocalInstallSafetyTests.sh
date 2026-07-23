#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT_DIR/scripts/local-snapshot-storage.sh"
source "$ROOT_DIR/scripts/local-entitlement-validation.sh"

TEST_ROOT="$(mktemp -d /tmp/QuotaGlance-local-install-tests.XXXXXX)"
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

test_snapshot_directory_validation() {
  local real_directory="$TEST_ROOT/real-directory"
  local linked_directory="$TEST_ROOT/linked-directory"
  local regular_file="$TEST_ROOT/regular-file"
  local safe_directory="$TEST_ROOT/safe-directory"

  /bin/mkdir "$real_directory"
  /bin/chmod 755 "$real_directory"
  /bin/ln -s "$real_directory" "$linked_directory"
  /usr/bin/touch "$regular_file"

  assert_fails quota_glance_prepare_snapshot_directory "$linked_directory"
  [[ "$(/usr/bin/stat -f '%Lp' "$real_directory")" == "755" ]] \
    || fail "symlink target permissions changed"
  assert_fails quota_glance_prepare_snapshot_directory "$regular_file"

  quota_glance_prepare_snapshot_directory "$safe_directory"
  [[ ! -L "$safe_directory" && -d "$safe_directory" ]] \
    || fail "safe snapshot directory was not created"
  [[ "$(/usr/bin/stat -f '%Lp' "$safe_directory")" == "700" ]] \
    || fail "safe snapshot directory is not mode 700"
  [[ "$(/usr/bin/stat -f '%u' "$safe_directory")" == "$EUID" ]] \
    || fail "safe snapshot directory has the wrong owner"
}

test_snapshot_migration() {
  local snapshot_directory="$TEST_ROOT/migration"
  local legacy_snapshot="$TEST_ROOT/legacy.json"
  local local_snapshot="$snapshot_directory/quota-snapshot-v1.json"
  local linked_snapshot="$snapshot_directory/linked.json"
  local link_target="$TEST_ROOT/link-target.json"

  quota_glance_prepare_snapshot_directory "$snapshot_directory"
  printf '%s\n' '{"source":"legacy"}' > "$legacy_snapshot"

  quota_glance_migrate_snapshot_if_needed "$legacy_snapshot" "$local_snapshot"
  /usr/bin/cmp -s "$legacy_snapshot" "$local_snapshot" \
    || fail "legacy snapshot was not migrated"
  [[ "$(/usr/bin/stat -f '%Lp' "$local_snapshot")" == "600" ]] \
    || fail "migrated snapshot is not mode 600"

  printf '%s\n' '{"source":"current"}' > "$local_snapshot"
  quota_glance_migrate_snapshot_if_needed "$legacy_snapshot" "$local_snapshot"
  [[ "$(<"$local_snapshot")" == '{"source":"current"}' ]] \
    || fail "existing snapshot was overwritten"

  printf '%s\n' '{"source":"target"}' > "$link_target"
  /bin/ln -s "$link_target" "$linked_snapshot"
  assert_fails \
    quota_glance_migrate_snapshot_if_needed "$legacy_snapshot" "$linked_snapshot"
  [[ "$(<"$link_target")" == '{"source":"target"}' ]] \
    || fail "snapshot symlink target was overwritten"
}

make_valid_entitlements() {
  local app_entitlements="$1"
  local widget_entitlements="$2"

  /usr/bin/plutil -create xml1 "$app_entitlements"
  /usr/bin/plutil -insert 'com\.apple\.security\.app-sandbox' \
    -bool true "$app_entitlements"
  /usr/bin/plutil -insert 'com\.apple\.security\.network\.client' \
    -bool true "$app_entitlements"
  /usr/bin/plutil -insert \
    'com\.apple\.security\.temporary-exception\.files\.absolute-path\.read-write' \
    -json '["/Users/Shared/QuotaGlance/"]' "$app_entitlements"

  /usr/bin/plutil -create xml1 "$widget_entitlements"
  /usr/bin/plutil -insert 'com\.apple\.security\.app-sandbox' \
    -bool true "$widget_entitlements"
  /usr/bin/plutil -insert \
    'com\.apple\.security\.temporary-exception\.files\.absolute-path\.read-only' \
    -json '["/Users/Shared/QuotaGlance/"]' "$widget_entitlements"
}

test_entitlement_validation() {
  local app_entitlements="$TEST_ROOT/app.entitlements"
  local widget_entitlements="$TEST_ROOT/widget.entitlements"
  local invalid_widget="$TEST_ROOT/invalid-widget.entitlements"

  make_valid_entitlements "$app_entitlements" "$widget_entitlements"
  quota_glance_validate_local_entitlements \
    "$app_entitlements" \
    "$widget_entitlements" \
    "/Users/Shared/QuotaGlance/"

  /bin/cp "$widget_entitlements" "$invalid_widget"
  /usr/bin/plutil -insert \
    'com\.apple\.security\.temporary-exception\.files\.absolute-path\.read-write' \
    -json '["/Users/Shared/QuotaGlance/"]' "$invalid_widget"
  assert_fails quota_glance_validate_local_entitlements \
    "$app_entitlements" "$invalid_widget" "/Users/Shared/QuotaGlance/"

  /bin/cp "$widget_entitlements" "$invalid_widget"
  /usr/bin/plutil -insert 'com\.apple\.security\.application-groups' \
    -json '["group.com.liangrui.QuotaGlance"]' "$invalid_widget"
  assert_fails quota_glance_validate_local_entitlements \
    "$app_entitlements" "$invalid_widget" "/Users/Shared/QuotaGlance/"

  /bin/cp "$widget_entitlements" "$invalid_widget"
  /usr/bin/plutil -replace \
    'com\.apple\.security\.temporary-exception\.files\.absolute-path\.read-only' \
    -json '["/Users/Shared/QuotaGlance/", "/tmp/"]' "$invalid_widget"
  assert_fails quota_glance_validate_local_entitlements \
    "$app_entitlements" "$invalid_widget" "/Users/Shared/QuotaGlance/"
}

test_snapshot_directory_validation
test_snapshot_migration
test_entitlement_validation

echo "Local install safety tests passed"
