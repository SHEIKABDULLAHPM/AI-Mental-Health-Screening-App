#!/usr/bin/env bash
# Start MindEase stack (development) from the repo root.
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE"

# Create .env from template if missing so `docker compose` has vars.
if [[ ! -f "$BASE/.env" ]]; then
  cp "$BASE/.env.example" "$BASE/.env"
  echo "Created $BASE/.env from template. Edit the secret values first."
fi

docker compose up -d --build "$@"
echo
echo "Starting. Run ./scripts/verify.sh to confirm health."