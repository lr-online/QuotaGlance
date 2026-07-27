#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CI_WORKFLOW="$ROOT_DIR/.github/workflows/ci.yml"
RELEASE_WORKFLOW="$ROOT_DIR/.github/workflows/release.yml"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$CI_WORKFLOW" ]] || fail "missing CI workflow"
[[ -f "$RELEASE_WORKFLOW" ]] || fail "missing release workflow"

rg -q "^name: CI$" "$CI_WORKFLOW" || fail "CI workflow name changed"
rg -q "pull_request:" "$CI_WORKFLOW" || fail "CI workflow missing pull_request trigger"
rg -q "push:" "$CI_WORKFLOW" || fail "CI workflow missing push trigger"
rg -q "main" "$CI_WORKFLOW" || fail "CI workflow missing main branch trigger"
rg -Fq "maxim-lobanov/setup-xcode@v1" "$CI_WORKFLOW" || fail "CI workflow does not select Xcode explicitly"
rg -Fq "xcode-version: '16.2'" "$CI_WORKFLOW" || fail "CI workflow does not pin the supported Xcode version"
rg -Fq "swift test" "$CI_WORKFLOW" || fail "CI workflow does not run swift test"
rg -Fq "Tests/ScriptTests/BuildEditionTests.sh" "$CI_WORKFLOW" || fail "CI workflow missing build edition contract test"
rg -Fq "Tests/ScriptTests/DMGPackagingTests.sh" "$CI_WORKFLOW" || fail "CI workflow missing DMG packaging test"
rg -Fq "Tests/ScriptTests/LocalInstallSafetyTests.sh" "$CI_WORKFLOW" || fail "CI workflow missing local install safety test"

rg -q "^name: Release$" "$RELEASE_WORKFLOW" || fail "release workflow name changed"
rg -q "tags:" "$RELEASE_WORKFLOW" || fail "release workflow missing tag trigger"
rg -q "v\*" "$RELEASE_WORKFLOW" || fail "release workflow missing version tag pattern"
rg -Fq "maxim-lobanov/setup-xcode@v1" "$RELEASE_WORKFLOW" || fail "release workflow does not select Xcode explicitly"
rg -Fq "xcode-version: '16.2'" "$RELEASE_WORKFLOW" || fail "release workflow does not pin the supported Xcode version"
rg -Fq "./scripts/package-dmg.sh" "$RELEASE_WORKFLOW" || fail "release workflow does not package DMGs"
rg -q "upload-artifact" "$RELEASE_WORKFLOW" || fail "release workflow does not upload artifacts"
rg -q "softprops/action-gh-release" "$RELEASE_WORKFLOW" || fail "release workflow does not publish a GitHub release"

echo "GitHub Actions contract tests passed"
