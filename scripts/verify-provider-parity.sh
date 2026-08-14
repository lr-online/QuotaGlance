#!/usr/bin/env bash
# Verify provider parity across the shared contracts and four platforms:
#   1. Swift ProviderID.allCases == ArkTS ProviderID union members == Rust
#      `ProviderID` enum raw values (and similarly Kotlin in
#      verify-android-parity.sh).
#   2. Contracts/Providers/<dir>/ has spec.json plus complete
#      <case>-response/-expected/-requests triples.
#   3. Contracts/Aggregation, Contracts/Alerts, and Contracts/RefreshLifecycle
#      have complete <case>-input/-expected pairs.
#   4. Every provider contract case is registered in ArkTS CONTRACT_CASES.
#   5. Registered ArkTS step URLs match the requests fixtures.
#   6. Each spec.json is byte-identical to its copies under
#      Sources/QuotaGlanceCore/Resources/ProviderSpecs/<id>.json,
#      HarmonyOS/entry/src/main/resources/rawfile/providerspecs/<id>.json, and
#      Windows/src-tauri/assets/providerspecs/<id>.json.
#   7. HarmonyOS ohosTest contract copies match Contracts/Providers,
#      Contracts/Aggregation, Contracts/Alerts, and Contracts/RefreshLifecycle
#      (same scope as scripts/sync-contracts-to-harmonyos.sh).
#   8. Windows portable-client contract copies match Contracts/{Providers,
#      Aggregation, Alerts, RefreshLifecycle} (same scope as
#      scripts/sync-contracts-to-windows.sh).
# Exits 1 on the first failing section after printing every error it found.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACTS_DIR="$REPO_ROOT/Contracts/Providers"
SWIFT_PROVIDER_FILE="$REPO_ROOT/Sources/QuotaGlanceCore/Domain/Provider.swift"
ARKTS_PROVIDER_FILE="$REPO_ROOT/HarmonyOS/entry/src/main/ets/providers/UsageProvider.ets"
SWIFT_USAGE_FILE="$REPO_ROOT/Sources/QuotaGlanceCore/Providers/UsageProvider.swift"
SWIFT_SPEC_FILE="$REPO_ROOT/Sources/QuotaGlanceCore/Providers/ProviderSpec.swift"
ARKTS_SPEC_FILE="$REPO_ROOT/HarmonyOS/entry/src/main/ets/providers/SpecDrivenProvider.ets"
CORE_SPEC_DIR="$REPO_ROOT/Sources/QuotaGlanceCore/Resources/ProviderSpecs"
HARMONYOS_SPEC_DIR="$REPO_ROOT/HarmonyOS/entry/src/main/resources/rawfile/providerspecs"
OHOSTEST_CONTRACTS_DIR="$REPO_ROOT/HarmonyOS/entry/src/ohosTest/resources/rawfile/contracts"
CONTRACT_TEST_FILE="$REPO_ROOT/HarmonyOS/entry/src/ohosTest/ets/test/Contract.test.ets"
WINDOWS_SPEC_DIR="$REPO_ROOT/Windows/src-tauri/assets/providerspecs"
WINDOWS_CONTRACTS_DIR="$REPO_ROOT/Windows/src-tauri/assets/contracts"
RUST_DOMAIN_FILE="$REPO_ROOT/Windows/src-tauri/src/domain.rs"
RUST_SPEC_FILE="$REPO_ROOT/Windows/src-tauri/src/providers/provider_spec.rs"
RUST_ERROR_FILE="$REPO_ROOT/Windows/src-tauri/src/providers/provider_error.rs"
ANDROID_PARITY_SCRIPT="$REPO_ROOT/scripts/verify-android-parity.sh"
WINDOWS_PARITY_SCRIPT="$REPO_ROOT/scripts/verify-windows-parity.sh"

errors=0

fail() {
  echo "error: $*" >&2
  errors=$((errors + 1))
}

extract_spec_id() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$1"
}

# Prints "providerId caseName" lines from CONTRACT_CASES object literals.
# Relies on each case listing provider: '…' then name: '…' (order as today).
extract_contract_cases() {
  sed -n '/^const CONTRACT_CASES/,/^];/p' "$CONTRACT_TEST_FILE" \
    | awk '
        /provider:/ {
          gsub(/.*provider: '\''/, ""); gsub(/'\''.*/, "");
          provider=$0
        }
        /name:/ {
          gsub(/.*name: '\''/, ""); gsub(/'\''.*/, "");
          if (provider != "") { print provider, $0; provider="" }
        }
      '
}
extract_single_quoted_array() {
  local file="$1"
  local marker="$2"
  sed -n "/$marker/,/^[[:space:]]*\];/p" "$file" \
    | grep -oE "'[^']+'" \
    | tr -d "'" \
    || true
}

extract_double_quoted_array() {
  local file="$1"
  local marker="$2"
  sed -n "/$marker/,/^[[:space:]]*\]/p" "$file" \
    | grep -oE '"[A-Za-z][A-Za-z0-9]*"' \
    | tr -d '"' \
    || true
}

compare_sets() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  local diff_output

  expected="${expected//$'\r'/}"
  actual="${actual//$'\r'/}"

  if ! diff_output="$(diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"))"; then
    fail "$label differ:"$'\n'"$diff_output"
  fi
}

compare_ordered_lists() {
  local label="$1"
  local expected="$2"
  local actual="$3"

  expected="${expected//$'\r'/}"
  actual="${actual//$'\r'/}"

  if [[ "$expected" != "$actual" ]]; then
    fail "$label differ (order is part of the persisted protocol):"$'\n'"expected:"$'\n'"$expected"$'\n'"actual:"$'\n'"$actual"
  fi
}

extract_rust_provider_ids() {
  local file="$1"
  python3 - "$file" <<'PY' 2>/dev/null || true
import re
import sys
src = open(sys.argv[1]).read()
m = re.search(r"pub enum ProviderID\s*\{([^}]+)\}", src)
if not m:
    sys.exit(0)
print('\n'.join(re.findall(r'rename\s*=\s*"([^"]+)"', m.group(1))))
PY
}

extract_rust_const_array() {
  local file="$1"
  local name="$2"
  python3 - "$file" "$name" <<'PY' 2>/dev/null || true
import re
import sys
src = open(sys.argv[1]).read()
m = re.search(rf"pub const {re.escape(sys.argv[2])}:\s*[^=]*=\s*&?\s*\[(.*?)\]", src, re.DOTALL)
if not m:
    sys.exit(0)
strings = sorted(set(re.findall(r'"([^"]+)"', m.group(1))))
print('\n'.join(strings))
PY
}

extract_rust_const_int() {
  local file="$1"
  local name="$2"
  python3 - "$file" "$name" <<'PY' 2>/dev/null || true
import re
import sys
src = open(sys.argv[1]).read()
m = re.search(rf"pub const {re.escape(sys.argv[2])}:\s*u32\s*=\s*(\d+)", src)
if m:
    print(m.group(1))
PY
}

# --- Check 1: Swift ProviderID.allCases == ArkTS ProviderID union -----------

check_provider_id_sets() {
  [[ -f "$SWIFT_PROVIDER_FILE" ]] || { fail "missing $SWIFT_PROVIDER_FILE"; return; }
  [[ -f "$ARKTS_PROVIDER_FILE" ]] || { fail "missing $ARKTS_PROVIDER_FILE"; return; }

  local swift_ids swift_ids_order arkts_ids arkts_array_ids arkts_known_ids spec_ids
  local rust_ids rust_ids_order
  swift_ids_order="$(
    sed -n '/static let allCases/,/^    \]/p' "$SWIFT_PROVIDER_FILE" \
      | grep -oE '\.[A-Za-z][A-Za-z0-9]*' \
      | sed 's/^\.//'
  )"
  swift_ids="$(printf '%s\n' "$swift_ids_order" | sort -u)"
  arkts_ids="$(
    grep -oE '^export type ProviderID[^;]*' "$ARKTS_PROVIDER_FILE" \
      | grep -oE "'[^']+'" \
      | tr -d "'" \
      | sort -u
  )"
  arkts_array_ids="$(
    sed -n '/ALL_PROVIDER_IDS:/,/^\];/p' "$ARKTS_PROVIDER_FILE" \
      | grep -oE "'[^']+'" \
      | tr -d "'"
  )"
  arkts_known_ids="$(
    sed -n '/KNOWN_PROVIDER_IDS:/,/^\];/p' "$ARKTS_SPEC_FILE" \
      | grep -oE "'[^']+'" \
      | tr -d "'" \
      | sort -u
  )"
  spec_ids="$(
    for spec in "$CONTRACTS_DIR"/*/spec.json; do
      [[ -f "$spec" ]] || continue
      extract_spec_id "$spec"
    done | sort -u
  )"
  rust_ids_order="$(extract_rust_provider_ids "$RUST_DOMAIN_FILE")"
  rust_ids="$(printf '%s\n' "$rust_ids_order" | sort -u)"

  [[ -n "$swift_ids" ]] || { fail "could not extract ProviderID allCases from $SWIFT_PROVIDER_FILE"; return; }
  [[ -n "$arkts_ids" ]] || { fail "could not extract ProviderID union from $ARKTS_PROVIDER_FILE"; return; }
  [[ -n "$arkts_array_ids" ]] || { fail "could not extract ALL_PROVIDER_IDS from $ARKTS_PROVIDER_FILE"; return; }
  [[ -n "$arkts_known_ids" ]] || { fail "could not extract KNOWN_PROVIDER_IDS from $ARKTS_SPEC_FILE"; return; }
  [[ -n "$spec_ids" ]] || { fail "could not extract provider ids from $CONTRACTS_DIR"; return; }
  [[ -n "$rust_ids" ]] || { fail "could not extract ProviderID enum from $RUST_DOMAIN_FILE"; return; }

  compare_sets "ProviderID sets (Swift allCases vs ArkTS union)" "$swift_ids" "$arkts_ids"
  compare_sets "ProviderID sets (Swift allCases vs ArkTS ALL_PROVIDER_IDS)" "$swift_ids" "$(printf '%s\n' "$arkts_array_ids" | sort -u)"
  compare_sets "ProviderID sets (Swift allCases vs ArkTS KNOWN_PROVIDER_IDS)" "$swift_ids" "$arkts_known_ids"
  compare_sets "ProviderID sets (Swift allCases vs Contracts specs)" "$swift_ids" "$spec_ids"
  compare_sets "ProviderID sets (Swift allCases vs Rust enum)" "$swift_ids" "$rust_ids"
  compare_ordered_lists "ProviderID order (Swift allCases vs ArkTS ALL_PROVIDER_IDS)" "$swift_ids_order" "$arkts_array_ids"
  compare_ordered_lists "ProviderID order (Swift allCases vs Rust enum)" "$swift_ids_order" "$rust_ids_order"
}

# --- Check 2: shared protocol enums and spec-engine allow-lists -------------

check_protocol_allow_lists() {
  local swift_regions arkts_regions arkts_known_regions
  local swift_kinds arkts_kinds arkts_known_kinds
  local swift_errors arkts_errors swift_fields arkts_fields
  local swift_version arkts_version
  local rust_regions rust_kinds rust_errors rust_fields rust_version

  swift_regions="$(
    sed -n '/public enum ProviderRegion/,/public enum ProviderCredentialKind/p' "$SWIFT_PROVIDER_FILE" \
      | grep -oE '^[[:space:]]*case [A-Za-z][A-Za-z0-9]*' \
      | sed -E 's/^[[:space:]]*case //' \
      | sort -u
  )"
  arkts_regions="$(
    grep -oE "^export type ProviderRegion = [^;]+" "$ARKTS_PROVIDER_FILE" \
      | grep -oE "'[^']+'" \
      | tr -d "'" \
      | sort -u
  )"
  arkts_known_regions="$(
    grep -oE "const KNOWN_REGIONS: string\[\] = \[[^]]*\]" "$ARKTS_SPEC_FILE" \
      | grep -oE "'[^']+'" \
      | tr -d "'" \
      | sort -u
  )"

  swift_kinds="$(
    sed -n '/public enum ProviderCredentialKind/,/public struct ProviderProfile/p' "$SWIFT_PROVIDER_FILE" \
      | grep -oE '^[[:space:]]*case [A-Za-z][A-Za-z0-9]*' \
      | sed -E 's/^[[:space:]]*case //' \
      | sort -u
  )"
  arkts_kinds="$(
    grep -oE "^export type ProviderCredentialKind = [^;]+" "$ARKTS_PROVIDER_FILE" \
      | grep -oE "'[^']+'" \
      | tr -d "'" \
      | sort -u
  )"
  arkts_known_kinds="$(
    grep -oE "const KNOWN_KINDS: string\[\] = \[[^]]*\]" "$ARKTS_SPEC_FILE" \
      | grep -oE "'[^']+'" \
      | tr -d "'" \
      | sort -u
  )"

  swift_errors="$(
    sed -n '/knownErrorTokens: Set/,/^    \]/p' "$SWIFT_SPEC_FILE" \
      | grep -oE '"[A-Za-z][A-Za-z0-9]*"' \
      | tr -d '"' \
      | sort -u
  )"
  arkts_errors="$(
    extract_single_quoted_array "$ARKTS_SPEC_FILE" '^const KNOWN_ERROR_TOKENS:' \
      | sort -u
  )"
  swift_fields="$(
    extract_double_quoted_array "$SWIFT_SPEC_FILE" 'knownSnapshotFields: Set' \
      | sort -u
  )"
  arkts_fields="$(
    extract_single_quoted_array "$ARKTS_SPEC_FILE" '^const KNOWN_SNAPSHOT_FIELDS:' \
      | sort -u
  )"
  swift_version="$(sed -n 's/.*supportedSpecVersion = \([0-9][0-9]*\).*/\1/p' "$SWIFT_SPEC_FILE")"
  arkts_version="$(sed -n 's/.*SUPPORTED_SPEC_VERSION = \([0-9][0-9]*\).*/\1/p' "$ARKTS_SPEC_FILE")"

  rust_regions="$(extract_rust_const_array "$RUST_SPEC_FILE" KNOWN_REGIONS)"
  rust_kinds="$(extract_rust_const_array "$RUST_SPEC_FILE" KNOWN_CREDENTIAL_KINDS)"
  rust_errors="$(extract_rust_const_array "$RUST_ERROR_FILE" KNOWN_ERROR_TOKENS)"
  rust_fields="$(extract_rust_const_array "$RUST_SPEC_FILE" KNOWN_SNAPSHOT_FIELDS)"
  rust_version="$(extract_rust_const_int "$RUST_SPEC_FILE" SPEC_VERSION)"

  compare_sets "ProviderRegion values (Swift vs ArkTS)" "$swift_regions" "$arkts_regions"
  compare_sets "ProviderRegion values (Swift vs ArkTS validator)" "$swift_regions" "$arkts_known_regions"
  compare_sets "ProviderRegion values (Swift vs Rust)" "$swift_regions" "$rust_regions"
  compare_sets "ProviderCredentialKind values (Swift vs ArkTS)" "$swift_kinds" "$arkts_kinds"
  compare_sets "ProviderCredentialKind values (Swift vs ArkTS validator)" "$swift_kinds" "$arkts_known_kinds"
  compare_sets "ProviderCredentialKind values (Swift vs Rust)" "$swift_kinds" "$rust_kinds"
  compare_sets "provider error tokens (Swift vs ArkTS)" "$swift_errors" "$arkts_errors"
  compare_sets "provider error tokens (Swift vs Rust)" "$swift_errors" "$rust_errors"
  compare_sets "snapshot field allow-list (Swift vs ArkTS)" "$swift_fields" "$arkts_fields"
  compare_sets "snapshot field allow-list (Swift vs Rust)" "$swift_fields" "$rust_fields"
  [[ -n "$swift_version" && -n "$arkts_version" && -n "$rust_version" ]] \
    || fail "could not extract provider spec engine versions from one or more platforms"
  [[ "$swift_version" == "$arkts_version" ]] \
    || fail "provider spec engine versions differ: Swift=$swift_version ArkTS=$arkts_version"
  [[ "$swift_version" == "$rust_version" ]] \
    || fail "provider spec engine versions differ: Swift=$swift_version Rust=$rust_version"

  local spec spec_version
  for spec in "$CONTRACTS_DIR"/*/spec.json; do
    [[ -f "$spec" ]] || continue
    spec_version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["specVersion"])' "$spec")"
    [[ "$spec_version" == "$swift_version" ]] \
      || fail "spec '$spec' has version $spec_version, expected $swift_version"
  done
}

# --- Check 3: UsageProvider's shared interface remains present --------------

check_usage_provider_interface() {
  local swift_interface arkts_interface marker
  swift_interface="$(sed -n '/public protocol UsageProvider/,/^}/p' "$SWIFT_USAGE_FILE")"
  arkts_interface="$(sed -n '/export interface UsageProvider/,/^}/p' "$ARKTS_PROVIDER_FILE")"

  [[ -n "$swift_interface" ]] || { fail "could not extract Swift UsageProvider interface"; return; }
  [[ -n "$arkts_interface" ]] || { fail "could not extract ArkTS UsageProvider interface"; return; }

  for marker in 'var id' 'var descriptor' 'func detect' 'func fetch'; do
    grep -Fq "$marker" <<< "$swift_interface" \
      || fail "Swift UsageProvider is missing shared member '$marker'"
  done
  for marker in 'readonly id' 'readonly descriptor' 'detect(' 'fetch('; do
    grep -Fq "$marker" <<< "$arkts_interface" \
      || fail "ArkTS UsageProvider is missing shared member '$marker'"
  done
}

# --- Check 4: contract fixture triples are complete -------------------------

check_contract_fixtures() {
  [[ -d "$CONTRACTS_DIR" ]] || { fail "missing $CONTRACTS_DIR"; return; }

  local dir provider cases fixture fixture_name
  for dir in "$CONTRACTS_DIR"/*/; do
    provider="$(basename "$dir")"
    [[ -f "$dir/spec.json" ]] || fail "Contracts/Providers/$provider: missing spec.json"

    cases="$(
      for fixture in "$dir"/*.json; do
        [[ -f "$fixture" ]] || continue
        fixture_name="${fixture##*/}"
        if [[ "$fixture_name" =~ ^(.+)-(response|requests|expected)[0-9]*\.json$ ]]; then
          printf '%s\n' "${BASH_REMATCH[1]}"
        fi
      done | sort -u
    )"
    [[ -n "$cases" ]] || fail "Contracts/Providers/$provider: no <case>-*.json fixtures found"

    local case_name
    for case_name in $cases; do
      [[ -f "$dir/$case_name-response.json" ]] \
        || fail "Contracts/Providers/$provider: case '$case_name' missing $case_name-response.json"
      [[ -f "$dir/$case_name-expected.json" ]] \
        || fail "Contracts/Providers/$provider: case '$case_name' missing $case_name-expected.json"
      [[ -f "$dir/$case_name-requests.json" ]] \
        || fail "Contracts/Providers/$provider: case '$case_name' missing $case_name-requests.json"
    done
  done
}

# --- Check 5: paired behavior-contract fixtures are complete ----------------

check_paired_contract_fixtures() {
  local contract_name contract_dir fixture fixture_name cases case_name
  local -a case_names

  for contract_name in Aggregation Alerts RefreshLifecycle; do
    contract_dir="$REPO_ROOT/Contracts/$contract_name"
    if [[ ! -d "$contract_dir" ]]; then
      fail "missing $contract_dir"
      continue
    fi

    case_names=()
    for fixture in "$contract_dir"/*.json; do
      [[ -f "$fixture" ]] || continue
      fixture_name="${fixture##*/}"
      if [[ "$fixture_name" =~ ^(.+)-(input|expected)\.json$ ]]; then
        case_names+=("${BASH_REMATCH[1]}")
      else
        fail "Contracts/$contract_name: unexpected fixture name '$fixture_name'"
      fi
    done

    cases="$(printf '%s\n' "${case_names[@]}" | sort -u)"
    if [[ -z "$cases" ]]; then
      fail "Contracts/$contract_name: no <case>-{input,expected}.json fixtures found"
      continue
    fi

    for case_name in $cases; do
      [[ -f "$contract_dir/$case_name-input.json" ]] \
        || fail "Contracts/$contract_name: case '$case_name' missing $case_name-input.json"
      [[ -f "$contract_dir/$case_name-expected.json" ]] \
        || fail "Contracts/$contract_name: case '$case_name' missing $case_name-expected.json"
    done
  done
}

# --- Check 6: refresh-lifecycle fixtures have the public seam shape --------

check_refresh_lifecycle_fixture_schema() {
  local contract_dir="$REPO_ROOT/Contracts/RefreshLifecycle"
  [[ -d "$contract_dir" ]] || { fail "missing $contract_dir"; return; }

  local status=0
  python3 - "$contract_dir" <<'PY' || status=$?
import json
import sys
from pathlib import Path

directory = Path(sys.argv[1])
errors = []
valid_outcomes = {"success", "failure", "superseded"}
valid_effects = {
    "persistSnapshots",
    "evaluateAlerts",
    "persistAlertEpisodes",
    "notificationCandidates",
    "deliverNotifications",
    "removeDeletedAccounts",
    "invalidateQuickViews",
}

def error(case, message):
    errors.append(f"error: Contracts/RefreshLifecycle/{case}: {message}")

for input_path in sorted(directory.glob("*-input.json")):
    case = input_path.name.removesuffix("-input.json")
    expected_path = directory / f"{case}-expected.json"
    try:
        input_data = json.loads(input_path.read_text())
        expected_data = json.loads(expected_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        error(case, f"invalid JSON: {exc}")
        continue

    missing_input = [
        key for key in ("invocation", "accounts", "snapshotsBefore", "results", "notificationPermission", "notificationDelivery")
        if key not in input_data
    ]
    missing_expected = [key for key in ("snapshots", "accounts", "effects") if key not in expected_data]
    for key in missing_input:
        error(case, f"input missing required key '{key}'")
    for key in missing_expected:
        error(case, f"expected missing required key '{key}'")
    if missing_input or missing_expected:
        continue

    invocation = input_data["invocation"]
    scope = invocation.get("scope") if isinstance(invocation, dict) else None
    if scope not in {"allEnabled", "account"}:
        error(case, "invocation.scope must be 'allEnabled' or 'account'")
    if scope == "account" and not isinstance(invocation.get("accountID"), str):
        error(case, "account-scoped invocation needs string accountID")
    if scope == "allEnabled" and "accountID" in invocation:
        error(case, "allEnabled invocation must not include accountID")

    accounts = input_data["accounts"]
    if not isinstance(accounts, list):
        error(case, "accounts must be an array")
        continue
    account_ids = [row.get("id") for row in accounts if isinstance(row, dict)]
    if len(account_ids) != len(accounts) or any(not isinstance(value, str) for value in account_ids):
        error(case, "each account needs string id")
    elif len(set(account_ids)) != len(account_ids):
        error(case, "account ids must be unique")
    elif scope == "account" and invocation["accountID"] not in account_ids:
        error(case, "account-scoped invocation references an unknown account")

    if input_data["notificationPermission"] not in {"granted", "denied"}:
        error(case, "notificationPermission must be 'granted' or 'denied'")
    if input_data["notificationDelivery"] not in {"succeeds", "fails"}:
        error(case, "notificationDelivery must be 'succeeds' or 'fails'")

    for result in input_data["results"]:
        if not isinstance(result, dict):
            error(case, "each result must be an object")
            continue
        if result.get("accountID") not in account_ids:
            error(case, "result references an unknown account")
        outcome = result.get("outcome")
        if outcome not in valid_outcomes:
            error(case, "result outcome must be success, failure, or superseded")
        elif outcome == "success" and "health" not in result:
            error(case, "successful result needs health")
        elif outcome == "failure" and not isinstance(result.get("failure"), str):
            error(case, "failed result needs string failure")

    for effect in expected_data["effects"]:
        if not isinstance(effect, dict) or effect.get("kind") not in valid_effects:
            error(case, "expected effect has an unknown kind")
            continue
        if effect["kind"] == "invalidateQuickViews":
            if set(effect) != {"kind"}:
                error(case, "invalidateQuickViews has no payload")
        elif not isinstance(effect.get("accountIDs"), list):
            error(case, f"{effect['kind']} needs accountIDs array")

for message in errors:
    print(message, file=sys.stderr)
sys.exit(1 if errors else 0)
PY
  (( status == 0 )) || fail "refresh-lifecycle fixture schema is invalid (see errors above)"
}

# --- Check 7: ArkTS CONTRACT_CASES covers provider contract fixtures --------

check_contract_case_registration() {
  [[ -f "$CONTRACT_TEST_FILE" ]] || { fail "missing $CONTRACT_TEST_FILE"; return; }
  [[ -d "$CONTRACTS_DIR" ]] || { fail "missing $CONTRACTS_DIR"; return; }

  local registered
  registered="$(extract_contract_cases | sort -u)"

  local dir provider case_name key spec_id expected
  for dir in "$CONTRACTS_DIR"/*/; do
    provider="$(basename "$dir")"
    spec_id="$(extract_spec_id "$dir/spec.json")"
    for expected in "$dir"*-expected.json; do
      [[ -f "$expected" ]] || continue
      case_name="$(basename "$expected" | sed -E 's/-expected\.json$//')"
      key="$spec_id $case_name"
      if ! grep -Fxq "$key" <<< "$registered"; then
        fail "CONTRACT_CASES missing case '$case_name' for provider '$spec_id' (from Contracts/Providers/$provider)"
      fi
    done
  done
}

# --- Check 8: ArkTS CONTRACT_CASES step URLs match requests fixtures --------

check_contract_case_step_urls() {
  [[ -f "$CONTRACT_TEST_FILE" ]] || { fail "missing $CONTRACT_TEST_FILE"; return; }
  [[ -d "$CONTRACTS_DIR" ]] || { fail "missing $CONTRACTS_DIR"; return; }

  local status=0
  python3 - "$REPO_ROOT" <<'PY' || status=$?
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
test = (root / "HarmonyOS/entry/src/ohosTest/ets/test/Contract.test.ets").read_text()
m = re.search(r"const CONTRACT_CASES: ContractCase\[\] = \[([\s\S]*?)\n\];", test)
if not m:
    print("error: could not find CONTRACT_CASES", file=sys.stderr)
    sys.exit(2)
body = m.group(1)

cases = []
i = 0
while True:
    start = body.find("{", i)
    if start < 0:
        break
    depth = 0
    for j, ch in enumerate(body[start:], start):
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                block = body[start:j + 1]
                i = j + 1
                break
    else:
        break
    provider = re.search(r"provider:\s*'([^']+)'", block)
    name = re.search(r"name:\s*'([^']+)'", block)
    urls = re.findall(r"url:\s*'([^']+)'", block)
    if provider and name:
        cases.append((provider.group(1), name.group(1), urls))

errors = 0
providers = root / "Contracts/Providers"
for spec_id, case_name, step_urls in cases:
    match_dir = None
    for directory in providers.iterdir():
        if not directory.is_dir():
            continue
        spec = directory / "spec.json"
        if not spec.exists():
            continue
        with spec.open() as spec_file:
            if json.load(spec_file)["id"] == spec_id:
                match_dir = directory
                break
    if match_dir is None:
        print(
            f"error: CONTRACT_CASES provider '{spec_id}' has no Contracts/Providers spec",
            file=sys.stderr,
        )
        errors += 1
        continue
    requests = match_dir / f"{case_name}-requests.json"
    if not requests.exists():
        continue
    with requests.open() as requests_file:
        expected_urls = [row["url"] for row in json.load(requests_file)]
    if step_urls != expected_urls:
        print(
            f"error: CONTRACT_CASES {spec_id}/{case_name} steps urls "
            f"{step_urls} != requests fixture {expected_urls}",
            file=sys.stderr,
        )
        errors += 1
sys.exit(1 if errors else 0)
PY

  if (( status == 2 )); then
    fail "could not parse CONTRACT_CASES for step URL check"
  elif (( status != 0 )); then
    fail "CONTRACT_CASES step URLs out of sync with *-requests.json fixtures (see errors above)"
  fi
}

# --- Check 9: spec.json copies are byte-identical ---------------------------

check_spec_copies() {
  [[ -d "$CONTRACTS_DIR" ]] || { fail "missing $CONTRACTS_DIR"; return; }

  local spec id core_copy harmonyos_copy windows_copy
  for spec in "$CONTRACTS_DIR"/*/spec.json; do
    [[ -f "$spec" ]] || continue
    id="$(extract_spec_id "$spec")"
    core_copy="$CORE_SPEC_DIR/$id.json"
    harmonyos_copy="$HARMONYOS_SPEC_DIR/$id.json"
    windows_copy="$WINDOWS_SPEC_DIR/$id.json"

    if [[ ! -f "$core_copy" ]]; then
      fail "spec '$id': missing Swift copy $core_copy (run scripts/sync-specs-to-core.sh)"
    elif ! cmp -s "$spec" "$core_copy"; then
      fail "spec '$id': $core_copy differs from $spec (run scripts/sync-specs-to-core.sh)"
    fi

    if [[ ! -f "$harmonyos_copy" ]]; then
      fail "spec '$id': missing HarmonyOS copy $harmonyos_copy (run scripts/sync-specs-to-harmonyos.sh)"
    elif ! cmp -s "$spec" "$harmonyos_copy"; then
      fail "spec '$id': $harmonyos_copy differs from $spec (run scripts/sync-specs-to-harmonyos.sh)"
    fi

    if [[ ! -f "$windows_copy" ]]; then
      fail "spec '$id': missing Windows copy $windows_copy (run scripts/sync-specs-to-windows.sh)"
    elif ! cmp -s "$spec" "$windows_copy"; then
      fail "spec '$id': $windows_copy differs from $spec (run scripts/sync-specs-to-windows.sh)"
    fi
  done

  # Stale copies whose provider directory no longer exists.
  local copy
  for copy in "$CORE_SPEC_DIR"/*.json "$HARMONYOS_SPEC_DIR"/*.json "$WINDOWS_SPEC_DIR"/*.json; do
    [[ -f "$copy" ]] || continue
    id="$(extract_spec_id "$copy")"
    local found=1 candidate
    for candidate in "$CONTRACTS_DIR"/*/spec.json; do
      [[ -f "$candidate" ]] || continue
      if [[ "$(extract_spec_id "$candidate")" == "$id" ]]; then
        found=0
        break
      fi
    done
    (( found == 0 )) || fail "stale spec copy $copy: no Contracts/Providers spec with id '$id'"
  done
}

# --- Check 10: ohosTest contract copies match Contracts/ --------------------

check_ohostest_contracts() {
  [[ -d "$CONTRACTS_DIR" ]] || { fail "missing $CONTRACTS_DIR"; return; }
  if [[ ! -d "$OHOSTEST_CONTRACTS_DIR" ]]; then
    fail "missing $OHOSTEST_CONTRACTS_DIR (run scripts/sync-contracts-to-harmonyos.sh)"
    return
  fi

  local hint="run scripts/sync-contracts-to-harmonyos.sh"
  local dir name diff_output

  # Provider trees: contracts/<provider>/ matches Contracts/Providers/<provider>/.
  for dir in "$CONTRACTS_DIR"/*/; do
    name="$(basename "$dir")"
    if ! diff_output="$(diff -r "$dir" "$OHOSTEST_CONTRACTS_DIR/$name" 2>&1)"; then
      fail "ohosTest contract copies for provider '$name' are out of sync ($hint):"$'\n'"$diff_output"
    fi
  done

  # Behavior-contract trees map to lowercase rawfile directories.
  local src_dir dst_name
  for pair in "Aggregation aggregation" "Alerts alerts" "RefreshLifecycle refreshlifecycle"; do
    src_dir="${pair%% *}"
    dst_name="${pair##* }"
    if ! diff_output="$(diff -r "$REPO_ROOT/Contracts/$src_dir" "$OHOSTEST_CONTRACTS_DIR/$dst_name" 2>&1)"; then
      fail "ohosTest contract copies for Contracts/$src_dir are out of sync ($hint):"$'\n'"$diff_output"
    fi
  done

  # No unexpected top-level entries beyond providers and behavior-contract trees.
  local entry
  for entry in "$OHOSTEST_CONTRACTS_DIR"/*; do
    [[ -e "$entry" ]] || continue
    name="$(basename "$entry")"
    [[ "$name" == "aggregation" || "$name" == "alerts" || "$name" == "refreshlifecycle" ]] && continue
    [[ -d "$CONTRACTS_DIR/$name" ]] \
      || fail "ohosTest contract copies have unexpected entry '$name' ($hint)"
  done
}

# --- Check 11: Windows contract copies match Contracts/ ---------------------

check_windows_contracts() {
  [[ -d "$CONTRACTS_DIR" ]] || { fail "missing $CONTRACTS_DIR"; return; }
  if [[ ! -d "$WINDOWS_CONTRACTS_DIR" ]]; then
    fail "missing $WINDOWS_CONTRACTS_DIR (run scripts/sync-contracts-to-windows.sh)"
    return
  fi

  local hint="run scripts/sync-contracts-to-windows.sh"
  local dir name diff_output

  # Provider trees: contracts/Providers/<provider>/ mirrors Contracts/Providers/<provider>/.
  for dir in "$CONTRACTS_DIR"/*/; do
    name="$(basename "$dir")"
    if ! diff_output="$(diff -r "$dir" "$WINDOWS_CONTRACTS_DIR/Providers/$name" 2>&1)"; then
      fail "Windows contract copies for provider '$name' are out of sync ($hint):"$'\n'"$diff_output"
    fi
  done

  # Behavior-contract trees map to lowercase asset directories.
  local src_dir dst_name
  for pair in "Aggregation aggregation" "Alerts alerts" "RefreshLifecycle refreshlifecycle"; do
    src_dir="${pair%% *}"
    dst_name="${pair##* }"
    if ! diff_output="$(diff -r "$REPO_ROOT/Contracts/$src_dir" "$WINDOWS_CONTRACTS_DIR/$dst_name" 2>&1)"; then
      fail "Windows contract copies for Contracts/$src_dir are out of sync ($hint):"$'\n'"$diff_output"
    fi
  done

  # No unexpected top-level entries beyond Providers and behavior-contract trees.
  local entry
  for entry in "$WINDOWS_CONTRACTS_DIR"/*; do
    [[ -e "$entry" ]] || continue
    name="$(basename "$entry")"
    [[ "$name" == "Providers" || "$name" == "aggregation" || "$name" == "alerts" || "$name" == "refreshlifecycle" ]] && continue
    [[ -d "$WINDOWS_CONTRACTS_DIR/Providers/$name" ]] \
      || fail "Windows contract copies have unexpected entry '$name' ($hint)"
  done
}

# --- Check 12: per-platform parity scripts exist ----------------------------

check_android_windows_parity_scripts_exist() {
  [[ -f "$ANDROID_PARITY_SCRIPT" ]] \
    || fail "missing $ANDROID_PARITY_SCRIPT"
  [[ -x "$ANDROID_PARITY_SCRIPT" ]] \
    || fail "$ANDROID_PARITY_SCRIPT is not executable (chmod +x scripts/verify-android-parity.sh)"
  [[ -f "$WINDOWS_PARITY_SCRIPT" ]] \
    || fail "missing $WINDOWS_PARITY_SCRIPT"
  [[ -x "$WINDOWS_PARITY_SCRIPT" ]] \
    || fail "$WINDOWS_PARITY_SCRIPT is not executable (chmod +x scripts/verify-windows-parity.sh)"
}

check_provider_id_sets
check_protocol_allow_lists
check_usage_provider_interface
check_contract_fixtures
check_paired_contract_fixtures
check_refresh_lifecycle_fixture_schema
check_contract_case_registration
check_contract_case_step_urls
check_spec_copies
check_ohostest_contracts
check_windows_contracts
check_android_windows_parity_scripts_exist

if (( errors > 0 )); then
  echo "FAIL: provider parity check found $errors problem(s)" >&2
  exit 1
fi

echo "OK: ProviderID sets match (Swift <-> ArkTS <-> Rust)"
echo "OK: protocol enums, error tokens, snapshot fields, and spec versions match"
echo "OK: UsageProvider shared interface members are present on both platforms"
echo "OK: contract fixture triples complete under Contracts/Providers/"
echo "OK: aggregation, alert, and refresh-lifecycle fixture pairs are complete"
echo "OK: refresh-lifecycle fixtures conform to the shared seam schema"
echo "OK: every provider contract fixture case is registered in ArkTS CONTRACT_CASES"
echo "OK: ArkTS CONTRACT_CASES step URLs match requests fixtures"
echo "OK: spec.json copies byte-identical (Contracts <-> Swift core <-> HarmonyOS <-> Windows)"
echo "OK: ohosTest contract copies in sync with Contracts/ (Providers + Aggregation + Alerts + RefreshLifecycle)"
echo "OK: Windows contract copies in sync with Contracts/ (Providers + Aggregation + Alerts + RefreshLifecycle)"
