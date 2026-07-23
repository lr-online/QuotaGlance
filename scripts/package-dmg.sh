#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT_DIR/dist}"
README_SOURCE="$ROOT_DIR/Distribution/README.txt"
GIT="/usr/bin/git"
WORK_DIR="$(mktemp -d /tmp/QuotaGlance-dmg-package.XXXXXX)"
STAGING_DIR="$WORK_DIR/staging"
PUBLISHED_DMG=""
PUBLISHED_CHECKSUM=""

cleanup() {
  if [[ -n "$PUBLISHED_DMG" ]]; then
    /bin/rm -f -- "$PUBLISHED_DMG"
  fi
  if [[ -n "$PUBLISHED_CHECKSUM" ]]; then
    /bin/rm -f -- "$PUBLISHED_CHECKSUM"
  fi
  /bin/rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT

[[ -f "$README_SOURCE" && ! -L "$README_SOURCE" ]] || {
  echo "Distribution README is missing: $README_SOURCE" >&2
  exit 1
}
[[ ! -L "$OUTPUT_DIR" ]] || {
  echo "Refusing symlink output directory: $OUTPUT_DIR" >&2
  exit 1
}

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

BUILT_APP="$("$ROOT_DIR/scripts/build-local.sh" Release)"
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
"$ROOT_DIR/scripts/verify-local-widget-bundle.sh" "$BUILT_APP"
"$ROOT_DIR/scripts/verify-widget-entrypoint.sh" \
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
  "$ROOT_DIR/scripts/verify-no-secret.sh" "$BUILT_APP"
else
  echo "LAOGE_KEY is not set; skipping configured-key byte scan"
fi

/bin/mkdir -p "$STAGING_DIR"
/usr/bin/ditto "$BUILT_APP" "$STAGING_DIR/QuotaGlance.app"
/bin/cp "$README_SOURCE" "$STAGING_DIR/README.txt"
/bin/ln -s /Applications "$STAGING_DIR/Applications"
"$GIT" archive \
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

"$ROOT_DIR/scripts/verify-dmg.sh" "$TEMP_DMG" "$TEMP_CHECKSUM"

/bin/mkdir -p "$OUTPUT_DIR"
/bin/mv "$TEMP_CHECKSUM" "$FINAL_CHECKSUM"
PUBLISHED_CHECKSUM="$FINAL_CHECKSUM"
/bin/mv "$TEMP_DMG" "$FINAL_DMG"
PUBLISHED_DMG="$FINAL_DMG"

printf '%s\n%s\n' "$FINAL_DMG" "$FINAL_CHECKSUM"
PUBLISHED_DMG=""
PUBLISHED_CHECKSUM=""
