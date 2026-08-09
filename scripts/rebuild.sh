#!/usr/bin/env bash
# Rebuild and restart the MindEase stack after code changes.
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE"

docker compose up -d --build "$@"