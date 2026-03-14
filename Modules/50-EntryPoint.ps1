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
        'Watch' {
            # -Config: optional path to thresholds JSON file
            Write-OutputColor "  Running threshold checks..." -color "Info"
            Write-OutputColor "" -color "Info"

            # Load thresholds
            $thresholds = Get-DefaultWatchThresholds
            if ($script:CLIConfig -and (Test-Path -LiteralPath $script:CLIConfig)) {
                try {
                    $customThresholds = Get-Content -LiteralPath $script:CLIConfig -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                    # Merge custom thresholds over defaults
                    foreach ($prop in $customThresholds.PSObject.Properties) {
                        if ($prop.Name -eq 'CPU' -and $null -ne $prop.Value.MaxPercent) {
                            $thresholds.CPU = @{ MaxPercent = $prop.Value.MaxPercent }
                        } elseif ($prop.Name -eq 'Memory' -and $null -ne $prop.Value.MaxPercent) {
                            $thresholds.Memory = @{ MaxPercent = $prop.Value.MaxPercent }
                        } elseif ($prop.Name -eq 'Disk' -and $null -ne $prop.Value.MaxUsedPercent) {
                            $thresholds.Disk = @{ MaxUsedPercent = $prop.Value.MaxUsedPercent }
                        } elseif ($prop.Name -eq 'Uptime' -and $null -ne $prop.Value.MaxDays) {
                            $thresholds.Uptime = @{ MaxDays = $prop.Value.MaxDays }
                        } elseif ($prop.Name -eq 'Certificates' -and $null -ne $prop.Value.MinDaysToExpiry) {
                            $thresholds.Certificates = @{ MinDaysToExpiry = $prop.Value.MinDaysToExpiry }
                        } elseif ($prop.Name -eq 'Services' -and $null -ne $prop.Value.RequireRunning) {
                            $thresholds.Services = @{ RequireRunning = @($prop.Value.RequireRunning) }
                        } elseif ($prop.Name -eq 'Events') {
                            $evtThresh = @{ MaxCriticalCount = 0; HoursBack = 24 }
                            if ($null -ne $prop.Value.MaxCriticalCount) { $evtThresh.MaxCriticalCount = $prop.Value.MaxCriticalCount }
                            if ($null -ne $prop.Value.HoursBack) { $evtThresh.HoursBack = $prop.Value.HoursBack }
                            $thresholds.Events = $evtThresh
                        }
                    }
                } catch {
                    Write-OutputColor "  WARNING: Could not parse thresholds file, using defaults: $_" -color "Warning"
                }
            }

            $watchChecks = Test-WatchThresholds -Thresholds $thresholds
            $alertCount = @($watchChecks | Where-Object { $_.Status -eq 'ALERT' }).Count
            $okCount = @($watchChecks | Where-Object { $_.Status -eq 'OK' }).Count
            $overallStatus = if ($alertCount -gt 0) { "ALERT" } else { "OK" }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  WATCH - THRESHOLD CHECK".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($chk in $watchChecks) {
                $checkName = if ($chk.Check.Length -gt 30) { $chk.Check.Substring(0, 27) + "..." } else { $chk.Check }
                $line = "  $($checkName.PadRight(32)) $("$($chk.Value) $($chk.Unit)".PadRight(18)) [$($chk.Status)]"
                if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                $color = if ($chk.Status -eq 'ALERT') { "Error" } else { "Success" }
                Write-OutputColor "  │$($line.PadRight(72))│" -color $color
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $summaryLine = "  Status: $overallStatus   OK: $okCount   Alerts: $alertCount"
            $summaryColor = if ($alertCount -gt 0) { "Error" } else { "Success" }
            Write-OutputColor "  │$($summaryLine.PadRight(72))│" -color $summaryColor
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool       = $script:ToolFullName
                    Version    = $script:ScriptVersion
                    Action     = 'Watch'
                    Timestamp  = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname   = $env:COMPUTERNAME
                    Status     = $overallStatus
                    AlertCount = $alertCount
                    OKCount    = $okCount
                    Checks     = $watchChecks
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }

            if ($alertCount -gt 0) { [Environment]::Exit(1) }
        }
        'Query' {
            # -Config: "C:\exports,section.field=value"
            if (-not $script:CLIConfig) {
                Write-OutputColor "  ERROR: -Config required." -color "Error"
                Write-OutputColor "  Format: -Config ""C:\exports,section.field=value""" -color "Info"
                Write-OutputColor "  Operators: = (equals), ~ (contains), > (greater), < (less)" -color "Info"
                Write-OutputColor "  Examples:" -color "Info"
                Write-OutputColor "    -Config ""C:\exports,ListeningPorts.LocalPort=3389""" -color "Info"
                Write-OutputColor "    -Config ""C:\exports,Software.Name~SQL""" -color "Info"
                Write-OutputColor "    -Config ""C:\exports,Hardening.Score<60""" -color "Info"
                [Environment]::Exit(1)
            }

            $commaIdx = $script:CLIConfig.IndexOf(',')
            if ($commaIdx -lt 1) {
                Write-OutputColor "  ERROR: -Config must be ""directory,query"" format." -color "Error"
                [Environment]::Exit(1)
            }

            $queryDir = $script:CLIConfig.Substring(0, $commaIdx)
            $queryExpr = $script:CLIConfig.Substring($commaIdx + 1)

            Write-OutputColor "  Querying reports in: $queryDir" -color "Info"
            Write-OutputColor "  Query: $queryExpr" -color "Info"
            Write-OutputColor "" -color "Info"

            $queryResult = Invoke-FleetQuery -ReportDir $queryDir -QueryExpr $queryExpr
            if ($null -eq $queryResult) { [Environment]::Exit(1) }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  FLEET QUERY RESULTS".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Query: $queryExpr".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Reports: $($queryResult.TotalReports)   Matches: $($queryResult.MatchCount)".PadRight(72))│" -color $(if ($queryResult.MatchCount -gt 0) { "Success" } else { "Warning" })
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if ($queryResult.MatchCount -gt 0) {
                foreach ($m in $queryResult.Matches) {
                    $hostLine = "  $($m.Hostname.PadRight(20)) $($m.MatchedValue)"
                    if ($hostLine.Length -gt 72) { $hostLine = $hostLine.Substring(0, 69) + "..." }
                    Write-OutputColor "  │$($hostLine.PadRight(72))│" -color "Info"
                }
            } else {
                Write-OutputColor "  │$("  No matching hosts found.".PadRight(72))│" -color "Warning"
            }
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool         = $script:ToolFullName
                    Version      = $script:ScriptVersion
                    Action       = 'Query'
                    Timestamp    = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname     = $env:COMPUTERNAME
                    Query        = $queryExpr
                    TotalReports = $queryResult.TotalReports
                    MatchCount   = $queryResult.MatchCount
                    Matches      = $queryResult.Matches
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
        }
        'Diff' {
            # -Config: "old.json,new.json"
            if (-not $script:CLIConfig) {
                Write-OutputColor "  ERROR: -Config required. Provide two Export JSON paths." -color "Error"
                Write-OutputColor "  Format: -Config ""old_export.json,new_export.json""" -color "Info"
                [Environment]::Exit(1)
            }

            $commaIdx = $script:CLIConfig.IndexOf(',')
            if ($commaIdx -lt 1) {
                Write-OutputColor "  ERROR: -Config must contain two comma-separated file paths." -color "Error"
                [Environment]::Exit(1)
            }

            $oldPath = $script:CLIConfig.Substring(0, $commaIdx).Trim()
            $newPath = $script:CLIConfig.Substring($commaIdx + 1).Trim()

            if (-not (Test-Path -LiteralPath $oldPath)) {
                Write-OutputColor "  ERROR: Old file not found: $oldPath" -color "Error"
                [Environment]::Exit(1)
            }
            if (-not (Test-Path -LiteralPath $newPath)) {
                Write-OutputColor "  ERROR: New file not found: $newPath" -color "Error"
                [Environment]::Exit(1)
            }

            Write-OutputColor "  Comparing export profiles..." -color "Info"
            Write-OutputColor "  Old: $(Split-Path $oldPath -Leaf)" -color "Info"
            Write-OutputColor "  New: $(Split-Path $newPath -Leaf)" -color "Info"
            Write-OutputColor "" -color "Info"

            $diffResult = Invoke-ExportDiff -OldPath $oldPath -NewPath $newPath
            if ($null -eq $diffResult) { [Environment]::Exit(1) }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  EXPORT DIFF - $($diffResult.Hostname)".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if ($diffResult.TimestampOld) {
                Write-OutputColor "  │$("  Old: $($diffResult.TimestampOld)".PadRight(72))│" -color "Info"
            }
            if ($diffResult.TimestampNew) {
                Write-OutputColor "  │$("  New: $($diffResult.TimestampNew)".PadRight(72))│" -color "Info"
            }
            Write-OutputColor "  │$("  Total Changes: $($diffResult.TotalChanges)".PadRight(72))│" -color $(if ($diffResult.TotalChanges -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

            if ($diffResult.TotalChanges -eq 0) {
                Write-OutputColor "  │$("  No changes detected.".PadRight(72))│" -color "Success"
            } else {
                foreach ($section in $diffResult.ChangedSections) {
                    $chg = $diffResult.Changes[$section]
                    if ($section -eq 'Hardening') {
                        $delta = if ($chg.ScoreDelta -gt 0) { "+$($chg.ScoreDelta)" } else { "$($chg.ScoreDelta)" }
                        Write-OutputColor "  │$("  [$section] Score: $($chg.ScoreOld) -> $($chg.ScoreNew) ($delta)".PadRight(72))│" -color $(if ($chg.ScoreDelta -lt 0) { "Error" } else { "Success" })
                    } elseif ($section -eq 'Health') {
                        Write-OutputColor "  │$("  [$section] $($chg.Old) -> $($chg.New)".PadRight(72))│" -color "Warning"
                    } elseif ($section -eq 'Uptime') {
                        Write-OutputColor "  │$("  [$section] Rebooted ($($chg.OldDays)d -> $($chg.NewDays)d)".PadRight(72))│" -color "Info"
                    } else {
                        $parts = @()
                        if ($chg.Added.Count -gt 0) { $parts += "+$($chg.Added.Count) added" }
                        if ($chg.Removed.Count -gt 0) { $parts += "-$($chg.Removed.Count) removed" }
                        if ($chg.Changed.Count -gt 0) { $parts += "$($chg.Changed.Count) changed" }
                        Write-OutputColor "  │$("  [$section] $($parts -join ', ')".PadRight(72))│" -color "Warning"
                    }
                }
            }
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool            = $script:ToolFullName
                    Version         = $script:ScriptVersion
                    Action          = 'Diff'
                    Timestamp       = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname        = $diffResult.Hostname
                    TimestampOld    = $diffResult.TimestampOld
                    TimestampNew    = $diffResult.TimestampNew
                    TotalChanges    = $diffResult.TotalChanges
                    ChangedSections = $diffResult.ChangedSections
                    Changes         = $diffResult.Changes
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }

            if ($diffResult.TotalChanges -gt 0) { [Environment]::Exit(1) }
        }
        'Baseline' {
            # -Config: directory to save baseline (or directory to check for latest)
            # -Tier: Save (default), Status
            $subCommand = if ($script:CLIProfile -and $script:CLIProfile -ne 'Standard') { $script:CLIProfile } else { 'Save' }

            switch ($subCommand) {
                'Save' {
                    $baselineDir = if ($script:CLIConfig) { $script:CLIConfig } else { "$script:TempPath\baselines" }

                    Write-OutputColor "  Capturing baseline Export..." -color "Info"
                    Write-OutputColor "" -color "Info"

                    # Run a full Export to collect all data (reuse Export internals)
                    $exportAllSections = @('Health', 'Inventory', 'Hardening', 'Snapshot', 'Certificates', 'ListeningPorts', 'Software', 'Uptime', 'Services', 'Events', 'Network')
                    $exportData = @{
                        Tool      = $script:ToolFullName
                        Version   = $script:ScriptVersion
                        Action    = 'Export'
                        Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                        Hostname  = $env:COMPUTERNAME
                        Sections  = $exportAllSections
                    }

                    # Collect each section
                    try { $exportData['Health'] = Show-SystemHealthCheck } catch { }
                    try { $exportData['Inventory'] = Get-ServerInventory } catch { }
                    try {
                        $hardenChecks = Get-SecurityHardeningChecks
                        $hardenPassCount = @($hardenChecks | Where-Object { $_.Status -eq 'Pass' }).Count
                        $hardenTotalCount = @($hardenChecks).Count
                        $hardenScore = if ($hardenTotalCount -gt 0) { [math]::Round(($hardenPassCount / $hardenTotalCount) * 100, 0) } else { 0 }
                        $exportData['Hardening'] = @{ Score = $hardenScore; Passed = $hardenPassCount; Total = $hardenTotalCount; Checks = $hardenChecks }
                    } catch { }
                    try { $exportData['Snapshot'] = Save-PerformanceSnapshot } catch { }

                    $savedPath = Save-ExportBaseline -BaselineDir $baselineDir -ExportData $exportData

                    if ($null -ne $savedPath) {
                        Write-OutputColor "  Baseline saved: $savedPath" -color "Success"
                    } else {
                        Write-OutputColor "  ERROR: Failed to save baseline." -color "Error"
                        [Environment]::Exit(1)
                    }

                    if ($script:CLIOutputFormat -eq 'JSON') {
                        $jsonResult = @{
                            Tool      = $script:ToolFullName
                            Version   = $script:ScriptVersion
                            Action    = 'Baseline'
                            SubAction = 'Save'
                            Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                            Hostname  = $env:COMPUTERNAME
                            Path      = $savedPath
                            Sections  = $exportAllSections
                        }
                        Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
                    }
                }
                'Status' {
                    $baselineDir = if ($script:CLIConfig) { $script:CLIConfig } else { "$script:TempPath\baselines" }

                    Write-OutputColor "  Checking for baseline in: $baselineDir" -color "Info"
                    Write-OutputColor "" -color "Info"

                    $latestPath = Get-LatestBaseline -BaselineDir $baselineDir -Hostname $env:COMPUTERNAME
                    $hasBaseline = $null -ne $latestPath

                    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
                    Write-OutputColor "  │$("  BASELINE STATUS".PadRight(72))│" -color "Info"
                    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                    if ($hasBaseline) {
                        $baselineFile = Split-Path $latestPath -Leaf
                        $baselineDate = (Get-Item $latestPath).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                        Write-OutputColor "  │$("  Baseline: $baselineFile".PadRight(72))│" -color "Success"
                        Write-OutputColor "  │$("  Date:     $baselineDate".PadRight(72))│" -color "Info"
                    } else {
                        Write-OutputColor "  │$("  No baseline found for $env:COMPUTERNAME".PadRight(72))│" -color "Warning"
                    }
                    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

                    if ($script:CLIOutputFormat -eq 'JSON') {
                        $jsonResult = @{
                            Tool        = $script:ToolFullName
                            Version     = $script:ScriptVersion
                            Action      = 'Baseline'
                            SubAction   = 'Status'
                            Timestamp   = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                            Hostname    = $env:COMPUTERNAME
                            HasBaseline = $hasBaseline
                            Path        = $latestPath
                        }
                        Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
                    }
                }
                default {
                    Write-OutputColor "  ERROR: Unknown Baseline sub-command: $subCommand" -color "Error"
                    Write-OutputColor "  Valid: Save, Status" -color "Info"
                    [Environment]::Exit(1)
                }
            }
        }
        'Alert' {
            # -Config: path to alert configuration JSON
            # -Tier: Test (send test notification), Watch (default), Diff
            if (-not $script:CLIConfig) {
                Write-OutputColor "  ERROR: -Config required. Provide path to alert config JSON." -color "Error"
                Write-OutputColor "  Format: -Config ""C:\alert-config.json""" -color "Info"
                Write-OutputColor "  Sub-commands via -Tier: Watch (default), Diff, Test" -color "Info"
                [Environment]::Exit(1)
            }

            if (-not (Test-Path -LiteralPath $script:CLIConfig)) {
                Write-OutputColor "  ERROR: Alert config not found: $($script:CLIConfig)" -color "Error"
                [Environment]::Exit(1)
            }

            try {
                $alertConfig = Get-Content -LiteralPath $script:CLIConfig -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                # Convert PSObject to hashtable for Channels
                $alertHashConfig = @{ Channels = $alertConfig.Channels }
            } catch {
                Write-OutputColor "  ERROR: Failed to parse alert config: $($_.Exception.Message)" -color "Error"
                [Environment]::Exit(1)
            }

            $alertMode = if ($script:CLIProfile -and $script:CLIProfile -ne 'Standard') { $script:CLIProfile } else { 'Watch' }
            $alertData = $null
            $triggered = $false

            switch ($alertMode) {
                'Test' {
                    Write-OutputColor "  Sending test notification to all channels..." -color "Info"
                    $alertData = @{
                        Action     = 'Alert'
                        Hostname   = $env:COMPUTERNAME
                        Timestamp  = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                        AlertCount = 1
                        Checks     = @(@{ Check = 'Test'; Status = 'ALERT'; Value = 'Test notification'; Unit = '' })
                    }
                    $triggered = $true
                }
                'Diff' {
                    if (-not $alertConfig.DiffPaths -or -not $alertConfig.DiffPaths.Old -or -not $alertConfig.DiffPaths.New) {
                        Write-OutputColor "  ERROR: Alert config must include DiffPaths.Old and DiffPaths.New for Diff mode." -color "Error"
                        [Environment]::Exit(1)
                    }
                    Write-OutputColor "  Running Diff detection..." -color "Info"
                    $diffResult = Invoke-ExportDiff -OldPath $alertConfig.DiffPaths.Old -NewPath $alertConfig.DiffPaths.New
                    if ($null -eq $diffResult) { [Environment]::Exit(1) }
                    if ($diffResult.TotalChanges -gt 0) {
                        $alertData = @{
                            Action          = 'Alert'
                            Hostname        = $diffResult.Hostname
                            Timestamp       = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                            AlertCount      = $diffResult.TotalChanges
                            TotalChanges    = $diffResult.TotalChanges
                            ChangedSections = $diffResult.ChangedSections
                        }
                        $triggered = $true
                    }
                }
                default {
                    # Watch mode (default)
                    Write-OutputColor "  Running Watch detection..." -color "Info"
                    $thresholds = Get-DefaultWatchThresholds
                    if ($null -ne $alertConfig.Thresholds) {
                        foreach ($prop in $alertConfig.Thresholds.PSObject.Properties) {
                            if ($prop.Name -eq 'CPU' -and $null -ne $prop.Value.MaxPercent) {
                                $thresholds.CPU = @{ MaxPercent = $prop.Value.MaxPercent }
                            } elseif ($prop.Name -eq 'Memory' -and $null -ne $prop.Value.MaxPercent) {
                                $thresholds.Memory = @{ MaxPercent = $prop.Value.MaxPercent }
                            } elseif ($prop.Name -eq 'Disk' -and $null -ne $prop.Value.MaxUsedPercent) {
                                $thresholds.Disk = @{ MaxUsedPercent = $prop.Value.MaxUsedPercent }
                            }
                        }
                    }
                    $watchChecks = Test-WatchThresholds -Thresholds $thresholds
                    $watchAlertCount = @($watchChecks | Where-Object { $_.Status -eq 'ALERT' }).Count
                    if ($watchAlertCount -gt 0) {
                        $alertData = @{
                            Action     = 'Alert'
                            Hostname   = $env:COMPUTERNAME
                            Timestamp  = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                            AlertCount = $watchAlertCount
                            Checks     = $watchChecks
                        }
                        $triggered = $true
                    }
                }
            }

            if ($triggered -and $null -ne $alertData) {
                $dispatchResult = Invoke-AlertDispatch -AlertConfig $alertHashConfig -AlertData $alertData
                Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
                Write-OutputColor "  │$("  ALERT DISPATCH - $($alertData.Hostname)".PadRight(72))│" -color "Info"
                Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                Write-OutputColor "  │$("  Mode: $alertMode   Alerts: $($alertData.AlertCount)".PadRight(72))│" -color "Warning"
                foreach ($cr in $dispatchResult.ChannelResults) {
                    $statusText = if ($cr.Success) { "OK" } else { "FAILED" }
                    $color = if ($cr.Success) { "Success" } else { "Error" }
                    $line = "  $($cr.Channel.PadRight(20)) [$statusText]"
                    if (-not $cr.Success -and $cr.Error) { $line += " $($cr.Error)" }
                    if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                    Write-OutputColor "  │$($line.PadRight(72))│" -color $color
                }
                Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                $summaryLine = "  Dispatched: $($dispatchResult.Dispatched)   OK: $($dispatchResult.Succeeded)   Failed: $($dispatchResult.Failed)"
                Write-OutputColor "  │$($summaryLine.PadRight(72))│" -color $(if ($dispatchResult.Failed -gt 0) { "Error" } else { "Success" })
                Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            } else {
                Write-OutputColor "  No alerts detected. No notifications sent." -color "Success"
            }

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool           = $script:ToolFullName
                    Version        = $script:ScriptVersion
                    Action         = 'Alert'
                    Mode           = $alertMode
                    Timestamp      = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname       = $env:COMPUTERNAME
                    Triggered      = $triggered
                    AlertCount     = if ($null -ne $alertData) { $alertData.AlertCount } else { 0 }
                    ChannelResults = if ($null -ne $dispatchResult) { $dispatchResult.ChannelResults } else { @() }
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }

            if ($null -ne $dispatchResult -and $dispatchResult.Failed -gt 0) { [Environment]::Exit(1) }
        }
        'FleetScan' {
            # -Config: path to fleet scan configuration JSON
            if (-not $script:CLIConfig) {
                Write-OutputColor "  ERROR: -Config required. Provide path to fleet scan config JSON." -color "Error"
                Write-OutputColor "  Format: -Config ""C:\fleet-config.json""" -color "Info"
                Write-OutputColor "  Config: { ""Targets"": [...], ""Action"": ""Watch"", ""Parallel"": 5, ""TimeoutSeconds"": 300 }" -color "Info"
                [Environment]::Exit(1)
            }

            if (-not (Test-Path -LiteralPath $script:CLIConfig)) {
                Write-OutputColor "  ERROR: Fleet config not found: $($script:CLIConfig)" -color "Error"
                [Environment]::Exit(1)
            }

            try {
                $fleetConfig = Get-Content -LiteralPath $script:CLIConfig -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Write-OutputColor "  ERROR: Failed to parse fleet config: $($_.Exception.Message)" -color "Error"
                [Environment]::Exit(1)
            }

            if (-not $fleetConfig.Targets -or -not $fleetConfig.Action) {
                Write-OutputColor "  ERROR: Fleet config must include Targets and Action fields." -color "Error"
                [Environment]::Exit(1)
            }

            $targets = Get-FleetTargets -Targets $fleetConfig.Targets
            if ($null -eq $targets -or $targets.Count -eq 0) {
                Write-OutputColor "  ERROR: No valid targets found." -color "Error"
                [Environment]::Exit(1)
            }

            $parallel = if ($null -ne $fleetConfig.Parallel) { $fleetConfig.Parallel } else { 5 }
            $timeout = if ($null -ne $fleetConfig.TimeoutSeconds) { $fleetConfig.TimeoutSeconds } else { 300 }
            $actionConfig = if ($fleetConfig.ActionConfig) { "$($fleetConfig.ActionConfig)" } else { $null }
            $actionTier = if ($fleetConfig.ActionTier) { "$($fleetConfig.ActionTier)" } else { $null }

            Write-OutputColor "  Fleet Scan: $($fleetConfig.Action) on $($targets.Count) target(s)" -color "Info"
            Write-OutputColor "  Parallel: $parallel   Timeout: ${timeout}s" -color "Info"
            Write-OutputColor "" -color "Info"

            $fleetResults = Invoke-FleetAction -Targets $targets -Action $fleetConfig.Action -ActionConfig $actionConfig -ActionTier $actionTier -Parallel $parallel -TimeoutSeconds $timeout

            $successCount = @($fleetResults | Where-Object { $_.Status -eq 'Success' }).Count
            $failCount = @($fleetResults | Where-Object { $_.Status -eq 'Failed' }).Count
            $timeoutCount = @($fleetResults | Where-Object { $_.Status -eq 'Timeout' }).Count

            # Save results if OutputDir specified
            $savedPath = $null
            if ($fleetConfig.OutputDir) {
                $savedPath = Save-FleetResults -OutputDir $fleetConfig.OutputDir -Results $fleetResults -Action $fleetConfig.Action
            }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  FLEET SCAN - $($fleetConfig.Action)".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($r in $fleetResults) {
                $statusIcon = switch ($r.Status) { 'Success' { 'OK' } 'Failed' { 'FAIL' } 'Timeout' { 'TIME' } default { '??' } }
                $line = "  $($r.Hostname.PadRight(25)) [$statusIcon]  $($r.Duration)s"
                if ($r.Error) { $line += "  $($r.Error)" }
                if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                $color = switch ($r.Status) { 'Success' { 'Success' } 'Failed' { 'Error' } 'Timeout' { 'Warning' } default { 'Info' } }
                Write-OutputColor "  │$($line.PadRight(72))│" -color $color
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $summaryLine = "  Total: $($targets.Count)   OK: $successCount   Failed: $failCount   Timeout: $timeoutCount"
            Write-OutputColor "  │$($summaryLine.PadRight(72))│" -color $(if ($failCount -gt 0 -or $timeoutCount -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($null -ne $savedPath) {
                Write-OutputColor "  Results saved: $savedPath" -color "Info"
            }

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool           = $script:ToolFullName
                    Version        = $script:ScriptVersion
                    Action         = 'FleetScan'
                    Timestamp      = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname       = $env:COMPUTERNAME
                    TargetAction   = $fleetConfig.Action
                    TotalTargets   = $targets.Count
                    Succeeded      = $successCount
                    Failed         = $failCount
                    TimedOut        = $timeoutCount
                    Results        = $fleetResults
                }
                if ($null -ne $savedPath) { $jsonResult['OutputPath'] = $savedPath }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }

            if ($failCount -gt 0 -or $timeoutCount -gt 0) { [Environment]::Exit(1) }
        }
        'PatchStatus' {
            # -Config: optional, max number of recent updates to return (default 15)
            $maxRecent = 15
            if ($script:CLIConfig -and $script:CLIConfig -match '^\d+$') {
                $maxRecent = [int]$script:CLIConfig
            }

            Write-OutputColor "  Checking patch status..." -color "Info"
            Write-OutputColor "" -color "Info"

            # Last installed hotfix
            $lastPatch = $null
            $daysSinceLastPatch = $null
            try {
                $hotfixes = @(Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending -ErrorAction SilentlyContinue)
                if ($hotfixes.Count -gt 0) {
                    $hf = $hotfixes[0]
                    $installedDate = if ($null -ne $hf.InstalledOn) { $hf.InstalledOn } else { $null }
                    $daysSince = if ($null -ne $installedDate) { [math]::Round(((Get-Date) - $installedDate).TotalDays, 0) } else { $null }
                    $lastPatch = @{
                        KBID        = $hf.HotFixID
                        InstalledOn = if ($null -ne $installedDate) { $installedDate.ToString("yyyy-MM-dd") } else { "Unknown" }
                        DaysSince   = $daysSince
                    }
                    $daysSinceLastPatch = $daysSince
                }
            } catch { }

            # Patch currency classification
            $patchCurrency = 'Unknown'
            if ($null -ne $daysSinceLastPatch) {
                if ($daysSinceLastPatch -le 30) { $patchCurrency = 'OK' }
                elseif ($daysSinceLastPatch -le 60) { $patchCurrency = 'Warning' }
                else { $patchCurrency = 'Critical' }
            }

            # Pending reboot detection
            $pendingReboot = $false
            $rebootKeys = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
            )
            foreach ($rk in $rebootKeys) {
                if (Test-Path -LiteralPath $rk -ErrorAction SilentlyContinue) { $pendingReboot = $true; break }
            }

            # Windows Update service status
            $wuService = $null
            try {
                $svc = Get-Service -Name wuauserv -ErrorAction Stop
                $wuService = @{ Status = "$($svc.Status)"; StartType = "$($svc.StartupType)" }
            } catch { }

            # Recent update history via COM
            $recentUpdates = @()
            $succeeded = 0; $failed = 0
            try {
                $session = New-Object -ComObject Microsoft.Update.Session
                $searcher = $session.CreateUpdateSearcher()
                $totalHistory = $searcher.GetTotalHistoryCount()
                $count = [math]::Min($maxRecent, $totalHistory)
                if ($count -gt 0) {
                    $history = $searcher.QueryHistory(0, $count)
                    for ($i = 0; $i -lt $history.Count; $i++) {
                        $entry = $history.Item($i)
                        $resultText = switch ($entry.ResultCode) { 0 { 'NotStarted' } 1 { 'InProgress' } 2 { 'Succeeded' } 3 { 'SucceededWithErrors' } 4 { 'Failed' } 5 { 'Aborted' } default { 'Unknown' } }
                        $kbMatch = ''
                        if ($entry.Title -match 'KB\d+') { $regexMatches = $Matches; $kbMatch = $regexMatches[0] }
                        $recentUpdates += @{
                            Title  = "$($entry.Title)"
                            Date   = $entry.Date.ToString("yyyy-MM-ddTHH:mm:ss")
                            Result = $resultText
                            KBID   = $kbMatch
                        }
                        if ($resultText -eq 'Succeeded' -or $resultText -eq 'SucceededWithErrors') { $succeeded++ }
                        elseif ($resultText -eq 'Failed') { $failed++ }
                    }
                }
            } catch { }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  PATCH STATUS - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if ($null -ne $lastPatch) {
                Write-OutputColor "  │$("  Last Patch:     $($lastPatch.KBID) ($($lastPatch.InstalledOn), $($lastPatch.DaysSince) days ago)".PadRight(72))│" -color "Info"
            } else {
                Write-OutputColor "  │$("  Last Patch:     Unknown".PadRight(72))│" -color "Warning"
            }
            $currencyColor = switch ($patchCurrency) { 'OK' { 'Success' } 'Warning' { 'Warning' } 'Critical' { 'Error' } default { 'Warning' } }
            Write-OutputColor "  │$("  Patch Currency: $patchCurrency".PadRight(72))│" -color $currencyColor
            $rebootColor = if ($pendingReboot) { "Warning" } else { "Success" }
            Write-OutputColor "  │$("  Pending Reboot: $pendingReboot".PadRight(72))│" -color $rebootColor
            if ($null -ne $wuService) {
                Write-OutputColor "  │$("  WU Service:     $($wuService.Status) ($($wuService.StartType))".PadRight(72))│" -color "Info"
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $summaryLine = "  Recent: $($recentUpdates.Count)   Succeeded: $succeeded   Failed: $failed"
            Write-OutputColor "  │$($summaryLine.PadRight(72))│" -color $(if ($failed -gt 0) { "Warning" } else { "Info" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool          = $script:ToolFullName
                    Version       = $script:ScriptVersion
                    Action        = 'PatchStatus'
                    Timestamp     = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname      = $env:COMPUTERNAME
                    LastPatch     = $lastPatch
                    PatchCurrency = $patchCurrency
                    PendingReboot = $pendingReboot
                    UpdateService = $wuService
                    RecentUpdates = $recentUpdates
                    Summary       = @{
                        TotalRecent        = $recentUpdates.Count
                        Succeeded          = $succeeded
                        Failed             = $failed
                        DaysSinceLastPatch = $daysSinceLastPatch
                    }
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }

            if ($patchCurrency -eq 'Critical' -or $pendingReboot) { [Environment]::Exit(1) }
        }
        'UserAudit' {
            # -Config: optional "passwordAgeDays,staleLoginDays" thresholds (default: 365,90)
            $pwdAgeThreshold = 365
            $staleLoginThreshold = 90
            if ($script:CLIConfig -and $script:CLIConfig -match '^\d+,\d+$') {
                $parts = $script:CLIConfig.Split(',')
                $pwdAgeThreshold = [int]$parts[0]
                $staleLoginThreshold = [int]$parts[1]
            }

            Write-OutputColor "  Auditing local user accounts..." -color "Info"
            Write-OutputColor "" -color "Info"

            $accounts = @()
            $issueCount = 0
            $adminCount = 0

            # Get Administrators group members
            $adminMembers = @()
            try {
                $adminMembers = @(Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name -replace '^.*\\', '' })
            } catch { }

            try {
                $localUsers = @(Get-LocalUser -ErrorAction Stop)
                foreach ($user in $localUsers) {
                    $flags = @()
                    $isAdmin = $adminMembers -contains $user.Name
                    if ($isAdmin) { $adminCount++ }

                    $pwdAgeDays = $null
                    if ($null -ne $user.PasswordLastSet) {
                        $pwdAgeDays = [math]::Round(((Get-Date) - $user.PasswordLastSet).TotalDays, 0)
                        if ($user.Enabled -and $pwdAgeDays -gt $pwdAgeThreshold) { $flags += 'OLD PWD' }
                        elseif ($user.Enabled -and $pwdAgeDays -gt 90) { $flags += 'AGING' }
                    }

                    $lastLogonDays = $null
                    if ($null -ne $user.LastLogon) {
                        $lastLogonDays = [math]::Round(((Get-Date) - $user.LastLogon).TotalDays, 0)
                        if ($user.Enabled -and $lastLogonDays -gt $staleLoginThreshold) { $flags += 'STALE' }
                    } elseif ($user.Enabled) {
                        $flags += 'NO LOGIN'
                    }

                    $pwdExpires = 'N/A'
                    if ($user.PasswordNeverExpires) { $pwdExpires = 'Never' }
                    elseif ($null -ne $user.PasswordExpires) { $pwdExpires = $user.PasswordExpires.ToString("yyyy-MM-dd") }

                    if ($user.Enabled -and $user.PasswordExpires -and $user.PasswordExpires -lt (Get-Date)) {
                        $flags += 'EXPIRED'
                    }

                    if ($flags.Count -gt 0) { $issueCount++ }

                    $accounts += @{
                        Name            = $user.Name
                        Enabled         = $user.Enabled
                        PasswordLastSet = if ($null -ne $user.PasswordLastSet) { $user.PasswordLastSet.ToString("yyyy-MM-ddTHH:mm:ss") } else { $null }
                        PasswordAgeDays = $pwdAgeDays
                        LastLogon       = if ($null -ne $user.LastLogon) { $user.LastLogon.ToString("yyyy-MM-ddTHH:mm:ss") } else { $null }
                        LastLogonDays   = $lastLogonDays
                        PasswordExpires = $pwdExpires
                        IsAdmin         = $isAdmin
                        Flags           = $flags
                    }
                }
            } catch {
                Write-OutputColor "  ERROR: Failed to query local users: $($_.Exception.Message)" -color "Error"
                [Environment]::Exit(1)
            }

            $enabledCount = @($accounts | Where-Object { $_.Enabled }).Count
            $disabledCount = @($accounts | Where-Object { -not $_.Enabled }).Count

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  USER AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($acct in $accounts) {
                $status = if ($acct.Enabled) { "ON " } else { "OFF" }
                $flagText = if ($acct.Flags.Count -gt 0) { " [$(($acct.Flags -join ', '))]" } else { "" }
                $adminTag = if ($acct.IsAdmin) { " (Admin)" } else { "" }
                $line = "  $($acct.Name.PadRight(22)) $status$adminTag$flagText"
                if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                $color = if ($acct.Flags.Count -gt 0) { "Warning" } elseif (-not $acct.Enabled) { "Info" } else { "Success" }
                Write-OutputColor "  │$($line.PadRight(72))│" -color $color
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $summaryLine = "  Total: $($accounts.Count)   Enabled: $enabledCount   Disabled: $disabledCount   Issues: $issueCount   Admins: $adminCount"
            Write-OutputColor "  │$($summaryLine.PadRight(72))│" -color $(if ($issueCount -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'UserAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname  = $env:COMPUTERNAME
                    Summary   = @{
                        Total          = $accounts.Count
                        Enabled        = $enabledCount
                        Disabled       = $disabledCount
                        Issues         = $issueCount
                        Administrators = $adminCount
                    }
                    Accounts  = $accounts
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }

            if ($issueCount -gt 0) { [Environment]::Exit(1) }
        }
        'FirewallAudit' {
            Write-OutputColor "  Auditing firewall configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $fwIssues = 0
            $profiles = @()

            # Check firewall profiles
            try {
                $fwProfiles = @(Get-NetFirewallProfile -ErrorAction Stop)
                foreach ($p in $fwProfiles) {
                    $enabled = $p.Enabled -eq $true
                    $status = 'OK'
                    if (-not $enabled) { $status = 'WARN'; $fwIssues++ }
                    if ($p.Name -eq 'Public' -and -not $enabled) { $status = 'CRITICAL' }
                    if ($p.Name -eq 'Public' -and "$($p.DefaultInboundAction)" -eq 'Allow') { $status = 'CRITICAL'; $fwIssues++ }

                    $profiles += @{
                        Name            = $p.Name
                        Enabled         = $enabled
                        DefaultInbound  = "$($p.DefaultInboundAction)"
                        DefaultOutbound = "$($p.DefaultOutboundAction)"
                        Status          = $status
                    }
                }
            } catch {
                Write-OutputColor "  ERROR: Failed to query firewall profiles: $($_.Exception.Message)" -color "Error"
                [Environment]::Exit(1)
            }

            # Count firewall rules
            $totalRules = 0; $enabledRules = 0; $disabledRules = 0
            $inboundAllow = 0; $inboundBlock = 0; $outboundAllow = 0; $outboundBlock = 0
            $topGroups = @()
            try {
                $allRules = @(Get-NetFirewallRule -ErrorAction Stop)
                $totalRules = $allRules.Count
                $enabledRules = @($allRules | Where-Object { $_.Enabled -eq 'True' }).Count
                $disabledRules = $totalRules - $enabledRules
                $enabledOnly = @($allRules | Where-Object { $_.Enabled -eq 'True' })
                $inboundAllow = @($enabledOnly | Where-Object { $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow' }).Count
                $inboundBlock = @($enabledOnly | Where-Object { $_.Direction -eq 'Inbound' -and $_.Action -eq 'Block' }).Count
                $outboundAllow = @($enabledOnly | Where-Object { $_.Direction -eq 'Outbound' -and $_.Action -eq 'Allow' }).Count
                $outboundBlock = @($enabledOnly | Where-Object { $_.Direction -eq 'Outbound' -and $_.Action -eq 'Block' }).Count

                # Top inbound allow groups
                $inboundAllowRules = @($enabledOnly | Where-Object { $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow' -and $_.DisplayGroup })
                $grouped = $inboundAllowRules | Group-Object DisplayGroup | Sort-Object Count -Descending | Select-Object -First 10
                foreach ($g in $grouped) {
                    $topGroups += @{ Group = $g.Name; Count = $g.Count }
                }
            } catch {
                Write-OutputColor "  WARNING: Could not enumerate firewall rules: $($_.Exception.Message)" -color "Warning"
            }

            $profilesDisabled = @($profiles | Where-Object { -not $_.Enabled }).Count

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  FIREWALL AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($p in $profiles) {
                $line = "  $($p.Name.PadRight(12)) Enabled: $($p.Enabled)  In: $($p.DefaultInbound)  Out: $($p.DefaultOutbound)  [$($p.Status)]"
                if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                $color = switch ($p.Status) { 'OK' { 'Success' } 'WARN' { 'Warning' } 'CRITICAL' { 'Error' } default { 'Info' } }
                Write-OutputColor "  │$($line.PadRight(72))│" -color $color
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Rules: $totalRules total, $enabledRules enabled, $disabledRules disabled".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Inbound: $inboundAllow allow, $inboundBlock block   Out: $outboundAllow allow, $outboundBlock block".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Profiles disabled: $profilesDisabled   Issues: $fwIssues".PadRight(72))│" -color $(if ($fwIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool     = $script:ToolFullName
                    Version  = $script:ScriptVersion
                    Action   = 'FirewallAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname = $env:COMPUTERNAME
                    Summary  = @{
                        TotalRules       = $totalRules
                        EnabledRules     = $enabledRules
                        DisabledRules    = $disabledRules
                        InboundAllow     = $inboundAllow
                        InboundBlock     = $inboundBlock
                        OutboundAllow    = $outboundAllow
                        OutboundBlock    = $outboundBlock
                        ProfilesDisabled = $profilesDisabled
                        Issues           = $fwIssues
                    }
                    Profiles        = $profiles
                    TopInboundGroups = $topGroups
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }

            if ($fwIssues -gt 0) { [Environment]::Exit(1) }
        }
        'TaskAudit' {
            Write-OutputColor "  Auditing scheduled tasks..." -color "Info"
            Write-OutputColor "" -color "Info"

            $tasks = @()
            $failedCount = 0
            $neverRunCount = 0

            try {
                $scheduledTasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notmatch '^\\Microsoft\\' -and $_.State -ne 'Disabled' })

                foreach ($t in $scheduledTasks) {
                    $taskInfo = $null
                    try { $taskInfo = $t | Get-ScheduledTaskInfo -ErrorAction Stop } catch { $taskInfo = $null }

                    $lastRun = $null
                    $lastResult = $null
                    $lastResultHex = $null
                    $nextRun = $null
                    $health = 'OK'

                    if ($null -ne $taskInfo) {
                        if ($null -ne $taskInfo.LastRunTime -and $taskInfo.LastRunTime.Year -gt 1999) {
                            $lastRun = $taskInfo.LastRunTime.ToString("yyyy-MM-ddTHH:mm:ss")
                        }
                        $lastResult = $taskInfo.LastTaskResult
                        $lastResultHex = "0x{0:X}" -f $taskInfo.LastTaskResult

                        if ($null -ne $taskInfo.NextRunTime -and $taskInfo.NextRunTime.Year -gt 1999) {
                            $nextRun = $taskInfo.NextRunTime.ToString("yyyy-MM-ddTHH:mm:ss")
                        }

                        # Classify health
                        if ($null -eq $lastRun) {
                            $health = 'NeverRun'; $neverRunCount++
                        } elseif ($lastResult -ne 0 -and $lastResult -ne 0x00041300 -and $lastResult -ne 0x00041303) {
                            $health = 'FAIL'; $failedCount++
                        }
                    } else {
                        $health = 'NeverRun'; $neverRunCount++
                    }

                    $tasks += @{
                        Name          = $t.TaskName
                        Path          = $t.TaskPath
                        State         = "$($t.State)"
                        LastRun       = $lastRun
                        LastResult    = $lastResult
                        LastResultHex = $lastResultHex
                        NextRun       = $nextRun
                        Health        = $health
                    }
                }
            } catch {
                Write-OutputColor "  ERROR: Failed to query scheduled tasks: $($_.Exception.Message)" -color "Error"
                [Environment]::Exit(1)
            }

            $healthyCount = @($tasks | Where-Object { $_.Health -eq 'OK' }).Count

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  TASK AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (@($tasks).Count -eq 0) {
                Write-OutputColor "  │$("  (No non-Microsoft scheduled tasks found)".PadRight(72))│" -color "Info"
            } else {
                foreach ($t in $tasks) {
                    $taskName = if ($t.Name.Length -gt 30) { $t.Name.Substring(0, 27) + "..." } else { $t.Name }
                    $line = "  $($taskName.PadRight(32)) [$($t.Health)]"
                    if ($t.LastRun) { $line += "  Last: $($t.LastRun.Substring(0, 10))" }
                    if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                    $color = switch ($t.Health) { 'OK' { 'Success' } 'FAIL' { 'Error' } 'NeverRun' { 'Warning' } default { 'Info' } }
                    Write-OutputColor "  │$($line.PadRight(72))│" -color $color
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $summaryLine = "  Total: $(@($tasks).Count)   Healthy: $healthyCount   Failed: $failedCount   Never Run: $neverRunCount"
            Write-OutputColor "  │$($summaryLine.PadRight(72))│" -color $(if ($failedCount -gt 0) { "Error" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'TaskAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname  = $env:COMPUTERNAME
                    Summary   = @{
                        Total    = @($tasks).Count
                        Healthy  = $healthyCount
                        Failed   = $failedCount
                        NeverRun = $neverRunCount
                    }
                    Tasks     = $tasks
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }

            if ($failedCount -gt 0) { [Environment]::Exit(1) }
        }
        'DiskAudit' {
            Write-OutputColor "  Auditing disk health and utilization..." -color "Info"
            Write-OutputColor "" -color "Info"

            $diskIssues = 0
            $volumes = @()
            $physicalDisks = @()

            # Physical disk health
            try {
                $pDisks = @(Get-PhysicalDisk -ErrorAction Stop)
                foreach ($d in $pDisks) {
                    $health = 'OK'
                    if ($d.HealthStatus -ne 'Healthy') { $health = 'FAIL'; $diskIssues++ }
                    if ($d.OperationalStatus -ne 'OK') { $health = 'FAIL'; if ($d.HealthStatus -eq 'Healthy') { $diskIssues++ } }
                    $sizeGB = [math]::Round($d.Size / 1GB, 1)
                    $physicalDisks += @{
                        DeviceId          = $d.DeviceId
                        FriendlyName      = $d.FriendlyName
                        MediaType         = "$($d.MediaType)"
                        BusType           = "$($d.BusType)"
                        SizeGB            = $sizeGB
                        HealthStatus      = "$($d.HealthStatus)"
                        OperationalStatus = "$($d.OperationalStatus)"
                        Health            = $health
                    }
                }
            } catch {
                Write-OutputColor "  WARNING: Could not query physical disks: $($_.Exception.Message)" -color "Warning"
            }

            # Volume utilization
            try {
                $vols = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop)
                foreach ($v in $vols) {
                    $totalGB = [math]::Round($v.Size / 1GB, 1)
                    $freeGB = [math]::Round($v.FreeSpace / 1GB, 1)
                    $usedGB = [math]::Round(($v.Size - $v.FreeSpace) / 1GB, 1)
                    $pctFree = if ($v.Size -gt 0) { [math]::Round(($v.FreeSpace / $v.Size) * 100, 1) } else { 0 }
                    $status = 'OK'
                    if ($pctFree -lt 10) { $status = 'WARN'; $diskIssues++ }
                    if ($pctFree -lt 5) { $status = 'CRITICAL' }
                    $volumes += @{
                        Drive    = $v.DeviceID
                        Label    = $v.VolumeName
                        TotalGB  = $totalGB
                        UsedGB   = $usedGB
                        FreeGB   = $freeGB
                        PctFree  = $pctFree
                        Status   = $status
                    }
                }
            } catch {
                Write-OutputColor "  ERROR: Failed to query volumes: $($_.Exception.Message)" -color "Error"
                [Environment]::Exit(1)
            }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  DISK AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (@($physicalDisks).Count -gt 0) {
                Write-OutputColor "  │$("  PHYSICAL DISKS".PadRight(72))│" -color "Info"
                foreach ($d in $physicalDisks) {
                    $line = "  $($d.FriendlyName)"
                    if ($line.Length -gt 35) { $line = $line.Substring(0, 32) + "..." }
                    $line = "$($line.PadRight(36)) $($d.SizeGB)GB  $($d.MediaType)  [$($d.Health)]"
                    if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                    $color = if ($d.Health -eq 'OK') { 'Success' } else { 'Error' }
                    Write-OutputColor "  │$($line.PadRight(72))│" -color $color
                }
                Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            }
            Write-OutputColor "  │$("  VOLUMES".PadRight(72))│" -color "Info"
            foreach ($v in $volumes) {
                $label = if ($v.Label) { " ($($v.Label))" } else { "" }
                $line = "  $($v.Drive)$label"
                if ($line.Length -gt 20) { $line = $line.Substring(0, 17) + "..." }
                $line = "$($line.PadRight(22)) $($v.UsedGB)/$($v.TotalGB)GB  Free: $($v.PctFree)%  [$($v.Status)]"
                if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                $color = switch ($v.Status) { 'OK' { 'Success' } 'WARN' { 'Warning' } 'CRITICAL' { 'Error' } default { 'Info' } }
                Write-OutputColor "  │$($line.PadRight(72))│" -color $color
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $summaryLine = "  Disks: $(@($physicalDisks).Count)   Volumes: $(@($volumes).Count)   Issues: $diskIssues"
            Write-OutputColor "  │$($summaryLine.PadRight(72))│" -color $(if ($diskIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'DiskAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname  = $env:COMPUTERNAME
                    Summary   = @{
                        PhysicalDisks = @($physicalDisks).Count
                        Volumes       = @($volumes).Count
                        Issues        = $diskIssues
                    }
                    PhysicalDisks = $physicalDisks
                    Volumes       = $volumes
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }

            if ($diskIssues -gt 0) { [Environment]::Exit(1) }
        }
        'TLSAudit' {
            Write-OutputColor "  Auditing TLS/SSL configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $tlsIssues = 0
            $protocols = @()
            $regBase = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols'

            $protocolList = @(
                @{ Name = 'SSL 2.0';  Secure = $false }
                @{ Name = 'SSL 3.0';  Secure = $false }
                @{ Name = 'TLS 1.0'; Secure = $false }
                @{ Name = 'TLS 1.1'; Secure = $false }
                @{ Name = 'TLS 1.2'; Secure = $true }
                @{ Name = 'TLS 1.3'; Secure = $true }
            )

            foreach ($proto in $protocolList) {
                $name = $proto.Name
                $serverPath = "$regBase\$name\Server"
                $clientPath = "$regBase\$name\Client"

                $serverEnabled = $null
                $clientEnabled = $null

                # Check Server subkey
                if (Test-Path $serverPath) {
                    $serverReg = Get-ItemProperty -Path $serverPath -ErrorAction SilentlyContinue
                    if ($null -ne $serverReg -and $null -ne $serverReg.Enabled) {
                        $serverEnabled = $serverReg.Enabled -ne 0
                    } elseif ($null -ne $serverReg -and $null -ne $serverReg.DisabledByDefault) {
                        $serverEnabled = $serverReg.DisabledByDefault -eq 0
                    }
                }

                # Check Client subkey
                if (Test-Path $clientPath) {
                    $clientReg = Get-ItemProperty -Path $clientPath -ErrorAction SilentlyContinue
                    if ($null -ne $clientReg -and $null -ne $clientReg.Enabled) {
                        $clientEnabled = $clientReg.Enabled -ne 0
                    } elseif ($null -ne $clientReg -and $null -ne $clientReg.DisabledByDefault) {
                        $clientEnabled = $clientReg.DisabledByDefault -eq 0
                    }
                }

                # Determine effective status
                # If registry keys don't exist, Windows uses defaults:
                # SSL 2.0/3.0: disabled by default on modern Windows
                # TLS 1.0/1.1: enabled by default (but deprecated)
                # TLS 1.2/1.3: enabled by default
                $effectiveServer = if ($null -ne $serverEnabled) { $serverEnabled } else {
                    # Default behavior for unset protocols
                    switch ($name) {
                        'SSL 2.0' { $false }
                        'SSL 3.0' { $false }
                        default { $true }
                    }
                }
                $effectiveClient = if ($null -ne $clientEnabled) { $clientEnabled } else {
                    switch ($name) {
                        'SSL 2.0' { $false }
                        'SSL 3.0' { $false }
                        default { $true }
                    }
                }

                $status = 'OK'
                $configured = $null -ne $serverEnabled -or $null -ne $clientEnabled

                if (-not $proto.Secure -and ($effectiveServer -or $effectiveClient)) {
                    $status = if ($name -match 'SSL') { 'CRITICAL' } else { 'WARN' }
                    $tlsIssues++
                }
                if ($proto.Secure -and -not $effectiveServer -and -not $effectiveClient) {
                    $status = 'CRITICAL'; $tlsIssues++
                }

                $protocols += @{
                    Protocol      = $name
                    ServerEnabled = $effectiveServer
                    ClientEnabled = $effectiveClient
                    Configured    = $configured
                    Secure        = $proto.Secure
                    Status        = $status
                }
            }

            # Check .NET strong crypto settings
            $netFx64 = 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319'
            $netFx32 = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319'
            $strongCrypto64 = $false
            $strongCrypto32 = $false
            try {
                $reg64 = Get-ItemProperty -Path $netFx64 -ErrorAction SilentlyContinue
                if ($null -ne $reg64 -and $null -ne $reg64.SchUseStrongCrypto) { $strongCrypto64 = $reg64.SchUseStrongCrypto -eq 1 }
                $reg32 = Get-ItemProperty -Path $netFx32 -ErrorAction SilentlyContinue
                if ($null -ne $reg32 -and $null -ne $reg32.SchUseStrongCrypto) { $strongCrypto32 = $reg32.SchUseStrongCrypto -eq 1 }
            } catch { }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  TLS AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($p in $protocols) {
                $serverStr = if ($p.ServerEnabled) { "On" } else { "Off" }
                $clientStr = if ($p.ClientEnabled) { "On" } else { "Off" }
                $cfgStr = if ($p.Configured) { "Explicit" } else { "Default" }
                $line = "  $($p.Protocol.PadRight(10)) Server: $($serverStr.PadRight(5)) Client: $($clientStr.PadRight(5)) ($cfgStr)  [$($p.Status)]"
                if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                $color = switch ($p.Status) { 'OK' { 'Success' } 'WARN' { 'Warning' } 'CRITICAL' { 'Error' } default { 'Info' } }
                Write-OutputColor "  │$($line.PadRight(72))│" -color $color
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $scLine = "  .NET Strong Crypto: x64=$(if ($strongCrypto64) { 'Yes' } else { 'No' })  x86=$(if ($strongCrypto32) { 'Yes' } else { 'No' })"
            $scColor = if ($strongCrypto64 -and $strongCrypto32) { "Success" } else { "Warning" }
            Write-OutputColor "  │$($scLine.PadRight(72))│" -color $scColor
            $summaryLine = "  Issues: $tlsIssues"
            Write-OutputColor "  │$($summaryLine.PadRight(72))│" -color $(if ($tlsIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'TLSAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname  = $env:COMPUTERNAME
                    Summary   = @{
                        Issues            = $tlsIssues
                        StrongCrypto64    = $strongCrypto64
                        StrongCrypto32    = $strongCrypto32
                    }
                    Protocols = $protocols
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }

            if ($tlsIssues -gt 0) { [Environment]::Exit(1) }
        }
        'SMBAudit' {
            Write-OutputColor "  Auditing SMB configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $smbIssues = 0

            # SMB server configuration
            $smbConfig = $null
            try {
                $smbConfig = Get-SmbServerConfiguration -ErrorAction Stop
            } catch {
                Write-OutputColor "  WARNING: Could not query SMB server config: $($_.Exception.Message)" -color "Warning"
            }

            $smb1Enabled = $false
            $signingRequired = $false
            $encryptData = $false
            if ($null -ne $smbConfig) {
                $smb1Enabled = $smbConfig.EnableSMB1Protocol -eq $true
                $signingRequired = $smbConfig.RequireSecuritySignature -eq $true
                $encryptData = $smbConfig.EncryptData -eq $true
                if ($smb1Enabled) { $smbIssues++ }
                if (-not $signingRequired) { $smbIssues++ }
            }

            # SMB shares
            $shares = @()
            try {
                $smbShares = @(Get-SmbShare -ErrorAction Stop | Where-Object { $_.Name -notmatch '^\$' -and $_.Name -ne 'IPC$' -and $_.Special -ne $true })
                foreach ($s in $smbShares) {
                    $access = @()
                    try {
                        $acl = @(Get-SmbShareAccess -Name $s.Name -ErrorAction Stop)
                        foreach ($a in $acl) {
                            $access += @{
                                AccountName = $a.AccountName
                                AccessRight = "$($a.AccessRight)"
                                AccessType  = "$($a.AccessControlType)"
                            }
                        }
                    } catch { }
                    $status = 'OK'
                    $everyoneFullControl = @($access | Where-Object { $_.AccountName -match 'Everyone' -and $_.AccessRight -eq 'Full' -and $_.AccessType -eq 'Allow' })
                    if (@($everyoneFullControl).Count -gt 0) { $status = 'WARN'; $smbIssues++ }

                    $shares += @{
                        Name        = $s.Name
                        Path        = $s.Path
                        Description = $s.Description
                        Status      = $status
                        Access      = $access
                    }
                }
            } catch {
                Write-OutputColor "  WARNING: Could not enumerate shares: $($_.Exception.Message)" -color "Warning"
            }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  SMB AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $smb1Color = if ($smb1Enabled) { "Error" } else { "Success" }
            $smb1Status = if ($smb1Enabled) { "ENABLED (insecure)" } else { "Disabled" }
            Write-OutputColor "  │$("  SMBv1:     $smb1Status".PadRight(72))│" -color $smb1Color
            $signColor = if ($signingRequired) { "Success" } else { "Warning" }
            $signStatus = if ($signingRequired) { "Required" } else { "Not required" }
            Write-OutputColor "  │$("  Signing:   $signStatus".PadRight(72))│" -color $signColor
            $encColor = if ($encryptData) { "Success" } else { "Info" }
            $encStatus = if ($encryptData) { "Enabled" } else { "Disabled" }
            Write-OutputColor "  │$("  Encryption: $encStatus".PadRight(72))│" -color $encColor
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (@($shares).Count -eq 0) {
                Write-OutputColor "  │$("  (No non-administrative shares found)".PadRight(72))│" -color "Info"
            } else {
                foreach ($s in $shares) {
                    $shareName = if ($s.Name.Length -gt 25) { $s.Name.Substring(0, 22) + "..." } else { $s.Name }
                    $sharePath = if ($s.Path.Length -gt 30) { $s.Path.Substring(0, 27) + "..." } else { $s.Path }
                    $line = "  $($shareName.PadRight(27)) $sharePath  [$($s.Status)]"
                    if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                    $color = if ($s.Status -eq 'OK') { 'Success' } else { 'Warning' }
                    Write-OutputColor "  │$($line.PadRight(72))│" -color $color
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $summaryLine = "  Shares: $(@($shares).Count)   Issues: $smbIssues"
            Write-OutputColor "  │$($summaryLine.PadRight(72))│" -color $(if ($smbIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'SMBAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname  = $env:COMPUTERNAME
                    Summary   = @{
                        SMBv1Enabled     = $smb1Enabled
                        SigningRequired  = $signingRequired
                        EncryptData      = $encryptData
                        ShareCount       = @($shares).Count
                        Issues           = $smbIssues
                    }
                    Shares    = $shares
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }

            if ($smbIssues -gt 0) { [Environment]::Exit(1) }
        }
        'DriverAudit' {
            Write-OutputColor "  Auditing system drivers..." -color "Info"
            Write-OutputColor "" -color "Info"

            $driverIssues = 0
            $drivers = @()

            try {
                $allDrivers = @(Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop |
                    Where-Object { $null -ne $_.DeviceName -and $_.DeviceName -ne '' })

                foreach ($d in $allDrivers) {
                    $signed = $d.IsSigned -eq $true
                    $health = 'OK'
                    if (-not $signed) { $health = 'WARN'; $driverIssues++ }

                    $drivers += @{
                        DeviceName    = $d.DeviceName
                        DriverVersion = $d.DriverVersion
                        Manufacturer  = $d.Manufacturer
                        DeviceClass   = $d.DeviceClass
                        IsSigned      = $signed
                        Signer        = $d.Signer
                        DriverDate    = if ($null -ne $d.DriverDate) { $d.DriverDate.ToString("yyyy-MM-dd") } else { $null }
                        Health        = $health
                    }
                }
            } catch {
                Write-OutputColor "  ERROR: Failed to query drivers: $($_.Exception.Message)" -color "Error"
                [Environment]::Exit(1)
            }

            $totalDrivers = @($drivers).Count
            $signedCount = @($drivers | Where-Object { $_.IsSigned }).Count
            $unsignedCount = @($drivers | Where-Object { -not $_.IsSigned }).Count
            $unsignedDrivers = @($drivers | Where-Object { -not $_.IsSigned })

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  DRIVER AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if ($unsignedCount -gt 0) {
                Write-OutputColor "  │$("  UNSIGNED DRIVERS".PadRight(72))│" -color "Warning"
                foreach ($d in $unsignedDrivers) {
                    $devName = if ($d.DeviceName.Length -gt 40) { $d.DeviceName.Substring(0, 37) + "..." } else { $d.DeviceName }
                    $line = "  $($devName.PadRight(42)) $($d.DeviceClass)"
                    if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                    Write-OutputColor "  │$($line.PadRight(72))│" -color "Warning"
                }
                Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            }
            $summaryLine = "  Total: $totalDrivers   Signed: $signedCount   Unsigned: $unsignedCount"
            Write-OutputColor "  │$($summaryLine.PadRight(72))│" -color $(if ($unsignedCount -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'DriverAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname  = $env:COMPUTERNAME
                    Summary   = @{
                        Total    = $totalDrivers
                        Signed   = $signedCount
                        Unsigned = $unsignedCount
                        Issues   = $driverIssues
                    }
                    UnsignedDrivers = $unsignedDrivers
                    AllDrivers      = $drivers
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }

            if ($driverIssues -gt 0) { [Environment]::Exit(1) }
        }
        'TimeAudit' {
            Write-OutputColor "  Auditing time configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $timeIssues = 0

            # W32Time service status
            $w32timeSvc = $null
            $w32timeRunning = $false
            try {
                $w32timeSvc = Get-Service -Name W32Time -ErrorAction Stop
                $w32timeRunning = $w32timeSvc.Status -eq 'Running'
                if (-not $w32timeRunning) { $timeIssues++ }
            } catch {
                Write-OutputColor "  WARNING: Could not query W32Time service: $($_.Exception.Message)" -color "Warning"
                $timeIssues++
            }

            # NTP configuration
            $ntpSource = "Unknown"
            $lastSync = "Unknown"
            $ntpType = "Unknown"
            try {
                $w32tmOutput = & w32tm /query /status 2>&1
                $w32tmStr = $w32tmOutput -join "`n"
                if ($w32tmStr -match 'Source:\s*(.+)') { $regexMatches = $Matches; $ntpSource = $regexMatches[1].Trim() }
                if ($w32tmStr -match 'Last Successful Sync Time:\s*(.+)') { $regexMatches = $Matches; $lastSync = $regexMatches[1].Trim() }
            } catch { }

            try {
                $ntpReg = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' -ErrorAction SilentlyContinue
                if ($null -ne $ntpReg -and $null -ne $ntpReg.Type) { $ntpType = $ntpReg.Type }
                if ($ntpType -eq 'NoSync') { $timeIssues++ }
            } catch { }

            # Time drift check
            $driftMs = $null
            $driftStatus = 'Unknown'
            try {
                $w32tmStrip = & w32tm /stripchart /computer:time.windows.com /dataonly /samples:1 2>&1
                $stripStr = $w32tmStrip -join "`n"
                if ($stripStr -match '([+-]?\d+\.?\d*s)') {
                    $regexMatches = $Matches; $driftStr = $regexMatches[1] -replace 's$', ''
                    $driftMs = [math]::Abs([double]$driftStr) * 1000
                    $driftStatus = if ($driftMs -lt 1000) { 'OK' } elseif ($driftMs -lt 5000) { 'WARN' } else { 'CRITICAL' }
                    if ($driftStatus -ne 'OK') { $timeIssues++ }
                }
            } catch { }

            # Boot time
            $bootTime = $null
            $uptimeDays = $null
            try {
                $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                $bootTime = $os.LastBootUpTime.ToString("yyyy-MM-ddTHH:mm:ss")
                $uptimeDays = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1)
            } catch { }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  TIME AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $svcColor = if ($w32timeRunning) { "Success" } else { "Error" }
            $svcStatus = if ($w32timeRunning) { "Running" } else { "Stopped" }
            Write-OutputColor "  │$("  W32Time Service: $svcStatus".PadRight(72))│" -color $svcColor
            Write-OutputColor "  │$("  NTP Source:      $ntpSource".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  NTP Type:        $ntpType".PadRight(72))│" -color $(if ($ntpType -eq 'NoSync') { "Error" } else { "Info" })
            Write-OutputColor "  │$("  Last Sync:       $lastSync".PadRight(72))│" -color "Info"
            if ($null -ne $driftMs) {
                $driftColor = switch ($driftStatus) { 'OK' { 'Success' } 'WARN' { 'Warning' } 'CRITICAL' { 'Error' } default { 'Info' } }
                Write-OutputColor "  │$("  Time Drift:      $([math]::Round($driftMs, 0))ms [$driftStatus]".PadRight(72))│" -color $driftColor
            }
            if ($null -ne $bootTime) {
                Write-OutputColor "  │$("  Boot Time:       $bootTime (${uptimeDays}d uptime)".PadRight(72))│" -color "Info"
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Issues: $timeIssues".PadRight(72))│" -color $(if ($timeIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'TimeAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname  = $env:COMPUTERNAME
                    Summary   = @{
                        W32TimeRunning = $w32timeRunning
                        NTPSource      = $ntpSource
                        NTPType        = $ntpType
                        LastSync       = $lastSync
                        DriftMs        = $driftMs
                        DriftStatus    = $driftStatus
                        BootTime       = $bootTime
                        UptimeDays     = $uptimeDays
                        Issues         = $timeIssues
                    }
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }

            if ($timeIssues -gt 0) { [Environment]::Exit(1) }
        }
        'BootAudit' {
            Write-OutputColor "  Auditing boot configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $bootIssues = 0

            # Secure Boot status
            $secureBoot = $null
            try {
                $secureBoot = Confirm-SecureBootUEFI -ErrorAction Stop
            } catch {
                # Not supported on BIOS systems — not an issue, just informational
                $secureBoot = $null
            }

            # UEFI vs BIOS
            $firmwareType = "Unknown"
            try {
                $env:firmware_type_check = $null
                $fwReg = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue
                if ($null -ne $fwReg) {
                    $firmwareType = "UEFI"
                } else {
                    # Check bcdedit for firmware type
                    $bcdOutput = & bcdedit /enum firmware 2>&1
                    $bcdStr = $bcdOutput -join "`n"
                    $firmwareType = if ($bcdStr -match 'firmware') { "UEFI" } else { "BIOS" }
                }
            } catch {
                $firmwareType = "Unknown"
            }

            # Boot time and uptime
            $bootTime = $null
            $uptimeDays = $null
            try {
                $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                $bootTime = $os.LastBootUpTime.ToString("yyyy-MM-ddTHH:mm:ss")
                $uptimeDays = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1)
                if ($uptimeDays -gt 90) { $bootIssues++ }
            } catch { }

            # Pending reboot check
            $pendingReboot = $false
            try {
                $cbsReboot = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
                $wuReboot = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
                $pfro = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
                $pendingReboot = $cbsReboot -or $wuReboot -or ($null -ne $pfro)
                if ($pendingReboot) { $bootIssues++ }
            } catch { }

            # DEP (Data Execution Prevention) status
            $depEnabled = $false
            try {
                $depReg = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                $depEnabled = $depReg.DataExecutionPrevention_Available -eq $true
            } catch { }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  BOOT AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Firmware:       $firmwareType".PadRight(72))│" -color $(if ($firmwareType -eq 'UEFI') { "Success" } else { "Info" })
            $sbStr = if ($null -eq $secureBoot) { "N/A (BIOS)" } elseif ($secureBoot) { "Enabled" } else { "Disabled" }
            $sbColor = if ($null -eq $secureBoot) { "Info" } elseif ($secureBoot) { "Success" } else { "Warning" }
            Write-OutputColor "  │$("  Secure Boot:    $sbStr".PadRight(72))│" -color $sbColor
            Write-OutputColor "  │$("  DEP:            $(if ($depEnabled) { 'Available' } else { 'Unavailable' })".PadRight(72))│" -color $(if ($depEnabled) { "Success" } else { "Warning" })
            if ($null -ne $bootTime) {
                $uptimeColor = if ($uptimeDays -gt 90) { "Warning" } else { "Success" }
                Write-OutputColor "  │$("  Boot Time:      $bootTime".PadRight(72))│" -color "Info"
                Write-OutputColor "  │$("  Uptime:         ${uptimeDays} days".PadRight(72))│" -color $uptimeColor
            }
            $rebootColor = if ($pendingReboot) { "Warning" } else { "Success" }
            Write-OutputColor "  │$("  Pending Reboot: $(if ($pendingReboot) { 'Yes' } else { 'No' })".PadRight(72))│" -color $rebootColor
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Issues: $bootIssues".PadRight(72))│" -color $(if ($bootIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'BootAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname  = $env:COMPUTERNAME
                    Summary   = @{
                        FirmwareType  = $firmwareType
                        SecureBoot    = $secureBoot
                        DEPAvailable  = $depEnabled
                        BootTime      = $bootTime
                        UptimeDays    = $uptimeDays
                        PendingReboot = $pendingReboot
                        Issues        = $bootIssues
                    }
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }

            if ($bootIssues -gt 0) { [Environment]::Exit(1) }
        }
        'GPOAudit' {
            Write-OutputColor "  Auditing Group Policy configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $gpoIssues = 0
            $gpoEntries = @()

            # Check if domain-joined
            $isDomainJoined = $false
            try {
                $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
                $isDomainJoined = $cs.PartOfDomain -eq $true
            } catch { }

            if (-not $isDomainJoined) {
                Write-OutputColor "  Not domain-joined — checking local policy only." -color "Info"
            }

            # Query applied GPOs via registry (works on all systems)
            $gpoRegPaths = @(
                @{ Scope = 'Machine'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\History' }
                @{ Scope = 'User'; Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\History' }
            )

            foreach ($gpoReg in $gpoRegPaths) {
                if (Test-Path $gpoReg.Path) {
                    try {
                        $subkeys = Get-ChildItem -Path $gpoReg.Path -ErrorAction SilentlyContinue
                        foreach ($sk in $subkeys) {
                            $innerKeys = Get-ChildItem -Path $sk.PSPath -ErrorAction SilentlyContinue
                            foreach ($ik in $innerKeys) {
                                $props = Get-ItemProperty -Path $ik.PSPath -ErrorAction SilentlyContinue
                                if ($null -ne $props -and $null -ne $props.DisplayName) {
                                    $gpoEntries += @{
                                        Scope       = $gpoReg.Scope
                                        DisplayName = $props.DisplayName
                                        GPOName     = if ($null -ne $props.GPOName) { $props.GPOName } else { "" }
                                        Extensions  = if ($null -ne $props.Extensions) { $props.Extensions } else { "" }
                                        Link        = if ($null -ne $props.Link) { $props.Link } else { "" }
                                        Status      = 'Applied'
                                    }
                                }
                            }
                        }
                    } catch { }
                }
            }

            # Deduplicate by DisplayName+Scope
            $uniqueGPOs = @()
            $seen = @{}
            foreach ($g in $gpoEntries) {
                $key = "$($g.Scope):$($g.DisplayName)"
                if (-not $seen.ContainsKey($key)) {
                    $seen[$key] = $true
                    $uniqueGPOs += $g
                }
            }

            # Last gpupdate time
            $lastGPUpdate = "Unknown"
            try {
                $gpResult = & gpresult /scope computer /v 2>&1
                $gpStr = $gpResult -join "`n"
                if ($gpStr -match 'Last time Group Policy was applied:\s*(.+)') {
                    $regexMatches = $Matches; $lastGPUpdate = $regexMatches[1].Trim()
                }
            } catch { }

            $machineGPOs = @($uniqueGPOs | Where-Object { $_.Scope -eq 'Machine' })
            $userGPOs = @($uniqueGPOs | Where-Object { $_.Scope -eq 'User' })

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  GPO AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Domain Joined: $isDomainJoined    Last GP Update: $lastGPUpdate".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (@($machineGPOs).Count -gt 0) {
                Write-OutputColor "  │$("  MACHINE POLICIES ($(@($machineGPOs).Count))".PadRight(72))│" -color "Info"
                foreach ($g in $machineGPOs) {
                    $gpoName = if ($g.DisplayName.Length -gt 65) { $g.DisplayName.Substring(0, 62) + "..." } else { $g.DisplayName }
                    Write-OutputColor "  │$("  $gpoName".PadRight(72))│" -color "Success"
                }
            }
            if (@($userGPOs).Count -gt 0) {
                Write-OutputColor "  │$("  USER POLICIES ($(@($userGPOs).Count))".PadRight(72))│" -color "Info"
                foreach ($g in $userGPOs) {
                    $gpoName = if ($g.DisplayName.Length -gt 65) { $g.DisplayName.Substring(0, 62) + "..." } else { $g.DisplayName }
                    Write-OutputColor "  │$("  $gpoName".PadRight(72))│" -color "Success"
                }
            }
            if (@($uniqueGPOs).Count -eq 0) {
                Write-OutputColor "  │$("  (No applied Group Policies found)".PadRight(72))│" -color "Info"
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $summaryLine = "  Machine: $(@($machineGPOs).Count)   User: $(@($userGPOs).Count)   Total: $(@($uniqueGPOs).Count)"
            Write-OutputColor "  │$($summaryLine.PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'GPOAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname  = $env:COMPUTERNAME
                    Summary   = @{
                        DomainJoined  = $isDomainJoined
                        LastGPUpdate  = $lastGPUpdate
                        MachinePolicies = @($machineGPOs).Count
                        UserPolicies    = @($userGPOs).Count
                        TotalPolicies   = @($uniqueGPOs).Count
                        Issues          = $gpoIssues
                    }
                    Policies  = $uniqueGPOs
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }

            if ($gpoIssues -gt 0) { [Environment]::Exit(1) }
        }
        'MemoryAudit' {
            Write-OutputColor "  Auditing memory configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $memIssues = 0

            # Physical memory
            $totalPhysicalGB = 0
            $availableGB = 0
            $usedGB = 0
            $pctUsed = 0
            try {
                $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                $totalPhysicalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
                $availableGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
                $usedGB = [math]::Round($totalPhysicalGB - $availableGB, 1)
                $pctUsed = if ($totalPhysicalGB -gt 0) { [math]::Round(($usedGB / $totalPhysicalGB) * 100, 1) } else { 0 }
                if ($pctUsed -gt 90) { $memIssues++ }
            } catch {
                Write-OutputColor "  ERROR: Failed to query memory: $($_.Exception.Message)" -color "Error"
                [Environment]::Exit(1)
            }

            # Memory DIMMs
            $dimms = @()
            try {
                $physMem = @(Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop)
                foreach ($m in $physMem) {
                    $dimms += @{
                        BankLabel    = "$($m.BankLabel)"
                        DeviceLocator = "$($m.DeviceLocator)"
                        CapacityGB   = [math]::Round($m.Capacity / 1GB, 1)
                        Speed        = $m.Speed
                        Manufacturer = "$($m.Manufacturer)"
                        PartNumber   = "$($m.PartNumber)".Trim()
                    }
                }
            } catch {
                Write-OutputColor "  WARNING: Could not enumerate DIMMs: $($_.Exception.Message)" -color "Warning"
            }

            # Page file
            $pageFiles = @()
            try {
                $pf = @(Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction Stop)
                foreach ($p in $pf) {
                    $pfSizeMB = $p.AllocatedBaseSize
                    $pfUsedMB = $p.CurrentUsage
                    $pfPctUsed = if ($pfSizeMB -gt 0) { [math]::Round(($pfUsedMB / $pfSizeMB) * 100, 1) } else { 0 }
                    $pfStatus = 'OK'
                    if ($pfPctUsed -gt 80) { $pfStatus = 'WARN'; $memIssues++ }
                    $pageFiles += @{
                        Name     = $p.Name
                        SizeMB   = $pfSizeMB
                        UsedMB   = $pfUsedMB
                        PctUsed  = $pfPctUsed
                        Status   = $pfStatus
                    }
                }
            } catch { }

            $memStatus = if ($pctUsed -gt 90) { 'CRITICAL' } elseif ($pctUsed -gt 80) { 'WARN' } else { 'OK' }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  MEMORY AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $memColor = switch ($memStatus) { 'OK' { 'Success' } 'WARN' { 'Warning' } 'CRITICAL' { 'Error' } default { 'Info' } }
            Write-OutputColor "  │$("  Physical RAM:   ${usedGB}/${totalPhysicalGB} GB used (${pctUsed}%) [$memStatus]".PadRight(72))│" -color $memColor
            Write-OutputColor "  │$("  Available:      ${availableGB} GB".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  DIMMs:          $(@($dimms).Count) installed".PadRight(72))│" -color "Info"
            if (@($dimms).Count -gt 0) {
                foreach ($d in $dimms) {
                    $dimmLine = "    $($d.DeviceLocator): $($d.CapacityGB)GB @ $($d.Speed)MHz"
                    if ($d.Manufacturer -and $d.Manufacturer -ne 'Unknown') { $dimmLine += " ($($d.Manufacturer))" }
                    if ($dimmLine.Length -gt 70) { $dimmLine = $dimmLine.Substring(0, 67) + "..." }
                    Write-OutputColor "  │$($dimmLine.PadRight(72))│" -color "Info"
                }
            }
            if (@($pageFiles).Count -gt 0) {
                Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                foreach ($pf in $pageFiles) {
                    $pfColor = if ($pf.Status -eq 'OK') { 'Success' } else { 'Warning' }
                    $pfLine = "  Page File: $($pf.Name)  $($pf.UsedMB)/$($pf.SizeMB)MB ($($pf.PctUsed)%) [$($pf.Status)]"
                    if ($pfLine.Length -gt 72) { $pfLine = $pfLine.Substring(0, 69) + "..." }
                    Write-OutputColor "  │$($pfLine.PadRight(72))│" -color $pfColor
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Issues: $memIssues".PadRight(72))│" -color $(if ($memIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'MemoryAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname  = $env:COMPUTERNAME
                    Summary   = @{
                        TotalGB     = $totalPhysicalGB
                        UsedGB      = $usedGB
                        AvailableGB = $availableGB
                        PctUsed     = $pctUsed
                        Status      = $memStatus
                        DIMMs       = @($dimms).Count
                        Issues      = $memIssues
                    }
                    DIMMs     = $dimms
                    PageFiles = $pageFiles
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }

            if ($memIssues -gt 0) { [Environment]::Exit(1) }
        }
        'ProcessAudit' {
            Write-OutputColor "  Auditing running processes..." -color "Info"
            Write-OutputColor "" -color "Info"

            $procIssues = 0
            $topCpu = @()
            $topMem = @()
            $unsignedProcs = @()

            try {
                $processes = @(Get-Process -ErrorAction Stop | Where-Object { $_.Name -ne 'Idle' -and $_.Name -ne 'System' })

                # Top 10 CPU consumers
                $topCpu = @($processes | Sort-Object CPU -Descending | Select-Object -First 10 | ForEach-Object {
                    @{
                        Name      = $_.Name
                        PID       = $_.Id
                        CPU       = [math]::Round($_.CPU, 1)
                        MemoryMB  = [math]::Round($_.WorkingSet64 / 1MB, 1)
                        Path      = "$($_.Path)"
                    }
                })

                # Top 10 memory consumers
                $topMem = @($processes | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 | ForEach-Object {
                    @{
                        Name      = $_.Name
                        PID       = $_.Id
                        MemoryMB  = [math]::Round($_.WorkingSet64 / 1MB, 1)
                        Path      = "$($_.Path)"
                    }
                })

                # Check for unsigned processes with paths
                $withPath = @($processes | Where-Object { $null -ne $_.Path -and $_.Path -ne '' })
                foreach ($p in $withPath) {
                    try {
                        $sig = Get-AuthenticodeSignature -FilePath $p.Path -ErrorAction Stop
                        if ($sig.Status -ne 'Valid') {
                            $unsignedProcs += @{
                                Name      = $p.Name
                                PID       = $p.Id
                                Path      = $p.Path
                                SigStatus = "$($sig.Status)"
                                MemoryMB  = [math]::Round($p.WorkingSet64 / 1MB, 1)
                            }
                        }
                    } catch { }
                }
                if (@($unsignedProcs).Count -gt 0) { $procIssues = @($unsignedProcs).Count }
            } catch {
                Write-OutputColor "  ERROR: Failed to query processes: $($_.Exception.Message)" -color "Error"
                [Environment]::Exit(1)
            }

            $totalProcs = @($processes).Count

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  PROCESS AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  TOP CPU CONSUMERS".PadRight(72))│" -color "Info"
            foreach ($p in $topCpu) {
                $pName = if ($p.Name.Length -gt 25) { $p.Name.Substring(0, 22) + "..." } else { $p.Name }
                $line = "  $($pName.PadRight(27)) CPU: $("$($p.CPU)s".PadRight(10)) Mem: $($p.MemoryMB)MB"
                if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                Write-OutputColor "  │$($line.PadRight(72))│" -color "Info"
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  TOP MEMORY CONSUMERS".PadRight(72))│" -color "Info"
            foreach ($p in $topMem) {
                $pName = if ($p.Name.Length -gt 25) { $p.Name.Substring(0, 22) + "..." } else { $p.Name }
                $line = "  $($pName.PadRight(27)) Mem: $($p.MemoryMB)MB"
                if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                Write-OutputColor "  │$($line.PadRight(72))│" -color "Info"
            }
            if (@($unsignedProcs).Count -gt 0) {
                Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                Write-OutputColor "  │$("  UNSIGNED PROCESSES ($(@($unsignedProcs).Count))".PadRight(72))│" -color "Warning"
                foreach ($p in $unsignedProcs) {
                    $pName = if ($p.Name.Length -gt 25) { $p.Name.Substring(0, 22) + "..." } else { $p.Name }
                    $line = "  $($pName.PadRight(27)) [$($p.SigStatus)]  $($p.MemoryMB)MB"
                    if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                    Write-OutputColor "  │$($line.PadRight(72))│" -color "Warning"
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $summaryLine = "  Total: $totalProcs   Unsigned: $(@($unsignedProcs).Count)"
            Write-OutputColor "  │$($summaryLine.PadRight(72))│" -color $(if ($procIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'ProcessAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname  = $env:COMPUTERNAME
                    Summary   = @{
                        TotalProcesses  = $totalProcs
                        UnsignedCount   = @($unsignedProcs).Count
                        Issues          = $procIssues
                    }
                    TopCPU           = $topCpu
                    TopMemory        = $topMem
                    UnsignedProcesses = $unsignedProcs
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }

            if ($procIssues -gt 0) { [Environment]::Exit(1) }
        }
        'BackupAudit' {
            Write-OutputColor "  Auditing backup configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $backupIssues = 0

            # VSS Writers
            $vssWriters = @()
            try {
                $vssOutput = & vssadmin list writers 2>&1
                $vssStr = $vssOutput -join "`n"
                $writerBlocks = $vssStr -split 'Writer name:'
                foreach ($block in $writerBlocks) {
                    if ($block.Trim() -eq '') { continue }
                    $writerName = ''
                    $writerState = ''
                    $lastError = ''
                    if ($block -match "^\s*'([^']+)'") { $regexMatches = $Matches; $writerName = $regexMatches[1] }
                    if ($block -match 'State:\s*\[\d+\]\s*(.+)') { $regexMatches = $Matches; $writerState = $regexMatches[1].Trim() }
                    if ($block -match 'Last error:\s*(.+)') { $regexMatches = $Matches; $lastError = $regexMatches[1].Trim() }
                    if ($writerName) {
                        $health = 'OK'
                        if ($writerState -ne 'Stable' -and $writerState -ne '') { $health = 'FAIL'; $backupIssues++ }
                        if ($lastError -ne 'No error' -and $lastError -ne '') { $health = 'FAIL'; if ($writerState -eq 'Stable') { $backupIssues++ } }
                        $vssWriters += @{
                            Name      = $writerName
                            State     = $writerState
                            LastError = $lastError
                            Health    = $health
                        }
                    }
                }
            } catch {
                Write-OutputColor "  WARNING: Could not query VSS writers: $($_.Exception.Message)" -color "Warning"
            }

            # Shadow copies
            $shadowCopies = @()
            try {
                $shadows = @(Get-CimInstance -ClassName Win32_ShadowCopy -ErrorAction Stop)
                foreach ($s in $shadows) {
                    $shadowCopies += @{
                        ID         = "$($s.ID)"
                        Volume     = "$($s.VolumeName)"
                        Created    = if ($null -ne $s.InstallDate) { $s.InstallDate.ToString("yyyy-MM-ddTHH:mm:ss") } else { "Unknown" }
                        Provider   = "$($s.ProviderID)"
                    }
                }
            } catch { }

            # Windows Server Backup status (if available)
            $wsbStatus = $null
            try {
                $wsbJob = Get-WBJob -Previous 1 -ErrorAction Stop
                if ($null -ne $wsbJob) {
                    $wsbStatus = @{
                        StartTime  = $wsbJob.StartTime.ToString("yyyy-MM-ddTHH:mm:ss")
                        EndTime    = if ($null -ne $wsbJob.EndTime) { $wsbJob.EndTime.ToString("yyyy-MM-ddTHH:mm:ss") } else { "Running" }
                        JobState   = "$($wsbJob.JobState)"
                        HResult    = $wsbJob.HResult
                        Health     = if ($wsbJob.HResult -eq 0) { 'OK' } else { 'FAIL' }
                    }
                    if ($wsbStatus.Health -eq 'FAIL') { $backupIssues++ }
                }
            } catch { }

            $failedWriters = @($vssWriters | Where-Object { $_.Health -eq 'FAIL' })

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  BACKUP AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  VSS WRITERS ($(@($vssWriters).Count) total, $(@($failedWriters).Count) failed)".PadRight(72))│" -color $(if (@($failedWriters).Count -gt 0) { "Warning" } else { "Success" })
            if (@($failedWriters).Count -gt 0) {
                foreach ($w in $failedWriters) {
                    $wName = if ($w.Name.Length -gt 35) { $w.Name.Substring(0, 32) + "..." } else { $w.Name }
                    $line = "  $($wName.PadRight(37)) $($w.State)  $($w.LastError)"
                    if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                    Write-OutputColor "  │$($line.PadRight(72))│" -color "Error"
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Shadow Copies: $(@($shadowCopies).Count)".PadRight(72))│" -color "Info"
            if ($null -ne $wsbStatus) {
                $wsbColor = if ($wsbStatus.Health -eq 'OK') { "Success" } else { "Error" }
                Write-OutputColor "  │$("  Last WSB Job: $($wsbStatus.JobState) at $($wsbStatus.EndTime) [$($wsbStatus.Health)]".PadRight(72))│" -color $wsbColor
            } else {
                Write-OutputColor "  │$("  Windows Server Backup: Not configured or not available".PadRight(72))│" -color "Info"
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Issues: $backupIssues".PadRight(72))│" -color $(if ($backupIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool      = $script:ToolFullName
                    Version   = $script:ScriptVersion
                    Action    = 'BackupAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    Hostname  = $env:COMPUTERNAME
                    Summary   = @{
                        VSSWriters     = @($vssWriters).Count
                        FailedWriters  = @($failedWriters).Count
                        ShadowCopies   = @($shadowCopies).Count
                        WSBConfigured  = $null -ne $wsbStatus
                        Issues         = $backupIssues
                    }
                    VSSWriters    = $vssWriters
                    ShadowCopies  = $shadowCopies
                    WSBStatus     = $wsbStatus
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }

            if ($backupIssues -gt 0) { [Environment]::Exit(1) }
        }
        'ShareAudit' {
            Write-OutputColor "  Auditing file share permissions..." -color "Info"
            Write-OutputColor "" -color "Info"

            $shareIssues = 0
            $shareResults = @()

            try {
                $shares = @(Get-SmbShare -ErrorAction Stop | Where-Object { $_.Name -notmatch '^\$' -and $_.Name -ne 'IPC$' -and $_.Special -ne $true })
                foreach ($s in $shares) {
                    $ntfsPerms = @()
                    $smbPerms = @()
                    $status = 'OK'

                    # SMB share permissions
                    try {
                        $smbAccess = @(Get-SmbShareAccess -Name $s.Name -ErrorAction Stop)
                        foreach ($a in $smbAccess) {
                            $smbPerms += @{ Account = $a.AccountName; Right = "$($a.AccessRight)"; Type = "$($a.AccessControlType)" }
                            if ($a.AccountName -match 'Everyone' -and "$($a.AccessRight)" -eq 'Full' -and "$($a.AccessControlType)" -eq 'Allow') {
                                $status = 'WARN'; $shareIssues++
                            }
                        }
                    } catch { }

                    # NTFS permissions on share path
                    if ($s.Path -and (Test-Path -LiteralPath $s.Path)) {
                        try {
                            $acl = Get-Acl -Path $s.Path -ErrorAction Stop
                            foreach ($ace in $acl.Access) {
                                $ntfsPerms += @{
                                    Account = "$($ace.IdentityReference)"
                                    Rights  = "$($ace.FileSystemRights)"
                                    Type    = "$($ace.AccessControlType)"
                                    Inherited = $ace.IsInherited
                                }
                                if ("$($ace.IdentityReference)" -match 'Everyone' -and "$($ace.FileSystemRights)" -match 'FullControl' -and "$($ace.AccessControlType)" -eq 'Allow') {
                                    if ($status -eq 'OK') { $status = 'WARN'; $shareIssues++ }
                                }
                            }
                        } catch { }
                    }

                    $shareResults += @{
                        Name        = $s.Name
                        Path        = $s.Path
                        Description = $s.Description
                        Status      = $status
                        SMBPerms    = $smbPerms
                        NTFSPerms   = $ntfsPerms
                    }
                }
            } catch {
                Write-OutputColor "  WARNING: Could not enumerate shares: $($_.Exception.Message)" -color "Warning"
            }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  SHARE AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (@($shareResults).Count -eq 0) {
                Write-OutputColor "  │$("  (No non-administrative shares found)".PadRight(72))│" -color "Info"
            } else {
                foreach ($s in $shareResults) {
                    $sName = if ($s.Name.Length -gt 20) { $s.Name.Substring(0, 17) + "..." } else { $s.Name }
                    $sPath = if ($s.Path.Length -gt 35) { $s.Path.Substring(0, 32) + "..." } else { $s.Path }
                    $line = "  $($sName.PadRight(22)) $sPath  [$($s.Status)]"
                    if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                    $color = if ($s.Status -eq 'OK') { 'Success' } else { 'Warning' }
                    Write-OutputColor "  │$($line.PadRight(72))│" -color $color
                    Write-OutputColor "  │$("    SMB: $(@($s.SMBPerms).Count) ACEs   NTFS: $(@($s.NTFSPerms).Count) ACEs".PadRight(72))│" -color "Info"
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Shares: $(@($shareResults).Count)   Issues: $shareIssues".PadRight(72))│" -color $(if ($shareIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'ShareAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ Shares = @($shareResults).Count; Issues = $shareIssues }
                    Shares = $shareResults
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($shareIssues -gt 0) { [Environment]::Exit(1) }
        }
        'DNSAudit' {
            Write-OutputColor "  Auditing DNS configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $dnsIssues = 0
            $adapters = @()

            try {
                $dnsClients = @(Get-DnsClientServerAddress -ErrorAction Stop | Where-Object { $_.ServerAddresses.Count -gt 0 -and $_.AddressFamily -eq 2 })
                $seen = @{}
                foreach ($dc in $dnsClients) {
                    $key = "$($dc.InterfaceAlias)"
                    if ($seen.ContainsKey($key)) { continue }
                    $seen[$key] = $true
                    $adapters += @{
                        Interface   = $dc.InterfaceAlias
                        DNSServers  = $dc.ServerAddresses
                        Status      = 'OK'
                    }
                }
            } catch {
                Write-OutputColor "  WARNING: Could not query DNS config: $($_.Exception.Message)" -color "Warning"
            }

            # DNS suffix search list
            $suffixList = @()
            try {
                $dnsClient = Get-DnsClient -ErrorAction SilentlyContinue | Select-Object -First 1
                $suffixSearch = Get-DnsClientGlobalSetting -ErrorAction SilentlyContinue
                if ($null -ne $suffixSearch) { $suffixList = @($suffixSearch.SuffixSearchList) }
            } catch { }

            # Resolution tests
            $resTests = @()
            $testTargets = @('dns.msftncsi.com', 'time.windows.com')
            foreach ($target in $testTargets) {
                $resolved = $false
                $resolvedIP = ''
                try {
                    $result = Resolve-DnsName -Name $target -Type A -ErrorAction Stop | Select-Object -First 1
                    $resolved = $true
                    $resolvedIP = "$($result.IPAddress)"
                } catch { $dnsIssues++ }
                $resTests += @{ Target = $target; Resolved = $resolved; IP = $resolvedIP }
            }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  DNS AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($a in $adapters) {
                $servers = ($a.DNSServers -join ', ')
                if ($servers.Length -gt 45) { $servers = $servers.Substring(0, 42) + "..." }
                $line = "  $($a.Interface): $servers"
                if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                Write-OutputColor "  │$($line.PadRight(72))│" -color "Info"
            }
            if (@($suffixList).Count -gt 0) {
                Write-OutputColor "  │$("  Suffix Search: $($suffixList -join ', ')".PadRight(72))│" -color "Info"
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($t in $resTests) {
                $rColor = if ($t.Resolved) { "Success" } else { "Error" }
                $rStatus = if ($t.Resolved) { "OK ($($t.IP))" } else { "FAIL" }
                Write-OutputColor "  │$("  Resolve $($t.Target): $rStatus".PadRight(72))│" -color $rColor
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Issues: $dnsIssues".PadRight(72))│" -color $(if ($dnsIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'DNSAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ Adapters = @($adapters).Count; SuffixCount = @($suffixList).Count; ResolutionTests = @($resTests).Count; Issues = $dnsIssues }
                    Adapters = $adapters; SuffixSearchList = $suffixList; ResolutionTests = $resTests
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($dnsIssues -gt 0) { [Environment]::Exit(1) }
        }
        'PowerAudit' {
            Write-OutputColor "  Auditing power configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $powerIssues = 0

            # Active power plan
            $activePlan = "Unknown"
            $planGuid = ""
            try {
                $plans = & powercfg /getactivescheme 2>&1
                $planStr = $plans -join " "
                if ($planStr -match 'Power Scheme GUID:\s*(\S+)\s*\(([^)]+)\)') {
                    $regexMatches = $Matches; $planGuid = $regexMatches[1]; $activePlan = $regexMatches[2]
                }
                if ($activePlan -notmatch 'High [Pp]erformance') { $powerIssues++ }
            } catch { }

            # Sleep/Hibernate settings
            $sleepAC = "Unknown"; $sleepDC = "Unknown"
            $hibernateEnabled = $false
            try {
                $sleepOutput = & powercfg /query $planGuid SUB_SLEEP STANDBYIDLE 2>&1
                $sleepStr = $sleepOutput -join "`n"
                if ($sleepStr -match 'Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)') {
                    $regexMatches = $Matches; $sleepAC = [int]("0x" + $regexMatches[1])
                    $sleepAC = if ($sleepAC -eq 0) { "Never" } else { "$($sleepAC)s" }
                }
                if ($sleepStr -match 'Current DC Power Setting Index:\s*0x([0-9a-fA-F]+)') {
                    $regexMatches = $Matches; $sleepDC = [int]("0x" + $regexMatches[1])
                    $sleepDC = if ($sleepDC -eq 0) { "Never" } else { "$($sleepDC)s" }
                }
            } catch { }

            try {
                $hibOutput = & powercfg /availablesleepstates 2>&1
                $hibStr = $hibOutput -join "`n"
                $hibernateEnabled = $hibStr -match 'Hibernate'
            } catch { }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  POWER AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $planColor = if ($activePlan -match 'High [Pp]erformance') { "Success" } else { "Warning" }
            Write-OutputColor "  │$("  Active Plan:    $activePlan".PadRight(72))│" -color $planColor
            Write-OutputColor "  │$("  Sleep (AC):     $sleepAC".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Sleep (DC):     $sleepDC".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Hibernate:      $(if ($hibernateEnabled) { 'Available' } else { 'Disabled' })".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Issues: $powerIssues".PadRight(72))│" -color $(if ($powerIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'PowerAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ ActivePlan = $activePlan; PlanGUID = $planGuid; SleepAC = $sleepAC; SleepDC = $sleepDC; HibernateAvailable = $hibernateEnabled; Issues = $powerIssues }
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($powerIssues -gt 0) { [Environment]::Exit(1) }
        }
        'RegistryAudit' {
            Write-OutputColor "  Auditing security registry settings..." -color "Info"
            Write-OutputColor "" -color "Info"

            $regIssues = 0
            $checks = @()

            # Security baseline registry checks
            $baselineChecks = @(
                @{ Name = 'UAC Enabled';           Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Key = 'EnableLUA';                  Expected = 1;  Critical = $true }
                @{ Name = 'UAC Prompt Admin';       Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Key = 'ConsentPromptBehaviorAdmin'; Expected = 2;  Critical = $false }
                @{ Name = 'RDP NLA Required';       Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'; Key = 'UserAuthentication'; Expected = 1; Critical = $true }
                @{ Name = 'AutoPlay Disabled';      Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Key = 'NoDriveTypeAutoRun'; Expected = 255; Critical = $false }
                @{ Name = 'WDigest Disabled';       Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'; Key = 'UseLogonCredential'; Expected = 0; Critical = $true }
                @{ Name = 'LSASS Protection';       Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Key = 'RunAsPPL'; Expected = 1; Critical = $true }
                @{ Name = 'Remote Registry Disabled'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\RemoteRegistry'; Key = 'Start'; Expected = 4; Critical = $false }
                @{ Name = 'LM Hash Storage Disabled'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Key = 'NoLMHash'; Expected = 1; Critical = $true }
                @{ Name = 'Anonymous SID Disabled'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Key = 'RestrictAnonymousSAM'; Expected = 1; Critical = $false }
                @{ Name = 'NTLM Min Server Sec';    Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0'; Key = 'NTLMMinServerSec'; Expected = 537395200; Critical = $false }
            )

            foreach ($check in $baselineChecks) {
                $actual = $null
                $exists = $false
                $pass = $false

                try {
                    if (Test-Path $check.Path) {
                        $reg = Get-ItemProperty -Path $check.Path -ErrorAction SilentlyContinue
                        if ($null -ne $reg -and ($reg.PSObject.Properties.Name -contains $check.Key)) {
                            $exists = $true
                            $actual = $reg.($check.Key)
                            $pass = $actual -eq $check.Expected
                        }
                    }
                } catch { }

                $status = if ($pass) { 'OK' } elseif ($check.Critical) { 'CRITICAL'; $regIssues++ } else { 'WARN'; $regIssues++ }

                $checks += @{
                    Name     = $check.Name
                    Path     = $check.Path
                    Key      = $check.Key
                    Expected = $check.Expected
                    Actual   = $actual
                    Exists   = $exists
                    Status   = $status
                }
            }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  REGISTRY AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($c in $checks) {
                $actualStr = if ($null -eq $c.Actual) { "(not set)" } else { "$($c.Actual)" }
                $line = "  $($c.Name.PadRight(28)) $($actualStr.PadRight(12)) [$($c.Status)]"
                if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                $color = switch ($c.Status) { 'OK' { 'Success' } 'WARN' { 'Warning' } 'CRITICAL' { 'Error' } default { 'Info' } }
                Write-OutputColor "  │$($line.PadRight(72))│" -color $color
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $passed = @($checks | Where-Object { $_.Status -eq 'OK' }).Count
            Write-OutputColor "  │$("  Passed: $passed/$(@($checks).Count)   Issues: $regIssues".PadRight(72))│" -color $(if ($regIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'RegistryAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ TotalChecks = @($checks).Count; Passed = $passed; Issues = $regIssues }
                    Checks = $checks
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($regIssues -gt 0) { [Environment]::Exit(1) }
        }
        'ProfileAudit' {
            Write-OutputColor "  Auditing user profiles..." -color "Info"
            Write-OutputColor "" -color "Info"

            $profileIssues = 0
            $profileResults = @()

            try {
                $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop | Where-Object { -not $_.Special -and $_.LocalPath -notmatch 'systemprofile|LocalService|NetworkService' })
                foreach ($p in $profiles) {
                    $sizeMB = 0
                    $lastUse = $null
                    $staleDays = 0
                    $health = 'OK'

                    if ($null -ne $p.LastUseTime) {
                        $lastUse = $p.LastUseTime.ToString("yyyy-MM-ddTHH:mm:ss")
                        $staleDays = [math]::Round(((Get-Date) - $p.LastUseTime).TotalDays, 0)
                    }

                    # Profile size
                    if (Test-Path -LiteralPath $p.LocalPath) {
                        try {
                            $dirInfo = Get-ChildItem -LiteralPath $p.LocalPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
                            $sizeMB = [math]::Round($dirInfo.Sum / 1MB, 1)
                        } catch { }
                    }

                    if ($staleDays -gt 180) { $health = 'STALE'; $profileIssues++ }
                    if ($sizeMB -gt 5120) { $health = 'LARGE'; $profileIssues++ }

                    $username = $p.LocalPath.Split('\')[-1]
                    $profileResults += @{
                        Username   = $username
                        Path       = $p.LocalPath
                        SizeMB     = $sizeMB
                        LastUsed   = $lastUse
                        StaleDays  = $staleDays
                        Loaded     = $p.Loaded
                        Health     = $health
                    }
                }
            } catch {
                Write-OutputColor "  ERROR: Failed to query profiles: $($_.Exception.Message)" -color "Error"
                [Environment]::Exit(1)
            }

            $totalSizeMB = ($profileResults | ForEach-Object { $_.SizeMB } | Measure-Object -Sum).Sum
            $totalSizeGB = [math]::Round($totalSizeMB / 1024, 1)

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  PROFILE AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($p in ($profileResults | Sort-Object SizeMB -Descending)) {
                $uName = if ($p.Username.Length -gt 18) { $p.Username.Substring(0, 15) + "..." } else { $p.Username }
                $loaded = if ($p.Loaded) { "Active" } else { "" }
                $line = "  $($uName.PadRight(20)) $("$($p.SizeMB)MB".PadRight(12)) $("$($p.StaleDays)d".PadRight(8)) $loaded  [$($p.Health)]"
                if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                $color = switch ($p.Health) { 'OK' { 'Success' } 'STALE' { 'Warning' } 'LARGE' { 'Warning' } default { 'Info' } }
                Write-OutputColor "  │$($line.PadRight(72))│" -color $color
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $staleCount = @($profileResults | Where-Object { $_.Health -eq 'STALE' }).Count
            $largeCount = @($profileResults | Where-Object { $_.Health -eq 'LARGE' }).Count
            $summaryLine = "  Profiles: $(@($profileResults).Count)   Total: ${totalSizeGB}GB   Stale: $staleCount   Large: $largeCount"
            Write-OutputColor "  │$($summaryLine.PadRight(72))│" -color $(if ($profileIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'ProfileAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ TotalProfiles = @($profileResults).Count; TotalSizeGB = $totalSizeGB; Stale = $staleCount; Large = $largeCount; Issues = $profileIssues }
                    Profiles = $profileResults
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($profileIssues -gt 0) { [Environment]::Exit(1) }
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