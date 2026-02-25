#region ===== SYSTEM HEALTH CHECK =====
# Function to display system health information
function Show-SystemHealthCheck {
    Clear-Host
    Write-CenteredOutput "System Health Check" -color "Info"

    Write-OutputColor "Gathering system information..." -color "Info"
    Write-OutputColor "" -color "Info"

    # System Info
    Write-OutputColor "=== SYSTEM INFORMATION ===" -color "Success"
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    Write-OutputColor "  Computer Name: $(if ($cs) { $cs.Name } else { $env:COMPUTERNAME })" -color "Info"
    Write-OutputColor "  OS: $(if ($os) { $os.Caption } else { 'Unknown' })" -color "Info"
    Write-OutputColor "  Version: $(if ($os) { $os.Version } else { 'Unknown' })" -color "Info"
    Write-OutputColor "  Last Boot: $(if ($os) { $os.LastBootUpTime } else { 'Unknown' })" -color "Info"

    if ($os -and $os.LastBootUpTime) {
        $uptime = (Get-Date) - $os.LastBootUpTime
        $uptimeStr = "{0} days, {1} hours, {2} minutes" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
    } else { $uptimeStr = "Unknown" }
    Write-OutputColor "  Uptime: $uptimeStr" -color "Info"
    Write-OutputColor "" -color "Info"

    # CPU
    Write-OutputColor "=== CPU ===" -color "Success"
    $cpuAll = Get-CimInstance -ClassName Win32_Processor
    $cpu = $cpuAll | Select-Object -First 1
    Write-OutputColor "  Processor: $($cpu.Name)" -color "Info"
    Write-OutputColor "  Cores: $($cpu.NumberOfCores) | Logical: $($cpu.NumberOfLogicalProcessors)" -color "Info"

    $cpuMeasure = $cpuAll | Measure-Object -Property LoadPercentage -Average
    $cpuLoad = if ($null -ne $cpuMeasure -and $null -ne $cpuMeasure.Average) { $cpuMeasure.Average } else { 0 }
    $cpuColor = if ($cpuLoad -gt 80) { "Error" } elseif ($cpuLoad -gt 50) { "Warning" } else { "Success" }
    Write-OutputColor "  Current Load: $([math]::Round($cpuLoad, 1))%" -color $cpuColor
    Write-OutputColor "" -color "Info"

    # Memory
    Write-OutputColor "=== MEMORY ===" -color "Success"
    $totalMemGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeMemGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedMemGB = $totalMemGB - $freeMemGB
    $memPercent = [math]::Round(($usedMemGB / $totalMemGB) * 100, 1)
    $memColor = if ($memPercent -gt 90) { "Error" } elseif ($memPercent -gt 75) { "Warning" } else { "Success" }
    Write-OutputColor "  Total: $totalMemGB GB" -color "Info"
    Write-OutputColor "  Used: $usedMemGB GB ($memPercent%)" -color $memColor
    Write-OutputColor "  Free: $freeMemGB GB" -color "Info"
    Write-OutputColor "" -color "Info"

    # Disk Space
    Write-OutputColor "=== DISK SPACE ===" -color "Success"
    $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3"
    foreach ($disk in $disks) {
        $totalGB = [math]::Round($disk.Size / 1GB, 2)
        $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        $usedPercent = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1)
        $diskColor = if ($usedPercent -gt 90) { "Error" } elseif ($usedPercent -gt 75) { "Warning" } else { "Success" }
        Write-OutputColor "  $($disk.DeviceID) - Total: $totalGB GB | Free: $freeGB GB | Used: $usedPercent%" -color $diskColor
    }
    Write-OutputColor "" -color "Info"

    # Network Adapters
    Write-OutputColor "=== NETWORK ADAPTERS ===" -color "Success"
    $allAdapters = Get-NetAdapter
    foreach ($adapter in ($allAdapters | Where-Object { $_.Status -eq "Up" })) {
        $ip = Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
        $ipStr = if ($ip) { $ip.IPAddress } else { "No IP" }
        Write-OutputColor "  $($adapter.Name): $ipStr ($($adapter.LinkSpeed))" -color "Success"
    }

    foreach ($adapter in ($allAdapters | Where-Object { $_.Status -ne "Up" })) {
        Write-OutputColor "  $($adapter.Name): DOWN" -color "Warning"
    }
    Write-OutputColor "" -color "Info"

    # Pending Updates
    Write-OutputColor "=== WINDOWS UPDATE STATUS ===" -color "Success"
    if (Test-RebootPending) {
        Write-OutputColor "  Reboot Pending: YES" -color "Warning"
    }
    else {
        Write-OutputColor "  Reboot Pending: No" -color "Success"
    }

    # Try to check for updates (may require PSWindowsUpdate module)
    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $pendingUpdates = $updateSearcher.Search("IsInstalled=0").Updates.Count
        $updateColor = if ($pendingUpdates -gt 10) { "Warning" } elseif ($pendingUpdates -gt 0) { "Info" } else { "Success" }
        Write-OutputColor "  Pending Updates: $pendingUpdates" -color $updateColor
    }
    catch {
        Write-OutputColor "  Pending Updates: Unable to check" -color "Info"
    }
    Write-OutputColor "" -color "Info"

    # Key Services
    Write-OutputColor "=== KEY SERVICES ===" -color "Success"
    $keyServices = @(
        @{ Name = "wuauserv"; Display = "Windows Update" },
        @{ Name = "WinRM"; Display = "WinRM" },
        @{ Name = "vmms"; Display = "Hyper-V Management" },
        @{ Name = "TermService"; Display = "Remote Desktop" },
        @{ Name = "DNS"; Display = "DNS Server" },
        @{ Name = "DFSR"; Display = "DFS Replication" }
    )

    foreach ($svc in $keyServices) {
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($service) {
            $svcColor = if ($service.Status -eq "Running") { "Success" } else { "Warning" }
            $statusStr = $service.Status.ToString()
            Write-OutputColor "  $($svc.Display): $statusStr" -color $svcColor
        }
    }
    Write-OutputColor "" -color "Info"

    # Summary
    Write-OutputColor "=== SUMMARY ===" -color "Success"
    $issues = @()
    if ($cpuLoad -gt 80) { $issues += "High CPU usage" }
    if ($memPercent -gt 90) { $issues += "High memory usage" }
    foreach ($disk in $disks) {
        $usedPercent = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1)
        if ($usedPercent -gt 90) { $issues += "Low disk space on $($disk.DeviceID)" }
    }
    if (Test-RebootPending) { $issues += "Reboot pending" }

    if ($issues.Count -eq 0) {
        Write-OutputColor "  System health: GOOD - No issues detected" -color "Success"
    }
    else {
        Write-OutputColor "  System health: ATTENTION NEEDED" -color "Warning"
        foreach ($issue in $issues) {
            Write-OutputColor "    - $issue" -color "Warning"
        }
    }

    # Disk I/O Latency (v1.7.0)
    Write-OutputColor "=== DISK I/O LATENCY ===" -color "Success"
    try {
        $diskCounters = Get-Counter '\PhysicalDisk(*)\Avg. Disk sec/Read', '\PhysicalDisk(*)\Avg. Disk sec/Write' -ErrorAction SilentlyContinue
        if ($diskCounters) {
            foreach ($sample in $diskCounters.CounterSamples) {
                $instanceName = $sample.InstanceName
                if ($instanceName -eq '_total') { continue }
                $latencyMs = [math]::Round($sample.CookedValue * 1000, 2)
                $metricName = if ($sample.Path -match 'Read') { "Read" } else { "Write" }
                $latColor = if ($latencyMs -gt 20) { "Error" } elseif ($latencyMs -gt 10) { "Warning" } else { "Success" }
                Write-OutputColor "  Disk $instanceName $metricName Latency: ${latencyMs}ms" -color $latColor
            }
        }
        else {
            Write-OutputColor "  Unable to read disk performance counters." -color "Debug"
        }
    }
    catch {
        Write-OutputColor "  Disk I/O check unavailable: $_" -color "Debug"
    }
    Write-OutputColor "" -color "Info"

    # NIC Error Counters (v1.7.0)
    Write-OutputColor "=== NIC ERROR COUNTERS ===" -color "Success"
    try {
        $nicStats = Get-NetAdapterStatistics -ErrorAction SilentlyContinue
        foreach ($nic in $nicStats) {
            $inErrors = $nic.InErrors
            $outErrors = $nic.OutErrors
            $inDiscards = $nic.InDiscards
            $totalErrors = $inErrors + $outErrors + $inDiscards
            $nicColor = if ($totalErrors -gt 0) { "Warning" } else { "Success" }
            Write-OutputColor "  $($nic.Name): InErrors=$inErrors OutErrors=$outErrors InDiscards=$inDiscards" -color $nicColor
        }
    }
    catch {
        Write-OutputColor "  NIC statistics unavailable." -color "Debug"
    }
    Write-OutputColor "" -color "Info"

    # Memory Pressure (v1.7.0)
    Write-OutputColor "=== MEMORY PRESSURE ===" -color "Success"
    try {
        $memCounters = Get-Counter '\Memory\Pages/sec', '\Memory\Available MBytes' -ErrorAction SilentlyContinue
        if ($memCounters) {
            foreach ($sample in $memCounters.CounterSamples) {
                $counterName = if ($sample.Path -match 'Pages') { "Pages/sec" } else { "Available MB" }
                $value = [math]::Round($sample.CookedValue, 1)
                $pressureColor = "Success"
                if ($counterName -eq "Pages/sec" -and $value -gt 1000) { $pressureColor = "Warning" }
                if ($counterName -eq "Available MB" -and $value -lt 500) { $pressureColor = "Error" }
                elseif ($counterName -eq "Available MB" -and $value -lt 2000) { $pressureColor = "Warning" }
                Write-OutputColor "  $counterName`: $value" -color $pressureColor
            }
        }
    }
    catch {
        Write-OutputColor "  Memory pressure counters unavailable." -color "Debug"
    }
    Write-OutputColor "" -color "Info"

    # Hyper-V Guest Health (v1.7.0)
    if (Test-HyperVInstalled) {
        Write-OutputColor "=== HYPER-V GUEST HEALTH ===" -color "Success"
        try {
            $runningVMs = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Running" }
            if ($runningVMs) {
                foreach ($vm in $runningVMs) {
                    $hb = Get-VMIntegrationService -VM $vm -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Heartbeat" }
                    $hbStatus = if ($hb -and $hb.PrimaryStatusDescription -eq "OK") { "OK" } elseif ($hb) { $hb.PrimaryStatusDescription } else { "N/A" }
                    $vmColor = if ($hbStatus -eq "OK") { "Success" } else { "Warning" }
                    Write-OutputColor "  $($vm.Name): Heartbeat=$hbStatus  CPU=$($vm.ProcessorCount)  RAM=$([math]::Round($vm.MemoryAssigned/1GB,1))GB" -color $vmColor
                }
            }
            else {
                Write-OutputColor "  No running VMs." -color "Info"
            }
        }
        catch {
            Write-OutputColor "  Hyper-V guest health unavailable." -color "Debug"
        }
        Write-OutputColor "" -color "Info"
    }

    # Top 5 CPU Processes (v1.7.0)
    Write-OutputColor "=== TOP 5 CPU PROCESSES ===" -color "Success"
    try {
        $topProcs = Get-Process -ErrorAction SilentlyContinue | Sort-Object CPU -Descending | Select-Object -First 5
        foreach ($proc in $topProcs) {
            $cpuSec = [math]::Round($proc.CPU, 1)
            $memMB = [math]::Round($proc.WorkingSet64 / 1MB, 0)
            Write-OutputColor "  $($proc.ProcessName.PadRight(30)) CPU: ${cpuSec}s  RAM: ${memMB}MB" -color "Info"
        }
    }
    catch {
        Write-OutputColor "  Process information unavailable." -color "Debug"
    }
    Write-OutputColor "" -color "Info"

    Add-SessionChange -Category "System" -Description "Ran system health check"
}

# Function to display server configuration readiness at a glance
function Show-ServerReadiness {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     SERVER READINESS DASHBOARD").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Checking configuration status..." -color "Info"
    Write-OutputColor "" -color "Info"

    $ready = 0
    $total = 0
    $items = @()

    # --- IDENTITY ---
    $hostname = $env:COMPUTERNAME
    $isDefaultName = $hostname -match '^WIN-|^DESKTOP-|^YOURSERVERNAME'
    $total++
    if (-not $isDefaultName) {
        $ready++
        $items += @{ Category = "IDENTITY"; Name = "Hostname"; Value = $hostname; Color = "Success"; Symbol = "[OK]" }
    } else {
        $items += @{ Category = "IDENTITY"; Name = "Hostname"; Value = "$hostname (default)"; Color = "Error"; Symbol = "[!!]" }
    }

    $total++
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    if ($cs.PartOfDomain) {
        $ready++
        $items += @{ Category = "IDENTITY"; Name = "Domain"; Value = $cs.Domain; Color = "Success"; Symbol = "[OK]" }
    } else {
        $items += @{ Category = "IDENTITY"; Name = "Domain"; Value = "WORKGROUP (not joined)"; Color = "Warning"; Symbol = "[--]" }
    }

    $total++
    $siteNum = Get-SiteNumberFromHostname
    if ($siteNum) {
        $ready++
        $items += @{ Category = "IDENTITY"; Name = "Site Number"; Value = $siteNum; Color = "Success"; Symbol = "[OK]" }
    } else {
        $items += @{ Category = "IDENTITY"; Name = "Site Number"; Value = "Not detected in hostname"; Color = "Warning"; Symbol = "[--]" }
    }

    # --- REMOTE ACCESS ---
    $total++
    $rdpState = Get-RDPState
    if ($rdpState -eq "Enabled") {
        $ready++
        $items += @{ Category = "REMOTE ACCESS"; Name = "RDP"; Value = "Enabled"; Color = "Success"; Symbol = "[OK]" }
    } else {
        $items += @{ Category = "REMOTE ACCESS"; Name = "RDP"; Value = "Disabled"; Color = "Warning"; Symbol = "[--]" }
    }

    $total++
    $winrmState = Get-WinRMState
    if ($winrmState -eq "Running") {
        $ready++
        $items += @{ Category = "REMOTE ACCESS"; Name = "WinRM"; Value = "Running"; Color = "Success"; Symbol = "[OK]" }
    } else {
        $items += @{ Category = "REMOTE ACCESS"; Name = "WinRM"; Value = $winrmState; Color = "Warning"; Symbol = "[--]" }
    }

    # --- SOFTWARE ---
    if (Test-AgentInstallerConfigured) {
        $total++
        $agentStatus = Test-AgentInstalled
        if ($agentStatus.Installed) {
            $ready++
            $agentVal = if ($agentStatus.Status -eq "Running") { "Installed & Running" } else { "Installed ($($agentStatus.Status))" }
            $agentColor = if ($agentStatus.Status -eq "Running") { "Success" } else { "Warning" }
            $items += @{ Category = "SOFTWARE"; Name = "$($script:AgentInstaller.ToolName) Agent"; Value = $agentVal; Color = $agentColor; Symbol = "[OK]" }
        } else {
            $items += @{ Category = "SOFTWARE"; Name = "$($script:AgentInstaller.ToolName) Agent"; Value = "Not Installed"; Color = "Error"; Symbol = "[!!]" }
        }
    }

    # --- ROLES & FEATURES ---
    $total++
    if (Test-HyperVInstalled) {
        $ready++
        $items += @{ Category = "ROLES"; Name = "Hyper-V"; Value = "Installed"; Color = "Success"; Symbol = "[OK]" }
    } else {
        $items += @{ Category = "ROLES"; Name = "Hyper-V"; Value = "Not Installed"; Color = "Info"; Symbol = "[--]" }
    }

    if (Test-WindowsServer) {
        $total++
        if (Test-MPIOInstalled) {
            $ready++
            $items += @{ Category = "ROLES"; Name = "MPIO"; Value = "Installed"; Color = "Success"; Symbol = "[OK]" }
        } else {
            $items += @{ Category = "ROLES"; Name = "MPIO"; Value = "Not Installed"; Color = "Info"; Symbol = "[--]" }
        }

        $total++
        if (Test-FailoverClusteringInstalled) {
            $ready++
            $items += @{ Category = "ROLES"; Name = "Failover Clustering"; Value = "Installed"; Color = "Success"; Symbol = "[OK]" }
        } else {
            $items += @{ Category = "ROLES"; Name = "Failover Clustering"; Value = "Not Installed"; Color = "Info"; Symbol = "[--]" }
        }
    }

    # --- NETWORK ---
    $total++
    $fwState = Get-FirewallState
    $fwCorrect = ($fwState.Domain -eq "Disabled" -and $fwState.Private -eq "Disabled" -and $fwState.Public -eq "Enabled")
    if ($fwCorrect) {
        $ready++
        $items += @{ Category = "NETWORK"; Name = "Firewall"; Value = "Domain=Off Private=Off Public=On"; Color = "Success"; Symbol = "[OK]" }
    } else {
        $status = "Domain=$(if($fwState.Domain -eq 'Enabled'){'On'}else{'Off'}) Private=$(if($fwState.Private -eq 'Enabled'){'On'}else{'Off'}) Public=$(if($fwState.Public -eq 'Enabled'){'On'}else{'Off'})"
        $items += @{ Category = "NETWORK"; Name = "Firewall"; Value = $status; Color = "Warning"; Symbol = "[--]" }
    }

    $total++
    $adaptersUp = @(Get-NetAdapter | Where-Object { $_.Status -eq "Up" })
    if ($adaptersUp.Count -gt 0) {
        $ready++
        $items += @{ Category = "NETWORK"; Name = "Network Adapters"; Value = "$($adaptersUp.Count) adapter(s) up"; Color = "Success"; Symbol = "[OK]" }
    } else {
        $items += @{ Category = "NETWORK"; Name = "Network Adapters"; Value = "No adapters up"; Color = "Error"; Symbol = "[!!]" }
    }

    # --- SYSTEM ---
    $total++
    $powerPlan = Get-CurrentPowerPlan
    if ($powerPlan.Name -eq "High performance") {
        $ready++
        $items += @{ Category = "SYSTEM"; Name = "Power Plan"; Value = "High Performance"; Color = "Success"; Symbol = "[OK]" }
    } else {
        $items += @{ Category = "SYSTEM"; Name = "Power Plan"; Value = $powerPlan.Name; Color = "Warning"; Symbol = "[--]" }
    }

    $total++
    if (Test-RebootPending) {
        $items += @{ Category = "SYSTEM"; Name = "Reboot Pending"; Value = "YES - reboot needed"; Color = "Error"; Symbol = "[!!]" }
    } else {
        $ready++
        $items += @{ Category = "SYSTEM"; Name = "Reboot Pending"; Value = "No"; Color = "Success"; Symbol = "[OK]" }
    }

    $total++
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $activated = Test-WindowsActivated
    if ($activated) {
        $ready++
        $items += @{ Category = "SYSTEM"; Name = "Windows License"; Value = "Activated"; Color = "Success"; Symbol = "[OK]" }
    } else {
        $items += @{ Category = "SYSTEM"; Name = "Windows License"; Value = "Not Activated"; Color = "Warning"; Symbol = "[--]" }
    }

    # --- RENDER ---
    $currentCategory = ""
    foreach ($item in $items) {
        if ($item.Category -ne $currentCategory) {
            if ($currentCategory -ne "") {
                Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
                Write-OutputColor "" -color "Info"
            }
            $currentCategory = $item.Category
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  $currentCategory".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        }
        $line = "  $($item.Symbol) $($item.Name):".PadRight(28) + $item.Value
        Write-OutputColor "  │$($line.PadRight(72))│" -color $item.Color
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Score
    $pct = [math]::Round(($ready / $total) * 100)
    $scoreColor = if ($pct -ge 80) { "Success" } elseif ($pct -ge 50) { "Warning" } else { "Error" }
    $scoreBar = ("█" * [math]::Floor($pct / 5)).PadRight(20, "░")

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  READINESS SCORE".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  $scoreBar  $pct% ($ready/$total checks passed)".PadRight(72))│" -color $scoreColor
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    Add-SessionChange -Category "System" -Description "Ran server readiness check ($ready/$total passed)"
}

# Guided Quick Setup Wizard - walks through essential server configuration steps
function Show-QuickSetupWizard {
    $steps = @(
        @{ Name = "Hostname";  Num = 1; Total = 6 }
        @{ Name = "Domain";    Num = 2; Total = 6 }
        @{ Name = "Agent";     Num = 3; Total = 6 }
        @{ Name = "RDP";       Num = 4; Total = 6 }
        @{ Name = "Power";     Num = 5; Total = 6 }
        @{ Name = "License";   Num = 6; Total = 6 }
    )
    $completed = 0
    $skipped = 0

    Add-SessionChange -Category "System" -Description "Started Quick Setup Wizard"

    # === STEP 1: HOSTNAME ===
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                        QUICK SETUP WIZARD").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Step 1 of 6: HOSTNAME" -color "Info"
    Write-OutputColor "  ────────────────────────────────────────────" -color "Info"
    Write-OutputColor "" -color "Info"

    $hostname = $env:COMPUTERNAME
    $isDefault = $hostname -match '^WIN-|^DESKTOP-|^YOURSERVERNAME'

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    if ($isDefault) {
        Write-OutputColor "  │$("  Current:  $hostname (DEFAULT - needs configuration)".PadRight(72))│" -color "Error"
    } else {
        Write-OutputColor "  │$("  Current:  $hostname".PadRight(72))│" -color "Success"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($isDefault) {
        if (Confirm-UserAction -Message "Set hostname now? (Required before agent install)" -DefaultYes) {
            Set-HostName
            $completed++
            if ($global:RebootNeeded) {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Hostname change requires a reboot before continuing." -color "Warning"
                Write-OutputColor "  Please reboot and re-run the Quick Setup Wizard." -color "Warning"
                Write-PressEnter
                return
            }
        } else { $skipped++ }
    } else {
        Write-OutputColor "  Hostname is set. Skipping." -color "Success"
        $completed++
        Start-Sleep -Milliseconds 500
    }

    # === STEP 2: DOMAIN JOIN ===
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                        QUICK SETUP WIZARD").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Step 2 of 6: DOMAIN JOIN" -color "Info"
    Write-OutputColor "  ────────────────────────────────────────────" -color "Info"
    Write-OutputColor "" -color "Info"

    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    if ($cs.PartOfDomain) {
        Write-OutputColor "  │$("  Current:  Joined to $($cs.Domain)".PadRight(72))│" -color "Success"
    } else {
        Write-OutputColor "  │$("  Current:  WORKGROUP (not domain-joined)".PadRight(72))│" -color "Warning"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not $cs.PartOfDomain) {
        if (Confirm-UserAction -Message "Join a domain now?") {
            Join-Domain
            $completed++
            if ($global:RebootNeeded) {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Domain join requires a reboot before continuing." -color "Warning"
                Write-OutputColor "  Please reboot and re-run the Quick Setup Wizard." -color "Warning"
                Write-PressEnter
                return
            }
        } else { $skipped++ }
    } else {
        Write-OutputColor "  Already domain-joined. Skipping." -color "Success"
        $completed++
        Start-Sleep -Milliseconds 500
    }

    # === STEP 3: AGENT ===
    if (Test-AgentInstallerConfigured) {
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                        QUICK SETUP WIZARD").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Step 3 of 6: $($script:AgentInstaller.ToolName.ToUpper()) AGENT" -color "Info"
        Write-OutputColor "  ────────────────────────────────────────────" -color "Info"
        Write-OutputColor "" -color "Info"

        $agentStatus = Test-AgentInstalled
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        if ($agentStatus.Installed) {
            $kVal = if ($agentStatus.Status -eq "Running") { "Installed & Running" } else { "Installed ($($agentStatus.Status))" }
            Write-OutputColor "  │$("  Current:  $kVal".PadRight(72))│" -color "Success"
        } else {
            Write-OutputColor "  │$("  Current:  Not Installed".PadRight(72))│" -color "Warning"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        if (-not $agentStatus.Installed) {
            if (Confirm-UserAction -Message "Install $($script:AgentInstaller.ToolName) Agent now?") {
                Install-Agent -ReturnAfterInstall
                $completed++
            } else { $skipped++ }
        } else {
            Write-OutputColor "  $($script:AgentInstaller.ToolName) is installed. Skipping." -color "Success"
            $completed++
            Start-Sleep -Milliseconds 500
        }
    } else { $skipped++ }

    # === STEP 4: RDP ===
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                        QUICK SETUP WIZARD").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Step 4 of 6: REMOTE DESKTOP (RDP)" -color "Info"
    Write-OutputColor "  ────────────────────────────────────────────" -color "Info"
    Write-OutputColor "" -color "Info"

    $rdpState = Get-RDPState
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    if ($rdpState -eq "Enabled") {
        Write-OutputColor "  │$("  Current:  RDP Enabled".PadRight(72))│" -color "Success"
    } else {
        Write-OutputColor "  │$("  Current:  RDP Disabled".PadRight(72))│" -color "Warning"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($rdpState -ne "Enabled") {
        if (Confirm-UserAction -Message "Enable RDP now?" -DefaultYes) {
            Enable-RDP
            $completed++
        } else { $skipped++ }
    } else {
        Write-OutputColor "  RDP is enabled. Skipping." -color "Success"
        $completed++
        Start-Sleep -Milliseconds 500
    }

    # === STEP 5: POWER PLAN ===
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                        QUICK SETUP WIZARD").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Step 5 of 6: POWER PLAN" -color "Info"
    Write-OutputColor "  ────────────────────────────────────────────" -color "Info"
    Write-OutputColor "" -color "Info"

    $powerPlan = Get-CurrentPowerPlan
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    if ($powerPlan.Name -eq "High performance") {
        Write-OutputColor "  │$("  Current:  High Performance".PadRight(72))│" -color "Success"
    } else {
        Write-OutputColor "  │$("  Current:  $($powerPlan.Name)".PadRight(72))│" -color "Warning"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($powerPlan.Name -ne "High performance") {
        if (Confirm-UserAction -Message "Set power plan to High Performance?" -DefaultYes) {
            Set-ServerPowerPlan
            $completed++
        } else { $skipped++ }
    } else {
        Write-OutputColor "  Power plan is High Performance. Skipping." -color "Success"
        $completed++
        Start-Sleep -Milliseconds 500
    }

    # === STEP 6: LICENSING ===
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                        QUICK SETUP WIZARD").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Step 6 of 6: WINDOWS LICENSING" -color "Info"
    Write-OutputColor "  ────────────────────────────────────────────" -color "Info"
    Write-OutputColor "" -color "Info"

    $activated = Test-WindowsActivated
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    if ($activated) {
        Write-OutputColor "  │$("  Current:  Windows is Activated".PadRight(72))│" -color "Success"
    } else {
        Write-OutputColor "  │$("  Current:  Not Activated".PadRight(72))│" -color "Warning"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not $activated) {
        if (Confirm-UserAction -Message "Configure Windows licensing now?") {
            Register-ServerLicense
            $completed++
        } else { $skipped++ }
    } else {
        Write-OutputColor "  Windows is activated. Skipping." -color "Success"
        $completed++
        Start-Sleep -Milliseconds 500
    }

    # === SUMMARY ===
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     QUICK SETUP - COMPLETE").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  RESULTS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Completed:  $completed of 6 steps".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Skipped:    $skipped of 6 steps".PadRight(72))│" -color $(if ($skipped -gt 0) { "Warning" } else { "Success" })
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($global:RebootNeeded) {
        Write-OutputColor "  A reboot is required to finalize changes." -color "Warning"
        Write-OutputColor "" -color "Info"
        if (Confirm-UserAction -Message "Reboot now?") {
            Add-SessionChange -Category "System" -Description "Quick Setup Wizard rebooting ($completed completed, $skipped skipped)"
            Restart-Computer -Force
        }
    }

    Add-SessionChange -Category "System" -Description "Quick Setup Wizard finished ($completed completed, $skipped skipped)"
}

# Server Role Templates - guided checklists for common server configurations
function Show-RoleTemplates {
    Clear-Host
    Write-CenteredOutput "Server Role Templates" -color "Info"

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Select a server role to see its configuration checklist:" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [1] Hyper-V Host" -color "Success"
    Write-OutputColor "      Hyper-V, MPIO, iSCSI, SET Teaming, High Performance" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [2] Standalone Server" -color "Success"
    Write-OutputColor "      Hostname, Domain, RDP, $($script:AgentInstaller.ToolName), License, Power Plan" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [3] Cluster Node" -color "Success"
    Write-OutputColor "      All of Hyper-V Host + Failover Clustering + Domain" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"

    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) {
        if (Invoke-NavigationAction -NavResult $navResult) { return }
    }

    $templateName = $null
    $checks = @()

    switch ($choice) {
        "1" {
            $templateName = "HYPER-V HOST"
            $checks = @(
                @{ Name = "Hostname Set";              Test = { $env:COMPUTERNAME -notmatch '^WIN-|^DESKTOP-|^YOURSERVERNAME' }; Action = "Set-HostName"; Category = "Identity" }
                @{ Name = "Domain Joined";             Test = { (Get-CimInstance Win32_ComputerSystem).PartOfDomain }; Action = "Join-Domain"; Category = "Identity" }
                @{ Name = "RDP Enabled";               Test = { (Get-RDPState) -eq "Enabled" }; Action = "Enable-RDP"; Category = "Access" }
                @{ Name = "High Performance Power";    Test = { (Get-CurrentPowerPlan).Name -match "High" }; Action = "Set-ServerPowerPlan"; Category = "System" }
                @{ Name = "Hyper-V Installed";         Test = { Test-HyperVInstalled }; Action = "Install-HyperVRole"; Category = "Roles" }
                @{ Name = "MPIO Installed";            Test = { Test-MPIOInstalled }; Action = "Install-MPIOFeature"; Category = "Roles" }
                @{ Name = "Windows Licensed";          Test = { Test-WindowsActivated }; Action = "Register-ServerLicense"; Category = "System" }
            )
            if (Test-AgentInstallerConfigured) { $checks += @{ Name = "$($script:AgentInstaller.ToolName) Agent"; Test = { (Test-AgentInstalled).Installed }; Action = "Install-Agent"; Category = "Software" } }
        }
        "2" {
            $templateName = "STANDALONE SERVER"
            $checks = @(
                @{ Name = "Hostname Set";              Test = { $env:COMPUTERNAME -notmatch '^WIN-|^DESKTOP-|^YOURSERVERNAME' }; Action = "Set-HostName"; Category = "Identity" }
                @{ Name = "Domain Joined";             Test = { (Get-CimInstance Win32_ComputerSystem).PartOfDomain }; Action = "Join-Domain"; Category = "Identity" }
                @{ Name = "RDP Enabled";               Test = { (Get-RDPState) -eq "Enabled" }; Action = "Enable-RDP"; Category = "Access" }
                @{ Name = "WinRM Enabled";             Test = { (Get-WinRMState) -match "Enabled|Running" }; Action = "Enable-PSRemoting"; Category = "Access" }
                @{ Name = "High Performance Power";    Test = { (Get-CurrentPowerPlan).Name -match "High" }; Action = "Set-ServerPowerPlan"; Category = "System" }
                @{ Name = "Windows Licensed";          Test = { Test-WindowsActivated }; Action = "Register-ServerLicense"; Category = "System" }
            )
            if (Test-AgentInstallerConfigured) { $checks += @{ Name = "$($script:AgentInstaller.ToolName) Agent"; Test = { (Test-AgentInstalled).Installed }; Action = "Install-Agent"; Category = "Software" } }
        }
        "3" {
            $templateName = "CLUSTER NODE"
            $checks = @(
                @{ Name = "Hostname Set";              Test = { $env:COMPUTERNAME -notmatch '^WIN-|^DESKTOP-|^YOURSERVERNAME' }; Action = "Set-HostName"; Category = "Identity" }
                @{ Name = "Domain Joined";             Test = { (Get-CimInstance Win32_ComputerSystem).PartOfDomain }; Action = "Join-Domain"; Category = "Identity" }
                @{ Name = "RDP Enabled";               Test = { (Get-RDPState) -eq "Enabled" }; Action = "Enable-RDP"; Category = "Access" }
                @{ Name = "High Performance Power";    Test = { (Get-CurrentPowerPlan).Name -match "High" }; Action = "Set-ServerPowerPlan"; Category = "System" }
                @{ Name = "Hyper-V Installed";         Test = { Test-HyperVInstalled }; Action = "Install-HyperVRole"; Category = "Roles" }
                @{ Name = "MPIO Installed";            Test = { Test-MPIOInstalled }; Action = "Install-MPIOFeature"; Category = "Roles" }
                @{ Name = "Failover Clustering";       Test = { Test-FailoverClusteringInstalled }; Action = "Install-FailoverClusteringFeature"; Category = "Roles" }
                @{ Name = "Windows Licensed";          Test = { Test-WindowsActivated }; Action = "Register-ServerLicense"; Category = "System" }
            )
            if (Test-AgentInstallerConfigured) { $checks += @{ Name = "$($script:AgentInstaller.ToolName) Agent"; Test = { (Test-AgentInstalled).Installed }; Action = "Install-Agent"; Category = "Software" } }
        }
        default {
            Write-OutputColor "Invalid selection." -color "Warning"
            return
        }
    }

    # Display checklist with live status
    Clear-Host
    Write-CenteredOutput "Role Template: $templateName" -color "Info"
    Write-OutputColor "" -color "Info"

    $passed = 0
    $total = $checks.Count
    $results = @()

    foreach ($check in $checks) {
        $status = $false
        try { $status = & $check.Test } catch { Write-OutputColor "  [!!] $($check.Name): check failed ($_)" -color "Debug" }
        $icon = if ($status) { "[OK]" } else { "[--]" }
        $color = if ($status) { "Success" } else { "Warning" }
        if ($status) { $passed++ }
        Write-OutputColor "  $icon $($check.Name)" -color $color
        $results += @{ Check = $check; Passed = $status }
    }

    $pct = [math]::Round(($passed / $total) * 100)
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Score: $passed/$total ($pct%)" -color $(if ($pct -ge 80) { "Success" } elseif ($pct -ge 50) { "Warning" } else { "Error" })
    Write-OutputColor "" -color "Info"

    # Offer to configure missing items
    $missing = @($results | Where-Object { -not $_.Passed })
    if ($missing.Count -eq 0) {
        Write-OutputColor "  All checks passed! Server is fully configured for $templateName." -color "Success"
        return
    }

    Write-OutputColor "  $($missing.Count) item(s) need attention." -color "Warning"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [A] Auto-configure all missing items (guided)" -color "Success"
    Write-OutputColor "  [B] Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $action = Read-Host "  Select"

    if ($action -ne "A" -and $action -ne "a") { return }

    # Run guided setup for missing items
    $stepNum = 0
    foreach ($item in $missing) {
        $stepNum++
        $check = $item.Check
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  --- Step $stepNum of $($missing.Count): $($check.Name) ---" -color "Info"

        if (Confirm-UserAction -Message "Configure $($check.Name) now?") {
            try {
                & $check.Action
                Write-PressEnter

                # Recheck
                $nowPassed = $false
                try { $nowPassed = & $check.Test } catch { Write-OutputColor "  [!!] $($check.Name): recheck failed ($_)" -color "Debug" }
                if ($nowPassed) {
                    Write-OutputColor "  $($check.Name): Configured successfully!" -color "Success"
                }
                else {
                    Write-OutputColor "  $($check.Name): May need a reboot or manual verification." -color "Warning"
                }

                # If reboot needed, offer to stop
                if ($global:RebootNeeded) {
                    Write-OutputColor "" -color "Info"
                    Write-OutputColor "  A reboot is needed. Remaining items will be available after restart." -color "Warning"
                    Add-SessionChange -Category "System" -Description "Role template $templateName paused at step $stepNum (reboot needed)"
                    return
                }
            }
            catch {
                Write-OutputColor "  Error configuring $($check.Name): $_" -color "Error"
            }
        }
        else {
            Write-OutputColor "  Skipped: $($check.Name)" -color "Info"
        }
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Role template $templateName setup complete!" -color "Success"
    Add-SessionChange -Category "System" -Description "Completed role template: $templateName"
}
#endregion