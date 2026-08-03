#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$REPO_ROOT/Contracts/Providers"
TARGET_DIR="$REPO_ROOT/Android/app/src/main/assets/providerspecs"

mkdir -p "$TARGET_DIR"
find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.json' -delete

for spec in "$SOURCE_DIR"/*/spec.json; do
  [[ -f "$spec" ]] || continue
  id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$spec")"
  cp "$spec" "$TARGET_DIR/$id.json"
done

echo "Synced provider specs to Android assets."
