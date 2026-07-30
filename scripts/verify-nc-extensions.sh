#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="${1:?usage: verify-nc-extensions.sh APP_BUNDLE}"
NC_WIDGET_BUNDLE_ID="com.liangrui.QuotaGlance.NCWidget"
NC_INTENTS_BUNDLE_ID="com.liangrui.QuotaGlance.NCIntents"
NC_WIDGET="$APP_BUNDLE/Contents/PlugIns/QuotaGlanceNCWidget.appex"
NC_INTENTS="$APP_BUNDLE/Contents/PlugIns/QuotaGlanceNCIntents.appex"

fail() {
  echo "$*" >&2
  exit 1
}

bundle_id() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$1/Contents/Info.plist" 2>/dev/null
}

min_version() {
  /usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' \
    "$1/Contents/Info.plist" 2>/dev/null
}

extension_point() {
  /usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' \
    "$1/Contents/Info.plist" 2>/dev/null
}

[[ -d "$APP_BUNDLE" ]] || fail "App bundle missing: $APP_BUNDLE"
[[ -d "$NC_WIDGET" ]] || fail "NC widget missing: $NC_WIDGET"
[[ -d "$NC_INTENTS" ]] || fail "NC intents missing: $NC_INTENTS"

[[ "$(bundle_id "$NC_WIDGET")" == "$NC_WIDGET_BUNDLE_ID" ]] \
  || fail "Unexpected NC widget bundle id"
[[ "$(bundle_id "$NC_INTENTS")" == "$NC_INTENTS_BUNDLE_ID" ]] \
  || fail "Unexpected NC intents bundle id"

[[ "$(min_version "$NC_WIDGET")" == "12.0" ]] \
  || fail "NC widget minimum system version is not macOS 12"
[[ "$(min_version "$NC_INTENTS")" == "12.0" ]] \
  || fail "NC intents minimum system version is not macOS 12"

[[ "$(extension_point "$NC_WIDGET")" == "com.apple.widgetkit-extension" ]] \
  || fail "NC widget extension point is wrong"
[[ "$(extension_point "$NC_INTENTS")" == "com.apple.intents-service" ]] \
  || fail "NC intents extension point is wrong"

WIDGET_BINARY="$NC_WIDGET/Contents/MacOS/QuotaGlanceNCWidget"
INTENTS_BINARY="$NC_INTENTS/Contents/MacOS/QuotaGlanceNCIntents"
[[ -x "$WIDGET_BINARY" ]] || fail "NC widget executable missing"
[[ -x "$INTENTS_BINARY" ]] || fail "NC intents executable missing"

for executable in "$WIDGET_BINARY" "$INTENTS_BINARY"; do
  archs="$(/usr/bin/lipo -archs "$executable")"
  [[ "$archs" == "arm64" ]] || fail "NC extension must be arm64-only: $executable ($archs)"
done

/usr/bin/strings "$WIDGET_BINARY" | rg -q 'QuotaGlanceNCWidget' \
  || fail "NC widget binary missing kind string"
/usr/bin/strings "$WIDGET_BINARY" | rg -q 'NCWidgetAccountIntent' \
  || fail "NC widget binary missing NCWidgetAccountIntent"

echo "NC extensions verified in $APP_BUNDLE"
