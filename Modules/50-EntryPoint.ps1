#region ===== SCRIPT ENTRY POINT =====
# Start transcript logging
function Start-ScriptTranscript {
    # Ensure temp directory exists
    $tempPath = $script:TempPath
    if (-not (Test-Path -LiteralPath $tempPath)) {
        try {
            New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
        }
        catch {
            # Fall back to user temp if we can't create directory
            $tempPath = $env:TEMP
        }
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $hostname = $env:COMPUTERNAME
    $script:TranscriptPath = Join-Path $tempPath "$($script:ToolName)Config_${hostname}_${timestamp}.log"

    try {
        Start-Transcript -Path $script:TranscriptPath -Append | Out-Null
        return $true
    }
    catch {
        # Transcript might already be running
        return $false
    }
}

# Stop transcript logging
function Stop-ScriptTranscript {
    try {
        Stop-Transcript | Out-Null
    }
    catch {
        # Ignore if transcript wasn't running
    }
}

# Clean up old transcript files (older than 30 days)
function Remove-OldTranscripts {
    param(
        [int]$DaysToKeep = 30,
        [long]$MaxDirectorySizeMB = 500
    )

    $tempPath = $script:TempPath
    if (-not (Test-Path -LiteralPath $tempPath)) { return }

    try {
        $logFilter = "$($script:ToolName)Config_*.log"
        $allLogs = Get-ChildItem -LiteralPath $tempPath -Filter $logFilter -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime

        if (-not $allLogs) { return }

        # Age-based cleanup: remove logs older than DaysToKeep
        $cutoffDate = (Get-Date).AddDays(-$DaysToKeep)
        $oldLogs = @($allLogs | Where-Object { $_.LastWriteTime -lt $cutoffDate })

        if ($oldLogs.Count -gt 0) {
            $count = $oldLogs.Count
            $oldLogs | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
            Write-OutputColor "Cleaned up $count old transcript(s) (older than $DaysToKeep days)" -color "Debug"
        }

        # Size-based safety: if transcript directory exceeds MaxDirectorySizeMB, remove oldest first
        $remainingLogs = Get-ChildItem -LiteralPath $tempPath -Filter $logFilter -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime
        if ($remainingLogs) {
            $totalSize = ($remainingLogs | Measure-Object -Property Length -Sum).Sum
            $maxBytes = $MaxDirectorySizeMB * 1MB
            if ($totalSize -gt $maxBytes) {
                $sizeCount = 0
                foreach ($log in $remainingLogs) {
                    if ($totalSize -le $maxBytes) { break }
                    $totalSize -= $log.Length
                    Remove-Item -LiteralPath $log.FullName -Force -ErrorAction SilentlyContinue
                    $sizeCount++
                }
                if ($sizeCount -gt 0) {
                    Write-OutputColor "Cleaned up $sizeCount transcript(s) (directory exceeded ${MaxDirectorySizeMB}MB)" -color "Debug"
                }
            }
        }
    }
    catch {
        # Silently ignore cleanup errors
    }
}

# Function to ensure the script is running with elevated privileges
function Assert-Elevation {
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-RackStackError -Code "RS-1001"
        try {
            $elevateArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
            if ($script:CLIAction)  { $elevateArgs += " -Action $($script:CLIAction)" }
            if ($script:CLIProfile -ne 'Standard') { $elevateArgs += " -Tier $($script:CLIProfile)" }
            if ($script:CLIConfig)  { $elevateArgs += " -Config `"$($script:CLIConfig)`"" }
            if ($script:CLISilent)  { $elevateArgs += " -Silent" }
            if ($script:CLIOutputFormat -ne 'Console') { $elevateArgs += " -OutputFormat $($script:CLIOutputFormat)" }
            Start-Process powershell -ArgumentList $elevateArgs -Verb RunAs -ErrorAction Stop
        }
        catch {
            Write-OutputColor "  Failed to elevate: $_" -color "Error"
            Write-OutputColor "  Please right-click and 'Run as Administrator'." -color "Warning"
            Read-Host "  Press Enter to exit"
        }
        [Environment]::Exit(0)
    }
    else {
        # Size and maximize console window before any output
        Initialize-ConsoleWindow

        # Start transcript logging
        $transcriptStarted = Start-ScriptTranscript
        if ($transcriptStarted -and $script:TranscriptPath) {
            Write-OutputColor "Transcript logging to: $($script:TranscriptPath)" -color "Debug"
        }

        # Clean up old transcripts (older than 30 days)
        Remove-OldTranscripts -DaysToKeep 30

        Write-OutputColor "  Script is running with elevated privileges." -color "Success"

        # Check for session to restore (v2.8.0)
        $null = Restore-SessionState

        # Load environment defaults and custom licenses from defaults.json
        Import-Defaults

        # Silent update check (non-blocking, 5s timeout)
        Test-StartupUpdateCheck

        # Auto-update: if enabled and update available, install without prompting
        if ($script:AutoUpdate -and $script:UpdateAvailable -and $script:LatestRelease) {
            Write-OutputColor "  Auto-update enabled. Installing v$($script:LatestVersion)..." -color "Info"
            try {
                Install-ScriptUpdate -Release $script:LatestRelease -Auto
            }
            catch {
                Write-OutputColor "  Auto-update failed: $($_.Exception.Message)" -color "Warning"
            }
        }

        # CLI headless mode: dispatch action instead of interactive menu
        if ($script:HeadlessMode) {
            Invoke-CLIAction
        }
        else {
            Start-Show-Mainmenu
        }

        # Stop transcript when done
        Stop-ScriptTranscript
    }
}

# CLI headless mode action dispatcher
function Invoke-CLIAction {
    Write-OutputColor "" -color "Info"
    Write-OutputColor ("=" * 65) -color "Info"
    Write-OutputColor "  $($script:ToolFullName.ToUpper()) v$($script:ScriptVersion) - CLI MODE" -color "Info"
    Write-OutputColor ("=" * 65) -color "Info"
    Write-OutputColor "  Action:  $($script:CLIAction)" -color "Info"
    Write-OutputColor "  Profile: $($script:CLIProfile)" -color "Info"
    if ($script:CLISilent) {
        Write-OutputColor "  Mode:    Silent (prompts auto-confirmed)" -color "Info"
    }
    if ($script:CLIOutputFormat -eq 'JSON') {
        Write-OutputColor "  Output: JSON" -color "Info"
        Write-OutputColor "" -color "Info"
    }
    Write-OutputColor "" -color "Info"

    switch ($script:CLIAction) {
        'Cleanup' {
            Write-OutputColor "  Running disk cleanup ($($script:CLIProfile) profile)..." -color "Info"
            Write-OutputColor "" -color "Info"
            switch ($script:CLIProfile) {
                'Light'      { Invoke-QuickClean }
                'Standard'   { Invoke-StandardClean }
                'Aggressive' { Invoke-DeepClean }
            }
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Cleanup complete." -color "Success"
            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool    = $script:ToolFullName
                    Version = $script:ScriptVersion
                    Action  = 'Cleanup'
                    Profile = $script:CLIProfile
                    Status  = 'Complete'
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 5)
            }
        }
        'Debloat' {
            $osType = if (Test-WindowsServer) { "Server" } else { "Workstation" }
            Write-OutputColor "  Running $osType debloat ($($script:CLIProfile) profile)..." -color "Info"
            Write-OutputColor "" -color "Info"
            if (Test-WindowsServer) {
                Invoke-ServerDebloat -DebloatProfile $script:CLIProfile
            }
            else {
                Invoke-WorkstationDebloat -DebloatProfile $script:CLIProfile
            }
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Debloat complete." -color "Success"
            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool    = $script:ToolFullName
                    Version = $script:ScriptVersion
                    Action  = 'Debloat'
                    Profile = $script:CLIProfile
                    Status  = 'Complete'
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 5)
            }
        }
        'HealthCheck' {
            $healthReport = Show-SystemHealthCheck
            if ($script:CLIOutputFormat -eq 'JSON' -and $null -ne $healthReport) {
                $jsonResult = @{
                    Tool    = $script:ToolFullName
                    Version = $script:ScriptVersion
                    Action  = 'HealthCheck'
                    Report  = $healthReport
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
        }
        'Batch' {
            if (-not $script:CLIConfig) {
                Write-OutputColor "  ERROR: -Action Batch requires -Config <path>" -color "Error"
                [Environment]::Exit(1)
            }
            if (-not (Test-Path -LiteralPath $script:CLIConfig)) {
                Write-OutputColor "  ERROR: Config file not found: $($script:CLIConfig)" -color "Error"
                [Environment]::Exit(1)
            }
            try {
                $batchConfig = Get-Content -LiteralPath $script:CLIConfig -Raw | ConvertFrom-Json
                $configHash = @{}
                $batchConfig.PSObject.Properties | ForEach-Object { $configHash[$_.Name] = $_.Value }
                Start-BatchMode -Config $configHash
            }
            catch {
                Write-OutputColor "  ERROR: Failed to load config: $_" -color "Error"
                [Environment]::Exit(1)
            }
        }
        'QuickScan' {
            Write-OutputColor "  Running quick scan (health + disk + debloat analysis)..." -color "Info"
            Write-OutputColor "" -color "Info"

            # Phase 1: System health
            Write-OutputColor "  --- SYSTEM HEALTH ---" -color "Info"
            $healthReport = Show-SystemHealthCheck

            # Phase 2: Disk space analysis
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  --- DISK SPACE ANALYSIS ---" -color "Info"
            $cleanupReport = Show-EnhancedCleanupAnalysis

            # Phase 3: Debloat recommendations
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  --- DEBLOAT RECOMMENDATIONS ---" -color "Info"
            $debloatReport = Show-DebloatAnalysis

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool        = $script:ToolFullName
                    Version     = $script:ScriptVersion
                    Action      = 'QuickScan'
                    Health      = $healthReport
                    DiskCleanup = $cleanupReport
                    Debloat     = $debloatReport
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
        }
        'Inventory' {
            $inventoryReport = Get-ServerInventory
            if ($script:CLIOutputFormat -eq 'JSON' -and $null -ne $inventoryReport) {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'Inventory'
                    Inventory = $inventoryReport
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
        }
        'Compliance' {
            Write-OutputColor "  Running compliance check..." -color "Info"
            Write-OutputColor "" -color "Info"

            # Health check
            Write-OutputColor "  [1/3] System health check..." -color "Info"
            $healthReport = Show-SystemHealthCheck

            # Readiness checks
            Write-OutputColor "  [2/3] Readiness checks..." -color "Info"
            $readinessChecks = Get-ReadinessChecks
            $readyCount = @($readinessChecks | Where-Object { $_.Status -eq 'OK' }).Count
            $totalChecks = $readinessChecks.Count
            $readinessScore = if ($totalChecks -gt 0) { [math]::Round(($readyCount / $totalChecks) * 100) } else { 0 }

            # Drift (optional, only if baseline provided)
            $driftResults = $null
            $driftCount = 0
            if ($script:CLIConfig) {
                Write-OutputColor "  [3/3] Drift check against: $($script:CLIConfig)" -color "Info"
                $driftResults = Compare-ConfigurationDrift -ProfilePath $script:CLIConfig
                if ($null -eq $driftResults) {
                    Write-OutputColor "  Warning: Could not load baseline, skipping drift check." -color "Warning"
                } else {
                    $driftCount = @($driftResults.Keys | Where-Object { -not $driftResults[$_].Match }).Count
                }
            } else {
                Write-OutputColor "  [3/3] Drift check skipped (no -Config baseline)" -color "Info"
            }

            # Calculate overall compliance score
            $healthIssues = if ($healthReport -and $healthReport.Issues) { $healthReport.Issues } else { 0 }
            $healthStatus = if ($healthReport -and $healthReport.Health) { $healthReport.Health } else { "Unknown" }

            Write-OutputColor "" -color "Info"
            Write-OutputColor "  ── Compliance Summary ──" -color "Info"
            Write-OutputColor "  Health:     $healthStatus ($healthIssues issue(s))" -color $(if ($healthStatus -eq 'OK') { 'Success' } elseif ($healthStatus -eq 'Warning') { 'Warning' } else { 'Error' })
            Write-OutputColor "  Readiness:  $readinessScore% ($readyCount/$totalChecks checks passing)" -color $(if ($readinessScore -ge 80) { 'Success' } elseif ($readinessScore -ge 50) { 'Warning' } else { 'Error' })
            if ($null -ne $driftResults) {
                Write-OutputColor "  Drift:      $driftCount setting(s) drifted" -color $(if ($driftCount -eq 0) { 'Success' } else { 'Warning' })
            }

            if ($script:CLIOutputFormat -eq 'JSON') {
                $readinessItems = @()
                foreach ($chk in $readinessChecks) {
                    $readinessItems += @{
                        Category = $chk.Category
                        Name     = $chk.Name
                        Value    = $chk.Value
                        Status   = $chk.Status
                    }
                }

                $jsonResult = @{
                    Tool             = $script:ToolFullName
                    Version          = $script:ScriptVersion
                    Action           = 'Compliance'
                    Hostname         = $env:COMPUTERNAME
                    Timestamp        = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Health           = $healthReport
                    Readiness        = @{
                        Score  = $readinessScore
                        Passed = $readyCount
                        Total  = $totalChecks
                        Checks = $readinessItems
                    }
                }

                if ($null -ne $driftResults) {
                    $driftItems = @()
                    foreach ($key in $driftResults.Keys) {
                        $item = $driftResults[$key]
                        $driftItems += @{
                            Setting  = $key
                            Expected = $item.Expected
                            Current  = $item.Current
                            Match    = $item.Match
                        }
                    }
                    $jsonResult.Drift = @{
                        Baseline   = $script:CLIConfig
                        DriftCount = $driftCount
                        Checks     = $driftItems
                    }
                }

                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
        }
        'Snapshot' {
            Write-OutputColor "  Saving performance snapshot..." -color "Info"
            $snapshotPath = Save-PerformanceSnapshot
            if ($null -ne $snapshotPath) {
                Write-OutputColor "  Snapshot saved: $snapshotPath" -color "Success"
                if ($script:CLIOutputFormat -eq 'JSON') {
                    $snapshotData = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json
                    $jsonResult = @{
                        Tool     = $script:ToolFullName
                        Version  = $script:ScriptVersion
                        Action   = 'Snapshot'
                        Snapshot = $snapshotData
                        SavedTo  = $snapshotPath
                    }
                    Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
                }
            } else {
                Write-OutputColor "  Failed to capture performance snapshot." -color "Error"
                [Environment]::Exit(1)
            }
        }
        'DriftCheck' {
            if ($script:CLIConfig) {
                # Compare current state against a baseline/profile
                Write-OutputColor "  Comparing against baseline: $($script:CLIConfig)" -color "Info"
                $driftResults = Compare-ConfigurationDrift -ProfilePath $script:CLIConfig
                if ($null -eq $driftResults) {
                    Write-OutputColor "  Failed to load baseline." -color "Error"
                    [Environment]::Exit(1)
                }
                Show-DriftReport -DriftResults $driftResults

                if ($script:CLIOutputFormat -eq 'JSON') {
                    $driftItems = @()
                    foreach ($key in $driftResults.Keys) {
                        $item = $driftResults[$key]
                        $driftItems += @{
                            Setting  = $key
                            Expected = $item.Expected
                            Current  = $item.Current
                            Match    = $item.Match
                        }
                    }
                    $driftCount = @($driftItems | Where-Object { -not $_.Match }).Count
                    $jsonResult = @{
                        Tool       = $script:ToolFullName
                        Version    = $script:ScriptVersion
                        Action     = 'DriftCheck'
                        Hostname   = $env:COMPUTERNAME
                        Baseline   = $script:CLIConfig
                        Checks     = $driftItems
                        DriftCount = $driftCount
                        Status     = if ($driftCount -eq 0) { 'Clean' } else { 'Drifted' }
                    }
                    Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
                }
            } else {
                # No baseline — capture current state
                Write-OutputColor "  Capturing server baseline..." -color "Info"
                $baselinePath = Save-DriftBaseline -Description "CLI baseline capture"
                if ($null -ne $baselinePath) {
                    Write-OutputColor "  Baseline saved: $baselinePath" -color "Success"
                    if ($script:CLIOutputFormat -eq 'JSON') {
                        $baselineData = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
                        $jsonResult = @{
                            Tool      = $script:ToolFullName
                            Version   = $script:ScriptVersion
                            Action    = 'DriftCheck'
                            Mode      = 'Capture'
                            Hostname  = $env:COMPUTERNAME
                            Baseline  = $baselineData
                            SavedTo   = $baselinePath
                        }
                        Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
                    }
                } else {
                    Write-OutputColor "  Failed to capture baseline." -color "Error"
                    [Environment]::Exit(1)
                }
            }
        }
        default {
            Write-OutputColor "  Unknown CLI action: $($script:CLIAction)" -color "Error"
            [Environment]::Exit(1)
        }
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  CLI action completed successfully." -color "Success"

    # Exit with proper code for automation consumers
    if ($script:HeadlessMode) {
        [Environment]::Exit(0)
    }
}

# Dry-run mode flag (set per batch session)
$script:DryRunMode = $false

# Wrapper for batch steps that respects dry-run mode
function Invoke-BatchStep {
    param(
        [string]$StepName,
        [string]$Description,
        [scriptblock]$Action
    )

    if ($script:DryRunMode) {
        Write-OutputColor "  [DRY RUN] Step: $StepName" -color "Info"
        Write-OutputColor "  [DRY RUN] Would: $Description" -color "Info"
        return $true
    }

    return (& $Action)
}

# Validate batch config before execution
function Test-BatchConfig {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Config
    )

    $errors = [System.Collections.ArrayList]::new()
    $warnings = [System.Collections.ArrayList]::new()

    # ConfigType validation
    if ($Config.ConfigType) {
        $validTypes = @("VM", "HOST")
        if ($Config.ConfigType.ToUpper() -notin $validTypes) {
            $null = $errors.Add("ConfigType '$($Config.ConfigType)' is invalid. Must be 'VM' or 'HOST'.")
        }
    }

    # Hostname validation
    if ($Config.Hostname) {
        if (-not (Test-ValidHostname -Hostname $Config.Hostname)) {
            $null = $errors.Add("Hostname '$($Config.Hostname)' is invalid. Must be 1-15 alphanumeric characters (hyphens allowed, not at start/end).")
        }
    } else {
        $null = $warnings.Add("Hostname is not set. Server will keep its current name.")
    }

    # IP address fields
    $ipFields = @("IPAddress", "Gateway", "DNS1", "DNS2")
    foreach ($field in $ipFields) {
        if ($Config[$field] -and $Config[$field] -is [string] -and $Config[$field].Trim() -ne "") {
            if (-not (Test-ValidIPAddress -IPAddress $Config[$field])) {
                $null = $errors.Add("$field '$($Config[$field])' is not a valid IPv4 address.")
            }
        }
    }

    # SubnetCIDR range
    if ($null -ne $Config.SubnetCIDR) {
        $cidr = $Config.SubnetCIDR -as [int]
        if ($null -eq $cidr -or $cidr -lt 1 -or $cidr -gt 32) {
            $null = $errors.Add("SubnetCIDR '$($Config.SubnetCIDR)' is invalid. Must be an integer between 1 and 32.")
        }
    }

    # Network consistency: IP requires Gateway
    if ($Config.IPAddress -and -not $Config.Gateway) {
        $null = $errors.Add("IPAddress is set but Gateway is missing. Both are required for network configuration.")
    }
    if ($Config.Gateway -and -not $Config.IPAddress) {
        $null = $errors.Add("Gateway is set but IPAddress is missing. Both are required for network configuration.")
    }

    # Boolean fields validation
    $boolFields = @("EnableRDP", "EnableWinRM", "ConfigureFirewall", "InstallHyperV",
                    "InstallMPIO", "InstallFailoverClustering", "CreateLocalAdmin",
                    "DisableBuiltInAdmin", "InstallUpdates", "AutoReboot",
                    "CreateVirtualSwitch", "CreateSETSwitch", "ConfigureSharedStorage",
                    "ConfigureMPIO", "InitializeHostStorage", "ConfigureDefenderExclusions",
                    "PromoteToDC", "InstallAgent", "ValidateCluster", "DryRun")
    foreach ($field in $boolFields) {
        if ($null -ne $Config[$field] -and $Config[$field] -isnot [bool]) {
            $null = $errors.Add("$field must be true or false (got '$($Config[$field])').")
        }
    }

    # Power plan validation
    if ($Config.SetPowerPlan) {
        if (-not $script:PowerPlanGUID.ContainsKey($Config.SetPowerPlan)) {
            $validPlans = ($script:PowerPlanGUID.Keys | Sort-Object) -join "', '"
            $null = $errors.Add("SetPowerPlan '$($Config.SetPowerPlan)' is invalid. Valid options: '$validPlans'.")
        }
    }

    # StorageBackendType validation
    if ($Config.StorageBackendType) {
        if ($script:ValidStorageBackends -and $Config.StorageBackendType -notin $script:ValidStorageBackends) {
            $validBackends = $script:ValidStorageBackends -join "', '"
            $null = $errors.Add("StorageBackendType '$($Config.StorageBackendType)' is invalid. Valid options: '$validBackends'.")
        }
    }

    # VirtualSwitchType validation
    if ($Config.VirtualSwitchType) {
        $validSwitchTypes = @("SET", "External", "Internal", "Private")
        if ($Config.VirtualSwitchType -notin $validSwitchTypes) {
            $null = $errors.Add("VirtualSwitchType '$($Config.VirtualSwitchType)' is invalid. Valid options: '$($validSwitchTypes -join "', '")'.")
        }
    }

    # CustomVNICs validation
    if ($Config.CustomVNICs) {
        if ($Config.CustomVNICs -isnot [array]) {
            $null = $errors.Add("CustomVNICs must be an array of objects with Name and optional VLAN.")
        } else {
            for ($i = 0; $i -lt $Config.CustomVNICs.Count; $i++) {
                $vnic = $Config.CustomVNICs[$i]
                if (-not $vnic.Name) {
                    $null = $errors.Add("CustomVNICs[$i] is missing required 'Name' field.")
                }
                if ($null -ne $vnic.VLAN) {
                    $vlan = $vnic.VLAN -as [int]
                    if ($null -eq $vlan -or $vlan -lt 1 -or $vlan -gt 4094) {
                        $null = $errors.Add("CustomVNICs[$i] VLAN must be 1-4094 (got '$($vnic.VLAN)').")
                    }
                }
            }
        }
    }

    # DC Promotion pre-flight validation
    if ($Config.PromoteToDC) {
        $promoType = if ($Config.DCPromoType) { $Config.DCPromoType } else { "NewForest" }
        $validPromoTypes = @("NewForest", "AdditionalDC", "RODC")
        if ($promoType -notin $validPromoTypes) {
            $null = $errors.Add("DCPromoType '$promoType' is invalid. Valid options: '$($validPromoTypes -join "', '")'.")
        }
        if ($promoType -eq "NewForest" -and -not $Config.ForestName) {
            $null = $errors.Add("ForestName is required for NewForest DC promotion.")
        }
        if ($promoType -in @("AdditionalDC", "RODC") -and -not $Config.ForestName -and -not $Config.DomainName) {
            $null = $errors.Add("ForestName or DomainName is required for $promoType DC promotion.")
        }
    }

    # HOST mode warnings
    if ($Config.ConfigType -and $Config.ConfigType.ToUpper() -eq "HOST") {
        if (-not $Config.InstallHyperV) {
            $null = $warnings.Add("ConfigType is HOST but InstallHyperV is not enabled.")
        }
        if ($Config.IPAddress -and -not $Config.AdapterName) {
            $null = $warnings.Add("HOST mode with IP config but no AdapterName. Network config will be skipped.")
        }
        if ($Config.CreateSETSwitch -and -not $Config.InstallHyperV) {
            $null = $warnings.Add("CreateSETSwitch requires Hyper-V. SET creation may fail.")
        }
        if ($Config.CustomVNICs -and -not $Config.CreateVirtualSwitch -and -not $Config.CreateSETSwitch) {
            $null = $warnings.Add("CustomVNICs requires a virtual switch. Set CreateVirtualSwitch or CreateSETSwitch to true.")
        }
    }

    # HOST-specific field validation
    if ($Config.SETAdapterMode -and $Config.SETAdapterMode -notin @("auto", "manual")) {
        $null = $errors.Add("SETAdapterMode must be 'auto' or 'manual' (got '$($Config.SETAdapterMode)').")
    }
    if ($null -ne $Config.iSCSIHostNumber -and $Config.iSCSIHostNumber -isnot [bool]) {
        $hostNum = $Config.iSCSIHostNumber -as [int]
        if ($null -eq $hostNum -or $hostNum -lt 1 -or $hostNum -gt 24) {
            $null = $errors.Add("iSCSIHostNumber must be 1-24 or null (got '$($Config.iSCSIHostNumber)').")
        }
    }
    if ($Config.HostStorageDrive) {
        $dl = "$($Config.HostStorageDrive)".ToUpper()
        if ($dl -notmatch '^[A-Z]$' -or $dl -eq 'C') {
            $null = $errors.Add("HostStorageDrive must be a single letter A-Z (not C). Got '$($Config.HostStorageDrive)'.")
        }
    }

    # SMB3 path validation
    if ($Config.StorageBackendType -eq "SMB3" -and $Config.SMB3SharePath) {
        if ($Config.SMB3SharePath -notmatch '^\\\\[^\\]+\\[^\\]+') {
            $null = $errors.Add("SMB3SharePath must be a valid UNC path (e.g., \\\\server\\share). Got '$($Config.SMB3SharePath)'.")
        }
    }

    # DisableBuiltInAdmin without CreateLocalAdmin
    if ($Config.DisableBuiltInAdmin -and -not $Config.CreateLocalAdmin) {
        $null = $warnings.Add("DisableBuiltInAdmin is set without CreateLocalAdmin. Ensure another admin account exists.")
    }

    return @{
        IsValid  = ($errors.Count -eq 0)
        Errors   = @($errors)
        Warnings = @($warnings)
    }
}

# Check for batch mode parameters passed via environment variables or a config file
# This is a simpler approach than full param() block which has issues with functions
function Start-BatchMode {
    param(
        [hashtable]$Config
    )

    # Start transcript for batch mode too
    $null = Start-ScriptTranscript

    # Load environment defaults and custom licenses from defaults.json (no wizard in batch mode)
    Import-Defaults

    Write-OutputColor "" -color "Info"
    Write-OutputColor ("=" * 65) -color "Info"
    Write-OutputColor "  $($script:ToolFullName.ToUpper()) v$($script:ScriptVersion) - BATCH MODE" -color "Info"
    Write-OutputColor ("=" * 65) -color "Info"
    Write-OutputColor "" -color "Info"

    # Validate config before proceeding
    $validation = Test-BatchConfig -Config $Config
    if ($validation.Warnings.Count -gt 0) {
        Write-OutputColor "  WARNINGS:" -color "Warning"
        foreach ($w in $validation.Warnings) {
            Write-OutputColor "    - $w" -color "Warning"
        }
        Write-OutputColor "" -color "Info"
    }
    if (-not $validation.IsValid) {
        Write-OutputColor "  VALIDATION ERRORS:" -color "Error"
        foreach ($e in $validation.Errors) {
            Write-OutputColor "    - $e" -color "Error"
        }
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Batch mode aborted. Fix the errors above and try again." -color "Critical"
        Stop-ScriptTranscript
        return
    }

    $configType = if ($Config.ConfigType) { $Config.ConfigType.ToUpper() } else { "VM" }

    # Dry-run mode detection
    if ($Config.DryRun -eq $true) {
        $script:DryRunMode = $true
        Write-OutputColor "`n  *** DRY RUN MODE ***" -color "Warning"
        Write-OutputColor "  No changes will be made. Actions will be logged only.`n" -color "Warning"
    }

    # Pre-execution summary
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  PLANNED ACTIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $plannedActions = 0
    $plannedSkips = 0

    # Walk each config key and display what will happen
    $summaryItems = @(
        @{ Label = "Hostname";           Active = [bool]$Config.Hostname;           Detail = if ($Config.Hostname) { "Set to '$($Config.Hostname)'" } else { $null } }
        @{ Label = "Network";            Active = [bool]($Config.IPAddress -and $Config.Gateway); Detail = if ($Config.IPAddress) { "$($Config.IPAddress) via $($Config.Gateway)" } else { $null } }
        @{ Label = "Timezone";           Active = [bool]$Config.Timezone;            Detail = $Config.Timezone }
        @{ Label = "RDP";                Active = [bool]$Config.EnableRDP;            Detail = "Enable Remote Desktop" }
        @{ Label = "WinRM";              Active = [bool]$Config.EnableWinRM;          Detail = "Enable PowerShell Remoting" }
        @{ Label = "Firewall";           Active = [bool]$Config.ConfigureFirewall;    Detail = "Domain=Off Private=Off Public=On" }
        @{ Label = "Power Plan";         Active = [bool]$Config.SetPowerPlan;         Detail = $Config.SetPowerPlan }
        @{ Label = "Hyper-V";            Active = [bool]$Config.InstallHyperV;        Detail = "Install Hyper-V role" }
        @{ Label = "MPIO";               Active = [bool]$Config.InstallMPIO;          Detail = "Install Multipath I/O" }
        @{ Label = "Clustering";         Active = [bool]$Config.InstallFailoverClustering; Detail = "Install Failover Clustering" }
        @{ Label = "Local Admin";        Active = [bool]$Config.CreateLocalAdmin;     Detail = if ($Config.LocalAdminName) { "Create '$($Config.LocalAdminName)'" } else { "Create local admin" } }
        @{ Label = "Disable Admin";      Active = [bool]$Config.DisableBuiltInAdmin;  Detail = "Disable built-in Administrator" }
        @{ Label = "Domain Join";        Active = [bool]$Config.DomainName;           Detail = $Config.DomainName }
        @{ Label = "Role Template";      Active = [bool]$Config.ServerRoleTemplate;   Detail = $Config.ServerRoleTemplate }
        @{ Label = "DC Promotion";       Active = [bool]$Config.PromoteToDC;          Detail = if ($Config.DCPromoType) { $Config.DCPromoType } else { "NewForest" } }
        @{ Label = "Windows Updates";    Active = [bool]$Config.InstallUpdates;       Detail = "Install available updates" }
        @{ Label = "Host Storage";       Active = [bool]($Config.InitializeHostStorage -and $configType -eq "HOST"); Detail = if ($Config.HostStorageDrive) { "Drive $($Config.HostStorageDrive):" } else { "Auto-detect drive" } }
        @{ Label = "Virtual Switch";     Active = [bool]($Config.CreateVirtualSwitch -or $Config.CreateSETSwitch); Detail = if ($Config.VirtualSwitchType) { $Config.VirtualSwitchType } else { "SET" } }
        @{ Label = "Custom vNICs";       Active = [bool]($Config.CustomVNICs -and $Config.CustomVNICs.Count -gt 0); Detail = if ($Config.CustomVNICs) { "$($Config.CustomVNICs.Count) vNIC(s)" } else { $null } }
        @{ Label = "Shared Storage";     Active = [bool]($Config.ConfigureSharedStorage -or $Config.ConfigureiSCSI); Detail = if ($Config.StorageBackendType) { $Config.StorageBackendType } else { "iSCSI" } }
        @{ Label = "MPIO Config";        Active = [bool]$Config.ConfigureMPIO;        Detail = "Configure multipath" }
        @{ Label = "Defender";           Active = [bool]$Config.ConfigureDefenderExclusions; Detail = "Add Hyper-V exclusions" }
        @{ Label = "Agent Install";      Active = [bool]($Config.InstallAgents -or $Config.InstallAgent); Detail = "Install monitoring agent" }
        @{ Label = "Cluster Validate";   Active = [bool]$Config.ValidateCluster;      Detail = "Run cluster readiness check" }
    )

    foreach ($item in $summaryItems) {
        if ($item.Active) {
            $line = "  [+] $($item.Label): $($item.Detail)"
            if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($line.PadRight(72))│" -color "Success"
            $plannedActions++
        } else {
            Write-OutputColor "  │$("  [-] $($item.Label): skip".PadRight(72))│" -color "Debug"
            $plannedSkips++
        }
    }

    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  $plannedActions action(s) will be applied, $plannedSkips will be skipped".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not $script:DryRunMode) {
        if (-not (Confirm-UserAction -Message "Proceed with batch configuration?")) {
            Write-OutputColor "  Batch mode cancelled by user." -color "Info"
            Stop-ScriptTranscript
            return
        }
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Config Type: $configType" -color "Info"
    Write-OutputColor "  Started:     $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -color "Info"
    Write-OutputColor "" -color "Info"

    $stepNum = 0
    $totalSteps = 24
    $changesApplied = 0
    $skipped = 0
    $errors = 0
    $script:BatchUndoStack = [System.Collections.Generic.List[object]]::new()
    $batchUndoPath = Join-Path $script:TempPath "batch-undo.json"

    # Check for previous batch session recovery data (skip in dry-run mode)
    if (-not $script:DryRunMode -and (Test-Path -LiteralPath $batchUndoPath)) {
        Write-OutputColor "  Previous batch session recovery data found." -color "Warning"
        Write-OutputColor "  Attempt rollback of previous session? [y/N]: " -color "Warning"
        $recoveryChoice = Read-Host
        if ($recoveryChoice -eq 'y' -or $recoveryChoice -eq 'Y') {
            try {
                $recoveredData = Get-Content -LiteralPath $batchUndoPath -Raw | ConvertFrom-Json
                $recoveredStack = [System.Collections.Generic.List[object]]::new()
                foreach ($item in $recoveredData) {
                    $recoveredStack.Add(@{
                        Step        = $item.Step
                        Description = $item.Description
                        Reversible  = $item.Reversible
                        UndoScript  = [scriptblock]::Create($item.UndoScript)
                    })
                }
                $script:BatchUndoStack = $recoveredStack
                Invoke-BatchUndo
                $script:BatchUndoStack = [System.Collections.Generic.List[object]]::new()
            }
            catch {
                Write-OutputColor "  Failed to recover previous session: $_" -color "Error"
            }
        }
        try {
            Remove-Item -LiteralPath $batchUndoPath -Force -ErrorAction Stop
        }
        catch {
            Write-OutputColor "  Could not remove recovery file: $_" -color "Warning"
        }
    }

    # Helper: persist undo stack to disk for crash recovery
    function Save-BatchUndoState {
        try {
            $serializableStack = @($script:BatchUndoStack | ForEach-Object {
                @{
                    Step        = $_.Step
                    Description = $_.Description
                    Reversible  = $_.Reversible
                    UndoScript  = $_.UndoScript.ToString()
                }
            })
            $serializableStack | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $batchUndoPath -Force -ErrorAction Stop
        }
        catch {
            # Don't break batch execution if persistence fails
        }
    }

    # Step 1: Set hostname
    $stepNum++
    if ($Config.Hostname) {
        if ($env:COMPUTERNAME -eq $Config.Hostname) {
            Write-OutputColor "  [$stepNum/$totalSteps] Hostname: already '$($Config.Hostname)'" -color "Debug"
            $skipped++
        }
        elseif (Test-ValidHostname -Hostname $Config.Hostname) {
            Write-OutputColor "  [$stepNum/$totalSteps] Setting hostname to '$($Config.Hostname)'..." -color "Info"
            if ($script:DryRunMode) {
                Write-OutputColor "           [DRY RUN] Would rename computer to '$($Config.Hostname)'" -color "Info"
                $changesApplied++
            }
            else {
            try {
                $oldHostname = $env:COMPUTERNAME
                Rename-Computer -NewName $Config.Hostname -Force -ErrorAction Stop
                Write-OutputColor "           Hostname set. Reboot required." -color "Success"
                $global:RebootNeeded = $true
                $changesApplied++
                Add-SessionChange -Category "System" -Description "Set hostname to $($Config.Hostname)"
                Clear-MenuCache
                $oldHostnameEsc = $oldHostname -replace "'", "''"
                $script:BatchUndoStack.Add(@{ Step = $stepNum; Description = "Revert hostname to $oldHostname"; Reversible = $true; UndoScript = [scriptblock]::Create("Rename-Computer -NewName '$oldHostnameEsc' -Force") })
                Save-BatchUndoState
            }
            catch {
                Write-OutputColor "           Failed: $_" -color "Error"
                $errors++
            }
            }
        }
        else {
            Write-OutputColor "           Invalid hostname: $($Config.Hostname)" -color "Error"
            $errors++
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Hostname: skipped (not set)" -color "Debug"
    }

    # Step 2: Configure network (skip for HOST mode unless adapter is specified)
    $stepNum++
    $skipNetwork = ($configType -eq "HOST" -and -not $Config.AdapterName)
    if (-not $skipNetwork -and $Config.IPAddress -and $Config.Gateway) {
        $adapterName = if ($Config.AdapterName) { $Config.AdapterName } else { "Ethernet" }
        $cidr = if ($Config.SubnetCIDR) { [int]$Config.SubnetCIDR } else { 24 }

        if ($script:DryRunMode) {
            $dnsInfo = @()
            if ($Config.DNS1) { $dnsInfo += $Config.DNS1 }
            if ($Config.DNS2) { $dnsInfo += $Config.DNS2 }
            Write-OutputColor "  [$stepNum/$totalSteps] Configuring network on '$adapterName'..." -color "Info"
            Write-OutputColor "           [DRY RUN] Would set IP $($Config.IPAddress)/$cidr  GW: $($Config.Gateway)" -color "Info"
            if ($dnsInfo.Count -gt 0) {
                Write-OutputColor "           [DRY RUN] Would set DNS: $($dnsInfo -join ', ')" -color "Info"
            }
            $changesApplied++
        }
        else {
        # Idempotency: check if adapter already has the target IP
        $existingIP = Get-NetIPAddress -InterfaceAlias $adapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -eq $Config.IPAddress -and $_.PrefixLength -eq $cidr }
        if ($existingIP) {
            # IP matches — check if DNS also matches
            $desiredDNS = @()
            if ($Config.DNS1) { $desiredDNS += $Config.DNS1 }
            if ($Config.DNS2) { $desiredDNS += $Config.DNS2 }
            $currentDNS = @((Get-DnsClientServerAddress -InterfaceAlias $adapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses)
            $dnsMatch = ($desiredDNS.Count -eq 0) -or (($null -ne $currentDNS) -and ($desiredDNS.Count -eq $currentDNS.Count) -and (-not (Compare-Object $desiredDNS $currentDNS -SyncWindow 0)))
            if ($dnsMatch) {
                Write-OutputColor "  [$stepNum/$totalSteps] Network: already configured ($($Config.IPAddress)/$cidr)" -color "Debug"
                $skipped++
            }
            else {
                Write-OutputColor "  [$stepNum/$totalSteps] Network: IP matches, updating DNS on '$adapterName'..." -color "Info"
                try {
                    Set-DnsClientServerAddress -InterfaceAlias $adapterName -ServerAddresses $desiredDNS -ErrorAction Stop
                    Write-OutputColor "           DNS servers updated on $adapterName" -color "Success"
                    $changesApplied++
                    Add-SessionChange -Category "Network" -Description "DNS servers updated on $adapterName"
                    Clear-MenuCache
                }
                catch {
                    Write-OutputColor "           Failed to update DNS: $_" -color "Error"
                    $errors++
                }
            }
        }
        else {
            Write-OutputColor "  [$stepNum/$totalSteps] Configuring network on '$adapterName'..." -color "Info"
            try {
                # Validate inputs
                if (-not (Test-ValidIPAddress -IPAddress $Config.IPAddress)) {
                    throw "Invalid IP address: $($Config.IPAddress)"
                }
                if (-not (Test-ValidIPAddress -IPAddress $Config.Gateway)) {
                    throw "Invalid gateway: $($Config.Gateway)"
                }

                # Capture current config for undo
                $oldIP = Get-NetIPAddress -InterfaceAlias $adapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
                $oldGW = (Get-NetRoute -InterfaceAlias $adapterName -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop
                $oldDNS = (Get-DnsClientServerAddress -InterfaceAlias $adapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses

                # Clear existing config
                Remove-NetIPAddress -InterfaceAlias $adapterName -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
                Remove-NetRoute -InterfaceAlias $adapterName -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue

                # Set IP
                New-NetIPAddress -InterfaceAlias $adapterName -IPAddress $Config.IPAddress `
                    -PrefixLength $cidr -DefaultGateway $Config.Gateway -ErrorAction Stop

                # Set DNS
                $dnsServers = @()
                if ($Config.DNS1) { $dnsServers += $Config.DNS1 }
                if ($Config.DNS2) { $dnsServers += $Config.DNS2 }
                if ($dnsServers.Count -gt 0) {
                    Set-DnsClientServerAddress -InterfaceAlias $adapterName -ServerAddresses $dnsServers -ErrorAction Stop
                }

                Write-OutputColor "           IP: $($Config.IPAddress)/$cidr  GW: $($Config.Gateway)" -color "Success"
                if ($dnsServers.Count -gt 0) {
                    Write-OutputColor "           DNS: $($dnsServers -join ', ')" -color "Success"
                }
                $changesApplied++
                Add-SessionChange -Category "Network" -Description "Set IP $($Config.IPAddress)/$cidr on $adapterName"
                Clear-MenuCache

                # Register undo (restore previous IP config)
                $undoAdapter = $adapterName
                $undoAdapterEsc = $undoAdapter -replace "'", "''"
                $undoOldIP = if ($oldIP) { $oldIP.IPAddress } else { $null }
                $undoOldPrefix = if ($oldIP) { $oldIP.PrefixLength } else { 24 }
                $undoOldGW = $oldGW
                $undoOldDNS = $oldDNS
                $script:BatchUndoStack.Add(@{ Step = $stepNum; Description = "Restore network config on $undoAdapter"; Reversible = $true; UndoScript = [scriptblock]::Create("Remove-NetIPAddress -InterfaceAlias '$undoAdapterEsc' -AddressFamily IPv4 -Confirm:`$false -ErrorAction SilentlyContinue; Remove-NetRoute -InterfaceAlias '$undoAdapterEsc' -AddressFamily IPv4 -Confirm:`$false -ErrorAction SilentlyContinue; if ('$undoOldIP') { New-NetIPAddress -InterfaceAlias '$undoAdapterEsc' -IPAddress '$undoOldIP' -PrefixLength $undoOldPrefix $(if($undoOldGW){"-DefaultGateway '$undoOldGW'"}) -ErrorAction SilentlyContinue }") })
                Save-BatchUndoState
            }
            catch {
                Write-OutputColor "           Failed: $_" -color "Error"
                $errors++
            }
        }
        }
    }
    else {
        $reason = if ($skipNetwork) { "HOST mode - configure SET via GUI" } else { "IP/Gateway not set" }
        Write-OutputColor "  [$stepNum/$totalSteps] Network: skipped ($reason)" -color "Debug"
    }

    # Step 3: Set timezone
    $stepNum++
    if ($Config.Timezone) {
        if ((Get-TimeZone).Id -eq $Config.Timezone) {
            Write-OutputColor "  [$stepNum/$totalSteps] Timezone: already '$($Config.Timezone)'" -color "Debug"
            $skipped++
        }
        else {
            Write-OutputColor "  [$stepNum/$totalSteps] Setting timezone to '$($Config.Timezone)'..." -color "Info"
            if ($script:DryRunMode) {
                Write-OutputColor "           [DRY RUN] Would set timezone to '$($Config.Timezone)'" -color "Info"
                $changesApplied++
            }
            else {
            try {
                $oldTimezone = (Get-TimeZone).Id
                Microsoft.PowerShell.Management\Set-TimeZone -Id $Config.Timezone -ErrorAction Stop
                Write-OutputColor "           Timezone set." -color "Success"
                $changesApplied++
                Add-SessionChange -Category "System" -Description "Set timezone to $($Config.Timezone)"
                Clear-MenuCache
                $oldTimezoneEsc = $oldTimezone -replace "'", "''"
                $script:BatchUndoStack.Add(@{ Step = $stepNum; Description = "Revert timezone to $oldTimezone"; Reversible = $true; UndoScript = [scriptblock]::Create("Microsoft.PowerShell.Management\Set-TimeZone -Id '$oldTimezoneEsc'") })
                Save-BatchUndoState
            }
            catch {
                Write-OutputColor "           Failed: $_" -color "Error"
                $errors++
            }
            }
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Timezone: skipped" -color "Debug"
    }

    # Step 4: Enable RDP
    $stepNum++
    if ($Config.EnableRDP) {
        $rdpValue = (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -ErrorAction SilentlyContinue).fDenyTSConnections
        if ($rdpValue -eq 0) {
            Write-OutputColor "  [$stepNum/$totalSteps] RDP: already enabled" -color "Debug"
            $skipped++
        }
        else {
            Write-OutputColor "  [$stepNum/$totalSteps] Enabling Remote Desktop..." -color "Info"
            if ($script:DryRunMode) {
                Write-OutputColor "           [DRY RUN] Would enable RDP and firewall rule" -color "Info"
                $changesApplied++
            }
            else {
            try {
                Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -ErrorAction Stop
                Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
                Write-OutputColor "           RDP enabled." -color "Success"
                $changesApplied++
                Add-SessionChange -Category "System" -Description "Enabled RDP"
                Clear-MenuCache
                $script:BatchUndoStack.Add(@{ Step = $stepNum; Description = "Disable RDP"; Reversible = $true; UndoScript = [scriptblock]::Create("Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 1; Disable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue") })
                Save-BatchUndoState
            }
            catch {
                Write-OutputColor "           Failed: $_" -color "Error"
                $errors++
            }
            }
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] RDP: skipped" -color "Debug"
    }

    # Step 5: Enable WinRM
    $stepNum++
    if ($Config.EnableWinRM) {
        $winrmSvc = Get-Service -Name WinRM -ErrorAction SilentlyContinue
        if ($winrmSvc -and $winrmSvc.Status -eq "Running") {
            Write-OutputColor "  [$stepNum/$totalSteps] WinRM: already enabled" -color "Debug"
            $skipped++
        }
        else {
            Write-OutputColor "  [$stepNum/$totalSteps] Enabling PowerShell Remoting..." -color "Info"
            if ($script:DryRunMode) {
                Write-OutputColor "           [DRY RUN] Would enable WinRM with Kerberos auth" -color "Info"
                $changesApplied++
            }
            else {
            try {
                Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction Stop
                Set-Item WSMan:\localhost\Service\Auth\Kerberos -Value $true -ErrorAction SilentlyContinue
                Write-OutputColor "           WinRM enabled with Kerberos auth." -color "Success"
                $changesApplied++
                Add-SessionChange -Category "System" -Description "Enabled PowerShell Remoting"
                Clear-MenuCache
                $script:BatchUndoStack.Add(@{ Step = $stepNum; Description = "Disable WinRM"; Reversible = $true; UndoScript = [scriptblock]::Create("Disable-PSRemoting -Force -ErrorAction SilentlyContinue; Stop-Service WinRM -Force -ErrorAction SilentlyContinue") })
                Save-BatchUndoState
            }
            catch {
                Write-OutputColor "           Failed: $_" -color "Error"
                $errors++
            }
            }
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] WinRM: skipped" -color "Debug"
    }

    # Step 6: Configure firewall
    $stepNum++
    if ($Config.ConfigureFirewall) {
        $fwState = Get-FirewallState
        if ($null -ne $fwState -and $fwState.Domain -eq "Disabled" -and $fwState.Private -eq "Disabled" -and $fwState.Public -eq "Enabled") {
            Write-OutputColor "  [$stepNum/$totalSteps] Firewall: already configured (Domain=Off Private=Off Public=On)" -color "Debug"
            $skipped++
        }
        else {
            Write-OutputColor "  [$stepNum/$totalSteps] Configuring firewall..." -color "Info"
            if ($script:DryRunMode) {
                Write-OutputColor "           [DRY RUN] Would set firewall: Domain=Off Private=Off Public=On" -color "Info"
                $changesApplied++
            }
            else {
            try {
                $oldDomain = $fwState.Domain
                $oldPrivate = $fwState.Private
                $oldPublic = $fwState.Public
                Set-NetFirewallProfile -Profile Domain -Enabled False -ErrorAction Stop
                Set-NetFirewallProfile -Profile Private -Enabled False -ErrorAction Stop
                Set-NetFirewallProfile -Profile Public -Enabled True -ErrorAction Stop
                Write-OutputColor "           Firewall: Domain=Off Private=Off Public=On" -color "Success"
                $changesApplied++
                Add-SessionChange -Category "Security" -Description "Configured firewall profiles"
                Clear-MenuCache
                $undoDomain = if ($oldDomain -eq "Enabled") { "True" } else { "False" }
                $undoPrivate = if ($oldPrivate -eq "Enabled") { "True" } else { "False" }
                $undoPublic = if ($oldPublic -eq "Enabled") { "True" } else { "False" }
                $script:BatchUndoStack.Add(@{ Step = $stepNum; Description = "Restore firewall profiles"; Reversible = $true; UndoScript = [scriptblock]::Create("Set-NetFirewallProfile -Profile Domain -Enabled $undoDomain; Set-NetFirewallProfile -Profile Private -Enabled $undoPrivate; Set-NetFirewallProfile -Profile Public -Enabled $undoPublic") })
                Save-BatchUndoState
            }
            catch {
                Write-OutputColor "           Failed: $_" -color "Error"
                $errors++
            }
            }
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Firewall: skipped" -color "Debug"
    }

    # Step 7: Set power plan
    $stepNum++
    if ($Config.SetPowerPlan) {
        if ($script:PowerPlanGUID.ContainsKey($Config.SetPowerPlan)) {
            $currentPlan = Get-CurrentPowerPlan
            if ($currentPlan.Name -eq $Config.SetPowerPlan) {
                Write-OutputColor "  [$stepNum/$totalSteps] Power plan: already '$($Config.SetPowerPlan)'" -color "Debug"
                $skipped++
            }
            else {
                Write-OutputColor "  [$stepNum/$totalSteps] Setting power plan to '$($Config.SetPowerPlan)'..." -color "Info"
                if ($script:DryRunMode) {
                    Write-OutputColor "           [DRY RUN] Would set power plan to '$($Config.SetPowerPlan)'" -color "Info"
                    $changesApplied++
                }
                else {
                $oldPlanGuid = $currentPlan.Guid
                powercfg /setactive $script:PowerPlanGUID[$Config.SetPowerPlan] 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Write-OutputColor "           Failed to set power plan (exit code $LASTEXITCODE)." -color "Warning"
                    $skipped++
                } else {
                    Write-OutputColor "           Power plan set." -color "Success"
                    $changesApplied++
                    Add-SessionChange -Category "System" -Description "Set power plan to $($Config.SetPowerPlan)"
                    Clear-MenuCache
                    $oldPlanGuidEsc = $oldPlanGuid -replace "'", "''"
                    $script:BatchUndoStack.Add(@{ Step = $stepNum; Description = "Revert power plan to $($currentPlan.Name)"; Reversible = $true; UndoScript = [scriptblock]::Create("powercfg /setactive '$oldPlanGuidEsc' 2>&1 | Out-Null") })
                    Save-BatchUndoState
                }
                }
            }
        }
        else {
            Write-OutputColor "  [$stepNum/$totalSteps] Power plan: unknown '$($Config.SetPowerPlan)'" -color "Warning"
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Power plan: skipped" -color "Debug"
    }

    # Step 8: Install Hyper-V
    $stepNum++
    if ($Config.InstallHyperV -and -not (Test-HyperVInstalled)) {
        if (-not (Test-WindowsServer)) {
            Write-OutputColor "  [$stepNum/$totalSteps] Hyper-V: skipped (requires Windows Server)" -color "Error"
            $errors++
        } else {
            Write-OutputColor "  [$stepNum/$totalSteps] Installing Hyper-V..." -color "Info"
            if ($script:DryRunMode) {
                Write-OutputColor "           [DRY RUN] Would install Hyper-V role with management tools" -color "Info"
                $changesApplied++
            }
            else {
            try {
                Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -ErrorAction Stop
                Write-OutputColor "           Hyper-V installed. Reboot required." -color "Success"
                $global:RebootNeeded = $true
                $changesApplied++
                Add-SessionChange -Category "System" -Description "Installed Hyper-V"
                Clear-MenuCache
            }
            catch {
                Write-OutputColor "           Failed: $_" -color "Error"
                $errors++
            }
            }
        }
    }
    else {
        $reason = if (Test-HyperVInstalled) { "already installed" } else { "not requested" }
        Write-OutputColor "  [$stepNum/$totalSteps] Hyper-V: skipped ($reason)" -color "Debug"
    }

    # Step 9: Install MPIO
    $stepNum++
    if ($Config.InstallMPIO -and -not (Test-MPIOInstalled)) {
        if (-not (Test-WindowsServer)) {
            Write-OutputColor "  [$stepNum/$totalSteps] MPIO: skipped (requires Windows Server)" -color "Error"
            $errors++
        } else {
            Write-OutputColor "  [$stepNum/$totalSteps] Installing MPIO..." -color "Info"
            if ($script:DryRunMode) {
                Write-OutputColor "           [DRY RUN] Would install Multipath I/O feature" -color "Info"
                $changesApplied++
            }
            else {
            try {
                Install-WindowsFeature -Name Multipath-IO -ErrorAction Stop
                Write-OutputColor "           MPIO installed. Reboot required." -color "Success"
                $global:RebootNeeded = $true
                $changesApplied++
                Add-SessionChange -Category "System" -Description "Installed MPIO"
                Clear-MenuCache
            }
            catch {
                Write-OutputColor "           Failed: $_" -color "Error"
                $errors++
            }
            }
        }
    }
    else {
        $reason = if ($Config.InstallMPIO -and (Test-MPIOInstalled)) { "already installed" } else { "not requested" }
        Write-OutputColor "  [$stepNum/$totalSteps] MPIO: skipped ($reason)" -color "Debug"
    }

    # Step 10: Install Failover Clustering
    $stepNum++
    if ($Config.InstallFailoverClustering -and -not (Test-FailoverClusteringInstalled)) {
        if (-not (Test-WindowsServer)) {
            Write-OutputColor "  [$stepNum/$totalSteps] Failover Clustering: skipped (requires Windows Server)" -color "Error"
            $errors++
        } else {
            Write-OutputColor "  [$stepNum/$totalSteps] Installing Failover Clustering..." -color "Info"
            if ($script:DryRunMode) {
                Write-OutputColor "           [DRY RUN] Would install Failover Clustering with management tools" -color "Info"
                $changesApplied++
            }
            else {
            try {
                Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools -ErrorAction Stop
                Write-OutputColor "           Failover Clustering installed. Reboot required." -color "Success"
                $global:RebootNeeded = $true
                $changesApplied++
                Add-SessionChange -Category "System" -Description "Installed Failover Clustering"
                Clear-MenuCache
            }
            catch {
                Write-OutputColor "           Failed: $_" -color "Error"
                $errors++
            }
            }
        }
    }
    else {
        $reason = if ($Config.InstallFailoverClustering -and (Test-FailoverClusteringInstalled)) { "already installed" } else { "not requested" }
        Write-OutputColor "  [$stepNum/$totalSteps] Failover Clustering: skipped ($reason)" -color "Debug"
    }

    # Step 11: Create local admin account
    $stepNum++
    if ($Config.CreateLocalAdmin) {
        $adminName = if ($Config.LocalAdminName) { $Config.LocalAdminName } else { $script:localadminaccountname }
        Write-OutputColor "  [$stepNum/$totalSteps] Creating local admin '$adminName'..." -color "Info"
        if ($script:DryRunMode) {
            Write-OutputColor "           [DRY RUN] Would create local admin '$adminName' and add to Administrators" -color "Info"
            $changesApplied++
        }
        else {
        try {
            $existingUser = Get-LocalUser -Name $adminName -ErrorAction SilentlyContinue
            if ($existingUser) {
                Write-OutputColor "           Account '$adminName' already exists." -color "Warning"
            } else {
                $securePassword = Read-Host -Prompt "           Enter password for $adminName" -AsSecureString
                New-LocalUser -Name $adminName -Password $securePassword -FullName $adminName -Description "Local Admin" -PasswordNeverExpires -ErrorAction Stop | Out-Null
                Add-LocalGroupMember -Group "Administrators" -Member $adminName -ErrorAction Stop
                Write-OutputColor "           Local admin '$adminName' created and added to Administrators." -color "Success"
                $changesApplied++
                Add-SessionChange -Category "Security" -Description "Created local admin account '$adminName'"
                Clear-MenuCache
                $undoAdminNameEsc = $adminName -replace "'", "''"
                $script:BatchUndoStack.Add(@{ Step = $stepNum; Description = "Remove local admin '$adminName'"; Reversible = $true; UndoScript = [scriptblock]::Create("Remove-LocalUser -Name '$undoAdminNameEsc' -ErrorAction SilentlyContinue") })
                Save-BatchUndoState
            }
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Local admin: skipped" -color "Debug"
    }

    # Step 12: Disable built-in Administrator
    $stepNum++
    if ($Config.DisableBuiltInAdmin) {
        Write-OutputColor "  [$stepNum/$totalSteps] Disabling built-in Administrator..." -color "Info"
        if ($script:DryRunMode) {
            Write-OutputColor "           [DRY RUN] Would disable built-in Administrator account" -color "Info"
            $changesApplied++
        }
        else {
        try {
            $builtInAdmin = Get-LocalUser -Name "Administrator" -ErrorAction Stop
            if ($builtInAdmin.Enabled) {
                Disable-LocalUser -Name "Administrator" -ErrorAction Stop
                Write-OutputColor "           Built-in Administrator disabled." -color "Success"
                $changesApplied++
                Add-SessionChange -Category "Security" -Description "Disabled built-in Administrator account"
                Clear-MenuCache
            } else {
                Write-OutputColor "           Already disabled." -color "Debug"
            }
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Disable built-in admin: skipped" -color "Debug"
    }

    # Step 13: Join domain (prompts for credentials - do near end)
    $stepNum++
    $csCim = Invoke-WithTimeout -ScriptBlock {
        Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    } -TimeoutSeconds 10 -Activity "Checking domain status"
    $csInfo = if ($csCim.TimedOut) { $null } else { $csCim.Result }
    $isDomainJoined = if ($null -ne $csInfo) { $csInfo.PartOfDomain } else { $false }
    if ($Config.DomainName -and -not $isDomainJoined) {
        Write-OutputColor "  [$stepNum/$totalSteps] Joining domain '$($Config.DomainName)'..." -color "Info"
        if ($script:DryRunMode) {
            Write-OutputColor "           [DRY RUN] Would join domain '$($Config.DomainName)'" -color "Info"
            $changesApplied++
        }
        else {
        try {
            $domainCred = Get-Credential -Message "Enter credentials to join $($Config.DomainName)"
            if ($domainCred) {
                Add-Computer -DomainName $Config.DomainName -Credential $domainCred -Force -ErrorAction Stop
                Write-OutputColor "           Joined domain. Reboot required." -color "Success"
                $global:RebootNeeded = $true
                $changesApplied++
                Add-SessionChange -Category "System" -Description "Joined domain $($Config.DomainName)"
                Clear-MenuCache
            }
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
        }
    }
    else {
        $reason = if ($isDomainJoined) { "already joined" } else { "not specified" }
        Write-OutputColor "  [$stepNum/$totalSteps] Domain join: skipped ($reason)" -color "Debug"
    }

    # Step 14: Install Server Role Template
    $stepNum++
    if ($Config.ServerRoleTemplate) {
        $templateKey = $Config.ServerRoleTemplate.ToUpper()
        $allTemplates = if ($script:ServerRoleTemplates) { $script:ServerRoleTemplates } else { @{} }
        if ($script:CustomRoleTemplates) {
            foreach ($k in $script:CustomRoleTemplates.Keys) { $allTemplates[$k] = $script:CustomRoleTemplates[$k] }
        }
        if ($allTemplates.ContainsKey($templateKey)) {
            $template = $allTemplates[$templateKey]
            Write-OutputColor "  [$stepNum/$totalSteps] Installing role template: $($template.FullName)..." -color "Info"
            if ($script:DryRunMode) {
                Write-OutputColor "           [DRY RUN] Would install role template '$($template.FullName)' ($($template.Features.Count) feature(s))" -color "Info"
                $changesApplied++
            }
            else {
            try {
                $installCount = 0
                # Pre-fetch all feature states once (avoids N+1 Get-WindowsFeature calls per feature)
                $installedFeatures = @(Get-WindowsFeature -Name $template.Features -ErrorAction SilentlyContinue | Where-Object { $_.Installed })
                $installedNames = @($installedFeatures | ForEach-Object { $_.Name })
                foreach ($featureName in $template.Features) {
                    if ($featureName -notin $installedNames) {
                        $null = Install-WindowsFeature -Name $featureName -IncludeManagementTools -ErrorAction Stop
                        $installCount++
                    }
                }
                Write-OutputColor "           Installed $installCount feature(s) for $($template.FullName)." -color "Success"
                if ($template.RequiresReboot -and $installCount -gt 0) {
                    $global:RebootNeeded = $true
                }
                $changesApplied++
                Add-SessionChange -Category "Roles" -Description "Installed role template: $($template.FullName)"
                Clear-MenuCache
            }
            catch {
                Write-OutputColor "           Failed: $_" -color "Error"
                $errors++
            }
            }
        } else {
            Write-OutputColor "  [$stepNum/$totalSteps] Role template '$templateKey' not found. Available: $($allTemplates.Keys -join ', ')" -color "Warning"
            $errors++
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Server role template: skipped" -color "Debug"
    }

    # Step 15: Promote to Domain Controller
    $stepNum++
    if ($Config.PromoteToDC) {
        $dcCim = Invoke-WithTimeout -ScriptBlock {
            Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        } -TimeoutSeconds 10 -Activity "Checking domain role"
        $domainRole = if ($dcCim.TimedOut) { $null } else { $dcCim.Result.DomainRole }
        if ($domainRole -ge 4) {
            Write-OutputColor "  [$stepNum/$totalSteps] DC Promotion: already a domain controller" -color "Debug"
            $skipped++
        }
        else {
        $promoType = if ($Config.DCPromoType) { $Config.DCPromoType } else { "NewForest" }
        Write-OutputColor "  [$stepNum/$totalSteps] DC Promotion ($promoType)..." -color "Info"
        if ($script:DryRunMode) {
            $dcDetail = if ($Config.ForestName) { $Config.ForestName } elseif ($Config.DomainName) { $Config.DomainName } else { "unspecified" }
            Write-OutputColor "           [DRY RUN] Would promote to DC ($promoType) for '$dcDetail'" -color "Info"
            $changesApplied++
        }
        else {
        try {
            # Ensure AD DS role is installed
            $addsFeature = Get-WindowsFeature -Name AD-Domain-Services -ErrorAction SilentlyContinue
            if ($null -eq $addsFeature -or -not $addsFeature.Installed) {
                Write-OutputColor "           Installing AD DS role first..." -color "Info"
                $null = Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -ErrorAction Stop
            }
            Import-Module ADDSDeployment -ErrorAction Stop
            # Prompt for DSRM password (cannot be stored in config for security)
            $dsrmPassword = Read-Host -Prompt "           Enter Safe Mode (DSRM) password" -AsSecureString
            $forestMode = if ($Config.ForestMode) { $Config.ForestMode } else { "WinThreshold" }
            $domainMode = if ($Config.DomainMode) { $Config.DomainMode } else { "WinThreshold" }
            switch ($promoType) {
                "NewForest" {
                    if (-not $Config.ForestName) {
                        Write-OutputColor "           ForestName is required for NewForest promotion." -color "Error"
                        $errors++
                    } else {
                        $netbios = ($Config.ForestName -split '\.')[0].ToUpper()
                        $null = Install-ADDSForest -DomainName $Config.ForestName -ForestMode $forestMode -DomainMode $domainMode -DomainNetbiosName $netbios -SafeModeAdministratorPassword $dsrmPassword -InstallDns:$true -CreateDnsDelegation:$false -NoRebootOnCompletion:$true -Force:$true -ErrorAction Stop
                        Write-OutputColor "           New forest '$($Config.ForestName)' configured. Reboot required." -color "Success"
                        $global:RebootNeeded = $true
                        $changesApplied++
                        Add-SessionChange -Category "AD DS" -Description "Promoted to DC: New forest $($Config.ForestName)"
                        Clear-MenuCache
                    }
                }
                "AdditionalDC" {
                    $domainName = if ($Config.ForestName) { $Config.ForestName } elseif ($Config.DomainName) { $Config.DomainName } else { $null }
                    if (-not $domainName) {
                        Write-OutputColor "           ForestName or DomainName required for AdditionalDC." -color "Error"
                        $errors++
                    } else {
                        $domainCred = Get-Credential -Message "Enter domain admin credentials for $domainName"
                        $null = Install-ADDSDomainController -DomainName $domainName -Credential $domainCred -SafeModeAdministratorPassword $dsrmPassword -InstallDns:$true -NoRebootOnCompletion:$true -Force:$true -ErrorAction Stop
                        Write-OutputColor "           Additional DC for '$domainName' configured. Reboot required." -color "Success"
                        $global:RebootNeeded = $true
                        $changesApplied++
                        Add-SessionChange -Category "AD DS" -Description "Promoted to additional DC: $domainName"
                        Clear-MenuCache
                    }
                }
                "RODC" {
                    $domainName = if ($Config.ForestName) { $Config.ForestName } elseif ($Config.DomainName) { $Config.DomainName } else { $null }
                    if (-not $domainName) {
                        Write-OutputColor "           ForestName or DomainName required for RODC." -color "Error"
                        $errors++
                    } else {
                        $domainCred = Get-Credential -Message "Enter domain admin credentials for $domainName"
                        $null = Install-ADDSDomainController -DomainName $domainName -Credential $domainCred -ReadOnlyReplica:$true -SafeModeAdministratorPassword $dsrmPassword -InstallDns:$true -NoRebootOnCompletion:$true -Force:$true -ErrorAction Stop
                        Write-OutputColor "           RODC for '$domainName' configured. Reboot required." -color "Success"
                        $global:RebootNeeded = $true
                        $changesApplied++
                        Add-SessionChange -Category "AD DS" -Description "Promoted to RODC: $domainName"
                        Clear-MenuCache
                    }
                }
                default {
                    Write-OutputColor "           Unknown DCPromoType: $promoType" -color "Error"
                    $errors++
                }
            }
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
        }
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] DC Promotion: skipped" -color "Debug"
    }

    # Step 16: Install updates (long running - always last)
    $stepNum++
    if ($Config.InstallUpdates) {
        Write-OutputColor "  [$stepNum/$totalSteps] Installing Windows Updates (this may take a while)..." -color "Info"
        if ($script:DryRunMode) {
            Write-OutputColor "           [DRY RUN] Would install available Windows Updates" -color "Info"
            $changesApplied++
        }
        else {
        try {
            Install-WindowsUpdates
            $changesApplied++
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Windows Updates: skipped" -color "Debug"
    }

    # Step 17: Initialize Host Storage
    $stepNum++
    if ($Config.InitializeHostStorage -and $configType -eq "HOST") {
        # Idempotency: check if storage directories already exist on the target drive
        $checkDrive = $Config.HostStorageDrive
        if (-not $checkDrive) {
            $autoVol = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveLetter -ne 'C' -and $_.DriveType -eq 'Fixed' -and $_.FileSystem -eq 'NTFS' } | Select-Object -First 1
            if ($autoVol) { $checkDrive = $autoVol.DriveLetter }
        }
        $storageAlready = $false
        if ($checkDrive) {
            $checkPaths = @("$($checkDrive):\Virtual Machines", "$($checkDrive):\ISOs", "$($checkDrive):\Virtual Machines\_BaseImages")
            $storageAlready = @($checkPaths | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 3
        }
        if ($storageAlready) {
            Write-OutputColor "  [$stepNum/$totalSteps] Host storage: already initialized on $($checkDrive):" -color "Debug"
            $script:SelectedHostDrive = "$($checkDrive):"
            $script:StorageInitialized = $true
            $skipped++
        }
        else {
        Write-OutputColor "  [$stepNum/$totalSteps] Initializing host storage..." -color "Info"
        if ($script:DryRunMode) {
            $driveInfo = if ($Config.HostStorageDrive) { "$($Config.HostStorageDrive):" } else { "auto-detect" }
            Write-OutputColor "           [DRY RUN] Would initialize host storage on $driveInfo" -color "Info"
            $changesApplied++
        }
        else {
        try {
            $driveLetter = $Config.HostStorageDrive
            if (-not $driveLetter) {
                # Auto-select first available non-C fixed NTFS drive
                $autoVol = Get-Volume -ErrorAction SilentlyContinue | Where-Object {
                    $_.DriveLetter -and $_.DriveLetter -ne 'C' -and $_.DriveType -eq 'Fixed' -and $_.FileSystem -eq 'NTFS'
                } | Select-Object -First 1
                if ($autoVol) { $driveLetter = $autoVol.DriveLetter }
            }
            if ($driveLetter) {
                $script:SelectedHostDrive = "$($driveLetter):"
                $script:HostVMStoragePath = "$($driveLetter):\Virtual Machines"
                $script:HostISOPath = "$($driveLetter):\ISOs"
                $script:VHDCachePath = "$($driveLetter):\Virtual Machines\_BaseImages"
                foreach ($folder in @($script:HostVMStoragePath, $script:HostISOPath, $script:VHDCachePath)) {
                    if (-not (Test-Path -LiteralPath $folder)) {
                        New-Item -Path $folder -ItemType Directory -Force | Out-Null
                    }
                }
                # Set Hyper-V defaults if available
                $vmHost = Get-VMHost -ErrorAction SilentlyContinue
                if ($vmHost) {
                    Set-VMHost -VirtualMachinePath $script:HostVMStoragePath -ErrorAction SilentlyContinue
                    Set-VMHost -VirtualHardDiskPath $script:HostVMStoragePath -ErrorAction SilentlyContinue
                }
                Update-DefenderVMPaths
                $script:StorageInitialized = $true
                Write-OutputColor "           Storage initialized on $($driveLetter):" -color "Success"
                $changesApplied++
                Add-SessionChange -Category "Host Storage" -Description "Initialized $($driveLetter): for VM storage"
                Clear-MenuCache
            } else {
                Write-OutputColor "           No suitable data drive found." -color "Warning"
            }
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
        }
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Host storage: skipped" -color "Debug"
    }

    # Step 18: Create Virtual Switch (SET, External, Internal, or Private)
    # Backward compat: CreateSETSwitch maps to CreateVirtualSwitch + VirtualSwitchType=SET
    $stepNum++
    $createSwitch = $Config.CreateVirtualSwitch -or $Config.CreateSETSwitch
    $vSwitchType = if ($Config.VirtualSwitchType) { $Config.VirtualSwitchType } else { "SET" }
    $vSwitchName = if ($Config.VirtualSwitchName) { $Config.VirtualSwitchName }
                   elseif ($Config.SETSwitchName) { $Config.SETSwitchName }
                   else { $SwitchName }

    if ($createSwitch -and $configType -eq "HOST") {
        $existingSwitch = Get-VMSwitch -Name $vSwitchName -ErrorAction SilentlyContinue
        if ($existingSwitch) {
            Write-OutputColor "  [$stepNum/$totalSteps] Virtual switch: '$vSwitchName' already exists ($($existingSwitch.SwitchType))" -color "Debug"
            $skipped++
        }
        else {
        Write-OutputColor "  [$stepNum/$totalSteps] Creating $vSwitchType switch '$vSwitchName'..." -color "Info"
        if ($script:DryRunMode) {
            Write-OutputColor "           [DRY RUN] Would create $vSwitchType virtual switch '$vSwitchName'" -color "Info"
            $changesApplied++
        }
        else {
        try {
            switch ($vSwitchType) {
                "SET" {
                    $mgmtName = if ($Config.SETManagementName) { $Config.SETManagementName } else { $ManagementName }
                    $internetAdapters = @(Test-AdapterInternetConnectivity | Where-Object { $_.HasInternet })
                    if ($internetAdapters.Count -ge 1) {
                        $adapterNames = @($internetAdapters | ForEach-Object { $_.Name })
                        New-VMSwitch -Name $vSwitchName -NetAdapterName $adapterNames -EnableEmbeddedTeaming $true -AllowManagementOS $true -ErrorAction Stop
                        Set-VMSwitchTeam -Name $vSwitchName -LoadBalancingAlgorithm Dynamic -ErrorAction SilentlyContinue
                        for ($wait = 0; $wait -lt 15; $wait++) {
                            $vnic = Get-VMNetworkAdapter -ManagementOS -Name $vSwitchName -ErrorAction SilentlyContinue
                            if ($vnic) { break }
                            Start-Sleep -Seconds 1
                        }
                        Rename-VMNetworkAdapter -ManagementOS -Name $vSwitchName -NewName $mgmtName -ErrorAction SilentlyContinue
                        $script:iSCSICandidateAdapters = @(Test-AdapterInternetConnectivity | Where-Object { -not $_.HasInternet })
                        Write-OutputColor "           SET '$vSwitchName' created with $($adapterNames.Count) adapter(s)." -color "Success"
                        $changesApplied++
                        Add-SessionChange -Category "Network" -Description "Created SET '$vSwitchName'"
                        Clear-MenuCache
                    } else {
                        Write-OutputColor "           No adapters with internet found for SET." -color "Warning"
                    }
                }
                "External" {
                    $adapterName = $Config.VirtualSwitchAdapter
                    if (-not $adapterName) {
                        $firstAdapter = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq "Up" -and $_.Name -notlike "vEthernet*" } | Select-Object -First 1
                        if ($firstAdapter) { $adapterName = $firstAdapter.Name }
                    }
                    if ($adapterName) {
                        New-VMSwitch -Name $vSwitchName -NetAdapterName $adapterName -AllowManagementOS $true -ErrorAction Stop
                        for ($wait = 0; $wait -lt 15; $wait++) {
                            $vnic = Get-VMNetworkAdapter -ManagementOS -Name $vSwitchName -ErrorAction SilentlyContinue
                            if ($vnic) { break }
                            Start-Sleep -Seconds 1
                        }
                        Rename-VMNetworkAdapter -ManagementOS -Name $vSwitchName -NewName "Management" -ErrorAction SilentlyContinue
                        Write-OutputColor "           External switch '$vSwitchName' created on '$adapterName'." -color "Success"
                        $changesApplied++
                        Add-SessionChange -Category "Network" -Description "Created External switch '$vSwitchName'"
                        Clear-MenuCache
                    } else {
                        Write-OutputColor "           No physical adapter found for External switch." -color "Warning"
                    }
                }
                "Internal" {
                    New-VMSwitch -Name $vSwitchName -SwitchType Internal -ErrorAction Stop
                    Write-OutputColor "           Internal switch '$vSwitchName' created." -color "Success"
                    $changesApplied++
                    Add-SessionChange -Category "Network" -Description "Created Internal switch '$vSwitchName'"
                    Clear-MenuCache
                }
                "Private" {
                    New-VMSwitch -Name $vSwitchName -SwitchType Private -ErrorAction Stop
                    Write-OutputColor "           Private switch '$vSwitchName' created." -color "Success"
                    $changesApplied++
                    Add-SessionChange -Category "Network" -Description "Created Private switch '$vSwitchName'"
                    Clear-MenuCache
                }
                default {
                    Write-OutputColor "           Unknown switch type '$vSwitchType'." -color "Warning"
                }
            }
            if ($vSwitchType -in "External","Internal","Private") {
                $undoSwitchNameEsc = $vSwitchName -replace "'", "''"
                $script:BatchUndoStack.Add(@{ Step = $stepNum; Description = "Remove virtual switch '$vSwitchName'"; Reversible = $true; UndoScript = [scriptblock]::Create("Remove-VMSwitch -Name '$undoSwitchNameEsc' -Force -ErrorAction SilentlyContinue") })
                Save-BatchUndoState
            }
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
        }
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Virtual switch: skipped" -color "Debug"
    }

    # Step 19: Create Custom vNICs on External/SET switch
    $stepNum++
    if ($Config.CustomVNICs -and $Config.CustomVNICs.Count -gt 0 -and $configType -eq "HOST") {
        Write-OutputColor "  [$stepNum/$totalSteps] Creating custom vNICs..." -color "Info"
        if ($script:DryRunMode) {
            Write-OutputColor "           [DRY RUN] Would create $($Config.CustomVNICs.Count) custom vNIC(s)" -color "Info"
            foreach ($vnicDef in $Config.CustomVNICs) {
                $vnicDetail = $vnicDef.Name
                if ($null -ne $vnicDef.VLAN) { $vnicDetail += " (VLAN $($vnicDef.VLAN))" }
                Write-OutputColor "           [DRY RUN]   - $vnicDetail" -color "Info"
            }
            $changesApplied++
        }
        else {
        try {
            $targetSwitch = Get-VMSwitch -ErrorAction SilentlyContinue | Where-Object { $_.SwitchType -eq "External" } | Select-Object -First 1
            if ($targetSwitch) {
                $vnicCount = 0
                $vnicSkipped = 0
                $createdVnicNames = @()
                foreach ($vnicDef in $Config.CustomVNICs) {
                    $vnicName = $vnicDef.Name
                    if (-not $vnicName) { continue }

                    # Idempotency: skip if vNIC already exists on the target switch
                    $existing = Get-VMNetworkAdapter -ManagementOS -SwitchName $targetSwitch.Name -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $vnicName }
                    if ($existing) {
                        $vnicSkipped++
                        continue
                    }

                    Add-VMNetworkAdapter -ManagementOS -SwitchName $targetSwitch.Name -Name $vnicName -ErrorAction Stop

                    $vlanId = $vnicDef.VLAN -as [int]
                    if ($null -ne $vlanId -and $vlanId -ge 1 -and $vlanId -le 4094) {
                        Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $vnicName -Access -VlanId $vlanId -ErrorAction SilentlyContinue
                    }
                    $vnicCount++
                    $createdVnicNames += $vnicName
                }
                if ($vnicCount -gt 0) {
                    Write-OutputColor "           Created $vnicCount custom vNIC(s) on '$($targetSwitch.Name)'$(if ($vnicSkipped -gt 0) { ", $vnicSkipped already existed" })." -color "Success"
                    $changesApplied++
                    Add-SessionChange -Category "Network" -Description "Created $vnicCount custom vNIC(s) on '$($targetSwitch.Name)'"
                    Clear-MenuCache
                    foreach ($createdName in $createdVnicNames) {
                        $createdNameEsc = $createdName -replace "'", "''"
                        $script:BatchUndoStack.Add(@{ Step = $stepNum; Description = "Remove vNIC '$createdName'"; Reversible = $true; UndoScript = [scriptblock]::Create("Remove-VMNetworkAdapter -ManagementOS -Name '$createdNameEsc' -ErrorAction SilentlyContinue") })
                    }
                    Save-BatchUndoState
                }
                else {
                    Write-OutputColor "           All $vnicSkipped vNIC(s) already exist." -color "Debug"
                    $skipped++
                }
            } else {
                Write-OutputColor "           No External switch found. Create a switch first." -color "Warning"
            }
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Custom vNICs: skipped" -color "Debug"
    }

    # Step 20: Configure Shared Storage
    $stepNum++
    # Determine storage backend (new key takes priority, fall back to legacy ConfigureiSCSI)
    $storageBackend = if ($Config.StorageBackendType) { $Config.StorageBackendType } else { "iSCSI" }
    $configureStorage = $Config.ConfigureSharedStorage -or $Config.ConfigureiSCSI
    if ($configureStorage -and $configType -eq "HOST") {
        Write-OutputColor "  [$stepNum/$totalSteps] Configuring shared storage ($storageBackend)..." -color "Info"
        if ($script:DryRunMode) {
            Write-OutputColor "           [DRY RUN] Would configure $storageBackend shared storage" -color "Info"
            $changesApplied++
        }
        else {
        try {
            if ($storageBackend -eq "iSCSI") {
                # iSCSI-specific configuration (preserved from v1.2.0)
                $hostNum = $Config.iSCSIHostNumber -as [int]
                if ($null -eq $hostNum) {
                    $hostNum = Get-HostNumberFromHostname
                }
                if ($null -ne $hostNum -and $hostNum -ge 1 -and $hostNum -le 24) {
                    $ip1 = Get-iSCSIAutoIP -HostNumber $hostNum -PortNumber 1
                    $ip2 = Get-iSCSIAutoIP -HostNumber $hostNum -PortNumber 2
                    $iscsiAdapters = @()
                    if ($script:iSCSICandidateAdapters) {
                        $iscsiAdapters = @($script:iSCSICandidateAdapters | ForEach-Object { $_.Adapter })
                    } else {
                        $iscsiAdapters = @(Get-NetAdapter | Where-Object {
                            $_.Name -notlike "vEthernet*" -and
                            $_.InterfaceDescription -notlike "*Hyper-V*" -and
                            $_.InterfaceDescription -notlike "*Virtual*"
                        })
                    }
                    if ($iscsiAdapters.Count -ge 2) {
                        $sideCheck = Test-iSCSICabling -Adapters $iscsiAdapters
                        if ($sideCheck.Valid) {
                            $aSide = $iscsiAdapters | Where-Object { $_.Name -eq $sideCheck.AdapterA }
                            $bSide = $iscsiAdapters | Where-Object { $_.Name -eq $sideCheck.AdapterB }
                            Write-OutputColor "           Auto-detected: $($sideCheck.AdapterA) = A-side, $($sideCheck.AdapterB) = B-side" -color "Info"
                        } else {
                            $aSide = $iscsiAdapters[0]
                            $bSide = $iscsiAdapters[1]
                            Write-OutputColor "           A/B side auto-detect inconclusive, using adapter order." -color "Warning"
                        }
                        Remove-NetIPAddress -InterfaceAlias $aSide.Name -Confirm:$false -ErrorAction SilentlyContinue
                        Remove-NetRoute -InterfaceAlias $aSide.Name -Confirm:$false -ErrorAction SilentlyContinue
                        New-NetIPAddress -InterfaceAlias $aSide.Name -IPAddress $ip1 -PrefixLength 24 -ErrorAction Stop
                        Disable-NetAdapterBinding -Name $aSide.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
                        Remove-NetIPAddress -InterfaceAlias $bSide.Name -Confirm:$false -ErrorAction SilentlyContinue
                        Remove-NetRoute -InterfaceAlias $bSide.Name -Confirm:$false -ErrorAction SilentlyContinue
                        New-NetIPAddress -InterfaceAlias $bSide.Name -IPAddress $ip2 -PrefixLength 24 -ErrorAction Stop
                        Disable-NetAdapterBinding -Name $bSide.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
                        Write-OutputColor "           iSCSI configured: A=$ip1, B=$ip2" -color "Success"
                        $changesApplied++
                        Add-SessionChange -Category "Network" -Description "Configured iSCSI: A-side $ip1, B-side $ip2"
                        Clear-MenuCache
                    } else {
                        Write-OutputColor "           Not enough iSCSI adapters found (need 2, found $($iscsiAdapters.Count))." -color "Warning"
                    }
                } else {
                    Write-OutputColor "           Could not determine host number for iSCSI." -color "Warning"
                }
            } else {
                # Non-iSCSI backends: use the generalized initializer
                $configHash = @{}
                if ($Config.SMB3SharePath) { $configHash["SMB3SharePath"] = $Config.SMB3SharePath }
                $null = Initialize-StorageBackendBatch -Config $configHash -BackendType $storageBackend
                $changesApplied++
                Add-SessionChange -Category "Storage" -Description "Configured $storageBackend storage backend"
                Clear-MenuCache
            }
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Shared storage: skipped" -color "Debug"
    }

    # Step 21: Configure MPIO / Multipath
    $stepNum++
    if ($Config.ConfigureMPIO -and $configType -eq "HOST") {
        Write-OutputColor "  [$stepNum/$totalSteps] Configuring MPIO for $storageBackend..." -color "Info"
        if ($script:DryRunMode) {
            Write-OutputColor "           [DRY RUN] Would configure MPIO for $storageBackend" -color "Info"
            $changesApplied++
        }
        else {
        try {
            if ($storageBackend -in @("S2D", "SMB3", "NVMeoF", "Local")) {
                Write-OutputColor "           MPIO not required for $storageBackend (handled natively)." -color "Info"
            } elseif (Test-MPIOInstalled) {
                Initialize-MPIOForBackend -BackendType $storageBackend
                $changesApplied++
                Add-SessionChange -Category "System" -Description "Configured MPIO for $storageBackend"
                Clear-MenuCache
            } else {
                Write-OutputColor "           MPIO not installed. Install it first (step 9)." -color "Warning"
            }
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] MPIO config: skipped" -color "Debug"
    }

    # Step 22: Configure Defender Exclusions
    $stepNum++
    if ($Config.ConfigureDefenderExclusions -and $configType -eq "HOST") {
        # Idempotency: check if exclusion paths are already configured
        $currentExclusions = @()
        try { $currentExclusions = @((Get-MpPreference -ErrorAction Stop).ExclusionPath) } catch { $currentExclusions = @() }
        $allPaths = @($script:DefenderExclusionPaths) + @($script:DefenderCommonVMPaths) | Where-Object { $_ }
        $missingPaths = @($allPaths | Where-Object { $_ -notin $currentExclusions })

        if ($missingPaths.Count -eq 0) {
            Write-OutputColor "  [$stepNum/$totalSteps] Defender exclusions: already configured" -color "Debug"
            $skipped++
        }
        else {
            Write-OutputColor "  [$stepNum/$totalSteps] Configuring Defender exclusions..." -color "Info"
            if ($script:DryRunMode) {
                Write-OutputColor "           [DRY RUN] Would add $($missingPaths.Count) Defender path exclusion(s)" -color "Info"
                $changesApplied++
            }
            else {
            try {
                $addedCount = 0
                $addedPaths = @()
                foreach ($path in $missingPaths) {
                    Add-MpPreference -ExclusionPath $path -ErrorAction SilentlyContinue
                    $addedPaths += $path
                    $addedCount++
                }
                # Add process exclusions
                $defenderProcesses = @("vmms.exe", "vmwp.exe", "vmcompute.exe")
                foreach ($proc in $defenderProcesses) {
                    Add-MpPreference -ExclusionProcess $proc -ErrorAction SilentlyContinue
                }
                Write-OutputColor "           Added $addedCount path exclusions and $($defenderProcesses.Count) process exclusions." -color "Success"
                $changesApplied++
                Add-SessionChange -Category "Security" -Description "Configured Defender exclusions for Hyper-V"
                Clear-MenuCache
                $pathsList = ($addedPaths | ForEach-Object { "'$_'" }) -join ','
                $script:BatchUndoStack.Add(@{ Step = $stepNum; Description = "Remove Defender exclusions"; Reversible = $true; UndoScript = [scriptblock]::Create("foreach (`$p in @($pathsList)) { Remove-MpPreference -ExclusionPath `$p -ErrorAction SilentlyContinue }") })
                Save-BatchUndoState
            }
            catch {
                Write-OutputColor "           Failed: $_" -color "Error"
                $errors++
            }
            }
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Defender exclusions: skipped" -color "Debug"
    }

    # Step 23: Install agents (v1.8.0)
    $stepNum++
    $agentsToInstall = @()
    if ($Config.InstallAgents -and $Config.InstallAgents -is [array]) {
        # New array syntax: list of agent ToolNames to install
        $allAgentConfigs = Get-AllAgentConfigs
        foreach ($agentName in $Config.InstallAgents) {
            $match = $allAgentConfigs | Where-Object { $_.ToolName -eq $agentName }
            if ($match) { $agentsToInstall += $match }
        }
    }
    elseif ($Config.InstallAgent) {
        # Backward compat: boolean installs primary agent only
        $agentsToInstall += $script:AgentInstaller
    }

    if ($agentsToInstall.Count -gt 0 -and (Test-AgentInstallerConfigured)) {
        foreach ($agentCfg in $agentsToInstall) {
            $agentInstalled = Test-AgentInstalledByConfig -AgentConfig $agentCfg
            if ($agentInstalled) {
                Write-OutputColor "  [$stepNum/$totalSteps] $($agentCfg.ToolName) agent: already installed" -color "Debug"
                $skipped++
            }
            else {
                Write-OutputColor "  [$stepNum/$totalSteps] Installing $($agentCfg.ToolName) agent..." -color "Info"
                if ($script:DryRunMode) {
                    Write-OutputColor "           [DRY RUN] Would install $($agentCfg.ToolName) agent" -color "Info"
                    $changesApplied++
                }
                else {
                try {
                    Install-Agent -Unattended
                    $changesApplied++
                    Add-SessionChange -Category "Software" -Description "Installed $($agentCfg.ToolName) agent via batch mode"
                    Clear-MenuCache
                }
                catch {
                    Write-OutputColor "           Failed: $_" -color "Error"
                    $errors++
                }
                }
            }
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Agent install: skipped" -color "Debug"
    }

    # Step 24: Validate cluster (v1.8.0)
    $stepNum++
    if ($Config.ValidateCluster) {
        Write-OutputColor "  [$stepNum/$totalSteps] Running cluster readiness check..." -color "Info"
        if ($script:DryRunMode) {
            Write-OutputColor "           [DRY RUN] Would run cluster readiness validation" -color "Info"
            $changesApplied++
        }
        else {
        try {
            $readiness = Test-ClusterReadiness
            if ($readiness.AllPassed) {
                Write-OutputColor "           Cluster readiness: all checks passed" -color "Success"
            }
            else {
                Write-OutputColor "           Cluster readiness: $($readiness.FailedChecks.Count) issue(s) found" -color "Warning"
                foreach ($fc in $readiness.FailedChecks) {
                    Write-OutputColor "             - $fc" -color "Warning"
                }
            }
            $changesApplied++
        }
        catch {
            Write-OutputColor "           Cluster check failed: $_" -color "Error"
            $errors++
        }
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Cluster validation: skipped" -color "Debug"
    }

    # Dry-run summary (replaces normal summary when in dry-run mode)
    if ($script:DryRunMode) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor ("=" * 65) -color "Warning"
        Write-OutputColor "  DRY RUN COMPLETE - No changes were made" -color "Warning"
        Write-OutputColor ("=" * 65) -color "Warning"
        Write-OutputColor "  $changesApplied step(s) would execute" -color "Info"
        Write-OutputColor "  $skipped step(s) would be skipped (already configured)" -color "Info"
        Write-OutputColor "  Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -color "Info"
        Write-OutputColor ("=" * 65) -color "Warning"
        Write-OutputColor "" -color "Info"

        # Reset dry-run mode
        $script:DryRunMode = $false

        # Stop transcript
        Stop-ScriptTranscript
        return
    }

    # Undo prompt on errors
    if ($errors -gt 0 -and $script:BatchUndoStack.Count -gt 0) {
        $reversible = @($script:BatchUndoStack | Where-Object { $_.Reversible })
        if ($reversible.Count -gt 0) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  $errors step(s) failed. $($reversible.Count) previous step(s) can be undone." -color "Warning"
            Write-OutputColor "  Undo all reversible changes? [y/N]: " -color "Warning"
            $undoChoice = Read-Host
            if ($undoChoice -eq 'y' -or $undoChoice -eq 'Y') {
                Invoke-BatchUndo
            }
        }
    }

    # Clean up batch undo persistence file (clean exit)
    if (Test-Path -LiteralPath $batchUndoPath) {
        try {
            Remove-Item -LiteralPath $batchUndoPath -Force -ErrorAction Stop
        }
        catch {
            # Non-critical — don't fail batch completion for cleanup
        }
    }

    # Summary
    Write-OutputColor "" -color "Info"
    Write-OutputColor ("=" * 65) -color "Info"
    $resultColor = if ($errors -eq 0) { "Success" } else { "Warning" }
    Write-OutputColor "  BATCH MODE COMPLETE: $changesApplied changed, $skipped skipped, $errors failed" -color $resultColor
    Write-OutputColor "  Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -color "Info"
    Write-OutputColor ("=" * 65) -color "Info"
    Write-OutputColor "" -color "Info"

    # Auto-save drift baseline after batch mode (v1.7.1)
    if ($changesApplied -gt 0) {
        try {
            $baselinePath = Save-DriftBaseline -Description "Auto-saved after batch mode ($changesApplied changes)"
            if ($baselinePath) {
                Write-OutputColor "  Drift baseline saved: $(Split-Path $baselinePath -Leaf)" -color "Debug"
            }
        }
        catch {
            Write-OutputColor "  Baseline auto-save skipped: $_" -color "Debug"
        }
    }

    # Show session summary
    Show-SessionSummary

    # Stop transcript
    Stop-ScriptTranscript

    # Auto-reboot if needed and configured
    if ($global:RebootNeeded -and $Config.AutoReboot) {
        Write-OutputColor "  Rebooting in 5 seconds... (Ctrl+C to cancel)" -color "Warning"
        Start-Sleep -Seconds 5
        Restart-Computer -Force
    }
    elseif ($global:RebootNeeded) {
        Write-OutputColor "⚠ Reboot required to complete changes. AutoReboot is disabled." -color "Warning"
        Write-OutputColor "  Run 'Restart-Computer' when ready." -color "Info"
    }
}

# Check for batch config file (only if script path is valid)
if ($script:ScriptPath) {
    $scriptDir = Split-Path -Parent $script:ScriptPath
    $batchConfigPath = Join-Path $scriptDir "batch_config.json"
    if (Test-Path -LiteralPath $batchConfigPath) {
        # Verify elevation before batch mode
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-OutputColor "  ERROR: Batch mode requires administrator privileges." -color "Error"
            [Environment]::Exit(1)
        }
        try {
            $batchConfig = Get-Content -LiteralPath $batchConfigPath -Raw | ConvertFrom-Json
            $configHash = @{}
            $batchConfig.PSObject.Properties | ForEach-Object { $configHash[$_.Name] = $_.Value }
            Start-BatchMode -Config $configHash
            [Environment]::Exit(0)
        }
        catch {
            Write-OutputColor "  Failed to load batch config: $_" -color "Error"
            [Environment]::Exit(1)
        }
    }
}

#endregion