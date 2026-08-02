#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PARITY_SCRIPT="$ROOT_DIR/scripts/verify-provider-parity.sh"

TEST_ROOT="$(mktemp -d /tmp/QuotaGlance-provider-parity-tests.XXXXXX)"

restore_files=()
restore_backup() {
  local backup="$1"
  local target="$2"
  if [[ -f "$backup" ]]; then
    /bin/cp "$backup" "$target"
  fi
}
trap '
  if (( ${#restore_files[@]} > 0 )); then
    for i in "${restore_files[@]}"; do
      restore_backup "$TEST_ROOT/$i.src" "$i"
      restore_backup "$TEST_ROOT/$i.harmonyos" "$i"
    done
  fi
  /bin/rm -rf "$TEST_ROOT"
' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_fails() {
  if "$@" >/dev/null 2>&1; then
    fail "command unexpectedly succeeded: $*"
  fi
}

# Back up the Swift-core and HarmonyOS copies of every spec so each negative
# test can tamper with one and the EXIT trap restores the originals.
backup_spec_copies() {
  local spec id core_copy harmonyos_copy
  for spec in "$ROOT_DIR"/Contracts/Providers/*/spec.json; do
    id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$spec")"
    core_copy="$ROOT_DIR/Sources/QuotaGlanceCore/Resources/ProviderSpecs/$id.json"
    harmonyos_copy="$ROOT_DIR/HarmonyOS/entry/src/main/resources/rawfile/providerspecs/$id.json"
    /bin/mkdir -p "$TEST_ROOT/$(/usr/bin/dirname "$core_copy")"
    /bin/mkdir -p "$TEST_ROOT/$(/usr/bin/dirname "$harmonyos_copy")"
    /bin/cp "$core_copy" "$TEST_ROOT/$core_copy.src"
    /bin/cp "$harmonyos_copy" "$TEST_ROOT/$harmonyos_copy.harmonyos"
    restore_files+=("$core_copy" "$harmonyos_copy")
  done
}

test_parity_script_exists() {
  [[ -f "$PARITY_SCRIPT" ]] || fail "missing $PARITY_SCRIPT"
}

test_current_tree_is_green() {
  /bin/bash "$PARITY_SCRIPT" >/dev/null \
    || fail "verify-provider-parity.sh failed on the current tree"
}

test_tampered_core_spec_copy_is_red() {
  local core_copy="$ROOT_DIR/Sources/QuotaGlanceCore/Resources/ProviderSpecs/kimi.json"
  printf '\n' >> "$core_copy"
  assert_fails /bin/bash "$PARITY_SCRIPT"
  restore_backup "$TEST_ROOT/$core_copy.src" "$core_copy"
  /bin/bash "$PARITY_SCRIPT" >/dev/null \
    || fail "verify-provider-parity.sh still failing after restoring the spec copy"
}

test_tampered_harmonyos_spec_copy_is_red() {
  local harmonyos_copy="$ROOT_DIR/HarmonyOS/entry/src/main/resources/rawfile/providerspecs/deepSeek.json"
  printf ' ' >> "$harmonyos_copy"
  assert_fails /bin/bash "$PARITY_SCRIPT"
  restore_backup "$TEST_ROOT/$harmonyos_copy.harmonyos" "$harmonyos_copy"
  /bin/bash "$PARITY_SCRIPT" >/dev/null \
    || fail "verify-provider-parity.sh still failing after restoring the spec copy"
}

backup_spec_copies
test_parity_script_exists
test_current_tree_is_green
test_tampered_core_spec_copy_is_red
test_tampered_harmonyos_spec_copy_is_red

echo "Provider parity tests passed"
