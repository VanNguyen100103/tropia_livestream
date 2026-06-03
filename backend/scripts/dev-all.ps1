#!/usr/bin/env pwsh
# =============================================================================
# dev-all.ps1 — start API + worker as separate processes in one terminal.
# =============================================================================
# Why not gộp vào 1 process: worker crash (FFmpeg, R2 timeout, OOM) sẽ kéo
# API xuống cùng. Prod k8s cũng tách 2 Deployments để scale độc lập, nên
# dev gộp sẽ giả lập sai môi trường thật. Script này giữ isolation bằng
# cách spawn 2 process riêng, nhưng tee log vào cùng terminal với prefix
# [api] / [wrk] để bạn nhìn được cả 2.
#
# Ctrl+C sẽ kill cả 2.
#
# Usage:
#   ./scripts/dev-all.ps1
#   ./scripts/dev-all.ps1 -LanIP       # also export SRS_*_HOST=LAN_IP first
# =============================================================================

[CmdletBinding()]
param(
    [switch] $LanIP
)

$ErrorActionPreference = 'Stop'

if ($LanIP) {
    function Get-LanIPv4 {
        $candidates = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -notlike '127.*' -and
                $_.IPAddress -notlike '169.254.*' -and
                $_.IPAddress -notlike '172.*' -and
                $_.PrefixOrigin -ne 'WellKnown'
            } |
            Sort-Object -Property @{
                Expression = { if ($_.InterfaceAlias -match 'Wi-Fi|Wireless') { 0 } else { 1 } }
            }, IPAddress
        return $candidates[0].IPAddress
    }
    $ip = Get-LanIPv4
    $env:SRS_RTMP_HOST = "rtmp://${ip}:1935"
    $env:SRS_HLS_HOST  = "http://${ip}:8090"
    $env:SRS_WHIP_HOST = "http://${ip}:1985"
    Write-Host "[dev-all] LAN IP: $ip" -ForegroundColor Green
}

$jobs = @()

# Start API
$apiJob = Start-Job -Name 'api' -ScriptBlock {
    param($cwd, $envVars)
    Set-Location $cwd
    foreach ($k in $envVars.Keys) { Set-Item -Path "env:$k" -Value $envVars[$k] }
    & go run ./cmd/api 2>&1
} -ArgumentList (Get-Location).Path, @{
    SRS_RTMP_HOST = $env:SRS_RTMP_HOST
    SRS_HLS_HOST  = $env:SRS_HLS_HOST
    SRS_WHIP_HOST = $env:SRS_WHIP_HOST
}
$jobs += $apiJob

# Start worker
$wrkJob = Start-Job -Name 'wrk' -ScriptBlock {
    param($cwd)
    Set-Location $cwd
    & go run ./cmd/worker 2>&1
} -ArgumentList (Get-Location).Path
$jobs += $wrkJob

Write-Host "[dev-all] api job=$($apiJob.Id)  worker job=$($wrkJob.Id)" -ForegroundColor Cyan
Write-Host "[dev-all] Ctrl+C to stop both" -ForegroundColor Cyan

# Stream output from both jobs, prefixed. Loop until either dies.
try {
    while ($true) {
        foreach ($j in $jobs) {
            $out = Receive-Job -Job $j -Keep:$false
            if ($out) {
                $tag = if ($j.Name -eq 'api') { '[api]' } else { '[wrk]' }
                $color = if ($j.Name -eq 'api') { 'Green' } else { 'Magenta' }
                foreach ($line in $out) {
                    Write-Host "$tag $line" -ForegroundColor $color
                }
            }
        }
        if ($jobs | Where-Object { $_.State -ne 'Running' }) {
            Write-Warning "A job exited; shutting down."
            break
        }
        Start-Sleep -Milliseconds 200
    }
} finally {
    Write-Host "[dev-all] stopping..." -ForegroundColor Yellow
    foreach ($j in $jobs) {
        Stop-Job -Job $j -ErrorAction SilentlyContinue
        Remove-Job -Job $j -Force -ErrorAction SilentlyContinue
    }
}
