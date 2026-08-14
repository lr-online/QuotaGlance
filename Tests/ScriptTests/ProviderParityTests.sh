#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PARITY_SCRIPT="$ROOT_DIR/scripts/verify-provider-parity.sh"
CONTRACT_TEST="$ROOT_DIR/Platforms/HarmonyOS/entry/src/ohosTest/ets/test/Contract.test.ets"
LIFECYCLE_INPUT="$ROOT_DIR/Contracts/RefreshLifecycle/all-success-input.json"

TEST_ROOT="$(mktemp -d /tmp/QuotaGlance-provider-parity-tests.XXXXXX)"

restore_files=()
restore_backup() {
  local backup="$1"
  local target="$2"
  if [[ -f "$backup" ]]; then
    /bin/cp "$backup" "$target"
  fi
}
cleanup() {
  if (( ${#restore_files[@]} > 0 )); then
    for i in "${restore_files[@]}"; do
      restore_backup "$TEST_ROOT/$i.src" "$i"
      restore_backup "$TEST_ROOT/$i.harmonyos" "$i"
    done
  fi
  /bin/rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

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
    core_copy="$ROOT_DIR/Shared/SwiftCore/Sources/QuotaGlanceCore/Resources/ProviderSpecs/$id.json"
    harmonyos_copy="$ROOT_DIR/Platforms/HarmonyOS/entry/src/main/resources/rawfile/providerspecs/$id.json"
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
  local core_copy="$ROOT_DIR/Shared/SwiftCore/Sources/QuotaGlanceCore/Resources/ProviderSpecs/kimi.json"
  printf '\n' >> "$core_copy"
  assert_fails /bin/bash "$PARITY_SCRIPT"
  restore_backup "$TEST_ROOT/$core_copy.src" "$core_copy"
  /bin/bash "$PARITY_SCRIPT" >/dev/null \
    || fail "verify-provider-parity.sh still failing after restoring the spec copy"
}

test_tampered_harmonyos_spec_copy_is_red() {
  local harmonyos_copy="$ROOT_DIR/Platforms/HarmonyOS/entry/src/main/resources/rawfile/providerspecs/deepSeek.json"
  printf ' ' >> "$harmonyos_copy"
  assert_fails /bin/bash "$PARITY_SCRIPT"
  restore_backup "$TEST_ROOT/$harmonyos_copy.harmonyos" "$harmonyos_copy"
  /bin/bash "$PARITY_SCRIPT" >/dev/null \
    || fail "verify-provider-parity.sh still failing after restoring the spec copy"
}

test_missing_contract_case_registration_is_red() {
  /bin/cp "$CONTRACT_TEST" "$TEST_ROOT/Contract.test.ets.bak"
  /usr/bin/python3 - "$CONTRACT_TEST" <<'PY'
from pathlib import Path
import re, sys
path = Path(sys.argv[1])
text = path.read_text()
# Remove the first case object that has name: 'balance' and provider deepSeek
pattern = re.compile(
    r"\s*\{\s*provider:\s*'deepSeek',\s*name:\s*'balance',[\s\S]*?\},",
    re.M,
)
new, n = pattern.subn("\n", text, count=1)
if n != 1:
    raise SystemExit("could not remove deepSeek balance CONTRACT_CASES entry")
path.write_text(new)
PY
  assert_fails /bin/bash "$PARITY_SCRIPT"
  /bin/cp "$TEST_ROOT/Contract.test.ets.bak" "$CONTRACT_TEST"
  /bin/bash "$PARITY_SCRIPT" >/dev/null \
    || fail "verify-provider-parity.sh still failing after restoring CONTRACT_CASES"
}

test_invalid_refresh_lifecycle_fixture_is_red() {
  /bin/cp "$LIFECYCLE_INPUT" "$TEST_ROOT/all-success-input.json.bak"
  /usr/bin/python3 - "$LIFECYCLE_INPUT" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = json.loads(path.read_text())
data.pop("notificationPermission", None)
path.write_text(json.dumps(data))
PY
  assert_fails /bin/bash "$PARITY_SCRIPT"
  /bin/cp "$TEST_ROOT/all-success-input.json.bak" "$LIFECYCLE_INPUT"
  /bin/bash "$PARITY_SCRIPT" >/dev/null \
    || fail "verify-provider-parity.sh still failing after restoring lifecycle fixture"
}

backup_spec_copies
test_parity_script_exists
test_current_tree_is_green
test_tampered_core_spec_copy_is_red
test_tampered_harmonyos_spec_copy_is_red
test_missing_contract_case_registration_is_red
test_invalid_refresh_lifecycle_fixture_is_red

echo "Provider parity tests passed"
