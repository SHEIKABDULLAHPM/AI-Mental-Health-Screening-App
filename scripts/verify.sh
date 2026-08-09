#!/usr/bin/env bash
# Verify all MindEase containers are healthy and probe the APIs.
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE"

docker compose ps

echo
echo "Backend health:"
curl -fsS http://localhost:8080/actuator/health || echo "backend not up yet"
echo
echo "AI service health:"
curl -fsS http://localhost:8000/health || echo "ai-service not up yet"