#!/usr/bin/env bash
# =============================================================================
# dev-mobile.sh — flutter run (frontend_main) targeting a physical phone.
# =============================================================================
# Auto-discovers this machine's LAN IPv4 and launches `flutter run` with
# --dart-define so the embedded livestream module (lib/livestream) uses the
# right BACKEND_URL (the Go livestream backend on :3000). The main app's own
# backend is read from the bundled .env asset, so it isn't overridden here.
#
# Usage:
#   ./scripts/dev-mobile.sh            # default port 3000
#   PORT=3000 ./scripts/dev-mobile.sh  # explicit
#   DEVICE=<id> ./scripts/dev-mobile.sh
# =============================================================================
set -euo pipefail

PORT="${PORT:-3000}"
DEVICE="${DEVICE:-}"

# Pick the first private, non-loopback IPv4. Prefer Wi-Fi/en0 on macOS.
detect_lan_ip() {
  if command -v ipconfig >/dev/null 2>&1; then            # macOS
    ipconfig getifaddr en0 2>/dev/null && return 0
    ipconfig getifaddr en1 2>/dev/null && return 0
  fi
  # Linux / fallback
  ip -4 addr show 2>/dev/null \
    | awk '/inet / && $2 !~ /^127\./ && $2 !~ /^169\.254\./ {print $2}' \
    | cut -d/ -f1 | grep -vE '^172\.' | head -n1
}

LAN_IP="$(detect_lan_ip || true)"
if [ -z "${LAN_IP}" ]; then
  echo "No usable LAN IPv4 address found. Are you connected to Wi-Fi?" >&2
  exit 1
fi

BACKEND_URL="http://${LAN_IP}:${PORT}"
echo ""
echo "  LAN IP    : ${LAN_IP}"
echo "  Backend   : ${BACKEND_URL}  (livestream module)"
echo "  Test from phone browser: ${BACKEND_URL}/health"
echo ""

if command -v curl >/dev/null 2>&1; then
  if curl -fsS --max-time 3 "${BACKEND_URL}/health" >/dev/null 2>&1; then
    echo "[health] reachable"
  else
    echo "[health] WARNING: cannot reach ${BACKEND_URL}/health — is the Go livestream backend (cd backend; make dev-api) running?" >&2
  fi
fi

ARGS=(run --dart-define "BACKEND_URL=${BACKEND_URL}")
[ -n "${DEVICE}" ] && ARGS+=(-d "${DEVICE}")

echo ""
echo "> flutter ${ARGS[*]}"
exec flutter "${ARGS[@]}"
