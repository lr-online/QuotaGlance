#!/usr/bin/env bash
# Sync shared contract fixtures into the HarmonyOS ohosTest rawfile directory.
# One-way: Contracts/ -> HarmonyOS ohosTest resources. Swift reads Contracts/ directly.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/Contracts/Providers"
DST="$REPO_ROOT/HarmonyOS/entry/src/ohosTest/resources/rawfile/contracts"

if [[ ! -d "$SRC" ]]; then
  echo "error: $SRC not found" >&2
  exit 1
fi

rm -rf "$DST"
mkdir -p "$DST"
cp -R "$SRC/." "$DST/"
echo "Synced contracts -> $DST"
