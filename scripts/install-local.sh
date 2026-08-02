#!/usr/bin/env bash
set -euo pipefail

APP_NAME="QuotaGlance"
APP_BUNDLE_ID="com.liangrui.QuotaGlance"
WIDGET_NAME="QuotaGlanceWidget"
WIDGET_BUNDLE_ID="com.liangrui.QuotaGlance.Widget"
NC_WIDGET_NAME="QuotaGlanceNCWidget"
NC_WIDGET_BUNDLE_ID="com.liangrui.QuotaGlance.NCWidget"
NC_INTENTS_NAME="QuotaGlanceNCIntents"
NC_INTENTS_BUNDLE_ID="com.liangrui.QuotaGlance.NCIntents"

EDITION="${1:-full}"
case "$EDITION" in
  full|legacy)
    ;;
  *)
    echo "usage: $0 [full|legacy]" >&2
    exit 2
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/local-snapshot-storage.sh"

BUILT_APP="$("$ROOT_DIR/scripts/build-local.sh" Release "$EDITION")"
BUILT_WIDGET="$BUILT_APP/Contents/PlugIns/$WIDGET_NAME.appex"
BUILT_NC_WIDGET="$BUILT_APP/Contents/PlugIns/$NC_WIDGET_NAME.appex"
BUILT_NC_INTENTS="$BUILT_APP/Contents/PlugIns/$NC_INTENTS_NAME.appex"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
INSTALLED_WIDGET="$INSTALLED_APP/Contents/PlugIns/$WIDGET_NAME.appex"
INSTALLED_NC_WIDGET="$INSTALLED_APP/Contents/PlugIns/$NC_WIDGET_NAME.appex"
INSTALLED_NC_INTENTS="$INSTALLED_APP/Contents/PlugIns/$NC_INTENTS_NAME.appex"
BACKUP_DIR="$HOME/Library/Application Support/$APP_NAME/Backups"
LOCAL_SNAPSHOT_DIR="/Users/Shared/$APP_NAME"
LOCAL_SNAPSHOT="$LOCAL_SNAPSHOT_DIR/quota-snapshot-v1.json"
LEGACY_SNAPSHOT="$HOME/Library/Group Containers/group.com.liangrui.QuotaGlance/quota-snapshot-v1.json"

bundle_id() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null
}

require_bundle_id() {
  local bundle_path="$1"
  local expected_id="$2"
  local actual_id

  if [[ ! -d "$bundle_path" ]]; then
    echo "Expected bundle is missing: $bundle_path" >&2
    exit 1
  fi

  actual_id="$(bundle_id "$bundle_path" || true)"
  if [[ "$actual_id" != "$expected_id" ]]; then
    echo "Refusing bundle with ID '${actual_id:-missing}'; expected '$expected_id': $bundle_path" >&2
    exit 1
  fi
}

require_bundle_id "$BUILT_APP" "$APP_BUNDLE_ID"
require_bundle_id "$BUILT_NC_WIDGET" "$NC_WIDGET_BUNDLE_ID"
require_bundle_id "$BUILT_NC_INTENTS" "$NC_INTENTS_BUNDLE_ID"
if [[ "$EDITION" == full ]]; then
  require_bundle_id "$BUILT_WIDGET" "$WIDGET_BUNDLE_ID"
elif [[ -e "$BUILT_WIDGET" ]]; then
  echo "Legacy build unexpectedly contains the desktop Widget" >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict "$BUILT_APP"
"$ROOT_DIR/scripts/verify-nc-extensions.sh" "$BUILT_APP"
if [[ "$EDITION" == full ]]; then
  "$ROOT_DIR/scripts/verify-local-widget-bundle.sh" "$BUILT_APP"
fi

/bin/mkdir -p "$INSTALL_DIR"
/bin/mkdir -p "$BACKUP_DIR"
quota_glance_prepare_snapshot_directory "$LOCAL_SNAPSHOT_DIR"
quota_glance_migrate_snapshot_if_needed "$LEGACY_SNAPSHOT" "$LOCAL_SNAPSHOT"

if [[ -e "$INSTALLED_APP" ]]; then
  require_bundle_id "$INSTALLED_APP" "$APP_BUNDLE_ID"

  timestamp="$(/bin/date '+%Y%m%d-%H%M%S')"
  backup_path="$BACKUP_DIR/$APP_NAME.backup-$timestamp.app"
  if [[ -e "$backup_path" ]]; then
    echo "Backup path already exists; refusing to overwrite it: $backup_path" >&2
    exit 1
  fi

  unregister_extension() {
    local bundle_path="$1"
    local executable_name="$2"
    local expected_bundle_id="$3"
    if [[ -d "$bundle_path" ]]; then
      require_bundle_id "$bundle_path" "$expected_bundle_id"
      /usr/bin/pkill -x "$executable_name" >/dev/null 2>&1 || true
      /usr/bin/pluginkit -r "$bundle_path" >/dev/null 2>&1 || true
    fi
  }
  unregister_extension "$INSTALLED_NC_WIDGET" "$NC_WIDGET_NAME" "$NC_WIDGET_BUNDLE_ID"
  unregister_extension "$INSTALLED_NC_INTENTS" "$NC_INTENTS_NAME" "$NC_INTENTS_BUNDLE_ID"
  unregister_extension "$INSTALLED_WIDGET" "$WIDGET_NAME" "$WIDGET_BUNDLE_ID"
  /usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  /bin/mv "$INSTALLED_APP" "$backup_path"
  echo "Previous installation moved to: $backup_path"
fi

/usr/bin/ditto "$BUILT_APP" "$INSTALLED_APP"
require_bundle_id "$INSTALLED_APP" "$APP_BUNDLE_ID"
require_bundle_id "$INSTALLED_NC_WIDGET" "$NC_WIDGET_BUNDLE_ID"
require_bundle_id "$INSTALLED_NC_INTENTS" "$NC_INTENTS_BUNDLE_ID"
if [[ "$EDITION" == full ]]; then
  require_bundle_id "$INSTALLED_WIDGET" "$WIDGET_BUNDLE_ID"
elif [[ -e "$INSTALLED_WIDGET" ]]; then
  echo "Legacy installation unexpectedly contains the desktop Widget" >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict "$INSTALLED_APP"

/usr/bin/pluginkit -a "$INSTALLED_NC_WIDGET"
/usr/bin/pluginkit -a "$INSTALLED_NC_INTENTS"
if [[ "$EDITION" == full ]]; then
  /usr/bin/pluginkit -a "$INSTALLED_WIDGET"
fi
/usr/bin/open -n "$INSTALLED_APP"

required_bundle_ids=("$NC_WIDGET_BUNDLE_ID" "$NC_INTENTS_BUNDLE_ID")
if [[ "$EDITION" == full ]]; then
  required_bundle_ids+=("$WIDGET_BUNDLE_ID")
fi
for required_bundle_id in "${required_bundle_ids[@]}"; do
  extension_registered=false
  for _ in {1..20}; do
    registered_extensions="$(/usr/bin/pluginkit -m -A -D || true)"
    if /usr/bin/grep -F "$required_bundle_id" <<< "$registered_extensions" >/dev/null; then
      extension_registered=true
      break
    fi
    sleep 0.5
  done

  if [[ "$extension_registered" != true ]]; then
    echo "The app was installed, but PlugInKit has not registered $required_bundle_id." >&2
    echo "Open the app once, then run this installer again or log out and back in." >&2
    exit 1
  fi
done

echo "Installed and launched ($EDITION): $INSTALLED_APP"
printf 'Registered extension: %s\n' "${required_bundle_ids[@]}"
