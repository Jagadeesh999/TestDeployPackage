<#
.SYNOPSIS
    Post-deployment health check for a webMethods IS package on Windows.
#>

param(
    [Parameter(Mandatory)][string] $Host,
    [Parameter(Mandatory)][string] $Port,
    [string]  $Protocol   = "http",
    [Parameter(Mandatory)][string] $User,
    [Parameter(Mandatory)][string] $Password,
    [Parameter(Mandatory)][string] $Package,
    [int]     $MaxWaitSec  = 60,
    [int]     $IntervalSec = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BaseUrl    = "${Protocol}://${Host}:${Port}"
$CredsBytes = [System.Text.Encoding]::ASCII.GetBytes("${User}:${Password}")
$BasicAuth  = "Basic " + [Convert]::ToBase64String($CredsBytes)
$Headers    = @{ Authorization = $BasicAuth }

Write-Host ""
Write-Host "  Post-Deployment Health Check (Windows)"
Write-Host "  Target : $BaseUrl"
Write-Host "  Package: $Package"
Write-Host ""

#  Check 1: IS Server reachability 
Write-Host "`n Check 1: IS server reachability..."
$elapsed = 0
$isReachable = $false

while ($elapsed -lt $MaxWaitSec) {
    try {
        Invoke-WebRequest -Uri "$BaseUrl/invoke/wm.server/ping" `
            -Headers $Headers -TimeoutSec 5 -UseBasicParsing | Out-Null
        $isReachable = $true
        break
    } catch {
        Write-Host "   Waiting for IS... ($elapsed s elapsed)"
        Start-Sleep -Seconds $IntervalSec
        $elapsed += $IntervalSec
    }
}

if (-not $isReachable) {
    Write-Error " IS server not reachable after ${MaxWaitSec}s"
    exit 1
}
Write-Host "   IS server is reachable"

#  Check 2: Package enabled status 
Write-Host "`n Check 2: Package enabled status..."
$statusResp = (Invoke-WebRequest `
    -Uri "$BaseUrl/invoke/wm.server.packages/packageStatus?packageName=$Package" `
    -Headers $Headers -TimeoutSec 30 -UseBasicParsing).Content

if ($statusResp -match '"enabled"\s*:\s*"true"') {
    Write-Host "   Package $Package is ENABLED"
} else {
    Write-Error " Package $Package is NOT enabled. Response: $statusResp"
    exit 1
}

#  Check 3: Load errors 
Write-Host "`n Check 3: Package load errors..."
if ($statusResp -match '"loadErrors"\s*:\s*\[\]') {
    Write-Host "   No load errors detected"
} elseif ($statusResp -match '"loadErrors"') {
    Write-Warning "    Load errors found  review IS server log manually"
}

#  Check 4: Server error log scan 
Write-Host "`n Check 4: Scanning IS error log for $Package..."
try {
    $logResp = (Invoke-WebRequest `
        -Uri "$BaseUrl/invoke/wm.server.logs/getLog?logType=error&lines=50" `
        -Headers $Headers -TimeoutSec 30 -UseBasicParsing).Content

    if ($logResp -match $Package -and $logResp -imatch "SEVERE|FATAL") {
        Write-Warning "    SEVERE/FATAL entries found for $Package in recent log. Review IS console."
    } else {
        Write-Host "   No severe errors in recent log for $Package"
    }
} catch {
    Write-Warning "    Could not retrieve log (non-fatal): $_"
}

Write-Host "`n Health check passed for package: $Package"