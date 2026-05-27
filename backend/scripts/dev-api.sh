#!/usr/bin/env bash
# =============================================================================
# dev-api.sh — start the Go API with SRS_*_HOST pointed at this LAN IP.
# =============================================================================
# See dev-api.ps1 for the rationale. macOS/Linux only.
# =============================================================================
set -euo pipefail

lan_ip() {
  if command -v ip >/dev/null 2>&1; then
    ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") print $(i+1)}' | head -1
  elif command -v ipconfig >/dev/null 2>&1; then
    ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null
  else
    ifconfig 2>/dev/null \
      | awk '/inet (192\.168|10\.|172\.(1[6-9]|2[0-9]|3[01]))/ {print $2; exit}'
  fi
}

IP="$(lan_ip || true)"
if [ -z "${IP}" ]; then
  echo "ERROR: could not detect LAN IPv4. Are you on Wi-Fi?" >&2
  exit 1
fi

export SRS_RTMP_HOST="rtmp://${IP}:1935"
export SRS_HLS_HOST="http://${IP}:8090"
export SRS_WHIP_HOST="http://${IP}:1985"

echo
echo "  LAN IP        : ${IP}"
echo "  SRS_RTMP_HOST : ${SRS_RTMP_HOST}"
echo "  SRS_HLS_HOST  : ${SRS_HLS_HOST}"
echo "  SRS_WHIP_HOST : ${SRS_WHIP_HOST}"
echo
echo "> go run ./cmd/api"

exec go run ./cmd/api
