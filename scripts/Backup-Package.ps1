<#
.SYNOPSIS
    Export (backup) an existing IS package before deployment.
#>

param(
    [Parameter(Mandatory)][string] $ISHost,
    [Parameter(Mandatory)][string] $Port,
    [string]  $Protocol  = "http",
    [Parameter(Mandatory)][string] $User,
    [Parameter(Mandatory)][string] $Password,
    [Parameter(Mandatory)][string] $Package,
    [string]  $BackupDir = ".\dist\backups"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BaseUrl    = "${Protocol}://${ISHost}:${Port}"
$CredsBytes = [System.Text.Encoding]::ASCII.GetBytes("${User}:${Password}")
$BasicAuth  = "Basic " + [Convert]::ToBase64String($CredsBytes)
$Timestamp  = (Get-Date -Format "yyyyMMdd-HHmmss")
$BackupFile = "$BackupDir\${Package}_backup_${Timestamp}.zip"

if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
}

Write-Host ""
Write-Host "  Backing up IS Package: $Package"
Write-Host "  Backup file: $BackupFile"
Write-Host ""

$ExportUri = "$BaseUrl/invoke/wm.server.packages/packageExport?packageName=$Package&exportACLs=true"

try {
    Invoke-WebRequest `
        -Uri            $ExportUri `
        -Headers        @{ Authorization = $BasicAuth } `
        -OutFile        $BackupFile `
        -TimeoutSec     120 `
        -UseBasicParsing

    if ((Test-Path $BackupFile) -and ((Get-Item $BackupFile).Length -gt 0)) {
        $sizeMB = [math]::Round((Get-Item $BackupFile).Length / 1MB, 2)
        Write-Host " Backup saved: $BackupFile ($sizeMB MB)"
    } else {
        Write-Error " Backup file is empty or missing: $BackupFile"
        exit 1
    }
} catch {
    Write-Error " Backup failed: $_"
    if (Test-Path $BackupFile) { Remove-Item $BackupFile -Force }
    exit 1
}
