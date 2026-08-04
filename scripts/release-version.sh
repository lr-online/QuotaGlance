#!/usr/bin/env bash
set -euo pipefail

tag="${1:-}"

[[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || {
  echo "usage: $0 v<major>.<minor>.<patch>" >&2
  exit 2
}

version="${tag#v}"
IFS='.' read -r major minor patch <<< "$version"
android_version_code=$((10#$major * 1000000 + 10#$minor * 1000 + 10#$patch))

(( android_version_code >= 1 && android_version_code <= 2147483647 )) || {
  echo "Android version code is out of range: $android_version_code" >&2
  exit 2
}

printf 'tag=%s\nversion=%s\nandroid_version_code=%s\n' \
  "$tag" "$version" "$android_version_code"
