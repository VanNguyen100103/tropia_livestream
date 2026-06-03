# Tropia seed helper for Windows PowerShell.
#
# Runs cmd/seed which populates the database with deterministic test fixtures
# (admin/seller/buyer accounts, one shop, categories, products, a live session).
# Idempotent — safe to re-run.
#
# Usage:
#   .\scripts\seed.ps1
#
# Reads DATABASE_URL from .env.development.

$ErrorActionPreference = "Stop"

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendDir = Split-Path -Parent $scriptDir

# Resolve `go` (prefer PATH, fall back to standard install location).
$goExe = "go"
if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    $candidate = "C:\Program Files\Go\bin\go.exe"
    if (Test-Path $candidate) {
        $goExe = $candidate
    } else {
        Write-Error "go not found on PATH and not at C:\Program Files\Go\bin\go.exe"
        exit 1
    }
}

Set-Location $backendDir
Write-Host "Seeding database..." -ForegroundColor Cyan
& $goExe run ./cmd/seed
