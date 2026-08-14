#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/release-version.sh"
GRADLE_FILE="$ROOT_DIR/Platforms/Android/app/build.gradle.kts"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ "$("$SCRIPT" v1.2.3)" == $'tag=v1.2.3\nversion=1.2.3\nandroid_version_code=1002003' ]] \
  || fail "v1.2.3 was not normalized"
[[ "$("$SCRIPT" v0.1.7)" == $'tag=v0.1.7\nversion=0.1.7\nandroid_version_code=1007' ]] \
  || fail "v0.1.7 was not normalized"

for invalid in 1.2.3 v1.2 v01.2.3 v1.02.3 v1.2.03 v1.2.3-beta v2148.0.0; do
  if "$SCRIPT" "$invalid" >/dev/null 2>&1; then
    fail "accepted invalid release tag: $invalid"
  fi
done

rg -Fq 'providers.gradleProperty("quotaglanceVersion")' "$GRADLE_FILE" \
  || fail "Android build does not accept a release version override"
rg -Fq 'providers.gradleProperty("quotaglanceVersionCode")' "$GRADLE_FILE" \
  || fail "Android build does not accept a release version-code override"

echo "Release version tests passed"
