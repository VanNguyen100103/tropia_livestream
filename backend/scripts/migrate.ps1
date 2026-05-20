# Tropia migrate helper for Windows PowerShell.
#
# Thin wrapper around the in-tree cmd/migrate binary. No external
# `migrate.exe` install required — just Go.
#
# Usage:
#   .\scripts\migrate.ps1 up                    # apply all pending
#   .\scripts\migrate.ps1 down                  # rollback last (default 1)
#   .\scripts\migrate.ps1 down 2                # rollback last 2
#   .\scripts\migrate.ps1 down all              # rollback EVERYTHING
#   .\scripts\migrate.ps1 status                # show current version
#   .\scripts\migrate.ps1 create add_phone      # create new migration pair
#   .\scripts\migrate.ps1 force 1               # force version (recover dirty)
#   .\scripts\migrate.ps1 goto 3                # migrate to a specific version

$ErrorActionPreference = "Stop"

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendDir = Split-Path -Parent $scriptDir

# Resolve `go` (prefer PATH, fall back to standard install).
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

if ($args.Count -eq 0) {
    & $goExe run ./cmd/migrate
    exit $LASTEXITCODE
}

& $goExe run ./cmd/migrate @args
exit $LASTEXITCODE
