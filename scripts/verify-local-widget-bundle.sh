#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/local-entitlement-validation.sh"

APP_BUNDLE="${1:-$HOME/Applications/QuotaGlance.app}"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/QuotaGlance"
WIDGET_BUNDLE="$APP_BUNDLE/Contents/PlugIns/QuotaGlanceWidget.appex"
WIDGET_BINARY="$WIDGET_BUNDLE/Contents/MacOS/QuotaGlanceWidget"
SHARED_DIRECTORY="/Users/Shared/QuotaGlance/"
SWIFT_DEMANGLE="/Library/Developer/CommandLineTools/usr/bin/swift-demangle"

for executable in "$APP_BINARY" "$WIDGET_BINARY" "$SWIFT_DEMANGLE"; do
  if [[ ! -x "$executable" ]]; then
    echo "Required executable is missing: $executable" >&2
    exit 1
  fi
done

read_entitlements() {
  local bundle="$1"
  local destination="$2"

  /usr/bin/codesign -d --entitlements :- "$bundle" 2>&1 \
    | /usr/bin/sed -n '/^<?xml/,$p' \
    > "$destination"
  /usr/bin/plutil -lint "$destination" >/dev/null
}

VERIFY_DIRECTORY="$(mktemp -d /tmp/QuotaGlance-entitlements.XXXXXX)"
trap '/bin/rm -rf "$VERIFY_DIRECTORY"' EXIT
APP_ENTITLEMENTS="$VERIFY_DIRECTORY/app.entitlements"
WIDGET_ENTITLEMENTS="$VERIFY_DIRECTORY/widget.entitlements"

read_entitlements "$APP_BUNDLE" "$APP_ENTITLEMENTS"
read_entitlements "$WIDGET_BUNDLE" "$WIDGET_ENTITLEMENTS"

if ! quota_glance_validate_local_entitlements \
  "$APP_ENTITLEMENTS" \
  "$WIDGET_ENTITLEMENTS" \
  "$SHARED_DIRECTORY"; then
  echo "Certificate-free bundle entitlements do not match the local policy" >&2
  exit 1
fi

WIDGET_SYMBOLS="$(/usr/bin/nm "$WIDGET_BINARY" | "$SWIFT_DEMANGLE")"

if rg -q 'QuotaGlanceTimelineProvider : WidgetKit.AppIntentTimelineProvider' \
  <<< "$WIDGET_SYMBOLS"; then
  echo "Certificate-free widget still requires App Intent metadata" >&2
  exit 1
fi

if ! rg -q 'QuotaGlanceTimelineProvider : WidgetKit.TimelineProvider' \
  <<< "$WIDGET_SYMBOLS"; then
  echo "Certificate-free widget is missing its static timeline provider" >&2
  exit 1
fi

echo "Certificate-free widget bundle is configured for local snapshot sharing"
