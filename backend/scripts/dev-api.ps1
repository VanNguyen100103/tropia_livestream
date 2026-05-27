#!/usr/bin/env pwsh
# =============================================================================
# dev-api.ps1 — start the Go API with SRS_*_HOST auto-pointed at this LAN IP.
# =============================================================================
# Reason: phones / OBS on the same Wi-Fi need an LAN-reachable URL for SRS.
# Hardcoding it in .env.development breaks every time Wi-Fi changes; this
# script picks the current LAN IPv4 and overrides the SRS env vars before
# launching `go run ./cmd/api`. Other env vars still come from
# .env.development as usual.
#
# Usage:
#   ./scripts/dev-api.ps1
# =============================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Get-LanIPv4 {
    $candidates = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notlike '127.*'      -and
            $_.IPAddress -notlike '169.254.*'  -and
            $_.IPAddress -notlike '172.*'      -and  # virtual / Docker
            $_.PrefixOrigin -ne 'WellKnown'
        } |
        Sort-Object -Property @{
            Expression = { if ($_.InterfaceAlias -match 'Wi-Fi|Wireless') { 0 } else { 1 } }
        }, IPAddress

    if (-not $candidates) {
        throw 'No usable LAN IPv4 address found. Are you connected to Wi-Fi?'
    }
    return $candidates[0].IPAddress
}

$ip = Get-LanIPv4

$env:SRS_RTMP_HOST = "rtmp://${ip}:1935"
$env:SRS_HLS_HOST  = "http://${ip}:8090"
$env:SRS_WHIP_HOST = "http://${ip}:1985"
# SRS_API_HOST stays localhost — that's the backend → SRS call, not phone → SRS.

Write-Host ""
Write-Host "  LAN IP            : $ip" -ForegroundColor Green
Write-Host "  SRS_RTMP_HOST     : $env:SRS_RTMP_HOST" -ForegroundColor DarkGray
Write-Host "  SRS_HLS_HOST      : $env:SRS_HLS_HOST"  -ForegroundColor DarkGray
Write-Host "  SRS_WHIP_HOST     : $env:SRS_WHIP_HOST" -ForegroundColor DarkGray
Write-Host ""
Write-Host "> go run ./cmd/api" -ForegroundColor Cyan

& go run ./cmd/api
