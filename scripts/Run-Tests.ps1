<#
.SYNOPSIS
    Execute webMethods IS WmTestSuite unit tests.
#>

param(
    [Parameter(Mandatory)][string] $ISHost,
    [Parameter(Mandatory)][string] $Port,
    [string]  $Protocol   = "http",
    [Parameter(Mandatory)][string] $User,
    [Parameter(Mandatory)][string] $Password,
    [Parameter(Mandatory)][string] $Package,
    [string]  $ReportDir  = ".\build\test-reports",
    [string]  $TestSuite  = ""    # e.g. "MyPackage.tests:runAllTests"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BaseUrl    = "${Protocol}://${ISHost}:${Port}"
$CredsBytes = [System.Text.Encoding]::ASCII.GetBytes("${User}:${Password}")
$BasicAuth  = "Basic " + [Convert]::ToBase64String($CredsBytes)

if (-not (Test-Path $ReportDir)) {
    New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
}

# Default test suite convention: <Package>.tests:runAllTests
if (-not $TestSuite) { $TestSuite = "$Package.tests:runAllTests" }

Write-Host ""
Write-Host "  Running Unit Tests"
Write-Host "  Package   : $Package"
Write-Host "  Suite     : $TestSuite"
Write-Host "  Server    : $BaseUrl"
Write-Host ""

$response = (Invoke-WebRequest `
    -Uri "$BaseUrl/invoke/$TestSuite" `
    -Headers @{ Authorization = $BasicAuth; Accept = "text/xml" } `
    -TimeoutSec 120 `
    -UseBasicParsing).Content

$reportFile = "$ReportDir\${Package}-test-results.xml"
$response | Out-File -FilePath $reportFile -Encoding utf8
Write-Host "  Test output saved: $reportFile"

if ($response -match "<failures>0</failures>" -and $response -match "<errors>0</errors>") {
    Write-Host " All tests passed"
} else {
    Write-Warning "  Tests may have failures  review $reportFile"
    # Uncomment below to fail the build on test failure:
    # exit 1
}