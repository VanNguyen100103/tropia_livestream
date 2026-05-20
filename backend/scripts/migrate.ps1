# Tropia migrate helper for Windows PowerShell.
#
# Usage:
#   .\scripts\migrate.ps1 up                    # apply all pending
#   .\scripts\migrate.ps1 down                  # rollback last
#   .\scripts\migrate.ps1 down-all              # rollback EVERYTHING
#   .\scripts\migrate.ps1 status                # show current version
#   .\scripts\migrate.ps1 create add_phone      # create new migration files
#   .\scripts\migrate.ps1 force 1               # force-set version (recover dirty)
#
# Requires `migrate.exe` on PATH:
#   scoop install migrate
#   # or
#   choco install migrate
#   # or download from https://github.com/golang-migrate/migrate/releases

param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("up","down","down-all","status","create","force")]
    [string]$Command,

    [Parameter(Position=1)]
    [string]$Arg
)

$ErrorActionPreference = "Stop"

# Resolve script directory and load .env.development from backend root.
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendDir = Split-Path -Parent $scriptDir
$envFile    = Join-Path $backendDir ".env.development"

if (-not (Test-Path $envFile)) {
    Write-Error "$envFile not found"
    exit 1
}

# Load DATABASE_URL from .env.development (handles "KEY=value" lines, skips comments).
$databaseUrl = $null
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*DATABASE_URL\s*=\s*(.+)$') {
        $databaseUrl = $matches[1].Trim()
    }
}

if (-not $databaseUrl) {
    Write-Error "DATABASE_URL not found in $envFile"
    exit 1
}

# Check migrate.exe is available.
if (-not (Get-Command migrate -ErrorAction SilentlyContinue)) {
    Write-Error "migrate.exe not found on PATH. Install via 'scoop install migrate' or 'choco install migrate'."
    exit 1
}

$migrationsDir = Join-Path $backendDir "migrations"

switch ($Command) {
    "up"        { migrate -path $migrationsDir -database $databaseUrl up }
    "down"      { migrate -path $migrationsDir -database $databaseUrl down 1 }
    "down-all"  { migrate -path $migrationsDir -database $databaseUrl down -all }
    "status"    { migrate -path $migrationsDir -database $databaseUrl version }
    "create"    {
        if (-not $Arg) { Write-Error "Usage: migrate.ps1 create <name>"; exit 1 }
        migrate create -ext sql -dir $migrationsDir -seq $Arg
    }
    "force"     {
        if (-not $Arg) { Write-Error "Usage: migrate.ps1 force <version>"; exit 1 }
        migrate -path $migrationsDir -database $databaseUrl force $Arg
    }
}
