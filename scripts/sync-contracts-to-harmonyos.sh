#!/usr/bin/env bash
# Sync shared contract fixtures into the HarmonyOS ohosTest rawfile directory.
# One-way: Contracts/ -> HarmonyOS ohosTest resources. Swift reads Contracts/ directly.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACTS="$REPO_ROOT/Contracts"
DST="$REPO_ROOT/HarmonyOS/entry/src/ohosTest/resources/rawfile/contracts"

for dir in Providers Aggregation Alerts RefreshLifecycle ServiceStatus; do
  if [[ ! -d "$CONTRACTS/$dir" ]]; then
    echo "error: $CONTRACTS/$dir not found" >&2
    exit 1
  fi
done

rm -rf "$DST"
mkdir -p "$DST"
cp -R "$CONTRACTS/Providers/." "$DST/"
mkdir -p "$DST/aggregation" "$DST/alerts" "$DST/refreshlifecycle" "$DST/servicestatus"
cp -R "$CONTRACTS/Aggregation/." "$DST/aggregation/"
cp -R "$CONTRACTS/Alerts/." "$DST/alerts/"
cp -R "$CONTRACTS/RefreshLifecycle/." "$DST/refreshlifecycle/"
cp -R "$CONTRACTS/ServiceStatus/." "$DST/servicestatus/"
echo "Synced contracts -> $DST"
