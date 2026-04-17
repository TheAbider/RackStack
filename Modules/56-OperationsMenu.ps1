#region ===== OPERATIONS MENU =====
function Show-OperationsMenu {
    param(
        [string]$ComputerName = $null,
        [System.Management.Automation.PSCredential]$Credential = $null
    )

    while ($true) {
        if ($global:ReturnToMainMenu) { return }

        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                          OPERATIONS").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  VM OPERATIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  VM Checkpoint Management"
        Write-MenuItem "[2]  VM Export / Import"
        Write-MenuItem "[31] Batch VM Cleanup"
        Write-MenuItem "[32] VM Migration Pre-Flight"
        Write-MenuItem "[33] Logged-On Users"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  CLUSTER OPERATIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[3]  Cluster Dashboard"
        Write-MenuItem "[4]  Cluster Operations (Drain/Resume)"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  REMOTE MANAGEMENT".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[5]  Remote PowerShell Session"
        Write-MenuItem "[6]  Remote Server Health Check"
        Write-MenuItem "[7]  Remote Service Manager"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  REPORTS & TOOLS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[8]  Generate HTML Health Report"
        Write-MenuItem "[9]  Generate HTML Readiness Report"
        Write-MenuItem "[10] Export Profile Comparison (HTML)"
        Write-MenuItem "[11] Network Diagnostics ►"
        Write-MenuItem "[12] Drift Detection ►"
        Write-MenuItem "[13] Save Performance Snapshot"
        Write-MenuItem "[14] Generate Trend Report"
        Write-MenuItem "[15] Collect Metrics (Interval)"
        Write-MenuItem "[16] Scheduled Task Viewer"
        Write-MenuItem "[17] SMB Share Audit"
        Write-MenuItem "[18] Installed Software Inventory"
        Write-MenuItem "[19] Certificate Expiry Check"
        Write-MenuItem "[20] VSS Writer Status"
        Write-MenuItem "[21] Event Log Alerts (24h)"
        Write-MenuItem "[22] Uptime & Reboot History"
        Write-MenuItem "[23] Driver Health Check"
        Write-MenuItem "[24] Disk Space Analyzer"
        Write-MenuItem "[25] Windows Update Status"
        Write-MenuItem "[26] Listening Ports & Services"
        Write-MenuItem "[27] Scheduled Task Overview"
        Write-MenuItem "[28] Firewall Rule Summary"
        Write-MenuItem "[29] Reboot Pending Details"
        Write-MenuItem "[30] Memory Pressure Diagnostics"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  [/] Search    [B] ◄ Back to Server Config" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        # Search feature — filter operations by keyword
        if ($choice -eq "/") {
            Write-OutputColor "" -color "Info"
            $searchTerm = Read-Host "  Search"
            if ([string]::IsNullOrWhiteSpace($searchTerm)) { continue }
            $opsItems = @(
                @{Num="1";  Name="VM Checkpoint Management"}; @{Num="2";  Name="VM Export / Import"}
                @{Num="3";  Name="Cluster Dashboard"};        @{Num="4";  Name="Cluster Operations (Drain/Resume)"}
                @{Num="5";  Name="Remote PowerShell Session"}; @{Num="6";  Name="Remote Server Health Check"}
                @{Num="7";  Name="Remote Service Manager"};   @{Num="8";  Name="Generate HTML Health Report"}
                @{Num="9";  Name="Generate HTML Readiness Report"}; @{Num="10"; Name="Export Profile Comparison (HTML)"}
                @{Num="11"; Name="Network Diagnostics"};      @{Num="12"; Name="Drift Detection"}
                @{Num="13"; Name="Save Performance Snapshot"}; @{Num="14"; Name="Generate Trend Report"}
                @{Num="15"; Name="Collect Metrics (Interval)"}; @{Num="16"; Name="Scheduled Task Viewer"}
                @{Num="17"; Name="SMB Share Audit"};           @{Num="18"; Name="Installed Software Inventory"}
                @{Num="19"; Name="Certificate Expiry Check"};  @{Num="20"; Name="VSS Writer Status"}
                @{Num="21"; Name="Event Log Alerts (24h)"};    @{Num="22"; Name="Uptime & Reboot History"}
                @{Num="23"; Name="Driver Health Check"};       @{Num="24"; Name="Disk Space Analyzer"}
                @{Num="25"; Name="Windows Update Status"};     @{Num="26"; Name="Listening Ports & Services"}
                @{Num="27"; Name="Scheduled Task Overview"};   @{Num="28"; Name="Firewall Rule Summary"}
                @{Num="29"; Name="Reboot Pending Details"};    @{Num="30"; Name="Memory Pressure Diagnostics"}
                @{Num="31"; Name="Batch VM Cleanup"};          @{Num="32"; Name="VM Migration Pre-Flight"}
                @{Num="33"; Name="Logged-On Users"}
            )
            $matched = @($opsItems | Where-Object { $_.Name -match [regex]::Escape($searchTerm) })
            Write-OutputColor "" -color "Info"
            if ($matched.Count -eq 0) {
                Write-OutputColor "  No matches for '$searchTerm'" -color "Warning"
            } else {
                Write-OutputColor "  Results for '$searchTerm':" -color "Info"
                foreach ($m in $matched) { Write-OutputColor "  [$($m.Num)] $($m.Name)" -color "Success" }
            }
            Write-OutputColor "" -color "Info"
            $choice = Read-Host "  Select or Enter to go back"
            if ([string]::IsNullOrWhiteSpace($choice)) { continue }
            $navResult = Test-NavigationCommand -UserInput $choice
            if ($navResult.ShouldReturn) { return }
        }

        switch ($choice) {
            "1" {
                Show-VMCheckpointManagement -ComputerName $ComputerName -Credential $Credential
            }
            "2" {
                Show-VMExportImportMenu -ComputerName $ComputerName -Credential $Credential
            }
            "3" {
                Show-ClusterDashboard
                Write-PressEnter
            }
            "4" {
                Show-ClusterOperationsMenu
            }
            "5" {
                Invoke-RemotePSSession
            }
            "6" {
                Invoke-RemoteHealthCheck
            }
            "7" {
                Invoke-RemoteServiceManager
            }
            "8" {
                Export-HTMLHealthReport
                Write-PressEnter
            }
            "9" {
                Export-HTMLReadinessReport
                Write-PressEnter
            }
            "10" {
                Export-ProfileComparisonHTML
                Write-PressEnter
            }
            "11" {
                Show-NetworkDiagnostics
            }
            "12" {
                Show-DriftDetectionMenu
            }
            "13" {
                $path = Save-PerformanceSnapshot
                if ($path) {
                    Write-OutputColor "  Snapshot saved: $path" -color "Success"
                }
                Write-PressEnter
            }
            "14" {
                Export-HTMLTrendReport
                Write-PressEnter
            }
            "15" {
                Write-OutputColor "  Interval (minutes, default 5):" -color "Info"
                $interval = Read-Host "  "
                $navResult = Test-NavigationCommand -UserInput $interval
                if ($navResult.ShouldReturn) { continue }
                if ([string]::IsNullOrWhiteSpace($interval)) { $interval = "5" }
                $intervalInt = 0
                if ($interval -notmatch '^\d+$' -or -not [int]::TryParse($interval, [ref]$intervalInt) -or $intervalInt -eq 0) {
                    Write-OutputColor "  Invalid interval (must be 1 or greater)." -color "Error"
                    Write-PressEnter
                    continue
                }
                Write-OutputColor "  Duration (minutes, default 60):" -color "Info"
                $duration = Read-Host "  "
                $navResult = Test-NavigationCommand -UserInput $duration
                if ($navResult.ShouldReturn) { continue }
                if ([string]::IsNullOrWhiteSpace($duration)) { $duration = "60" }
                $durationInt = 0
                if ($duration -notmatch '^\d+$' -or -not [int]::TryParse($duration, [ref]$durationInt)) {
                    Write-OutputColor "  Invalid duration." -color "Error"
                    Write-PressEnter
                    continue
                }
                Start-MetricCollection -IntervalMinutes $intervalInt -DurationMinutes $durationInt
                Write-PressEnter
            }
            "16" {
                Show-ScheduledTaskViewer
                Write-PressEnter
            }
            "17" {
                Show-SMBShareAudit
                Write-PressEnter
            }
            "18" {
                Show-InstalledSoftware
            }
            "19" {
                Show-CertificateExpiryCheck
                Write-PressEnter
            }
            "20" {
                Show-VSSWriterStatus
                Write-PressEnter
            }
            "21" {
                Show-EventLogAlerts
                Write-PressEnter
            }
            "22" {
                Show-UptimeRebootHistory
                Write-PressEnter
            }
            "23" {
                Show-DriverHealthCheck
                Write-PressEnter
            }
            "24" {
                Show-DiskSpaceAnalyzer
                Write-PressEnter
            }
            "25" {
                Show-WindowsUpdateStatus
                Write-PressEnter
            }
            "26" {
                Show-ListeningPorts
                Write-PressEnter
            }
            "27" {
                Show-ScheduledTaskOverview
                Write-PressEnter
            }
            "28" {
                Show-FirewallRuleSummary
                Write-PressEnter
            }
            "29" {
                Show-RebootPendingDetails
                Write-PressEnter
            }
            "30" {
                Show-MemoryDiagnostics
                Write-PressEnter
            }
            "31" {
                Remove-BatchVMs
                Write-PressEnter
            }
            "32" {
                Test-VMMigrationReadiness
                Write-PressEnter
            }
            "33" {
                Show-LoggedOnUsers
                Write-PressEnter
            }
            "b" { return }
            "B" { return }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-33, [/] to search, or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

function Invoke-RemotePSSession {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       REMOTE POWERSHELL SESSION").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $target = Read-Host "  Enter remote server name or IP"
    $navResult = Test-NavigationCommand -UserInput $target
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($target)) { return }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Testing connectivity to $target ..." -color "Info"

    $testResult = Test-NetConnection -ComputerName $target -Port 5985 -WarningAction SilentlyContinue
    if (-not $testResult.TcpTestSucceeded) {
        Write-OutputColor "  WinRM port (5985) not reachable on $target" -color "Error"
        Write-OutputColor "  Ensure WinRM is enabled: Enable-PSRemoting -Force" -color "Warning"
        Write-PressEnter
        return
    }

    Write-OutputColor "  WinRM port open. Connecting..." -color "Success"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  NOTE: Type 'exit' to return to this tool." -color "Warning"
    Write-OutputColor "" -color "Info"

    try {
        $useCredential = Read-Host "  Use alternate credentials? [Y/N]"
        $navResult = Test-NavigationCommand -UserInput $useCredential
        if ($navResult.ShouldReturn) { return }
        if ($useCredential -eq 'Y' -or $useCredential -eq 'y') {
            $cred = Get-Credential -Message "Credentials for $target"
            Enter-PSSession -ComputerName $target -Credential $cred -ErrorAction Stop
        } else {
            Enter-PSSession -ComputerName $target -ErrorAction Stop
        }
    }
    catch {
        Write-OutputColor "  Connection failed: $($_.Exception.Message)" -color "Error"
        Write-PressEnter
    }
}

function Invoke-RemoteHealthCheck {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       REMOTE SERVER HEALTH CHECK").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $target = Read-Host "  Enter remote server name or IP"
    $navResult = Test-NavigationCommand -UserInput $target
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($target)) { return }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Gathering health data from $target ..." -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $health = Invoke-Command -ComputerName $target -ScriptBlock {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
            $cpu = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Measure-Object -Property LoadPercentage -Average).Average
            $totalMem = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
            $freeMem = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
            $usedMem = $totalMem - $freeMem
            $memPct = if ($totalMem -gt 0) { [math]::Round(($usedMem / $totalMem) * 100, 1) } else { 0 }
            $uptime = if ($os -and $os.LastBootUpTime) { (Get-Date) - $os.LastBootUpTime } else { [timespan]::Zero }
            $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue | ForEach-Object {
                @{
                    Drive = $_.DeviceID
                    SizeGB = [math]::Round($_.Size / 1GB, 1)
                    FreeGB = [math]::Round($_.FreeSpace / 1GB, 1)
                    UsedPct = if ($_.Size -gt 0) { [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1) } else { 0 }
                }
            }
            @{
                Hostname = $env:COMPUTERNAME
                OS = $os.Caption
                CPU = $cpu
                TotalMemGB = $totalMem
                UsedMemGB = $usedMem
                MemPct = $memPct
                Uptime = "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"
                Disks = $disks
            }
        } -ErrorAction Stop

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        $lineStr = "  REMOTE HEALTH: $($health.Hostname) ($target)"
        if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "  OS:          $($health.OS)"
        Write-MenuItem "  Uptime:      $($health.Uptime)"

        $cpuColor = if ($health.CPU -lt 70) { "Success" } elseif ($health.CPU -lt 90) { "Warning" } else { "Error" }
        $cpuLine = "  CPU:         $($health.CPU)%"
        Write-OutputColor "  │$($cpuLine.PadRight(72))│" -color $cpuColor

        $memColor = if ($health.MemPct -lt 70) { "Success" } elseif ($health.MemPct -lt 90) { "Warning" } else { "Error" }
        $memLine = "  Memory:      $($health.UsedMemGB)/$($health.TotalMemGB) GB ($($health.MemPct)%)"
        Write-OutputColor "  │$($memLine.PadRight(72))│" -color $memColor

        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  DISK USAGE".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        foreach ($d in $health.Disks) {
            $diskColor = if ($d.UsedPct -lt 70) { "Success" } elseif ($d.UsedPct -lt 90) { "Warning" } else { "Error" }
            $diskLine = "  $($d.Drive)  $($d.FreeGB) GB free / $($d.SizeGB) GB ($($d.UsedPct)% used)"
            Write-OutputColor "  │$($diskLine.PadRight(72))│" -color $diskColor
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }
    catch {
        Write-OutputColor "  Failed to connect: $($_.Exception.Message)" -color "Error"
        Write-OutputColor "  Ensure WinRM is enabled and you have permissions." -color "Warning"
    }
    Write-PressEnter
}

function Invoke-RemoteServiceManager {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                         REMOTE SERVICE MANAGER").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $target = Read-Host "  Enter remote server name or IP"
    $navResult = Test-NavigationCommand -UserInput $target
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($target)) { return }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Testing connectivity to $target ..." -color "Info"

    if (-not (Test-Connection -ComputerName $target -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
        Write-OutputColor "  Cannot reach $target — host is unreachable or offline." -color "Error"
        Write-PressEnter
        return
    }

    Write-OutputColor "  Fetching services from $target ..." -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $services = Get-Service -ComputerName $target -ErrorAction Stop |
            Where-Object { $_.Status -eq 'Running' -or $_.StartType -eq 'Automatic' } |
            Sort-Object Status, DisplayName |
            Select-Object -First 40

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        $lineStr = "  SERVICES: $target"
        if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        $header = "  Status".PadRight(12) + "Name".PadRight(22) + "Display Name"
        Write-OutputColor "  │$($header.PadRight(72))│" -color "Warning"
        Write-OutputColor "  │$("  $('─' * 70)".PadRight(72))│" -color "Info"

        foreach ($svc in $services) {
            $statusColor = if ($svc.Status -eq 'Running') { "Success" } else { "Error" }
            $displayName = if ($svc.DisplayName -and $svc.DisplayName.Length -gt 34) { $svc.DisplayName.Substring(0, 31) + "..." } elseif ($svc.DisplayName) { $svc.DisplayName } else { "(unknown)" }
            $line = "  $($svc.Status.ToString().PadRight(10))$($svc.ServiceName.PadRight(22))$displayName"
            Write-OutputColor "  │$($line.PadRight(72))│" -color $statusColor
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

        Write-OutputColor "" -color "Info"
        $svcAction = Read-Host "  Enter service name to start/stop/restart (or B to go back)"
        $navResult = Test-NavigationCommand -UserInput $svcAction
        if ($navResult.ShouldReturn) { return }
        if ([string]::IsNullOrWhiteSpace($svcAction) -or $svcAction -eq 'B' -or $svcAction -eq 'b') { return }
        if ($svcAction -match '[\*\?\[\]]') {
            Write-OutputColor "  Wildcard characters not allowed in service names." -color "Error"
            Write-PressEnter
            return
        }

        $action = Read-Host "  Action: [S]tart, [T]op, [R]estart"
        $navResult = Test-NavigationCommand -UserInput $action
        if ($navResult.ShouldReturn) { return }
        $actionName = switch ($action) {
            { $_ -eq 'S' -or $_ -eq 's' } { "start" }
            { $_ -eq 'T' -or $_ -eq 't' } { "stop" }
            { $_ -eq 'R' -or $_ -eq 'r' } { "restart" }
            default { $null }
        }
        if (-not $actionName) {
            Write-OutputColor "  Invalid action." -color "Error"
        }
        elseif (Confirm-UserAction -Message "$($actionName.Substring(0,1).ToUpper() + $actionName.Substring(1)) service '$svcAction' on $target?") {
            switch ($action) {
                { $_ -eq 'S' -or $_ -eq 's' } {
                    try {
                        Get-Service -ComputerName $target -Name $svcAction -ErrorAction Stop | Start-Service -ErrorAction Stop
                        Write-OutputColor "  Service '$svcAction' started." -color "Success"
                    }
                    catch {
                        Write-OutputColor "  Failed to start service '$svcAction': $($_.Exception.Message)" -color "Error"
                    }
                }
                { $_ -eq 'T' -or $_ -eq 't' } {
                    try {
                        Get-Service -ComputerName $target -Name $svcAction -ErrorAction Stop | Stop-Service -Force -ErrorAction Stop
                        Write-OutputColor "  Service '$svcAction' stopped." -color "Success"
                    }
                    catch {
                        Write-OutputColor "  Failed to stop service '$svcAction': $($_.Exception.Message)" -color "Error"
                    }
                }
                { $_ -eq 'R' -or $_ -eq 'r' } {
                    try {
                        Get-Service -ComputerName $target -Name $svcAction -ErrorAction Stop | Restart-Service -Force -ErrorAction Stop
                        Write-OutputColor "  Service '$svcAction' restarted." -color "Success"
                    }
                    catch {
                        Write-OutputColor "  Failed to restart service '$svcAction': $($_.Exception.Message)" -color "Error"
                    }
                }
            }
        }
    }
    catch {
        Write-OutputColor "  Failed: $($_.Exception.Message)" -color "Error"
    }
    Write-PressEnter
}

# Initialize SAN target pairs from configured iSCSI subnet
# Supports custom SANTargetPairings config (A side = even, B side = odd by convention)
function Initialize-SANTargetPairs {
    $sub = $script:iSCSISubnet

    if ($null -ne $script:SANTargetPairings -and $script:SANTargetPairings.Pairs) {
        # Custom pairings: build from SANTargetPairings config
        $script:SANTargetPairs = @()
        $pairIndex = 0
        foreach ($pair in $script:SANTargetPairings.Pairs) {
            $aLabel = "A$($pair.A)"
            $bLabel = "B$($pair.B)"
            if ($pair.ALabel) { $aLabel = $pair.ALabel }
            if ($pair.BLabel) { $bLabel = $pair.BLabel }
            $script:SANTargetPairs += @{
                Index  = $pairIndex
                Name   = $pair.Name
                A      = "$sub.$($pair.A)"
                B      = "$sub.$($pair.B)"
                ALabel = $aLabel
                BLabel = $bLabel
                Labels = "$aLabel/$bLabel"
            }
            $pairIndex++
        }
    }
    else {
        # Default: build pairs from consecutive mapping entries (A, B alternating)
        $mappings = $script:SANTargetMappings
        $script:SANTargetPairs = @()
        for ($i = 0; $i + 1 -lt $mappings.Count; $i += 2) {
            $script:SANTargetPairs += @{
                Index  = [int]($i / 2)
                A      = "$sub.$($mappings[$i].Suffix)"
                B      = "$sub.$($mappings[$i + 1].Suffix)"
                ALabel = $mappings[$i].Label
                BLabel = $mappings[$i + 1].Label
                Labels = "$($mappings[$i].Label)/$($mappings[$i + 1].Label)"
            }
        }
    }
}

# Get available company defaults files (*.defaults.json excluding defaults.json and defaults.example.json)
function Get-CompanyDefaultsFiles {
    $results = @()
    if (-not $script:ModuleRoot) { return $results }

    $files = Get-ChildItem -LiteralPath $script:ModuleRoot -Filter "*.defaults.json" -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        # Exclude defaults.json itself and defaults.example.json
        if ($f.Name -eq "defaults.json" -or $f.Name -eq "defaults.example.json") { continue }
        $name = $f.BaseName -replace '\.defaults$', ''
        if (-not $name) { continue }  # Skip files with empty extracted name
        $results += @{ Name = $name; Path = $f.FullName }
    }
    return ,$results
}

# Show interactive picker for company defaults files
function Show-CompanyDefaultsPicker {
    $files = @(Get-CompanyDefaultsFiles)
    if ($files.Count -eq 0) {
        Write-OutputColor "  No company defaults files found." -color "Warning"
        Write-OutputColor "  Place <name>.defaults.json files in the script directory." -color "Debug"
        return $null
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Available company defaults:" -color "Info"
    Write-OutputColor "" -color "Info"

    for ($i = 0; $i -lt $files.Count; $i++) {
        $marker = ""
        if ($script:CompanyDefaultsPath -and $files[$i].Path -eq $script:CompanyDefaultsPath) {
            $marker = " (current)"
        }
        Write-MenuItem "[$($i + 1)]  $($files[$i].Name)$marker"
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [S] Skip / no company defaults" -color "Info"
    Write-OutputColor "  [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return $null }

    if ("$choice".ToUpper() -eq "B") { return $null }
    if ("$choice".ToUpper() -eq "S") { return "__skip__" }

    if ($choice -match '^\d+$') {
        $idx = [int]$choice - 1
        if ($idx -ge 0 -and $idx -lt $files.Count) {
            return $files[$idx]
        }
    }

    Write-OutputColor "  Invalid selection. Enter 1-$($files.Count), S, or B." -color "Error"
    return $null
}

# Merge company defaults into a hashtable (same logic as personal defaults merge)
function Import-CompanyDefaults {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Merged,
        [Parameter(Mandatory=$true)]
        [string]$CompanyFilePath
    )

    if (-not (Test-Path -LiteralPath $CompanyFilePath)) {
        Write-OutputColor "  Warning: Company defaults file not found: $CompanyFilePath" -color "Warning"
        return
    }

    try {
        $companyData = Get-Content -LiteralPath $CompanyFilePath -Raw | ConvertFrom-Json
        foreach ($prop in $companyData.PSObject.Properties) {
            if ($prop.Name -like "_*") { continue }  # Skip metadata fields
            if ($null -ne $prop.Value -and $prop.Value -ne "") {
                $Merged[$prop.Name] = $prop.Value
            }
        }
    }
    catch {
        Write-OutputColor "  Warning: Could not read company defaults: $_" -color "Warning"
    }
}

# Import environment defaults from defaults.json (merges with built-in generics)
function Import-Defaults {

    # Reset agent installer to factory defaults before re-merge (prevents stale config from previous company)
    $script:AgentInstaller = @{
        ToolName         = "MSP"
        FolderName       = "Agents"
        FilePattern      = ".*\.exe$"
        ServiceName      = "*Agent*"
        InstallArgs      = "/s /norestart"
        InstallPaths     = @()
        SuccessExitCodes = @(0, 1641, 3010)
        TimeoutSeconds   = 300
    }
    $script:AdditionalAgents = @()
    $script:AgentInstallerCache = $null
    $script:AgentInstallerCacheTime = $null

    # Check for company defaults files
    $companyFiles = @(Get-CompanyDefaultsFiles)

    # Run first-run wizard if no defaults.json exists (skip in batch mode)
    if (-not (Test-Path -LiteralPath $script:DefaultsPath)) {
        $batchConfig = Join-Path $script:ModuleRoot "batch_config.json"
        if (-not (Test-Path -LiteralPath $batchConfig)) {
            Show-FirstRunWizard
        }
    }

    # Built-in generic defaults
    $builtinDefaults = @{
        Domain             = ""
        LocalAdminName     = "localadmin"
        LocalAdminFullName = "Local Administrator"
        SwitchName         = "LAN-SET"
        ManagementName     = "Management"
        BackupName         = "Backup"
        DNSPresets         = @{}
        FileServer = @{
            BaseURL      = ""
            ClientId     = ""
            ClientSecret = ""
            ISOsFolder   = "ISOs"
            VHDsFolder   = "VirtualHardDrives"
            AgentFolder  = "Agents"
        }
        iSCSISubnet        = "172.16.1"
        StorageBackendType = "iSCSI"
        TimeZoneRegion     = ""
    }

    # Start with built-in defaults
    $merged = $builtinDefaults.Clone()

    # Tier 2: Merge company defaults if available and not yet loaded
    # - 0 company files: skip silently (no prompt)
    # - 1 company file: auto-load silently (user placed it there intentionally)
    # - 2+ company files: auto-resolve from saved preference, or show picker
    if ($companyFiles.Count -gt 0 -and -not $script:CompanyDefaultsPath) {
        if ($companyFiles.Count -eq 1) {
            # Single company defaults file: load silently
            $script:CompanyDefaultsName = $companyFiles[0].Name
            $script:CompanyDefaultsPath = $companyFiles[0].Path
        }
        else {
            # Multiple company defaults files: try saved preference first
            $companyDefaultsResolved = $false
            if (Test-Path -LiteralPath $script:DefaultsPath) {
                try {
                    $existingDefaults = Get-Content -LiteralPath $script:DefaultsPath -Raw | ConvertFrom-Json
                    if ($existingDefaults._companyDefaults) {
                        $matchingFile = $companyFiles | Where-Object { $_.Name -eq $existingDefaults._companyDefaults } | Select-Object -First 1
                        if ($matchingFile) {
                            $script:CompanyDefaultsName = $matchingFile.Name
                            $script:CompanyDefaultsPath = $matchingFile.Path
                            $companyDefaultsResolved = $true
                        }
                    }
                } catch {
                    Write-OutputColor "  Warning: Could not read defaults.json for company defaults: $_" -color "Warning"
                }
            }
            # If not auto-resolved, show picker
            if (-not $companyDefaultsResolved) {
                Write-OutputColor "  Multiple defaults files found." -color "Info"
                $picked = Show-CompanyDefaultsPicker
                if ($null -ne $picked -and $picked -ne "__skip__") {
                    $script:CompanyDefaultsName = $picked.Name
                    $script:CompanyDefaultsPath = $picked.Path
                }
            }
        }
    }

    if ($script:CompanyDefaultsPath) {
        Import-CompanyDefaults -Merged $merged -CompanyFilePath $script:CompanyDefaultsPath
    }

    # Tier 3: Merge personal defaults from file if it exists
    if (Test-Path -LiteralPath $script:DefaultsPath) {
        try {
            $fileDefaults = Get-Content -LiteralPath $script:DefaultsPath -Raw | ConvertFrom-Json
            foreach ($prop in $fileDefaults.PSObject.Properties) {
                if ($prop.Name -like "_*") { continue }  # Skip metadata fields
                # When company defaults are active, don't let personal defaults override agent config
                # (old defaults.json files may have stale AgentInstaller with ToolName="MSP")
                if ($script:CompanyDefaultsPath -and $prop.Name -in @('AgentInstaller', 'AdditionalAgents')) { continue }
                if ($null -ne $prop.Value -and $prop.Value -ne "") {
                    # Deep-merge nested objects (FileServer, AgentInstaller, etc.)
                    # so empty sub-properties in personal defaults don't overwrite
                    # non-empty values from company defaults
                    if ($prop.Value -is [PSCustomObject] -and $merged.ContainsKey($prop.Name) -and $null -ne $merged[$prop.Name]) {
                        $existing = $merged[$prop.Name]
                        foreach ($subProp in $prop.Value.PSObject.Properties) {
                            if ($null -ne $subProp.Value -and $subProp.Value -ne "") {
                                if ($existing -is [hashtable]) {
                                    $existing[$subProp.Name] = $subProp.Value
                                } elseif ($existing -is [PSCustomObject]) {
                                    $existing | Add-Member -NotePropertyName $subProp.Name -NotePropertyValue $subProp.Value -Force
                                }
                            }
                        }
                    }
                    else {
                        $merged[$prop.Name] = $prop.Value
                    }
                }
            }
        }
        catch {
            Write-RackStackError -Code "RS-1002" -Detail "$_"
        }
    }

    # Apply tool identity from defaults
    if ($merged.ToolName) {
        $script:ToolName = $merged.ToolName
    }
    if ($merged.ToolFullName) {
        $script:ToolFullName = $merged.ToolFullName
    }
    if ($merged.SupportContact) {
        $script:SupportContact = $merged.SupportContact
    }

    # Derive config directory name and re-derive dependent paths
    $script:ConfigDirName = "$($script:ToolName)config".ToLower()
    $script:AppConfigDir = "$env:USERPROFILE\.$($script:ConfigDirName)"
    $script:FavoritesPath = "$script:AppConfigDir\favorites.json"
    $script:HistoryPath = "$script:AppConfigDir\history.json"
    $script:SessionStatePath = "$script:AppConfigDir\session.json"

    # Apply merged values to script variables
    $script:domain = $merged.Domain
    $domain = $merged.Domain
    $script:localadminaccountname = $merged.LocalAdminName
    $localadminaccountname = $merged.LocalAdminName
    $script:FullName = $merged.LocalAdminFullName
    $FullName = $merged.LocalAdminFullName
    $script:SwitchName = $merged.SwitchName
    $SwitchName = $merged.SwitchName
    $script:ManagementName = $merged.ManagementName
    $ManagementName = $merged.ManagementName
    $script:BackupName = $merged.BackupName
    $BackupName = $merged.BackupName
    $script:iSCSISubnet = $merged.iSCSISubnet

    # Override storage backend type
    if ($merged.StorageBackendType -and $merged.StorageBackendType -in $script:ValidStorageBackends) {
        $script:StorageBackendType = $merged.StorageBackendType
    }

    # Override auto-update flag
    if ($null -ne $merged.AutoUpdate) {
        $script:AutoUpdate = [bool]$merged.AutoUpdate
    }

    # Override temp path
    if ($merged.TempPath) {
        $script:TempPath = $merged.TempPath
    }

    # Override dashboard color thresholds (CPU/memory/disk — used by the main menu dashboard in 48-MenuDisplay.ps1)
    if ($null -ne $merged.DashboardWarningPercent) {
        $w = [int]$merged.DashboardWarningPercent
        if ($w -ge 1 -and $w -le 100) { $script:DashboardWarningPercent = $w }
    }
    if ($null -ne $merged.DashboardCriticalPercent) {
        $c = [int]$merged.DashboardCriticalPercent
        if ($c -ge 1 -and $c -le 100) { $script:DashboardCriticalPercent = $c }
    }

    # Override timezone region
    if ($merged.TimeZoneRegion) {
        $script:TimeZoneRegion = $merged.TimeZoneRegion
    }

    # Override SAN target mappings
    if ($merged.SANTargetMappings -and $merged.SANTargetMappings -is [array]) {
        $script:SANTargetMappings = @()
        foreach ($mapping in $merged.SANTargetMappings) {
            if ($mapping -is [PSCustomObject]) {
                $script:SANTargetMappings += @{ Suffix = [int]$mapping.Suffix; Label = $mapping.Label }
            } else {
                $script:SANTargetMappings += $mapping
            }
        }
    }

    # Override SAN target pairings (custom A/B pair definitions and host assignments)
    if ($merged.SANTargetPairings -and $merged.SANTargetPairings -is [PSCustomObject]) {
        $pairings = @{}
        if ($merged.SANTargetPairings.Pairs -and $merged.SANTargetPairings.Pairs -is [array]) {
            $pairings.Pairs = @()
            foreach ($pair in $merged.SANTargetPairings.Pairs) {
                $p = @{ Name = $pair.Name; A = [int]$pair.A; B = [int]$pair.B }
                if ($pair.ALabel) { $p.ALabel = $pair.ALabel }
                if ($pair.BLabel) { $p.BLabel = $pair.BLabel }
                $pairings.Pairs += $p
            }
        }
        if ($merged.SANTargetPairings.HostAssignments -and $merged.SANTargetPairings.HostAssignments -is [array]) {
            $pairings.HostAssignments = @()
            foreach ($assignment in $merged.SANTargetPairings.HostAssignments) {
                $pairings.HostAssignments += @{
                    HostMod      = [int]$assignment.HostMod
                    PrimaryPair  = $assignment.PrimaryPair
                    RetryOrder   = @($assignment.RetryOrder)
                }
            }
        }
        $cycleSize = 4
        if ($merged.SANTargetPairings.CycleSize) {
            $cycleSize = [int]$merged.SANTargetPairings.CycleSize
        }
        $pairings.CycleSize = $cycleSize
        $script:SANTargetPairings = $pairings
    }

    # Override Defender exclusion paths
    if ($merged.DefenderExclusionPaths -and $merged.DefenderExclusionPaths -is [array]) {
        $script:DefenderExclusionPaths = @($merged.DefenderExclusionPaths)
    }
    if ($merged.DefenderCommonVMPaths -and $merged.DefenderCommonVMPaths -is [array]) {
        $script:DefenderCommonVMPaths = @($merged.DefenderCommonVMPaths)
    } else {
        # Auto-generate from current host drive if not overridden
        Update-DefenderVMPaths
    }

    # Override storage paths
    if ($merged.StoragePaths) {
        $sp = $merged.StoragePaths
        if ($sp -is [PSCustomObject]) {
            if ($sp.HostVMStoragePath)    { $script:HostVMStoragePath = $sp.HostVMStoragePath }
            if ($sp.HostISOPath)          { $script:HostISOPath = $sp.HostISOPath }
            if ($sp.ClusterISOPath)       { $script:ClusterISOPath = $sp.ClusterISOPath }
            if ($sp.VHDCachePath)         { $script:VHDCachePath = $sp.VHDCachePath }
            if ($sp.ClusterVHDCachePath)  { $script:ClusterVHDCachePath = $sp.ClusterVHDCachePath }
            if ($sp.SelectedHostDrive)    { $script:SelectedHostDrive = $sp.SelectedHostDrive }
        }
    }

    # Override agent installer config
    if ($merged.AgentInstaller) {
        $ai = $merged.AgentInstaller
        if ($ai -is [PSCustomObject]) {
            foreach ($prop in $ai.PSObject.Properties) {
                if ($prop.Name -like '_*') { continue }
                if ($prop.Name -eq 'SuccessExitCodes' -and $prop.Value -is [array]) {
                    $script:AgentInstaller[$prop.Name] = @($prop.Value | ForEach-Object { [int]$_ })
                }
                elseif ($prop.Name -eq 'InstallPaths' -and $prop.Value -is [array]) {
                    $script:AgentInstaller[$prop.Name] = @($prop.Value)
                }
                elseif ($prop.Name -eq 'TimeoutSeconds') {
                    $script:AgentInstaller[$prop.Name] = [int]$prop.Value
                }
                else {
                    $script:AgentInstaller[$prop.Name] = $prop.Value
                }
            }
        }
    }

    # Override additional agents (v1.8.0)
    if ($merged.AdditionalAgents -and $merged.AdditionalAgents -is [array]) {
        $script:AdditionalAgents = @()
        foreach ($agentDef in $merged.AdditionalAgents) {
            if ($agentDef -is [PSCustomObject]) {
                $agentConfig = @{}
                foreach ($prop in $agentDef.PSObject.Properties) {
                    if ($prop.Name -like '_*') { continue }
                    if ($prop.Name -eq 'SuccessExitCodes' -and $prop.Value -is [array]) {
                        $agentConfig[$prop.Name] = @($prop.Value | ForEach-Object { [int]$_ })
                    }
                    elseif ($prop.Name -eq 'InstallPaths' -and $prop.Value -is [array]) {
                        $agentConfig[$prop.Name] = @($prop.Value)
                    }
                    elseif ($prop.Name -eq 'TimeoutSeconds') {
                        $agentConfig[$prop.Name] = [int]$prop.Value
                    }
                    else {
                        $agentConfig[$prop.Name] = $prop.Value
                    }
                }
                $script:AdditionalAgents += $agentConfig
            }
        }
    }

    # Merge custom DNS presets into the built-in presets
    $customDNS = $merged.DNSPresets
    if ($customDNS) {
        if ($customDNS -is [PSCustomObject]) {
            foreach ($prop in $customDNS.PSObject.Properties) {
                $script:DNSPresets[$prop.Name] = @($prop.Value)
            }
        }
        elseif ($customDNS -is [hashtable]) {
            foreach ($key in $customDNS.Keys) {
                $script:DNSPresets[$key] = @($customDNS[$key])
            }
        }
    }

    # Update FileServer settings
    $acCloud = $merged.FileServer
    if ($acCloud) {
        if ($acCloud -is [PSCustomObject]) {
            foreach ($prop in $acCloud.PSObject.Properties) {
                $script:FileServer[$prop.Name] = $prop.Value
            }
        }
        elseif ($acCloud -is [hashtable]) {
            foreach ($key in $acCloud.Keys) {
                $script:FileServer[$key] = $acCloud[$key]
            }
        }
        # Backward compat: remap old KaseyaFolder key to AgentFolder (always overwrite)
        if ($script:FileServer.ContainsKey("KaseyaFolder")) {
            $script:FileServer["AgentFolder"] = $script:FileServer["KaseyaFolder"]
            $script:FileServer.Remove("KaseyaFolder")
        }
    }

    # Import custom license keys from merged defaults (supports company + personal)
    $script:CustomKMSKeys = @{}
    $script:CustomAVMAKeys = @{}
    $mergedKMS = $merged["CustomKMSKeys"]
    if ($mergedKMS -and $mergedKMS -is [PSCustomObject]) {
        foreach ($verProp in $mergedKMS.PSObject.Properties) {
            $editionHash = @{}
            foreach ($edProp in $verProp.Value.PSObject.Properties) {
                $editionHash[$edProp.Name] = $edProp.Value
            }
            $script:CustomKMSKeys[$verProp.Name] = $editionHash
        }
    }
    $mergedAVMA = $merged["CustomAVMAKeys"]
    if ($mergedAVMA -and $mergedAVMA -is [PSCustomObject]) {
        foreach ($verProp in $mergedAVMA.PSObject.Properties) {
            $editionHash = @{}
            foreach ($edProp in $verProp.Value.PSObject.Properties) {
                $editionHash[$edProp.Name] = $edProp.Value
            }
            $script:CustomAVMAKeys[$verProp.Name] = $editionHash
        }
    }

    # Import VM naming convention from merged defaults
    $mergedVMNaming = $merged["VMNaming"]
    if ($mergedVMNaming -and $mergedVMNaming -is [PSCustomObject]) {
        foreach ($prop in $mergedVMNaming.PSObject.Properties) {
            if ($prop.Name -like '_*') { continue }
            $script:VMNaming[$prop.Name] = $prop.Value
        }
    }

    # Import custom VM templates and role templates from file (complex nested structures)
    if ((Test-Path -LiteralPath $script:DefaultsPath)) {
        try {
            $fileData = Get-Content -LiteralPath $script:DefaultsPath -Raw | ConvertFrom-Json

            # Import custom VM templates (merge with built-in StandardVMTemplates)
            if ($null -eq $script:BuiltInVMTemplates) {
                # Snapshot built-in templates on first call (deep clone)
                $script:BuiltInVMTemplates = @{}
                foreach ($k in $script:StandardVMTemplates.Keys) {
                    $clone = @{}
                    foreach ($field in $script:StandardVMTemplates[$k].Keys) {
                        $val = $script:StandardVMTemplates[$k][$field]
                        if ($val -is [array]) {
                            $arrClone = @()
                            foreach ($item in $val) {
                                if ($item -is [hashtable]) {
                                    $arrClone += ($item.Clone())
                                } else {
                                    $arrClone += $item
                                }
                            }
                            $clone[$field] = $arrClone
                        } else {
                            $clone[$field] = $val
                        }
                    }
                    $script:BuiltInVMTemplates[$k] = $clone
                }
            } else {
                # Restore built-in templates before re-merging
                foreach ($k in $script:BuiltInVMTemplates.Keys) {
                    $clone = @{}
                    foreach ($field in $script:BuiltInVMTemplates[$k].Keys) {
                        $val = $script:BuiltInVMTemplates[$k][$field]
                        if ($val -is [array]) {
                            $arrClone = @()
                            foreach ($item in $val) {
                                if ($item -is [hashtable]) {
                                    $arrClone += ($item.Clone())
                                } else {
                                    $arrClone += $item
                                }
                            }
                            $clone[$field] = $arrClone
                        } else {
                            $clone[$field] = $val
                        }
                    }
                    $script:StandardVMTemplates[$k] = $clone
                }
            }

            $script:CustomVMTemplates = @{}
            if ($fileData.CustomVMTemplates) {
                foreach ($tplProp in $fileData.CustomVMTemplates.PSObject.Properties) {
                    if ($tplProp.Name -like '_*') { continue }
                    $tplData = @{}
                    foreach ($fp in $tplProp.Value.PSObject.Properties) {
                        if ($fp.Name -eq 'Disks' -and $fp.Value -is [array]) {
                            # Convert PSCustomObject[] to hashtable[]
                            $diskArr = @()
                            foreach ($diskObj in $fp.Value) {
                                $diskHash = @{}
                                foreach ($dp in $diskObj.PSObject.Properties) {
                                    $diskHash[$dp.Name] = $dp.Value
                                }
                                $diskArr += $diskHash
                            }
                            $tplData[$fp.Name] = $diskArr
                        } else {
                            $tplData[$fp.Name] = $fp.Value
                        }
                    }
                    $script:CustomVMTemplates[$tplProp.Name] = $tplData

                    # Merge into StandardVMTemplates
                    if ($script:StandardVMTemplates.ContainsKey($tplProp.Name)) {
                        # Existing template: field-level merge (partial override)
                        foreach ($field in $tplData.Keys) {
                            $script:StandardVMTemplates[$tplProp.Name][$field] = $tplData[$field]
                        }
                    } else {
                        # New template: add with defaults for optional fields
                        $newTpl = $tplData.Clone()
                        if (-not $newTpl.ContainsKey('SortOrder'))        { $newTpl['SortOrder'] = 100 }
                        if (-not $newTpl.ContainsKey('GuestServices'))    { $newTpl['GuestServices'] = $true }
                        if (-not $newTpl.ContainsKey('TimeSyncWithHost')) { $newTpl['TimeSyncWithHost'] = $true }
                        if (-not $newTpl.ContainsKey('Notes'))           { $newTpl['Notes'] = "" }
                        $script:StandardVMTemplates[$tplProp.Name] = $newTpl
                    }
                }
            }

            # Import custom role templates (merge with built-in ServerRoleTemplates)
            $script:CustomRoleTemplates = @{}
            if ($fileData.CustomRoleTemplates) {
                foreach ($tplProp in $fileData.CustomRoleTemplates.PSObject.Properties) {
                    if ($tplProp.Name -like '_*') { continue }
                    $tplData = @{}
                    foreach ($fp in $tplProp.Value.PSObject.Properties) {
                        if ($fp.Name -eq 'Features' -and $fp.Value -is [array]) {
                            $tplData[$fp.Name] = @($fp.Value)
                        } else {
                            $tplData[$fp.Name] = $fp.Value
                        }
                    }
                    # Validate custom template before adding
                    if (Test-CustomRoleTemplate -Template $tplData -TemplateName $tplProp.Name) {
                        $script:CustomRoleTemplates[$tplProp.Name] = $tplData
                    }
                }
            }

            # Import custom VM defaults (for non-template VMs)
            $script:CustomVMDefaults = @{}
            if ($fileData.CustomVMDefaults) {
                foreach ($prop in $fileData.CustomVMDefaults.PSObject.Properties) {
                    if ($prop.Name -like '_*') { continue }
                    $script:CustomVMDefaults[$prop.Name] = $prop.Value
                }
            }
        }
        catch {
            Write-OutputColor "  Warning: Could not load VM defaults from defaults.json: $($_.Exception.Message)" -color "Warning"
        }
    }

    # Override centralized timeouts
    if ($null -ne $merged.Timeouts) {
        $timeoutSource = $merged.Timeouts
        if ($timeoutSource -is [PSCustomObject]) {
            foreach ($key in $timeoutSource.PSObject.Properties.Name) {
                if ($script:Timeouts.ContainsKey($key)) {
                    $script:Timeouts[$key] = [int]$timeoutSource.$key
                }
            }
        }
        elseif ($timeoutSource -is [hashtable]) {
            foreach ($key in $timeoutSource.Keys) {
                if ($script:Timeouts.ContainsKey($key)) {
                    $script:Timeouts[$key] = [int]$timeoutSource[$key]
                }
            }
        }
    }

    # Apply CLI defaults (only when CLI flags weren't explicitly provided)
    if ($null -ne $merged.CLIDefaults) {
        $cliDef = $merged.CLIDefaults
        if ($cliDef.OutputFormat -and $script:CLIOutputFormat -eq 'Console' -and -not $OutputFormat) {
            $script:CLIOutputFormat = "$($cliDef.OutputFormat)"
        }
        if ($cliDef.DefaultTier -and $script:CLIProfile -eq 'Standard' -and -not $Tier) {
            $script:CLIProfile = "$($cliDef.DefaultTier)"
        }
        if ($cliDef.QuietMode -eq $true -and -not $script:CLIQuiet) {
            $script:CLIQuiet = $true
        }
    }

    # Rebuild SAN target pairs from configured subnet
    Initialize-SANTargetPairs
}

# Export current defaults to defaults.json (includes custom license keys)
function Export-Defaults {

    # Gather custom DNS presets (exclude built-in ones)
    $builtinDNSNames = @("Google DNS", "Cloudflare", "OpenDNS", "Quad9")
    $customDNS = @{}
    foreach ($key in $script:DNSPresets.Keys) {
        if ($key -notin $builtinDNSNames) {
            $customDNS[$key] = $script:DNSPresets[$key]
        }
    }

    $defaults = [ordered]@{
        "_description"       = "Environment defaults for $($script:ToolFullName)"
        "_companyDefaults"   = if ($script:CompanyDefaultsName) { $script:CompanyDefaultsName } else { $null }
        ToolName             = $script:ToolName
        ToolFullName         = $script:ToolFullName
        SupportContact       = $script:SupportContact
        Domain               = if ($script:domain) { $script:domain } else { $domain }
        LocalAdminName       = if ($script:localadminaccountname) { $script:localadminaccountname } else { $localadminaccountname }
        LocalAdminFullName   = if ($script:FullName) { $script:FullName } else { $FullName }
        AutoUpdate           = $script:AutoUpdate
        TempPath             = $script:TempPath
        SwitchName           = if ($script:SwitchName) { $script:SwitchName } else { $SwitchName }
        ManagementName       = if ($script:ManagementName) { $script:ManagementName } else { $ManagementName }
        BackupName           = if ($script:BackupName) { $script:BackupName } else { $BackupName }
        DNSPresets           = $customDNS
        FileServer          = $script:FileServer
        iSCSISubnet          = $script:iSCSISubnet
        SANTargetMappings    = $script:SANTargetMappings
        StorageBackendType   = $script:StorageBackendType
        StoragePaths         = [ordered]@{
            HostVMStoragePath   = $script:HostVMStoragePath
            HostISOPath         = $script:HostISOPath
            ClusterISOPath      = $script:ClusterISOPath
            VHDCachePath        = $script:VHDCachePath
            ClusterVHDCachePath = $script:ClusterVHDCachePath
        }
        AgentInstaller       = $script:AgentInstaller
        VMNaming             = $script:VMNaming
        DefenderExclusionPaths  = $script:DefenderExclusionPaths
        DefenderCommonVMPaths   = $script:DefenderCommonVMPaths
        CustomKMSKeys        = $script:CustomKMSKeys
        CustomAVMAKeys       = $script:CustomAVMAKeys
        CustomVMTemplates    = $script:CustomVMTemplates
        CustomVMDefaults     = $script:CustomVMDefaults
        CustomRoleTemplates  = $script:CustomRoleTemplates
        TimeZoneRegion       = $script:TimeZoneRegion
    }

    # Include SANTargetPairings only if custom pairings are configured
    if ($script:SANTargetPairings) {
        $defaults["SANTargetPairings"] = $script:SANTargetPairings
    }

    try {
        $tempPath = "$($script:DefaultsPath).tmp"
        $defaults | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $tempPath -Encoding UTF8 -Force -ErrorAction Stop
        Move-Item -LiteralPath $tempPath -Destination $script:DefaultsPath -Force -ErrorAction Stop
        return $true
    }
    catch {
        Remove-Item -LiteralPath "$($script:DefaultsPath).tmp" -Force -ErrorAction SilentlyContinue
        Write-OutputColor "  Failed to save defaults: $_" -color "Error"
        return $false
    }
}

# Import-CustomLicenses is handled by Import-Defaults (licenses stored in defaults.json)
# This wrapper exists for backward compatibility
function Import-CustomLicenses {
    # License keys are loaded as part of Import-Defaults from defaults.json
    # No separate file needed
}

# Export-CustomLicenses saves via Export-Defaults (licenses stored in defaults.json)
function Export-CustomLicenses {
    Export-Defaults
}

# Settings menu: Edit Environment Defaults
function Show-EditDefaults {
    while ($true) {
        if ($global:ReturnToMainMenu) { return }
        Clear-Host

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                      ENVIRONMENT DEFAULTS").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        # Gather custom DNS presets
        $builtinDNSNames = @("Google DNS", "Cloudflare", "OpenDNS", "Quad9")
        $customDNSCount = 0
        foreach ($key in $script:DNSPresets.Keys) {
            if ($key -notin $builtinDNSNames) { $customDNSCount++ }
        }

        $domainDisplay = if ($domain) { $domain } else { "(not set)" }
        $acDisplay = if ($script:FileServer.BaseURL) { "Configured" } else { "(not set)" }

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  CURRENT VALUES".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  Domain" -Status $domainDisplay -StatusColor "Info"
        Write-MenuItem "[2]  Local Admin Name" -Status $localadminaccountname -StatusColor "Info"
        Write-MenuItem "[3]  Local Admin Full Name" -Status $FullName -StatusColor "Info"
        Write-MenuItem "[4]  Switch/NIC Names" -Status "$SwitchName / $ManagementName / $BackupName" -StatusColor "Info"
        Write-MenuItem "[5]  Custom DNS Presets" -Status "$customDNSCount custom preset(s)" -StatusColor "Info"
        Write-MenuItem "[6]  FileServer Settings" -Status $acDisplay -StatusColor "Info"
        Write-MenuItem "[7]  iSCSI Subnet" -Status "$($script:iSCSISubnet).x" -StatusColor "Info"
        Write-MenuItem "[8]  Storage Backend" -Status $script:StorageBackendType -StatusColor "Info"
        $companyDisplay = if ($script:CompanyDefaultsName) { $script:CompanyDefaultsName } else { "(none)" }
        Write-MenuItem "[9]  Company Defaults" -Status $companyDisplay -StatusColor "Info"
        $autoUpdateDisplay = if ($script:AutoUpdate) { "On" } else { "Off" }
        Write-MenuItem "[10] Auto-Update" -Status $autoUpdateDisplay -StatusColor "Info"
        Write-MenuItem "[11] Temp Path" -Status $script:TempPath -StatusColor "Info"
        $tzRegionDisplay = if ($script:TimeZoneRegion) { $script:TimeZoneRegion } else { "(show picker)" }
        Write-MenuItem "[12] Timezone Region" -Status $tzRegionDisplay -StatusColor "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  [S] Save to defaults.json" -color "Info"
        Write-OutputColor "  [R] Reset to generic defaults" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) {
            if (Invoke-NavigationAction -NavResult $navResult) { return }
        }

        switch ("$choice".ToUpper()) {
            "1" {
                Write-OutputColor "  Enter domain name (e.g., contoso.local) or leave empty to clear:" -color "Info"
                $val = Read-Host
                $domain = $val
                $script:domain = $val
            }
            "2" {
                Write-OutputColor "  Enter local admin account name:" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) {
                    $localadminaccountname = $val
                    $script:localadminaccountname = $val
                }
            }
            "3" {
                Write-OutputColor "  Enter local admin full name:" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) {
                    $FullName = $val
                    $script:FullName = $val
                }
            }
            "4" {
                Write-OutputColor "  Enter SET name (current: $SwitchName):" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) { $SwitchName = $val; $script:SwitchName = $val }

                Write-OutputColor "  Enter Management NIC name (current: $ManagementName):" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) { $ManagementName = $val; $script:ManagementName = $val }

                Write-OutputColor "  Enter Backup NIC name (current: $BackupName):" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) { $BackupName = $val; $script:BackupName = $val }
            }
            "5" {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Current DNS Presets:" -color "Info"
                $presetIndex = 1
                foreach ($key in $script:DNSPresets.Keys) {
                    $marker = if ($key -in $builtinDNSNames) { " (built-in)" } else { " (custom)" }
                    Write-OutputColor "  $presetIndex. $key ($($script:DNSPresets[$key] -join ', '))$marker" -color "Info"
                    $presetIndex++
                }
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  [A] Add custom DNS preset  [D] Delete custom preset  [B] ◄ Back" -color "Info"
                $dnsChoice = Read-Host "  Select"
                $navResult = Test-NavigationCommand -UserInput $dnsChoice
                if ($navResult.ShouldReturn) { return }

                switch ("$dnsChoice".ToUpper()) {
                    "A" {
                        Write-OutputColor "  Enter preset name (e.g., 'Company DNS'):" -color "Info"
                        $presetName = Read-Host
                        if (-not [string]::IsNullOrWhiteSpace($presetName)) {
                            Write-OutputColor "  Enter primary DNS server IP:" -color "Info"
                            $dns1 = Read-Host
                            if (-not (Test-ValidIPAddress -IPAddress $dns1)) {
                                Write-OutputColor "  Invalid IP address." -color "Error"
                                Start-Sleep -Seconds 1
                            }
                            else {
                                Write-OutputColor "  Enter secondary DNS server IP (or leave empty):" -color "Info"
                                $dns2 = Read-Host
                                $servers = @($dns1)
                                if (-not [string]::IsNullOrWhiteSpace($dns2)) {
                                    if (Test-ValidIPAddress -IPAddress $dns2) {
                                        $servers += $dns2
                                    }
                                    else {
                                        Write-OutputColor "  Invalid secondary IP, skipping." -color "Warning"
                                    }
                                }
                                $script:DNSPresets[$presetName] = $servers
                                Write-OutputColor "  Added DNS preset '$presetName'." -color "Success"
                            }
                        }
                    }
                    "D" {
                        Write-OutputColor "  Enter name of custom preset to delete:" -color "Info"
                        $delName = Read-Host
                        if ($delName -in $builtinDNSNames) {
                            Write-OutputColor "  Cannot delete built-in presets." -color "Error"
                        }
                        elseif ($script:DNSPresets.Contains($delName)) {
                            $script:DNSPresets.Remove($delName)
                            Write-OutputColor "  Deleted '$delName'." -color "Success"
                        }
                        else {
                            Write-OutputColor "  Preset not found." -color "Error"
                        }
                    }
                    default {
                        Write-OutputColor "  Invalid choice. Enter A, D, or B." -color "Error"
                    }
                }
                Start-Sleep -Seconds 1
            }
            "6" {
                Write-OutputColor "  Enter FileServer base URL:" -color "Info"
                Write-OutputColor "  Leave empty to disable cloud features." -color "Debug"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.BaseURL = $val }
                elseif ($val -eq "") { $script:FileServer.BaseURL = "" }

                Write-OutputColor "  Enter CF-Access-Client-Id:" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.ClientId = $val }

                Write-OutputColor "  Enter CF-Access-Client-Secret:" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.ClientSecret = $val }

                Write-OutputColor "  Enter ISOs subfolder name (default: ISOs):" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.ISOsFolder = $val }

                Write-OutputColor "  Enter VHDs subfolder name (default: VirtualHardDrives):" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.VHDsFolder = $val }

                Write-OutputColor "  Enter agent installer subfolder name (default: Agents):" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.AgentFolder = $val }
            }
            "7" {
                Write-OutputColor "  Enter iSCSI subnet (first 3 octets, e.g., 172.16.1):" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) {
                    $octets = $val -split '\.'
                    $validSubnet = ($octets.Count -eq 3) -and ($octets | ForEach-Object { $_ -match '^\d{1,3}$' -and [int]$_ -ge 0 -and [int]$_ -le 255 }) -notcontains $false
                    if ($validSubnet) {
                        $script:iSCSISubnet = $val
                        Initialize-SANTargetPairs
                        Write-OutputColor "  iSCSI subnet set to $val.x" -color "Success"
                    }
                    else {
                        Write-OutputColor "  Invalid subnet format. Expected 3 octets (e.g., 172.16.1)." -color "Error"
                        Start-Sleep -Seconds 1
                    }
                }
            }
            "8" {
                Set-StorageBackendType
            }
            "9" {
                $companyFiles = @(Get-CompanyDefaultsFiles)
                if ($companyFiles.Count -eq 0) {
                    Write-OutputColor "  No company defaults files found." -color "Warning"
                    Write-OutputColor "  Place <name>.defaults.json files in the script directory." -color "Debug"
                    Start-Sleep -Seconds 1
                }
                else {
                    $picked = Show-CompanyDefaultsPicker
                    if ($null -ne $picked -and $picked -ne "__skip__") {
                        $script:CompanyDefaultsName = $picked.Name
                        $script:CompanyDefaultsPath = $picked.Path
                        Import-Defaults
                        Write-OutputColor "  Company defaults loaded: $($picked.Name)" -color "Success"
                        Start-Sleep -Seconds 1
                    }
                    elseif ($picked -eq "__skip__") {
                        $script:CompanyDefaultsName = $null
                        $script:CompanyDefaultsPath = $null
                        Import-Defaults
                        Write-OutputColor "  Company defaults cleared." -color "Info"
                        Start-Sleep -Seconds 1
                    }
                }
            }
            "10" {
                $script:AutoUpdate = -not $script:AutoUpdate
                $stateWord = if ($script:AutoUpdate) { "enabled" } else { "disabled" }
                Write-OutputColor "  Auto-update $stateWord." -color "Success"
                Start-Sleep -Seconds 1
            }
            "11" {
                Write-OutputColor "  Enter temp path (current: $($script:TempPath)):" -color "Info"
                $val = Read-Host "  Path"
                if (-not [string]::IsNullOrWhiteSpace($val)) { $val = $val.Trim('"') }
                if (-not [string]::IsNullOrWhiteSpace($val)) {
                    if (-not (Test-Path $val -IsValid)) {
                        Write-OutputColor "  Invalid path format." -color "Error"
                    } elseif ($val -match '^\\\\\w') {
                        Write-OutputColor "  Warning: UNC path — transcripts and exports will be written to a network share." -color "Warning"
                        if (Confirm-UserAction -Message "Use network path anyway?") {
                            $script:TempPath = $val
                            Write-OutputColor "  Temp path set to $val" -color "Success"
                        }
                    } else {
                        if (-not (Test-Path -LiteralPath $val)) {
                            Write-OutputColor "  Note: Directory does not exist yet. It will be created when needed." -color "Warning"
                        }
                        $script:TempPath = $val
                        Write-OutputColor "  Temp path set to $val" -color "Success"
                    }
                }
                Start-Sleep -Seconds 1
            }
            "12" {
                Write-OutputColor "  Select timezone region:" -color "Info"
                Write-OutputColor "  [0] Show picker (default)" -color "Info"
                $regionKeys = @("North America", "South America", "Europe", "Africa", "Asia", "Oceania/Pacific", "UTC/Manual")
                for ($ri = 0; $ri -lt $regionKeys.Count; $ri++) {
                    Write-OutputColor "  [$($ri + 1)] $($regionKeys[$ri])" -color "Info"
                }
                $val = Read-Host "  Select"
                $navResult = Test-NavigationCommand -UserInput $val
                if ($navResult.ShouldReturn) { return }
                if ($val -eq "0" -or [string]::IsNullOrWhiteSpace($val)) {
                    $script:TimeZoneRegion = ""
                    Write-OutputColor "  Timezone region cleared (will show picker)." -color "Success"
                }
                elseif ($val -match '^\d+$' -and [int]$val -ge 1 -and [int]$val -le $regionKeys.Count) {
                    $script:TimeZoneRegion = $regionKeys[[int]$val - 1]
                    Write-OutputColor "  Timezone region set to $($script:TimeZoneRegion)." -color "Success"
                }
                else {
                    Write-OutputColor "  Invalid selection. Enter 0-$($regionKeys.Count)." -color "Error"
                }
                Start-Sleep -Seconds 1
            }
            "S" {
                if (Export-Defaults) {
                    Write-OutputColor "  Defaults saved to $($script:DefaultsPath)" -color "Success"
                }
                Start-Sleep -Seconds 1
            }
            "R" {
                if (Confirm-UserAction -Message "Reset all defaults to generic values?") {
                    $domain = ""; $script:domain = ""
                    $localadminaccountname = "localadmin"; $script:localadminaccountname = "localadmin"
                    $FullName = "Local Administrator"; $script:FullName = "Local Administrator"
                    $SwitchName = "LAN-SET"; $script:SwitchName = "LAN-SET"
                    $ManagementName = "Management"; $script:ManagementName = "Management"
                    $BackupName = "Backup"; $script:BackupName = "Backup"
                    $script:iSCSISubnet = "172.16.1"
                    $script:StorageBackendType = "iSCSI"
                    $script:AutoUpdate = $false
                    $script:TempPath = "$env:SystemDrive\Temp"
                    $script:TimeZoneRegion = ""

                    # Remove custom DNS presets
                    $toRemove = @()
                    foreach ($key in $script:DNSPresets.Keys) {
                        if ($key -notin $builtinDNSNames) { $toRemove += $key }
                    }
                    foreach ($key in $toRemove) { $script:DNSPresets.Remove($key) }

                    $script:FileServer = @{ BaseURL = ""; ClientId = ""; ClientSecret = ""; ISOsFolder = "ISOs"; VHDsFolder = "VirtualHardDrives"; AgentFolder = "Agents" }
                    Initialize-SANTargetPairs

                    Write-OutputColor "  Defaults reset to generic values." -color "Success"
                    Start-Sleep -Seconds 1
                }
            }
            "B" { return }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-12, S, R, or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Settings menu: Edit Custom Licenses
function Show-EditLicenses {
    while ($true) {
        if ($global:ReturnToMainMenu) { return }
        Clear-Host

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                        CUSTOM LICENSE KEYS").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        $kmsCount = 0
        foreach ($ver in $script:CustomKMSKeys.Keys) {
            foreach ($ed in $script:CustomKMSKeys[$ver].Keys) { $kmsCount++ }
        }
        $avmaCount = 0
        foreach ($ver in $script:CustomAVMAKeys.Keys) {
            foreach ($ed in $script:CustomAVMAKeys[$ver].Keys) { $avmaCount++ }
        }

        Write-OutputColor "  Custom KMS keys: $kmsCount    Custom AVMA keys: $avmaCount" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-MenuItem "[A]  Add custom license key"
        Write-MenuItem "[D]  Delete custom license key"
        Write-MenuItem "[V]  View all keys (built-in + custom)"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  [S] Save to licenses.json" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) {
            if (Invoke-NavigationAction -NavResult $navResult) { return }
        }

        switch ("$choice".ToUpper()) {
            "A" {
                Write-OutputColor "  License type:" -color "Info"
                Write-OutputColor "  1. KMS (for hosts)" -color "Info"
                Write-OutputColor "  2. AVMA (for VMs on Datacenter hosts)" -color "Info"
                $typeChoice = Read-Host "  Select"
                $navResult = Test-NavigationCommand -UserInput $typeChoice
                if ($navResult.ShouldReturn) { return }
                if ($typeChoice -ne "1" -and $typeChoice -ne "2") {
                    Write-OutputColor "  Invalid choice. Enter 1 or 2." -color "Error"
                    Start-Sleep -Seconds 1
                    continue
                }

                Write-OutputColor "  Enter Windows Server version (e.g., Windows Server 2022):" -color "Info"
                $version = Read-Host
                $navResult = Test-NavigationCommand -UserInput $version
                if ($navResult.ShouldReturn) { continue }

                Write-OutputColor "  Enter edition (e.g., Datacenter, Standard):" -color "Info"
                $edition = Read-Host
                $navResult = Test-NavigationCommand -UserInput $edition
                if ($navResult.ShouldReturn) { continue }

                Write-OutputColor "  Enter product key (XXXXX-XXXXX-XXXXX-XXXXX-XXXXX):" -color "Info"
                $key = Read-Host
                $navResult = Test-NavigationCommand -UserInput $key
                if ($navResult.ShouldReturn) { continue }

                if (-not [string]::IsNullOrWhiteSpace($version) -and -not [string]::IsNullOrWhiteSpace($edition) -and -not [string]::IsNullOrWhiteSpace($key)) {
                    if ($typeChoice -eq "1") {
                        if (-not $script:CustomKMSKeys.ContainsKey($version)) {
                            $script:CustomKMSKeys[$version] = @{}
                        }
                        $script:CustomKMSKeys[$version][$edition] = $key.ToUpper()
                        Write-OutputColor "  Added custom KMS key for $version $edition." -color "Success"
                    }
                    else {
                        if (-not $script:CustomAVMAKeys.ContainsKey($version)) {
                            $script:CustomAVMAKeys[$version] = @{}
                        }
                        $script:CustomAVMAKeys[$version][$edition] = $key.ToUpper()
                        Write-OutputColor "  Added custom AVMA key for $version $edition." -color "Success"
                    }
                }
                else {
                    Write-OutputColor "  All fields are required." -color "Error"
                }
                Start-Sleep -Seconds 1
            }
            "D" {
                Write-OutputColor "  Delete from: 1. KMS  2. AVMA" -color "Info"
                $typeChoice = Read-Host "  Select"
                $navResult = Test-NavigationCommand -UserInput $typeChoice
                if ($navResult.ShouldReturn) { return }
                if ($typeChoice -ne "1" -and $typeChoice -ne "2") {
                    Write-OutputColor "  Invalid choice. Enter 1 or 2." -color "Error"
                    Start-Sleep -Seconds 1
                    continue
                }
                $targetKeys = if ($typeChoice -eq "1") { $script:CustomKMSKeys } else { $script:CustomAVMAKeys }
                $typeName = if ($typeChoice -eq "1") { "KMS" } else { "AVMA" }

                if ($targetKeys.Count -eq 0) {
                    Write-OutputColor "  No custom $typeName keys to delete." -color "Warning"
                }
                else {
                    $idx = 1
                    $keyList = @()
                    foreach ($ver in $targetKeys.Keys) {
                        foreach ($ed in $targetKeys[$ver].Keys) {
                            Write-OutputColor "  $idx. $ver - ${ed}: $($targetKeys[$ver][$ed])" -color "Info"
                            $keyList += @{ Version = $ver; Edition = $ed }
                            $idx++
                        }
                    }
                    Write-OutputColor "  Enter number to delete (or B to cancel):" -color "Info"
                    $delChoice = Read-Host
                    $navResult = Test-NavigationCommand -UserInput $delChoice
                    if ($navResult.ShouldReturn) { continue }
                    if ($delChoice -match '^\d+$') {
                        $delIdx = [int]$delChoice - 1
                        if ($delIdx -ge 0 -and $delIdx -lt $keyList.Count) {
                            $item = $keyList[$delIdx]
                            $targetKeys[$item.Version].Remove($item.Edition)
                            if ($targetKeys[$item.Version].Count -eq 0) {
                                $targetKeys.Remove($item.Version)
                            }
                            Write-OutputColor "  Deleted." -color "Success"
                        }
                    }
                }
                Start-Sleep -Seconds 1
            }
            "V" {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Built-in keys are shown in gray, custom keys in green." -color "Info"
                Write-OutputColor "" -color "Info"

                # Show custom KMS keys
                if ($script:CustomKMSKeys.Count -gt 0) {
                    Write-OutputColor "  Custom KMS Keys:" -color "Success"
                    foreach ($ver in $script:CustomKMSKeys.Keys) {
                        foreach ($ed in $script:CustomKMSKeys[$ver].Keys) {
                            Write-OutputColor "    $ver - $ed : $($script:CustomKMSKeys[$ver][$ed])" -color "Success"
                        }
                    }
                    Write-OutputColor "" -color "Info"
                }

                # Show custom AVMA keys
                if ($script:CustomAVMAKeys.Count -gt 0) {
                    Write-OutputColor "  Custom AVMA Keys:" -color "Success"
                    foreach ($ver in $script:CustomAVMAKeys.Keys) {
                        foreach ($ed in $script:CustomAVMAKeys[$ver].Keys) {
                            Write-OutputColor "    $ver - $ed : $($script:CustomAVMAKeys[$ver][$ed])" -color "Success"
                        }
                    }
                    Write-OutputColor "" -color "Info"
                }

                if ($script:CustomKMSKeys.Count -eq 0 -and $script:CustomAVMAKeys.Count -eq 0) {
                    Write-OutputColor "  No custom license keys configured." -color "Debug"
                }

                Write-OutputColor "  (Built-in Microsoft KB keys are always available)" -color "Debug"
                Write-PressEnter
            }
            "S" {
                Export-CustomLicenses
                Write-OutputColor "  Licenses saved to $($script:DefaultsPath)" -color "Success"
                Start-Sleep -Seconds 1
            }
            "B" { return }
            default {
                Write-OutputColor "  Invalid choice. Enter A, D, V, S, or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# First-run configuration wizard
function Show-FirstRunWizard {
    try { Clear-Host } catch { }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    FIRST-RUN CONFIGURATION").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Check for company defaults files — auto-adopt if present
    $companyFiles = @(Get-CompanyDefaultsFiles)
    if ($companyFiles.Count -gt 0) {
        if ($companyFiles.Count -eq 1) {
            # Single company file: auto-adopt without prompting
            $script:CompanyDefaultsName = $companyFiles[0].Name
            $script:CompanyDefaultsPath = $companyFiles[0].Path
            Write-OutputColor "  Company defaults loaded: $($script:CompanyDefaultsName)" -color "Success"
        }
        else {
            # Multiple company files: show picker
            Write-OutputColor "  Multiple company defaults files detected:" -color "Info"
            foreach ($cf in $companyFiles) {
                Write-OutputColor "    - $($cf.Name).defaults.json" -color "Info"
            }
            Write-OutputColor "" -color "Info"
            $picked = Show-CompanyDefaultsPicker
            if ($null -ne $picked -and $picked -ne "__skip__") {
                $script:CompanyDefaultsName = $picked.Name
                $script:CompanyDefaultsPath = $picked.Path
                Write-OutputColor "  Company defaults loaded: $($script:CompanyDefaultsName)" -color "Success"
            }
        }

        if ($script:CompanyDefaultsPath) {
            # Save minimal defaults.json that just references the company defaults file
            # Do NOT use Export-Defaults here — script variables haven't been merged yet,
            # so it would save built-in defaults (empty FileServer/AgentInstaller) that
            # would overwrite company values on subsequent loads.
            $minimalDefaults = [ordered]@{
                "_description"     = "Environment defaults for $($script:ToolFullName)"
                "_companyDefaults" = $script:CompanyDefaultsName
            }
            try {
                $tempPath = "$($script:DefaultsPath).tmp"
                $minimalDefaults | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $tempPath -Encoding UTF8 -Force -ErrorAction Stop
                Move-Item -LiteralPath $tempPath -Destination $script:DefaultsPath -Force -ErrorAction Stop
                Write-OutputColor "  Configuration saved. Customize anytime in Settings > Edit Environment Defaults." -color "Info"
            }
            catch {
                Remove-Item -LiteralPath "$($script:DefaultsPath).tmp" -Force -ErrorAction SilentlyContinue
                Write-OutputColor "  Failed to save defaults: $_" -color "Error"
            }
            Start-Sleep -Seconds 2
            return
        }
    }

    # No company defaults — offer interactive setup or generic defaults
    Write-OutputColor "  Welcome! No environment defaults file was found." -color "Info"
    Write-OutputColor "  You can configure company-specific settings now, or use generic defaults." -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Settings can be changed later from: Settings > Edit Environment Defaults" -color "Debug"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Configure environment defaults now?")) {
        # User declined - save generic defaults so wizard won't run again
        if (Export-Defaults) {
            Write-OutputColor "  Generic defaults saved. You can configure later in Settings." -color "Info"
        }
        Start-Sleep -Seconds 2
        return
    }

    Write-OutputColor "" -color "Info"

    # Domain
    Write-OutputColor "  Enter your primary domain (e.g., contoso.local) or press Enter to skip:" -color "Info"
    $val = Read-Host "  Domain"
    if (-not [string]::IsNullOrWhiteSpace($val)) {
        $domain = $val
        $script:domain = $val
    }

    # Local admin
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enter local admin account name (default: localadmin):" -color "Info"
    $val = Read-Host "  Admin name"
    if (-not [string]::IsNullOrWhiteSpace($val)) {
        $localadminaccountname = $val
        $script:localadminaccountname = $val
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enter local admin full name (default: Local Administrator):" -color "Info"
    $val = Read-Host "  Full name"
    if (-not [string]::IsNullOrWhiteSpace($val)) {
        $FullName = $val
        $script:FullName = $val
    }

    # Custom DNS
    Write-OutputColor "" -color "Info"
    if (Confirm-UserAction -Message "Add a custom DNS preset (e.g., company DNS servers)?") {
        Write-OutputColor "  Enter preset name (e.g., 'Company DNS'):" -color "Info"
        $presetName = Read-Host "  Name"
        if (-not [string]::IsNullOrWhiteSpace($presetName)) {
            Write-OutputColor "  Enter primary DNS server IP:" -color "Info"
            $dns1 = Read-Host "  Primary"
            if (-not (Test-ValidIPAddress -IPAddress $dns1)) {
                Write-OutputColor "  Invalid IP address." -color "Error"
                Start-Sleep -Seconds 1
            }
            else {
                Write-OutputColor "  Enter secondary DNS server IP (or press Enter to skip):" -color "Info"
                $dns2 = Read-Host "  Secondary"
                $servers = @($dns1)
                if (-not [string]::IsNullOrWhiteSpace($dns2)) {
                    if (Test-ValidIPAddress -IPAddress $dns2) {
                        $servers += $dns2
                    }
                    else {
                        Write-OutputColor "  Invalid secondary IP, skipping." -color "Warning"
                    }
                }
                $script:DNSPresets[$presetName] = $servers
                Write-OutputColor "  Added DNS preset '$presetName'." -color "Success"
            }
        }
    }

    # FileServer
    Write-OutputColor "" -color "Info"
    if (Confirm-UserAction -Message "Configure FileServer for ISO/VHD/agent downloads?") {
        Write-OutputColor "  Enter FileServer base URL:" -color "Info"
        $val = Read-Host "  URL"
        if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.BaseURL = $val }

        Write-OutputColor "  Enter CF-Access-Client-Id:" -color "Info"
        $val = Read-Host "  ClientId"
        if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.ClientId = $val }

        Write-OutputColor "  Enter CF-Access-Client-Secret:" -color "Info"
        $val = Read-Host "  Secret"
        if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.ClientSecret = $val }

        Write-OutputColor "  Enter ISOs subfolder name (default: ISOs):" -color "Info"
        $val = Read-Host "  ISOs"
        if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.ISOsFolder = $val }

        Write-OutputColor "  Enter VHDs subfolder name (default: VirtualHardDrives):" -color "Info"
        $val = Read-Host "  VHDs"
        if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.VHDsFolder = $val }

        Write-OutputColor "  Enter agent installer subfolder name (default: Agents):" -color "Info"
        $val = Read-Host "  Agents"
        if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.AgentFolder = $val }
    }

    # iSCSI Subnet
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enter iSCSI subnet (first 3 octets, default: 172.16.1):" -color "Info"
    $val = Read-Host "  Subnet"
    if (-not [string]::IsNullOrWhiteSpace($val)) {
        $octets = $val -split '\.'
        $validSubnet = ($octets.Count -eq 3) -and ($octets | ForEach-Object { $_ -match '^\d{1,3}$' -and [int]$_ -ge 0 -and [int]$_ -le 255 }) -notcontains $false
        if ($validSubnet) {
            $script:iSCSISubnet = $val
            Initialize-SANTargetPairs
        }
        else {
            Write-OutputColor "  Invalid subnet format. Expected 3 octets (e.g., 172.16.1)." -color "Error"
            Start-Sleep -Seconds 1
        }
    }

    # Save
    if (Export-Defaults) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Configuration saved to $($script:DefaultsPath)" -color "Success"
    }
    Write-OutputColor "  You can edit these anytime from: Settings > Edit Environment Defaults" -color "Info"
    Write-PressEnter
}

function Remove-BatchVMs {
    # List all VMs with checkbox-style selection
    $vms = Get-VM -ErrorAction SilentlyContinue
    if ($null -eq $vms) {
        Write-OutputColor "  No virtual machines found" -color "Info"
        return
    }

    Write-OutputColor "`n  Select VMs to remove:" -color "Info"
    $vmList = @($vms)
    for ($i = 0; $i -lt $vmList.Count; $i++) {
        $vm = $vmList[$i]
        $state = $vm.State.ToString()
        $stateColor = if ($state -eq 'Running') { "Success" } else { "Warning" }
        Write-OutputColor "  [$($i+1)] $($vm.Name) ($state)" -color $stateColor
    }

    Write-OutputColor "`n  Enter VM numbers to remove (comma-separated), or 'cancel':" -color "Info"
    $selection = Read-Host "  Selection"
    $navResult = Test-NavigationCommand -UserInput $selection
    if ($navResult.ShouldReturn) { return }

    # Parse selection, confirm, then remove with option to delete VHDs
    $indices = $selection -split ',' | ForEach-Object { $_.Trim() }
    $selectedVMs = @()
    foreach ($idx in $indices) {
        $num = 0
        if ([int]::TryParse($idx, [ref]$num) -and $num -ge 1 -and $num -le $vmList.Count) {
            $selectedVMs += $vmList[$num - 1]
        }
    }

    if (@($selectedVMs).Count -eq 0) {
        Write-OutputColor "  No valid VMs selected" -color "Warning"
        return
    }

    # Show confirmation
    Write-OutputColor "`n  VMs to be removed:" -color "Warning"
    foreach ($vm in $selectedVMs) {
        Write-OutputColor "    - $($vm.Name)" -color "Warning"
    }

    Write-OutputColor "`n  Also delete associated VHD files? [Y/N]" -color "Warning"
    $deleteVHDs = Read-Host "  Choice"

    Write-OutputColor "`n  Are you SURE? This cannot be undone. [Y/N]" -color "Error"
    $confirm = Read-Host "  Confirm"
    if ($confirm -ne 'Y') {
        Write-OutputColor "  Operation cancelled" -color "Info"
        return
    }

    foreach ($vm in $selectedVMs) {
        try {
            if ($vm.State -eq 'Running') {
                Stop-VM -Name $vm.Name -Force -ErrorAction Stop
            }
            if ($deleteVHDs -eq 'Y') {
                $vhds = Get-VMHardDiskDrive -VMName $vm.Name -ErrorAction SilentlyContinue
                Remove-VM -Name $vm.Name -Force -ErrorAction Stop
                foreach ($vhd in $vhds) {
                    if (Test-Path -LiteralPath $vhd.Path) {
                        Remove-Item -LiteralPath $vhd.Path -Force
                    }
                }
            } else {
                Remove-VM -Name $vm.Name -Force -ErrorAction Stop
            }
            Write-OutputColor "  Removed: $($vm.Name)" -color "Success"
            Add-SessionChange -Category "VM" -Description "Removed VM: $($vm.Name)"
            Clear-MenuCache
        } catch {
            Write-OutputColor "  Failed to remove $($vm.Name): $($_.Exception.Message)" -color "Error"
        }
    }
}

function Test-VMMigrationReadiness {
    $vms = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Running' }
    if ($null -eq $vms) {
        Write-OutputColor "  No running VMs found" -color "Info"
        return
    }

    Write-OutputColor "`n  Enter target host for migration:" -color "Info"
    $targetHost = Read-Host "  Target host"
    $navResult = Test-NavigationCommand -UserInput $targetHost
    if ($navResult.ShouldReturn) { return }

    # Test connectivity
    Write-OutputColor "`n  Checking migration readiness..." -color "Info"

    $pingResult = Test-Connection -ComputerName $targetHost -Count 1 -Quiet -ErrorAction SilentlyContinue
    if (-not $pingResult) {
        Write-OutputColor "  Cannot reach $targetHost" -color "Error"
        return
    }
    Write-OutputColor "  Connectivity to ${targetHost}: OK" -color "Success"

    # Check if target is Hyper-V host
    try {
        $null = Get-VMHost -ComputerName $targetHost -ErrorAction Stop
        Write-OutputColor "  Hyper-V on ${targetHost}: OK" -color "Success"
    } catch {
        Write-OutputColor "  Cannot connect to Hyper-V on $targetHost" -color "Error"
        return
    }

    # Check processor compatibility
    try {
        $localProc = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $remoteProc = Get-CimInstance -ClassName Win32_Processor -ComputerName $targetHost -ErrorAction Stop | Select-Object -First 1
        if ($localProc.Manufacturer -eq $remoteProc.Manufacturer) {
            Write-OutputColor "  CPU Manufacturer match: OK ($($localProc.Manufacturer))" -color "Success"
        } else {
            Write-OutputColor "  CPU Manufacturer MISMATCH: $($localProc.Manufacturer) vs $($remoteProc.Manufacturer)" -color "Error"
            Write-OutputColor "  Live migration may fail - use processor compatibility mode" -color "Warning"
        }
    } catch {
        Write-OutputColor "  Could not compare processors: $($_.Exception.Message)" -color "Warning"
    }

    # Check available memory on target
    try {
        $targetMem = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $targetHost -ErrorAction Stop
        $freeMB = [math]::Round($targetMem.FreePhysicalMemory / 1024)
        Write-OutputColor "  Available memory on ${targetHost}: ${freeMB} MB" -color "Info"
    } catch {
        Write-OutputColor "  Could not check memory on $targetHost" -color "Warning"
    }

    Write-OutputColor "`n  Pre-flight check complete" -color "Success"
}
#endregion