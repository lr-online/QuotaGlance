#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ARGUMENT="${1:-$ROOT_DIR/dist}"
GIT="/usr/bin/git"
WORK_DIR=""
STAGING_DIR=""
SOURCE_DIR=""
PUBLISHED_DMG=""
PUBLISHED_CHECKSUM=""
PUBLISHED_DMG_SOURCE=""
PUBLISHED_CHECKSUM_SOURCE=""

same_file() {
  [[ "$(/usr/bin/stat -f '%d:%i' "$1" 2>/dev/null || true)" \
    == "$(/usr/bin/stat -f '%d:%i' "$2" 2>/dev/null || true)" ]]
}

cleanup() {
  if [[ -n "$PUBLISHED_DMG" \
    && ! -L "$PUBLISHED_DMG" \
    && -e "$PUBLISHED_DMG_SOURCE" ]] \
    && same_file "$PUBLISHED_DMG" "$PUBLISHED_DMG_SOURCE"; then
    /bin/rm -f -- "$PUBLISHED_DMG"
  fi
  if [[ -n "$PUBLISHED_CHECKSUM" \
    && ! -L "$PUBLISHED_CHECKSUM" \
    && -e "$PUBLISHED_CHECKSUM_SOURCE" ]] \
    && same_file "$PUBLISHED_CHECKSUM" "$PUBLISHED_CHECKSUM_SOURCE"; then
    /bin/rm -f -- "$PUBLISHED_CHECKSUM"
  fi
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    /bin/rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

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
STAGING_DIR="$WORK_DIR/staging"
SOURCE_DIR="$WORK_DIR/source"
/bin/chmod 700 "$WORK_DIR"

cd "$ROOT_DIR"
[[ -z "$("$GIT" status --porcelain --untracked-files=all)" ]] || {
  echo "Refusing to package a dirty Git worktree" >&2
  exit 1
}
SOURCE_COMMIT="$("$GIT" rev-parse HEAD)"
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

README_SOURCE="$SOURCE_DIR/Distribution/README.txt"
[[ -f "$README_SOURCE" && ! -L "$README_SOURCE" ]] || {
  echo "Distribution README is missing from source commit" >&2
  exit 1
}

BUILT_APP="$("$SOURCE_DIR/scripts/build-local.sh" Release)"
VERSION="$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' \
  "$BUILT_APP/Contents/Info.plist")"
[[ "$VERSION" =~ ^[0-9A-Za-z][0-9A-Za-z.-]*$ ]] || {
  echo "Invalid app version for artifact name: $VERSION" >&2
  exit 1
}

DMG_NAME="QuotaGlance-$VERSION-arm64.dmg"
CHECKSUM_NAME="$DMG_NAME.sha256"
SOURCE_NAME="QuotaGlance-$VERSION-source.zip"
FINAL_DMG="$OUTPUT_DIR/$DMG_NAME"
FINAL_CHECKSUM="$OUTPUT_DIR/$CHECKSUM_NAME"
TEMP_DMG="$WORK_DIR/$DMG_NAME"
TEMP_CHECKSUM="$WORK_DIR/$CHECKSUM_NAME"

if [[ -e "$FINAL_DMG" || -L "$FINAL_DMG" \
  || -e "$FINAL_CHECKSUM" || -L "$FINAL_CHECKSUM" ]]; then
  echo "Refusing to overwrite an existing distribution artifact" >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict "$BUILT_APP"
"$SOURCE_DIR/scripts/verify-local-widget-bundle.sh" "$BUILT_APP"
"$SOURCE_DIR/scripts/verify-widget-entrypoint.sh" \
  "$BUILT_APP/Contents/PlugIns/QuotaGlanceWidget.appex"

for executable in \
  "$BUILT_APP/Contents/MacOS/QuotaGlance" \
  "$BUILT_APP/Contents/PlugIns/QuotaGlanceWidget.appex/Contents/MacOS/QuotaGlanceWidget"; do
  ARCHS="$(/usr/bin/lipo -archs "$executable")"
  [[ "$ARCHS" == "arm64" ]] || {
    echo "Release executable must contain only arm64, found: $ARCHS" >&2
    exit 1
  }
done

if [[ -n "${LAOGE_KEY:-}" ]]; then
  "$SOURCE_DIR/scripts/verify-no-secret.sh" "$BUILT_APP"
else
  echo "LAOGE_KEY is not set; skipping configured-key byte scan"
fi

/bin/mkdir -p "$STAGING_DIR"
/usr/bin/ditto "$BUILT_APP" "$STAGING_DIR/QuotaGlance.app"
/bin/cp "$README_SOURCE" "$STAGING_DIR/README.txt"
/bin/ln -s /Applications "$STAGING_DIR/Applications"
"$GIT" -C "$SOURCE_DIR" archive \
  --format=zip \
  --prefix="QuotaGlance-$VERSION-source/" \
  --output="$STAGING_DIR/$SOURCE_NAME" \
  "$SOURCE_COMMIT"
printf 'Git commit: %s\n' "$SOURCE_COMMIT" \
  > "$STAGING_DIR/SOURCE-COMMIT.txt"

/usr/bin/hdiutil create \
  -volname QuotaGlance \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$TEMP_DMG" >/dev/null

(
  cd "$WORK_DIR"
  /usr/bin/shasum -a 256 "$DMG_NAME" > "$CHECKSUM_NAME"
)

"$SOURCE_DIR/scripts/verify-dmg.sh" "$TEMP_DMG" "$TEMP_CHECKSUM"

/bin/ln "$TEMP_DMG" "$FINAL_DMG"
PUBLISHED_DMG="$FINAL_DMG"
PUBLISHED_DMG_SOURCE="$TEMP_DMG"
/bin/ln "$TEMP_CHECKSUM" "$FINAL_CHECKSUM"
PUBLISHED_CHECKSUM="$FINAL_CHECKSUM"
PUBLISHED_CHECKSUM_SOURCE="$TEMP_CHECKSUM"

printf '%s\n%s\n' "$FINAL_DMG" "$FINAL_CHECKSUM"
PUBLISHED_DMG=""
PUBLISHED_CHECKSUM=""
PUBLISHED_DMG_SOURCE=""
PUBLISHED_CHECKSUM_SOURCE=""
