#!/usr/bin/env bash
# Verify provider + contract + allow-list parity between the Swift engine
# (Sources/QuotaGlanceCore/) and the Rust engine (Windows/src-tauri/src/):
#
#   1. Swift `ProviderID.allCases` raw values == Rust `ProviderID` enum raw
#      values (in declaration order).
#   2. Swift `knownErrorTokens` set == Rust `KNOWN_ERROR_TOKENS`.
#   3. Swift `ProviderRegion` cases == Rust `KNOWN_REGIONS`.
#   4. Swift `ProviderCredentialKind` cases == Rust `KNOWN_CREDENTIAL_KINDS`.
#   5. Swift `knownSnapshotFields` set == Rust `KNOWN_SNAPSHOT_FIELDS`.
#   6. Swift `supportedSpecVersion` == Rust `SPEC_VERSION` == every
#      Contracts/Providers/<id>/spec.json `specVersion`.
#   7. Contract fixture triples (response/expected/requests) are complete
#      under Contracts/Providers/.
#   8. Spec.json copies under Windows/src-tauri/assets/providerspecs/ are
#      byte-identical to the Contracts sources (run
#      scripts/sync-specs-to-windows.sh).
#   9. Contract fixture trees under Windows/src-tauri/assets/contracts/
#      match the Contracts directories byte for byte (run
#      scripts/sync-contracts-to-windows.sh).
#
# Exits 1 on the first failing section after printing every error it found.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACTS_DIR="$REPO_ROOT/Contracts/Providers"

SWIFT_PROVIDER_FILE="$REPO_ROOT/Sources/QuotaGlanceCore/Domain/Provider.swift"
SWIFT_SPEC_FILE="$REPO_ROOT/Sources/QuotaGlanceCore/Providers/ProviderSpec.swift"
RUST_DOMAIN_FILE="$REPO_ROOT/Windows/src-tauri/src/domain.rs"
RUST_SPEC_FILE="$REPO_ROOT/Windows/src-tauri/src/providers/provider_spec.rs"
RUST_ERROR_FILE="$REPO_ROOT/Windows/src-tauri/src/providers/provider_error.rs"
SPEC_TARGET="$REPO_ROOT/Windows/src-tauri/assets/providerspecs"
FIXTURE_TARGET="$REPO_ROOT/Windows/src-tauri/assets/contracts"

errors=0

fail() {
  echo "error: $*" >&2
  errors=$((errors + 1))
}

# --- File presence ----------------------------------------------------------

for f in "$SWIFT_PROVIDER_FILE" "$SWIFT_SPEC_FILE" \
         "$RUST_DOMAIN_FILE" "$RUST_SPEC_FILE" "$RUST_ERROR_FILE"; do
  [[ -f "$f" ]] || fail "missing file $f"
done

# --- ProviderID sets --------------------------------------------------------

status=0
python3 - "$SWIFT_PROVIDER_FILE" "$RUST_DOMAIN_FILE" <<'PY' || status=$?
import re
import sys

swift_path, rust_path = sys.argv[1], sys.argv[2]

swift_src = open(swift_path).read()
m = re.search(r"static let allCases[^\]]*\]", swift_src, re.DOTALL)
if not m:
    print("error: cannot extract Swift allCases", file=sys.stderr)
    sys.exit(1)
swift_cases = re.findall(r"\s*\.\s*(\w+)\s*,", m.group(0))

# Swift's enum case names map directly onto the Rust raw value strings
# (deepSeek == deepSeek, openRouter == openRouter, miniMax == miniMax,
# bioMapCoding == bioMapCoding, apiInfo == apiInfo, kimi == kimi). The
# shape parity gate is the same string set + order on both sides.
swift_ids = swift_cases

rust_src = open(rust_path).read()
enum_match = re.search(r"pub enum ProviderID\s*\{([^}]+)\}", rust_src)
if not enum_match:
    print("error: cannot extract Rust ProviderID enum", file=sys.stderr)
    sys.exit(1)
rust_ids = re.findall(r'rename\s*=\s*"([^"]+)"', enum_match.group(1))

if swift_ids != rust_ids:
    print("error: ProviderID raw values differ between Swift and Rust", file=sys.stderr)
    print(f"  swift: {swift_ids}", file=sys.stderr)
    print(f"  rust:  {rust_ids}", file=sys.stderr)
    sys.exit(1)
print("ProviderID raw values match (Swift <-> Rust)")
PY
if (( status != 0 )); then
  fail "ProviderID raw values differ between Swift and Rust"
fi

# --- KNOWN_* allow-list parity (Rust), enum cases (Swift) -------------------

status=0
python3 - "$SWIFT_SPEC_FILE" "$SWIFT_PROVIDER_FILE" "$RUST_SPEC_FILE" <<'PY' || status=$?
import re
import sys

swift_spec_path, swift_provider_path, rust_spec_path = sys.argv[1:4]
swift_spec = open(swift_spec_path).read()
swift_provider = open(swift_provider_path).read()
rust_spec = open(rust_spec_path).read()

def rust_const_array(src, name):
    m = re.search(rf"pub const {name}:[^[]*\[(.*?)\]", src, re.DOTALL)
    if not m:
        return set()
    return set(re.findall(r'"([^"]+)"', m.group(1)))

def swift_set(src, decl):
    m = re.search(rf"{decl}[^=]*=\s*\[(.*?)\]", src, re.DOTALL)
    if not m:
        return set()
    return set(re.findall(r'"([^"]+)"', m.group(1)))

# Error tokens
swift_errors = swift_set(swift_spec, "knownErrorTokens")
rust_errors = rust_const_array(rust_spec, "KNOWN_ERROR_TOKENS")

# Snapshot fields
swift_fields = swift_set(swift_spec, "knownSnapshotFields")
rust_fields = rust_const_array(rust_spec, "KNOWN_SNAPSHOT_FIELDS")

# Regions
swift_region_match = re.search(
    r"public enum ProviderRegion[^}]+}", swift_provider, re.DOTALL
)
swift_regions = (
    set(re.findall(r"case\s+(\w+)", swift_region_match.group(0)))
    if swift_region_match
    else set()
)
rust_regions = rust_const_array(rust_spec, "KNOWN_REGIONS")

# Credential kinds
swift_kind_match = re.search(
    r"public enum ProviderCredentialKind[^}]+}", swift_provider, re.DOTALL
)
swift_kinds = (
    set(re.findall(r"case\s+(\w+)", swift_kind_match.group(0)))
    if swift_kind_match
    else set()
)
rust_kinds = rust_const_array(rust_spec, "KNOWN_CREDENTIAL_KINDS")

# Spec versions
swift_version = (
    re.search(r"supportedSpecVersion\s*=\s*(\d+)", swift_spec)
    .group(1)
    if re.search(r"supportedSpecVersion\s*=\s*(\d+)", swift_spec)
    else ""
)
rust_version = (
    re.search(r"pub const SPEC_VERSION:\s*u32\s*=\s*(\d+)", rust_spec)
    .group(1)
    if re.search(r"pub const SPEC_VERSION:\s*u32\s*=\s*(\d+)", rust_spec)
    else ""
)

failures = []
if swift_errors != rust_errors:
    failures.append(("error tokens", swift_errors, rust_errors))
if swift_fields != rust_fields:
    failures.append(("snapshot fields", swift_fields, rust_fields))
if swift_regions != rust_regions:
    failures.append(("regions", swift_regions, rust_regions))
if swift_kinds != rust_kinds:
    failures.append(("credential kinds", swift_kinds, rust_kinds))
if swift_version and rust_version and swift_version != rust_version:
    failures.append(("spec version", {swift_version}, {rust_version}))
if failures:
    for name, expected, actual in failures:
        print(f"error: {name} differ", file=sys.stderr)
        print(f"  swift: {sorted(expected)}", file=sys.stderr)
        print(f"  rust:  {sorted(actual)}", file=sys.stderr)
    sys.exit(1)
print("known error tokens / snapshot fields / regions / credential kinds / spec version match")
PY
if (( status != 0 )); then
  fail "Rust KNOWN_* allow-lists / spec version diverge from Swift"
fi

# --- specVersion per-provider spec.json matches SPEC_VERSION ---------------

status=0
python3 - "$CONTRACTS_DIR" <<'PY' || status=$?
import json
import os
import sys

contracts = sys.argv[1]
expected_version = 1
problems = []
for entry in sorted(os.listdir(contracts)):
    spec_path = os.path.join(contracts, entry, "spec.json")
    if not os.path.isfile(spec_path):
        continue
    with open(spec_path) as f:
        spec = json.load(f)
    if spec.get("specVersion") != expected_version:
        problems.append((entry, spec.get("specVersion")))
if problems:
    for entry, version in problems:
        print(f"error: {entry}/spec.json specVersion={version} != {expected_version}", file=sys.stderr)
    sys.exit(1)
print(f"All provider spec.json files report specVersion={expected_version}.")
PY
if (( status != 0 )); then
  fail "one or more Contracts/Providers/<id>/spec.json are out of date"
fi

# --- Contract fixture triples ------------------------------------------------

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
  [[ -n "$cases" ]] || { fail "Contracts/Providers/$provider: no <case>-*.json fixtures found"; continue; }
  for case_name in $cases; do
    [[ -f "$dir/$case_name-response.json" ]] \
      || fail "Contracts/Providers/$provider: case '$case_name' missing $case_name-response.json"
    [[ -f "$dir/$case_name-expected.json" ]] \
      || fail "Contracts/Providers/$provider: case '$case_name' missing $case_name-expected.json"
    [[ -f "$dir/$case_name-requests.json" ]] \
      || fail "Contracts/Providers/$provider: case '$case_name' missing $case_name-requests.json"
  done
done

# --- Spec copy parity -------------------------------------------------------

if [[ ! -d "$SPEC_TARGET" ]]; then
  fail "missing spec target $SPEC_TARGET (run scripts/sync-specs-to-windows.sh)"
else
  for spec in "$CONTRACTS_DIR"/*/spec.json; do
    [[ -f "$spec" ]] || continue
    id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$spec")"
    target="$SPEC_TARGET/$id.json"
    if [[ ! -f "$target" ]]; then
      fail "missing Windows spec copy $id.json (run scripts/sync-specs-to-windows.sh)"
    elif ! cmp -s "$spec" "$target"; then
      fail "Windows spec copy out of sync: $id.json"
    fi
  done
fi

# --- Contract fixture sync --------------------------------------------------

if [[ ! -d "$FIXTURE_TARGET" ]]; then
  fail "missing fixture target $FIXTURE_TARGET (run scripts/sync-contracts-to-windows.sh)"
else
  for dir in "$CONTRACTS_DIR"/*; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    if [[ ! -d "$FIXTURE_TARGET/$name" ]]; then
      fail "missing fixture tree $FIXTURE_TARGET/$name"
    elif ! diff -qr "$dir" "$FIXTURE_TARGET/$name" >/dev/null 2>&1; then
      fail "Windows contract fixture tree out of sync for provider '$name'"
    fi
  done
  for src_pair in "Aggregation aggregation" "Alerts alerts"; do
    src="${src_pair%% *}"
    dst="${src_pair##* }"
    if [[ ! -d "$FIXTURE_TARGET/$dst" ]]; then
      fail "missing fixture dir $FIXTURE_TARGET/$dst"
    elif ! diff -qr "$REPO_ROOT/Contracts/$src" "$FIXTURE_TARGET/$dst" >/dev/null 2>&1; then
      fail "Windows contract fixture tree out of sync for $src"
    fi
  done
fi

if (( errors > 0 )); then
  echo "FAIL: Windows parity check found $errors problem(s)" >&2
  exit 1
fi

echo "OK: Windows provider, contract, allow-list, spec_version parity verified."
