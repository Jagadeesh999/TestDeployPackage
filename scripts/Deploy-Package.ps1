<#
.SYNOPSIS
    Deploy a webMethods IS composite package on Windows Server.
.DESCRIPTION
    Uploads the composite ZIP to Integration Server via REST API,
    installs, enables, and optionally reloads the package.
.EXAMPLE
    .\Deploy-Package.ps1 -Host "is-server" -Port "5555" -Protocol "http" `
        -User "Administrator" -Password "manage" `
        -Package "MyPackage" -CompositeFile "C:\build\MyPackage_1.zip" -Reload $true
#>

param(
    [Parameter(Mandatory)][string] $Host,
    [Parameter(Mandatory)][string] $Port,
    [string]  $Protocol      = "http",
    [Parameter(Mandatory)][string] $User,
    [Parameter(Mandatory)][string] $Password,
    [Parameter(Mandatory)][string] $Package,
    [Parameter(Mandatory)][string] $CompositeFile,
    [bool]    $Reload         = $true,
    [int]     $MaxRetries     = 3,
    [int]     $RetryDelaySec  = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Helpers ───────────────────────────────────────────────────────────────────
$BaseUrl   = "${Protocol}://${Host}:${Port}"
$CredsBytes = [System.Text.Encoding]::ASCII.GetBytes("${User}:${Password}")
$BasicAuth = "Basic " + [Convert]::ToBase64String($CredsBytes)
$Headers   = @{ Authorization = $BasicAuth }

function Invoke-ISRequest {
    param(
        [string] $Uri,
        [string] $Method      = "GET",
        [string] $ContentType = "application/json",
        [byte[]] $Body        = $null
    )
    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        try {
            $params = @{
                Uri                  = $Uri
                Method               = $Method
                Headers              = $Headers
                TimeoutSec           = 120
                UseBasicParsing      = $true
            }
            if ($ContentType) { $params.ContentType = $ContentType }
            if ($Body)        { $params.Body        = $Body }

            $response = Invoke-WebRequest @params
            return $response.Content
        } catch {
            $attempt++
            Write-Warning "  ⚠️  Attempt $attempt/$MaxRetries failed: $_"
            if ($attempt -ge $MaxRetries) { throw }
            Start-Sleep -Seconds $RetryDelaySec
        }
    }
}

# ── Validation ────────────────────────────────────────────────────────────────
if (-not (Test-Path $CompositeFile)) {
    Write-Error "❌ Composite file not found: $CompositeFile"
    exit 1
}

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "  webMethods IS Package Deployment (Windows)"
Write-Host "  Target : $BaseUrl"
Write-Host "  Package: $Package"
Write-Host "  File   : $CompositeFile"
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Step 1: Upload composite ZIP ─────────────────────────────────────────────
Write-Host "`n📦 Step 1: Uploading composite file..."
$fileBytes = [System.IO.File]::ReadAllBytes($CompositeFile)
$uploadUri = "$BaseUrl/invoke/wm.server.packages/packageUpload?packageName=$Package"
$result    = Invoke-ISRequest -Uri $uploadUri -Method "PUT" -ContentType "application/zip" -Body $fileBytes
Write-Host "  Response: $result"

# ── Step 2: Install package ───────────────────────────────────────────────────
Write-Host "`n🔧 Step 2: Installing package..."
$installUri = "$BaseUrl/invoke/wm.server.packages/packageInstall"
$installBody = [System.Text.Encoding]::UTF8.GetBytes("packageName=$Package")
$result = Invoke-ISRequest -Uri $installUri -Method "POST" -ContentType "application/x-www-form-urlencoded" -Body $installBody
Write-Host "  Response: $result"

# ── Step 3: Enable package ────────────────────────────────────────────────────
Write-Host "`n✅ Step 3: Enabling package..."
$result = Invoke-ISRequest -Uri "$BaseUrl/invoke/wm.server.packages/packageEnable?packageName=$Package"
Write-Host "  Response: $result"

# ── Step 4: Reload package ────────────────────────────────────────────────────
if ($Reload) {
    Write-Host "`n🔄 Step 4: Reloading package..."
    $result = Invoke-ISRequest -Uri "$BaseUrl/invoke/wm.server.packages/packageLoad?packageName=$Package"
    Write-Host "  Response: $result"
}

# ── Step 5: Verify package state ─────────────────────────────────────────────
Write-Host "`n🔍 Step 5: Verifying package state..."
$statusResp = Invoke-ISRequest -Uri "$BaseUrl/invoke/wm.server.packages/packageStatus?packageName=$Package"

if ($statusResp -match '"enabled"\s*:\s*"true"') {
    Write-Host "  ✅ Package $Package is ENABLED and running."
} else {
    Write-Error "❌ Package $Package does not appear to be enabled. Response: $statusResp"
    exit 1
}

Write-Host "`n🎉 Deployment of $Package completed successfully!"
