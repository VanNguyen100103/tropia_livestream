#!/usr/bin/env bash
# =============================================================================
# dev-all.sh — start API + worker as separate processes in one terminal.
# =============================================================================
# See dev-all.ps1 for rationale. POSIX version using background jobs + trap.
#
# Usage:
#   ./scripts/dev-all.sh
#   LAN_IP=1 ./scripts/dev-all.sh    # auto-export SRS_*_HOST=LAN_IP first
# =============================================================================
set -euo pipefail

if [ "${LAN_IP:-0}" = "1" ]; then
  lan_ip() {
    if command -v ip >/dev/null 2>&1; then
      ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") print $(i+1)}' | head -1
    elif command -v ipconfig >/dev/null 2>&1; then
      ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null
    fi
  }
  IP="$(lan_ip || true)"
  if [ -n "${IP}" ]; then
    export SRS_RTMP_HOST="rtmp://${IP}:1935"
    export SRS_HLS_HOST="http://${IP}:8090"
    export SRS_WHIP_HOST="http://${IP}:1985"
    echo "[dev-all] LAN IP: ${IP}"
  fi
fi

# Prefix stdout/stderr of each subprocess.
prefix() {
  local tag="$1"
  awk -v t="$tag" '{print t" "$0; fflush()}'
}

api_pid=
wrk_pid=

cleanup() {
  echo "[dev-all] stopping..."
  [ -n "${api_pid}" ] && kill "${api_pid}" 2>/dev/null || true
  [ -n "${wrk_pid}" ] && kill "${wrk_pid}" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup INT TERM EXIT

# shellcheck disable=SC2069
( go run ./cmd/api 2>&1 | prefix "[api]" ) &
api_pid=$!

( go run ./cmd/worker 2>&1 | prefix "[wrk]" ) &
wrk_pid=$!

echo "[dev-all] api pid=${api_pid}  worker pid=${wrk_pid}"
echo "[dev-all] Ctrl+C to stop both"

# Wait for either to exit, then cleanup the other.
wait -n "${api_pid}" "${wrk_pid}" 2>/dev/null || true
echo "[dev-all] one process exited; shutting down peer"
