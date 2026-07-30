#!/usr/bin/env bash
# Build the HarmonyOS entry HAP with ErBWs/setup-ohos or DevEco CLI tools.
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

# ErBWs/setup-ohos exports HOS_SDK_HOME=.../command-line-tools/sdk (contains default/).
# Working CI examples set DEVECO_SDK_HOME to that sdk directory, not sdk/default.
if [[ -n "${HOS_SDK_HOME:-}" ]]; then
  export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-${HOS_SDK_HOME}}"
  cat > local.properties <<EOF
sdk.dir=${HOS_SDK_HOME}/default/openharmony
hwsdk.dir=${HOS_SDK_HOME}/default
EOF
  echo "Configured DEVECO_SDK_HOME=${DEVECO_SDK_HOME}"
  echo "Configured local.properties from HOS_SDK_HOME=${HOS_SDK_HOME}"
fi

if [[ -z "${DEVECO_SDK_HOME:-}" ]]; then
  echo "error: DEVECO_SDK_HOME is not set (run ErBWs/setup-ohos or install DevEco Studio)" >&2
  exit 1
fi

if ! command -v ohpm >/dev/null 2>&1; then
  echo "error: ohpm not found on PATH" >&2
  exit 1
fi

# Prefer the CLI-tools hvigorw from PATH (ErBWs). Avoid the local wrapper when it would
# recurse incorrectly or force a DevEco.app path on CI.
if ! command -v hvigorw >/dev/null 2>&1; then
  echo "error: hvigorw not found on PATH" >&2
  exit 1
fi
HVIGORW=(hvigorw)

MODULE_JSON5="$HARMONY_DIR/entry/src/main/module.json5"
if ! grep -Fq '"tablet"' "$MODULE_JSON5"; then
  echo "error: entry module must declare deviceTypes including tablet (Huawei Pad Mini)" >&2
  exit 1
fi
if ! grep -Fq '"phone"' "$MODULE_JSON5"; then
  echo "error: entry module must declare deviceTypes including phone" >&2
  exit 1
fi

echo "ohpm install --all"
ohpm install --all --registry https://ohpm.openharmony.cn/ohpm/ || ohpm install --all

HVIGOR_ARGS=(
  assembleHap
  --mode module
  -p product=default
  -p module=entry@default
  -p "buildMode=${BUILD_MODE}"
  --no-daemon
)

if [[ "$SKIP_SIGN" == "1" ]]; then
  # Matches open-source CI (e.g. OHOTP) that builds without a Huawei debug cert.
  HVIGOR_ARGS+=(--config properties.ignoreSignHap=true)
fi

echo "Building entry HAP (buildMode=${BUILD_MODE}, skipSign=${SKIP_SIGN})"
echo "Using hvigorw: $(command -v hvigorw)"
ls -la "${DEVECO_SDK_HOME}" || true
ls -la "${DEVECO_SDK_HOME}/default" 2>/dev/null || true

"${HVIGORW[@]}" "${HVIGOR_ARGS[@]}"

HAP_DIR="$HARMONY_DIR/entry/build/default/outputs/default"
shopt -s nullglob
haps=("$HAP_DIR"/*.hap)
if [[ ${#haps[@]} -eq 0 ]]; then
  # Fallback: search common output locations
  mapfile -t haps < <(find "$HARMONY_DIR" -type f -name '*.hap' 2>/dev/null | head -20)
fi
if [[ ${#haps[@]} -eq 0 ]]; then
  echo "error: no .hap produced under $HARMONY_DIR" >&2
  exit 1
fi

echo "BUILD SUCCESSFUL"
printf 'HAP: %s\n' "${haps[@]}"
