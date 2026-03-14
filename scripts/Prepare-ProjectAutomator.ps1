<#
.SYNOPSIS
    Prepare-ProjectAutomator.ps1
    Reads ProjectAutomator.xml template, substitutes runtime values,
    writes the final XML to the deploy directory, then runs projectautomator.bat.
.EXAMPLE
    .\Prepare-ProjectAutomator.ps1 `
        -SourceHost "localhost" -SourcePort "5555" `
        -TargetHost "localhost" -TargetPort "5555" `
        -User "Administrator" -Password "manage" `
        -Package "TestDeployPackage" -BuildNumber "42" `
        -WorkspaceDir "C:\jenkins\workspace\myJob" `
        -DeployDir "C:\jenkins\workspace\myJob\dist"
#>

param(
    [Parameter(Mandatory)][string] $SourceHost,
    [Parameter(Mandatory)][string] $SourcePort,
    [string]  $SourceUser     = "Administrator",
    [Parameter(Mandatory)][string] $SourcePassword,
    [Parameter(Mandatory)][string] $TargetHost,
    [Parameter(Mandatory)][string] $TargetPort,
    [string]  $TargetUser     = "Administrator",
    [Parameter(Mandatory)][string] $TargetPassword,
    [Parameter(Mandatory)][string] $Package,
    [Parameter(Mandatory)][string] $BuildNumber,
    [Parameter(Mandatory)][string] $WorkspaceDir,
    [Parameter(Mandatory)][string] $DeployDir,
    [string]  $ProjectAutomatorBat = "C:\SoftwareAG11\IntegrationServer\instances\default\packages\WmDeployer\bin\projectautomator.bat"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$TemplateFile = "$WorkspaceDir\config\ProjectAutomator.xml"
$OutputFile   = "$DeployDir\ProjectAutomator-runtime.xml"
$LogFile      = "$DeployDir\projectautomator.log"

Write-Host "--------------------------------------------------"
Write-Host "  Prepare ProjectAutomator.xml"
Write-Host "  Package     : $Package"
Write-Host "  Source IS   : ${SourceHost}:${SourcePort}"
Write-Host "  Target IS   : ${TargetHost}:${TargetPort}"
Write-Host "  Build       : $BuildNumber"
Write-Host "  Output XML  : $OutputFile"
Write-Host "--------------------------------------------------"

# -- Step 1: Validate template exists -----------------------------------------
if (-not (Test-Path $TemplateFile)) {
    Write-Error "ProjectAutomator.xml template not found: $TemplateFile"
    exit 1
}
if (-not (Test-Path $ProjectAutomatorBat)) {
    Write-Error "projectautomator.bat not found: $ProjectAutomatorBat"
    exit 1
}

# -- Step 2: Substitute placeholders ------------------------------------------
Write-Host ""
Write-Host "[Step 1] Substituting placeholders in ProjectAutomator.xml..."

if (-not (Test-Path $DeployDir)) {
    New-Item -ItemType Directory -Force -Path $DeployDir | Out-Null
}

$content = Get-Content $TemplateFile -Raw
$content = $content -replace '@@SOURCE_HOST@@',     $SourceHost
$content = $content -replace '@@SOURCE_PORT@@',     $SourcePort
$content = $content -replace '@@SOURCE_USER@@',     $SourceUser
$content = $content -replace '@@SOURCE_PASSWORD@@', $SourcePassword
$content = $content -replace '@@TARGET_HOST@@',     $TargetHost
$content = $content -replace '@@TARGET_PORT@@',     $TargetPort
$content = $content -replace '@@TARGET_USER@@',     $TargetUser
$content = $content -replace '@@TARGET_PASSWORD@@', $TargetPassword
$content = $content -replace '@@PACKAGE_NAME@@',    $Package
$content = $content -replace '@@BUILD_NUMBER@@',    $BuildNumber

Set-Content -Path $OutputFile -Value $content -Encoding UTF8
Write-Host "  Runtime XML written to: $OutputFile"

# -- Step 3: Run ProjectAutomator ---------------------------------------------
Write-Host ""
Write-Host "[Step 2] Running ProjectAutomator..."
Write-Host "  Bat: $ProjectAutomatorBat"
Write-Host "  Log: $LogFile"

# Write a small wrapper bat to avoid path-with-spaces issues in Start-Process
$WrapperBat = "$DeployDir\run-pa.bat"
"@echo off" | Set-Content $WrapperBat
"call `"$ProjectAutomatorBat`" `"$OutputFile`"" | Add-Content $WrapperBat

$process = Start-Process `
    -FilePath $WrapperBat `
    -RedirectStandardOutput $LogFile `
    -RedirectStandardError  "$DeployDir\pa-err.log" `
    -Wait `
    -PassThru `
    -NoNewWindow

# -- Step 4: Show log output --------------------------------------------------
Write-Host ""
Write-Host "[Step 3] ProjectAutomator output:"
Write-Host "--------------------------------------------------"
if (Test-Path $LogFile) {
    Get-Content $LogFile | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host "  No stdout log produced."
}
$ErrLog = "$DeployDir\pa-err.log"
if ((Test-Path $ErrLog) -and (Get-Content $ErrLog -Raw).Trim()) {
    Write-Host "  [STDERR]:"
    Get-Content $ErrLog | ForEach-Object { Write-Host "  $_" }
}
Write-Host "--------------------------------------------------"

# -- Step 5: Check exit code --------------------------------------------------
if ($process.ExitCode -ne 0) {
    Write-Error "ProjectAutomator failed with exit code: $($process.ExitCode). Review log: $LogFile"
    exit 1
}

Write-Host ""
Write-Host "ProjectAutomator deployment of $Package completed successfully!"