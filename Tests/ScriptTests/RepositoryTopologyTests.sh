#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY_SCRIPT="$ROOT_DIR/scripts/verify-repository-topology.sh"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quotaglance-topology.XXXXXX")"
CANONICAL_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quotaglance-topology.XXXXXX")"

cleanup() {
  rm -rf "$TEMP_ROOT"
  rm -rf "$CANONICAL_ROOT"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_failure() {
  if "$@" >/dev/null 2>&1; then
    fail "expected command to fail: $*"
  fi
}

[[ -x "$VERIFY_SCRIPT" ]] || fail "repository topology verifier is missing or not executable"

"$VERIFY_SCRIPT" "$ROOT_DIR"

mkdir -p \
  "$TEMP_ROOT/Contracts" \
  "$TEMP_ROOT/Sources/QuotaGlanceCore" \
  "$TEMP_ROOT/App" \
  "$TEMP_ROOT/Widget" \
  "$TEMP_ROOT/NCWidget" \
  "$TEMP_ROOT/NCIntents" \
  "$TEMP_ROOT/Config" \
  "$TEMP_ROOT/Distribution" \
  "$TEMP_ROOT/Android" \
  "$TEMP_ROOT/Android/app" \
  "$TEMP_ROOT/HarmonyOS" \
  "$TEMP_ROOT/HarmonyOS/entry" \
  "$TEMP_ROOT/Windows" \
  "$TEMP_ROOT/Windows/src-tauri" \
  "$TEMP_ROOT/script" \
  "$TEMP_ROOT/scripts"
cp "$ROOT_DIR/script/build_and_run.sh" "$TEMP_ROOT/script/build_and_run.sh"
cp "$ROOT_DIR/scripts/run-local.sh" "$TEMP_ROOT/scripts/run-local.sh"
chmod +x "$TEMP_ROOT/scripts/run-local.sh"
touch \
  "$TEMP_ROOT/Package.swift" \
  "$TEMP_ROOT/App/Info.plist" \
  "$TEMP_ROOT/Widget/Info.plist" \
  "$TEMP_ROOT/NCWidget/Info.plist" \
  "$TEMP_ROOT/NCIntents/Info.plist" \
  "$TEMP_ROOT/Android/settings.gradle.kts" \
  "$TEMP_ROOT/Android/app/build.gradle.kts" \
  "$TEMP_ROOT/HarmonyOS/build-profile.template.json5" \
  "$TEMP_ROOT/HarmonyOS/hvigorfile.ts" \
  "$TEMP_ROOT/HarmonyOS/entry/hvigorfile.ts" \
  "$TEMP_ROOT/Windows/package.json" \
  "$TEMP_ROOT/Windows/Cargo.toml" \
  "$TEMP_ROOT/Windows/src-tauri/Cargo.toml" \
  "$TEMP_ROOT/Windows/src-tauri/tauri.conf.json"

"$VERIFY_SCRIPT" "$TEMP_ROOT"

mkdir -p "$TEMP_ROOT/Platforms/Android"
expect_failure "$VERIFY_SCRIPT" "$TEMP_ROOT"
rmdir "$TEMP_ROOT/Platforms/Android"
rmdir "$TEMP_ROOT/Platforms"

touch "$TEMP_ROOT/script/unapproved.sh"
expect_failure "$VERIFY_SCRIPT" "$TEMP_ROOT"

mkdir -p \
  "$CANONICAL_ROOT/Contracts" \
  "$CANONICAL_ROOT/scripts" \
  "$CANONICAL_ROOT/Shared/SwiftCore/Sources/QuotaGlanceCore" \
  "$CANONICAL_ROOT/Shared/SwiftCore/Tests/QuotaGlanceCoreTests" \
  "$CANONICAL_ROOT/Platforms/macOS/App" \
  "$CANONICAL_ROOT/Platforms/macOS/Widget" \
  "$CANONICAL_ROOT/Platforms/macOS/NCWidget" \
  "$CANONICAL_ROOT/Platforms/macOS/NCIntents" \
  "$CANONICAL_ROOT/Platforms/macOS/Config" \
  "$CANONICAL_ROOT/Platforms/macOS/Distribution" \
  "$CANONICAL_ROOT/Platforms/Android/app" \
  "$CANONICAL_ROOT/Platforms/HarmonyOS/entry" \
  "$CANONICAL_ROOT/Platforms/Windows/src-tauri"
touch \
  "$CANONICAL_ROOT/Shared/SwiftCore/Package.swift" \
  "$CANONICAL_ROOT/Platforms/macOS/App/Info.plist" \
  "$CANONICAL_ROOT/Platforms/macOS/Widget/Info.plist" \
  "$CANONICAL_ROOT/Platforms/macOS/NCWidget/Info.plist" \
  "$CANONICAL_ROOT/Platforms/macOS/NCIntents/Info.plist" \
  "$CANONICAL_ROOT/Platforms/Android/settings.gradle.kts" \
  "$CANONICAL_ROOT/Platforms/Android/app/build.gradle.kts" \
  "$CANONICAL_ROOT/Platforms/HarmonyOS/build-profile.template.json5" \
  "$CANONICAL_ROOT/Platforms/HarmonyOS/hvigorfile.ts" \
  "$CANONICAL_ROOT/Platforms/HarmonyOS/entry/hvigorfile.ts" \
  "$CANONICAL_ROOT/Platforms/Windows/package.json" \
  "$CANONICAL_ROOT/Platforms/Windows/Cargo.toml" \
  "$CANONICAL_ROOT/Platforms/Windows/src-tauri/Cargo.toml" \
  "$CANONICAL_ROOT/Platforms/Windows/src-tauri/tauri.conf.json"

"$VERIFY_SCRIPT" "$CANONICAL_ROOT"

mkdir "$CANONICAL_ROOT/Platforms/Windows/Contracts"
expect_failure "$VERIFY_SCRIPT" "$CANONICAL_ROOT"
rmdir "$CANONICAL_ROOT/Platforms/Windows/Contracts"

rm "$CANONICAL_ROOT/Platforms/Android/settings.gradle.kts"
expect_failure "$VERIFY_SCRIPT" "$CANONICAL_ROOT"

echo "Repository topology tests passed."
