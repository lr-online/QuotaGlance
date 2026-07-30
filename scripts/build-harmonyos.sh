#!/usr/bin/env bash
# Build the HarmonyOS entry HAP with DevEco CLI tools or ErBWs/setup-ohos.
# Expects hvigorw + ohpm on PATH (or DevEco Studio installed locally).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARMONY_DIR="$ROOT_DIR/HarmonyOS"
BUILD_MODE="${HARMONYOS_BUILD_MODE:-debug}"
SKIP_SIGN="${HARMONYOS_SKIP_SIGN:-0}"

if [[ ! -d "$HARMONY_DIR" ]]; then
  echo "error: HarmonyOS project not found at $HARMONY_DIR" >&2
  exit 1
fi

cd "$HARMONY_DIR"

if [[ -n "${HOS_SDK_HOME:-}" ]]; then
  export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-${HOS_SDK_HOME}/default}"
  cat > local.properties <<EOF
sdk.dir=${HOS_SDK_HOME}/default/openharmony
hwsdk.dir=${HOS_SDK_HOME}/default
EOF
  echo "Configured local.properties from HOS_SDK_HOME=${HOS_SDK_HOME}"
fi

if [[ -z "${DEVECO_SDK_HOME:-}" ]]; then
  echo "error: DEVECO_SDK_HOME is not set (run ErBWs/setup-ohos or install DevEco Studio)" >&2
  exit 1
fi

PROFILE="$HARMONY_DIR/build-profile.json5"
PROFILE_BACKUP=""
restore_profile() {
  if [[ -n "$PROFILE_BACKUP" && -f "$PROFILE_BACKUP" ]]; then
    mv "$PROFILE_BACKUP" "$PROFILE"
  fi
}
trap restore_profile EXIT

if [[ "$SKIP_SIGN" == "1" ]]; then
  # CI has no Huawei debug cert; drop the product signingConfig reference.
  PROFILE_BACKUP="$(mktemp)"
  cp "$PROFILE" "$PROFILE_BACKUP"
  python3 - "$PROFILE" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
updated = re.sub(r'\n\s*"signingConfig"\s*:\s*"[^"]*"\s*,?', '', text, count=1)
if updated == text:
    raise SystemExit('error: signingConfig not found in build-profile.json5')
path.write_text(updated)
PY
  echo "Removed signingConfig for unsigned CI build"
fi

if ! command -v ohpm >/dev/null 2>&1; then
  echo "error: ohpm not found on PATH" >&2
  exit 1
fi

if ! command -v hvigorw >/dev/null 2>&1 && [[ ! -x "$HARMONY_DIR/hvigorw" ]]; then
  echo "error: hvigorw not found on PATH" >&2
  exit 1
fi

echo "ohpm install --all"
ohpm install --all

HVIGORW=(./hvigorw)
if [[ ! -x "$HARMONY_DIR/hvigorw" ]]; then
  HVIGORW=(hvigorw)
fi

echo "Building entry HAP (buildMode=${BUILD_MODE}, skipSign=${SKIP_SIGN})"
"${HVIGORW[@]}" assembleHap \
  --mode module \
  -p product=default \
  -p module=entry@default \
  -p "buildMode=${BUILD_MODE}" \
  --no-daemon

HAP_DIR="$HARMONY_DIR/entry/build/default/outputs/default"
shopt -s nullglob
haps=("$HAP_DIR"/*.hap)
if [[ ${#haps[@]} -eq 0 ]]; then
  echo "error: no .hap produced under $HAP_DIR" >&2
  exit 1
fi

echo "BUILD SUCCESSFUL"
printf 'HAP: %s\n' "${haps[@]}"
