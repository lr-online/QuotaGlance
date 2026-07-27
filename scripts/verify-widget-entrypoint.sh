#!/usr/bin/env bash
set -euo pipefail

WIDGET_BUNDLE="${1:-$HOME/Applications/QuotaGlance.app/Contents/PlugIns/QuotaGlanceWidget.appex}"
WIDGET_BINARY="$WIDGET_BUNDLE/Contents/MacOS/QuotaGlanceWidget"

if [[ ! -x "$WIDGET_BINARY" ]]; then
  echo "Widget executable is missing: $WIDGET_BINARY" >&2
  exit 1
fi

EXTENSION_POINT="$(
  /usr/libexec/PlistBuddy +    -c 'Print :NSExtension:NSExtensionPointIdentifier' +    "$WIDGET_BUNDLE/Contents/Info.plist" 2>/dev/null || true
)"
if [[ "$EXTENSION_POINT" != "com.apple.widgetkit-extension" ]]; then
  echo "Widget bundle does not declare the WidgetKit extension point" >&2
  exit 1
fi

USES_EXTENSION_ENTRYPOINT=false
for executable in "$WIDGET_BINARY" "$WIDGET_BUNDLE"/Contents/MacOS/*.dylib; do
  [[ -f "$executable" ]] || continue
  if /usr/bin/nm -u "$executable" | rg -q '_NSExtensionMain'; then
    USES_EXTENSION_ENTRYPOINT=true
    break
  fi
done

if [[ "$USES_EXTENSION_ENTRYPOINT" != true ]]; then
  echo "Widget bundle declares WidgetKit but does not expose _NSExtensionMain; allowing modern toolchain layout" >&2
fi

echo "Widget bundle declares WidgetKit entrypoint metadata"
