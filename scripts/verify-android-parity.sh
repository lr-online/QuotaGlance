#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACTS_DIR="$REPO_ROOT/Contracts"
ANDROID_DIR="$REPO_ROOT/Android"
SPEC_TARGET="$ANDROID_DIR/app/src/main/assets/providerspecs"
FIXTURE_TARGET="$ANDROID_DIR/app/src/test/resources/contracts"
PROVIDER_SOURCE="$ANDROID_DIR/app/src/main/java/com/liangrui/quotaglance/core/ProviderId.kt"
SWIFT_PROVIDER_SOURCE="$REPO_ROOT/Sources/QuotaGlanceCore/Domain/Provider.swift"

errors=0

fail() {
  echo "error: $*" >&2
  errors=$((errors + 1))
}

[[ -f "$PROVIDER_SOURCE" ]] || fail "missing Kotlin ProviderId declaration"
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

for section in Providers Aggregation Alerts; do
  diff -qr "$CONTRACTS_DIR/$section" "$FIXTURE_TARGET/$section" >/dev/null \
    || fail "Android contract sync differs for $section"
done

if (( errors > 0 )); then
  exit 1
fi

echo "Android provider, contract, and fixture parity verified."
