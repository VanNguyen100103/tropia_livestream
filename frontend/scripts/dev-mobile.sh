#!/usr/bin/env bash
# =============================================================================
# dev-mobile.sh — flutter run targeting a physical phone on the same Wi-Fi.
# =============================================================================
# Auto-discovers this machine's LAN IPv4 and launches `flutter run` with
# --dart-define so the Flutter app uses the right BACKEND_URL.
#
# Usage:
#   ./scripts/dev-mobile.sh                  # default port 3000
#   PORT=3001 ./scripts/dev-mobile.sh
#   ./scripts/dev-mobile.sh -d <device-id>   # pin to a specific device
#
# macOS/Linux only. On Windows use dev-mobile.ps1.
# =============================================================================
set -euo pipefail

PORT="${PORT:-3000}"

lan_ip() {
  if command -v ip >/dev/null 2>&1; then
    # Linux: pick the source address used for the default route.
    ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") print $(i+1)}' | head -1
  elif command -v ipconfig >/dev/null 2>&1; then
    # macOS
    ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null
  else
    # POSIX fallback: parse `ifconfig` for 192.168/10. addresses.
    ifconfig 2>/dev/null \
      | awk '/inet (192\.168|10\.|172\.(1[6-9]|2[0-9]|3[01]))/ {print $2; exit}'
  fi
}

IP="$(lan_ip || true)"
if [ -z "${IP}" ]; then
  echo "ERROR: could not detect LAN IPv4. Are you on Wi-Fi?" >&2
  exit 1
fi

BACKEND_URL="http://${IP}:${PORT}"

echo
echo "  LAN IP    : ${IP}"
echo "  Backend   : ${BACKEND_URL}"
echo "  Test from phone browser: ${BACKEND_URL}/health"
echo

# Quick reachability check from this host.
if command -v curl >/dev/null 2>&1; then
  if out="$(curl -sS --max-time 3 "${BACKEND_URL}/health" 2>&1)"; then
    echo "[health] ${out}"
  else
    echo "WARN: cannot reach ${BACKEND_URL}/health — is \`go run ./cmd/api\` running?" >&2
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../env.development.json"

# Load env.development.json first so placeholder / Sentry / etc. vars get
# applied, then override BACKEND_URL with the LAN IP detected above.
# Later --dart-define flags override earlier --dart-define-from-file keys,
# so this ordering wins.
DEFINE_FILE_ARG=()
if [ -f "${ENV_FILE}" ]; then
  DEFINE_FILE_ARG=(--dart-define-from-file="${ENV_FILE}")
fi

echo
echo "> flutter run ${DEFINE_FILE_ARG[*]} --dart-define BACKEND_URL=${BACKEND_URL} $*"
exec flutter run "${DEFINE_FILE_ARG[@]}" --dart-define "BACKEND_URL=${BACKEND_URL}" "$@"
