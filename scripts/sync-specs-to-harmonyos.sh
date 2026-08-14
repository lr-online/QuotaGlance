#!/usr/bin/env bash
# Sync shared provider specs into the HarmonyOS app rawfile directory.
# One-way: Contracts/Providers/<dir>/spec.json ->
# Platforms/HarmonyOS/entry/src/main/resources/rawfile/providerspecs/<id>.json where
# <id> is the camelCase spec "id" (apiInfo, deepSeek, ...). Swift reads the
# same specs via scripts/sync-specs-to-core.sh; ohosTest reads the copies
# under contracts/ synced by sync-contracts-to-harmonyos.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/Contracts/Providers"
DST="$REPO_ROOT/Platforms/HarmonyOS/entry/src/main/resources/rawfile/providerspecs"

if [[ ! -d "$SRC" ]]; then
  echo "error: $SRC not found" >&2
  exit 1
fi

rm -rf "$DST"
mkdir -p "$DST"

for dir in "$SRC"/*/; do
  spec="$dir/spec.json"
  if [[ ! -f "$spec" ]]; then
    continue
  fi
  id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$spec")"
  cp "$spec" "$DST/$id.json"
  echo "Synced $spec -> $DST/$id.json"
done
