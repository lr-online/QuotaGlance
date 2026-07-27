#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

build_setting() {
  local target="$1"
  local setting="$2"

  DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" /usr/bin/xcodebuild \
    -project "$ROOT_DIR/QuotaGlance.xcodeproj" \
    -target "$target" \
    -showBuildSettings 2>/dev/null \
    | /usr/bin/awk -v setting="$setting" \
      '$1 == setting && $2 == "=" { print $3; exit }'
}

rg -Fq '.macOS(.v12)' "$ROOT_DIR/Package.swift" \
  || fail "QuotaGlanceCore does not support macOS 12"
rg -q '^  QuotaGlanceLegacy:$' "$ROOT_DIR/project.yml" \
  || fail "legacy host target is missing"
rg -q 'QuotaGlanceLegacy' "$ROOT_DIR/scripts/build-local.sh" \
  || fail "local build script cannot select the legacy edition"
[[ -f "$ROOT_DIR/Tests/ScriptTests/AppIconTests.sh" ]] \
  || fail "app icon contract test is missing"
[[ -f "$ROOT_DIR/Tests/ScriptTests/GitHubActionsTests.sh" ]] \
  || fail "GitHub Actions contract test is missing"

SCHEMES="$(
  DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" /usr/bin/xcodebuild \
    -project "$ROOT_DIR/QuotaGlance.xcodeproj" \
    -list 2>/dev/null
)"
rg -q '^[[:space:]]+QuotaGlanceLegacy$' <<< "$SCHEMES" \
  || fail "legacy shared scheme is missing"

[[ "$(build_setting QuotaGlanceLegacy MACOSX_DEPLOYMENT_TARGET)" == "12.0" ]] \
  || fail "legacy host deployment target is not macOS 12"
[[ "$(build_setting QuotaGlance MACOSX_DEPLOYMENT_TARGET)" == "14.0" ]] \
  || fail "full host deployment target changed"
[[ "$(build_setting QuotaGlanceWidget MACOSX_DEPLOYMENT_TARGET)" == "14.0" ]] \
  || fail "Widget deployment target changed"

LEGACY_TARGET_BLOCK="$(/usr/bin/awk '
  /\/\* QuotaGlanceLegacy \*\/ = \{/ { capture = 1 }
  capture { print }
  capture && /productType =/ { exit }
' "$ROOT_DIR/QuotaGlance.xcodeproj/project.pbxproj")"
if rg -q 'QuotaGlanceWidget|PBXTargetDependency' <<< "$LEGACY_TARGET_BLOCK"; then
  fail "legacy host unexpectedly depends on the Widget"
fi

echo "Build edition contract tests passed"
