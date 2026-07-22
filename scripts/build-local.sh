#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-Release}"
APP_NAME="QuotaGlance"
APP_BUNDLE_ID="com.liangrui.QuotaGlance"
WIDGET_NAME="QuotaGlanceWidget"
WIDGET_BUNDLE_ID="com.liangrui.QuotaGlance.Widget"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_PARENT="$ROOT_DIR/DerivedData/ManualBuild"
SWIFTC="/Library/Developer/CommandLineTools/usr/bin/swiftc"
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
TOOLCHAIN_FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

case "$CONFIGURATION" in
  Debug)
    OPTIMIZATION_FLAGS=(-Onone -g)
    ;;
  Release)
    OPTIMIZATION_FLAGS=(-O)
    ;;
  *)
    echo "usage: $0 [Debug|Release]" >&2
    exit 2
    ;;
esac

[[ -x "$SWIFTC" ]] || {
  echo "Swift Command Line Tools are required at $SWIFTC" >&2
  exit 1
}
[[ -d "$SDK_PATH" ]] || {
  echo "The macOS Command Line Tools SDK is missing: $SDK_PATH" >&2
  exit 1
}
command -v rg >/dev/null 2>&1 || {
  echo "ripgrep is required to collect Swift sources." >&2
  exit 1
}

mkdir -p "$BUILD_PARENT"
BUILD_DIR="$(mktemp -d "$BUILD_PARENT/$CONFIGURATION.XXXXXX")"
MODULE_CACHE="$BUILD_DIR/ModuleCache"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_BINARY="$APP_CONTENTS/MacOS/$APP_NAME"
WIDGET_BUNDLE="$APP_CONTENTS/PlugIns/$WIDGET_NAME.appex"
WIDGET_CONTENTS="$WIDGET_BUNDLE/Contents"
WIDGET_BINARY="$WIDGET_CONTENTS/MacOS/$WIDGET_NAME"

mkdir -p \
  "$MODULE_CACHE" \
  "$APP_CONTENTS/MacOS" \
  "$WIDGET_CONTENTS/MacOS"

CORE_SOURCES=()
while IFS= read -r source; do
  CORE_SOURCES+=("$ROOT_DIR/$source")
done < <(cd "$ROOT_DIR" && rg --files Sources/QuotaGlanceCore -g '*.swift' | sort)

APP_SOURCES=()
while IFS= read -r source; do
  APP_SOURCES+=("$ROOT_DIR/$source")
done < <(cd "$ROOT_DIR" && rg --files App -g '*.swift' | sort)

WIDGET_SOURCES=()
while IFS= read -r source; do
  WIDGET_SOURCES+=("$ROOT_DIR/$source")
done < <(cd "$ROOT_DIR" && rg --files Widget -g '*.swift' | sort)

export DEVELOPER_DIR="/Library/Developer/CommandLineTools"
export DYLD_LIBRARY_PATH="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

COMMON_SWIFT_FLAGS=(
  -swift-version 6
  -target arm64-apple-macosx14.0
  -sdk "$SDK_PATH"
  -F "$TOOLCHAIN_FRAMEWORKS"
  -module-cache-path "$MODULE_CACHE"
  "${OPTIMIZATION_FLAGS[@]}"
)

"$SWIFTC" \
  -emit-library \
  -static \
  -emit-module \
  -parse-as-library \
  -module-name QuotaGlanceCore \
  "${COMMON_SWIFT_FLAGS[@]}" \
  -emit-module-path "$BUILD_DIR/QuotaGlanceCore.swiftmodule" \
  "${CORE_SOURCES[@]}" \
  -o "$BUILD_DIR/libQuotaGlanceCore.a"

"$SWIFTC" \
  -emit-executable \
  -parse-as-library \
  -module-name "$APP_NAME" \
  "${COMMON_SWIFT_FLAGS[@]}" \
  -I "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -lQuotaGlanceCore \
  "${APP_SOURCES[@]}" \
  -o "$APP_BINARY"

"$SWIFTC" \
  -emit-executable \
  -parse-as-library \
  -module-name "$WIDGET_NAME" \
  "${COMMON_SWIFT_FLAGS[@]}" \
  -I "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -lQuotaGlanceCore \
  "${WIDGET_SOURCES[@]}" \
  -o "$WIDGET_BINARY"

cp "$ROOT_DIR/App/Info.plist" "$APP_CONTENTS/Info.plist"
cp "$ROOT_DIR/Widget/Info.plist" "$WIDGET_CONTENTS/Info.plist"

/usr/bin/plutil -replace CFBundleExecutable -string "$APP_NAME" "$APP_CONTENTS/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string "$APP_BUNDLE_ID" "$APP_CONTENTS/Info.plist"
/usr/bin/plutil -replace CFBundleName -string "$APP_NAME" "$APP_CONTENTS/Info.plist"
/usr/bin/plutil -replace CFBundleShortVersionString -string 0.1.0 "$APP_CONTENTS/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string 1 "$APP_CONTENTS/Info.plist"
/usr/bin/plutil -replace LSMinimumSystemVersion -string "$MIN_SYSTEM_VERSION" "$APP_CONTENTS/Info.plist"
/usr/bin/plutil -insert CFBundleSupportedPlatforms -json '["MacOSX"]' "$APP_CONTENTS/Info.plist"

/usr/bin/plutil -replace CFBundleExecutable -string "$WIDGET_NAME" "$WIDGET_CONTENTS/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string "$WIDGET_BUNDLE_ID" "$WIDGET_CONTENTS/Info.plist"
/usr/bin/plutil -replace CFBundleName -string "$WIDGET_NAME" "$WIDGET_CONTENTS/Info.plist"
/usr/bin/plutil -replace CFBundleShortVersionString -string 0.1.0 "$WIDGET_CONTENTS/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string 1 "$WIDGET_CONTENTS/Info.plist"
/usr/bin/plutil -insert LSMinimumSystemVersion -string "$MIN_SYSTEM_VERSION" "$WIDGET_CONTENTS/Info.plist"
/usr/bin/plutil -insert CFBundleSupportedPlatforms -json '["MacOSX"]' "$WIDGET_CONTENTS/Info.plist"

/usr/bin/codesign \
  --force \
  --sign - \
  --timestamp=none \
  --generate-entitlement-der \
  --requirements "=designated => identifier \"$WIDGET_BUNDLE_ID\"" \
  --entitlements "$ROOT_DIR/Widget/QuotaGlanceWidget.entitlements" \
  "$WIDGET_BUNDLE"

/usr/bin/codesign \
  --force \
  --sign - \
  --timestamp=none \
  --generate-entitlement-der \
  --requirements "=designated => identifier \"$APP_BUNDLE_ID\"" \
  --entitlements "$ROOT_DIR/App/QuotaGlance.entitlements" \
  "$APP_BUNDLE"

/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
printf '%s\n' "$APP_BUNDLE"
