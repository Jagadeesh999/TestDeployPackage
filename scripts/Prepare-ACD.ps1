<#
.SYNOPSIS
    Prepare-ACD.ps1
    Copies the ACD template and substitutes the package name placeholder.
#>

param(
    [Parameter(Mandatory)][string] $PackageName,
    [Parameter(Mandatory)][string] $WorkspaceDir,
    [Parameter(Mandatory)][string] $AbeProjectDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$AcdSrc  = "$WorkspaceDir\abe\acd\PACKAGE_NAME.acd"
$AcdDir  = "$AbeProjectDir\acd"
$AcdDest = "$AcdDir\$PackageName.acd"

Write-Host "[Prepare-ACD] Package    : $PackageName"
Write-Host "[Prepare-ACD] Source ACD : $AcdSrc"
Write-Host "[Prepare-ACD] Output ACD : $AcdDest"

# Validate source ACD template exists
if (-not (Test-Path $AcdSrc)) {
    Write-Error "ERROR: ACD template not found: $AcdSrc"
    exit 1
}

# Create output directory
New-Item -ItemType Directory -Force -Path $AcdDir | Out-Null

# Read, substitute and write
(Get-Content $AcdSrc) -replace '\$\{PACKAGE_NAME\}', $PackageName |
    Set-Content $AcdDest

Write-Host "[Prepare-ACD] OK - ACD written to $AcdDest"
