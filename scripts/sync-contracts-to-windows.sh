#!/usr/bin/env bash
# Sync the full contract tree (Providers + Aggregation + Alerts + RefreshLifecycle) into the
# Windows portable client's test resource tree
# (Platforms/Windows/src-tauri/assets/contracts/). The Rust integration test harness
# replays the shared fixtures through the spec engine, snapshot aggregator,
# and alert evaluator at `cargo test` time; see
# Platforms/Windows/src-tauri/tests/README.md for the planned suites.
#
# Mirror of scripts/sync-contracts-to-android.sh; identical scope on both
# platforms. Do not commit the synced output directly; the sync scripts
# reproduce it from Contracts/.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$REPO_ROOT/Contracts"
TARGET_DIR="$REPO_ROOT/Platforms/Windows/src-tauri/assets/contracts"

mkdir -p "$TARGET_DIR"
find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +

cp -R "$SOURCE_DIR/Providers" "$TARGET_DIR/Providers"
mkdir -p "$TARGET_DIR/aggregation" "$TARGET_DIR/alerts" "$TARGET_DIR/refreshlifecycle"
cp -R "$SOURCE_DIR/Aggregation/." "$TARGET_DIR/aggregation/"
cp -R "$SOURCE_DIR/Alerts/." "$TARGET_DIR/alerts/"
cp -R "$SOURCE_DIR/RefreshLifecycle/." "$TARGET_DIR/refreshlifecycle/"

echo "Synced provider, aggregation, alert, and refresh-lifecycle contracts to Windows test resources."
