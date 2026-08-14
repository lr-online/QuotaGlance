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
  rg -Fq 'scripts/build-local.sh' "$legacy_dir/build_and_run.sh" \
    || fail "script/build_and_run.sh must delegate to scripts/build-local.sh"
}

require_directory "$REPO_ROOT"
require_directory "$REPO_ROOT/Contracts"
require_directory "$REPO_ROOT/scripts"

require_exactly_one_layout "SwiftCore" "$REPO_ROOT/Sources/QuotaGlanceCore" "$REPO_ROOT/Shared/SwiftCore"
check_macos_layout
require_exactly_one_layout "Android" "$REPO_ROOT/Android" "$REPO_ROOT/Platforms/Android"
require_exactly_one_layout "HarmonyOS" "$REPO_ROOT/HarmonyOS" "$REPO_ROOT/Platforms/HarmonyOS"
require_exactly_one_layout "Windows" "$REPO_ROOT/Windows" "$REPO_ROOT/Platforms/Windows"
check_platforms_directory
check_legacy_script_alias

echo "Repository topology is valid."
