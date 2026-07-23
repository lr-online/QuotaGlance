#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-Release}"
APP_NAME="QuotaGlance"
APP_BUNDLE_ID="com.liangrui.QuotaGlance"
WIDGET_NAME="QuotaGlanceWidget"
WIDGET_BUNDLE_ID="com.liangrui.QuotaGlance.Widget"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_PARENT="$ROOT_DIR/DerivedData/LocalBuild"
XCODEBUILD="/usr/bin/xcodebuild"
XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

case "$CONFIGURATION" in
  Debug)
    COMPILATION_CONDITIONS="DEBUG QUOTAGLANCE_CERTIFICATE_FREE_STORAGE"
    ;;
  Release)
    COMPILATION_CONDITIONS="QUOTAGLANCE_CERTIFICATE_FREE_STORAGE"
    ;;
  *)
    echo "usage: $0 [Debug|Release]" >&2
    exit 2
    ;;
esac

[[ -x "$XCODEBUILD" ]] || {
  echo "Xcode is required to generate configurable widget metadata." >&2
  exit 1
}
[[ -d "$XCODE_DEVELOPER_DIR" ]] || {
  echo "Xcode is missing at $XCODE_DEVELOPER_DIR" >&2
  exit 1
}

export DEVELOPER_DIR="$XCODE_DEVELOPER_DIR"
if ! "$XCODEBUILD" -checkFirstLaunchStatus >/dev/null 2>&1 \
  || ! "$XCODEBUILD" -license check >/dev/null 2>&1; then
  echo "Finish Xcode first-launch setup and accept its license before building." >&2
  exit 1
fi

/bin/mkdir -p "$BUILD_PARENT"
BUILD_DIR="$(mktemp -d "$BUILD_PARENT/$CONFIGURATION.XXXXXX")"
DERIVED_DATA="$BUILD_DIR/DerivedData"
BUILD_LOG="$BUILD_DIR/xcodebuild.log"
APP_BUNDLE="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
WIDGET_BUNDLE="$APP_BUNDLE/Contents/PlugIns/$WIDGET_NAME.appex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

if ! "$XCODEBUILD" \
  -project "$ROOT_DIR/QuotaGlance.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  REGISTER_WITH_LAUNCH_SERVICES=NO \
  "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$COMPILATION_CONDITIONS" \
  build \
  > "$BUILD_LOG" 2>&1; then
  /usr/bin/tail -n 200 "$BUILD_LOG" >&2
  exit 1
fi

if [[ ! -d "$APP_BUNDLE" || ! -d "$WIDGET_BUNDLE" ]]; then
  echo "Xcode build did not produce the expected app and widget bundles." >&2
  exit 1
fi

"$LSREGISTER" -u "$APP_BUNDLE" >/dev/null 2>&1 || true
/usr/bin/pluginkit -r "$WIDGET_BUNDLE" >/dev/null 2>&1 || true

/usr/bin/codesign \
  --force \
  --sign - \
  --timestamp=none \
  --generate-entitlement-der \
  --requirements "=designated => identifier \"$WIDGET_BUNDLE_ID\"" \
  --entitlements "$ROOT_DIR/Config/Local/QuotaGlanceWidget.entitlements" \
  "$WIDGET_BUNDLE"

/usr/bin/codesign \
  --force \
  --sign - \
  --timestamp=none \
  --generate-entitlement-der \
  --requirements "=designated => identifier \"$APP_BUNDLE_ID\"" \
  --entitlements "$ROOT_DIR/Config/Local/QuotaGlance.entitlements" \
  "$APP_BUNDLE"

/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
printf '%s\n' "$APP_BUNDLE"
