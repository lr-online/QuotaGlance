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

require_exactly_one_layout() {
  local name="$1"
  local legacy_path="$2"
  local canonical_path="$3"
  local legacy_exists=0
  local canonical_exists=0

  [[ -d "$legacy_path" ]] && legacy_exists=1
  [[ -d "$canonical_path" ]] && canonical_exists=1

  case "$legacy_exists:$canonical_exists" in
    1:0 | 0:1) ;;
    0:0) fail "$name is missing from both ${legacy_path#"$REPO_ROOT"/} and ${canonical_path#"$REPO_ROOT"/}" ;;
    1:1) fail "$name exists at both legacy and canonical paths; migrate with git mv instead of duplicating it" ;;
  esac
}

check_macos_layout() {
  local legacy_paths=(App Widget NCWidget NCIntents Config Distribution)
  local legacy_count=0
  local path
  for path in "${legacy_paths[@]}"; do
    [[ -d "$REPO_ROOT/$path" ]] && ((legacy_count += 1))
  done

  local canonical_exists=0
  [[ -d "$REPO_ROOT/Platforms/macOS" ]] && canonical_exists=1
  case "$legacy_count:$canonical_exists" in
    6:0 | 0:1) ;;
    0:0) fail "macOS host is missing from both the legacy root layout and Platforms/macOS" ;;
    6:1) fail "macOS host exists at both legacy and canonical paths; migrate it as one unit" ;;
    *) fail "macOS legacy host is partial; App, Widget, NCWidget, NCIntents, Config, and Distribution move together" ;;
  esac

  if [[ "$legacy_count" -eq 6 ]]; then
    require_file "$REPO_ROOT/App/Info.plist"
    require_file "$REPO_ROOT/Widget/Info.plist"
    require_file "$REPO_ROOT/NCWidget/Info.plist"
    require_file "$REPO_ROOT/NCIntents/Info.plist"
  else
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
  fi
}

check_swift_core_layout() {
  local legacy_path="$REPO_ROOT/Sources/QuotaGlanceCore"
  local canonical_path="$REPO_ROOT/Shared/SwiftCore"
  require_exactly_one_layout "SwiftCore" "$legacy_path" "$canonical_path"

  if [[ -d "$legacy_path" ]]; then
    require_file "$REPO_ROOT/Package.swift"
    require_directory "$REPO_ROOT/Tests/QuotaGlanceCoreTests"
  else
    require_file "$canonical_path/Package.swift"
    require_directory "$canonical_path/Sources/QuotaGlanceCore"
    require_directory "$canonical_path/Tests/QuotaGlanceCoreTests"
    [[ ! -e "$REPO_ROOT/Tests/QuotaGlanceCoreTests" ]] \
      || fail "Tests/QuotaGlanceCoreTests must move with Shared/SwiftCore"
  fi
}

check_android_layout() {
  local legacy_path="$REPO_ROOT/Android"
  local canonical_path="$REPO_ROOT/Platforms/Android"
  require_exactly_one_layout "Android" "$legacy_path" "$canonical_path"
  local root="$legacy_path"
  [[ -d "$canonical_path" ]] && root="$canonical_path"
  require_file "$root/settings.gradle.kts"
  require_file "$root/app/build.gradle.kts"
}

check_harmonyos_layout() {
  local legacy_path="$REPO_ROOT/HarmonyOS"
  local canonical_path="$REPO_ROOT/Platforms/HarmonyOS"
  require_exactly_one_layout "HarmonyOS" "$legacy_path" "$canonical_path"
  local root="$legacy_path"
  [[ -d "$canonical_path" ]] && root="$canonical_path"
  require_file "$root/build-profile.template.json5"
  require_file "$root/hvigorfile.ts"
  require_file "$root/entry/hvigorfile.ts"
}

check_windows_layout() {
  local legacy_path="$REPO_ROOT/Windows"
  local canonical_path="$REPO_ROOT/Platforms/Windows"
  require_exactly_one_layout "Windows" "$legacy_path" "$canonical_path"
  local root="$legacy_path"
  [[ -d "$canonical_path" ]] && root="$canonical_path"
  require_file "$root/package.json"
  require_file "$root/Cargo.toml"
  require_file "$root/src-tauri/Cargo.toml"
  require_file "$root/src-tauri/tauri.conf.json"
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

check_legacy_script_alias() {
  local legacy_dir="$REPO_ROOT/script"
  [[ -d "$legacy_dir" ]] || return 0
  local entries=()
  local entry
  while IFS= read -r entry; do
    entries+=("${entry#"$legacy_dir"/}")
  done < <(find "$legacy_dir" -mindepth 1 -maxdepth 1 -print | sort)

  [[ "${#entries[@]}" -eq 1 && "${entries[0]}" == "build_and_run.sh" ]] \
    || fail "script/ is a temporary compatibility alias and may contain only build_and_run.sh"
  [[ -x "$legacy_dir/build_and_run.sh" ]] || fail "script/build_and_run.sh must remain executable while the compatibility alias exists"
  [[ -x "$REPO_ROOT/scripts/run-local.sh" ]] || fail "scripts/run-local.sh must provide the canonical local-run entrypoint"
  rg -Fq 'exec "$ROOT_DIR/scripts/run-local.sh" "$@"' "$legacy_dir/build_and_run.sh" \
    || fail "script/build_and_run.sh must be a pure exec adapter to scripts/run-local.sh"
}

check_migrated_path_consumers() {
  local module="$1"
  local legacy_path="$2"
  local canonical_path="$3"
  [[ -d "$canonical_path" ]] || return 0

  local search_roots=()
  local path
  for path in "$REPO_ROOT/scripts" "$REPO_ROOT/.github/workflows" "$REPO_ROOT/project.yml" "$REPO_ROOT/Package.swift"; do
    [[ -e "$path" ]] && search_roots+=("$path")
  done

  [[ "${#search_roots[@]}" -gt 0 ]] || return 0
  if rg -l -F "$legacy_path" "${search_roots[@]}" \
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
check_legacy_script_alias
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
