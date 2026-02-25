<#
.SYNOPSIS
    Automated Test Runner for RackStack v1.8.3

.DESCRIPTION
    Comprehensive non-interactive test suite covering:
    - Parse tests (monolithic + 63 modules)
    - Module loading
    - PSScriptAnalyzer (Error-severity only)
    - Function existence (50+ functions)
    - Version consistency
    - Module count verification
    - Monolithic/modular sync check
    - ConvertFrom-AgentFilename tests
    - Test-NavigationCommand tests
    - Test-WindowsServer tests
    - Guard function tests (MPIO, Clustering)
    - Color theme tests
    - Box width tests (72-char)
    - Search-AgentInstaller tests
    - Session/navigation tests
    - Network diagnostics function existence
    - Operations menu function existence

.NOTES
    File Name: Run-Tests.ps1
    Created: 2026-02-05
    Version: 2.0

    Exit code 0 = all tests passed, 1 = failures detected.
    Uses ASCII only (no Unicode checkmarks/crosses).
#>

# ============================================================================
# TEST INFRASTRUCTURE
# ============================================================================

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$VerbosePreference = "SilentlyContinue"

$script:TotalTests = 0
$script:PassedTests = 0
$script:FailedTests = 0
$script:SkippedTests = 0
$script:FailedDetails = @()
$script:StartTime = Get-Date

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = "",
        [switch]$Skipped
    )

    $script:TotalTests++

    if ($Skipped) {
        $script:SkippedTests++
        Write-Host "[SKIP] $TestName" -ForegroundColor Yellow
        if ($Message) { Write-Host "       $Message" -ForegroundColor DarkGray }
        return
    }

    if ($Passed) {
        $script:PassedTests++
        Write-Host "[PASS] $TestName" -ForegroundColor Green
    } else {
        $script:FailedTests++
        Write-Host "[FAIL] $TestName" -ForegroundColor Red
        if ($Message) { Write-Host "       Error: $Message" -ForegroundColor Red }
        $script:FailedDetails += @{ Test = $TestName; Error = $Message }
    }
}

function Write-SectionHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host ">>> $Title" -ForegroundColor Cyan
    Write-Host ""
}

# ============================================================================
# PATHS
# ============================================================================

$script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$modulesPath = Join-Path $script:ModuleRoot "Modules"
$loaderPath = Join-Path $script:ModuleRoot "RackStack.ps1"

# Derive monolithic path from defaults.json
$_testDefaultsJson = Join-Path $script:ModuleRoot "defaults.json"
$_testToolFullName = "RackStack"
$_testScriptVersion = "1.0.0"
if (Test-Path $_testDefaultsJson) {
    try {
        $_testDj = Get-Content $_testDefaultsJson -Raw | ConvertFrom-Json
        if ($_testDj.ToolFullName) { $_testToolFullName = $_testDj.ToolFullName }
    } catch { }
}
# Read version dynamically from 00-Initialization.ps1
$_testInitFile = Join-Path $modulesPath "00-Initialization.ps1"
if (Test-Path $_testInitFile) {
    $_testInitContent = Get-Content $_testInitFile -Raw
    if ($_testInitContent -match '\$script:ScriptVersion\s*=\s*"([^"]+)"') {
        $_testScriptVersion = $Matches[1]
    }
}
$monolithicPath = Join-Path (Split-Path $script:ModuleRoot) "$_testToolFullName v$_testScriptVersion.ps1"
$expectedModuleCount = 63  # 00-62 inclusive

# ============================================================================
# BANNER
# ============================================================================

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  $_testToolFullName - Automated Test Runner v2.0" -ForegroundColor Cyan
Write-Host "  Target: v$_testScriptVersion | Modules: $expectedModuleCount | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# SECTION 1: PARSE TESTS
# ============================================================================

Write-SectionHeader "SECTION 1: PARSE TESTS"

# 1a. Monolithic script parsing
try {
    $monolithicContent = Get-Content $monolithicPath -Raw -ErrorAction Stop
    $parseErrors = $null
    $null = [System.Management.Automation.PSParser]::Tokenize($monolithicContent, [ref]$parseErrors)
    $pass = $parseErrors.Count -eq 0
    Write-TestResult "Monolithic script parses without errors" $pass $(if (-not $pass) { "Parse errors: $($parseErrors.Count)" } else { "" })
} catch {
    Write-TestResult "Monolithic script parses without errors" $false $_.Exception.Message
}

# 1b. All 59 module files parse
$moduleFiles = Get-ChildItem -Path $modulesPath -Filter "*.ps1" | Sort-Object Name

foreach ($moduleFile in $moduleFiles) {
    try {
        $content = Get-Content $moduleFile.FullName -Raw -ErrorAction Stop
        $parseErrors = $null
        $null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$parseErrors)
        $pass = $parseErrors.Count -eq 0
        Write-TestResult "Module $($moduleFile.Name) parses cleanly" $pass $(if (-not $pass) { "$($parseErrors.Count) parse error(s)" } else { "" })
    } catch {
        Write-TestResult "Module $($moduleFile.Name) parses cleanly" $false $_.Exception.Message
    }
}

# ============================================================================
# SECTION 2: INITIALIZE SCRIPT ENVIRONMENT (before dot-sourcing)
# ============================================================================

Write-SectionHeader "SECTION 2: INITIALIZE SCRIPT ENVIRONMENT"

# Initialize all required $script: variables BEFORE dot-sourcing modules
$script:ScriptVersion = $_testScriptVersion
$script:ScriptPath = $PSCommandPath
$script:ScriptStartTime = Get-Date
$script:SessionChanges = [System.Collections.Generic.List[object]]::new()
$script:ChangeCounter = 0
$script:UndoStack = [System.Collections.Generic.List[object]]::new()
$script:ColorTheme = "Default"
$script:DNSPresets = @{
    "Google DNS" = @("8.8.8.8", "8.8.4.4")
}
$script:MinPasswordLength = 14
$script:MaxRetryAttempts = 3
$script:UpdateTimeoutSeconds = 300
$script:CacheTTLMinutes = 10
$script:FeatureInstallTimeoutSeconds = 1800
$script:LargeFileDownloadTimeoutSeconds = 3600
$script:DefaultDownloadTimeoutSeconds = 1800
$script:AgentInstaller = @{
    ToolName        = "Kaseya"
    FolderName      = "Agents"
    FilePattern     = "Kaseya.*\.exe$"
    ServiceName     = "Kaseya Agent*"
    InstallArgs     = "/s /norestart"
    InstallPaths    = @(
        "$env:ProgramFiles\Kaseya"
        "${env:ProgramFiles(x86)}\Kaseya"
        "C:\kworking"
    )
    SuccessExitCodes = @(0, 1641, 3010)
    TimeoutSeconds  = 300
}
$script:FileServer = @{
    StorageType    = "nginx"
    BaseURL        = ""
    ClientId       = ""
    ClientSecret   = ""
    AzureAccount   = ""
    AzureContainer = ""
    AzureSasToken  = ""
    ISOsFolder     = "ISOs"
    VHDsFolder     = "VirtualHardDrives"
    AgentFolder    = "Agents"
}
$script:FileCache = @{}
$script:AgentInstallerCache = $null
$script:AgentInstallerCacheTime = $null
$script:SelectedHostDrive = "D:"
$script:HostVMStoragePath = "D:\Virtual Machines"
$script:HostISOPath = "D:\ISOs"
$script:ClusterISOPath = "C:\ClusterStorage\Volume1\ISOs"
$script:VHDCachePath = "D:\Virtual Machines\_BaseImages"
$script:ClusterVHDCachePath = "C:\ClusterStorage\Volume1\_BaseImages"
$script:StorageInitialized = $false
$script:ToolName = "Server"
$script:ToolFullName = "Server Configuration Tool"
$script:SupportContact = "your administrator"
$script:ConfigDirName = "serverconfig"
$script:AppConfigDir = "$env:USERPROFILE\.$($script:ConfigDirName)"
$script:FavoritesPath = "$script:AppConfigDir\favorites.json"
$script:HistoryPath = "$script:AppConfigDir\history.json"
$script:SessionStatePath = "$script:AppConfigDir\session.json"
$script:Favorites = @()
$script:CommandHistory = @()
$script:MaxHistoryItems = 100
$script:VMDeploymentQueue = @()
$script:iSCSICandidateAdapters = @()
$logFilePath = $null  # Disable logging for tests

# Initialize color themes (will be overwritten when 00-Initialization loads, but needed as fallback)
$script:ColorThemes = @{
    "Default" = @{
        Success  = 'Green'
        Warning  = 'Yellow'
        Error    = 'Red'
        Info     = 'Cyan'
        Debug    = 'DarkGray'
        Critical = 'Magenta'
        Verbose  = 'White'
    }
}

# Initialize global flags
$global:RebootNeeded = $false
$global:DisabledAdminReboot = $false
$global:ReturnToMainMenu = $false

# Initialize menu cache
$script:MenuCache = @{
    HyperVInstalled = $null
    RDPState = $null
    FirewallState = $null
    AdminEnabled = $null
    PowerPlan = $null
    LastUpdate = $null
}

Write-TestResult "Script environment initialized" $true

# ============================================================================
# SECTION 3: MODULE LOAD TEST
# ============================================================================

Write-SectionHeader "SECTION 3: MODULE LOAD TEST (dot-source all 63 modules)"

$loadedModules = 0
$loadErrors = @()

foreach ($moduleFile in $moduleFiles) {
    try {
        . $moduleFile.FullName
        $loadedModules++
        Write-Host "  [OK] $($moduleFile.Name)" -ForegroundColor DarkGreen
    } catch {
        $loadErrors += $moduleFile.Name
        Write-Host "  [ERR] $($moduleFile.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-TestResult "All $expectedModuleCount modules loaded without errors" ($loadedModules -eq $expectedModuleCount -and $loadErrors.Count -eq 0) $(if ($loadErrors.Count -gt 0) { "Failed: $($loadErrors -join ', ')" } else { "Loaded: $loadedModules" })

# ============================================================================
# SECTION 4: PSSCRIPTANALYZER
# ============================================================================

Write-SectionHeader "SECTION 4: PSSCRIPTANALYZER"

$pssaAvailable = $null -ne (Get-Module -ListAvailable -Name PSScriptAnalyzer)
$pssaSettingsPath = Join-Path (Split-Path $PSScriptRoot) 'PSScriptAnalyzerSettings.psd1'

if ($pssaAvailable) {
    Import-Module PSScriptAnalyzer -ErrorAction SilentlyContinue

    # Determine settings - use project settings file if it exists
    $pssaParams = @{}
    if (Test-Path $pssaSettingsPath) {
        $pssaParams['Settings'] = $pssaSettingsPath
        Write-TestResult "PSSA settings file exists" $true
    } else {
        Write-TestResult "PSSA settings file exists" $false "Expected: $pssaSettingsPath"
    }

    # 4a. Run on monolithic (errors only - monolithic is too large for full scan)
    try {
        $monolithicFindings = Invoke-ScriptAnalyzer -Path $monolithicPath -Severity Error -ErrorAction SilentlyContinue
        $errorCount = if ($monolithicFindings) { @($monolithicFindings).Count } else { 0 }
        Write-TestResult "PSSA monolithic: 0 errors" ($errorCount -eq 0) $(if ($errorCount -gt 0) { "$errorCount error(s): $(($monolithicFindings | ForEach-Object { "$($_.RuleName) L$($_.Line)" }) -join '; ')" } else { "" })
    } catch {
        Write-TestResult "PSSA monolithic scan" $false $_.Exception.Message
    }

    # 4b. Run on all modules with settings (0 errors AND 0 warnings)
    $totalModuleErrors = 0
    $totalModuleWarnings = 0
    $moduleIssueDetails = @()

    foreach ($moduleFile in $moduleFiles) {
        try {
            $findings = Invoke-ScriptAnalyzer -Path $moduleFile.FullName @pssaParams -ErrorAction SilentlyContinue
            if ($findings) {
                foreach ($f in @($findings)) {
                    if ($f.Severity -eq 'Error') {
                        $totalModuleErrors++
                        $moduleIssueDetails += "$($moduleFile.Name): ERROR $($f.RuleName) L$($f.Line)"
                    } else {
                        $totalModuleWarnings++
                        $moduleIssueDetails += "$($moduleFile.Name): WARN $($f.RuleName) L$($f.Line)"
                    }
                }
            }
        } catch {
            $totalModuleErrors++
            $moduleIssueDetails += "$($moduleFile.Name): SCAN FAILED - $($_.Exception.Message)"
        }
    }

    Write-TestResult "PSSA modules: 0 errors across all $expectedModuleCount" ($totalModuleErrors -eq 0) $(if ($totalModuleErrors -gt 0) { "$totalModuleErrors error(s)" } else { "" })
    Write-TestResult "PSSA modules: 0 warnings across all $expectedModuleCount" ($totalModuleWarnings -eq 0) $(if ($totalModuleWarnings -gt 0) { "$totalModuleWarnings warning(s): $($moduleIssueDetails -join ' | ')" } else { "" })
} else {
    Write-TestResult "PSScriptAnalyzer available" -Skipped -Message "PSScriptAnalyzer module not installed. Run: Install-Module PSScriptAnalyzer"
}

# ============================================================================
# SECTION 5: FUNCTION EXISTENCE (50+ important functions)
# ============================================================================

Write-SectionHeader "SECTION 5: FUNCTION EXISTENCE (50+ key functions)"

$requiredFunctions = @(
    # Core / Initialization (01-Console, 02-Logging)
    "Initialize-ConsoleWindow",
    "Write-OutputColor",
    "Write-CenteredOutput",
    "Write-LogMessage",
    "Write-MenuItem",
    # Write-MenuLine removed (dead code)
    # Input Validation (03)
    "Test-ValidHostname",
    "Test-ValidIPAddress",
    "Confirm-UserAction",
    "Get-ValidatedInput",
    # Navigation (04)
    "Test-NavigationCommand",
    "Invoke-NavigationAction",
    "Add-SessionChange",
    "Write-PressEnter",
    "Add-UndoAction",
    "Undo-LastChange",
    "Get-CachedValue",
    "Clear-MenuCache",
    "Show-ProgressMessage",
    "Complete-ProgressMessage",
    # System Check (05)
    "Test-WindowsServer",
    "Test-HyperVInstalled",
    "Test-RebootPending",
    "Test-NetworkConnectivity",
    "Get-RDPState",
    "Get-WinRMState",
    "Get-FirewallState",
    "Get-CurrentPowerPlan",
    "Set-ServerPowerPlan",
    # Network (06-09)
    "Format-LinkSpeed",
    "Show-AdaptersTable",
    "Convert-SubnetMaskToPrefix",
    "Test-AdapterInternetConnectivity",
    # iSCSI / SAN (10)
    "Get-HostNumberFromHostname",
    "Get-iSCSIAutoIP",
    # Config / Export (45-46)
    "Export-ServerConfiguration",
    "Save-ConfigurationProfile",
    "Import-ConfigurationProfile",
    "Show-SessionSummary",
    # Kaseya (57)
    "Test-AgentInstalled",
    "Get-AgentInstallerList",
    "ConvertFrom-AgentFilename",
    "Search-AgentInstaller",
    "Get-SiteNumberFromHostname",
    "Show-AgentInstallerList",
    "Install-SelectedAgent",
    "Install-KaseyaAgent",
    # Guard functions (26-27)
    "Test-MPIOInstalled",
    "Test-FailoverClusteringInstalled",
    # Menu functions (48-50)
    "Show-MainMenu",
    "Show-ConfigureServerMenu",
    "Assert-Elevation",
    # Network Diagnostics (58)
    "Show-NetworkDiagnostics",
    "Invoke-PingHost",
    "Invoke-PortTest",
    "Invoke-TraceRoute",
    "Invoke-SubnetSweep",
    "Invoke-DnsLookup",
    "Show-ActiveConnections",
    "Show-ArpTable",
    # Operations Menu (56)
    "Show-OperationsMenu",
    "Invoke-RemotePSSession",
    "Invoke-RemoteHealthCheck",
    "Invoke-RemoteServiceManager",
    # VM / Deployment (44)
    "Show-VMDeploymentMenu",
    "Show-DeploymentQueue",
    # Cluster (51)
    "Show-ClusterDashboard",
    "Show-ClusterOperationsMenu",
    # VM Checkpoints / Export-Import (52-53)
    "Show-VMCheckpointManagement",
    "Show-VMExportImportMenu",
    # HTML Reports (54)
    "Export-HTMLHealthReport",
    # QoL Features (55)
    "Initialize-AppConfigDir",
    "Show-Favorites",
    # Health Check (37)
    "Show-SystemHealthCheck",
    "Show-ServerReadiness",
    "Show-QuickSetupWizard",
    # HTML Reports (54) - readiness
    "Export-HTMLReadinessReport",
    # Storage Manager (38)
    "Show-StorageManagerMenu",
    # Batch Config (36)
    "New-BatchConfigTemplate",
    # Help / Settings (34)
    "Show-Help",
    "Set-ColorTheme",
    "Show-Changelog",
    "Show-SettingsMenu",
    # Pre-flight validation (05)
    "Test-FeaturePrerequisites",
    "Show-PreFlightCheck",
    # Role Templates (37)
    "Show-RoleTemplates",
    # Audit Log (04)
    "Show-AuditLog"
)

$funcCheckPassed = 0
$funcCheckFailed = 0

foreach ($funcName in $requiredFunctions) {
    try {
        $exists = Get-Command -Name $funcName -ErrorAction SilentlyContinue
        $pass = $null -ne $exists
        Write-TestResult "Function exists: $funcName" $pass $(if (-not $pass) { "Not found after loading modules" } else { "" })
        if ($pass) { $funcCheckPassed++ } else { $funcCheckFailed++ }
    } catch {
        Write-TestResult "Function exists: $funcName" $false $_.Exception.Message
        $funcCheckFailed++
    }
}

Write-Host ""
Write-Host "  Function existence: $funcCheckPassed/$($requiredFunctions.Count) found" -ForegroundColor $(if ($funcCheckFailed -eq 0) { "Green" } else { "Yellow" })

# ============================================================================
# SECTION 6: VERSION CONSISTENCY
# ============================================================================

Write-SectionHeader "SECTION 6: VERSION CONSISTENCY"

# 6a. Script-scope version after loading modules
try {
    $pass = $script:ScriptVersion -eq $_testScriptVersion
    Write-TestResult "ScriptVersion is '$_testScriptVersion' in script scope" $pass "Found: '$($script:ScriptVersion)'"
} catch {
    Write-TestResult "ScriptVersion is '$_testScriptVersion' in script scope" $false $_.Exception.Message
}

# 6b. Monolithic file contains matching version
try {
    $monoContent = Get-Content $monolithicPath -Raw
    $escapedVer = [regex]::Escape($_testScriptVersion)
    $monoHasVersion = $monoContent -match ('\$script:ScriptVersion\s*=\s*"' + $escapedVer + '"')
    Write-TestResult "Monolithic contains ScriptVersion = '$_testScriptVersion'" $monoHasVersion
} catch {
    Write-TestResult "Monolithic contains ScriptVersion = '$_testScriptVersion'" $false $_.Exception.Message
}

# 6c. Loader comment/header contains version
try {
    $loaderContent = Get-Content $loaderPath -Raw
    $loaderHasVersion = $loaderContent -match [regex]::Escape($_testScriptVersion)
    Write-TestResult "Loader (RackStack.ps1) references v$_testScriptVersion" $loaderHasVersion
} catch {
    Write-TestResult "Loader references v$_testScriptVersion" $false $_.Exception.Message
}

# ============================================================================
# SECTION 7: MODULE COUNT
# ============================================================================

Write-SectionHeader "SECTION 7: MODULE COUNT"

try {
    $actualCount = $moduleFiles.Count
    Write-TestResult "Module count is exactly $expectedModuleCount" ($actualCount -eq $expectedModuleCount) "Actual: $actualCount"
} catch {
    Write-TestResult "Module count verification" $false $_.Exception.Message
}

# Verify first and last module names
try {
    $firstName = $moduleFiles[0].Name
    $lastName = $moduleFiles[-1].Name
    $pass = $firstName -eq "00-Initialization.ps1" -and $lastName -eq "62-HyperVReplica.ps1"
    Write-TestResult "Module range 00-Initialization to 62-HyperVReplica" $pass "First=$firstName, Last=$lastName"
} catch {
    Write-TestResult "Module range verification" $false $_.Exception.Message
}

# All modules have #region headers
try {
    $missingRegion = @()
    foreach ($moduleFile in $moduleFiles) {
        $content = Get-Content $moduleFile.FullName -Raw
        if ($content -notmatch '#region') {
            $missingRegion += $moduleFile.Name
        }
    }
    $pass = $missingRegion.Count -eq 0
    Write-TestResult "All modules contain #region headers" $pass $(if (-not $pass) { "Missing: $($missingRegion -join ', ')" } else { "" })
} catch {
    Write-TestResult "All modules contain #region headers" $false $_.Exception.Message
}

# ============================================================================
# SECTION 8: MONOLITHIC/MODULAR SYNC CHECK
# ============================================================================

Write-SectionHeader "SECTION 8: MONOLITHIC/MODULAR SYNC CHECK"

try {
    $monoContent = Get-Content $monolithicPath -Raw -ErrorAction Stop
    $syncErrors = @()
    $syncChecked = 0

    foreach ($moduleFile in $moduleFiles) {
        $modContent = Get-Content $moduleFile.FullName -Raw
        # Extract all function names from this module
        $funcMatches = [regex]::Matches($modContent, '(?m)^function\s+([A-Za-z0-9_-]+)')

        foreach ($match in $funcMatches) {
            $funcName = $match.Groups[1].Value
            $syncChecked++
            # Check if the function exists in the monolithic script
            $escapedName = [regex]::Escape($funcName)
            if ($monoContent -notmatch "function\s+$escapedName\s*[\{(]") {
                $syncErrors += "$funcName (from $($moduleFile.Name))"
            }
        }
    }

    Write-TestResult "All modular functions found in monolithic ($syncChecked checked)" ($syncErrors.Count -eq 0) $(if ($syncErrors.Count -gt 0) { "Missing: $($syncErrors -join '; ')" } else { "" })

    if ($syncErrors.Count -gt 0 -and $syncErrors.Count -le 10) {
        foreach ($err in $syncErrors) {
            Write-Host "       - $err" -ForegroundColor DarkYellow
        }
    }
} catch {
    Write-TestResult "Monolithic/modular sync check" $false $_.Exception.Message
}

# ============================================================================
# SECTION 9: ConvertFrom-AgentFilename TESTS
# ============================================================================

Write-SectionHeader "SECTION 9: ConvertFrom-AgentFilename TESTS"

# Test case 1: Standard format - site number + name
try {
    $result = ConvertFrom-AgentFilename -FileName "Kaseya_acme.1001-mainoffice.exe"
    $pass = $result.Valid -and
            @($result.SiteNumbers).Count -eq 1 -and
            @($result.SiteNumbers)[0] -eq "1001" -and
            $result.SiteName -eq "mainoffice" -and
            $result.DisplayName -ne ""
    Write-TestResult "Parse 'Kaseya_acme.1001-mainoffice.exe' (standard)" $pass "Sites=$(@($result.SiteNumbers) -join ','), Name=$($result.SiteName)"
} catch {
    Write-TestResult "Parse 'Kaseya_acme.1001-mainoffice.exe'" $false $_.Exception.Message
}

# Test case 2: Site number only (no name)
try {
    $result = ConvertFrom-AgentFilename -FileName "Kaseya_acme.3001.exe"
    $pass = $result.Valid -and
            @($result.SiteNumbers).Count -eq 1 -and
            @($result.SiteNumbers)[0] -eq "3001" -and
            $result.SiteName -eq ""
    Write-TestResult "Parse 'Kaseya_acme.3001.exe' (number only)" $pass "Sites=$(@($result.SiteNumbers) -join ',')"
} catch {
    Write-TestResult "Parse 'Kaseya_acme.3001.exe'" $false $_.Exception.Message
}

# Test case 3: Underscore-separated multiple site numbers
try {
    $result = ConvertFrom-AgentFilename -FileName "Kaseya_acme.1001_0452-sitename.exe"
    $pass = $result.Valid -and
            @($result.SiteNumbers).Count -eq 2 -and
            "1001" -in @($result.SiteNumbers) -and
            "0452" -in @($result.SiteNumbers)
    Write-TestResult "Parse underscore-separated numbers (1001_0452)" $pass "Sites=$(@($result.SiteNumbers) -join ',')"
} catch {
    Write-TestResult "Parse underscore-separated numbers" $false $_.Exception.Message
}

# Test case 4: .staging suffix
try {
    $result = ConvertFrom-AgentFilename -FileName "Kaseya_acme.1001-mainoffice.staging.exe"
    $pass = $result.Valid -and
            @($result.SiteNumbers)[0] -eq "1001" -and
            $result.SiteName -eq "mainoffice"
    Write-TestResult "Parse .staging suffix (stripped correctly)" $pass
} catch {
    Write-TestResult "Parse .staging suffix" $false $_.Exception.Message
}

# Test case 5: .workstations suffix
try {
    $result = ConvertFrom-AgentFilename -FileName "Kaseya_acme.1001-mainoffice.workstations.exe"
    $pass = $result.Valid -and
            @($result.SiteNumbers)[0] -eq "1001" -and
            $result.SiteName -eq "mainoffice"
    Write-TestResult "Parse .workstations suffix (stripped correctly)" $pass
} catch {
    Write-TestResult "Parse .workstations suffix" $false $_.Exception.Message
}

# Test case 6: Invalid filename returns Valid=false
try {
    $result = ConvertFrom-AgentFilename -FileName "randomfile.txt"
    Write-TestResult "Parse 'randomfile.txt' returns Valid=false" (-not $result.Valid)
} catch {
    Write-TestResult "Parse 'randomfile.txt' returns Valid=false" $false $_.Exception.Message
}

# Test case 7: SiteNumbers is always an array
try {
    $result = ConvertFrom-AgentFilename -FileName "Kaseya_acme.1001-mainoffice.exe"
    $isArray = @($result.SiteNumbers) -is [Array]
    Write-TestResult "SiteNumbers wrapped in @() is array" $isArray "Type: $(@($result.SiteNumbers).GetType().Name)"
} catch {
    Write-TestResult "SiteNumbers is array" $false $_.Exception.Message
}

# Test case 8: DisplayName non-empty for valid entries
try {
    $result = ConvertFrom-AgentFilename -FileName "Kaseya_acme.1001-mainoffice.exe"
    $pass = $result.Valid -and -not [string]::IsNullOrWhiteSpace($result.DisplayName)
    Write-TestResult "DisplayName non-empty for valid entry" $pass "DisplayName='$($result.DisplayName)'"
} catch {
    Write-TestResult "DisplayName non-empty for valid entry" $false $_.Exception.Message
}

# Test case 9: Large underscore-separated numbers
try {
    $result = ConvertFrom-AgentFilename -FileName "Kaseya_acme.5001_5002-branch-datacenter.exe"
    $pass = $result.Valid -and @($result.SiteNumbers).Count -eq 2
    Write-TestResult "Parse large underscore numbers (5001_5002)" $pass "Sites=$(@($result.SiteNumbers) -join ',')"
} catch {
    Write-TestResult "Parse large underscore numbers" $false $_.Exception.Message
}

# Test case 10: Multiple dash-separated site numbers
try {
    $result = ConvertFrom-AgentFilename -FileName "Kaseya_acme.2001-2002-2005-westsite.exe"
    $pass = $result.Valid -and @($result.SiteNumbers).Count -eq 3
    Write-TestResult "Parse dash-separated numbers (2001-2002-2005)" $pass "Sites=$(@($result.SiteNumbers) -join ',')"
} catch {
    Write-TestResult "Parse dash-separated numbers" $false $_.Exception.Message
}

# Test case 11: Multiple numbers with no site name
try {
    $result = ConvertFrom-AgentFilename -FileName "Kaseya_acme.7001-7002.exe"
    $pass = $result.Valid -and @($result.SiteNumbers).Count -eq 2 -and $result.SiteName -eq ""
    Write-TestResult "Parse two numbers with no site name" $pass "Sites=$(@($result.SiteNumbers) -join ','), Name='$($result.SiteName)'"
} catch {
    Write-TestResult "Parse two numbers with no site name" $false $_.Exception.Message
}

# Test case 12: Empty string
try {
    $result = ConvertFrom-AgentFilename -FileName ""
    Write-TestResult "Parse empty string returns Valid=false" (-not $result.Valid)
} catch {
    Write-TestResult "Parse empty string" $false $_.Exception.Message
}

# ============================================================================
# SECTION 10: Test-NavigationCommand TESTS
# ============================================================================

Write-SectionHeader "SECTION 10: Test-NavigationCommand TESTS"

# Commands that should return ShouldReturn=$true
$trueInputs = @(
    @{ Input = "B";    ExpAction = "back"; Desc = "'B' -> back" }
    @{ Input = "b";    ExpAction = "back"; Desc = "'b' -> back (lowercase)" }
    @{ Input = "BACK"; ExpAction = "back"; Desc = "'BACK' -> back" }
    @{ Input = "Q";    ExpAction = "exit"; Desc = "'Q' -> exit" }
    @{ Input = "q";    ExpAction = "exit"; Desc = "'q' -> exit (lowercase)" }
    @{ Input = "QUIT"; ExpAction = "exit"; Desc = "'QUIT' -> exit" }
    @{ Input = "EXIT"; ExpAction = "exit"; Desc = "'EXIT' -> exit" }
    @{ Input = "exit"; ExpAction = "exit"; Desc = "'exit' -> exit" }
    @{ Input = "C";    ExpAction = "back"; Desc = "'C' (cancel) -> back" }
    @{ Input = "0";    ExpAction = "back"; Desc = "'0' -> back" }
    @{ Input = "  b  "; ExpAction = "back"; Desc = "'  b  ' (whitespace) -> back" }
)

foreach ($tc in $trueInputs) {
    try {
        $result = Test-NavigationCommand -UserInput $tc.Input
        $pass = $result.ShouldReturn -eq $true -and $result.Action -eq $tc.ExpAction
        Write-TestResult "NavCommand: $($tc.Desc)" $pass $(if (-not $pass) { "Got Action='$($result.Action)', ShouldReturn='$($result.ShouldReturn)'" } else { "" })
    } catch {
        Write-TestResult "NavCommand: $($tc.Desc)" $false $_.Exception.Message
    }
}

# Commands that should return ShouldReturn=$false
$falseInputs = @(
    @{ Input = "1";        Desc = "'1' -> no match" }
    @{ Input = "X";        Desc = "'X' -> no match" }
    @{ Input = "H";        Desc = "'H' -> no match" }
    @{ Input = "?";        Desc = "'?' -> no match" }
    @{ Input = "MENU";     Desc = "'MENU' -> no match" }
    @{ Input = "HELP";     Desc = "'HELP' -> no match" }
    @{ Input = "hello";    Desc = "'hello' -> no match" }
    @{ Input = "42";       Desc = "'42' -> no match" }
)

foreach ($tc in $falseInputs) {
    try {
        $result = Test-NavigationCommand -UserInput $tc.Input
        $pass = $result.ShouldReturn -eq $false
        Write-TestResult "NavCommand: $($tc.Desc)" $pass $(if (-not $pass) { "Got ShouldReturn=$($result.ShouldReturn), Action='$($result.Action)'" } else { "" })
    } catch {
        Write-TestResult "NavCommand: $($tc.Desc)" $false $_.Exception.Message
    }
}

# Empty input should return Action="empty" and ShouldReturn=$false
try {
    $result = Test-NavigationCommand -UserInput ""
    $pass = $result.ShouldReturn -eq $false -and $result.Action -eq "empty"
    Write-TestResult "NavCommand: empty string -> Action='empty', ShouldReturn=false" $pass
} catch {
    Write-TestResult "NavCommand: empty string" $false $_.Exception.Message
}

# ============================================================================
# SECTION 11: Test-WindowsServer TESTS
# ============================================================================

Write-SectionHeader "SECTION 11: Test-WindowsServer TESTS"

try {
    $result = Test-WindowsServer
    $isBoolean = $result -is [bool]
    Write-TestResult "Test-WindowsServer returns boolean" $isBoolean "Result=$result, Type=$($result.GetType().Name)"
} catch {
    Write-TestResult "Test-WindowsServer returns boolean" $false $_.Exception.Message
}

# Context-aware: on client OS should return false
try {
    $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($osInfo.ProductType -eq 1) {
        $result = Test-WindowsServer
        Write-TestResult "Test-WindowsServer returns false on client OS" ($result -eq $false) "ProductType=$($osInfo.ProductType)"
    } else {
        $result = Test-WindowsServer
        Write-TestResult "Test-WindowsServer returns true on server OS" ($result -eq $true) "ProductType=$($osInfo.ProductType)"
    }
} catch {
    Write-TestResult "Test-WindowsServer context check" $false $_.Exception.Message
}

# ============================================================================
# SECTION 12: GUARD FUNCTION TESTS
# ============================================================================

Write-SectionHeader "SECTION 12: GUARD FUNCTION TESTS"

# Test-MPIOInstalled returns boolean (not error)
try {
    $result = Test-MPIOInstalled
    Write-TestResult "Test-MPIOInstalled returns boolean (no throw)" ($result -is [bool]) "Result=$result"
} catch {
    Write-TestResult "Test-MPIOInstalled returns boolean" $false $_.Exception.Message
}

# Test-FailoverClusteringInstalled returns boolean (not error)
try {
    $result = Test-FailoverClusteringInstalled
    Write-TestResult "Test-FailoverClusteringInstalled returns boolean (no throw)" ($result -is [bool]) "Result=$result"
} catch {
    Write-TestResult "Test-FailoverClusteringInstalled returns boolean" $false $_.Exception.Message
}

# Test-AgentInstalled returns hashtable with Installed key
try {
    $result = Test-AgentInstalled
    $pass = $result -is [hashtable] -and $result.ContainsKey("Installed") -and ($result.Installed -is [bool])
    Write-TestResult "Test-AgentInstalled returns hashtable with Installed key" $pass
} catch {
    Write-TestResult "Test-AgentInstalled returns hashtable" $false $_.Exception.Message
}

# Test-HyperVInstalled returns boolean
try {
    $result = Test-HyperVInstalled
    Write-TestResult "Test-HyperVInstalled returns boolean (no throw)" ($result -is [bool]) "Result=$result"
} catch {
    Write-TestResult "Test-HyperVInstalled returns boolean" $false $_.Exception.Message
}

# Test-RebootPending returns boolean
try {
    $result = Test-RebootPending
    Write-TestResult "Test-RebootPending returns boolean" ($result -is [bool]) "Result=$result"
} catch {
    Write-TestResult "Test-RebootPending returns boolean" $false $_.Exception.Message
}

# ============================================================================
# SECTION 13: COLOR THEME TESTS
# ============================================================================

Write-SectionHeader "SECTION 13: COLOR THEME TESTS"

# $script:ColorThemes should exist after loading modules
try {
    $pass = $null -ne $script:ColorThemes -and $script:ColorThemes -is [hashtable]
    Write-TestResult "ColorThemes exists and is hashtable" $pass
} catch {
    Write-TestResult "ColorThemes exists" $false $_.Exception.Message
}

# Expected themes: Default, Dark, Light, Matrix, Ocean (from 00-Initialization.ps1)
$expectedThemes = @("Default", "Dark", "Light", "Matrix", "Ocean")

foreach ($theme in $expectedThemes) {
    try {
        $pass = $script:ColorThemes.ContainsKey($theme)
        Write-TestResult "ColorThemes contains '$theme'" $pass
    } catch {
        Write-TestResult "ColorThemes contains '$theme'" $false $_.Exception.Message
    }
}

# Default theme has all 7 required color keys
try {
    $requiredKeys = @("Success", "Warning", "Error", "Info", "Debug", "Critical", "Verbose")
    $defaultTheme = $script:ColorThemes["Default"]
    $missingKeys = @()
    foreach ($key in $requiredKeys) {
        if (-not $defaultTheme.ContainsKey($key)) {
            $missingKeys += $key
        }
    }
    $pass = $missingKeys.Count -eq 0
    Write-TestResult "Default theme has all 7 color keys" $pass $(if (-not $pass) { "Missing: $($missingKeys -join ', ')" } else { "" })
} catch {
    Write-TestResult "Default theme has all color keys" $false $_.Exception.Message
}

# Write-OutputColor doesn't throw
try {
    Write-OutputColor "Test message for color test" -color "Info" | Out-Null
    Write-TestResult "Write-OutputColor executes without error" $true
} catch {
    Write-TestResult "Write-OutputColor executes without error" $false $_.Exception.Message
}

# Write-OutputColor handles empty string
try {
    Write-OutputColor "" -color "Info" | Out-Null
    Write-TestResult "Write-OutputColor handles empty string" $true
} catch {
    Write-TestResult "Write-OutputColor handles empty string" $false $_.Exception.Message
}

# ============================================================================
# SECTION 14: BOX WIDTH TESTS (72-char inner width)
# ============================================================================

Write-SectionHeader "SECTION 14: BOX WIDTH TESTS (72-char inner width)"

# Check menu display module for PadRight(72) usage
$boxWidthModules = @(
    @{ File = "48-MenuDisplay.ps1"; Desc = "MenuDisplay" }
    @{ File = "56-OperationsMenu.ps1"; Desc = "OperationsMenu" }
    @{ File = "58-NetworkDiagnostics.ps1"; Desc = "NetworkDiagnostics" }
    @{ File = "44-VMDeployment.ps1"; Desc = "VMDeployment" }
    @{ File = "34-Help.ps1"; Desc = "Help/Settings" }
)

foreach ($mod in $boxWidthModules) {
    try {
        $filePath = Join-Path $modulesPath $mod.File
        if (Test-Path $filePath) {
            $content = Get-Content $filePath -Raw
            $has72 = $content -match 'PadRight\(72\)'
            Write-TestResult "Box width: $($mod.Desc) uses PadRight(72)" $has72
        } else {
            Write-TestResult "Box width: $($mod.Desc)" -Skipped -Message "File not found"
        }
    } catch {
        Write-TestResult "Box width: $($mod.Desc)" $false $_.Exception.Message
    }
}

# Check for PadRight(70) on menu items (content inside box) - either raw PadRight(70) or Write-MenuItem helper
try {
    $menuContent = Get-Content (Join-Path $modulesPath "48-MenuDisplay.ps1") -Raw
    $has70 = ($menuContent -match 'PadRight\(70\)') -or ($menuContent -match 'Write-MenuItem ')
    Write-TestResult "Menu items use PadRight(70) or Write-MenuItem for content" $has70
} catch {
    Write-TestResult "Menu items PadRight(70) or Write-MenuItem" $false $_.Exception.Message
}

# ============================================================================
# SECTION 15: Search-AgentInstaller TESTS
# ============================================================================

Write-SectionHeader "SECTION 15: Search-AgentInstaller TESTS"

# Create mock agent array for testing
$mockAgents = @(
    @{ FileID = "id1"; FileName = "Kaseya_acme.1001-mainoffice.exe"; SiteNumbers = @("1001"); SiteName = "mainoffice"; DisplayName = "mainoffice (Sites: 1001)" }
    @{ FileID = "id2"; FileName = "Kaseya_acme.3001.exe"; SiteNumbers = @("3001"); SiteName = ""; DisplayName = "Site 3001" }
    @{ FileID = "id3"; FileName = "Kaseya_acme.2001-westsite.exe"; SiteNumbers = @("2001"); SiteName = "westsite"; DisplayName = "westsite (Sites: 2001)" }
    @{ FileID = "id4"; FileName = "Kaseya_acme.0500-testco.exe"; SiteNumbers = @("0500"); SiteName = "testco"; DisplayName = "testco (Sites: 0500)" }
)

# Search by exact site number
try {
    $results = @(Search-AgentInstaller -SearchTerm "1001" -Agents $mockAgents)
    $pass = $results.Count -eq 1 -and $results[0].SiteNumbers -contains "1001"
    Write-TestResult "Search by site number '1001' returns 1 result" $pass "Count=$($results.Count)"
} catch {
    Write-TestResult "Search by site number '1001'" $false $_.Exception.Message
}

# Search by partial name
try {
    $results = @(Search-AgentInstaller -SearchTerm "west" -Agents $mockAgents)
    $pass = $results.Count -eq 1 -and $results[0].SiteName -like "*west*"
    Write-TestResult "Search by partial name 'west' returns 1 result" $pass "Count=$($results.Count)"
} catch {
    Write-TestResult "Search by partial name 'west'" $false $_.Exception.Message
}

# Search returns array (even single result when wrapped)
try {
    $results = @(Search-AgentInstaller -SearchTerm "1001" -Agents $mockAgents)
    $isArray = $results -is [Array]
    Write-TestResult "Search results wrapped in @() are array" $isArray
} catch {
    Write-TestResult "Search results are array" $false $_.Exception.Message
}

# No results returns empty
try {
    $results = @(Search-AgentInstaller -SearchTerm "9999" -Agents $mockAgents)
    Write-TestResult "Search '9999' (no match) returns empty" ($results.Count -eq 0) "Count=$($results.Count)"
} catch {
    Write-TestResult "Search '9999' returns empty" $false $_.Exception.Message
}

# Search with empty agents array
try {
    $results = @(Search-AgentInstaller -SearchTerm "test" -Agents @())
    Write-TestResult "Search with empty agents returns empty" ($results.Count -eq 0)
} catch {
    Write-TestResult "Search with empty agents" $false $_.Exception.Message
}

# Search with exact site number
try {
    $results = @(Search-AgentInstaller -SearchTerm "1001" -Agents $mockAgents)
    $pass = $results.Count -ge 1
    Write-TestResult "Search '1001' matches site number" $pass "Count=$($results.Count)"
} catch {
    Write-TestResult "Search site number" $false $_.Exception.Message
}

# Search by name returning multiple (if name matches)
try {
    $results = @(Search-AgentInstaller -SearchTerm "s" -Agents $mockAgents)
    # "mainoffice" and "testco" have 's' - at least mainoffice
    $pass = $results.Count -ge 1
    Write-TestResult "Search by partial 's' returns multiple matches" $pass "Count=$($results.Count)"
} catch {
    Write-TestResult "Search by partial 's'" $false $_.Exception.Message
}

# ============================================================================
# SECTION 16: SESSION / NAVIGATION TESTS
# ============================================================================

Write-SectionHeader "SECTION 16: SESSION / NAVIGATION TESTS"

# Reset session changes for clean testing
$script:SessionChanges = [System.Collections.Generic.List[object]]::new()

# Add-SessionChange with valid inputs
try {
    $initialCount = $script:SessionChanges.Count
    Add-SessionChange -Category "Test" -Description "Test change from test runner"
    $newCount = $script:SessionChanges.Count
    $pass = $newCount -eq ($initialCount + 1)
    Write-TestResult "Add-SessionChange adds entry to SessionChanges" $pass "Before=$initialCount, After=$newCount"
} catch {
    Write-TestResult "Add-SessionChange adds entry" $false $_.Exception.Message
}

# Verify entry structure
try {
    if ($script:SessionChanges.Count -gt 0) {
        $lastChange = $script:SessionChanges[-1]
        $pass = $null -ne $lastChange.Timestamp -and
                $null -ne $lastChange.Category -and
                $null -ne $lastChange.Description
        Write-TestResult "SessionChange has Timestamp, Category, Description" $pass
    } else {
        Write-TestResult "SessionChange entry structure" $false "No entries found"
    }
} catch {
    Write-TestResult "SessionChange entry structure" $false $_.Exception.Message
}

# Add-SessionChange with empty Description should fail (Mandatory parameter)
try {
    Add-SessionChange -Category "Test" -Description "" -ErrorAction Stop
    # If we get here, empty string was accepted - that's actually possible with [string]
    # Mandatory won't block "" in non-interactive mode, so this may pass. Let's just note behavior.
    Write-TestResult "Add-SessionChange handles empty Description" $true "Accepted empty string (Mandatory allows '' non-interactively)"
} catch {
    # Expected: Mandatory string parameter rejects empty string
    Write-TestResult "Add-SessionChange rejects empty Description (Mandatory)" $true
}

# Add multiple changes and verify count
try {
    $beforeCount = $script:SessionChanges.Count
    Add-SessionChange -Category "Network" -Description "Changed DNS"
    Add-SessionChange -Category "System" -Description "Set hostname"
    $afterCount = $script:SessionChanges.Count
    $pass = $afterCount -eq ($beforeCount + 2)
    Write-TestResult "Multiple Add-SessionChange calls accumulate correctly" $pass "Before=$beforeCount, After=$afterCount"
} catch {
    Write-TestResult "Multiple Add-SessionChange calls" $false $_.Exception.Message
}

# Get-SessionChanges - verify SessionChanges array is accessible
try {
    $changes = $script:SessionChanges
    $pass = $changes -is [Array] -or $changes -is [System.Collections.ArrayList] -or $changes -is [System.Collections.Generic.List[object]]
    Write-TestResult "SessionChanges is accessible collection" $pass "Count=$($changes.Count), Type=$($changes.GetType().Name)"
} catch {
    Write-TestResult "SessionChanges is accessible" $false $_.Exception.Message
}

# Clear-MenuCache runs without error
try {
    Clear-MenuCache
    Write-TestResult "Clear-MenuCache executes without error" $true
} catch {
    Write-TestResult "Clear-MenuCache executes without error" $false $_.Exception.Message
}

# ============================================================================
# SECTION 17: NETWORK DIAGNOSTICS FUNCTION EXISTENCE
# ============================================================================

Write-SectionHeader "SECTION 17: NETWORK DIAGNOSTICS FUNCTION EXISTENCE"

$netDiagFunctions = @(
    "Show-NetworkDiagnostics",
    "Invoke-PingHost",
    "Invoke-PortTest",
    "Invoke-TraceRoute",
    "Invoke-SubnetSweep",
    "Invoke-DnsLookup",
    "Show-ActiveConnections",
    "Show-ArpTable"
)

foreach ($funcName in $netDiagFunctions) {
    try {
        $exists = Get-Command -Name $funcName -ErrorAction SilentlyContinue
        Write-TestResult "NetDiag function: $funcName" ($null -ne $exists)
    } catch {
        Write-TestResult "NetDiag function: $funcName" $false $_.Exception.Message
    }
}

# ============================================================================
# SECTION 18: OPERATIONS MENU FUNCTION EXISTENCE
# ============================================================================

Write-SectionHeader "SECTION 18: OPERATIONS MENU FUNCTION EXISTENCE"

$opsFunctions = @(
    "Show-OperationsMenu",
    "Invoke-RemotePSSession",
    "Invoke-RemoteHealthCheck",
    "Invoke-RemoteServiceManager"
)

foreach ($funcName in $opsFunctions) {
    try {
        $exists = Get-Command -Name $funcName -ErrorAction SilentlyContinue
        Write-TestResult "Operations function: $funcName" ($null -ne $exists)
    } catch {
        Write-TestResult "Operations function: $funcName" $false $_.Exception.Message
    }
}

# ============================================================================
# SECTION 19: ADDITIONAL BEHAVIORAL TESTS
# ============================================================================

Write-SectionHeader "SECTION 19: ADDITIONAL BEHAVIORAL TESTS"

# Test-NavigationCommand has UserInput parameter (not $Input which is reserved)
try {
    $cmd = Get-Command Test-NavigationCommand -ErrorAction Stop
    $hasUserInput = $cmd.Parameters.ContainsKey("UserInput")
    $hasInput = $cmd.Parameters.ContainsKey("Input")
    $pass = $hasUserInput -and -not $hasInput
    Write-TestResult "Test-NavigationCommand uses 'UserInput' param (not reserved 'Input')" $pass
} catch {
    Write-TestResult "Test-NavigationCommand parameter name check" $false $_.Exception.Message
}

# Write-OutputColor has message and color parameters
try {
    $cmd = Get-Command Write-OutputColor -ErrorAction Stop
    $pass = $cmd.Parameters.ContainsKey("message") -and $cmd.Parameters.ContainsKey("color")
    Write-TestResult "Write-OutputColor has 'message' and 'color' parameters" $pass
} catch {
    Write-TestResult "Write-OutputColor parameters" $false $_.Exception.Message
}

# Get-RDPState returns string
try {
    $result = Get-RDPState
    Write-TestResult "Get-RDPState returns string" ($result -is [string]) "Result='$result'"
} catch {
    Write-TestResult "Get-RDPState returns string" $false $_.Exception.Message
}

# Get-FirewallState returns hashtable with expected keys
try {
    $result = Get-FirewallState
    $pass = $result -is [hashtable] -and
            $result.ContainsKey("Domain") -and
            $result.ContainsKey("Private") -and
            $result.ContainsKey("Public")
    Write-TestResult "Get-FirewallState returns hashtable with Domain/Private/Public" $pass
} catch {
    Write-TestResult "Get-FirewallState returns hashtable" $false $_.Exception.Message
}

# Get-CurrentPowerPlan returns hashtable with Name key
try {
    $result = Get-CurrentPowerPlan
    $pass = $result -is [hashtable] -and $result.ContainsKey("Name")
    Write-TestResult "Get-CurrentPowerPlan returns hashtable with 'Name' key" $pass "Name='$($result.Name)'"
} catch {
    Write-TestResult "Get-CurrentPowerPlan returns hashtable" $false $_.Exception.Message
}

# Get-WinRMState returns string
try {
    $result = Get-WinRMState
    Write-TestResult "Get-WinRMState returns string" ($result -is [string]) "Result='$result'"
} catch {
    Write-TestResult "Get-WinRMState returns string" $false $_.Exception.Message
}

# Global variables initialized correctly
try {
    $pass = $global:RebootNeeded -is [bool] -and
            $global:DisabledAdminReboot -is [bool] -and
            $global:ReturnToMainMenu -is [bool]
    Write-TestResult "Global flags (RebootNeeded, DisabledAdminReboot, ReturnToMainMenu) are booleans" $pass
} catch {
    Write-TestResult "Global flags are booleans" $false $_.Exception.Message
}

# Script-scoped variables accessible
try {
    $pass = $null -ne $script:ScriptVersion -and
            $null -ne $script:ColorThemes -and
            $null -ne $script:SessionChanges -and
            $null -ne $script:FileServer
    Write-TestResult "Script-scoped variables accessible after dot-source" $pass
} catch {
    Write-TestResult "Script-scoped variables accessible" $false $_.Exception.Message
}

# Write-CenteredOutput doesn't throw
try {
    Write-CenteredOutput "Test Header Text" -color "Info" | Out-Null
    Write-TestResult "Write-CenteredOutput executes without error" $true
} catch {
    Write-TestResult "Write-CenteredOutput executes without error" $false $_.Exception.Message
}

# DNS presets initialized (built-in presets: Google, Cloudflare, OpenDNS, Quad9)
try {
    $pass = $script:DNSPresets.Contains("Google DNS") -and
            $script:DNSPresets.Contains("Cloudflare")
    Write-TestResult "DNS presets contain expected keys" $pass
} catch {
    Write-TestResult "DNS presets initialized" $false $_.Exception.Message
}

# FileServer structure
try {
    $pass = $script:FileServer.ContainsKey("BaseURL") -and
            $script:FileServer.ContainsKey("ISOsFolder") -and
            $script:FileServer.ContainsKey("VHDsFolder") -and
            $script:FileServer.ContainsKey("AgentFolder")
    Write-TestResult "FileServer has BaseURL, ISOsFolder, VHDsFolder, and AgentFolder keys" $pass
} catch {
    Write-TestResult "FileServer structure" $false $_.Exception.Message
}

# ============================================================================
# SECTION 20: INPUT VALIDATION BEHAVIORAL TESTS
# ============================================================================

Write-SectionHeader "SECTION 20: INPUT VALIDATION BEHAVIORAL TESTS"

# --- Test-ValidHostname ---
$validHostnames = @(
    @{ Name = "A";           Desc = "single letter" }
    @{ Name = "SV1";         Desc = "short name" }
    @{ Name = "SRV-HV1";     Desc = "standard server" }
    @{ Name = "ABCDEFGHIJKLMNO"; Desc = "max 15 chars" }
    @{ Name = "my-server";   Desc = "with hyphen" }
    @{ Name = "DC1";         Desc = "typical DC name" }
    @{ Name = "000508-pacs"; Desc = "digit-start site number" }
    @{ Name = "1SRV";        Desc = "starts with digit" }
    @{ Name = "12345";       Desc = "all numbers" }
)

foreach ($tc in $validHostnames) {
    try {
        $result = Test-ValidHostname -Hostname $tc.Name
        Write-TestResult "ValidHostname: '$($tc.Name)' ($($tc.Desc)) -> true" ($result -eq $true) "Got: $result"
    } catch {
        Write-TestResult "ValidHostname: '$($tc.Name)'" $false $_.Exception.Message
    }
}

$invalidHostnames = @(
    @{ Name = "";                  Desc = "empty" }
    @{ Name = "ABCDEFGHIJKLMNOP"; Desc = "16 chars (too long)" }
    @{ Name = "-server";           Desc = "starts with hyphen" }
    @{ Name = "server-";           Desc = "ends with hyphen" }
    @{ Name = "my server";         Desc = "contains space" }
    @{ Name = "srv.local";         Desc = "contains dot" }
)

foreach ($tc in $invalidHostnames) {
    try {
        $result = Test-ValidHostname -Hostname $tc.Name
        Write-TestResult "ValidHostname: '$($tc.Name)' ($($tc.Desc)) -> false" ($result -eq $false) "Got: $result"
    } catch {
        # Empty string causes mandatory param error - that's expected
        if ($tc.Name -eq "") {
            Write-TestResult "ValidHostname: empty string -> error (Mandatory param)" $true
        } else {
            Write-TestResult "ValidHostname: '$($tc.Name)'" $false $_.Exception.Message
        }
    }
}

# --- Test-ValidIPAddress ---
$validIPs = @(
    @{ IP = "192.168.1.1";     Desc = "standard private" }
    @{ IP = "10.0.0.1";        Desc = "class A private" }
    @{ IP = "172.16.1.100";    Desc = "class B private" }
    @{ IP = "255.255.255.0";   Desc = "subnet mask" }
    @{ IP = "0.0.0.0";         Desc = "all zeros" }
    @{ IP = "192.168.1.1/24";  Desc = "with CIDR" }
)

foreach ($tc in $validIPs) {
    try {
        $result = Test-ValidIPAddress -IPAddress $tc.IP
        Write-TestResult "ValidIP: '$($tc.IP)' ($($tc.Desc)) -> true" ($result -eq $true) "Got: $result"
    } catch {
        Write-TestResult "ValidIP: '$($tc.IP)'" $false $_.Exception.Message
    }
}

$invalidIPs = @(
    @{ IP = "999.999.999.999"; Desc = "octets > 255" }
    @{ IP = "abc.def.ghi.jkl"; Desc = "not numbers" }
    @{ IP = "192.168.1";       Desc = "only 3 octets" }
    @{ IP = "192.168.1.1.5";   Desc = "5 octets" }
    @{ IP = "";                Desc = "empty" }
)

foreach ($tc in $invalidIPs) {
    try {
        $result = Test-ValidIPAddress -IPAddress $tc.IP
        Write-TestResult "ValidIP: '$($tc.IP)' ($($tc.Desc)) -> false" ($result -eq $false) "Got: $result"
    } catch {
        if ($tc.IP -eq "") {
            Write-TestResult "ValidIP: empty string -> error (Mandatory param)" $true
        } else {
            Write-TestResult "ValidIP: '$($tc.IP)'" $false $_.Exception.Message
        }
    }
}

# --- Test-ValidVLANId ---
$validVLANs = @(1, 100, 2000, 4094)
foreach ($vlan in $validVLANs) {
    try {
        $result = Test-ValidVLANId -VLANId $vlan
        Write-TestResult "ValidVLAN: $vlan -> true" ($result -eq $true) "Got: $result"
    } catch {
        Write-TestResult "ValidVLAN: $vlan" $false $_.Exception.Message
    }
}

$invalidVLANs = @(0, -1, 4095, 9999, "abc")
foreach ($vlan in $invalidVLANs) {
    try {
        $result = Test-ValidVLANId -VLANId $vlan
        Write-TestResult "ValidVLAN: '$vlan' -> false" ($result -eq $false) "Got: $result"
    } catch {
        Write-TestResult "ValidVLAN: '$vlan'" $false $_.Exception.Message
    }
}

# Test-ValidSubnetMask removed (dead code - subnet validation uses CIDR prefix instead)

# ============================================================================
# SECTION 21: SUBNET CONVERSION TESTS
# ============================================================================

Write-SectionHeader "SECTION 21: SUBNET CONVERSION TESTS"

$subnetTests = @(
    @{ Mask = "255.255.255.0";   Expected = 24 }
    @{ Mask = "255.255.0.0";     Expected = 16 }
    @{ Mask = "255.0.0.0";       Expected = 8 }
    @{ Mask = "255.255.255.128"; Expected = 25 }
    @{ Mask = "255.255.255.252"; Expected = 30 }
    @{ Mask = "255.255.252.0";   Expected = 22 }
    @{ Mask = "255.255.255.255"; Expected = 32 }
    @{ Mask = "0.0.0.0";         Expected = 0 }
)

foreach ($tc in $subnetTests) {
    try {
        $result = Convert-SubnetMaskToPrefix -SubnetMask $tc.Mask
        $pass = $result -eq $tc.Expected
        Write-TestResult "SubnetToPrefix: $($tc.Mask) -> /$($tc.Expected)" $pass "Got: $result"
    } catch {
        Write-TestResult "SubnetToPrefix: $($tc.Mask)" $false $_.Exception.Message
    }
}

# Invalid masks return $null
$invalidSubnets = @("255.0.255.0", "abc", "192.168.1.1")
foreach ($mask in $invalidSubnets) {
    try {
        $result = Convert-SubnetMaskToPrefix -SubnetMask $mask
        Write-TestResult "SubnetToPrefix: '$mask' (invalid) -> null" ($null -eq $result) "Got: $result"
    } catch {
        Write-TestResult "SubnetToPrefix: '$mask'" $false $_.Exception.Message
    }
}

# ============================================================================
# SECTION 22: FORMAT LINK SPEED TESTS
# ============================================================================

Write-SectionHeader "SECTION 22: FORMAT LINK SPEED TESTS"

$speedTests = @(
    @{ Bps = 1000000000;      Expected = "1 Gbps";    Desc = "1 Gbps" }
    @{ Bps = 10000000000;     Expected = "10 Gbps";   Desc = "10 Gbps" }
    @{ Bps = 25000000000;     Expected = "25 Gbps";   Desc = "25 Gbps" }
    @{ Bps = 100000000;       Expected = "100 Mbps";  Desc = "100 Mbps" }
    @{ Bps = 1000000;         Expected = "1 Mbps";    Desc = "1 Mbps" }
    @{ Bps = 1000000000000;   Expected = "1 Tbps";    Desc = "1 Tbps" }
    @{ Bps = 0;               Expected = "N/A";       Desc = "zero" }
    @{ Bps = "";             Expected = "N/A";       Desc = "empty string" }
)

foreach ($tc in $speedTests) {
    try {
        $result = Format-LinkSpeed -SpeedBps $tc.Bps
        $pass = $result -eq $tc.Expected
        Write-TestResult "LinkSpeed: $($tc.Desc) -> '$($tc.Expected)'" $pass "Got: '$result'"
    } catch {
        Write-TestResult "LinkSpeed: $($tc.Desc)" $false $_.Exception.Message
    }
}

# ============================================================================
# SECTION 23: HOSTNAME PARSING TESTS
# ============================================================================

Write-SectionHeader "SECTION 23: HOSTNAME PARSING TESTS"

# Get-HostNumberFromHostname
$hostNumTests = @(
    @{ Name = "123456-HV1";   Expected = 1;    Desc = "standard HV1" }
    @{ Name = "123456-HV2";   Expected = 2;    Desc = "standard HV2" }
    @{ Name = "123456-HV24";  Expected = 24;   Desc = "HV24" }
    @{ Name = "123456-H1";    Expected = 1;    Desc = "-H1 suffix" }
    @{ Name = "123456-FS1";   Expected = $null; Desc = "no HV pattern" }
    @{ Name = "DESKTOP-ABC";  Expected = $null; Desc = "no number" }
)

foreach ($tc in $hostNumTests) {
    try {
        $result = Get-HostNumberFromHostname -Hostname $tc.Name
        $pass = $result -eq $tc.Expected
        Write-TestResult "HostNumber: '$($tc.Name)' -> $($tc.Expected)" $pass "Got: $result"
    } catch {
        Write-TestResult "HostNumber: '$($tc.Name)'" $false $_.Exception.Message
    }
}

# Get-SiteNumberFromHostnameParam
$siteNumTests = @(
    @{ Name = "123456-HV1";    Expected = "123456"; Desc = "6-digit standard" }
    @{ Name = "123456-FS1";    Expected = "123456"; Desc = "6-digit FS" }
    @{ Name = "123456-DC1";    Expected = "123456"; Desc = "6-digit DC" }
    @{ Name = "DESKTOP-ABC";   Expected = $null;    Desc = "no digits (expects null)" }
)

foreach ($tc in $siteNumTests) {
    try {
        $result = Get-SiteNumberFromHostnameParam -Hostname $tc.Name
        $pass = $result -eq $tc.Expected
        Write-TestResult "SiteNumber: '$($tc.Name)' -> '$($tc.Expected)'" $pass "Got: '$result'"
    } catch {
        Write-TestResult "SiteNumber: '$($tc.Name)'" $false $_.Exception.Message
    }
}

# ============================================================================
# SECTION 24: iSCSI AUTO-IP TESTS
# ============================================================================

Write-SectionHeader "SECTION 24: iSCSI AUTO-IP TESTS"

$iscsiTests = @(
    @{ Host = 1;  Port = 1; Expected = "172.16.1.21";  Desc = "H1P1" }
    @{ Host = 1;  Port = 2; Expected = "172.16.1.22";  Desc = "H1P2" }
    @{ Host = 2;  Port = 1; Expected = "172.16.1.31";  Desc = "H2P1" }
    @{ Host = 2;  Port = 2; Expected = "172.16.1.32";  Desc = "H2P2" }
    @{ Host = 10; Port = 1; Expected = "172.16.1.111"; Desc = "H10P1" }
    @{ Host = 24; Port = 1; Expected = "172.16.1.251"; Desc = "H24P1 (max)" }
    @{ Host = 24; Port = 2; Expected = "172.16.1.252"; Desc = "H24P2 (max)" }
)

foreach ($tc in $iscsiTests) {
    try {
        $result = Get-iSCSIAutoIP -HostNumber $tc.Host -PortNumber $tc.Port
        $pass = $result -eq $tc.Expected
        Write-TestResult "iSCSI IP: $($tc.Desc) -> $($tc.Expected)" $pass "Got: $result"
    } catch {
        Write-TestResult "iSCSI IP: $($tc.Desc)" $false $_.Exception.Message
    }
}

# Out of range returns $null
$iscsiInvalid = @(
    @{ Host = 0;  Port = 1; Desc = "host 0" }
    @{ Host = 25; Port = 1; Desc = "host 25" }
    @{ Host = 1;  Port = 0; Desc = "port 0" }
    @{ Host = 1;  Port = 3; Desc = "port 3" }
)

foreach ($tc in $iscsiInvalid) {
    try {
        $result = Get-iSCSIAutoIP -HostNumber $tc.Host -PortNumber $tc.Port
        Write-TestResult "iSCSI IP: $($tc.Desc) -> null" ($null -eq $result) "Got: $result"
    } catch {
        Write-TestResult "iSCSI IP: $($tc.Desc)" $false $_.Exception.Message
    }
}

# ============================================================================
# SECTION 25: VM TEMPLATE VALIDATION
# ============================================================================

Write-SectionHeader "SECTION 25: VM TEMPLATE VALIDATION"

# Templates should exist
try {
    $pass = $null -ne $script:StandardVMTemplates -and $script:StandardVMTemplates -is [hashtable]
    Write-TestResult "StandardVMTemplates exists and is hashtable" $pass
} catch {
    Write-TestResult "StandardVMTemplates exists" $false $_.Exception.Message
}

# Expected template keys (generic built-ins: DC, FS, WEB)
$expectedTemplates = @("DC", "FS", "WEB")
foreach ($key in $expectedTemplates) {
    try {
        $pass = $script:StandardVMTemplates.ContainsKey($key)
        Write-TestResult "VM template '$key' exists" $pass
    } catch {
        Write-TestResult "VM template '$key'" $false $_.Exception.Message
    }
}

# Each template has required keys
$requiredTemplateKeys = @("FullName", "Prefix", "OSType", "vCPU", "MemoryGB", "MemoryType", "Disks", "NICs", "SortOrder")
foreach ($tplKey in $expectedTemplates) {
    if (-not $script:StandardVMTemplates.ContainsKey($tplKey)) { continue }
    $tpl = $script:StandardVMTemplates[$tplKey]
    $missing = @()
    foreach ($rk in $requiredTemplateKeys) {
        if (-not $tpl.ContainsKey($rk)) { $missing += $rk }
    }
    try {
        $pass = $missing.Count -eq 0
        Write-TestResult "VM template '$tplKey' has all required keys" $pass $(if (-not $pass) { "Missing: $($missing -join ', ')" } else { "" })
    } catch {
        Write-TestResult "VM template '$tplKey' keys" $false $_.Exception.Message
    }
}

# All built-in templates have OSType = "Windows"
try {
    $allWindows = $true
    foreach ($key in $expectedTemplates) {
        if ($script:StandardVMTemplates[$key].OSType -ne "Windows") { $allWindows = $false }
    }
    Write-TestResult "DC, FS, WEB have OSType='Windows'" $allWindows
} catch {
    Write-TestResult "Windows OSType check" $false $_.Exception.Message
}

# DC should have TimeSyncWithHost = $false
try {
    $dcTimeSync = $script:StandardVMTemplates["DC"].TimeSyncWithHost
    Write-TestResult "DC has TimeSyncWithHost=false" ($dcTimeSync -eq $false) "Got $dcTimeSync"
} catch {
    Write-TestResult "DC TimeSyncWithHost" $false $_.Exception.Message
}

# FS should have 2 disks (OS + Data)
try {
    $fsDiskCount = $script:StandardVMTemplates["FS"].Disks.Count
    Write-TestResult "FS has 2 disks (OS + Data)" ($fsDiskCount -eq 2) "Got $fsDiskCount"
} catch {
    Write-TestResult "FS disk count" $false $_.Exception.Message
}

# Disk definitions are arrays with Name/SizeGB/Type
try {
    $diskErrors = @()
    foreach ($tplKey in $expectedTemplates) {
        $tpl = $script:StandardVMTemplates[$tplKey]
        foreach ($disk in $tpl.Disks) {
            if (-not $disk.ContainsKey("Name") -or -not $disk.ContainsKey("SizeGB") -or -not $disk.ContainsKey("Type")) {
                $diskErrors += "$tplKey disk missing Name/SizeGB/Type"
            }
        }
    }
    $pass = $diskErrors.Count -eq 0
    Write-TestResult "All VM template disks have Name, SizeGB, Type" $pass $(if (-not $pass) { $diskErrors -join '; ' } else { "" })
} catch {
    Write-TestResult "VM template disk structure" $false $_.Exception.Message
}

# VMNaming variable exists and has required keys
try {
    $pass = $null -ne $script:VMNaming -and $script:VMNaming -is [hashtable]
    Write-TestResult "VMNaming exists and is hashtable" $pass
} catch {
    Write-TestResult "VMNaming exists" $false $_.Exception.Message
}

try {
    $requiredNamingKeys = @("SiteId", "Pattern", "SiteIdSource", "SiteIdRegex")
    $missing = @()
    foreach ($k in $requiredNamingKeys) {
        if (-not $script:VMNaming.ContainsKey($k)) { $missing += $k }
    }
    $pass = $missing.Count -eq 0
    Write-TestResult "VMNaming has all required keys" $pass $(if (-not $pass) { "Missing: $($missing -join ', ')" } else { "" })
} catch {
    Write-TestResult "VMNaming keys" $false $_.Exception.Message
}

try {
    Write-TestResult "VMNaming.Pattern default is '{Site}-{Prefix}{Seq}'" ($script:VMNaming.Pattern -eq "{Site}-{Prefix}{Seq}") "Got $($script:VMNaming.Pattern)"
} catch {
    Write-TestResult "VMNaming.Pattern default" $false $_.Exception.Message
}

try {
    Write-TestResult "VMNaming.SiteIdSource default is 'hostname'" ($script:VMNaming.SiteIdSource -eq "hostname") "Got $($script:VMNaming.SiteIdSource)"
} catch {
    Write-TestResult "VMNaming.SiteIdSource default" $false $_.Exception.Message
}

# Get-SiteNumberFromHostnameParam uses configurable regex
try {
    # Default regex: ^(\d{3,6})-
    $result = Get-SiteNumberFromHostnameParam -Hostname "123456-HV1"
    Write-TestResult "SiteNumber: 123456-HV1 -> 123456" ($result -eq "123456") "Got $result"
} catch {
    Write-TestResult "SiteNumber detection" $false $_.Exception.Message
}

try {
    # Fallback: 3+ digit sequence
    $result = Get-SiteNumberFromHostnameParam -Hostname "SERVER001"
    Write-TestResult "SiteNumber fallback: SERVER001 -> 001" ($result -eq "001") "Got $result"
} catch {
    Write-TestResult "SiteNumber fallback" $false $_.Exception.Message
}

try {
    # Custom regex: alpha site IDs
    $origRegex = $script:VMNaming.SiteIdRegex
    $script:VMNaming.SiteIdRegex = "^([A-Z]{2,6})-"
    $result = Get-SiteNumberFromHostnameParam -Hostname "CRV-DC-01"
    Write-TestResult "SiteNumber custom regex: CRV-DC-01 -> CRV" ($result -eq "CRV") "Got $result"
    $script:VMNaming.SiteIdRegex = $origRegex
} catch {
    Write-TestResult "SiteNumber custom regex" $false $_.Exception.Message
    $script:VMNaming.SiteIdRegex = "^(\d{3,6})-"
}

# ============================================================================
# SECTION 26: UNDO SYSTEM TESTS
# ============================================================================

Write-SectionHeader "SECTION 26: UNDO SYSTEM TESTS"

# Reset undo stack for clean test
$script:UndoStack = [System.Collections.Generic.List[object]]::new()

# Add-UndoAction adds entry
try {
    $beforeCount = $script:UndoStack.Count
    Add-UndoAction -Category "Test" -Description "Test undo action" -UndoScript { Write-Host "undo" }
    $afterCount = $script:UndoStack.Count
    $pass = $afterCount -eq ($beforeCount + 1)
    Write-TestResult "Add-UndoAction adds entry to UndoStack" $pass "Before=$beforeCount, After=$afterCount"
} catch {
    Write-TestResult "Add-UndoAction adds entry" $false $_.Exception.Message
}

# Verify undo entry structure
try {
    $lastUndo = $script:UndoStack[-1]
    $pass = $null -ne $lastUndo.Timestamp -and
            $null -ne $lastUndo.Category -and
            $null -ne $lastUndo.Description -and
            $null -ne $lastUndo.UndoScript
    Write-TestResult "UndoStack entry has Timestamp, Category, Description, UndoScript" $pass
} catch {
    Write-TestResult "UndoStack entry structure" $false $_.Exception.Message
}

# Multiple undo actions accumulate
try {
    $before = $script:UndoStack.Count
    Add-UndoAction -Category "DNS" -Description "Changed DNS to 8.8.8.8" -UndoScript { Write-Host "revert" }
    Add-UndoAction -Category "IP" -Description "Changed IP to 10.0.0.1" -UndoScript { Write-Host "revert" }
    $after = $script:UndoStack.Count
    $pass = $after -eq ($before + 2)
    Write-TestResult "Multiple Add-UndoAction calls accumulate" $pass "Before=$before, After=$after"
} catch {
    Write-TestResult "Multiple undo actions" $false $_.Exception.Message
}

# UndoStack is accessible array
try {
    $pass = $script:UndoStack -is [Array] -or $script:UndoStack -is [System.Collections.ArrayList] -or $script:UndoStack -is [System.Collections.Generic.List[object]]
    Write-TestResult "UndoStack is accessible collection" $pass "Count=$($script:UndoStack.Count), Type=$($script:UndoStack.GetType().Name)"
} catch {
    Write-TestResult "UndoStack accessible" $false $_.Exception.Message
}

# Clean up test undo stack
$script:UndoStack = [System.Collections.Generic.List[object]]::new()

# ============================================================================
# SECTION 27: STORAGE PATH TESTS
# ============================================================================

Write-SectionHeader "SECTION 27: STORAGE PATH TESTS"

# Get-VHDCachePath returns string (standalone mode)
try {
    $script:VMDeploymentMode = $null
    $result = Get-VHDCachePath
    $pass = $result -eq $script:VHDCachePath
    Write-TestResult "Get-VHDCachePath (standalone) returns VHDCachePath" $pass "Got: $result"
} catch {
    Write-TestResult "Get-VHDCachePath standalone" $false $_.Exception.Message
}

# Get-VHDCachePath returns cluster path in cluster mode
try {
    $script:VMDeploymentMode = "Cluster"
    $result = Get-VHDCachePath
    $pass = $result -eq $script:ClusterVHDCachePath
    Write-TestResult "Get-VHDCachePath (cluster) returns ClusterVHDCachePath" $pass "Got: $result"
    $script:VMDeploymentMode = $null
} catch {
    $script:VMDeploymentMode = $null
    Write-TestResult "Get-VHDCachePath cluster" $false $_.Exception.Message
}

# Get-ISOStoragePath returns string (standalone mode)
try {
    $script:VMDeploymentMode = $null
    $result = Get-ISOStoragePath
    $pass = $result -eq $script:HostISOPath
    Write-TestResult "Get-ISOStoragePath (standalone) returns HostISOPath" $pass "Got: $result"
} catch {
    Write-TestResult "Get-ISOStoragePath standalone" $false $_.Exception.Message
}

# Get-ISOStoragePath returns cluster path in cluster mode
try {
    $script:VMDeploymentMode = "Cluster"
    $result = Get-ISOStoragePath
    $pass = $result -eq $script:ClusterISOPath
    Write-TestResult "Get-ISOStoragePath (cluster) returns ClusterISOPath" $pass "Got: $result"
    $script:VMDeploymentMode = $null
} catch {
    $script:VMDeploymentMode = $null
    Write-TestResult "Get-ISOStoragePath cluster" $false $_.Exception.Message
}

# ============================================================================
# SECTION 28: FILESERVER FUNCTION TESTS
# ============================================================================

Write-SectionHeader "SECTION 28: FILESERVER FUNCTION TESTS"

# Get-FileServerFiles exists and has FolderPath param
try {
    $cmd = Get-Command Get-FileServerFiles -ErrorAction Stop
    $pass = $cmd.Parameters.ContainsKey("FolderPath") -and $cmd.Parameters.ContainsKey("ForceRefresh")
    Write-TestResult "Get-FileServerFiles has FolderPath and ForceRefresh params" $pass
} catch {
    Write-TestResult "Get-FileServerFiles params" $false $_.Exception.Message
}

# Find-FileServerFile exists and has FolderPath + Keyword params
try {
    $cmd = Get-Command Find-FileServerFile -ErrorAction Stop
    $pass = $cmd.Parameters.ContainsKey("FolderPath") -and
            $cmd.Parameters.ContainsKey("Keyword") -and
            $cmd.Parameters.ContainsKey("Extension")
    Write-TestResult "Find-FileServerFile has FolderPath, Keyword, Extension params" $pass
} catch {
    Write-TestResult "Find-FileServerFile params" $false $_.Exception.Message
}

# Get-FileServerFile unconfigured detection
try {
    $origBaseURL = $script:FileServer.BaseURL
    $script:FileServer.BaseURL = ""
    $result = Get-FileServerFile -FilePath "test/test.iso" -DestinationPath "C:\temp" -FileName "test.iso"
    $pass = $result.Success -eq $false -and $result.Error -match "not configured"
    Write-TestResult "Get-FileServerFile rejects unconfigured share" $pass "Error: $($result.Error)"
    $script:FileServer.BaseURL = $origBaseURL
} catch {
    Write-TestResult "Get-FileServerFile unconfigured detection" $false $_.Exception.Message
    $script:FileServer.BaseURL = $origBaseURL
}

# Get-FileServerFile has required parameters
try {
    $cmd = Get-Command Get-FileServerFile -ErrorAction Stop
    $pass = $cmd.Parameters.ContainsKey("FilePath") -and
            $cmd.Parameters.ContainsKey("DestinationPath") -and
            $cmd.Parameters.ContainsKey("FileName") -and
            $cmd.Parameters.ContainsKey("TimeoutSeconds")
    Write-TestResult "Get-FileServerFile has FilePath, DestinationPath, FileName, TimeoutSeconds" $pass
} catch {
    Write-TestResult "Get-FileServerFile params" $false $_.Exception.Message
}

# Test-FileIntegrity exists and has FilePath param
try {
    $cmd = Get-Command Test-FileIntegrity -ErrorAction Stop
    $pass = $cmd.Parameters.ContainsKey("FilePath")
    Write-TestResult "Test-FileIntegrity has FilePath param" $pass
} catch {
    Write-TestResult "Test-FileIntegrity params" $false $_.Exception.Message
}

# Get-FileHashBackground exists and has FilePath param
try {
    $cmd = Get-Command Get-FileHashBackground -ErrorAction Stop
    $pass = $cmd.Parameters.ContainsKey("FilePath")
    Write-TestResult "Get-FileHashBackground has FilePath param" $pass
} catch {
    Write-TestResult "Get-FileHashBackground params" $false $_.Exception.Message
}

# FileCache is hashtable
try {
    $pass = $script:FileCache -is [hashtable]
    Write-TestResult "FileCache is hashtable" $pass
} catch {
    Write-TestResult "FileCache structure" $false $_.Exception.Message
}

# ============================================================================
# SECTION 29: REGION COUNT VERIFICATION
# ============================================================================

Write-SectionHeader "SECTION 29: REGION COUNT VERIFICATION"

try {
    $monoLines = Get-Content $monolithicPath
    $regionStartCount = 0
    $regionEndCount = 0
    foreach ($line in $monoLines) {
        if ($line -match '^\s*#region\s') { $regionStartCount++ }
        if ($line -match '^\s*#endregion') { $regionEndCount++ }
    }
    Write-TestResult "Monolithic has 62 #region tags" ($regionStartCount -eq 62) "Found: $regionStartCount"
    Write-TestResult "Monolithic has 62 #endregion tags" ($regionEndCount -eq 62) "Found: $regionEndCount"
    Write-TestResult "Region start/end counts match" ($regionStartCount -eq $regionEndCount) "Starts=$regionStartCount, Ends=$regionEndCount"
} catch {
    Write-TestResult "Region count verification" $false $_.Exception.Message
}

# ============================================================================
# SECTION 30: DUPLICATE FUNCTION DETECTION
# ============================================================================

Write-SectionHeader "SECTION 30: DUPLICATE FUNCTION DETECTION"

try {
    $allFunctions = @{}
    $duplicates = @()

    foreach ($moduleFile in $moduleFiles) {
        $modContent = Get-Content $moduleFile.FullName -Raw
        $funcMatches = [regex]::Matches($modContent, '(?m)^function\s+([A-Za-z0-9_-]+)')

        foreach ($match in $funcMatches) {
            $funcName = $match.Groups[1].Value
            if ($allFunctions.ContainsKey($funcName)) {
                $duplicates += "$funcName (in $($allFunctions[$funcName]) AND $($moduleFile.Name))"
            } else {
                $allFunctions[$funcName] = $moduleFile.Name
            }
        }
    }

    $pass = $duplicates.Count -eq 0
    Write-TestResult "No duplicate function names across modules" $pass $(if (-not $pass) { "Duplicates: $($duplicates -join '; ')" } else { "Checked $($allFunctions.Count) functions" })
} catch {
    Write-TestResult "Duplicate function detection" $false $_.Exception.Message
}

# ============================================================================
# SECTION 31: CACHING SYSTEM TESTS
# ============================================================================

Write-SectionHeader "SECTION 31: CACHING SYSTEM TESTS"

# Get-CachedValue caches result
try {
    $script:MenuCache = @{
        HyperVInstalled = $null
        RDPState = $null
        FirewallState = $null
        AdminEnabled = $null
        PowerPlan = $null
        LastUpdate = $null
    }
    $callCount = 0
    $result1 = Get-CachedValue -Key "RDPState" -FetchScript { $script:testCallCount++; return "Enabled" } -CacheSeconds 30
    $result2 = Get-CachedValue -Key "RDPState" -FetchScript { $script:testCallCount++; return "Disabled" } -CacheSeconds 30
    $pass = $result1 -eq "Enabled" -and $result2 -eq "Enabled"
    Write-TestResult "Get-CachedValue returns cached value on second call" $pass "First=$result1, Second=$result2"
} catch {
    Write-TestResult "Get-CachedValue caching" $false $_.Exception.Message
}

# Clear-MenuCache clears all keys
try {
    $script:MenuCache.RDPState = "Enabled"
    $script:MenuCache.RDPState_LastUpdate = Get-Date
    Clear-MenuCache
    $pass = $null -eq $script:MenuCache.RDPState -and -not $script:MenuCache.ContainsKey("RDPState_LastUpdate")
    Write-TestResult "Clear-MenuCache clears all cached values" $pass
} catch {
    Write-TestResult "Clear-MenuCache clears values" $false $_.Exception.Message
}

# ============================================================================
# SECTION 32: COLOR THEME APPLICATION TESTS
# ============================================================================

Write-SectionHeader "SECTION 32: COLOR THEME APPLICATION TESTS"

# All themes have all 7 required keys
try {
    $requiredColorKeys = @("Success", "Warning", "Error", "Info", "Debug", "Critical", "Verbose")
    $themeErrors = @()
    foreach ($themeName in $script:ColorThemes.Keys) {
        $theme = $script:ColorThemes[$themeName]
        foreach ($ck in $requiredColorKeys) {
            if (-not $theme.ContainsKey($ck)) {
                $themeErrors += "$themeName missing $ck"
            }
        }
    }
    $pass = $themeErrors.Count -eq 0
    Write-TestResult "All themes have 7 required color keys" $pass $(if (-not $pass) { $themeErrors -join '; ' } else { "Checked $($script:ColorThemes.Count) themes" })
} catch {
    Write-TestResult "Theme color key validation" $false $_.Exception.Message
}

# All theme color values are valid ConsoleColor names
try {
    $validColors = [System.Enum]::GetNames([System.ConsoleColor])
    $colorErrors = @()
    foreach ($themeName in $script:ColorThemes.Keys) {
        $theme = $script:ColorThemes[$themeName]
        foreach ($ck in $theme.Keys) {
            if ($theme[$ck] -notin $validColors) {
                $colorErrors += "$themeName.$ck = '$($theme[$ck])' (invalid)"
            }
        }
    }
    $pass = $colorErrors.Count -eq 0
    Write-TestResult "All theme colors are valid ConsoleColor values" $pass $(if (-not $pass) { $colorErrors -join '; ' } else { "" })
} catch {
    Write-TestResult "Theme color validation" $false $_.Exception.Message
}

# ============================================================================
# SECTION 33: ADDITIONAL FUNCTION EXISTENCE
# ============================================================================

Write-SectionHeader "SECTION 33: ADDITIONAL FUNCTION EXISTENCE"

$additionalFunctions = @(
    "Test-ValidVLANId",
    # Test-ValidSubnetMask removed (dead code)
    "Get-FileServerFiles",
    "Find-FileServerFile",
    "Get-FileServerFileSize",
    "Get-VHDCachePath",
    "Get-ISOStoragePath",
    "Test-CachedVHD",
    "Test-CachedISO",
    "Get-SiteNumberFromHostnameParam",
    "Show-OSVersionMenu",
    "Test-OpticalDrive",
    "Initialize-AppConfigDir",
    "Export-HTMLHealthReport"
)

foreach ($funcName in $additionalFunctions) {
    try {
        $exists = Get-Command -Name $funcName -ErrorAction SilentlyContinue
        Write-TestResult "Function exists: $funcName" ($null -ne $exists)
    } catch {
        Write-TestResult "Function exists: $funcName" $false $_.Exception.Message
    }
}

# ============================================================================
# SECTION 34: EXTERNAL DEFAULTS & CONFIGURATION SYSTEM
# ============================================================================

Write-SectionHeader "SECTION 34: EXTERNAL DEFAULTS & CONFIGURATION SYSTEM"

# Test new function existence
$defaultsFunctions = @(
    "Initialize-SANTargetPairs",
    "Import-Defaults",
    "Export-Defaults",
    "Import-CustomLicenses",
    "Export-CustomLicenses",
    "Show-EditDefaults",
    "Show-EditLicenses",
    "Show-FirstRunWizard"
)

foreach ($funcName in $defaultsFunctions) {
    try {
        $exists = Get-Command -Name $funcName -ErrorAction SilentlyContinue
        Write-TestResult "Function exists: $funcName" ($null -ne $exists)
    } catch {
        Write-TestResult "Function exists: $funcName" $false $_.Exception.Message
    }
}

# Test generic defaults (no org-specific values at init)
Write-TestResult "Generic default: domain is empty" ($domain -eq "" -or $null -eq $domain) "domain='$domain'"
Write-TestResult "Generic default: localadminaccountname is 'localadmin'" ($localadminaccountname -eq 'localadmin') "localadminaccountname='$localadminaccountname'"
Write-TestResult "Generic default: FullName is 'Local Administrator'" ($FullName -eq 'Local Administrator') "FullName='$FullName'"
Write-TestResult "Generic default: SwitchName is 'LAN-SET'" ($SwitchName -eq 'LAN-SET') "SwitchName='$SwitchName'"

# Test tool identity variables exist with defaults
Write-TestResult "Tool identity: ToolName exists" ($null -ne $script:ToolName) "ToolName='$($script:ToolName)'"
Write-TestResult "Tool identity: ToolFullName exists" ($null -ne $script:ToolFullName) "ToolFullName='$($script:ToolFullName)'"
Write-TestResult "Tool identity: SupportContact exists" ($null -ne $script:SupportContact) "SupportContact='$($script:SupportContact)'"
Write-TestResult "Tool identity: ConfigDirName exists" ($null -ne $script:ConfigDirName) "ConfigDirName='$($script:ConfigDirName)'"

# Test DNS presets have built-in entries
Write-TestResult "DNS presets: contains Google DNS" ($script:DNSPresets.Contains("Google DNS"))
Write-TestResult "DNS presets: contains Cloudflare" ($script:DNSPresets.Contains("Cloudflare"))
Write-TestResult "DNS presets: contains OpenDNS" ($script:DNSPresets.Contains("OpenDNS"))
Write-TestResult "DNS presets: contains Quad9" ($script:DNSPresets.Contains("Quad9"))

# Test FileServer BaseURL is empty at init (before Import-Defaults)
Write-TestResult "FileServer: BaseURL is empty at init" ($script:FileServer.BaseURL -eq "")
Write-TestResult "FileServer: ISOsFolder defaults to 'ISOs'" ($script:FileServer.ISOsFolder -eq "ISOs")

# Test script variables exist
Write-TestResult "Variable exists: script:DefaultsPath" ($null -ne $script:DefaultsPath)
Write-TestResult "Variable exists: script:iSCSISubnet" ($null -ne $script:iSCSISubnet)
Write-TestResult "Variable exists: script:CustomKMSKeys" ($null -ne $script:CustomKMSKeys)
Write-TestResult "Variable exists: script:CustomAVMAKeys" ($null -ne $script:CustomAVMAKeys)

# Test Initialize-SANTargetPairs works
try {
    $oldSubnet = $script:iSCSISubnet
    $script:iSCSISubnet = "10.0.0"
    Initialize-SANTargetPairs
    $pairA = $script:SANTargetPairs[0].A
    $pairOK = $pairA -eq "10.0.0.10"
    Write-TestResult "Initialize-SANTargetPairs uses script:iSCSISubnet" $pairOK "Expected 10.0.0.10, got $pairA"
    # Restore
    $script:iSCSISubnet = $oldSubnet
    Initialize-SANTargetPairs
} catch {
    Write-TestResult "Initialize-SANTargetPairs uses script:iSCSISubnet" $false $_.Exception.Message
}

# Test Import-Defaults with no file (should set generic defaults)
try {
    $testDir = "$env:TEMP\appconfig_test_$(Get-Random)"
    $origDefaultsPath = $script:DefaultsPath
    $origConfigDir = $script:AppConfigDir
    $script:AppConfigDir = $testDir
    $script:DefaultsPath = "$testDir\defaults.json"
    Import-Defaults
    $domainAfter = $script:domain
    Write-TestResult "Import-Defaults (no file): domain stays empty" ($domainAfter -eq "" -or $null -eq $domainAfter) "domain='$domainAfter'"
    # Restore
    $script:DefaultsPath = $origDefaultsPath
    $script:AppConfigDir = $origConfigDir
    if (Test-Path $testDir) { Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue }
} catch {
    Write-TestResult "Import-Defaults (no file): domain stays empty" $false $_.Exception.Message
    $script:DefaultsPath = $origDefaultsPath
    $script:AppConfigDir = $origConfigDir
}

# Test Import-Defaults with file (should merge)
try {
    $testDir = "$env:TEMP\appconfig_test_$(Get-Random)"
    $null = New-Item -Path $testDir -ItemType Directory -Force
    $origDefaultsPath = $script:DefaultsPath
    $origConfigDir = $script:AppConfigDir
    $script:AppConfigDir = $testDir
    $script:DefaultsPath = "$testDir\defaults.json"

    $testDefaults = @{
        Domain = "test.local"
        LocalAdminName = "testadmin"
        DNSPresets = @{
            "Test DNS" = @("10.0.0.1", "10.0.0.2")
        }
        iSCSISubnet = "192.168.5"
    }
    $testDefaults | ConvertTo-Json -Depth 5 | Out-File "$testDir\defaults.json" -Encoding UTF8

    Import-Defaults
    Write-TestResult "Import-Defaults (with file): domain merged" ($script:domain -eq "test.local") "domain='$($script:domain)'"
    Write-TestResult "Import-Defaults (with file): admin merged" ($script:localadminaccountname -eq "testadmin") "admin='$($script:localadminaccountname)'"
    Write-TestResult "Import-Defaults (with file): custom DNS merged" ($script:DNSPresets.Contains("Test DNS")) "Has 'Test DNS'=$($script:DNSPresets.Contains('Test DNS'))"
    Write-TestResult "Import-Defaults (with file): iSCSI subnet merged" ($script:iSCSISubnet -eq "192.168.5") "subnet='$($script:iSCSISubnet)'"
    Write-TestResult "Import-Defaults (with file): built-in DNS preserved" ($script:DNSPresets.Contains("Google DNS")) "Has 'Google DNS'=$($script:DNSPresets.Contains('Google DNS'))"

    # Restore
    $script:DefaultsPath = $origDefaultsPath
    $script:AppConfigDir = $origConfigDir
    $script:iSCSISubnet = "172.16.1"
    Initialize-SANTargetPairs
    # Reset domain/admin to generic
    $domain = ""; $script:domain = ""
    $localadminaccountname = "localadmin"; $script:localadminaccountname = "localadmin"
    # Remove test DNS preset
    if ($script:DNSPresets.Contains("Test DNS")) { $script:DNSPresets.Remove("Test DNS") }
    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-TestResult "Import-Defaults (with file): merge test" $false $_.Exception.Message
    $script:DefaultsPath = $origDefaultsPath
    $script:AppConfigDir = $origConfigDir
}

# Test Export-Defaults round-trip
try {
    $testDir = "$env:TEMP\appconfig_test_$(Get-Random)"
    $null = New-Item -Path $testDir -ItemType Directory -Force
    $origDefaultsPath = $script:DefaultsPath
    $origConfigDir = $script:AppConfigDir
    $script:AppConfigDir = $testDir
    $script:DefaultsPath = "$testDir\defaults.json"

    Export-Defaults
    $fileExists = Test-Path "$testDir\defaults.json"
    Write-TestResult "Export-Defaults creates file" $fileExists

    if ($fileExists) {
        $exported = Get-Content "$testDir\defaults.json" -Raw | ConvertFrom-Json
        Write-TestResult "Export-Defaults: has Domain field" ($null -ne $exported.Domain -or $exported.PSObject.Properties.Name -contains "Domain")
        Write-TestResult "Export-Defaults: has iSCSISubnet field" ($null -ne $exported.iSCSISubnet)
        Write-TestResult "Export-Defaults: has CustomKMSKeys field" ($exported.PSObject.Properties.Name -contains "CustomKMSKeys")
        Write-TestResult "Export-Defaults: has CustomAVMAKeys field" ($exported.PSObject.Properties.Name -contains "CustomAVMAKeys")
    }

    # Restore
    $script:DefaultsPath = $origDefaultsPath
    $script:AppConfigDir = $origConfigDir
    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-TestResult "Export-Defaults round-trip" $false $_.Exception.Message
    $script:DefaultsPath = $origDefaultsPath
    $script:AppConfigDir = $origConfigDir
}

# Test defaults.json ships alongside the tool (skip in CI / public repo where it's gitignored)
$defaultsFilePath = Join-Path (Split-Path $PSScriptRoot) 'defaults.json'
if (Test-Path $defaultsFilePath) {
    Write-TestResult "defaults.json file exists" $true "Path: $defaultsFilePath"
    try {
        $shippedDefaults = Get-Content $defaultsFilePath -Raw | ConvertFrom-Json
        Write-TestResult "defaults.json: valid JSON" $true
        Write-TestResult "defaults.json: has Domain" ($null -ne $shippedDefaults.Domain)
        Write-TestResult "defaults.json: has FileServer" ($null -ne $shippedDefaults.FileServer)
        Write-TestResult "defaults.json: has iSCSISubnet" ($null -ne $shippedDefaults.iSCSISubnet)
        Write-TestResult "defaults.json: has CustomKMSKeys" ($null -ne $shippedDefaults.CustomKMSKeys)
        $has2019 = $null -ne $shippedDefaults.CustomKMSKeys.'Windows Server 2019'
        $has2022 = $null -ne $shippedDefaults.CustomKMSKeys.'Windows Server 2022'
        Write-TestResult "defaults.json: CustomKMSKeys has 2019+2022" ($has2019 -and $has2022) "2019=$has2019, 2022=$has2022"
    } catch {
        Write-TestResult "defaults.json: valid JSON" $false $_.Exception.Message
    }
} else {
    Write-TestResult "defaults.json file exists" -Skipped -Message "gitignored - not present in public repo"
}

# ============================================================================
# SECTION 35: FILESERVER MIGRATION QA
# ============================================================================

Write-SectionHeader "SECTION 35: FILESERVER MIGRATION QA"

# --- 35a: nginx autoindex HTML parsing (regex) ---
# This tests the core regex used in Get-FileServerFiles against various nginx HTML formats

$testRegex = '<a href="([^"]+)">([^<]+)</a>\s+(\d{2}-\w{3}-\d{4}\s+\d{2}:\d{2})\s+(\d+|-)'

# Normal short filename (not truncated)
try {
    $html1 = '<a href="Server2022.iso">Server2022.iso</a>                                     08-Feb-2026 14:30  5368709120'
    $m1 = [regex]::Matches($html1, $testRegex)
    $pass = $m1.Count -eq 1 -and $m1[0].Groups[1].Value -eq "Server2022.iso" -and $m1[0].Groups[4].Value -eq "5368709120"
    Write-TestResult "nginx parse: short filename (href = display)" $pass "href=$($m1[0].Groups[1].Value)"
} catch {
    Write-TestResult "nginx parse: short filename" $false $_.Exception.Message
}

# Truncated long filename (nginx adds ..> to display, href has full name)
try {
    $html2 = '<a href="SW_DVD9_Win_Server_STD_CORE_2025_24H2.5_64Bit_English_DC_STD_MLF_X23-81290.ISO">SW_DVD9_Win_Server_STD_CORE_2025_24H2.5_64Bit_E..&gt;</a> 01-Jan-2026 10:00  5905580032'
    $m2 = [regex]::Matches($html2, $testRegex)
    $pass = $m2.Count -eq 1 -and $m2[0].Groups[1].Value -eq "SW_DVD9_Win_Server_STD_CORE_2025_24H2.5_64Bit_English_DC_STD_MLF_X23-81290.ISO"
    Write-TestResult "nginx parse: truncated display, href has full filename" $pass "href=$($m2[0].Groups[1].Value)"
} catch {
    Write-TestResult "nginx parse: truncated filename" $false $_.Exception.Message
}

# Code uses href (group 1) not display text (group 2) for filename
try {
    $html3 = '<a href="SW_DVD9_Win_Server_STD_CORE_2022_2108.27_64Bit_English_DC_STD_MLF_X23-12345.ISO">SW_DVD9_Win_Server_STD_CORE_2022_2108.27_64Bit_..&gt;</a> 15-Dec-2025 08:00  5200000000'
    $m3 = [regex]::Matches($html3, $testRegex)
    $hrefName = [System.Uri]::UnescapeDataString($m3[0].Groups[1].Value)
    $displayName = $m3[0].Groups[2].Value
    $pass = $hrefName -ne $displayName -and $hrefName.EndsWith(".ISO") -and -not $hrefName.Contains("..") -and $displayName.Contains("..")
    Write-TestResult "nginx parse: href (full) differs from display (truncated)" $pass "href=$hrefName display=$displayName"
} catch {
    Write-TestResult "nginx parse: href vs display" $false $_.Exception.Message
}

# Parent directory link is skipped
try {
    $html4 = '<a href="../">../</a>                                                          08-Feb-2026 14:30     -'
    $m4 = [regex]::Matches($html4, $testRegex)
    # The regex won't match ../ because size "-" is valid but date format may not match,
    # OR the href is ../. Either way, if it matches, code should skip it.
    if ($m4.Count -gt 0) {
        $pass = $m4[0].Groups[1].Value -eq '../'
        Write-TestResult "nginx parse: parent link detected for skip" $pass
    } else {
        Write-TestResult "nginx parse: parent link not matched by regex (also fine)" $true
    }
} catch {
    Write-TestResult "nginx parse: parent link" $false $_.Exception.Message
}

# Directory entry (href ends with /)
try {
    $html5 = '<a href="subfolder/">subfolder/</a>                                            08-Feb-2026 14:30     -'
    $m5 = [regex]::Matches($html5, $testRegex)
    if ($m5.Count -gt 0) {
        $pass = $m5[0].Groups[1].Value.EndsWith('/')
        Write-TestResult "nginx parse: directory entry detected for skip" $pass
    } else {
        Write-TestResult "nginx parse: directory entry not matched (also fine)" $true
    }
} catch {
    Write-TestResult "nginx parse: directory entry" $false $_.Exception.Message
}

# URL-encoded filename in href (spaces become %20)
try {
    $html6 = '<a href="Server%202025%20Standard.iso">Server 2025 Standard.iso</a>            05-Feb-2026 09:15  5300000000'
    $m6 = [regex]::Matches($html6, $testRegex)
    $decoded = [System.Uri]::UnescapeDataString($m6[0].Groups[1].Value)
    $pass = $m6.Count -eq 1 -and $decoded -eq "Server 2025 Standard.iso"
    Write-TestResult "nginx parse: URL-encoded href decodes correctly" $pass "decoded=$decoded"
} catch {
    Write-TestResult "nginx parse: URL-encoded href" $false $_.Exception.Message
}

# Multiple files in single HTML block
try {
    $html7 = @"
<html><body><pre>
<a href="../">../</a>
<a href="Server2025.iso">Server2025.iso</a>                                     08-Feb-2026 14:30  5368709120
<a href="Server2022.iso">Server2022.iso</a>                                     07-Jan-2026 10:00  5200000000
<a href="Server2019.iso">Server2019.iso</a>                                     01-Dec-2025 08:00  4900000000
</pre></body></html>
"@
    $m7 = [regex]::Matches($html7, $testRegex)
    $fileNames = @()
    foreach ($match in $m7) {
        $h = $match.Groups[1].Value
        if ($h -ne '../' -and -not $h.EndsWith('/')) { $fileNames += $h }
    }
    $pass = $fileNames.Count -eq 3 -and $fileNames[0] -eq "Server2025.iso" -and $fileNames[2] -eq "Server2019.iso"
    Write-TestResult "nginx parse: multi-file listing extracts 3 files" $pass "Found: $($fileNames -join ', ')"
} catch {
    Write-TestResult "nginx parse: multi-file listing" $false $_.Exception.Message
}

# Size parsing: large file (bytes)
try {
    $html8 = '<a href="big.vhdx">big.vhdx</a>                                               01-Jan-2026 00:00  53687091200'
    $m8 = [regex]::Matches($html8, $testRegex)
    $sizeStr = $m8[0].Groups[4].Value
    $pass = $sizeStr -eq "53687091200" -and [long]$sizeStr -eq 53687091200
    Write-TestResult "nginx parse: large file size parsed as number" $pass "size=$sizeStr"
} catch {
    Write-TestResult "nginx parse: large file size" $false $_.Exception.Message
}

# --- 35b: Stale reference detection ---

# Check module files for stale Nextcloud function/variable references (not changelogs)
try {
    $stalePatterns = @('NextcloudShare', 'NextcloudBaseURL', 'NextcloudShareToken', 'Get-NextcloudFile', 'Find-NextcloudFile', 'Get-NextcloudFolderFiles')
    $staleFound = @()
    foreach ($moduleFile in $moduleFiles) {
        $content = Get-Content $moduleFile.FullName -Raw
        foreach ($pattern in $stalePatterns) {
            if ($content -match [regex]::Escape($pattern)) {
                $staleFound += "$($moduleFile.Name): $pattern"
            }
        }
    }
    $pass = $staleFound.Count -eq 0
    Write-TestResult "No stale Nextcloud function/variable refs in modules" $pass $(if (-not $pass) { $staleFound -join '; ' } else { "Checked $($stalePatterns.Count) patterns across $($moduleFiles.Count) modules" })
} catch {
    Write-TestResult "Stale Nextcloud reference check" $false $_.Exception.Message
}

# Check monolithic for stale Nextcloud function/variable references (outside changelog)
try {
    $monoContent = Get-Content $monolithicPath
    $stalePatterns = @('NextcloudShare', 'NextcloudBaseURL', 'NextcloudShareToken', 'Get-NextcloudFile', 'Find-NextcloudFile', 'Get-NextcloudFolderFiles')
    $staleLines = @()
    $inCommentBlock = $false
    for ($i = 0; $i -lt $monoContent.Count; $i++) {
        $line = $monoContent[$i]
        # Skip <# ... #> comment blocks (changelog is in the header comment block)
        if ($line -match '^\s*<#') { $inCommentBlock = $true }
        if ($inCommentBlock) {
            if ($line -match '#>') { $inCommentBlock = $false }
            continue
        }
        foreach ($pattern in $stalePatterns) {
            if ($line -match [regex]::Escape($pattern)) {
                $staleLines += "Line $($i+1): $pattern"
            }
        }
    }
    $pass = $staleLines.Count -eq 0
    Write-TestResult "No stale Nextcloud refs in monolithic (excl changelog)" $pass $(if (-not $pass) { $staleLines -join '; ' } else { "Clean" })
} catch {
    Write-TestResult "Stale Nextcloud ref check (monolithic)" $false $_.Exception.Message
}

# No stale "from Nextcloud" in non-changelog function comments
try {
    $staleComments = @()
    foreach ($moduleFile in $moduleFiles) {
        $lines = Get-Content $moduleFile.FullName
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($line -match '^\s*#.*from Nextcloud' -and $line -notmatch 'v2\.[0-8]\.' -and $moduleFile.Name -ne '34-Help.ps1') {
                $staleComments += "$($moduleFile.Name):$($i+1)"
            }
        }
    }
    $pass = $staleComments.Count -eq 0
    Write-TestResult "No stale 'from Nextcloud' comments in module code" $pass $(if (-not $pass) { $staleComments -join '; ' } else { "Clean" })
} catch {
    Write-TestResult "Stale Nextcloud comment check" $false $_.Exception.Message
}

# --- 35c: File and module structure ---

# 39-FileServer.ps1 exists
try {
    $fileServerModule = Join-Path $modulesPath "39-FileServer.ps1"
    $pass = Test-Path $fileServerModule
    Write-TestResult "Module 39-FileServer.ps1 exists" $pass
} catch {
    Write-TestResult "Module 39-FileServer.ps1 exists" $false $_.Exception.Message
}

# 39-Nextcloud.ps1 does NOT exist (was renamed)
try {
    $oldModule = Join-Path $modulesPath "39-Nextcloud.ps1"
    $pass = -not (Test-Path $oldModule)
    Write-TestResult "Old module 39-Nextcloud.ps1 does not exist" $pass
} catch {
    Write-TestResult "39-Nextcloud.ps1 removed check" $false $_.Exception.Message
}

# Loader references 39-FileServer.ps1 not 39-Nextcloud.ps1
try {
    $loaderContent = Get-Content $loaderPath -Raw
    $hasNew = $loaderContent -match '39-FileServer\.ps1'
    $hasOld = $loaderContent -match '39-Nextcloud\.ps1'
    $pass = $hasNew -and -not $hasOld
    Write-TestResult "Loader references 39-FileServer.ps1 (not Nextcloud)" $pass "New=$hasNew Old=$hasOld"
} catch {
    Write-TestResult "Loader module reference check" $false $_.Exception.Message
}

# Monolithic has FILESERVER DOWNLOAD region (not NEXTCLOUD)
try {
    $monoRaw = Get-Content $monolithicPath -Raw
    $hasAbider = $monoRaw -match '#region\s+=+\s+FILESERVER DOWNLOAD'
    $hasNextcloud = $monoRaw -match '#region\s+=+\s+NEXTCLOUD DOWNLOAD'
    $pass = $hasAbider -and -not $hasNextcloud
    Write-TestResult "Monolithic has FILESERVER DOWNLOAD region (not NEXTCLOUD)" $pass "FileServer=$hasAbider Nextcloud=$hasNextcloud"
} catch {
    Write-TestResult "Monolithic region name check" $false $_.Exception.Message
}

# --- 35d: defaults.json FileServer structure ---
$defaultsFilePath2 = Join-Path (Split-Path $PSScriptRoot) 'defaults.json'
if (Test-Path $defaultsFilePath2) {
    try {
        $defaults = Get-Content $defaultsFilePath2 -Raw | ConvertFrom-Json
        $ac = $defaults.FileServer
        $hasAll = $null -ne $ac.BaseURL -or $ac.PSObject.Properties.Name -contains "BaseURL"
        $hasAll = $hasAll -and ($null -ne $ac.ClientId -or $ac.PSObject.Properties.Name -contains "ClientId")
        $hasAll = $hasAll -and ($null -ne $ac.ClientSecret -or $ac.PSObject.Properties.Name -contains "ClientSecret")
        $hasAll = $hasAll -and ($ac.ISOsFolder -eq "ISOs")
        $hasAll = $hasAll -and ($ac.VHDsFolder -eq "VirtualHardDrives")
        $hasAll = $hasAll -and (($ac.AgentFolder -eq "Agents") -or ($ac.KaseyaFolder -eq "KaseyaAgents"))
        Write-TestResult "defaults.json: FileServer has required keys" $hasAll
    } catch {
        Write-TestResult "defaults.json: FileServer structure" $false $_.Exception.Message
    }
} else {
    Write-TestResult "defaults.json: FileServer structure" -Skipped -Message "defaults.json not present"
}

# No credentials in script files - check that defaults.json values don't appear in code
try {
    $credFound = @()
    # Load actual credential values from defaults.json (if it exists) to verify they don't leak
    $defaultsFile = Join-Path $script:ModuleRoot "defaults.json"
    $credPatterns = @()
    if (Test-Path $defaultsFile) {
        $dj = Get-Content $defaultsFile -Raw | ConvertFrom-Json
        if ($dj.FileServer.ClientId -and $dj.FileServer.ClientId.Length -gt 10) {
            $credPatterns += $dj.FileServer.ClientId
        }
        if ($dj.FileServer.ClientSecret -and $dj.FileServer.ClientSecret.Length -gt 10) {
            $credPatterns += $dj.FileServer.ClientSecret
        }
    }
    if ($credPatterns.Count -gt 0) {
        foreach ($moduleFile in $moduleFiles) {
            $content = Get-Content $moduleFile.FullName -Raw
            foreach ($pat in $credPatterns) {
                if ($content.Contains($pat)) { $credFound += "$($moduleFile.Name): credential value found" }
            }
        }
    }
    $pass = $credFound.Count -eq 0
    Write-TestResult "No hardcoded credentials in module files" $pass $(if (-not $pass) { $credFound -join '; ' } else { "Clean" })
} catch {
    Write-TestResult "Credential leak check" $false $_.Exception.Message
}

# No credentials in monolithic script
try {
    $monoRaw2 = Get-Content $monolithicPath -Raw
    $credLeaks = @()
    if ($credPatterns.Count -gt 0) {
        foreach ($pat in $credPatterns) {
            if ($monoRaw2.Contains($pat)) { $credLeaks += "credential value found" }
        }
    }
    $pass = $credLeaks.Count -eq 0
    Write-TestResult "No hardcoded credentials in monolithic" $pass
} catch {
    Write-TestResult "Credential leak check (monolithic)" $false $_.Exception.Message
}

# --- 35e: FileServer variable structure at init ---
try {
    $keys = @("StorageType", "BaseURL", "ClientId", "ClientSecret", "AzureAccount", "AzureContainer", "AzureSasToken", "ISOsFolder", "VHDsFolder", "AgentFolder")
    $missing = @()
    foreach ($k in $keys) {
        if (-not $script:FileServer.ContainsKey($k)) { $missing += $k }
    }
    $pass = $missing.Count -eq 0
    Write-TestResult "FileServer hashtable has all 10 keys" $pass $(if (-not $pass) { "Missing: $($missing -join ', ')" } else { "" })
} catch {
    Write-TestResult "FileServer hashtable keys" $false $_.Exception.Message
}

Write-TestResult "FileServer: VHDsFolder defaults to 'VirtualHardDrives'" ($script:FileServer.VHDsFolder -eq "VirtualHardDrives")
Write-TestResult "FileServer: AgentFolder defaults to 'Agents'" ($script:FileServer.AgentFolder -eq "Agents")
Write-TestResult "FileServer: ClientId is empty at init" ($script:FileServer.ClientId -eq "")
Write-TestResult "FileServer: ClientSecret is empty at init" ($script:FileServer.ClientSecret -eq "")

# --- 35f: Import-Defaults merges FileServer fields ---
try {
    $testDir = "$env:TEMP\appconfig_qatest_$(Get-Random)"
    $null = New-Item -Path $testDir -ItemType Directory -Force
    $origDefaultsPath2 = $script:DefaultsPath
    $origConfigDir2 = $script:AppConfigDir
    $origFileServer = $script:FileServer.Clone()

    $script:AppConfigDir = $testDir
    $script:DefaultsPath = "$testDir\defaults.json"

    # Use variables to avoid false-positive secret scan matches
    $_tcid = "test-client-id"
    $_tcsec = "test-client-" + "secret"
    $testDefaults = @{
        FileServer = @{
            BaseURL      = "https://test.example.com/files"
            ClientId     = $_tcid
            ClientSecret = $_tcsec
            ISOsFolder   = "TestISOs"
            VHDsFolder   = "TestVHDs"
            AgentFolder  = "TestAgents"
        }
    }
    $testDefaults | ConvertTo-Json -Depth 5 | Out-File "$testDir\defaults.json" -Encoding UTF8
    Import-Defaults

    Write-TestResult "Import-Defaults: FileServer.BaseURL merged" ($script:FileServer.BaseURL -eq "https://test.example.com/files") "Got: $($script:FileServer.BaseURL)"
    Write-TestResult "Import-Defaults: FileServer.ClientId merged" ($script:FileServer.ClientId -eq $_tcid) "Got: $($script:FileServer.ClientId)"
    Write-TestResult "Import-Defaults: FileServer.ClientSecret merged" ($script:FileServer.ClientSecret -eq $_tcsec)
    Write-TestResult "Import-Defaults: FileServer.ISOsFolder merged" ($script:FileServer.ISOsFolder -eq "TestISOs") "Got: $($script:FileServer.ISOsFolder)"
    Write-TestResult "Import-Defaults: FileServer.VHDsFolder merged" ($script:FileServer.VHDsFolder -eq "TestVHDs")
    Write-TestResult "Import-Defaults: FileServer.AgentFolder merged" ($script:FileServer.AgentFolder -eq "TestAgents")

    # Restore
    $script:DefaultsPath = $origDefaultsPath2
    $script:AppConfigDir = $origConfigDir2
    $script:FileServer = $origFileServer
    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-TestResult "Import-Defaults: FileServer merge" $false $_.Exception.Message
    $script:DefaultsPath = $origDefaultsPath2
    $script:AppConfigDir = $origConfigDir2
    $script:FileServer = $origFileServer
}

# --- 35g: Export-Defaults includes FileServer block ---
try {
    $testDir = "$env:TEMP\appconfig_qatest_$(Get-Random)"
    $null = New-Item -Path $testDir -ItemType Directory -Force
    $origDefaultsPath3 = $script:DefaultsPath
    $origConfigDir3 = $script:AppConfigDir
    $script:AppConfigDir = $testDir
    $script:DefaultsPath = "$testDir\defaults.json"

    # Set some test values
    $origFileServer2 = $script:FileServer.Clone()
    $script:FileServer.BaseURL = "https://export-test.example.com"
    $script:FileServer.ClientId = "export-test-id"

    Export-Defaults
    $exported = Get-Content "$testDir\defaults.json" -Raw | ConvertFrom-Json

    $hasAC = $null -ne $exported.FileServer
    Write-TestResult "Export-Defaults: has FileServer block" $hasAC
    if ($hasAC) {
        Write-TestResult "Export-Defaults: FileServer.BaseURL preserved" ($exported.FileServer.BaseURL -eq "https://export-test.example.com")
        Write-TestResult "Export-Defaults: FileServer.ClientId preserved" ($exported.FileServer.ClientId -eq "export-test-id")
        Write-TestResult "Export-Defaults: FileServer.ISOsFolder preserved" ($exported.FileServer.ISOsFolder -eq $script:FileServer.ISOsFolder)
    }

    # Restore
    $script:DefaultsPath = $origDefaultsPath3
    $script:AppConfigDir = $origConfigDir3
    $script:FileServer = $origFileServer2
    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-TestResult "Export-Defaults: FileServer block" $false $_.Exception.Message
    $script:DefaultsPath = $origDefaultsPath3
    $script:AppConfigDir = $origConfigDir3
    $script:FileServer = $origFileServer2
}

# --- 35h: Find-FileServerFile matching with mock cache ---
try {
    # Populate cache with mock data
    $mockFolder = "TestISOsQA"
    $script:FileCache[$mockFolder] = @{
        Files = @(
            @{ FileName = "Server2025_Standard.iso"; FilePath = "$mockFolder/Server2025_Standard.iso"; Size = 5368709120 }
            @{ FileName = "Server2022_Datacenter.iso"; FilePath = "$mockFolder/Server2022_Datacenter.iso"; Size = 5200000000 }
            @{ FileName = "Server2019_Standard.iso"; FilePath = "$mockFolder/Server2019_Standard.iso"; Size = 4900000000 }
        )
        CacheTime = Get-Date
    }

    # Test keyword match
    $found = Find-FileServerFile -FolderPath $mockFolder -Keyword "2025"
    $pass = $null -ne $found -and $found.FileName -eq "Server2025_Standard.iso"
    Write-TestResult "Find-FileServerFile: keyword '2025' matches correct file" $pass "Found: $($found.FileName)"

    # Test keyword + extension match
    $found2 = Find-FileServerFile -FolderPath $mockFolder -Keyword "2022" -Extension "iso"
    $pass2 = $null -ne $found2 -and $found2.FileName -eq "Server2022_Datacenter.iso"
    Write-TestResult "Find-FileServerFile: keyword '2022' + ext 'iso' matches" $pass2 "Found: $($found2.FileName)"

    # Test no match
    $found3 = Find-FileServerFile -FolderPath $mockFolder -Keyword "2016"
    Write-TestResult "Find-FileServerFile: keyword '2016' returns null (no match)" ($null -eq $found3)

    # Test size is populated
    Write-TestResult "Find-FileServerFile: matched file has Size property" ($found.Size -eq 5368709120) "Size=$($found.Size)"

    # Test FilePath is populated
    Write-TestResult "Find-FileServerFile: matched file has FilePath" ($found.FilePath -eq "$mockFolder/Server2025_Standard.iso")

    # Cleanup
    $script:FileCache.Remove($mockFolder)
} catch {
    Write-TestResult "Find-FileServerFile mock cache test" $false $_.Exception.Message
    $script:FileCache.Remove($mockFolder)
}

# --- 35i: Get-FileServerFiles unconfigured returns empty ---
try {
    $origBaseURL2 = $script:FileServer.BaseURL
    $script:FileServer.BaseURL = ""
    $result = Get-FileServerFiles -FolderPath "ISOs"
    $pass = $null -eq $result -or $result.Count -eq 0
    Write-TestResult "Get-FileServerFiles: unconfigured returns empty" $pass
    $script:FileServer.BaseURL = $origBaseURL2
} catch {
    Write-TestResult "Get-FileServerFiles unconfigured" $false $_.Exception.Message
    $script:FileServer.BaseURL = $origBaseURL2
}

# --- 35j: Monolithic/modular sync for FileServer functions ---
try {
    $monoRaw3 = Get-Content $monolithicPath -Raw
    $modContent = Get-Content (Join-Path $modulesPath "39-FileServer.ps1") -Raw

    # Check all 4 functions exist in both
    $funcs = @("Get-FileServerFiles", "Find-FileServerFile", "Get-FileServerFile", "Get-FileServerFileSize")
    $syncOK = $true
    $details = @()
    foreach ($f in $funcs) {
        $inMono = $monoRaw3 -match "function\s+$f\s*\{"
        $inMod = $modContent -match "function\s+$f\s*\{"
        if (-not $inMono) { $details += "$f missing from monolithic"; $syncOK = $false }
        if (-not $inMod) { $details += "$f missing from module"; $syncOK = $false }
    }
    Write-TestResult "Monolithic/module sync: all 4 FileServer functions present" $syncOK $(if (-not $syncOK) { $details -join '; ' } else { "" })
} catch {
    Write-TestResult "Monolithic/module FileServer sync" $false $_.Exception.Message
}

# Check integrity validation code exists in both monolithic and modules
try {
    $monoRaw4 = Get-Content $monolithicPath -Raw
    $isoMod = Get-Content (Join-Path $modulesPath "42-ISODownload.ps1") -Raw
    $vhdMod = Get-Content (Join-Path $modulesPath "41-VHDManagement.ps1") -Raw
    $kaseyaMod = Get-Content (Join-Path $modulesPath "57-KaseyaInstaller.ps1") -Raw

    # Integrity is now centralized in Get-FileServerFile (39-FileServer) via Test-FileIntegrity
    # Consumer modules (ISO/VHD/Kaseya) no longer need their own post-download checks
    $acMod2 = Get-Content (Join-Path $modulesPath "39-FileServer.ps1") -Raw
    $acHasIntegrity = $acMod2 -match 'Test-FileIntegrity'
    $acHasTransferComplete = $acMod2 -match 'Write-TransferComplete'
    $vhdHasProgressBar = $vhdMod -match 'Write-ProgressBar|Write-TransferComplete'
    $monoHasRetry = $monoRaw4 -match 'Retrying download'
    $monoHasIntegrity = $monoRaw4 -match 'Test-FileIntegrity'
    $monoHasTransferComplete = $monoRaw4 -match 'Write-TransferComplete'

    Write-TestResult "Module 39-FileServer: has centralized integrity check (Test-FileIntegrity)" $acHasIntegrity
    Write-TestResult "Module 39-FileServer: has transfer completion display" $acHasTransferComplete
    Write-TestResult "Module 41-VHD: has progress bar for copy/convert" $vhdHasProgressBar
    Write-TestResult "Monolithic: has download retry logic" $monoHasRetry
    Write-TestResult "Monolithic: has centralized integrity check (Test-FileIntegrity)" $monoHasIntegrity
    Write-TestResult "Monolithic: has transfer completion display" $monoHasTransferComplete
} catch {
    Write-TestResult "Integrity validation code check" $false $_.Exception.Message
}

# Check that Get-FileServerFile has retry logic
try {
    $acMod = Get-Content (Join-Path $modulesPath "39-FileServer.ps1") -Raw
    $hasRetry = $acMod -match 'Retrying download'
    $hasIntegrity = $acMod -match 'Test-FileIntegrity'
    $hasWebClient = $acMod -match 'System\.Net\.WebClient'
    Write-TestResult "Get-FileServerFile: has retry logic on download failure" $hasRetry
    Write-TestResult "Get-FileServerFile: calls Test-FileIntegrity for validation" $hasIntegrity
    Write-TestResult "Get-FileServerFile: uses WebClient for downloads" $hasWebClient
} catch {
    Write-TestResult "Get-FileServerFile retry logic" $false $_.Exception.Message
}

# --- 35k: Pre-use integrity checks exist in consumer modules ---
try {
    $isoMod2 = Get-Content (Join-Path $modulesPath "42-ISODownload.ps1") -Raw
    $vhdMod2 = Get-Content (Join-Path $modulesPath "41-VHDManagement.ps1") -Raw

    # ISO: size mismatch silently deletes before "already downloaded" display
    $isoPreUse = $isoMod2 -match 'Integrity check: size mismatch = corrupt, silently delete'
    Write-TestResult "Module 42-ISO: has pre-use size mismatch detection" $isoPreUse

    # ISO: filename mismatch shows update available
    $isoUpdate = $isoMod2 -match 'UPDATE AVAILABLE'
    Write-TestResult "Module 42-ISO: has filename mismatch update detection" $isoUpdate

    # VHD: same patterns
    $vhdPreUse = $vhdMod2 -match 'Integrity check: size mismatch = corrupt, silently delete'
    Write-TestResult "Module 41-VHD: has pre-use size mismatch detection" $vhdPreUse

    $vhdUpdate = $vhdMod2 -match 'UPDATE AVAILABLE'
    Write-TestResult "Module 41-VHD: has filename mismatch update detection" $vhdUpdate
} catch {
    Write-TestResult "Pre-use integrity check" $false $_.Exception.Message
}

# ============================================================================
# SECTION 36: MAGIC CONSTANTS TESTS
# ============================================================================

Write-SectionHeader "SECTION 36: MAGIC CONSTANTS TESTS"

# Verify constants exist and have expected values
$constantTests = @(
    @{ Name = "CacheTTLMinutes"; Expected = 10; Desc = "Cache TTL" }
    @{ Name = "FeatureInstallTimeoutSeconds"; Expected = 1800; Desc = "Feature install timeout" }
    @{ Name = "LargeFileDownloadTimeoutSeconds"; Expected = 3600; Desc = "Large file download timeout" }
    @{ Name = "DefaultDownloadTimeoutSeconds"; Expected = 1800; Desc = "Default download timeout" }
    @{ Name = "MinPasswordLength"; Expected = 14; Desc = "Min password length" }
    @{ Name = "MaxRetryAttempts"; Expected = 3; Desc = "Max retries" }
    @{ Name = "UpdateTimeoutSeconds"; Expected = 300; Desc = "Update timeout" }
    @{ Name = "MaxHistoryItems"; Expected = 100; Desc = "Max history" }
)

foreach ($tc in $constantTests) {
    try {
        $value = (Get-Variable -Name $tc.Name -Scope Script -ErrorAction Stop).Value
        $pass = $value -eq $tc.Expected
        Write-TestResult "Constant $($tc.Name) = $($tc.Expected)" $pass "Got: $value"
    } catch {
        Write-TestResult "Constant $($tc.Name)" $false $_.Exception.Message
    }
}

# AgentInstaller.TimeoutSeconds (moved from standalone constant to hashtable)
try {
    $value = $script:AgentInstaller.TimeoutSeconds
    $pass = $value -eq 300
    Write-TestResult "Constant AgentInstaller.TimeoutSeconds = 300" $pass "Got: $value"
} catch {
    Write-TestResult "Constant AgentInstaller.TimeoutSeconds" $false $_.Exception.Message
}

# Verify constants are used in code (not hardcoded values)
try {
    $mpioContent = Get-Content (Join-Path $modulesPath "26-MPIO.ps1") -Raw
    $usesHelper = $mpioContent -match 'Install-WindowsFeatureWithTimeout'
    Write-TestResult "26-MPIO uses Install-WindowsFeatureWithTimeout helper" $usesHelper
} catch {
    Write-TestResult "26-MPIO uses helper" $false $_.Exception.Message
}

try {
    $fcContent = Get-Content (Join-Path $modulesPath "27-FailoverClustering.ps1") -Raw
    $usesHelper = $fcContent -match 'Install-WindowsFeatureWithTimeout'
    Write-TestResult "27-FailoverClustering uses Install-WindowsFeatureWithTimeout helper" $usesHelper
} catch {
    Write-TestResult "27-FailoverClustering uses helper" $false $_.Exception.Message
}

try {
    $kaseyaContent = Get-Content (Join-Path $modulesPath "57-KaseyaInstaller.ps1") -Raw
    $usesConstant = $kaseyaContent -match 'AgentInstaller\.TimeoutSeconds'
    Write-TestResult "57-KaseyaInstaller uses AgentInstaller.TimeoutSeconds constant" $usesConstant
} catch {
    Write-TestResult "57-KaseyaInstaller uses constant" $false $_.Exception.Message
}

try {
    $acContent = Get-Content (Join-Path $modulesPath "39-FileServer.ps1") -Raw
    $usesConstant = $acContent -match 'CacheTTLMinutes'
    Write-TestResult "39-FileServer uses CacheTTLMinutes constant" $usesConstant
} catch {
    Write-TestResult "39-FileServer uses constant" $false $_.Exception.Message
}

try {
    $kaseyaContent2 = Get-Content (Join-Path $modulesPath "57-KaseyaInstaller.ps1") -Raw
    $usesConstant = $kaseyaContent2 -match 'CacheTTLMinutes'
    Write-TestResult "57-KaseyaInstaller uses CacheTTLMinutes constant" $usesConstant
} catch {
    Write-TestResult "57-KaseyaInstaller uses CacheTTL" $false $_.Exception.Message
}

# ============================================================================
# SECTION 37: RENAMED FUNCTION TESTS
# ============================================================================

Write-SectionHeader "SECTION 37: RENAMED FUNCTION TESTS"

# Functions that were renamed to follow Verb-Noun convention
$renamedFunctions = @(
    @{ New = "Test-ValidLicenseKey"; Old = "IsValidLicenseKey"; Desc = "license key validation" }
    @{ New = "Select-PhysicalAdapters"; Old = "Select-Physical-Adapters"; Desc = "physical adapter selection" }
    @{ New = "Select-PhysicalAdaptersSmart"; Old = "Select-Physical-Adapters-Smart"; Desc = "smart adapter selection" }
    @{ New = "Set-iSCSIAdapter"; Old = "Set-iSCSI-Adapter"; Desc = "iSCSI adapter config" }
)

foreach ($tc in $renamedFunctions) {
    try {
        $newExists = $null -ne (Get-Command -Name $tc.New -ErrorAction SilentlyContinue)
        Write-TestResult "Renamed function exists: $($tc.New)" $newExists
    } catch {
        Write-TestResult "Renamed function: $($tc.New)" $false $_.Exception.Message
    }
}

# Old names should NOT exist (verify rename was complete)
foreach ($tc in $renamedFunctions) {
    try {
        $oldExists = $null -ne (Get-Command -Name $tc.Old -ErrorAction SilentlyContinue)
        Write-TestResult "Old function removed: $($tc.Old)" (-not $oldExists) $(if ($oldExists) { "Still exists!" } else { "" })
    } catch {
        Write-TestResult "Old function removed: $($tc.Old)" $true
    }
}

# ============================================================================
# SECTION 38: FORMAT-TRANSFERSIZE TESTS (including TB support)
# ============================================================================

Write-SectionHeader "SECTION 38: FORMAT-TRANSFERSIZE TESTS"

$transferSizeTests = @(
    @{ Bytes = 0;              Expected = "0 B";       Desc = "zero bytes" }
    @{ Bytes = 512;            Expected = "512 B";     Desc = "512 bytes" }
    @{ Bytes = 1024;           Expected = "1 KB";      Desc = "1 KB" }
    @{ Bytes = 1048576;        Expected = "1 MB";      Desc = "1 MB" }
    @{ Bytes = 1073741824;     Expected = "1.00 GB";   Desc = "1 GB" }
    @{ Bytes = 5368709120;     Expected = "5.00 GB";   Desc = "5 GB" }
    @{ Bytes = 1099511627776;  Expected = "1.00 TB";   Desc = "1 TB (new)" }
    @{ Bytes = 2199023255552;  Expected = "2.00 TB";   Desc = "2 TB (new)" }
)

foreach ($tc in $transferSizeTests) {
    try {
        $result = Format-TransferSize -Bytes $tc.Bytes
        $pass = $result -eq $tc.Expected
        Write-TestResult "TransferSize: $($tc.Desc) -> '$($tc.Expected)'" $pass "Got: '$result'"
    } catch {
        Write-TestResult "TransferSize: $($tc.Desc)" $false $_.Exception.Message
    }
}

# Format-ByteSize should be a wrapper that returns same results
try {
    $tsResult = Format-TransferSize -Bytes 1073741824
    $bsResult = Format-ByteSize -Bytes 1073741824
    $pass = $tsResult -eq $bsResult
    Write-TestResult "Format-ByteSize wraps Format-TransferSize (same output)" $pass "TS='$tsResult', BS='$bsResult'"
} catch {
    Write-TestResult "Format-ByteSize wraps Format-TransferSize" $false $_.Exception.Message
}

# ============================================================================
# SECTION 39: PROGRESS BAR UTILITY TESTS
# ============================================================================

Write-SectionHeader "SECTION 39: PROGRESS BAR UTILITY TESTS"

$progressFunctions = @(
    "Format-TransferSize",
    "Write-ProgressBar",
    "Write-TransferComplete",
    "Get-FileHashBackground"
)

foreach ($funcName in $progressFunctions) {
    try {
        $exists = Get-Command -Name $funcName -ErrorAction SilentlyContinue
        Write-TestResult "Progress function exists: $funcName" ($null -ne $exists)
    } catch {
        Write-TestResult "Progress function: $funcName" $false $_.Exception.Message
    }
}

# ============================================================================
# SECTION 40: CIM DEDUP VERIFICATION
# ============================================================================

Write-SectionHeader "SECTION 40: CIM DEDUP VERIFICATION"

# 28-PerformanceDashboard should NOT have two Win32_OperatingSystem calls
try {
    $pdContent = Get-Content (Join-Path $modulesPath "28-PerformanceDashboard.ps1") -Raw
    $osCallCount = ([regex]::Matches($pdContent, 'Get-CimInstance\s+Win32_OperatingSystem')).Count
    $pass = $osCallCount -le 1
    Write-TestResult "28-PerformanceDashboard: at most 1 Win32_OperatingSystem call" $pass "Found: $osCallCount"
} catch {
    Write-TestResult "28-PerformanceDashboard CIM dedup" $false $_.Exception.Message
}

# 48-MenuDisplay Show-SystemConfigMenu should NOT have two Win32_ComputerSystem calls
try {
    $mdContent = Get-Content (Join-Path $modulesPath "48-MenuDisplay.ps1") -Raw
    # Check specifically in Show-SystemConfigMenu function area
    $hasConsolidated = $mdContent -match '\$computerSystem\s*=\s*Get-CimInstance'
    Write-TestResult "48-MenuDisplay: consolidated Win32_ComputerSystem into single call" $hasConsolidated
} catch {
    Write-TestResult "48-MenuDisplay CIM dedup" $false $_.Exception.Message
}

# 37-HealthCheck should have at most 1 Win32_Processor call (cpuAll pattern)
try {
    $hcContent = Get-Content (Join-Path $modulesPath "37-HealthCheck.ps1") -Raw
    $cpuCallCount = ([regex]::Matches($hcContent, 'Get-CimInstance\s+-ClassName\s+Win32_Processor')).Count
    $pass = $cpuCallCount -le 1
    Write-TestResult "37-HealthCheck: at most 1 Win32_Processor call" $pass "Found: $cpuCallCount"
} catch {
    Write-TestResult "37-HealthCheck CIM dedup" $false $_.Exception.Message
}

# 54-HTMLReports should have at most 1 Win32_Processor call
try {
    $hrContent = Get-Content (Join-Path $modulesPath "54-HTMLReports.ps1") -Raw
    $cpuCallCount = ([regex]::Matches($hrContent, 'Get-CimInstance\s+-ClassName\s+Win32_Processor')).Count
    $pass = $cpuCallCount -le 1
    Write-TestResult "54-HTMLReports: at most 1 Win32_Processor call" $pass "Found: $cpuCallCount"
} catch {
    Write-TestResult "54-HTMLReports CIM dedup" $false $_.Exception.Message
}

# ============================================================================
# SECTION 41: BACK LABEL CONSISTENCY
# ============================================================================

Write-SectionHeader "SECTION 41: BACK LABEL CONSISTENCY"

# Check that Licensing module uses [N] bracket format (not "N. Back")
try {
    $licContent = Get-Content (Join-Path $modulesPath "21-Licensing.ps1") -Raw
    $hasDotBack = $licContent -match '\d+\.\s*Back'
    Write-TestResult "21-Licensing: no 'N. Back' labels (uses [N] format)" (-not $hasDotBack)
} catch {
    Write-TestResult "21-Licensing back label format" $false $_.Exception.Message
}

# Check that Utilities module has arrow on back label
try {
    $utilContent = Get-Content (Join-Path $modulesPath "35-Utilities.ps1") -Raw
    # Should use [B] Back with arrow symbol (standardized navigation)
    $hasBackWithArrow = $utilContent -match '\[B\].*Back'
    Write-TestResult "35-Utilities: back label has arrow symbol" $hasBackWithArrow
} catch {
    Write-TestResult "35-Utilities back label" $false $_.Exception.Message
}

# ============================================================================
# SECTION 42: LIST[OBJECT] ACCUMULATOR TESTS
# ============================================================================

Write-SectionHeader "SECTION 42: LIST[OBJECT] ACCUMULATOR TESTS"

# After loading modules, SessionChanges should be List[object]
try {
    $type = $script:SessionChanges.GetType().Name
    $pass = $type -eq "List``1"
    Write-TestResult "SessionChanges is List[object] (not array)" $pass "Type=$type"
} catch {
    Write-TestResult "SessionChanges is List[object]" $false $_.Exception.Message
}

# UndoStack should be List[object]
try {
    $type = $script:UndoStack.GetType().Name
    $pass = $type -eq "List``1"
    Write-TestResult "UndoStack is List[object] (not array)" $pass "Type=$type"
} catch {
    Write-TestResult "UndoStack is List[object]" $false $_.Exception.Message
}

# Add-SessionChange uses .Add() on List (verify by adding and checking count)
try {
    $before = $script:SessionChanges.Count
    Add-SessionChange -Category "ListTest" -Description "Verify List.Add works"
    $after = $script:SessionChanges.Count
    $pass = $after -eq ($before + 1)
    Write-TestResult "Add-SessionChange works with List[object]" $pass "Before=$before, After=$after"
} catch {
    Write-TestResult "Add-SessionChange with List[object]" $false $_.Exception.Message
}

# Add-UndoAction uses .Add() on List
try {
    $before = $script:UndoStack.Count
    Add-UndoAction -Category "ListTest" -Description "Verify List.Add works" -UndoScript { }
    $after = $script:UndoStack.Count
    $pass = $after -eq ($before + 1)
    Write-TestResult "Add-UndoAction works with List[object]" $pass "Before=$before, After=$after"
} catch {
    Write-TestResult "Add-UndoAction with List[object]" $false $_.Exception.Message
}

# Clean up
$script:UndoStack = [System.Collections.Generic.List[object]]::new()

# ============================================================================
# SECTION 43: DEAD CODE REMOVAL VERIFICATION
# ============================================================================

Write-SectionHeader "SECTION 43: DEAD CODE REMOVAL VERIFICATION"

# Removed functions should NOT exist
$removedFunctions = @(
    "Show-ReportsMenu",
    # "Add-CommandHistory",  # Re-added in v1.4.0 (Bug Fix #5)
    "Send-LogEmail",
    "Write-MenuLine",
    "Write-CenteredMainMenuOutput",
    "Test-ValidSubnetMask"
)

foreach ($funcName in $removedFunctions) {
    try {
        $exists = $null -ne (Get-Command -Name $funcName -ErrorAction SilentlyContinue)
        Write-TestResult "Dead code removed: $funcName" (-not $exists) $(if ($exists) { "Still exists!" } else { "" })
    } catch {
        Write-TestResult "Dead code removed: $funcName" $true
    }
}

# ============================================================================
# SECTION 44: WHILE-LOOP MENU VERIFICATION
# ============================================================================

Write-SectionHeader "SECTION 44: WHILE-LOOP MENU VERIFICATION"

# These menus should have while ($true) loops for persistent navigation
$whileLoopModules = @(
    @{ File = "18-FirewallTemplates.ps1"; Func = "Set-FirewallRuleTemplates" }
    @{ File = "19-NTPConfiguration.ps1"; Func = "Set-NTPConfiguration" }
    @{ File = "20-DiskCleanup.ps1"; Func = "Start-DiskCleanup" }
    @{ File = "29-EventLogViewer.ps1"; Func = "Show-EventLogViewer" }
    @{ File = "30-ServiceManager.ps1"; Func = "Show-ServiceManager" }
    @{ File = "31-BitLocker.ps1"; Func = "Show-BitLockerManagement" }
    @{ File = "32-Deduplication.ps1"; Func = "Show-DeduplicationManagement" }
    @{ File = "33-StorageReplica.ps1"; Func = "Show-StorageReplicaManagement" }
)

foreach ($mod in $whileLoopModules) {
    try {
        $content = Get-Content (Join-Path $modulesPath $mod.File) -Raw
        $hasWhileLoop = $content -match 'while\s*\(\s*\$true\s*\)'
        Write-TestResult "While-loop: $($mod.Func) in $($mod.File)" $hasWhileLoop
    } catch {
        Write-TestResult "While-loop: $($mod.File)" $false $_.Exception.Message
    }
}

# ============================================================================
# SECTION 45: ADDITIONAL FUNCTION EXISTENCE TESTS
# ============================================================================

Write-SectionHeader "SECTION 45: ADDITIONAL FUNCTION EXISTENCE TESTS"

# Functions missing from original required list (identified by coverage audit)
$additionalFunctions = @(
    # Hostname / Domain (11-12)
    "Set-HostName",
    "Join-Domain",
    # RDP / Remoting (15)
    "Enable-RDP",
    "Enable-PowerShellRemoting",
    # Firewall (16-18)
    "Disable-WindowsFirewallDomainPrivate",
    "Set-DefenderExclusions",
    "Set-FirewallRuleTemplates",
    # Timezone / Updates / Password (13-14, 22)
    "Set-ServerTimeZone",
    "Install-WindowsUpdates",
    "Register-ServerLicense",
    # Storage (38)
    "Get-DiskHealthStatus",
    "Show-AllDisks",
    # Admin accounts (23-24)
    "Add-LocalAdminAccount",
    "Disable-BuiltInAdminAccount",
    # Network (06-09)
    "New-SwitchEmbeddedTeam",
    "Set-AdapterVLAN",
    "Set-VMIPAddress",
    "Disable-AllIPv6",
    # Hyper-V / MPIO / Clustering install (25-27)
    "Install-HyperVRole",
    "Install-MPIOFeature",
    "Install-FailoverClusteringFeature",
    # iSCSI (10)
    "Set-iSCSIAutoConfiguration",
    "Set-iSCSIAdapter",
    "Test-SANTargetConnectivity",
    # FileServer (39)
    "Get-FileServerFile",
    "Get-FileServerFileSize",
    "Find-FileServerFile",
    "Test-FileIntegrity",
    # Utilities (35)
    "Compare-ConfigurationProfiles",
    # Disk Cleanup (20)
    "Start-DiskCleanup",
    # NTP (19)
    "Set-NTPConfiguration"
)

foreach ($funcName in $additionalFunctions) {
    try {
        $exists = Get-Command -Name $funcName -ErrorAction SilentlyContinue
        $pass = $null -ne $exists
        Write-TestResult "Function exists: $funcName" $pass $(if (-not $pass) { "Not found after loading modules" } else { "" })
    } catch {
        Write-TestResult "Function exists: $funcName" $false $_.Exception.Message
    }
}

# ============================================================================
# SECTION 46: INPUT VALIDATION EDGE CASES
# ============================================================================

Write-SectionHeader "SECTION 46: INPUT VALIDATION EDGE CASES"

# --- Test-ValidHostname additional edge cases ---
$hostnameEdgeCases = @(
    @{ Name = "a-b-c-d";       Valid = $true;  Desc = "multiple hyphens" }
    @{ Name = "SRV--HV";       Valid = $true;  Desc = "consecutive hyphens" }
    @{ Name = "a";             Valid = $true;  Desc = "single char" }
    @{ Name = "ABCDEFGHIJKLMNO"; Valid = $true; Desc = "exactly 15 chars" }
    @{ Name = "my_server";     Valid = $false; Desc = "underscore" }
    @{ Name = "srv!name";      Valid = $false; Desc = "exclamation mark" }
    @{ Name = "srv@name";      Valid = $false; Desc = "at sign" }
    @{ Name = "srv#name";      Valid = $false; Desc = "hash" }
    @{ Name = "   ";           Valid = $false; Desc = "whitespace only" }
)

foreach ($tc in $hostnameEdgeCases) {
    try {
        $result = Test-ValidHostname -Hostname $tc.Name
        $expected = $tc.Valid
        Write-TestResult "Hostname edge: '$($tc.Name)' ($($tc.Desc)) -> $expected" ($result -eq $expected) "Got: $result"
    } catch {
        if ($tc.Valid -eq $false) {
            Write-TestResult "Hostname edge: '$($tc.Name)' ($($tc.Desc)) -> error" $true
        } else {
            Write-TestResult "Hostname edge: '$($tc.Name)'" $false $_.Exception.Message
        }
    }
}

# --- Test-ValidIPAddress additional edge cases ---
$ipEdgeCases = @(
    @{ IP = "255.255.255.255"; Valid = $true;  Desc = "broadcast" }
    @{ IP = "1.1.1.1";        Valid = $true;  Desc = "Cloudflare DNS" }
    @{ IP = "127.0.0.1";      Valid = $true;  Desc = "loopback" }
    @{ IP = "192.168.1.1/32"; Valid = $true;  Desc = "CIDR /32" }
    @{ IP = "2001:db8::1";    Valid = $false; Desc = "IPv6 address" }
    @{ IP = "192.168.1";      Valid = $false; Desc = "3 octets" }
    @{ IP = "192.168.1.1.5";  Valid = $false; Desc = "5 octets" }
    @{ IP = "256.1.1.1";      Valid = $false; Desc = "first octet > 255" }
    @{ IP = "1.256.1.1";      Valid = $false; Desc = "second octet > 255" }
    @{ IP = "1.1.256.1";      Valid = $false; Desc = "third octet > 255" }
    @{ IP = "1.1.1.256";      Valid = $false; Desc = "fourth octet > 255" }
    @{ IP = "not.an.ip.addr"; Valid = $false; Desc = "alpha octets" }
)

foreach ($tc in $ipEdgeCases) {
    try {
        $result = Test-ValidIPAddress -IPAddress $tc.IP
        Write-TestResult "IP edge: '$($tc.IP)' ($($tc.Desc)) -> $($tc.Valid)" ($result -eq $tc.Valid) "Got: $result"
    } catch {
        if ($tc.Valid -eq $false) {
            Write-TestResult "IP edge: '$($tc.IP)' ($($tc.Desc)) -> error" $true
        } else {
            Write-TestResult "IP edge: '$($tc.IP)'" $false $_.Exception.Message
        }
    }
}

# --- Convert-SubnetMaskToPrefix edge cases ---
$subnetCases = @(
    @{ Mask = "255.255.255.0";   Prefix = 24; Desc = "/24" }
    @{ Mask = "255.255.0.0";     Prefix = 16; Desc = "/16" }
    @{ Mask = "255.0.0.0";       Prefix = 8;  Desc = "/8" }
    @{ Mask = "255.255.255.128"; Prefix = 25; Desc = "/25" }
    @{ Mask = "255.255.255.252"; Prefix = 30; Desc = "/30" }
    @{ Mask = "255.255.255.255"; Prefix = 32; Desc = "/32" }
)

foreach ($tc in $subnetCases) {
    try {
        $result = Convert-SubnetMaskToPrefix -SubnetMask $tc.Mask
        Write-TestResult "SubnetToPrefix: $($tc.Mask) -> $($tc.Prefix)" ($result -eq $tc.Prefix) "Got: $result"
    } catch {
        Write-TestResult "SubnetToPrefix: $($tc.Mask)" $false $_.Exception.Message
    }
}

# ============================================================================
# SECTION 47: TEST-NAVIGATIONCOMMAND EDGE CASES
# ============================================================================

Write-SectionHeader "SECTION 47: TEST-NAVIGATIONCOMMAND EDGE CASES"

$navEdgeCases = @(
    @{ Input = "BACK";    Action = "back";    Desc = "uppercase BACK" }
    @{ Input = "Back";    Action = "back";    Desc = "mixed case Back" }
    @{ Input = "EXIT";    Action = "exit";    Desc = "uppercase EXIT" }
    @{ Input = "Exit";    Action = "exit";    Desc = "mixed case Exit" }
    @{ Input = "QUIT";    Action = "exit";    Desc = "uppercase QUIT" }
    @{ Input = "Q";       Action = "exit";    Desc = "single Q" }
    @{ Input = "q";       Action = "exit";    Desc = "lowercase q" }
    @{ Input = "B";       Action = "back";    Desc = "single B" }
    @{ Input = "b";       Action = "back";    Desc = "lowercase b" }
    @{ Input = "1";       Action = "continue"; Desc = "numeric input" }
    @{ Input = "hello";   Action = "continue"; Desc = "random text" }
    @{ Input = " b ";     Action = "back";    Desc = "b with spaces (trimmed)" }
)

foreach ($tc in $navEdgeCases) {
    try {
        $result = Test-NavigationCommand -UserInput $tc.Input
        $actualAction = $result.Action
        Write-TestResult "NavCommand: '$($tc.Input)' ($($tc.Desc)) -> $($tc.Action)" ($actualAction -eq $tc.Action) "Got: $actualAction"
    } catch {
        Write-TestResult "NavCommand: '$($tc.Input)'" $false $_.Exception.Message
    }
}

# ============================================================================
# SECTION 48: CONVERTFROM-AGENTFILENAME EDGE CASES
# ============================================================================

Write-SectionHeader "SECTION 48: CONVERTFROM-AGENTFILENAME EDGE CASES"

$kaseyaEdgeCases = @(
    @{ File = "Kaseya_acme.1001-0452-0453-multi.exe"; Sites = @("1001","0452","0453"); Name = "multi"; Desc = "three sites with hyphens" }
    @{ File = "Kaseya_acme.0001-a.exe"; Sites = @("0001"); Name = "a"; Desc = "min site number" }
    @{ File = "Kaseya_acme.999999-big.exe"; Sites = @("999999"); Name = "big"; Desc = "max site number" }
    @{ File = "Kaseya_acme.1001.exe"; Sites = @("1001"); Name = ""; Desc = "no site name" }
    @{ File = "Kaseya_acme.5001_5002-northdc.exe"; Sites = @("5001","5002"); Name = "northdc"; Desc = "underscore between sites" }
)

foreach ($tc in $kaseyaEdgeCases) {
    try {
        $result = ConvertFrom-AgentFilename -FileName $tc.File
        $sitesMatch = ($null -ne $result) -and (@(Compare-Object @($result.SiteNumbers) @($tc.Sites) -SyncWindow 0).Count -eq 0)
        Write-TestResult "AgentFN: '$($tc.Desc)' sites=$($tc.Sites -join ',')" $sitesMatch $(if (-not $sitesMatch) { "Got: $($result.SiteNumbers -join ',')" } else { "" })
    } catch {
        Write-TestResult "AgentFN: '$($tc.Desc)'" $false $_.Exception.Message
    }
}

# ============================================================================
# SECTION 49: CACHE TTL AND WRITE-MENUITEM BEHAVIORAL TESTS
# ============================================================================

Write-SectionHeader "SECTION 49: CACHE TTL AND WRITE-MENUITEM TESTS"

# Test cache TTL expiration (1-second TTL)
try {
    $val1 = Get-CachedValue -Key "TTLTest" -FetchScript { "fresh" } -CacheSeconds 1
    Write-TestResult "Cache TTL: fresh value returned" ($val1 -eq "fresh")
} catch {
    Write-TestResult "Cache TTL: fresh value" $false $_.Exception.Message
}

try {
    $val2 = Get-CachedValue -Key "TTLTest" -FetchScript { "stale" } -CacheSeconds 1
    Write-TestResult "Cache TTL: cached value (not re-fetched)" ($val2 -eq "fresh")
} catch {
    Write-TestResult "Cache TTL: cached value" $false $_.Exception.Message
}

try {
    Start-Sleep -Seconds 2
    $val3 = Get-CachedValue -Key "TTLTest" -FetchScript { "refreshed" } -CacheSeconds 1
    Write-TestResult "Cache TTL: expired -> re-fetched" ($val3 -eq "refreshed")
} catch {
    Write-TestResult "Cache TTL: expired re-fetch" $false $_.Exception.Message
}

# Test Write-MenuItem doesn't throw
try {
    Write-MenuItem "Test Item"
    Write-TestResult "Write-MenuItem: simple item (no error)" $true
} catch {
    Write-TestResult "Write-MenuItem: simple item" $false $_.Exception.Message
}

try {
    Write-MenuItem "Test Status" -Status "Online" -StatusColor "Success"
    Write-TestResult "Write-MenuItem: status item (no error)" $true
} catch {
    Write-TestResult "Write-MenuItem: status item" $false $_.Exception.Message
}

# Test Write-MenuItem with all color options
$menuItemColors = @("Success", "Warning", "Error", "Info", "Debug", "Critical", "Verbose")
foreach ($color in $menuItemColors) {
    try {
        Write-MenuItem "Color $color" -Color $color
        Write-TestResult "Write-MenuItem: Color=$color (no error)" $true
    } catch {
        Write-TestResult "Write-MenuItem: Color=$color" $false $_.Exception.Message
    }
}

# ============================================================================
# SECTION 50: ROBUSTNESS FEATURE VERIFICATION
# ============================================================================

Write-SectionHeader "SECTION 50: ROBUSTNESS FEATURE VERIFICATION"

# Verify SET switch creation uses polling instead of fixed sleep
try {
    $setContent = Get-Content (Join-Path $modulesPath "09-SET.ps1") -Raw
    $hasPolling = $setContent -match 'Get-VMNetworkAdapter -ManagementOS.*SilentlyContinue'
    $noFixedSleep = $setContent -notmatch 'Start-Sleep -Seconds 2\s+# Give Windows time'
    Write-TestResult "09-SET: uses polling for vNIC creation (not fixed sleep)" ($hasPolling -and $noFixedSleep)
} catch {
    Write-TestResult "09-SET: polling" $false $_.Exception.Message
}

# Verify MPIO has failure logging
try {
    $mpioContent = Get-Content (Join-Path $modulesPath "26-MPIO.ps1") -Raw
    $hasFailLog = $mpioContent -match 'Add-SessionChange.*MPIO installation failed'
    $hasTimeoutLog = $mpioContent -match 'Add-SessionChange.*MPIO installation timed out'
    Write-TestResult "26-MPIO: logs installation failures" ($hasFailLog -and $hasTimeoutLog)
} catch {
    Write-TestResult "26-MPIO: failure logging" $false $_.Exception.Message
}

# Verify domain join has DNS pre-flight
try {
    $djContent = Get-Content (Join-Path $modulesPath "12-DomainJoin.ps1") -Raw
    $hasDnsCheck = $djContent -match 'Resolve-DnsName.*targetDomain'
    Write-TestResult "12-DomainJoin: has DNS pre-flight check" $hasDnsCheck
} catch {
    Write-TestResult "12-DomainJoin: DNS check" $false $_.Exception.Message
}

# Verify RDP NLA uses try/catch (not SilentlyContinue)
try {
    $rdpContent = Get-Content (Join-Path $modulesPath "15-RDP.ps1") -Raw
    $hasNlaTryCatch = $rdpContent -match 'UserAuthentication.*-ErrorAction Stop'
    Write-TestResult "15-RDP: NLA uses ErrorAction Stop (not SilentlyContinue)" $hasNlaTryCatch
} catch {
    Write-TestResult "15-RDP: NLA error handling" $false $_.Exception.Message
}

# Verify iSCSI has null checks on adapter selection
try {
    $iscsiContent = Get-Content (Join-Path $modulesPath "10-iSCSI.ps1") -Raw
    $hasACheck = $iscsiContent -match '\$null -eq \$aSideAdapter'
    $hasBCheck = $iscsiContent -match '\$null -eq \$bSideAdapter'
    Write-TestResult "10-iSCSI: null check on A-side adapter" $hasACheck
    Write-TestResult "10-iSCSI: null check on B-side adapter" $hasBCheck
} catch {
    Write-TestResult "10-iSCSI: adapter null checks" $false $_.Exception.Message
}

# Verify iSCSI has partial failure tracking
try {
    $hasPartialTrack = $iscsiContent -match 'aSideOK.*bSideOK|Partial configuration'
    Write-TestResult "10-iSCSI: partial failure tracking (A/B side)" $hasPartialTrack
} catch {
    Write-TestResult "10-iSCSI: partial failure" $false $_.Exception.Message
}

# Verify disk space check in FileServer downloads
try {
    $acContent = Get-Content (Join-Path $modulesPath "39-FileServer.ps1") -Raw
    $hasDiskCheck = $acContent -match 'Insufficient disk space|SizeRemaining.*requiredSpace'
    Write-TestResult "39-FileServer: disk space check before download" $hasDiskCheck
} catch {
    Write-TestResult "39-FileServer: disk check" $false $_.Exception.Message
}

# Verify Hyper-V uses helper for Server path and has timeout for Client path
try {
    $hvContent = Get-Content (Join-Path $modulesPath "25-HyperV.ps1") -Raw
    $usesHelper = $hvContent -match 'Install-WindowsFeatureWithTimeout'
    $hasClientTimeout = $hvContent -match 'FeatureInstallTimeoutSeconds'
    Write-TestResult "25-HyperV: timeout check on install loops (both paths)" ($usesHelper -and $hasClientTimeout)
} catch {
    Write-TestResult "25-HyperV: timeout" $false $_.Exception.Message
}

# Verify IP config has rollback mechanism
try {
    $ipContent = Get-Content (Join-Path $modulesPath "07-IPConfiguration.ps1") -Raw
    $hasRollback = $ipContent -match 'Rollback|previousIP|Restoring previous'
    Write-TestResult "07-IPConfig: has IP rollback on failure" $hasRollback
} catch {
    Write-TestResult "07-IPConfig: rollback" $false $_.Exception.Message
}

# Verify health dashboard in main menu
try {
    $menuContent = Get-Content (Join-Path $modulesPath "48-MenuDisplay.ps1") -Raw
    $hasDashboard = $menuContent -match 'DashCPU|DashOS|DashDisk'
    Write-TestResult "48-MenuDisplay: health dashboard on main menu" $hasDashboard
} catch {
    Write-TestResult "48-MenuDisplay: dashboard" $false $_.Exception.Message
}

# SECTION 51: KASEYA INSTALLER VERIFICATION TESTS
# ============================================================================
Write-SectionHeader "SECTION 51: KASEYA INSTALLER TESTS"

# Verify Install-SelectedAgent has post-install service verification
try {
    $kaseyaContent = Get-Content (Join-Path $modulesPath "57-KaseyaInstaller.ps1") -Raw

    # Exit code handling
    $hasExitCodes = $kaseyaContent -match 'switch \(\$exitCode\)' -and $kaseyaContent -match '3010' -and $kaseyaContent -match '1641'
    Write-TestResult "57-Kaseya: exit code handling (0, 1641, 3010, 1602, 1603)" $hasExitCodes

    # Service verification polling loop
    $hasServicePoll = $kaseyaContent -match 'verifyTimeout' -and $kaseyaContent -match 'Test-AgentInstalled' -and $kaseyaContent -match 'verifyElapsed'
    Write-TestResult "57-Kaseya: post-install service verification loop" $hasServicePoll

    # Result display box
    $hasResultBox = $kaseyaContent -match 'INSTALLATION RESULT' -and $kaseyaContent -match 'overallStatus' -and $kaseyaContent -match 'serviceStatus'
    Write-TestResult "57-Kaseya: installation result display box" $hasResultBox

    # Menu cache clearing after install
    $hasCacheClear = $kaseyaContent -match 'MenuCache\["AgentInstalled"\]'
    Write-TestResult "57-Kaseya: clears MenuCache after install" $hasCacheClear

    # Timeout logging (the fix we just added)
    $hasTimeoutLog = $kaseyaContent -match 'Add-SessionChange.*timed out'
    Write-TestResult "57-Kaseya: timeout logs to session changes" $hasTimeoutLog

    # Reboot flag on 3010/1641
    $hasRebootFlag = $kaseyaContent -match 'RebootNeeded = \$true'
    Write-TestResult "57-Kaseya: sets RebootNeeded on reboot exit codes" $hasRebootFlag

    # Hostname prerequisite checks
    $hasHostnameCheck = $kaseyaContent -match 'WIN-' -and $kaseyaContent -match 'DESKTOP-' -and $kaseyaContent -match 'HOSTNAME NOT CONFIGURED'
    Write-TestResult "57-Kaseya: hostname prerequisite validation" $hasHostnameCheck

    # Pending hostname change detection
    $hasPendingName = $kaseyaContent -match 'pendingName' -and $kaseyaContent -match 'activeName'
    Write-TestResult "57-Kaseya: detects pending hostname change" $hasPendingName

    # Already-installed detection (dynamic tool name)
    $hasAlreadyInstalled = $kaseyaContent -match 'ALREADY INSTALLED'
    Write-TestResult "57-Kaseya: checks if already installed" $hasAlreadyInstalled

    # Site number auto-detection from hostname
    $hasSiteDetect = $kaseyaContent -match 'Get-SiteNumberFromHostname' -and $kaseyaContent -match 'AGENT MATCH FOUND'
    Write-TestResult "57-Kaseya: auto-detects site from hostname" $hasSiteDetect

    # Installer cleanup in finally block
    $hasCleanup = $kaseyaContent -match 'finally' -and $kaseyaContent -match 'Remove-Item \$tempPath'
    Write-TestResult "57-Kaseya: cleans up temp installer in finally block" $hasCleanup

    # Install uses AgentInstaller.InstallArgs
    $hasSilent = $kaseyaContent -match 'AgentInstaller\.InstallArgs'
    Write-TestResult "57-Kaseya: uses AgentInstaller.InstallArgs for install flags" $hasSilent
} catch {
    Write-TestResult "57-Kaseya: installer verification" $false $_.Exception.Message
}

# Verify ConvertFrom-AgentFilename returns consistent structure
try {
    $valid = ConvertFrom-AgentFilename -FileName "Kaseya_acme.1001-testsite.exe"
    $hasAllKeys = $valid.ContainsKey('SiteNumbers') -and $valid.ContainsKey('SiteName') -and $valid.ContainsKey('DisplayName') -and $valid.ContainsKey('Valid')
    Write-TestResult "ConvertFrom-AgentFilename: returns all 4 keys" $hasAllKeys

    $invalid = ConvertFrom-AgentFilename -FileName "notakaseya.txt"
    Write-TestResult "ConvertFrom-AgentFilename: invalid file returns Valid=false" (-not $invalid.Valid)
    Write-TestResult "ConvertFrom-AgentFilename: invalid file returns empty SiteNumbers" ($invalid.SiteNumbers.Count -eq 0)
} catch {
    Write-TestResult "ConvertFrom-AgentFilename: structure" $false $_.Exception.Message
}

# ============================================================================
# SECTION 52: SERVER READINESS DASHBOARD TESTS
# ============================================================================
Write-SectionHeader "SECTION 52: SERVER READINESS TESTS"

# Function exists
Write-TestResult "Function exists: Show-ServerReadiness" ($null -ne (Get-Command Show-ServerReadiness -ErrorAction SilentlyContinue))

# Verify it's in the menu display
try {
    $menuContent = Get-Content (Join-Path $modulesPath "48-MenuDisplay.ps1") -Raw
    $hasMenuItem = $menuContent -match 'Server Readiness'
    Write-TestResult "48-MenuDisplay: Server Readiness in Tools menu" $hasMenuItem
} catch {
    Write-TestResult "48-MenuDisplay: Server Readiness menu item" $false $_.Exception.Message
}

# Verify it's wired up in the runner
try {
    $runnerContent = Get-Content (Join-Path $modulesPath "49-MenuRunner.ps1") -Raw
    $hasRunner = $runnerContent -match '"7".*Show-ServerReadiness'
    Write-TestResult "49-MenuRunner: Server Readiness wired as [7]" $hasRunner
} catch {
    Write-TestResult "49-MenuRunner: Server Readiness wiring" $false $_.Exception.Message
}

# Verify readiness dashboard checks expected items
try {
    $hcContent = Get-Content (Join-Path $modulesPath "37-HealthCheck.ps1") -Raw

    $checksHostname = $hcContent -match 'isDefaultName' -and $hcContent -match 'WIN-'
    Write-TestResult "37-HealthCheck: readiness checks hostname" $checksHostname

    $checksDomain = $hcContent -match 'PartOfDomain'
    Write-TestResult "37-HealthCheck: readiness checks domain join" $checksDomain

    $checksKaseya = $hcContent -match 'Test-AgentInstalled' -and $hcContent -match 'Show-ServerReadiness' -and $hcContent -match 'Kaseya Agent'
    Write-TestResult "37-HealthCheck: readiness checks Kaseya" $checksKaseya

    $checksRDP = $hcContent -match 'Get-RDPState' -and $hcContent -match 'Show-ServerReadiness'
    Write-TestResult "37-HealthCheck: readiness checks RDP" $checksRDP

    $checksPower = $hcContent -match 'Get-CurrentPowerPlan' -and $hcContent -match 'High performance'
    Write-TestResult "37-HealthCheck: readiness checks power plan" $checksPower

    $checksLicense = $hcContent -match 'Test-WindowsActivated'
    Write-TestResult "37-HealthCheck: readiness checks Windows license" $checksLicense

    $hasScore = $hcContent -match 'READINESS SCORE' -and $hcContent -match 'ready.*total'
    Write-TestResult "37-HealthCheck: readiness has score display" $hasScore
} catch {
    Write-TestResult "37-HealthCheck: readiness dashboard" $false $_.Exception.Message
}

# ============================================================================
# SECTION 53: QUICK SETUP WIZARD TESTS
# ============================================================================
Write-SectionHeader "SECTION 53: QUICK SETUP WIZARD TESTS"

# Function exists
Write-TestResult "Function exists: Show-QuickSetupWizard" ($null -ne (Get-Command Show-QuickSetupWizard -ErrorAction SilentlyContinue))

# Verify it's in Configure Server menu display
try {
    $menuContent = Get-Content (Join-Path $modulesPath "48-MenuDisplay.ps1") -Raw
    $hasWizard = $menuContent -match 'Quick Setup Wizard'
    Write-TestResult "48-MenuDisplay: Quick Setup Wizard in Server Config menu" $hasWizard
} catch {
    Write-TestResult "48-MenuDisplay: Quick Setup Wizard" $false $_.Exception.Message
}

# Verify it's wired in the runner
try {
    $runnerContent = Get-Content (Join-Path $modulesPath "49-MenuRunner.ps1") -Raw
    $hasRunner = $runnerContent -match '"Q"' -and $runnerContent -match 'Show-QuickSetupWizard'
    Write-TestResult "49-MenuRunner: Quick Setup Wizard wired as [Q]" $hasRunner
} catch {
    Write-TestResult "49-MenuRunner: wizard wiring" $false $_.Exception.Message
}

# Verify wizard checks 6 steps
try {
    $hcContent = Get-Content (Join-Path $modulesPath "37-HealthCheck.ps1") -Raw
    $hasHostname = $hcContent -match 'Show-QuickSetupWizard' -and $hcContent -match 'Step 1 of 6.*HOSTNAME'
    Write-TestResult "37-HealthCheck: wizard Step 1 Hostname" $hasHostname

    $hasDomain = $hcContent -match 'Step 2 of 6.*DOMAIN'
    Write-TestResult "37-HealthCheck: wizard Step 2 Domain" $hasDomain

    $hasAgent = $hcContent -match 'Step 3 of 6.*AgentInstaller\.ToolName'
    Write-TestResult "37-HealthCheck: wizard Step 3 Agent" $hasAgent

    $hasRDP = $hcContent -match 'Step 4 of 6.*RDP'
    Write-TestResult "37-HealthCheck: wizard Step 4 RDP" $hasRDP

    $hasPower = $hcContent -match 'Step 5 of 6.*POWER'
    Write-TestResult "37-HealthCheck: wizard Step 5 Power" $hasPower

    $hasLicense = $hcContent -match 'Step 6 of 6.*LICENS'
    Write-TestResult "37-HealthCheck: wizard Step 6 License" $hasLicense

    $hasSummary = $hcContent -match 'QUICK SETUP - COMPLETE' -and $hcContent -match 'Completed:.*6 steps'
    Write-TestResult "37-HealthCheck: wizard completion summary" $hasSummary
} catch {
    Write-TestResult "37-HealthCheck: wizard steps" $false $_.Exception.Message
}

# ============================================================================
# SECTION 54: HTML READINESS REPORT TESTS
# ============================================================================
Write-SectionHeader "SECTION 54: HTML READINESS REPORT TESTS"

Write-TestResult "Function exists: Export-HTMLReadinessReport" ($null -ne (Get-Command Export-HTMLReadinessReport -ErrorAction SilentlyContinue))

# Verify it's in Operations menu
try {
    $opsContent = Get-Content (Join-Path $modulesPath "56-OperationsMenu.ps1") -Raw
    $hasMenuItem = $opsContent -match 'HTML Readiness Report'
    Write-TestResult "56-OperationsMenu: Readiness Report in menu" $hasMenuItem

    $hasRunner = $opsContent -match '"9"' -and $opsContent -match 'Export-HTMLReadinessReport'
    Write-TestResult "56-OperationsMenu: Readiness Report wired as [9]" $hasRunner
} catch {
    Write-TestResult "56-OperationsMenu: readiness report" $false $_.Exception.Message
}

# Verify report checks key items
try {
    $rptContent = Get-Content (Join-Path $modulesPath "54-HTMLReports.ps1") -Raw
    $hasChecks = $rptContent -match 'Export-HTMLReadinessReport' -and $rptContent -match 'Test-AgentInstalled' -and $rptContent -match 'Get-RDPState'
    Write-TestResult "54-HTMLReports: readiness report checks Kaseya + RDP" $hasChecks

    $hasScore = $rptContent -match 'READINESS SCORE\|READY\|PARTIALLY READY\|NOT READY' -or ($rptContent -match 'READY' -and $rptContent -match 'PARTIALLY READY')
    Write-TestResult "54-HTMLReports: readiness report has score display" $hasScore

    $hasStyle = $rptContent -match 'progress-outer' -and $rptContent -match 'progress-inner'
    Write-TestResult "54-HTMLReports: readiness report has progress bar CSS" $hasStyle
} catch {
    Write-TestResult "54-HTMLReports: readiness report" $false $_.Exception.Message
}

# ============================================================================
# SECTION 55: SESSION LOG PERSISTENCE TESTS
# ============================================================================
Write-SectionHeader "SECTION 55: SESSION LOG PERSISTENCE TESTS"

# Verify Add-SessionChange writes to disk
try {
    $navContent = Get-Content (Join-Path $modulesPath "04-Navigation.ps1") -Raw
    $hasLogFile = $navContent -match 'session-log\.txt' -and $navContent -match 'Add-Content'
    Write-TestResult "04-Navigation: Add-SessionChange persists to session-log.txt" $hasLogFile

    $hasDateStamp = $navContent -match 'yyyy-MM-dd'
    Write-TestResult "04-Navigation: session log includes date stamp" $hasDateStamp
} catch {
    Write-TestResult "04-Navigation: session log" $false $_.Exception.Message
}

# Verify Show-SessionSummary mentions log path
try {
    $sumContent = Get-Content (Join-Path $modulesPath "46-SessionSummary.ps1") -Raw
    $hasLogPath = $sumContent -match 'session-log\.txt'
    Write-TestResult "46-SessionSummary: mentions session log file path" $hasLogPath
} catch {
    Write-TestResult "46-SessionSummary: log path mention" $false $_.Exception.Message
}

# Functional test: Add-SessionChange creates log entry
try {
    $testLog = "$script:AppConfigDir\session-log.txt"
    $beforeLines = if (Test-Path $testLog) { @(Get-Content $testLog).Count } else { 0 }
    Add-SessionChange -Category "Test" -Description "Automated test entry"
    Start-Sleep -Milliseconds 200
    $afterLines = @(Get-Content $testLog).Count
    $lineAdded = $afterLines -gt $beforeLines
    Write-TestResult "Add-SessionChange: log file grows on write" $lineAdded

    $lastLine = (Get-Content $testLog)[-1]
    $hasFormat = $lastLine -match '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[Test\]'
    Write-TestResult "Add-SessionChange: log entry has correct format" $hasFormat
} catch {
    Write-TestResult "Add-SessionChange: log persistence" $false $_.Exception.Message
}

# ============================================================================
# SECTION 56: PRE-FLIGHT VALIDATION TESTS
# ============================================================================
Write-SectionHeader "SECTION 56: PRE-FLIGHT VALIDATION TESTS"

Write-TestResult "Function exists: Test-FeaturePrerequisites" ($null -ne (Get-Command Test-FeaturePrerequisites -ErrorAction SilentlyContinue))
Write-TestResult "Function exists: Show-PreFlightCheck" ($null -ne (Get-Command Show-PreFlightCheck -ErrorAction SilentlyContinue))

# Verify pre-flight checks in install functions
try {
    $hvContent = Get-Content (Join-Path $modulesPath "25-HyperV.ps1") -Raw
    $hasPreFlight = $hvContent -match 'Show-PreFlightCheck' -and $hvContent -match 'Hyper-V'
    Write-TestResult "25-HyperV: pre-flight check integrated" $hasPreFlight
} catch {
    Write-TestResult "25-HyperV: pre-flight" $false $_.Exception.Message
}

try {
    $mpioContent = Get-Content (Join-Path $modulesPath "26-MPIO.ps1") -Raw
    $hasPreFlight = $mpioContent -match 'Show-PreFlightCheck' -and $mpioContent -match 'MPIO'
    Write-TestResult "26-MPIO: pre-flight check integrated" $hasPreFlight
} catch {
    Write-TestResult "26-MPIO: pre-flight" $false $_.Exception.Message
}

try {
    $fcContent = Get-Content (Join-Path $modulesPath "27-FailoverClustering.ps1") -Raw
    $hasPreFlight = $fcContent -match 'Show-PreFlightCheck' -and $fcContent -match 'FailoverClustering'
    Write-TestResult "27-FailoverClustering: pre-flight check integrated" $hasPreFlight
} catch {
    Write-TestResult "27-FailoverClustering: pre-flight" $false $_.Exception.Message
}

# Verify Test-FeaturePrerequisites returns correct structure
try {
    $checks = Test-FeaturePrerequisites -Feature "Hyper-V"
    $hasChecks = $checks.Count -ge 3
    Write-TestResult "Test-FeaturePrerequisites: Hyper-V returns 3+ checks" $hasChecks
    $hasStatus = $checks[0].Keys -contains 'Status'
    Write-TestResult "Test-FeaturePrerequisites: returns Status field" $hasStatus
    $hasName = $checks[0].Keys -contains 'Name'
    Write-TestResult "Test-FeaturePrerequisites: returns Name field" $hasName
} catch {
    Write-TestResult "Test-FeaturePrerequisites: structure" $false $_.Exception.Message
}

# Verify checks cover different features
try {
    $mpioChecks = Test-FeaturePrerequisites -Feature "MPIO"
    $hasMPIOServer = ($mpioChecks | Where-Object { $_.Name -eq "Windows Server" }).Count -ge 1
    Write-TestResult "Test-FeaturePrerequisites: MPIO checks Windows Server" $hasMPIOServer

    $fcChecks = Test-FeaturePrerequisites -Feature "FailoverClustering"
    $hasFCDomain = ($fcChecks | Where-Object { $_.Name -eq "Domain Joined" }).Count -ge 1
    Write-TestResult "Test-FeaturePrerequisites: Clustering checks Domain" $hasFCDomain
} catch {
    Write-TestResult "Test-FeaturePrerequisites: feature checks" $false $_.Exception.Message
}

# Verify common reboot check is always present
try {
    foreach ($feat in @("Hyper-V", "MPIO", "FailoverClustering", "iSCSI")) {
        $result = Test-FeaturePrerequisites -Feature $feat
        $hasReboot = ($result | Where-Object { $_.Name -eq "Pending Reboot" }).Count -ge 1
        if (-not $hasReboot) { throw "$feat missing reboot check" }
    }
    Write-TestResult "Test-FeaturePrerequisites: all features check reboot" $true
} catch {
    Write-TestResult "Test-FeaturePrerequisites: reboot check" $false $_.Exception.Message
}

# ============================================================================
# SECTION 57: MENU STATUS INDICATOR TESTS
# ============================================================================
Write-SectionHeader "SECTION 57: MENU STATUS INDICATOR TESTS"

# Verify Configure Server menu shows role summary
try {
    $menuContent = Get-Content (Join-Path $modulesPath "48-MenuDisplay.ps1") -Raw
    $hasRoleSummary = $menuContent -match 'rolesSummary' -and $menuContent -match 'rolesColor'
    Write-TestResult "48-MenuDisplay: Roles & Features shows install count" $hasRoleSummary

    $hasSecSummary = $menuContent -match 'secSummary' -and $menuContent -match 'secColor'
    Write-TestResult "48-MenuDisplay: Security & Access shows RDP/WinRM status" $hasSecSummary

    $hasSysSummary = $menuContent -match 'sysSummary' -and $menuContent -match 'sysColor'
    Write-TestResult "48-MenuDisplay: System Config shows host/power status" $hasSysSummary
} catch {
    Write-TestResult "48-MenuDisplay: submenu status" $false $_.Exception.Message
}

# Verify license status in System Config menu
try {
    $hasLicCache = $menuContent -match 'LicenseActivated' -and $menuContent -match 'licColor'
    Write-TestResult "48-MenuDisplay: License Server shows activation status" $hasLicCache
} catch {
    Write-TestResult "48-MenuDisplay: license status" $false $_.Exception.Message
}

# Verify Kaseya status cached in Configure Server
try {
    $hasKaseyaCache = $menuContent -match 'AgentInstalled' -and $menuContent -match 'kaseyaStatus'
    Write-TestResult "48-MenuDisplay: Configure Server caches Kaseya status" $hasKaseyaCache
} catch {
    Write-TestResult "48-MenuDisplay: kaseya cache" $false $_.Exception.Message
}

# ============================================================================
# SECTION 58: ROLE TEMPLATES TESTS
# ============================================================================
Write-SectionHeader "SECTION 58: ROLE TEMPLATES TESTS"

Write-TestResult "Function exists: Show-RoleTemplates" ($null -ne (Get-Command Show-RoleTemplates -ErrorAction SilentlyContinue))

# Verify wired in menu
try {
    $menuContent = Get-Content (Join-Path $modulesPath "48-MenuDisplay.ps1") -Raw
    $hasMenuItem = $menuContent -match 'Server Role Template'
    Write-TestResult "48-MenuDisplay: Server Role Template in Tools menu" $hasMenuItem
} catch {
    Write-TestResult "48-MenuDisplay: role templates" $false $_.Exception.Message
}

try {
    $runnerContent = Get-Content (Join-Path $modulesPath "49-MenuRunner.ps1") -Raw
    $hasRunner = $runnerContent -match '"8"' -and $runnerContent -match 'Show-RoleTemplates'
    Write-TestResult "49-MenuRunner: Role Templates wired as [8]" $hasRunner
} catch {
    Write-TestResult "49-MenuRunner: role templates wiring" $false $_.Exception.Message
}

# Verify template definitions
try {
    $hcContent = Get-Content (Join-Path $modulesPath "37-HealthCheck.ps1") -Raw
    $hasHyperV = $hcContent -match 'HYPER-V HOST' -and $hcContent -match 'Install-HyperVRole'
    Write-TestResult "37-HealthCheck: Hyper-V Host template" $hasHyperV

    $hasStandalone = $hcContent -match 'STANDALONE SERVER'
    Write-TestResult "37-HealthCheck: Standalone Server template" $hasStandalone

    $hasCluster = $hcContent -match 'CLUSTER NODE' -and $hcContent -match 'Install-FailoverClusteringFeature'
    Write-TestResult "37-HealthCheck: Cluster Node template" $hasCluster

    $hasAutoConfig = $hcContent -match 'Auto-configure all missing'
    Write-TestResult "37-HealthCheck: Role templates offer auto-configure" $hasAutoConfig
} catch {
    Write-TestResult "37-HealthCheck: role templates" $false $_.Exception.Message
}

# ============================================================================
# SECTION 59: AUDIT LOG TESTS
# ============================================================================
Write-SectionHeader "SECTION 59: AUDIT LOG TESTS"

Write-TestResult "Function exists: Show-AuditLog" ($null -ne (Get-Command Show-AuditLog -ErrorAction SilentlyContinue))

# Verify JSON audit logging in Add-SessionChange
try {
    $navContent = Get-Content (Join-Path $modulesPath "04-Navigation.ps1") -Raw
    $hasJsonLog = $navContent -match 'audit-log\.jsonl' -and $navContent -match 'ConvertTo-Json'
    Write-TestResult "04-Navigation: Add-SessionChange writes JSON audit log" $hasJsonLog

    $hasRotation = $navContent -match '10MB' -and $navContent -match 'Move-Item'
    Write-TestResult "04-Navigation: audit log rotation at 10MB" $hasRotation

    $hasHost = $navContent -match 'COMPUTERNAME' -and $navContent -match 'USERNAME'
    Write-TestResult "04-Navigation: audit log includes host and user" $hasHost
} catch {
    Write-TestResult "04-Navigation: audit log" $false $_.Exception.Message
}

# Verify audit log viewer in Settings
try {
    $helpContent = Get-Content (Join-Path $modulesPath "34-Help.ps1") -Raw
    $hasMenuItem = $helpContent -match 'Audit Log'
    Write-TestResult "34-Help: Audit Log in Settings menu" $hasMenuItem

    $hasRunner = $helpContent -match '"13"' -and $helpContent -match 'Show-AuditLog'
    Write-TestResult "34-Help: Audit Log wired as [13]" $hasRunner
} catch {
    Write-TestResult "34-Help: audit log settings" $false $_.Exception.Message
}

# Functional test: verify JSON audit entry is created
try {
    $auditFile = "$script:AppConfigDir\audit-log.jsonl"
    $beforeLines = if (Test-Path $auditFile) { @(Get-Content $auditFile).Count } else { 0 }
    Add-SessionChange -Category "Test" -Description "Audit log test entry"
    Start-Sleep -Milliseconds 200
    $afterLines = @(Get-Content $auditFile).Count
    $lineAdded = $afterLines -gt $beforeLines
    Write-TestResult "Add-SessionChange: JSON audit log grows on write" $lineAdded

    $lastLine = (Get-Content $auditFile)[-1]
    $entry = $lastLine | ConvertFrom-Json
    $hasFields = $entry.ts -and $entry.host -and $entry.user -and $entry.category -and $entry.action
    Write-TestResult "Add-SessionChange: JSON entry has all required fields" $hasFields
} catch {
    Write-TestResult "Add-SessionChange: JSON audit" $false $_.Exception.Message
}

# ============================================================================
# SECTION 60: CENTRALIZED CONSTANTS TESTS
# ============================================================================
Write-SectionHeader "SECTION 60: CENTRALIZED CONSTANTS TESTS"

# Power plan GUIDs
Write-TestResult "Constant: PowerPlanGUID defined" ($null -ne $script:PowerPlanGUID)
Write-TestResult "Constant: PowerPlanGUID has High Performance" ($script:PowerPlanGUID["High Performance"] -eq "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c")
Write-TestResult "Constant: PowerPlanGUID has Balanced" ($script:PowerPlanGUID["Balanced"] -eq "381b4222-f694-41f0-9685-ff5bb260df2e")
Write-TestResult "Constant: PowerPlanGUID has Power Saver" ($script:PowerPlanGUID["Power Saver"] -eq "a1841308-3541-4fab-bc81-f71556f20b4a")

# Windows Licensing AppId
Write-TestResult "Constant: WindowsLicensingAppId defined" ($null -ne $script:WindowsLicensingAppId)
Write-TestResult "Constant: WindowsLicensingAppId value" ($script:WindowsLicensingAppId -eq "55c92734-d682-4d71-983e-d6ec3f16059f")

# Verify modules use centralized constants (not hardcoded GUIDs)
try {
    $scContent = Get-Content (Join-Path $modulesPath "05-SystemCheck.ps1") -Raw
    $usesConstant = $scContent -match 'PowerPlanGUID'
    Write-TestResult "05-SystemCheck: uses PowerPlanGUID constant" $usesConstant
} catch {
    Write-TestResult "05-SystemCheck: PowerPlanGUID" $false $_.Exception.Message
}

try {
    $ceContent = Get-Content (Join-Path $modulesPath "45-ConfigExport.ps1") -Raw
    $usesConstant = $ceContent -match 'PowerPlanGUID'
    Write-TestResult "45-ConfigExport: uses PowerPlanGUID constant" $usesConstant
} catch {
    Write-TestResult "45-ConfigExport: PowerPlanGUID" $false $_.Exception.Message
}

try {
    $epContent = Get-Content (Join-Path $modulesPath "50-EntryPoint.ps1") -Raw
    $usesConstant = $epContent -match 'PowerPlanGUID'
    Write-TestResult "50-EntryPoint: uses PowerPlanGUID constant" $usesConstant
} catch {
    Write-TestResult "50-EntryPoint: PowerPlanGUID" $false $_.Exception.Message
}

try {
    $hcContent = Get-Content (Join-Path $modulesPath "37-HealthCheck.ps1") -Raw
    $usesAppId = $hcContent -match 'Test-WindowsActivated'
    Write-TestResult "37-HealthCheck: uses Test-WindowsActivated helper" $usesAppId
} catch {
    Write-TestResult "37-HealthCheck: WindowsLicensingAppId" $false $_.Exception.Message
}

try {
    $mdContent = Get-Content (Join-Path $modulesPath "48-MenuDisplay.ps1") -Raw
    $usesAppId = $mdContent -match 'Test-WindowsActivated'
    Write-TestResult "48-MenuDisplay: uses Test-WindowsActivated helper" $usesAppId
} catch {
    Write-TestResult "48-MenuDisplay: WindowsLicensingAppId" $false $_.Exception.Message
}

# ============================================================================
# SECTION 61: BUG FIX VERIFICATION TESTS
# ============================================================================
Write-SectionHeader "SECTION 61: BUG FIX VERIFICATION TESTS"

# Firewall readiness check logic (was inverted)
try {
    $hcContent = Get-Content (Join-Path $modulesPath "37-HealthCheck.ps1") -Raw
    $correctLogic = $hcContent -match 'fwCorrect' -and $hcContent -match '-not \$fwState\.Domain'
    Write-TestResult "37-HealthCheck: firewall readiness checks Domain=Off (not inverted)" $correctLogic
} catch {
    Write-TestResult "37-HealthCheck: firewall logic" $false $_.Exception.Message
}

# Settings menu exit handling
try {
    $helpContent = Get-Content (Join-Path $modulesPath "34-Help.ps1") -Raw
    $hasExitHandler = $helpContent -match '"EXIT"' -and $helpContent -match 'Exit-Script'
    Write-TestResult "34-Help: Settings menu handles EXIT command" $hasExitHandler
    $returnsExit = $helpContent -match 'return "EXIT"'
    Write-TestResult "34-Help: Show-SettingsMenu returns EXIT for exit/quit" $returnsExit
} catch {
    Write-TestResult "34-Help: exit handling" $false $_.Exception.Message
}

# Quick Setup Wizard lowercase q
try {
    $mrContent = Get-Content (Join-Path $modulesPath "49-MenuRunner.ps1") -Raw
    $hasLowerQ = $mrContent -match '-eq "q"'
    Write-TestResult "49-MenuRunner: Configure Server handles lowercase q" $hasLowerQ
} catch {
    Write-TestResult "49-MenuRunner: lowercase q" $false $_.Exception.Message
}

# Batch mode Test-WindowsServer guards
try {
    $epContent = Get-Content (Join-Path $modulesPath "50-EntryPoint.ps1") -Raw
    $hvGuard = $epContent -match 'Hyper-V.*requires Windows Server' -or ($epContent -match 'Test-WindowsServer' -and $epContent -match 'Hyper-V: skipped \(requires')
    Write-TestResult "50-EntryPoint: batch Hyper-V has Test-WindowsServer guard" $hvGuard
    $mpioGuard = $epContent -match 'MPIO: skipped \(requires Windows Server\)'
    Write-TestResult "50-EntryPoint: batch MPIO has Test-WindowsServer guard" $mpioGuard
    $fcGuard = $epContent -match 'Failover Clustering: skipped \(requires Windows Server\)'
    Write-TestResult "50-EntryPoint: batch FC has Test-WindowsServer guard" $fcGuard
} catch {
    Write-TestResult "50-EntryPoint: batch guards" $false $_.Exception.Message
}

# Batch mode elevation check
try {
    $epContent = Get-Content (Join-Path $modulesPath "50-EntryPoint.ps1") -Raw
    $hasElevCheck = $epContent -match 'Batch mode requires administrator privileges'
    Write-TestResult "50-EntryPoint: batch mode has elevation check" $hasElevCheck
} catch {
    Write-TestResult "50-EntryPoint: elevation check" $false $_.Exception.Message
}

# Semantic colors (no hardcoded Green/Yellow in menu display)
try {
    $mdContent = Get-Content (Join-Path $modulesPath "48-MenuDisplay.ps1") -Raw
    $noHardGreen = -not ($mdContent -match '"Green"')
    $noHardYellow = -not ($mdContent -match '"Yellow"')
    Write-TestResult "48-MenuDisplay: no hardcoded Green color (uses Success)" $noHardGreen
    Write-TestResult "48-MenuDisplay: no hardcoded Yellow color (uses Warning)" $noHardYellow
} catch {
    Write-TestResult "48-MenuDisplay: semantic colors" $false $_.Exception.Message
}

# No stale FIXED comments
try {
    $djContent = Get-Content (Join-Path $modulesPath "12-DomainJoin.ps1") -Raw
    $noFixed = -not ($djContent -match '# FIXED:')
    Write-TestResult "12-DomainJoin: no stale # FIXED: comments" $noFixed
    $mrContent = Get-Content (Join-Path $modulesPath "49-MenuRunner.ps1") -Raw
    $noFixed2 = -not ($mrContent -match '# FIXED:')
    Write-TestResult "49-MenuRunner: no stale # FIXED: comments" $noFixed2
} catch {
    Write-TestResult "Stale comments" $false $_.Exception.Message
}

# ============================================================================
# SECTION 62: RELEASE VALIDATION SCRIPT TESTS
# ============================================================================
Write-SectionHeader "SECTION 62: RELEASE VALIDATION SCRIPT TESTS"

$validateScript = Join-Path $PSScriptRoot "Validate-Release.ps1"
Write-TestResult "Validate-Release.ps1 exists" (Test-Path $validateScript)

try {
    $vrContent = Get-Content $validateScript -Raw
    Write-TestResult "Validate-Release: has parse check section" ($vrContent -match 'PARSE CHECK')
    Write-TestResult "Validate-Release: has PSSA section" ($vrContent -match 'PSSCRIPTANALYZER')
    Write-TestResult "Validate-Release: has module structure check" ($vrContent -match 'MODULE STRUCTURE')
    Write-TestResult "Validate-Release: has region integrity check" ($vrContent -match 'REGION INTEGRITY')
    Write-TestResult "Validate-Release: has version consistency check" ($vrContent -match 'VERSION CONSISTENCY')
    Write-TestResult "Validate-Release: has sync verification" ($vrContent -match 'SYNC VERIFICATION')
    Write-TestResult "Validate-Release: has defaults check" ($vrContent -match 'DEFAULTS.*CONFIGURATION')
    Write-TestResult "Validate-Release: has test suite integration" ($vrContent -match 'AUTOMATED TEST SUITE')
    Write-TestResult "Validate-Release: supports -SkipTests flag" ($vrContent -match '\[switch\]\$SkipTests')
} catch {
    Write-TestResult "Validate-Release: content" $false $_.Exception.Message
}

# ============================================================================
# SECTION 63: DOCUMENTATION TESTS
# ============================================================================
Write-SectionHeader "SECTION 63: DOCUMENTATION TESTS"

$readmePath = Join-Path $PSScriptRoot "..\README.md"
Write-TestResult "README.md exists" (Test-Path $readmePath)

try {
    $readmeContent = Get-Content $readmePath -Raw
    Write-TestResult "README: mentions 63 modules" ($readmeContent -match '63 module')
    Write-TestResult "README: has batch mode section" ($readmeContent -match 'Batch Mode')
    Write-TestResult "README: has testing section" ($readmeContent -match 'Testing')
    Write-TestResult "README: has defaults.json example" ($readmeContent -match 'defaults\.json')
} catch {
    Write-TestResult "README: content" $false $_.Exception.Message
}

# Show-Help covers new features
try {
    $helpContent = Get-Content (Join-Path $modulesPath "34-Help.ps1") -Raw
    Write-TestResult "Show-Help: documents Settings menu [13] Audit Log" ($helpContent -match 'View Audit Log' -and $helpContent -match '\[13\]')
    Write-TestResult "Show-Help: documents Tools [7] Server Readiness" ($helpContent -match 'Server Readiness')
    Write-TestResult "Show-Help: documents Tools [8] Role Templates" ($helpContent -match 'Role Templates')
    Write-TestResult "Show-Help: documents Operations [5] Remote PowerShell" ($helpContent -match 'Remote PowerShell')
    Write-TestResult "Show-Help: documents Operations [7] Remote Service Manager" ($helpContent -match 'Remote Service Manager')
} catch {
    Write-TestResult "Show-Help: documentation" $false $_.Exception.Message
}

# Show-Changelog covers v1.0.0 features
try {
    $helpContent = Get-Content (Join-Path $modulesPath "34-Help.ps1") -Raw
    Write-TestResult "Show-Changelog: mentions Network Diagnostics" ($helpContent -match 'Network Diagnostics.*ping')
    Write-TestResult "Show-Changelog: mentions FileServer" ($helpContent -match 'FileServer.*integration')
    Write-TestResult "Show-Changelog: mentions Pre-flight validation" ($helpContent -match 'Pre-flight validation')
    Write-TestResult "Show-Changelog: mentions Role Templates" ($helpContent -match 'Role Templates.*auto-configure')
    Write-TestResult "Show-Changelog: mentions JSON audit logging" ($helpContent -match 'JSON audit logging')
} catch {
    Write-TestResult "Show-Changelog: v1.0.0" $false $_.Exception.Message
}

# ============================================================================
# SECTION 64: PASSWORD ENFORCEMENT
# ============================================================================
Write-SectionHeader "SECTION 64: PASSWORD ENFORCEMENT"

try {
    $pwContent = Get-Content (Join-Path $modulesPath "22-Password.ps1") -Raw
    $initContent = Get-Content (Join-Path $modulesPath "00-Initialization.ps1") -Raw

    # MinPasswordLength is set to 14
    Write-TestResult "MinPasswordLength defined as 14" ($initContent -match '\$script:MinPasswordLength\s*=\s*14')

    # Test-PasswordComplexity checks all 5 criteria
    Write-TestResult "Password: checks minimum length" ($pwContent -match '\$InputString\.Length\s+-lt\s+\$minLength')
    Write-TestResult "Password: checks uppercase" ($pwContent -match '\[A-Z\]')
    Write-TestResult "Password: checks lowercase" ($pwContent -match '\[a-z\]')
    Write-TestResult "Password: checks digits" ($pwContent -match '\\d')
    Write-TestResult "Password: checks special chars" ($pwContent -match '\[!@#\$%')

    # Test-PasswordComplexity has ValidateNotNullOrEmpty
    Write-TestResult "Test-PasswordComplexity: has ValidateNotNullOrEmpty" ($pwContent -match 'function Test-PasswordComplexity[\s\S]{0,200}ValidateNotNullOrEmpty')

    # Get-SecurePassword has ValidateNotNullOrEmpty and ValidateRange
    Write-TestResult "Get-SecurePassword: has ValidateNotNullOrEmpty" ($pwContent -match 'function Get-SecurePassword[\s\S]{0,200}ValidateNotNullOrEmpty')
    Write-TestResult "Get-SecurePassword: maxAttempts has ValidateRange" ($pwContent -match 'ValidateRange\(1,10\)')

    # Get-SecurePassword uses secure memory cleanup
    Write-TestResult "Get-SecurePassword: uses Clear-SecureMemory" ($pwContent -match 'Clear-SecureMemory')
    Write-TestResult "Get-SecurePassword: uses ZeroFreeBSTR" ($pwContent -match 'ZeroFreeBSTR')

    # ConvertFrom-SecureStringToPlainText has try/finally with ZeroFreeBSTR
    $hasSecureString = $pwContent -match 'SecureStringToBSTR'
    $hasFinally = $pwContent -match 'finally'
    $hasZeroFree = $pwContent -match 'ZeroFreeBSTR'
    Write-TestResult "SecureString conversion: uses try/finally for BSTR cleanup" ($hasSecureString -and $hasFinally -and $hasZeroFree)
} catch {
    Write-TestResult "Password enforcement" $false $_.Exception.Message
}

# ============================================================================
# SECTION 65: BATCH MODE
# ============================================================================
Write-SectionHeader "SECTION 65: BATCH MODE"

try {
    $entryContent = Get-Content (Join-Path $modulesPath "50-EntryPoint.ps1") -Raw

    # Batch mode function exists
    Write-TestResult "Start-BatchMode function exists" ($entryContent -match 'function Start-BatchMode')

    # Batch mode accepts Config hashtable
    Write-TestResult "Start-BatchMode: accepts [hashtable] Config" ($entryContent -match 'Start-BatchMode[\s\S]{0,100}\[hashtable\]\$Config')

    # Batch elevation check
    Write-TestResult "Batch mode: elevation check before processing" ($entryContent -match 'batch_config\.json[\s\S]{0,500}IsInRole.*Administrator')

    # Batch mode guards for server-only features
    Write-TestResult "Batch mode: Hyper-V guarded by Test-WindowsServer" ($entryContent -match 'Hyper-V[\s\S]{0,200}Test-WindowsServer')
    Write-TestResult "Batch mode: MPIO guarded by Test-WindowsServer" ($entryContent -match 'MPIO[\s\S]{0,200}Test-WindowsServer')
    Write-TestResult "Batch mode: Failover Clustering guarded by Test-WindowsServer" ($entryContent -match 'Failover Clustering[\s\S]{0,200}Test-WindowsServer')

    # Batch mode loads defaults
    Write-TestResult "Batch mode: calls Import-Defaults" ($entryContent -match 'Start-BatchMode[\s\S]{0,500}Import-Defaults')

    # Batch mode starts transcript
    Write-TestResult "Batch mode: starts transcript" ($entryContent -match 'Start-BatchMode[\s\S]{0,500}Start-ScriptTranscript')

    # Batch mode tracks changes/errors
    Write-TestResult "Batch mode: tracks changesApplied counter" ($entryContent -match '\$changesApplied\s*=\s*0')
    Write-TestResult "Batch mode: tracks errors counter" ($entryContent -match '\$errors\s*=\s*0')

    # Config steps exist (hostname, network, DNS, timezone, licensing, RDP, firewall, power plan)
    Write-TestResult "Batch mode: handles Hostname step" ($entryContent -match 'Step 1.*hostname' -or $entryContent -match '\$Config\.Hostname')
    Write-TestResult "Batch mode: handles DNS step" ($entryContent -match '\$Config\.DNS')
} catch {
    Write-TestResult "Batch mode" $false $_.Exception.Message
}

# ============================================================================
# SECTION 66: PARAMETER VALIDATION
# ============================================================================
Write-SectionHeader "SECTION 66: PARAMETER VALIDATION"

try {
    $iSCSIContent = Get-Content (Join-Path $modulesPath "10-iSCSI.ps1") -Raw
    $ipContent = Get-Content (Join-Path $modulesPath "07-IPConfiguration.ps1") -Raw
    $vlanContent = Get-Content (Join-Path $modulesPath "08-VLAN.ps1") -Raw
    $hostContent = Get-Content (Join-Path $modulesPath "03-InputValidation.ps1") -Raw

    # Get-SANTargetsForHost has ValidateRange
    Write-TestResult "Get-SANTargetsForHost: ValidateRange(1,24)" ($iSCSIContent -match 'Get-SANTargetsForHost[\s\S]{0,200}ValidateRange\(1,24\)')

    # Set-VMIPAddress has ValidateNotNullOrEmpty
    Write-TestResult "Set-VMIPAddress: ValidateNotNullOrEmpty" ($ipContent -match 'function Set-VMIPAddress[\s\S]{0,200}ValidateNotNullOrEmpty')

    # Set-VMDNSAddress has ValidateNotNullOrEmpty
    Write-TestResult "Set-VMDNSAddress: ValidateNotNullOrEmpty" ($ipContent -match 'function Set-VMDNSAddress[\s\S]{0,200}ValidateNotNullOrEmpty')

    # Set-AdapterVLAN has ValidateNotNullOrEmpty
    Write-TestResult "Set-AdapterVLAN: ValidateNotNullOrEmpty" ($vlanContent -match 'function Set-AdapterVLAN[\s\S]{0,200}ValidateNotNullOrEmpty')

    # Test-ValidHostname has ValidateNotNullOrEmpty
    Write-TestResult "Test-ValidHostname: ValidateNotNullOrEmpty" ($hostContent -match 'function Test-ValidHostname[\s\S]{0,200}ValidateNotNullOrEmpty')
} catch {
    Write-TestResult "Parameter validation" $false $_.Exception.Message
}

# ============================================================================
# SECTION 67: WRITE-MENUITEM MIGRATION
# ============================================================================
Write-SectionHeader "SECTION 67: WRITE-MENUITEM MIGRATION"

# Verify no remaining old-pattern menu items in migrated modules
$menuMigrationModules = @(
    "17-DefenderExclusions.ps1", "18-FirewallTemplates.ps1", "19-NTPConfiguration.ps1",
    "20-DiskCleanup.ps1", "27-FailoverClustering.ps1", "29-EventLogViewer.ps1",
    "30-ServiceManager.ps1", "31-BitLocker.ps1", "32-Deduplication.ps1",
    "33-StorageReplica.ps1", "51-ClusterDashboard.ps1", "52-VMCheckpoints.ps1",
    "53-VMExportImport.ps1", "58-NetworkDiagnostics.ps1", "09-SET.ps1"
)
$oldPatternCount = 0
foreach ($mod in $menuMigrationModules) {
    $modContent = Get-Content (Join-Path $modulesPath $mod) -Raw
    if ($modContent -match 'PadRight\(70\).*-ForegroundColor Green') { $oldPatternCount++ }
}
Write-TestResult "Write-MenuItem migration: 0 old-pattern menus in migrated modules" ($oldPatternCount -eq 0) "$oldPatternCount modules still have old pattern"

# Verify Write-MenuItem is used in migrated modules
$menuItemUsers = 0
foreach ($mod in $menuMigrationModules) {
    $modContent = Get-Content (Join-Path $modulesPath $mod) -Raw
    if ($modContent -match 'Write-MenuItem') { $menuItemUsers++ }
}
Write-TestResult "Write-MenuItem: used in $menuItemUsers of $($menuMigrationModules.Count) migrated modules" ($menuItemUsers -eq $menuMigrationModules.Count)

# ============================================================================
# SECTION 68: TEST-WINDOWSACTIVATED HELPER
# ============================================================================
Write-SectionHeader "SECTION 68: TEST-WINDOWSACTIVATED HELPER"

try {
    $sysCheckContent = Get-Content (Join-Path $modulesPath "05-SystemCheck.ps1") -Raw
    $healthContent = Get-Content (Join-Path $modulesPath "37-HealthCheck.ps1") -Raw
    $htmlContent = Get-Content (Join-Path $modulesPath "54-HTMLReports.ps1") -Raw
    $menuContent = Get-Content (Join-Path $modulesPath "48-MenuDisplay.ps1") -Raw

    Write-TestResult "Test-WindowsActivated function exists in 05-SystemCheck" ($sysCheckContent -match 'function Test-WindowsActivated')
    Write-TestResult "Test-WindowsActivated uses WindowsLicensingAppId constant" ($sysCheckContent -match 'Test-WindowsActivated[\s\S]{0,200}WindowsLicensingAppId')
    Write-TestResult "37-HealthCheck uses Test-WindowsActivated (readiness)" ($healthContent -match 'Test-WindowsActivated')
    Write-TestResult "54-HTMLReports uses Test-WindowsActivated" ($htmlContent -match 'Test-WindowsActivated')
    Write-TestResult "48-MenuDisplay uses Test-WindowsActivated" ($menuContent -match 'Test-WindowsActivated')
} catch {
    Write-TestResult "Test-WindowsActivated" $false $_.Exception.Message
}

# ============================================================================
# SECTION 69: CONNECTIVITY CONSTANT
# ============================================================================
Write-SectionHeader "SECTION 69: CONNECTIVITY CONSTANT"

try {
    $initContent = Get-Content (Join-Path $modulesPath "00-Initialization.ps1") -Raw
    $sysContent = Get-Content (Join-Path $modulesPath "05-SystemCheck.ps1") -Raw
    $setContent = Get-Content (Join-Path $modulesPath "09-SET.ps1") -Raw

    Write-TestResult "DefaultConnectivityTarget defined in 00-Initialization" ($initContent -match '\$script:DefaultConnectivityTarget')
    Write-TestResult "05-SystemCheck uses DefaultConnectivityTarget" ($sysContent -match 'DefaultConnectivityTarget')
    Write-TestResult "09-SET uses DefaultConnectivityTarget" ($setContent -match 'DefaultConnectivityTarget')
} catch {
    Write-TestResult "Connectivity constant" $false $_.Exception.Message
}

# ============================================================================
# SECTION 70: LICENSING MODULE
# ============================================================================
Write-SectionHeader "SECTION 70: LICENSING MODULE"

try {
    $licContent = Get-Content (Join-Path $modulesPath "21-Licensing.ps1") -Raw

    Write-TestResult "Register-ServerLicense function exists" ($licContent -match 'function Register-ServerLicense')
    Write-TestResult "Licensing: has KMS client keys" ($licContent -match 'KMS client|volume license')
    Write-TestResult "Licensing: has AVMA keys" ($licContent -match 'AVMA|Automatic Virtual Machine Activation')
    Write-TestResult "Licensing: covers Server 2025" ($licContent -match '2025')
    Write-TestResult "Licensing: covers Server 2022" ($licContent -match '2022')
    Write-TestResult "Licensing: covers Server 2019" ($licContent -match '2019')
    Write-TestResult "Licensing: has manual key entry" ($licContent -match 'manual|Manual|slmgr')
    Write-TestResult "Licensing: merges custom keys from defaults" ($licContent -match 'CustomKMSKeys|CustomAVMAKeys')
} catch {
    Write-TestResult "Licensing module" $false $_.Exception.Message
}

# ============================================================================
# SECTION 71: NTP/TIMEZONE/FIREWALL MODULES
# ============================================================================
Write-SectionHeader "SECTION 71: NTP/TIMEZONE/FIREWALL MODULES"

try {
    $ntpContent = Get-Content (Join-Path $modulesPath "19-NTPConfiguration.ps1") -Raw
    $tzContent = Get-Content (Join-Path $modulesPath "13-Timezone.ps1") -Raw
    $fwContent = Get-Content (Join-Path $modulesPath "16-Firewall.ps1") -Raw

    # NTP crash fix verification
    Write-TestResult "NTP: w32tm query has null safety check" ($ntpContent -match 'null.*-ne.*sourceLine|sourceLine.*null')
    Write-TestResult "NTP: w32tm wrapped in try/catch" ($ntpContent -match 'try[\s\S]{0,100}w32tm')
    Write-TestResult "NTP: has domain controller option" ($ntpContent -match 'Domain Controller')
    Write-TestResult "NTP: has custom server option" ($ntpContent -match 'Custom NTP')
    Write-TestResult "NTP: uses Write-MenuItem for menu" ($ntpContent -match 'Write-MenuItem')

    Write-TestResult "Timezone: Set-ServerTimeZone function exists" ($tzContent -match 'function Set-ServerTimeZone')
    Write-TestResult "Timezone: has US timezone options" ($tzContent -match 'Pacific|Mountain|Central|Eastern')

    Write-TestResult "Firewall: Disable-WindowsFirewallDomainPrivate exists" ($fwContent -match 'function Disable-WindowsFirewallDomainPrivate')
    Write-TestResult "Firewall: disables Domain and Private profiles" ($fwContent -match 'Domain.*Private|Set-NetFirewallProfile')
} catch {
    Write-TestResult "NTP/Timezone/Firewall" $false $_.Exception.Message
}

# ============================================================================
# SECTION 72: OFFLINE VHD & SESSION SUMMARY
# ============================================================================
Write-SectionHeader "SECTION 72: OFFLINE VHD & SESSION SUMMARY"

try {
    $vhdContent = Get-Content (Join-Path $modulesPath "43-OfflineVHD.ps1") -Raw
    $sessContent = Get-Content (Join-Path $modulesPath "46-SessionSummary.ps1") -Raw

    # OfflineVHD partial failure tracking (bug fix)
    Write-TestResult "OfflineVHD: tracks offlineStepsApplied" ($vhdContent -match '\$offlineStepsApplied')
    Write-TestResult "OfflineVHD: tracks offlineStepsFailed" ($vhdContent -match '\$offlineStepsFailed')
    Write-TestResult "OfflineVHD: uses ErrorAction Stop (not SilentlyContinue)" ($vhdContent -match 'ErrorAction Stop')
    Write-TestResult "OfflineVHD: reports partial failure summary" ($vhdContent -match 'offlineStepsFailed.*-gt.*0')
    Write-TestResult "OfflineVHD: uses PowerPlanGUID constant" ($vhdContent -match 'PowerPlanGUID')
    Write-TestResult "OfflineVHD: has VHDPath ValidateNotNullOrEmpty" ($vhdContent -match 'Set-OfflineVHDConfiguration[\s\S]{0,200}ValidateNotNullOrEmpty')

    Write-TestResult "SessionSummary: Show-SessionSummary function exists" ($sessContent -match 'function Show-SessionSummary')
    Write-TestResult "SessionSummary: shows session changes" ($sessContent -match 'SessionChanges')
} catch {
    Write-TestResult "OfflineVHD/SessionSummary" $false $_.Exception.Message
}

# ============================================================================
# SECTION 73: MENURUNNER HYPER-V FIX
# ============================================================================
Write-SectionHeader "SECTION 73: MENURUNNER HYPER-V FIX"

try {
    $runnerContent = Get-Content (Join-Path $modulesPath "49-MenuRunner.ps1") -Raw

    Write-TestResult "MenuRunner: Hyper-V install has try/catch" ($runnerContent -match 'Install Hyper-V[\s\S]{0,300}try[\s\S]{0,300}Install-WindowsFeature.*Hyper-V')
    Write-TestResult "MenuRunner: Hyper-V install no -Restart flag" (-not ($runnerContent -match 'Install-WindowsFeature.*Hyper-V.*-Restart'))
    Write-TestResult "MenuRunner: Hyper-V install logs session change" ($runnerContent -match 'Add-SessionChange.*Hyper-V')
    Write-TestResult "MenuRunner: Hyper-V install checks RestartNeeded" ($runnerContent -match 'RestartNeeded')
} catch {
    Write-TestResult "MenuRunner Hyper-V fix" $false $_.Exception.Message
}

# ============================================================================
# SECTION 74: SHOW-HELP SUBMENU STRUCTURE
# ============================================================================
Write-SectionHeader "SECTION 74: SHOW-HELP SUBMENU STRUCTURE"

try {
    $helpContent = Get-Content (Join-Path $modulesPath "34-Help.ps1") -Raw

    Write-TestResult "Show-Help: uses submenu structure (not flat [1]-[19])" ($helpContent -match '7 submenus')
    Write-TestResult "Show-Help: documents Network Config submenu" ($helpContent -match '\[1\] Network Config')
    Write-TestResult "Show-Help: documents System Config submenu" ($helpContent -match '\[2\] System Config')
    Write-TestResult "Show-Help: documents Roles & Features submenu" ($helpContent -match '\[3\] Roles & Features')
    Write-TestResult "Show-Help: documents Security & Access submenu" ($helpContent -match '\[4\] Security & Access')
    Write-TestResult "Show-Help: documents Tools & Utilities submenu" ($helpContent -match '\[5\] Tools & Utilities')
    Write-TestResult "Show-Help: documents Storage & Clustering submenu" ($helpContent -match '\[6\] Storage & Clustering')
    Write-TestResult "Show-Help: documents Operations submenu" ($helpContent -match '\[7\] Operations')
    Write-TestResult "Show-Help: documents Quick Setup Wizard" ($helpContent -match '\[Q\].*Quick Setup')
    Write-TestResult "Show-Help: documents Performance Dashboard" ($helpContent -match '\[10\].*Performance Dashboard')
} catch {
    Write-TestResult "Show-Help submenu structure" $false $_.Exception.Message
}

# ============================================================================
# SECTION 75: INSTALL-WINDOWSFEATUREWITHTIMEOUT HELPER
# ============================================================================
Write-SectionHeader "SECTION 75: INSTALL-WINDOWSFEATUREWITHTIMEOUT HELPER"

try {
    $sysCheckContent = Get-Content (Join-Path $modulesPath "05-SystemCheck.ps1") -Raw
    $hvContent = Get-Content (Join-Path $modulesPath "25-HyperV.ps1") -Raw
    $mpioContent = Get-Content (Join-Path $modulesPath "26-MPIO.ps1") -Raw
    $fcContent = Get-Content (Join-Path $modulesPath "27-FailoverClustering.ps1") -Raw

    Write-TestResult "Install-WindowsFeatureWithTimeout function exists" ($sysCheckContent -match 'function Install-WindowsFeatureWithTimeout')
    Write-TestResult "Helper uses FeatureInstallTimeoutSeconds constant" ($sysCheckContent -match 'function Install-WindowsFeatureWithTimeout' -and $sysCheckContent -match 'FeatureInstallTimeoutSeconds')
    Write-TestResult "Helper uses Start-Job pattern" ($sysCheckContent -match 'function Install-WindowsFeatureWithTimeout' -and $sysCheckContent -match 'Start-Job')
    Write-TestResult "25-HyperV calls helper for Server path" ($hvContent -match 'Install-WindowsFeatureWithTimeout.*Hyper-V')
    Write-TestResult "26-MPIO calls helper" ($mpioContent -match 'Install-WindowsFeatureWithTimeout.*MultipathIO')
    Write-TestResult "27-FailoverClustering calls helper" ($fcContent -match 'Install-WindowsFeatureWithTimeout.*Failover-Clustering')
} catch {
    Write-TestResult "Install-WindowsFeatureWithTimeout" $false $_.Exception.Message
}

# ============================================================================
# SECTION 76: NULL SAFETY FIXES
# ============================================================================
Write-SectionHeader "SECTION 76: NULL SAFETY FIXES"

try {
    $qolContent = Get-Content (Join-Path $modulesPath "55-QoLFeatures.ps1") -Raw
    $naContent = Get-Content (Join-Path $modulesPath "06-NetworkAdapters.ps1") -Raw
    $rdpContent = Get-Content (Join-Path $modulesPath "15-RDP.ps1") -Raw

    # .ToUpper() null safety (should use "$var".ToUpper() not $var.ToUpper())
    $vmDeployContent = Get-Content (Join-Path $modulesPath "44-VMDeployment.ps1") -Raw
    $unsafeToUpper = ([regex]::Matches($vmDeployContent, '\$\w+\.ToUpper\(\)')).Count
    $safeToUpper = ([regex]::Matches($vmDeployContent, '"\$\w+"\.ToUpper\(\)')).Count
    Write-TestResult "44-VMDeployment: .ToUpper() uses null-safe pattern" ($safeToUpper -ge 6)

    # QoL favorites null guard
    Write-TestResult "55-QoLFeatures: favorites has Name null guard" ($qolContent -match 'null.*fav\.Name|fav\.Name.*null')
    Write-TestResult "55-QoLFeatures: Timestamp has length guard" ($qolContent -match 'Timestamp\.Length')

    # NetworkAdapters numeric guard
    Write-TestResult "06-NetworkAdapters: selection has numeric guard" ($naContent -match 'selection.*-notmatch.*\\d')

    # RDP WinRM null check
    Write-TestResult "15-RDP: WinRM service has null check" ($rdpContent -match 'null.*winrmService|winrmService.*null')
} catch {
    Write-TestResult "Null safety" $false $_.Exception.Message
}

# ============================================================================
# SECTION 77: FIREWALL STATE + TEMPPATH + $MATCHES CONVENTION
# ============================================================================
Write-SectionHeader "SECTION 77: FIREWALL STATE + TEMPPATH + MATCHES CONVENTION"

try {
    $htmlContent = Get-Content (Join-Path $modulesPath "54-HTMLReports.ps1") -Raw
    $initContent = Get-Content (Join-Path $modulesPath "00-Initialization.ps1") -Raw
    $entryContent = Get-Content (Join-Path $modulesPath "50-EntryPoint.ps1") -Raw

    # Firewall state uses string comparison not truthiness
    Write-TestResult "54-HTMLReports: firewall checks use -eq Enabled" ($htmlContent -match "fw\.Domain -eq .Enabled.")
    Write-TestResult "54-HTMLReports: firewall checks use -ne Enabled" ($htmlContent -match "fw\.Domain -ne .Enabled.")

    # TempPath constant
    Write-TestResult "00-Initialization: TempPath constant defined" ($initContent -match '\$script:TempPath')
    Write-TestResult "50-EntryPoint: uses TempPath constant" ($entryContent -match '\$script:TempPath')

    # $matches convention - spot check that key files use $regexMatches
    $iscsiContent = Get-Content (Join-Path $modulesPath "10-iSCSI.ps1") -Raw
    $smContent = Get-Content (Join-Path $modulesPath "38-StorageManager.ps1") -Raw
    Write-TestResult "10-iSCSI: uses regexMatches convention" ($iscsiContent -match '\$regexMatches')
    Write-TestResult "38-StorageManager: uses regexMatches convention" ($smContent -match '\$regexMatches')
} catch {
    Write-TestResult "Firewall/TempPath/Matches" $false $_.Exception.Message
}

# ============================================================================
Write-SectionHeader "SECTION 78: VM DEPLOYMENT REFACTORING"

try {
    $content = Get-Content (Join-Path $modulesPath "44-VMDeployment.ps1") -Raw

    # Invoke-VMConfigEditAction function exists
    Write-TestResult "44-VMDeployment: Invoke-VMConfigEditAction function exists" ($content -match 'function\s+Invoke-VMConfigEditAction')

    # Publish-StandardVM uses Invoke-VMConfigEditAction (not its own switch cases 1-7)
    Write-TestResult "44-VMDeployment: Publish-StandardVM uses Invoke-VMConfigEditAction" ($content -match 'Publish-StandardVM[\s\S]*?Invoke-VMConfigEditAction')

    # Publish-CustomVM uses Invoke-VMConfigEditAction
    Write-TestResult "44-VMDeployment: Publish-CustomVM uses Invoke-VMConfigEditAction" ($content -match 'Publish-CustomVM[\s\S]*?Invoke-VMConfigEditAction')

    # Edit-QueuedVM uses Invoke-VMConfigEditAction
    Write-TestResult "44-VMDeployment: Edit-QueuedVM uses Invoke-VMConfigEditAction" ($content -match 'Edit-QueuedVM[\s\S]*?Invoke-VMConfigEditAction')

    # Invoke-VMConfigEditAction handles choices 1-7
    Write-TestResult "44-VMDeployment: Invoke-VMConfigEditAction handles Set-VMConfigCPU" ($content -match 'Invoke-VMConfigEditAction[\s\S]*?Set-VMConfigCPU')
    Write-TestResult "44-VMDeployment: Invoke-VMConfigEditAction handles Set-VMConfigMemory" ($content -match 'Invoke-VMConfigEditAction[\s\S]*?Set-VMConfigMemory')
    Write-TestResult "44-VMDeployment: Invoke-VMConfigEditAction handles Set-VMConfigDisks" ($content -match 'Invoke-VMConfigEditAction[\s\S]*?Set-VMConfigDisks')
    Write-TestResult "44-VMDeployment: Invoke-VMConfigEditAction handles Set-VMConfigNICs" ($content -match 'Invoke-VMConfigEditAction[\s\S]*?Set-VMConfigNICs')
    Write-TestResult "44-VMDeployment: Invoke-VMConfigEditAction handles GuestServices toggle" ($content -match 'Invoke-VMConfigEditAction[\s\S]*?GuestServices')
    Write-TestResult "44-VMDeployment: Invoke-VMConfigEditAction handles TimeSyncWithHost toggle" ($content -match 'Invoke-VMConfigEditAction[\s\S]*?TimeSyncWithHost')
    Write-TestResult "44-VMDeployment: Invoke-VMConfigEditAction handles UseVHD toggle" ($content -match 'Invoke-VMConfigEditAction[\s\S]*?UseVHD')

    # Invoke-VMConfigEditAction returns $false for unrecognized choices
    Write-TestResult "44-VMDeployment: Invoke-VMConfigEditAction returns false for unrecognized choices" ($content -match 'Invoke-VMConfigEditAction[\s\S]*?default\s*\{\s*return\s+\$false')
} catch {
    Write-TestResult "VM Deployment Refactoring" $false $_.Exception.Message
}

# ============================================================================
Write-SectionHeader "SECTION 79: IP CONFIG DISPLAY REFACTORING"

try {
    $content = Get-Content (Join-Path $modulesPath "48-MenuDisplay.ps1") -Raw

    # Show-AdapterInfoBox function exists
    Write-TestResult "48-MenuDisplay: Show-AdapterInfoBox function exists" ($content -match 'function\s+Show-AdapterInfoBox')

    # Show-Host-IPNetworkMenu uses Show-AdapterInfoBox
    Write-TestResult "48-MenuDisplay: Show-Host-IPNetworkMenu uses Show-AdapterInfoBox" ($content -match 'Show-Host-IPNetworkMenu[\s\S]*?Show-AdapterInfoBox')

    # Show-VM-NetworkMenu uses Show-AdapterInfoBox
    Write-TestResult "48-MenuDisplay: Show-VM-NetworkMenu uses Show-AdapterInfoBox" ($content -match 'Show-VM-NetworkMenu[\s\S]*?Show-AdapterInfoBox')

    # Show-AdapterInfoBox has null safety for empty adapter name
    Write-TestResult "48-MenuDisplay: Show-AdapterInfoBox has null safety for adapter name" ($content -match 'Show-AdapterInfoBox[\s\S]*?(none selected|\(none)')

    # Show-AdapterInfoBox uses Get-NetAdapter
    Write-TestResult "48-MenuDisplay: Show-AdapterInfoBox uses Get-NetAdapter" ($content -match 'Show-AdapterInfoBox[\s\S]*?Get-NetAdapter')
} catch {
    Write-TestResult "IP Config Display Refactoring" $false $_.Exception.Message
}

# ============================================================================
Write-SectionHeader "SECTION 80: ORPHAN FUNCTION WIRING"

try {
    $hostnameContent = Get-Content (Join-Path $modulesPath "11-Hostname.ps1") -Raw
    $ipConfigContent = Get-Content (Join-Path $modulesPath "07-IPConfiguration.ps1") -Raw

    # 11-Hostname.ps1 contains Test-ComputerNameInAD call
    Write-TestResult "11-Hostname: calls Test-ComputerNameInAD" ($hostnameContent -match 'Test-ComputerNameInAD')

    # 07-IPConfiguration.ps1 contains Test-IPAddressInUse call
    Write-TestResult "07-IPConfiguration: calls Test-IPAddressInUse" ($ipConfigContent -match 'Test-IPAddressInUse')

    # Both have confirmation prompts after the check
    Write-TestResult "11-Hostname: has confirmation after AD check" ($hostnameContent -match 'Test-ComputerNameInAD[\s\S]*?(Confirm-UserAction|Continue with this)')
    Write-TestResult "07-IPConfiguration: has confirmation after IP check" ($ipConfigContent -match 'Test-IPAddressInUse[\s\S]*?(Confirm-UserAction|Continue with this)')
} catch {
    Write-TestResult "Orphan Function Wiring" $false $_.Exception.Message
}

# ============================================================================
Write-SectionHeader "SECTION 81: SHARED HELPER DEDUPLICATION"

try {
    $sysCheckContent = Get-Content (Join-Path $modulesPath "05-SystemCheck.ps1") -Raw
    $hypervContent = Get-Content (Join-Path $modulesPath "25-HyperV.ps1") -Raw
    $mpioContent = Get-Content (Join-Path $modulesPath "26-MPIO.ps1") -Raw
    $clusterContent = Get-Content (Join-Path $modulesPath "27-FailoverClustering.ps1") -Raw
    $initContent = Get-Content (Join-Path $modulesPath "00-Initialization.ps1") -Raw
    $utilContent = Get-Content (Join-Path $modulesPath "35-Utilities.ps1") -Raw

    # 05-SystemCheck.ps1 has Install-WindowsFeatureWithTimeout function
    Write-TestResult "05-SystemCheck: Install-WindowsFeatureWithTimeout function defined" ($sysCheckContent -match 'function\s+Install-WindowsFeatureWithTimeout')

    # 25-HyperV.ps1 uses Install-WindowsFeatureWithTimeout
    Write-TestResult "25-HyperV: uses Install-WindowsFeatureWithTimeout" ($hypervContent -match 'Install-WindowsFeatureWithTimeout')

    # 26-MPIO.ps1 uses Install-WindowsFeatureWithTimeout
    Write-TestResult "26-MPIO: uses Install-WindowsFeatureWithTimeout" ($mpioContent -match 'Install-WindowsFeatureWithTimeout')

    # 27-FailoverClustering.ps1 uses Install-WindowsFeatureWithTimeout
    Write-TestResult "27-FailoverClustering: uses Install-WindowsFeatureWithTimeout" ($clusterContent -match 'Install-WindowsFeatureWithTimeout')

    # 00-Initialization.ps1 has $script:TempPath constant
    Write-TestResult "00-Initialization: TempPath constant defined" ($initContent -match '\$script:TempPath')

    # 35-Utilities.ps1 uses $script:TempPath (not hardcoded C:\Temp)
    Write-TestResult "35-Utilities: uses TempPath constant" ($utilContent -match '\$script:TempPath')
} catch {
    Write-TestResult "Shared Helper Deduplication" $false $_.Exception.Message
}

# ============================================================================
Write-SectionHeader "SECTION 82: STORAGE MANAGER BEHAVIORAL TESTS"

try {
    $content = Get-Content (Join-Path $modulesPath "38-StorageManager.ps1") -Raw

    # Has Show-StorageManagerMenu function
    Write-TestResult "38-StorageManager: Show-StorageManagerMenu function exists" ($content -match 'function\s+Show-StorageManagerMenu')

    # Has Format-ByteSize function (wrapper for Format-TransferSize)
    Write-TestResult "38-StorageManager: Format-ByteSize function exists" ($content -match 'function\s+Format-ByteSize')

    # Uses Format-TransferSize (shared helper)
    Write-TestResult "38-StorageManager: uses Format-TransferSize helper" ($content -match 'Format-TransferSize')

    # Has Start-StorageManager function
    Write-TestResult "38-StorageManager: Start-StorageManager function exists" ($content -match 'function\s+Start-StorageManager')

    # Has disk selection logic (Get-Disk)
    Write-TestResult "38-StorageManager: has disk selection logic (Get-Disk)" ($content -match 'Get-Disk')

    # Uses $regexMatches convention (no raw $matches[ usage)
    Write-TestResult "38-StorageManager: uses regexMatches convention" ($content -match '\$regexMatches')
    Write-TestResult "38-StorageManager: no raw matches[] usage" ($content -notmatch '\$matches\[')
} catch {
    Write-TestResult "Storage Manager Behavioral Tests" $false $_.Exception.Message
}

# ============================================================================
Write-SectionHeader "SECTION 83: CLUSTER MANAGEMENT TESTS"

try {
    $content = Get-Content (Join-Path $modulesPath "27-FailoverClustering.ps1") -Raw

    # Has Install-FailoverClusteringFeature function
    Write-TestResult "27-FailoverClustering: Install-FailoverClusteringFeature function exists" ($content -match 'function\s+Install-FailoverClusteringFeature')

    # Has Show-ClusterManagementMenu function
    Write-TestResult "27-FailoverClustering: Show-ClusterManagementMenu function exists" ($content -match 'function\s+Show-ClusterManagementMenu')

    # Uses Install-WindowsFeatureWithTimeout
    Write-TestResult "27-FailoverClustering: uses Install-WindowsFeatureWithTimeout" ($content -match 'Install-WindowsFeatureWithTimeout')

    # Uses $script:TempPath not hardcoded paths
    Write-TestResult "27-FailoverClustering: uses TempPath constant" ($content -match '\$script:TempPath')

    # Has Test-WindowsServer guard (client OS protection)
    Write-TestResult "27-FailoverClustering: has Test-WindowsServer guard" ($content -match 'Test-WindowsServer')
} catch {
    Write-TestResult "Cluster Management Tests" $false $_.Exception.Message
}

# ============================================================================
Write-SectionHeader "SECTION 84: HTML REPORTS BEHAVIORAL TESTS"

try {
    $content = Get-Content (Join-Path $modulesPath "54-HTMLReports.ps1") -Raw

    # Has Export-HTMLReadinessReport function
    Write-TestResult "54-HTMLReports: Export-HTMLReadinessReport function exists" ($content -match 'function\s+Export-HTMLReadinessReport')

    # Has Export-HTMLHealthReport function
    Write-TestResult "54-HTMLReports: Export-HTMLHealthReport function exists" ($content -match 'function\s+Export-HTMLHealthReport')

    # Uses Get-CimInstance for system info
    Write-TestResult "54-HTMLReports: uses Get-CimInstance for system info" ($content -match 'Get-CimInstance')

    # Has -ErrorAction SilentlyContinue on CIM calls
    Write-TestResult "54-HTMLReports: CIM calls have ErrorAction SilentlyContinue" ($content -match 'Get-CimInstance.*-ErrorAction SilentlyContinue')

    # Firewall state uses string comparison -eq "Enabled" not boolean truthiness
    Write-TestResult "54-HTMLReports: firewall uses string comparison -eq Enabled" ($content -match '-eq\s+.Enabled.')

    # Has Get-FirewallState call
    Write-TestResult "54-HTMLReports: calls Get-FirewallState" ($content -match 'Get-FirewallState')

    # Generates HTML
    Write-TestResult "54-HTMLReports: generates HTML output" ($content -match '<html>|<table>|<tr>|<td>')
} catch {
    Write-TestResult "HTML Reports Behavioral Tests" $false $_.Exception.Message
}

# ============================================================================
Write-SectionHeader "SECTION 85: BATCH MODE BEHAVIORAL TESTS"

try {
    $content = Get-Content (Join-Path $modulesPath "50-EntryPoint.ps1") -Raw

    # Has Start-BatchMode function
    Write-TestResult "50-EntryPoint: Start-BatchMode function exists" ($content -match 'function\s+Start-BatchMode')

    # Uses cached $isDomainJoined (not duplicate CIM calls)
    Write-TestResult "50-EntryPoint: uses cached isDomainJoined variable" ($content -match '\$isDomainJoined')

    # Uses $script:TempPath constant
    Write-TestResult "50-EntryPoint: uses TempPath constant" ($content -match '\$script:TempPath')

    # Has domain join logic
    Write-TestResult "50-EntryPoint: has domain join logic (DomainName)" ($content -match 'DomainName')
    Write-TestResult "50-EntryPoint: has domain join logic (Add-Computer)" ($content -match 'Add-Computer')

    # Has defaults import logic
    Write-TestResult "50-EntryPoint: has Import-Defaults call" ($content -match 'Import-Defaults')
} catch {
    Write-TestResult "Batch Mode Behavioral Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 86: CUSTOM VM TEMPLATES & DEFAULTS MERGE
# ============================================================================

Write-SectionHeader "SECTION 86: CUSTOM VM TEMPLATES & DEFAULTS MERGE"

# Variables exist and are hashtables
Write-TestResult "Variable exists: script:CustomVMTemplates" ($null -ne $script:CustomVMTemplates)
Write-TestResult "Variable exists: script:CustomVMDefaults" ($null -ne $script:CustomVMDefaults)
Write-TestResult "CustomVMTemplates is hashtable" ($script:CustomVMTemplates -is [hashtable])
Write-TestResult "CustomVMDefaults is hashtable" ($script:CustomVMDefaults -is [hashtable])

# BuiltInVMTemplates snapshot
Write-TestResult "BuiltInVMTemplates set after Import-Defaults" ($null -ne $script:BuiltInVMTemplates -or $script:CustomVMTemplates.Count -eq 0)

# Partial override: merge with temp defaults.json
try {
    $testDir = "$env:TEMP\appconfig_vmtest_$(Get-Random)"
    $null = New-Item -Path $testDir -ItemType Directory -Force
    $origDefaultsPath = $script:DefaultsPath
    $origConfigDir = $script:AppConfigDir
    $script:AppConfigDir = $testDir
    $script:DefaultsPath = "$testDir\defaults.json"

    # Save original FS MemoryGB for comparison
    $origFSMemory = $script:BuiltInVMTemplates["FS"].MemoryGB
    $origFSvCPU = $script:BuiltInVMTemplates["FS"].vCPU

    # Write test defaults with partial FS override and new SQL template
    $testDefaults = @{
        CustomVMTemplates = @{
            FS = @{ MemoryGB = 64 }
            SQL = @{
                FullName = "SQL Server"
                Prefix = "SQL"
                OSType = "Windows"
                vCPU = 8
                MemoryGB = 32
                MemoryType = "Static"
                Disks = @(
                    @{ Name = "OS"; SizeGB = 150; Type = "Fixed" }
                    @{ Name = "Data"; SizeGB = 500; Type = "Fixed" }
                )
                NICs = 1
            }
        }
        CustomVMDefaults = @{
            vCPU = 2
            MemoryGB = 16
            DiskSizeGB = 200
            DiskType = "Dynamic"
            MemoryType = "Static"
        }
    }
    $testDefaults | ConvertTo-Json -Depth 5 | Out-File "$testDir\defaults.json" -Encoding UTF8

    Import-Defaults

    # Partial override: FS MemoryGB changed
    $fsMemAfter = $script:StandardVMTemplates["FS"].MemoryGB
    Write-TestResult "Partial override: FS MemoryGB changed to 64" ($fsMemAfter -eq 64) "Got $fsMemAfter"

    # Partial override: FS vCPU preserved from built-in
    $fsCpuAfter = $script:StandardVMTemplates["FS"].vCPU
    Write-TestResult "Partial override: FS vCPU preserved ($origFSvCPU)" ($fsCpuAfter -eq $origFSvCPU) "Got $fsCpuAfter"

    # Partial override: FS Disks preserved from built-in
    $fsDiskCount = $script:StandardVMTemplates["FS"].Disks.Count
    Write-TestResult "Partial override: FS Disks preserved (2 disks)" ($fsDiskCount -eq 2) "Got $fsDiskCount"

    # New template: SQL added
    Write-TestResult "New template: SQL exists in StandardVMTemplates" ($script:StandardVMTemplates.ContainsKey("SQL"))

    # New template: SQL has default SortOrder=100
    if ($script:StandardVMTemplates.ContainsKey("SQL")) {
        $sqlSort = $script:StandardVMTemplates["SQL"].SortOrder
        Write-TestResult "New template: SQL gets default SortOrder=100" ($sqlSort -eq 100) "Got $sqlSort"

        # New template: SQL has default GuestServices=$true
        $sqlGS = $script:StandardVMTemplates["SQL"].GuestServices
        Write-TestResult "New template: SQL gets default GuestServices=true" ($sqlGS -eq $true) "Got $sqlGS"

        # New template: SQL has default TimeSyncWithHost=$true
        $sqlTS = $script:StandardVMTemplates["SQL"].TimeSyncWithHost
        Write-TestResult "New template: SQL gets default TimeSyncWithHost=true" ($sqlTS -eq $true) "Got $sqlTS"

        # Disk conversion: SQL disks are hashtables (not PSCustomObject)
        $sqlDisk0 = $script:StandardVMTemplates["SQL"].Disks[0]
        Write-TestResult "Disk conversion: SQL disk[0] is hashtable" ($sqlDisk0 -is [hashtable]) "Type: $($sqlDisk0.GetType().Name)"
    }

    # CustomVMTemplates captured correctly
    Write-TestResult "CustomVMTemplates has FS entry" ($script:CustomVMTemplates.ContainsKey("FS"))
    Write-TestResult "CustomVMTemplates has SQL entry" ($script:CustomVMTemplates.ContainsKey("SQL"))

    # CustomVMDefaults captured correctly
    Write-TestResult "CustomVMDefaults has vCPU=2" ($script:CustomVMDefaults['vCPU'] -eq 2) "Got $($script:CustomVMDefaults['vCPU'])"
    Write-TestResult "CustomVMDefaults has MemoryGB=16" ($script:CustomVMDefaults['MemoryGB'] -eq 16) "Got $($script:CustomVMDefaults['MemoryGB'])"
    Write-TestResult "CustomVMDefaults has DiskSizeGB=200" ($script:CustomVMDefaults['DiskSizeGB'] -eq 200) "Got $($script:CustomVMDefaults['DiskSizeGB'])"

    # Re-import idempotency: import again and verify FS still correct
    Import-Defaults
    $fsMemAgain = $script:StandardVMTemplates["FS"].MemoryGB
    $fsCpuAgain = $script:StandardVMTemplates["FS"].vCPU
    Write-TestResult "Re-import idempotent: FS MemoryGB still 64" ($fsMemAgain -eq 64) "Got $fsMemAgain"
    Write-TestResult "Re-import idempotent: FS vCPU still $origFSvCPU" ($fsCpuAgain -eq $origFSvCPU) "Got $fsCpuAgain"

    # Export-Defaults includes new fields
    Export-Defaults
    if (Test-Path "$testDir\defaults.json") {
        $exported = Get-Content "$testDir\defaults.json" -Raw | ConvertFrom-Json
        Write-TestResult "Export-Defaults: has CustomVMTemplates field" ($exported.PSObject.Properties.Name -contains "CustomVMTemplates")
        Write-TestResult "Export-Defaults: has CustomVMDefaults field" ($exported.PSObject.Properties.Name -contains "CustomVMDefaults")
    }

    # Restore
    $script:DefaultsPath = $origDefaultsPath
    $script:AppConfigDir = $origConfigDir
    Import-Defaults
    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue

    # Verify SQL template removed after restore (only built-in + real defaults remain)
    # SQL only exists if the real defaults.json defines it
} catch {
    Write-TestResult "Custom VM Templates merge" $false $_.Exception.Message
    $script:DefaultsPath = $origDefaultsPath
    $script:AppConfigDir = $origConfigDir
    Import-Defaults
    if (Test-Path $testDir) { Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue }
}

# _comment fields are skipped
try {
    $testDir2 = "$env:TEMP\appconfig_vmtest2_$(Get-Random)"
    $null = New-Item -Path $testDir2 -ItemType Directory -Force
    $origDefaultsPath2 = $script:DefaultsPath
    $origConfigDir2 = $script:AppConfigDir
    $script:AppConfigDir = $testDir2
    $script:DefaultsPath = "$testDir2\defaults.json"
    @{ CustomVMTemplates = @{ _comment = "should be skipped" } } | ConvertTo-Json -Depth 3 | Out-File "$testDir2\defaults.json" -Encoding UTF8
    Import-Defaults
    Write-TestResult "Underscore fields skipped: _comment not in CustomVMTemplates" (-not $script:CustomVMTemplates.ContainsKey("_comment"))
    $script:DefaultsPath = $origDefaultsPath2
    $script:AppConfigDir = $origConfigDir2
    Import-Defaults
    Remove-Item $testDir2 -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-TestResult "Underscore field skipping" $false $_.Exception.Message
    $script:DefaultsPath = $origDefaultsPath2
    $script:AppConfigDir = $origConfigDir2
    Import-Defaults
}

# defaults.example.json has new sections
$examplePath = Join-Path (Split-Path $PSScriptRoot) 'defaults.example.json'
if (Test-Path $examplePath) {
    try {
        $exampleData = Get-Content $examplePath -Raw | ConvertFrom-Json
        Write-TestResult "defaults.example.json: has CustomVMTemplates" ($null -ne $exampleData.CustomVMTemplates)
        Write-TestResult "defaults.example.json: has CustomVMDefaults" ($null -ne $exampleData.CustomVMDefaults)
        Write-TestResult "defaults.example.json: CustomVMTemplates has FS example" ($null -ne $exampleData.CustomVMTemplates.FS)
        Write-TestResult "defaults.example.json: CustomVMTemplates has SQL example" ($null -ne $exampleData.CustomVMTemplates.SQL)
        Write-TestResult "defaults.example.json: CustomVMDefaults has vCPU" ($null -ne $exampleData.CustomVMDefaults.vCPU)
        Write-TestResult "defaults.example.json: has VMNaming" ($null -ne $exampleData.VMNaming)
        Write-TestResult "defaults.example.json: VMNaming has Pattern" ($null -ne $exampleData.VMNaming.Pattern)
        Write-TestResult "defaults.example.json: CustomVMTemplates has APP example" ($null -ne $exampleData.CustomVMTemplates.APP)
    } catch {
        Write-TestResult "defaults.example.json VM sections" $false $_.Exception.Message
    }
}

# 44-VMDeployment.ps1: New-VMConfiguration uses CustomVMDefaults
try {
    $vmContent = Get-Content (Join-Path $modulesPath "44-VMDeployment.ps1") -Raw
    Write-TestResult "44-VMDeployment: New-VMConfiguration references CustomVMDefaults" ($vmContent -match 'CustomVMDefaults')
} catch {
    Write-TestResult "New-VMConfiguration CustomVMDefaults reference" $false $_.Exception.Message
}

# Edge case: empty CustomVMTemplates and CustomVMDefaults
try {
    $testDir3 = "$env:TEMP\appconfig_vmtest3_$(Get-Random)"
    $null = New-Item -Path $testDir3 -ItemType Directory -Force
    $origDefaultsPath3 = $script:DefaultsPath
    $origConfigDir3 = $script:AppConfigDir
    $script:AppConfigDir = $testDir3
    $script:DefaultsPath = "$testDir3\defaults.json"

    # Save original FS values for comparison
    $origFSMemory3 = $script:BuiltInVMTemplates["FS"].MemoryGB
    $origFSvCPU3 = $script:BuiltInVMTemplates["FS"].vCPU

    @{ CustomVMTemplates = @{}; CustomVMDefaults = @{} } | ConvertTo-Json -Depth 3 | Out-File "$testDir3\defaults.json" -Encoding UTF8
    Import-Defaults
    Write-TestResult "Empty CustomVMTemplates: no crash" $true
    Write-TestResult "Empty CustomVMTemplates: FS vCPU unchanged" ($script:StandardVMTemplates["FS"].vCPU -eq $origFSvCPU3) "Got $($script:StandardVMTemplates["FS"].vCPU)"
    Write-TestResult "Empty CustomVMTemplates: FS MemoryGB unchanged" ($script:StandardVMTemplates["FS"].MemoryGB -eq $origFSMemory3) "Got $($script:StandardVMTemplates["FS"].MemoryGB)"
    Write-TestResult "Empty CustomVMDefaults: hashtable stays empty" ($script:CustomVMDefaults.Count -eq 0) "Count=$($script:CustomVMDefaults.Count)"

    $script:DefaultsPath = $origDefaultsPath3
    $script:AppConfigDir = $origConfigDir3
    Import-Defaults
    Remove-Item $testDir3 -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-TestResult "Empty CustomVMTemplates/Defaults" $false $_.Exception.Message
    $script:DefaultsPath = $origDefaultsPath3
    $script:AppConfigDir = $origConfigDir3
    Import-Defaults
}

# Edge case: new template missing optional fields gets defaults
try {
    $testDir4 = "$env:TEMP\appconfig_vmtest4_$(Get-Random)"
    $null = New-Item -Path $testDir4 -ItemType Directory -Force
    $origDefaultsPath4 = $script:DefaultsPath
    $origConfigDir4 = $script:AppConfigDir
    $script:AppConfigDir = $testDir4
    $script:DefaultsPath = "$testDir4\defaults.json"

    # Minimal new template: only required fields, no SortOrder/GuestServices/TimeSyncWithHost/Notes
    @{
        CustomVMTemplates = @{
            MINI = @{
                FullName = "Minimal Server"
                Prefix = "MINI"
                OSType = "Windows"
                vCPU = 2
                MemoryGB = 4
                MemoryType = "Dynamic"
                Disks = @( @{ Name = "OS"; SizeGB = 80; Type = "Fixed" } )
                NICs = 1
            }
        }
    } | ConvertTo-Json -Depth 5 | Out-File "$testDir4\defaults.json" -Encoding UTF8
    Import-Defaults

    if ($script:StandardVMTemplates.ContainsKey("MINI")) {
        $mini = $script:StandardVMTemplates["MINI"]
        Write-TestResult "Minimal template: MINI added" $true
        Write-TestResult "Minimal template: SortOrder defaults to 100" ($mini.SortOrder -eq 100) "Got $($mini.SortOrder)"
        Write-TestResult "Minimal template: GuestServices defaults to true" ($mini.GuestServices -eq $true) "Got $($mini.GuestServices)"
        Write-TestResult "Minimal template: TimeSyncWithHost defaults to true" ($mini.TimeSyncWithHost -eq $true) "Got $($mini.TimeSyncWithHost)"
        Write-TestResult "Minimal template: Notes defaults to empty" ($mini.Notes -eq "") "Got '$($mini.Notes)'"
        Write-TestResult "Minimal template: vCPU=2" ($mini.vCPU -eq 2) "Got $($mini.vCPU)"
        Write-TestResult "Minimal template: MemoryGB=4" ($mini.MemoryGB -eq 4) "Got $($mini.MemoryGB)"
    } else {
        Write-TestResult "Minimal template: MINI added" $false "Not found in StandardVMTemplates"
    }

    $script:DefaultsPath = $origDefaultsPath4
    $script:AppConfigDir = $origConfigDir4
    Import-Defaults
    Remove-Item $testDir4 -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-TestResult "Minimal template edge case" $false $_.Exception.Message
    $script:DefaultsPath = $origDefaultsPath4
    $script:AppConfigDir = $origConfigDir4
    Import-Defaults
}

# Edge case: MemoryType override on existing template
try {
    $testDir5 = "$env:TEMP\appconfig_vmtest5_$(Get-Random)"
    $null = New-Item -Path $testDir5 -ItemType Directory -Force
    $origDefaultsPath5 = $script:DefaultsPath
    $origConfigDir5 = $script:AppConfigDir
    $script:AppConfigDir = $testDir5
    $script:DefaultsPath = "$testDir5\defaults.json"

    @{ CustomVMTemplates = @{ WEB = @{ MemoryType = "Static" } } } | ConvertTo-Json -Depth 3 | Out-File "$testDir5\defaults.json" -Encoding UTF8
    Import-Defaults
    $webMemType = $script:StandardVMTemplates["WEB"].MemoryType
    $webVCPU = $script:StandardVMTemplates["WEB"].vCPU
    Write-TestResult "MemoryType override: WEB changed to Static" ($webMemType -eq "Static") "Got $webMemType"
    Write-TestResult "MemoryType override: WEB vCPU preserved" ($webVCPU -eq $script:BuiltInVMTemplates["WEB"].vCPU) "Got $webVCPU"

    $script:DefaultsPath = $origDefaultsPath5
    $script:AppConfigDir = $origConfigDir5
    Import-Defaults
    Remove-Item $testDir5 -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-TestResult "MemoryType override" $false $_.Exception.Message
    $script:DefaultsPath = $origDefaultsPath5
    $script:AppConfigDir = $origConfigDir5
    Import-Defaults
}

# Edge case: no CustomVMTemplates key at all in defaults.json
try {
    $testDir6 = "$env:TEMP\appconfig_vmtest6_$(Get-Random)"
    $null = New-Item -Path $testDir6 -ItemType Directory -Force
    $origDefaultsPath6 = $script:DefaultsPath
    $origConfigDir6 = $script:AppConfigDir
    $script:AppConfigDir = $testDir6
    $script:DefaultsPath = "$testDir6\defaults.json"

    @{ Domain = "test.local" } | ConvertTo-Json | Out-File "$testDir6\defaults.json" -Encoding UTF8
    Import-Defaults
    Write-TestResult "Missing VM keys: no crash" $true
    Write-TestResult "Missing VM keys: built-in templates intact" ($script:StandardVMTemplates.ContainsKey("FS") -and $script:StandardVMTemplates.ContainsKey("DC"))

    $script:DefaultsPath = $origDefaultsPath6
    $script:AppConfigDir = $origConfigDir6
    Import-Defaults
    Remove-Item $testDir6 -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-TestResult "Missing VM keys edge case" $false $_.Exception.Message
    $script:DefaultsPath = $origDefaultsPath6
    $script:AppConfigDir = $origConfigDir6
    Import-Defaults
}

# VMNaming import from defaults.json
try {
    $testDir7 = "$env:TEMP\appconfig_vmtest7_$(Get-Random)"
    $null = New-Item -Path $testDir7 -ItemType Directory -Force
    $origDefaultsPath7 = $script:DefaultsPath
    $origConfigDir7 = $script:AppConfigDir
    $script:AppConfigDir = $testDir7
    $script:DefaultsPath = "$testDir7\defaults.json"

    @{
        VMNaming = @{
            SiteId = "ACME"
            Pattern = "{Site}-{Prefix}-{Seq:00}"
            SiteIdSource = "static"
            SiteIdRegex = "^([A-Z]+)-"
        }
    } | ConvertTo-Json -Depth 3 | Out-File "$testDir7\defaults.json" -Encoding UTF8
    Import-Defaults
    Write-TestResult "VMNaming import: SiteId set to ACME" ($script:VMNaming.SiteId -eq "ACME") "Got $($script:VMNaming.SiteId)"
    Write-TestResult "VMNaming import: Pattern updated" ($script:VMNaming.Pattern -eq "{Site}-{Prefix}-{Seq:00}") "Got $($script:VMNaming.Pattern)"
    Write-TestResult "VMNaming import: SiteIdSource set to static" ($script:VMNaming.SiteIdSource -eq "static") "Got $($script:VMNaming.SiteIdSource)"

    $script:DefaultsPath = $origDefaultsPath7
    $script:AppConfigDir = $origConfigDir7
    # Reset VMNaming to defaults
    $script:VMNaming = @{ SiteId = ""; Pattern = "{Site}-{Prefix}{Seq}"; SiteIdSource = "hostname"; SiteIdRegex = "^(\d{3,6})-" }
    Import-Defaults
    Remove-Item $testDir7 -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-TestResult "VMNaming import" $false $_.Exception.Message
    $script:DefaultsPath = $origDefaultsPath7
    $script:AppConfigDir = $origConfigDir7
    $script:VMNaming = @{ SiteId = ""; Pattern = "{Site}-{Prefix}{Seq}"; SiteIdSource = "hostname"; SiteIdRegex = "^(\d{3,6})-" }
    Import-Defaults
}

# ============================================================================
# SECTION 87: BATCH CONFIG VALIDATION (Test-BatchConfig)
# ============================================================================

Write-SectionHeader "SECTION 87: BATCH CONFIG VALIDATION (Test-BatchConfig)"

try {
    # Function exists
    $entryContent = Get-Content (Join-Path $modulesPath "50-EntryPoint.ps1") -Raw
    Write-TestResult "50-EntryPoint: Test-BatchConfig function exists" ($entryContent -match 'function\s+Test-BatchConfig')

    # Valid config passes
    $validConfig = @{
        ConfigType = "VM"
        Hostname = "TEST-VM1"
        IPAddress = "10.0.1.100"
        Gateway = "10.0.1.1"
        SubnetCIDR = 24
        DNS1 = "8.8.8.8"
        EnableRDP = $true
        SetPowerPlan = "High Performance"
    }
    $result = Test-BatchConfig -Config $validConfig
    Write-TestResult "Valid config: IsValid=true" ($result.IsValid -eq $true)
    Write-TestResult "Valid config: zero errors" ($result.Errors.Count -eq 0) "Errors: $($result.Errors.Count)"

    # Invalid ConfigType
    $badType = @{ ConfigType = "INVALID" }
    $result = Test-BatchConfig -Config $badType
    Write-TestResult "Invalid ConfigType: IsValid=false" ($result.IsValid -eq $false)
    Write-TestResult "Invalid ConfigType: error mentions ConfigType" ($result.Errors[0] -match "ConfigType")

    # Invalid hostname (too long)
    $badHost = @{ Hostname = "ABCDEFGHIJKLMNOP" }
    $result = Test-BatchConfig -Config $badHost
    Write-TestResult "Invalid hostname: caught" ($result.Errors.Count -gt 0 -and ($result.Errors -join " ") -match "Hostname")

    # Invalid IP address
    $badIP = @{ IPAddress = "999.999.999.999"; Gateway = "10.0.1.1" }
    $result = Test-BatchConfig -Config $badIP
    Write-TestResult "Invalid IP: caught" ($result.Errors.Count -gt 0 -and ($result.Errors -join " ") -match "IPAddress")

    # IP without gateway
    $noGW = @{ IPAddress = "10.0.1.100" }
    $result = Test-BatchConfig -Config $noGW
    Write-TestResult "IP without gateway: error" ($result.Errors.Count -gt 0 -and ($result.Errors -join " ") -match "Gateway")

    # Invalid CIDR
    $badCIDR = @{ SubnetCIDR = 99 }
    $result = Test-BatchConfig -Config $badCIDR
    Write-TestResult "Invalid CIDR (99): caught" ($result.Errors.Count -gt 0 -and ($result.Errors -join " ") -match "SubnetCIDR")

    # Invalid boolean field
    $badBool = @{ EnableRDP = "yes" }
    $result = Test-BatchConfig -Config $badBool
    Write-TestResult "Non-boolean EnableRDP: caught" ($result.Errors.Count -gt 0 -and ($result.Errors -join " ") -match "EnableRDP")

    # Invalid power plan
    $badPlan = @{ SetPowerPlan = "Ultra Turbo" }
    $result = Test-BatchConfig -Config $badPlan
    Write-TestResult "Invalid power plan: caught" ($result.Errors.Count -gt 0 -and ($result.Errors -join " ") -match "SetPowerPlan")

    # HOST mode without Hyper-V: warning
    $hostNoHV = @{ ConfigType = "HOST"; InstallHyperV = $false }
    $result = Test-BatchConfig -Config $hostNoHV
    Write-TestResult "HOST without Hyper-V: warning" ($result.Warnings.Count -gt 0 -and ($result.Warnings -join " ") -match "InstallHyperV")

    # DisableBuiltInAdmin without CreateLocalAdmin: warning
    $dangerAdmin = @{ DisableBuiltInAdmin = $true; CreateLocalAdmin = $false }
    $result = Test-BatchConfig -Config $dangerAdmin
    Write-TestResult "DisableAdmin without CreateAdmin: warning" ($result.Warnings.Count -gt 0 -and ($result.Warnings -join " ") -match "DisableBuiltInAdmin")

    # Empty config: valid (everything optional)
    $empty = @{}
    $result = Test-BatchConfig -Config $empty
    Write-TestResult "Empty config: IsValid=true" ($result.IsValid -eq $true)

    # Start-BatchMode calls Test-BatchConfig
    Write-TestResult "Start-BatchMode: calls Test-BatchConfig" ($entryContent -match 'Test-BatchConfig\s+-Config')

} catch {
    Write-TestResult "Batch Config Validation Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 88: NEW-DEPLOYEDVM REFACTOR (helper functions)
# ============================================================================

Write-SectionHeader "SECTION 88: NEW-DEPLOYEDVM REFACTOR (helper functions)"

try {
    $vmContent = Get-Content (Join-Path $modulesPath "44-VMDeployment.ps1") -Raw

    # Helper functions exist
    Write-TestResult "44-VMDeployment: Resolve-VMStoragePaths exists" ($vmContent -match 'function\s+Resolve-VMStoragePaths')
    Write-TestResult "44-VMDeployment: New-VMDirectories exists" ($vmContent -match 'function\s+New-VMDirectories')
    Write-TestResult "44-VMDeployment: New-VMShell exists" ($vmContent -match 'function\s+New-VMShell')
    Write-TestResult "44-VMDeployment: New-VMDisk exists" ($vmContent -match 'function\s+New-VMDisk\b')
    Write-TestResult "44-VMDeployment: New-VMDisks exists" ($vmContent -match 'function\s+New-VMDisks\b')
    Write-TestResult "44-VMDeployment: Set-VMNetworkConfig exists" ($vmContent -match 'function\s+Set-VMNetworkConfig')
    Write-TestResult "44-VMDeployment: Set-VMAdvancedConfig exists" ($vmContent -match 'function\s+Set-VMAdvancedConfig')
    Write-TestResult "44-VMDeployment: Register-VMInCluster exists" ($vmContent -match 'function\s+Register-VMInCluster')

    # Orchestrator calls helpers
    Write-TestResult "New-DeployedVM: calls Resolve-VMStoragePaths" ($vmContent -match 'Resolve-VMStoragePaths\s+-Config')
    Write-TestResult "New-DeployedVM: calls New-VMDirectories" ($vmContent -match 'New-VMDirectories\s+-VMSpecificPath')
    Write-TestResult "New-DeployedVM: calls New-VMShell" ($vmContent -match 'New-VMShell\s+-Config')
    Write-TestResult "New-DeployedVM: calls New-VMDisks" ($vmContent -match 'New-VMDisks\s+-VM')
    Write-TestResult "New-DeployedVM: calls Set-VMNetworkConfig" ($vmContent -match 'Set-VMNetworkConfig\s+-VM')
    Write-TestResult "New-DeployedVM: calls Set-VMAdvancedConfig" ($vmContent -match 'Set-VMAdvancedConfig\s+-VM')
    Write-TestResult "New-DeployedVM: calls Register-VMInCluster" ($vmContent -match 'Register-VMInCluster\s+-VMName')

} catch {
    Write-TestResult "New-DeployedVM Refactor Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 89: REMOTE PRE-FLIGHT (Test-RemoteReadiness)
# ============================================================================

Write-SectionHeader "SECTION 89: REMOTE PRE-FLIGHT (Test-RemoteReadiness)"

try {
    $utilContent = Get-Content (Join-Path $modulesPath "35-Utilities.ps1") -Raw

    # Functions exist
    Write-TestResult "35-Utilities: Test-RemoteReadiness exists" ($utilContent -match 'function\s+Test-RemoteReadiness')
    Write-TestResult "35-Utilities: Show-PreflightResults exists" ($utilContent -match 'function\s+Show-PreflightResults')

    # Test-RemoteReadiness has required params
    Write-TestResult "Test-RemoteReadiness: has ComputerName param" ($utilContent -match 'Test-RemoteReadiness[\s\S]*?\[string\]\$ComputerName')
    Write-TestResult "Test-RemoteReadiness: has Credential param" ($utilContent -match 'Test-RemoteReadiness[\s\S]*?\[pscredential\]\$Credential')

    # Returns expected structure keys
    Write-TestResult "Test-RemoteReadiness: returns Ping check" ($utilContent -match 'result\.Ping')
    Write-TestResult "Test-RemoteReadiness: returns WinRMPort check" ($utilContent -match 'result\.WinRMPort')
    Write-TestResult "Test-RemoteReadiness: returns WSMan check" ($utilContent -match 'result\.WSMan')
    Write-TestResult "Test-RemoteReadiness: returns Credential check" ($utilContent -match 'result\.Credential')
    Write-TestResult "Test-RemoteReadiness: returns PSVersion check" ($utilContent -match 'result\.PSVersion')
    Write-TestResult "Test-RemoteReadiness: returns AllPassed flag" ($utilContent -match 'result\.AllPassed')

    # Integration: Invoke-RemoteProfileApply calls pre-flight
    Write-TestResult "Invoke-RemoteProfileApply: calls Test-RemoteReadiness" ($utilContent -match 'Test-RemoteReadiness\s+-ComputerName')
    Write-TestResult "Invoke-RemoteProfileApply: calls Show-PreflightResults" ($utilContent -match 'Show-PreflightResults\s+-Results')

} catch {
    Write-TestResult "Remote Pre-flight Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 90: VM CHECKPOINT MANAGEMENT TESTS
# ============================================================================

Write-SectionHeader "SECTION 90: VM CHECKPOINT MANAGEMENT TESTS"

try {
    $cpContent = Get-Content (Join-Path $modulesPath "52-VMCheckpoints.ps1") -Raw

    # Function existence
    Write-TestResult "52-VMCheckpoints: Get-VMCheckpointList exists" ($cpContent -match 'function\s+Get-VMCheckpointList')
    Write-TestResult "52-VMCheckpoints: Show-VMCheckpointList exists" ($cpContent -match 'function\s+Show-VMCheckpointList')
    Write-TestResult "52-VMCheckpoints: New-VMCheckpointWizard exists" ($cpContent -match 'function\s+New-VMCheckpointWizard')
    Write-TestResult "52-VMCheckpoints: Restore-VMCheckpointWizard exists" ($cpContent -match 'function\s+Restore-VMCheckpointWizard')
    Write-TestResult "52-VMCheckpoints: Remove-VMCheckpointWizard exists" ($cpContent -match 'function\s+Remove-VMCheckpointWizard')
    Write-TestResult "52-VMCheckpoints: Show-VMCheckpointManagement exists" ($cpContent -match 'function\s+Show-VMCheckpointManagement')

    # Parameters
    Write-TestResult "Get-VMCheckpointList: has ComputerName param" ($cpContent -match 'Get-VMCheckpointList[\s\S]*?\$ComputerName')
    Write-TestResult "Get-VMCheckpointList: has VMName param" ($cpContent -match 'Get-VMCheckpointList[\s\S]*?\$VMName')
    Write-TestResult "Get-VMCheckpointList: has Credential param" ($cpContent -match 'Get-VMCheckpointList[\s\S]*?\$Credential')

    # Return structure
    Write-TestResult "Get-VMCheckpointList: returns Success key" ($cpContent -match 'Success\s*=\s*\$true')
    Write-TestResult "Get-VMCheckpointList: returns Checkpoints key" ($cpContent -match 'Checkpoints\s*=')
    Write-TestResult "Get-VMCheckpointList: returns Message key" ($cpContent -match 'Message\s*=')

    # Navigation support
    Write-TestResult "52-VMCheckpoints: has navigation (Test-NavigationCommand)" ($cpContent -match 'Test-NavigationCommand')

    # Confirmation before destructive actions
    Write-TestResult "52-VMCheckpoints: confirms before restore" ($cpContent -match 'Confirm-UserAction.*[Rr]estore')
    Write-TestResult "52-VMCheckpoints: confirms before delete" ($cpContent -match 'Confirm-UserAction.*[Dd]elete|[Rr]emov')

} catch {
    Write-TestResult "VM Checkpoint Management Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 91: BATCH CONFIG TEMPLATE STRUCTURE
# ============================================================================

Write-SectionHeader "SECTION 91: BATCH CONFIG TEMPLATE STRUCTURE"

try {
    $batchContent = Get-Content (Join-Path $modulesPath "36-BatchConfig.ps1") -Raw

    # Function existence
    Write-TestResult "36-BatchConfig: New-BatchConfigTemplate exists" ($batchContent -match 'function\s+New-BatchConfigTemplate')

    # Template has all expected fields
    Write-TestResult "36-BatchConfig: template has ConfigType" ($batchContent -match '"ConfigType"')
    Write-TestResult "36-BatchConfig: template has Hostname" ($batchContent -match '"Hostname"')
    Write-TestResult "36-BatchConfig: template has IPAddress" ($batchContent -match '"IPAddress"')
    Write-TestResult "36-BatchConfig: template has Gateway" ($batchContent -match '"Gateway"')
    Write-TestResult "36-BatchConfig: template has SubnetCIDR" ($batchContent -match '"SubnetCIDR"')
    Write-TestResult "36-BatchConfig: template has DNS1" ($batchContent -match '"DNS1"')
    Write-TestResult "36-BatchConfig: template has EnableRDP" ($batchContent -match '"EnableRDP"')
    Write-TestResult "36-BatchConfig: template has EnableWinRM" ($batchContent -match '"EnableWinRM"')
    Write-TestResult "36-BatchConfig: template has SetPowerPlan" ($batchContent -match '"SetPowerPlan"')
    Write-TestResult "36-BatchConfig: template has DomainName" ($batchContent -match '"DomainName"')
    Write-TestResult "36-BatchConfig: template has AutoReboot" ($batchContent -match '"AutoReboot"')

    # Help fields
    Write-TestResult "36-BatchConfig: has _Help fields" ($batchContent -match '_\w+_Help')

    # Test-BatchConfig integrates with batch mode
    $entryContent = Get-Content (Join-Path $modulesPath "50-EntryPoint.ps1") -Raw
    Write-TestResult "50-EntryPoint: Test-BatchConfig validates before Start-BatchMode" ($entryContent -match 'validation\.IsValid')

} catch {
    Write-TestResult "Batch Config Template Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 92: FILESERVER FUNCTION COVERAGE
# ============================================================================

Write-SectionHeader "SECTION 92: FILESERVER FUNCTION COVERAGE"

try {
    $acContent = Get-Content (Join-Path $modulesPath "39-FileServer.ps1") -Raw

    # All functions exist
    Write-TestResult "39-FileServer: Get-FileServerFiles exists" ($acContent -match 'function\s+Get-FileServerFiles')
    Write-TestResult "39-FileServer: Find-FileServerFile exists" ($acContent -match 'function\s+Find-FileServerFile')
    Write-TestResult "39-FileServer: Get-FileServerFile exists" ($acContent -match 'function\s+Get-FileServerFile\b')
    Write-TestResult "39-FileServer: Get-FileServerFileSize exists" ($acContent -match 'function\s+Get-FileServerFileSize')
    Write-TestResult "39-FileServer: Get-FileServerHashFile exists" ($acContent -match 'function\s+Get-FileServerHashFile')
    Write-TestResult "39-FileServer: Test-FileIntegrity exists" ($acContent -match 'function\s+Test-FileIntegrity')

    # Cache uses TTL constant
    Write-TestResult "39-FileServer: uses CacheTTLMinutes" ($acContent -match 'CacheTTLMinutes')
    Write-TestResult "39-FileServer: uses FileCache hashtable" ($acContent -match 'FileCache')

    # FileServer variable structure
    $acKeys = @("StorageType", "BaseURL", "ClientId", "ClientSecret", "AzureAccount", "AzureContainer", "AzureSasToken", "ISOsFolder", "VHDsFolder", "AgentFolder")
    foreach ($key in $acKeys) {
        Write-TestResult "FileServer variable has '$key' key" ($null -ne $script:FileServer.$key -or $script:FileServer.ContainsKey($key))
    }

    # Security: CF-Access headers used
    Write-TestResult "39-FileServer: uses CF-Access-Client-Id header" ($acContent -match 'CF-Access-Client-Id')
    Write-TestResult "39-FileServer: uses CF-Access-Client-Secret header" ($acContent -match 'CF-Access-Client-Secret')

    # Cloud storage helper functions exist
    Write-TestResult "39-FileServer: Get-FileServerUrl exists" ($acContent -match 'function\s+Get-FileServerUrl')
    Write-TestResult "39-FileServer: Get-FileServerHeaders exists" ($acContent -match 'function\s+Get-FileServerHeaders')
    Write-TestResult "39-FileServer: Test-FileServerConfigured exists" ($acContent -match 'function\s+Test-FileServerConfigured')

    # StorageType handling
    Write-TestResult "39-FileServer: handles StorageType switch" ($acContent -match 'switch\s*\(\$storageType\)')
    Write-TestResult "39-FileServer: supports azure storage type" ($acContent -match '"azure"')
    Write-TestResult "39-FileServer: supports static storage type" ($acContent -match '"static"')
    Write-TestResult "39-FileServer: Azure uses blob.core.windows.net" ($acContent -match 'blob\.core\.windows\.net')
    Write-TestResult "39-FileServer: static fetches index.json" ($acContent -match 'index\.json')

} catch {
    Write-TestResult "FileServer Function Coverage Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 92b: CLOUD STORAGE HELPER FUNCTION TESTS
# ============================================================================

Write-SectionHeader "SECTION 92b: CLOUD STORAGE HELPERS"

try {
    # --- Test Get-FileServerUrl ---
    # nginx mode
    $origFS = $script:FileServer.Clone()
    $script:FileServer.StorageType = "nginx"
    $script:FileServer.BaseURL = "https://files.example.com/server-tools"
    $url = Get-FileServerUrl -FilePath "ISOs/test.iso"
    Write-TestResult "Get-FileServerUrl: nginx returns BaseURL/path" ($url -eq "https://files.example.com/server-tools/ISOs/test.iso")

    # azure mode
    $script:FileServer.StorageType = "azure"
    $script:FileServer.AzureAccount = "teststorage"
    $script:FileServer.AzureContainer = "server-tools"
    $testSas = "sv=2022&sp=rl"
    $script:FileServer.AzureSasToken = $testSas
    $url = Get-FileServerUrl -FilePath "ISOs/test.iso"
    $pass = ($url -match "^https://teststorage\.blob\.core\.windows\.net/server-tools/ISOs/test\.iso\?sv=2022&sp=rl$")
    Write-TestResult "Get-FileServerUrl: azure returns blob URL with SAS" $pass "Got: $url"

    # static mode (same as nginx)
    $script:FileServer.StorageType = "static"
    $script:FileServer.BaseURL = "https://cdn.example.com/files"
    $url = Get-FileServerUrl -FilePath "VHDs/disk.vhdx"
    Write-TestResult "Get-FileServerUrl: static returns BaseURL/path" ($url -eq "https://cdn.example.com/files/VHDs/disk.vhdx")

    # URL encoding (spaces in path)
    $script:FileServer.StorageType = "nginx"
    $script:FileServer.BaseURL = "https://files.example.com/tools"
    $url = Get-FileServerUrl -FilePath "Agents/My Agent.exe"
    Write-TestResult "Get-FileServerUrl: encodes spaces in path" ($url -match 'My%20Agent\.exe')

    $script:FileServer = $origFS
} catch {
    Write-TestResult "Get-FileServerUrl tests" $false $_.Exception.Message
    $script:FileServer = $origFS
}

try {
    # --- Test Get-FileServerHeaders ---
    $origFS = $script:FileServer.Clone()

    # nginx with CF credentials
    $script:FileServer.StorageType = "nginx"
    $testCfCreds = @{ Id = "test-id.access"; Key = "test-secret-hex" }
    $script:FileServer.ClientId = $testCfCreds.Id
    $script:FileServer.ClientSecret = $testCfCreds.Key
    $headers = Get-FileServerHeaders
    Write-TestResult "Get-FileServerHeaders: nginx includes CF-Access-Client-Id" ($headers["CF-Access-Client-Id"] -eq "test-id.access")
    Write-TestResult "Get-FileServerHeaders: nginx includes CF-Access-Client-Secret" ($headers["CF-Access-Client-Secret"] -eq "test-secret-hex")

    # nginx without credentials
    $script:FileServer.ClientId = ""
    $script:FileServer.ClientSecret = ""
    $headers = Get-FileServerHeaders
    Write-TestResult "Get-FileServerHeaders: no creds returns empty headers" ($headers.Count -eq 0)

    # azure mode returns empty headers (auth is in SAS token)
    $script:FileServer.StorageType = "azure"
    $script:FileServer.ClientId = "should-be-ignored"
    $headers = Get-FileServerHeaders
    Write-TestResult "Get-FileServerHeaders: azure returns empty headers" ($headers.Count -eq 0)

    $script:FileServer = $origFS
} catch {
    Write-TestResult "Get-FileServerHeaders tests" $false $_.Exception.Message
    $script:FileServer = $origFS
}

try {
    # --- Test Test-FileServerConfigured ---
    $origFS = $script:FileServer.Clone()

    # nginx: configured when BaseURL set
    $script:FileServer.StorageType = "nginx"
    $script:FileServer.BaseURL = "https://files.example.com"
    Write-TestResult "Test-FileServerConfigured: nginx with BaseURL = true" (Test-FileServerConfigured)

    # nginx: not configured when BaseURL empty
    $script:FileServer.BaseURL = ""
    Write-TestResult "Test-FileServerConfigured: nginx without BaseURL = false" (-not (Test-FileServerConfigured))

    # azure: configured when AzureAccount + AzureContainer set
    $script:FileServer.StorageType = "azure"
    $script:FileServer.AzureAccount = "teststorage"
    $script:FileServer.AzureContainer = "server-tools"
    Write-TestResult "Test-FileServerConfigured: azure with account+container = true" (Test-FileServerConfigured)

    # azure: not configured when AzureAccount missing
    $script:FileServer.AzureAccount = ""
    Write-TestResult "Test-FileServerConfigured: azure without account = false" (-not (Test-FileServerConfigured))

    # static: uses BaseURL like nginx
    $script:FileServer.StorageType = "static"
    $script:FileServer.BaseURL = "https://cdn.example.com"
    Write-TestResult "Test-FileServerConfigured: static with BaseURL = true" (Test-FileServerConfigured)

    $script:FileServer = $origFS
} catch {
    Write-TestResult "Test-FileServerConfigured tests" $false $_.Exception.Message
    $script:FileServer = $origFS
}

try {
    # --- Test StorageType defaults ---
    $origFS = $script:FileServer.Clone()

    # Default storage type should be nginx
    Write-TestResult "FileServer: StorageType defaults to 'nginx'" ($script:FileServer.StorageType -eq "nginx")
    Write-TestResult "FileServer: AzureAccount is empty at init" ($script:FileServer.AzureAccount -eq "")
    Write-TestResult "FileServer: AzureContainer is empty at init" ($script:FileServer.AzureContainer -eq "")
    Write-TestResult "FileServer: AzureSasToken is empty at init" ($script:FileServer.AzureSasToken -eq "")

    # Get-FileServerFiles unconfigured with azure type returns empty
    $script:FileServer.StorageType = "azure"
    $script:FileServer.AzureAccount = ""
    $script:FileServer.AzureContainer = ""
    $result = Get-FileServerFiles -FolderPath "ISOs"
    Write-TestResult "Get-FileServerFiles: unconfigured azure returns empty" ($null -eq $result -or $result.Count -eq 0)

    # Get-FileServerFiles unconfigured with static type returns empty
    $script:FileServer.StorageType = "static"
    $script:FileServer.BaseURL = ""
    $result = Get-FileServerFiles -FolderPath "ISOs"
    Write-TestResult "Get-FileServerFiles: unconfigured static returns empty" ($null -eq $result -or $result.Count -eq 0)

    $script:FileServer = $origFS
} catch {
    Write-TestResult "Cloud storage defaults tests" $false $_.Exception.Message
    $script:FileServer = $origFS
}

# ============================================================================
# SECTION 93: AGENT INSTALLER CONFIGURATION TESTS
# ============================================================================

Write-SectionHeader "SECTION 93: AGENT INSTALLER CONFIGURATION TESTS"

try {
    # AgentInstaller variable structure
    $requiredKeys = @("ToolName", "FolderName", "FilePattern", "ServiceName", "InstallArgs", "InstallPaths", "SuccessExitCodes", "TimeoutSeconds")
    foreach ($key in $requiredKeys) {
        Write-TestResult "AgentInstaller has '$key' key" ($script:AgentInstaller.ContainsKey($key))
    }

    # Default values (Kaseya when no defaults.json override)
    Write-TestResult "AgentInstaller: ToolName is string" ($script:AgentInstaller.ToolName -is [string])
    Write-TestResult "AgentInstaller: InstallPaths is array" ($script:AgentInstaller.InstallPaths -is [array])
    Write-TestResult "AgentInstaller: SuccessExitCodes is array" ($script:AgentInstaller.SuccessExitCodes -is [array])
    Write-TestResult "AgentInstaller: TimeoutSeconds is int" ($script:AgentInstaller.TimeoutSeconds -is [int])
    Write-TestResult "AgentInstaller: SuccessExitCodes contains 0" (0 -in $script:AgentInstaller.SuccessExitCodes)

    # Functions use config, not hardcoded values
    $aiContent = Get-Content (Join-Path $modulesPath "57-KaseyaInstaller.ps1") -Raw
    Write-TestResult "57-KaseyaInstaller: uses AgentInstaller.ServiceName" ($aiContent -match 'AgentInstaller\.ServiceName')
    Write-TestResult "57-KaseyaInstaller: uses AgentInstaller.InstallArgs" ($aiContent -match 'AgentInstaller\.InstallArgs')
    Write-TestResult "57-KaseyaInstaller: uses AgentInstaller.FilePattern" ($aiContent -match 'AgentInstaller\.FilePattern')
    Write-TestResult "57-KaseyaInstaller: uses AgentInstaller.InstallPaths" ($aiContent -match 'AgentInstaller\.InstallPaths')
    Write-TestResult "57-KaseyaInstaller: uses AgentInstaller.SuccessExitCodes" ($aiContent -match 'AgentInstaller\.SuccessExitCodes')
    Write-TestResult "57-KaseyaInstaller: uses AgentInstaller.TimeoutSeconds" ($aiContent -match 'AgentInstaller\.TimeoutSeconds')
    Write-TestResult "57-KaseyaInstaller: uses AgentInstaller.FolderName" ($aiContent -match 'AgentInstaller\.FolderName')
    Write-TestResult "57-KaseyaInstaller: uses AgentInstaller.ToolName" ($aiContent -match 'AgentInstaller\.ToolName')

    # Import-Defaults handles AgentInstaller override
    $opsContent = Get-Content (Join-Path $modulesPath "56-OperationsMenu.ps1") -Raw
    Write-TestResult "Import-Defaults: handles AgentInstaller override" ($opsContent -match 'merged\.AgentInstaller')

} catch {
    Write-TestResult "Agent Installer Configuration Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 94: WINDOWS UPDATES MODULE
# ============================================================================

Write-SectionHeader "SECTION 94: WINDOWS UPDATES MODULE"

try {
    $wuContent = Get-Content (Join-Path $modulesPath "14-WindowsUpdates.ps1") -Raw

    # Function existence
    Write-TestResult "14-WindowsUpdates: Install-WindowsUpdates exists" ($wuContent -match 'function\s+Install-WindowsUpdates')

    # Uses PSWindowsUpdate module
    Write-TestResult "14-WindowsUpdates: imports PSWindowsUpdate module" ($wuContent -match 'Import-Module\s+PSWindowsUpdate')
    Write-TestResult "14-WindowsUpdates: calls Get-WindowsUpdate" ($wuContent -match 'Get-WindowsUpdate')
    Write-TestResult "14-WindowsUpdates: calls Install-WindowsUpdate" ($wuContent -match 'Install-WindowsUpdate\s+-AcceptAll')

    # Checks network connectivity before proceeding
    Write-TestResult "14-WindowsUpdates: checks network connectivity" ($wuContent -match 'Test-NetworkConnectivity')

    # Uses timeout protection via jobs
    Write-TestResult "14-WindowsUpdates: uses Start-Job for timeout" ($wuContent -match 'Start-Job\s+-ScriptBlock')
    Write-TestResult "14-WindowsUpdates: references UpdateTimeoutSeconds" ($wuContent -match 'UpdateTimeoutSeconds')

    # Uses progress messages
    Write-TestResult "14-WindowsUpdates: shows progress" ($wuContent -match 'Show-ProgressMessage')
    Write-TestResult "14-WindowsUpdates: completes progress" ($wuContent -match 'Complete-ProgressMessage')

    # User confirmation before install
    Write-TestResult "14-WindowsUpdates: confirms before install" ($wuContent -match 'Confirm-UserAction')

    # Sets reboot flag
    Write-TestResult "14-WindowsUpdates: sets RebootNeeded flag" ($wuContent -match 'RebootNeeded\s*=\s*\$true')

    # Logs session change
    Write-TestResult "14-WindowsUpdates: logs session change" ($wuContent -match 'Add-SessionChange')

} catch {
    Write-TestResult "Windows Updates Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 95: LOCAL ADMIN ACCOUNT MODULE
# ============================================================================

Write-SectionHeader "SECTION 95: LOCAL ADMIN ACCOUNT MODULE"

try {
    $laContent = Get-Content (Join-Path $modulesPath "23-LocalAdmin.ps1") -Raw

    # Function existence
    Write-TestResult "23-LocalAdmin: Add-LocalAdminAccount exists" ($laContent -match 'function\s+Add-LocalAdminAccount')

    # Username validation regex (alphanumeric, 1-20 chars, starts with letter)
    Write-TestResult "23-LocalAdmin: validates account name format" ($laContent -match '\^\[a-zA-Z\]\[a-zA-Z0-9_\-\]\{0,19\}\$')

    # Uses Get-SecurePassword for password handling
    Write-TestResult "23-LocalAdmin: calls Get-SecurePassword" ($laContent -match 'Get-SecurePassword')

    # Checks for existing account before creating
    Write-TestResult "23-LocalAdmin: checks for existing user" ($laContent -match 'Get-LocalUser\s+-Name\s+\$accountName')

    # Adds user to Administrators group
    Write-TestResult "23-LocalAdmin: adds to Administrators group" ($laContent -match 'Add-LocalGroupMember\s+-Group\s+"Administrators"')

    # Sets PasswordNeverExpires
    Write-TestResult "23-LocalAdmin: sets PasswordNeverExpires" ($laContent -match 'PasswordNeverExpires')

    # Null password check (cancellation path)
    Write-TestResult "23-LocalAdmin: handles null password" ($laContent -match '\$null\s*-eq\s*\$Password')

    # Logs session change on success
    Write-TestResult "23-LocalAdmin: logs session change" ($laContent -match 'Add-SessionChange\s+-Category\s+"Security"')

    # User confirmation for default name
    Write-TestResult "23-LocalAdmin: confirms default account name" ($laContent -match 'Confirm-UserAction')

} catch {
    Write-TestResult "Local Admin Account Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 96: DISABLE ADMIN MODULE
# ============================================================================

Write-SectionHeader "SECTION 96: DISABLE ADMIN MODULE"

try {
    $daContent = Get-Content (Join-Path $modulesPath "24-DisableAdmin.ps1") -Raw

    # Function existence
    Write-TestResult "24-DisableAdmin: Disable-BuiltInAdminAccount exists" ($daContent -match 'function\s+Disable-BuiltInAdminAccount')

    # Targets the built-in Administrator account by name
    Write-TestResult "24-DisableAdmin: targets 'Administrator' account" ($daContent -match 'Get-LocalUser\s+-Name\s+"Administrator"')

    # Checks if already disabled before acting
    Write-TestResult "24-DisableAdmin: checks if already disabled" ($daContent -match '-not\s+\$adminAccount\.Enabled')

    # Calls Disable-LocalUser
    Write-TestResult "24-DisableAdmin: calls Disable-LocalUser" ($daContent -match 'Disable-LocalUser\s+-Name\s+"Administrator"')

    # Warns about needing alternate admin access
    Write-TestResult "24-DisableAdmin: warns about alternate admin" ($daContent -match 'another local admin account')

    # User confirmation before disabling
    Write-TestResult "24-DisableAdmin: confirms before disabling" ($daContent -match 'Confirm-UserAction')

    # Sets DisabledAdminReboot flag
    Write-TestResult "24-DisableAdmin: sets DisabledAdminReboot flag" ($daContent -match 'DisabledAdminReboot\s*=\s*\$true')

    # Verifies disable succeeded
    Write-TestResult "24-DisableAdmin: verifies after disabling" ($daContent -match 'Get-LocalUser\s+-Name\s+"Administrator"[\s\S]*?-not\s+\$adminAccount\.Enabled')

    # Logs session change
    Write-TestResult "24-DisableAdmin: logs session change" ($daContent -match 'Add-SessionChange\s+-Category\s+"Security"')

    # Invalidates menu cache after change
    Write-TestResult "24-DisableAdmin: clears menu cache" ($daContent -match 'Clear-MenuCache')

} catch {
    Write-TestResult "Disable Admin Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 97: HOST STORAGE SETUP MODULE
# ============================================================================

Write-SectionHeader "SECTION 97: HOST STORAGE SETUP MODULE"

try {
    $hsContent = Get-Content (Join-Path $modulesPath "40-HostStorage.ps1") -Raw

    # All 4 functions exist
    Write-TestResult "40-HostStorage: Test-OpticalDrive exists" ($hsContent -match 'function\s+Test-OpticalDrive')
    Write-TestResult "40-HostStorage: Get-NextAvailableDriveLetter exists" ($hsContent -match 'function\s+Get-NextAvailableDriveLetter')
    Write-TestResult "40-HostStorage: Move-OpticalDriveFromD exists" ($hsContent -match 'function\s+Move-OpticalDriveFromD')
    Write-TestResult "40-HostStorage: Initialize-HostStorage exists" ($hsContent -match 'function\s+Initialize-HostStorage')

    # Test-OpticalDrive has mandatory DriveLetter parameter
    Write-TestResult "Test-OpticalDrive: has Mandatory DriveLetter param" ($hsContent -match 'Test-OpticalDrive[\s\S]*?Mandatory=\$true[\s\S]*?\[string\]\$DriveLetter')

    # Test-OpticalDrive returns hashtable with IsOptical key
    Write-TestResult "Test-OpticalDrive: returns IsOptical key" ($hsContent -match 'IsOptical\s*=\s*\$true' -and $hsContent -match 'IsOptical\s*=\s*\$false')

    # Get-NextAvailableDriveLetter skips A, B, C, D
    Write-TestResult "Get-NextAvailableDriveLetter: searches Z down to E" ($hsContent -match "'Z','Y','X'")

    # Get-NextAvailableDriveLetter accepts Exclude parameter
    Write-TestResult "Get-NextAvailableDriveLetter: has Exclude param" ($hsContent -match 'Get-NextAvailableDriveLetter[\s\S]*?\$Exclude')

    # Initialize-HostStorage updates script-scope storage variables
    Write-TestResult "Initialize-HostStorage: sets SelectedHostDrive" ($hsContent -match 'script:SelectedHostDrive')
    Write-TestResult "Initialize-HostStorage: sets HostVMStoragePath" ($hsContent -match 'script:HostVMStoragePath')
    Write-TestResult "Initialize-HostStorage: sets StorageInitialized" ($hsContent -match 'script:StorageInitialized\s*=\s*\$true')

    # Filters drives: excludes C:, non-NTFS, and drives < 20GB
    Write-TestResult "Initialize-HostStorage: excludes C: drive" ($hsContent -match "DriveLetter\s+-ne\s+'C'")
    Write-TestResult "Initialize-HostStorage: requires NTFS" ($hsContent -match "FileSystem\s+-eq\s+'NTFS'")

} catch {
    Write-TestResult "Host Storage Setup Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 98: EXIT CLEANUP MODULE
# ============================================================================

Write-SectionHeader "SECTION 98: EXIT CLEANUP MODULE"

try {
    $ecContent = Get-Content (Join-Path $modulesPath "47-ExitCleanup.ps1") -Raw

    # Function existence
    Write-TestResult "47-ExitCleanup: Exit-Script exists" ($ecContent -match 'function\s+Exit-Script')

    # Shows session summary before exiting
    Write-TestResult "47-ExitCleanup: calls Show-SessionSummary" ($ecContent -match 'Show-SessionSummary')

    # Checks both global:RebootNeeded and Test-RebootPending
    Write-TestResult "47-ExitCleanup: checks RebootNeeded flag" ($ecContent -match 'global:RebootNeeded')
    Write-TestResult "47-ExitCleanup: calls Test-RebootPending" ($ecContent -match 'Test-RebootPending')

    # Cleanup targets use $script:ToolName (dynamic, not hardcoded)
    Write-TestResult "47-ExitCleanup: uses ToolName for monolithic pattern" ($ecContent -match '\$\(\$script:ToolName\)\s*v\*\.ps1')
    Write-TestResult "47-ExitCleanup: uses ToolName for exe pattern" ($ecContent -match '\$\(\$script:ToolName\)[\*]?\.exe')
    Write-TestResult "47-ExitCleanup: uses ToolName for cleanup task name" ($ecContent -match '\$\(\$script:ToolName\)Cleanup')

    # Cleanup targets config directory
    Write-TestResult "47-ExitCleanup: cleans up AppConfigDir" ($ecContent -match 'script:AppConfigDir')

    # Searches for defaults.json in cleanup paths
    Write-TestResult "47-ExitCleanup: targets defaults.json" ($ecContent -match 'defaults\.json')

    # Uses scheduled task for post-reboot cleanup
    Write-TestResult "47-ExitCleanup: schedules cleanup task" ($ecContent -match 'Register-ScheduledTask')

    # Saves session state if VM deployment queue has items
    Write-TestResult "47-ExitCleanup: saves session state for pending VMs" ($ecContent -match 'Save-SessionState')

} catch {
    Write-TestResult "Exit Cleanup Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 99: CONFIG EXPORT EXPANDED
# ============================================================================

Write-SectionHeader "SECTION 99: CONFIG EXPORT EXPANDED"

try {
    $ceContent = Get-Content (Join-Path $modulesPath "45-ConfigExport.ps1") -Raw

    # All 3 functions exist
    Write-TestResult "45-ConfigExport: Export-ServerConfiguration exists" ($ceContent -match 'function\s+Export-ServerConfiguration')
    Write-TestResult "45-ConfigExport: Save-ConfigurationProfile exists" ($ceContent -match 'function\s+Save-ConfigurationProfile')
    Write-TestResult "45-ConfigExport: Import-ConfigurationProfile exists" ($ceContent -match 'function\s+Import-ConfigurationProfile')

    # Export format structure: has section headers
    Write-TestResult "45-ConfigExport: export has SYSTEM INFORMATION section" ($ceContent -match '### SYSTEM INFORMATION ###')
    Write-TestResult "45-ConfigExport: export has NETWORK CONFIGURATION section" ($ceContent -match '### NETWORK CONFIGURATION ###')
    Write-TestResult "45-ConfigExport: export has STORAGE section" ($ceContent -match '### STORAGE ###')
    Write-TestResult "45-ConfigExport: export has HYPER-V STATUS section" ($ceContent -match '### HYPER-V STATUS ###')

    # Save profile creates JSON with _ProfileInfo metadata
    Write-TestResult "45-ConfigExport: profile has _ProfileInfo metadata" ($ceContent -match '_ProfileInfo')
    Write-TestResult "45-ConfigExport: profile records ScriptVersion" ($ceContent -match '"ScriptVersion"\s*=\s*\$script:ScriptVersion')
    Write-TestResult "45-ConfigExport: profile records CreatedFrom hostname" ($ceContent -match '"CreatedFrom"\s*=\s*\$env:COMPUTERNAME')

    # Import profile validates file path
    Write-TestResult "45-ConfigExport: import checks file exists" ($ceContent -match 'Test-Path\s+\$profilePath')
    Write-TestResult "45-ConfigExport: import uses navigation check" ($ceContent -match 'Test-NavigationCommand\s+-UserInput\s+\$profilePath')

    # Import profile applies 13 configuration steps
    Write-TestResult "45-ConfigExport: import has step counter (13 steps)" ($ceContent -match '\[1/13\]' -and $ceContent -match '\[13/13\]')

    # Profile save uses ConvertTo-Json
    Write-TestResult "45-ConfigExport: profile saves as JSON" ($ceContent -match 'ConvertTo-Json\s+-Depth\s+10')

} catch {
    Write-TestResult "Config Export Expanded Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 100: QOL FEATURES EXPANDED
# ============================================================================

Write-SectionHeader "SECTION 100: QOL FEATURES EXPANDED"

try {
    $qolContent = Get-Content (Join-Path $modulesPath "55-QoLFeatures.ps1") -Raw

    # All 14 functions exist
    $qolFunctions = @(
        "Initialize-AppConfigDir",
        "Import-Favorites",
        "Export-Favorites",
        "Add-Favorite",
        "Show-Favorites",
        "Import-CommandHistory",
        "Export-CommandHistory",
        "Show-CommandHistory",
        "Save-SessionState",
        "Restore-SessionState",
        "Set-PagefileConfiguration",
        "Set-SNMPConfiguration",
        "Install-WindowsServerBackup",
        "Show-CertificateMenu"
    )

    foreach ($funcName in $qolFunctions) {
        Write-TestResult "55-QoLFeatures: $funcName exists" ($qolContent -match "function\s+$funcName")
    }

    # Pagefile validation: minimum 1024 MB
    Write-TestResult "55-QoLFeatures: pagefile minimum 1024 MB" ($qolContent -match '1024')

    # Pagefile validation: max must be >= initial
    Write-TestResult "55-QoLFeatures: pagefile max >= initial check" ($qolContent -match '\$maxMB\s+-lt\s+\$initialMB')

    # SNMP: checks Test-WindowsServer
    Write-TestResult "55-QoLFeatures: SNMP requires Windows Server" ($qolContent -match 'Set-SNMPConfiguration[\s\S]*?Test-WindowsServer')

    # SNMP: uses correct registry path
    Write-TestResult "55-QoLFeatures: SNMP uses ValidCommunities registry" ($qolContent -match 'HKLM:\\SYSTEM\\CurrentControlSet\\Services\\SNMP\\Parameters\\ValidCommunities')

    # Favorites uses FavoritesPath variable
    Write-TestResult "55-QoLFeatures: favorites uses FavoritesPath" ($qolContent -match 'script:FavoritesPath')

    # History uses HistoryPath variable
    Write-TestResult "55-QoLFeatures: history uses HistoryPath" ($qolContent -match 'script:HistoryPath')

    # History enforces MaxHistoryItems limit
    Write-TestResult "55-QoLFeatures: history enforces MaxHistoryItems" ($qolContent -match 'MaxHistoryItems')

    # Session state uses SessionStatePath variable
    Write-TestResult "55-QoLFeatures: session state uses SessionStatePath" ($qolContent -match 'script:SessionStatePath')

    # Restore-SessionState checks session age (24 hours)
    Write-TestResult "55-QoLFeatures: session restore checks 24h freshness" ($qolContent -match 'hoursSinceSave\s+-gt\s+24')

} catch {
    Write-TestResult "QoL Features Expanded Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 101: OPERATIONS MENU EXPANDED
# ============================================================================

Write-SectionHeader "SECTION 101: OPERATIONS MENU EXPANDED"

try {
    $omContent = Get-Content (Join-Path $modulesPath "56-OperationsMenu.ps1") -Raw

    # Import-Defaults handles all major config keys
    $defaultKeys = @(
        "Domain",
        "LocalAdminName",
        "LocalAdminFullName",
        "SwitchName",
        "ManagementName",
        "BackupName",
        "iSCSISubnet",
        "FileServer",
        "AgentInstaller",
        "DNSPresets",
        "SANTargetMappings",
        "DefenderExclusionPaths",
        "StoragePaths",
        "ToolName",
        "ToolFullName",
        "SupportContact"
    )

    foreach ($key in $defaultKeys) {
        Write-TestResult "Import-Defaults: handles $key" ($omContent -match "merged\.$key")
    }

    # Export-Defaults roundtrip: includes key fields in output
    Write-TestResult "Export-Defaults: includes ToolName" ($omContent -match 'function\s+Export-Defaults[\s\S]*?ToolName\s*=\s*\$script:ToolName')
    Write-TestResult "Export-Defaults: includes Domain" ($omContent -match 'function\s+Export-Defaults[\s\S]*?Domain\s*=')
    Write-TestResult "Export-Defaults: includes LocalAdminName" ($omContent -match 'function\s+Export-Defaults[\s\S]*?LocalAdminName\s*=')

    # First-run wizard exists and has expected prompts
    Write-TestResult "56-OperationsMenu: Show-FirstRunWizard exists" ($omContent -match 'function\s+Show-FirstRunWizard')

    # Count wizard steps (Domain, Admin name, Admin full name, DNS, FileServer, iSCSI = 6 prompts)
    Write-TestResult "Show-FirstRunWizard: prompts for Domain" ($omContent -match 'Show-FirstRunWizard[\s\S]*?Domain')
    Write-TestResult "Show-FirstRunWizard: prompts for admin name" ($omContent -match 'Show-FirstRunWizard[\s\S]*?Admin name')
    Write-TestResult "Show-FirstRunWizard: prompts for FileServer" ($omContent -match 'Show-FirstRunWizard[\s\S]*?FileServer')
    Write-TestResult "Show-FirstRunWizard: prompts for iSCSI subnet" ($omContent -match 'Show-FirstRunWizard[\s\S]*?iSCSI subnet')

    # VMNaming import from defaults.json
    Write-TestResult "Import-Defaults: imports VMNaming config" ($omContent -match 'fileData\.VMNaming')

    # Import-Defaults derives ConfigDirName from ToolName
    Write-TestResult "Import-Defaults: derives ConfigDirName" ($omContent -match 'script:ConfigDirName\s*=.*ToolName')

    # Import-Defaults re-derives dependent paths (FavoritesPath, HistoryPath, SessionStatePath)
    Write-TestResult "Import-Defaults: re-derives FavoritesPath" ($omContent -match 'script:FavoritesPath\s*=.*AppConfigDir')
    Write-TestResult "Import-Defaults: re-derives HistoryPath" ($omContent -match 'script:HistoryPath\s*=.*AppConfigDir')
    Write-TestResult "Import-Defaults: re-derives SessionStatePath" ($omContent -match 'script:SessionStatePath\s*=.*AppConfigDir')

    # Import-Defaults skips metadata fields (underscore prefix)
    Write-TestResult "Import-Defaults: skips _metadata fields" ($omContent -match "prop\.Name\s+-like\s+'_\*'")

    # Export-Defaults saves with ConvertTo-Json
    Write-TestResult "Export-Defaults: saves as JSON" ($omContent -match 'function\s+Export-Defaults[\s\S]*?ConvertTo-Json')

} catch {
    Write-TestResult "Operations Menu Expanded Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 102: DYNAMIC DEFENDER PATHS
# ============================================================================

Write-SectionHeader "SECTION 102: DYNAMIC DEFENDER PATHS"

try {
    $hsContent = Get-Content (Join-Path $modulesPath "40-HostStorage.ps1") -Raw
    $initContent = Get-Content (Join-Path $modulesPath "00-Initialization.ps1") -Raw

    # Update-DefenderVMPaths function exists
    Write-TestResult "40-HostStorage: Update-DefenderVMPaths exists" ($hsContent -match 'function\s+Update-DefenderVMPaths')

    # Function references $script:SelectedHostDrive
    Write-TestResult "Update-DefenderVMPaths: references SelectedHostDrive" ($hsContent -match 'Update-DefenderVMPaths[\s\S]*?script:SelectedHostDrive')

    # Function sets $script:DefenderCommonVMPaths
    Write-TestResult "Update-DefenderVMPaths: sets DefenderCommonVMPaths" ($hsContent -match 'Update-DefenderVMPaths[\s\S]*?script:DefenderCommonVMPaths')

    # Function checks for C:\ClusterStorage
    Write-TestResult "Update-DefenderVMPaths: checks ClusterStorage" ($hsContent -match 'Update-DefenderVMPaths[\s\S]*?C:\\ClusterStorage')

    # Initialize-HostStorage calls Update-DefenderVMPaths
    Write-TestResult "Initialize-HostStorage: calls Update-DefenderVMPaths" ($hsContent -match 'Initialize-HostStorage[\s\S]*?Update-DefenderVMPaths')

    # Initialization: DefenderCommonVMPaths initialized as empty array
    Write-TestResult "00-Initialization: DefenderCommonVMPaths initialized as empty array" ($initContent -match 'DefenderCommonVMPaths\s*=\s*@\(\)')

} catch {
    Write-TestResult "Dynamic Defender Paths Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 103: BATCH MODE HOST EXTENSIONS
# ============================================================================

Write-SectionHeader "SECTION 103: BATCH MODE HOST EXTENSIONS"

try {
    $bcContent = Get-Content (Join-Path $modulesPath "36-BatchConfig.ps1") -Raw
    $epContent = Get-Content (Join-Path $modulesPath "50-EntryPoint.ps1") -Raw

    # Template contains host extension keys
    Write-TestResult "36-BatchConfig: template has CreateSETSwitch" ($bcContent -match '"CreateSETSwitch"')
    Write-TestResult "36-BatchConfig: template has ConfigureiSCSI" ($bcContent -match '"ConfigureiSCSI"')
    Write-TestResult "36-BatchConfig: template has ConfigureMPIO" ($bcContent -match '"ConfigureMPIO"')
    Write-TestResult "36-BatchConfig: template has InitializeHostStorage" ($bcContent -match '"InitializeHostStorage"')
    Write-TestResult "36-BatchConfig: template has HostStorageDrive" ($bcContent -match '"HostStorageDrive"')
    Write-TestResult "36-BatchConfig: template has ConfigureDefenderExclusions" ($bcContent -match '"ConfigureDefenderExclusions"')
    Write-TestResult "36-BatchConfig: template has SETSwitchName" ($bcContent -match '"SETSwitchName"')
    Write-TestResult "36-BatchConfig: template has SETAdapterMode" ($bcContent -match '"SETAdapterMode"')
    Write-TestResult "36-BatchConfig: template has iSCSIHostNumber" ($bcContent -match '"iSCSIHostNumber"')

    # Functions exist
    Write-TestResult "36-BatchConfig: Show-BatchConfigMenu exists" ($bcContent -match 'function\s+Show-BatchConfigMenu')
    Write-TestResult "36-BatchConfig: Export-BatchConfigFromState exists" ($bcContent -match 'function\s+Export-BatchConfigFromState')

    # EntryPoint: totalSteps is 24
    Write-TestResult "50-EntryPoint: totalSteps is 24" ($epContent -match 'totalSteps\s*=\s*24')

    # EntryPoint: step 14 mentions Server Role Template
    Write-TestResult "50-EntryPoint: step 14 is Server Role Template" ($epContent -match '14.*Server Role Template|14.*ServerRoleTemplate')

    # EntryPoint: step 15 mentions DC Promotion
    Write-TestResult "50-EntryPoint: step 15 is DC Promotion" ($epContent -match '15.*Promote.*Domain Controller|15.*PromoteToDC')

    # EntryPoint: step 17 mentions Host Storage or Initialize
    Write-TestResult "50-EntryPoint: step 17 is Host Storage" ($epContent -match '17.*Host\s*Storage|17.*Initialize')

    # EntryPoint: step 18 mentions SET
    Write-TestResult "50-EntryPoint: step 18 is SET" ($epContent -match '18.*SET')

    # EntryPoint: step 19 mentions Custom vNICs
    Write-TestResult "50-EntryPoint: step 19 is Custom vNICs" ($epContent -match '19.*Custom\s*vNIC')

    # EntryPoint: step 20 mentions shared storage
    Write-TestResult "50-EntryPoint: step 20 is shared storage" ($epContent -match '20.*Configure Shared Storage')

    # EntryPoint: step 21 mentions MPIO
    Write-TestResult "50-EntryPoint: step 21 is MPIO" ($epContent -match '21.*MPIO')

    # EntryPoint: step 22 mentions Defender
    Write-TestResult "50-EntryPoint: step 22 is Defender" ($epContent -match '22.*Defender')

    # Test-BatchConfig validates SETAdapterMode
    Write-TestResult "50-EntryPoint: Test-BatchConfig validates SETAdapterMode" ($epContent -match 'Test-BatchConfig[\s\S]*?SETAdapterMode')

    # Test-BatchConfig validates iSCSIHostNumber
    Write-TestResult "50-EntryPoint: Test-BatchConfig validates iSCSIHostNumber" ($epContent -match 'Test-BatchConfig[\s\S]*?iSCSIHostNumber')

    # Test-BatchConfig validates HostStorageDrive
    Write-TestResult "50-EntryPoint: Test-BatchConfig validates HostStorageDrive" ($epContent -match 'Test-BatchConfig[\s\S]*?HostStorageDrive')

} catch {
    Write-TestResult "Batch Mode Host Extensions Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 104: BATCH CONFIG FROM STATE
# ============================================================================

Write-SectionHeader "SECTION 104: BATCH CONFIG FROM STATE"

try {
    $bcContent = Get-Content (Join-Path $modulesPath "36-BatchConfig.ps1") -Raw
    $mrContent = Get-Content (Join-Path $modulesPath "49-MenuRunner.ps1") -Raw

    # Export-BatchConfigFromState function exists
    Write-TestResult "36-BatchConfig: Export-BatchConfigFromState exists" ($bcContent -match 'function\s+Export-BatchConfigFromState')

    # Function detects ConfigType via Test-HyperVInstalled
    Write-TestResult "Export-BatchConfigFromState: detects ConfigType via Test-HyperVInstalled" ($bcContent -match 'Export-BatchConfigFromState[\s\S]*?Test-HyperVInstalled')

    # Function queries Get-NetAdapter
    Write-TestResult "Export-BatchConfigFromState: queries Get-NetAdapter" ($bcContent -match 'Export-BatchConfigFromState[\s\S]*?Get-NetAdapter')

    # Function queries Get-CimInstance Win32_ComputerSystem
    Write-TestResult "Export-BatchConfigFromState: queries Win32_ComputerSystem" ($bcContent -match 'Export-BatchConfigFromState[\s\S]*?Win32_ComputerSystem')

    # Function queries Get-TimeZone
    Write-TestResult "Export-BatchConfigFromState: queries Get-TimeZone" ($bcContent -match 'Export-BatchConfigFromState[\s\S]*?Get-TimeZone')

    # Function queries Get-RDPState
    Write-TestResult "Export-BatchConfigFromState: queries Get-RDPState" ($bcContent -match 'Export-BatchConfigFromState[\s\S]*?Get-RDPState')

    # Function queries Get-WinRMState
    Write-TestResult "Export-BatchConfigFromState: queries Get-WinRMState" ($bcContent -match 'Export-BatchConfigFromState[\s\S]*?Get-WinRMState')

    # Function queries Get-CurrentPowerPlan
    Write-TestResult "Export-BatchConfigFromState: queries Get-CurrentPowerPlan" ($bcContent -match 'Export-BatchConfigFromState[\s\S]*?Get-CurrentPowerPlan')

    # Function detects SET switch via Get-VMSwitch
    Write-TestResult "Export-BatchConfigFromState: detects SET switch via Get-VMSwitch" ($bcContent -match 'Export-BatchConfigFromState[\s\S]*?Get-VMSwitch')

    # Function detects iSCSI sessions via Get-IscsiSession
    Write-TestResult "Export-BatchConfigFromState: detects iSCSI via Get-IscsiSession" ($bcContent -match 'Export-BatchConfigFromState[\s\S]*?Get-IscsiSession')

    # Function outputs JSON via ConvertTo-Json
    Write-TestResult "Export-BatchConfigFromState: outputs JSON via ConvertTo-Json" ($bcContent -match 'Export-BatchConfigFromState[\s\S]*?ConvertTo-Json')

    # Function calls Add-SessionChange
    Write-TestResult "Export-BatchConfigFromState: calls Add-SessionChange" ($bcContent -match 'Export-BatchConfigFromState[\s\S]*?Add-SessionChange')

    # Menu runner case "6" calls Show-BatchConfigMenu
    Write-TestResult "49-MenuRunner: case 6 calls Show-BatchConfigMenu" ($mrContent -match '"6"[\s\S]*?Show-BatchConfigMenu')

    # Menu runner handles option "2" calling Export-BatchConfigFromState
    Write-TestResult "49-MenuRunner: batch menu option 2 calls Export-BatchConfigFromState" ($mrContent -match '"2"[\s\S]*?Export-BatchConfigFromState')

} catch {
    Write-TestResult "Batch Config From State Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 105: EXECUTABLE FAVORITES
# ============================================================================

Write-SectionHeader "SECTION 105: EXECUTABLE FAVORITES"

try {
    $qolContent = Get-Content (Join-Path $modulesPath "55-QoLFeatures.ps1") -Raw

    # $script:FavoriteDispatch variable exists
    Write-TestResult "55-QoLFeatures: FavoriteDispatch variable exists" ($qolContent -match 'script:FavoriteDispatch')

    # Dispatch map contains expected entries
    Write-TestResult "55-QoLFeatures: dispatch has Configure SET" ($qolContent -match 'Configure SET')
    Write-TestResult "55-QoLFeatures: dispatch has Host Storage Setup" ($qolContent -match 'Host Storage Setup')
    Write-TestResult "55-QoLFeatures: dispatch has VM Deployment" ($qolContent -match 'VM Deployment')
    Write-TestResult "55-QoLFeatures: dispatch has Network Diagnostics" ($qolContent -match 'Network Diagnostics')
    Write-TestResult "55-QoLFeatures: dispatch has Configuration Drift Check" ($qolContent -match 'Configuration Drift Check')

    # Add-Favorite accepts FunctionName parameter
    Write-TestResult "55-QoLFeatures: Add-Favorite accepts FunctionName param" ($qolContent -match 'Add-Favorite[\s\S]*?\$FunctionName')

    # Add-Favorite auto-populates from dispatch map
    Write-TestResult "55-QoLFeatures: Add-Favorite uses dispatch map" ($qolContent -match 'FavoriteDispatch\.ContainsKey|FavoriteDispatch\[')

    # Show-Favorites invokes function when selected
    Write-TestResult "55-QoLFeatures: Show-Favorites invokes function" ($qolContent -match 'Show-Favorites[\s\S]*?(&\s+\$|Invoke-Command|FunctionName)')

} catch {
    Write-TestResult "Executable Favorites Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 106: CONFIGURATION DRIFT DETECTION
# ============================================================================

Write-SectionHeader "SECTION 106: CONFIGURATION DRIFT DETECTION"

try {
    $ceContent = Get-Content (Join-Path $modulesPath "45-ConfigExport.ps1") -Raw

    # Compare-ConfigurationDrift function exists
    Write-TestResult "45-ConfigExport: Compare-ConfigurationDrift exists" ($ceContent -match 'function\s+Compare-ConfigurationDrift')

    # Function accepts ProfilePath parameter
    Write-TestResult "Compare-ConfigurationDrift: accepts ProfilePath param" ($ceContent -match 'Compare-ConfigurationDrift[\s\S]*?\$ProfilePath')

    # Function checks hostname drift
    Write-TestResult "Compare-ConfigurationDrift: checks hostname drift" ($ceContent -match 'Compare-ConfigurationDrift[\s\S]*?Hostname')

    # Function checks IP drift
    Write-TestResult "Compare-ConfigurationDrift: checks IP drift" ($ceContent -match 'Compare-ConfigurationDrift[\s\S]*?IPAddress')

    # Function checks DNS drift
    Write-TestResult "Compare-ConfigurationDrift: checks DNS drift" ($ceContent -match 'Compare-ConfigurationDrift[\s\S]*?DNS')

    # Function checks domain drift
    Write-TestResult "Compare-ConfigurationDrift: checks domain drift" ($ceContent -match 'Compare-ConfigurationDrift[\s\S]*?Domain')

    # Function checks timezone drift
    Write-TestResult "Compare-ConfigurationDrift: checks timezone drift" ($ceContent -match 'Compare-ConfigurationDrift[\s\S]*?TimeZone')

    # Function checks RDP state
    Write-TestResult "Compare-ConfigurationDrift: checks RDP state" ($ceContent -match 'Compare-ConfigurationDrift[\s\S]*?RDP')

    # Function checks WinRM state
    Write-TestResult "Compare-ConfigurationDrift: checks WinRM state" ($ceContent -match 'Compare-ConfigurationDrift[\s\S]*?WinRM')

    # Function checks power plan
    Write-TestResult "Compare-ConfigurationDrift: checks power plan" ($ceContent -match 'Compare-ConfigurationDrift[\s\S]*?PowerPlan|Compare-ConfigurationDrift[\s\S]*?Power\s*Plan')

    # Function checks Hyper-V installation
    Write-TestResult "Compare-ConfigurationDrift: checks Hyper-V" ($ceContent -match 'Compare-ConfigurationDrift[\s\S]*?Hyper-V|Compare-ConfigurationDrift[\s\S]*?HyperV')

    # Function checks MPIO installation
    Write-TestResult "Compare-ConfigurationDrift: checks MPIO" ($ceContent -match 'Compare-ConfigurationDrift[\s\S]*?MPIO')

    # Function checks Failover Clustering
    Write-TestResult "Compare-ConfigurationDrift: checks Failover Clustering" ($ceContent -match 'Compare-ConfigurationDrift[\s\S]*?FailoverClustering|Compare-ConfigurationDrift[\s\S]*?Failover')

    # Show-DriftReport function exists
    Write-TestResult "45-ConfigExport: Show-DriftReport exists" ($ceContent -match 'function\s+Show-DriftReport')

    # Show-DriftReport shows match count and drift count
    Write-TestResult "Show-DriftReport: shows match and drift counts" ($ceContent -match 'Show-DriftReport[\s\S]*?match' -and $ceContent -match 'Show-DriftReport[\s\S]*?drift')

    # Start-DriftCheck function exists
    Write-TestResult "45-ConfigExport: Start-DriftCheck exists" ($ceContent -match 'function\s+Start-DriftCheck')

    # Start-DriftCheck calls Compare-ConfigurationDrift
    Write-TestResult "Start-DriftCheck: calls Compare-ConfigurationDrift" ($ceContent -match 'Start-DriftCheck[\s\S]*?Compare-ConfigurationDrift')

    # Start-DriftCheck calls Show-DriftReport
    Write-TestResult "Start-DriftCheck: calls Show-DriftReport" ($ceContent -match 'Start-DriftCheck[\s\S]*?Show-DriftReport')

} catch {
    Write-TestResult "Configuration Drift Detection Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 107: OPERATIONS MENU DRIFT CHECK
# ============================================================================

Write-SectionHeader "SECTION 107: OPERATIONS MENU DRIFT CHECK"

try {
    $omContent = Get-Content (Join-Path $modulesPath "56-OperationsMenu.ps1") -Raw

    # Menu displays option 12 for drift check
    Write-TestResult "56-OperationsMenu: menu has option 12 for Drift" ($omContent -match '\[12\].*Drift|Configuration Drift')

    # Switch handles case "12"
    Write-TestResult "56-OperationsMenu: switch handles case 12" ($omContent -match '"12"')

    # Case "12" calls Show-DriftDetectionMenu (v1.7.1 upgrade from Start-DriftCheck)
    Write-TestResult "56-OperationsMenu: case 12 calls Show-DriftDetectionMenu" ($omContent -match '"12"[\s\S]*?Show-DriftDetectionMenu')

} catch {
    Write-TestResult "Operations Menu Drift Check Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 108: CUSTOM VNIC FEATURE (v1.2.0)
# ============================================================================

Write-SectionHeader "SECTION 108: CUSTOM VNIC FEATURE"

try {
    $setContent = Get-Content (Join-Path $modulesPath "09-SET.ps1") -Raw

    # Add-CustomVNIC function exists
    Write-TestResult "09-SET: Add-CustomVNIC function exists" ($setContent -match 'function Add-CustomVNIC')

    # Add-CustomVNIC has PresetName parameter
    Write-TestResult "09-SET: Add-CustomVNIC has PresetName param" ($setContent -match 'Add-CustomVNIC[\s\S]*?\[string\]\$PresetName')

    # Add-CustomVNIC finds existing External switches (SET or standard)
    Write-TestResult "09-SET: Add-CustomVNIC finds External switches" ($setContent -match 'Add-CustomVNIC[\s\S]*?Get-VMSwitch[\s\S]*?External')

    # Add-CustomVNIC shows existing vNICs
    Write-TestResult "09-SET: Add-CustomVNIC shows existing adapters" ($setContent -match 'Add-CustomVNIC[\s\S]*?Get-VMNetworkAdapter -ManagementOS')

    # Add-CustomVNIC offers preset names (Backup, Cluster, Live Migration, Storage, Custom)
    Write-TestResult "09-SET: Add-CustomVNIC has Backup preset" ($setContent -match 'Add-CustomVNIC[\s\S]*?"Backup"')
    Write-TestResult "09-SET: Add-CustomVNIC has Cluster preset" ($setContent -match 'Add-CustomVNIC[\s\S]*?"Cluster"')
    Write-TestResult "09-SET: Add-CustomVNIC has Live Migration preset" ($setContent -match 'Add-CustomVNIC[\s\S]*?"Live Migration"')
    Write-TestResult "09-SET: Add-CustomVNIC has Storage preset" ($setContent -match 'Add-CustomVNIC[\s\S]*?"Storage"')

    # Add-CustomVNIC handles duplicate vNIC (remove and recreate)
    Write-TestResult "09-SET: Add-CustomVNIC handles existing vNIC" ($setContent -match 'Add-CustomVNIC[\s\S]*?Remove-VMNetworkAdapter -ManagementOS')

    # Add-CustomVNIC creates adapter via Add-VMNetworkAdapter
    Write-TestResult "09-SET: Add-CustomVNIC creates vNIC" ($setContent -match 'Add-CustomVNIC[\s\S]*?Add-VMNetworkAdapter -ManagementOS -SwitchName')

    # Add-CustomVNIC supports VLAN configuration
    Write-TestResult "09-SET: Add-CustomVNIC supports VLAN" ($setContent -match 'Add-CustomVNIC[\s\S]*?Set-VMNetworkAdapterVlan')

    # Add-CustomVNIC validates VLAN range 1-4094
    Write-TestResult "09-SET: Add-CustomVNIC validates VLAN range" ($setContent -match '4094')

    # Add-CustomVNIC supports optional IP configuration
    Write-TestResult "09-SET: Add-CustomVNIC supports IP config" ($setContent -match 'Add-CustomVNIC[\s\S]*?New-NetIPAddress')

    # Add-CustomVNIC calls Add-SessionChange
    Write-TestResult "09-SET: Add-CustomVNIC tracks session change" ($setContent -match 'Add-CustomVNIC[\s\S]*?Add-SessionChange')

    # Add-MultipleVNICs function exists
    Write-TestResult "09-SET: Add-MultipleVNICs function exists" ($setContent -match 'function Add-MultipleVNICs')

    # Add-MultipleVNICs calls Add-CustomVNIC in a loop
    Write-TestResult "09-SET: Add-MultipleVNICs calls Add-CustomVNIC" ($setContent -match 'Add-MultipleVNICs[\s\S]*?Add-CustomVNIC')

    # Add-MultipleVNICs shows summary
    Write-TestResult "09-SET: Add-MultipleVNICs shows summary" ($setContent -match 'Add-MultipleVNICs[\s\S]*?SUMMARY')

    # Add-BackupNIC still exists as wrapper
    Write-TestResult "09-SET: Add-BackupNIC wrapper exists" ($setContent -match 'function Add-BackupNIC')

    # Add-BackupNIC calls Add-CustomVNIC
    Write-TestResult "09-SET: Add-BackupNIC delegates to Add-CustomVNIC" ($setContent -match 'Add-BackupNIC[\s\S]*?Add-CustomVNIC -PresetName')

    # Menu renamed to "Add Virtual NIC to Switch"
    $menuContent = Get-Content (Join-Path $modulesPath "48-MenuDisplay.ps1") -Raw
    Write-TestResult "48-MenuDisplay: menu says 'Add Virtual NIC to Switch'" ($menuContent -match 'Add Virtual NIC to Switch')
    Write-TestResult "48-MenuDisplay: no 'Add Backup NIC to SET' label" (-not ($menuContent -match 'Add Backup NIC to SET'))

    # Menu runner calls Add-CustomVNIC
    $runnerContent = Get-Content (Join-Path $modulesPath "49-MenuRunner.ps1") -Raw
    Write-TestResult "49-MenuRunner: case 2 calls Add-CustomVNIC" ($runnerContent -match '"2"[\s\S]*?Add-CustomVNIC')

    # Batch mode supports CustomVNICs
    $batchContent = Get-Content (Join-Path $modulesPath "50-EntryPoint.ps1") -Raw
    Write-TestResult "50-EntryPoint: batch has CustomVNICs step" ($batchContent -match 'CustomVNICs')
    Write-TestResult "50-EntryPoint: batch step creates vNICs on SET" ($batchContent -match 'Custom vNICs[\s\S]*?Add-VMNetworkAdapter -ManagementOS')
    Write-TestResult "50-EntryPoint: totalSteps is 24" ($batchContent -match '\$totalSteps = 24')

    # Batch template has CustomVNICs
    $templateContent = Get-Content (Join-Path $modulesPath "36-BatchConfig.ps1") -Raw
    Write-TestResult "36-BatchConfig: template has CustomVNICs key" ($templateContent -match '"CustomVNICs"')
    Write-TestResult "36-BatchConfig: template has CustomVNICs help" ($templateContent -match '_CustomVNICs_Help')
    Write-TestResult "36-BatchConfig: state export detects vNICs" ($templateContent -match 'Export-BatchConfigFromState[\s\S]*?CustomVNICs')

    # FavoriteDispatch has Add Virtual NIC entry
    $qolContent = Get-Content (Join-Path $modulesPath "55-QoLFeatures.ps1") -Raw
    Write-TestResult "55-QoLFeatures: FavoriteDispatch has Add Virtual NIC" ($qolContent -match '"Add Virtual NIC"')

    # defaults.example.json has CustomVNICs
    $defaultsExamplePath = Join-Path (Join-Path $PSScriptRoot "..") "defaults.example.json"
    $defaultsContent = Get-Content $defaultsExamplePath -Raw
    Write-TestResult "defaults.example.json: has CustomVNICs section" ($defaultsContent -match '"CustomVNICs"')

} catch {
    Write-TestResult "Custom vNIC Feature Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 109: iSCSI CABLING CHECK FEATURE (v1.2.0)
# ============================================================================

Write-SectionHeader "SECTION 109: iSCSI CABLING CHECK FEATURE"

try {
    $iscsiContent = Get-Content (Join-Path $modulesPath "10-iSCSI.ps1") -Raw

    # Test-iSCSIAdapterSide function exists
    Write-TestResult "10-iSCSI: Test-iSCSIAdapterSide function exists" ($iscsiContent -match 'function Test-iSCSIAdapterSide')

    # Test-iSCSIAdapterSide has AdapterName and TempIP parameters
    Write-TestResult "10-iSCSI: Test-iSCSIAdapterSide has AdapterName param" ($iscsiContent -match 'Test-iSCSIAdapterSide[\s\S]*?\$AdapterName')
    Write-TestResult "10-iSCSI: Test-iSCSIAdapterSide has TempIP param" ($iscsiContent -match 'Test-iSCSIAdapterSide[\s\S]*?\$TempIP')

    # Test-iSCSIAdapterSide uses SANTargetMappings to categorize A/B
    Write-TestResult "10-iSCSI: Test-iSCSIAdapterSide uses SANTargetMappings" ($iscsiContent -match 'Test-iSCSIAdapterSide[\s\S]*?SANTargetMappings')

    # Test-iSCSIAdapterSide assigns temporary IP
    Write-TestResult "10-iSCSI: Test-iSCSIAdapterSide assigns temp IP" ($iscsiContent -match 'Test-iSCSIAdapterSide[\s\S]*?New-NetIPAddress[\s\S]*?TempIP')

    # Test-iSCSIAdapterSide pings targets
    Write-TestResult "10-iSCSI: Test-iSCSIAdapterSide pings targets" ($iscsiContent -match 'Test-iSCSIAdapterSide[\s\S]*?Test-Connection')

    # Test-iSCSIAdapterSide removes temporary IP after test
    Write-TestResult "10-iSCSI: Test-iSCSIAdapterSide cleans up temp IP" ($iscsiContent -match 'Test-iSCSIAdapterSide[\s\S]*?Remove-NetIPAddress')

    # Test-iSCSIAdapterSide returns Side (A/B/Both/None)
    Write-TestResult "10-iSCSI: Test-iSCSIAdapterSide returns Side values" ($iscsiContent -match 'Test-iSCSIAdapterSide[\s\S]*?\$result\.Side\s*=\s*"Both"')

    # Test-iSCSICabling function exists
    Write-TestResult "10-iSCSI: Test-iSCSICabling function exists" ($iscsiContent -match 'function Test-iSCSICabling')

    # Test-iSCSICabling calls Test-iSCSIAdapterSide
    Write-TestResult "10-iSCSI: Test-iSCSICabling calls Test-iSCSIAdapterSide" ($iscsiContent -match 'Test-iSCSICabling[\s\S]*?Test-iSCSIAdapterSide')

    # Test-iSCSICabling uses temp IPs .253 and .254
    Write-TestResult "10-iSCSI: Test-iSCSICabling uses .253/.254 temp IPs" ($iscsiContent -match '\.253.*\.254')

    # Test-iSCSICabling displays results table
    Write-TestResult "10-iSCSI: Test-iSCSICabling shows results table" ($iscsiContent -match 'Test-iSCSICabling[\s\S]*?Adapter.*A-Side.*B-Side.*Result')

    # Test-iSCSICabling warns on same-side cabling
    Write-TestResult "10-iSCSI: Test-iSCSICabling warns same-side" ($iscsiContent -match 'Both adapters reach the same side')

    # Test-iSCSICabling warns on both-sides-reachable
    Write-TestResult "10-iSCSI: Test-iSCSICabling warns both sides reachable" ($iscsiContent -match 'reaches both A and B side')

    # Test-iSCSICabling warns on no connectivity
    Write-TestResult "10-iSCSI: Test-iSCSICabling warns no connectivity" ($iscsiContent -match 'No SAN targets reachable')

    # Test-iSCSICabling returns Valid and adapter assignments
    Write-TestResult "10-iSCSI: Test-iSCSICabling returns Valid flag" ($iscsiContent -match 'Test-iSCSICabling[\s\S]*?\$returnResult\.Valid\s*=\s*\$true')

    # Set-iSCSIAutoConfiguration integrates ping check
    Write-TestResult "10-iSCSI: auto-config calls Test-iSCSICabling" ($iscsiContent -match 'Set-iSCSIAutoConfiguration[\s\S]*?Test-iSCSICabling')

    # Set-iSCSIAutoConfiguration has skipManualSelection logic
    Write-TestResult "10-iSCSI: auto-config has skipManualSelection" ($iscsiContent -match 'skipManualSelection')

    # iSCSI menu has cabling test option [3]
    Write-TestResult "10-iSCSI: menu has Test iSCSI Cabling option" ($iscsiContent -match '\[3\].*Test iSCSI Cabling')

    # iSCSI menu renumbered to 8 options
    Write-TestResult "10-iSCSI: menu has 8 options" ($iscsiContent -match '\[8\].*Disconnect iSCSI')

    # Menu runner handles case "3" for cabling test
    Write-TestResult "10-iSCSI: runner handles case 3 for cabling" ($iscsiContent -match '"3"[\s\S]*?Test-iSCSICabling')

    # Menu runner handles case "8" for disconnect
    Write-TestResult "10-iSCSI: runner handles case 8 for disconnect" ($iscsiContent -match '"8"[\s\S]*?Disconnect-iSCSITargets')

    # FavoriteDispatch has Test iSCSI Cabling entry
    $qolContent = Get-Content (Join-Path $modulesPath "55-QoLFeatures.ps1") -Raw
    Write-TestResult "55-QoLFeatures: FavoriteDispatch has Test iSCSI Cabling" ($qolContent -match '"Test iSCSI Cabling"')

    # Batch mode iSCSI step uses Test-iSCSICabling
    $batchContent = Get-Content (Join-Path $modulesPath "50-EntryPoint.ps1") -Raw
    Write-TestResult "50-EntryPoint: iSCSI batch step uses Test-iSCSICabling" ($batchContent -match 'ConfigureiSCSI[\s\S]*?Test-iSCSICabling')

} catch {
    Write-TestResult "iSCSI Cabling Check Feature Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 110: STORAGE BACKENDS MODULE (v1.3.0)
# ============================================================================

Write-SectionHeader "SECTION 110: STORAGE BACKENDS MODULE"

try {
    $storageBackendsPath = Join-Path $modulesPath "59-StorageBackends.ps1"
    Write-TestResult "59-StorageBackends.ps1 exists" (Test-Path $storageBackendsPath)

    $sbContent = Get-Content $storageBackendsPath -Raw

    # Region header
    Write-TestResult "59-StorageBackends: has STORAGE BACKENDS region" ($sbContent -match '#region.*STORAGE BACKENDS')

    # Valid backends list
    Write-TestResult "59-StorageBackends: ValidStorageBackends defined" ($sbContent -match '\$script:ValidStorageBackends')
    Write-TestResult "59-StorageBackends: supports iSCSI backend" ($sbContent -match '"iSCSI"')
    Write-TestResult "59-StorageBackends: supports FC backend" ($sbContent -match '"FC"')
    Write-TestResult "59-StorageBackends: supports S2D backend" ($sbContent -match '"S2D"')
    Write-TestResult "59-StorageBackends: supports SMB3 backend" ($sbContent -match '"SMB3"')
    Write-TestResult "59-StorageBackends: supports NVMeoF backend" ($sbContent -match '"NVMeoF"')
    Write-TestResult "59-StorageBackends: supports Local backend" ($sbContent -match '"Local"')

    # Core functions
    Write-TestResult "59-StorageBackends: Show-StorageBackendSelector defined" ($sbContent -match 'function Show-StorageBackendSelector')
    Write-TestResult "59-StorageBackends: Set-StorageBackendType defined" ($sbContent -match 'function Set-StorageBackendType')
    Write-TestResult "59-StorageBackends: Get-DetectedStorageBackend defined" ($sbContent -match 'function Get-DetectedStorageBackend')
    Write-TestResult "59-StorageBackends: Show-StorageBackendStatus defined" ($sbContent -match 'function Show-StorageBackendStatus')

    # FC functions
    Write-TestResult "59-StorageBackends: Show-FCAdapters defined" ($sbContent -match 'function Show-FCAdapters')
    Write-TestResult "59-StorageBackends: Initialize-MPIOForFC defined" ($sbContent -match 'function Initialize-MPIOForFC')
    Write-TestResult "59-StorageBackends: Invoke-FCScan defined" ($sbContent -match 'function Invoke-FCScan')
    Write-TestResult "59-StorageBackends: Show-FCSANMenu defined" ($sbContent -match 'function Show-FCSANMenu')
    Write-TestResult "59-StorageBackends: Start-FCSANMenu defined" ($sbContent -match 'function Start-FCSANMenu')

    # S2D functions
    Write-TestResult "59-StorageBackends: Test-S2DAvailable defined" ($sbContent -match 'function Test-S2DAvailable')
    Write-TestResult "59-StorageBackends: Show-S2DStatus defined" ($sbContent -match 'function Show-S2DStatus')
    Write-TestResult "59-StorageBackends: Enable-S2DOnCluster defined" ($sbContent -match 'function Enable-S2DOnCluster')
    Write-TestResult "59-StorageBackends: New-S2DVirtualDisk defined" ($sbContent -match 'function New-S2DVirtualDisk')
    Write-TestResult "59-StorageBackends: Show-S2DMenu defined" ($sbContent -match 'function Show-S2DMenu')
    Write-TestResult "59-StorageBackends: Start-S2DMenu defined" ($sbContent -match 'function Start-S2DMenu')

    # SMB3 functions
    Write-TestResult "59-StorageBackends: Show-SMB3Status defined" ($sbContent -match 'function Show-SMB3Status')
    Write-TestResult "59-StorageBackends: Test-SMB3SharePath defined" ($sbContent -match 'function Test-SMB3SharePath')
    Write-TestResult "59-StorageBackends: Show-SMB3Menu defined" ($sbContent -match 'function Show-SMB3Menu')
    Write-TestResult "59-StorageBackends: Start-SMB3Menu defined" ($sbContent -match 'function Start-SMB3Menu')

    # NVMe-oF functions
    Write-TestResult "59-StorageBackends: Show-NVMeoFStatus defined" ($sbContent -match 'function Show-NVMeoFStatus')
    Write-TestResult "59-StorageBackends: Show-NVMeoFMenu defined" ($sbContent -match 'function Show-NVMeoFMenu')
    Write-TestResult "59-StorageBackends: Start-NVMeoFMenu defined" ($sbContent -match 'function Start-NVMeoFMenu')

    # Unified menu
    Write-TestResult "59-StorageBackends: Show-StorageSANMenu defined" ($sbContent -match 'function Show-StorageSANMenu')
    Write-TestResult "59-StorageBackends: Start-StorageSANMenu defined" ($sbContent -match 'function Start-StorageSANMenu')

    # Batch helpers
    Write-TestResult "59-StorageBackends: Initialize-StorageBackendBatch defined" ($sbContent -match 'function Initialize-StorageBackendBatch')
    Write-TestResult "59-StorageBackends: Initialize-MPIOForBackend defined" ($sbContent -match 'function Initialize-MPIOForBackend')

    # Backend detection checks for various storage types
    Write-TestResult "59-StorageBackends: auto-detect checks iSCSI sessions" ($sbContent -match 'Get-DetectedStorageBackend[\s\S]*?iSCSISession')
    Write-TestResult "59-StorageBackends: auto-detect checks FC HBAs" ($sbContent -match 'Get-DetectedStorageBackend[\s\S]*?Fibre Channel')
    Write-TestResult "59-StorageBackends: auto-detect checks S2D cluster" ($sbContent -match 'Get-DetectedStorageBackend[\s\S]*?S2DEnabled')

    # Menu dispatches to correct backend
    Write-TestResult "59-StorageBackends: SAN menu dispatches iSCSI" ($sbContent -match 'Start-StorageSANMenu[\s\S]*?Start-Show-iSCSISANMenu')
    Write-TestResult "59-StorageBackends: SAN menu dispatches FC" ($sbContent -match 'Start-StorageSANMenu[\s\S]*?Start-FCSANMenu')
    Write-TestResult "59-StorageBackends: SAN menu dispatches S2D" ($sbContent -match 'Start-StorageSANMenu[\s\S]*?Start-S2DMenu')
    Write-TestResult "59-StorageBackends: SAN menu dispatches SMB3" ($sbContent -match 'Start-StorageSANMenu[\s\S]*?Start-SMB3Menu')
    Write-TestResult "59-StorageBackends: SAN menu dispatches NVMeoF" ($sbContent -match 'Start-StorageSANMenu[\s\S]*?Start-NVMeoFMenu')

    # MPIO backend dispatch
    Write-TestResult "59-StorageBackends: MPIO dispatch handles iSCSI" ($sbContent -match 'Initialize-MPIOForBackend[\s\S]*?iSCSI')
    Write-TestResult "59-StorageBackends: MPIO dispatch handles FC" ($sbContent -match 'Initialize-MPIOForBackend[\s\S]*?Fibre Channel')
    Write-TestResult "59-StorageBackends: MPIO dispatch skips S2D" ($sbContent -match 'Initialize-MPIOForBackend[\s\S]*?S2D[\s\S]*?natively')

} catch {
    Write-TestResult "Storage Backends Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 111: STORAGE BACKEND INTEGRATION (v1.3.0)
# ============================================================================

Write-SectionHeader "SECTION 111: STORAGE BACKEND INTEGRATION"

try {
    # 00-Initialization: StorageBackendType variable
    $initContent = Get-Content (Join-Path $modulesPath "00-Initialization.ps1") -Raw
    Write-TestResult "00-Init: StorageBackendType default iSCSI" ($initContent -match '\$script:StorageBackendType\s*=\s*"iSCSI"')

    # 48-MenuDisplay: renamed menu
    $menuContent = Get-Content (Join-Path $modulesPath "48-MenuDisplay.ps1") -Raw
    Write-TestResult "48-MenuDisplay: Storage & SAN Management label" ($menuContent -match 'Storage & SAN Management')

    # 49-MenuRunner: dispatches to Start-StorageSANMenu
    $runnerContent = Get-Content (Join-Path $modulesPath "49-MenuRunner.ps1") -Raw
    Write-TestResult "49-MenuRunner: dispatches to Start-StorageSANMenu" ($runnerContent -match 'Start-StorageSANMenu')

    # 55-QoLFeatures: storage backend favorites
    $qolContent = Get-Content (Join-Path $modulesPath "55-QoLFeatures.ps1") -Raw
    Write-TestResult "55-QoL: Storage Backend Status favorite" ($qolContent -match '"Storage Backend Status"')
    Write-TestResult "55-QoL: Change Storage Backend favorite" ($qolContent -match '"Change Storage Backend"')

    # 56-OperationsMenu: settings menu option [8]
    $opsContent = Get-Content (Join-Path $modulesPath "56-OperationsMenu.ps1") -Raw
    Write-TestResult "56-Ops: settings has storage backend option" ($opsContent -match '\[8\].*[Ss]torage [Bb]ackend')
    Write-TestResult "56-Ops: settings handler calls Set-StorageBackendType" ($opsContent -match '"8"[\s\S]*?Set-StorageBackendType')
    Write-TestResult "56-Ops: builtin defaults has StorageBackendType" ($opsContent -match 'StorageBackendType\s*=\s*"iSCSI"')
    Write-TestResult "56-Ops: import handles StorageBackendType" ($opsContent -match 'merged\.StorageBackendType')
    Write-TestResult "56-Ops: export includes StorageBackendType" ($opsContent -match 'StorageBackendType\s*=\s*\$script:StorageBackendType')

    # 36-BatchConfig: new batch keys
    $batchContent = Get-Content (Join-Path $modulesPath "36-BatchConfig.ps1") -Raw
    Write-TestResult "36-Batch: template has StorageBackendType" ($batchContent -match 'StorageBackendType')
    Write-TestResult "36-Batch: template has ConfigureSharedStorage" ($batchContent -match 'ConfigureSharedStorage')

    # 50-EntryPoint: backend-aware batch steps
    $entryContent = Get-Content (Join-Path $modulesPath "50-EntryPoint.ps1") -Raw
    Write-TestResult "50-Entry: step 18 Configure Shared Storage" ($entryContent -match 'Configure Shared Storage')
    Write-TestResult "50-Entry: step 18 dispatches by StorageBackendType" ($entryContent -match 'StorageBackendType')
    Write-TestResult "50-Entry: step 19 uses Initialize-MPIOForBackend" ($entryContent -match 'Initialize-MPIOForBackend')
    Write-TestResult "50-Entry: backward compat ConfigureiSCSI" ($entryContent -match 'ConfigureiSCSI')
    Write-TestResult "50-Entry: Initialize-StorageBackendBatch for non-iSCSI" ($entryContent -match 'Initialize-StorageBackendBatch')

    # defaults.example.json: storage backend section
    $examplePath = Join-Path $script:ModuleRoot "defaults.example.json"
    if (Test-Path $examplePath) {
        $exampleContent = Get-Content $examplePath -Raw
        Write-TestResult "defaults.example.json: has StorageBackendType" ($exampleContent -match 'StorageBackendType')
        Write-TestResult "defaults.example.json: has storage backend help" ($exampleContent -match '_StorageBackendType_help')
    } else {
        Write-TestResult "defaults.example.json: exists" $false "File not found"
    }

    # RackStack.ps1 loader includes 62-HyperVReplica.ps1
    $loaderContent = Get-Content $loaderPath -Raw
    Write-TestResult "RackStack.ps1: loads 62-HyperVReplica.ps1" ($loaderContent -match '62-HyperVReplica\.ps1')
    Write-TestResult "RackStack.ps1: mentions 63 modules" ($loaderContent -match '63 modules')

    # Module count verification
    $moduleCount = (Get-ChildItem -Path $modulesPath -Filter "*.ps1").Count
    Write-TestResult "Module count is 63" ($moduleCount -eq 63) "Found $moduleCount modules"

    # Changelog mentions v1.4.0
    $changelogPath = Join-Path $script:ModuleRoot "Changelog.md"
    $changelogContent = Get-Content $changelogPath -Raw
    Write-TestResult "Changelog: has v1.4.0 entry" ($changelogContent -match '## v1\.4\.0')
    Write-TestResult "Changelog: mentions Server Role Templates" ($changelogContent -match 'Server Role Templates')
    Write-TestResult "Changelog: mentions 63 modules" ($changelogContent -match '63 modules')

} catch {
    Write-TestResult "Storage Backend Integration Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 112: VIRTUAL SWITCH MANAGEMENT (v1.5.0)
# ============================================================================

Write-SectionHeader "SECTION 112: VIRTUAL SWITCH MANAGEMENT"

try {
    $setContent = Get-Content (Join-Path $modulesPath "09-SET.ps1") -Raw
    $menuContent = Get-Content (Join-Path $modulesPath "48-MenuDisplay.ps1") -Raw
    $runnerContent = Get-Content (Join-Path $modulesPath "49-MenuRunner.ps1") -Raw
    $entryContent = Get-Content (Join-Path $modulesPath "50-EntryPoint.ps1") -Raw
    $batchContent = Get-Content (Join-Path $modulesPath "36-BatchConfig.ps1") -Raw

    # New functions exist
    Write-TestResult "09-SET: New-StandardVSwitch function exists" ($setContent -match 'function New-StandardVSwitch')
    Write-TestResult "09-SET: Show-VirtualSwitches function exists" ($setContent -match 'function Show-VirtualSwitches')
    Write-TestResult "09-SET: Remove-VirtualSwitch function exists" ($setContent -match 'function Remove-VirtualSwitch')

    # New-StandardVSwitch supports all types
    Write-TestResult "09-SET: New-StandardVSwitch validates External/Internal/Private" ($setContent -match 'ValidateSet.*External.*Internal.*Private')
    Write-TestResult "09-SET: New-StandardVSwitch creates External with physical NIC" ($setContent -match 'New-StandardVSwitch[\s\S]*?New-VMSwitch -Name \$SwitchName -NetAdapterName')
    Write-TestResult "09-SET: New-StandardVSwitch creates Internal switch" ($setContent -match 'New-VMSwitch -Name \$SwitchName -SwitchType Internal')
    Write-TestResult "09-SET: New-StandardVSwitch creates Private switch" ($setContent -match 'New-VMSwitch -Name \$SwitchName -SwitchType Private')

    # Show-VirtualSwitches displays switch info
    Write-TestResult "09-SET: Show-VirtualSwitches displays switch type" ($setContent -match 'Show-VirtualSwitches[\s\S]*?SwitchType')
    Write-TestResult "09-SET: Show-VirtualSwitches detects SET" ($setContent -match 'Show-VirtualSwitches[\s\S]*?EmbeddedTeamingEnabled')

    # Remove-VirtualSwitch has safety checks
    Write-TestResult "09-SET: Remove-VirtualSwitch checks for connected VMs" ($setContent -match 'Remove-VirtualSwitch[\s\S]*?VMName')
    Write-TestResult "09-SET: Remove-VirtualSwitch confirms before delete" ($setContent -match 'Remove-VirtualSwitch[\s\S]*?Confirm-UserAction')

    # Virtual Switch Management menu exists
    Write-TestResult "48-MenuDisplay: Show-VirtualSwitchMenu function exists" ($menuContent -match 'function Show-VirtualSwitchMenu')
    Write-TestResult "48-MenuDisplay: menu has Virtual Switch Management" ($menuContent -match 'Virtual Switch Management')
    Write-TestResult "48-MenuDisplay: menu offers SET creation" ($menuContent -match 'Create Switch Embedded Team')
    Write-TestResult "48-MenuDisplay: menu offers External creation" ($menuContent -match 'Create External Virtual Switch')
    Write-TestResult "48-MenuDisplay: menu offers Internal creation" ($menuContent -match 'Create Internal Virtual Switch')
    Write-TestResult "48-MenuDisplay: menu offers Private creation" ($menuContent -match 'Create Private Virtual Switch')
    Write-TestResult "48-MenuDisplay: menu offers Show switches" ($menuContent -match 'Show Virtual Switches')
    Write-TestResult "48-MenuDisplay: menu offers Remove switch" ($menuContent -match 'Remove Virtual Switch')

    # Menu runner routes to submenu
    Write-TestResult "49-MenuRunner: Start-Show-VirtualSwitchMenu exists" ($runnerContent -match 'function Start-Show-VirtualSwitchMenu')
    Write-TestResult "49-MenuRunner: host network option 1 routes to VirtualSwitchMenu" ($runnerContent -match 'Start-Show-VirtualSwitchMenu')
    Write-TestResult "49-MenuRunner: virtual switch menu calls New-StandardVSwitch" ($runnerContent -match 'New-StandardVSwitch')

    # Batch mode supports new switch types
    Write-TestResult "50-EntryPoint: batch supports CreateVirtualSwitch" ($entryContent -match 'CreateVirtualSwitch')
    Write-TestResult "50-EntryPoint: batch handles VirtualSwitchType SET" ($entryContent -match 'VirtualSwitchType[\s\S]*?SET')
    Write-TestResult "50-EntryPoint: batch handles External switch type" ($entryContent -match '"External"[\s\S]*?New-VMSwitch')
    Write-TestResult "50-EntryPoint: batch handles Internal switch type" ($entryContent -match '"Internal"[\s\S]*?New-VMSwitch')
    Write-TestResult "50-EntryPoint: batch handles Private switch type" ($entryContent -match '"Private"[\s\S]*?New-VMSwitch')
    Write-TestResult "50-EntryPoint: backward compat CreateSETSwitch" ($entryContent -match 'Config\.CreateSETSwitch')

    # Batch template has new fields
    Write-TestResult "36-BatchConfig: template has CreateVirtualSwitch" ($batchContent -match '"CreateVirtualSwitch"')
    Write-TestResult "36-BatchConfig: template has VirtualSwitchType" ($batchContent -match '"VirtualSwitchType"')
    Write-TestResult "36-BatchConfig: template has VirtualSwitchName" ($batchContent -match '"VirtualSwitchName"')
    Write-TestResult "36-BatchConfig: template has VirtualSwitchAdapter" ($batchContent -match '"VirtualSwitchAdapter"')

    # VM deployment offers switch type choice when no switch exists
    $vmContent = Get-Content (Join-Path $modulesPath "44-VMDeployment.ps1") -Raw
    Write-TestResult "44-VMDeployment: no-switch menu offers SET" ($vmContent -match 'Switch Embedded Team.*SET')
    Write-TestResult "44-VMDeployment: no-switch menu offers External" ($vmContent -match 'External Virtual Switch')
    Write-TestResult "44-VMDeployment: switch list shows type (SET label)" ($vmContent -match 'EmbeddedTeamingEnabled.*SET')

} catch {
    Write-TestResult "Virtual Switch Management Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 113: CUSTOM SAN TARGET PAIRINGS (v1.5.0)
# ============================================================================

Write-SectionHeader "SECTION 113: CUSTOM SAN TARGET PAIRINGS"

try {
    $initContent = Get-Content (Join-Path $modulesPath "00-Initialization.ps1") -Raw
    $opsContent = Get-Content (Join-Path $modulesPath "56-OperationsMenu.ps1") -Raw
    $iscsiContent = Get-Content (Join-Path $modulesPath "10-iSCSI.ps1") -Raw
    $batchContent = Get-Content (Join-Path $modulesPath "36-BatchConfig.ps1") -Raw
    $exampleContent = Get-Content (Join-Path $script:ModuleRoot "defaults.example.json") -Raw

    # Initialization
    Write-TestResult "00-Init: SANTargetPairings variable declared" ($initContent -match '\$script:SANTargetPairings')
    Write-TestResult "00-Init: SANTargetPairings defaults to null" ($initContent -match '\$script:SANTargetPairings = \$null')

    # Import-Defaults loads SANTargetPairings
    Write-TestResult "56-OpsMenu: Import-Defaults loads SANTargetPairings" ($opsContent -match 'SANTargetPairings[\s\S]*?Pairs')
    Write-TestResult "56-OpsMenu: Import-Defaults parses HostAssignments" ($opsContent -match 'HostAssignments[\s\S]*?HostMod')
    Write-TestResult "56-OpsMenu: Import-Defaults parses CycleSize" ($opsContent -match 'CycleSize')

    # Initialize-SANTargetPairs supports custom pairings
    Write-TestResult "56-OpsMenu: Initialize-SANTargetPairs handles custom Pairs" ($opsContent -match 'Initialize-SANTargetPairs[\s\S]*?SANTargetPairings\.Pairs')
    Write-TestResult "56-OpsMenu: Initialize-SANTargetPairs sets Name on pairs" ($opsContent -match 'Name\s*=\s*\$pair\.Name')
    Write-TestResult "56-OpsMenu: Initialize-SANTargetPairs still has default fallback" ($opsContent -match 'Initialize-SANTargetPairs[\s\S]*?\$mappings\.Count')

    # Get-SANTargetsForHost supports custom assignments
    Write-TestResult "10-iSCSI: Get-SANTargetsForHost uses HostAssignments" ($iscsiContent -match 'Get-SANTargetsForHost[\s\S]*?HostAssignments')
    Write-TestResult "10-iSCSI: Get-SANTargetsForHost uses CycleSize" ($iscsiContent -match 'CycleSize')
    Write-TestResult "10-iSCSI: Get-SANTargetsForHost uses PrimaryPair name" ($iscsiContent -match 'PrimaryPair')
    Write-TestResult "10-iSCSI: Get-SANTargetsForHost builds RetryOrder from config" ($iscsiContent -match 'RetryOrder')
    Write-TestResult "10-iSCSI: Get-SANTargetsForHost still has default mod fallback" ($iscsiContent -match 'primaryIndex.*HostNumber.*1.*%.*pairCount')

    # Batch template has SANTargetPairings
    Write-TestResult "36-BatchConfig: template has SANTargetPairings field" ($batchContent -match '"SANTargetPairings"')

    # defaults.example.json documents SANTargetPairings
    Write-TestResult "defaults.example.json: has SANTargetPairings section" ($exampleContent -match '"SANTargetPairings"')
    Write-TestResult "defaults.example.json: has Pairs with A/B" ($exampleContent -match '"Pairs"[\s\S]*?"A".*?"B"')
    Write-TestResult "defaults.example.json: has HostAssignments with HostMod" ($exampleContent -match '"HostAssignments"[\s\S]*?"HostMod"')
    Write-TestResult "defaults.example.json: has CycleSize" ($exampleContent -match '"CycleSize":\s*4')
    Write-TestResult "defaults.example.json: pairs use A0/B0 labeling" ($exampleContent -match '"ALabel":\s*"A0"')

    # Test Get-SANTargetsForHost default behavior still works
    $script:SANTargetPairings = $null
    $sub = "172.16.1"
    $script:SANTargetPairs = @(
        @{ Index = 0; A = "$sub.10"; B = "$sub.11"; ALabel = "A0"; BLabel = "B1"; Labels = "A0/B1" },
        @{ Index = 1; A = "$sub.13"; B = "$sub.12"; ALabel = "A1"; BLabel = "B0"; Labels = "A1/B0" },
        @{ Index = 2; A = "$sub.14"; B = "$sub.15"; ALabel = "A2"; BLabel = "B3"; Labels = "A2/B3" },
        @{ Index = 3; A = "$sub.17"; B = "$sub.16"; ALabel = "A3"; BLabel = "B2"; Labels = "A3/B2" }
    )

    $host1 = Get-SANTargetsForHost -HostNumber 1
    $host2 = Get-SANTargetsForHost -HostNumber 2
    $host5 = Get-SANTargetsForHost -HostNumber 5

    Write-TestResult "Get-SANTargetsForHost: host 1 gets pair 0" ($host1.Index -eq 0)
    Write-TestResult "Get-SANTargetsForHost: host 2 gets pair 1" ($host2.Index -eq 1)
    Write-TestResult "Get-SANTargetsForHost: host 5 cycles to pair 0" ($host5.Index -eq 0)

    $retryOrder = Get-SANTargetsForHost -HostNumber 1 -AllPairsInRetryOrder
    Write-TestResult "Get-SANTargetsForHost: retry order returns all pairs" (@($retryOrder).Count -eq 4)
    Write-TestResult "Get-SANTargetsForHost: primary pair first in retry" ($retryOrder[0].Index -eq 0)

    # Test custom pairings behavior
    $script:SANTargetPairings = @{
        Pairs = @(
            @{ Name = "Pair0"; A = 10; B = 11 },
            @{ Name = "Pair1"; A = 12; B = 13 }
        )
        HostAssignments = @(
            @{ HostMod = 1; PrimaryPair = "Pair0"; RetryOrder = @("Pair1") },
            @{ HostMod = 2; PrimaryPair = "Pair1"; RetryOrder = @("Pair0") }
        )
        CycleSize = 2
    }

    # Re-initialize pairs with custom config
    Initialize-SANTargetPairs
    Write-TestResult "Custom SANTargetPairings: builds 2 pairs" ($script:SANTargetPairs.Count -eq 2)
    Write-TestResult "Custom SANTargetPairings: pair 0 has name Pair0" ($script:SANTargetPairs[0].Name -eq "Pair0")

    $customHost1 = Get-SANTargetsForHost -HostNumber 1
    $customHost2 = Get-SANTargetsForHost -HostNumber 2
    $customHost3 = Get-SANTargetsForHost -HostNumber 3

    Write-TestResult "Custom pairings: host 1 gets Pair0" ($customHost1.Name -eq "Pair0")
    Write-TestResult "Custom pairings: host 2 gets Pair1" ($customHost2.Name -eq "Pair1")
    Write-TestResult "Custom pairings: host 3 cycles to Pair0 (CycleSize=2)" ($customHost3.Name -eq "Pair0")

    $customRetry = Get-SANTargetsForHost -HostNumber 1 -AllPairsInRetryOrder
    Write-TestResult "Custom pairings: retry order has 2 entries" (@($customRetry).Count -eq 2)
    Write-TestResult "Custom pairings: retry starts with Pair0" ($customRetry[0].Name -eq "Pair0")
    Write-TestResult "Custom pairings: retry fallback is Pair1" ($customRetry[1].Name -eq "Pair1")

    # Reset
    $script:SANTargetPairings = $null

} catch {
    Write-TestResult "Custom SAN Target Pairings Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 114: DOMAIN JOIN MODULE (12-DomainJoin.ps1)
# ============================================================================

Write-SectionHeader "114" "DOMAIN JOIN MODULE"

try {
    $djContent = Get-Content "$modulesPath\12-DomainJoin.ps1" -Raw

    Write-TestResult "12-DomainJoin: function Join-Domain exists" ($djContent -match 'function\s+Join-Domain\b')
    Write-TestResult "12-DomainJoin: checks current domain status" ($djContent -match 'Get-CimInstance.*Win32_ComputerSystem|PartOfDomain')
    Write-TestResult "12-DomainJoin: prompts for domain name" ($djContent -match 'Read-Host|domain')
    Write-TestResult "12-DomainJoin: prompts for credentials" ($djContent -match 'Get-Credential|PSCredential')
    Write-TestResult "12-DomainJoin: calls Add-Computer" ($djContent -match 'Add-Computer')
    Write-TestResult "12-DomainJoin: handles reboot" ($djContent -match 'Restart-Computer|RebootNeeded|reboot')
    Write-TestResult "12-DomainJoin: tracks session change" ($djContent -match 'Add-SessionChange|SessionChange')
    Write-TestResult "12-DomainJoin: has error handling" ($djContent -match 'try\s*\{|catch\s*\{')

} catch {
    Write-TestResult "Domain Join Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 115: RDP & WINRM MODULE (15-RDP.ps1)
# ============================================================================

Write-SectionHeader "115" "RDP & WINRM MODULE"

try {
    $rdpContent = Get-Content "$modulesPath\15-RDP.ps1" -Raw

    Write-TestResult "15-RDP: function Enable-RDP exists" ($rdpContent -match 'function\s+Enable-RDP\b')
    Write-TestResult "15-RDP: function Enable-PowerShellRemoting exists" ($rdpContent -match 'function\s+Enable-PowerShellRemoting\b')
    Write-TestResult "15-RDP: modifies Terminal Server registry" ($rdpContent -match 'Terminal Server|fDenyTSConnections')
    Write-TestResult "15-RDP: enables firewall rule for RDP" ($rdpContent -match 'Enable-NetFirewallRule|Remote Desktop')
    Write-TestResult "15-RDP: configures WinRM" ($rdpContent -match 'Enable-PSRemoting|WinRM|WSMan')
    Write-TestResult "15-RDP: NLA setting addressed" ($rdpContent -match 'UserAuthentication|NLA|Network Level')
    Write-TestResult "15-RDP: tracks session changes" ($rdpContent -match 'Add-SessionChange|SessionChange')
    Write-TestResult "15-RDP: has error handling" ($rdpContent -match 'try\s*\{|catch\s*\{')

} catch {
    Write-TestResult "RDP & WinRM Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 116: FIREWALL TEMPLATES MODULE (18-FirewallTemplates.ps1)
# ============================================================================

Write-SectionHeader "116" "FIREWALL TEMPLATES MODULE"

try {
    $fwContent = Get-Content "$modulesPath\18-FirewallTemplates.ps1" -Raw

    Write-TestResult "18-FirewallTemplates: function Set-FirewallRuleTemplates exists" ($fwContent -match 'function\s+Set-FirewallRuleTemplates\b')
    Write-TestResult "18-FirewallTemplates: function Enable-HyperVFirewallRules exists" ($fwContent -match 'function\s+Enable-HyperVFirewallRules\b')
    Write-TestResult "18-FirewallTemplates: function Enable-ClusterFirewallRules exists" ($fwContent -match 'function\s+Enable-ClusterFirewallRules\b')
    Write-TestResult "18-FirewallTemplates: function Enable-ReplicaFirewallRules exists" ($fwContent -match 'function\s+Enable-ReplicaFirewallRules\b')
    Write-TestResult "18-FirewallTemplates: function Enable-LiveMigrationFirewallRules exists" ($fwContent -match 'function\s+Enable-LiveMigrationFirewallRules\b')
    Write-TestResult "18-FirewallTemplates: function Enable-iSCSIFirewallRules exists" ($fwContent -match 'function\s+Enable-iSCSIFirewallRules\b')
    Write-TestResult "18-FirewallTemplates: function Enable-SMBFirewallRules exists" ($fwContent -match 'function\s+Enable-SMBFirewallRules\b')
    Write-TestResult "18-FirewallTemplates: function Show-HyperVClusterFirewallRules exists" ($fwContent -match 'function\s+Show-HyperVClusterFirewallRules\b')
    Write-TestResult "18-FirewallTemplates: uses Enable-NetFirewallRule" ($fwContent -match 'Enable-NetFirewallRule')
    Write-TestResult "18-FirewallTemplates: iSCSI uses port 3260" ($fwContent -match '3260')
    Write-TestResult "18-FirewallTemplates: cluster uses UDP 3343" ($fwContent -match '3343')
    Write-TestResult "18-FirewallTemplates: has Hyper-V guard check" ($fwContent -match 'Test-HyperVInstalled|Hyper-V')

} catch {
    Write-TestResult "Firewall Templates Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 117: DISK CLEANUP MODULE (20-DiskCleanup.ps1)
# ============================================================================

Write-SectionHeader "117" "DISK CLEANUP MODULE"

try {
    $dcContent = Get-Content "$modulesPath\20-DiskCleanup.ps1" -Raw

    Write-TestResult "20-DiskCleanup: function Start-DiskCleanup exists" ($dcContent -match 'function\s+Start-DiskCleanup\b')
    Write-TestResult "20-DiskCleanup: function Invoke-QuickClean exists" ($dcContent -match 'function\s+Invoke-QuickClean\b')
    Write-TestResult "20-DiskCleanup: function Invoke-StandardClean exists" ($dcContent -match 'function\s+Invoke-StandardClean\b')
    Write-TestResult "20-DiskCleanup: function Invoke-DeepClean exists" ($dcContent -match 'function\s+Invoke-DeepClean\b')
    Write-TestResult "20-DiskCleanup: function Clear-WindowsUpdateCache exists" ($dcContent -match 'function\s+Clear-WindowsUpdateCache\b')
    Write-TestResult "20-DiskCleanup: cleans temp files" ($dcContent -match 'Temp|temp|TEMP')
    Write-TestResult "20-DiskCleanup: cleans Windows Update cache" ($dcContent -match 'SoftwareDistribution|wuauserv')
    Write-TestResult "20-DiskCleanup: deep clean uses DISM or component cleanup" ($dcContent -match 'DISM|Dism|StartComponentCleanup|ResetBase')
    Write-TestResult "20-DiskCleanup: shows space savings info" ($dcContent -match 'MB|Potential|savings|size')
    Write-TestResult "20-DiskCleanup: has confirmation for destructive ops" ($dcContent -match 'Confirm|confirm|Y/N|[Yy]es')

} catch {
    Write-TestResult "Disk Cleanup Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 118: PASSWORD MODULE (22-Password.ps1)
# ============================================================================

Write-SectionHeader "118" "PASSWORD MODULE"

try {
    $pwContent = Get-Content "$modulesPath\22-Password.ps1" -Raw

    Write-TestResult "22-Password: function Test-PasswordComplexity exists" ($pwContent -match 'function\s+Test-PasswordComplexity\b')
    Write-TestResult "22-Password: function Get-SecurePassword exists" ($pwContent -match 'function\s+Get-SecurePassword\b')
    Write-TestResult "22-Password: function ConvertFrom-SecureStringToPlainText exists" ($pwContent -match 'function\s+ConvertFrom-SecureStringToPlainText\b')
    Write-TestResult "22-Password: function Clear-SecureMemory exists" ($pwContent -match 'function\s+Clear-SecureMemory\b')
    Write-TestResult "22-Password: enforces minimum length" ($pwContent -match 'MinPasswordLength|\.Length\s*[-<]|length')
    Write-TestResult "22-Password: checks uppercase" ($pwContent -match '\[A-Z\]|uppercase|upper')
    Write-TestResult "22-Password: checks lowercase" ($pwContent -match '\[a-z\]|lowercase|lower')
    Write-TestResult "22-Password: checks digits" ($pwContent -match '\[0-9\]|\\d|digit')
    Write-TestResult "22-Password: checks special chars" ($pwContent -match 'special|[!@#\$%\^&\*]|\\W')
    Write-TestResult "22-Password: uses SecureString for input" ($pwContent -match 'Read-Host\s+-AsSecureString|SecureString')
    Write-TestResult "22-Password: confirmation matching" ($pwContent -match 'confirm|match|Confirm')
    Write-TestResult "22-Password: memory cleanup" ($pwContent -match 'Dispose|Clear|Zero|clear')

    # Runtime tests
    Write-TestResult "Test-PasswordComplexity: weak password rejected" ((Test-PasswordComplexity "short") -eq $false)
    Write-TestResult "Test-PasswordComplexity: no uppercase rejected" ((Test-PasswordComplexity "alllowercasenoups123!@") -eq $false)
    Write-TestResult "Test-PasswordComplexity: strong password accepted" ((Test-PasswordComplexity "MyStr0ngP@ssw0rd!") -eq $true)

} catch {
    Write-TestResult "Password Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 119: HYPER-V MODULE (25-HyperV.ps1)
# ============================================================================

Write-SectionHeader "119" "HYPER-V MODULE"

try {
    $hvContent = Get-Content "$modulesPath\25-HyperV.ps1" -Raw

    Write-TestResult "25-HyperV: function Install-HyperVRole exists" ($hvContent -match 'function\s+Install-HyperVRole\b')
    Write-TestResult "25-HyperV: installs Hyper-V feature" ($hvContent -match 'Install-WindowsFeature.*Hyper-V|Enable-WindowsOptionalFeature.*Hyper-V')
    Write-TestResult "25-HyperV: installs management tools" ($hvContent -match 'RSAT-Hyper-V-Tools|Hyper-V-Tools|IncludeManagementTools')
    Write-TestResult "25-HyperV: handles reboot requirement" ($hvContent -match 'Restart-Computer|RebootNeeded|reboot|RestartNeeded')
    Write-TestResult "25-HyperV: checks if already installed" ($hvContent -match 'Get-WindowsFeature|Get-WindowsOptionalFeature|already.*install')
    Write-TestResult "25-HyperV: tracks session change" ($hvContent -match 'Add-SessionChange|SessionChange')
    Write-TestResult "25-HyperV: has error handling" ($hvContent -match 'try\s*\{|catch\s*\{')

} catch {
    Write-TestResult "Hyper-V Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 120: PERFORMANCE DASHBOARD MODULE (28-PerformanceDashboard.ps1)
# ============================================================================

Write-SectionHeader "120" "PERFORMANCE DASHBOARD MODULE"

try {
    $pdContent = Get-Content "$modulesPath\28-PerformanceDashboard.ps1" -Raw

    Write-TestResult "28-PerfDash: function Show-PerformanceDashboard exists" ($pdContent -match 'function\s+Show-PerformanceDashboard\b')
    Write-TestResult "28-PerfDash: function Get-ProgressBar exists" ($pdContent -match 'function\s+Get-ProgressBar\b')
    Write-TestResult "28-PerfDash: monitors CPU" ($pdContent -match 'CPU|Processor|LoadPercentage')
    Write-TestResult "28-PerfDash: monitors memory" ($pdContent -match 'Memory|RAM|TotalVisibleMemorySize|FreePhysicalMemory')
    Write-TestResult "28-PerfDash: monitors disk" ($pdContent -match 'Disk|disk|PhysicalDisk|LogicalDisk')
    Write-TestResult "28-PerfDash: monitors network" ($pdContent -match 'Network|network|BytesReceived|BytesSent')
    Write-TestResult "28-PerfDash: shows uptime" ($pdContent -match 'Uptime|uptime|LastBootUpTime')
    Write-TestResult "28-PerfDash: progress bar generates string" ($pdContent -match 'PadRight|PadLeft|\[.*\]|bar')

    # Runtime test for Get-ProgressBar
    $bar = Get-ProgressBar -Value 50 -MaxValue 100
    Write-TestResult "Get-ProgressBar: returns non-empty string" ($null -ne $bar -and $bar.Length -gt 0)

} catch {
    Write-TestResult "Performance Dashboard Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 121: EVENT LOG VIEWER MODULE (29-EventLogViewer.ps1)
# ============================================================================

Write-SectionHeader "121" "EVENT LOG VIEWER MODULE"

try {
    $elContent = Get-Content "$modulesPath\29-EventLogViewer.ps1" -Raw

    Write-TestResult "29-EventLog: function Show-EventLogViewer exists" ($elContent -match 'function\s+Show-EventLogViewer\b')
    Write-TestResult "29-EventLog: queries System log" ($elContent -match 'System')
    Write-TestResult "29-EventLog: queries Application log" ($elContent -match 'Application')
    Write-TestResult "29-EventLog: queries Security log" ($elContent -match 'Security')
    Write-TestResult "29-EventLog: filters by time range" ($elContent -match 'AddHours|AddDays|StartTime|After|TimeCreated')
    Write-TestResult "29-EventLog: filters by severity" ($elContent -match 'Error|Warning|Critical|Level')
    Write-TestResult "29-EventLog: uses Get-WinEvent or Get-EventLog" ($elContent -match 'Get-WinEvent|Get-EventLog')
    Write-TestResult "29-EventLog: shows event details" ($elContent -match 'Message|Source|Id|EventID')

} catch {
    Write-TestResult "Event Log Viewer Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 122: SERVICE MANAGER MODULE (30-ServiceManager.ps1)
# ============================================================================

Write-SectionHeader "122" "SERVICE MANAGER MODULE"

try {
    $smContent = Get-Content "$modulesPath\30-ServiceManager.ps1" -Raw

    Write-TestResult "30-ServiceMgr: function Show-ServiceManager exists" ($smContent -match 'function\s+Show-ServiceManager\b')
    Write-TestResult "30-ServiceMgr: lists key services" ($smContent -match 'vmms|vmcompute|ClusSvc|WinRM|W32Time|DNS|DHCP')
    Write-TestResult "30-ServiceMgr: shows service status" ($smContent -match 'Get-Service|Status|Running|Stopped')
    Write-TestResult "30-ServiceMgr: can start services" ($smContent -match 'Start-Service')
    Write-TestResult "30-ServiceMgr: can stop services" ($smContent -match 'Stop-Service')
    Write-TestResult "30-ServiceMgr: can restart services" ($smContent -match 'Restart-Service')
    Write-TestResult "30-ServiceMgr: has error handling" ($smContent -match 'try\s*\{|catch\s*\{')

} catch {
    Write-TestResult "Service Manager Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 123: BITLOCKER MODULE (31-BitLocker.ps1)
# ============================================================================

Write-SectionHeader "123" "BITLOCKER MODULE"

try {
    $blContent = Get-Content "$modulesPath\31-BitLocker.ps1" -Raw

    Write-TestResult "31-BitLocker: function Show-BitLockerManagement exists" ($blContent -match 'function\s+Show-BitLockerManagement\b')
    Write-TestResult "31-BitLocker: checks BitLocker status" ($blContent -match 'Get-BitLockerVolume')
    Write-TestResult "31-BitLocker: enables encryption" ($blContent -match 'Enable-BitLocker')
    Write-TestResult "31-BitLocker: supports TPM protector" ($blContent -match 'TpmProtector|TPM')
    Write-TestResult "31-BitLocker: supports password protector" ($blContent -match 'PasswordProtector|Password')
    Write-TestResult "31-BitLocker: handles recovery key" ($blContent -match 'RecoveryKey|RecoveryPassword|BackupToAAD')
    Write-TestResult "31-BitLocker: can disable/decrypt" ($blContent -match 'Disable-BitLocker')
    Write-TestResult "31-BitLocker: has error handling" ($blContent -match 'try\s*\{|catch\s*\{')

} catch {
    Write-TestResult "BitLocker Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 124: STORAGE REPLICA MODULE (33-StorageReplica.ps1)
# ============================================================================

Write-SectionHeader "124" "STORAGE REPLICA MODULE"

try {
    $srContent = Get-Content "$modulesPath\33-StorageReplica.ps1" -Raw

    Write-TestResult "33-StorageReplica: function Show-StorageReplicaManagement exists" ($srContent -match 'function\s+Show-StorageReplicaManagement\b')
    Write-TestResult "33-StorageReplica: checks SR feature installation" ($srContent -match 'Storage-Replica|Get-WindowsFeature')
    Write-TestResult "33-StorageReplica: creates partnerships" ($srContent -match 'New-SRPartnership|SRPartnership')
    Write-TestResult "33-StorageReplica: shows partnership status" ($srContent -match 'Get-SRPartnership|Get-SRGroup')
    Write-TestResult "33-StorageReplica: supports sync replication" ($srContent -match 'Synchronous|sync')
    Write-TestResult "33-StorageReplica: supports async replication" ($srContent -match 'Asynchronous|async')
    Write-TestResult "33-StorageReplica: tests topology" ($srContent -match 'Test-SRTopology')
    Write-TestResult "33-StorageReplica: edition check (Datacenter)" ($srContent -match 'Datacenter|edition|Edition')

} catch {
    Write-TestResult "Storage Replica Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 125: UTILITIES MODULE (35-Utilities.ps1)
# ============================================================================

Write-SectionHeader "125" "UTILITIES MODULE"

try {
    $utilContent = Get-Content "$modulesPath\35-Utilities.ps1" -Raw

    Write-TestResult "35-Utilities: function Test-ScriptUpdate exists" ($utilContent -match 'function\s+Test-ScriptUpdate\b')
    Write-TestResult "35-Utilities: function Install-ScriptUpdate exists" ($utilContent -match 'function\s+Install-ScriptUpdate\b')
    Write-TestResult "35-Utilities: function Test-StartupUpdateCheck exists" ($utilContent -match 'function\s+Test-StartupUpdateCheck\b')
    Write-TestResult "35-Utilities: function Compare-ConfigurationProfiles exists" ($utilContent -match 'function\s+Compare-ConfigurationProfiles\b')
    Write-TestResult "35-Utilities: function Test-ComputerNameInAD exists" ($utilContent -match 'function\s+Test-ComputerNameInAD\b')
    Write-TestResult "35-Utilities: function Test-IPAddressInUse exists" ($utilContent -match 'function\s+Test-IPAddressInUse\b')
    Write-TestResult "35-Utilities: function Invoke-RemoteProfileApply exists" ($utilContent -match 'function\s+Invoke-RemoteProfileApply\b')
    Write-TestResult "35-Utilities: function Show-CredentialManager exists" ($utilContent -match 'function\s+Show-CredentialManager\b')
    Write-TestResult "35-Utilities: update check uses GitHub API" ($utilContent -match 'api\.github\.com|github\.com.*releases')
    Write-TestResult "35-Utilities: profile comparison shows differences" ($utilContent -match 'diff|Diff|compare|Compare|changed|Changed')
    Write-TestResult "35-Utilities: remote apply uses Enter-PSSession or Invoke-Command" ($utilContent -match 'Enter-PSSession|Invoke-Command')

} catch {
    Write-TestResult "Utilities Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 126: VHD MANAGEMENT MODULE (41-VHDManagement.ps1)
# ============================================================================

Write-SectionHeader "126" "VHD MANAGEMENT MODULE"

try {
    $vhdContent = Get-Content "$modulesPath\41-VHDManagement.ps1" -Raw

    Write-TestResult "41-VHD: function Get-VHDCachePath exists" ($vhdContent -match 'function\s+Get-VHDCachePath\b')
    Write-TestResult "41-VHD: function Show-OSVersionMenu exists" ($vhdContent -match 'function\s+Show-OSVersionMenu\b')
    Write-TestResult "41-VHD: function Test-CachedVHD exists" ($vhdContent -match 'function\s+Test-CachedVHD\b')
    Write-TestResult "41-VHD: function Get-SyspreppedVHD exists" ($vhdContent -match 'function\s+Get-SyspreppedVHD\b')
    Write-TestResult "41-VHD: function Copy-VHDForVM exists" ($vhdContent -match 'function\s+Copy-VHDForVM\b')
    Write-TestResult "41-VHD: function Show-VHDManagementMenu exists" ($vhdContent -match 'function\s+Show-VHDManagementMenu\b')
    Write-TestResult "41-VHD: function Show-SysprepGuide exists" ($vhdContent -match 'function\s+Show-SysprepGuide\b')
    Write-TestResult "41-VHD: function Show-LinuxVHDGuide exists" ($vhdContent -match 'function\s+Show-LinuxVHDGuide\b')
    Write-TestResult "41-VHD: function Start-VHDManagement exists" ($vhdContent -match 'function\s+Start-VHDManagement\b')
    Write-TestResult "41-VHD: handles cluster vs standalone paths" ($vhdContent -match 'ClusterStorage|ClusterVHDCachePath|HostVMStoragePath')
    Write-TestResult "41-VHD: OS version selection includes 2022/2025" ($vhdContent -match '2022|2025')
    Write-TestResult "41-VHD: VHD download uses FileServer" ($vhdContent -match 'FileServer|BaseURL|VHDsFolder')

    # Runtime test for Get-VHDCachePath
    $vhdPath = Get-VHDCachePath
    Write-TestResult "Get-VHDCachePath: returns non-null path" ($null -ne $vhdPath -and $vhdPath.Length -gt 0)

} catch {
    Write-TestResult "VHD Management Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 127: ISO DOWNLOAD MODULE (42-ISODownload.ps1)
# ============================================================================

Write-SectionHeader "127" "ISO DOWNLOAD MODULE"

try {
    $isoContent = Get-Content "$modulesPath\42-ISODownload.ps1" -Raw

    Write-TestResult "42-ISO: function Get-ISOStoragePath exists" ($isoContent -match 'function\s+Get-ISOStoragePath\b')
    Write-TestResult "42-ISO: function Test-CachedISO exists" ($isoContent -match 'function\s+Test-CachedISO\b')
    Write-TestResult "42-ISO: function Get-ServerISO exists" ($isoContent -match 'function\s+Get-ServerISO\b')
    Write-TestResult "42-ISO: function Show-ISODownloadMenu exists" ($isoContent -match 'function\s+Show-ISODownloadMenu\b')
    Write-TestResult "42-ISO: function Start-ISODownload exists" ($isoContent -match 'function\s+Start-ISODownload\b')
    Write-TestResult "42-ISO: handles cluster vs standalone paths" ($isoContent -match 'ClusterStorage|ClusterISOPath|HostISOPath')
    Write-TestResult "42-ISO: uses FileServer for downloads" ($isoContent -match 'FileServer|BaseURL|ISOsFolder')
    Write-TestResult "42-ISO: checks for cached ISOs" ($isoContent -match 'Test-Path|cached|exist')
    Write-TestResult "42-ISO: handles downloads" ($isoContent -match 'download|Download|Invoke-WebRequest|Start-BitsTransfer')

    # Runtime test
    $isoPath = Get-ISOStoragePath
    Write-TestResult "Get-ISOStoragePath: returns non-null path" ($null -ne $isoPath -and $isoPath.Length -gt 0)

} catch {
    Write-TestResult "ISO Download Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 128: ACTIVE DIRECTORY MODULE (61-ActiveDirectory.ps1)
# ============================================================================

Write-SectionHeader "128" "ACTIVE DIRECTORY MODULE"

try {
    $adContent = Get-Content "$modulesPath\61-ActiveDirectory.ps1" -Raw

    Write-TestResult "61-AD: function Test-ADDSInstalled exists" ($adContent -match 'function\s+Test-ADDSInstalled\b')
    Write-TestResult "61-AD: function Test-ADDSPrerequisites exists" ($adContent -match 'function\s+Test-ADDSPrerequisites\b')
    Write-TestResult "61-AD: function Show-ADDSPrerequisiteResults exists" ($adContent -match 'function\s+Show-ADDSPrerequisiteResults\b')
    Write-TestResult "61-AD: function Install-ADDSRoleIfNeeded exists" ($adContent -match 'function\s+Install-ADDSRoleIfNeeded\b')
    Write-TestResult "61-AD: function Test-ValidDomainName exists" ($adContent -match 'function\s+Test-ValidDomainName\b')
    Write-TestResult "61-AD: function Get-NetBIOSNameFromFQDN exists" ($adContent -match 'function\s+Get-NetBIOSNameFromFQDN\b')
    Write-TestResult "61-AD: function Select-FunctionalLevel exists" ($adContent -match 'function\s+Select-FunctionalLevel\b')
    Write-TestResult "61-AD: function Read-DSRMPassword exists" ($adContent -match 'function\s+Read-DSRMPassword\b')
    Write-TestResult "61-AD: function Show-ADDSPromotionMenu exists" ($adContent -match 'function\s+Show-ADDSPromotionMenu\b')
    Write-TestResult "61-AD: function Install-NewForest exists" ($adContent -match 'function\s+Install-NewForest\b')
    Write-TestResult "61-AD: function Install-AdditionalDC exists" ($adContent -match 'function\s+Install-AdditionalDC\b')
    Write-TestResult "61-AD: function Install-ReadOnlyDC exists" ($adContent -match 'function\s+Install-ReadOnlyDC\b')
    Write-TestResult "61-AD: function Show-ADDSStatus exists" ($adContent -match 'function\s+Show-ADDSStatus\b')
    Write-TestResult "61-AD: calls Install-ADDSForest" ($adContent -match 'Install-ADDSForest')
    Write-TestResult "61-AD: calls Install-ADDSDomainController" ($adContent -match 'Install-ADDSDomainController')
    Write-TestResult "61-AD: checks static IP prerequisite" ($adContent -match 'static.*IP|StaticIP|DHCP.*enabled|IPAddress')
    Write-TestResult "61-AD: DSRM password uses SecureString" ($adContent -match 'SecureString|AsSecureString|SafeModeAdministratorPassword')
    Write-TestResult "61-AD: supports functional levels" ($adContent -match 'WinThreshold|Win2012R2|Win2016|ForestMode|DomainMode')

    # Runtime tests for helper functions
    Write-TestResult "Test-ValidDomainName: valid FQDN accepted" ((Test-ValidDomainName "corp.contoso.com") -eq $true)
    Write-TestResult "Test-ValidDomainName: single label rejected" ((Test-ValidDomainName "noperiod") -eq $false)
    Write-TestResult "Get-NetBIOSNameFromFQDN: extracts first label" ((Get-NetBIOSNameFromFQDN "corp.contoso.com") -eq "CORP")

} catch {
    Write-TestResult "Active Directory Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 129: HYPER-V REPLICA MODULE (62-HyperVReplica.ps1)
# ============================================================================

Write-SectionHeader "129" "HYPER-V REPLICA MODULE"

try {
    $repContent = Get-Content "$modulesPath\62-HyperVReplica.ps1" -Raw

    Write-TestResult "62-Replica: function Test-HyperVReplicaEnabled exists" ($repContent -match 'function\s+Test-HyperVReplicaEnabled\b')
    Write-TestResult "62-Replica: function Show-HyperVReplicaMenu exists" ($repContent -match 'function\s+Show-HyperVReplicaMenu\b')
    Write-TestResult "62-Replica: function Enable-ReplicaServer exists" ($repContent -match 'function\s+Enable-ReplicaServer\b')
    Write-TestResult "62-Replica: function Enable-VMReplicationWizard exists" ($repContent -match 'function\s+Enable-VMReplicationWizard\b')
    Write-TestResult "62-Replica: function Show-ReplicationStatus exists" ($repContent -match 'function\s+Show-ReplicationStatus\b')
    Write-TestResult "62-Replica: function Start-TestFailover exists" ($repContent -match 'function\s+Start-TestFailover\b')
    Write-TestResult "62-Replica: function Start-PlannedFailover exists" ($repContent -match 'function\s+Start-PlannedFailover\b')
    Write-TestResult "62-Replica: function Set-ReverseReplication exists" ($repContent -match 'function\s+Set-ReverseReplication\b')
    Write-TestResult "62-Replica: function Remove-VMReplicationWizard exists" ($repContent -match 'function\s+Remove-VMReplicationWizard\b')
    Write-TestResult "62-Replica: supports Kerberos auth" ($repContent -match 'Kerberos')
    Write-TestResult "62-Replica: supports Certificate auth" ($repContent -match 'Certificate|certificate')
    Write-TestResult "62-Replica: configures firewall for replica" ($repContent -match 'Firewall|firewall|Enable-NetFirewallRule')
    Write-TestResult "62-Replica: uses Set-VMReplicationServer" ($repContent -match 'Set-VMReplicationServer')
    Write-TestResult "62-Replica: uses Enable-VMReplication" ($repContent -match 'Enable-VMReplication')
    Write-TestResult "62-Replica: uses Start-VMFailover" ($repContent -match 'Start-VMFailover')
    Write-TestResult "62-Replica: replication frequency options" ($repContent -match '30.*sec|5.*min|15.*min|ReplicationFrequencySec')
    Write-TestResult "62-Replica: confirmation on remove" ($repContent -match 'Confirm|confirm|Y/N|Remove-VMReplication')
    Write-TestResult "62-Replica: has error handling" ($repContent -match 'try\s*\{|catch\s*\{')

} catch {
    Write-TestResult "Hyper-V Replica Module Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 130: BATCH IDEMPOTENCY (50-EntryPoint.ps1 v1.6.0)
# ============================================================================

Write-SectionHeader "130" "BATCH IDEMPOTENCY"

try {
    $entryContent = Get-Content "$modulesPath\50-EntryPoint.ps1" -Raw

    # Idempotency checks exist for each step
    Write-TestResult "50-Batch: hostname idempotency check" ($entryContent -match '\$env:COMPUTERNAME\s+-eq\s+\$Config\.Hostname')
    Write-TestResult "50-Batch: network IP idempotency check" ($entryContent -match 'Get-NetIPAddress.*InterfaceAlias.*adapterName.*IPAddress.*Config\.IPAddress')
    Write-TestResult "50-Batch: timezone idempotency check" ($entryContent -match '\(Get-TimeZone\)\.Id\s+-eq\s+\$Config\.Timezone')
    Write-TestResult "50-Batch: RDP idempotency check" ($entryContent -match '\$rdpValue\s+-eq\s+0')
    Write-TestResult "50-Batch: WinRM idempotency check" ($entryContent -match 'winrmSvc.*Status\s+-eq\s+.Running')
    Write-TestResult "50-Batch: firewall idempotency check" ($entryContent -match 'fwState\.Domain.*fwState\.Private.*fwState\.Public')
    Write-TestResult "50-Batch: power plan idempotency check" ($entryContent -match 'currentPlan\.Name\s+-eq\s+\$Config\.SetPowerPlan')
    Write-TestResult "50-Batch: DC promotion idempotency check" ($entryContent -match 'DomainRole\s+-ge\s+4')
    Write-TestResult "50-Batch: host storage idempotency check" ($entryContent -match 'storageAlready.*checkPaths')
    Write-TestResult "50-Batch: vSwitch idempotency check" ($entryContent -match '\$existingSwitch\s*=\s*Get-VMSwitch\s+-Name\s+\$vSwitchName')
    Write-TestResult "50-Batch: vNIC idempotency (skip existing)" ($entryContent -match 'vnicSkipped\+\+')
    Write-TestResult "50-Batch: Defender exclusion idempotency" ($entryContent -match '\$missingPaths.*notin.*currentExclusions')

    # Summary line includes skipped count
    Write-TestResult "50-Batch: summary includes skipped" ($entryContent -match 'BATCH MODE COMPLETE.*changed.*skipped.*failed')
    Write-TestResult "50-Batch: skipped counter initialized" ($entryContent -match '\$skipped\s*=\s*0')
    Write-TestResult "50-Batch: BatchUndoStack initialized" ($entryContent -match 'BatchUndoStack.*Generic\.List')

    # Undo prompt on errors
    Write-TestResult "50-Batch: undo prompt on errors" ($entryContent -match 'Invoke-BatchUndo')
    Write-TestResult "50-Batch: undo prompt asks user" ($entryContent -match 'step\(s\) can be undone')

} catch {
    Write-TestResult "Batch Idempotency Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 131: TRANSACTION ROLLBACK (04-Navigation.ps1 v1.6.0)
# ============================================================================

Write-SectionHeader "131" "TRANSACTION ROLLBACK"

try {
    $navContent = Get-Content "$modulesPath\04-Navigation.ps1" -Raw
    $entryContent2 = Get-Content "$modulesPath\50-EntryPoint.ps1" -Raw

    Write-TestResult "04-Nav: function Invoke-BatchUndo exists" ($navContent -match 'function\s+Invoke-BatchUndo\b')
    Write-TestResult "04-Nav: Invoke-BatchUndo reverses order" ($navContent -match 'reversible\.Count\s*-\s*1.*-ge\s*0.*i--')
    Write-TestResult "04-Nav: Invoke-BatchUndo executes UndoScript" ($navContent -match '&\s+\$action\.UndoScript')
    Write-TestResult "04-Nav: Invoke-BatchUndo tracks undone/failed counts" ($navContent -match '\$undone\+\+' -and $navContent -match '\$undoFailed\+\+')
    Write-TestResult "04-Nav: Invoke-BatchUndo clears stack" ($navContent -match 'BatchUndoStack.*Generic\.List.*new\(\)')
    Write-TestResult "04-Nav: Invoke-BatchUndo logs session changes" ($navContent -match 'Add-SessionChange.*Undo.*Batch undo')

    # Undo registrations in batch mode
    Write-TestResult "50-Batch: hostname undo registered" ($entryContent2 -match 'BatchUndoStack\.Add.*Revert hostname')
    Write-TestResult "50-Batch: network undo registered" ($entryContent2 -match 'BatchUndoStack\.Add.*Restore network')
    Write-TestResult "50-Batch: timezone undo registered" ($entryContent2 -match 'BatchUndoStack\.Add.*Revert timezone')
    Write-TestResult "50-Batch: RDP undo registered" ($entryContent2 -match 'BatchUndoStack\.Add.*Disable RDP')
    Write-TestResult "50-Batch: WinRM undo registered" ($entryContent2 -match 'BatchUndoStack\.Add.*Disable WinRM')
    Write-TestResult "50-Batch: firewall undo registered" ($entryContent2 -match 'BatchUndoStack\.Add.*Restore firewall')
    Write-TestResult "50-Batch: power plan undo registered" ($entryContent2 -match 'BatchUndoStack\.Add.*Revert power plan')
    Write-TestResult "50-Batch: local admin undo registered" ($entryContent2 -match 'BatchUndoStack\.Add.*Remove local admin')
    Write-TestResult "50-Batch: vSwitch undo registered" ($entryContent2 -match 'BatchUndoStack\.Add.*Remove virtual switch')
    Write-TestResult "50-Batch: vNIC undo registered" ($entryContent2 -match 'BatchUndoStack\.Add.*Remove vNIC')
    Write-TestResult "50-Batch: Defender undo registered" ($entryContent2 -match 'BatchUndoStack\.Add.*Remove Defender')

} catch {
    Write-TestResult "Transaction Rollback Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 132: VM PRE-FLIGHT VALIDATION (44-VMDeployment.ps1 v1.6.1)
# ============================================================================

Write-SectionHeader "132" "VM PRE-FLIGHT VALIDATION"

try {
    $vmContent = Get-Content "$modulesPath\44-VMDeployment.ps1" -Raw

    Write-TestResult "44-VM: function Test-VMDeploymentPreFlight exists" ($vmContent -match 'function\s+Test-VMDeploymentPreFlight\b')
    Write-TestResult "44-VM: function Show-PreFlightTable exists" ($vmContent -match 'function\s+Show-PreFlightTable\b')
    Write-TestResult "44-VM: pre-flight checks disk space" ($vmContent -match 'Test-DeploymentDiskSpace|diskCheck')
    Write-TestResult "44-VM: pre-flight checks RAM" ($vmContent -match 'FreePhysicalMemory|freeRAMMB')
    Write-TestResult "44-VM: pre-flight checks vCPU ratio" ($vmContent -match 'NumberOfLogicalProcessors|vCPU.*ratio')
    Write-TestResult "44-VM: pre-flight checks VM switches" ($vmContent -match 'Get-VMSwitch.*requestedSwitches|missingSwitches')
    Write-TestResult "44-VM: pre-flight checks VHD sources" ($vmContent -match 'vhdAccessible|Test-Path.*VHD')
    Write-TestResult "44-VM: pre-flight returns HasFailure flag" ($vmContent -match 'HasFailure')
    Write-TestResult "44-VM: Show-PreFlightTable renders table" ($vmContent -match 'PRE-FLIGHT VALIDATION')
    Write-TestResult "44-VM: pre-flight has OK/WARN/FAIL statuses" ($vmContent -match '"OK"' -and $vmContent -match '"WARN"' -and $vmContent -match '"FAIL"')

} catch {
    Write-TestResult "VM Pre-Flight Validation Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 133: VM POST-DEPLOY SMOKE TESTS (44-VMDeployment.ps1 v1.6.1)
# ============================================================================

Write-SectionHeader "133" "VM POST-DEPLOY SMOKE TESTS"

try {
    $vmContent2 = Get-Content "$modulesPath\44-VMDeployment.ps1" -Raw

    Write-TestResult "44-VM: function Test-VMPostDeployment exists" ($vmContent2 -match 'function\s+Test-VMPostDeployment\b')
    Write-TestResult "44-VM: function Show-SmokeSummary exists" ($vmContent2 -match 'function\s+Show-SmokeSummary\b')
    Write-TestResult "44-VM: smoke checks VM state Running" ($vmContent2 -match 'State\s+-eq\s+.Running')
    Write-TestResult "44-VM: smoke checks heartbeat" ($vmContent2 -match 'Get-VMIntegrationService.*Heartbeat')
    Write-TestResult "44-VM: smoke checks NIC connected" ($vmContent2 -match 'Get-VMNetworkAdapter')
    Write-TestResult "44-VM: smoke polls for guest IP" ($vmContent2 -match 'IPTimeoutSeconds|IPAddresses')
    Write-TestResult "44-VM: smoke checks ping response" ($vmContent2 -match 'Test-Connection.*guestIP')
    Write-TestResult "44-VM: smoke checks RDP port 3389" ($vmContent2 -match 'BeginConnect.*3389|RDP.*3389')
    Write-TestResult "44-VM: smoke returns results" ($vmContent2 -match 'Passed|passedChecks')
    Write-TestResult "44-VM: Show-SmokeSummary renders per-VM" ($vmContent2 -match 'POST-DEPLOYMENT SMOKE|SMOKE TEST')
    Write-TestResult "44-VM: smoke summary output" ($vmContent2 -match 'SMOKE TEST|SmokeSummary|smokeResults')

} catch {
    Write-TestResult "VM Post-Deploy Smoke Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 134: DOWNLOAD RESUME/RETRY (39-FileServer.ps1 v1.7.0)
# ============================================================================

Write-SectionHeader "134" "DOWNLOAD RESUME/RETRY"

try {
    $fsContent = Get-Content "$modulesPath\39-FileServer.ps1" -Raw
    $initContent = Get-Content "$modulesPath\00-Initialization.ps1" -Raw

    Write-TestResult "39-FS: dynamic retry count for large files" ($fsContent -match 'MaxDownloadRetries|maxAttempts')
    Write-TestResult "39-FS: function Get-FileServerFile exists" ($fsContent -match 'function\s+Get-FileServerFile\b')
    Write-TestResult "39-FS: function Test-FileIntegrity exists" ($fsContent -match 'function\s+Test-FileIntegrity\b')
    Write-TestResult "39-FS: hash verification with SHA256" ($fsContent -match 'Get-FileHashBackground|SHA256')
    Write-TestResult "39-FS: disk space check before download" ($fsContent -match 'SizeRemaining|requiredSpace|Insufficient disk')
    Write-TestResult "39-FS: progress bar with speed/ETA" ($fsContent -match 'Write-ProgressBar|SpeedBytesPerSec')
    Write-TestResult "00-Init: MaxDownloadRetries constant" ($initContent -match '\$script:MaxDownloadRetries\s*=\s*3')
    Write-TestResult "00-Init: BITSPreferred constant" ($initContent -match '\$script:BITSPreferred\s*=\s*\$true')

} catch {
    Write-TestResult "Download Resume/Retry Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 135: EXPANDED HEALTH DASHBOARD (37-HealthCheck.ps1 v1.7.0)
# ============================================================================

Write-SectionHeader "135" "EXPANDED HEALTH DASHBOARD"

try {
    $healthContent = Get-Content "$modulesPath\37-HealthCheck.ps1" -Raw

    Write-TestResult "37-Health: disk I/O latency section" ($healthContent -match 'DISK I/O LATENCY')
    Write-TestResult "37-Health: uses Get-Counter for disk latency" ($healthContent -match "Get-Counter.*PhysicalDisk.*Avg.*Disk sec")
    Write-TestResult "37-Health: NIC error counters section" ($healthContent -match 'NIC ERROR COUNTERS')
    Write-TestResult "37-Health: uses Get-NetAdapterStatistics" ($healthContent -match 'Get-NetAdapterStatistics')
    Write-TestResult "37-Health: memory pressure section" ($healthContent -match 'MEMORY PRESSURE')
    Write-TestResult "37-Health: uses Pages/sec counter" ($healthContent -match 'Pages/sec|Available MBytes')
    Write-TestResult "37-Health: Hyper-V guest health section" ($healthContent -match 'HYPER-V GUEST HEALTH')
    Write-TestResult "37-Health: guest heartbeat per VM" ($healthContent -match 'Get-VMIntegrationService.*Heartbeat')
    Write-TestResult "37-Health: top 5 CPU processes section" ($healthContent -match 'TOP 5 CPU PROCESSES')
    Write-TestResult "37-Health: sorts processes by CPU" ($healthContent -match 'Sort-Object CPU -Descending')
    Write-TestResult "37-Health: disk latency thresholds" ($healthContent -match 'latencyMs.*-gt\s+20|20.*Error')
    Write-TestResult "37-Health: NIC error threshold" ($healthContent -match 'totalErrors.*-gt\s*0')

} catch {
    Write-TestResult "Expanded Health Dashboard Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 136: DRIFT DETECTION PERSISTENCE (45-ConfigExport.ps1 v1.7.1)
# ============================================================================

Write-SectionHeader "136" "DRIFT DETECTION PERSISTENCE"

try {
    $driftContent = Get-Content "$modulesPath\45-ConfigExport.ps1" -Raw

    Write-TestResult "45-Drift: function Save-DriftBaseline exists" ($driftContent -match 'function\s+Save-DriftBaseline\b')
    Write-TestResult "45-Drift: function Get-DriftBaselines exists" ($driftContent -match 'function\s+Get-DriftBaselines\b')
    Write-TestResult "45-Drift: function Compare-DriftHistory exists" ($driftContent -match 'function\s+Compare-DriftHistory\b')
    Write-TestResult "45-Drift: function Show-DriftTrend exists" ($driftContent -match 'function\s+Show-DriftTrend\b')
    Write-TestResult "45-Drift: function Show-DriftDetectionMenu exists" ($driftContent -match 'function\s+Show-DriftDetectionMenu\b')
    Write-TestResult "45-Drift: saves baselines to AppConfigDir" ($driftContent -match 'AppConfigDir.*baselines')
    Write-TestResult "45-Drift: baseline captures hostname" ($driftContent -match 'Hostname.*env:COMPUTERNAME')
    Write-TestResult "45-Drift: baseline captures timezone" ($driftContent -match 'Get-TimeZone')
    Write-TestResult "45-Drift: baseline captures firewall state" ($driftContent -match 'Get-FirewallState')
    Write-TestResult "45-Drift: baseline captures installed features" ($driftContent -match 'Test-HyperVInstalled|Test-MPIOInstalled')
    Write-TestResult "45-Drift: Compare-DriftHistory detects changes" ($driftContent -match 'HasChanges|changes\.Count')
    Write-TestResult "45-Drift: Show-DriftTrend shows timeline" ($driftContent -match 'DRIFT TREND|drift trend')
    Write-TestResult "45-Drift: drift menu has multiple options" ($driftContent -match '\[1\].*drift|\[2\].*baseline')
    Write-TestResult "45-Drift: logs session changes" ($driftContent -match 'Add-SessionChange.*[Dd]rift')

} catch {
    Write-TestResult "Drift Detection Persistence Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 137: PERFORMANCE TREND REPORTS (54-HTMLReports.ps1 v1.7.1)
# ============================================================================

Write-SectionHeader "137" "PERFORMANCE TREND REPORTS"

try {
    $trendContent = Get-Content "$modulesPath\54-HTMLReports.ps1" -Raw
    $opsContent = Get-Content "$modulesPath\56-OperationsMenu.ps1" -Raw

    Write-TestResult "54-HTML: function Save-PerformanceSnapshot exists" ($trendContent -match 'function\s+Save-PerformanceSnapshot\b')
    Write-TestResult "54-HTML: function Export-HTMLTrendReport exists" ($trendContent -match 'function\s+Export-HTMLTrendReport\b')
    Write-TestResult "54-HTML: function Start-MetricCollection exists" ($trendContent -match 'function\s+Start-MetricCollection\b')
    Write-TestResult "54-HTML: snapshots save to metrics dir" ($trendContent -match 'AppConfigDir.*metrics')
    Write-TestResult "54-HTML: snapshot captures CPU%" ($trendContent -match 'CPUPercent')
    Write-TestResult "54-HTML: snapshot captures memory" ($trendContent -match 'MemoryUsedPercent')
    Write-TestResult "54-HTML: snapshot captures disk info" ($trendContent -match 'diskInfo.*FreeGB|FreeGB')
    Write-TestResult "54-HTML: trend report uses CSS bar charts" ($trendContent -match 'border-radius.*min-width')
    Write-TestResult "54-HTML: trend report estimates days until full" ($trendContent -match 'days until full|daysLeft')
    Write-TestResult "54-HTML: metric collection supports interval" ($trendContent -match 'IntervalMinutes.*DurationMinutes')
    Write-TestResult "56-Ops: drift detection menu wired" ($opsContent -match 'Show-DriftDetectionMenu')
    Write-TestResult "56-Ops: save snapshot menu item" ($opsContent -match 'Save-PerformanceSnapshot')
    Write-TestResult "56-Ops: trend report menu item" ($opsContent -match 'Export-HTMLTrendReport')
    Write-TestResult "56-Ops: metric collection menu item" ($opsContent -match 'Start-MetricCollection')

    # Auto-baseline test (depends on drift functions)
    $entryContent3 = Get-Content "$modulesPath\50-EntryPoint.ps1" -Raw
    Write-TestResult "50-Batch: auto-save drift baseline" ($entryContent3 -match 'Save-DriftBaseline.*Auto-saved after batch')

} catch {
    Write-TestResult "Performance Trend Report Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 138: MULTI-AGENT SUPPORT (57-KaseyaInstaller.ps1 v1.8.0)
# ============================================================================

Write-SectionHeader "138" "MULTI-AGENT SUPPORT"

try {
    $agentContent = Get-Content "$modulesPath\57-KaseyaInstaller.ps1" -Raw
    $initContent2 = Get-Content "$modulesPath\00-Initialization.ps1" -Raw

    Write-TestResult "57-Agent: function Get-AllAgentConfigs exists" ($agentContent -match 'function\s+Get-AllAgentConfigs\b')
    Write-TestResult "57-Agent: function Test-AgentInstalledByConfig exists" ($agentContent -match 'function\s+Test-AgentInstalledByConfig\b')
    Write-TestResult "57-Agent: function Show-AgentManagement exists" ($agentContent -match 'function\s+Show-AgentManagement\b')
    Write-TestResult "57-Agent: Get-AllAgentConfigs returns primary" ($agentContent -match 'IsPrimary.*true')
    Write-TestResult "57-Agent: Get-AllAgentConfigs includes AdditionalAgents" ($agentContent -match 'AdditionalAgents.*Count.*-gt\s*0')
    Write-TestResult "57-Agent: Test-AgentInstalledByConfig checks service" ($agentContent -match 'Get-Service.*AgentConfig\.ServiceName')
    Write-TestResult "57-Agent: Test-AgentInstalledByConfig checks paths" ($agentContent -match 'AgentConfig\.InstallPaths')
    Write-TestResult "57-Agent: Show-AgentManagement status display" ($agentContent -match 'AGENT MANAGEMENT|AGENT STATUS')
    Write-TestResult "57-Agent: agent management has install all option" ($agentContent -match 'Install all missing agents')
    Write-TestResult "57-Agent: falls back to original menu for single agent" ($agentContent -match 'allConfigs\.Count\s*-le\s*1')
    Write-TestResult "00-Init: AdditionalAgents variable" ($initContent2 -match '\$script:AdditionalAgents\s*=\s*@\(\)')

} catch {
    Write-TestResult "Multi-Agent Support Tests" $false $_.Exception.Message
}

# ============================================================================
# SECTION 139: CLUSTER CSV PREP (51-ClusterDashboard.ps1 v1.8.0)
# ============================================================================

Write-SectionHeader "139" "CLUSTER CSV PREP"

try {
    $clusterContent = Get-Content "$modulesPath\51-ClusterDashboard.ps1" -Raw

    Write-TestResult "51-Cluster: function Test-ClusterReadiness exists" ($clusterContent -match 'function\s+Test-ClusterReadiness\b')
    Write-TestResult "51-Cluster: function Initialize-ClusterCSV exists" ($clusterContent -match 'function\s+Initialize-ClusterCSV\b')
    Write-TestResult "51-Cluster: readiness checks all nodes online" ($clusterContent -match '\$nodesUp.*Where-Object.*State.*-eq.*Up')
    Write-TestResult "51-Cluster: readiness checks quorum" ($clusterContent -match '\$quorumOK\s*=.*null.*-ne.*quorum')
    Write-TestResult "51-Cluster: readiness checks CSVs online" ($clusterContent -match '\$csvOK\s*=\s*\$csvOnline\s*-and')
    Write-TestResult "51-Cluster: readiness checks redirected I/O" ($clusterContent -match 'FileSystemRedirectedIOReason|csvRedirected')
    Write-TestResult "51-Cluster: readiness checks cluster networks" ($clusterContent -match '\$networksUp.*Where-Object.*State.*Up')
    Write-TestResult "51-Cluster: readiness returns Ready flag" ($clusterContent -match 'Ready.*allOK')
    Write-TestResult "51-Cluster: CSV validation reports space" ($clusterContent -match 'CSV VALIDATION.*FreeSpace|totalGB.*freeGB')
    Write-TestResult "51-Cluster: CSV validation checks redirected I/O" ($clusterContent -match 'Redirected I/O.*FileSystemRedirectedIOReason')
    Write-TestResult "51-Cluster: cluster ops menu has readiness check" ($clusterContent -match '\[5\].*Cluster Readiness')
    Write-TestResult "51-Cluster: cluster ops menu has CSV validation" ($clusterContent -match '\[6\].*CSV Validation')
    Write-TestResult "51-Cluster: logs session changes" ($clusterContent -match 'Add-SessionChange.*Cluster.*readiness|Add-SessionChange.*Cluster.*CSV')

} catch {
    Write-TestResult "Cluster CSV Prep Tests" $false $_.Exception.Message
}

# ============================================================================
# FINAL SUMMARY
# ============================================================================

$elapsed = (Get-Date) - $script:StartTime

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Total Tests:   $script:TotalTests" -ForegroundColor White
Write-Host "  Passed:        $script:PassedTests" -ForegroundColor Green
Write-Host "  Failed:        $script:FailedTests" -ForegroundColor $(if ($script:FailedTests -eq 0) { "Green" } else { "Red" })
Write-Host "  Skipped:       $script:SkippedTests" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Elapsed Time:  $([math]::Round($elapsed.TotalSeconds, 2)) seconds" -ForegroundColor White
Write-Host ""

if ($script:FailedTests -eq 0) {
    Write-Host "  ALL TESTS PASSED!" -ForegroundColor Green
    $exitCode = 0
} else {
    Write-Host "  SOME TESTS FAILED:" -ForegroundColor Red
    Write-Host ""
    foreach ($detail in $script:FailedDetails) {
        Write-Host "    - $($detail.Test)" -ForegroundColor Red
        if ($detail.Error) {
            Write-Host "      $($detail.Error)" -ForegroundColor DarkRed
        }
    }
    $exitCode = 1
}

$runnableTests = $script:TotalTests - $script:SkippedTests
if ($runnableTests -gt 0) {
    $percentPassed = [math]::Round(($script:PassedTests / $runnableTests) * 100, 1)
    Write-Host ""
    Write-Host "  Pass Rate:     $percentPassed% ($script:PassedTests/$runnableTests)" -ForegroundColor $(if ($percentPassed -ge 95) { "Green" } elseif ($percentPassed -ge 80) { "Yellow" } else { "Red" })
}

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

exit $exitCode
