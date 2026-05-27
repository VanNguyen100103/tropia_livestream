#!/usr/bin/env pwsh
# =============================================================================
# dev-mobile.ps1 — flutter run targeting a physical phone on the same Wi-Fi.
# =============================================================================
# Auto-discovers this machine's LAN IPv4, opens the dev ports through Windows
# Firewall if needed, then launches `flutter run` with --dart-define so the
# Flutter app uses the right BACKEND_URL.
#
# Usage:
#   ./scripts/dev-mobile.ps1                 # default port 3000
#   ./scripts/dev-mobile.ps1 -Port 3000      # explicit
#   ./scripts/dev-mobile.ps1 -Device <id>    # pin to a specific device
#   ./scripts/dev-mobile.ps1 -SkipFirewall   # skip the UAC firewall step
# =============================================================================

[CmdletBinding()]
param(
    [int]    $Port         = 3000,
    [string] $Device       = '',
    [switch] $SkipFirewall
)

$ErrorActionPreference = 'Stop'

function Get-LanIPv4 {
    # Prefer a Wi-Fi or Ethernet interface with a private RFC1918 address.
    # Filter out APIPA (169.254.*) and Hyper-V virtual switches (172.*).
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

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-FirewallRule {
    param([int[]] $Ports)

    $ruleName = 'Tropia dev (3000/1935/8080/1985)'
    $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "[firewall] rule '$ruleName' already exists - skipping" -ForegroundColor DarkGray
        return
    }

    if (-not (Test-IsAdmin)) {
        Write-Warning "Cannot create firewall rule without admin rights. Re-run this script in an elevated PowerShell, OR run manually:"
        Write-Host "    New-NetFirewallRule -DisplayName '$ruleName' -Direction Inbound -Protocol TCP -LocalPort $($Ports -join ',') -Action Allow" -ForegroundColor Yellow
        return
    }

    Write-Host "[firewall] creating inbound rule for ports $($Ports -join ',')..." -ForegroundColor Cyan
    New-NetFirewallRule `
        -DisplayName $ruleName `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $Ports `
        -Action Allow | Out-Null
}

# ─── Main ────────────────────────────────────────────────────────────────────

$lanIp = Get-LanIPv4
$backendUrl = "http://${lanIp}:${Port}"

Write-Host ""
Write-Host "  LAN IP    : $lanIp" -ForegroundColor Green
Write-Host "  Backend   : $backendUrl" -ForegroundColor Green
Write-Host "  Test from phone browser: $backendUrl/health" -ForegroundColor DarkGray
Write-Host ""

if (-not $SkipFirewall) {
    Ensure-FirewallRule -Ports @(3000, 1935, 8080, 1985)
}

# Quick reachability check from this host. If this fails, the phone won't
# reach it either.
try {
    $r = Invoke-WebRequest -Uri "$backendUrl/health" -TimeoutSec 3 -UseBasicParsing
    Write-Host "[health] $($r.StatusCode) $($r.Content)" -ForegroundColor DarkGreen
} catch {
    Write-Warning "Cannot reach $backendUrl/health - is `go run ./cmd/api` running?"
    Write-Warning $_.Exception.Message
}

# Build flutter args. We load env.development.json first so any
# placeholder / Sentry / etc. vars defined there get applied, then
# override BACKEND_URL with the freshly-detected LAN IP. Later --dart-
# define flags override earlier --dart-define-from-file keys, so this
# ordering is what we want.
#
# Windows PowerShell 5.1's Join-Path only takes 2 positional args
# (-Path, -ChildPath); a 3-arg call crashes with a positional-binding
# error that gets attributed to this script. Build the path via simple
# concatenation instead so it works on both 5.1 and 7+.
$envFile = "$PSScriptRoot\..\env.development.json"
$flutterArgs = @('run')
if (Test-Path $envFile) {
    $flutterArgs += @("--dart-define-from-file=$envFile")
}
$flutterArgs += @('--dart-define', "BACKEND_URL=$backendUrl")
if ($Device) {
    $flutterArgs += @('-d', $Device)
}

Write-Host ""
Write-Host "> flutter $($flutterArgs -join ' ')" -ForegroundColor Cyan
& flutter @flutterArgs
