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

read_entitlements() {
  local bundle="$1"
  local destination="$2"
  /usr/bin/codesign -d --entitlements :- "$bundle" 2>&1 \
    | /usr/bin/sed -n '/^<?xml/,$p' > "$destination"
  /usr/bin/plutil -lint "$destination" >/dev/null
}

require_true_entitlement() {
  local plist="$1"
  local key="$2"
  [[ "$(/usr/bin/plutil -extract "$key" raw -expect bool -o - "$plist" 2>/dev/null || true)" == true ]]
}

require_absent_entitlement() {
  local plist="$1"
  local key="$2"
  ! /usr/bin/plutil -extract "$key" raw -o /dev/null "$plist" >/dev/null 2>&1
}

validate_entitlements() {
  local bundle="$1"
  local entitlements="$2"
  local app_group_key='com\.apple\.security\.application-groups'
  local read_only_key='com\.apple\.security\.temporary-exception\.files\.absolute-path\.read-only'
  local network_key='com\.apple\.security\.network\.client'

  read_entitlements "$bundle" "$entitlements"
  require_true_entitlement "$entitlements" 'com\.apple\.security\.app-sandbox' \
    || fail "NC extension is not sandboxed: $bundle"
  require_absent_entitlement "$entitlements" "$network_key" \
    || fail "NC extension has network entitlement: $bundle"

  if [[ "$(/usr/bin/plutil -extract "$app_group_key.0" raw -expect string -o - "$entitlements" 2>/dev/null || true)" == "group.com.liangrui.QuotaGlance" ]]; then
    return
  fi
  [[ "$(/usr/bin/plutil -extract "$read_only_key.0" raw -expect string -o - "$entitlements" 2>/dev/null || true)" == "/Users/Shared/QuotaGlance/" ]] \
    || fail "NC extension has neither the App Group nor certificate-free read entitlement: $bundle"
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

ENTITLEMENTS_DIR="$(mktemp -d /tmp/QuotaGlance-nc-entitlements.XXXXXX)"
trap '/bin/rm -rf "$ENTITLEMENTS_DIR"' EXIT
validate_entitlements "$NC_WIDGET" "$ENTITLEMENTS_DIR/widget.plist"
validate_entitlements "$NC_INTENTS" "$ENTITLEMENTS_DIR/intents.plist"

for executable in "$WIDGET_BINARY" "$INTENTS_BINARY"; do
  archs="$(/usr/bin/lipo -archs "$executable")"
  [[ "$archs" == "arm64" ]] || fail "NC extension must be arm64-only: $executable ($archs)"
done

# Search binaries directly. Avoid `strings | rg -q` under pipefail:
# rg -q exits early on match and can SIGPIPE strings (exit 141), falsely failing.
rg -a -q 'QuotaGlanceNCWidget' "$WIDGET_BINARY" \
  || fail "NC widget binary missing kind string"
rg -a -q 'IntentConfiguration|IntentTimelineProvider' "$WIDGET_BINARY" \
  || fail "NC widget binary missing IntentConfiguration path"
rg -a -q 'NCWidgetAccountIntent' "$INTENTS_BINARY" \
  || fail "NC intents binary missing NCWidgetAccountIntent"
rg -a -q 'systemMedium' "$WIDGET_BINARY" \
  || fail "NC widget binary missing systemMedium family"

INTENT_DEFINITION="$NC_WIDGET/Contents/Resources/NCWidgetAccountIntent.intentdefinition"
[[ -f "$INTENT_DEFINITION" ]] \
  || fail "NC widget is missing its Intent definition"

echo "NC extensions verified in $APP_BUNDLE" >&2
