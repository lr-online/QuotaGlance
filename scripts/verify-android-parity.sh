#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACTS_DIR="$REPO_ROOT/Contracts"
ANDROID_DIR="$REPO_ROOT/Android"
SPEC_TARGET="$ANDROID_DIR/app/src/main/assets/providerspecs"
FIXTURE_TARGET="$ANDROID_DIR/app/src/test/resources/contracts"
PROVIDER_SOURCE="$ANDROID_DIR/app/src/main/java/com/liangrui/quotaglance/core/ProviderId.kt"
PROVIDER_TEST_SOURCE="$ANDROID_DIR/app/src/test/java/com/liangrui/quotaglance/core/ProviderContractTest.kt"
SWIFT_PROVIDER_SOURCE="$REPO_ROOT/Shared/SwiftCore/Sources/QuotaGlanceCore/Domain/Provider.swift"

errors=0

fail() {
  echo "error: $*" >&2
  errors=$((errors + 1))
}

[[ -f "$PROVIDER_SOURCE" ]] || fail "missing Kotlin ProviderId declaration"
[[ -f "$PROVIDER_TEST_SOURCE" ]] || fail "missing Kotlin provider contract test"
[[ -d "$SPEC_TARGET" ]] || fail "missing Android provider spec sync output"
[[ -d "$FIXTURE_TARGET" ]] || fail "missing Android contract fixture sync output"

expected_ids="$(sed -n '/static let allCases/,/^    ]/p' "$SWIFT_PROVIDER_SOURCE" \
  | grep -oE '\.[A-Za-z][A-Za-z0-9]*' | sed 's/^\.//')"
actual_ids="$(sed -n '/enum class ProviderId/,/^}/p' "$PROVIDER_SOURCE" 2>/dev/null \
  | grep -oE '"[A-Za-z][A-Za-z0-9]*"' | tr -d '"' || true)"

if [[ "$expected_ids" != "$actual_ids" ]]; then
  fail "ProviderID ordered values differ between Contracts and Kotlin declaration"
  diff -u <(printf '%s\n' "$expected_ids") <(printf '%s\n' "$actual_ids") || true
fi

for spec in "$CONTRACTS_DIR"/Providers/*/spec.json; do
  id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$spec")"
  target="$SPEC_TARGET/$id.json"
  [[ -f "$target" ]] || { fail "missing Android spec $id.json"; continue; }
  cmp -s "$spec" "$target" || fail "Android spec copy differs: $id.json"
done

for provider_dir in "$CONTRACTS_DIR"/Providers/*; do
  [[ -d "$provider_dir" ]] || continue
  provider="$(basename "$provider_dir")"
  for response in "$provider_dir"/*-response.json; do
    [[ -f "$response" ]] || continue
    case_name="$(basename "$response" -response.json)"
    [[ -f "$provider_dir/$case_name-expected.json" ]] || fail "missing expected fixture: $provider/$case_name"
    [[ -f "$provider_dir/$case_name-requests.json" ]] || fail "missing requests fixture: $provider/$case_name"
  done
done

if ! python3 - "$CONTRACTS_DIR/Providers" "$PROVIDER_SOURCE" "$PROVIDER_TEST_SOURCE" <<'PY'
import pathlib
import re
import sys

providers = pathlib.Path(sys.argv[1])
provider_source = pathlib.Path(sys.argv[2]).read_text()
test_source = pathlib.Path(sys.argv[3]).read_text()

enum_to_raw = dict(re.findall(r'^\s*([A-Z_]+)\("([A-Za-z][A-Za-z0-9]*)"\)', provider_source, re.M))
registered = {
    (enum_to_raw[enum].lower(), case)
    for enum, case in re.findall(r'ContractCase\(ProviderId\.([A-Z_]+),\s*"([^"]+)"', test_source)
    if enum in enum_to_raw
}
fixtures = {
    (directory.name, response.name.removesuffix('-response.json'))
    for directory in providers.iterdir() if directory.is_dir()
    for response in directory.glob('*-response.json')
}
missing = fixtures - registered
extra = registered - fixtures
if missing:
    print('missing Kotlin provider contract registrations:', ', '.join(f'{provider}/{case}' for provider, case in sorted(missing)), file=sys.stderr)
if extra:
    print('Kotlin provider contract registrations without fixtures:', ', '.join(f'{provider}/{case}' for provider, case in sorted(extra)), file=sys.stderr)
raise SystemExit(bool(missing or extra))
PY
then
  fail "Kotlin provider contract registrations differ from shared fixtures"
fi

for section in Providers Aggregation Alerts RefreshLifecycle; do
  diff -qr "$CONTRACTS_DIR/$section" "$FIXTURE_TARGET/$section" >/dev/null \
    || fail "Android contract sync differs for $section"
done

if (( errors > 0 )); then
  exit 1
fi

echo "Android provider, contract, and fixture parity verified."
