#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY_SCRIPT="$ROOT_DIR/scripts/verify-repository-topology.sh"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quotaglance-topology.XXXXXX")"

cleanup() {
  rm -rf "$TEMP_ROOT"
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
  "$TEMP_ROOT/scripts" \
  "$TEMP_ROOT/Shared/SwiftCore/Sources/QuotaGlanceCore" \
  "$TEMP_ROOT/Shared/SwiftCore/Tests/QuotaGlanceCoreTests" \
  "$TEMP_ROOT/Platforms/macOS/App" \
  "$TEMP_ROOT/Platforms/macOS/Widget" \
  "$TEMP_ROOT/Platforms/macOS/NCWidget" \
  "$TEMP_ROOT/Platforms/macOS/NCIntents" \
  "$TEMP_ROOT/Platforms/macOS/Config" \
  "$TEMP_ROOT/Platforms/macOS/Distribution" \
  "$TEMP_ROOT/Platforms/Android/app" \
  "$TEMP_ROOT/Platforms/HarmonyOS/entry" \
  "$TEMP_ROOT/Platforms/Windows/src-tauri" \
  "$TEMP_ROOT/QuotaGlance.xcodeproj"
touch \
  "$TEMP_ROOT/Shared/SwiftCore/Package.swift" \
  "$TEMP_ROOT/Platforms/macOS/App/Info.plist" \
  "$TEMP_ROOT/Platforms/macOS/Widget/Info.plist" \
  "$TEMP_ROOT/Platforms/macOS/NCWidget/Info.plist" \
  "$TEMP_ROOT/Platforms/macOS/NCIntents/Info.plist" \
  "$TEMP_ROOT/Platforms/Android/settings.gradle.kts" \
  "$TEMP_ROOT/Platforms/Android/app/build.gradle.kts" \
  "$TEMP_ROOT/Platforms/HarmonyOS/build-profile.template.json5" \
  "$TEMP_ROOT/Platforms/HarmonyOS/hvigorfile.ts" \
  "$TEMP_ROOT/Platforms/HarmonyOS/entry/hvigorfile.ts" \
  "$TEMP_ROOT/Platforms/Windows/package.json" \
  "$TEMP_ROOT/Platforms/Windows/Cargo.toml" \
  "$TEMP_ROOT/Platforms/Windows/src-tauri/Cargo.toml" \
  "$TEMP_ROOT/Platforms/Windows/src-tauri/tauri.conf.json"
printf '%s\n' 'Platforms/macOS/App/Info.plist' > "$TEMP_ROOT/QuotaGlance.xcodeproj/project.pbxproj"
cp "$ROOT_DIR/scripts/run-local.sh" "$TEMP_ROOT/scripts/run-local.sh"
chmod +x "$TEMP_ROOT/scripts/run-local.sh"

"$VERIFY_SCRIPT" "$TEMP_ROOT"

cp "$ROOT_DIR/scripts/verify-repository-topology.sh" "$TEMP_ROOT/scripts/stale-path.sh"
expect_failure "$VERIFY_SCRIPT" "$TEMP_ROOT"
rm "$TEMP_ROOT/scripts/stale-path.sh"

printf '%s\n' 'App/Info.plist' >> "$TEMP_ROOT/QuotaGlance.xcodeproj/project.pbxproj"
expect_failure "$VERIFY_SCRIPT" "$TEMP_ROOT"
printf '%s\n' 'Platforms/macOS/App/Info.plist' > "$TEMP_ROOT/QuotaGlance.xcodeproj/project.pbxproj"

for legacy_path in \
  Package.swift Sources Tests/QuotaGlanceCoreTests \
  App Widget NCWidget NCIntents Config Distribution \
  Android HarmonyOS Windows script; do
  mkdir -p "$TEMP_ROOT/$legacy_path"
  expect_failure "$VERIFY_SCRIPT" "$TEMP_ROOT"
  rmdir "$TEMP_ROOT/$legacy_path"
done

mkdir "$TEMP_ROOT/Platforms/Windows/Contracts"
expect_failure "$VERIFY_SCRIPT" "$TEMP_ROOT"
rmdir "$TEMP_ROOT/Platforms/Windows/Contracts"

rm "$TEMP_ROOT/Platforms/Android/settings.gradle.kts"
expect_failure "$VERIFY_SCRIPT" "$TEMP_ROOT"

echo "Repository topology tests passed."
