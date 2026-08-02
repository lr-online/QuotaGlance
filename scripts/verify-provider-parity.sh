#!/usr/bin/env bash
# Verify provider parity across the shared contracts and both platforms:
#   1. Swift ProviderID.allCases == ArkTS ProviderID union members.
#   2. Contracts/Providers/<dir>/ has spec.json plus complete
#      <case>-response/-expected/-requests triples.
#   3. Contracts/Aggregation and Contracts/Alerts have complete
#      <case>-input/-expected pairs.
#   4. Every provider contract case is registered in ArkTS CONTRACT_CASES.
#   5. Registered ArkTS step URLs match the requests fixtures.
#   6. Each spec.json is byte-identical to its copies under
#      Sources/QuotaGlanceCore/Resources/ProviderSpecs/<id>.json and
#      HarmonyOS/entry/src/main/resources/rawfile/providerspecs/<id>.json.
#   7. HarmonyOS ohosTest contract copies match Contracts/Providers,
#      Contracts/Aggregation, and Contracts/Alerts
#      (same scope as scripts/sync-contracts-to-harmonyos.sh).
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

  if ! diff_output="$(diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"))"; then
    fail "$label differ:"$'\n'"$diff_output"
  fi
}

compare_ordered_lists() {
  local label="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$expected" != "$actual" ]]; then
    fail "$label differ (order is part of the persisted protocol):"$'\n'"expected:"$'\n'"$expected"$'\n'"actual:"$'\n'"$actual"
  fi
}

# --- Check 1: Swift ProviderID.allCases == ArkTS ProviderID union -----------

check_provider_id_sets() {
  [[ -f "$SWIFT_PROVIDER_FILE" ]] || { fail "missing $SWIFT_PROVIDER_FILE"; return; }
  [[ -f "$ARKTS_PROVIDER_FILE" ]] || { fail "missing $ARKTS_PROVIDER_FILE"; return; }

  local swift_ids swift_ids_order arkts_ids arkts_array_ids arkts_known_ids spec_ids
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

  [[ -n "$swift_ids" ]] || { fail "could not extract ProviderID allCases from $SWIFT_PROVIDER_FILE"; return; }
  [[ -n "$arkts_ids" ]] || { fail "could not extract ProviderID union from $ARKTS_PROVIDER_FILE"; return; }
  [[ -n "$arkts_array_ids" ]] || { fail "could not extract ALL_PROVIDER_IDS from $ARKTS_PROVIDER_FILE"; return; }
  [[ -n "$arkts_known_ids" ]] || { fail "could not extract KNOWN_PROVIDER_IDS from $ARKTS_SPEC_FILE"; return; }
  [[ -n "$spec_ids" ]] || { fail "could not extract provider ids from $CONTRACTS_DIR"; return; }

  compare_sets "ProviderID sets (Swift allCases vs ArkTS union)" "$swift_ids" "$arkts_ids"
  compare_sets "ProviderID sets (Swift allCases vs ArkTS ALL_PROVIDER_IDS)" "$swift_ids" "$(printf '%s\n' "$arkts_array_ids" | sort -u)"
  compare_sets "ProviderID sets (Swift allCases vs ArkTS KNOWN_PROVIDER_IDS)" "$swift_ids" "$arkts_known_ids"
  compare_sets "ProviderID sets (Swift allCases vs Contracts specs)" "$swift_ids" "$spec_ids"
  compare_ordered_lists "ProviderID order (Swift allCases vs ArkTS ALL_PROVIDER_IDS)" "$swift_ids_order" "$arkts_array_ids"
}

# --- Check 2: shared protocol enums and spec-engine allow-lists -------------

check_protocol_allow_lists() {
  local swift_regions arkts_regions arkts_known_regions
  local swift_kinds arkts_kinds arkts_known_kinds
  local swift_errors arkts_errors swift_fields arkts_fields
  local swift_version arkts_version

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

  compare_sets "ProviderRegion values (Swift vs ArkTS)" "$swift_regions" "$arkts_regions"
  compare_sets "ProviderRegion values (Swift vs ArkTS validator)" "$swift_regions" "$arkts_known_regions"
  compare_sets "ProviderCredentialKind values (Swift vs ArkTS)" "$swift_kinds" "$arkts_kinds"
  compare_sets "ProviderCredentialKind values (Swift vs ArkTS validator)" "$swift_kinds" "$arkts_known_kinds"
  compare_sets "provider error tokens (Swift vs ArkTS)" "$swift_errors" "$arkts_errors"
  compare_sets "snapshot field allow-list (Swift vs ArkTS)" "$swift_fields" "$arkts_fields"
  [[ -n "$swift_version" && -n "$arkts_version" ]] \
    || fail "could not extract provider spec engine versions"
  [[ "$swift_version" == "$arkts_version" ]] \
    || fail "provider spec engine versions differ: Swift=$swift_version ArkTS=$arkts_version"

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

# --- Check 5: aggregation and alert fixture pairs are complete --------------

check_paired_contract_fixtures() {
  local contract_name contract_dir fixture fixture_name cases case_name
  local -a case_names

  for contract_name in Aggregation Alerts; do
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

# --- Check 6: ArkTS CONTRACT_CASES covers provider contract fixtures --------

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

# --- Check 7: ArkTS CONTRACT_CASES step URLs match requests fixtures --------

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

# --- Check 8: spec.json copies are byte-identical ---------------------------

check_spec_copies() {
  [[ -d "$CONTRACTS_DIR" ]] || { fail "missing $CONTRACTS_DIR"; return; }

  local spec id core_copy harmonyos_copy
  for spec in "$CONTRACTS_DIR"/*/spec.json; do
    [[ -f "$spec" ]] || continue
    id="$(extract_spec_id "$spec")"
    core_copy="$CORE_SPEC_DIR/$id.json"
    harmonyos_copy="$HARMONYOS_SPEC_DIR/$id.json"

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
  done

  # Stale copies whose provider directory no longer exists.
  local copy
  for copy in "$CORE_SPEC_DIR"/*.json "$HARMONYOS_SPEC_DIR"/*.json; do
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

# --- Check 9: ohosTest contract copies match Contracts/ ---------------------

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

  # Aggregation and alerts trees: contracts/aggregation|alerts/ match
  # Contracts/Aggregation|Alerts/.
  local src_dir dst_name
  for pair in "Aggregation aggregation" "Alerts alerts"; do
    src_dir="${pair%% *}"
    dst_name="${pair##* }"
    if ! diff_output="$(diff -r "$REPO_ROOT/Contracts/$src_dir" "$OHOSTEST_CONTRACTS_DIR/$dst_name" 2>&1)"; then
      fail "ohosTest contract copies for Contracts/$src_dir are out of sync ($hint):"$'\n'"$diff_output"
    fi
  done

  # No unexpected top-level entries beyond providers and aggregation/alerts.
  local entry
  for entry in "$OHOSTEST_CONTRACTS_DIR"/*; do
    [[ -e "$entry" ]] || continue
    name="$(basename "$entry")"
    [[ "$name" == "aggregation" || "$name" == "alerts" ]] && continue
    [[ -d "$CONTRACTS_DIR/$name" ]] \
      || fail "ohosTest contract copies have unexpected entry '$name' ($hint)"
  done
}

check_provider_id_sets
check_protocol_allow_lists
check_usage_provider_interface
check_contract_fixtures
check_paired_contract_fixtures
check_contract_case_registration
check_contract_case_step_urls
check_spec_copies
check_ohostest_contracts

if (( errors > 0 )); then
  echo "FAIL: provider parity check found $errors problem(s)" >&2
  exit 1
fi

echo "OK: ProviderID sets match (Swift <-> ArkTS)"
echo "OK: protocol enums, error tokens, snapshot fields, and spec versions match"
echo "OK: UsageProvider shared interface members are present on both platforms"
echo "OK: contract fixture triples complete under Contracts/Providers/"
echo "OK: aggregation and alert contract fixture pairs are complete"
echo "OK: every provider contract fixture case is registered in ArkTS CONTRACT_CASES"
echo "OK: ArkTS CONTRACT_CASES step URLs match requests fixtures"
echo "OK: spec.json copies byte-identical (Contracts <-> Swift core <-> HarmonyOS)"
echo "OK: ohosTest contract copies in sync with Contracts/ (Providers + Aggregation + Alerts)"
