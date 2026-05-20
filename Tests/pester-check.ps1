<#
.SYNOPSIS
    Pester 5.x test runner for the RackStack pure-function unit-test suite.

.DESCRIPTION
    Pester complements the existing regex-pattern test harness (Run-Tests.ps1) with
    functional unit tests for pure functions (input validation, navigation, password
    complexity, formatters). Pester tests live in Tests/Pester/*.Tests.ps1 and run in
    isolation — each file dot-sources only the modules it needs.

    Exit code 0 = all tests passed, 1 = failures detected.

.NOTES
    Requires Pester 5.0+. Install via:
        Install-Module Pester -MinimumVersion 5.5.0 -Force -SkipPublisherCheck
#>

[CmdletBinding()]
param(
    [switch]$Detailed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Verify Pester 5.x is available
$pester = Get-Module Pester -ListAvailable | Where-Object { $_.Version -ge [version]'5.0.0' } | Select-Object -First 1
if (-not $pester) {
    Write-Host "ERROR: Pester 5.x not installed. Install via:" -ForegroundColor Red
    Write-Host "  Install-Module Pester -MinimumVersion 5.5.0 -Force -SkipPublisherCheck" -ForegroundColor Yellow
    exit 2
}
Import-Module Pester -MinimumVersion 5.0.0 -Force

$testsDir = Join-Path $PSScriptRoot 'Pester'
if (-not (Test-Path -LiteralPath $testsDir)) {
    Write-Host "No Pester tests directory at $testsDir" -ForegroundColor Yellow
    exit 0
}

$config = New-PesterConfiguration
$config.Run.Path = $testsDir
$config.Run.PassThru = $true
$config.Output.Verbosity = if ($Detailed) { 'Detailed' } else { 'Normal' }
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'NUnitXml'
$config.TestResult.OutputPath = Join-Path $PSScriptRoot 'pester-results.xml'

Write-Host "Running Pester 5.x unit-test suite (Pester $($pester.Version))..." -ForegroundColor Cyan
$result = Invoke-Pester -Configuration $config

Write-Host ""
Write-Host "Pester results: $($result.PassedCount) passed, $($result.FailedCount) failed, $($result.SkippedCount) skipped, $($result.TotalCount) total." -ForegroundColor $(if ($result.FailedCount -eq 0) { 'Green' } else { 'Red' })

if ($result.FailedCount -gt 0) {
    exit 1
}
exit 0
