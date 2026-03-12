<#
.SYNOPSIS
    Deploy a webMethods IS package on the local Windows Server.
.DESCRIPTION
    Extracts the composite ZIP directly into the IS packages directory,
    then calls the IS REST API to reload the package.
    This approach works reliably for IS 11.x on the same machine as Jenkins.
.EXAMPLE
    .\Deploy-Package.ps1 -ISHost "localhost" -Port "5555" -Protocol "http" `
        -User "Administrator" -Password "manage" `
        -Package "TestDeployPackage" `
        -CompositeFile "C:\build\TestDeployPackage.zip" `
        -ISPackagesDir "C:\SoftwareAG11\IntegrationServer\instances\default\packages" `
        -Reload "true"
#>

param(
    [Parameter(Mandatory)][string] $ISHost,
    [Parameter(Mandatory)][string] $Port,
    [string]  $Protocol      = "http",
    [Parameter(Mandatory)][string] $User,
    [Parameter(Mandatory)][string] $Password,
    [Parameter(Mandatory)][string] $Package,
    [Parameter(Mandatory)][string] $CompositeFile,
    [string]  $ISPackagesDir  = "C:\SoftwareAG11\IntegrationServer\instances\default\packages",
    [string]  $Reload         = "true",
    [int]     $MaxRetries     = 3,
    [int]     $RetryDelaySec  = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ReloadBool = ($Reload -eq "true" -or $Reload -eq "1" -or $Reload -eq "True")
$BaseUrl    = "${Protocol}://${ISHost}:${Port}"
$CredsBytes = [System.Text.Encoding]::ASCII.GetBytes("${User}:${Password}")
$BasicAuth  = "Basic " + [Convert]::ToBase64String($CredsBytes)
$Headers    = @{ Authorization = $BasicAuth }

function Invoke-ISRequest {
    param(
        [string] $Uri,
        [string] $Method      = "GET",
        [hashtable] $Headers  = @{},
        [string] $ContentType = "application/x-www-form-urlencoded",
        [string] $Body        = $null
    )
    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        try {
            $params = @{
                Uri             = $Uri
                Method          = $Method
                Headers         = $Headers
                TimeoutSec      = 60
                UseBasicParsing = $true
            }
            if ($Body) {
                $params.Body        = $Body
                $params.ContentType = $ContentType
            }
            $response = Invoke-WebRequest @params
            return $response.Content
        } catch {
            $attempt++
            Write-Warning "  Attempt $attempt/$MaxRetries failed: $_"
            if ($attempt -ge $MaxRetries) { throw }
            Start-Sleep -Seconds $RetryDelaySec
        }
    }
}

# -- Validation ----------------------------------------------------------------
if (-not (Test-Path $CompositeFile)) {
    Write-Error "Composite file not found: $CompositeFile"
    exit 1
}
if (-not (Test-Path $ISPackagesDir)) {
    Write-Error "IS packages directory not found: $ISPackagesDir"
    exit 1
}

Write-Host "--------------------------------------------------"
Write-Host "  webMethods IS Package Deployment"
Write-Host "  IS Packages Dir : $ISPackagesDir"
Write-Host "  Package         : $Package"
Write-Host "  Composite File  : $CompositeFile"
Write-Host "  Reload          : $ReloadBool"
Write-Host "--------------------------------------------------"

# -- Step 1: Stop package before overwriting ----------------------------------
Write-Host ""
Write-Host "[Step 1] Disabling package before update..."
try {
    $result = Invoke-ISRequest -Uri "$BaseUrl/invoke/wm.server.packages/packageDisable?packageName=$Package" -Headers $Headers
    Write-Host "  Response: $result"
} catch {
    Write-Host "  Package may not exist yet - continuing: $_"
}

# -- Step 2: Extract ZIP into IS packages directory ---------------------------
Write-Host ""
Write-Host "[Step 2] Extracting composite ZIP to IS packages directory..."

Add-Type -AssemblyName System.IO.Compression.FileSystem

$PackageTargetDir = Join-Path $ISPackagesDir $Package

# Remove old package directory if it exists
if (Test-Path $PackageTargetDir) {
    Write-Host "  Removing existing package directory: $PackageTargetDir"
    Remove-Item -Recurse -Force $PackageTargetDir
}

# Extract ZIP - the ZIP contains a folder named after the package
$TempExtract = Join-Path $env:TEMP "IS_deploy_$Package"
if (Test-Path $TempExtract) { Remove-Item -Recurse -Force $TempExtract }
New-Item -ItemType Directory -Force -Path $TempExtract | Out-Null

[System.IO.Compression.ZipFile]::ExtractToDirectory($CompositeFile, $TempExtract)

# Find the extracted package folder and move it into IS packages dir
$ExtractedFolder = Get-ChildItem -Path $TempExtract -Directory | Select-Object -First 1
if ($ExtractedFolder) {
    Move-Item -Path $ExtractedFolder.FullName -Destination $PackageTargetDir -Force
} else {
    # ZIP was flat - move TempExtract itself
    Move-Item -Path $TempExtract -Destination $PackageTargetDir -Force
}

if (Test-Path $TempExtract) { Remove-Item -Recurse -Force $TempExtract -ErrorAction SilentlyContinue }
Write-Host "  Package extracted to: $PackageTargetDir"

# -- Step 3: Reload / load the package via IS REST API ------------------------
if ($ReloadBool) {
    Write-Host ""
    Write-Host "[Step 3] Reloading package on IS..."
    $result = Invoke-ISRequest `
        -Uri "$BaseUrl/invoke/wm.server.packages/packageLoad?packageName=$Package" `
        -Headers $Headers
    Write-Host "  Response: $result"
} else {
    Write-Host ""
    Write-Host "[Step 3] Skipping reload (Reload=false)"
}

# -- Step 4: Enable the package -----------------------------------------------
Write-Host ""
Write-Host "[Step 4] Enabling package..."
$result = Invoke-ISRequest `
    -Uri "$BaseUrl/invoke/wm.server.packages/packageEnable?packageName=$Package" `
    -Headers $Headers
Write-Host "  Response: $result"

# -- Step 5: Verify -----------------------------------------------------------
Write-Host ""
Write-Host "[Step 5] Verifying package state..."
$statusResp = Invoke-ISRequest `
    -Uri "$BaseUrl/invoke/wm.server.packages/packageStatus?packageName=$Package" `
    -Headers $Headers

if ($statusResp -match '"enabled"\s*:\s*"true"') {
    Write-Host "  Package $Package is ENABLED and running."
} else {
    Write-Error "Package $Package does not appear to be enabled. Response: $statusResp"
    exit 1
}

Write-Host ""
Write-Host "Deployment of $Package completed successfully!"