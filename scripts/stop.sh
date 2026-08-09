#!/usr/bin/env bash
# Stop the MindEase stack. Add -v to also remove volumes (destroys data).
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE"

docker compose down "$@"