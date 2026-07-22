#!/usr/bin/env bash
set -euo pipefail

: "${LAOGE_KEY:?Set LAOGE_KEY before running this check}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLED_APP="$HOME/Applications/QuotaGlance.app"
TEMP_DIR="$(mktemp -d)"
SECRET_PATTERN_FILE="$TEMP_DIR/api-key.pattern"
GIT="/Library/Developer/CommandLineTools/usr/bin/git"

cleanup() {
  rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT

chmod 700 "$TEMP_DIR"
umask 077
printf '%s' "$LAOGE_KEY" > "$SECRET_PATTERN_FILE"
chmod 600 "$SECRET_PATTERN_FILE"

if [[ ! -d "$INSTALLED_APP" ]]; then
  echo "Installed app not found: $INSTALLED_APP" >&2
  exit 1
fi
if [[ ! -x "$GIT" ]]; then
  echo "Command Line Tools Git is missing: $GIT" >&2
  exit 1
fi

cd "$ROOT_DIR"
if DEVELOPER_DIR=/Library/Developer/CommandLineTools \
  "$GIT" grep -q -F -f "$SECRET_PATTERN_FILE" -- .
then
  echo "Secret bytes found in tracked files" >&2
  exit 1
fi

if rg -a -q -F -f "$SECRET_PATTERN_FILE" "$INSTALLED_APP"; then
  echo "Secret bytes found in installed app" >&2
  exit 1
fi

echo "No configured API key bytes found"
