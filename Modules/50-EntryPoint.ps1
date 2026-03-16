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
            if ($script:CLIQuiet)   { $elevateArgs += " -Quiet" }
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

        # CLI quick flags: -Version and -ListActions exit immediately
        if ($script:CLIVersion) {
            Write-Output "$($script:ToolFullName) v$($script:ScriptVersion)"
            [Environment]::Exit(0)
        }
        if ($script:CLIListActions) {
            $actionList = @(
                @{ Action = 'Cleanup';          Description = 'Disk cleanup (Light/Standard/Aggressive)' }
                @{ Action = 'Debloat';          Description = 'Remove bloatware and telemetry' }
                @{ Action = 'HealthCheck';      Description = 'System health report' }
                @{ Action = 'QuickScan';        Description = 'Health + disk + debloat analysis' }
                @{ Action = 'Inventory';        Description = 'Server inventory for CMDB' }
                @{ Action = 'DriftCheck';       Description = 'Configuration drift detection' }
                @{ Action = 'Snapshot';         Description = 'Performance metric capture' }
                @{ Action = 'Compliance';       Description = 'Unified health + readiness + drift report' }
                @{ Action = 'Harden';           Description = 'CIS-lite security hardening audit' }
                @{ Action = 'Remediate';        Description = 'Auto-fix drifted settings' }
                @{ Action = 'Aggregate';        Description = 'Fleet-wide report aggregation' }
                @{ Action = 'Compare';          Description = 'Side-by-side host comparison' }
                @{ Action = 'Export';            Description = 'Comprehensive server profile export' }
                @{ Action = 'Trend';            Description = 'Performance trend analysis' }
                @{ Action = 'CertCheck';        Description = 'Certificate expiry audit' }
                @{ Action = 'ReportHTML';       Description = 'Generate HTML reports' }
                @{ Action = 'ListeningPorts';   Description = 'TCP listening port inventory' }
                @{ Action = 'SoftwareList';     Description = 'Installed software audit' }
                @{ Action = 'Uptime';           Description = 'Uptime + reboot history' }
                @{ Action = 'ServiceAudit';     Description = 'Key service status audit' }
                @{ Action = 'EventAudit';       Description = 'Critical/error event log summary' }
                @{ Action = 'NetInfo';          Description = 'Network adapter configuration' }
                @{ Action = 'ScheduledExport';  Description = 'Automated export scheduling' }
                @{ Action = 'ValidateConfig';   Description = 'Batch config file validation' }
                @{ Action = 'Watch';            Description = 'Threshold-based monitoring gate' }
                @{ Action = 'Query';            Description = 'Search fleet export archive' }
                @{ Action = 'Diff';             Description = 'Full-profile change detection' }
                @{ Action = 'Baseline';         Description = 'Capture known-good profile' }
                @{ Action = 'Alert';            Description = 'Webhook/email/event log alerting' }
                @{ Action = 'FleetScan';        Description = 'Run any action across fleet via WinRM' }
                @{ Action = 'PatchStatus';      Description = 'Patch currency + pending reboot' }
                @{ Action = 'UserAudit';        Description = 'Local account security hygiene' }
                @{ Action = 'FirewallAudit';    Description = 'Firewall profile + rule analysis' }
                @{ Action = 'TaskAudit';        Description = 'Scheduled task health check' }
                @{ Action = 'DiskAudit';        Description = 'Physical disk + volume utilization' }
                @{ Action = 'TLSAudit';         Description = 'TLS/SSL protocol configuration' }
                @{ Action = 'SMBAudit';         Description = 'SMB protocol + share security' }
                @{ Action = 'DriverAudit';      Description = 'Driver signing audit' }
                @{ Action = 'TimeAudit';        Description = 'NTP sync + time drift detection' }
                @{ Action = 'BootAudit';        Description = 'Firmware + secure boot + reboot status' }
                @{ Action = 'GPOAudit';         Description = 'Applied Group Policy inventory' }
                @{ Action = 'MemoryAudit';      Description = 'RAM + DIMM + page file audit' }
                @{ Action = 'ProcessAudit';     Description = 'Top CPU/memory + unsigned processes' }
                @{ Action = 'BackupAudit';      Description = 'VSS writers + shadow copies + WSB' }
                @{ Action = 'ShareAudit';       Description = 'SMB + NTFS share permissions' }
                @{ Action = 'DNSAudit';         Description = 'DNS config + resolution tests' }
                @{ Action = 'PowerAudit';       Description = 'Power plan + sleep configuration' }
                @{ Action = 'RegistryAudit';    Description = 'Security hardening baseline' }
                @{ Action = 'ProfileAudit';     Description = 'User profile size + staleness' }
                @{ Action = 'HyperVAudit';      Description = 'VM inventory + checkpoints + replication' }
                @{ Action = 'NetworkAudit';     Description = 'Adapter config + IP + routing' }
                @{ Action = 'StorageAudit';     Description = 'Storage pools + virtual disks' }
                @{ Action = 'FeatureAudit';     Description = 'Installed roles + features' }
                @{ Action = 'AutoStartAudit';   Description = 'Registry Run keys + startup + services' }
                @{ Action = 'BIOSAudit';        Description = 'BIOS/firmware + serial numbers' }
                @{ Action = 'ClusterAudit';     Description = 'Failover cluster nodes + resources' }
                @{ Action = 'AuditPolicyAudit'; Description = 'Windows security audit policies' }
                @{ Action = 'EnvAudit';         Description = 'Environment variables + PATH analysis' }
                @{ Action = 'CrashAudit';       Description = 'BSOD/crash dump history' }
                @{ Action = 'LocalGroupAudit';  Description = 'Local groups + membership' }
                @{ Action = 'WMIAudit';         Description = 'WMI repository health' }
                @{ Action = 'TempAudit';        Description = 'Temp file + reclaimable space analysis' }
                @{ Action = 'UpdatePolicyAudit'; Description = 'Windows Update policy + WSUS config' }
                @{ Action = 'IISAudit';         Description = 'IIS sites + app pools' }
                @{ Action = 'SSHAudit';         Description = 'OpenSSH server config + keys' }
                @{ Action = 'BitLockerAudit';  Description = 'BitLocker encryption status' }
                @{ Action = 'PrintAudit';      Description = 'Printer inventory + queue status' }
                @{ Action = 'CredGuardAudit';  Description = 'Credential Guard + VBS + HVCI' }
                @{ Action = 'PortAudit';       Description = 'Outbound connectivity tests' }
                @{ Action = 'AntivirusAudit';  Description = 'Windows Defender + AV status' }
                @{ Action = 'DotNetAudit';     Description = '.NET Framework + Runtime versions' }
                @{ Action = 'RDPAudit';        Description = 'RDP config + active sessions' }
                @{ Action = 'VPNAudit';        Description = 'VPN connections + RRAS status' }
                @{ Action = 'HostsFileAudit'; Description = 'Hosts file entries + suspicious redirects' }
                @{ Action = 'NetStatAudit';   Description = 'Established TCP connections' }
                @{ Action = 'LicenseAudit';   Description = 'Windows activation + licensing' }
                @{ Action = 'USBDeviceAudit'; Description = 'USB devices + storage policy' }
                @{ Action = 'AppLockerAudit'; Description = 'AppLocker policy + rules' }
                @{ Action = 'EventSubAudit';  Description = 'WMI event subscriptions (persistence)' }
                @{ Action = 'HotfixAudit';    Description = 'Installed hotfix/KB inventory' }
                @{ Action = 'SysInfoAudit';   Description = 'Comprehensive system snapshot' }
                @{ Action = 'LogonAudit';     Description = 'Recent logons + failed attempts' }
                @{ Action = 'ACLAudit';       Description = 'Critical folder permissions' }
                @{ Action = 'RecoveryAudit';  Description = 'Restore points + recovery options' }
                @{ Action = 'ServiceAccountAudit'; Description = 'Services with custom accounts' }
                @{ Action = 'ProxyAudit';     Description = 'System/WinHTTP proxy config' }
                @{ Action = 'PendingRebootAudit'; Description = 'Comprehensive reboot detection' }
                @{ Action = 'PageFileAudit';  Description = 'Page file config + utilization' }
                @{ Action = 'CPUAudit';       Description = 'CPU topology + utilization' }
                @{ Action = 'DefenderExclusionAudit'; Description = 'Defender exclusion paths/processes' }
                @{ Action = 'KerberosAudit';  Description = 'Kerberos tickets + config' }
                @{ Action = 'DHCPAudit';      Description = 'DHCP client lease details' }
                @{ Action = 'NUMAAudit';      Description = 'NUMA topology' }
                @{ Action = 'SymlinkAudit';   Description = 'Symlinks in system directories' }
                @{ Action = 'StartupScriptAudit'; Description = 'GPO startup/shutdown scripts' }
                @{ Action = 'SecureChannelAudit'; Description = 'Domain secure channel health' }
                @{ Action = 'ComObjectAudit'; Description = 'Non-system COM object persistence' }
                @{ Action = 'FirewallLogAudit'; Description = 'Firewall log analysis + drops' }
                @{ Action = 'ScheduledRebootAudit'; Description = 'Scheduled reboots + history' }
                @{ Action = 'PowerShellAudit'; Description = 'PS exec policy + logging + CLM' }
                @{ Action = 'RouteTableAudit'; Description = 'Full routing table' }
                @{ Action = 'TokenPrivilegeAudit'; Description = 'Current process privileges' }
                @{ Action = 'WindowsCapabilityAudit'; Description = 'Installed capabilities + RSAT' }
                @{ Action = 'ARPTableAudit';  Description = 'ARP neighbor cache' }
                @{ Action = 'LocaleAudit';    Description = 'Language + region + timezone' }
                @{ Action = 'TaskHistoryAudit'; Description = 'Scheduled task run history' }
                @{ Action = 'NTFSAudit';      Description = 'NTFS volume health + features' }
                @{ Action = 'Win11Cleanup';    Description = 'Apply Windows 10-style UI tweaks (Win11/2025)' }
                @{ Action = 'DarkMode';        Description = 'Set OS to dark theme' }
                @{ Action = 'LightMode';       Description = 'Set OS to light theme' }
                @{ Action = 'iSCSIAudit';      Description = 'iSCSI sessions, targets, MPIO paths' }
                @{ Action = 'NICTeamAudit';    Description = 'SET/LBFO team health + member status' }
                @{ Action = 'SMBSessionAudit'; Description = 'Active SMB sessions + open files' }
                @{ Action = 'WindowsUpdateAudit'; Description = 'List pending updates (no install)' }
                @{ Action = 'Batch';            Description = 'JSON-driven full configuration' }
            )
            if ($script:CLIOutputFormat -eq 'JSON') {
                Write-Output ($actionList | ConvertTo-Json -Depth 10)
            } else {
                Write-OutputColor "  $($script:ToolFullName) v$($script:ScriptVersion) - Available Actions ($(@($actionList).Count))" -color "Info"
                Write-OutputColor "" -color "Info"
                foreach ($a in $actionList) {
                    Write-OutputColor "  $($a.Action.PadRight(22)) $($a.Description)" -color "Info"
                }
            }
            [Environment]::Exit(0)
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
    if (-not $script:CLIQuiet) {
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
    }

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
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
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
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
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

            $targets = @(Get-FleetTargets -Targets $fleetConfig.Targets)
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
            $summaryLine = "  Recent: $(@($recentUpdates).Count)   Succeeded: $succeeded   Failed: $failed"
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
                        TotalRecent        = @($recentUpdates).Count
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
            $summaryLine = "  Total: $(@($accounts).Count)   Enabled: $enabledCount   Disabled: $disabledCount   Issues: $issueCount   Admins: $adminCount"
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
                        Total          = @($accounts).Count
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
        'HyperVAudit' {
            Write-OutputColor "  Auditing Hyper-V configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $hvIssues = 0
            $vmResults = @()
            $hvInstalled = $false

            # Check if Hyper-V is installed
            try {
                $hvFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -ErrorAction SilentlyContinue
                if ($null -eq $hvFeature) { $hvFeature = Get-WindowsFeature -Name Hyper-V -ErrorAction SilentlyContinue }
                $hvInstalled = ($null -ne $hvFeature -and ($hvFeature.State -eq 'Enabled' -or $hvFeature.Installed -eq $true))
            } catch { }

            if (-not $hvInstalled) {
                Write-OutputColor "  Hyper-V is not installed on this system." -color "Info"
            } else {
                try {
                    $vms = @(Get-VM -ErrorAction Stop)
                    foreach ($vm in $vms) {
                        $health = 'OK'
                        if ($vm.State -ne 'Running' -and $vm.State -ne 'Off') { $health = 'WARN'; $hvIssues++ }

                        $checkpoints = @(Get-VMCheckpoint -VMName $vm.Name -ErrorAction SilentlyContinue)
                        if (@($checkpoints).Count -gt 3) { $health = 'WARN'; $hvIssues++ }

                        $repl = $null
                        try {
                            $replObj = Get-VMReplication -VMName $vm.Name -ErrorAction SilentlyContinue
                            if ($null -ne $replObj) {
                                $repl = @{ State = "$($replObj.State)"; Health = "$($replObj.Health)"; Mode = "$($replObj.Mode)" }
                                if ("$($replObj.Health)" -ne 'Normal' -and "$($replObj.Health)" -ne '') { $hvIssues++ }
                            }
                        } catch { }

                        $vmResults += @{
                            Name        = $vm.Name
                            State       = "$($vm.State)"
                            CPUCount    = $vm.ProcessorCount
                            MemoryMB    = [math]::Round($vm.MemoryAssigned / 1MB, 0)
                            Uptime      = if ($vm.Uptime) { "$($vm.Uptime)" } else { "" }
                            Checkpoints = @($checkpoints).Count
                            Replication = $repl
                            Health      = $health
                        }
                    }
                } catch {
                    Write-OutputColor "  ERROR: Failed to query VMs: $($_.Exception.Message)" -color "Error"
                    [Environment]::Exit(1)
                }
            }

            $running = @($vmResults | Where-Object { $_.State -eq 'Running' }).Count
            $off = @($vmResults | Where-Object { $_.State -eq 'Off' }).Count
            $other = @($vmResults).Count - $running - $off

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  HYPERV AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (-not $hvInstalled) {
                Write-OutputColor "  │$("  Hyper-V: Not installed".PadRight(72))│" -color "Info"
            } elseif (@($vmResults).Count -eq 0) {
                Write-OutputColor "  │$("  (No virtual machines found)".PadRight(72))│" -color "Info"
            } else {
                foreach ($v in $vmResults) {
                    $vName = if ($v.Name.Length -gt 25) { $v.Name.Substring(0, 22) + "..." } else { $v.Name }
                    $chkStr = if ($v.Checkpoints -gt 0) { "Chk:$($v.Checkpoints)" } else { "" }
                    $line = "  $($vName.PadRight(27)) $("$($v.State)".PadRight(10)) $("$($v.MemoryMB)MB".PadRight(10)) $chkStr  [$($v.Health)]"
                    if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                    $color = switch ($v.Health) { 'OK' { 'Success' } 'WARN' { 'Warning' } default { 'Info' } }
                    Write-OutputColor "  │$($line.PadRight(72))│" -color $color
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $summaryLine = "  VMs: $(@($vmResults).Count)   Running: $running   Off: $off   Other: $other   Issues: $hvIssues"
            Write-OutputColor "  │$($summaryLine.PadRight(72))│" -color $(if ($hvIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'HyperVAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ HyperVInstalled = $hvInstalled; TotalVMs = @($vmResults).Count; Running = $running; Off = $off; Other = $other; Issues = $hvIssues }
                    VMs = $vmResults
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($hvIssues -gt 0) { [Environment]::Exit(1) }
        }
        'NetworkAudit' {
            Write-OutputColor "  Auditing network configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $netIssues = 0
            $adapterResults = @()

            try {
                $adapters = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })
                foreach ($a in $adapters) {
                    $ipConfig = @()
                    try {
                        $ips = @(Get-NetIPAddress -InterfaceIndex $a.ifIndex -ErrorAction SilentlyContinue | Where-Object { $_.AddressFamily -eq 'IPv4' -and $_.IPAddress -ne '127.0.0.1' })
                        foreach ($ip in $ips) {
                            $ipConfig += @{ Address = $ip.IPAddress; Prefix = $ip.PrefixLength; Type = "$($ip.PrefixOrigin)" }
                        }
                    } catch { }

                    $gateway = ""
                    try {
                        $gw = Get-NetRoute -InterfaceIndex $a.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($null -ne $gw) { $gateway = $gw.NextHop }
                    } catch { }

                    $health = 'OK'
                    if ($a.LinkSpeed -match '100\s*Mbps') { $health = 'WARN'; $netIssues++ }

                    $adapterResults += @{
                        Name       = $a.Name
                        MacAddress = $a.MacAddress
                        LinkSpeed  = "$($a.LinkSpeed)"
                        DriverVer  = "$($a.DriverVersion)"
                        IPs        = $ipConfig
                        Gateway    = $gateway
                        Health     = $health
                    }
                }
            } catch {
                Write-OutputColor "  ERROR: Failed to query adapters: $($_.Exception.Message)" -color "Error"
                [Environment]::Exit(1)
            }

            # Default route
            $defaultRoutes = @()
            try {
                $routes = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)
                foreach ($r in $routes) { $defaultRoutes += @{ Interface = $r.InterfaceAlias; NextHop = $r.NextHop; Metric = $r.RouteMetric } }
            } catch { }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  NETWORK AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($a in $adapterResults) {
                $aName = if ($a.Name.Length -gt 20) { $a.Name.Substring(0, 17) + "..." } else { $a.Name }
                $ipStr = if (@($a.IPs).Count -gt 0) { $a.IPs[0].Address } else { "No IP" }
                $line = "  $($aName.PadRight(22)) $($ipStr.PadRight(16)) $($a.LinkSpeed)  [$($a.Health)]"
                if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                $color = if ($a.Health -eq 'OK') { 'Success' } else { 'Warning' }
                Write-OutputColor "  │$($line.PadRight(72))│" -color $color
            }
            if (@($defaultRoutes).Count -gt 0) {
                Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                foreach ($r in $defaultRoutes) {
                    Write-OutputColor "  │$("  Route: $($r.Interface) -> $($r.NextHop) (metric $($r.Metric))".PadRight(72))│" -color "Info"
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Adapters: $(@($adapterResults).Count)   Routes: $(@($defaultRoutes).Count)   Issues: $netIssues".PadRight(72))│" -color $(if ($netIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'NetworkAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ Adapters = @($adapterResults).Count; DefaultRoutes = @($defaultRoutes).Count; Issues = $netIssues }
                    Adapters = $adapterResults; DefaultRoutes = $defaultRoutes
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($netIssues -gt 0) { [Environment]::Exit(1) }
        }
        'StorageAudit' {
            Write-OutputColor "  Auditing storage configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $storIssues = 0
            $pools = @()
            $vDisks = @()

            # Storage Pools
            try {
                $storagePools = @(Get-StoragePool -ErrorAction Stop | Where-Object { $_.FriendlyName -ne 'Primordial' })
                foreach ($sp in $storagePools) {
                    $health = 'OK'
                    if ("$($sp.HealthStatus)" -ne 'Healthy') { $health = 'FAIL'; $storIssues++ }
                    if ("$($sp.OperationalStatus)" -ne 'OK') { $health = 'FAIL'; if ("$($sp.HealthStatus)" -eq 'Healthy') { $storIssues++ } }
                    $pools += @{
                        Name              = $sp.FriendlyName
                        SizeGB            = [math]::Round($sp.Size / 1GB, 1)
                        AllocatedGB       = [math]::Round($sp.AllocatedSize / 1GB, 1)
                        HealthStatus      = "$($sp.HealthStatus)"
                        OperationalStatus = "$($sp.OperationalStatus)"
                        Health            = $health
                    }
                }
            } catch { }

            # Virtual Disks
            try {
                $virtualDisks = @(Get-VirtualDisk -ErrorAction Stop)
                foreach ($vd in $virtualDisks) {
                    $health = 'OK'
                    if ("$($vd.HealthStatus)" -ne 'Healthy') { $health = 'FAIL'; $storIssues++ }
                    if ("$($vd.OperationalStatus)" -ne 'OK') { $health = 'FAIL'; if ("$($vd.HealthStatus)" -eq 'Healthy') { $storIssues++ } }
                    $vDisks += @{
                        Name              = $vd.FriendlyName
                        SizeGB            = [math]::Round($vd.Size / 1GB, 1)
                        ResiliencyType    = "$($vd.ResiliencySettingName)"
                        HealthStatus      = "$($vd.HealthStatus)"
                        OperationalStatus = "$($vd.OperationalStatus)"
                        Health            = $health
                    }
                }
            } catch { }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  STORAGE AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (@($pools).Count -eq 0 -and @($vDisks).Count -eq 0) {
                Write-OutputColor "  │$("  (No storage pools or virtual disks configured)".PadRight(72))│" -color "Info"
            } else {
                if (@($pools).Count -gt 0) {
                    Write-OutputColor "  │$("  STORAGE POOLS".PadRight(72))│" -color "Info"
                    foreach ($p in $pools) {
                        $line = "  $($p.Name.PadRight(25)) $($p.AllocatedGB)/$($p.SizeGB)GB  [$($p.Health)]"
                        if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                        $color = if ($p.Health -eq 'OK') { 'Success' } else { 'Error' }
                        Write-OutputColor "  │$($line.PadRight(72))│" -color $color
                    }
                }
                if (@($vDisks).Count -gt 0) {
                    Write-OutputColor "  │$("  VIRTUAL DISKS".PadRight(72))│" -color "Info"
                    foreach ($v in $vDisks) {
                        $line = "  $($v.Name.PadRight(25)) $($v.SizeGB)GB  $($v.ResiliencyType)  [$($v.Health)]"
                        if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                        $color = if ($v.Health -eq 'OK') { 'Success' } else { 'Error' }
                        Write-OutputColor "  │$($line.PadRight(72))│" -color $color
                    }
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Pools: $(@($pools).Count)   VDisks: $(@($vDisks).Count)   Issues: $storIssues".PadRight(72))│" -color $(if ($storIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'StorageAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ Pools = @($pools).Count; VirtualDisks = @($vDisks).Count; Issues = $storIssues }
                    StoragePools = $pools; VirtualDisks = $vDisks
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($storIssues -gt 0) { [Environment]::Exit(1) }
        }
        'FeatureAudit' {
            Write-OutputColor "  Auditing installed Windows features..." -color "Info"
            Write-OutputColor "" -color "Info"

            $featureIssues = 0
            $featureResults = @()

            try {
                # Try Server features first
                $features = @(Get-WindowsFeature -ErrorAction Stop | Where-Object { $_.Installed -eq $true })
                foreach ($f in $features) {
                    $featureResults += @{
                        Name        = $f.Name
                        DisplayName = $f.DisplayName
                        FeatureType = "$($f.FeatureType)"
                        Depth       = $f.Depth
                    }
                }
            } catch {
                # Fallback to client features
                try {
                    $features = @(Get-WindowsOptionalFeature -Online -ErrorAction Stop | Where-Object { $_.State -eq 'Enabled' })
                    foreach ($f in $features) {
                        $featureResults += @{
                            Name        = $f.FeatureName
                            DisplayName = $f.FeatureName
                            FeatureType = "Optional"
                            Depth       = 0
                        }
                    }
                } catch {
                    Write-OutputColor "  WARNING: Could not query features: $($_.Exception.Message)" -color "Warning"
                }
            }

            # Categorize
            $roles = @($featureResults | Where-Object { $_.FeatureType -eq 'Role' })
            $roleServices = @($featureResults | Where-Object { $_.FeatureType -eq 'Role Service' })
            $otherFeatures = @($featureResults | Where-Object { $_.FeatureType -ne 'Role' -and $_.FeatureType -ne 'Role Service' })

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  FEATURE AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (@($roles).Count -gt 0) {
                Write-OutputColor "  │$("  INSTALLED ROLES ($(@($roles).Count))".PadRight(72))│" -color "Info"
                foreach ($r in $roles) {
                    $rName = if ($r.DisplayName.Length -gt 65) { $r.DisplayName.Substring(0, 62) + "..." } else { $r.DisplayName }
                    Write-OutputColor "  │$("  $rName".PadRight(72))│" -color "Success"
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $summaryLine = "  Roles: $(@($roles).Count)   Services: $(@($roleServices).Count)   Features: $(@($otherFeatures).Count)   Total: $(@($featureResults).Count)"
            Write-OutputColor "  │$($summaryLine.PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'FeatureAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ Roles = @($roles).Count; RoleServices = @($roleServices).Count; Features = @($otherFeatures).Count; Total = @($featureResults).Count; Issues = $featureIssues }
                    InstalledFeatures = $featureResults
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($featureIssues -gt 0) { [Environment]::Exit(1) }
        }
        'AutoStartAudit' {
            Write-OutputColor "  Auditing auto-start entries..." -color "Info"
            Write-OutputColor "" -color "Info"

            $autoIssues = 0
            $entries = @()

            # Registry Run keys
            $runPaths = @(
                @{ Scope = 'Machine'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' }
                @{ Scope = 'Machine'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' }
                @{ Scope = 'Machine'; Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' }
                @{ Scope = 'User';    Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' }
                @{ Scope = 'User';    Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' }
            )

            foreach ($rp in $runPaths) {
                if (Test-Path $rp.Path) {
                    try {
                        $reg = Get-ItemProperty -Path $rp.Path -ErrorAction SilentlyContinue
                        if ($null -ne $reg) {
                            foreach ($prop in $reg.PSObject.Properties) {
                                if ($prop.Name -match '^PS') { continue }
                                $entries += @{ Name = $prop.Name; Command = "$($prop.Value)"; Source = $rp.Path; Scope = $rp.Scope; Type = 'Registry' }
                            }
                        }
                    } catch { }
                }
            }

            # Startup folder
            $startupPaths = @(
                [Environment]::GetFolderPath('CommonStartup')
                [Environment]::GetFolderPath('Startup')
            )
            foreach ($sp in $startupPaths) {
                if ($sp -and (Test-Path -LiteralPath $sp)) {
                    try {
                        $items = @(Get-ChildItem -LiteralPath $sp -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })
                        foreach ($item in $items) {
                            $entries += @{ Name = $item.Name; Command = $item.FullName; Source = $sp; Scope = 'Startup'; Type = 'StartupFolder' }
                        }
                    } catch { }
                }
            }

            # Auto-start services (non-Microsoft)
            $autoServices = @()
            try {
                $autoServices = @(Get-CimInstance -ClassName Win32_Service -Filter "StartMode='Auto'" -ErrorAction Stop |
                    Where-Object { $_.PathName -notmatch 'Windows\\system32|Windows\\SysWOW64|Microsoft' -and $null -ne $_.PathName -and $_.PathName -ne '' })
                foreach ($svc in $autoServices) {
                    $entries += @{ Name = $svc.Name; Command = "$($svc.PathName)"; Source = 'Services'; Scope = 'Machine'; Type = 'Service' }
                }
            } catch { }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  AUTOSTART AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $regEntries = @($entries | Where-Object { $_.Type -eq 'Registry' })
            $folderEntries = @($entries | Where-Object { $_.Type -eq 'StartupFolder' })
            $svcEntries = @($entries | Where-Object { $_.Type -eq 'Service' })
            if (@($regEntries).Count -gt 0) {
                Write-OutputColor "  │$("  REGISTRY ($(@($regEntries).Count))".PadRight(72))│" -color "Info"
                foreach ($e in $regEntries) {
                    $eName = if ($e.Name.Length -gt 30) { $e.Name.Substring(0, 27) + "..." } else { $e.Name }
                    $line = "  $($eName.PadRight(32)) [$($e.Scope)]"
                    Write-OutputColor "  │$($line.PadRight(72))│" -color "Info"
                }
            }
            if (@($svcEntries).Count -gt 0) {
                Write-OutputColor "  │$("  NON-MICROSOFT AUTO SERVICES ($(@($svcEntries).Count))".PadRight(72))│" -color "Info"
                foreach ($e in $svcEntries) {
                    $eName = if ($e.Name.Length -gt 65) { $e.Name.Substring(0, 62) + "..." } else { $e.Name }
                    Write-OutputColor "  │$("  $eName".PadRight(72))│" -color "Info"
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $summaryLine = "  Registry: $(@($regEntries).Count)   Startup: $(@($folderEntries).Count)   Services: $(@($svcEntries).Count)   Total: $(@($entries).Count)"
            Write-OutputColor "  │$($summaryLine.PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'AutoStartAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ Registry = @($regEntries).Count; StartupFolder = @($folderEntries).Count; Services = @($svcEntries).Count; Total = @($entries).Count; Issues = $autoIssues }
                    Entries = $entries
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($autoIssues -gt 0) { [Environment]::Exit(1) }
        }
        'BIOSAudit' {
            Write-OutputColor "  Auditing BIOS/firmware information..." -color "Info"
            Write-OutputColor "" -color "Info"

            $biosIssues = 0
            $biosInfo = @{}
            $systemInfo = @{}

            try {
                $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
                $biosInfo = @{
                    Manufacturer   = "$($bios.Manufacturer)"
                    Version        = "$($bios.SMBIOSBIOSVersion)"
                    ReleaseDate    = if ($null -ne $bios.ReleaseDate) { $bios.ReleaseDate.ToString("yyyy-MM-dd") } else { "Unknown" }
                    SerialNumber   = "$($bios.SerialNumber)"
                    SMBIOSVersion  = "$($bios.SMBIOSMajorVersion).$($bios.SMBIOSMinorVersion)"
                }
            } catch {
                Write-OutputColor "  WARNING: Could not query BIOS: $($_.Exception.Message)" -color "Warning"
            }

            try {
                $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
                $systemInfo = @{
                    Manufacturer = "$($cs.Manufacturer)"
                    Model        = "$($cs.Model)"
                    SystemType   = "$($cs.SystemType)"
                    TotalMemoryGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
                    Domain       = "$($cs.Domain)"
                    DomainRole   = $cs.DomainRole
                }
            } catch { }

            try {
                $board = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop
                $systemInfo['BaseBoardProduct'] = "$($board.Product)"
                $systemInfo['BaseBoardManufacturer'] = "$($board.Manufacturer)"
                $systemInfo['BaseBoardSerial'] = "$($board.SerialNumber)"
            } catch { }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  BIOS AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if ($biosInfo.Count -gt 0) {
                Write-OutputColor "  │$("  BIOS Vendor:    $($biosInfo.Manufacturer)".PadRight(72))│" -color "Info"
                Write-OutputColor "  │$("  BIOS Version:   $($biosInfo.Version)".PadRight(72))│" -color "Info"
                Write-OutputColor "  │$("  Release Date:   $($biosInfo.ReleaseDate)".PadRight(72))│" -color "Info"
                Write-OutputColor "  │$("  Serial Number:  $($biosInfo.SerialNumber)".PadRight(72))│" -color "Info"
                Write-OutputColor "  │$("  SMBIOS:         $($biosInfo.SMBIOSVersion)".PadRight(72))│" -color "Info"
            }
            if ($systemInfo.Count -gt 0) {
                Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                Write-OutputColor "  │$("  System:         $($systemInfo.Manufacturer) $($systemInfo.Model)".PadRight(72))│" -color "Info"
                Write-OutputColor "  │$("  Type:           $($systemInfo.SystemType)".PadRight(72))│" -color "Info"
                if ($systemInfo.ContainsKey('BaseBoardProduct')) {
                    Write-OutputColor "  │$("  Baseboard:      $($systemInfo.BaseBoardManufacturer) $($systemInfo.BaseBoardProduct)".PadRight(72))│" -color "Info"
                }
            }
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'BIOSAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ Issues = $biosIssues }
                    BIOS = $biosInfo; System = $systemInfo
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($biosIssues -gt 0) { [Environment]::Exit(1) }
        }
        'ClusterAudit' {
            Write-OutputColor "  Auditing failover cluster..." -color "Info"
            Write-OutputColor "" -color "Info"

            $clusterIssues = 0
            $clusterName = ""
            $nodeResults = @()
            $resourceResults = @()
            $clusterInstalled = $false

            try {
                $cluster = Get-Cluster -ErrorAction Stop
                $clusterInstalled = $true
                $clusterName = $cluster.Name

                # Nodes
                $nodes = @(Get-ClusterNode -ErrorAction Stop)
                foreach ($n in $nodes) {
                    $health = 'OK'
                    if ("$($n.State)" -ne 'Up') { $health = 'FAIL'; $clusterIssues++ }
                    $nodeResults += @{ Name = $n.Name; State = "$($n.State)"; Health = $health }
                }

                # Resources
                $resources = @(Get-ClusterResource -ErrorAction Stop)
                foreach ($r in $resources) {
                    $health = 'OK'
                    if ("$($r.State)" -ne 'Online') { $health = 'WARN'; $clusterIssues++ }
                    $resourceResults += @{ Name = $r.Name; ResourceType = "$($r.ResourceType)"; State = "$($r.State)"; OwnerNode = "$($r.OwnerNode)"; Health = $health }
                }
            } catch {
                $clusterInstalled = $false
            }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  CLUSTER AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (-not $clusterInstalled) {
                Write-OutputColor "  │$("  Failover Clustering: Not configured".PadRight(72))│" -color "Info"
            } else {
                Write-OutputColor "  │$("  Cluster: $clusterName".PadRight(72))│" -color "Success"
                Write-OutputColor "  │$("  NODES ($(@($nodeResults).Count))".PadRight(72))│" -color "Info"
                foreach ($n in $nodeResults) {
                    $color = if ($n.Health -eq 'OK') { 'Success' } else { 'Error' }
                    Write-OutputColor "  │$("  $($n.Name.PadRight(30)) $($n.State)  [$($n.Health)]".PadRight(72))│" -color $color
                }
                $failedRes = @($resourceResults | Where-Object { $_.Health -ne 'OK' })
                if (@($failedRes).Count -gt 0) {
                    Write-OutputColor "  │$("  OFFLINE/FAILED RESOURCES ($(@($failedRes).Count))".PadRight(72))│" -color "Warning"
                    foreach ($r in $failedRes) {
                        $rName = if ($r.Name.Length -gt 30) { $r.Name.Substring(0, 27) + "..." } else { $r.Name }
                        Write-OutputColor "  │$("  $($rName.PadRight(32)) $($r.State)".PadRight(72))│" -color "Warning"
                    }
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Nodes: $(@($nodeResults).Count)   Resources: $(@($resourceResults).Count)   Issues: $clusterIssues".PadRight(72))│" -color $(if ($clusterIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'ClusterAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ ClusterInstalled = $clusterInstalled; ClusterName = $clusterName; Nodes = @($nodeResults).Count; Resources = @($resourceResults).Count; Issues = $clusterIssues }
                    Nodes = $nodeResults; Resources = $resourceResults
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($clusterIssues -gt 0) { [Environment]::Exit(1) }
        }
        'AuditPolicyAudit' {
            Write-OutputColor "  Auditing Windows audit policies..." -color "Info"
            Write-OutputColor "" -color "Info"

            $apIssues = 0
            $policies = @()

            try {
                $auditOutput = & auditpol /get /category:* 2>&1
                $auditStr = $auditOutput -join "`n"
                $lines = $auditStr -split "`n"
                $currentCategory = ""

                foreach ($line in $lines) {
                    $trimmed = $line.Trim()
                    if ($trimmed -eq '' -or $trimmed -match '^(System|Machine|The command)') { continue }

                    # Category header (no leading spaces, no "No Auditing" etc.)
                    if ($line -match '^\S' -and $trimmed -notmatch '(Success|Failure|No Auditing)') {
                        $currentCategory = $trimmed
                        continue
                    }

                    # Subcategory line
                    if ($line -match '^\s{2}\S' -and $trimmed -match '(.+?)\s{2,}(Success and Failure|Success|Failure|No Auditing)') {
                        $regexMatches = $Matches
                        $subcat = $regexMatches[1].Trim()
                        $setting = $regexMatches[2].Trim()
                        $status = if ($setting -eq 'No Auditing') { 'WARN' } else { 'OK' }

                        $policies += @{
                            Category    = $currentCategory
                            Subcategory = $subcat
                            Setting     = $setting
                            Status      = $status
                        }
                        if ($status -eq 'WARN') { $apIssues++ }
                    }
                }
            } catch {
                Write-OutputColor "  WARNING: Could not query audit policies: $($_.Exception.Message)" -color "Warning"
            }

            $configured = @($policies | Where-Object { $_.Status -eq 'OK' }).Count
            $notAudited = @($policies | Where-Object { $_.Status -eq 'WARN' }).Count

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  AUDIT POLICY AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $categories = @($policies | ForEach-Object { $_.Category } | Select-Object -Unique)
            foreach ($cat in $categories) {
                $catPolicies = @($policies | Where-Object { $_.Category -eq $cat })
                $catConfigured = @($catPolicies | Where-Object { $_.Status -eq 'OK' }).Count
                $color = if ($catConfigured -eq @($catPolicies).Count) { "Success" } else { "Warning" }
                $catName = if ($cat.Length -gt 40) { $cat.Substring(0, 37) + "..." } else { $cat }
                Write-OutputColor "  │$("  $($catName.PadRight(42)) $catConfigured/$(@($catPolicies).Count) configured".PadRight(72))│" -color $color
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Total: $(@($policies).Count)   Configured: $configured   Not Audited: $notAudited".PadRight(72))│" -color $(if ($apIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'AuditPolicyAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ Total = @($policies).Count; Configured = $configured; NotAudited = $notAudited; Issues = $apIssues }
                    Policies = $policies
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($apIssues -gt 0) { [Environment]::Exit(1) }
        }
        'EnvAudit' {
            Write-OutputColor "  Auditing environment variables..." -color "Info"
            Write-OutputColor "" -color "Info"

            $envIssues = 0
            $sysVars = @()
            $pathEntries = @()
            $pathIssues = @()

            # System environment variables
            try {
                $sysEnv = [Environment]::GetEnvironmentVariables('Machine')
                foreach ($key in ($sysEnv.Keys | Sort-Object)) {
                    $sysVars += @{ Name = "$key"; Value = "$($sysEnv[$key])"; Scope = 'Machine' }
                }
            } catch { }

            # PATH analysis
            $systemPath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
            if ($systemPath) {
                $dirs = $systemPath -split ';' | Where-Object { $_ -ne '' }
                $seen = @{}
                foreach ($dir in $dirs) {
                    $exists = Test-Path -LiteralPath $dir -ErrorAction SilentlyContinue
                    $duplicate = $seen.ContainsKey($dir.ToLower())
                    $seen[$dir.ToLower()] = $true
                    $status = 'OK'
                    if (-not $exists) { $status = 'MISSING'; $envIssues++ }
                    if ($duplicate) { $status = 'DUPLICATE'; $envIssues++ }
                    $pathEntries += @{ Directory = $dir; Exists = $exists; Duplicate = $duplicate; Status = $status }
                }
            }
            if ($pathEntries.Count -gt 50) { $pathIssues += "PATH has $($pathEntries.Count) entries (excessive)" }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  ENV AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  System Variables: $(@($sysVars).Count)".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  PATH Entries:     $(@($pathEntries).Count)".PadRight(72))│" -color $(if (@($pathEntries).Count -gt 50) { "Warning" } else { "Info" })
            $missing = @($pathEntries | Where-Object { $_.Status -eq 'MISSING' })
            $dupes = @($pathEntries | Where-Object { $_.Status -eq 'DUPLICATE' })
            if (@($missing).Count -gt 0) {
                Write-OutputColor "  │$("  MISSING PATH ENTRIES ($(@($missing).Count))".PadRight(72))│" -color "Warning"
                foreach ($m in $missing) {
                    $mDir = if ($m.Directory.Length -gt 65) { $m.Directory.Substring(0, 62) + "..." } else { $m.Directory }
                    Write-OutputColor "  │$("  $mDir".PadRight(72))│" -color "Warning"
                }
            }
            if (@($dupes).Count -gt 0) {
                Write-OutputColor "  │$("  DUPLICATE PATH ENTRIES ($(@($dupes).Count))".PadRight(72))│" -color "Warning"
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Issues: $envIssues".PadRight(72))│" -color $(if ($envIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'EnvAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ SystemVars = @($sysVars).Count; PathEntries = @($pathEntries).Count; Missing = @($missing).Count; Duplicates = @($dupes).Count; Issues = $envIssues }
                    SystemVariables = $sysVars; PathAnalysis = $pathEntries
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($envIssues -gt 0) { [Environment]::Exit(1) }
        }
        'CrashAudit' {
            Write-OutputColor "  Auditing crash/BSOD history..." -color "Info"
            Write-OutputColor "" -color "Info"

            $crashIssues = 0
            $crashes = @()
            $dumpFiles = @()

            # Check for BugCheck events (Event ID 1001 from BugCheck)
            try {
                $bugChecks = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001 } -MaxEvents 20 -ErrorAction SilentlyContinue)
                foreach ($bc in $bugChecks) {
                    $crashes += @{
                        TimeCreated = $bc.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ss")
                        Message     = if ($bc.Message.Length -gt 200) { $bc.Message.Substring(0, 197) + "..." } else { $bc.Message }
                        EventId     = $bc.Id
                    }
                    $crashIssues++
                }
            } catch { }

            # Also check for unexpected shutdowns (Event ID 6008)
            try {
                $unexpectedShutdowns = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 6008 } -MaxEvents 10 -ErrorAction SilentlyContinue)
                foreach ($us in $unexpectedShutdowns) {
                    $crashes += @{
                        TimeCreated = $us.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ss")
                        Message     = "Unexpected shutdown"
                        EventId     = 6008
                    }
                    $crashIssues++
                }
            } catch { }

            # Check for minidump files
            $miniDumpPath = "$env:SystemRoot\Minidump"
            if (Test-Path -LiteralPath $miniDumpPath) {
                try {
                    $dumps = @(Get-ChildItem -LiteralPath $miniDumpPath -Filter "*.dmp" -ErrorAction SilentlyContinue)
                    foreach ($d in $dumps) {
                        $dumpFiles += @{ Name = $d.Name; SizeKB = [math]::Round($d.Length / 1KB, 1); Created = $d.CreationTime.ToString("yyyy-MM-ddTHH:mm:ss") }
                    }
                } catch { }
            }

            # Full memory dump
            $fullDump = "$env:SystemRoot\MEMORY.DMP"
            $fullDumpExists = Test-Path -LiteralPath $fullDump

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  CRASH AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (@($crashes).Count -eq 0) {
                Write-OutputColor "  │$("  (No crash events or unexpected shutdowns found)".PadRight(72))│" -color "Success"
            } else {
                Write-OutputColor "  │$("  CRASH EVENTS ($(@($crashes).Count))".PadRight(72))│" -color "Error"
                foreach ($c in ($crashes | Select-Object -First 10)) {
                    $line = "  $($c.TimeCreated)  Event $($c.EventId)"
                    Write-OutputColor "  │$($line.PadRight(72))│" -color "Warning"
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Minidumps: $(@($dumpFiles).Count)   Full dump: $(if ($fullDumpExists) { 'Present' } else { 'None' })".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Issues: $crashIssues".PadRight(72))│" -color $(if ($crashIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'CrashAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ CrashEvents = @($crashes).Count; Minidumps = @($dumpFiles).Count; FullDumpPresent = $fullDumpExists; Issues = $crashIssues }
                    CrashEvents = $crashes; DumpFiles = $dumpFiles
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($crashIssues -gt 0) { [Environment]::Exit(1) }
        }
        'LocalGroupAudit' {
            Write-OutputColor "  Auditing local groups..." -color "Info"
            Write-OutputColor "" -color "Info"

            $groupIssues = 0
            $groupResults = @()

            try {
                $groups = @(Get-LocalGroup -ErrorAction Stop)
                foreach ($g in $groups) {
                    $members = @()
                    try {
                        $grpMembers = @(Get-LocalGroupMember -Group $g.Name -ErrorAction Stop)
                        foreach ($m in $grpMembers) {
                            $members += @{ Name = "$($m.Name)"; ObjectClass = "$($m.ObjectClass)"; PrincipalSource = "$($m.PrincipalSource)" }
                        }
                    } catch { }

                    $groupResults += @{
                        Name        = $g.Name
                        Description = "$($g.Description)"
                        MemberCount = @($members).Count
                        Members     = $members
                    }
                }
            } catch {
                Write-OutputColor "  ERROR: Failed to query groups: $($_.Exception.Message)" -color "Error"
                [Environment]::Exit(1)
            }

            $adminGroup = $groupResults | Where-Object { $_.Name -eq 'Administrators' } | Select-Object -First 1
            $adminCount = if ($null -ne $adminGroup) { $adminGroup.MemberCount } else { 0 }
            if ($adminCount -gt 5) { $groupIssues++ }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  LOCAL GROUP AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($g in ($groupResults | Sort-Object MemberCount -Descending)) {
                $gName = if ($g.Name.Length -gt 30) { $g.Name.Substring(0, 27) + "..." } else { $g.Name }
                $color = if ($g.Name -eq 'Administrators' -and $g.MemberCount -gt 5) { "Warning" } else { "Info" }
                Write-OutputColor "  │$("  $($gName.PadRight(32)) Members: $($g.MemberCount)".PadRight(72))│" -color $color
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Groups: $(@($groupResults).Count)   Admin members: $adminCount   Issues: $groupIssues".PadRight(72))│" -color $(if ($groupIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'LocalGroupAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ TotalGroups = @($groupResults).Count; AdminMembers = $adminCount; Issues = $groupIssues }
                    Groups = $groupResults
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($groupIssues -gt 0) { [Environment]::Exit(1) }
        }
        'WMIAudit' {
            Write-OutputColor "  Auditing WMI repository..." -color "Info"
            Write-OutputColor "" -color "Info"

            $wmiIssues = 0
            $wmiHealth = 'OK'
            $repoSizeMB = 0
            $providerResults = @()

            # WMI repository verification
            try {
                $verifyOutput = & winmgmt /verifyrepository 2>&1
                $verifyStr = $verifyOutput -join " "
                if ($verifyStr -notmatch 'consistent') { $wmiHealth = 'FAIL'; $wmiIssues++ }
            } catch {
                $wmiHealth = 'Unknown'
            }

            # Repository size
            $repoPath = "$env:SystemRoot\System32\wbem\Repository"
            if (Test-Path -LiteralPath $repoPath) {
                try {
                    $repoSize = (Get-ChildItem -LiteralPath $repoPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                    $repoSizeMB = [math]::Round($repoSize / 1MB, 1)
                    if ($repoSizeMB -gt 500) { $wmiIssues++ }
                } catch { }
            }

            # Key WMI providers
            $testClasses = @(
                @{ Class = 'Win32_OperatingSystem'; Name = 'OS Info' }
                @{ Class = 'Win32_ComputerSystem'; Name = 'System Info' }
                @{ Class = 'Win32_Processor'; Name = 'CPU Info' }
                @{ Class = 'Win32_LogicalDisk'; Name = 'Disk Info' }
                @{ Class = 'Win32_NetworkAdapter'; Name = 'Network' }
                @{ Class = 'Win32_Service'; Name = 'Services' }
            )

            foreach ($tc in $testClasses) {
                $queryOk = $false
                $queryTime = 0
                try {
                    $sw = [System.Diagnostics.Stopwatch]::StartNew()
                    $null = Get-CimInstance -ClassName $tc.Class -ErrorAction Stop | Select-Object -First 1
                    $sw.Stop()
                    $queryOk = $true
                    $queryTime = $sw.ElapsedMilliseconds
                } catch {
                    $wmiIssues++
                }
                $providerResults += @{ Name = $tc.Name; Class = $tc.Class; Available = $queryOk; QueryMs = $queryTime }
            }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  WMI AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $healthColor = if ($wmiHealth -eq 'OK') { 'Success' } else { 'Error' }
            Write-OutputColor "  │$("  Repository:     $wmiHealth".PadRight(72))│" -color $healthColor
            Write-OutputColor "  │$("  Repo Size:      ${repoSizeMB}MB".PadRight(72))│" -color $(if ($repoSizeMB -gt 500) { "Warning" } else { "Info" })
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  PROVIDER TESTS".PadRight(72))│" -color "Info"
            foreach ($p in $providerResults) {
                $pStatus = if ($p.Available) { "OK (${$p.QueryMs}ms)" } else { "FAIL" }
                $pColor = if ($p.Available) { 'Success' } else { 'Error' }
                Write-OutputColor "  │$("  $($p.Name.PadRight(20)) $pStatus".PadRight(72))│" -color $pColor
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Issues: $wmiIssues".PadRight(72))│" -color $(if ($wmiIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'WMIAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ RepositoryHealth = $wmiHealth; RepoSizeMB = $repoSizeMB; ProvidersOK = @($providerResults | Where-Object { $_.Available }).Count; ProvidersFailed = @($providerResults | Where-Object { -not $_.Available }).Count; Issues = $wmiIssues }
                    Providers = $providerResults
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($wmiIssues -gt 0) { [Environment]::Exit(1) }
        }
        'TempAudit' {
            Write-OutputColor "  Auditing temporary files..." -color "Info"
            Write-OutputColor "" -color "Info"

            $tempIssues = 0
            $categories = @()

            $tempPaths = @(
                @{ Name = 'Windows Temp';     Path = "$env:SystemRoot\Temp" }
                @{ Name = 'User Temp';        Path = $env:TEMP }
                @{ Name = 'WU Download';      Path = "$env:SystemRoot\SoftwareDistribution\Download" }
                @{ Name = 'WU DataStore';     Path = "$env:SystemRoot\SoftwareDistribution\DataStore\Logs" }
                @{ Name = 'Prefetch';         Path = "$env:SystemRoot\Prefetch" }
                @{ Name = 'CBS Logs';         Path = "$env:SystemRoot\Logs\CBS" }
                @{ Name = 'DISM Logs';        Path = "$env:SystemRoot\Logs\DISM" }
                @{ Name = 'IIS Logs';         Path = "$env:SystemDrive\inetpub\logs\LogFiles" }
                @{ Name = 'Crash Dumps';      Path = "$env:SystemRoot\Minidump" }
                @{ Name = 'Error Reports';    Path = "$env:ProgramData\Microsoft\Windows\WER\ReportQueue" }
            )

            $totalReclaimMB = 0
            foreach ($tp in $tempPaths) {
                $sizeMB = 0
                $fileCount = 0
                $exists = Test-Path -LiteralPath $tp.Path -ErrorAction SilentlyContinue
                if ($exists) {
                    try {
                        $items = Get-ChildItem -LiteralPath $tp.Path -Recurse -Force -ErrorAction SilentlyContinue
                        $fileCount = @($items | Where-Object { -not $_.PSIsContainer }).Count
                        $sizeMB = [math]::Round(($items | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1MB, 1)
                    } catch { }
                }
                $totalReclaimMB += $sizeMB
                $categories += @{ Name = $tp.Name; Path = $tp.Path; Exists = $exists; SizeMB = $sizeMB; Files = $fileCount }
            }

            $totalReclaimGB = [math]::Round($totalReclaimMB / 1024, 2)
            if ($totalReclaimGB -gt 5) { $tempIssues++ }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  TEMP AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($c in ($categories | Where-Object { $_.Exists -and $_.SizeMB -gt 0 } | Sort-Object SizeMB -Descending)) {
                $line = "  $($c.Name.PadRight(20)) $("$($c.SizeMB)MB".PadRight(12)) $($c.Files) files"
                if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                $color = if ($c.SizeMB -gt 1024) { "Warning" } else { "Info" }
                Write-OutputColor "  │$($line.PadRight(72))│" -color $color
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Reclaimable: ${totalReclaimGB}GB   Issues: $tempIssues".PadRight(72))│" -color $(if ($tempIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'TempAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ ReclaimableGB = $totalReclaimGB; Categories = @($categories | Where-Object { $_.Exists }).Count; Issues = $tempIssues }
                    Categories = $categories
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($tempIssues -gt 0) { [Environment]::Exit(1) }
        }
        'UpdatePolicyAudit' {
            Write-OutputColor "  Auditing Windows Update policy..." -color "Info"
            Write-OutputColor "" -color "Info"

            $upIssues = 0

            # Auto Update settings
            $auPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
            $wuPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
            $autoUpdate = 'Not configured (OS defaults)'
            $wsusServer = ''
            $deferDays = 0
            $noAutoReboot = $false

            try {
                if (Test-Path $auPath) {
                    $auReg = Get-ItemProperty -Path $auPath -ErrorAction SilentlyContinue
                    if ($null -ne $auReg) {
                        $auOption = if ($null -ne $auReg.AUOptions) { $auReg.AUOptions } else { 0 }
                        $autoUpdate = switch ($auOption) {
                            2 { 'Notify before download' }
                            3 { 'Auto download, notify install' }
                            4 { 'Auto download and install' }
                            5 { 'Allow local admin to choose' }
                            default { "Not configured ($auOption)" }
                        }
                        if ($null -ne $auReg.NoAutoRebootWithLoggedOnUsers) { $noAutoReboot = $auReg.NoAutoRebootWithLoggedOnUsers -eq 1 }
                    }
                }
                if (Test-Path $wuPath) {
                    $wuReg = Get-ItemProperty -Path $wuPath -ErrorAction SilentlyContinue
                    if ($null -ne $wuReg) {
                        if ($null -ne $wuReg.WUServer) { $wsusServer = $wuReg.WUServer }
                        if ($null -ne $wuReg.DeferFeatureUpdatesPeriodInDays) { $deferDays = $wuReg.DeferFeatureUpdatesPeriodInDays }
                    }
                }
            } catch { }

            # Windows Update service
            $wuService = $null
            $wuRunning = $false
            try {
                $wuService = Get-Service -Name wuauserv -ErrorAction Stop
                $wuRunning = $wuService.Status -eq 'Running'
            } catch { }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  UPDATE POLICY AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $svcColor = if ($wuRunning) { "Success" } else { "Warning" }
            Write-OutputColor "  │$("  WU Service:       $(if ($wuRunning) { 'Running' } else { 'Stopped' })".PadRight(72))│" -color $svcColor
            Write-OutputColor "  │$("  Auto Update:      $autoUpdate".PadRight(72))│" -color "Info"
            if ($wsusServer) { Write-OutputColor "  │$("  WSUS Server:      $wsusServer".PadRight(72))│" -color "Info" }
            if ($deferDays -gt 0) { Write-OutputColor "  │$("  Feature Deferral: $deferDays days".PadRight(72))│" -color "Info" }
            Write-OutputColor "  │$("  No Auto Reboot:   $noAutoReboot".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Issues: $upIssues".PadRight(72))│" -color $(if ($upIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'UpdatePolicyAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ WUServiceRunning = $wuRunning; AutoUpdatePolicy = $autoUpdate; WSUSServer = $wsusServer; FeatureDeferralDays = $deferDays; NoAutoReboot = $noAutoReboot; Issues = $upIssues }
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($upIssues -gt 0) { [Environment]::Exit(1) }
        }
        'IISAudit' {
            Write-OutputColor "  Auditing IIS configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $iisIssues = 0
            $sites = @()
            $appPools = @()
            $iisInstalled = $false

            try {
                Import-Module WebAdministration -ErrorAction Stop
                $iisInstalled = $true

                # Sites
                $iisSites = @(Get-Website -ErrorAction Stop)
                foreach ($s in $iisSites) {
                    $bindings = @($s.Bindings.Collection | ForEach-Object { "$($_.protocol)/$($_.bindingInformation)" })
                    $health = 'OK'
                    if ($s.State -ne 'Started') { $health = 'WARN'; $iisIssues++ }
                    $sites += @{
                        Name     = $s.Name
                        State    = "$($s.State)"
                        PhysPath = $s.PhysicalPath
                        Bindings = $bindings
                        AppPool  = $s.ApplicationPool
                        Health   = $health
                    }
                }

                # App Pools
                $iisAppPools = @(Get-ChildItem IIS:\AppPools -ErrorAction Stop)
                foreach ($ap in $iisAppPools) {
                    $health = 'OK'
                    if ($ap.State -ne 'Started') { $health = 'WARN'; $iisIssues++ }
                    $appPools += @{
                        Name           = $ap.Name
                        State          = "$($ap.State)"
                        ManagedRuntime = "$($ap.ManagedRuntimeVersion)"
                        PipelineMode   = "$($ap.ManagedPipelineMode)"
                        Health         = $health
                    }
                }
            } catch {
                $iisInstalled = $false
            }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  IIS AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (-not $iisInstalled) {
                Write-OutputColor "  │$("  IIS is not installed on this system".PadRight(72))│" -color "Info"
            } else {
                if (@($sites).Count -gt 0) {
                    Write-OutputColor "  │$("  SITES ($(@($sites).Count))".PadRight(72))│" -color "Info"
                    foreach ($s in $sites) {
                        $sName = if ($s.Name.Length -gt 30) { $s.Name.Substring(0, 27) + "..." } else { $s.Name }
                        $line = "  $($sName.PadRight(32)) $($s.State)  [$($s.Health)]"
                        $color = if ($s.Health -eq 'OK') { 'Success' } else { 'Warning' }
                        Write-OutputColor "  │$($line.PadRight(72))│" -color $color
                    }
                }
                if (@($appPools).Count -gt 0) {
                    Write-OutputColor "  │$("  APP POOLS ($(@($appPools).Count))".PadRight(72))│" -color "Info"
                    foreach ($ap in $appPools) {
                        $apName = if ($ap.Name.Length -gt 30) { $ap.Name.Substring(0, 27) + "..." } else { $ap.Name }
                        $line = "  $($apName.PadRight(32)) $($ap.State)  $($ap.ManagedRuntime)  [$($ap.Health)]"
                        $color = if ($ap.Health -eq 'OK') { 'Success' } else { 'Warning' }
                        Write-OutputColor "  │$($line.PadRight(72))│" -color $color
                    }
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Sites: $(@($sites).Count)   App Pools: $(@($appPools).Count)   Issues: $iisIssues".PadRight(72))│" -color $(if ($iisIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'IISAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ IISInstalled = $iisInstalled; Sites = @($sites).Count; AppPools = @($appPools).Count; Issues = $iisIssues }
                    Sites = $sites; AppPools = $appPools
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($iisIssues -gt 0) { [Environment]::Exit(1) }
        }
        'SSHAudit' {
            Write-OutputColor "  Auditing OpenSSH configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $sshIssues = 0
            $sshInstalled = $false
            $sshRunning = $false
            $sshConfig = @{}

            # Check if OpenSSH Server is installed
            try {
                $sshSvc = Get-Service -Name sshd -ErrorAction Stop
                $sshInstalled = $true
                $sshRunning = $sshSvc.Status -eq 'Running'
                if (-not $sshRunning) { $sshIssues++ }
                $sshConfig['StartType'] = "$($sshSvc.StartType)"
            } catch {
                $sshInstalled = $false
            }

            # SSH config file
            $configPath = "$env:ProgramData\ssh\sshd_config"
            $configExists = Test-Path -LiteralPath $configPath
            $configSettings = @()
            if ($configExists) {
                try {
                    $configLines = Get-Content -LiteralPath $configPath -ErrorAction Stop | Where-Object { $_ -match '^\s*\w' -and $_ -notmatch '^\s*#' }
                    foreach ($line in $configLines) {
                        if ($line -match '^\s*(\S+)\s+(.+)$') {
                            $regexMatches = $Matches
                            $configSettings += @{ Setting = $regexMatches[1]; Value = $regexMatches[2].Trim() }
                        }
                    }

                    # Security checks
                    $rootLogin = $configSettings | Where-Object { $_.Setting -eq 'PermitRootLogin' } | Select-Object -First 1
                    if ($null -ne $rootLogin -and $rootLogin.Value -eq 'yes') { $sshIssues++ }
                    $pwdAuth = $configSettings | Where-Object { $_.Setting -eq 'PasswordAuthentication' } | Select-Object -First 1
                    $pubkeyAuth = $configSettings | Where-Object { $_.Setting -eq 'PubkeyAuthentication' } | Select-Object -First 1
                } catch { }
            }

            # Authorized keys
            $authKeysCount = 0
            $adminAuthKeys = "$env:ProgramData\ssh\administrators_authorized_keys"
            if (Test-Path -LiteralPath $adminAuthKeys) {
                try {
                    $authKeysCount = @(Get-Content -LiteralPath $adminAuthKeys -ErrorAction Stop | Where-Object { $_ -match '\S' }).Count
                } catch { }
            }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  SSH AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (-not $sshInstalled) {
                Write-OutputColor "  │$("  OpenSSH Server: Not installed".PadRight(72))│" -color "Info"
            } else {
                $svcColor = if ($sshRunning) { "Success" } else { "Warning" }
                Write-OutputColor "  │$("  Service:         $(if ($sshRunning) { 'Running' } else { 'Stopped' }) ($($sshConfig['StartType']))".PadRight(72))│" -color $svcColor
                Write-OutputColor "  │$("  Config File:     $(if ($configExists) { 'Present' } else { 'Missing' })".PadRight(72))│" -color "Info"
                Write-OutputColor "  │$("  Config Settings:  $(@($configSettings).Count) active".PadRight(72))│" -color "Info"
                Write-OutputColor "  │$("  Admin Auth Keys: $authKeysCount".PadRight(72))│" -color "Info"
                if (@($configSettings).Count -gt 0) {
                    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                    foreach ($cs in ($configSettings | Select-Object -First 15)) {
                        $line = "  $($cs.Setting.PadRight(28)) $($cs.Value)"
                        if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                        Write-OutputColor "  │$($line.PadRight(72))│" -color "Info"
                    }
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Issues: $sshIssues".PadRight(72))│" -color $(if ($sshIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'SSHAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ SSHInstalled = $sshInstalled; SSHRunning = $sshRunning; ConfigExists = $configExists; ConfigSettings = @($configSettings).Count; AuthorizedKeys = $authKeysCount; Issues = $sshIssues }
                    Config = $configSettings
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($sshIssues -gt 0) { [Environment]::Exit(1) }
        }
        'BitLockerAudit' {
            Write-OutputColor "  Auditing BitLocker encryption..." -color "Info"
            Write-OutputColor "" -color "Info"

            $blIssues = 0
            $volumes = @()

            try {
                $blVolumes = @(Get-BitLockerVolume -ErrorAction Stop)
                foreach ($v in $blVolumes) {
                    $health = 'OK'
                    if ("$($v.ProtectionStatus)" -ne 'On' -and $v.MountPoint -eq "$env:SystemDrive\") {
                        $health = 'WARN'; $blIssues++
                    }
                    $keyProtectors = @($v.KeyProtector | ForEach-Object { "$($_.KeyProtectorType)" })
                    $hasRecoveryPwd = @($v.KeyProtector | Where-Object { "$($_.KeyProtectorType)" -eq 'RecoveryPassword' }).Count -gt 0

                    $volumes += @{
                        MountPoint       = "$($v.MountPoint)"
                        VolumeType       = "$($v.VolumeType)"
                        ProtectionStatus = "$($v.ProtectionStatus)"
                        EncryptionMethod = "$($v.EncryptionMethod)"
                        EncryptionPct    = $v.EncryptionPercentage
                        LockStatus       = "$($v.LockStatus)"
                        KeyProtectors    = $keyProtectors
                        HasRecoveryKey   = $hasRecoveryPwd
                        Health           = $health
                    }
                }
            } catch {
                Write-OutputColor "  BitLocker not available: $($_.Exception.Message)" -color "Info"
            }

            $encrypted = @($volumes | Where-Object { $_.ProtectionStatus -eq 'On' }).Count

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  BITLOCKER AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (@($volumes).Count -eq 0) {
                Write-OutputColor "  │$("  (BitLocker not configured or not available)".PadRight(72))│" -color "Info"
            } else {
                foreach ($v in $volumes) {
                    $line = "  $($v.MountPoint.PadRight(8)) $("$($v.ProtectionStatus)".PadRight(8)) $($v.EncryptionMethod)  $($v.EncryptionPct)%  [$($v.Health)]"
                    if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                    $color = switch ($v.Health) { 'OK' { 'Success' } 'WARN' { 'Warning' } default { 'Info' } }
                    Write-OutputColor "  │$($line.PadRight(72))│" -color $color
                    $recStr = if ($v.HasRecoveryKey) { "Recovery key: Yes" } else { "Recovery key: No" }
                    Write-OutputColor "  │$("    $recStr  Protectors: $($v.KeyProtectors -join ', ')".PadRight(72))│" -color "Info"
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Volumes: $(@($volumes).Count)   Encrypted: $encrypted   Issues: $blIssues".PadRight(72))│" -color $(if ($blIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'BitLockerAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ Volumes = @($volumes).Count; Encrypted = $encrypted; Issues = $blIssues }
                    Volumes = $volumes
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($blIssues -gt 0) { [Environment]::Exit(1) }
        }
        'PrintAudit' {
            Write-OutputColor "  Auditing print configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $printIssues = 0
            $printers = @()

            try {
                $installedPrinters = @(Get-Printer -ErrorAction Stop)
                foreach ($p in $installedPrinters) {
                    $health = 'OK'
                    $jobCount = 0
                    try {
                        $jobs = @(Get-PrintJob -PrinterName $p.Name -ErrorAction SilentlyContinue)
                        $jobCount = @($jobs).Count
                        if ($jobCount -gt 10) { $health = 'WARN'; $printIssues++ }
                    } catch { }

                    $printers += @{
                        Name       = $p.Name
                        DriverName = "$($p.DriverName)"
                        PortName   = "$($p.PortName)"
                        Shared     = $p.Shared
                        Type       = "$($p.Type)"
                        JobCount   = $jobCount
                        Health     = $health
                    }
                }
            } catch {
                Write-OutputColor "  Print services not available: $($_.Exception.Message)" -color "Info"
            }

            $shared = @($printers | Where-Object { $_.Shared }).Count

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  PRINT AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (@($printers).Count -eq 0) {
                Write-OutputColor "  │$("  (No printers installed)".PadRight(72))│" -color "Info"
            } else {
                foreach ($p in $printers) {
                    $pName = if ($p.Name.Length -gt 30) { $p.Name.Substring(0, 27) + "..." } else { $p.Name }
                    $sharedStr = if ($p.Shared) { "Shared" } else { "" }
                    $line = "  $($pName.PadRight(32)) Jobs:$($p.JobCount)  $sharedStr  [$($p.Health)]"
                    if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                    $color = if ($p.Health -eq 'OK') { 'Info' } else { 'Warning' }
                    Write-OutputColor "  │$($line.PadRight(72))│" -color $color
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Printers: $(@($printers).Count)   Shared: $shared   Issues: $printIssues".PadRight(72))│" -color $(if ($printIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'PrintAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ Printers = @($printers).Count; Shared = $shared; Issues = $printIssues }
                    Printers = $printers
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($printIssues -gt 0) { [Environment]::Exit(1) }
        }
        'CredGuardAudit' {
            Write-OutputColor "  Auditing credential protection..." -color "Info"
            Write-OutputColor "" -color "Info"

            $cgIssues = 0

            # Device Guard / VBS status
            $vbsRunning = $false
            $cgRunning = $false
            $hvciRunning = $false
            $securityServices = @()

            try {
                $dgInfo = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace 'root\Microsoft\Windows\DeviceGuard' -ErrorAction Stop
                $vbsRunning = $dgInfo.VirtualizationBasedSecurityStatus -eq 2
                if ($null -ne $dgInfo.SecurityServicesRunning) {
                    $svcIds = @($dgInfo.SecurityServicesRunning)
                    $cgRunning = $svcIds -contains 1
                    $hvciRunning = $svcIds -contains 2
                    foreach ($id in $svcIds) {
                        $svcName = switch ($id) { 1 { 'Credential Guard' } 2 { 'HVCI' } 3 { 'System Guard' } default { "Service $id" } }
                        $securityServices += $svcName
                    }
                }
            } catch { }

            # LSA protection
            $lsaPPL = $false
            try {
                $lsaReg = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -ErrorAction SilentlyContinue
                if ($null -ne $lsaReg -and $null -ne $lsaReg.RunAsPPL) { $lsaPPL = $lsaReg.RunAsPPL -eq 1 }
            } catch { }

            if (-not $cgRunning) { $cgIssues++ }
            if (-not $lsaPPL) { $cgIssues++ }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  CREDENTIAL GUARD AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $vbsColor = if ($vbsRunning) { "Success" } else { "Warning" }
            Write-OutputColor "  │$("  VBS:              $(if ($vbsRunning) { 'Running' } else { 'Not running' })".PadRight(72))│" -color $vbsColor
            $cgColor = if ($cgRunning) { "Success" } else { "Warning" }
            Write-OutputColor "  │$("  Credential Guard: $(if ($cgRunning) { 'Running' } else { 'Not running' })".PadRight(72))│" -color $cgColor
            $hvciColor = if ($hvciRunning) { "Success" } else { "Info" }
            Write-OutputColor "  │$("  HVCI:             $(if ($hvciRunning) { 'Running' } else { 'Not running' })".PadRight(72))│" -color $hvciColor
            $lsaColor = if ($lsaPPL) { "Success" } else { "Warning" }
            Write-OutputColor "  │$("  LSASS Protection: $(if ($lsaPPL) { 'Enabled (PPL)' } else { 'Not enabled' })".PadRight(72))│" -color $lsaColor
            if (@($securityServices).Count -gt 0) {
                Write-OutputColor "  │$("  Active Services:  $($securityServices -join ', ')".PadRight(72))│" -color "Success"
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Issues: $cgIssues".PadRight(72))│" -color $(if ($cgIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'CredGuardAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ VBSRunning = $vbsRunning; CredentialGuard = $cgRunning; HVCI = $hvciRunning; LSAProtection = $lsaPPL; SecurityServices = $securityServices; Issues = $cgIssues }
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($cgIssues -gt 0) { [Environment]::Exit(1) }
        }
        'PortAudit' {
            Write-OutputColor "  Testing outbound connectivity..." -color "Info"
            Write-OutputColor "" -color "Info"

            $portIssues = 0
            $portTests = @()

            $targets = @(
                @{ Host = 'dns.google';          Port = 443;  Name = 'Google DNS (HTTPS)' }
                @{ Host = '8.8.8.8';             Port = 53;   Name = 'Google DNS' }
                @{ Host = 'time.windows.com';    Port = 123;  Name = 'Windows NTP' }
                @{ Host = 'go.microsoft.com';    Port = 443;  Name = 'Microsoft Update' }
                @{ Host = 'login.microsoftonline.com'; Port = 443; Name = 'Azure AD' }
                @{ Host = 'github.com';          Port = 443;  Name = 'GitHub' }
            )

            foreach ($t in $targets) {
                $reachable = $false
                $latencyMs = 0
                try {
                    $sw = [System.Diagnostics.Stopwatch]::StartNew()
                    $tcp = [System.Net.Sockets.TcpClient]::new()
                    $connectTask = $tcp.ConnectAsync($t.Host, $t.Port)
                    $completed = $connectTask.Wait(3000)
                    $sw.Stop()
                    $latencyMs = $sw.ElapsedMilliseconds
                    if ($completed -and $tcp.Connected) { $reachable = $true }
                    $tcp.Dispose()
                } catch {
                    $reachable = $false
                }

                if (-not $reachable) { $portIssues++ }
                $portTests += @{
                    Name      = $t.Name
                    Host      = $t.Host
                    Port      = $t.Port
                    Reachable = $reachable
                    LatencyMs = $latencyMs
                    Status    = if ($reachable) { 'OK' } else { 'FAIL' }
                }
            }

            $passed = @($portTests | Where-Object { $_.Reachable }).Count

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  PORT AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($p in $portTests) {
                $latStr = if ($p.Reachable) { "$($p.LatencyMs)ms" } else { "timeout" }
                $line = "  $($p.Name.PadRight(25)) $($p.Host):$($p.Port)".PadRight(55) + " $latStr  [$($p.Status)]"
                if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                $color = if ($p.Reachable) { 'Success' } else { 'Error' }
                Write-OutputColor "  │$($line.PadRight(72))│" -color $color
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Passed: $passed/$(@($portTests).Count)   Issues: $portIssues".PadRight(72))│" -color $(if ($portIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'PortAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ Tested = @($portTests).Count; Passed = $passed; Failed = $portIssues; Issues = $portIssues }
                    Tests = $portTests
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($portIssues -gt 0) { [Environment]::Exit(1) }
        }
        'AntivirusAudit' {
            Write-OutputColor "  Auditing antivirus status..." -color "Info"
            Write-OutputColor "" -color "Info"

            $avIssues = 0
            $avProducts = @()
            $defenderStatus = @{}

            # Windows Defender status
            try {
                $mpStatus = Get-MpComputerStatus -ErrorAction Stop
                $defenderStatus = @{
                    AMRunning              = $mpStatus.AMServiceEnabled
                    RealTimeProtection     = $mpStatus.RealTimeProtectionEnabled
                    BehaviorMonitor        = $mpStatus.BehaviorMonitorEnabled
                    AntiSpyware            = $mpStatus.AntispywareEnabled
                    Antivirus              = $mpStatus.AntivirusEnabled
                    NISEnabled             = $mpStatus.NISEnabled
                    DefSignatureAge        = $mpStatus.AntivirusSignatureAge
                    DefLastUpdated         = if ($null -ne $mpStatus.AntivirusSignatureLastUpdated) { $mpStatus.AntivirusSignatureLastUpdated.ToString("yyyy-MM-ddTHH:mm:ss") } else { "Unknown" }
                    EngineVersion          = "$($mpStatus.AMEngineVersion)"
                    ProductVersion         = "$($mpStatus.AMProductVersion)"
                }
                if (-not $mpStatus.RealTimeProtectionEnabled) { $avIssues++ }
                if ($mpStatus.AntivirusSignatureAge -gt 7) { $avIssues++ }
            } catch {
                Write-OutputColor "  Windows Defender not available: $($_.Exception.Message)" -color "Info"
            }

            # Third-party AV (via WMI SecurityCenter2)
            try {
                $avWmi = @(Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop)
                foreach ($av in $avWmi) {
                    $avProducts += @{ Name = "$($av.displayName)"; State = $av.productState; Path = "$($av.pathToSignedProductExe)" }
                }
            } catch { }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  ANTIVIRUS AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if ($defenderStatus.Count -gt 0) {
                $rtpColor = if ($defenderStatus.RealTimeProtection) { "Success" } else { "Error" }
                Write-OutputColor "  │$("  Defender RTP:     $(if ($defenderStatus.RealTimeProtection) { 'Enabled' } else { 'DISABLED' })".PadRight(72))│" -color $rtpColor
                $sigColor = if ($defenderStatus.DefSignatureAge -le 7) { "Success" } else { "Warning" }
                Write-OutputColor "  │$("  Signature Age:    $($defenderStatus.DefSignatureAge) days".PadRight(72))│" -color $sigColor
                Write-OutputColor "  │$("  Engine:           $($defenderStatus.EngineVersion)".PadRight(72))│" -color "Info"
                Write-OutputColor "  │$("  Last Updated:     $($defenderStatus.DefLastUpdated)".PadRight(72))│" -color "Info"
            } else {
                Write-OutputColor "  │$("  Windows Defender: Not available".PadRight(72))│" -color "Warning"
            }
            if (@($avProducts).Count -gt 0) {
                Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                foreach ($av in $avProducts) {
                    Write-OutputColor "  │$("  $($av.Name)".PadRight(72))│" -color "Info"
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Issues: $avIssues".PadRight(72))│" -color $(if ($avIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'AntivirusAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ DefenderAvailable = ($defenderStatus.Count -gt 0); RealTimeProtection = $defenderStatus.RealTimeProtection; SignatureAgeDays = $defenderStatus.DefSignatureAge; ThirdPartyAV = @($avProducts).Count; Issues = $avIssues }
                    Defender = $defenderStatus; ThirdPartyProducts = $avProducts
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($avIssues -gt 0) { [Environment]::Exit(1) }
        }
        'DotNetAudit' {
            Write-OutputColor "  Auditing .NET installations..." -color "Info"
            Write-OutputColor "" -color "Info"

            $dnIssues = 0
            $frameworks = @()
            $runtimes = @()

            # .NET Framework versions
            $fwPath = 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP'
            if (Test-Path $fwPath) {
                try {
                    $fwKeys = @('v2.0.50727', 'v3.0', 'v3.5', 'v4\Full')
                    foreach ($key in $fwKeys) {
                        $regPath = Join-Path $fwPath $key
                        if (Test-Path $regPath) {
                            $reg = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                            if ($null -ne $reg) {
                                $version = if ($null -ne $reg.Version) { "$($reg.Version)" } else { $key }
                                $release = if ($null -ne $reg.Release) { $reg.Release } else { 0 }
                                $frameworks += @{ Key = $key; Version = $version; Release = $release; Installed = ($null -ne $reg.Install -and $reg.Install -eq 1) -or ($null -ne $reg.Version) }
                            }
                        }
                    }
                } catch { }
            }

            # .NET Runtime (Core/5+)
            try {
                $dotnetOutput = & dotnet --list-runtimes 2>&1
                if ($LASTEXITCODE -eq 0) {
                    foreach ($line in $dotnetOutput) {
                        if ($line -match '^(\S+)\s+(\S+)\s+\[(.+)\]') {
                            $regexMatches = $Matches
                            $runtimes += @{ Name = $regexMatches[1]; Version = $regexMatches[2]; Path = $regexMatches[3] }
                        }
                    }
                }
            } catch { }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  .NET AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (@($frameworks).Count -gt 0) {
                Write-OutputColor "  │$("  .NET FRAMEWORK".PadRight(72))│" -color "Info"
                foreach ($fw in $frameworks) {
                    $installed = if ($fw.Installed) { "Installed" } else { "Not found" }
                    Write-OutputColor "  │$("  $($fw.Key.PadRight(18)) $($fw.Version.PadRight(18)) $installed".PadRight(72))│" -color $(if ($fw.Installed) { "Success" } else { "Info" })
                }
            }
            if (@($runtimes).Count -gt 0) {
                Write-OutputColor "  │$("  .NET RUNTIMES".PadRight(72))│" -color "Info"
                foreach ($rt in $runtimes) {
                    $line = "  $($rt.Name.PadRight(30)) $($rt.Version)"
                    if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                    Write-OutputColor "  │$($line.PadRight(72))│" -color "Success"
                }
            }
            if (@($frameworks).Count -eq 0 -and @($runtimes).Count -eq 0) {
                Write-OutputColor "  │$("  (No .NET installations detected)".PadRight(72))│" -color "Warning"
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Frameworks: $(@($frameworks | Where-Object { $_.Installed }).Count)   Runtimes: $(@($runtimes).Count)".PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'DotNetAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ Frameworks = @($frameworks | Where-Object { $_.Installed }).Count; Runtimes = @($runtimes).Count; Issues = $dnIssues }
                    Frameworks = $frameworks; Runtimes = $runtimes
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($dnIssues -gt 0) { [Environment]::Exit(1) }
        }
        'RDPAudit' {
            Write-OutputColor "  Auditing RDP configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $rdpIssues = 0

            # RDP enabled
            $rdpEnabled = $false
            $nlaRequired = $false
            $rdpPort = 3389
            try {
                $rdpReg = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -ErrorAction SilentlyContinue
                $rdpEnabled = $null -ne $rdpReg -and $rdpReg.fDenyTSConnections -eq 0
                $rdpTcpReg = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -ErrorAction SilentlyContinue
                if ($null -ne $rdpTcpReg) {
                    $nlaRequired = $rdpTcpReg.UserAuthentication -eq 1
                    if ($null -ne $rdpTcpReg.PortNumber) { $rdpPort = $rdpTcpReg.PortNumber }
                }
                if ($rdpEnabled -and -not $nlaRequired) { $rdpIssues++ }
            } catch { }

            # Active RDP sessions
            $sessions = @()
            try {
                $qwinstaOutput = & qwinsta 2>&1
                foreach ($line in $qwinstaOutput) {
                    if ($line -match '^\s*(rdp-tcp#\d+|console)\s+(\S+)\s+(\d+)\s+(Active|Disc)') {
                        $regexMatches = $Matches
                        $sessions += @{ Session = $regexMatches[1]; User = $regexMatches[2]; ID = $regexMatches[3]; State = $regexMatches[4] }
                    }
                }
            } catch { }

            $activeSessions = @($sessions | Where-Object { $_.State -eq 'Active' }).Count
            $discSessions = @($sessions | Where-Object { $_.State -eq 'Disc' }).Count

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  RDP AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  RDP Enabled:      $(if ($rdpEnabled) { 'Yes' } else { 'No' })".PadRight(72))│" -color $(if ($rdpEnabled) { "Success" } else { "Info" })
            $nlaColor = if ($nlaRequired) { "Success" } else { "Warning" }
            Write-OutputColor "  │$("  NLA Required:     $(if ($nlaRequired) { 'Yes' } else { 'No' })".PadRight(72))│" -color $nlaColor
            Write-OutputColor "  │$("  RDP Port:         $rdpPort".PadRight(72))│" -color $(if ($rdpPort -ne 3389) { "Info" } else { "Info" })
            Write-OutputColor "  │$("  Active Sessions:  $activeSessions".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Disconnected:     $discSessions".PadRight(72))│" -color $(if ($discSessions -gt 0) { "Warning" } else { "Info" })
            if (@($sessions).Count -gt 0) {
                Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                foreach ($s in $sessions) {
                    Write-OutputColor "  │$("  $($s.User.PadRight(25)) $($s.Session.PadRight(18)) $($s.State)".PadRight(72))│" -color "Info"
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Issues: $rdpIssues".PadRight(72))│" -color $(if ($rdpIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'RDPAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ RDPEnabled = $rdpEnabled; NLARequired = $nlaRequired; Port = $rdpPort; ActiveSessions = $activeSessions; DisconnectedSessions = $discSessions; Issues = $rdpIssues }
                    Sessions = $sessions
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($rdpIssues -gt 0) { [Environment]::Exit(1) }
        }
        'VPNAudit' {
            Write-OutputColor "  Auditing VPN connections..." -color "Info"
            Write-OutputColor "" -color "Info"

            $vpnIssues = 0
            $vpnConnections = @()
            $rasConnections = @()

            # VPN client connections
            try {
                $vpns = @(Get-VpnConnection -ErrorAction Stop)
                foreach ($v in $vpns) {
                    $vpnConnections += @{
                        Name             = $v.Name
                        ServerAddress    = "$($v.ServerAddress)"
                        TunnelType       = "$($v.TunnelType)"
                        AuthMethod       = "$($v.AuthenticationMethod)"
                        ConnectionStatus = "$($v.ConnectionStatus)"
                        SplitTunneling   = $v.SplitTunneling
                    }
                }
            } catch { }

            # Active RAS connections
            try {
                $rasConns = @(Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue)
                foreach ($r in $rasConns) {
                    if ($r.Name -notin ($vpnConnections | ForEach-Object { $_.Name })) {
                        $vpnConnections += @{
                            Name             = $r.Name
                            ServerAddress    = "$($r.ServerAddress)"
                            TunnelType       = "$($r.TunnelType)"
                            AuthMethod       = "$($r.AuthenticationMethod)"
                            ConnectionStatus = "$($r.ConnectionStatus)"
                            SplitTunneling   = $r.SplitTunneling
                        }
                    }
                }
            } catch { }

            # RRAS (server-side)
            $rrasInstalled = $false
            try {
                $rrasSvc = Get-Service -Name RemoteAccess -ErrorAction SilentlyContinue
                if ($null -ne $rrasSvc) { $rrasInstalled = $true }
            } catch { }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  VPN AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (@($vpnConnections).Count -eq 0) {
                Write-OutputColor "  │$("  (No VPN connections configured)".PadRight(72))│" -color "Info"
            } else {
                foreach ($v in $vpnConnections) {
                    $vName = if ($v.Name.Length -gt 22) { $v.Name.Substring(0, 19) + "..." } else { $v.Name }
                    $line = "  $($vName.PadRight(24)) $($v.TunnelType.PadRight(12)) $($v.ConnectionStatus)"
                    if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                    $color = if ($v.ConnectionStatus -eq 'Connected') { "Success" } else { "Info" }
                    Write-OutputColor "  │$($line.PadRight(72))│" -color $color
                }
            }
            Write-OutputColor "  │$("  RRAS Service: $(if ($rrasInstalled) { 'Installed' } else { 'Not installed' })".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  VPN Connections: $(@($vpnConnections).Count)   Issues: $vpnIssues".PadRight(72))│" -color $(if ($vpnIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'VPNAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ VPNConnections = @($vpnConnections).Count; RRASInstalled = $rrasInstalled; Issues = $vpnIssues }
                    Connections = $vpnConnections
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($vpnIssues -gt 0) { [Environment]::Exit(1) }
        }
        'HostsFileAudit' {
            Write-OutputColor "  Auditing hosts file..." -color "Info"
            Write-OutputColor "" -color "Info"

            $hostsIssues = 0
            $hostsEntries = @()
            $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"

            if (Test-Path -LiteralPath $hostsPath) {
                try {
                    $lines = Get-Content -LiteralPath $hostsPath -ErrorAction Stop
                    foreach ($line in $lines) {
                        $trimmed = $line.Trim()
                        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
                        if ($trimmed -match '^(\S+)\s+(.+)$') {
                            $regexMatches = $Matches; $ip = $regexMatches[1]; $hostnames = $regexMatches[2].Trim()
                            $suspicious = $false
                            # Flag redirects of known domains (potential hijacking)
                            if ($hostnames -match 'microsoft\.com|windows\.com|google\.com|windowsupdate|login\.live' -and $ip -ne '127.0.0.1' -and $ip -ne '::1') {
                                $suspicious = $true; $hostsIssues++
                            }
                            $hostsEntries += @{ IP = $ip; Hostnames = $hostnames; Suspicious = $suspicious }
                        }
                    }
                } catch { }
            }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  HOSTS FILE AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (@($hostsEntries).Count -eq 0) {
                Write-OutputColor "  │$("  (No custom hosts entries)".PadRight(72))│" -color "Success"
            } else {
                foreach ($h in $hostsEntries) {
                    $line = "  $($h.IP.PadRight(18)) $($h.Hostnames)"
                    if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                    $color = if ($h.Suspicious) { "Error" } else { "Info" }
                    $suffix = if ($h.Suspicious) { " [SUSPICIOUS]" } else { "" }
                    Write-OutputColor "  │$(($line + $suffix).PadRight(72))│" -color $color
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Entries: $(@($hostsEntries).Count)   Suspicious: $hostsIssues".PadRight(72))│" -color $(if ($hostsIssues -gt 0) { "Error" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'HostsFileAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ Entries = @($hostsEntries).Count; Suspicious = $hostsIssues; Issues = $hostsIssues }
                    HostsEntries = $hostsEntries
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($hostsIssues -gt 0) { [Environment]::Exit(1) }
        }
        'NetStatAudit' {
            Write-OutputColor "  Auditing TCP connections..." -color "Info"
            Write-OutputColor "" -color "Info"

            $nsIssues = 0
            $connections = @()

            try {
                $tcpConns = @(Get-NetTCPConnection -State Established -ErrorAction Stop)
                foreach ($c in $tcpConns) {
                    $processName = ""
                    try { $processName = (Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue).Name } catch { }
                    $connections += @{
                        LocalAddress  = "$($c.LocalAddress)"
                        LocalPort     = $c.LocalPort
                        RemoteAddress = "$($c.RemoteAddress)"
                        RemotePort    = $c.RemotePort
                        ProcessName   = $processName
                        PID           = $c.OwningProcess
                    }
                }
            } catch {
                Write-OutputColor "  WARNING: Could not query connections: $($_.Exception.Message)" -color "Warning"
            }

            $uniqueRemote = @($connections | ForEach-Object { $_.RemoteAddress } | Select-Object -Unique)
            $uniqueProcesses = @($connections | ForEach-Object { $_.ProcessName } | Where-Object { $_ -ne '' } | Select-Object -Unique)

            # Console output - top connections by process
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  NETSTAT AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $byProcess = $connections | Group-Object ProcessName | Sort-Object Count -Descending | Select-Object -First 15
            foreach ($grp in $byProcess) {
                $pName = if ($grp.Name.Length -gt 25) { $grp.Name.Substring(0, 22) + "..." } elseif ($grp.Name -eq '') { "(unknown)" } else { $grp.Name }
                Write-OutputColor "  │$("  $($pName.PadRight(27)) $($grp.Count) connections".PadRight(72))│" -color "Info"
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Connections: $(@($connections).Count)   Remote IPs: $(@($uniqueRemote).Count)   Processes: $(@($uniqueProcesses).Count)".PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'NetStatAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ Connections = @($connections).Count; UniqueRemoteIPs = @($uniqueRemote).Count; UniqueProcesses = @($uniqueProcesses).Count; Issues = $nsIssues }
                    Connections = $connections
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($nsIssues -gt 0) { [Environment]::Exit(1) }
        }
        'LicenseAudit' {
            Write-OutputColor "  Auditing Windows licensing..." -color "Info"
            Write-OutputColor "" -color "Info"

            $licIssues = 0
            $licenseInfo = @{}

            try {
                $slmgr = & cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /dli 2>&1
                $slmgrStr = $slmgr -join "`n"
                if ($slmgrStr -match 'Name:\s*(.+)') { $regexMatches = $Matches; $licenseInfo['ProductName'] = $regexMatches[1].Trim() }
                if ($slmgrStr -match 'Description:\s*(.+)') { $regexMatches = $Matches; $licenseInfo['Description'] = $regexMatches[1].Trim() }
                if ($slmgrStr -match 'License Status:\s*(.+)') { $regexMatches = $Matches; $licenseInfo['LicenseStatus'] = $regexMatches[1].Trim() }
                if ($slmgrStr -match 'Product Key Channel:\s*(.+)') { $regexMatches = $Matches; $licenseInfo['KeyChannel'] = $regexMatches[1].Trim() }

                if ($licenseInfo.ContainsKey('LicenseStatus') -and $licenseInfo['LicenseStatus'] -ne 'Licensed') { $licIssues++ }
            } catch { }

            # Also check via CIM
            try {
                $slp = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND LicenseStatus=1" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($null -ne $slp) {
                    $licenseInfo['PartialProductKey'] = "$($slp.PartialProductKey)"
                    $licenseInfo['GracePeriodDays'] = [math]::Round($slp.GracePeriodRemaining / 1440, 0)
                }
            } catch { }

            $status = if ($licenseInfo.ContainsKey('LicenseStatus')) { $licenseInfo['LicenseStatus'] } else { 'Unknown' }

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  LICENSE AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $statusColor = if ($status -eq 'Licensed') { "Success" } else { "Warning" }
            if ($licenseInfo.ContainsKey('ProductName')) { Write-OutputColor "  │$("  Product:    $($licenseInfo['ProductName'])".PadRight(72))│" -color "Info" }
            Write-OutputColor "  │$("  Status:     $status".PadRight(72))│" -color $statusColor
            if ($licenseInfo.ContainsKey('KeyChannel')) { Write-OutputColor "  │$("  Channel:    $($licenseInfo['KeyChannel'])".PadRight(72))│" -color "Info" }
            if ($licenseInfo.ContainsKey('PartialProductKey')) { Write-OutputColor "  │$("  Key:        *****-$($licenseInfo['PartialProductKey'])".PadRight(72))│" -color "Info" }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Issues: $licIssues".PadRight(72))│" -color $(if ($licIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'LicenseAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ LicenseStatus = $status; Issues = $licIssues }
                    License = $licenseInfo
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($licIssues -gt 0) { [Environment]::Exit(1) }
        }
        'USBDeviceAudit' {
            Write-OutputColor "  Auditing USB devices..." -color "Info"
            Write-OutputColor "" -color "Info"

            $usbIssues = 0
            $usbDevices = @()

            try {
                $devices = @(Get-CimInstance -ClassName Win32_USBControllerDevice -ErrorAction Stop)
                $seen = @{}
                foreach ($d in $devices) {
                    $depPath = $d.Dependent
                    if ($depPath -match 'DeviceID="(.+)"') {
                        $regexMatches = $Matches; $devId = $regexMatches[1] -replace '\\\\', '\'
                        if ($seen.ContainsKey($devId)) { continue }
                        $seen[$devId] = $true
                        try {
                            $pnp = Get-CimInstance -ClassName Win32_PnPEntity -Filter "DeviceID='$($devId -replace "'", "''")'" -ErrorAction SilentlyContinue
                            if ($null -ne $pnp -and $pnp.Name -notmatch 'Root Hub|Host Controller|Generic Hub') {
                                $usbDevices += @{
                                    Name         = "$($pnp.Name)"
                                    DeviceID     = $devId
                                    Manufacturer = "$($pnp.Manufacturer)"
                                    Status       = "$($pnp.Status)"
                                    PNPClass     = "$($pnp.PNPClass)"
                                }
                            }
                        } catch { }
                    }
                }
            } catch { }

            # Check USB storage policy
            $usbStorageDisabled = $false
            try {
                $usbStor = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR' -ErrorAction SilentlyContinue
                if ($null -ne $usbStor -and $usbStor.Start -eq 4) { $usbStorageDisabled = $true }
            } catch { }

            $storageDevices = @($usbDevices | Where-Object { $_.PNPClass -eq 'DiskDrive' -or $_.PNPClass -eq 'USB' -and $_.Name -match 'Storage|Disk|Flash|Drive' })

            # Console output
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  USB DEVICE AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  USB Storage Policy: $(if ($usbStorageDisabled) { 'Blocked' } else { 'Allowed' })".PadRight(72))│" -color $(if ($usbStorageDisabled) { "Success" } else { "Info" })
            if (@($usbDevices).Count -eq 0) {
                Write-OutputColor "  │$("  (No USB devices connected)".PadRight(72))│" -color "Info"
            } else {
                Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                foreach ($u in $usbDevices) {
                    $uName = if ($u.Name.Length -gt 50) { $u.Name.Substring(0, 47) + "..." } else { $u.Name }
                    $line = "  $uName  [$($u.Status)]"
                    if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                    Write-OutputColor "  │$($line.PadRight(72))│" -color "Info"
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Devices: $(@($usbDevices).Count)   Storage blocked: $usbStorageDisabled   Issues: $usbIssues".PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'USBDeviceAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ Devices = @($usbDevices).Count; StorageBlocked = $usbStorageDisabled; Issues = $usbIssues }
                    Devices = $usbDevices
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($usbIssues -gt 0) { [Environment]::Exit(1) }
        }
        'AppLockerAudit' {
            Write-OutputColor "  Auditing AppLocker policies..." -color "Info"
            Write-OutputColor "" -color "Info"

            $alIssues = 0
            $alPolicies = @()
            $alConfigured = $false

            try {
                $alSvc = Get-Service -Name AppIDSvc -ErrorAction SilentlyContinue
                $alRunning = $null -ne $alSvc -and $alSvc.Status -eq 'Running'

                $ruleTypes = @('Exe', 'Msi', 'Script', 'Appx', 'Dll')
                foreach ($rt in $ruleTypes) {
                    try {
                        $rules = @(Get-AppLockerPolicy -Effective -ErrorAction Stop | Select-Object -ExpandProperty RuleCollections | Where-Object { $_.RuleCollectionType -eq $rt })
                        if (@($rules).Count -gt 0) { $alConfigured = $true }
                        $alPolicies += @{ Type = $rt; RuleCount = @($rules).Count; Enforcement = if (@($rules).Count -gt 0) { 'Configured' } else { 'Not configured' } }
                    } catch {
                        $alPolicies += @{ Type = $rt; RuleCount = 0; Enforcement = 'Not available' }
                    }
                }
            } catch {
                foreach ($rt in @('Exe', 'Msi', 'Script', 'Appx', 'Dll')) {
                    $alPolicies += @{ Type = $rt; RuleCount = 0; Enforcement = 'Not available' }
                }
            }

            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  APPLOCKER AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  AppIDSvc:   $(if ($alRunning) { 'Running' } else { 'Not running' })".PadRight(72))│" -color $(if ($alRunning) { "Success" } else { "Info" })
            Write-OutputColor "  │$("  Configured: $alConfigured".PadRight(72))│" -color $(if ($alConfigured) { "Success" } else { "Info" })
            foreach ($p in $alPolicies) {
                Write-OutputColor "  │$("  $($p.Type.PadRight(12)) Rules: $($p.RuleCount)  ($($p.Enforcement))".PadRight(72))│" -color $(if ($p.RuleCount -gt 0) { "Success" } else { "Info" })
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Issues: $alIssues".PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'AppLockerAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ AppIDSvcRunning = $alRunning; Configured = $alConfigured; Issues = $alIssues }
                    Policies = $alPolicies
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($alIssues -gt 0) { [Environment]::Exit(1) }
        }
        'EventSubAudit' {
            Write-OutputColor "  Auditing WMI event subscriptions..." -color "Info"
            Write-OutputColor "" -color "Info"

            $esIssues = 0
            $subscriptions = @()

            # WMI event consumers (persistence mechanism)
            $subTypes = @(
                @{ Class = 'CommandLineEventConsumer'; Name = 'CommandLine' }
                @{ Class = 'ActiveScriptEventConsumer'; Name = 'ActiveScript' }
                @{ Class = 'LogFileEventConsumer'; Name = 'LogFile' }
                @{ Class = 'NTEventLogEventConsumer'; Name = 'NTEventLog' }
                @{ Class = 'SMTPEventConsumer'; Name = 'SMTP' }
            )

            foreach ($st in $subTypes) {
                try {
                    $consumers = @(Get-CimInstance -Namespace 'root\subscription' -ClassName $st.Class -ErrorAction Stop)
                    foreach ($c in $consumers) {
                        $esIssues++
                        $subscriptions += @{
                            Type   = $st.Name
                            Name   = "$($c.Name)"
                            Detail = if ($st.Class -eq 'CommandLineEventConsumer') { "$($c.CommandLineTemplate)" } elseif ($st.Class -eq 'ActiveScriptEventConsumer') { "$($c.ScriptText)" } else { "$($c.Name)" }
                        }
                    }
                } catch { }
            }

            # Event filters
            $filters = @()
            try {
                $eventFilters = @(Get-CimInstance -Namespace 'root\subscription' -ClassName '__EventFilter' -ErrorAction Stop)
                foreach ($f in $eventFilters) {
                    $filters += @{ Name = "$($f.Name)"; Query = "$($f.Query)"; Language = "$($f.QueryLanguage)" }
                }
            } catch { }

            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  WMI EVENT SUBSCRIPTION AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (@($subscriptions).Count -eq 0 -and @($filters).Count -eq 0) {
                Write-OutputColor "  │$("  (No WMI event subscriptions found)".PadRight(72))│" -color "Success"
            } else {
                if (@($subscriptions).Count -gt 0) {
                    Write-OutputColor "  │$("  EVENT CONSUMERS ($(@($subscriptions).Count)) - REVIEW FOR PERSISTENCE".PadRight(72))│" -color "Warning"
                    foreach ($s in $subscriptions) {
                        $detail = if ($s.Detail.Length -gt 50) { $s.Detail.Substring(0, 47) + "..." } else { $s.Detail }
                        Write-OutputColor "  │$("  [$($s.Type)] $detail".PadRight(72))│" -color "Warning"
                    }
                }
                Write-OutputColor "  │$("  Event Filters: $(@($filters).Count)".PadRight(72))│" -color "Info"
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Consumers: $(@($subscriptions).Count)   Filters: $(@($filters).Count)   Issues: $esIssues".PadRight(72))│" -color $(if ($esIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'EventSubAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ Consumers = @($subscriptions).Count; Filters = @($filters).Count; Issues = $esIssues }
                    Consumers = $subscriptions; Filters = $filters
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($esIssues -gt 0) { [Environment]::Exit(1) }
        }
        'HotfixAudit' {
            Write-OutputColor "  Auditing installed hotfixes..." -color "Info"
            Write-OutputColor "" -color "Info"

            $hfIssues = 0
            $hotfixes = @()

            try {
                $hfs = @(Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending -ErrorAction SilentlyContinue)
                foreach ($hf in $hfs) {
                    $installedDate = if ($null -ne $hf.InstalledOn) { $hf.InstalledOn.ToString("yyyy-MM-dd") } else { "Unknown" }
                    $hotfixes += @{
                        HotFixID    = "$($hf.HotFixID)"
                        Description = "$($hf.Description)"
                        InstalledBy = "$($hf.InstalledBy)"
                        InstalledOn = $installedDate
                    }
                }
            } catch {
                Write-OutputColor "  WARNING: Could not query hotfixes: $($_.Exception.Message)" -color "Warning"
            }

            $latestDate = if (@($hotfixes).Count -gt 0 -and $hotfixes[0].InstalledOn -ne 'Unknown') { $hotfixes[0].InstalledOn } else { "Unknown" }

            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  HOTFIX AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Total Hotfixes: $(@($hotfixes).Count)   Latest: $latestDate".PadRight(72))│" -color "Info"
            if (@($hotfixes).Count -gt 0) {
                Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                foreach ($hf in ($hotfixes | Select-Object -First 15)) {
                    $line = "  $($hf.HotFixID.PadRight(14)) $($hf.InstalledOn.PadRight(12)) $($hf.Description)"
                    if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                    Write-OutputColor "  │$($line.PadRight(72))│" -color "Info"
                }
                if (@($hotfixes).Count -gt 15) {
                    Write-OutputColor "  │$("  ... and $(@($hotfixes).Count - 15) more".PadRight(72))│" -color "Info"
                }
            }
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'HotfixAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ Total = @($hotfixes).Count; LatestInstall = $latestDate; Issues = $hfIssues }
                    Hotfixes = $hotfixes
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($hfIssues -gt 0) { [Environment]::Exit(1) }
        }
        'SysInfoAudit' {
            Write-OutputColor "  Collecting system information..." -color "Info"
            Write-OutputColor "" -color "Info"

            $siIssues = 0
            $sysInfo = @{}

            try {
                $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
                $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1

                $sysInfo = @{
                    ComputerName  = $env:COMPUTERNAME
                    Domain        = "$($cs.Domain)"
                    DomainJoined  = $cs.PartOfDomain -eq $true
                    OSName        = "$($os.Caption)"
                    OSVersion     = "$($os.Version)"
                    OSBuild       = "$($os.BuildNumber)"
                    Architecture  = "$($os.OSArchitecture)"
                    InstallDate   = if ($null -ne $os.InstallDate) { $os.InstallDate.ToString("yyyy-MM-ddTHH:mm:ss") } else { "Unknown" }
                    LastBoot      = if ($null -ne $os.LastBootUpTime) { $os.LastBootUpTime.ToString("yyyy-MM-ddTHH:mm:ss") } else { "Unknown" }
                    UptimeDays    = if ($null -ne $os.LastBootUpTime) { [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1) } else { 0 }
                    Manufacturer  = "$($cs.Manufacturer)"
                    Model         = "$($cs.Model)"
                    TotalMemoryGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
                    CPUName       = "$($cpu.Name)".Trim()
                    CPUCores      = $cpu.NumberOfCores
                    CPULogical    = $cpu.NumberOfLogicalProcessors
                    TimeZone      = (Get-TimeZone).Id
                    PowerShell    = "$($PSVersionTable.PSVersion)"
                }
            } catch {
                Write-OutputColor "  ERROR: Failed to query system info: $($_.Exception.Message)" -color "Error"
                [Environment]::Exit(1)
            }

            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  SYSTEM INFO - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  OS:           $($sysInfo.OSName)".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Build:        $($sysInfo.OSVersion) ($($sysInfo.OSBuild))".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Arch:         $($sysInfo.Architecture)".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Hardware:     $($sysInfo.Manufacturer) $($sysInfo.Model)".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  CPU:          $($sysInfo.CPUName)".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Cores:        $($sysInfo.CPUCores) cores / $($sysInfo.CPULogical) logical".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  RAM:          $($sysInfo.TotalMemoryGB)GB".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Domain:       $($sysInfo.Domain) (joined: $($sysInfo.DomainJoined))".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Uptime:       $($sysInfo.UptimeDays) days".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  TimeZone:     $($sysInfo.TimeZone)".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  PowerShell:   $($sysInfo.PowerShell)".PadRight(72))│" -color "Info"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'SysInfoAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ Issues = $siIssues }
                    SystemInfo = $sysInfo
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($siIssues -gt 0) { [Environment]::Exit(1) }
        }
        'LogonAudit' {
            Write-OutputColor "  Auditing logon events..." -color "Info"
            Write-OutputColor "" -color "Info"

            $logonIssues = 0
            $recentLogons = @()
            $failedLogons = @()

            # Recent successful logons (Event ID 4624, Type 2=Interactive, 10=RemoteInteractive)
            try {
                $logonEvents = @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4624 } -MaxEvents 50 -ErrorAction SilentlyContinue)
                foreach ($evt in $logonEvents) {
                    $logonType = $evt.Properties[8].Value
                    if ($logonType -eq 2 -or $logonType -eq 10 -or $logonType -eq 11) {
                        $user = "$($evt.Properties[5].Value)"
                        if ($user -match 'SYSTEM|DWM-|UMFD-|Font Driver') { continue }
                        $recentLogons += @{
                            Time      = $evt.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ss")
                            User      = $user
                            Domain    = "$($evt.Properties[6].Value)"
                            LogonType = switch ($logonType) { 2 { 'Interactive' } 10 { 'RemoteDesktop' } 11 { 'CachedInteractive' } default { "$logonType" } }
                            Source    = "$($evt.Properties[18].Value)"
                        }
                    }
                }
            } catch { }

            # Failed logons (Event ID 4625)
            try {
                $failEvents = @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4625 } -MaxEvents 30 -ErrorAction SilentlyContinue)
                foreach ($evt in $failEvents) {
                    $failedLogons += @{
                        Time       = $evt.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ss")
                        User       = "$($evt.Properties[5].Value)"
                        Domain     = "$($evt.Properties[6].Value)"
                        SourceIP   = "$($evt.Properties[19].Value)"
                        FailReason = "$($evt.Properties[8].Value)"
                    }
                    $logonIssues++
                }
            } catch { }

            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  LOGON AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  RECENT LOGONS ($(@($recentLogons).Count))".PadRight(72))│" -color "Info"
            foreach ($l in ($recentLogons | Select-Object -First 10)) {
                $line = "  $($l.Time.Substring(0,16))  $($l.User.PadRight(20)) $($l.LogonType)"
                if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                Write-OutputColor "  │$($line.PadRight(72))│" -color "Info"
            }
            if (@($failedLogons).Count -gt 0) {
                Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                Write-OutputColor "  │$("  FAILED LOGONS ($(@($failedLogons).Count))".PadRight(72))│" -color "Warning"
                foreach ($f in ($failedLogons | Select-Object -First 10)) {
                    $line = "  $($f.Time.Substring(0,16))  $($f.User.PadRight(20)) $($f.SourceIP)"
                    if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                    Write-OutputColor "  │$($line.PadRight(72))│" -color "Warning"
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Successful: $(@($recentLogons).Count)   Failed: $(@($failedLogons).Count)".PadRight(72))│" -color $(if ($logonIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'LogonAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ RecentLogons = @($recentLogons).Count; FailedLogons = @($failedLogons).Count; Issues = $logonIssues }
                    RecentLogons = $recentLogons; FailedLogons = $failedLogons
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($logonIssues -gt 0) { [Environment]::Exit(1) }
        }
        'ACLAudit' {
            Write-OutputColor "  Auditing critical folder permissions..." -color "Info"
            Write-OutputColor "" -color "Info"

            $aclIssues = 0
            $aclResults = @()

            $criticalPaths = @(
                @{ Path = "$env:SystemRoot"; Name = 'Windows' }
                @{ Path = "$env:SystemRoot\System32"; Name = 'System32' }
                @{ Path = "$env:ProgramFiles"; Name = 'Program Files' }
                @{ Path = "${env:ProgramFiles(x86)}"; Name = 'Program Files (x86)' }
                @{ Path = "$env:SystemRoot\System32\drivers"; Name = 'Drivers' }
                @{ Path = "$env:ProgramData"; Name = 'ProgramData' }
            )

            foreach ($cp in $criticalPaths) {
                if (-not (Test-Path -LiteralPath $cp.Path)) { continue }
                $status = 'OK'
                $aces = @()
                try {
                    $acl = Get-Acl -Path $cp.Path -ErrorAction Stop
                    foreach ($ace in $acl.Access) {
                        $aces += @{ Identity = "$($ace.IdentityReference)"; Rights = "$($ace.FileSystemRights)"; Type = "$($ace.AccessControlType)" }
                        if ("$($ace.IdentityReference)" -eq 'Everyone' -and "$($ace.FileSystemRights)" -match 'FullControl|Modify|Write' -and "$($ace.AccessControlType)" -eq 'Allow') {
                            $status = 'WARN'; $aclIssues++
                        }
                    }
                } catch { }
                $aclResults += @{ Name = $cp.Name; Path = $cp.Path; ACECount = @($aces).Count; Status = $status; ACEs = $aces }
            }

            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  ACL AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($a in $aclResults) {
                $line = "  $($a.Name.PadRight(22)) ACEs: $($a.ACECount)  [$($a.Status)]"
                $color = if ($a.Status -eq 'OK') { 'Success' } else { 'Warning' }
                Write-OutputColor "  │$($line.PadRight(72))│" -color $color
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Paths checked: $(@($aclResults).Count)   Issues: $aclIssues".PadRight(72))│" -color $(if ($aclIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'ACLAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ PathsChecked = @($aclResults).Count; Issues = $aclIssues }
                    Paths = $aclResults
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($aclIssues -gt 0) { [Environment]::Exit(1) }
        }
        'RecoveryAudit' {
            Write-OutputColor "  Auditing recovery configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $recIssues = 0
            $restorePoints = @()

            # System Restore points
            try {
                $rps = @(Get-ComputerRestorePoint -ErrorAction Stop)
                foreach ($rp in $rps) {
                    $restorePoints += @{ SequenceNumber = $rp.SequenceNumber; Description = "$($rp.Description)"; CreationTime = "$($rp.CreationTime)"; RestorePointType = $rp.RestorePointType }
                }
            } catch { }

            # Recovery partition
            $recoveryPartition = $false
            try {
                $parts = @(Get-Partition -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'Recovery' })
                $recoveryPartition = @($parts).Count -gt 0
            } catch { }

            # System protection enabled
            $protectionEnabled = $false
            try {
                $vssOutput = & vssadmin list shadowstorage 2>&1
                $protectionEnabled = ($vssOutput -join ' ') -match 'Used Shadow Copy Storage'
            } catch { }

            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  RECOVERY AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  System Protection: $(if ($protectionEnabled) { 'Enabled' } else { 'Disabled' })".PadRight(72))│" -color $(if ($protectionEnabled) { "Success" } else { "Info" })
            Write-OutputColor "  │$("  Recovery Partition: $(if ($recoveryPartition) { 'Present' } else { 'Not found' })".PadRight(72))│" -color $(if ($recoveryPartition) { "Success" } else { "Info" })
            Write-OutputColor "  │$("  Restore Points: $(@($restorePoints).Count)".PadRight(72))│" -color "Info"
            if (@($restorePoints).Count -gt 0) {
                foreach ($rp in ($restorePoints | Select-Object -First 5)) {
                    $desc = if ($rp.Description.Length -gt 55) { $rp.Description.Substring(0, 52) + "..." } else { $rp.Description }
                    Write-OutputColor "  │$("  #$($rp.SequenceNumber) $desc".PadRight(72))│" -color "Info"
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Issues: $recIssues".PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'RecoveryAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ ProtectionEnabled = $protectionEnabled; RecoveryPartition = $recoveryPartition; RestorePoints = @($restorePoints).Count; Issues = $recIssues }
                    RestorePoints = $restorePoints
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($recIssues -gt 0) { [Environment]::Exit(1) }
        }
        'ServiceAccountAudit' {
            Write-OutputColor "  Auditing service accounts..." -color "Info"
            Write-OutputColor "" -color "Info"

            $saIssues = 0
            $serviceAccounts = @()

            try {
                $services = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop |
                    Where-Object { $_.StartName -ne 'LocalSystem' -and $_.StartName -ne 'NT AUTHORITY\LocalService' -and $_.StartName -ne 'NT AUTHORITY\NetworkService' -and $_.StartName -ne 'NT Authority\LocalService' -and $_.StartName -ne 'NT Authority\NetworkService' -and $null -ne $_.StartName -and $_.StartName -ne '' })

                foreach ($svc in $services) {
                    $health = 'OK'
                    $serviceAccounts += @{
                        ServiceName  = $svc.Name
                        DisplayName  = "$($svc.DisplayName)"
                        StartName    = "$($svc.StartName)"
                        StartMode    = "$($svc.StartMode)"
                        State        = "$($svc.State)"
                        Health       = $health
                    }
                }
            } catch {
                Write-OutputColor "  WARNING: Could not query services: $($_.Exception.Message)" -color "Warning"
            }

            $domainAccounts = @($serviceAccounts | Where-Object { $_.StartName -match '\\' -and $_.StartName -notmatch 'NT SERVICE' })
            $localAccounts = @($serviceAccounts | Where-Object { $_.StartName -match '^\.\\'  })

            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  SERVICE ACCOUNT AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (@($serviceAccounts).Count -eq 0) {
                Write-OutputColor "  │$("  (All services use built-in accounts)".PadRight(72))│" -color "Success"
            } else {
                foreach ($sa in $serviceAccounts) {
                    $sName = if ($sa.ServiceName.Length -gt 22) { $sa.ServiceName.Substring(0, 19) + "..." } else { $sa.ServiceName }
                    $line = "  $($sName.PadRight(24)) $($sa.StartName)"
                    if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
                    Write-OutputColor "  │$($line.PadRight(72))│" -color "Info"
                }
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Custom accounts: $(@($serviceAccounts).Count)   Domain: $(@($domainAccounts).Count)   Local: $(@($localAccounts).Count)".PadRight(72))│" -color "Info"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'ServiceAccountAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ CustomAccounts = @($serviceAccounts).Count; DomainAccounts = @($domainAccounts).Count; LocalAccounts = @($localAccounts).Count; Issues = $saIssues }
                    Services = $serviceAccounts
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($saIssues -gt 0) { [Environment]::Exit(1) }
        }
        'ProxyAudit' {
            Write-OutputColor "  Auditing proxy configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $proxyIssues = 0
            $proxyConfig = @{}

            # System (IE) proxy
            try {
                $inetReg = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
                $proxyConfig['IEProxyEnabled'] = $null -ne $inetReg -and $inetReg.ProxyEnable -eq 1
                $proxyConfig['IEProxyServer'] = if ($null -ne $inetReg -and $null -ne $inetReg.ProxyServer) { "$($inetReg.ProxyServer)" } else { '' }
                $proxyConfig['IEAutoConfigURL'] = if ($null -ne $inetReg -and $null -ne $inetReg.AutoConfigURL) { "$($inetReg.AutoConfigURL)" } else { '' }
            } catch { }

            # WinHTTP proxy
            try {
                $winhttp = & netsh winhttp show proxy 2>&1
                $winhttpStr = $winhttp -join ' '
                $proxyConfig['WinHTTPProxy'] = if ($winhttpStr -match 'Proxy Server.*:\s*(\S+)') { $regexMatches = $Matches; $regexMatches[1] } else { 'Direct' }
                $proxyConfig['WinHTTPBypass'] = if ($winhttpStr -match 'Bypass List.*:\s*(.+)') { $regexMatches = $Matches; $regexMatches[1].Trim() } else { '' }
            } catch { }

            # Environment proxy
            $proxyConfig['HTTP_PROXY'] = if ($env:HTTP_PROXY) { $env:HTTP_PROXY } else { '' }
            $proxyConfig['HTTPS_PROXY'] = if ($env:HTTPS_PROXY) { $env:HTTPS_PROXY } else { '' }
            $proxyConfig['NO_PROXY'] = if ($env:NO_PROXY) { $env:NO_PROXY } else { '' }

            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  PROXY AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  IE Proxy:     $(if ($proxyConfig['IEProxyEnabled']) { $proxyConfig['IEProxyServer'] } else { 'Disabled' })".PadRight(72))│" -color "Info"
            if ($proxyConfig['IEAutoConfigURL']) { Write-OutputColor "  │$("  PAC URL:      $($proxyConfig['IEAutoConfigURL'])".PadRight(72))│" -color "Info" }
            Write-OutputColor "  │$("  WinHTTP:      $($proxyConfig['WinHTTPProxy'])".PadRight(72))│" -color "Info"
            if ($proxyConfig['HTTP_PROXY']) { Write-OutputColor "  │$("  HTTP_PROXY:   $($proxyConfig['HTTP_PROXY'])".PadRight(72))│" -color "Info" }
            if ($proxyConfig['HTTPS_PROXY']) { Write-OutputColor "  │$("  HTTPS_PROXY:  $($proxyConfig['HTTPS_PROXY'])".PadRight(72))│" -color "Info" }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Issues: $proxyIssues".PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'ProxyAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ Issues = $proxyIssues }
                    ProxyConfig = $proxyConfig
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($proxyIssues -gt 0) { [Environment]::Exit(1) }
        }
        'PendingRebootAudit' {
            Write-OutputColor "  Checking pending reboot status..." -color "Info"
            Write-OutputColor "" -color "Info"

            $rebootRequired = $false
            $rebootReasons = @()

            # CBS (Component Based Servicing)
            if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
                $rebootRequired = $true; $rebootReasons += 'CBS RebootPending'
            }

            # Windows Update
            if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
                $rebootRequired = $true; $rebootReasons += 'Windows Update'
            }

            # Pending file rename operations
            $pfro = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
            if ($null -ne $pfro -and $null -ne $pfro.PendingFileRenameOperations) {
                $rebootRequired = $true; $rebootReasons += 'Pending File Rename'
            }

            # Computer rename pending
            $activeCompName = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -ErrorAction SilentlyContinue
            $pendCompName = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -ErrorAction SilentlyContinue
            if ($null -ne $activeCompName -and $null -ne $pendCompName -and $activeCompName.ComputerName -ne $pendCompName.ComputerName) {
                $rebootRequired = $true; $rebootReasons += 'Computer Rename'
            }

            # Domain join
            if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\JoinDomain') {
                $rebootRequired = $true; $rebootReasons += 'Domain Join'
            }

            # SCCM
            try {
                $sccm = Invoke-CimMethod -Namespace 'ROOT\ccm\ClientSDK' -ClassName CCM_ClientUtilities -MethodName DetermineIfRebootPending -ErrorAction SilentlyContinue
                if ($null -ne $sccm -and ($sccm.IsHardRebootPending -or $sccm.RebootPending)) {
                    $rebootRequired = $true; $rebootReasons += 'SCCM'
                }
            } catch { }

            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  PENDING REBOOT AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $statusColor = if ($rebootRequired) { "Warning" } else { "Success" }
            Write-OutputColor "  │$("  Reboot Required: $(if ($rebootRequired) { 'YES' } else { 'No' })".PadRight(72))│" -color $statusColor
            if (@($rebootReasons).Count -gt 0) {
                foreach ($r in $rebootReasons) {
                    Write-OutputColor "  │$("  - $r".PadRight(72))│" -color "Warning"
                }
            }
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'PendingRebootAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ RebootRequired = $rebootRequired; ReasonCount = @($rebootReasons).Count; Issues = if ($rebootRequired) { 1 } else { 0 } }
                    Reasons = $rebootReasons
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($rebootRequired) { [Environment]::Exit(1) }
        }
        'PageFileAudit' {
            Write-OutputColor "  Auditing page file configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $pfIssues = 0
            $pageFiles = @()
            $autoManaged = $false

            try {
                $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
                $autoManaged = $cs.AutomaticManagedPagefile -eq $true
            } catch { }

            try {
                $pfs = @(Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue)
                foreach ($pf in $pfs) {
                    $pageFiles += @{ Path = "$($pf.Name)"; InitialMB = $pf.InitialSize; MaximumMB = $pf.MaximumSize; AutoManaged = ($pf.InitialSize -eq 0 -and $pf.MaximumSize -eq 0) }
                }
            } catch { }

            # Current usage
            $pfUsage = @()
            try {
                $usage = @(Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction Stop)
                foreach ($u in $usage) {
                    $pctUsed = if ($u.AllocatedBaseSize -gt 0) { [math]::Round(($u.CurrentUsage / $u.AllocatedBaseSize) * 100, 1) } else { 0 }
                    if ($pctUsed -gt 80) { $pfIssues++ }
                    $pfUsage += @{ Path = "$($u.Name)"; AllocatedMB = $u.AllocatedBaseSize; UsedMB = $u.CurrentUsage; PeakMB = $u.PeakUsage; PctUsed = $pctUsed }
                }
            } catch { }

            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  PAGE FILE AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Auto Managed: $autoManaged".PadRight(72))│" -color "Info"
            foreach ($u in $pfUsage) {
                $color = if ($u.PctUsed -gt 80) { "Warning" } else { "Success" }
                Write-OutputColor "  │$("  $($u.Path)".PadRight(72))│" -color "Info"
                Write-OutputColor "  │$("    Used: $($u.UsedMB)/$($u.AllocatedMB)MB ($($u.PctUsed)%)  Peak: $($u.PeakMB)MB".PadRight(72))│" -color $color
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Issues: $pfIssues".PadRight(72))│" -color $(if ($pfIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'PageFileAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ AutoManaged = $autoManaged; PageFiles = @($pfUsage).Count; Issues = $pfIssues }
                    Settings = $pageFiles; Usage = $pfUsage
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($pfIssues -gt 0) { [Environment]::Exit(1) }
        }
        'CPUAudit' {
            Write-OutputColor "  Auditing CPU configuration..." -color "Info"
            Write-OutputColor "" -color "Info"

            $cpuIssues = 0
            $cpuResults = @()

            try {
                $cpus = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
                foreach ($cpu in $cpus) {
                    $loadPct = $cpu.LoadPercentage
                    if ($null -ne $loadPct -and $loadPct -gt 90) { $cpuIssues++ }
                    $cpuResults += @{
                        Name              = "$($cpu.Name)".Trim()
                        DeviceID          = "$($cpu.DeviceID)"
                        Cores             = $cpu.NumberOfCores
                        LogicalProcessors = $cpu.NumberOfLogicalProcessors
                        MaxClockMHz       = $cpu.MaxClockSpeed
                        CurrentClockMHz   = $cpu.CurrentClockSpeed
                        LoadPct           = $loadPct
                        L2CacheKB         = $cpu.L2CacheSize
                        L3CacheKB         = $cpu.L3CacheSize
                        Architecture      = switch ($cpu.Architecture) { 0 { 'x86' } 5 { 'ARM' } 9 { 'x64' } 12 { 'ARM64' } default { "$($cpu.Architecture)" } }
                        Virtualization     = $cpu.VirtualizationFirmwareEnabled -eq $true
                    }
                }
            } catch {
                Write-OutputColor "  ERROR: Failed to query CPU: $($_.Exception.Message)" -color "Error"
                [Environment]::Exit(1)
            }

            $totalCores = ($cpuResults | ForEach-Object { $_.Cores } | Measure-Object -Sum).Sum
            $totalLogical = ($cpuResults | ForEach-Object { $_.LogicalProcessors } | Measure-Object -Sum).Sum

            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  CPU AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($c in $cpuResults) {
                $cpuName = if ($c.Name.Length -gt 55) { $c.Name.Substring(0, 52) + "..." } else { $c.Name }
                Write-OutputColor "  │$("  $cpuName".PadRight(72))│" -color "Info"
                Write-OutputColor "  │$("    Cores: $($c.Cores)  Logical: $($c.LogicalProcessors)  Clock: $($c.CurrentClockMHz)/$($c.MaxClockMHz)MHz".PadRight(72))│" -color "Info"
                $loadStr = if ($null -ne $c.LoadPct) { "$($c.LoadPct)%" } else { "N/A" }
                $loadColor = if ($null -ne $c.LoadPct -and $c.LoadPct -gt 90) { "Error" } elseif ($null -ne $c.LoadPct -and $c.LoadPct -gt 70) { "Warning" } else { "Success" }
                Write-OutputColor "  │$("    Load: $loadStr  VT: $(if ($c.Virtualization) { 'Enabled' } else { 'Disabled' })  Arch: $($c.Architecture)".PadRight(72))│" -color $loadColor
            }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Sockets: $(@($cpuResults).Count)   Cores: $totalCores   Logical: $totalLogical   Issues: $cpuIssues".PadRight(72))│" -color $(if ($cpuIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{
                    Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'CPUAudit'
                    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
                    Summary = @{ Sockets = @($cpuResults).Count; TotalCores = $totalCores; TotalLogical = $totalLogical; Issues = $cpuIssues }
                    Processors = $cpuResults
                }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($cpuIssues -gt 0) { [Environment]::Exit(1) }
        }
        'DefenderExclusionAudit' {
            Write-OutputColor "  Auditing Defender exclusions..." -color "Info"
            Write-OutputColor "" -color "Info"
            $deIssues = 0; $exclusions = @()
            try {
                $prefs = Get-MpPreference -ErrorAction Stop
                foreach ($p in @($prefs.ExclusionPath)) { if ($p) { $exclusions += @{ Type = 'Path'; Value = "$p" }; $deIssues++ } }
                foreach ($p in @($prefs.ExclusionProcess)) { if ($p) { $exclusions += @{ Type = 'Process'; Value = "$p" }; $deIssues++ } }
                foreach ($e in @($prefs.ExclusionExtension)) { if ($e) { $exclusions += @{ Type = 'Extension'; Value = "$e" }; $deIssues++ } }
                foreach ($ip in @($prefs.ExclusionIpAddress)) { if ($ip) { $exclusions += @{ Type = 'IPAddress'; Value = "$ip" }; $deIssues++ } }
            } catch { Write-OutputColor "  Defender not available" -color "Info" }
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  DEFENDER EXCLUSION AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (@($exclusions).Count -eq 0) { Write-OutputColor "  │$("  (No exclusions configured)".PadRight(72))│" -color "Success" }
            else { foreach ($e in $exclusions) { $line = "  [$($e.Type.PadRight(10))] $($e.Value)"; if ($line.Length -gt 72) { $line = $line.Substring(0,69) + "..." }; Write-OutputColor "  │$($line.PadRight(72))│" -color "Warning" } }
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Exclusions: $(@($exclusions).Count)   (review for abuse)".PadRight(72))│" -color $(if ($deIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            if ($script:CLIOutputFormat -eq 'JSON') { $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'DefenderExclusionAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ Exclusions = @($exclusions).Count; Issues = $deIssues }; Exclusions = $exclusions }; Write-Output ($jsonResult | ConvertTo-Json -Depth 10) }
            if ($deIssues -gt 0) { [Environment]::Exit(1) }
        }
        'KerberosAudit' {
            Write-OutputColor "  Auditing Kerberos configuration..." -color "Info"
            Write-OutputColor "" -color "Info"
            $kbIssues = 0; $tickets = @(); $kerbConfig = @{}
            try { $klistOutput = & klist 2>&1; $klistStr = $klistOutput -join "`n"; $ticketCount = 0; if ($klistStr -match 'Cached Tickets:\s*(\d+)') { $regexMatches = $Matches; $ticketCount = [int]$regexMatches[1] }; $kerbConfig['CachedTickets'] = $ticketCount } catch { }
            try { $krbReg = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters' -ErrorAction SilentlyContinue; if ($null -ne $krbReg) { $kerbConfig['MaxTokenSize'] = $krbReg.MaxTokenSize; $kerbConfig['MaxPacketSize'] = $krbReg.MaxPacketSize } } catch { }
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  KERBEROS AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Cached Tickets: $($kerbConfig['CachedTickets'])".PadRight(72))│" -color "Info"
            if ($kerbConfig.ContainsKey('MaxTokenSize')) { Write-OutputColor "  │$("  Max Token Size: $($kerbConfig['MaxTokenSize'])".PadRight(72))│" -color "Info" }
            Write-OutputColor "  │$("  Issues: $kbIssues".PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            if ($script:CLIOutputFormat -eq 'JSON') { $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'KerberosAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ Issues = $kbIssues }; Config = $kerbConfig }; Write-Output ($jsonResult | ConvertTo-Json -Depth 10) }
            if ($kbIssues -gt 0) { [Environment]::Exit(1) }
        }
        'DHCPAudit' {
            Write-OutputColor "  Auditing DHCP client configuration..." -color "Info"
            Write-OutputColor "" -color "Info"
            $dhcpIssues = 0; $leases = @()
            try { $adapters = @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "DHCPEnabled=TRUE" -ErrorAction Stop)
                foreach ($a in $adapters) { $leases += @{ Description = "$($a.Description)"; DHCPServer = "$($a.DHCPServer)"; IPAddress = if ($null -ne $a.IPAddress) { $a.IPAddress[0] } else { '' }; LeaseObtained = if ($null -ne $a.DHCPLeaseObtained) { $a.DHCPLeaseObtained.ToString("yyyy-MM-ddTHH:mm:ss") } else { '' }; LeaseExpires = if ($null -ne $a.DHCPLeaseExpires) { $a.DHCPLeaseExpires.ToString("yyyy-MM-ddTHH:mm:ss") } else { '' } } }
            } catch { }
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  DHCP AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (@($leases).Count -eq 0) { Write-OutputColor "  │$("  (No DHCP-enabled adapters)".PadRight(72))│" -color "Info" }
            else { foreach ($l in $leases) { Write-OutputColor "  │$("  $($l.IPAddress.PadRight(16)) DHCP: $($l.DHCPServer)".PadRight(72))│" -color "Info"; Write-OutputColor "  │$("    Expires: $($l.LeaseExpires)".PadRight(72))│" -color "Info" } }
            Write-OutputColor "  │$("  DHCP Adapters: $(@($leases).Count)   Issues: $dhcpIssues".PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            if ($script:CLIOutputFormat -eq 'JSON') { $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'DHCPAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ DHCPAdapters = @($leases).Count; Issues = $dhcpIssues }; Leases = $leases }; Write-Output ($jsonResult | ConvertTo-Json -Depth 10) }
            if ($dhcpIssues -gt 0) { [Environment]::Exit(1) }
        }
        'NUMAAudit' {
            Write-OutputColor "  Auditing NUMA topology..." -color "Info"
            Write-OutputColor "" -color "Info"
            $numaIssues = 0; $numaNodes = @()
            try { $nodes = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
                foreach ($n in $nodes) { $numaNodes += @{ DeviceID = "$($n.DeviceID)"; Cores = $n.NumberOfCores; Logical = $n.NumberOfLogicalProcessors; L2KB = $n.L2CacheSize; L3KB = $n.L3CacheSize; NUMANode = $n.DeviceID -replace 'CPU', '' } }
            } catch { }
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  NUMA AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($n in $numaNodes) { Write-OutputColor "  │$("  $($n.DeviceID): $($n.Cores) cores, $($n.Logical) logical, L2:$($n.L2KB)KB L3:$($n.L3KB)KB".PadRight(72))│" -color "Info" }
            Write-OutputColor "  │$("  NUMA Nodes: $(@($numaNodes).Count)   Issues: $numaIssues".PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            if ($script:CLIOutputFormat -eq 'JSON') { $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'NUMAAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ Nodes = @($numaNodes).Count; Issues = $numaIssues }; Nodes = $numaNodes }; Write-Output ($jsonResult | ConvertTo-Json -Depth 10) }
            if ($numaIssues -gt 0) { [Environment]::Exit(1) }
        }
        'SymlinkAudit' {
            Write-OutputColor "  Auditing symbolic links in system directories..." -color "Info"
            Write-OutputColor "" -color "Info"
            $slIssues = 0; $symlinks = @()
            $searchPaths = @("$env:SystemRoot\System32", "$env:SystemRoot\SysWOW64", "$env:ProgramData")
            foreach ($sp in $searchPaths) { if (Test-Path -LiteralPath $sp) { try { $items = @(Get-ChildItem -LiteralPath $sp -Force -ErrorAction SilentlyContinue | Where-Object { $_.Attributes -match 'ReparsePoint' } | Select-Object -First 20); foreach ($i in $items) { $symlinks += @{ Name = $i.Name; Path = $i.FullName; Target = "$($i.Target)"; ParentDir = $sp }; $slIssues++ } } catch { } } }
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  SYMLINK AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (@($symlinks).Count -eq 0) { Write-OutputColor "  │$("  (No symlinks/reparse points found in system dirs)".PadRight(72))│" -color "Success" }
            else { foreach ($s in ($symlinks | Select-Object -First 15)) { $line = "  $($s.Name)"; if ($line.Length -gt 72) { $line = $line.Substring(0,69) + "..." }; Write-OutputColor "  │$($line.PadRight(72))│" -color "Info" } }
            Write-OutputColor "  │$("  Symlinks: $(@($symlinks).Count)".PadRight(72))│" -color "Info"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            if ($script:CLIOutputFormat -eq 'JSON') { $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'SymlinkAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ Symlinks = @($symlinks).Count; Issues = $slIssues }; Symlinks = $symlinks }; Write-Output ($jsonResult | ConvertTo-Json -Depth 10) }
            if ($slIssues -gt 0) { [Environment]::Exit(1) }
        }
        'StartupScriptAudit' {
            Write-OutputColor "  Auditing GPO startup/logon scripts..." -color "Info"
            Write-OutputColor "" -color "Info"
            $ssIssues = 0; $scripts = @()
            $scriptPaths = @( @{ Type = 'MachineStartup'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Startup' }; @{ Type = 'MachineShutdown'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Shutdown' } )
            foreach ($sp in $scriptPaths) { if (Test-Path $sp.Path) { try { $subkeys = Get-ChildItem -Path $sp.Path -ErrorAction SilentlyContinue; foreach ($sk in $subkeys) { $innerKeys = Get-ChildItem -Path $sk.PSPath -ErrorAction SilentlyContinue; foreach ($ik in $innerKeys) { $props = Get-ItemProperty -Path $ik.PSPath -ErrorAction SilentlyContinue; if ($null -ne $props -and $null -ne $props.Script) { $scripts += @{ Type = $sp.Type; Script = "$($props.Script)"; Parameters = "$($props.Parameters)" } } } } } catch { } } }
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  STARTUP SCRIPT AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (@($scripts).Count -eq 0) { Write-OutputColor "  │$("  (No GPO startup/shutdown scripts configured)".PadRight(72))│" -color "Success" }
            else { foreach ($s in $scripts) { $line = "  [$($s.Type)] $($s.Script)"; if ($line.Length -gt 72) { $line = $line.Substring(0,69) + "..." }; Write-OutputColor "  │$($line.PadRight(72))│" -color "Info" } }
            Write-OutputColor "  │$("  Scripts: $(@($scripts).Count)   Issues: $ssIssues".PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            if ($script:CLIOutputFormat -eq 'JSON') { $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'StartupScriptAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ Scripts = @($scripts).Count; Issues = $ssIssues }; Scripts = $scripts }; Write-Output ($jsonResult | ConvertTo-Json -Depth 10) }
            if ($ssIssues -gt 0) { [Environment]::Exit(1) }
        }
        'SecureChannelAudit' {
            Write-OutputColor "  Auditing domain secure channel..." -color "Info"
            Write-OutputColor "" -color "Info"
            $scIssues = 0; $scStatus = @{}
            try { $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop; $scStatus['DomainJoined'] = $cs.PartOfDomain -eq $true; $scStatus['Domain'] = "$($cs.Domain)" } catch { }
            if ($scStatus['DomainJoined']) {
                try { $nltest = & nltest /sc_query:$($scStatus['Domain']) 2>&1; $nltestStr = $nltest -join ' '; $scStatus['SecureChannel'] = if ($nltestStr -match 'NERR_Success') { 'OK' } else { 'FAIL' }; if ($scStatus['SecureChannel'] -ne 'OK') { $scIssues++ }; if ($nltestStr -match 'Trusted DC Name\s*(.+?)(?:\s|$)') { $regexMatches = $Matches; $scStatus['TrustedDC'] = $regexMatches[1].Trim() } } catch { $scStatus['SecureChannel'] = 'Error' }
            } else { $scStatus['SecureChannel'] = 'N/A (not domain-joined)' }
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  SECURE CHANNEL AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Domain:         $($scStatus['Domain'])".PadRight(72))│" -color "Info"
            $scColor = if ($scStatus['SecureChannel'] -eq 'OK') { 'Success' } elseif ($scStatus['SecureChannel'] -eq 'FAIL') { 'Error' } else { 'Info' }
            Write-OutputColor "  │$("  Secure Channel: $($scStatus['SecureChannel'])".PadRight(72))│" -color $scColor
            if ($scStatus.ContainsKey('TrustedDC')) { Write-OutputColor "  │$("  Trusted DC:     $($scStatus['TrustedDC'])".PadRight(72))│" -color "Info" }
            Write-OutputColor "  │$("  Issues: $scIssues".PadRight(72))│" -color $(if ($scIssues -gt 0) { "Error" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            if ($script:CLIOutputFormat -eq 'JSON') { $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'SecureChannelAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ Issues = $scIssues }; Status = $scStatus }; Write-Output ($jsonResult | ConvertTo-Json -Depth 10) }
            if ($scIssues -gt 0) { [Environment]::Exit(1) }
        }
        'ComObjectAudit' {
            Write-OutputColor "  Auditing COM object persistence..." -color "Info"
            Write-OutputColor "" -color "Info"
            $coIssues = 0; $comObjects = @()
            $comPaths = @('HKLM:\SOFTWARE\Classes\CLSID', 'HKCU:\SOFTWARE\Classes\CLSID')
            foreach ($cp in $comPaths) { if (Test-Path $cp) { try { $keys = Get-ChildItem -Path $cp -ErrorAction SilentlyContinue | Select-Object -First 500; foreach ($k in $keys) { $server = Get-ItemProperty -Path "$($k.PSPath)\InprocServer32" -ErrorAction SilentlyContinue; if ($null -ne $server -and $null -ne $server.'(default)' -and $server.'(default)' -notmatch 'System32|SysWOW64|Windows|Microsoft|Common Files') { $coIssues++; $comObjects += @{ CLSID = $k.PSChildName; Path = "$($server.'(default)')"; Source = $cp } } } } catch { } } }
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  COM OBJECT AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (@($comObjects).Count -eq 0) { Write-OutputColor "  │$("  (No non-system COM objects found)".PadRight(72))│" -color "Success" }
            else { foreach ($c in ($comObjects | Select-Object -First 15)) { $line = "  $($c.Path)"; if ($line.Length -gt 72) { $line = $line.Substring(0,69) + "..." }; Write-OutputColor "  │$($line.PadRight(72))│" -color "Info" } }
            Write-OutputColor "  │$("  Non-system COM: $(@($comObjects).Count)".PadRight(72))│" -color "Info"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            if ($script:CLIOutputFormat -eq 'JSON') { $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'ComObjectAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ NonSystemCOM = @($comObjects).Count; Issues = $coIssues }; COMObjects = $comObjects }; Write-Output ($jsonResult | ConvertTo-Json -Depth 10) }
            if ($coIssues -gt 0) { [Environment]::Exit(1) }
        }
        'FirewallLogAudit' {
            Write-OutputColor "  Auditing firewall logs..." -color "Info"
            Write-OutputColor "" -color "Info"
            $flIssues = 0; $logStats = @{}; $recentDrops = @()
            $logPath = "$env:SystemRoot\System32\LogFiles\Firewall\pfirewall.log"
            $logStats['LogExists'] = Test-Path -LiteralPath $logPath
            if ($logStats['LogExists']) {
                try { $logLines = Get-Content -LiteralPath $logPath -Tail 500 -ErrorAction Stop | Where-Object { $_ -notmatch '^#' -and $_ -match '\S' }
                    $drops = @($logLines | Where-Object { $_ -match '\bDROP\b' }); $allows = @($logLines | Where-Object { $_ -match '\bALLOW\b' })
                    $logStats['TotalLines'] = @($logLines).Count; $logStats['Drops'] = @($drops).Count; $logStats['Allows'] = @($allows).Count
                    foreach ($d in ($drops | Select-Object -Last 10)) { if ($d -match '(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\s+DROP\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)') { $regexMatches = $Matches; $recentDrops += @{ Date = $regexMatches[1]; Time = $regexMatches[2]; Protocol = $regexMatches[3]; SrcIP = $regexMatches[4]; DstIP = $regexMatches[5]; SrcPort = $regexMatches[6]; DstPort = $regexMatches[7] } } }
                } catch { }
            }
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  FIREWALL LOG AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Log File: $(if ($logStats['LogExists']) { 'Present' } else { 'Not found (logging may be disabled)' })".PadRight(72))│" -color $(if ($logStats['LogExists']) { "Success" } else { "Warning" })
            if ($logStats['LogExists'] -and $logStats.ContainsKey('Drops')) { Write-OutputColor "  │$("  Recent: $($logStats['Drops']) drops, $($logStats['Allows']) allows (last 500 lines)".PadRight(72))│" -color "Info" }
            if (@($recentDrops).Count -gt 0) { Write-OutputColor "  │$("  RECENT DROPS".PadRight(72))│" -color "Warning"; foreach ($d in ($recentDrops | Select-Object -First 5)) { Write-OutputColor "  │$("  $($d.SrcIP):$($d.SrcPort) -> $($d.DstIP):$($d.DstPort) ($($d.Protocol))".PadRight(72))│" -color "Warning" } }
            Write-OutputColor "  │$("  Issues: $flIssues".PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            if ($script:CLIOutputFormat -eq 'JSON') { $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'FirewallLogAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ LogExists = $logStats['LogExists']; Drops = $logStats['Drops']; Allows = $logStats['Allows']; Issues = $flIssues }; RecentDrops = $recentDrops }; Write-Output ($jsonResult | ConvertTo-Json -Depth 10) }
            if ($flIssues -gt 0) { [Environment]::Exit(1) }
        }
        'ScheduledRebootAudit' {
            Write-OutputColor "  Auditing scheduled reboots..." -color "Info"
            Write-OutputColor "" -color "Info"
            $srIssues = 0; $rebootTasks = @(); $rebootEvents = @()
            try { $tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskName -match 'reboot|restart|shutdown' -and $_.State -ne 'Disabled' }); foreach ($t in $tasks) { $rebootTasks += @{ Name = $t.TaskName; Path = $t.TaskPath; State = "$($t.State)" } } } catch { }
            try { $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = @(1074, 6006, 6009) } -MaxEvents 10 -ErrorAction SilentlyContinue)
                foreach ($e in $events) { $rebootEvents += @{ Time = $e.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ss"); EventId = $e.Id; Type = switch ($e.Id) { 1074 { 'User-initiated restart' } 6006 { 'Clean shutdown' } 6009 { 'Boot' } default { "Event $($e.Id)" } } } }
            } catch { }
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  SCHEDULED REBOOT AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Reboot-related tasks: $(@($rebootTasks).Count)".PadRight(72))│" -color "Info"
            foreach ($t in $rebootTasks) { Write-OutputColor "  │$("  $($t.Name) [$($t.State)]".PadRight(72))│" -color "Info" }
            if (@($rebootEvents).Count -gt 0) { Write-OutputColor "  │$("  RECENT REBOOT EVENTS".PadRight(72))│" -color "Info"; foreach ($e in $rebootEvents) { Write-OutputColor "  │$("  $($e.Time)  $($e.Type)".PadRight(72))│" -color "Info" } }
            Write-OutputColor "  │$("  Issues: $srIssues".PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            if ($script:CLIOutputFormat -eq 'JSON') { $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'ScheduledRebootAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ RebootTasks = @($rebootTasks).Count; RebootEvents = @($rebootEvents).Count; Issues = $srIssues }; Tasks = $rebootTasks; Events = $rebootEvents }; Write-Output ($jsonResult | ConvertTo-Json -Depth 10) }
            if ($srIssues -gt 0) { [Environment]::Exit(1) }
        }
        'PowerShellAudit' {
            Write-OutputColor "  Auditing PowerShell configuration..." -color "Info"
            Write-OutputColor "" -color "Info"
            $psIssues = 0; $psConfig = @{}
            $psConfig['Version'] = "$($PSVersionTable.PSVersion)"
            $psConfig['Edition'] = "$($PSVersionTable.PSEdition)"
            try { $psConfig['ExecutionPolicy'] = (Get-ExecutionPolicy).ToString() } catch { $psConfig['ExecutionPolicy'] = 'Unknown' }
            try { $psConfig['MachinePolicy'] = (Get-ExecutionPolicy -Scope MachinePolicy).ToString() } catch { }
            try { $psConfig['UserPolicy'] = (Get-ExecutionPolicy -Scope UserPolicy).ToString() } catch { }
            $psConfig['LanguageMode'] = "$($ExecutionContext.SessionState.LanguageMode)"
            if ($psConfig['LanguageMode'] -ne 'FullLanguage') { $psIssues++ }
            # Script block logging
            try { $sblReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' -ErrorAction SilentlyContinue; $psConfig['ScriptBlockLogging'] = $null -ne $sblReg -and $sblReg.EnableScriptBlockLogging -eq 1 } catch { $psConfig['ScriptBlockLogging'] = $false }
            try { $tReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription' -ErrorAction SilentlyContinue; $psConfig['Transcription'] = $null -ne $tReg -and $tReg.EnableTranscripting -eq 1 } catch { $psConfig['Transcription'] = $false }
            # Module logging
            try { $mlReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging' -ErrorAction SilentlyContinue; $psConfig['ModuleLogging'] = $null -ne $mlReg -and $mlReg.EnableModuleLogging -eq 1 } catch { $psConfig['ModuleLogging'] = $false }
            # PS2 engine
            try { $ps2 = Get-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2 -ErrorAction SilentlyContinue; $psConfig['PS2Engine'] = $null -ne $ps2 -and $ps2.State -eq 'Enabled'; if ($psConfig['PS2Engine']) { $psIssues++ } } catch { $psConfig['PS2Engine'] = $false }
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  POWERSHELL AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Version:        $($psConfig['Version']) ($($psConfig['Edition']))".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Exec Policy:    $($psConfig['ExecutionPolicy'])".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Language Mode:  $($psConfig['LanguageMode'])".PadRight(72))│" -color $(if ($psConfig['LanguageMode'] -eq 'FullLanguage') { "Info" } else { "Warning" })
            Write-OutputColor "  │$("  Script Logging: $(if ($psConfig['ScriptBlockLogging']) { 'Enabled' } else { 'Disabled' })".PadRight(72))│" -color $(if ($psConfig['ScriptBlockLogging']) { "Success" } else { "Info" })
            Write-OutputColor "  │$("  Transcription:  $(if ($psConfig['Transcription']) { 'Enabled' } else { 'Disabled' })".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  PS2 Engine:     $(if ($psConfig['PS2Engine']) { 'ENABLED (security risk)' } else { 'Disabled' })".PadRight(72))│" -color $(if ($psConfig['PS2Engine']) { "Warning" } else { "Success" })
            Write-OutputColor "  │$("  Issues: $psIssues".PadRight(72))│" -color $(if ($psIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            if ($script:CLIOutputFormat -eq 'JSON') { $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'PowerShellAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ Issues = $psIssues }; Config = $psConfig }; Write-Output ($jsonResult | ConvertTo-Json -Depth 10) }
            if ($psIssues -gt 0) { [Environment]::Exit(1) }
        }
        'RouteTableAudit' {
            Write-OutputColor "  Auditing routing table..." -color "Info"
            Write-OutputColor "" -color "Info"
            $rtIssues = 0; $routes = @()
            try { $allRoutes = @(Get-NetRoute -ErrorAction Stop | Where-Object { $_.DestinationPrefix -ne 'ff00::/8' -and $_.DestinationPrefix -ne 'fe80::/10' })
                foreach ($r in $allRoutes) { $routes += @{ Destination = "$($r.DestinationPrefix)"; NextHop = "$($r.NextHop)"; Metric = $r.RouteMetric; Interface = "$($r.InterfaceAlias)"; Type = "$($r.AddressFamily)" } }
            } catch { Write-OutputColor "  WARNING: Could not query routes" -color "Warning" }
            $ipv4Routes = @($routes | Where-Object { $_.Type -eq 'IPv4' })
            $defaultRoutes = @($routes | Where-Object { $_.Destination -eq '0.0.0.0/0' })
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  ROUTE TABLE AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Default gateways: $(@($defaultRoutes).Count)".PadRight(72))│" -color "Info"
            foreach ($dr in $defaultRoutes) { Write-OutputColor "  │$("    $($dr.NextHop) via $($dr.Interface) (metric $($dr.Metric))".PadRight(72))│" -color "Info" }
            Write-OutputColor "  │$("  IPv4 routes: $(@($ipv4Routes).Count)   Total: $(@($routes).Count)".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Issues: $rtIssues".PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            if ($script:CLIOutputFormat -eq 'JSON') { $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'RouteTableAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ TotalRoutes = @($routes).Count; IPv4Routes = @($ipv4Routes).Count; DefaultGateways = @($defaultRoutes).Count; Issues = $rtIssues }; Routes = $routes }; Write-Output ($jsonResult | ConvertTo-Json -Depth 10) }
            if ($rtIssues -gt 0) { [Environment]::Exit(1) }
        }
        'TokenPrivilegeAudit' {
            Write-OutputColor "  Auditing token privileges..." -color "Info"
            Write-OutputColor "" -color "Info"
            $tpIssues = 0; $privileges = @()
            try { $whoami = & whoami /priv /fo csv 2>&1; $privData = $whoami | ConvertFrom-Csv -ErrorAction Stop
                foreach ($p in $privData) { $enabled = "$($p.State)" -match 'Enabled'; $privName = "$($p.'Privilege Name')"; $privileges += @{ Name = $privName; State = "$($p.State)"; Description = "$($p.Description)" }
                    if ($enabled -and $privName -match 'SeDebugPrivilege|SeTcbPrivilege|SeBackupPrivilege|SeRestorePrivilege') { $tpIssues++ } }
            } catch { }
            $enabledCount = @($privileges | Where-Object { $_.State -match 'Enabled' }).Count
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  TOKEN PRIVILEGE AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($p in $privileges) { $color = if ($p.State -match 'Enabled') { "Success" } else { "Info" }; $pName = if ($p.Name.Length -gt 35) { $p.Name.Substring(0,32) + "..." } else { $p.Name }; Write-OutputColor "  │$("  $($pName.PadRight(37)) $($p.State)".PadRight(72))│" -color $color }
            Write-OutputColor "  │$("  Total: $(@($privileges).Count)   Enabled: $enabledCount   Issues: $tpIssues".PadRight(72))│" -color $(if ($tpIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            if ($script:CLIOutputFormat -eq 'JSON') { $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'TokenPrivilegeAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ Total = @($privileges).Count; Enabled = $enabledCount; Issues = $tpIssues }; Privileges = $privileges }; Write-Output ($jsonResult | ConvertTo-Json -Depth 10) }
            if ($tpIssues -gt 0) { [Environment]::Exit(1) }
        }
        'WindowsCapabilityAudit' {
            Write-OutputColor "  Auditing Windows capabilities..." -color "Info"
            Write-OutputColor "" -color "Info"
            $wcIssues = 0; $capabilities = @()
            try { $caps = @(Get-WindowsCapability -Online -ErrorAction Stop | Where-Object { $_.State -eq 'Installed' })
                foreach ($c in $caps) { $capabilities += @{ Name = "$($c.Name)"; State = "$($c.State)" } }
            } catch { Write-OutputColor "  WARNING: Could not query capabilities" -color "Warning" }
            $rsatCaps = @($capabilities | Where-Object { $_.Name -match 'Rsat' })
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  WINDOWS CAPABILITY AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Installed: $(@($capabilities).Count)   RSAT: $(@($rsatCaps).Count)".PadRight(72))│" -color "Info"
            if (@($rsatCaps).Count -gt 0) { Write-OutputColor "  │$("  RSAT TOOLS".PadRight(72))│" -color "Info"; foreach ($r in $rsatCaps) { $rName = $r.Name -replace 'Rsat\.', '' -replace '~~~~.*', ''; Write-OutputColor "  │$("  $rName".PadRight(72))│" -color "Success" } }
            foreach ($c in ($capabilities | Where-Object { $_.Name -notmatch 'Rsat' } | Select-Object -First 10)) { $cName = $c.Name -replace '~~~~.*', ''; if ($cName.Length -gt 65) { $cName = $cName.Substring(0,62) + "..." }; Write-OutputColor "  │$("  $cName".PadRight(72))│" -color "Info" }
            if (@($capabilities).Count -gt @($rsatCaps).Count + 10) { Write-OutputColor "  │$("  ... and $(@($capabilities).Count - @($rsatCaps).Count - 10) more".PadRight(72))│" -color "Info" }
            Write-OutputColor "  │$("  Issues: $wcIssues".PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            if ($script:CLIOutputFormat -eq 'JSON') { $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'WindowsCapabilityAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ Installed = @($capabilities).Count; RSAT = @($rsatCaps).Count; Issues = $wcIssues }; Capabilities = $capabilities }; Write-Output ($jsonResult | ConvertTo-Json -Depth 10) }
            if ($wcIssues -gt 0) { [Environment]::Exit(1) }
        }
        'ARPTableAudit' {
            Write-OutputColor "  Auditing ARP table..." -color "Info"
            Write-OutputColor "" -color "Info"
            $arpIssues = 0; $arpEntries = @()
            try { $neighbors = @(Get-NetNeighbor -ErrorAction Stop | Where-Object { $_.State -ne 'Unreachable' -and $_.IPAddress -notmatch '^ff|^224|^239' })
                foreach ($n in $neighbors) { $arpEntries += @{ IPAddress = "$($n.IPAddress)"; LinkLayerAddress = "$($n.LinkLayerAddress)"; State = "$($n.State)"; Interface = "$($n.InterfaceAlias)"; AddressFamily = "$($n.AddressFamily)" } }
            } catch { Write-OutputColor "  WARNING: Could not query ARP table" -color "Warning" }
            $staleCount = @($arpEntries | Where-Object { $_.State -eq 'Stale' }).Count
            $reachable = @($arpEntries | Where-Object { $_.State -eq 'Reachable' }).Count
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  ARP TABLE AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($a in ($arpEntries | Where-Object { $_.AddressFamily -eq 'IPv4' } | Select-Object -First 20)) { Write-OutputColor "  │$("  $($a.IPAddress.PadRight(17)) $($a.LinkLayerAddress.PadRight(20)) $($a.State)".PadRight(72))│" -color "Info" }
            Write-OutputColor "  │$("  Entries: $(@($arpEntries).Count)   Reachable: $reachable   Stale: $staleCount".PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            if ($script:CLIOutputFormat -eq 'JSON') { $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'ARPTableAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ Entries = @($arpEntries).Count; Reachable = $reachable; Stale = $staleCount; Issues = $arpIssues }; Neighbors = $arpEntries }; Write-Output ($jsonResult | ConvertTo-Json -Depth 10) }
            if ($arpIssues -gt 0) { [Environment]::Exit(1) }
        }
        'LocaleAudit' {
            Write-OutputColor "  Auditing locale configuration..." -color "Info"
            Write-OutputColor "" -color "Info"
            $lcIssues = 0; $localeConfig = @{}
            try { $culture = [System.Globalization.CultureInfo]::CurrentCulture; $uiCulture = [System.Globalization.CultureInfo]::CurrentUICulture
                $localeConfig['SystemLocale'] = "$($culture.Name)"
                $localeConfig['DisplayName'] = "$($culture.DisplayName)"
                $localeConfig['UILanguage'] = "$($uiCulture.Name)"
                $localeConfig['UIDisplayName'] = "$($uiCulture.DisplayName)"
            } catch { }
            try { $tz = Get-TimeZone -ErrorAction Stop; $localeConfig['TimeZone'] = $tz.Id; $localeConfig['UTCOffset'] = "$($tz.BaseUtcOffset)" } catch { }
            try { $kbLayouts = @(Get-WinUserLanguageList -ErrorAction SilentlyContinue); $localeConfig['InputLanguages'] = @($kbLayouts | ForEach-Object { "$($_.LanguageTag)" }) } catch { $localeConfig['InputLanguages'] = @() }
            $localeConfig['DateFormat'] = [System.Globalization.CultureInfo]::CurrentCulture.DateTimeFormat.ShortDatePattern
            $localeConfig['NumberDecimal'] = [System.Globalization.CultureInfo]::CurrentCulture.NumberFormat.NumberDecimalSeparator
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  LOCALE AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  System Locale: $($localeConfig['SystemLocale']) ($($localeConfig['DisplayName']))".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  UI Language:   $($localeConfig['UILanguage']) ($($localeConfig['UIDisplayName']))".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Time Zone:     $($localeConfig['TimeZone']) ($($localeConfig['UTCOffset']))".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Date Format:   $($localeConfig['DateFormat'])   Decimal: $($localeConfig['NumberDecimal'])".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Issues: $lcIssues".PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            if ($script:CLIOutputFormat -eq 'JSON') { $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'LocaleAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ Issues = $lcIssues }; Locale = $localeConfig }; Write-Output ($jsonResult | ConvertTo-Json -Depth 10) }
            if ($lcIssues -gt 0) { [Environment]::Exit(1) }
        }
        'TaskHistoryAudit' {
            Write-OutputColor "  Auditing scheduled task history..." -color "Info"
            Write-OutputColor "" -color "Info"
            $thIssues = 0; $taskHistory = @()
            try { $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-TaskScheduler/Operational'; Id = @(102, 201) } -MaxEvents 50 -ErrorAction SilentlyContinue)
                foreach ($e in $events) {
                    $taskName = ''; $resultCode = ''
                    if ($e.Id -eq 102) { if ($e.Properties.Count -ge 2) { $taskName = "$($e.Properties[0].Value)"; $resultCode = "$($e.Properties[1].Value)" } }
                    elseif ($e.Id -eq 201) { if ($e.Properties.Count -ge 2) { $taskName = "$($e.Properties[0].Value)"; $resultCode = "$($e.Properties[1].Value)" } }
                    if ($taskName) { $health = if ($resultCode -eq '0' -or $resultCode -eq '267009' -or $resultCode -eq '267014') { 'OK' } else { 'FAIL' }
                        if ($health -eq 'FAIL') { $thIssues++ }
                        $taskHistory += @{ Time = $e.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ss"); TaskName = $taskName; ResultCode = $resultCode; Health = $health } }
                }
            } catch { }
            $failedTasks = @($taskHistory | Where-Object { $_.Health -eq 'FAIL' })
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  TASK HISTORY AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if (@($failedTasks).Count -gt 0) { Write-OutputColor "  │$("  FAILED TASKS ($(@($failedTasks).Count))".PadRight(72))│" -color "Warning"
                foreach ($t in ($failedTasks | Select-Object -First 10)) { $tName = if ($t.TaskName.Length -gt 40) { $t.TaskName.Substring(0,37) + "..." } else { $t.TaskName }; Write-OutputColor "  │$("  $($t.Time.Substring(0,16))  $tName  RC:$($t.ResultCode)".PadRight(72))│" -color "Warning" } }
            Write-OutputColor "  │$("  Recent: $(@($taskHistory).Count)   Failed: $(@($failedTasks).Count)".PadRight(72))│" -color $(if ($thIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            if ($script:CLIOutputFormat -eq 'JSON') { $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'TaskHistoryAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ RecentTasks = @($taskHistory).Count; Failed = @($failedTasks).Count; Issues = $thIssues }; History = $taskHistory }; Write-Output ($jsonResult | ConvertTo-Json -Depth 10) }
            if ($thIssues -gt 0) { [Environment]::Exit(1) }
        }
        'NTFSAudit' {
            Write-OutputColor "  Auditing NTFS features..." -color "Info"
            Write-OutputColor "" -color "Info"
            $ntfsIssues = 0; $volumeInfo = @()
            try { $vols = @(Get-Volume -ErrorAction Stop | Where-Object { $_.FileSystem -eq 'NTFS' -and $null -ne $_.DriveLetter -and $_.DriveLetter -ne '' })
                foreach ($v in $vols) {
                    $compressed = $false; $encrypted = $false
                    $drivePath = "$($v.DriveLetter):\"
                    if (Test-Path -LiteralPath $drivePath) {
                        try { $compFiles = @(Get-ChildItem -LiteralPath $drivePath -Recurse -Force -ErrorAction SilentlyContinue -Attributes Compressed | Select-Object -First 1); $compressed = @($compFiles).Count -gt 0 } catch { }
                        try { $encFiles = @(Get-ChildItem -LiteralPath $drivePath -Recurse -Force -ErrorAction SilentlyContinue -Attributes Encrypted | Select-Object -First 1); $encrypted = @($encFiles).Count -gt 0 } catch { }
                    }
                    $volumeInfo += @{ DriveLetter = "$($v.DriveLetter):"; FileSystem = "$($v.FileSystem)"; SizeGB = [math]::Round($v.Size / 1GB, 1); Label = "$($v.FileSystemLabel)"; HasCompressed = $compressed; HasEncrypted = $encrypted; HealthStatus = "$($v.HealthStatus)" }
                    if ("$($v.HealthStatus)" -ne 'Healthy') { $ntfsIssues++ }
                }
            } catch { Write-OutputColor "  WARNING: Could not query volumes" -color "Warning" }
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  NTFS AUDIT - $env:COMPUTERNAME".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($vol in $volumeInfo) {
                $flags = @(); if ($vol.HasCompressed) { $flags += "COMP" }; if ($vol.HasEncrypted) { $flags += "EFS" }
                $flagStr = if (@($flags).Count -gt 0) { "[$($flags -join ',')]" } else { "" }
                Write-OutputColor "  │$("  $($vol.DriveLetter) $($vol.Label.PadRight(15)) $($vol.SizeGB)GB  $($vol.HealthStatus)  $flagStr".PadRight(72))│" -color $(if ($vol.HealthStatus -eq 'Healthy') { "Success" } else { "Error" })
            }
            Write-OutputColor "  │$("  NTFS Volumes: $(@($volumeInfo).Count)   Issues: $ntfsIssues".PadRight(72))│" -color $(if ($ntfsIssues -gt 0) { "Warning" } else { "Success" })
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            if ($script:CLIOutputFormat -eq 'JSON') { $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'NTFSAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ Volumes = @($volumeInfo).Count; Issues = $ntfsIssues }; Volumes = $volumeInfo }; Write-Output ($jsonResult | ConvertTo-Json -Depth 10) }
            if ($ntfsIssues -gt 0) { [Environment]::Exit(1) }
        }
        'Win11Cleanup' {
            $build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber -ErrorAction SilentlyContinue).CurrentBuildNumber
            if ($build -lt 22000) {
                Write-OutputColor "  Not Windows 11 or Server 2025 (build $build). Skipping." -color "Warning"
                if ($script:CLIOutputFormat -eq 'JSON') {
                    $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'Win11Cleanup'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Status = 'Skipped'; Build = $build; Reason = 'OS build < 22000' }
                    Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
                }
            }
            else {
                $tweakResults = @()
                $tweaks = @(
                    @{ Name = "Classic right-click"; Key = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"; IsDefault = $true; Value = "" }
                    @{ Name = "Left-align taskbar"; Key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Prop = "TaskbarAl"; Value = 0 }
                    @{ Name = "Show file extensions"; Key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Prop = "HideFileExt"; Value = 0 }
                    @{ Name = "Show hidden files"; Key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Prop = "Hidden"; Value = 1 }
                    @{ Name = "Disable Widgets"; Key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Prop = "TaskbarDa"; Value = 0 }
                    @{ Name = "Disable Chat"; Key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Prop = "TaskbarMn"; Value = 0 }
                    @{ Name = "Minimize search box"; Key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Prop = "SearchboxTaskbarMode"; Value = 1 }
                    @{ Name = "Disable Copilot"; Key = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"; Prop = "TurnOffWindowsCopilot"; Value = 1 }
                    @{ Name = "Explorer to This PC"; Key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Prop = "LaunchTo"; Value = 1 }
                    @{ Name = "Disable Snap flyout"; Key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Prop = "EnableSnapAssistFlyout"; Value = 0 }
                    @{ Name = "Disable Start recommendations"; Key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Prop = "Start_IrisRecommendations"; Value = 0 }
                    @{ Name = "Disable Gallery"; Key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Prop = "ShowGalleryInExplorer"; Value = 0 }
                    @{ Name = "Disable Home page"; Key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Prop = "ShowHome"; Value = 0 }
                )
                $applied = 0; $w11failed = 0
                foreach ($t in $tweaks) {
                    try {
                        if (-not (Test-Path -LiteralPath $t.Key)) { $null = New-Item -Path $t.Key -Force -ErrorAction Stop }
                        if ($t.IsDefault) { $null = Set-Item -LiteralPath $t.Key -Value $t.Value -Force -ErrorAction Stop }
                        else { $null = Set-ItemProperty -LiteralPath $t.Key -Name $t.Prop -Value $t.Value -Type DWord -Force -ErrorAction Stop }
                        Write-OutputColor "  [OK] $($t.Name)" -color "Success"
                        $tweakResults += @{ Name = $t.Name; Status = 'Applied' }
                        $applied++
                    }
                    catch {
                        Write-OutputColor "  [!!] $($t.Name): $($_.Exception.Message)" -color "Error"
                        $tweakResults += @{ Name = $t.Name; Status = 'Failed'; Error = $_.Exception.Message }
                        $w11failed++
                    }
                }
                # Reset folder grouping
                Remove-Item -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes" -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Streams" -Recurse -Force -ErrorAction SilentlyContinue
                $tweakResults += @{ Name = 'Reset folder grouping'; Status = 'Applied' }
                $applied++
                Write-OutputColor "  [OK] Reset folder grouping" -color "Success"
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Applied: $applied   Failed: $w11failed" -color $(if ($w11failed -gt 0) { "Warning" } else { "Success" })
                if ($script:CLIOutputFormat -eq 'JSON') {
                    $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'Win11Cleanup'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Build = $build; Applied = $applied; Failed = $w11failed; Tweaks = $tweakResults }
                    Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
                }
                Add-SessionChange -Category "Debloat" -Description "Win11Cleanup CLI: $applied tweaks applied"
                if ($w11failed -gt 0) { [Environment]::Exit(1) }
            }
        }
        'DarkMode' {
            $themeKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
            try {
                if (-not (Test-Path -LiteralPath $themeKey)) { $null = New-Item -Path $themeKey -Force }
                Set-ItemProperty -LiteralPath $themeKey -Name AppsUseLightTheme -Value 0 -Type DWord -Force
                Set-ItemProperty -LiteralPath $themeKey -Name SystemUsesLightTheme -Value 0 -Type DWord -Force
                Write-OutputColor "  Dark Mode applied." -color "Success"
                if ($script:CLIOutputFormat -eq 'JSON') { Write-Output (@{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'DarkMode'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Status = 'Applied' } | ConvertTo-Json -Depth 10) }
            }
            catch { Write-OutputColor "  Failed: $($_.Exception.Message)" -color "Error"; [Environment]::Exit(1) }
        }
        'LightMode' {
            $themeKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
            try {
                if (-not (Test-Path -LiteralPath $themeKey)) { $null = New-Item -Path $themeKey -Force }
                Set-ItemProperty -LiteralPath $themeKey -Name AppsUseLightTheme -Value 1 -Type DWord -Force
                Set-ItemProperty -LiteralPath $themeKey -Name SystemUsesLightTheme -Value 1 -Type DWord -Force
                Write-OutputColor "  Light Mode applied." -color "Success"
                if ($script:CLIOutputFormat -eq 'JSON') { Write-Output (@{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'LightMode'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Status = 'Applied' } | ConvertTo-Json -Depth 10) }
            }
            catch { Write-OutputColor "  Failed: $($_.Exception.Message)" -color "Error"; [Environment]::Exit(1) }
        }
        'iSCSIAudit' {
            Write-OutputColor "  Auditing iSCSI configuration..." -color "Info"
            Write-OutputColor "" -color "Info"
            $iscsiIssues = 0
            $sessions = @(Get-IscsiSession -ErrorAction SilentlyContinue)
            $targets = @(Get-IscsiTarget -ErrorAction SilentlyContinue)
            $connections = @(Get-IscsiConnection -ErrorAction SilentlyContinue)
            $initiator = Get-InitiatorPort -ErrorAction SilentlyContinue | Select-Object -First 1
            $iqn = if ($initiator) { $initiator.NodeAddress } else { "Unknown" }
            Write-OutputColor "  Initiator IQN: $iqn" -color "Info"
            Write-OutputColor "  Active Sessions: $($sessions.Count)" -color $(if ($sessions.Count -gt 0) { "Success" } else { "Warning" })
            Write-OutputColor "  Known Targets: $($targets.Count)" -color "Info"
            Write-OutputColor "  Connections: $($connections.Count)" -color "Info"
            if ($sessions.Count -eq 0) {
                Write-OutputColor "  No active iSCSI sessions." -color "Warning"
                $iscsiIssues++
            }
            else {
                Write-OutputColor "" -color "Info"
                foreach ($s in $sessions) {
                    $pathCount = @($connections | Where-Object { $_.SessionIdentifier -eq $s.SessionIdentifier }).Count
                    $color = if ($s.IsConnected) { "Success" } else { "Error" }
                    Write-OutputColor "  Target: $($s.TargetNodeAddress)" -color $color
                    Write-OutputColor "    Connected: $($s.IsConnected)   Persistent: $($s.IsPersistent)   Paths: $pathCount" -color "Info"
                    if (-not $s.IsConnected) { $iscsiIssues++ }
                    if (-not $s.IsPersistent) { $iscsiIssues++; Write-OutputColor "    WARNING: Session is not persistent (won't survive reboot)" -color "Warning" }
                }
            }
            # MPIO check
            $mpioDevices = @(Get-MSDSMSupportedHW -ErrorAction SilentlyContinue)
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  MPIO Claimed Devices: $($mpioDevices.Count)" -color $(if ($mpioDevices.Count -gt 0) { "Success" } else { "Info" })
            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'iSCSIAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ InitiatorIQN = $iqn; Sessions = $sessions.Count; Targets = $targets.Count; Connections = $connections.Count; MPIODevices = $mpioDevices.Count; Issues = $iscsiIssues }; Sessions = @($sessions | ForEach-Object { @{ Target = $_.TargetNodeAddress; Connected = $_.IsConnected; Persistent = $_.IsPersistent } }) }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($iscsiIssues -gt 0) { [Environment]::Exit(1) }
        }
        'NICTeamAudit' {
            Write-OutputColor "  Auditing NIC teaming..." -color "Info"
            Write-OutputColor "" -color "Info"
            $teamIssues = 0
            # Check SET teams (Hyper-V Switch Embedded Teaming)
            $setTeams = @(Get-VMSwitch -ErrorAction SilentlyContinue | Where-Object { $_.EmbeddedTeamingEnabled })
            if ($setTeams.Count -gt 0) {
                Write-OutputColor "  SET Teams: $($setTeams.Count)" -color "Success"
                foreach ($team in $setTeams) {
                    $members = @(Get-VMSwitchTeam -VMSwitch $team -ErrorAction SilentlyContinue | ForEach-Object { $_.NetAdapterInterfaceDescription })
                    Write-OutputColor "    Switch: $($team.Name)  Members: $($members.Count)  Mode: $($team.BandwidthReservationMode)" -color "Info"
                    foreach ($member in $members) {
                        $nic = Get-NetAdapter -InterfaceDescription $member -ErrorAction SilentlyContinue
                        $status = if ($nic) { $nic.Status } else { "Unknown" }
                        $color = if ($status -eq "Up") { "Success" } else { "Error" }
                        Write-OutputColor "      $member — $status" -color $color
                        if ($status -ne "Up") { $teamIssues++ }
                    }
                }
            }
            # Check LBFO teams
            $lbfoTeams = @(Get-NetLbfoTeam -ErrorAction SilentlyContinue)
            if ($lbfoTeams.Count -gt 0) {
                Write-OutputColor "  LBFO Teams: $($lbfoTeams.Count)" -color "Success"
                foreach ($team in $lbfoTeams) {
                    $color = if ($team.Status -eq "Up") { "Success" } else { "Error" }
                    Write-OutputColor "    Team: $($team.Name)  Status: $($team.Status)  Mode: $($team.TeamingMode)  LB: $($team.LoadBalancingAlgorithm)" -color $color
                    $members = @(Get-NetLbfoTeamMember -Team $team.Name -ErrorAction SilentlyContinue)
                    foreach ($m in $members) {
                        $mColor = if ($m.AdministrativeMode -eq "Active" -and $m.ReceiveLinkSpeed -gt 0) { "Success" } else { "Warning" }
                        Write-OutputColor "      $($m.Name) — $($m.AdministrativeMode)  Speed: $(Format-LinkSpeed $m.ReceiveLinkSpeed)" -color $mColor
                    }
                    if ($team.Status -ne "Up") { $teamIssues++ }
                }
            }
            if ($setTeams.Count -eq 0 -and $lbfoTeams.Count -eq 0) {
                Write-OutputColor "  No NIC teams (SET or LBFO) found." -color "Info"
            }
            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'NICTeamAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ SETTeams = $setTeams.Count; LBFOTeams = $lbfoTeams.Count; Issues = $teamIssues } }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($teamIssues -gt 0) { [Environment]::Exit(1) }
        }
        'SMBSessionAudit' {
            Write-OutputColor "  Auditing SMB sessions..." -color "Info"
            Write-OutputColor "" -color "Info"
            $smbIssues = 0
            $sessions = @(Get-SmbSession -ErrorAction SilentlyContinue)
            $openFiles = @(Get-SmbOpenFile -ErrorAction SilentlyContinue)
            Write-OutputColor "  Active Sessions: $($sessions.Count)" -color $(if ($sessions.Count -gt 0) { "Success" } else { "Info" })
            Write-OutputColor "  Open Files: $($openFiles.Count)" -color "Info"
            if ($sessions.Count -gt 0) {
                Write-OutputColor "" -color "Info"
                $grouped = $sessions | Group-Object -Property ClientComputerName
                foreach ($g in $grouped) {
                    $clientFiles = @($openFiles | Where-Object { $_.ClientComputerName -eq $g.Name }).Count
                    Write-OutputColor "  Client: $($g.Name)  Sessions: $($g.Count)  Open Files: $clientFiles" -color "Info"
                }
                # Check for stale sessions (connected > 24h)
                $stale = @($sessions | Where-Object { $null -ne $_.ConnectedTime -and (New-TimeSpan -Start $_.ConnectedTime).TotalHours -gt 24 })
                if ($stale.Count -gt 0) {
                    Write-OutputColor "" -color "Info"
                    Write-OutputColor "  Stale sessions (>24h): $($stale.Count)" -color "Warning"
                    $smbIssues++
                }
            }
            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'SMBSessionAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ ActiveSessions = $sessions.Count; OpenFiles = $openFiles.Count; Issues = $smbIssues }; SessionsByClient = @($sessions | Group-Object ClientComputerName | ForEach-Object { @{ Client = $_.Name; Sessions = $_.Count } }) }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($smbIssues -gt 0) { [Environment]::Exit(1) }
        }
        'WindowsUpdateAudit' {
            Write-OutputColor "  Checking for pending Windows updates..." -color "Info"
            Write-OutputColor "" -color "Info"
            $wuIssues = 0
            $pendingUpdates = @()
            try {
                # Try PSWindowsUpdate module first (faster, more reliable)
                $pswu = Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue
                if ($pswu) {
                    Import-Module PSWindowsUpdate -ErrorAction Stop
                    $updates = @(Get-WindowsUpdate -AcceptAll -ErrorAction Stop)
                    foreach ($u in $updates) {
                        $sizeMB = if ($u.Size) { [math]::Round($u.Size / 1MB, 1) } else { 0 }
                        $pendingUpdates += @{ Title = "$($u.Title)"; KB = "$($u.KB)"; SizeMB = $sizeMB; IsImportant = ($u.MsrcSeverity -eq "Critical" -or $u.MsrcSeverity -eq "Important") }
                        $color = if ($u.MsrcSeverity -eq "Critical") { "Error" } elseif ($u.MsrcSeverity -eq "Important") { "Warning" } else { "Info" }
                        Write-OutputColor "  [$($u.MsrcSeverity)] $($u.Title) ($sizeMB MB)" -color $color
                    }
                }
                else {
                    # Fallback: COM-based update search
                    $session = New-Object -ComObject Microsoft.Update.Session
                    $searcher = $session.CreateUpdateSearcher()
                    $result = $searcher.Search("IsInstalled=0")
                    foreach ($u in $result.Updates) {
                        $sizeMB = if ($u.MaxDownloadSize) { [math]::Round($u.MaxDownloadSize / 1MB, 1) } else { 0 }
                        $severity = if ($u.MsrcSeverity) { $u.MsrcSeverity } else { "Unspecified" }
                        $kbMatch = if ($u.Title -match 'KB(\d+)') { $matches[1] } else { "" }
                        $pendingUpdates += @{ Title = "$($u.Title)"; KB = $kbMatch; SizeMB = $sizeMB; Severity = $severity }
                        $color = if ($severity -eq "Critical") { "Error" } elseif ($severity -eq "Important") { "Warning" } else { "Info" }
                        Write-OutputColor "  [$severity] $($u.Title) ($sizeMB MB)" -color $color
                    }
                }
            }
            catch {
                Write-OutputColor "  Failed to check updates: $($_.Exception.Message)" -color "Error"
                $wuIssues++
            }
            Write-OutputColor "" -color "Info"
            $critical = @($pendingUpdates | Where-Object { $_.IsImportant -or $_.Severity -eq "Critical" }).Count
            Write-OutputColor "  Pending: $($pendingUpdates.Count)   Critical/Important: $critical" -color $(if ($critical -gt 0) { "Warning" } elseif ($pendingUpdates.Count -gt 0) { "Info" } else { "Success" })
            if ($pendingUpdates.Count -eq 0 -and $wuIssues -eq 0) {
                Write-OutputColor "  System is up to date." -color "Success"
            }
            if ($critical -gt 0) { $wuIssues++ }
            if ($script:CLIOutputFormat -eq 'JSON') {
                $jsonResult = @{ Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'WindowsUpdateAudit'; Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME; Summary = @{ PendingUpdates = $pendingUpdates.Count; Critical = $critical; Issues = $wuIssues }; Updates = $pendingUpdates }
                Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
            }
            if ($wuIssues -gt 0) { [Environment]::Exit(1) }
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
            $serializableStack | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $batchUndoPath -Force -ErrorAction Stop
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