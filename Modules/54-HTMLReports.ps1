#region ===== HTML REPORTING (v2.8.0) =====
# HTML-encode dynamic values to prevent display issues with special characters
function ConvertTo-HtmlSafe([string]$s) { if ($s) { [System.Net.WebUtility]::HtmlEncode($s) } else { $s } }

# Function to generate HTML health report
function Export-HTMLHealthReport {
    param(
        [string]$OutputPath = "$env:USERPROFILE\Desktop\HealthReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html",
        [string[]]$Sections = @()
    )

    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                      GENERATE HTML HEALTH REPORT").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Default path: $OutputPath" -color "Info"
    Write-OutputColor "" -color "Info"

    $useDefault = Confirm-UserAction -Message "Use default path?" -DefaultYes
    if (-not $useDefault) {
        Write-OutputColor "  Enter output path:" -color "Info"
        $customPath = Read-Host "  "
        $navResult = Test-NavigationCommand -UserInput $customPath
        if ($navResult.ShouldReturn) { return }
        if (-not [string]::IsNullOrWhiteSpace($customPath)) {
            $OutputPath = $customPath.Trim('"')
        }
    }

    # Validate output directory exists
    $outputDir = Split-Path -Parent $OutputPath
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        Write-OutputColor "  Directory does not exist: $outputDir" -color "Error"
        return
    }

    # Section selection (System Info is always included)
    if ($Sections.Count -eq 0) {
        Write-OutputColor "  Select report sections (System Info is always included):" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [1] Performance Metrics  (CPU, Memory, Top Processes)" -color "Info"
        Write-OutputColor "  [2] Storage Health       (Disks, I/O Latency)" -color "Info"
        Write-OutputColor "  [3] Network              (Adapters, NIC Errors)" -color "Info"
        Write-OutputColor "  [4] Security Status      (Firewall, Defender, Certs, Events)" -color "Info"
        Write-OutputColor "  [A] All sections" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Enter choices (e.g. 1,2,3 or A for all):" -color "Info"
        $sectionChoice = Read-Host "  "
        $navResult = Test-NavigationCommand -UserInput $sectionChoice
        if ($navResult.ShouldReturn) { return }

        if ($sectionChoice -match '[Aa]' -or [string]::IsNullOrWhiteSpace($sectionChoice)) {
            $Sections = @("Performance", "Storage", "Network", "Security")
        } else {
            $Sections = @()
            if ($sectionChoice -match '1') { $Sections += "Performance" }
            if ($sectionChoice -match '2') { $Sections += "Storage" }
            if ($sectionChoice -match '3') { $Sections += "Network" }
            if ($sectionChoice -match '4') { $Sections += "Security" }
            if ($Sections.Count -eq 0) { $Sections = @("Performance", "Storage", "Network", "Security") }
        }
    }

    $includePerformance = $Sections -contains "Performance"
    $includeStorage = $Sections -contains "Storage"
    $includeNetwork = $Sections -contains "Network"
    $includeSecurity = $Sections -contains "Security"

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Gathering system information..." -color "Info"

    # Gather data (CIM with timeout — immune to WMI hangs)
    $cimResult = Invoke-WithTimeout -ScriptBlock {
        @{
            OS  = Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec 8 -ErrorAction SilentlyContinue
            CS  = Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec 8 -ErrorAction SilentlyContinue
            CPU = Get-CimInstance -ClassName Win32_Processor -OperationTimeoutSec 8 -ErrorAction SilentlyContinue
        }
    } -TimeoutSeconds 15 -Activity "Querying system info"

    if ($cimResult.TimedOut) {
        Write-OutputColor "  WMI/CIM query timed out. Report will have limited data." -color "Warning"
        $os = $null; $cs = $null; $cpuAll = $null
    } else {
        $os = $cimResult.Result.OS
        $cs = $cimResult.Result.CS
        $cpuAll = $cimResult.Result.CPU
    }
    $cpu = $cpuAll | Select-Object -First 1
    $uptime = if ($os -and $os.LastBootUpTime) { (Get-Date) - $os.LastBootUpTime } else { $null }
    $uptimeStr = if ($uptime) { "{0} days, {1} hours, {2} minutes" -f $uptime.Days, $uptime.Hours, $uptime.Minutes } else { "Unknown" }

    # CPU load (always gathered for issues summary)
    $cpuLoadMeasure = if ($cpuAll) { ($cpuAll | Measure-Object -Property LoadPercentage -Average).Average } else { $null }
    $cpuLoad = if ($null -ne $cpuLoadMeasure) { $cpuLoadMeasure } else { 0 }
    $cpuStatus = if ($cpuLoad -gt 80) { "bad" } elseif ($cpuLoad -gt 50) { "warn" } else { "good" }

    # Memory (always gathered for issues summary)
    $totalMemGB = if ($os) { [math]::Round($os.TotalVisibleMemorySize / 1MB, 2) } else { 0 }
    $freeMemGB = if ($os) { [math]::Round($os.FreePhysicalMemory / 1MB, 2) } else { 0 }
    $usedMemGB = $totalMemGB - $freeMemGB
    $memPercent = if ($totalMemGB -gt 0) { [math]::Round(($usedMemGB / $totalMemGB) * 100, 1) } else { 0 }
    $memStatus = if ($memPercent -gt 90) { "bad" } elseif ($memPercent -gt 75) { "warn" } else { "good" }

    # Disks (always query for issues summary; HTML only if section selected)
    $diskResult = Invoke-WithTimeout -ScriptBlock {
        Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -OperationTimeoutSec 8 -ErrorAction SilentlyContinue
    } -TimeoutSeconds 10 -Activity "Querying disk info"
    $disks = if ($diskResult.TimedOut) { $null } else { $diskResult.Result }
    $diskHtml = ""
    if ($includeStorage) {
        if (-not $disks) {
            $diskHtml = "<tr><td colspan='5'>Disk information unavailable</td></tr>"
        }
        foreach ($disk in $disks) {
            $totalGB = [math]::Round($disk.Size / 1GB, 1)
            $freeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
            $usedPercent = if ($disk.Size -gt 0) { [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1) } else { 0 }
            $diskStatus = if ($usedPercent -gt 90) { "bad" } elseif ($usedPercent -gt 75) { "warn" } else { "good" }
            $diskHtml += @"
        <tr>
            <td>$(ConvertTo-HtmlSafe $disk.DeviceID)</td>
            <td>$totalGB GB</td>
            <td>$freeGB GB</td>
            <td class="status-$diskStatus">$usedPercent%</td>
            <td><div class="progress-bar"><div class="progress-fill status-bg-$diskStatus" style="width: $usedPercent%"></div></div></td>
        </tr>
"@
        }
    }

    # Network adapters (batch query to avoid N+1)
    $networkHtml = ""
    if ($includeNetwork) {
        $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" }
        $allIPv4Html = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if (-not $adapters) {
            $networkHtml = "<tr><td colspan='4'>No active network adapters found</td></tr>"
        }
        foreach ($adapter in $adapters) {
            $ip = $allIPv4Html | Where-Object { $_.InterfaceAlias -eq $adapter.Name }
            $ipStr = if ($ip) { $ip.IPAddress } else { "No IP" }
            $networkHtml += "<tr><td>$(ConvertTo-HtmlSafe $adapter.Name)</td><td>$(ConvertTo-HtmlSafe $ipStr)</td><td class='status-good'>Up</td><td>$(ConvertTo-HtmlSafe $adapter.LinkSpeed)</td></tr>"
        }
    }

    # Services
    $servicesHtml = ""
    if ($includePerformance) {
        $keyServices = @(
            @{ Name = "wuauserv"; Display = "Windows Update" },
            @{ Name = "WinRM"; Display = "WinRM" },
            @{ Name = "vmms"; Display = "Hyper-V Management" },
            @{ Name = "TermService"; Display = "Remote Desktop" }
        )
        foreach ($svc in $keyServices) {
            $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
            if ($service) {
                $svcStatus = if ($service.Status -eq "Running") { "good" } else { "warn" }
                $servicesHtml += "<tr><td>$(ConvertTo-HtmlSafe $svc.Display)</td><td class='status-$svcStatus'>$(ConvertTo-HtmlSafe $service.Status)</td></tr>"
            }
        }
    }

    # Certificates (Security section)
    $certHtml = ""
    if ($includeSecurity) {
        try {
            $now = Get-Date
            $allCerts = @(Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction SilentlyContinue)
            if ($allCerts.Count -gt 0) {
                foreach ($cert in ($allCerts | Sort-Object NotAfter)) {
                    $subject = if ($cert.Subject) { $cert.Subject } else { "(no subject)" }
                    $daysLeft = [math]::Floor(($cert.NotAfter - $now).TotalDays)
                    $certStatus = if ($daysLeft -lt 0) { "bad" } elseif ($daysLeft -lt 30) { "warn" } else { "good" }
                    $statusTag = if ($daysLeft -lt 0) { "EXPIRED" } elseif ($daysLeft -lt 30) { "EXPIRING" } else { "OK" }
                    $certHtml += "<tr><td>$(ConvertTo-HtmlSafe $subject)</td><td>$($cert.NotAfter.ToString('yyyy-MM-dd'))</td><td>${daysLeft}d</td><td class='status-$certStatus'>$statusTag</td></tr>"
                }
            } else {
                $certHtml = "<tr><td colspan='4'>No certificates in LocalMachine\My store</td></tr>"
            }
        } catch {
            $certHtml = "<tr><td colspan='4'>Certificate check unavailable</td></tr>"
        }
    }

    # Disk I/O Latency (Storage section)
    $diskIOHtml = ""
    if ($includeStorage) {
        $diskIOHtml = "<table><tr><th>Disk</th><th>Metric</th><th>Latency</th><th>Status</th></tr>"
        try {
            $diskCounters = Get-Counter '\PhysicalDisk(*)\Avg. Disk sec/Read', '\PhysicalDisk(*)\Avg. Disk sec/Write' -ErrorAction SilentlyContinue
            if ($diskCounters) {
                foreach ($sample in $diskCounters.CounterSamples) {
                    if ($sample.InstanceName -eq '_total') { continue }
                    $latMs = [math]::Round($sample.CookedValue * 1000, 2)
                    $metricName = if ($sample.Path -match 'Read') { "Read" } else { "Write" }
                    $latStat = if ($latMs -gt 20) { "bad" } elseif ($latMs -gt 10) { "warn" } else { "good" }
                    $diskIOHtml += "<tr><td>$(ConvertTo-HtmlSafe $sample.InstanceName)</td><td>$metricName</td><td>${latMs}ms</td><td class='status-$latStat'>$($latStat.ToUpper())</td></tr>"
                }
            } else { $diskIOHtml += "<tr><td colspan='4'>Performance counters unavailable</td></tr>" }
        } catch { $diskIOHtml += "<tr><td colspan='4'>Unable to read disk I/O counters</td></tr>" }
        $diskIOHtml += "</table>"
    }

    # NIC Error Counters (Network section)
    $nicErrorHtml = ""
    if ($includeNetwork) {
        $nicErrorHtml = "<table><tr><th>Adapter</th><th>InErrors</th><th>OutErrors</th><th>InDiscards</th><th>Status</th></tr>"
        try {
            $nicStats = Get-NetAdapterStatistics -ErrorAction SilentlyContinue
            foreach ($nic in $nicStats) {
                $totalErr = $nic.InErrors + $nic.OutErrors + $nic.InDiscards
                $nicStat = if ($totalErr -gt 0) { "warn" } else { "good" }
                $nicErrorHtml += "<tr><td>$(ConvertTo-HtmlSafe $nic.Name)</td><td>$($nic.InErrors)</td><td>$($nic.OutErrors)</td><td>$($nic.InDiscards)</td><td class='status-$nicStat'>$($nicStat.ToUpper())</td></tr>"
            }
        } catch { $nicErrorHtml += "<tr><td colspan='5'>NIC statistics unavailable</td></tr>" }
        $nicErrorHtml += "</table>"
    }

    # Memory Pressure (Performance section)
    $memPressureHtml = ""
    if ($includePerformance) {
        $memPressureHtml = "<table><tr><th>Metric</th><th>Value</th><th>Status</th></tr>"
        try {
            $memCounters = Get-Counter '\Memory\Pages/sec', '\Memory\Available MBytes' -ErrorAction SilentlyContinue
            if ($memCounters) {
                foreach ($sample in $memCounters.CounterSamples) {
                    $cName = if ($sample.Path -match 'Pages') { "Pages/sec" } else { "Available MB" }
                    $cVal = [math]::Round($sample.CookedValue, 1)
                    $mStat = "good"
                    if ($cName -eq "Pages/sec" -and $cVal -gt 1000) { $mStat = "warn" }
                    if ($cName -eq "Available MB" -and $cVal -lt 500) { $mStat = "bad" } elseif ($cName -eq "Available MB" -and $cVal -lt 2000) { $mStat = "warn" }
                    $memPressureHtml += "<tr><td>$cName</td><td>$cVal</td><td class='status-$mStat'>$($mStat.ToUpper())</td></tr>"
                }
            }
        } catch { $memPressureHtml += "<tr><td colspan='3'>Memory pressure counters unavailable</td></tr>" }
        $memPressureHtml += "</table>"
    }

    # Hyper-V Guest Health (Performance section)
    $hvGuestHtml = ""
    if ($includePerformance -and (Test-HyperVInstalled)) {
        $hvGuestHtml = "<h2>Hyper-V Guest Health</h2><table><tr><th>VM</th><th>Heartbeat</th><th>vCPU</th><th>RAM (GB)</th></tr>"
        try {
            $hvVMs = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Running" }
            if ($hvVMs) {
                foreach ($hvm in $hvVMs) {
                    $hvHb = Get-VMIntegrationService -VM $hvm -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Heartbeat" }
                    $hvHbSt = if ($hvHb -and $hvHb.PrimaryStatusDescription -eq "OK") { "good" } else { "warn" }
                    $hvHbTxt = if ($hvHb) { $hvHb.PrimaryStatusDescription } else { "N/A" }
                    $hvRAM = [math]::Round($hvm.MemoryAssigned / 1GB, 1)
                    $hvGuestHtml += "<tr><td>$(ConvertTo-HtmlSafe $hvm.Name)</td><td class='status-$hvHbSt'>$(ConvertTo-HtmlSafe $hvHbTxt)</td><td>$($hvm.ProcessorCount)</td><td>$hvRAM</td></tr>"
                }
            } else { $hvGuestHtml += "<tr><td colspan='4'>No running VMs</td></tr>" }
        } catch { $hvGuestHtml += "<tr><td colspan='4'>Guest health unavailable</td></tr>" }
        $hvGuestHtml += "</table>"
    }

    # Top 5 CPU Processes (Performance section)
    $topProcsHtml = ""
    if ($includePerformance) {
        $topProcsHtml = "<table><tr><th>Process</th><th>CPU (sec)</th><th>RAM (MB)</th></tr>"
        try {
            $topP = Get-Process -ErrorAction SilentlyContinue | Sort-Object CPU -Descending | Select-Object -First 5
            foreach ($p in $topP) {
                $pCPU = if ($null -ne $p.CPU) { [math]::Round($p.CPU, 1) } else { 0 }
                $pMem = [math]::Round($p.WorkingSet64 / 1MB, 0)
                $topProcsHtml += "<tr><td>$(ConvertTo-HtmlSafe $p.ProcessName)</td><td>$pCPU</td><td>$pMem</td></tr>"
            }
        } catch { $topProcsHtml += "<tr><td colspan='3'>Process information unavailable</td></tr>" }
        $topProcsHtml += "</table>"
    }

    # Time Sync Status (Security section)
    $timeSyncHtml = ""
    $timeSyncSource = "Unknown"
    $timeSyncOffset = $null
    if ($includeSecurity) {
        $timeSyncHtml = "<table><tr><th>Property</th><th>Value</th><th>Status</th></tr>"
        try {
            $w32tmOut = w32tm /query /status 2>&1
            $timeSyncStat = "good"
            foreach ($tsLine in $w32tmOut) {
                $tsText = $tsLine.ToString()
                if ($tsText -match 'Source:\s*(.+)') {
                    $regexMatches = $matches
                    $timeSyncSource = $regexMatches[1].Trim()
                }
                if ($tsText -match 'Phase Offset:\s*([\-\d\.]+)s') {
                    $regexMatches = $matches
                    $timeSyncOffset = [double]$regexMatches[1]
                }
            }
            if ($timeSyncSource -match 'Free-Running|Local CMOS') { $timeSyncStat = "warn" }
            $offsetStr = if ($null -ne $timeSyncOffset) { "$([math]::Round($timeSyncOffset, 3))s" } else { "N/A" }
            $offsetStat = "good"
            if ($null -ne $timeSyncOffset) {
                $absOffset = [math]::Abs($timeSyncOffset)
                if ($absOffset -gt 30) { $offsetStat = "bad" } elseif ($absOffset -gt 5) { $offsetStat = "warn" }
            }
            $timeSyncHtml += "<tr><td>Source</td><td>$(ConvertTo-HtmlSafe $timeSyncSource)</td><td class='status-$timeSyncStat'>$(if ($timeSyncStat -eq 'good') { 'OK' } else { 'CHECK' })</td></tr>"
            $timeSyncHtml += "<tr><td>Phase Offset</td><td>$(ConvertTo-HtmlSafe $offsetStr)</td><td class='status-$offsetStat'>$(if ($offsetStat -eq 'good') { 'OK' } elseif ($offsetStat -eq 'warn') { 'DRIFT' } else { 'HIGH DRIFT' })</td></tr>"
        } catch {
            $timeSyncHtml += "<tr><td colspan='3'>Time sync status unavailable</td></tr>"
        }
        $timeSyncHtml += "</table>"
    }

    # Firewall Status (Security section)
    # Always query firewall for issues summary
    $fwProfiles = try { Get-NetFirewallProfile -ErrorAction SilentlyContinue } catch { $null }
    $firewallHtml = ""
    if ($includeSecurity) {
        $firewallHtml = "<table><tr><th>Profile</th><th>Enabled</th><th>Status</th></tr>"
        try {
            foreach ($fwProf in $fwProfiles) {
                $fwOn = $fwProf.Enabled -eq $true
                $fwStat = if ($fwOn) { "good" } else { "bad" }
                $fwText = if ($fwOn) { "Enabled" } else { "DISABLED" }
                $firewallHtml += "<tr><td>$(ConvertTo-HtmlSafe $fwProf.Name)</td><td class='status-$fwStat'>$fwText</td><td class='status-$fwStat'>$(if ($fwOn) { 'OK' } else { 'WARNING' })</td></tr>"
            }
        } catch {
            $firewallHtml += "<tr><td colspan='3'>Firewall status unavailable</td></tr>"
        }
        $firewallHtml += "</table>"
    }

    # Always query critical events for issues summary
    $critEvents = @(try { Get-WinEvent -FilterHashtable @{LogName='System','Application'; Level=1,2; StartTime=(Get-Date).AddHours(-24)} -MaxEvents 10 -ErrorAction SilentlyContinue } catch { })
    $critEventsHtml = ""
    if ($includeSecurity) {
        $critEventsHtml = "<table><tr><th>Time</th><th>Source</th><th>ID</th><th>Message</th></tr>"
        try {
            if ($critEvents.Count -gt 0) {
                foreach ($evt in ($critEvents | Select-Object -First 5)) {
                    $evtMsg = if ($evt.Message) { $evt.Message.Split("`n")[0] } else { "N/A" }
                    if ($evtMsg.Length -gt 80) { $evtMsg = $evtMsg.Substring(0, 77) + "..." }
                    $critEventsHtml += "<tr><td>$($evt.TimeCreated.ToString('MM/dd HH:mm'))</td><td>$(ConvertTo-HtmlSafe $evt.ProviderName)</td><td>$($evt.Id)</td><td>$(ConvertTo-HtmlSafe $evtMsg)</td></tr>"
                }
            } else {
                $critEventsHtml += "<tr><td colspan='4' class='status-good'>No critical/error events in last 24 hours</td></tr>"
            }
        } catch {
            $critEventsHtml += "<tr><td colspan='4'>Event log query unavailable</td></tr>"
        }
        $critEventsHtml += "</table>"
    }

    # Issues summary
    $issues = @()
    if ($cpuLoad -gt 80) { $issues += "High CPU usage ($([math]::Round($cpuLoad, 1))%)" }
    if ($memPercent -gt 90) { $issues += "High memory usage ($memPercent%)" }
    foreach ($disk in $disks) {
        $usedPercent = if ($disk.Size -gt 0) { [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1) } else { 0 }
        if ($usedPercent -gt 90) { $issues += "Low disk space on $($disk.DeviceID) ($usedPercent% used)" }
    }
    if (Test-RebootPending) { $issues += "Reboot pending" }
    if ($null -ne $timeSyncOffset -and [math]::Abs($timeSyncOffset) -gt 30) { $issues += "Time sync offset > 30s" }
    if ($timeSyncSource -match 'Free-Running|Local CMOS') { $issues += "No external time source configured" }
    # Event log capacity check
    try {
        foreach ($logName in @('Application', 'System', 'Security')) {
            $evtLog = Get-WinEvent -ListLog $logName -ErrorAction SilentlyContinue
            if ($null -ne $evtLog -and $evtLog.MaximumSizeInBytes -gt 0) {
                $logPct = [math]::Round(($evtLog.FileSize / $evtLog.MaximumSizeInBytes) * 100, 1)
                if ($logPct -ge 90) { $issues += "$logName event log near capacity ($logPct%)" }
            }
        }
    } catch { }
    try {
        foreach ($fwProf in $fwProfiles) {
            if ($fwProf.Enabled -ne $true) { $issues += "Firewall profile '$($fwProf.Name)' disabled"; break }
        }
    } catch { }
    if ($critEvents.Count -ge 5) { $issues += "$($critEvents.Count) critical/error events in last 24h" }

    $overallStatus = if ($issues.Count -eq 0) { "good" } elseif ($issues.Count -le 2) { "warn" } else { "bad" }
    $overallText = if ($issues.Count -eq 0) { "HEALTHY" } else { "ATTENTION NEEDED" }
    $issuesHtml = if ($issues.Count -eq 0) { "<li class='status-good'>No issues detected</li>" } else { ($issues | ForEach-Object { "<li class='status-warn'>$(ConvertTo-HtmlSafe $_)</li>" }) -join "`n" }

    # Build conditional HTML sections
    $performanceSectionHtml = ""
    if ($includePerformance) {
        $performanceSectionHtml = @"
        <h2>CPU</h2>
        <div class="info-grid">
            <div class="info-box"><div class="info-label">Processor</div><div class="info-value">$(if ($cpu) { ConvertTo-HtmlSafe $cpu.Name } else { 'Unknown' })</div></div>
            <div class="info-box"><div class="info-label">Cores / Logical</div><div class="info-value">$(if ($cpu) { "$($cpu.NumberOfCores) / $($cpu.NumberOfLogicalProcessors)" } else { 'N/A' })</div></div>
            <div class="info-box"><div class="info-label">Current Load</div><div class="info-value status-$cpuStatus">$([math]::Round($cpuLoad, 1))%</div></div>
        </div>

        <h2>Memory</h2>
        <div class="info-grid">
            <div class="info-box"><div class="info-label">Total</div><div class="info-value">$totalMemGB GB</div></div>
            <div class="info-box"><div class="info-label">Used</div><div class="info-value status-$memStatus">$usedMemGB GB ($memPercent%)</div></div>
            <div class="info-box"><div class="info-label">Free</div><div class="info-value">$freeMemGB GB</div></div>
        </div>

        <h2>Memory Pressure</h2>
        $memPressureHtml

        $hvGuestHtml

        <h2>Top 5 CPU Processes</h2>
        $topProcsHtml

        <h2>Key Services</h2>
        <table>
            <tr><th>Service</th><th>Status</th></tr>
            $servicesHtml
        </table>
"@
    }

    $storageSectionHtml = ""
    if ($includeStorage) {
        $storageSectionHtml = @"
        <h2>Disk Space</h2>
        <table>
            <tr><th>Drive</th><th>Total</th><th>Free</th><th>Used %</th><th>Usage</th></tr>
            $diskHtml
        </table>

        <h2>Disk I/O Latency</h2>
        $diskIOHtml
"@
    }

    $networkSectionHtml = ""
    if ($includeNetwork) {
        $networkSectionHtml = @"
        <h2>Network Adapters</h2>
        <table>
            <tr><th>Adapter</th><th>IP Address</th><th>Status</th><th>Speed</th></tr>
            $networkHtml
        </table>

        <h2>NIC Error Counters</h2>
        $nicErrorHtml
"@
    }

    $securitySectionHtml = ""
    if ($includeSecurity) {
        $securitySectionHtml = @"
        <h2>Certificates</h2>
        <table>
            <tr><th>Subject</th><th>Expires</th><th>Days Left</th><th>Status</th></tr>
            $certHtml
        </table>

        <h2>Time Sync</h2>
        $timeSyncHtml

        <h2>Firewall Status</h2>
        $firewallHtml

        <h2>Recent Critical Events (24h)</h2>
        $critEventsHtml
"@
    }

    # Build HTML
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Server Health Report - $(ConvertTo-HtmlSafe $cs.Name)</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #0078d4; margin-top: 30px; }
        .status-good { color: #28a745; font-weight: bold; }
        .status-warn { color: #ffc107; font-weight: bold; }
        .status-bad { color: #dc3545; font-weight: bold; }
        .status-bg-good { background: #28a745; }
        .status-bg-warn { background: #ffc107; }
        .status-bg-bad { background: #dc3545; }
        .summary-box { padding: 20px; border-radius: 8px; margin: 20px 0; }
        .summary-good { background: #d4edda; border: 1px solid #28a745; }
        .summary-warn { background: #fff3cd; border: 1px solid #ffc107; }
        .summary-bad { background: #f8d7da; border: 1px solid #dc3545; }
        table { border-collapse: collapse; width: 100%; margin: 15px 0; }
        th, td { border: 1px solid #dee2e6; padding: 10px; text-align: left; }
        th { background: #343a40; color: white; }
        tr:nth-child(even) { background: #f8f9fa; }
        .progress-bar { background: #e9ecef; border-radius: 4px; height: 20px; width: 150px; }
        .progress-fill { height: 100%; border-radius: 4px; }
        .info-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 20px; }
        .info-box { background: #f8f9fa; padding: 15px; border-radius: 8px; border: 1px solid #dee2e6; }
        .info-label { color: #666; font-size: 12px; text-transform: uppercase; }
        .info-value { font-size: 18px; font-weight: bold; color: #333; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #dee2e6; color: #666; font-size: 12px; }
        @media (prefers-color-scheme: dark) {
            body { background-color: #1a1a2e; color: #e0e0e0; }
            .container { background: #16213e; }
            h1 { color: #e0e0e0; }
            h2 { color: #5dade2; }
            table { border-color: #444; }
            th { background-color: #16213e; color: #e0e0e0; }
            td { border-color: #333; }
            tr:nth-child(even) { background: #1a2744; }
            .info-box { background: #1a2744; border-color: #333; }
            .info-label { color: #aaa; }
            .info-value { color: #e0e0e0; }
            .summary-good { background: #1b4332; border-color: #28a745; }
            .summary-warn { background: #3d2e00; border-color: #ffc107; }
            .summary-bad { background: #3d1014; border-color: #dc3545; }
            .status-warn { color: #ffa726; }
            .status-bad { color: #ef5350; }
            .status-good { color: #66bb6a; }
            .footer { border-color: #444; color: #999; }
        }
        .dark-mode { background-color: #1a1a2e !important; color: #e0e0e0 !important; }
        .dark-mode .container { background: #16213e !important; }
        .dark-mode h1 { color: #e0e0e0 !important; }
        .dark-mode h2 { color: #5dade2 !important; }
        .dark-mode table { border-color: #444 !important; }
        .dark-mode th { background-color: #16213e !important; color: #e0e0e0 !important; }
        .dark-mode td { border-color: #333 !important; }
        .dark-mode tr:nth-child(even) { background: #1a2744 !important; }
        .dark-mode .info-box { background: #1a2744 !important; border-color: #333 !important; }
        .dark-mode .info-label { color: #aaa !important; }
        .dark-mode .info-value { color: #e0e0e0 !important; }
        .dark-mode .summary-good { background: #1b4332 !important; border-color: #28a745 !important; }
        .dark-mode .summary-warn { background: #3d2e00 !important; border-color: #ffc107 !important; }
        .dark-mode .summary-bad { background: #3d1014 !important; border-color: #dc3545 !important; }
        .dark-mode .status-warn { color: #ffa726 !important; }
        .dark-mode .status-bad { color: #ef5350 !important; }
        .dark-mode .status-good { color: #66bb6a !important; }
        .dark-mode .footer { border-color: #444 !important; color: #999 !important; }
    </style>
</head>
<body>
    <button onclick="document.body.classList.toggle('dark-mode')" style="position:fixed;top:10px;right:10px;padding:5px 10px;cursor:pointer;z-index:1000;border-radius:4px;border:1px solid #ccc;">Toggle Dark Mode</button>
    <div class="container">
        <h1>Server Health Report</h1>
        <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>

        <div class="summary-box summary-$overallStatus">
            <h2 style="margin-top:0;">Overall Status: <span class="status-$overallStatus">$overallText</span></h2>
            <ul>$issuesHtml</ul>
        </div>

        <h2>System Information</h2>
        <div class="info-grid">
            <div class="info-box"><div class="info-label">Computer Name</div><div class="info-value">$(ConvertTo-HtmlSafe $cs.Name)</div></div>
            <div class="info-box"><div class="info-label">Operating System</div><div class="info-value">$(ConvertTo-HtmlSafe $os.Caption)</div></div>
            <div class="info-box"><div class="info-label">OS Version</div><div class="info-value">$(ConvertTo-HtmlSafe $os.Version)</div></div>
            <div class="info-box"><div class="info-label">Uptime</div><div class="info-value">$(ConvertTo-HtmlSafe $uptimeStr)</div></div>
        </div>

        $performanceSectionHtml

        $storageSectionHtml

        $networkSectionHtml

        $securitySectionHtml

        <div class="footer">
            Report generated by $(ConvertTo-HtmlSafe $script:ToolFullName) v$(ConvertTo-HtmlSafe $script:ScriptVersion)
        </div>
    </div>
</body>
</html>
"@

    try {
        $html | Out-File -LiteralPath $OutputPath -Encoding UTF8 -Force
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Report saved to: $OutputPath" -color "Success"
        Add-SessionChange -Category "Report" -Description "Generated HTML health report"

        Write-OutputColor "" -color "Info"
        if (Confirm-UserAction -Message "Open report in browser?") {
            Start-Process $OutputPath
        }
    }
    catch {
        Write-OutputColor "  Error saving report: $_" -color "Error"
    }
}

# Function to export profile comparison as HTML
function Export-ProfileComparisonHTML {
    param(
        [string]$Profile1Path,
        [string]$Profile2Path,
        [string]$OutputPath = "$env:USERPROFILE\Desktop\ProfileComparison_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    )

    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                   EXPORT PROFILE COMPARISON (HTML)").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Get first profile if not provided
    if (-not $Profile1Path) {
        Write-OutputColor "  Enter path to FIRST profile:" -color "Info"
        $Profile1Path = Read-Host "  "
        $navResult = Test-NavigationCommand -UserInput $Profile1Path
        if ($navResult.ShouldReturn) { return }
    }

    $Profile1Path = $Profile1Path.Trim('"')
    if ([string]::IsNullOrWhiteSpace($Profile1Path)) {
        Write-OutputColor "  No path entered." -color "Error"
        return
    }
    if (-not (Test-Path -LiteralPath $Profile1Path)) {
        Write-OutputColor "  File not found: $Profile1Path" -color "Error"
        return
    }

    # Get second profile if not provided
    if (-not $Profile2Path) {
        Write-OutputColor "  Enter path to SECOND profile:" -color "Info"
        $Profile2Path = Read-Host "  "
        $navResult = Test-NavigationCommand -UserInput $Profile2Path
        if ($navResult.ShouldReturn) { return }
    }

    $Profile2Path = $Profile2Path.Trim('"')
    if ([string]::IsNullOrWhiteSpace($Profile2Path)) {
        Write-OutputColor "  No path entered." -color "Error"
        return
    }
    if (-not (Test-Path -LiteralPath $Profile2Path)) {
        Write-OutputColor "  File not found: $Profile2Path" -color "Error"
        return
    }

    # Validate output directory exists
    $outputDir = Split-Path -Parent $OutputPath
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        Write-OutputColor "  Output directory does not exist: $outputDir" -color "Error"
        return
    }

    try {
        $profile1 = Get-Content -LiteralPath $Profile1Path -Raw | ConvertFrom-Json
        $profile2 = Get-Content -LiteralPath $Profile2Path -Raw | ConvertFrom-Json
    }
    catch {
        Write-OutputColor "  Error parsing JSON files: $_" -color "Error"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Comparing profiles..." -color "Info"

    # Get all properties
    $allProps = @()
    $profile1.PSObject.Properties | ForEach-Object { $allProps += $_.Name }
    $profile2.PSObject.Properties | ForEach-Object { if ($_.Name -notin $allProps) { $allProps += $_.Name } }
    $allProps = $allProps | Where-Object { $_ -notlike "_*" } | Sort-Object -Unique

    # Build comparison rows
    $rowsHtml = ""
    $added = 0
    $removed = 0
    $changed = 0

    foreach ($prop in $allProps) {
        $val1 = $profile1.$prop
        $val2 = $profile2.$prop

        $hasVal1 = $null -ne $val1
        $hasVal2 = $null -ne $val2

        $eProp = ConvertTo-HtmlSafe $prop
        $eVal1 = ConvertTo-HtmlSafe "$val1"
        $eVal2 = ConvertTo-HtmlSafe "$val2"
        if ($hasVal1 -and -not $hasVal2) {
            $rowsHtml += "<tr class='removed'><td>$eProp</td><td>$eVal1</td><td><em>(removed)</em></td><td>Removed</td></tr>"
            $removed++
        }
        elseif (-not $hasVal1 -and $hasVal2) {
            $rowsHtml += "<tr class='added'><td>$eProp</td><td><em>(none)</em></td><td>$eVal2</td><td>Added</td></tr>"
            $added++
        }
        elseif ((ConvertTo-Json $val1 -Compress -Depth 5) -ne (ConvertTo-Json $val2 -Compress -Depth 5)) {
            $rowsHtml += "<tr class='changed'><td>$eProp</td><td>$eVal1</td><td>$eVal2</td><td>Changed</td></tr>"
            $changed++
        }
        else {
            $rowsHtml += "<tr><td>$eProp</td><td>$eVal1</td><td>$eVal2</td><td>Same</td></tr>"
        }
    }

    $totalDiffs = $added + $removed + $changed
    $summaryText = if ($totalDiffs -eq 0) { "Profiles are identical" } else { "$totalDiffs difference(s): $added added, $removed removed, $changed changed" }

    # Build HTML
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Profile Comparison</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: 'Segoe UI', sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        .summary { padding: 15px; background: #f8f9fa; border-radius: 8px; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; margin: 15px 0; }
        th, td { border: 1px solid #dee2e6; padding: 10px; text-align: left; }
        th { background: #343a40; color: white; }
        .added { background: #d4edda; }
        .removed { background: #f8d7da; }
        .changed { background: #fff3cd; }
        .file-name { font-family: monospace; background: #e9ecef; padding: 2px 6px; border-radius: 4px; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #dee2e6; color: #666; font-size: 12px; }
        @media (prefers-color-scheme: dark) {
            body { background-color: #1a1a2e; color: #e0e0e0; }
            .container { background: #16213e; }
            h1 { color: #e0e0e0; }
            table { border-color: #444; }
            th { background-color: #16213e; color: #e0e0e0; }
            td { border-color: #333; }
            .summary { background: #1a2744; }
            .added { background: #1b4332; }
            .removed { background: #3d1014; }
            .changed { background: #3d2e00; }
            .file-name { background: #2a3a5e; }
            .footer { border-color: #444; color: #999; }
        }
        .dark-mode { background-color: #1a1a2e !important; color: #e0e0e0 !important; }
        .dark-mode .container { background: #16213e !important; }
        .dark-mode h1 { color: #e0e0e0 !important; }
        .dark-mode table { border-color: #444 !important; }
        .dark-mode th { background-color: #16213e !important; color: #e0e0e0 !important; }
        .dark-mode td { border-color: #333 !important; }
        .dark-mode .summary { background: #1a2744 !important; }
        .dark-mode .added { background: #1b4332 !important; }
        .dark-mode .removed { background: #3d1014 !important; }
        .dark-mode .changed { background: #3d2e00 !important; }
        .dark-mode .file-name { background: #2a3a5e !important; }
        .dark-mode .footer { border-color: #444 !important; color: #999 !important; }
    </style>
</head>
<body>
    <button onclick="document.body.classList.toggle('dark-mode')" style="position:fixed;top:10px;right:10px;padding:5px 10px;cursor:pointer;z-index:1000;border-radius:4px;border:1px solid #ccc;">Toggle Dark Mode</button>
    <div class="container">
        <h1>Configuration Profile Comparison</h1>
        <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>

        <div class="summary">
            <strong>Profile 1:</strong> <span class="file-name">$(ConvertTo-HtmlSafe (Split-Path $Profile1Path -Leaf))</span><br>
            <strong>Profile 2:</strong> <span class="file-name">$(ConvertTo-HtmlSafe (Split-Path $Profile2Path -Leaf))</span><br><br>
            <strong>Result:</strong> $(ConvertTo-HtmlSafe $summaryText)
        </div>

        <table>
            <tr><th>Property</th><th>Profile 1</th><th>Profile 2</th><th>Status</th></tr>
            $rowsHtml
        </table>

        <div class="footer">
            Report generated by $(ConvertTo-HtmlSafe $script:ToolFullName) v$(ConvertTo-HtmlSafe $script:ScriptVersion)
        </div>
    </div>
</body>
</html>
"@

    try {
        $html | Out-File -LiteralPath $OutputPath -Encoding UTF8 -Force
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Comparison saved to: $OutputPath" -color "Success"
        Add-SessionChange -Category "Report" -Description "Generated HTML profile comparison"

        Write-OutputColor "" -color "Info"
        if (Confirm-UserAction -Message "Open comparison in browser?") {
            Start-Process $OutputPath
        }
    }
    catch {
        Write-OutputColor "  Error saving comparison: $_" -color "Error"
    }
}

# Function to generate HTML server readiness report
function Get-ReadinessChecks {
    <#
    .SYNOPSIS
        Returns structured readiness check results as an array of hashtables.
        Reusable by both Export-HTMLReadinessReport and CLI Compliance action.
    #>
    $checks = [System.Collections.Generic.List[object]]::new()

    # Hostname
    $hostname = $env:COMPUTERNAME
    $isDefault = $hostname -match '^WIN-|^DESKTOP-|^YOURSERVERNAME'
    if (-not $isDefault) {
        $checks.Add(@{ Category = "Identity"; Name = "Hostname"; Value = $hostname; Status = "OK" })
    } else {
        $checks.Add(@{ Category = "Identity"; Name = "Hostname"; Value = "$hostname (default)"; Status = "Fail" })
    }

    # Domain
    $csResult = Invoke-WithTimeout -ScriptBlock { Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec 8 -ErrorAction SilentlyContinue } -TimeoutSeconds 10 -Activity "Checking domain"
    $cs = if ($csResult.TimedOut) { $null } else { $csResult.Result }
    if ($cs -and $cs.PartOfDomain) {
        $checks.Add(@{ Category = "Identity"; Name = "Domain"; Value = $cs.Domain; Status = "OK" })
    } else {
        $checks.Add(@{ Category = "Identity"; Name = "Domain"; Value = "WORKGROUP"; Status = "Warn" })
    }

    # Site Number
    $siteNum = Get-SiteNumberFromHostname
    if ($siteNum) {
        $checks.Add(@{ Category = "Identity"; Name = "Site Number"; Value = $siteNum; Status = "OK" })
    } else {
        $checks.Add(@{ Category = "Identity"; Name = "Site Number"; Value = "Not detected"; Status = "Warn" })
    }

    # RDP
    $rdp = Get-RDPState
    if ($rdp -eq "Enabled") {
        $checks.Add(@{ Category = "Remote Access"; Name = "RDP"; Value = "Enabled"; Status = "OK" })
    } else {
        $checks.Add(@{ Category = "Remote Access"; Name = "RDP"; Value = "Disabled"; Status = "Warn" })
    }

    # WinRM
    $winrm = Get-WinRMState
    if ($winrm -eq "Enabled") {
        $checks.Add(@{ Category = "Remote Access"; Name = "WinRM"; Value = "Enabled"; Status = "OK" })
    } else {
        $checks.Add(@{ Category = "Remote Access"; Name = "WinRM"; Value = $winrm; Status = "Warn" })
    }

    # Agent (only if configured)
    if (Test-AgentInstallerConfigured) {
        $agentCheck = Test-AgentInstalled
        if ($agentCheck.Installed) {
            $kVal = if ($agentCheck.Status -eq "Running") { "Running" } else { "$($agentCheck.Status)" }
            $checks.Add(@{ Category = "Software"; Name = "$($script:AgentInstaller.ToolName) Agent"; Value = $kVal; Status = "OK" })
        } else {
            $checks.Add(@{ Category = "Software"; Name = "$($script:AgentInstaller.ToolName) Agent"; Value = "Not Installed"; Status = "Fail" })
        }
    }

    # Hyper-V
    if (Test-HyperVInstalled) {
        $checks.Add(@{ Category = "Roles"; Name = "Hyper-V"; Value = "Installed"; Status = "OK" })
    } else {
        $checks.Add(@{ Category = "Roles"; Name = "Hyper-V"; Value = "Not Installed"; Status = "Warn" })
    }

    # Server-only roles
    if (Test-WindowsServer) {
        if (Test-MPIOInstalled) {
            $checks.Add(@{ Category = "Roles"; Name = "MPIO"; Value = "Installed"; Status = "OK" })
        } else {
            $checks.Add(@{ Category = "Roles"; Name = "MPIO"; Value = "Not Installed"; Status = "Warn" })
        }

        if (Test-FailoverClusteringInstalled) {
            $checks.Add(@{ Category = "Roles"; Name = "Failover Clustering"; Value = "Installed"; Status = "OK" })
        } else {
            $checks.Add(@{ Category = "Roles"; Name = "Failover Clustering"; Value = "Not Installed"; Status = "Warn" })
        }
    }

    # Firewall
    $fw = Get-FirewallState
    if ($fw.Domain -eq "Enabled" -and $fw.Private -eq "Enabled" -and $fw.Public -eq "Enabled") {
        $checks.Add(@{ Category = "Network"; Name = "Firewall"; Value = "All profiles enabled"; Status = "OK" })
    } else {
        $disabled = @()
        if ($fw.Domain -ne "Enabled") { $disabled += "Domain" }
        if ($fw.Private -ne "Enabled") { $disabled += "Private" }
        if ($fw.Public -ne "Enabled") { $disabled += "Public" }
        $checks.Add(@{ Category = "Network"; Name = "Firewall"; Value = "Disabled: $($disabled -join ', ')"; Status = "Warn" })
    }

    # Network adapters
    $nics = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" })
    if ($nics.Count -gt 0) {
        $checks.Add(@{ Category = "Network"; Name = "Adapters"; Value = "$($nics.Count) up"; Status = "OK" })
    } else {
        $checks.Add(@{ Category = "Network"; Name = "Adapters"; Value = "None up"; Status = "Fail" })
    }

    # Power plan
    $power = Get-CurrentPowerPlan
    if ($power.Name -eq "High performance") {
        $checks.Add(@{ Category = "System"; Name = "Power Plan"; Value = "High Performance"; Status = "OK" })
    } else {
        $checks.Add(@{ Category = "System"; Name = "Power Plan"; Value = $power.Name; Status = "Warn" })
    }

    # Reboot pending
    if (Test-RebootPending) {
        $checks.Add(@{ Category = "System"; Name = "Reboot Pending"; Value = "YES"; Status = "Fail" })
    } else {
        $checks.Add(@{ Category = "System"; Name = "Reboot Pending"; Value = "No"; Status = "OK" })
    }

    # License
    $lic = Test-WindowsActivated
    if ($lic) {
        $checks.Add(@{ Category = "System"; Name = "Windows License"; Value = "Activated"; Status = "OK" })
    } else {
        $checks.Add(@{ Category = "System"; Name = "Windows License"; Value = "Not Activated"; Status = "Warn" })
    }

    # C: Drive space
    try {
        $cVol = Get-Volume -DriveLetter C -ErrorAction Stop
        if ($null -ne $cVol -and $cVol.Size -gt 0) {
            $freeGB = [math]::Round($cVol.SizeRemaining / 1GB, 1)
            $totalGB = [math]::Round($cVol.Size / 1GB, 1)
            $usedPct = [math]::Round((($cVol.Size - $cVol.SizeRemaining) / $cVol.Size) * 100)
            if ($freeGB -lt 5) {
                $checks.Add(@{ Category = "Storage"; Name = "C: Drive Space"; Value = "${freeGB}GB free of ${totalGB}GB ($usedPct% used)"; Status = "Fail" })
            } elseif ($freeGB -lt 20) {
                $checks.Add(@{ Category = "Storage"; Name = "C: Drive Space"; Value = "${freeGB}GB free of ${totalGB}GB ($usedPct% used)"; Status = "Warn" })
            } else {
                $checks.Add(@{ Category = "Storage"; Name = "C: Drive Space"; Value = "${freeGB}GB free of ${totalGB}GB"; Status = "OK" })
            }
        } else {
            $checks.Add(@{ Category = "Storage"; Name = "C: Drive Space"; Value = "Unable to read"; Status = "Warn" })
        }
    } catch {
        $checks.Add(@{ Category = "Storage"; Name = "C: Drive Space"; Value = "Check failed"; Status = "Warn" })
    }

    # DNS Resolution
    try {
        $dnsResult = Resolve-DnsName -Name "dns.msftncsi.com" -Type A -DnsOnly -ErrorAction Stop
        if ($dnsResult) {
            $checks.Add(@{ Category = "Network"; Name = "DNS Resolution"; Value = "Working"; Status = "OK" })
        } else {
            $checks.Add(@{ Category = "Network"; Name = "DNS Resolution"; Value = "No response"; Status = "Warn" })
        }
    } catch {
        $checks.Add(@{ Category = "Network"; Name = "DNS Resolution"; Value = "Failed"; Status = "Fail" })
    }

    # Time Sync
    try {
        $w32tmOut = w32tm /query /status 2>&1
        $tsSource = "Unknown"
        foreach ($tsLine in $w32tmOut) {
            $tsText = $tsLine.ToString()
            if ($tsText -match 'Source:\s*(.+)') { $regexMatches = $matches; $tsSource = $regexMatches[1].Trim() }
        }
        if ($tsSource -match 'Free-Running|Local CMOS') {
            $checks.Add(@{ Category = "System"; Name = "Time Sync"; Value = "No external source ($tsSource)"; Status = "Warn" })
        } else {
            $checks.Add(@{ Category = "System"; Name = "Time Sync"; Value = "Source: $tsSource"; Status = "OK" })
        }
    } catch {
        $checks.Add(@{ Category = "System"; Name = "Time Sync"; Value = "Unable to check"; Status = "Warn" })
    }

    # Disk timeout (iSCSI/SAN environments)
    $iscsiCheck = Get-Service -Name MSiSCSI -ErrorAction SilentlyContinue
    if ($null -ne $iscsiCheck -and $iscsiCheck.Status -eq 'Running') {
        $dtVal = try { (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Disk' -Name 'TimeOutValue' -ErrorAction SilentlyContinue).TimeOutValue } catch { $null }
        $dtNum = if ($null -ne $dtVal) { $dtVal } else { 60 }
        if ($dtNum -ge 60) {
            $checks.Add(@{ Category = "Storage"; Name = "Disk Timeout"; Value = "${dtNum}s"; Status = "OK" })
        } else {
            $checks.Add(@{ Category = "Storage"; Name = "Disk Timeout"; Value = "${dtNum}s (need 60+ for SAN)"; Status = "Fail" })
        }
    }

    # Windows Defender
    try {
        $mpStat = Get-MpComputerStatus -ErrorAction Stop
        if ($mpStat.RealTimeProtectionEnabled) {
            $checks.Add(@{ Category = "Security"; Name = "Defender Real-Time"; Value = "Enabled"; Status = "OK" })
        } else {
            $checks.Add(@{ Category = "Security"; Name = "Defender Real-Time"; Value = "DISABLED"; Status = "Fail" })
        }
        # Signature age
        $sigAge = $mpStat.AntivirusSignatureAge
        if ($null -ne $sigAge) {
            $sigStatus = if ($sigAge -le 3) { "OK" } elseif ($sigAge -le 7) { "Warn" } else { "Fail" }
            $checks.Add(@{ Category = "Security"; Name = "Defender Signatures"; Value = "$sigAge day(s) old"; Status = $sigStatus })
        }
    } catch {
        $checks.Add(@{ Category = "Security"; Name = "Defender Real-Time"; Value = "Unavailable"; Status = "Warn" })
    }

    return @($checks)
}

function Export-HTMLReadinessReport {
    param(
        [string]$OutputPath = "$env:USERPROFILE\Desktop\ReadinessReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    )

    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                   GENERATE READINESS REPORT (HTML)").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Default path: $OutputPath" -color "Info"
    Write-OutputColor "" -color "Info"

    $useDefault = Confirm-UserAction -Message "Use default path?" -DefaultYes
    if (-not $useDefault) {
        Write-OutputColor "  Enter output path:" -color "Info"
        $customPath = Read-Host "  "
        $navResult = Test-NavigationCommand -UserInput $customPath
        if ($navResult.ShouldReturn) { return }
        if (-not [string]::IsNullOrWhiteSpace($customPath)) {
            $OutputPath = $customPath.Trim('"')
        }
    }

    # Validate output directory exists
    $outputDir = Split-Path -Parent $OutputPath
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        Write-OutputColor "  Directory does not exist: $outputDir" -color "Error"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Gathering readiness data..." -color "Info"

    # Use shared Get-ReadinessChecks function
    $readinessChecks = Get-ReadinessChecks
    $total = $readinessChecks.Count
    $ready = @($readinessChecks | Where-Object { $_.Status -eq 'OK' }).Count
    $rows = ""

    # Helper to add a check row
    function Add-ReadinessRow {
        param([string]$Cat, [string]$Name, [string]$Value, [string]$Status)
        $class = switch ($Status) { "OK" { "good" }; "Warn" { "warn" }; "Fail" { "bad" }; default { "good" } }
        $icon = switch ($Status) { "OK" { "&#10004;" }; "Warn" { "&#9888;" }; "Fail" { "&#10008;" }; default { "?" } }
        return "<tr><td>$(ConvertTo-HtmlSafe $Cat)</td><td>$(ConvertTo-HtmlSafe $Name)</td><td class='status-$class'>$icon $(ConvertTo-HtmlSafe $Value)</td></tr>"
    }

    foreach ($chk in $readinessChecks) {
        $rows += Add-ReadinessRow -Cat $chk.Category -Name $chk.Name -Value $chk.Value -Status $chk.Status
    }

    # Get domain info for report title (from checks)
    $csResult = Invoke-WithTimeout -ScriptBlock { Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec 8 -ErrorAction SilentlyContinue } -TimeoutSeconds 10 -Activity "Getting hostname"
    $cs = if ($csResult.TimedOut) { $null } else { $csResult.Result }

    $pct = if ($total -gt 0) { [math]::Round(($ready / $total) * 100) } else { 0 }
    $overallStatus = if ($pct -ge 80) { "good" } elseif ($pct -ge 50) { "warn" } else { "bad" }
    $overallText = if ($pct -ge 80) { "READY" } elseif ($pct -ge 50) { "PARTIALLY READY" } else { "NOT READY" }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Server Readiness Report - $(ConvertTo-HtmlSafe $cs.Name)</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 900px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        .status-good { color: #28a745; font-weight: bold; }
        .status-warn { color: #ffc107; font-weight: bold; }
        .status-bad { color: #dc3545; font-weight: bold; }
        .summary-box { padding: 20px; border-radius: 8px; margin: 20px 0; text-align: center; }
        .summary-good { background: #d4edda; border: 2px solid #28a745; }
        .summary-warn { background: #fff3cd; border: 2px solid #ffc107; }
        .summary-bad { background: #f8d7da; border: 2px solid #dc3545; }
        .score { font-size: 48px; font-weight: bold; margin: 10px 0; }
        .score-good { color: #28a745; }
        .score-warn { color: #ffc107; }
        .score-bad { color: #dc3545; }
        .progress-outer { background: #e9ecef; border-radius: 10px; height: 30px; margin: 15px auto; max-width: 400px; }
        .progress-inner { height: 100%; border-radius: 10px; transition: width 0.3s; }
        .bg-good { background: #28a745; }
        .bg-warn { background: #ffc107; }
        .bg-bad { background: #dc3545; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #dee2e6; padding: 10px 15px; text-align: left; }
        th { background: #343a40; color: white; }
        tr:nth-child(even) { background: #f8f9fa; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #dee2e6; color: #666; font-size: 12px; }
        .info { display: flex; gap: 20px; margin: 15px 0; }
        .info-item { background: #f8f9fa; padding: 10px 15px; border-radius: 8px; flex: 1; }
        .info-label { font-size: 11px; color: #666; text-transform: uppercase; }
        .info-value { font-size: 16px; font-weight: bold; }
        @media (prefers-color-scheme: dark) {
            body { background-color: #1a1a2e; color: #e0e0e0; }
            .container { background: #16213e; }
            h1 { color: #e0e0e0; }
            table { border-color: #444; }
            th { background-color: #16213e; color: #e0e0e0; }
            td { border-color: #333; }
            tr:nth-child(even) { background: #1a2744; }
            .summary-good { background: #1b4332; border-color: #28a745; }
            .summary-warn { background: #3d2e00; border-color: #ffc107; }
            .summary-bad { background: #3d1014; border-color: #dc3545; }
            .score-good { color: #66bb6a; }
            .score-warn { color: #ffa726; }
            .score-bad { color: #ef5350; }
            .status-warn { color: #ffa726; }
            .status-bad { color: #ef5350; }
            .status-good { color: #66bb6a; }
            .info-item { background: #1a2744; }
            .info-label { color: #aaa; }
            .info-value { color: #e0e0e0; }
            .footer { border-color: #444; color: #999; }
        }
        .dark-mode { background-color: #1a1a2e !important; color: #e0e0e0 !important; }
        .dark-mode .container { background: #16213e !important; }
        .dark-mode h1 { color: #e0e0e0 !important; }
        .dark-mode table { border-color: #444 !important; }
        .dark-mode th { background-color: #16213e !important; color: #e0e0e0 !important; }
        .dark-mode td { border-color: #333 !important; }
        .dark-mode tr:nth-child(even) { background: #1a2744 !important; }
        .dark-mode .summary-good { background: #1b4332 !important; border-color: #28a745 !important; }
        .dark-mode .summary-warn { background: #3d2e00 !important; border-color: #ffc107 !important; }
        .dark-mode .summary-bad { background: #3d1014 !important; border-color: #dc3545 !important; }
        .dark-mode .score-good { color: #66bb6a !important; }
        .dark-mode .score-warn { color: #ffa726 !important; }
        .dark-mode .score-bad { color: #ef5350 !important; }
        .dark-mode .status-warn { color: #ffa726 !important; }
        .dark-mode .status-bad { color: #ef5350 !important; }
        .dark-mode .status-good { color: #66bb6a !important; }
        .dark-mode .info-item { background: #1a2744 !important; }
        .dark-mode .info-label { color: #aaa !important; }
        .dark-mode .info-value { color: #e0e0e0 !important; }
        .dark-mode .footer { border-color: #444 !important; color: #999 !important; }
    </style>
</head>
<body>
    <button onclick="document.body.classList.toggle('dark-mode')" style="position:fixed;top:10px;right:10px;padding:5px 10px;cursor:pointer;z-index:1000;border-radius:4px;border:1px solid #ccc;">Toggle Dark Mode</button>
    <div class="container">
        <h1>Server Readiness Report</h1>
        <div class="info">
            <div class="info-item"><div class="info-label">Server</div><div class="info-value">$(ConvertTo-HtmlSafe $cs.Name)</div></div>
            <div class="info-item"><div class="info-label">Generated</div><div class="info-value">$(Get-Date -Format 'yyyy-MM-dd HH:mm')</div></div>
            <div class="info-item"><div class="info-label">Tool Version</div><div class="info-value">v$(ConvertTo-HtmlSafe $script:ScriptVersion)</div></div>
        </div>

        <div class="summary-box summary-$overallStatus">
            <div class="score score-$overallStatus">$pct%</div>
            <div><strong>$overallText</strong> - $ready of $total checks passed</div>
            <div class="progress-outer"><div class="progress-inner bg-$overallStatus" style="width: $pct%"></div></div>
        </div>

        <h2>Configuration Checks</h2>
        <table>
            <tr><th>Category</th><th>Check</th><th>Status</th></tr>
            $rows
        </table>

        <div class="footer">
            Report generated by $(ConvertTo-HtmlSafe $script:ToolFullName) v$(ConvertTo-HtmlSafe $script:ScriptVersion)
        </div>
    </div>
</body>
</html>
"@

    try {
        $html | Out-File -LiteralPath $OutputPath -Encoding UTF8 -Force
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Report saved to: $OutputPath" -color "Success"
        Add-SessionChange -Category "Report" -Description "Generated HTML readiness report ($pct% ready)"

        Write-OutputColor "" -color "Info"
        if (Confirm-UserAction -Message "Open report in browser?") {
            Start-Process $OutputPath
        }
    }
    catch {
        Write-OutputColor "  Error saving report: $_" -color "Error"
    }
}

# ============================================================================
# PERFORMANCE TREND REPORTS (v1.7.1)
# ============================================================================

# Save a performance snapshot to JSON
function Save-PerformanceSnapshot {
    $metricsDir = "$script:AppConfigDir\metrics"
    if (-not (Test-Path -LiteralPath $metricsDir)) {
        $null = New-Item -Path $metricsDir -ItemType Directory -Force -ErrorAction SilentlyContinue
    }

    $hostname = $env:COMPUTERNAME
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $snapshotPath = Join-Path $metricsDir "${hostname}_${timestamp}.json"

    try {
        $cimSnap = Invoke-WithTimeout -ScriptBlock {
            @{
                OS   = Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 8 -ErrorAction SilentlyContinue
                CPU  = Get-CimInstance Win32_Processor -OperationTimeoutSec 8 -ErrorAction SilentlyContinue
                Disk = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -OperationTimeoutSec 8 -ErrorAction SilentlyContinue
            }
        } -TimeoutSeconds 15 -Activity "Collecting metrics"

        if ($cimSnap.TimedOut) {
            Write-OutputColor "  CIM query timed out — snapshot skipped." -color "Warning"
            return
        }

        $os = $cimSnap.Result.OS
        $cpuAll = $cimSnap.Result.CPU
        $cpuLoad = ($cpuAll | Measure-Object -Property LoadPercentage -Average).Average
        $totalMemMB = [math]::Round($os.TotalVisibleMemorySize / 1024, 0)
        $freeMemMB = [math]::Round($os.FreePhysicalMemory / 1024, 0)

        # Disk info
        $diskInfo = @()
        $disks = $cimSnap.Result.Disk
        foreach ($disk in $disks) {
            $totalGB = [math]::Round($disk.Size / 1GB, 2)
            $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
            $diskInfo += @{ Drive = $disk.DeviceID; TotalGB = $totalGB; FreeGB = $freeGB; UsedPercent = if ($disk.Size -gt 0) { [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1) } else { 0 } }
        }

        # Network bytes
        $netInfo = @()
        try {
            $netStats = Get-NetAdapterStatistics -ErrorAction Stop
            foreach ($ns in $netStats) {
                $netInfo += @{ Name = $ns.Name; BytesSent = $ns.SentBytes; BytesReceived = $ns.ReceivedBytes; InErrors = $ns.InErrors; OutErrors = $ns.OutErrors }
            }
        } catch { $netInfo = @() }

        $snapshot = [ordered]@{
            Hostname = $hostname
            Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
            CPUPercent = [math]::Round($cpuLoad, 1)
            MemoryTotalMB = $totalMemMB
            MemoryFreeMB = $freeMemMB
            MemoryUsedPercent = if ($totalMemMB -gt 0) { [math]::Round((($totalMemMB - $freeMemMB) / $totalMemMB) * 100, 1) } else { 0 }
            Disks = $diskInfo
            Network = $netInfo
        }

        $snapshot | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $snapshotPath -Encoding UTF8 -Force
        Add-SessionChange -Category "Metrics" -Description "Saved performance snapshot"
        return $snapshotPath
    }
    catch {
        Write-OutputColor "  Failed to save snapshot: $_" -color "Error"
        return $null
    }
}

# Generate a self-contained HTML trend report with CSS-based bar charts
function Export-HTMLTrendReport {
    param(
        [string]$OutputPath = "$env:USERPROFILE\Desktop\TrendReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    )

    $metricsDir = "$script:AppConfigDir\metrics"
    if (-not (Test-Path -LiteralPath $metricsDir)) {
        Write-OutputColor "  No metrics found. Save snapshots first." -color "Warning"
        return
    }

    $files = @(Get-ChildItem -LiteralPath $metricsDir -Filter "*.json" -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($files.Count -eq 0) {
        Write-OutputColor "  No snapshot files found." -color "Warning"
        return
    }

    Write-OutputColor "  Loading $($files.Count) snapshot(s)..." -color "Info"

    $snapshotList = [System.Collections.Generic.List[object]]::new()
    $failedFiles = 0
    foreach ($file in $files) {
        try {
            $data = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            $snapshotList.Add($data)
        } catch {
            $failedFiles++
        }
    }
    $snapshots = @($snapshotList)
    if ($failedFiles -gt 0) {
        Write-OutputColor "  Warning: $failedFiles snapshot file(s) could not be parsed and were skipped." -color "Warning"
    }

    if ($snapshots.Count -eq 0) {
        Write-OutputColor "  No valid snapshots." -color "Warning"
        return
    }

    # Build CSS bar chart rows for CPU and memory
    $cpuRows = ""
    $memRows = ""
    foreach ($snap in $snapshots) {
        $ts = if ($snap.Timestamp) { $snap.Timestamp } else { "?" }
        $shortTs = $ts -replace 'T', ' '

        $cpuPct = $snap.CPUPercent
        $cpuColor = if ($cpuPct -gt 80) { "#dc3545" } elseif ($cpuPct -gt 50) { "#ffc107" } else { "#28a745" }
        $cpuRows += "<tr><td style='width:160px;font-size:11px'>$shortTs</td><td><div style='background:$cpuColor;width:$($cpuPct)%;height:18px;border-radius:3px;min-width:2px'></div></td><td style='width:50px'>$cpuPct%</td></tr>`n"

        $memPct = $snap.MemoryUsedPercent
        $memColor = if ($memPct -gt 90) { "#dc3545" } elseif ($memPct -gt 75) { "#ffc107" } else { "#28a745" }
        $memRows += "<tr><td style='width:160px;font-size:11px'>$shortTs</td><td><div style='background:$memColor;width:$($memPct)%;height:18px;border-radius:3px;min-width:2px'></div></td><td style='width:50px'>$memPct%</td></tr>`n"
    }

    # Disk trend — estimate days until full
    $diskSection = ""
    $latestSnap = $snapshots[-1]
    if ($latestSnap.Disks) {
        $diskSection = "<h2>Disk Usage (Latest)</h2><table><tr><th>Drive</th><th>Total GB</th><th>Free GB</th><th>Used %</th><th>Projection</th></tr>"
        foreach ($disk in $latestSnap.Disks) {
            $daysUntilFull = ""
            if ($snapshots.Count -ge 2) {
                $firstSnap = $snapshots[0]
                $firstDisk = $firstSnap.Disks | Where-Object { $_.Drive -eq $disk.Drive }
                if ($firstDisk -and $firstDisk.FreeGB -gt $disk.FreeGB) {
                    $consumedGB = $firstDisk.FreeGB - $disk.FreeGB
                    try {
                        $firstDate = [datetime]::Parse($firstSnap.Timestamp)
                        $lastDate = [datetime]::Parse($latestSnap.Timestamp)
                        $daysBetween = ($lastDate - $firstDate).TotalDays
                        if ($daysBetween -gt 0 -and $consumedGB -gt 0) {
                            $ratePerDay = $consumedGB / $daysBetween
                            $daysLeft = [math]::Round($disk.FreeGB / $ratePerDay, 0)
                            $daysUntilFull = " (~$daysLeft days until full)"
                        }
                    } catch {
                        # Disk growth calculation is non-critical; skip silently
                    }
                }
            }
            $diskColor = if ($disk.UsedPercent -gt 90) { "status-bad" } elseif ($disk.UsedPercent -gt 75) { "status-warn" } else { "status-good" }
            $diskSection += "<tr><td>$(ConvertTo-HtmlSafe $disk.Drive)</td><td>$($disk.TotalGB) GB</td><td>$($disk.FreeGB) GB free</td><td class='$diskColor'>$($disk.UsedPercent)%$(ConvertTo-HtmlSafe $daysUntilFull)</td></tr>"
        }
        $diskSection += "</table>"
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Performance Trend Report - $(ConvertTo-HtmlSafe $latestSnap.Hostname)</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: 'Segoe UI', Tahoma, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #0078d4; margin-top: 30px; }
        .status-good { color: #28a745; font-weight: bold; }
        .status-warn { color: #ffc107; font-weight: bold; }
        .status-bad { color: #dc3545; font-weight: bold; }
        table { border-collapse: collapse; width: 100%; margin: 15px 0; }
        th, td { border: 1px solid #dee2e6; padding: 8px; text-align: left; }
        th { background: #343a40; color: white; }
        tr:nth-child(even) { background: #f8f9fa; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #dee2e6; color: #666; font-size: 12px; }
        .metric-info { color: #666; font-size: 13px; margin-bottom: 10px; }
        @media (prefers-color-scheme: dark) {
            body { background-color: #1a1a2e; color: #e0e0e0; }
            .container { background: #16213e; }
            h1 { color: #e0e0e0; }
            h2 { color: #5dade2; }
            table { border-color: #444; }
            th { background-color: #16213e; color: #e0e0e0; }
            td { border-color: #333; }
            tr:nth-child(even) { background: #1a2744; }
            .status-warn { color: #ffa726; }
            .status-bad { color: #ef5350; }
            .status-good { color: #66bb6a; }
            .metric-info { color: #aaa; }
            .footer { border-color: #444; color: #999; }
        }
        .dark-mode { background-color: #1a1a2e !important; color: #e0e0e0 !important; }
        .dark-mode .container { background: #16213e !important; }
        .dark-mode h1 { color: #e0e0e0 !important; }
        .dark-mode h2 { color: #5dade2 !important; }
        .dark-mode table { border-color: #444 !important; }
        .dark-mode th { background-color: #16213e !important; color: #e0e0e0 !important; }
        .dark-mode td { border-color: #333 !important; }
        .dark-mode tr:nth-child(even) { background: #1a2744 !important; }
        .dark-mode .status-warn { color: #ffa726 !important; }
        .dark-mode .status-bad { color: #ef5350 !important; }
        .dark-mode .status-good { color: #66bb6a !important; }
        .dark-mode .metric-info { color: #aaa !important; }
        .dark-mode .footer { border-color: #444 !important; color: #999 !important; }
    </style>
</head>
<body>
    <button onclick="document.body.classList.toggle('dark-mode')" style="position:fixed;top:10px;right:10px;padding:5px 10px;cursor:pointer;z-index:1000;border-radius:4px;border:1px solid #ccc;">Toggle Dark Mode</button>
    <div class="container">
        <h1>Performance Trend Report</h1>
        <p>Server: $(ConvertTo-HtmlSafe $latestSnap.Hostname) | Snapshots: $($snapshots.Count) | Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>

        <h2>CPU Usage Over Time</h2>
        <p class="metric-info">Bar width = CPU utilization percentage</p>
        <table>
            <tr><th>Timestamp</th><th>Usage</th><th>%</th></tr>
            $cpuRows
        </table>

        <h2>Memory Usage Over Time</h2>
        <p class="metric-info">Bar width = memory utilization percentage</p>
        <table>
            <tr><th>Timestamp</th><th>Usage</th><th>%</th></tr>
            $memRows
        </table>

        $diskSection

        <div class="footer">
            Report generated by $(ConvertTo-HtmlSafe $script:ToolFullName) v$(ConvertTo-HtmlSafe $script:ScriptVersion)
        </div>
    </div>
</body>
</html>
"@

    try {
        $html | Out-File -LiteralPath $OutputPath -Encoding UTF8 -Force
        Write-OutputColor "  Trend report saved to: $OutputPath" -color "Success"
        Add-SessionChange -Category "Report" -Description "Generated performance trend report ($($snapshots.Count) snapshots)"

        if (Confirm-UserAction -Message "Open report in browser?") {
            Start-Process $OutputPath
        }
    }
    catch {
        Write-OutputColor "  Error saving report: $_" -color "Error"
    }
}

# Interval-based metric collection
function Start-MetricCollection {
    param(
        [int]$IntervalMinutes = 5,
        [int]$DurationMinutes = 60
    )

    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     METRIC COLLECTION").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($IntervalMinutes -le 0) { $IntervalMinutes = 5 }
    $totalSnapshots = [math]::Ceiling($DurationMinutes / $IntervalMinutes)
    Write-OutputColor "  Collecting $totalSnapshots snapshots every $IntervalMinutes minute(s) for $DurationMinutes minutes." -color "Info"
    Write-OutputColor "  Press Ctrl+C to stop early." -color "Info"
    Write-OutputColor "" -color "Info"

    $collected = 0
    $endTime = (Get-Date).AddMinutes($DurationMinutes)

    while ((Get-Date) -lt $endTime) {
        if ($global:ReturnToMainMenu) { break }
        $collected++
        $path = Save-PerformanceSnapshot
        if ($path) {
            Write-OutputColor "  [$collected/$totalSnapshots] Snapshot saved ($(Get-Date -Format 'HH:mm:ss'))" -color "Success"
        }
        else {
            Write-OutputColor "  [$collected/$totalSnapshots] Snapshot failed" -color "Error"
        }

        if ((Get-Date).AddMinutes($IntervalMinutes) -lt $endTime) {
            Start-Sleep -Seconds ($IntervalMinutes * 60)
        }
        else {
            break
        }
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Collection complete: $collected snapshot(s) saved." -color "Success"
    Add-SessionChange -Category "Metrics" -Description "Collected $collected performance snapshots over $DurationMinutes minutes"
}

# Fleet Aggregate — reads JSON outputs from previous CLI actions and produces a summary report
function Invoke-FleetAggregate {
    param(
        [Parameter(Mandatory)]
        [string]$InputPath   # Directory of JSON files or single JSON array file
    )

    # Load JSON reports
    $reports = [System.Collections.Generic.List[object]]::new()

    if (Test-Path -LiteralPath $InputPath -PathType Container) {
        # Directory — read all .json files
        $jsonFiles = @(Get-ChildItem -LiteralPath $InputPath -Filter "*.json" -File)
        if ($jsonFiles.Count -eq 0) {
            Write-OutputColor "  No JSON files found in: $InputPath" -color "Error"
            return $null
        }
        foreach ($file in $jsonFiles) {
            try {
                $content = Get-Content -LiteralPath $file.FullName -Raw
                $parsed = $content | ConvertFrom-Json
                # Could be a single report or an array
                if ($parsed -is [System.Array]) {
                    foreach ($item in $parsed) { $reports.Add($item) }
                } else {
                    $reports.Add($parsed)
                }
            }
            catch {
                Write-OutputColor "  WARNING: Skipping invalid JSON: $($file.Name)" -color "Warning"
            }
        }
    }
    elseif (Test-Path -LiteralPath $InputPath -PathType Leaf) {
        # Single file — could be one report or an array
        try {
            $content = Get-Content -LiteralPath $InputPath -Raw
            $parsed = $content | ConvertFrom-Json
            if ($parsed -is [System.Array]) {
                foreach ($item in $parsed) { $reports.Add($item) }
            } else {
                $reports.Add($parsed)
            }
        }
        catch {
            Write-OutputColor "  ERROR: Failed to parse JSON: $InputPath" -color "Error"
            return $null
        }
    }
    else {
        Write-OutputColor "  ERROR: Path not found: $InputPath" -color "Error"
        return $null
    }

    if ($reports.Count -eq 0) {
        Write-OutputColor "  No valid reports found." -color "Error"
        return $null
    }

    # Group by action type
    $grouped = @{}
    foreach ($report in $reports) {
        $action = $null
        if ($null -ne $report.Action) { $action = [string]$report.Action }
        if (-not $action) { $action = 'Unknown' }
        if (-not $grouped.ContainsKey($action)) {
            $grouped[$action] = [System.Collections.Generic.List[object]]::new()
        }
        $grouped[$action].Add($report)
    }

    # Build aggregation result
    $result = @{
        TotalReports = $reports.Count
        ActionTypes  = @($grouped.Keys | Sort-Object)
        Hosts        = @($reports | ForEach-Object { $_.Hostname } | Where-Object { $_ } | Select-Object -Unique | Sort-Object)
        Aggregations = @{}
    }

    foreach ($action in @($grouped.Keys | Sort-Object)) {
        $items = $grouped[$action]
        $agg = @{ Count = $items.Count; Hosts = @($items | ForEach-Object { $_.Hostname } | Where-Object { $_ } | Select-Object -Unique | Sort-Object) }

        switch ($action) {
            'HealthCheck' {
                # Count health statuses from Report.OverallHealth or Report.Health
                $statuses = @{ OK = 0; Warning = 0; Critical = 0; Unknown = 0 }
                foreach ($r in $items) {
                    $health = $null
                    if ($null -ne $r.Report -and $null -ne $r.Report.OverallHealth) { $health = $r.Report.OverallHealth }
                    elseif ($null -ne $r.Report -and $null -ne $r.Report.Health) { $health = $r.Report.Health }
                    elseif ($null -ne $r.Health) { $health = $r.Health }
                    if ($null -ne $health -and $statuses.ContainsKey([string]$health)) {
                        $statuses[[string]$health]++
                    } else {
                        $statuses['Unknown']++
                    }
                }
                $agg.HealthStatuses = $statuses
            }
            'Harden' {
                # Aggregate scores
                $scores = @($items | ForEach-Object { $_.Score } | Where-Object { $null -ne $_ })
                if ($scores.Count -gt 0) {
                    $agg.ScoreMin = ($scores | Measure-Object -Minimum).Minimum
                    $agg.ScoreMax = ($scores | Measure-Object -Maximum).Maximum
                    $agg.ScoreAvg = [math]::Round(($scores | Measure-Object -Average).Average, 1)
                }
                # Common failures across hosts
                $failureCounts = @{}
                foreach ($r in $items) {
                    if ($null -ne $r.Checks) {
                        foreach ($chk in @($r.Checks)) {
                            if ($chk.Status -eq 'Fail') {
                                $key = "$($chk.Category): $($chk.Name)"
                                if (-not $failureCounts.ContainsKey($key)) { $failureCounts[$key] = 0 }
                                $failureCounts[$key]++
                            }
                        }
                    }
                }
                $agg.CommonFailures = @($failureCounts.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 10 | ForEach-Object {
                    @{ Check = $_.Key; FailCount = $_.Value }
                })
            }
            'Compliance' {
                # Aggregate readiness scores
                $scores = @($items | Where-Object { $null -ne $_.Readiness -and $null -ne $_.Readiness.Score } | ForEach-Object { $_.Readiness.Score })
                if ($scores.Count -gt 0) {
                    $agg.ReadinessMin = ($scores | Measure-Object -Minimum).Minimum
                    $agg.ReadinessMax = ($scores | Measure-Object -Maximum).Maximum
                    $agg.ReadinessAvg = [math]::Round(($scores | Measure-Object -Average).Average, 1)
                }
                $driftCounts = @($items | Where-Object { $null -ne $_.Drift } | ForEach-Object { $_.Drift.DriftCount } | Where-Object { $null -ne $_ })
                if ($driftCounts.Count -gt 0) {
                    $agg.TotalDriftItems = ($driftCounts | Measure-Object -Sum).Sum
                    $agg.HostsWithDrift = @($items | Where-Object { $null -ne $_.Drift -and $_.Drift.DriftCount -gt 0 }).Count
                }
            }
            'Inventory' {
                # OS and domain distribution
                $osCounts = @{}
                $domainCounts = @{}
                $roleCounts = @{}
                foreach ($r in $items) {
                    $inv = $r.Inventory
                    if ($null -eq $inv) { continue }
                    # OS
                    $os = if ($null -ne $inv.OS -and $null -ne $inv.OS.Caption) { $inv.OS.Caption } elseif ($null -ne $inv.OperatingSystem) { [string]$inv.OperatingSystem } else { 'Unknown' }
                    if (-not $osCounts.ContainsKey($os)) { $osCounts[$os] = 0 }
                    $osCounts[$os]++
                    # Domain
                    $dom = if ($null -ne $inv.Domain) { [string]$inv.Domain } else { 'Unknown' }
                    if (-not $domainCounts.ContainsKey($dom)) { $domainCounts[$dom] = 0 }
                    $domainCounts[$dom]++
                    # Roles
                    $roles = $null
                    if ($null -ne $inv.Roles) { $roles = @($inv.Roles) }
                    elseif ($null -ne $inv.InstalledRoles) { $roles = @($inv.InstalledRoles) }
                    if ($null -ne $roles) {
                        foreach ($role in $roles) {
                            $roleName = if ($role -is [string]) { $role } elseif ($null -ne $role.Name) { $role.Name } else { [string]$role }
                            if (-not $roleCounts.ContainsKey($roleName)) { $roleCounts[$roleName] = 0 }
                            $roleCounts[$roleName]++
                        }
                    }
                }
                $agg.OSDistribution = @($osCounts.GetEnumerator() | Sort-Object -Property Value -Descending | ForEach-Object { @{ OS = $_.Key; Count = $_.Value } })
                $agg.DomainDistribution = @($domainCounts.GetEnumerator() | Sort-Object -Property Value -Descending | ForEach-Object { @{ Domain = $_.Key; Count = $_.Value } })
                $agg.RoleDistribution = @($roleCounts.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 15 | ForEach-Object { @{ Role = $_.Key; Count = $_.Value } })
            }
            'Snapshot' {
                # Aggregate CPU, memory, disk averages
                $cpuValues = [System.Collections.Generic.List[double]]::new()
                $memValues = [System.Collections.Generic.List[double]]::new()
                $diskValues = [System.Collections.Generic.List[double]]::new()
                foreach ($r in $items) {
                    $snap = $r.Snapshot
                    if ($null -eq $snap) { $snap = $r }
                    if ($null -ne $snap.CPU -and $null -ne $snap.CPU.UsagePercent) { $cpuValues.Add([double]$snap.CPU.UsagePercent) }
                    elseif ($null -ne $snap.CPUPercent) { $cpuValues.Add([double]$snap.CPUPercent) }
                    if ($null -ne $snap.Memory -and $null -ne $snap.Memory.UsedPercent) { $memValues.Add([double]$snap.Memory.UsedPercent) }
                    elseif ($null -ne $snap.MemoryPercent) { $memValues.Add([double]$snap.MemoryPercent) }
                    if ($null -ne $snap.Disk) {
                        foreach ($d in @($snap.Disk)) {
                            if ($null -ne $d.UsedPercent) { $diskValues.Add([double]$d.UsedPercent) }
                        }
                    }
                }
                if ($cpuValues.Count -gt 0) {
                    $agg.CPU = @{
                        Avg = [math]::Round(($cpuValues | Measure-Object -Average).Average, 1)
                        Max = [math]::Round(($cpuValues | Measure-Object -Maximum).Maximum, 1)
                        Min = [math]::Round(($cpuValues | Measure-Object -Minimum).Minimum, 1)
                    }
                }
                if ($memValues.Count -gt 0) {
                    $agg.Memory = @{
                        Avg = [math]::Round(($memValues | Measure-Object -Average).Average, 1)
                        Max = [math]::Round(($memValues | Measure-Object -Maximum).Maximum, 1)
                        Min = [math]::Round(($memValues | Measure-Object -Minimum).Minimum, 1)
                    }
                }
                if ($diskValues.Count -gt 0) {
                    $agg.Disk = @{
                        Avg = [math]::Round(($diskValues | Measure-Object -Average).Average, 1)
                        Max = [math]::Round(($diskValues | Measure-Object -Maximum).Maximum, 1)
                    }
                }
            }
            'Remediate' {
                # Aggregate fix/skip/fail counts
                $totalFixed = 0; $totalSkipped = 0; $totalFailed = 0; $totalManual = 0; $rebootCount = 0
                foreach ($r in $items) {
                    $sum = $r.Summary
                    if ($null -eq $sum) { continue }
                    if ($null -ne $sum.Fixed)   { $totalFixed   += $sum.Fixed }
                    if ($null -ne $sum.Skipped) { $totalSkipped += $sum.Skipped }
                    if ($null -ne $sum.Failed)  { $totalFailed  += $sum.Failed }
                    if ($null -ne $sum.Manual)  { $totalManual  += $sum.Manual }
                    if ($r.RebootRequired -eq $true) { $rebootCount++ }
                }
                $agg.TotalFixed = $totalFixed
                $agg.TotalSkipped = $totalSkipped
                $agg.TotalFailed = $totalFailed
                $agg.TotalManual = $totalManual
                $agg.HostsNeedingReboot = $rebootCount
            }
        }

        $result.Aggregations[$action] = $agg
    }

    return $result
}

# Display fleet aggregate report to console
function Show-FleetAggregateReport {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Result
    )

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ── Fleet Aggregate Report ──" -color "Info"
    Write-OutputColor "  Total reports:  $($Result.TotalReports)" -color "Info"
    Write-OutputColor "  Unique hosts:   $($Result.Hosts.Count)" -color "Info"
    Write-OutputColor "  Action types:   $($Result.ActionTypes -join ', ')" -color "Info"
    Write-OutputColor "" -color "Info"

    foreach ($action in $Result.ActionTypes) {
        $agg = $Result.Aggregations[$action]
        Write-OutputColor "  ── $action ($($agg.Count) report(s), $($agg.Hosts.Count) host(s)) ──" -color "Info"

        switch ($action) {
            'HealthCheck' {
                $s = $agg.HealthStatuses
                Write-OutputColor "    OK: $($s.OK)  Warning: $($s.Warning)  Critical: $($s.Critical)  Unknown: $($s.Unknown)" -color $(if ($s.Critical -gt 0) { 'Error' } elseif ($s.Warning -gt 0) { 'Warning' } else { 'Success' })
            }
            'Harden' {
                if ($null -ne $agg.ScoreAvg) {
                    Write-OutputColor "    Score  — Avg: $($agg.ScoreAvg)%  Min: $($agg.ScoreMin)%  Max: $($agg.ScoreMax)%" -color $(if ($agg.ScoreAvg -ge 70) { 'Success' } elseif ($agg.ScoreAvg -ge 40) { 'Warning' } else { 'Error' })
                }
                if ($agg.CommonFailures.Count -gt 0) {
                    Write-OutputColor "    Top failures:" -color "Warning"
                    foreach ($f in $agg.CommonFailures) {
                        Write-OutputColor "      $($f.FailCount)x  $($f.Check)" -color "Warning"
                    }
                }
            }
            'Compliance' {
                if ($null -ne $agg.ReadinessAvg) {
                    Write-OutputColor "    Readiness — Avg: $($agg.ReadinessAvg)%  Min: $($agg.ReadinessMin)%  Max: $($agg.ReadinessMax)%" -color $(if ($agg.ReadinessAvg -ge 80) { 'Success' } elseif ($agg.ReadinessAvg -ge 50) { 'Warning' } else { 'Error' })
                }
                if ($null -ne $agg.TotalDriftItems) {
                    Write-OutputColor "    Drift — $($agg.TotalDriftItems) total item(s) across $($agg.HostsWithDrift) host(s)" -color $(if ($agg.TotalDriftItems -eq 0) { 'Success' } else { 'Warning' })
                }
            }
            'Inventory' {
                if ($agg.OSDistribution.Count -gt 0) {
                    Write-OutputColor "    OS distribution:" -color "Info"
                    foreach ($os in $agg.OSDistribution) { Write-OutputColor "      $($os.Count)x  $($os.OS)" -color "Info" }
                }
                if ($agg.DomainDistribution.Count -gt 0) {
                    Write-OutputColor "    Domains:" -color "Info"
                    foreach ($dom in $agg.DomainDistribution) { Write-OutputColor "      $($dom.Count)x  $($dom.Domain)" -color "Info" }
                }
                if ($agg.RoleDistribution.Count -gt 0) {
                    Write-OutputColor "    Top roles:" -color "Info"
                    foreach ($role in $agg.RoleDistribution) { Write-OutputColor "      $($role.Count)x  $($role.Role)" -color "Info" }
                }
            }
            'Snapshot' {
                if ($null -ne $agg.CPU) {
                    Write-OutputColor "    CPU    — Avg: $($agg.CPU.Avg)%  Min: $($agg.CPU.Min)%  Max: $($agg.CPU.Max)%" -color $(if ($agg.CPU.Avg -ge 80) { 'Warning' } else { 'Success' })
                }
                if ($null -ne $agg.Memory) {
                    Write-OutputColor "    Memory — Avg: $($agg.Memory.Avg)%  Min: $($agg.Memory.Min)%  Max: $($agg.Memory.Max)%" -color $(if ($agg.Memory.Avg -ge 85) { 'Warning' } else { 'Success' })
                }
                if ($null -ne $agg.Disk) {
                    Write-OutputColor "    Disk   — Avg: $($agg.Disk.Avg)%  Max: $($agg.Disk.Max)%" -color $(if ($agg.Disk.Max -ge 90) { 'Warning' } else { 'Success' })
                }
            }
            'Remediate' {
                Write-OutputColor "    Fixed: $($agg.TotalFixed)  Skipped: $($agg.TotalSkipped)  Failed: $($agg.TotalFailed)  Manual: $($agg.TotalManual)" -color $(if ($agg.TotalFailed -gt 0) { 'Warning' } else { 'Success' })
                if ($agg.HostsNeedingReboot -gt 0) {
                    Write-OutputColor "    $($agg.HostsNeedingReboot) host(s) need reboot" -color "Warning"
                }
            }
            default {
                Write-OutputColor "    $($agg.Count) report(s) — no specific aggregation for this action type" -color "Info"
            }
        }
        Write-OutputColor "" -color "Info"
    }
}

# Fleet Compare — side-by-side comparison of two JSON outputs from previous CLI actions
function Invoke-FleetCompare {
    param(
        [Parameter(Mandatory)]
        [string]$FilePathA,

        [Parameter(Mandatory)]
        [string]$FilePathB
    )

    # Load both JSON files
    $reportA = $null
    $reportB = $null
    try {
        $reportA = Get-Content -LiteralPath $FilePathA -Raw | ConvertFrom-Json
    }
    catch {
        Write-OutputColor "  ERROR: Failed to parse: $(Split-Path $FilePathA -Leaf)" -color "Error"
        return $null
    }
    try {
        $reportB = Get-Content -LiteralPath $FilePathB -Raw | ConvertFrom-Json
    }
    catch {
        Write-OutputColor "  ERROR: Failed to parse: $(Split-Path $FilePathB -Leaf)" -color "Error"
        return $null
    }

    $hostA = if ($null -ne $reportA.Hostname) { [string]$reportA.Hostname } else { Split-Path $FilePathA -Leaf }
    $hostB = if ($null -ne $reportB.Hostname) { [string]$reportB.Hostname } else { Split-Path $FilePathB -Leaf }
    $actionA = if ($null -ne $reportA.Action) { [string]$reportA.Action } else { 'Unknown' }
    $actionB = if ($null -ne $reportB.Action) { [string]$reportB.Action } else { 'Unknown' }

    if ($actionA -ne $actionB) {
        Write-OutputColor "  WARNING: Action mismatch ($actionA vs $actionB) — using generic comparison" -color "Warning"
    }

    $diffs = [System.Collections.Generic.List[object]]::new()

    # Helper to add a comparison item
    $addItem = {
        param([string]$Property, $ValueA, $ValueB)
        $strA = if ($null -ne $ValueA) { "$ValueA" } else { "(none)" }
        $strB = if ($null -ne $ValueB) { "$ValueB" } else { "(none)" }
        $diffs.Add(@{
            Property = $Property
            HostA    = $strA
            HostB    = $strB
            Match    = ($strA -eq $strB)
        })
    }

    $action = if ($actionA -eq $actionB) { $actionA } else { 'Mixed' }

    switch ($action) {
        'Inventory' {
            $invA = $reportA.Inventory
            $invB = $reportB.Inventory
            # OS
            $osA = if ($null -ne $invA -and $null -ne $invA.OS) { $invA.OS.Caption } else { $null }
            $osB = if ($null -ne $invB -and $null -ne $invB.OS) { $invB.OS.Caption } else { $null }
            & $addItem 'OS' $osA $osB
            $osVerA = if ($null -ne $invA -and $null -ne $invA.OS) { $invA.OS.Version } else { $null }
            $osVerB = if ($null -ne $invB -and $null -ne $invB.OS) { $invB.OS.Version } else { $null }
            & $addItem 'OS Version' $osVerA $osVerB
            # Domain
            $domA = if ($null -ne $invA -and $null -ne $invA.System) { $invA.System.Domain } elseif ($null -ne $invA) { $invA.Domain } else { $null }
            $domB = if ($null -ne $invB -and $null -ne $invB.System) { $invB.System.Domain } elseif ($null -ne $invB) { $invB.Domain } else { $null }
            & $addItem 'Domain' $domA $domB
            # Manufacturer/Model
            $mfgA = if ($null -ne $invA -and $null -ne $invA.System) { $invA.System.Manufacturer } else { $null }
            $mfgB = if ($null -ne $invB -and $null -ne $invB.System) { $invB.System.Manufacturer } else { $null }
            & $addItem 'Manufacturer' $mfgA $mfgB
            $mdlA = if ($null -ne $invA -and $null -ne $invA.System) { $invA.System.Model } else { $null }
            $mdlB = if ($null -ne $invB -and $null -ne $invB.System) { $invB.System.Model } else { $null }
            & $addItem 'Model' $mdlA $mdlB
            # CPU
            $cpuA = if ($null -ne $invA -and $null -ne $invA.CPU) { $invA.CPU.Name } else { $null }
            $cpuB = if ($null -ne $invB -and $null -ne $invB.CPU) { $invB.CPU.Name } else { $null }
            & $addItem 'CPU' $cpuA $cpuB
            $coresA = if ($null -ne $invA -and $null -ne $invA.CPU) { $invA.CPU.Cores } else { $null }
            $coresB = if ($null -ne $invB -and $null -ne $invB.CPU) { $invB.CPU.Cores } else { $null }
            & $addItem 'CPU Cores' $coresA $coresB
            # Memory
            $memA = if ($null -ne $invA) { $invA.MemoryGB } else { $null }
            $memB = if ($null -ne $invB) { $invB.MemoryGB } else { $null }
            & $addItem 'Memory (GB)' $memA $memB
            # Roles
            if ($null -ne $invA -and $null -ne $invA.Roles) {
                $roleProps = @('HyperV', 'FailoverClustering', 'MPIO')
                foreach ($rp in $roleProps) {
                    $rvA = if ($null -ne $invA.Roles.PSObject.Properties[$rp]) { $invA.Roles.$rp } else { $null }
                    $rvB = if ($null -ne $invB -and $null -ne $invB.Roles -and $null -ne $invB.Roles.PSObject.Properties[$rp]) { $invB.Roles.$rp } else { $null }
                    & $addItem "Role: $rp" $rvA $rvB
                }
            }
            # Volume count
            $volsA = if ($null -ne $invA -and $null -ne $invA.Volumes) { @($invA.Volumes).Count } else { 0 }
            $volsB = if ($null -ne $invB -and $null -ne $invB.Volumes) { @($invB.Volumes).Count } else { 0 }
            & $addItem 'Volume Count' $volsA $volsB
        }
        'Snapshot' {
            # CPU
            $cpuA = if ($null -ne $reportA.Snapshot -and $null -ne $reportA.Snapshot.CPU) { $reportA.Snapshot.CPU.UsagePercent } elseif ($null -ne $reportA.CPUPercent) { $reportA.CPUPercent } else { $null }
            $cpuB = if ($null -ne $reportB.Snapshot -and $null -ne $reportB.Snapshot.CPU) { $reportB.Snapshot.CPU.UsagePercent } elseif ($null -ne $reportB.CPUPercent) { $reportB.CPUPercent } else { $null }
            $cpuItem = @{ Property = 'CPU%'; HostA = "$(if ($null -ne $cpuA) { $cpuA } else { '(none)' })"; HostB = "$(if ($null -ne $cpuB) { $cpuB } else { '(none)' })"; Match = ("$cpuA" -eq "$cpuB") }
            if ($null -ne $cpuA -and $null -ne $cpuB) { $cpuItem.Delta = [math]::Round([double]$cpuB - [double]$cpuA, 1) }
            $diffs.Add($cpuItem)
            # Memory
            $memA = if ($null -ne $reportA.Snapshot -and $null -ne $reportA.Snapshot.Memory) { $reportA.Snapshot.Memory.UsedPercent } elseif ($null -ne $reportA.MemoryPercent) { $reportA.MemoryPercent } else { $null }
            $memB = if ($null -ne $reportB.Snapshot -and $null -ne $reportB.Snapshot.Memory) { $reportB.Snapshot.Memory.UsedPercent } elseif ($null -ne $reportB.MemoryPercent) { $reportB.MemoryPercent } else { $null }
            $memItem = @{ Property = 'Memory%'; HostA = "$(if ($null -ne $memA) { $memA } else { '(none)' })"; HostB = "$(if ($null -ne $memB) { $memB } else { '(none)' })"; Match = ("$memA" -eq "$memB") }
            if ($null -ne $memA -and $null -ne $memB) { $memItem.Delta = [math]::Round([double]$memB - [double]$memA, 1) }
            $diffs.Add($memItem)
            # Disks
            $disksA = @()
            $disksB = @()
            if ($null -ne $reportA.Snapshot -and $null -ne $reportA.Snapshot.Disk) { $disksA = @($reportA.Snapshot.Disk) }
            if ($null -ne $reportB.Snapshot -and $null -ne $reportB.Snapshot.Disk) { $disksB = @($reportB.Snapshot.Disk) }
            $allDrives = @($disksA | ForEach-Object { $_.Drive }) + @($disksB | ForEach-Object { $_.Drive }) | Where-Object { $_ } | Select-Object -Unique | Sort-Object
            foreach ($drv in $allDrives) {
                $dA = $disksA | Where-Object { $_.Drive -eq $drv } | Select-Object -First 1
                $dB = $disksB | Where-Object { $_.Drive -eq $drv } | Select-Object -First 1
                $pctA = if ($null -ne $dA) { $dA.UsedPercent } else { $null }
                $pctB = if ($null -ne $dB) { $dB.UsedPercent } else { $null }
                $diskItem = @{ Property = "Disk $drv Used%"; HostA = "$(if ($null -ne $pctA) { $pctA } else { '(none)' })"; HostB = "$(if ($null -ne $pctB) { $pctB } else { '(none)' })"; Match = ("$pctA" -eq "$pctB") }
                if ($null -ne $pctA -and $null -ne $pctB) { $diskItem.Delta = [math]::Round([double]$pctB - [double]$pctA, 1) }
                $diffs.Add($diskItem)
            }
        }
        'Harden' {
            # Scores
            & $addItem 'Score' $reportA.Score $reportB.Score
            $passA = if ($null -ne $reportA.Summary) { $reportA.Summary.Passed } else { $null }
            $passB = if ($null -ne $reportB.Summary) { $reportB.Summary.Passed } else { $null }
            & $addItem 'Passed' $passA $passB
            $failA = if ($null -ne $reportA.Summary) { $reportA.Summary.Failed } else { $null }
            $failB = if ($null -ne $reportB.Summary) { $reportB.Summary.Failed } else { $null }
            & $addItem 'Failed' $failA $failB
            # Per-check comparison
            $checksA = @{}
            $checksB = @{}
            if ($null -ne $reportA.Checks) {
                foreach ($chk in @($reportA.Checks)) {
                    $key = "$($chk.Category): $($chk.Name)"
                    $checksA[$key] = $chk.Status
                }
            }
            if ($null -ne $reportB.Checks) {
                foreach ($chk in @($reportB.Checks)) {
                    $key = "$($chk.Category): $($chk.Name)"
                    $checksB[$key] = $chk.Status
                }
            }
            $allKeys = @($checksA.Keys) + @($checksB.Keys) | Select-Object -Unique | Sort-Object
            foreach ($key in $allKeys) {
                $sA = if ($checksA.ContainsKey($key)) { $checksA[$key] } else { '(absent)' }
                $sB = if ($checksB.ContainsKey($key)) { $checksB[$key] } else { '(absent)' }
                $diffs.Add(@{
                    Property = $key
                    HostA    = $sA
                    HostB    = $sB
                    Match    = ($sA -eq $sB)
                })
            }
        }
        'Compliance' {
            $scoreA = if ($null -ne $reportA.Readiness) { $reportA.Readiness.Score } else { $null }
            $scoreB = if ($null -ne $reportB.Readiness) { $reportB.Readiness.Score } else { $null }
            & $addItem 'Readiness Score' $scoreA $scoreB
            $passA = if ($null -ne $reportA.Readiness) { $reportA.Readiness.Passed } else { $null }
            $passB = if ($null -ne $reportB.Readiness) { $reportB.Readiness.Passed } else { $null }
            & $addItem 'Readiness Passed' $passA $passB
            $driftA = if ($null -ne $reportA.Drift) { $reportA.Drift.DriftCount } else { 0 }
            $driftB = if ($null -ne $reportB.Drift) { $reportB.Drift.DriftCount } else { 0 }
            & $addItem 'Drift Count' $driftA $driftB
        }
        'HealthCheck' {
            $healthA = if ($null -ne $reportA.Report) { $reportA.Report.OverallHealth } else { $null }
            $healthB = if ($null -ne $reportB.Report) { $reportB.Report.OverallHealth } else { $null }
            & $addItem 'Health Status' $healthA $healthB
            $issA = if ($null -ne $reportA.Report) { $reportA.Report.IssueCount } else { $null }
            $issB = if ($null -ne $reportB.Report) { $reportB.Report.IssueCount } else { $null }
            & $addItem 'Issue Count' $issA $issB
        }
        default {
            # Generic: compare top-level properties (excluding metadata)
            $skipKeys = @('Tool', 'Version', 'Action', 'Timestamp', 'Hostname')
            $propsA = @()
            $propsB = @()
            if ($null -ne $reportA.PSObject) { $propsA = @($reportA.PSObject.Properties | Where-Object { $_.Name -notin $skipKeys } | ForEach-Object { $_.Name }) }
            if ($null -ne $reportB.PSObject) { $propsB = @($reportB.PSObject.Properties | Where-Object { $_.Name -notin $skipKeys } | ForEach-Object { $_.Name }) }
            $allProps = @($propsA) + @($propsB) | Select-Object -Unique | Sort-Object
            foreach ($prop in $allProps) {
                $vA = if ($null -ne $reportA.PSObject.Properties[$prop]) { ($reportA.$prop | ConvertTo-Json -Compress -Depth 5) } else { $null }
                $vB = if ($null -ne $reportB.PSObject.Properties[$prop]) { ($reportB.$prop | ConvertTo-Json -Compress -Depth 5) } else { $null }
                $strA = if ($null -ne $vA) { if ($vA.Length -gt 60) { $vA.Substring(0, 57) + '...' } else { $vA } } else { '(none)' }
                $strB = if ($null -ne $vB) { if ($vB.Length -gt 60) { $vB.Substring(0, 57) + '...' } else { $vB } } else { '(none)' }
                $diffs.Add(@{
                    Property = $prop
                    HostA    = $strA
                    HostB    = $strB
                    Match    = ($vA -eq $vB)
                })
            }
        }
    }

    $matched = @($diffs | Where-Object { $_.Match }).Count
    $different = @($diffs | Where-Object { -not $_.Match }).Count

    return @{
        HostA      = $hostA
        HostB      = $hostB
        Action     = $action
        TimestampA = $reportA.Timestamp
        TimestampB = $reportB.Timestamp
        Differences = @($diffs)
        Summary    = @{
            Total     = $diffs.Count
            Matched   = $matched
            Different = $different
        }
    }
}

# Display fleet compare report to console
function Show-FleetCompareReport {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Result
    )

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ── Fleet Compare Report ──" -color "Info"
    Write-OutputColor "  Host A: $($Result.HostA)$(if ($Result.TimestampA) { " ($($Result.TimestampA))" })" -color "Info"
    Write-OutputColor "  Host B: $($Result.HostB)$(if ($Result.TimestampB) { " ($($Result.TimestampB))" })" -color "Info"
    Write-OutputColor "  Action: $($Result.Action)" -color "Info"
    Write-OutputColor "" -color "Info"

    # Table header
    $propW = 26; $valW = 22; $statW = 6
    $headerLine = "  $('Property'.PadRight($propW))  $('Host A'.PadRight($valW))  $('Host B'.PadRight($valW))  Status"
    $divider = "  $('-' * $propW)  $('-' * $valW)  $('-' * $valW)  $('-' * $statW)"
    Write-OutputColor $headerLine -color "Info"
    Write-OutputColor $divider -color "Info"

    foreach ($item in $Result.Differences) {
        $prop = if ($item.Property.Length -gt $propW) { $item.Property.Substring(0, $propW - 2) + '..' } else { $item.Property.PadRight($propW) }
        $vA = if ($item.HostA.Length -gt $valW) { $item.HostA.Substring(0, $valW - 2) + '..' } else { $item.HostA.PadRight($valW) }
        $vB = if ($item.HostB.Length -gt $valW) { $item.HostB.Substring(0, $valW - 2) + '..' } else { $item.HostB.PadRight($valW) }
        $status = if ($item.Match) { '  OK  ' } else { ' DIFF ' }
        $color = if ($item.Match) { 'Success' } else { 'Error' }
        $deltaStr = ''
        if ($null -ne $item.Delta) { $deltaStr = "  ($($item.Delta))" }
        Write-OutputColor "  $prop  $vA  $vB  $status$deltaStr" -color $color
    }

    Write-OutputColor "" -color "Info"
    $s = $Result.Summary
    $sumColor = if ($s.Different -eq 0) { 'Success' } elseif ($s.Different -le 3) { 'Warning' } else { 'Error' }
    Write-OutputColor "  Summary: $($s.Total) compared, $($s.Matched) match, $($s.Different) different" -color $sumColor
    Write-OutputColor "" -color "Info"
}

# Fleet Trend — analyze performance snapshots from a single host over time
function Invoke-FleetTrend {
    param(
        [Parameter(Mandatory)]
        [string]$InputPath
    )

    if (-not (Test-Path -LiteralPath $InputPath -PathType Container)) {
        Write-OutputColor "  ERROR: Directory not found: $InputPath" -color "Error"
        return $null
    }

    $jsonFiles = @(Get-ChildItem -LiteralPath $InputPath -Filter "*.json" -File)
    if ($jsonFiles.Count -eq 0) {
        Write-OutputColor "  No JSON files found in: $InputPath" -color "Error"
        return $null
    }

    $snapshots = [System.Collections.Generic.List[object]]::new()
    $failedFiles = 0
    foreach ($file in $jsonFiles) {
        try {
            $data = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            if ($null -ne $data.Timestamp) {
                $snapshots.Add($data)
            } else {
                $failedFiles++
            }
        } catch {
            $failedFiles++
        }
    }

    if ($failedFiles -gt 0) {
        Write-OutputColor "  Warning: $failedFiles file(s) skipped (invalid JSON or missing Timestamp)." -color "Warning"
    }

    if ($snapshots.Count -lt 2) {
        Write-OutputColor "  ERROR: At least 2 valid snapshots required for trend analysis (found $($snapshots.Count))." -color "Error"
        return $null
    }

    $sorted = @($snapshots | Sort-Object { [datetime]::Parse($_.Timestamp) })
    $first = $sorted[0]
    $last = $sorted[$sorted.Count - 1]
    $hostname = if ($null -ne $last.Hostname) { $last.Hostname } else { 'Unknown' }

    $getDirection = {
        param([double]$FirstVal, [double]$LastVal)
        $delta = $LastVal - $FirstVal
        if ($delta -gt 5) { return 'Rising' }
        elseif ($delta -lt -5) { return 'Falling' }
        else { return 'Stable' }
    }

    # CPU trend
    $cpuValues = [System.Collections.Generic.List[double]]::new()
    foreach ($snap in $sorted) {
        if ($null -ne $snap.CPUPercent) { $cpuValues.Add([double]$snap.CPUPercent) }
    }
    $cpuTrend = $null
    if ($cpuValues.Count -ge 2) {
        $cpuTrend = @{
            Avg       = [math]::Round(($cpuValues | Measure-Object -Average).Average, 1)
            Min       = [math]::Round(($cpuValues | Measure-Object -Minimum).Minimum, 1)
            Max       = [math]::Round(($cpuValues | Measure-Object -Maximum).Maximum, 1)
            First     = [math]::Round($cpuValues[0], 1)
            Last      = [math]::Round($cpuValues[$cpuValues.Count - 1], 1)
            Direction = & $getDirection $cpuValues[0] $cpuValues[$cpuValues.Count - 1]
        }
    }

    # Memory trend
    $memValues = [System.Collections.Generic.List[double]]::new()
    foreach ($snap in $sorted) {
        if ($null -ne $snap.MemoryUsedPercent) { $memValues.Add([double]$snap.MemoryUsedPercent) }
    }
    $memTrend = $null
    if ($memValues.Count -ge 2) {
        $memTrend = @{
            Avg       = [math]::Round(($memValues | Measure-Object -Average).Average, 1)
            Min       = [math]::Round(($memValues | Measure-Object -Minimum).Minimum, 1)
            Max       = [math]::Round(($memValues | Measure-Object -Maximum).Maximum, 1)
            First     = [math]::Round($memValues[0], 1)
            Last      = [math]::Round($memValues[$memValues.Count - 1], 1)
            Direction = & $getDirection $memValues[0] $memValues[$memValues.Count - 1]
        }
    }

    # Disk trends per drive
    $diskTrends = [System.Collections.Generic.List[object]]::new()
    $allDrives = [System.Collections.Generic.List[string]]::new()
    foreach ($snap in $sorted) {
        if ($null -ne $snap.Disks) {
            foreach ($d in @($snap.Disks)) {
                if ($null -ne $d.Drive -and -not $allDrives.Contains($d.Drive)) {
                    $allDrives.Add($d.Drive)
                }
            }
        }
    }

    foreach ($drive in @($allDrives | Sort-Object)) {
        $diskValues = [System.Collections.Generic.List[double]]::new()
        foreach ($snap in $sorted) {
            if ($null -ne $snap.Disks) {
                $diskEntry = $snap.Disks | Where-Object { $_.Drive -eq $drive } | Select-Object -First 1
                if ($null -ne $diskEntry -and $null -ne $diskEntry.UsedPercent) {
                    $diskValues.Add([double]$diskEntry.UsedPercent)
                }
            }
        }
        if ($diskValues.Count -ge 2) {
            $diskTrends.Add(@{
                Drive     = $drive
                Avg       = [math]::Round(($diskValues | Measure-Object -Average).Average, 1)
                Min       = [math]::Round(($diskValues | Measure-Object -Minimum).Minimum, 1)
                Max       = [math]::Round(($diskValues | Measure-Object -Maximum).Maximum, 1)
                First     = [math]::Round($diskValues[0], 1)
                Last      = [math]::Round($diskValues[$diskValues.Count - 1], 1)
                Direction = & $getDirection $diskValues[0] $diskValues[$diskValues.Count - 1]
            })
        }
    }

    return @{
        Hostname  = $hostname
        TimeRange = @{
            Start     = $first.Timestamp
            End       = $last.Timestamp
            Snapshots = $sorted.Count
        }
        CPU       = $cpuTrend
        Memory    = $memTrend
        Disks     = @($diskTrends)
    }
}

# Display fleet trend report to console
function Show-FleetTrendReport {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Result
    )

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ── Performance Trend Report ──" -color "Info"
    Write-OutputColor "  Host:       $($Result.Hostname)" -color "Info"
    Write-OutputColor "  Time range: $($Result.TimeRange.Start) -> $($Result.TimeRange.End)" -color "Info"
    Write-OutputColor "  Snapshots:  $($Result.TimeRange.Snapshots)" -color "Info"
    Write-OutputColor "" -color "Info"

    $metricW = 16; $avgW = 8; $minW = 8; $maxW = 8; $firstW = 8; $lastW = 8; $dirW = 9
    $headerLine = "  $('Metric'.PadRight($metricW))  $('Avg'.PadRight($avgW))  $('Min'.PadRight($minW))  $('Max'.PadRight($maxW))  $('First'.PadRight($firstW))  $('Last'.PadRight($lastW))  Direction"
    $divider = "  $('-' * $metricW)  $('-' * $avgW)  $('-' * $minW)  $('-' * $maxW)  $('-' * $firstW)  $('-' * $lastW)  $('-' * $dirW)"
    Write-OutputColor $headerLine -color "Info"
    Write-OutputColor $divider -color "Info"

    $dirColor = {
        param([string]$Direction)
        if ($Direction -eq 'Rising') { return 'Warning' }
        else { return 'Success' }
    }

    if ($null -ne $Result.CPU) {
        $c = $Result.CPU
        $color = & $dirColor $c.Direction
        $line = "  $('CPU %'.PadRight($metricW))  $("$($c.Avg)".PadRight($avgW))  $("$($c.Min)".PadRight($minW))  $("$($c.Max)".PadRight($maxW))  $("$($c.First)".PadRight($firstW))  $("$($c.Last)".PadRight($lastW))  $($c.Direction)"
        Write-OutputColor $line -color $color
    }

    if ($null -ne $Result.Memory) {
        $m = $Result.Memory
        $color = & $dirColor $m.Direction
        $line = "  $('Memory %'.PadRight($metricW))  $("$($m.Avg)".PadRight($avgW))  $("$($m.Min)".PadRight($minW))  $("$($m.Max)".PadRight($maxW))  $("$($m.First)".PadRight($firstW))  $("$($m.Last)".PadRight($lastW))  $($m.Direction)"
        Write-OutputColor $line -color $color
    }

    foreach ($disk in $Result.Disks) {
        $color = & $dirColor $disk.Direction
        $label = "Disk $($disk.Drive) %"
        $line = "  $($label.PadRight($metricW))  $("$($disk.Avg)".PadRight($avgW))  $("$($disk.Min)".PadRight($minW))  $("$($disk.Max)".PadRight($maxW))  $("$($disk.First)".PadRight($firstW))  $("$($disk.Last)".PadRight($lastW))  $($disk.Direction)"
        Write-OutputColor $line -color $color
    }

    Write-OutputColor "" -color "Info"

    $warnings = 0
    if ($null -ne $Result.CPU -and $Result.CPU.Direction -eq 'Rising') {
        Write-OutputColor "  [!] CPU usage is trending upward" -color "Warning"
        $warnings++
    }
    if ($null -ne $Result.Memory -and $Result.Memory.Direction -eq 'Rising') {
        Write-OutputColor "  [!] Memory usage is trending upward" -color "Warning"
        $warnings++
    }
    foreach ($disk in $Result.Disks) {
        if ($disk.Direction -eq 'Rising') {
            Write-OutputColor "  [!] Disk $($disk.Drive) usage is trending upward" -color "Warning"
            $warnings++
        }
    }
    if ($warnings -eq 0) {
        Write-OutputColor "  All metrics stable or declining." -color "Success"
    }
    Write-OutputColor "" -color "Info"
}

# Query a directory of Export/Inventory JSON files with a search expression
# Query format: "section.field=value", "section.field~contains", "section.field<num", "section.field>num"
function Invoke-FleetQuery {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ReportDir,
        [Parameter(Mandatory=$true)]
        [string]$QueryExpr
    )

    if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
        Write-OutputColor "  ERROR: Directory not found: $ReportDir" -color "Error"
        return $null
    }

    # Parse query expression: section.field<operator>value
    $queryMatch = $null
    if ($QueryExpr -match '^([^.]+)\.([^=~<>]+)(=|~|<|>)(.+)$') {
        $regexMatches = $matches
        $queryMatch = @{
            Section  = $regexMatches[1]
            Field    = $regexMatches[2]
            Operator = $regexMatches[3]
            Value    = $regexMatches[4]
        }
    }
    if ($null -eq $queryMatch) {
        Write-OutputColor "  ERROR: Invalid query syntax. Use: section.field=value, section.field~contains, section.field<num, section.field>num" -color "Error"
        return $null
    }

    $jsonFiles = @(Get-ChildItem -Path $ReportDir -Filter "*.json" -File -ErrorAction SilentlyContinue)
    if ($jsonFiles.Count -eq 0) {
        Write-OutputColor "  No JSON reports found in $ReportDir" -color "Warning"
        return @{ Query = $QueryExpr; MatchCount = 0; TotalReports = 0; Matches = @() }
    }

    $matches2 = [System.Collections.Generic.List[object]]::new()
    $totalReports = 0

    foreach ($file in $jsonFiles) {
        try {
            $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
            $report = $content | ConvertFrom-Json -ErrorAction Stop
        } catch { continue }

        # Must have a Hostname to be a valid report
        if (-not $report.Hostname) { continue }
        $totalReports++

        # Navigate to the section
        $section = $null
        $sectionName = $queryMatch.Section

        # Map common query section names to JSON structure
        $sectionData = $null
        if ($report.PSObject.Properties.Name -contains $sectionName) {
            $sectionData = $report.$sectionName
        } elseif ($sectionName -eq 'health' -and $report.Health) {
            $sectionData = $report.Health
        } elseif ($sectionName -eq 'hardening' -and $report.Hardening) {
            $sectionData = $report.Hardening
        }

        if ($null -eq $sectionData) { continue }

        $fieldName = $queryMatch.Field
        $op = $queryMatch.Operator
        $queryVal = $queryMatch.Value

        # Handle array sections (ListeningPorts, Software, Services, Events, Certificates, Network/Adapters)
        $dataArray = $null
        if ($sectionData -is [array]) {
            $dataArray = $sectionData
        } elseif ($sectionData.PSObject.Properties.Name -contains 'Items') {
            $dataArray = $sectionData.Items
        }

        if ($null -ne $dataArray) {
            # Search within array items
            $matched = $false
            $matchedVal = $null
            foreach ($item in $dataArray) {
                if (-not ($item.PSObject.Properties.Name -contains $fieldName)) { continue }
                $itemVal = $item.$fieldName
                $itemValStr = "$itemVal"

                $hit = switch ($op) {
                    '=' { $itemValStr -eq $queryVal }
                    '~' { $itemValStr -like "*$queryVal*" }
                    '>' { ($itemVal -as [double]) -gt ($queryVal -as [double]) }
                    '<' { ($itemVal -as [double]) -lt ($queryVal -as [double]) }
                }
                if ($hit) {
                    $matched = $true
                    $matchedVal = $itemValStr
                    break
                }
            }
            if ($matched) {
                $matches2.Add(@{
                    Hostname     = $report.Hostname
                    Timestamp    = if ($report.Timestamp) { $report.Timestamp } else { $null }
                    MatchedValue = $matchedVal
                })
            }
        } else {
            # Scalar or object section — check the field directly
            $fieldVal = $null
            if ($sectionData.PSObject.Properties.Name -contains $fieldName) {
                $fieldVal = $sectionData.$fieldName
            } elseif ($sectionData -is [hashtable] -and $sectionData.ContainsKey($fieldName)) {
                $fieldVal = $sectionData[$fieldName]
            }

            if ($null -ne $fieldVal) {
                $fieldValStr = "$fieldVal"
                $hit = switch ($op) {
                    '=' { $fieldValStr -eq $queryVal }
                    '~' { $fieldValStr -like "*$queryVal*" }
                    '>' { ($fieldVal -as [double]) -gt ($queryVal -as [double]) }
                    '<' { ($fieldVal -as [double]) -lt ($queryVal -as [double]) }
                }
                if ($hit) {
                    $matches2.Add(@{
                        Hostname     = $report.Hostname
                        Timestamp    = if ($report.Timestamp) { $report.Timestamp } else { $null }
                        MatchedValue = $fieldValStr
                    })
                }
            }
        }
    }

    return @{
        Query        = $QueryExpr
        MatchCount   = $matches2.Count
        TotalReports = $totalReports
        Matches      = @($matches2)
    }
}

# Deep-diff two Export JSONs from the same host at different times
function Invoke-ExportDiff {
    param(
        [Parameter(Mandatory=$true)]
        [string]$OldPath,
        [Parameter(Mandatory=$true)]
        [string]$NewPath
    )

    try { $oldReport = Get-Content -LiteralPath $OldPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch {
        Write-OutputColor "  ERROR: Failed to parse old report: $($_.Exception.Message)" -color "Error"
        return $null
    }
    try { $newReport = Get-Content -LiteralPath $NewPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch {
        Write-OutputColor "  ERROR: Failed to parse new report: $($_.Exception.Message)" -color "Error"
        return $null
    }

    $changes = @{}
    $totalChanges = 0
    $changedSections = [System.Collections.Generic.List[string]]::new()

    # Helper: diff two arrays by a key field, return Added/Removed/Changed
    $diffArrays = {
        param($oldArr, $newArr, [string]$keyField, [string[]]$compareFields)
        $result = @{ Added = @(); Removed = @(); Changed = @() }
        $oldItems = @{}; $newItems = @{}
        foreach ($o in @($oldArr)) { if ($null -ne $o.$keyField) { $oldItems["$($o.$keyField)"] = $o } }
        foreach ($n in @($newArr)) { if ($null -ne $n.$keyField) { $newItems["$($n.$keyField)"] = $n } }
        # Added
        foreach ($key in $newItems.Keys) {
            if (-not $oldItems.ContainsKey($key)) { $result.Added += @{ $keyField = $key } }
        }
        # Removed
        foreach ($key in $oldItems.Keys) {
            if (-not $newItems.ContainsKey($key)) { $result.Removed += @{ $keyField = $key } }
        }
        # Changed
        foreach ($key in $newItems.Keys) {
            if ($oldItems.ContainsKey($key)) {
                $diffs = @{}
                foreach ($f in $compareFields) {
                    $ov = "$($oldItems[$key].$f)"; $nv = "$($newItems[$key].$f)"
                    if ($ov -ne $nv) { $diffs[$f] = @{ Old = $ov; New = $nv } }
                }
                if ($diffs.Count -gt 0) {
                    $changed = @{ $keyField = $key }
                    foreach ($dk in $diffs.Keys) { $changed[$dk] = $diffs[$dk] }
                    $result.Changed += $changed
                }
            }
        }
        return $result
    }

    # Software diff
    $oldSw = if ($null -ne $oldReport.Software) { $oldReport.Software } else { @() }
    $newSw = if ($null -ne $newReport.Software) { $newReport.Software } else { @() }
    if (@($oldSw).Count -gt 0 -or @($newSw).Count -gt 0) {
        $swDiff = & $diffArrays $oldSw $newSw 'Name' @('Version')
        $swCount = $swDiff.Added.Count + $swDiff.Removed.Count + $swDiff.Changed.Count
        if ($swCount -gt 0) {
            $changes['Software'] = $swDiff; $totalChanges += $swCount; $changedSections.Add('Software')
        }
    }

    # ListeningPorts diff
    $oldPorts = if ($null -ne $oldReport.ListeningPorts) { $oldReport.ListeningPorts } else { @() }
    $newPorts = if ($null -ne $newReport.ListeningPorts) { $newReport.ListeningPorts } else { @() }
    if (@($oldPorts).Count -gt 0 -or @($newPorts).Count -gt 0) {
        $portDiff = & $diffArrays $oldPorts $newPorts 'LocalPort' @('Process', 'BindAddress')
        $portCount = $portDiff.Added.Count + $portDiff.Removed.Count + $portDiff.Changed.Count
        if ($portCount -gt 0) {
            $changes['ListeningPorts'] = $portDiff; $totalChanges += $portCount; $changedSections.Add('ListeningPorts')
        }
    }

    # Services diff
    $oldSvc = if ($null -ne $oldReport.Services) { $oldReport.Services } else { @() }
    $newSvc = if ($null -ne $newReport.Services) { $newReport.Services } else { @() }
    if (@($oldSvc).Count -gt 0 -or @($newSvc).Count -gt 0) {
        $svcDiff = & $diffArrays $oldSvc $newSvc 'Name' @('Status', 'StartType', 'Health')
        $svcCount = $svcDiff.Added.Count + $svcDiff.Removed.Count + $svcDiff.Changed.Count
        if ($svcCount -gt 0) {
            $changes['Services'] = $svcDiff; $totalChanges += $svcCount; $changedSections.Add('Services')
        }
    }

    # Certificates diff
    $oldCerts = if ($null -ne $oldReport.Certificates) { $oldReport.Certificates } else { @() }
    $newCerts = if ($null -ne $newReport.Certificates) { $newReport.Certificates } else { @() }
    if (@($oldCerts).Count -gt 0 -or @($newCerts).Count -gt 0) {
        $certDiff = & $diffArrays $oldCerts $newCerts 'Thumbprint' @('Status', 'DaysRemaining')
        $certCount = $certDiff.Added.Count + $certDiff.Removed.Count + $certDiff.Changed.Count
        if ($certCount -gt 0) {
            $changes['Certificates'] = $certDiff; $totalChanges += $certCount; $changedSections.Add('Certificates')
        }
    }

    # Network diff
    $oldNet = if ($null -ne $oldReport.Network) { $oldReport.Network } else { @() }
    $newNet = if ($null -ne $newReport.Network) { $newReport.Network } else { @() }
    if (@($oldNet).Count -gt 0 -or @($newNet).Count -gt 0) {
        $netDiff = & $diffArrays $oldNet $newNet 'Name' @('Status', 'IPv4', 'Gateway', 'DNS', 'Speed')
        $netCount = $netDiff.Added.Count + $netDiff.Removed.Count + $netDiff.Changed.Count
        if ($netCount -gt 0) {
            $changes['Network'] = $netDiff; $totalChanges += $netCount; $changedSections.Add('Network')
        }
    }

    # Hardening score diff
    $oldScore = if ($null -ne $oldReport.Hardening -and $null -ne $oldReport.Hardening.Score) { $oldReport.Hardening.Score } else { $null }
    $newScore = if ($null -ne $newReport.Hardening -and $null -ne $newReport.Hardening.Score) { $newReport.Hardening.Score } else { $null }
    if ($null -ne $oldScore -and $null -ne $newScore -and $oldScore -ne $newScore) {
        $changes['Hardening'] = @{ ScoreOld = $oldScore; ScoreNew = $newScore; ScoreDelta = $newScore - $oldScore }
        $totalChanges++; $changedSections.Add('Hardening')
    }

    # Health status diff
    $oldHealth = if ($null -ne $oldReport.Health -and $null -ne $oldReport.Health.Health) { "$($oldReport.Health.Health)" } else { $null }
    $newHealth = if ($null -ne $newReport.Health -and $null -ne $newReport.Health.Health) { "$($newReport.Health.Health)" } else { $null }
    if ($null -ne $oldHealth -and $null -ne $newHealth -and $oldHealth -ne $newHealth) {
        $changes['Health'] = @{ Old = $oldHealth; New = $newHealth }
        $totalChanges++; $changedSections.Add('Health')
    }

    # Uptime diff
    $oldUptime = if ($null -ne $oldReport.Uptime -and $null -ne $oldReport.Uptime.Days) { $oldReport.Uptime.Days } else { $null }
    $newUptime = if ($null -ne $newReport.Uptime -and $null -ne $newReport.Uptime.Days) { $newReport.Uptime.Days } else { $null }
    if ($null -ne $oldUptime -and $null -ne $newUptime) {
        # Uptime decreased = reboot happened
        if ($newUptime -lt $oldUptime) {
            $changes['Uptime'] = @{ OldDays = $oldUptime; NewDays = $newUptime; Rebooted = $true }
            $totalChanges++; $changedSections.Add('Uptime')
        }
    }

    $hostname = if ($newReport.Hostname) { $newReport.Hostname } elseif ($oldReport.Hostname) { $oldReport.Hostname } else { "Unknown" }

    return @{
        Hostname        = $hostname
        TimestampOld    = if ($oldReport.Timestamp) { $oldReport.Timestamp } else { $null }
        TimestampNew    = if ($newReport.Timestamp) { $newReport.Timestamp } else { $null }
        TotalChanges    = $totalChanges
        ChangedSections = @($changedSections)
        Changes         = $changes
    }
}
#endregion