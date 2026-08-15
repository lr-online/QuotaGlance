#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_directory() {
  [[ -d "$1" ]] || fail "missing required directory: ${1#"$REPO_ROOT"/}"
}

require_file() {
  [[ -f "$1" ]] || fail "missing required file: ${1#"$REPO_ROOT"/}"
}

check_macos_layout() {
  require_directory "$REPO_ROOT/Platforms/macOS/App"
  require_directory "$REPO_ROOT/Platforms/macOS/Widget"
  require_directory "$REPO_ROOT/Platforms/macOS/NCWidget"
  require_directory "$REPO_ROOT/Platforms/macOS/NCIntents"
  require_directory "$REPO_ROOT/Platforms/macOS/Config"
  require_directory "$REPO_ROOT/Platforms/macOS/Distribution"
  require_file "$REPO_ROOT/Platforms/macOS/App/Info.plist"
  require_file "$REPO_ROOT/Platforms/macOS/Widget/Info.plist"
  require_file "$REPO_ROOT/Platforms/macOS/NCWidget/Info.plist"
  require_file "$REPO_ROOT/Platforms/macOS/NCIntents/Info.plist"
}

check_swift_core_layout() {
  require_file "$REPO_ROOT/Shared/SwiftCore/Package.swift"
  require_directory "$REPO_ROOT/Shared/SwiftCore/Sources/QuotaGlanceCore"
  require_directory "$REPO_ROOT/Shared/SwiftCore/Tests/QuotaGlanceCoreTests"
}

check_android_layout() {
  require_file "$REPO_ROOT/Platforms/Android/settings.gradle.kts"
  require_file "$REPO_ROOT/Platforms/Android/app/build.gradle.kts"
}

check_harmonyos_layout() {
  require_file "$REPO_ROOT/Platforms/HarmonyOS/build-profile.template.json5"
  require_file "$REPO_ROOT/Platforms/HarmonyOS/hvigorfile.ts"
  require_file "$REPO_ROOT/Platforms/HarmonyOS/entry/hvigorfile.ts"
}

check_windows_layout() {
  require_file "$REPO_ROOT/Platforms/Windows/package.json"
  require_file "$REPO_ROOT/Platforms/Windows/Cargo.toml"
  require_file "$REPO_ROOT/Platforms/Windows/src-tauri/Cargo.toml"
  require_file "$REPO_ROOT/Platforms/Windows/src-tauri/tauri.conf.json"
}

check_platforms_directory() {
  [[ -d "$REPO_ROOT/Platforms" ]] || return 0
  local platform
  for platform in "$REPO_ROOT/Platforms"/*; do
    [[ -e "$platform" ]] || continue
    [[ -d "$platform" ]] || fail "Platforms contains a non-directory entry: ${platform#"$REPO_ROOT"/}"
    case "$(basename "$platform")" in
      macOS|Android|HarmonyOS|Windows) ;;
      *) fail "Platforms contains an unrecognized platform: ${platform#"$REPO_ROOT"/}" ;;
    esac
    [[ ! -d "$platform/Contracts" ]] || fail "${platform#"$REPO_ROOT"/} must consume top-level Contracts authority"
  done
}

check_final_contraction() {
  local legacy_path
  for legacy_path in \
    Package.swift \
    Sources \
    Tests/QuotaGlanceCoreTests \
    App Widget NCWidget NCIntents Config Distribution \
    Android HarmonyOS Windows script; do
    [[ ! -e "$REPO_ROOT/$legacy_path" ]] \
      || fail "legacy topology residue must be removed: $legacy_path"
  done

  [[ -x "$REPO_ROOT/scripts/run-local.sh" ]] \
    || fail "scripts/run-local.sh must provide the canonical local-run entrypoint"
}

check_migrated_path_consumers() {
  local module="$1"
  local legacy_path="$2"
  local canonical_path="$3"
  [[ -d "$canonical_path" ]] || return 0

  local search_roots=()
  local path
  for path in "$REPO_ROOT/scripts" "$REPO_ROOT/.github/workflows" "$REPO_ROOT/project.yml" "$REPO_ROOT/QuotaGlance.xcodeproj/project.pbxproj" "$REPO_ROOT/Shared/SwiftCore/Package.swift"; do
    [[ -e "$path" ]] && search_roots+=("$path")
  done

  [[ "${#search_roots[@]}" -gt 0 ]] || return 0
  local legacy_root_reference="\$REPO_ROOT/$legacy_path"
  local standalone_legacy_pattern="(^|[[:space:]\"'])$legacy_path"
  if rg -l -F "$legacy_root_reference" "${search_roots[@]}" \
    --glob '!verify-repository-topology.sh' \
    --glob '!RepositoryTopologyTests.sh' >/dev/null \
    || rg -l -e "$standalone_legacy_pattern" "${search_roots[@]}" \
      --glob '!verify-repository-topology.sh' \
      --glob '!RepositoryTopologyTests.sh' >/dev/null; then
    fail "$module has moved, but an active build or workflow consumer still references $legacy_path"
  fi
}

require_directory "$REPO_ROOT"
require_directory "$REPO_ROOT/Contracts"
require_directory "$REPO_ROOT/scripts"

check_swift_core_layout
check_macos_layout
check_android_layout
check_harmonyos_layout
check_windows_layout
check_platforms_directory
check_final_contraction
check_migrated_path_consumers "SwiftCore" "Sources/QuotaGlanceCore" "$REPO_ROOT/Shared/SwiftCore"
check_migrated_path_consumers "macOS host" "App/" "$REPO_ROOT/Platforms/macOS"
check_migrated_path_consumers "macOS host" "Widget/" "$REPO_ROOT/Platforms/macOS"
check_migrated_path_consumers "macOS host" "NCWidget/" "$REPO_ROOT/Platforms/macOS"
check_migrated_path_consumers "macOS host" "NCIntents/" "$REPO_ROOT/Platforms/macOS"
check_migrated_path_consumers "macOS host" "Config/" "$REPO_ROOT/Platforms/macOS"
check_migrated_path_consumers "macOS host" "Distribution/" "$REPO_ROOT/Platforms/macOS"
check_migrated_path_consumers "Android" "Android/" "$REPO_ROOT/Platforms/Android"
check_migrated_path_consumers "HarmonyOS" "HarmonyOS/" "$REPO_ROOT/Platforms/HarmonyOS"
check_migrated_path_consumers "Windows" "Windows/" "$REPO_ROOT/Platforms/Windows"

echo "Repository topology is valid."
