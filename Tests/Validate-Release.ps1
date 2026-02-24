<#
.SYNOPSIS
    Automated pre-release validation for RackStack
.DESCRIPTION
    Runs all validation checks required before releasing a new version:
    1. Parse check (all 63 modules + monolithic)
    2. PSScriptAnalyzer (0 errors required)
    3. Module count verification
    4. Region count verification (monolithic)
    5. Sync verification (modules match monolithic)
    6. Version consistency check
    7. Required function existence
    8. Full test suite (Run-Tests.ps1)
    Results are displayed with pass/fail indicators and a final summary.
.NOTES
    Run from the RackStack directory:
    powershell -File Tests\Validate-Release.ps1
#>

param(
    [switch]$SkipTests,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"
$script:PassCount = 0
$script:FailCount = 0
$script:WarnCount = 0
$script:StartTime = Get-Date

$_vrRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$modulesDir = Join-Path $_vrRepoRoot "Modules"
$loaderPath = Join-Path $_vrRepoRoot "RackStack.ps1"
$settingsPath = Join-Path $_vrRepoRoot "PSScriptAnalyzerSettings.psd1"
$utf8Bom = New-Object System.Text.UTF8Encoding $true

# Derive monolithic path from defaults.json
$_vrDefaultsJson = Join-Path $_vrRepoRoot "defaults.json"
$_vrToolFullName = "Server Configuration Tool"
$_vrScriptVersion = "1.0.0"
if (Test-Path $_vrDefaultsJson) {
    try {
        $_vrDj = Get-Content $_vrDefaultsJson -Raw | ConvertFrom-Json
        if ($_vrDj.ToolFullName) { $_vrToolFullName = $_vrDj.ToolFullName }
    } catch { }
}
$_vrInitFile = Join-Path $modulesDir "00-Initialization.ps1"
if (Test-Path $_vrInitFile) {
    $_vrInitContent = Get-Content $_vrInitFile -Raw
    if ($_vrInitContent -match '\$script:ScriptVersion\s*=\s*"([^"]+)"') {
        $_vrScriptVersion = $Matches[1]
    }
}
$monoPath = Join-Path (Split-Path $_vrRepoRoot) "$_vrToolFullName v$_vrScriptVersion.ps1"

function Write-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail = "")
    if ($Passed) {
        $script:PassCount++
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    } else {
        $script:FailCount++
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
    }
    if ($Detail -and $Verbose) {
        Write-Host "         $Detail" -ForegroundColor DarkGray
    }
}

function Write-Warning-Check {
    param([string]$Name, [string]$Detail = "")
    $script:WarnCount++
    Write-Host "  [WARN] $Name" -ForegroundColor Yellow
    if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkGray }
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ">>> $Title" -ForegroundColor Cyan
    Write-Host ""
}

# ============================================================================
Write-Host ""
Write-Host ("=" * 72) -ForegroundColor Cyan
Write-Host "  RACKSTACK - PRE-RELEASE VALIDATION" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host ("=" * 72) -ForegroundColor Cyan

# ============================================================================
Write-Section "1. PARSE CHECK"
# ============================================================================

$moduleFiles = Get-ChildItem $modulesDir -Filter "*.ps1" | Sort-Object Name
$parseErrors = 0
foreach ($f in $moduleFiles) {
    $e = $null
    [System.Management.Automation.PSParser]::Tokenize((Get-Content $f.FullName -Raw), [ref]$e) | Out-Null
    if ($e.Count -gt 0) {
        Write-Check "$($f.Name): parse" $false "Line $($e[0].Token.StartLine): $($e[0].Message)"
        $parseErrors++
    }
}
if ($parseErrors -eq 0) {
    Write-Check "All $($moduleFiles.Count) modules parse cleanly" $true
} else {
    Write-Check "$parseErrors module(s) have parse errors" $false
}

# Monolithic parse
$e = $null
[System.Management.Automation.PSParser]::Tokenize(([System.IO.File]::ReadAllText($monoPath, $utf8Bom)), [ref]$e) | Out-Null
Write-Check "Monolithic script parses cleanly" ($e.Count -eq 0) "$(if($e.Count -gt 0){"$($e.Count) errors, first at line $($e[0].Token.StartLine)"})"

# ============================================================================
Write-Section "2. PSSCRIPTANALYZER"
# ============================================================================

$pssaAvailable = $null -ne (Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue)
if (-not $pssaAvailable) {
    try { Import-Module PSScriptAnalyzer -ErrorAction Stop; $pssaAvailable = $true } catch { }
}

if ($pssaAvailable) {
    $settingsFile = if (Test-Path $settingsPath) { $settingsPath } else { $null }
    $pssaParams = @{ Path = $modulesDir; Recurse = $true; Severity = "Error" }
    if ($settingsFile) { $pssaParams.Settings = $settingsFile }
    $pssaErrors = @(Invoke-ScriptAnalyzer @pssaParams)
    Write-Check "PSScriptAnalyzer: 0 errors on modules" ($pssaErrors.Count -eq 0) "$($pssaErrors.Count) error(s)"
    if ($pssaErrors.Count -gt 0) {
        foreach ($err in $pssaErrors | Select-Object -First 5) {
            Write-Host "         $($err.ScriptName):$($err.Line) - $($err.Message)" -ForegroundColor Red
        }
    }

    $pssaMonoErrors = @(Invoke-ScriptAnalyzer -Path $monoPath -Severity Error)
    Write-Check "PSScriptAnalyzer: 0 errors on monolithic" ($pssaMonoErrors.Count -eq 0) "$($pssaMonoErrors.Count) error(s)"
} else {
    Write-Warning-Check "PSScriptAnalyzer not installed - skipping" "Install-Module PSScriptAnalyzer"
}

# ============================================================================
Write-Section "3. MODULE STRUCTURE"
# ============================================================================

$expectedModuleCount = 63
Write-Check "Module count: $($moduleFiles.Count) files (expected $expectedModuleCount)" ($moduleFiles.Count -eq $expectedModuleCount)

# Verify loader lists all modules
$loaderContent = Get-Content $loaderPath -Raw
$loaderModules = [regex]::Matches($loaderContent, '"(\d{2}-[^"]+\.ps1)"') | ForEach-Object { $_.Groups[1].Value }
Write-Check "Loader references $($loaderModules.Count) modules" ($loaderModules.Count -eq $expectedModuleCount)

# Check each loader module exists on disk
$missingModules = $loaderModules | Where-Object { -not (Test-Path (Join-Path $modulesDir $_)) }
Write-Check "All loader-referenced modules exist on disk" ($missingModules.Count -eq 0) "Missing: $($missingModules -join ', ')"

# Check for orphan files (on disk but not in loader)
$loaderSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$loaderModules, [System.StringComparer]::OrdinalIgnoreCase)
$orphanFiles = $moduleFiles | Where-Object { -not $loaderSet.Contains($_.Name) }
Write-Check "No orphan module files (all on disk are in loader)" ($orphanFiles.Count -eq 0) "Orphans: $($orphanFiles.Name -join ', ')"

# ============================================================================
Write-Section "4. REGION INTEGRITY"
# ============================================================================

$monoContent = [System.IO.File]::ReadAllLines($monoPath, $utf8Bom)
$regionStarts = @($monoContent | Where-Object { $_ -match '^\s*#region\s+' }).Count
$regionEnds = @($monoContent | Where-Object { $_ -match '^\s*#endregion' }).Count
Write-Check "Region pairs balanced: $regionStarts starts, $regionEnds ends" ($regionStarts -eq $regionEnds)

# Each module should have a matching region
$moduleRegions = @{}
foreach ($f in $moduleFiles) {
    $firstLine = (Get-Content $f.FullName -First 1).Trim()
    if ($firstLine -match '^#region\s+(.+)$') {
        $moduleRegions[$f.Name] = $Matches[1].Trim()
    }
}
$modulesWithRegions = $moduleRegions.Count
Write-Check "Modules with #region headers: $modulesWithRegions/$($moduleFiles.Count)" ($modulesWithRegions -eq $moduleFiles.Count)

# ============================================================================
Write-Section "5. VERSION CONSISTENCY"
# ============================================================================

# Get version from 00-Initialization
$initContent = Get-Content (Join-Path $modulesDir "00-Initialization.ps1") -Raw
$versionMatch = [regex]::Match($initContent, '\$script:ScriptVersion\s*=\s*"([^"]+)"')
$moduleVersion = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { "UNKNOWN" }
Write-Check "Module version: $moduleVersion" ($versionMatch.Success)

# Verify monolithic filename matches
$monoFileName = [System.IO.Path]::GetFileNameWithoutExtension($monoPath)
$monoHasVersion = $monoFileName -match [regex]::Escape($moduleVersion)
Write-Check "Monolithic filename contains version $moduleVersion" $monoHasVersion

# Verify loader version
$loaderHasVersion = $loaderContent -match [regex]::Escape($moduleVersion)
Write-Check "Loader script references version $moduleVersion" $loaderHasVersion

# Verify Header.ps1 version matches
$headerPath = Join-Path $_vrRepoRoot "Header.ps1"
if (Test-Path $headerPath) {
    $headerContent = Get-Content $headerPath -Raw
    $headerVersionMatch = [regex]::Match($headerContent, '\.VERSION\s+(\S+)')
    $headerVersion = if ($headerVersionMatch.Success) { $headerVersionMatch.Groups[1].Value } else { "UNKNOWN" }
    Write-Check "Header.ps1 .VERSION matches ($headerVersion)" ($headerVersion -eq $moduleVersion)
} else {
    Write-Check "Header.ps1 exists" $false
}

# Verify Run-Tests.ps1 synopsis version matches
$testRunnerPath = Join-Path $PSScriptRoot "Run-Tests.ps1"
if (Test-Path $testRunnerPath) {
    $testContent = Get-Content $testRunnerPath -Raw
    $testHasVersion = $testContent -match [regex]::Escape("v$moduleVersion")
    Write-Check "Run-Tests.ps1 synopsis references v$moduleVersion" $testHasVersion
} else {
    Write-Check "Run-Tests.ps1 exists" $false
}

# ============================================================================
Write-Section "6. SYNC VERIFICATION"
# ============================================================================

# Spot-check: verify key functions exist in both modules and monolithic
$spotCheckFunctions = @(
    "Test-FeaturePrerequisites",
    "Show-PreFlightCheck",
    "Show-RoleTemplates",
    "Show-AuditLog",
    "Show-ServerReadiness",
    "Show-QuickSetupWizard",
    "Write-MenuItem",
    "Test-WindowsServer",
    "Get-CachedValue"
)
$monoRaw = [System.IO.File]::ReadAllText($monoPath, $utf8Bom)
$syncIssues = 0
foreach ($func in $spotCheckFunctions) {
    $inMono = $monoRaw -match "function $func"
    if (-not $inMono) {
        Write-Check "Sync: $func in monolithic" $false
        $syncIssues++
    }
}
if ($syncIssues -eq 0) {
    Write-Check "Sync spot-check: all $($spotCheckFunctions.Count) key functions in monolithic" $true
}

# Line count comparison
$monoLineCount = $monoContent.Count
Write-Host "  [INFO] Monolithic: $monoLineCount lines" -ForegroundColor DarkGray

# ============================================================================
Write-Section "7. DEFAULTS & CONFIGURATION"
# ============================================================================

$defaultsPath = Join-Path $PSScriptRoot "..\defaults.json"
$defaultsExists = Test-Path $defaultsPath
Write-Check "defaults.json exists" $defaultsExists

if ($defaultsExists) {
    try {
        $defaults = Get-Content $defaultsPath -Raw | ConvertFrom-Json
        Write-Check "defaults.json is valid JSON" $true
        Write-Check "defaults.json has FileServer config" ($null -ne $defaults.FileServer)
        Write-Check "defaults.json has Domain field" ($null -ne $defaults.Domain)
        Write-Check "defaults.json has iSCSISubnet field" ($null -ne $defaults.iSCSISubnet)
    } catch {
        Write-Check "defaults.json is valid JSON" $false $_.Exception.Message
    }
}

# ============================================================================
Write-Section "8. CONSTANTS VERIFICATION"
# ============================================================================

$constantChecks = @(
    @{ Pattern = '\$script:PowerPlanGUID'; File = '00-Initialization.ps1'; Desc = 'PowerPlanGUID centralized' },
    @{ Pattern = '\$script:WindowsLicensingAppId'; File = '00-Initialization.ps1'; Desc = 'WindowsLicensingAppId centralized' },
    @{ Pattern = '\$script:CacheTTLMinutes'; File = '00-Initialization.ps1'; Desc = 'CacheTTLMinutes defined' },
    @{ Pattern = '\$script:FeatureInstallTimeoutSeconds'; File = '00-Initialization.ps1'; Desc = 'FeatureInstallTimeoutSeconds defined' }
)
foreach ($check in $constantChecks) {
    $content = Get-Content (Join-Path $modulesDir $check.File) -Raw
    $found = $content -match [regex]::Escape($check.Pattern.Replace('\',''))
    Write-Check $check.Desc $found
}

# ============================================================================
Write-Section "9. CONTENT INTEGRITY"
# ============================================================================

# Only scan git-tracked files (excludes defaults.json, local/, etc.)
$scanDir = $_vrRepoRoot
$trackedFiles = & git -C $scanDir ls-files --cached -- "*.ps1" "*.md" "*.json" "*.yml" 2>$null
$scanFiles = $trackedFiles | ForEach-Object { Join-Path $scanDir $_ } | Where-Object { Test-Path $_ }

# Blocked-term scan A (patterns split to avoid self-match)
$blockedA = @("clau" + "de", "anthro" + "pic", "copi" + "lot", "Co-Authored" + "-By")
$hitsA = 0
foreach ($f in $scanFiles) {
    $fc = Get-Content $f -Raw -ErrorAction SilentlyContinue
    if ($fc) {
        foreach ($pat in $blockedA) {
            if ($fc -match $pat) {
                $hitsA++
                if ($Verbose) { Write-Host "         Hit: $(Split-Path $f -Leaf)" -ForegroundColor DarkGray }
                break
            }
        }
    }
}
Write-Check "Content scan A: 0 blocked terms ($($scanFiles.Count) files)" ($hitsA -eq 0) "$hitsA file(s) matched"

# Blocked-term scan B (case-sensitive, word boundaries to avoid false positives)
$blockedB = @("Eth" + "os", "\bNV" + "A\b", "anab" + "ider")
$hitsB = 0
foreach ($f in $scanFiles) {
    $fc = Get-Content $f -Raw -ErrorAction SilentlyContinue
    if ($fc) {
        foreach ($pat in $blockedB) {
            if ($fc -cmatch $pat) {
                $hitsB++
                if ($Verbose) { Write-Host "         Hit: $(Split-Path $f -Leaf)" -ForegroundColor DarkGray }
                break
            }
        }
    }
}
Write-Check "Content scan B: 0 blocked terms ($($scanFiles.Count) files)" ($hitsB -eq 0) "$hitsB file(s) matched"

# ============================================================================
Write-Section "10. AUTOMATED TEST SUITE"
# ============================================================================

if ($SkipTests) {
    Write-Warning-Check "Test suite skipped (-SkipTests flag)"
} else {
    Write-Host "  Running full test suite..." -ForegroundColor DarkGray
    $testScript = Join-Path $PSScriptRoot "Run-Tests.ps1"
    if (Test-Path $testScript) {
        $testOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $testScript 2>&1
        $testOutputStr = $testOutput -join "`n"

        # Parse results from output
        $totalMatch = [regex]::Match($testOutputStr, 'Total Tests:\s+(\d+)')
        $passMatch = [regex]::Match($testOutputStr, 'Passed:\s+(\d+)')
        $failMatch = [regex]::Match($testOutputStr, 'Failed:\s+(\d+)')

        $totalTests = if ($totalMatch.Success) { [int]$totalMatch.Groups[1].Value } else { 0 }
        $passTests = if ($passMatch.Success) { [int]$passMatch.Groups[1].Value } else { 0 }
        $failTests = if ($failMatch.Success) { [int]$failMatch.Groups[1].Value } else { 0 }

        Write-Check "Test suite: $passTests/$totalTests passed, $failTests failed" ($failTests -eq 0) ""

        if ($failTests -gt 0) {
            $failLines = $testOutput | Where-Object { $_ -match '^\[FAIL\]' -or $_ -match '^\s+- ' }
            foreach ($line in $failLines | Select-Object -First 10) {
                Write-Host "         $line" -ForegroundColor Red
            }
        }
    } else {
        Write-Check "Test suite found at $testScript" $false
    }
}

# ============================================================================
# FINAL SUMMARY
# ============================================================================

$elapsed = (Get-Date) - $script:StartTime
Write-Host ""
Write-Host ("=" * 72) -ForegroundColor Cyan
Write-Host "  VALIDATION SUMMARY" -ForegroundColor Cyan
Write-Host ("=" * 72) -ForegroundColor Cyan
Write-Host ""
Write-Host "  Passed:   $($script:PassCount)" -ForegroundColor Green
Write-Host "  Failed:   $($script:FailCount)" -ForegroundColor $(if ($script:FailCount -gt 0) { "Red" } else { "Green" })
Write-Host "  Warnings: $($script:WarnCount)" -ForegroundColor $(if ($script:WarnCount -gt 0) { "Yellow" } else { "Green" })
Write-Host ""
Write-Host "  Elapsed:  $([math]::Round($elapsed.TotalSeconds, 1)) seconds" -ForegroundColor DarkGray
Write-Host ""

if ($script:FailCount -eq 0) {
    Write-Host "  RELEASE VALIDATION PASSED" -ForegroundColor Green
} else {
    Write-Host "  RELEASE VALIDATION FAILED - $($script:FailCount) issue(s) must be resolved" -ForegroundColor Red
}

Write-Host ""
Write-Host ("=" * 72) -ForegroundColor Cyan
Write-Host ""

exit $script:FailCount
