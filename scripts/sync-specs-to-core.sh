#!/usr/bin/env bash
# Sync provider specs into the QuotaGlanceCore resource bundle.
# One-way: Contracts/Providers/<dir>/spec.json ->
# Shared/SwiftCore/Sources/QuotaGlanceCore/Resources/ProviderSpecs/<id>.json, where <id> is the
# camelCase provider id declared inside the spec (the spec stays the
# authoritative source). SwiftPM ships them via .process("Resources") and
# ProviderSpecLoader reads them through Bundle.module.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/Contracts/Providers"
DST="$REPO_ROOT/Shared/SwiftCore/Sources/QuotaGlanceCore/Resources/ProviderSpecs"

if [[ ! -d "$SRC" ]]; then
  echo "error: $SRC not found" >&2
  exit 1
fi

rm -rf "$DST"
mkdir -p "$DST"
for spec in "$SRC"/*/spec.json; do
  id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$spec")"
  cp "$spec" "$DST/$id.json"
done
echo "Synced provider specs -> $DST"
