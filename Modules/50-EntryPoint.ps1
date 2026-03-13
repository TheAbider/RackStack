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
        'Harden' {
            Write-OutputColor "  Running security hardening audit..." -color "Info"
            $hardenReport = Show-SecurityHardeningReport
            if ($script:CLIOutputFormat -eq 'JSON' -and $null -ne $hardenReport) {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'Harden'
                    Hostname  = $env:COMPUTERNAME
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Score     = $hardenReport.Score
                    Summary   = @{
                        Total    = $hardenReport.Total
                        Passed   = $hardenReport.Passed
                        Failed   = $hardenReport.Failed
                        Warnings = $hardenReport.Warnings
                        Info     = $hardenReport.Info
                    }
                    Checks    = @($hardenReport.Checks | ForEach-Object {
                        @{
                            Category = $_.Category
                            Name     = $_.Name
                            Value    = $_.Value
                            Status   = $_.Status
                        }
                    })
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
        }
        'Remediate' {
            if (-not $script:CLIConfig) {
                Write-OutputColor "  ERROR: -Config <baseline.json> is required for Remediate." -color "Error"
                Write-OutputColor "  Usage: RackStack.exe -Action Remediate -Config <path>" -color "Info"
                [Environment]::Exit(1)
            }
            if (-not (Test-Path -LiteralPath $script:CLIConfig)) {
                Write-OutputColor "  ERROR: Config file not found: $($script:CLIConfig)" -color "Error"
                [Environment]::Exit(1)
            }

            Write-OutputColor "  Remediating drift against: $($script:CLIConfig)" -color "Info"
            Write-OutputColor "" -color "Info"
            $remediationResult = Invoke-Remediation -ProfilePath $script:CLIConfig

            if ($null -eq $remediationResult) {
                Write-OutputColor "  Remediation failed." -color "Error"
                [Environment]::Exit(1)
            }

            Show-RemediationReport -Result $remediationResult

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'Remediate'
                    Hostname  = $env:COMPUTERNAME
                    Baseline  = $script:CLIConfig
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Summary   = @{
                        Total    = $remediationResult.Total
                        Fixed    = $remediationResult.Fixed
                        Skipped  = $remediationResult.Skipped
                        Failed   = $remediationResult.Failed
                        Manual   = $remediationResult.Manual
                    }
                    Items     = @($remediationResult.Items | ForEach-Object {
                        @{
                            Setting  = $_.Setting
                            Expected = $_.Expected
                            Current  = $_.Current
                            Action   = $_.Action
                            Detail   = $_.Detail
                        }
                    })
                    RebootRequired = $remediationResult.RebootRequired
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }

            if ($remediationResult.RebootRequired) {
                $global:RebootNeeded = $true
            }
        }
        'Aggregate' {
            if (-not $script:CLIConfig) {
                Write-OutputColor "  ERROR: -Config <path> is required for Aggregate." -color "Error"
                Write-OutputColor "  Provide a directory of JSON files or a single JSON array file." -color "Info"
                [Environment]::Exit(1)
            }
            if (-not (Test-Path -LiteralPath $script:CLIConfig)) {
                Write-OutputColor "  ERROR: Path not found: $($script:CLIConfig)" -color "Error"
                [Environment]::Exit(1)
            }

            Write-OutputColor "  Aggregating fleet reports from: $($script:CLIConfig)" -color "Info"
            Write-OutputColor "" -color "Info"
            $aggResult = Invoke-FleetAggregate -InputPath $script:CLIConfig

            if ($null -eq $aggResult) {
                Write-OutputColor "  Aggregation failed — no valid reports found." -color "Error"
                [Environment]::Exit(1)
            }

            Show-FleetAggregateReport -Result $aggResult

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool         = $script:ToolFullName
                    Version      = $script:ScriptVersion
                    Action       = 'Aggregate'
                    Timestamp    = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    TotalReports = $aggResult.TotalReports
                    Hosts        = $aggResult.Hosts
                    ActionTypes  = $aggResult.ActionTypes
                    Aggregations = $aggResult.Aggregations
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
        }
        'Compare' {
            if (-not $script:CLIConfig) {
                Write-OutputColor "  ERROR: -Config is required for Compare." -color "Error"
                Write-OutputColor "  Usage: RackStack.exe -Action Compare -Config `"fileA.json,fileB.json`"" -color "Info"
                [Environment]::Exit(1)
            }

            $comparePaths = @($script:CLIConfig -split ',', 2)
            if ($comparePaths.Count -lt 2) {
                Write-OutputColor "  ERROR: Compare requires two file paths separated by comma." -color "Error"
                Write-OutputColor "  Usage: -Config `"path\fileA.json,path\fileB.json`"" -color "Info"
                [Environment]::Exit(1)
            }

            $pathA = $comparePaths[0].Trim()
            $pathB = $comparePaths[1].Trim()

            if (-not (Test-Path -LiteralPath $pathA)) {
                Write-OutputColor "  ERROR: File not found: $pathA" -color "Error"
                [Environment]::Exit(1)
            }
            if (-not (Test-Path -LiteralPath $pathB)) {
                Write-OutputColor "  ERROR: File not found: $pathB" -color "Error"
                [Environment]::Exit(1)
            }

            Write-OutputColor "  Comparing: $(Split-Path $pathA -Leaf) vs $(Split-Path $pathB -Leaf)" -color "Info"
            Write-OutputColor "" -color "Info"

            $compareResult = Invoke-FleetCompare -FilePathA $pathA -FilePathB $pathB

            if ($null -eq $compareResult) {
                Write-OutputColor "  Comparison failed." -color "Error"
                [Environment]::Exit(1)
            }

            Show-FleetCompareReport -Result $compareResult

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool        = $script:ToolFullName
                    Version     = $script:ScriptVersion
                    Action      = 'Compare'
                    Timestamp   = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    HostA       = $compareResult.HostA
                    HostB       = $compareResult.HostB
                    CompareType = $compareResult.Action
                    Summary     = $compareResult.Summary
                    Differences = @($compareResult.Differences)
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
        }
        'Export' {
            # All valid section names (11 sections)
            $exportAllSections = @('Health', 'Inventory', 'Hardening', 'Snapshot', 'Certificates', 'ListeningPorts', 'Software', 'Uptime', 'Services', 'Events', 'Network')

            # Parse -Config for section filter (comma-separated, case-insensitive)
            $exportSections = $exportAllSections
            if ($script:CLIConfig) {
                $requested = @($script:CLIConfig -split ',' | ForEach-Object { $_.Trim() })
                $invalid = @($requested | Where-Object { $_ -notin $exportAllSections })
                if ($invalid.Count -gt 0) {
                    Write-OutputColor "  ERROR: Unknown Export section(s): $($invalid -join ', ')" -color "Error"
                    Write-OutputColor "  Valid sections: $($exportAllSections -join ', ')" -color "Info"
                    [Environment]::Exit(1)
                }
                $exportSections = $requested
            }
            $totalSteps = $exportSections.Count
            $stepNum = 0

            Write-OutputColor "  Running server export ($totalSteps section$(if ($totalSteps -ne 1) { 's' }))..." -color "Info"
            Write-OutputColor "" -color "Info"

            $healthReport = $null
            $inventoryReport = $null
            $hardeningChecks = $null
            $hardenScore = 0
            $hardenPassCount = 0
            $hardenTotalCount = 0
            $snapshotData = $null
            $exportCerts = @()
            $certExpired = 0
            $certCritical = 0
            $exportPorts = @()
            $exportSoftware = @()
            $exportLastBoot = $null
            $exportUptimeDays = 0
            $exportUptimeDisplay = "Unknown"
            $exportUptimeStatus = "Unknown"
            $exportReboots = @()
            $exportSvcItems = @()
            $exportSvcRunning = 0
            $exportSvcStopped = 0
            $exportSvcMisconfigured = 0
            $exportEvtItems = @()
            $exportEvtCritical = 0
            $exportEvtError = 0
            $exportEvtSources = @()
            $exportNetItems = @()
            $exportNetUp = 0
            $exportNetDown = 0
            $exportNetNicErrors = 0

            if ($exportSections -contains 'Health') {
                $stepNum++
                Write-OutputColor "  [$stepNum/$totalSteps] Collecting system health..." -color "Info"
                $healthReport = Show-SystemHealthCheck
                Write-OutputColor "" -color "Info"
            }

            if ($exportSections -contains 'Inventory') {
                $stepNum++
                Write-OutputColor "  [$stepNum/$totalSteps] Collecting server inventory..." -color "Info"
                $inventoryReport = Get-ServerInventory
                Write-OutputColor "" -color "Info"
            }

            if ($exportSections -contains 'Hardening') {
                $stepNum++
                Write-OutputColor "  [$stepNum/$totalSteps] Running security hardening audit..." -color "Info"
                $hardeningChecks = Get-SecurityHardeningChecks
                $hardenPassCount = @($hardeningChecks | Where-Object { $_.Status -eq 'Pass' }).Count
                $hardenTotalCount = @($hardeningChecks).Count
                $hardenScore = if ($hardenTotalCount -gt 0) { [math]::Round(($hardenPassCount / $hardenTotalCount) * 100) } else { 0 }
                Write-OutputColor "" -color "Info"
            }

            if ($exportSections -contains 'Snapshot') {
                $stepNum++
                Write-OutputColor "  [$stepNum/$totalSteps] Capturing performance snapshot..." -color "Info"
                $snapshotPath = Save-PerformanceSnapshot
                if ($null -ne $snapshotPath -and (Test-Path -LiteralPath $snapshotPath)) {
                    try {
                        $snapshotData = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json
                    } catch {
                        Write-OutputColor "  Warning: Could not read snapshot file." -color "Warning"
                    }
                }
                Write-OutputColor "" -color "Info"
            }

            if ($exportSections -contains 'Certificates') {
                $stepNum++
                Write-OutputColor "  [$stepNum/$totalSteps] Auditing certificates..." -color "Info"
                $certStores = @(
                    @{ Name = "Personal (My)";    Path = "Cert:\LocalMachine\My" }
                    @{ Name = "Trusted Root CA";  Path = "Cert:\LocalMachine\Root" }
                    @{ Name = "Intermediate CA";  Path = "Cert:\LocalMachine\CA" }
                    @{ Name = "Web Hosting";      Path = "Cert:\LocalMachine\WebHosting" }
                    @{ Name = "Remote Desktop";   Path = "Cert:\LocalMachine\Remote Desktop" }
                )
                $exportCertList = [System.Collections.Generic.List[object]]::new()
                $certNow = Get-Date
                foreach ($store in $certStores) {
                    try {
                        $certs = @(Get-ChildItem -Path $store.Path -ErrorAction Stop | Where-Object { $null -ne $_.NotAfter })
                        foreach ($cert in $certs) {
                            $daysLeft = [math]::Round(($cert.NotAfter - $certNow).TotalDays, 0)
                            $subject = if ($cert.Subject) { $cert.Subject } else { "(no subject)" }
                            if ($subject.Length -gt 60) { $subject = $subject.Substring(0, 57) + "..." }
                            $certStatus = if ($daysLeft -lt 0) { "Expired" }
                                          elseif ($daysLeft -le 7) { "Critical" }
                                          elseif ($daysLeft -le 30) { "Warning" }
                                          elseif ($daysLeft -le 90) { "Expiring" }
                                          else { "Valid" }
                            $exportCertList.Add(@{ Store = $store.Name; Subject = $subject; Expires = $cert.NotAfter.ToString("yyyy-MM-dd"); DaysLeft = $daysLeft; Status = $certStatus })
                        }
                    } catch { }
                }
                $exportCerts = @($exportCertList)
                $certExpired = @($exportCerts | Where-Object { $_.Status -eq "Expired" }).Count
                $certCritical = @($exportCerts | Where-Object { $_.Status -eq "Critical" }).Count
            }

            if ($exportSections -contains 'ListeningPorts') {
                $stepNum++
                Write-OutputColor "  [$stepNum/$totalSteps] Scanning listening ports..." -color "Info"
                $exportPortList = [System.Collections.Generic.List[object]]::new()
                try {
                    $exportListeners = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Sort-Object LocalPort)
                    $exportSeenPorts = @{}
                    foreach ($conn in $exportListeners) {
                        $key = "$($conn.LocalAddress):$($conn.LocalPort)"
                        if ($exportSeenPorts.ContainsKey($key)) { continue }
                        $exportSeenPorts[$key] = $true
                        $pName = try { (Get-Process -Id $conn.OwningProcess -ErrorAction Stop).ProcessName } catch { "PID $($conn.OwningProcess)" }
                        $svc = switch ($conn.LocalPort) { 22 { "SSH" } 53 { "DNS" } 80 { "HTTP" } 135 { "RPC" } 139 { "NetBIOS" } 389 { "LDAP" } 443 { "HTTPS" } 445 { "SMB" } 636 { "LDAPS" } 1433 { "MSSQL" } 3260 { "iSCSI" } 3389 { "RDP" } 5985 { "WinRM" } 5986 { "WinRM-S" } default { "" } }
                        $exportPortList.Add(@{ Port = $conn.LocalPort; Address = $conn.LocalAddress; Process = $pName; Service = $svc })
                    }
                } catch { }
                $exportPorts = @($exportPortList)
            }

            if ($exportSections -contains 'Software') {
                $stepNum++
                Write-OutputColor "  [$stepNum/$totalSteps] Scanning installed software..." -color "Info"
                $exportSWList = [System.Collections.Generic.List[object]]::new()
                foreach ($regPath in @("HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")) {
                    try {
                        $entries = @(Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne "" })
                        foreach ($entry in $entries) {
                            $exportSWList.Add(@{
                                Name      = $entry.DisplayName
                                Version   = if ($entry.DisplayVersion) { $entry.DisplayVersion } else { "N/A" }
                                Publisher = if ($entry.Publisher) { $entry.Publisher } else { "Unknown" }
                            })
                        }
                    } catch { }
                }
                $exportSoftware = @($exportSWList | Sort-Object { $_.Name } -Unique)
            }

            if ($exportSections -contains 'Uptime') {
                $stepNum++
                Write-OutputColor "  [$stepNum/$totalSteps] Checking uptime..." -color "Info"
                try {
                    $exportCim = Invoke-WithTimeout -ScriptBlock { Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } -TimeoutSeconds 10 -Activity "Querying uptime"
                    if (-not $exportCim.TimedOut) {
                        $exportBoot = $exportCim.Result.LastBootUpTime
                        $exportUptime = (Get-Date) - $exportBoot
                        $exportLastBoot = $exportBoot.ToString("yyyy-MM-ddTHH:mm:ss")
                        $exportUptimeDays = [math]::Round($exportUptime.TotalDays, 2)
                        $exportUptimeDisplay = ""
                        if ($exportUptime.Days -gt 0) { $exportUptimeDisplay += "$($exportUptime.Days)d " }
                        $exportUptimeDisplay += "$($exportUptime.Hours)h $($exportUptime.Minutes)m"
                        $exportUptimeStatus = if ($exportUptime.Days -ge 60) { "Critical" } elseif ($exportUptime.Days -ge 30) { "Warning" } else { "OK" }
                    }
                } catch { }
                $exportRebootList = [System.Collections.Generic.List[object]]::new()
                try {
                    foreach ($e in @(Get-WinEvent -FilterHashtable @{ LogName = "System"; Id = 1074 } -MaxEvents 10 -ErrorAction Stop)) {
                        $reason = ($e.Message -split "`n")[0]
                        if ($null -eq $reason) { $reason = "Planned restart" }
                        if ($reason.Length -gt 80) { $reason = $reason.Substring(0, 77) + "..." }
                        $exportRebootList.Add(@{ Time = $e.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ss"); Type = "Planned"; Reason = $reason })
                    }
                } catch { }
                try {
                    foreach ($e in @(Get-WinEvent -FilterHashtable @{ LogName = "System"; Id = 6008 } -MaxEvents 5 -ErrorAction Stop)) {
                        $exportRebootList.Add(@{ Time = $e.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ss"); Type = "Unexpected"; Reason = "Unexpected shutdown" })
                    }
                } catch { }
                $exportReboots = @($exportRebootList | Sort-Object { $_.Time } -Descending)
            }

            if ($exportSections -contains 'Services') {
                $stepNum++
                Write-OutputColor "  [$stepNum/$totalSteps] Auditing services..." -color "Info"
                $exportSvcList = [System.Collections.Generic.List[object]]::new()
                $svcMonitored = if ($script:Defaults.MonitoredServices) { $script:Defaults.MonitoredServices } else {
                    @(
                        @{ Name = "vmms"; DisplayName = "Hyper-V Virtual Machine Management" }
                        @{ Name = "vmcompute"; DisplayName = "Hyper-V Host Compute Service" }
                        @{ Name = "ClusSvc"; DisplayName = "Cluster Service" }
                        @{ Name = "MSiSCSI"; DisplayName = "Microsoft iSCSI Initiator Service" }
                        @{ Name = "WinRM"; DisplayName = "Windows Remote Management" }
                        @{ Name = "DNS"; DisplayName = "DNS Client" }
                        @{ Name = "wuauserv"; DisplayName = "Windows Update" }
                        @{ Name = "W32Time"; DisplayName = "Windows Time" }
                        @{ Name = "LanmanServer"; DisplayName = "Server (SMB)" }
                        @{ Name = "LanmanWorkstation"; DisplayName = "Workstation (SMB Client)" }
                        @{ Name = "EventLog"; DisplayName = "Windows Event Log" }
                        @{ Name = "Netlogon"; DisplayName = "Netlogon" }
                        @{ Name = "NTDS"; DisplayName = "Active Directory Domain Services" }
                    )
                }
                foreach ($svc in $svcMonitored) {
                    $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
                    if ($null -eq $service) { continue }
                    $startTag = switch ($service.StartType) { "Automatic" { "Auto" } "Manual" { "Manual" } "Disabled" { "Disabled" } default { "$($service.StartType)" } }
                    $dn = if ($service.DisplayName) { $service.DisplayName } elseif ($svc.DisplayName) { $svc.DisplayName } else { $svc.Name }
                    $svcHealth = "OK"
                    if ($service.Status -eq "Running") {
                        $exportSvcRunning++
                    } else {
                        $exportSvcStopped++
                        if ($service.StartType -eq "Automatic") { $exportSvcMisconfigured++; $svcHealth = "FAIL" }
                        elseif ($service.StartType -eq "Disabled") { $svcHealth = "Disabled" }
                        else { $svcHealth = "Stopped" }
                    }
                    $exportSvcList.Add(@{ Name = $svc.Name; DisplayName = $dn; Status = "$($service.Status)"; StartType = $startTag; Health = $svcHealth })
                }
                $exportSvcItems = @($exportSvcList)
            }

            if ($exportSections -contains 'Events') {
                $stepNum++
                Write-OutputColor "  [$stepNum/$totalSteps] Auditing events (last 24h)..." -color "Info"
                $evtStartTime = (Get-Date).AddHours(-24)
                $exportEvtList = [System.Collections.Generic.List[object]]::new()
                $exportEvtSourceList = [System.Collections.Generic.List[object]]::new()
                foreach ($logName in @('System', 'Application')) {
                    try {
                        $critEvts = @(Get-WinEvent -FilterHashtable @{ LogName = $logName; Level = 1; StartTime = $evtStartTime } -MaxEvents 25 -ErrorAction SilentlyContinue)
                        foreach ($evt in $critEvts) {
                            $msg = if ($evt.Message) { $evt.Message -replace "`r?`n", " " } else { "(no message)" }
                            if ($msg.Length -gt 120) { $msg = $msg.Substring(0, 117) + "..." }
                            $exportEvtList.Add(@{ Time = $evt.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ss"); Log = $logName; Level = "Critical"; EventId = $evt.Id; Source = $evt.ProviderName; Message = $msg })
                        }
                        $exportEvtCritical += $critEvts.Count
                    } catch { }
                    try {
                        $errEvts = @(Get-WinEvent -FilterHashtable @{ LogName = $logName; Level = 2; StartTime = $evtStartTime } -MaxEvents 25 -ErrorAction SilentlyContinue)
                        foreach ($evt in $errEvts) {
                            $msg = if ($evt.Message) { $evt.Message -replace "`r?`n", " " } else { "(no message)" }
                            if ($msg.Length -gt 120) { $msg = $msg.Substring(0, 117) + "..." }
                            $exportEvtList.Add(@{ Time = $evt.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ss"); Log = $logName; Level = "Error"; EventId = $evt.Id; Source = $evt.ProviderName; Message = $msg })
                        }
                        $exportEvtError += $errEvts.Count
                        $grouped = $errEvts | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 10
                        foreach ($g in $grouped) {
                            $exportEvtSourceList.Add(@{ Log = $logName; Source = $g.Name; Count = $g.Count })
                        }
                    } catch { }
                }
                $exportEvtItems = @($exportEvtList | Sort-Object { $_.Time } -Descending)
                $exportEvtSources = @($exportEvtSourceList | Sort-Object { $_.Count } -Descending)
            }

            if ($exportSections -contains 'Network') {
                $stepNum++
                Write-OutputColor "  [$stepNum/$totalSteps] Scanning network configuration..." -color "Info"
                $exportNetList = [System.Collections.Generic.List[object]]::new()
                try {
                    $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Sort-Object Name)
                    foreach ($adapter in $adapters) {
                        $ipv4Addrs = @()
                        $gateway = $null
                        $dnsServers = @()
                        $vlanId = $null
                        if ($adapter.Status -eq "Up") {
                            $exportNetUp++
                            try { $ipv4Addrs = @(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" }) } catch { }
                            try { $gw = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue; if ($null -ne $gw -and $null -ne $gw.IPv4DefaultGateway) { $gateway = $gw.IPv4DefaultGateway.NextHop } } catch { }
                            try { $dns = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue; if ($null -ne $dns) { $dnsServers = @($dns.ServerAddresses) } } catch { }
                        } else { $exportNetDown++ }
                        try { $vlanId = $adapter.VlanID } catch { }
                        $inErrors = 0; $outErrors = 0
                        try { $stats = Get-NetAdapterStatistics -Name $adapter.Name -ErrorAction SilentlyContinue; if ($null -ne $stats) { $inErrors = if ($null -ne $stats.InErrors) { $stats.InErrors } else { 0 }; $outErrors = if ($null -ne $stats.OutErrors) { $stats.OutErrors } else { 0 }; if ($inErrors -gt 0 -or $outErrors -gt 0) { $exportNetNicErrors++ } } } catch { }
                        $speed = if ($adapter.LinkSpeed) { "$($adapter.LinkSpeed)" } else { "N/A" }
                        $exportNetList.Add(@{ Name = $adapter.Name; Description = $adapter.InterfaceDescription; Status = "$($adapter.Status)"; MacAddress = $adapter.MacAddress; Speed = $speed; IPv4 = $ipv4Addrs; Gateway = $gateway; DNS = $dnsServers; VlanID = $vlanId; InErrors = $inErrors; OutErrors = $outErrors })
                    }
                } catch { }
                $exportNetItems = @($exportNetList)
            }

            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Export complete ($totalSteps section$(if ($totalSteps -ne 1) { 's' }))." -color "Success"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'Export'
                    Hostname  = $env:COMPUTERNAME
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Sections  = $exportSections
                }
                if ($exportSections -contains 'Health') { $jsonResult.Health = $healthReport }
                if ($exportSections -contains 'Inventory') { $jsonResult.Inventory = $inventoryReport }
                if ($exportSections -contains 'Hardening') {
                    $jsonResult.Hardening = @{
                        Score    = $hardenScore
                        Total    = $hardenTotalCount
                        Passed   = $hardenPassCount
                        Failed   = @($hardeningChecks | Where-Object { $_.Status -eq 'Fail' }).Count
                        Warnings = @($hardeningChecks | Where-Object { $_.Status -eq 'Warn' }).Count
                        Info     = @($hardeningChecks | Where-Object { $_.Status -eq 'Info' }).Count
                        Checks   = @($hardeningChecks | ForEach-Object { @{ Category = $_.Category; Name = $_.Name; Value = $_.Value; Status = $_.Status } })
                    }
                }
                if ($exportSections -contains 'Snapshot') { $jsonResult.Snapshot = $snapshotData }
                if ($exportSections -contains 'Certificates') { $jsonResult.Certificates = @{ Total = $exportCerts.Count; Expired = $certExpired; Critical = $certCritical; Items = $exportCerts } }
                if ($exportSections -contains 'ListeningPorts') { $jsonResult.ListeningPorts = @{ Count = $exportPorts.Count; Ports = $exportPorts } }
                if ($exportSections -contains 'Software') { $jsonResult.Software = @{ Count = $exportSoftware.Count; Items = $exportSoftware } }
                if ($exportSections -contains 'Uptime') {
                    $jsonResult.Uptime = @{
                        LastBoot = $exportLastBoot; Days = $exportUptimeDays; Display = $exportUptimeDisplay; Status = $exportUptimeStatus
                        Reboots = @{ Total = $exportReboots.Count; Unexpected = @($exportReboots | Where-Object { $_.Type -eq "Unexpected" }).Count; Events = $exportReboots }
                    }
                }
                if ($exportSections -contains 'Services') { $jsonResult.Services = @{ Total = $exportSvcItems.Count; Running = $exportSvcRunning; Stopped = $exportSvcStopped; Misconfigured = $exportSvcMisconfigured; Items = $exportSvcItems } }
                if ($exportSections -contains 'Events') { $jsonResult.Events = @{ TimeWindowHours = 24; Critical = $exportEvtCritical; Error = $exportEvtError; TopSources = $exportEvtSources; Items = $exportEvtItems } }
                if ($exportSections -contains 'Network') { $jsonResult.Network = @{ Total = $exportNetItems.Count; Up = $exportNetUp; Down = $exportNetDown; NICErrors = $exportNetNicErrors; Adapters = $exportNetItems } }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
        }
        'Trend' {
            if (-not $script:CLIConfig) {
                Write-OutputColor "  ERROR: -Config <path> is required for Trend." -color "Error"
                Write-OutputColor "  Provide a directory containing snapshot JSON files." -color "Info"
                [Environment]::Exit(1)
            }
            if (-not (Test-Path -LiteralPath $script:CLIConfig)) {
                Write-OutputColor "  ERROR: Path not found: $($script:CLIConfig)" -color "Error"
                [Environment]::Exit(1)
            }

            Write-OutputColor "  Analyzing performance trends from: $($script:CLIConfig)" -color "Info"
            Write-OutputColor "" -color "Info"
            $trendResult = Invoke-FleetTrend -InputPath $script:CLIConfig

            if ($null -eq $trendResult) {
                Write-OutputColor "  Trend analysis failed." -color "Error"
                [Environment]::Exit(1)
            }

            Show-FleetTrendReport -Result $trendResult

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'Trend'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname  = $trendResult.Hostname
                    TimeRange = $trendResult.TimeRange
                    CPU       = $trendResult.CPU
                    Memory    = $trendResult.Memory
                    Disks     = $trendResult.Disks
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
        }
        'CertCheck' {
            Write-OutputColor "  Running certificate expiry audit..." -color "Info"
            Write-OutputColor "" -color "Info"

            $stores = @(
                @{ Name = "Personal (My)";    Path = "Cert:\LocalMachine\My" }
                @{ Name = "Trusted Root CA";  Path = "Cert:\LocalMachine\Root" }
                @{ Name = "Intermediate CA";  Path = "Cert:\LocalMachine\CA" }
                @{ Name = "Web Hosting";      Path = "Cert:\LocalMachine\WebHosting" }
                @{ Name = "Remote Desktop";   Path = "Cert:\LocalMachine\Remote Desktop" }
            )

            $warnDays = 90
            $now = Get-Date
            $certList = [System.Collections.Generic.List[object]]::new()

            foreach ($store in $stores) {
                try {
                    $certs = @(Get-ChildItem -Path $store.Path -ErrorAction Stop | Where-Object {
                        $null -ne $_.NotAfter
                    })
                    foreach ($cert in $certs) {
                        $daysLeft = [math]::Round(($cert.NotAfter - $now).TotalDays, 0)
                        $subject = if ($cert.Subject) { $cert.Subject } else { "(no subject)" }
                        if ($subject.Length -gt 60) { $subject = $subject.Substring(0, 57) + "..." }

                        $status = if ($daysLeft -lt 0) { "Expired" }
                                  elseif ($daysLeft -le 7) { "Critical" }
                                  elseif ($daysLeft -le 30) { "Warning" }
                                  elseif ($daysLeft -le $warnDays) { "Expiring" }
                                  else { "Valid" }

                        $certList.Add([PSCustomObject]@{
                            Store      = $store.Name
                            Subject    = $subject
                            Thumbprint = if ($cert.Thumbprint) { $cert.Thumbprint } else { "N/A" }
                            Expires    = $cert.NotAfter.ToString("yyyy-MM-dd")
                            DaysLeft   = $daysLeft
                            Status     = $status
                        })
                    }
                } catch {
                    Write-OutputColor "  Could not read $($store.Name) store: $_" -color "Warning"
                }
            }

            $allCerts = @($certList)
            $expired = @($allCerts | Where-Object { $_.Status -eq "Expired" })
            $critical = @($allCerts | Where-Object { $_.Status -eq "Critical" })
            $warning = @($allCerts | Where-Object { $_.Status -eq "Warning" })
            $expiring = @($allCerts | Where-Object { $_.Status -eq "Expiring" })
            $valid = @($allCerts | Where-Object { $_.Status -eq "Valid" })

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  CERTIFICATE EXPIRY AUDIT".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Total Certificates:   $($allCerts.Count)".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Expired:              $($expired.Count)".PadRight(72))│" -color $(if ($expired.Count -gt 0) { "Error" } else { "Success" })
            Write-OutputColor "  │$("  Critical (≤7d):       $($critical.Count)".PadRight(72))│" -color $(if ($critical.Count -gt 0) { "Error" } else { "Success" })
            Write-OutputColor "  │$("  Warning (≤30d):       $($warning.Count)".PadRight(72))│" -color $(if ($warning.Count -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  │$("  Expiring (≤${warnDays}d):     $($expiring.Count)".PadRight(72))│" -color $(if ($expiring.Count -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  │$("  Valid:                $($valid.Count)".PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($expired.Count -gt 0 -or $critical.Count -gt 0) {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  ATTENTION: $($expired.Count + $critical.Count) certificate(s) require immediate action!" -color "Error"
                foreach ($cert in @($expired + $critical | Sort-Object DaysLeft)) {
                    Write-OutputColor "    [$($cert.Status.ToUpper())] $($cert.Subject) — expires $($cert.Expires) ($($cert.DaysLeft)d)" -color "Error"
                }
            }

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'CertCheck'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname  = $env:COMPUTERNAME
                    Summary   = @{
                        Total    = $allCerts.Count
                        Expired  = $expired.Count
                        Critical = $critical.Count
                        Warning  = $warning.Count
                        Expiring = $expiring.Count
                        Valid    = $valid.Count
                    }
                    Certificates = @($allCerts | Select-Object Store, Subject, Thumbprint, Expires, DaysLeft, Status)
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
        }
        'ReportHTML' {
            # Report type from -Config (default: Health)
            $reportType = if ($script:CLIConfig) { $script:CLIConfig } else { "Health" }
            $validTypes = @("Health", "Readiness", "Trend")

            if ($reportType -notin $validTypes) {
                Write-OutputColor "  ERROR: Invalid report type '$reportType'." -color "Error"
                Write-OutputColor "  Valid types: $($validTypes -join ', ')" -color "Info"
                Write-OutputColor "  Usage: -Action ReportHTML -Config Health|Readiness|Trend" -color "Info"
                [Environment]::Exit(1)
            }

            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $outputPath = "$env:USERPROFILE\Desktop\${reportType}Report_${timestamp}.html"

            Write-OutputColor "  Generating $reportType HTML report..." -color "Info"
            Write-OutputColor "  Output: $outputPath" -color "Info"
            Write-OutputColor "" -color "Info"

            switch ($reportType) {
                'Health' {
                    Export-HTMLHealthReport -OutputPath $outputPath -Sections @("Performance", "Storage", "Network", "Security")
                }
                'Readiness' {
                    Export-HTMLReadinessReport -OutputPath $outputPath
                }
                'Trend' {
                    Export-HTMLTrendReport -OutputPath $outputPath
                }
            }

            if (Test-Path -LiteralPath $outputPath) {
                $fileSize = [math]::Round((Get-Item $outputPath).Length / 1KB, 1)
                Write-OutputColor "  Report generated: $outputPath ($fileSize KB)" -color "Success"
            } else {
                Write-OutputColor "  Report generation may have failed — file not found." -color "Warning"
            }

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool       = $script:ToolFullName
                    Version    = $script:ScriptVersion
                    Action     = 'ReportHTML'
                    Timestamp  = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname   = $env:COMPUTERNAME
                    ReportType = $reportType
                    OutputPath = $outputPath
                    Generated  = (Test-Path -LiteralPath $outputPath)
                    FileSizeKB = if (Test-Path -LiteralPath $outputPath) { [math]::Round((Get-Item $outputPath).Length / 1KB, 1) } else { 0 }
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
        }
        'ListeningPorts' {
            Write-OutputColor "  Scanning listening ports..." -color "Info"
            Write-OutputColor "" -color "Info"

            try {
                $listeners = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Sort-Object LocalPort)
            } catch {
                Write-OutputColor "  Could not query TCP connections: $_" -color "Error"
                [Environment]::Exit(1)
            }

            $portList = [System.Collections.Generic.List[object]]::new()
            $seenPorts = @{}
            foreach ($conn in $listeners) {
                $port = $conn.LocalPort
                $addr = $conn.LocalAddress
                $key = "$addr`:$port"
                if ($seenPorts.ContainsKey($key)) { continue }
                $seenPorts[$key] = $true

                $processName = "Unknown"
                try {
                    $proc = Get-Process -Id $conn.OwningProcess -ErrorAction Stop
                    $processName = $proc.ProcessName
                } catch {
                    $processName = "PID $($conn.OwningProcess)"
                }

                $svcLabel = switch ($port) {
                    22 { "SSH" } 53 { "DNS" } 80 { "HTTP" } 135 { "RPC" } 139 { "NetBIOS" }
                    389 { "LDAP" } 443 { "HTTPS" } 445 { "SMB" } 636 { "LDAPS" }
                    1433 { "MSSQL" } 3260 { "iSCSI" } 3389 { "RDP" }
                    5985 { "WinRM" } 5986 { "WinRM-S" } default { "" }
                }

                $portList.Add([PSCustomObject]@{
                    Port    = $port
                    Address = $addr
                    Process = $processName
                    PID     = $conn.OwningProcess
                    Service = $svcLabel
                })
            }

            $allPorts = @($portList)
            $uniquePortCount = @($allPorts | Select-Object -Property Port -Unique).Count

            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  LISTENING PORTS".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Total Endpoints:  $($allPorts.Count)".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Unique Ports:     $uniquePortCount".PadRight(72))│" -color "Info"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            # Show well-known ports in console
            $wellKnown = @($allPorts | Where-Object { $_.Port -le 1023 })
            if ($wellKnown.Count -gt 0) {
                Write-OutputColor "" -color "Info"
                foreach ($p in $wellKnown) {
                    $label = if ($p.Service) { " ($($p.Service))" } else { "" }
                    Write-OutputColor "    :$($p.Port)$label — $($p.Process)" -color "Info"
                }
            }

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'ListeningPorts'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname  = $env:COMPUTERNAME
                    Summary   = @{
                        TotalEndpoints = $allPorts.Count
                        UniquePorts    = $uniquePortCount
                    }
                    Ports     = @($allPorts | Select-Object Port, Address, Process, PID, Service)
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
        }
        'SoftwareList' {
            Write-OutputColor "  Scanning installed software..." -color "Info"
            Write-OutputColor "" -color "Info"

            $softwareList = [System.Collections.Generic.List[object]]::new()
            $regPaths = @(
                "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
                "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
            )

            foreach ($regPath in $regPaths) {
                try {
                    $entries = @(Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue |
                        Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne "" })
                    foreach ($entry in $entries) {
                        $softwareList.Add([PSCustomObject]@{
                            Name        = $entry.DisplayName
                            Version     = if ($entry.DisplayVersion) { $entry.DisplayVersion } else { "N/A" }
                            Publisher   = if ($entry.Publisher) { $entry.Publisher } else { "Unknown" }
                            InstallDate = if ($entry.InstallDate -and $entry.InstallDate -match '^\d{8}$') {
                                "$($entry.InstallDate.Substring(0,4))-$($entry.InstallDate.Substring(4,2))-$($entry.InstallDate.Substring(6,2))"
                            } else { $null }
                            SizeMB      = if ($entry.EstimatedSize) { [math]::Round($entry.EstimatedSize / 1024, 1) } else { $null }
                        })
                    }
                } catch {
                    Write-OutputColor "  Could not read registry: $_" -color "Warning"
                }
            }

            $software = @($softwareList | Sort-Object Name, Version -Unique)

            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  INSTALLED SOFTWARE".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Total Programs:   $($software.Count)".PadRight(72))│" -color "Info"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            # Show top publishers
            $byPublisher = @($software | Group-Object Publisher | Sort-Object Count -Descending | Select-Object -First 5)
            if ($byPublisher.Count -gt 0) {
                Write-OutputColor "" -color "Info"
                foreach ($pub in $byPublisher) {
                    $pubName = if ($pub.Name.Length -gt 40) { $pub.Name.Substring(0, 37) + "..." } else { $pub.Name }
                    Write-OutputColor "    $($pubName.PadRight(45)) $($pub.Count) app(s)" -color "Info"
                }
            }

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'SoftwareList'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname  = $env:COMPUTERNAME
                    Count     = $software.Count
                    Software  = @($software | Select-Object Name, Version, Publisher, InstallDate, SizeMB)
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
        }
        'Uptime' {
            Write-OutputColor "  Checking uptime and reboot history..." -color "Info"
            Write-OutputColor "" -color "Info"

            $lastBootStr = $null
            $uptimeDays = 0
            $uptimeDisplay = "Unknown"
            $uptimeStatus = "Unknown"

            try {
                $uptCim = Invoke-WithTimeout -ScriptBlock {
                    Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
                } -TimeoutSeconds 10 -Activity "Querying uptime"
                if ($uptCim.TimedOut) { throw "CIM query timed out" }
                $osData = $uptCim.Result
                $lastBoot = $osData.LastBootUpTime
                $uptime = (Get-Date) - $lastBoot
                $lastBootStr = $lastBoot.ToString("yyyy-MM-ddTHH:mm:ss")
                $uptimeDays = [math]::Round($uptime.TotalDays, 2)

                $uptimeDisplay = ""
                if ($uptime.Days -gt 0) { $uptimeDisplay += "$($uptime.Days)d " }
                $uptimeDisplay += "$($uptime.Hours)h $($uptime.Minutes)m"

                $uptimeStatus = if ($uptime.Days -ge 60) { "Critical" }
                                elseif ($uptime.Days -ge 30) { "Warning" }
                                else { "OK" }
            } catch {
                Write-OutputColor "  Could not determine uptime: $_" -color "Error"
            }

            # Reboot history from event log
            $rebootList = [System.Collections.Generic.List[object]]::new()
            try {
                $shutdownEvents = @(Get-WinEvent -FilterHashtable @{ LogName = "System"; Id = 1074 } -MaxEvents 20 -ErrorAction Stop)
                foreach ($e in $shutdownEvents) {
                    $reason = ($e.Message -split "`n")[0]
                    if ($null -eq $reason) { $reason = "Planned restart" }
                    if ($reason.Length -gt 80) { $reason = $reason.Substring(0, 77) + "..." }
                    $rebootList.Add([PSCustomObject]@{
                        Time   = $e.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ss")
                        Type   = "Planned"
                        Reason = $reason
                    })
                }
            } catch {
                if ($_.Exception.Message -notmatch "No events were found") {
                    Write-OutputColor "  Could not read planned shutdown events: $_" -color "Warning"
                }
            }

            try {
                $unexpectedEvents = @(Get-WinEvent -FilterHashtable @{ LogName = "System"; Id = 6008 } -MaxEvents 10 -ErrorAction Stop)
                foreach ($e in $unexpectedEvents) {
                    $rebootList.Add([PSCustomObject]@{
                        Time   = $e.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ss")
                        Type   = "Unexpected"
                        Reason = "Unexpected shutdown (crash/power loss)"
                    })
                }
            } catch {
                if ($_.Exception.Message -notmatch "No events were found") {
                    Write-OutputColor "  Could not read unexpected shutdown events: $_" -color "Warning"
                }
            }

            $rebootEvents = @($rebootList | Sort-Object Time -Descending | Select-Object -First 15)
            $totalReboots = $rebootEvents.Count
            $unexpectedCount = @($rebootEvents | Where-Object { $_.Type -eq "Unexpected" }).Count

            # Console output
            $statusColor = switch ($uptimeStatus) { "Critical" { "Error" } "Warning" { "Warning" } default { "Success" } }
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  UPTIME & REBOOT HISTORY".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Last Boot:        $lastBootStr".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Uptime:           $uptimeDisplay".PadRight(72))│" -color $statusColor
            Write-OutputColor "  │$("  Status:           $uptimeStatus".PadRight(72))│" -color $statusColor
            Write-OutputColor "  │$("  Total Reboots:    $totalReboots".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Unexpected:       $unexpectedCount".PadRight(72))│" -color $(if ($unexpectedCount -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($unexpectedCount -gt 0) {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  ATTENTION: $unexpectedCount unexpected shutdown(s) detected!" -color "Warning"
                foreach ($evt in @($rebootEvents | Where-Object { $_.Type -eq "Unexpected" })) {
                    Write-OutputColor "    [UNEXPECTED] $($evt.Time)" -color "Warning"
                }
            }

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'Uptime'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname  = $env:COMPUTERNAME
                    LastBoot  = $lastBootStr
                    Uptime    = @{
                        Days    = $uptimeDays
                        Display = $uptimeDisplay
                        Status  = $uptimeStatus
                    }
                    RebootHistory = @{
                        Total      = $totalReboots
                        Unexpected = $unexpectedCount
                        Events     = @($rebootEvents | Select-Object Time, Type, Reason)
                    }
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
        }
        'ServiceAudit' {
            Write-OutputColor "  Auditing key service status..." -color "Info"
            Write-OutputColor "" -color "Info"

            # Configurable service list (from defaults.json MonitoredServices or built-in fallback)
            $auditServices = if ($script:Defaults.MonitoredServices) {
                $script:Defaults.MonitoredServices
            } else {
                @(
                    @{ Name = "vmms"; DisplayName = "Hyper-V Virtual Machine Management" }
                    @{ Name = "vmcompute"; DisplayName = "Hyper-V Host Compute Service" }
                    @{ Name = "ClusSvc"; DisplayName = "Cluster Service" }
                    @{ Name = "MSiSCSI"; DisplayName = "Microsoft iSCSI Initiator Service" }
                    @{ Name = "WinRM"; DisplayName = "Windows Remote Management" }
                    @{ Name = "DNS"; DisplayName = "DNS Client" }
                    @{ Name = "wuauserv"; DisplayName = "Windows Update" }
                    @{ Name = "W32Time"; DisplayName = "Windows Time" }
                    @{ Name = "LanmanServer"; DisplayName = "Server (SMB)" }
                    @{ Name = "LanmanWorkstation"; DisplayName = "Workstation (SMB Client)" }
                    @{ Name = "EventLog"; DisplayName = "Windows Event Log" }
                    @{ Name = "Netlogon"; DisplayName = "Netlogon" }
                    @{ Name = "NTDS"; DisplayName = "Active Directory Domain Services" }
                )
            }

            $svcResults = [System.Collections.Generic.List[object]]::new()
            $svcRunning = 0
            $svcStopped = 0
            $svcMisconfigured = 0

            foreach ($svc in $auditServices) {
                $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
                if ($null -eq $service) { continue }
                $startTag = switch ($service.StartType) { "Automatic" { "Auto" } "Manual" { "Manual" } "Disabled" { "Disabled" } default { "$($service.StartType)" } }
                $dn = if ($service.DisplayName) { $service.DisplayName } elseif ($svc.DisplayName) { $svc.DisplayName } else { $svc.Name }
                $svcStatus = "OK"
                if ($service.Status -eq "Running") {
                    $svcRunning++
                } else {
                    $svcStopped++
                    if ($service.StartType -eq "Automatic") {
                        $svcMisconfigured++
                        $svcStatus = "FAIL"
                    } elseif ($service.StartType -eq "Disabled") {
                        $svcStatus = "Disabled"
                    } else {
                        $svcStatus = "Stopped"
                    }
                }
                $svcResults.Add(@{ Name = $svc.Name; DisplayName = $dn; Status = "$($service.Status)"; StartType = $startTag; Health = $svcStatus })
            }
            $svcItems = @($svcResults)

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  SERVICE AUDIT".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($s in $svcItems) {
                $dispName = if ($s.DisplayName.Length -gt 38) { $s.DisplayName.Substring(0, 35) + "..." } else { $s.DisplayName }
                $line = "  $($dispName.PadRight(40)) $($s.Status.PadRight(10)) [$($s.StartType)]"
                if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                $color = switch ($s.Health) { "FAIL" { "Error" } "Stopped" { "Warning" } "Disabled" { "Info" } default { "Success" } }
                Write-OutputColor "  │$($line.PadRight(72))│" -color $color
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Running: $svcRunning   Stopped: $svcStopped   Misconfigured: $svcMisconfigured".PadRight(72))│" -color $(if ($svcMisconfigured -gt 0) { "Error" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($svcMisconfigured -gt 0) {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  WARNING: $svcMisconfigured service(s) set to Automatic but not running!" -color "Error"
                foreach ($s in @($svcItems | Where-Object { $_.Health -eq "FAIL" })) {
                    Write-OutputColor "    [FAIL] $($s.DisplayName) ($($s.Name))" -color "Error"
                }
            }

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'ServiceAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname  = $env:COMPUTERNAME
                    Summary   = @{
                        Total         = $svcItems.Count
                        Running       = $svcRunning
                        Stopped       = $svcStopped
                        Misconfigured = $svcMisconfigured
                    }
                    Services  = $svcItems
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }

            if ($svcMisconfigured -gt 0) {
                [Environment]::Exit(1)
            }
        }
        'EventAudit' {
            $hoursBack = 24
            if ($script:CLIConfig -and $script:CLIConfig -match '^\d+$') {
                $hoursBack = [int]$script:CLIConfig
            }
            Write-OutputColor "  Auditing critical/error events (last $hoursBack hours)..." -color "Info"
            Write-OutputColor "" -color "Info"

            $startTime = (Get-Date).AddHours(-$hoursBack)
            $logNames = @('System', 'Application')
            $totalCritical = 0
            $totalError = 0
            $eventList = [System.Collections.Generic.List[object]]::new()
            $sourceGroups = [System.Collections.Generic.List[object]]::new()

            foreach ($logName in $logNames) {
                try {
                    $criticalEvents = @(Get-WinEvent -FilterHashtable @{ LogName = $logName; Level = 1; StartTime = $startTime } -MaxEvents 25 -ErrorAction SilentlyContinue)
                    foreach ($evt in $criticalEvents) {
                        $msg = if ($evt.Message) { $evt.Message -replace "`r?`n", " " } else { "(no message)" }
                        if ($msg.Length -gt 120) { $msg = $msg.Substring(0, 117) + "..." }
                        $eventList.Add(@{ Time = $evt.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ss"); Log = $logName; Level = "Critical"; EventId = $evt.Id; Source = $evt.ProviderName; Message = $msg })
                    }
                    $totalCritical += $criticalEvents.Count
                } catch {
                    if ($_.Exception.Message -notmatch "No events were found") {
                        Write-OutputColor "  Could not read $logName critical events: $_" -color "Warning"
                    }
                }
                try {
                    $errorEvents = @(Get-WinEvent -FilterHashtable @{ LogName = $logName; Level = 2; StartTime = $startTime } -MaxEvents 25 -ErrorAction SilentlyContinue)
                    foreach ($evt in $errorEvents) {
                        $msg = if ($evt.Message) { $evt.Message -replace "`r?`n", " " } else { "(no message)" }
                        if ($msg.Length -gt 120) { $msg = $msg.Substring(0, 117) + "..." }
                        $eventList.Add(@{ Time = $evt.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ss"); Log = $logName; Level = "Error"; EventId = $evt.Id; Source = $evt.ProviderName; Message = $msg })
                    }
                    $totalError += $errorEvents.Count

                    # Group errors by source for console summary
                    $grouped = $errorEvents | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 10
                    foreach ($g in $grouped) {
                        $sourceGroups.Add(@{ Log = $logName; Source = $g.Name; Count = $g.Count })
                    }
                } catch {
                    if ($_.Exception.Message -notmatch "No events were found") {
                        Write-OutputColor "  Could not read $logName error events: $_" -color "Warning"
                    }
                }
            }

            $allEvents = @($eventList | Sort-Object { $_.Time } -Descending)

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  EVENT AUDIT (last $hoursBack hours)".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Critical Events:  $totalCritical".PadRight(72))│" -color $(if ($totalCritical -gt 0) { "Error" } else { "Success" })
            Write-OutputColor "  │$("  Error Events:     $totalError".PadRight(72))│" -color $(if ($totalError -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if (@($sourceGroups).Count -gt 0) {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Top error sources:" -color "Info"
                foreach ($sg in @($sourceGroups | Sort-Object { $_.Count } -Descending | Select-Object -First 8)) {
                    $src = if ($sg.Source.Length -gt 40) { $sg.Source.Substring(0, 37) + "..." } else { $sg.Source }
                    Write-OutputColor "    $($sg.Log.PadRight(12)) $($src.PadRight(42)) $($sg.Count) error(s)" -color "Warning"
                }
            }

            if ($totalCritical -eq 0 -and $totalError -eq 0) {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  No critical or error events found." -color "Success"
            }

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'EventAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname  = $env:COMPUTERNAME
                    TimeWindowHours = $hoursBack
                    Summary   = @{
                        Critical = $totalCritical
                        Error    = $totalError
                    }
                    TopSources = @($sourceGroups | Sort-Object { $_.Count } -Descending)
                    Events    = $allEvents
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
        }
        'NetInfo' {
            Write-OutputColor "  Scanning network configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $adapterList = [System.Collections.Generic.List[object]]::new()
            $upCount = 0
            $downCount = 0
            $nicErrors = 0

            try {
                $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Sort-Object Name)
                foreach ($adapter in $adapters) {
                    $ipv4Addrs = @()
                    $gateway = $null
                    $dnsServers = @()
                    $vlanId = $null

                    if ($adapter.Status -eq "Up") {
                        $upCount++
                        try {
                            $ipAddrs = @(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
                            $ipv4Addrs = @($ipAddrs | ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" })
                        } catch { }
                        try {
                            $gw = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue
                            if ($null -ne $gw -and $null -ne $gw.IPv4DefaultGateway) {
                                $gateway = $gw.IPv4DefaultGateway.NextHop
                            }
                        } catch { }
                        try {
                            $dns = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
                            if ($null -ne $dns) { $dnsServers = @($dns.ServerAddresses) }
                        } catch { }
                    } else {
                        $downCount++
                    }

                    try { $vlanId = $adapter.VlanID } catch { }

                    # NIC error counters
                    $inErrors = 0
                    $outErrors = 0
                    try {
                        $stats = Get-NetAdapterStatistics -Name $adapter.Name -ErrorAction SilentlyContinue
                        if ($null -ne $stats) {
                            $inErrors = if ($null -ne $stats.InErrors) { $stats.InErrors } else { 0 }
                            $outErrors = if ($null -ne $stats.OutErrors) { $stats.OutErrors } else { 0 }
                            if ($inErrors -gt 0 -or $outErrors -gt 0) { $nicErrors++ }
                        }
                    } catch { }

                    $speed = if ($adapter.LinkSpeed) { "$($adapter.LinkSpeed)" } else { "N/A" }

                    $adapterList.Add(@{
                        Name        = $adapter.Name
                        Description = $adapter.InterfaceDescription
                        Status      = "$($adapter.Status)"
                        MacAddress  = $adapter.MacAddress
                        Speed       = $speed
                        IPv4        = $ipv4Addrs
                        Gateway     = $gateway
                        DNS         = $dnsServers
                        VlanID      = $vlanId
                        InErrors    = $inErrors
                        OutErrors   = $outErrors
                    })
                }
            } catch {
                Write-OutputColor "  Could not enumerate adapters: $_" -color "Error"
            }
            $netItems = @($adapterList)

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  NETWORK CONFIGURATION".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($nic in $netItems) {
                $nicName = if ($nic.Name.Length -gt 20) { $nic.Name.Substring(0, 17) + "..." } else { $nic.Name }
                $statusColor = if ($nic.Status -eq "Up") { "Success" } else { "Error" }
                Write-OutputColor "  │$("  $nicName  [$($nic.Status)]  $($nic.Speed)".PadRight(72))│" -color $statusColor
                if ($nic.IPv4.Count -gt 0) {
                    $ipStr = $nic.IPv4 -join ", "
                    if ($ipStr.Length -gt 60) { $ipStr = $ipStr.Substring(0, 57) + "..." }
                    Write-OutputColor "  │$("    IP: $ipStr".PadRight(72))│" -color "Info"
                }
                if ($nic.Gateway) {
                    Write-OutputColor "  │$("    GW: $($nic.Gateway)".PadRight(72))│" -color "Info"
                }
                if ($nic.DNS.Count -gt 0) {
                    Write-OutputColor "  │$("    DNS: $($nic.DNS -join ', ')".PadRight(72))│" -color "Info"
                }
                if ($nic.InErrors -gt 0 -or $nic.OutErrors -gt 0) {
                    Write-OutputColor "  │$("    NIC Errors: In=$($nic.InErrors) Out=$($nic.OutErrors)".PadRight(72))│" -color "Warning"
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Adapters: $($netItems.Count)   Up: $upCount   Down: $downCount   NIC Errors: $nicErrors".PadRight(72))│" -color $(if ($nicErrors -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'NetInfo'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname  = $env:COMPUTERNAME
                    Summary   = @{
                        Total     = $netItems.Count
                        Up        = $upCount
                        Down      = $downCount
                        NICErrors = $nicErrors
                    }
                    Adapters  = $netItems
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
        }
        'ScheduledExport' {
            # -Tier: Register, Unregister, Status (default: Status)
            # -Config: "C:\ExportDir,Daily" or "C:\ExportDir,Hourly,Health,Inventory" (dir,frequency[,sections...])
            $subCommand = if ($script:CLIProfile -and $script:CLIProfile -ne 'Standard') { $script:CLIProfile } else { 'Status' }

            switch ($subCommand) {
                'Register' {
                    if (-not $script:CLIConfig) {
                        Write-OutputColor "  ERROR: -Config required for Register." -color "Error"
                        Write-OutputColor "  Format: -Config ""C:\ExportDir,Daily""" -color "Info"
                        Write-OutputColor "  Frequencies: Hourly, Daily, Weekly" -color "Info"
                        Write-OutputColor "  Optional sections: -Config ""C:\ExportDir,Daily,Health,Inventory""" -color "Info"
                        [Environment]::Exit(1)
                    }

                    $parts = @($script:CLIConfig -split ',' | ForEach-Object { $_.Trim() })
                    if ($parts.Count -lt 2) {
                        Write-OutputColor "  ERROR: -Config must include output directory and frequency." -color "Error"
                        Write-OutputColor "  Example: -Config ""C:\Exports,Daily""" -color "Info"
                        [Environment]::Exit(1)
                    }

                    $exportDir = $parts[0]
                    $freq = $parts[1]
                    $validFreqs = @('Hourly', 'Daily', 'Weekly')
                    if ($freq -notin $validFreqs) {
                        Write-OutputColor "  ERROR: Invalid frequency '$freq'. Must be: $($validFreqs -join ', ')" -color "Error"
                        [Environment]::Exit(1)
                    }

                    $sectionFilter = $null
                    if ($parts.Count -gt 2) {
                        $exportAllSections = @('Health', 'Inventory', 'Hardening', 'Snapshot', 'Certificates', 'ListeningPorts', 'Software', 'Uptime', 'Services', 'Events', 'Network')
                        $reqSections = @($parts[2..($parts.Count - 1)])
                        $invalidSec = @($reqSections | Where-Object { $_ -notin $exportAllSections })
                        if ($invalidSec.Count -gt 0) {
                            Write-OutputColor "  ERROR: Unknown section(s): $($invalidSec -join ', ')" -color "Error"
                            Write-OutputColor "  Valid: $($exportAllSections -join ', ')" -color "Info"
                            [Environment]::Exit(1)
                        }
                        $sectionFilter = $reqSections -join ','
                    }

                    Write-OutputColor "  Registering scheduled export task..." -color "Info"
                    Write-OutputColor "" -color "Info"

                    $outFmt = if ($script:CLIOutputFormat -eq 'JSON') { 'JSON' } else { 'JSON' }
                    $regResult = Register-ScheduledExport -OutputDir $exportDir -Frequency $freq -Sections $sectionFilter -OutputFormat $outFmt

                    if ($script:CLIOutputFormat -eq 'JSON') {
                        $jsonResult = @{
                            Tool      = $script:ToolFullName
                            Version   = $script:ScriptVersion
                            Action    = 'ScheduledExport'
                            SubAction = 'Register'
                            Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                            Hostname  = $env:COMPUTERNAME
                            Success   = [bool]$regResult
                            Config    = @{
                                OutputDir = $exportDir
                                Frequency = $freq
                                Sections  = $sectionFilter
                            }
                        }
                        Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
                    }

                    if (-not $regResult) { [Environment]::Exit(1) }
                }
                'Unregister' {
                    Write-OutputColor "  Removing scheduled export task..." -color "Info"
                    Write-OutputColor "" -color "Info"

                    $unregResult = Unregister-ScheduledExport

                    if ($script:CLIOutputFormat -eq 'JSON') {
                        $jsonResult = @{
                            Tool      = $script:ToolFullName
                            Version   = $script:ScriptVersion
                            Action    = 'ScheduledExport'
                            SubAction = 'Unregister'
                            Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                            Hostname  = $env:COMPUTERNAME
                            Success   = [bool]$unregResult
                        }
                        Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
                    }

                    if (-not $unregResult) { [Environment]::Exit(1) }
                }
                'Status' {
                    Write-OutputColor "  Checking scheduled export status..." -color "Info"
                    Write-OutputColor "" -color "Info"

                    $status = Get-ScheduledExportStatus

                    if ($status.Registered) {
                        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
                        Write-OutputColor "  │$("  SCHEDULED EXPORT STATUS".PadRight(72))│" -color "Info"
                        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                        Write-OutputColor "  │$("  Task:     $($status.TaskName)".PadRight(72))│" -color "Success"
                        Write-OutputColor "  │$("  State:    $($status.State)".PadRight(72))│" -color $(if ($status.State -eq 'Ready') { "Success" } else { "Warning" })
                        if ($status.LastRun) {
                            Write-OutputColor "  │$("  Last Run: $($status.LastRun)".PadRight(72))│" -color "Info"
                        }
                        if ($null -ne $status.LastResult) {
                            $resultColor = if ($status.LastResult -eq 0) { "Success" } else { "Error" }
                            Write-OutputColor "  │$("  Result:   $($status.LastResult)".PadRight(72))│" -color $resultColor
                        }
                        if ($status.NextRun) {
                            Write-OutputColor "  │$("  Next Run: $($status.NextRun)".PadRight(72))│" -color "Info"
                        }
                        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
                    } else {
                        Write-OutputColor "  No scheduled export task is registered." -color "Warning"
                    }

                    if ($script:CLIOutputFormat -eq 'JSON') {
                        $jsonResult = @{
                            Tool      = $script:ToolFullName
                            Version   = $script:ScriptVersion
                            Action    = 'ScheduledExport'
                            SubAction = 'Status'
                            Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                            Hostname  = $env:COMPUTERNAME
                            Status    = $status
                        }
                        Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
                    }
                }
                default {
                    Write-OutputColor "  ERROR: Unknown ScheduledExport sub-command: $subCommand" -color "Error"
                    Write-OutputColor "  Valid: Register, Unregister, Status" -color "Info"
                    Write-OutputColor "  Usage: -Action ScheduledExport -Tier Register -Config ""C:\Exports,Daily""" -color "Info"
                    [Environment]::Exit(1)
                }
            }
        }
        'ValidateConfig' {
            # -Config: path to batch_config.json file
            if (-not $script:CLIConfig) {
                Write-OutputColor "  ERROR: -Config required. Provide path to batch_config.json." -color "Error"
                Write-OutputColor "  Usage: -Action ValidateConfig -Config ""C:\path\to\batch_config.json""" -color "Info"
                [Environment]::Exit(1)
            }

            $configPath = $script:CLIConfig
            if (-not (Test-Path -LiteralPath $configPath)) {
                Write-OutputColor "  ERROR: File not found: $configPath" -color "Error"
                [Environment]::Exit(1)
            }

            Write-OutputColor "  Validating batch config: $configPath" -color "Info"
            Write-OutputColor "" -color "Info"

            # Parse the JSON file
            try {
                $rawContent = Get-Content -LiteralPath $configPath -Raw -ErrorAction Stop
                $batchConfig = $rawContent | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Write-OutputColor "  ERROR: Invalid JSON: $($_.Exception.Message)" -color "Error"
                if ($script:CLIOutputFormat -eq 'JSON') {
                    $jsonResult = @{
                        Tool      = $script:ToolFullName
                        Version   = $script:ScriptVersion
                        Action    = 'ValidateConfig'
                        Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                        Hostname  = $env:COMPUTERNAME
                        File      = $configPath
                        Valid     = $false
                        Errors    = @("Invalid JSON: $($_.Exception.Message)")
                        Warnings  = @()
                    }
                    Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
                }
                [Environment]::Exit(1)
            }

            # Convert PSCustomObject to hashtable for Test-BatchConfig
            $configHash = @{}
            foreach ($prop in $batchConfig.PSObject.Properties) {
                if ($prop.Name -notlike '_*') {
                    $configHash[$prop.Name] = $prop.Value
                }
            }

            $validation = Test-BatchConfig -Config $configHash

            # Count active steps (non-null, non-false settings that map to batch steps)
            $activeSteps = 0
            $stepFields = @('Hostname', 'IPAddress', 'DomainName', 'Timezone', 'EnableRDP', 'EnableWinRM',
                           'ConfigureFirewall', 'SetPowerPlan', 'InstallHyperV', 'InstallMPIO',
                           'InstallFailoverClustering', 'CreateLocalAdmin', 'DisableBuiltInAdmin',
                           'InstallUpdates', 'CreateVirtualSwitch', 'ConfigureSharedStorage',
                           'ConfigureMPIO', 'InitializeHostStorage', 'ConfigureDefenderExclusions',
                           'ServerRoleTemplate', 'PromoteToDC')
            foreach ($sf in $stepFields) {
                $val = $configHash[$sf]
                if ($null -ne $val -and $val -ne $false -and $val -ne '') {
                    $activeSteps++
                }
            }

            # Display results
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  BATCH CONFIG VALIDATION".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  File: $configPath".PadRight(72))│" -color "Info"

            $cfgType = if ($configHash.ConfigType) { $configHash.ConfigType } else { "(not set)" }
            Write-OutputColor "  │$("  Type: $cfgType".PadRight(72))│" -color "Info"

            $cfgHost = if ($configHash.Hostname) { $configHash.Hostname } else { "(not set)" }
            Write-OutputColor "  │$("  Hostname: $cfgHost".PadRight(72))│" -color "Info"

            Write-OutputColor "  │$("  Active Steps: $activeSteps".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

            if ($validation.IsValid -and $validation.Warnings.Count -eq 0) {
                Write-OutputColor "  │$("  RESULT: VALID - No errors or warnings".PadRight(72))│" -color "Success"
            } elseif ($validation.IsValid) {
                Write-OutputColor "  │$("  RESULT: VALID with $($validation.Warnings.Count) warning(s)".PadRight(72))│" -color "Warning"
            } else {
                Write-OutputColor "  │$("  RESULT: INVALID - $($validation.Errors.Count) error(s)".PadRight(72))│" -color "Error"
            }
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($validation.Errors.Count -gt 0) {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  ERRORS:" -color "Error"
                foreach ($e in $validation.Errors) {
                    Write-OutputColor "    [X] $e" -color "Error"
                }
            }
            if ($validation.Warnings.Count -gt 0) {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  WARNINGS:" -color "Warning"
                foreach ($w in $validation.Warnings) {
                    Write-OutputColor "    [!] $w" -color "Warning"
                }
            }

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'ValidateConfig'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname  = $env:COMPUTERNAME
                    File      = $configPath
                    Valid     = $validation.IsValid
                    Errors    = $validation.Errors
                    Warnings  = $validation.Warnings
                    Summary   = @{
                        ConfigType  = $cfgType
                        Hostname    = $cfgHost
                        ActiveSteps = $activeSteps
                    }
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }

            if (-not $validation.IsValid) { [Environment]::Exit(1) }
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