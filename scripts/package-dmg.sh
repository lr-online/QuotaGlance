#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ARGUMENT="${1:-$ROOT_DIR/dist}"
EDITION_SELECTION="${2:-all}"
GIT="/usr/bin/git"
WORK_DIR=""
SOURCE_DIR=""
VERSION=""
TEMP_DMGS=()
TEMP_CHECKSUMS=()
FINAL_DMGS=()
FINAL_CHECKSUMS=()
PUBLISHED_FINALS=()
PUBLISHED_SOURCES=()

same_file() {
  [[ "$(/usr/bin/stat -f '%d:%i' "$1" 2>/dev/null || true)" \
    == "$(/usr/bin/stat -f '%d:%i' "$2" 2>/dev/null || true)" ]]
}

cleanup() {
  local index

  for index in "${!PUBLISHED_FINALS[@]}"; do
    if [[ ! -L "${PUBLISHED_FINALS[$index]}" \
      && -e "${PUBLISHED_SOURCES[$index]}" ]] \
      && same_file \
        "${PUBLISHED_FINALS[$index]}" \
        "${PUBLISHED_SOURCES[$index]}"; then
      /bin/rm -f -- "${PUBLISHED_FINALS[$index]}"
    fi
  done
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    /bin/rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

case "$EDITION_SELECTION" in
  all|legacy|full)
    ;;
  *)
    echo "usage: $0 [OUTPUT_DIR] [all|legacy|full]" >&2
    exit 2
    ;;
esac

if [[ "$OUTPUT_ARGUMENT" == /* ]]; then
  OUTPUT_DIR="$OUTPUT_ARGUMENT"
else
  OUTPUT_DIR="$PWD/$OUTPUT_ARGUMENT"
fi
[[ ! -L "$OUTPUT_DIR" ]] || {
  echo "Refusing symlink output directory: $OUTPUT_ARGUMENT" >&2
  exit 1
}
/bin/mkdir -p "$OUTPUT_DIR"
[[ -d "$OUTPUT_DIR" && ! -L "$OUTPUT_DIR" ]] || {
  echo "Distribution output is not a directory: $OUTPUT_ARGUMENT" >&2
  exit 1
}
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"
WORK_DIR="$(mktemp -d "$OUTPUT_DIR/.QuotaGlance-package.XXXXXX")"
SOURCE_DIR="$WORK_DIR/source"
/bin/chmod 700 "$WORK_DIR"

cd "$ROOT_DIR"
[[ -z "$($GIT status --porcelain --untracked-files=all)" ]] || {
  echo "Refusing to package a dirty Git worktree" >&2
  exit 1
}
SOURCE_COMMIT="$($GIT rev-parse HEAD)"
[[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || {
  echo "Unable to resolve the source commit" >&2
  exit 1
}

"$GIT" clone --quiet --no-local --no-checkout "$ROOT_DIR" "$SOURCE_DIR"
"$GIT" -C "$SOURCE_DIR" checkout --quiet --detach "$SOURCE_COMMIT"
[[ "$($GIT -C "$SOURCE_DIR" rev-parse HEAD)" == "$SOURCE_COMMIT" \
  && -z "$($GIT -C "$SOURCE_DIR" status --porcelain --untracked-files=all)" ]] || {
  echo "Unable to create an immutable source checkout" >&2
  exit 1
}
package_edition() {
  local edition="$1"
  local os_tag
  local readme_source
  local volume_name
  local built_app
  local built_version
  local widget
  local dmg_name
  local checksum_name
  local final_dmg
  local final_checksum
  local temporary_dmg
  local temporary_checksum
  local staging_dir
  local executable
  local archs
  local -a executables

  case "$edition" in
    legacy)
      os_tag="macOS12"
      readme_source="$SOURCE_DIR/Distribution/README-macOS12.txt"
      volume_name="QuotaGlance macOS 12"
      ;;
    full)
      os_tag="macOS14"
      readme_source="$SOURCE_DIR/Distribution/README-macOS14.txt"
      volume_name="QuotaGlance macOS 14"
      ;;
  esac
  [[ -f "$readme_source" && ! -L "$readme_source" ]] || {
    echo "Distribution README is missing from source commit: $edition" >&2
    exit 1
  }

  built_app="$("$SOURCE_DIR/scripts/build-local.sh" Release "$edition")"
  built_version="$(/usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' \
    "$built_app/Contents/Info.plist")"
  [[ "$built_version" =~ ^[0-9A-Za-z][0-9A-Za-z.-]*$ ]] || {
    echo "Invalid app version for artifact name: $built_version" >&2
    exit 1
  }
  if [[ -z "$VERSION" ]]; then
    VERSION="$built_version"
  elif [[ "$VERSION" != "$built_version" ]]; then
    echo "Build editions have different app versions" >&2
    exit 1
  fi

  dmg_name="QuotaGlance-$VERSION-$os_tag-arm64.dmg"
  checksum_name="$dmg_name.sha256"
  final_dmg="$OUTPUT_DIR/$dmg_name"
  final_checksum="$OUTPUT_DIR/$checksum_name"
  temporary_dmg="$WORK_DIR/$dmg_name"
  temporary_checksum="$WORK_DIR/$checksum_name"
  staging_dir="$WORK_DIR/staging-$edition"

  if [[ -e "$final_dmg" || -L "$final_dmg" \
    || -e "$final_checksum" || -L "$final_checksum" ]]; then
    echo "Refusing to overwrite an existing distribution artifact" >&2
    exit 1
  fi

  /usr/bin/codesign --verify --deep --strict "$built_app"
  executables=("$built_app/Contents/MacOS/QuotaGlance")
  widget="$built_app/Contents/PlugIns/QuotaGlanceWidget.appex"
  if [[ "$edition" == full ]]; then
    "$SOURCE_DIR/scripts/verify-local-widget-bundle.sh" "$built_app"
    "$SOURCE_DIR/scripts/verify-widget-entrypoint.sh" "$widget"
    executables+=("$widget/Contents/MacOS/QuotaGlanceWidget")
  elif [[ -e "$widget" ]]; then
    echo "macOS 12 build unexpectedly contains the Widget" >&2
    exit 1
  fi
  for executable in "${executables[@]}"; do
    archs="$(/usr/bin/lipo -archs "$executable")"
    [[ "$archs" == "arm64" ]] || {
      echo "Release executable must contain only arm64, found: $archs" >&2
      exit 1
    }
  done

  if [[ -n "${LAOGE_KEY:-}" ]]; then
    "$SOURCE_DIR/scripts/verify-no-secret.sh" "$built_app"
  else
    echo "LAOGE_KEY is not set; skipping configured-key byte scan"
  fi

  /bin/mkdir -p "$staging_dir"
  /usr/bin/ditto "$built_app" "$staging_dir/QuotaGlance.app"
  /usr/bin/sed \
    -e "s/@VERSION@/$VERSION/g" \
    "$readme_source" > "$staging_dir/README.txt"
  /bin/ln -s /Applications "$staging_dir/Applications"

  /usr/bin/hdiutil create \
    -volname "$volume_name" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$temporary_dmg" >/dev/null
  (
    cd "$WORK_DIR"
    /usr/bin/shasum -a 256 "$dmg_name" > "$checksum_name"
  )

  "$SOURCE_DIR/scripts/verify-dmg.sh" \
    "$temporary_dmg" \
    "$temporary_checksum" \
    "$edition"

  TEMP_DMGS+=("$temporary_dmg")
  TEMP_CHECKSUMS+=("$temporary_checksum")
  FINAL_DMGS+=("$final_dmg")
  FINAL_CHECKSUMS+=("$final_checksum")
}

if [[ "$EDITION_SELECTION" == all || "$EDITION_SELECTION" == legacy ]]; then
  package_edition legacy
fi
if [[ "$EDITION_SELECTION" == all || "$EDITION_SELECTION" == full ]]; then
  package_edition full
fi

for index in "${!TEMP_DMGS[@]}"; do
  /bin/ln "${TEMP_DMGS[$index]}" "${FINAL_DMGS[$index]}"
  PUBLISHED_FINALS+=("${FINAL_DMGS[$index]}")
  PUBLISHED_SOURCES+=("${TEMP_DMGS[$index]}")
  /bin/ln "${TEMP_CHECKSUMS[$index]}" "${FINAL_CHECKSUMS[$index]}"
  PUBLISHED_FINALS+=("${FINAL_CHECKSUMS[$index]}")
  PUBLISHED_SOURCES+=("${TEMP_CHECKSUMS[$index]}")
done

for index in "${!FINAL_DMGS[@]}"; do
  printf '%s\n%s\n' "${FINAL_DMGS[$index]}" "${FINAL_CHECKSUMS[$index]}"
done
PUBLISHED_FINALS=()
PUBLISHED_SOURCES=()
