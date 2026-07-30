#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CI_WORKFLOW="$ROOT_DIR/.github/workflows/ci.yml"
PACKAGE_WORKFLOW="$ROOT_DIR/.github/workflows/package.yml"
RELEASE_WORKFLOW="$ROOT_DIR/.github/workflows/release.yml"
HARMONYOS_WORKFLOW="$ROOT_DIR/.github/workflows/harmonyos.yml"
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
[[ -x "$FETCH_SCRIPT" ]] || fail "CI package fetch script is missing or not executable"
[[ -x "$HARMONYOS_BUILD_SCRIPT" ]] || fail "HarmonyOS build script is missing or not executable"

rg -q "^name: CI$" "$CI_WORKFLOW" || fail "CI workflow name changed"
rg -q "pull_request:" "$CI_WORKFLOW" || fail "CI workflow missing pull_request trigger"
rg -q "push:" "$CI_WORKFLOW" || fail "CI workflow missing push trigger"
rg -q "main" "$CI_WORKFLOW" || fail "CI workflow missing main branch trigger"
rg -Fq "maxim-lobanov/setup-xcode@v1" "$CI_WORKFLOW" || fail "CI workflow does not select Xcode explicitly"
rg -Fq "xcode-version: '16.2'" "$CI_WORKFLOW" || fail "CI workflow does not pin the supported Xcode version"
rg -Fq "brew install ripgrep" "$CI_WORKFLOW" || fail "CI workflow does not install ripgrep"
rg -Fq "swift test" "$CI_WORKFLOW" || fail "CI workflow does not run swift test"
rg -Fq "Tests/ScriptTests/BuildEditionTests.sh" "$CI_WORKFLOW" || fail "CI workflow missing build edition contract test"
rg -Fq "Tests/ScriptTests/DMGPackagingTests.sh" "$CI_WORKFLOW" || fail "CI workflow missing DMG packaging test"
rg -Fq "Tests/ScriptTests/LocalInstallSafetyTests.sh" "$CI_WORKFLOW" || fail "CI workflow missing local install safety test"

rg -q "^name: Package$" "$PACKAGE_WORKFLOW" || fail "Package workflow name changed"
rg -q "workflow_dispatch:" "$PACKAGE_WORKFLOW" || fail "Package workflow missing workflow_dispatch"
rg -q "pull_request:" "$PACKAGE_WORKFLOW" || fail "Package workflow missing pull_request trigger"
rg -Fq "maxim-lobanov/setup-xcode@v1" "$PACKAGE_WORKFLOW" || fail "Package workflow does not select Xcode explicitly"
rg -Fq "xcode-version: '16.2'" "$PACKAGE_WORKFLOW" || fail "Package workflow does not pin the supported Xcode version"
rg -Fq "./scripts/package-dmg.sh dist" "$PACKAGE_WORKFLOW" || fail "Package workflow does not package DMGs"
rg -q "upload-artifact" "$PACKAGE_WORKFLOW" || fail "Package workflow does not upload artifacts"
rg -Fq "fetch-ci-package.sh" "$FETCH_SCRIPT" || fail "fetch script self-path changed"
rg -q -- "--install" "$FETCH_SCRIPT" || fail "fetch script missing --install mode"
rg -q -- "--verify" "$FETCH_SCRIPT" || fail "fetch script missing --verify mode"

rg -q "^name: Release$" "$RELEASE_WORKFLOW" || fail "release workflow name changed"
rg -q "tags:" "$RELEASE_WORKFLOW" || fail "release workflow missing tag trigger"
rg -q "v\*" "$RELEASE_WORKFLOW" || fail "release workflow missing version tag pattern"
rg -Fq "maxim-lobanov/setup-xcode@v1" "$RELEASE_WORKFLOW" || fail "release workflow does not select Xcode explicitly"
rg -Fq "xcode-version: '16.2'" "$RELEASE_WORKFLOW" || fail "release workflow does not pin the supported Xcode version"
rg -Fq "brew install ripgrep" "$RELEASE_WORKFLOW" || fail "release workflow does not install ripgrep"
rg -Fq 'QUOTAGLANCE_VERSION: ${{ github.ref_name }}' "$RELEASE_WORKFLOW" \
  || fail "release workflow does not pass the tag version to packaging"
rg -Fq "./scripts/package-dmg.sh" "$RELEASE_WORKFLOW" || fail "release workflow does not package DMGs"
rg -q "upload-artifact" "$RELEASE_WORKFLOW" || fail "release workflow does not upload artifacts"
rg -q "softprops/action-gh-release" "$RELEASE_WORKFLOW" || fail "release workflow does not publish a GitHub release"

rg -q "^name: HarmonyOS$" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow name changed"
rg -q "workflow_dispatch:" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow missing workflow_dispatch"
rg -q "pull_request:" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow missing pull_request trigger"
rg -Fq "ErBWs/setup-ohos@v2" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow does not use ErBWs/setup-ohos@v2"
rg -Fq "version: 6.1.1.280" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow does not pin CLI tools 6.1.1.280"
rg -Fq "cache: true" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow does not enable SDK cache"
rg -Fq "libgl1-mesa-dev" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow missing Linux libGL dependency"
rg -Fq "scripts/build-harmonyos.sh" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow does not run build-harmonyos.sh"
rg -Fq "scripts/sync-contracts-to-harmonyos.sh" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow does not sync contract fixtures"
rg -q "upload-artifact" "$HARMONYOS_WORKFLOW" || fail "HarmonyOS workflow does not upload HAP artifacts"
rg -Fq "HARMONYOS_SKIP_SIGN" "$HARMONYOS_BUILD_SCRIPT" || fail "HarmonyOS build script missing unsigned CI mode"
rg -Fq "ohpm install --all" "$HARMONYOS_BUILD_SCRIPT" || fail "HarmonyOS build script does not install ohpm deps"
rg -Fq "assembleHap" "$HARMONYOS_BUILD_SCRIPT" || fail "HarmonyOS build script does not assemble HAP"

echo "GitHub Actions contract tests passed"
