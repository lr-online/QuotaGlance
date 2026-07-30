#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: fetch-ci-package.sh <pr-number|branch|run-id> [--install] [--edition legacy|full]

Download Package workflow DMG artifacts from GitHub Actions.
With --install, replace ~/Applications/QuotaGlance.app from the macOS12 (legacy) DMG.
EOF
  exit 2
}

TARGET="${1:-}"
[[ -n "$TARGET" ]] || usage
shift || true

INSTALL=false
EDITION="legacy"
REPO="${QUOTAGLANCE_REPO:-lr-online/QuotaGlance}"
OUT_DIR="${QUOTAGLANCE_PACKAGE_DIR:-$HOME/Downloads/QuotaGlance-ci}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      INSTALL=true
      ;;
    --edition)
      shift
      EDITION="${1:-}"
      [[ "$EDITION" == "legacy" || "$EDITION" == "full" ]] || usage
      ;;
    *)
      usage
      ;;
  esac
  shift || true
done

OS_TAG="macOS12"
if [[ "$EDITION" == "full" ]]; then
  OS_TAG="macOS14"
fi

resolve_run_id() {
  local target="$1"
  local run_id=""
  local branch=""

  if [[ "$target" =~ ^[0-9]+$ ]] && [[ ${#target} -ge 8 ]]; then
    # Likely a run id (Package runs are large integers).
    if gh run view "$target" -R "$REPO" --json databaseId >/dev/null 2>&1; then
      printf '%s\n' "$target"
      return 0
    fi
  fi

  if [[ "$target" =~ ^[0-9]+$ ]]; then
    branch="$(gh pr view "$target" -R "$REPO" --json headRefName -q .headRefName)"
  else
    branch="$target"
  fi

  run_id="$(
    gh run list \
      -R "$REPO" \
      --workflow=Package \
      --branch "$branch" \
      --limit 20 \
      --json databaseId,status,conclusion,event \
      --jq '
        map(select(.status == "completed" and .conclusion == "success"))
        | .[0].databaseId // empty
      '
  )"

  if [[ -z "$run_id" ]]; then
    run_id="$(
      gh run list \
        -R "$REPO" \
        --workflow=Package \
        --branch "$branch" \
        --limit 5 \
        --json databaseId,status \
        --jq 'map(select(.status != "completed")) | .[0].databaseId // empty'
    )"
  fi

  [[ -n "$run_id" ]] || {
    echo "No Package run found for: $target (branch: $branch)" >&2
    exit 1
  }
  printf '%s\n' "$run_id"
}

wait_for_success() {
  local run_id="$1"

  echo "Waiting for Package run $run_id ..."
  gh run watch "$run_id" -R "$REPO" --exit-status
}

install_from_dmg() {
  local dmg="$1"
  local mount_point=""
  local app_src=""
  local install_dir="$HOME/Applications"
  local installed_app="$install_dir/QuotaGlance.app"
  local attach_output=""

  /bin/mkdir -p "$install_dir"
  pkill -x QuotaGlance >/dev/null 2>&1 || true
  sleep 1

  attach_output="$(/usr/bin/hdiutil attach -nobrowse -plist "$dmg")"
  mount_point="$(
    /usr/bin/plutil -extract system-entities json -o - - <<< "$attach_output" \
      | /usr/bin/python3 -c '
import json,sys
entities=json.load(sys.stdin)
for entity in entities:
    mount=entity.get("mount-point")
    if mount:
        print(mount)
        break
'
  )"
  [[ -n "$mount_point" ]] || {
    echo "Failed to mount DMG: $dmg" >&2
    exit 1
  }

  app_src="$(/usr/bin/find "$mount_point" -maxdepth 2 -name 'QuotaGlance.app' -type d | /usr/bin/head -n 1)"
  [[ -d "$app_src" ]] || {
    /usr/bin/hdiutil detach "$mount_point" >/dev/null 2>&1 || true
    echo "QuotaGlance.app missing from DMG" >&2
    exit 1
  }

  /bin/rm -rf "$installed_app"
  /usr/bin/ditto "$app_src" "$installed_app"
  /usr/bin/xattr -dr com.apple.quarantine "$installed_app" 2>/dev/null || true
  /usr/bin/hdiutil detach "$mount_point" >/dev/null

  echo "Installed: $installed_app"
  /usr/bin/open -n "$installed_app"
  sleep 2
  /usr/bin/pgrep -x QuotaGlance >/dev/null || {
    echo "QuotaGlance did not stay running after open" >&2
    exit 1
  }
  echo "Smoke check passed: QuotaGlance is running"
}

RUN_ID="$(resolve_run_id "$TARGET")"
RUN_META="$(gh run view "$RUN_ID" -R "$REPO" --json status,conclusion,url)"
STATUS="$(printf '%s' "$RUN_META" | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["status"])')"
CONCLUSION="$(printf '%s' "$RUN_META" | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("conclusion") or "-")')"
URL="$(printf '%s' "$RUN_META" | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["url"])')"
echo "Using run $RUN_ID ($STATUS/$CONCLUSION) $URL"

if [[ "$STATUS" != "completed" ]]; then
  wait_for_success "$RUN_ID"
elif [[ "$CONCLUSION" != "success" ]]; then
  echo "Run did not succeed: $CONCLUSION" >&2
  exit 1
fi

/bin/mkdir -p "$OUT_DIR"
/bin/rm -rf "$OUT_DIR/artifact"
gh run download "$RUN_ID" -R "$REPO" -D "$OUT_DIR/artifact"

DMG="$(/usr/bin/find "$OUT_DIR/artifact" -name "QuotaGlance-*-$OS_TAG-arm64.dmg" | /usr/bin/head -n 1)"
CHECKSUM="$DMG.sha256"
[[ -f "$DMG" ]] || {
  echo "No $OS_TAG DMG found in run $RUN_ID artifacts" >&2
  /usr/bin/find "$OUT_DIR/artifact" -type f >&2 || true
  exit 1
}
[[ -f "$CHECKSUM" ]] || {
  echo "Missing checksum for $DMG" >&2
  exit 1
}

(
  cd "$(/usr/bin/dirname "$DMG")"
  /usr/bin/shasum -a 256 -c "$(/usr/bin/basename "$CHECKSUM")"
)

echo "Downloaded: $DMG"
if [[ "$INSTALL" == true ]]; then
  [[ "$EDITION" == "legacy" ]] || {
    echo "--install currently supports --edition legacy only" >&2
    exit 1
  }
  install_from_dmg "$DMG"
fi
