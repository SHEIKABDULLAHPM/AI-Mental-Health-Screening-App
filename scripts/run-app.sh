#!/usr/bin/env bash
# Run the Flutter app on an Android device connected over wireless debugging.
#
# The app reads its backend URL from AppConfig.apiBaseUrl, which defaults to
# the emulator-only alias 10.0.2.2. On a physical phone that address is
# unroutable, so every request fails with "Unable to reach the server". This
# script points the app at the host's real LAN address instead.
#
# Wireless debugging rotates the device's connect port on every re-pair, so the
# port is re-discovered via mDNS on each run.
#
# Usage:
#   ./scripts/run-app.sh                 # build + run on the wireless device
#   ./scripts/run-app.sh --release       # extra flags are forwarded to flutter
#   ANDROID_SERIAL=host:port ./scripts/run-app.sh
#   HOST_IP=10.0.0.5 ./scripts/run-app.sh
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$BASE/app"
cd "$APP"

BACKEND_PORT="${BACKEND_PORT:-8080}"

# Address of this machine on the network the phone shares with us.
if [[ -z "${HOST_IP:-}" ]]; then
  HOST_IP="$(ip -4 route get 1.1.1.1 2>/dev/null |
    awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}')"
fi
if [[ -z "$HOST_IP" ]]; then
  echo "Could not determine this host's LAN address. Set HOST_IP=<ip> and retry." >&2
  exit 1
fi

# Resolve the adb serial to talk to.
DEVICE="${ANDROID_SERIAL:-}"
if [[ -z "$DEVICE" ]]; then
  DEVICE="$(adb devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')"
fi

if [[ -z "$DEVICE" ]]; then
  # Wireless debugging hands out a new connect port each time it is enabled.
  MDNS="$(adb mdns services 2>/dev/null |
    awk '$2 == "_adb-tls-connect._tcp" { print $3; exit }')"
  if [[ -n "$MDNS" ]]; then
    echo "Connecting to $MDNS over wireless debugging..."
    adb connect "$MDNS" >/dev/null 2>&1 || true
    sleep 1
    DEVICE="$(adb devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')"
  fi
fi

if [[ -z "$DEVICE" ]]; then
  cat >&2 <<'EOF'
No Android device found.

On the phone: Settings -> About phone -> tap "Build number" 7 times, then
Settings -> Developer options -> Wireless debugging -> Pair device with pairing
code. Pair once with:

    adb pair <phone-ip>:<pair-port> <pair-code>
EOF
  exit 1
fi

# Never target an iOS/desktop entry: this script only injects Android host rules.
case "$DEVICE" in
  *:*) ;;
  *) echo "Resolved device '$DEVICE' has no host:port; expected a wireless serial." >&2; exit 1 ;;
esac

API_BASE_URL="http://${HOST_IP}:${BACKEND_PORT}/api/v1"

echo "Device:      $DEVICE"
echo "API base:    $API_BASE_URL"
echo

# Make sure the backend is actually reachable before spending time on a build.
if ! curl -fsS --max-time 5 "http://127.0.0.1:${BACKEND_PORT}/actuator/health" >/dev/null; then
  echo "WARNING: backend is not answering on 127.0.0.1:${BACKEND_PORT}." >&2
  echo "         Start it with ./scripts/start.sh, or set BACKEND_PORT." >&2
fi

flutter pub get
exec flutter run \
  -d "$DEVICE" \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=AI_SERVICE_URL="http://${HOST_IP}:${AI_SERVICE_PORT:-8000}/api/v1" \
  --dart-define=AUTH_SERVER_URL="http://${HOST_IP}:${KEYCLOAK_PORT:-8083}" \
  --dart-define=ENVIRONMENT=development \
  "$@"