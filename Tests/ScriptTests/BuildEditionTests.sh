#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
XCODE_DEVELOPER_DIR="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

build_setting() {
  local target="$1"
  local setting="$2"

  DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" /usr/bin/xcodebuild \
    -project "$ROOT_DIR/QuotaGlance.xcodeproj" \
    -target "$target" \
    -showBuildSettings 2>/dev/null \
    | /usr/bin/awk -v setting="$setting" \
      '$1 == setting && $2 == "=" { print $3; exit }'
}

rg -Fq '.macOS(.v12)' "$ROOT_DIR/Package.swift" \
  || fail "QuotaGlanceCore does not support macOS 12"
rg -q '^  QuotaGlanceLegacy:$' "$ROOT_DIR/project.yml" \
  || fail "legacy host target is missing"
rg -q 'QuotaGlanceLegacy' "$ROOT_DIR/scripts/build-local.sh" \
  || fail "local build script cannot select the legacy edition"
[[ -f "$ROOT_DIR/Tests/ScriptTests/AppIconTests.sh" ]] \
  || fail "app icon contract test is missing"
[[ -f "$ROOT_DIR/Tests/ScriptTests/GitHubActionsTests.sh" ]] \
  || fail "GitHub Actions contract test is missing"

rg -q 'compatibleSystemSymbol' "$ROOT_DIR/App/MenuBar/StatusBarController.swift" \
  || fail "status bar does not use compatible SF Symbol fallback"
rg -q 'NSApp.activate\(ignoringOtherApps: true\)' \
  "$ROOT_DIR/App/MenuBar/StatusBarController.swift" \
  || fail "popover show path does not activate the accessory app"
rg -q 'ApplicationMenuInstaller.installMainMenuIfNeeded' \
  "$ROOT_DIR/App/QuotaGlanceApp.swift" \
  || fail "accessory app does not install Edit menu for paste shortcuts"
rg -q 'PasteboardCommands' "$ROOT_DIR/App/QuotaGlanceApp.swift" \
  || fail "Settings scene lacks pasteboard Commands for ⌘V"
rg -q 'QuotaGlanceApplication' "$ROOT_DIR/App/Info.plist" \
  || fail "Info.plist does not use QuotaGlanceApplication for edit shortcuts"
rg -q '@objc\(QuotaGlanceApplication\)' \
  "$ROOT_DIR/App/Compatibility/QuotaGlanceApplication.swift" \
  || fail "QuotaGlanceApplication subclass is missing"
rg -q 'APIKeyPasteShortcutBridge' \
  "$ROOT_DIR/App/Settings/AccountEditorView.swift" \
  || fail "account editor lacks ⌘V bridge for SecureField"
rg -q 'func pasteAPIKey' "$ROOT_DIR/App/Settings/AccountEditorView.swift" \
  || fail "account editor lacks explicit Paste API key action"
rg -q 'onPasteCommand' "$ROOT_DIR/App/Settings/AccountEditorView.swift" \
  || fail "API key SecureField lacks onPasteCommand"
rg -Fq '"gauge"' \
  "$ROOT_DIR/Sources/QuotaGlanceCore/Presentation/CompatibleSystemSymbolNames.swift" \
  || fail "compatible symbol fallback list is missing gauge"

SCHEMES="$(
  DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" /usr/bin/xcodebuild \
    -project "$ROOT_DIR/QuotaGlance.xcodeproj" \
    -list 2>/dev/null
)"
rg -q '^[[:space:]]+QuotaGlanceLegacy$' <<< "$SCHEMES" \
  || fail "legacy shared scheme is missing"

[[ "$(build_setting QuotaGlanceLegacy MACOSX_DEPLOYMENT_TARGET)" == "12.0" ]] \
  || fail "legacy host deployment target is not macOS 12"
[[ "$(build_setting QuotaGlance MACOSX_DEPLOYMENT_TARGET)" == "14.0" ]] \
  || fail "full host deployment target changed"
[[ "$(build_setting QuotaGlanceWidget MACOSX_DEPLOYMENT_TARGET)" == "14.0" ]] \
  || fail "Widget deployment target changed"
[[ "$(build_setting QuotaGlanceNCWidget MACOSX_DEPLOYMENT_TARGET)" == "12.0" ]] \
  || fail "NC widget deployment target is not macOS 12"
[[ "$(build_setting QuotaGlanceNCIntents MACOSX_DEPLOYMENT_TARGET)" == "12.0" ]] \
  || fail "NC intents deployment target is not macOS 12"

rg -q '^  QuotaGlanceNCWidget:$' "$ROOT_DIR/project.yml" \
  || fail "NC widget target is missing"
rg -q '^  QuotaGlanceNCIntents:$' "$ROOT_DIR/project.yml" \
  || fail "NC intents target is missing"

# XcodeGen stores host→extension links as opaque PBXTargetDependency IDs.
# Resolve those IDs to target names instead of grepping the native-target block.
host_dependency_targets() {
  local host_target="$1"
  local pbxproj="$ROOT_DIR/QuotaGlance.xcodeproj/project.pbxproj"
  local dep_ids
  local dep_id

  dep_ids="$(
    /usr/bin/awk -v host="$host_target" '
      $0 ~ "^\\t\\t[A-F0-9]+ /\\* " host " \\*/ = \\{$" { capture = 1 }
      capture && /dependencies = \(/ { in_deps = 1 }
      in_deps {
        for (i = 1; i <= NF; i++) {
          if ($(i) ~ /^[A-F0-9]+$/ && $(i + 1) == "/*" && $(i + 2) == "PBXTargetDependency") {
            print $(i)
          }
        }
      }
      in_deps && /\);/ { in_deps = 0 }
      capture && /productType =/ { exit }
    ' "$pbxproj"
  )"

  while IFS= read -r dep_id; do
    [[ -n "$dep_id" ]] || continue
    /usr/bin/awk -v id="$dep_id" '
      index($0, id " /* PBXTargetDependency */ = {") { capture = 1 }
      capture && /target = / {
        start = index($0, "/* ")
        end = index($0, " */")
        if (start > 0 && end > start) {
          print substr($0, start + 3, end - start - 3)
        }
        exit
      }
      capture && $0 == "\t\t};" { exit }
    ' "$pbxproj"
  done <<< "$dep_ids"
}

LEGACY_DEPENDENCIES="$(host_dependency_targets QuotaGlanceLegacy)"
if rg -qx 'QuotaGlanceWidget' <<< "$LEGACY_DEPENDENCIES"; then
  fail "legacy host unexpectedly depends on the desktop Widget"
fi
rg -qx 'QuotaGlanceNCWidget' <<< "$LEGACY_DEPENDENCIES" \
  || fail "legacy host does not depend on the NC widget"
rg -qx 'QuotaGlanceNCIntents' <<< "$LEGACY_DEPENDENCIES" \
  || fail "legacy host does not depend on the NC intents extension"

FULL_DEPENDENCIES="$(host_dependency_targets QuotaGlance)"
rg -qx 'QuotaGlanceNCWidget' <<< "$FULL_DEPENDENCIES" \
  || fail "full host does not depend on the NC widget"
rg -qx 'QuotaGlanceNCIntents' <<< "$FULL_DEPENDENCIES" \
  || fail "full host does not depend on the NC intents extension"
rg -qx 'QuotaGlanceWidget' <<< "$FULL_DEPENDENCIES" \
  || fail "full host does not depend on the desktop Widget"

for required_source in \
  ApplicationMenuInstaller.swift \
  CompatibleSystemSymbol.swift \
  PasteboardCommands.swift \
  QuotaGlanceApplication.swift
do
  rg -Fq "$required_source in Sources" \
    "$ROOT_DIR/QuotaGlance.xcodeproj/project.pbxproj" \
    || fail "Xcode project is missing Compatibility source: $required_source"
done

echo "Build edition contract tests passed"
