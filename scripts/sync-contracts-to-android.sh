#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$REPO_ROOT/Contracts"
TARGET_DIR="$REPO_ROOT/Platforms/Android/app/src/test/resources/contracts"

mkdir -p "$TARGET_DIR"
find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +

for name in Providers Aggregation Alerts RefreshLifecycle; do
  cp -R "$SOURCE_DIR/$name" "$TARGET_DIR/$name"
done

echo "Synced provider, aggregation, alert, and refresh-lifecycle contracts to Android test resources."
