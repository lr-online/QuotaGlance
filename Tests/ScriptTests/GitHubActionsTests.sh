#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CI_WORKFLOW="$ROOT_DIR/.github/workflows/ci.yml"
PACKAGE_WORKFLOW="$ROOT_DIR/.github/workflows/package.yml"
RELEASE_WORKFLOW="$ROOT_DIR/.github/workflows/release.yml"
HARMONYOS_WORKFLOW="$ROOT_DIR/.github/workflows/harmonyos.yml"
ANDROID_WORKFLOW="$ROOT_DIR/.github/workflows/android.yml"
QUALITY_WORKFLOW="$ROOT_DIR/.github/workflows/quality.yml"
WINDOWS_WORKFLOW="$ROOT_DIR/.github/workflows/windows.yml"
FETCH_SCRIPT="$ROOT_DIR/scripts/fetch-ci-package.sh"
HARMONYOS_BUILD_SCRIPT="$ROOT_DIR/scripts/build-harmonyos.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$CI_WORKFLOW" ]] || fail "missing CI workflow"
[[ -f "$PACKAGE_WORKFLOW" ]] || fail "missing Package workflow"
[[ -f "$RELEASE_WORKFLOW" ]] || fail "missing release workflow"
[[ -f "$HARMONYOS_WORKFLOW" ]] || fail "missing HarmonyOS workflow"
[[ -f "$ANDROID_WORKFLOW" ]] || fail "missing Android workflow"
[[ -f "$QUALITY_WORKFLOW" ]] || fail "missing Quality workflow"
[[ -f "$WINDOWS_WORKFLOW" ]] || fail "missing Windows workflow"
[[ -x "$FETCH_SCRIPT" ]] || fail "CI package fetch script is missing or not executable"
[[ -x "$HARMONYOS_BUILD_SCRIPT" ]] || fail "HarmonyOS build script is missing or not executable"

assert_pinned_action() {
  local action="$1"
  local workflow="$2"
  rg -q "${action}@[0-9a-f]{40}" "$workflow" \
    || fail "$workflow does not pin $action to a commit SHA"
}

assert_read_only_workflow() {
  local workflow="$1"
  rg -q '^permissions:$' "$workflow" \
    || fail "$workflow does not declare permissions"
  rg -q '^  contents: read$' "$workflow" \
    || fail "$workflow does not restrict contents permission to read"
  rg -Fq 'persist-credentials: false' "$workflow" \
    || fail "$workflow does not disable checkout credential persistence"
  rg -q '^concurrency:$' "$workflow" \
    || fail "$workflow does not declare concurrency"
}

rg -q "^name: CI$" "$CI_WORKFLOW" || fail "CI workflow name changed"
rg -q "pull_request:" "$CI_WORKFLOW" || fail "CI workflow missing pull_request trigger"
rg -q "push:" "$CI_WORKFLOW" || fail "CI workflow missing push trigger"
rg -q "main" "$CI_WORKFLOW" || fail "CI workflow missing main branch trigger"
assert_pinned_action "actions/checkout" "$CI_WORKFLOW"
assert_pinned_action "maxim-lobanov/setup-xcode" "$CI_WORKFLOW"
assert_read_only_workflow "$CI_WORKFLOW"
rg -Fq "xcode-version: '16.2'" "$CI_WORKFLOW" || fail "CI workflow does not pin the supported Xcode version"
rg -Fq "command -v rg" "$CI_WORKFLOW" || fail "CI workflow does not ensure ripgrep availability"
rg -Fq "brew install ripgrep" "$CI_WORKFLOW" || fail "CI workflow lacks the ripgrep install fallback"
rg -Fq "swift test" "$CI_WORKFLOW" || fail "CI workflow does not run swift test"
rg -Fq "scripts/verify-provider-parity.sh" "$CI_WORKFLOW" || fail "CI workflow does not run the provider parity check"
rg -Fq "Tests/ScriptTests/RepositoryTopologyTests.sh" "$CI_WORKFLOW" \
  || fail "CI workflow missing repository topology test"
rg -Fq "scripts/sync-specs-to-windows.sh" "$CI_WORKFLOW" || fail "CI workflow does not sync Windows provider specs before global parity"
rg -Fq "scripts/sync-contracts-to-windows.sh" "$CI_WORKFLOW" || fail "CI workflow does not sync Windows contracts before global parity"
rg -Fq "Tests/ScriptTests/ProviderParityTests.sh" "$CI_WORKFLOW" || fail "CI workflow missing provider parity tests"
rg -Fq "Tests/ScriptTests/HarmonyOSStringParityTests.sh" "$CI_WORKFLOW" \
  || fail "CI workflow missing HarmonyOS string parity test"
rg -Fq "Tests/ScriptTests/BuildEditionTests.sh" "$CI_WORKFLOW" || fail "CI workflow missing build edition contract test"
rg -Fq "Tests/ScriptTests/DMGPackagingTests.sh" "$CI_WORKFLOW" || fail "CI workflow missing DMG packaging test"
rg -Fq "Tests/ScriptTests/ReleaseVersionTests.sh" "$CI_WORKFLOW" || fail "CI workflow missing release version test"
rg -Fq "Tests/ScriptTests/LocalInstallSafetyTests.sh" "$CI_WORKFLOW" || fail "CI workflow missing local install safety test"

rg -q "^name: Package macOS$" "$PACKAGE_WORKFLOW" || fail "macOS packaging workflow name is wrong"
rg -q "workflow_dispatch:" "$PACKAGE_WORKFLOW" || fail "Package workflow missing workflow_dispatch"
rg -q "pull_request:" "$PACKAGE_WORKFLOW" || fail "Package workflow missing pull_request trigger"
assert_pinned_action "actions/checkout" "$PACKAGE_WORKFLOW"
assert_pinned_action "maxim-lobanov/setup-xcode" "$PACKAGE_WORKFLOW"
assert_pinned_action "actions/upload-artifact" "$PACKAGE_WORKFLOW"
assert_read_only_workflow "$PACKAGE_WORKFLOW"
rg -Fq "xcode-version: '16.2'" "$PACKAGE_WORKFLOW" || fail "Package workflow does not pin the supported Xcode version"
rg -Fq "./scripts/package-dmg.sh dist" "$PACKAGE_WORKFLOW" || fail "Package workflow does not package DMGs"
rg -q "upload-artifact" "$PACKAGE_WORKFLOW" || fail "Package workflow does not upload artifacts"
rg -Fq 'QuotaGlance-macOS-${{ steps.metadata.outputs.version }}' "$PACKAGE_WORKFLOW" \
  || fail "macOS package artifact is not versioned"
rg -Fq "fetch-ci-package.sh" "$FETCH_SCRIPT" || fail "fetch script self-path changed"
rg -Fq -- '--workflow="Package macOS"' "$FETCH_SCRIPT" || fail "fetch script uses old workflow name"
rg -q -- "--install" "$FETCH_SCRIPT" || fail "fetch script missing --install mode"
rg -q -- "--verify" "$FETCH_SCRIPT" || fail "fetch script missing --verify mode"

rg -q "^name: Release$" "$RELEASE_WORKFLOW" || fail "release workflow name changed"
rg -q "workflow_dispatch:" "$RELEASE_WORKFLOW" || fail "release workflow missing manual trigger"
rg -Fq "description: Existing release tag in vX.Y.Z form" "$RELEASE_WORKFLOW" \
  || fail "release workflow missing tag input"
rg -Fq "ref: \${{ inputs.tag }}" "$RELEASE_WORKFLOW" || fail "release workflow does not check out selected tag"
! rg -q "push:" "$RELEASE_WORKFLOW" || fail "release workflow must not run automatically on pushes"
! rg -q "tags:" "$RELEASE_WORKFLOW" || fail "release workflow must not use a tag trigger"
assert_pinned_action "actions/checkout" "$RELEASE_WORKFLOW"
assert_pinned_action "maxim-lobanov/setup-xcode" "$RELEASE_WORKFLOW"
assert_pinned_action "actions/setup-node" "$RELEASE_WORKFLOW"
assert_pinned_action "actions/upload-artifact" "$RELEASE_WORKFLOW"
assert_pinned_action "actions/download-artifact" "$RELEASE_WORKFLOW"
assert_pinned_action "softprops/action-gh-release" "$RELEASE_WORKFLOW"
rg -Fq 'persist-credentials: false' "$RELEASE_WORKFLOW" \
  || fail "release workflow does not disable checkout credential persistence"
rg -q '^concurrency:$' "$RELEASE_WORKFLOW" \
  || fail "release workflow does not declare concurrency"
rg -Fq "xcode-version: '16.2'" "$RELEASE_WORKFLOW" || fail "release workflow does not pin the supported Xcode version"
rg -Fq "command -v rg" "$RELEASE_WORKFLOW" || fail "release workflow does not ensure ripgrep availability"
rg -Fq "brew install ripgrep" "$RELEASE_WORKFLOW" || fail "release workflow lacks the ripgrep install fallback"
rg -Fq "scripts/release-version.sh" "$RELEASE_WORKFLOW" \
  || fail "release workflow does not validate the selected tag"
rg -Fq "scripts/sync-specs-to-windows.sh" "$RELEASE_WORKFLOW" \
  || fail "release workflow does not sync Windows provider specs before global parity"
rg -Fq "scripts/sync-contracts-to-windows.sh" "$RELEASE_WORKFLOW" \
  || fail "release workflow does not sync Windows contracts before global parity"
rg -Fq "name: Sync parity inputs" "$RELEASE_WORKFLOW" \
  || fail "release Android job does not prepare all parity inputs"
rg -Fq 'QUOTAGLANCE_VERSION: ${{ needs.prepare.outputs.tag }}' "$RELEASE_WORKFLOW" \
  || fail "release workflow does not pass the selected tag to macOS packaging"
rg -Fq "quotaglanceVersionCode" "$RELEASE_WORKFLOW" \
  || fail "release workflow does not set Android version code"
rg -Fq "./scripts/package-dmg.sh" "$RELEASE_WORKFLOW" || fail "release workflow does not package DMGs"
rg -Fq "runs-on: windows-latest" "$RELEASE_WORKFLOW" \
  || fail "release workflow does not build Windows assets"
rg -Fq "npm exec -- tauri build --target \$target --bundles nsis,msi" "$RELEASE_WORKFLOW" \
  || fail "release workflow does not build NSIS and MSI Windows installers"
rg -Fq "Compress-Archive" "$RELEASE_WORKFLOW" \
  || fail "release workflow does not package the Windows portable ZIP"
rg -Fq "Get-FileHash" "$RELEASE_WORKFLOW" \
  || fail "release workflow does not generate Windows SHA-256 files"
rg -Fq 'QuotaGlance-Windows-${{ needs.prepare.outputs.version }}' "$RELEASE_WORKFLOW" \
  || fail "release workflow does not version Windows artifacts"
rg -Fq "release-assets/windows/*-windows-x64-*.zip" "$RELEASE_WORKFLOW" \
  || fail "release workflow does not publish the Windows portable ZIP"
rg -Fq "release-assets/windows/*-windows-x64-*.exe" "$RELEASE_WORKFLOW" \
  || fail "release workflow does not publish the Windows NSIS installer"
rg -Fq "release-assets/windows/*-windows-x64-*.msi" "$RELEASE_WORKFLOW" \
  || fail "release workflow does not publish the Windows MSI installers"
rg -q "upload-artifact" "$RELEASE_WORKFLOW" || fail "release workflow does not upload artifacts"
rg -q "softprops/action-gh-release" "$RELEASE_WORKFLOW" || fail "release workflow does not publish a GitHub release"
rg -Fq "git log --no-merges" "$RELEASE_WORKFLOW" || fail "release workflow does not derive notes from commits"
rg -Fq "body_path: release-notes.md" "$RELEASE_WORKFLOW" || fail "release workflow does not use generated release notes"
! rg -q "generate_release_notes" "$RELEASE_WORKFLOW" || fail "release workflow must not use generated GitHub notes"
! rg -q "HarmonyOS" "$RELEASE_WORKFLOW" || fail "release workflow must not publish unsigned HarmonyOS HAPs"

rg -q "^name: HarmonyOS$" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow name changed"
rg -q "workflow_dispatch:" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow missing workflow_dispatch"
rg -q "pull_request:" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow missing pull_request trigger"
rg -Fq '"Contracts/**"' "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow does not trigger on all shared contracts"
assert_pinned_action "actions/checkout" "$HARMONYOS_WORKFLOW"
assert_pinned_action "ErBWs/setup-ohos" "$HARMONYOS_WORKFLOW"
assert_pinned_action "actions/upload-artifact" "$HARMONYOS_WORKFLOW"
rg -Fq 'persist-credentials: false' "$HARMONYOS_WORKFLOW" \
  || fail "HarmonyOS workflow does not disable checkout credential persistence"
rg -q '^concurrency:$' "$HARMONYOS_WORKFLOW" \
  || fail "HarmonyOS workflow does not declare concurrency"
rg -Fq "version: 6.1.1.280" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow does not pin CLI tools 6.1.1.280"
rg -Fq "cache: true" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow does not enable SDK cache"
rg -Fq "libgl1-mesa-dev" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow missing Linux libGL dependency"
rg -Fq "scripts/build-harmonyos.sh" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow does not run build-harmonyos.sh"
rg -Fq "scripts/sync-contracts-to-harmonyos.sh" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow does not sync contract fixtures"
rg -Fq "scripts/sync-specs-to-harmonyos.sh" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow does not sync provider specs"
rg -Fq "scripts/sync-specs-to-windows.sh" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow does not sync Windows provider specs before global parity"
rg -Fq "scripts/sync-contracts-to-windows.sh" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow does not sync Windows contracts before global parity"
rg -Fq "scripts/verify-provider-parity.sh" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow does not verify provider parity"
rg -q "upload-artifact" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow does not upload HAP artifacts"
rg -Fq 'QuotaGlance-HarmonyOS-${{ steps.metadata.outputs.version }}' "$HARMONYOS_WORKFLOW" \
  || fail "HarmonyOS artifact is not versioned"
rg -Fq "HARMONYOS_SKIP_SIGN" "$HARMONYOS_BUILD_SCRIPT" || fail "HarmonyOS build script missing unsigned CI mode"
rg -Fq "properties.ignoreSignHap=true" "$HARMONYOS_BUILD_SCRIPT" || fail "HarmonyOS build script missing ignoreSignHap"
rg -Fq "ohpm install --all" "$HARMONYOS_BUILD_SCRIPT" || fail "HarmonyOS build script does not install ohpm deps"
rg -Fq "assembleHap" "$HARMONYOS_BUILD_SCRIPT" || fail "HarmonyOS build script does not assemble HAP"
rg -Fq 'Huawei Pad Mini' "$HARMONYOS_BUILD_SCRIPT" || fail "HarmonyOS build script missing tablet/Pad Mini deviceTypes check"
HARMONYOS_BUILD_PROFILE_TEMPLATE="$ROOT_DIR/Platforms/HarmonyOS/build-profile.template.json5"
HARMONYOS_GITIGNORE="$ROOT_DIR/Platforms/HarmonyOS/.gitignore"
[[ -f "$HARMONYOS_BUILD_PROFILE_TEMPLATE" ]] || fail "missing HarmonyOS build profile template"
rg -Fq '"signingConfigs": []' "$HARMONYOS_BUILD_PROFILE_TEMPLATE" \
  || fail "HarmonyOS build profile template must not contain signing material"
grep -Fxq '/build-profile.json5' "$HARMONYOS_GITIGNORE" \
  || fail "machine-local HarmonyOS build profile is not ignored"
rg -Fq 'build-profile.template.json5' "$HARMONYOS_BUILD_SCRIPT" \
  || fail "HarmonyOS build script does not initialize the local build profile"
HARMONYOS_MODULE_JSON5="$ROOT_DIR/Platforms/HarmonyOS/entry/src/main/module.json5"
[[ -f "$HARMONYOS_MODULE_JSON5" ]] || fail "missing HarmonyOS entry module.json5"
rg -Fq '"tablet"' "$HARMONYOS_MODULE_JSON5" || fail "HarmonyOS entry module missing tablet deviceType"
rg -Fq '"phone"' "$HARMONYOS_MODULE_JSON5" || fail "HarmonyOS entry module missing phone deviceType"

rg -q '^name: Quality$' "$QUALITY_WORKFLOW" || fail "Quality workflow name changed"
rg -q 'pull_request:' "$QUALITY_WORKFLOW" || fail "Quality workflow missing pull_request trigger"
rg -q 'push:' "$QUALITY_WORKFLOW" || fail "Quality workflow missing push trigger"
rg -q 'merge_group:' "$QUALITY_WORKFLOW" || fail "Quality workflow missing merge_group trigger"
rg -q 'workflow_dispatch:' "$QUALITY_WORKFLOW" || fail "Quality workflow missing workflow_dispatch"
rg -q '^permissions:$' "$QUALITY_WORKFLOW" || fail "Quality workflow missing permissions"
rg -q '^  contents: read$' "$QUALITY_WORKFLOW" || fail "Quality workflow is not read-only"
rg -q '^concurrency:$' "$QUALITY_WORKFLOW" || fail "Quality workflow missing concurrency"
assert_pinned_action "actions/checkout" "$QUALITY_WORKFLOW"
rg -Fq 'actionlint' "$QUALITY_WORKFLOW" || fail "Quality workflow missing actionlint"
rg -Fq 'zizmor' "$QUALITY_WORKFLOW" || fail "Quality workflow missing zizmor"
rg -Fq 'shellcheck --shell=bash --severity=warning' "$QUALITY_WORKFLOW" \
  || fail "Quality workflow missing warning-level ShellCheck"
rg -Fq 'gitleaks git' "$QUALITY_WORKFLOW" || fail "Quality workflow missing Git history secret scan"
rg -Fq 'gitleaks dir' "$QUALITY_WORKFLOW" || fail "Quality workflow missing working-tree secret scan"
rg -Fq 'github.com/zricethezav/gitleaks/v8@v8.28.0' "$QUALITY_WORKFLOW" \
  || fail "Quality workflow uses the wrong gitleaks module path"
rg -Fq 'scripts/verify-provider-parity.sh' "$QUALITY_WORKFLOW" \
  || fail "Quality workflow missing provider protocol parity check"
rg -Fq 'scripts/sync-specs-to-windows.sh' "$QUALITY_WORKFLOW" \
  || fail "Quality workflow does not sync Windows provider specs before global parity"
rg -Fq 'scripts/sync-contracts-to-windows.sh' "$QUALITY_WORKFLOW" \
  || fail "Quality workflow does not sync Windows contracts before global parity"

rg -q '^name: Android$' "$ANDROID_WORKFLOW" || fail "Android workflow name changed"
rg -q 'workflow_dispatch:' "$ANDROID_WORKFLOW" || fail "Android workflow missing workflow_dispatch"
rg -q 'pull_request:' "$ANDROID_WORKFLOW" || fail "Android workflow missing pull_request trigger"
assert_pinned_action "actions/checkout" "$ANDROID_WORKFLOW"
assert_pinned_action "actions/setup-java" "$ANDROID_WORKFLOW"
assert_pinned_action "android-actions/setup-android" "$ANDROID_WORKFLOW"
assert_pinned_action "actions/upload-artifact" "$ANDROID_WORKFLOW"
! rg -q 'tags:' "$ANDROID_WORKFLOW" || fail "Android workflow must not trigger from tags"
! rg -q 'softprops/action-gh-release' "$ANDROID_WORKFLOW" || fail "Android workflow must not publish releases"
rg -Fq 'persist-credentials: false' "$ANDROID_WORKFLOW" \
  || fail "Android workflow does not disable checkout credential persistence"
rg -q '^concurrency:$' "$ANDROID_WORKFLOW" \
  || fail "Android workflow does not declare concurrency"
rg -Fq 'java-version: "17"' "$ANDROID_WORKFLOW" \
  || fail "Android workflow does not use JDK 17"
rg -Fq 'sdkmanager "platforms;android-36" "build-tools;36.0.0"' "$ANDROID_WORKFLOW" \
  || fail "Android workflow does not install the required SDK inputs"
rg -Fq 'scripts/sync-specs-to-android.sh' "$ANDROID_WORKFLOW" \
  || fail "Android workflow does not sync provider specs"
rg -Fq 'scripts/sync-contracts-to-android.sh' "$ANDROID_WORKFLOW" \
  || fail "Android workflow does not sync contract fixtures"
rg -Fq 'scripts/sync-specs-to-windows.sh' "$ANDROID_WORKFLOW" \
  || fail "Android workflow does not sync Windows provider specs before global parity"
rg -Fq 'scripts/sync-contracts-to-windows.sh' "$ANDROID_WORKFLOW" \
  || fail "Android workflow does not sync Windows contracts before global parity"
rg -Fq 'scripts/verify-android-parity.sh' "$ANDROID_WORKFLOW" \
  || fail "Android workflow does not verify Android parity"
rg -Fq ':app:testDebugUnitTest :app:lint :app:assembleDebug :app:assembleRelease' "$ANDROID_WORKFLOW" \
  || fail "Android workflow does not test, lint, and build both APK variants"
rg -Fq 'QuotaGlance-Android-${{ steps.metadata.outputs.version }}' "$ANDROID_WORKFLOW" \
  || fail "Android artifact is not versioned"

rg -q '^name: Windows Tauri client$' "$WINDOWS_WORKFLOW" || fail "Windows workflow name changed"
rg -q 'pull_request:' "$WINDOWS_WORKFLOW" || fail "Windows workflow missing pull_request trigger"
assert_pinned_action "actions/checkout" "$WINDOWS_WORKFLOW"
assert_pinned_action "actions/setup-node" "$WINDOWS_WORKFLOW"
assert_read_only_workflow "$WINDOWS_WORKFLOW"
rg -Fq 'cache-dependency-path: Windows/package-lock.json' "$WINDOWS_WORKFLOW" \
  || fail "Windows workflow does not cache the locked npm dependencies"
rg -Fq 'run: npm ci' "$WINDOWS_WORKFLOW" \
  || fail "Windows workflow does not use the checked-in npm lockfile"
rg -Fq 'scripts/sync-specs-to-windows.sh' "$WINDOWS_WORKFLOW" \
  || fail "Windows workflow does not sync provider specs"
rg -Fq 'scripts/sync-contracts-to-windows.sh' "$WINDOWS_WORKFLOW" \
  || fail "Windows workflow does not sync contract fixtures"
rg -Fq 'scripts/generate-windows-icons.ps1' "$WINDOWS_WORKFLOW" \
  || fail "Windows workflow does not generate ignored Tauri icon assets"
rg -Fq 'tray-icon.png' "$ROOT_DIR/scripts/generate-windows-icons.ps1" \
  || fail "Windows icon generator does not produce the compile-time tray icon"
rg -Fq 'npm exec -- tauri build' "$WINDOWS_WORKFLOW" \
  || fail "Windows workflow does not use the Tauri CLI installed by npm ci"
rg -Fq 'npm exec -- tauri build --target $target --bundles nsis,msi' "$WINDOWS_WORKFLOW" \
  || fail "Windows workflow does not build both NSIS and MSI installers"

[[ -f "$ROOT_DIR/.github/dependabot.yml" ]] \
  || fail "missing Dependabot configuration"
rg -q 'package-ecosystem: github-actions' "$ROOT_DIR/.github/dependabot.yml" \
  || fail "Dependabot is not configured for GitHub Actions"

echo "GitHub Actions contract tests passed"
