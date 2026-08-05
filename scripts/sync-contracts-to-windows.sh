#!/usr/bin/env bash
# Sync the full contract tree (Providers + Aggregation + Alerts) into the
# Windows portable client's test resource tree
# (Windows/src-tauri/assets/contracts/). The Rust integration test harness
# replays the shared fixtures through the spec engine, snapshot aggregator,
# and alert evaluator at `cargo test` time; see
# Windows/src-tauri/tests/README.md for the planned suites.
#
# Mirror of scripts/sync-contracts-to-android.sh; identical scope on both
# platforms. Do not commit the synced output directly; the sync scripts
# reproduce it from Contracts/.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$REPO_ROOT/Contracts"
TARGET_DIR="$REPO_ROOT/Windows/src-tauri/assets/contracts"

mkdir -p "$TARGET_DIR"
find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +

for name in Providers Aggregation Alerts; do
  cp -R "$SOURCE_DIR/$name" "$TARGET_DIR/$name"
done

echo "Synced provider, aggregation, and alert contracts to Windows test resources."
