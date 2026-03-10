#region ===== HTML REPORTING (v2.8.0) =====
# HTML-encode dynamic values to prevent display issues with special characters
function ConvertTo-HtmlSafe([string]$s) { if ($s) { [System.Net.WebUtility]::HtmlEncode($s) } else { $s } }

# Function to generate HTML health report
function Export-HTMLHealthReport {
    param(
        [string]$OutputPath = "$env:USERPROFILE\Desktop\HealthReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
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

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Gathering system information..." -color "Info"

    # Gather data (CIM with timeout — immune to WMI hangs)
    $cimResult = Invoke-WithTimeout -ScriptBlock {
        @{
            OS  = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
            CS  = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
            CPU = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue
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

    # CPU load
    $cpuLoadMeasure = if ($cpuAll) { ($cpuAll | Measure-Object -Property LoadPercentage -Average).Average } else { $null }
    $cpuLoad = if ($null -ne $cpuLoadMeasure) { $cpuLoadMeasure } else { 0 }
    $cpuStatus = if ($cpuLoad -gt 80) { "bad" } elseif ($cpuLoad -gt 50) { "warn" } else { "good" }

    # Memory
    $totalMemGB = if ($os) { [math]::Round($os.TotalVisibleMemorySize / 1MB, 2) } else { 0 }
    $freeMemGB = if ($os) { [math]::Round($os.FreePhysicalMemory / 1MB, 2) } else { 0 }
    $usedMemGB = $totalMemGB - $freeMemGB
    $memPercent = if ($totalMemGB -gt 0) { [math]::Round(($usedMemGB / $totalMemGB) * 100, 1) } else { 0 }
    $memStatus = if ($memPercent -gt 90) { "bad" } elseif ($memPercent -gt 75) { "warn" } else { "good" }

    # Disks
    $diskResult = Invoke-WithTimeout -ScriptBlock {
        Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
    } -TimeoutSeconds 10 -Activity "Querying disk info"
    $disks = if ($diskResult.TimedOut) { $null } else { $diskResult.Result }
    $diskHtml = ""
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

    # Network adapters (batch query to avoid N+1)
    $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" }
    $allIPv4Html = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $networkHtml = ""
    if (-not $adapters) {
        $networkHtml = "<tr><td colspan='4'>No active network adapters found</td></tr>"
    }
    foreach ($adapter in $adapters) {
        $ip = $allIPv4Html | Where-Object { $_.InterfaceAlias -eq $adapter.Name }
        $ipStr = if ($ip) { $ip.IPAddress } else { "No IP" }
        $networkHtml += "<tr><td>$(ConvertTo-HtmlSafe $adapter.Name)</td><td>$(ConvertTo-HtmlSafe $ipStr)</td><td class='status-good'>Up</td><td>$(ConvertTo-HtmlSafe $adapter.LinkSpeed)</td></tr>"
    }

    # Services
    $keyServices = @(
        @{ Name = "wuauserv"; Display = "Windows Update" },
        @{ Name = "WinRM"; Display = "WinRM" },
        @{ Name = "vmms"; Display = "Hyper-V Management" },
        @{ Name = "TermService"; Display = "Remote Desktop" }
    )
    $servicesHtml = ""
    foreach ($svc in $keyServices) {
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($service) {
            $svcStatus = if ($service.Status -eq "Running") { "good" } else { "warn" }
            $servicesHtml += "<tr><td>$(ConvertTo-HtmlSafe $svc.Display)</td><td class='status-$svcStatus'>$(ConvertTo-HtmlSafe $service.Status)</td></tr>"
        }
    }

    # Certificates
    $certHtml = ""
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

    # Disk I/O Latency (v1.7.0)
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

    # NIC Error Counters (v1.7.0)
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

    # Memory Pressure (v1.7.0)
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

    # Hyper-V Guest Health (v1.7.0)
    $hvGuestHtml = ""
    if (Test-HyperVInstalled) {
        $hvGuestHtml = "<h2>Hyper-V Guest Health</h2><table><tr><th>VM</th><th>Heartbeat</th><th>vCPU</th><th>RAM (GB)</th></tr>"
        try {
            $hvVMs = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Running" }
            if ($hvVMs) {
                foreach ($hvm in $hvVMs) {
                    $hvHb = Get-VMIntegrationService -VM $hvm -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Heartbeat" }
                    $hvHbSt = if ($hvHb -and $hvHb.PrimaryStatusDescription -eq "OK") { "good" } else { "warn" }
                    $hvHbTxt = if ($hvHb) { $hvHb.PrimaryStatusDescription } else { "N/A" }
                    $hvRAM = [math]::Round($hvm.MemoryAssigned / 1GB, 1)
                    $hvGuestHtml += "<tr><td>$(ConvertTo-HtmlSafe $hvm.Name)</td><td class='status-$hvHbSt'>$hvHbTxt</td><td>$($hvm.ProcessorCount)</td><td>$hvRAM</td></tr>"
                }
            } else { $hvGuestHtml += "<tr><td colspan='4'>No running VMs</td></tr>" }
        } catch { $hvGuestHtml += "<tr><td colspan='4'>Guest health unavailable</td></tr>" }
        $hvGuestHtml += "</table>"
    }

    # Top 5 CPU Processes (v1.7.0)
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

    # Time Sync Status
    $timeSyncHtml = "<table><tr><th>Property</th><th>Value</th><th>Status</th></tr>"
    try {
        $w32tmOut = w32tm /query /status 2>&1
        $timeSyncSource = "Unknown"
        $timeSyncOffset = $null
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

    # Firewall Status
    $firewallHtml = "<table><tr><th>Profile</th><th>Enabled</th><th>Status</th></tr>"
    try {
        $fwProfiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
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

    # Recent Critical Events (24h)
    $critEventsHtml = "<table><tr><th>Time</th><th>Source</th><th>ID</th><th>Message</th></tr>"
    try {
        $critEvents = @(Get-WinEvent -FilterHashtable @{LogName='System','Application'; Level=1,2; StartTime=(Get-Date).AddHours(-24)} -MaxEvents 10 -ErrorAction SilentlyContinue)
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
    try {
        foreach ($fwProf in $fwProfiles) {
            if ($fwProf.Enabled -ne $true) { $issues += "Firewall profile '$($fwProf.Name)' disabled"; break }
        }
    } catch { }
    if ($critEvents.Count -ge 5) { $issues += "$($critEvents.Count) critical/error events in last 24h" }

    $overallStatus = if ($issues.Count -eq 0) { "good" } elseif ($issues.Count -le 2) { "warn" } else { "bad" }
    $overallText = if ($issues.Count -eq 0) { "HEALTHY" } else { "ATTENTION NEEDED" }
    $issuesHtml = if ($issues.Count -eq 0) { "<li class='status-good'>No issues detected</li>" } else { ($issues | ForEach-Object { "<li class='status-warn'>$(ConvertTo-HtmlSafe $_)</li>" }) -join "`n" }

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
    </style>
</head>
<body>
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
            <div class="info-box"><div class="info-label">Uptime</div><div class="info-value">$uptimeStr</div></div>
        </div>

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

        <h2>Disk Space</h2>
        <table>
            <tr><th>Drive</th><th>Total</th><th>Free</th><th>Used %</th><th>Usage</th></tr>
            $diskHtml
        </table>

        <h2>Network Adapters</h2>
        <table>
            <tr><th>Adapter</th><th>IP Address</th><th>Status</th><th>Speed</th></tr>
            $networkHtml
        </table>

        <h2>Key Services</h2>
        <table>
            <tr><th>Service</th><th>Status</th></tr>
            $servicesHtml
        </table>

        <h2>Certificates</h2>
        <table>
            <tr><th>Subject</th><th>Expires</th><th>Days Left</th><th>Status</th></tr>
            $certHtml
        </table>

        <h2>Disk I/O Latency</h2>
        $diskIOHtml

        <h2>NIC Error Counters</h2>
        $nicErrorHtml

        <h2>Memory Pressure</h2>
        $memPressureHtml

        $hvGuestHtml

        <h2>Top 5 CPU Processes</h2>
        $topProcsHtml

        <h2>Time Sync</h2>
        $timeSyncHtml

        <h2>Firewall Status</h2>
        $firewallHtml

        <h2>Recent Critical Events (24h)</h2>
        $critEventsHtml

        <div class="footer">
            Report generated by $($script:ToolFullName) v$($script:ScriptVersion)
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
    </style>
</head>
<body>
    <div class="container">
        <h1>Configuration Profile Comparison</h1>
        <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>

        <div class="summary">
            <strong>Profile 1:</strong> <span class="file-name">$(ConvertTo-HtmlSafe (Split-Path $Profile1Path -Leaf))</span><br>
            <strong>Profile 2:</strong> <span class="file-name">$(ConvertTo-HtmlSafe (Split-Path $Profile2Path -Leaf))</span><br><br>
            <strong>Result:</strong> $summaryText
        </div>

        <table>
            <tr><th>Property</th><th>Profile 1</th><th>Profile 2</th><th>Status</th></tr>
            $rowsHtml
        </table>

        <div class="footer">
            Report generated by $($script:ToolFullName) v$($script:ScriptVersion)
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

    $ready = 0
    $total = 0
    $rows = ""

    # Helper to add a check row
    function Add-ReadinessRow {
        param([string]$Cat, [string]$Name, [string]$Value, [string]$Status)
        $class = switch ($Status) { "ok" { "good" }; "warn" { "warn" }; "fail" { "bad" }; default { "good" } }
        $icon = switch ($Status) { "ok" { "&#10004;" }; "warn" { "&#9888;" }; "fail" { "&#10008;" }; default { "?" } }
        return "<tr><td>$(ConvertTo-HtmlSafe $Cat)</td><td>$(ConvertTo-HtmlSafe $Name)</td><td class='status-$class'>$icon $(ConvertTo-HtmlSafe $Value)</td></tr>"
    }

    # Hostname
    $hostname = $env:COMPUTERNAME
    $isDefault = $hostname -match '^WIN-|^DESKTOP-|^YOURSERVERNAME'
    $total++
    if (-not $isDefault) { $ready++; $rows += Add-ReadinessRow -Cat "Identity" -Name "Hostname" -Value $hostname -Status "ok" }
    else { $rows += Add-ReadinessRow -Cat "Identity" -Name "Hostname" -Value "$hostname (default)" -Status "fail" }

    # Domain
    $csResult = Invoke-WithTimeout -ScriptBlock { Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue } -TimeoutSeconds 10 -Activity "Checking domain"
    $cs = if ($csResult.TimedOut) { $null } else { $csResult.Result }
    $total++
    if ($cs -and $cs.PartOfDomain) { $ready++; $rows += Add-ReadinessRow -Cat "Identity" -Name "Domain" -Value $cs.Domain -Status "ok" }
    else { $rows += Add-ReadinessRow -Cat "Identity" -Name "Domain" -Value "WORKGROUP" -Status "warn" }

    # Site Number
    $total++
    $siteNum = Get-SiteNumberFromHostname
    if ($siteNum) { $ready++; $rows += Add-ReadinessRow -Cat "Identity" -Name "Site Number" -Value $siteNum -Status "ok" }
    else { $rows += Add-ReadinessRow -Cat "Identity" -Name "Site Number" -Value "Not detected" -Status "warn" }

    # RDP
    $total++
    $rdp = Get-RDPState
    if ($rdp -eq "Enabled") { $ready++; $rows += Add-ReadinessRow -Cat "Remote Access" -Name "RDP" -Value "Enabled" -Status "ok" }
    else { $rows += Add-ReadinessRow -Cat "Remote Access" -Name "RDP" -Value "Disabled" -Status "warn" }

    # WinRM
    $total++
    $winrm = Get-WinRMState
    if ($winrm -eq "Enabled") { $ready++; $rows += Add-ReadinessRow -Cat "Remote Access" -Name "WinRM" -Value "Enabled" -Status "ok" }
    else { $rows += Add-ReadinessRow -Cat "Remote Access" -Name "WinRM" -Value $winrm -Status "warn" }

    # Agent (only if configured)
    if (Test-AgentInstallerConfigured) {
        $total++
        $agentCheck = Test-AgentInstalled
        if ($agentCheck.Installed) {
            $ready++
            $kVal = if ($agentCheck.Status -eq "Running") { "Running" } else { "$($agentCheck.Status)" }
            $rows += Add-ReadinessRow -Cat "Software" -Name "$($script:AgentInstaller.ToolName) Agent" -Value $kVal -Status "ok"
        } else { $rows += Add-ReadinessRow -Cat "Software" -Name "$($script:AgentInstaller.ToolName) Agent" -Value "Not Installed" -Status "fail" }
    }

    # Hyper-V
    $total++
    if (Test-HyperVInstalled) { $ready++; $rows += Add-ReadinessRow -Cat "Roles" -Name "Hyper-V" -Value "Installed" -Status "ok" }
    else { $rows += Add-ReadinessRow -Cat "Roles" -Name "Hyper-V" -Value "Not Installed" -Status "warn" }

    # Server-only roles
    if (Test-WindowsServer) {
        $total++
        if (Test-MPIOInstalled) { $ready++; $rows += Add-ReadinessRow -Cat "Roles" -Name "MPIO" -Value "Installed" -Status "ok" }
        else { $rows += Add-ReadinessRow -Cat "Roles" -Name "MPIO" -Value "Not Installed" -Status "warn" }

        $total++
        if (Test-FailoverClusteringInstalled) { $ready++; $rows += Add-ReadinessRow -Cat "Roles" -Name "Failover Clustering" -Value "Installed" -Status "ok" }
        else { $rows += Add-ReadinessRow -Cat "Roles" -Name "Failover Clustering" -Value "Not Installed" -Status "warn" }
    }

    # Firewall
    $total++
    $fw = Get-FirewallState
    if ($fw.Domain -eq "Enabled" -and $fw.Private -eq "Enabled" -and $fw.Public -eq "Enabled") {
        $ready++; $rows += Add-ReadinessRow -Cat "Network" -Name "Firewall" -Value "All profiles enabled" -Status "ok"
    } else {
        $disabled = @()
        if ($fw.Domain -ne "Enabled") { $disabled += "Domain" }
        if ($fw.Private -ne "Enabled") { $disabled += "Private" }
        if ($fw.Public -ne "Enabled") { $disabled += "Public" }
        $rows += Add-ReadinessRow -Cat "Network" -Name "Firewall" -Value "Disabled: $($disabled -join ', ')" -Status "warn"
    }

    # Network
    $total++
    $nics = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" })
    if ($nics.Count -gt 0) { $ready++; $rows += Add-ReadinessRow -Cat "Network" -Name "Adapters" -Value "$($nics.Count) up" -Status "ok" }
    else { $rows += Add-ReadinessRow -Cat "Network" -Name "Adapters" -Value "None up" -Status "fail" }

    # Power
    $total++
    $power = Get-CurrentPowerPlan
    if ($power.Name -eq "High performance") { $ready++; $rows += Add-ReadinessRow -Cat "System" -Name "Power Plan" -Value "High Performance" -Status "ok" }
    else { $rows += Add-ReadinessRow -Cat "System" -Name "Power Plan" -Value $power.Name -Status "warn" }

    # Reboot
    $total++
    if (Test-RebootPending) { $rows += Add-ReadinessRow -Cat "System" -Name "Reboot Pending" -Value "YES" -Status "fail" }
    else { $ready++; $rows += Add-ReadinessRow -Cat "System" -Name "Reboot Pending" -Value "No" -Status "ok" }

    # License
    $total++
    $lic = Test-WindowsActivated
    if ($lic) { $ready++; $rows += Add-ReadinessRow -Cat "System" -Name "Windows License" -Value "Activated" -Status "ok" }
    else { $rows += Add-ReadinessRow -Cat "System" -Name "Windows License" -Value "Not Activated" -Status "warn" }

    # C: Drive Space
    $total++
    try {
        $cVol = Get-Volume -DriveLetter C -ErrorAction Stop
        if ($null -ne $cVol -and $cVol.Size -gt 0) {
            $freeGB = [math]::Round($cVol.SizeRemaining / 1GB, 1)
            $totalGB = [math]::Round($cVol.Size / 1GB, 1)
            $usedPct = [math]::Round((($cVol.Size - $cVol.SizeRemaining) / $cVol.Size) * 100)
            if ($freeGB -lt 5) {
                $rows += Add-ReadinessRow -Cat "Storage" -Name "C: Drive Space" -Value "${freeGB}GB free of ${totalGB}GB ($usedPct% used)" -Status "fail"
            } elseif ($freeGB -lt 20) {
                $rows += Add-ReadinessRow -Cat "Storage" -Name "C: Drive Space" -Value "${freeGB}GB free of ${totalGB}GB ($usedPct% used)" -Status "warn"
            } else {
                $ready++; $rows += Add-ReadinessRow -Cat "Storage" -Name "C: Drive Space" -Value "${freeGB}GB free of ${totalGB}GB" -Status "ok"
            }
        } else {
            $rows += Add-ReadinessRow -Cat "Storage" -Name "C: Drive Space" -Value "Unable to read" -Status "warn"
        }
    } catch {
        $rows += Add-ReadinessRow -Cat "Storage" -Name "C: Drive Space" -Value "Check failed" -Status "warn"
    }

    # DNS Resolution
    $total++
    try {
        $dnsResult = Resolve-DnsName -Name "dns.msftncsi.com" -Type A -DnsOnly -ErrorAction Stop
        if ($dnsResult) {
            $ready++; $rows += Add-ReadinessRow -Cat "Network" -Name "DNS Resolution" -Value "Working" -Status "ok"
        } else {
            $rows += Add-ReadinessRow -Cat "Network" -Name "DNS Resolution" -Value "No response" -Status "warn"
        }
    } catch {
        $rows += Add-ReadinessRow -Cat "Network" -Name "DNS Resolution" -Value "Failed" -Status "fail"
    }

    # Time Sync
    $total++
    try {
        $w32tmOut = w32tm /query /status 2>&1
        $tsSource = "Unknown"
        foreach ($tsLine in $w32tmOut) {
            $tsText = $tsLine.ToString()
            if ($tsText -match 'Source:\s*(.+)') { $regexMatches = $matches; $tsSource = $regexMatches[1].Trim() }
        }
        if ($tsSource -match 'Free-Running|Local CMOS') {
            $rows += Add-ReadinessRow -Cat "System" -Name "Time Sync" -Value "No external source ($tsSource)" -Status "warn"
        } else {
            $ready++; $rows += Add-ReadinessRow -Cat "System" -Name "Time Sync" -Value "Source: $tsSource" -Status "ok"
        }
    } catch {
        $rows += Add-ReadinessRow -Cat "System" -Name "Time Sync" -Value "Unable to check" -Status "warn"
    }

    # Windows Defender
    $total++
    try {
        $mpStat = Get-MpComputerStatus -ErrorAction Stop
        if ($mpStat.RealTimeProtectionEnabled) {
            $ready++; $rows += Add-ReadinessRow -Cat "Security" -Name "Defender Real-Time" -Value "Enabled" -Status "ok"
        } else {
            $rows += Add-ReadinessRow -Cat "Security" -Name "Defender Real-Time" -Value "DISABLED" -Status "fail"
        }
    } catch {
        $rows += Add-ReadinessRow -Cat "Security" -Name "Defender Real-Time" -Value "Unavailable" -Status "warn"
    }

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
    </style>
</head>
<body>
    <div class="container">
        <h1>Server Readiness Report</h1>
        <div class="info">
            <div class="info-item"><div class="info-label">Server</div><div class="info-value">$(ConvertTo-HtmlSafe $cs.Name)</div></div>
            <div class="info-item"><div class="info-label">Generated</div><div class="info-value">$(Get-Date -Format 'yyyy-MM-dd HH:mm')</div></div>
            <div class="info-item"><div class="info-label">Tool Version</div><div class="info-value">v$($script:ScriptVersion)</div></div>
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
            Report generated by $($script:ToolFullName) v$($script:ScriptVersion)
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
                OS   = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
                CPU  = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
                Disk = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
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
        $diskSection = "<h2>Disk Usage (Latest)</h2><table>"
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
    </style>
</head>
<body>
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
            Report generated by $($script:ToolFullName) v$($script:ScriptVersion)
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
#endregion