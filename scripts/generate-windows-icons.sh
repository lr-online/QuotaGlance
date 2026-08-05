#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
powershell -NoProfile -ExecutionPolicy Bypass -File "$REPO_ROOT/scripts/generate-windows-icons.ps1"
