#!/usr/bin/env bash
set -euo pipefail

DMG_PATH="${1:?usage: verify-dmg.sh DMG_PATH [CHECKSUM_PATH] [legacy|full]}"
CHECKSUM_PATH="${2:-}"
EDITION="${3:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/distribution-validation.sh"
APP_BUNDLE_ID="com.liangrui.QuotaGlance"
WIDGET_BUNDLE_ID="com.liangrui.QuotaGlance.Widget"
NC_WIDGET_BUNDLE_ID="com.liangrui.QuotaGlance.NCWidget"
NC_INTENTS_BUNDLE_ID="com.liangrui.QuotaGlance.NCIntents"
VERIFY_DIR="$(mktemp -d /tmp/QuotaGlance-dmg-verify.XXXXXX)"
ATTACH_PLIST="$VERIFY_DIR/attach.plist"
MOUNT_POINT=""
DEVICE_NODE=""

cleanup() {
  if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
    /usr/bin/hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  elif [[ -n "$DEVICE_NODE" ]]; then
    /usr/bin/hdiutil detach "$DEVICE_NODE" >/dev/null 2>&1 || true
  fi
  /bin/rm -rf -- "$VERIFY_DIR"
}
trap cleanup EXIT

bundle_id() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$1/Contents/Info.plist" 2>/dev/null
}

if [[ -z "$EDITION" ]]; then
  case "$(/usr/bin/basename "$DMG_PATH")" in
    *-macOS12-arm64.dmg)
      EDITION="legacy"
      ;;
    *-macOS14-arm64.dmg)
      EDITION="full"
      ;;
    *)
      echo "Unable to infer DMG edition from its file name" >&2
      exit 1
      ;;
  esac
fi
case "$EDITION" in
  legacy)
    OS_TAG="macOS12"
    EXPECTED_MINIMUM="12.0"
    README_TITLE_SUFFIX="macOS 12 兼容版安装说明"
    ;;
  full)
    OS_TAG="macOS14"
    EXPECTED_MINIMUM="14.0"
    README_TITLE_SUFFIX="macOS 14 完整版安装说明"
    ;;
  *)
    echo "DMG edition must be legacy or full" >&2
    exit 1
    ;;
esac

[[ -f "$DMG_PATH" && ! -L "$DMG_PATH" ]] || {
  echo "DMG is missing or is not a regular file: $DMG_PATH" >&2
  exit 1
}

/usr/bin/hdiutil verify "$DMG_PATH" >/dev/null

if [[ -n "$CHECKSUM_PATH" ]]; then
  [[ -f "$CHECKSUM_PATH" && ! -L "$CHECKSUM_PATH" ]] || {
    echo "Checksum is missing or is not a regular file: $CHECKSUM_PATH" >&2
    exit 1
  }
  CHECKSUM_RECORD="$(/usr/bin/awk '
    NF == 0 { next }
    {
      count += 1
      if (count > 1 || NF != 2) {
        exit 2
      }
      print $1
      print $2
    }
    END {
      if (count != 1) {
        exit 2
      }
    }
  ' "$CHECKSUM_PATH")" || {
    echo "Checksum must contain exactly one SHA-256 record" >&2
    exit 1
  }
  EXPECTED_DIGEST="$(/usr/bin/sed -n '1p' <<< "$CHECKSUM_RECORD")"
  CHECKSUM_NAME="$(/usr/bin/sed -n '2p' <<< "$CHECKSUM_RECORD")"
  EXPECTED_NAME="$(/usr/bin/basename "$DMG_PATH")"
  [[ "$EXPECTED_DIGEST" =~ ^[0-9A-Fa-f]{64}$ \
    && "$CHECKSUM_NAME" == "$EXPECTED_NAME" ]] || {
    echo "Checksum does not describe the selected DMG" >&2
    exit 1
  }
  ACTUAL_DIGEST="$(/usr/bin/shasum -a 256 "$DMG_PATH" | /usr/bin/awk '{print $1}')"
  NORMALIZED_EXPECTED="$(printf '%s' "$EXPECTED_DIGEST" | /usr/bin/tr 'A-F' 'a-f')"
  NORMALIZED_ACTUAL="$(printf '%s' "$ACTUAL_DIGEST" | /usr/bin/tr 'A-F' 'a-f')"
  [[ "$NORMALIZED_EXPECTED" == "$NORMALIZED_ACTUAL" ]] || {
    echo "DMG checksum mismatch" >&2
    exit 1
  }
fi

/usr/bin/hdiutil attach -readonly -nobrowse -plist "$DMG_PATH" > "$ATTACH_PLIST"
MOUNT_INFO="$(quota_glance_mount_info "$ATTACH_PLIST")" || {
  echo "DMG attach response did not contain a mount point" >&2
  exit 1
}
DEVICE_NODE="$(/usr/bin/sed -n '1p' <<< "$MOUNT_INFO")"
MOUNT_POINT="$(/usr/bin/sed -n '2p' <<< "$MOUNT_INFO")"

[[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]] || {
  echo "DMG did not mount successfully" >&2
  exit 1
}

APP="$MOUNT_POINT/QuotaGlance.app"
[[ -d "$APP" ]] || {
  echo "DMG app is missing" >&2
  exit 1
}
VERSION="$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
EXPECTED_DMG_NAME="QuotaGlance-$VERSION-$OS_TAG-arm64.dmg"
[[ "$(/usr/bin/basename "$DMG_PATH")" == "$EXPECTED_DMG_NAME" ]] || {
  echo "DMG file name does not match its app version and edition" >&2
  exit 1
}
[[ "$(/usr/libexec/PlistBuddy \
  -c 'Print :LSMinimumSystemVersion' \
  "$APP/Contents/Info.plist")" == "$EXPECTED_MINIMUM" ]] || {
  echo "Host minimum system version does not match the DMG edition" >&2
  exit 1
}

ACTUAL_ITEMS="$(
  /usr/bin/find "$MOUNT_POINT" -mindepth 1 -maxdepth 1 \
    -exec /usr/bin/basename {} \; | LC_ALL=C /usr/bin/sort
)"
EXPECTED_ITEMS="$(printf '%s\n' \
  'Applications' \
  'QuotaGlance.app' \
  'README.txt' | LC_ALL=C /usr/bin/sort)"
[[ "$ACTUAL_ITEMS" == "$EXPECTED_ITEMS" ]] || {
  echo "DMG top-level layout is invalid:" >&2
  printf '%s\n' "$ACTUAL_ITEMS" >&2
  exit 1
}

[[ -L "$MOUNT_POINT/Applications" \
  && "$(/usr/bin/readlink "$MOUNT_POINT/Applications")" == "/Applications" ]] || {
  echo "DMG Applications shortcut is invalid" >&2
  exit 1
}
quota_glance_validate_mounted_payload "$MOUNT_POINT" || {
  echo "DMG payload contains an unsafe file type or symbolic link" >&2
  exit 1
}

WIDGET="$APP/Contents/PlugIns/QuotaGlanceWidget.appex"
NC_WIDGET="$APP/Contents/PlugIns/QuotaGlanceNCWidget.appex"
NC_INTENTS="$APP/Contents/PlugIns/QuotaGlanceNCIntents.appex"
[[ "$(bundle_id "$APP")" == "$APP_BUNDLE_ID" ]] || {
  echo "Unexpected host bundle identifier" >&2
  exit 1
}

/usr/bin/codesign --verify --deep --strict "$APP"
EXECUTABLES=("$APP/Contents/MacOS/QuotaGlance")
"$ROOT_DIR/scripts/verify-nc-extensions.sh" "$APP"
EXECUTABLES+=(
  "$NC_WIDGET/Contents/MacOS/QuotaGlanceNCWidget"
  "$NC_INTENTS/Contents/MacOS/QuotaGlanceNCIntents"
)
if [[ "$EDITION" == full ]]; then
  [[ "$(bundle_id "$WIDGET")" == "$WIDGET_BUNDLE_ID" ]] || {
    echo "Unexpected widget bundle identifier" >&2
    exit 1
  }
  [[ "$(/usr/libexec/PlistBuddy \
    -c 'Print :LSMinimumSystemVersion' \
    "$WIDGET/Contents/Info.plist")" == "14.0" ]] || {
    echo "Widget minimum system version is not macOS 14" >&2
    exit 1
  }
  "$ROOT_DIR/scripts/verify-local-widget-bundle.sh" "$APP"
  "$ROOT_DIR/scripts/verify-widget-entrypoint.sh" "$WIDGET"
  EXECUTABLES+=("$WIDGET/Contents/MacOS/QuotaGlanceWidget")
else
  if [[ -e "$WIDGET" ]]; then
    echo "macOS 12 edition unexpectedly contains the desktop Widget" >&2
    exit 1
  fi
fi

# Only allow the expected appexes for this edition.
while IFS= read -r appex; do
  case "$(basename "$appex")" in
    QuotaGlanceNCWidget.appex|QuotaGlanceNCIntents.appex)
      ;;
    QuotaGlanceWidget.appex)
      [[ "$EDITION" == full ]] || {
        echo "Unexpected desktop Widget in macOS 12 edition" >&2
        exit 1
      }
      ;;
    *)
      echo "Unexpected app extension: $appex" >&2
      exit 1
      ;;
  esac
done < <(/usr/bin/find "$APP/Contents/PlugIns" -maxdepth 1 -type d -name '*.appex' 2>/dev/null)

for executable in "${EXECUTABLES[@]}"; do
  ARCHS="$(/usr/bin/lipo -archs "$executable")"
  [[ "$ARCHS" == "arm64" ]] || {
    echo "DMG executable must contain only arm64, found: $ARCHS" >&2
    exit 1
  }
done

SIGNING_DETAILS="$(/usr/bin/codesign -dvvv "$APP" 2>&1)"
rg -q '^Signature=adhoc$' <<< "$SIGNING_DETAILS" || {
  echo "DMG app is not ad hoc signed as documented" >&2
  exit 1
}

rg -q "^QuotaGlance $VERSION $README_TITLE_SUFFIX$" "$MOUNT_POINT/README.txt" || {
  echo "DMG README version does not match the app" >&2
  exit 1
}
rg -q '未经过 Apple Developer ID 签名或 Apple 公证' "$MOUNT_POINT/README.txt" || {
  echo "DMG README does not disclose Gatekeeper limitations" >&2
  exit 1
}
if [[ "$EDITION" == legacy ]]; then
  rg -q '不包含桌面小组件' "$MOUNT_POINT/README.txt" || {
    echo "macOS 12 README does not disclose the Widget limitation" >&2
    exit 1
  }
  rg -q '通知中心' "$MOUNT_POINT/README.txt" || {
    echo "macOS 12 README does not describe Notification Center widget support" >&2
    exit 1
  }
else
  rg -q '包含可选择全部账户或指定账户的桌面小组件' \
    "$MOUNT_POINT/README.txt" || {
    echo "macOS 14 README does not describe Widget support" >&2
    exit 1
  }
  rg -q '通知中心' "$MOUNT_POINT/README.txt" || {
    echo "macOS 14 README does not describe Notification Center widget support" >&2
    exit 1
  }
fi
if rg -q '@VERSION@|@SOURCE_ARCHIVE@|SOURCE-COMMIT|source\.zip' "$MOUNT_POINT/README.txt"; then
  echo "DMG README contains an unresolved template placeholder" >&2
  exit 1
fi

set +e
GATEKEEPER_OUTPUT="$(/usr/sbin/spctl -a -vv --type execute "$APP" 2>&1)"
GATEKEEPER_STATUS=$?
set -e
if [[ "$GATEKEEPER_STATUS" == 0 ]]; then
  echo "Gatekeeper unexpectedly accepted the ad hoc build" >&2
  exit 1
fi
if ! quota_glance_validate_gatekeeper_rejection \
  "$GATEKEEPER_STATUS" \
  "$GATEKEEPER_OUTPUT"; then
  echo "Gatekeeper assessment failed unexpectedly" >&2
  exit 1
fi
echo "Gatekeeper rejection confirmed for the documented ad hoc build"

echo "DMG verification passed: $DMG_PATH"
