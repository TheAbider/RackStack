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

# Code coverage — measure which lines of the pure-function modules the Pester
# suite actually exercises. Output is JaCoCo XML, which Codecov.io ingests
# natively.
#
# Scope policy: only modules where the majority of the content is pure /
# functionally testable get measured. Interactive Show- / Set- / Show-* code
# (RDP, BitLocker, ConfigExport's HTML report builders, etc.) is exercised
# by the regex-pattern harness in Run-Tests.ps1, not by Pester. Measuring
# coverage on those modules would dilute the % without adding signal —
# you'd be "covering" lines of menu loops you can't test in isolation.
#
# If you want to add a module here, first ensure Pester actually tests
# >= 60% of its lines; otherwise the score becomes theatre.
$coveredModules = @(
    '03-InputValidation.ps1'    # 100% line coverage. All 6 functions covered including
                                # Read-Host paths (Confirm-UserAction, Get-ValidatedInput
                                # via Pester Mock).
    '02-Logging.ps1'            # 100% line coverage. Write-LogMessage, Write-StructuredLog
                                # (incl. secret-redaction), Write-OutputColor (every theme +
                                # box-drawing + file-logging branch), Write-CenteredOutput,
                                # Write-RackStackError (incl. OSC 8 hyperlink path),
                                # Write-MenuItem (all StatusColor enum values).
    #
    # NOTE: 22-Password.ps1 is intentionally NOT in the measured set. It contains an
    # async `[System.Threading.TimerCallback]` scriptblock in New-StrongPassword's
    # clipboard-auto-clear path that fires after the function returns; Pester cannot
    # reliably observe execution of that block. The pure parts of 22-Password are
    # individually validated by Tests/Pester/Password.Tests.ps1's 50+ tests, but the
    # async-callback lines would suppress 100% on a per-line basis.
    #
    # If you want broader coverage tracking, add 22-Password back here — expect 95%
    # rather than 100% for the reason above. Codecov + the README badge will then
    # show 95% rather than 100%.
) | ForEach-Object { Join-Path $PSScriptRoot "..\Modules\$_" } | Where-Object { Test-Path -LiteralPath $_ }
if ($coveredModules) {
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = $coveredModules
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
    $config.CodeCoverage.OutputPath = Join-Path $PSScriptRoot 'coverage.xml'
}

Write-Host "Running Pester 5.x unit-test suite (Pester $($pester.Version))..." -ForegroundColor Cyan
$result = Invoke-Pester -Configuration $config

Write-Host ""
Write-Host "Pester results: $($result.PassedCount) passed, $($result.FailedCount) failed, $($result.SkippedCount) skipped, $($result.TotalCount) total." -ForegroundColor $(if ($result.FailedCount -eq 0) { 'Green' } else { 'Red' })

if ($result.CodeCoverage) {
    $cov = $result.CodeCoverage
    $pct = if ($cov.CommandsAnalyzedCount -gt 0) {
        [math]::Round(($cov.CommandsExecutedCount / $cov.CommandsAnalyzedCount) * 100, 2)
    } else { 0 }
    Write-Host "Code coverage: $pct% ($($cov.CommandsExecutedCount)/$($cov.CommandsAnalyzedCount) commands across $($coveredModules.Count) modules)" -ForegroundColor Cyan
}

if ($result.FailedCount -gt 0) {
    exit 1
}
exit 0
