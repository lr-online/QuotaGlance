#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WIDGET_CARD="$ROOT_DIR/Platforms/HarmonyOS/entry/src/main/ets/widget/pages/WidgetCard.ets"
FORM_ABILITY="$ROOT_DIR/Platforms/HarmonyOS/entry/src/main/ets/entryformability/EntryFormAbility.ets"
WORKFLOW="$ROOT_DIR/.github/workflows/harmonyos.yml"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local needle="$1"
  local file="$2"
  grep -Fq -- "$needle" "$file" || fail "$file missing: $needle"
}

assert_not_contains() {
  local needle="$1"
  local file="$2"
  ! grep -Fq -- "$needle" "$file" || fail "$file must not contain: $needle"
}

# Widget pages run in the system form process. Keep swipe recognition inside
# the widget-supported Swiper component and dispatch persistence to its
# FormExtensionAbility through the supported message event.
assert_contains 'Swiper()' "$WIDGET_CARD"
assert_contains '.onChange((index: number)' "$WIDGET_CARD"
assert_contains "action: 'message'" "$WIDGET_CARD"
assert_not_contains 'PanGesture' "$WIDGET_CARD"
assert_not_contains 'getContext(' "$WIDGET_CARD"
assert_not_contains 'switchFormAccount(' "$WIDGET_CARD"

assert_contains 'onFormEvent(formId: string, message: string): void' "$FORM_ABILITY"
assert_contains 'switchFormAccount(this.context, formId, direction)' "$FORM_ABILITY"
assert_contains '"Tests/ScriptTests/HarmonyOSWidgetInteractionTests.sh"' "$WORKFLOW"

echo "OK: HarmonyOS widget interactions use form-supported APIs"
