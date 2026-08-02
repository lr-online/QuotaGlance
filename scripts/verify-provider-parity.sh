#!/usr/bin/env bash
# Verify provider parity across the shared contracts and both platforms:
#   1. Swift ProviderID.allCases == ArkTS ProviderID union members.
#   2. Contracts/Providers/<dir>/ has spec.json plus complete
#      <case>-response/-expected/-requests triples.
#   3. Each spec.json is byte-identical to its copies under
#      Sources/QuotaGlanceCore/Resources/ProviderSpecs/<id>.json and
#      HarmonyOS/entry/src/main/resources/rawfile/providerspecs/<id>.json.
#   4. HarmonyOS ohosTest contract copies match Contracts/Providers
#      (same scope as scripts/sync-contracts-to-harmonyos.sh).
# Exits 1 on the first failing section after printing every error it found.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACTS_DIR="$REPO_ROOT/Contracts/Providers"
SWIFT_PROVIDER_FILE="$REPO_ROOT/Sources/QuotaGlanceCore/Domain/Provider.swift"
ARKTS_PROVIDER_FILE="$REPO_ROOT/HarmonyOS/entry/src/main/ets/providers/UsageProvider.ets"
CORE_SPEC_DIR="$REPO_ROOT/Sources/QuotaGlanceCore/Resources/ProviderSpecs"
HARMONYOS_SPEC_DIR="$REPO_ROOT/HarmonyOS/entry/src/main/resources/rawfile/providerspecs"
OHOSTEST_CONTRACTS_DIR="$REPO_ROOT/HarmonyOS/entry/src/ohosTest/resources/rawfile/contracts"

errors=0

fail() {
  echo "error: $*" >&2
  errors=$((errors + 1))
}

extract_spec_id() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$1"
}

# --- Check 1: Swift ProviderID.allCases == ArkTS ProviderID union -----------

check_provider_id_sets() {
  [[ -f "$SWIFT_PROVIDER_FILE" ]] || { fail "missing $SWIFT_PROVIDER_FILE"; return; }
  [[ -f "$ARKTS_PROVIDER_FILE" ]] || { fail "missing $ARKTS_PROVIDER_FILE"; return; }

  local swift_ids arkts_ids
  swift_ids="$(
    sed -n '/static let allCases/,/^    \]/p' "$SWIFT_PROVIDER_FILE" \
      | grep -oE '\.[A-Za-z][A-Za-z0-9]*' \
      | sed 's/^\.//' \
      | sort -u
  )"
  arkts_ids="$(
    grep -oE '^export type ProviderID[^;]*' "$ARKTS_PROVIDER_FILE" \
      | grep -oE "'[^']+'" \
      | tr -d "'" \
      | sort -u
  )"

  [[ -n "$swift_ids" ]] || { fail "could not extract ProviderID allCases from $SWIFT_PROVIDER_FILE"; return; }
  [[ -n "$arkts_ids" ]] || { fail "could not extract ProviderID union from $ARKTS_PROVIDER_FILE"; return; }

  local diff_output
  if ! diff_output="$(diff <(printf '%s\n' "$swift_ids") <(printf '%s\n' "$arkts_ids"))"; then
    fail "ProviderID sets differ (Swift allCases vs ArkTS ProviderID union):"$'\n'"$diff_output"
  fi
}

# --- Check 2: contract fixture triples are complete -------------------------

check_contract_fixtures() {
  [[ -d "$CONTRACTS_DIR" ]] || { fail "missing $CONTRACTS_DIR"; return; }

  local dir provider cases
  for dir in "$CONTRACTS_DIR"/*/; do
    provider="$(basename "$dir")"
    [[ -f "$dir/spec.json" ]] || fail "Contracts/Providers/$provider: missing spec.json"

    cases="$(
      ls "$dir" \
        | sed -nE 's/^(.+)-(response|requests|expected)[0-9]*\.json$/\1/p' \
        | sort -u
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

# --- Check 3: spec.json copies are byte-identical ----------------------------

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

# --- Check 4: ohosTest contract copies match Contracts/Providers ------------

check_ohostest_contracts() {
  [[ -d "$CONTRACTS_DIR" ]] || { fail "missing $CONTRACTS_DIR"; return; }
  if [[ ! -d "$OHOSTEST_CONTRACTS_DIR" ]]; then
    fail "missing $OHOSTEST_CONTRACTS_DIR (run scripts/sync-contracts-to-harmonyos.sh)"
    return
  fi

  local diff_output
  if ! diff_output="$(diff -r "$CONTRACTS_DIR" "$OHOSTEST_CONTRACTS_DIR" 2>&1)"; then
    fail "ohosTest contract copies are out of sync (run scripts/sync-contracts-to-harmonyos.sh):"$'\n'"$diff_output"
  fi
}

check_provider_id_sets
check_contract_fixtures
check_spec_copies
check_ohostest_contracts

if (( errors > 0 )); then
  echo "FAIL: provider parity check found $errors problem(s)" >&2
  exit 1
fi

echo "OK: ProviderID sets match (Swift <-> ArkTS)"
echo "OK: contract fixture triples complete under Contracts/Providers/"
echo "OK: spec.json copies byte-identical (Contracts <-> Swift core <-> HarmonyOS)"
echo "OK: ohosTest contract copies in sync with Contracts/Providers/"
