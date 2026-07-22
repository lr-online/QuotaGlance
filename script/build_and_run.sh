#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="QuotaGlance"
BUNDLE_ID="com.liangrui.QuotaGlance"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/QuotaGlance.xcodeproj"
DERIVED_DATA="$ROOT_DIR/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cd "$ROOT_DIR"
xcodegen generate --spec "$ROOT_DIR/project.yml"

if ! /usr/bin/xcodebuild -version >/dev/null 2>&1; then
  echo "Full Xcode is required. Install Xcode, launch it once, then select it with xcode-select." >&2
  exit 1
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

/usr/bin/xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$APP_NAME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    /usr/bin/lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
