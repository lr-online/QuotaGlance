#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASE="$ROOT_DIR/Platforms/HarmonyOS/entry/src/main/resources/base/element/string.json"
EN="$ROOT_DIR/Platforms/HarmonyOS/entry/src/main/resources/en_US/element/string.json"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$BASE" ]] || fail "missing $BASE"
[[ -f "$EN" ]] || fail "missing $EN"

python3 - "$BASE" "$EN" <<'PY'
import json
import sys

base = {entry["name"] for entry in json.load(open(sys.argv[1]))["string"]}
en = {entry["name"] for entry in json.load(open(sys.argv[2]))["string"]}
missing = sorted(base - en)
extra = sorted(en - base)
if missing or extra:
    if missing:
        print("missing in en_US:", ", ".join(missing), file=sys.stderr)
    if extra:
        print("extra in en_US:", ", ".join(extra), file=sys.stderr)
    sys.exit(1)
print(f"OK: {len(base)} string keys match between base and en_US")
PY
