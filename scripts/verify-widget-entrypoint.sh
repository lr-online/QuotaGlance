#!/usr/bin/env bash
set -euo pipefail

WIDGET_BUNDLE="${1:-$HOME/Applications/QuotaGlance.app/Contents/PlugIns/QuotaGlanceWidget.appex}"
WIDGET_BINARY="$WIDGET_BUNDLE/Contents/MacOS/QuotaGlanceWidget"

if [[ ! -x "$WIDGET_BINARY" ]]; then
  echo "Widget executable is missing: $WIDGET_BINARY" >&2
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
  echo "Widget is not linked with the macOS extension entry point" >&2
  exit 1
fi

echo "Widget uses _NSExtensionMain"
