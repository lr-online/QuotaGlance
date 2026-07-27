#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ASSET_ROOT="$ROOT_DIR/App/Assets.xcassets"
APP_ICON_SET="$ASSET_ROOT/AppIcon.appiconset"
CONTENTS="$APP_ICON_SET/Contents.json"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -d "$ASSET_ROOT" ]] || fail "missing asset catalog"
[[ -d "$APP_ICON_SET" ]] || fail "missing AppIcon appiconset"
[[ -f "$CONTENTS" ]] || fail "missing AppIcon Contents.json"

for size in 16 32 64 128 256 512 1024; do
  [[ -f "$APP_ICON_SET/icon-${size}.png" ]] || fail "missing icon-${size}.png"
done

rg -q "ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon" "$ROOT_DIR/project.yml" \
  || fail "project.yml does not persist AppIcon name"
rg -q "path: App/Assets.xcassets" "$ROOT_DIR/project.yml" \
  || fail "project.yml does not include the asset catalog source path"

echo "App icon asset tests passed"
