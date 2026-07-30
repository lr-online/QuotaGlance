#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-Release}"
EDITION="${2:-full}"
APP_NAME="QuotaGlance"
APP_BUNDLE_ID="com.liangrui.QuotaGlance"
WIDGET_NAME="QuotaGlanceWidget"
WIDGET_BUNDLE_ID="com.liangrui.QuotaGlance.Widget"
NC_WIDGET_NAME="QuotaGlanceNCWidget"
NC_WIDGET_BUNDLE_ID="com.liangrui.QuotaGlance.NCWidget"
NC_INTENTS_NAME="QuotaGlanceNCIntents"
NC_INTENTS_BUNDLE_ID="com.liangrui.QuotaGlance.NCIntents"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_PARENT="$ROOT_DIR/DerivedData/LocalBuild"
XCODEBUILD="/usr/bin/xcodebuild"
XCODE_DEVELOPER_DIR="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"
VERSION_BUILD_SETTING=()

if [[ -n "${QUOTAGLANCE_VERSION:-}" ]]; then
  APP_VERSION="${QUOTAGLANCE_VERSION#v}"
  [[ "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || {
    echo "Invalid QuotaGlance version: $QUOTAGLANCE_VERSION" >&2
    exit 2
  }
  VERSION_BUILD_SETTING=("MARKETING_VERSION=$APP_VERSION")
fi

case "$CONFIGURATION" in
  Debug)
    COMPILATION_CONDITIONS="DEBUG QUOTAGLANCE_CERTIFICATE_FREE_STORAGE"
    ;;
  Release)
    COMPILATION_CONDITIONS="QUOTAGLANCE_CERTIFICATE_FREE_STORAGE"
    ;;
  *)
    echo "usage: $0 [Debug|Release] [full|legacy]" >&2
    exit 2
    ;;
esac

case "$EDITION" in
  full)
    SCHEME="QuotaGlance"
    EXPECTS_WIDGET=true
    ;;
  legacy)
    SCHEME="QuotaGlanceLegacy"
    EXPECTS_WIDGET=false
    ;;
  *)
    echo "usage: $0 [Debug|Release] [full|legacy]" >&2
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
NC_WIDGET_BUNDLE="$APP_BUNDLE/Contents/PlugIns/$NC_WIDGET_NAME.appex"
NC_INTENTS_BUNDLE="$APP_BUNDLE/Contents/PlugIns/$NC_INTENTS_NAME.appex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

XCODEBUILD_ARGS=(
  -project "$ROOT_DIR/QuotaGlance.xcodeproj"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "platform=macOS,arch=arm64"
  -derivedDataPath "$DERIVED_DATA"
  ARCHS=arm64
  ONLY_ACTIVE_ARCH=YES
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  REGISTER_WITH_LAUNCH_SERVICES=NO
  "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$COMPILATION_CONDITIONS"
)
if [[ ${#VERSION_BUILD_SETTING[@]} -gt 0 ]]; then
  XCODEBUILD_ARGS+=("${VERSION_BUILD_SETTING[@]}")
fi
XCODEBUILD_ARGS+=(build)

if ! "$XCODEBUILD" "${XCODEBUILD_ARGS[@]}" > "$BUILD_LOG" 2>&1; then
  /usr/bin/tail -n 200 "$BUILD_LOG" >&2
  exit 1
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Xcode build did not produce the expected app bundle." >&2
  exit 1
fi
if [[ "$EXPECTS_WIDGET" == true && ! -d "$WIDGET_BUNDLE" ]]; then
  echo "Full build did not produce the expected Widget bundle." >&2
  exit 1
fi
if [[ "$EXPECTS_WIDGET" == false && -e "$WIDGET_BUNDLE" ]]; then
  echo "Legacy build unexpectedly contains a Widget bundle." >&2
  exit 1
fi
if [[ ! -d "$NC_WIDGET_BUNDLE" ]]; then
  echo "Build did not produce the expected NC Widget bundle." >&2
  exit 1
fi
if [[ ! -d "$NC_INTENTS_BUNDLE" ]]; then
  echo "Build did not produce the expected NC Intents bundle." >&2
  exit 1
fi

"$LSREGISTER" -u "$APP_BUNDLE" >/dev/null 2>&1 || true
/usr/bin/pluginkit -r "$NC_WIDGET_BUNDLE" >/dev/null 2>&1 || true
/usr/bin/pluginkit -r "$NC_INTENTS_BUNDLE" >/dev/null 2>&1 || true

/usr/bin/codesign \
  --force \
  --sign - \
  --timestamp=none \
  --generate-entitlement-der \
  --requirements "=designated => identifier \"$NC_WIDGET_BUNDLE_ID\"" \
  --entitlements "$ROOT_DIR/Config/Local/QuotaGlanceNCWidget.entitlements" \
  "$NC_WIDGET_BUNDLE"

/usr/bin/codesign \
  --force \
  --sign - \
  --timestamp=none \
  --generate-entitlement-der \
  --requirements "=designated => identifier \"$NC_INTENTS_BUNDLE_ID\"" \
  --entitlements "$ROOT_DIR/Config/Local/QuotaGlanceNCIntents.entitlements" \
  "$NC_INTENTS_BUNDLE"

if [[ "$EXPECTS_WIDGET" == true ]]; then
  /usr/bin/pluginkit -r "$WIDGET_BUNDLE" >/dev/null 2>&1 || true

  /usr/bin/codesign \
    --force \
    --sign - \
    --timestamp=none \
    --generate-entitlement-der \
    --requirements "=designated => identifier \"$WIDGET_BUNDLE_ID\"" \
    --entitlements "$ROOT_DIR/Config/Local/QuotaGlanceWidget.entitlements" \
    "$WIDGET_BUNDLE"
fi

/usr/bin/codesign \
  --force \
  --sign - \
  --timestamp=none \
  --generate-entitlement-der \
  --requirements "=designated => identifier \"$APP_BUNDLE_ID\"" \
  --entitlements "$ROOT_DIR/Config/Local/QuotaGlance.entitlements" \
  "$APP_BUNDLE"

/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
"$ROOT_DIR/scripts/verify-nc-extensions.sh" "$APP_BUNDLE"
printf '%s\n' "$APP_BUNDLE"
