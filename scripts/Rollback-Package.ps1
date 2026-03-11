<#
.SYNOPSIS
    Rollback a webMethods IS package to its last backup.
#>

param(
    [Parameter(Mandatory)][string] $Host,
    [Parameter(Mandatory)][string] $Port,
    [string]  $Protocol    = "http",
    [Parameter(Mandatory)][string] $User,
    [Parameter(Mandatory)][string] $Password,
    [Parameter(Mandatory)][string] $Package,
    [string]  $BackupDir   = ".\dist\backups",
    [string]  $BackupFile  = ""   # If empty, picks most recent backup automatically
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Auto-select latest backup
if (-not $BackupFile) {
    $latest = Get-ChildItem -Path $BackupDir -Filter "${Package}_backup_*.zip" -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending |
              Select-Object -First 1
    if (-not $latest) {
        Write-Error " No backup found in $BackupDir for package $Package"
        exit 1
    }
    $BackupFile = $latest.FullName
}

if (-not (Test-Path $BackupFile)) {
    Write-Error " Backup file not found: $BackupFile"
    exit 1
}

Write-Host ""
Write-Host "    ROLLBACK: $Package"
Write-Host "  Using backup: $BackupFile"
Write-Host ""
$confirm = Read-Host "Confirm rollback? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Rollback cancelled."
    exit 0
}

# Delegate to Deploy-Package.ps1
& "$PSScriptRoot\Deploy-Package.ps1" `
    -Host          $Host `
    -Port          $Port `
    -Protocol      $Protocol `
    -User          $User `
    -Password      $Password `
    -Package       $Package `
    -CompositeFile $BackupFile `
    -Reload        $true

Write-Host " Rollback of $Package completed."