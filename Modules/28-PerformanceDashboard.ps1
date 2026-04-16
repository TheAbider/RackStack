#region ===== PERFORMANCE DASHBOARD =====
# Function to show real-time performance metrics
function Show-PerformanceDashboard {
    while ($true) {
        if ($global:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                      PERFORMANCE DASHBOARD").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        # Batch CIM queries with timeout (immune to WMI hangs)
        $cimResult = Invoke-WithTimeout -ScriptBlock {
            @{
                CPU = Get-CimInstance Win32_Processor -OperationTimeoutSec 8 -ErrorAction SilentlyContinue
                OS  = Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 8 -ErrorAction SilentlyContinue
            }
        } -TimeoutSeconds 10 -Activity "Refreshing metrics"

        if ($cimResult.TimedOut) {
            Write-OutputColor "  WMI/CIM query timed out. Press [R] to retry." -color "Warning"
            $choice = Read-Host "  "
            if ($choice -and $choice.ToLower().Trim() -eq "r") { continue }
            return
        }

        # Guard against Failed path from Invoke-WithTimeout (e.g., runspace creation failed).
        # In that case Result is $null and naive .CPU/.OS access would crash.
        if ($cimResult.Failed -or $null -eq $cimResult.Result) {
            Write-OutputColor "  WMI/CIM query failed: $($cimResult.Error). Press [R] to retry." -color "Error"
            $choice = Read-Host "  "
            if ($choice -and $choice.ToLower().Trim() -eq "r") { continue }
            return
        }

        $cpuAll = $cimResult.Result.CPU
        $os = $cimResult.Result.OS

        # CPU
        $cpu = $cpuAll | Measure-Object -Property LoadPercentage -Average
        $cpuAvg = if ($null -ne $cpu.Average) { [math]::Round($cpu.Average, 1) } else { 0 }
        $cpuColor = if ($cpuAvg -lt 70) { "Success" } elseif ($cpuAvg -lt 90) { "Warning" } else { "Error" }
        $cpuBar = Get-ProgressBar -Percent $cpuAvg -Width 40

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  CPU USAGE".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  $cpuBar $cpuAvg%".PadRight(72))│" -color $cpuColor
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        # Memory
        if ($os) {
            $totalMem = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
            $freeMem = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        } else {
            $totalMem = 0
            $freeMem = 0
        }
        $usedMem = $totalMem - $freeMem
        $memPercent = if ($totalMem -gt 0) { [math]::Round(($usedMem / $totalMem) * 100, 1) } else { 0 }
        $memColor = if ($memPercent -lt 70) { "Success" } elseif ($memPercent -lt 90) { "Warning" } else { "Error" }
        $memBar = Get-ProgressBar -Percent $memPercent -Width 40

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  MEMORY USAGE".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  $memBar $memPercent%".PadRight(72))│" -color $memColor
        Write-OutputColor "  │$("  Used: $usedMem GB / Total: $totalMem GB / Free: $freeMem GB".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        # Disk
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  DISK USAGE".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        $volumes = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveType -eq "Fixed" }
        if (-not $volumes) {
            Write-OutputColor "  │$("  No fixed volumes detected".PadRight(72))│" -color "Warning"
        }
        foreach ($vol in @($volumes | Where-Object { $_.Size -gt 0 })) {
            $totalGB = [math]::Round($vol.Size / 1GB, 1)
            $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 1)
            $usedPercent = if ($totalGB -gt 0) { [math]::Round((($totalGB - $freeGB) / $totalGB) * 100, 1) } else { 0 }
            $diskColor = if ($usedPercent -lt 80) { "Success" } elseif ($usedPercent -lt 95) { "Warning" } else { "Error" }
            $diskBar = Get-ProgressBar -Percent $usedPercent -Width 30
            Write-OutputColor "  │$("  $($vol.DriveLetter): $diskBar $usedPercent% (Free: $freeGB GB)".PadRight(72))│" -color $diskColor
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        # Disk I/O Latency
        $diskIOData = Show-DiskIOMetrics
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  DISK I/O LATENCY".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        if (@($diskIOData).Count -eq 0) {
            Write-OutputColor "  │$("  No physical disk performance data available".PadRight(72))│" -color "Warning"
        } else {
            $headerLine = "  {0,-17} {1,-14} {2,-8} {3,-12}" -f "Disk", "Latency(R/W)", "Queue", "Throughput"
            Write-OutputColor "  │$($headerLine.PadRight(72))│" -color "Info"
            $separatorLine = "  {0,-17} {1,-14} {2,-8} {3,-12}" -f "─────────────", "────────────", "─────", "──────────"
            Write-OutputColor "  │$($separatorLine.PadRight(72))│" -color "Info"
            foreach ($diskIO in $diskIOData) {
                $latencyColor = if ($diskIO.MaxLatency -gt 20) { "Error" } elseif ($diskIO.MaxLatency -ge 5) { "Warning" } else { "Success" }
                $queueColor = if ($diskIO.QueueLength -gt 4) { "Error" } elseif ($diskIO.QueueLength -ge 2) { "Warning" } else { "Success" }
                $worstColor = if ($latencyColor -eq "Error" -or $queueColor -eq "Error") { "Error" } elseif ($latencyColor -eq "Warning" -or $queueColor -eq "Warning") { "Warning" } else { "Success" }
                $dataLine = "  {0,-17} {1,-14} {2,-8} {3,-12}" -f $diskIO.Name, $diskIO.LatencyDisplay, $diskIO.QueueDisplay, $diskIO.ThroughputDisplay
                Write-OutputColor "  │$($dataLine.PadRight(72))│" -color $worstColor
            }
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        # Network
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  NETWORK ADAPTERS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | Select-Object -First 5
        if (-not $adapters) {
            Write-OutputColor "  │$("  No active network adapters".PadRight(72))│" -color "Warning"
        }
        foreach ($adapter in $adapters) {
            $speed = if ($adapter.LinkSpeed) { $adapter.LinkSpeed } else { "Unknown" }
            $name = if ($adapter.Name.Length -gt 30) { $adapter.Name.Substring(0,27) + "..." } else { $adapter.Name }
            Write-OutputColor "  │$("  $name - $speed".PadRight(72))│" -color "Success"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        # Network Bandwidth
        $bandwidthData = Show-NetworkBandwidth
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  NETWORK BANDWIDTH".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        if (@($bandwidthData).Count -eq 0) {
            Write-OutputColor "  │$("  No active adapters with bandwidth data".PadRight(72))│" -color "Warning"
        } else {
            $bwHeader = "  {0,-17} {1,-10} {2,-10} {3,-10} {4,-8}" -f "Adapter", "Speed", "TX/s", "RX/s", "Errors"
            Write-OutputColor "  │$($bwHeader.PadRight(72))│" -color "Info"
            $bwSep = "  {0,-17} {1,-10} {2,-10} {3,-10} {4,-8}" -f "─────────────", "──────", "──────", "──────", "──────"
            Write-OutputColor "  │$($bwSep.PadRight(72))│" -color "Info"
            foreach ($bw in $bandwidthData) {
                $bwColor = if ($bw.HasErrors) { "Warning" } else { "Success" }
                $bwLine = "  {0,-17} {1,-10} {2,-10} {3,-10} {4,-8}" -f $bw.Name, $bw.Speed, $bw.TxDisplay, $bw.RxDisplay, $bw.ErrorCount
                Write-OutputColor "  │$($bwLine.PadRight(72))│" -color $bwColor
            }
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        # Uptime (reuse $os from memory section above)
        $bootTime = if ($os) { $os.LastBootUpTime } else { $null }
        $uptime = if ($bootTime) { (Get-Date) - $bootTime } else { $null }
        $uptimeStr = if ($uptime) { "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m" } else { "Unknown" }

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  SYSTEM INFO".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  Uptime: $uptimeStr".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Last Boot: $(if ($bootTime) { $bootTime.ToString('yyyy-MM-dd HH:mm:ss') } else { 'Unknown' })".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        # Top Processes
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  TOP PROCESSES (by CPU)".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        $topProcs = Get-Process -ErrorAction SilentlyContinue | Sort-Object CPU -Descending | Select-Object -First 5
        foreach ($proc in $topProcs) {
            $procName = if ($proc.ProcessName.Length -gt 25) { $proc.ProcessName.Substring(0,22) + "..." } else { $proc.ProcessName }
            $cpuSec = if ($null -ne $proc.CPU) { [math]::Round($proc.CPU, 1) } else { 0 }
            $memMB = [math]::Round($proc.WorkingSet64 / 1MB, 0)
            $line = "  $procName (PID $($proc.Id)) - CPU: ${cpuSec}s - Mem: $memMB MB"
            Write-OutputColor "  │$($line.PadRight(72))│" -color "Info"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        # Top Processes by Memory
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  TOP PROCESSES (by Memory)".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        $topMemProcs = Get-Process -ErrorAction SilentlyContinue | Sort-Object WorkingSet64 -Descending | Select-Object -First 5
        foreach ($proc in $topMemProcs) {
            $procName = if ($proc.ProcessName.Length -gt 25) { $proc.ProcessName.Substring(0,22) + "..." } else { $proc.ProcessName }
            $memMB = [math]::Round($proc.WorkingSet64 / 1MB, 0)
            $line = "  $procName (PID $($proc.Id)) - $memMB MB"
            Write-OutputColor "  │$($line.PadRight(72))│" -color "Info"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  [R] Refresh  |  [C] Copy to Clipboard  |  Press Enter or [B] to go back" -color "Info"
        $choice = Read-Host "  "
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }
        $lowerChoice = if ($choice) { $choice.ToLower().Trim() } else { "" }
        if ($lowerChoice -eq "r") { continue }
        if ($lowerChoice -eq "c") {
            $clipLines = @(
                "=== System Performance Summary ==="
                "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                "Hostname:  $env:COMPUTERNAME"
                ""
                "CPU:    $cpuAvg%"
                "Memory: $memPercent% ($usedMem GB / $totalMem GB)"
                "Uptime: $uptimeStr"
                ""
                "Disks:"
            )
            foreach ($vol in $volumes) {
                $dTotal = [math]::Round($vol.Size / 1GB, 1)
                $dFree = [math]::Round($vol.SizeRemaining / 1GB, 1)
                $dUsed = if ($dTotal -gt 0) { [math]::Round((($dTotal - $dFree) / $dTotal) * 100, 1) } else { 0 }
                $clipLines += "  $($vol.DriveLetter): $dUsed% used ($dFree GB free / $dTotal GB)"
            }
            $clipLines += ""
            $clipLines += "Disk I/O:"
            foreach ($diskIO in $diskIOData) {
                $clipLines += "  $($diskIO.Name) - Latency: $($diskIO.LatencyDisplay) - Queue: $($diskIO.QueueDisplay) - $($diskIO.ThroughputDisplay)"
            }
            $clipLines += ""
            $clipLines += "Network:"
            foreach ($adapter in $adapters) {
                $clipLines += "  $($adapter.Name) - $($adapter.LinkSpeed)"
            }
            $clipLines += ""
            $clipLines += "Network Bandwidth:"
            foreach ($bw in $bandwidthData) {
                $clipLines += "  $($bw.Name) - TX: $($bw.TxDisplay)/s - RX: $($bw.RxDisplay)/s - Errors: $($bw.ErrorCount)"
            }
            $clipLines += ""
            $clipLines += "Top Processes (by CPU):"
            foreach ($proc in $topProcs) {
                $pCpu = if ($null -ne $proc.CPU) { [math]::Round($proc.CPU, 1) } else { 0 }
                $pMem = [math]::Round($proc.WorkingSet64 / 1MB, 0)
                $clipLines += "  $($proc.ProcessName) (PID $($proc.Id)) - CPU: ${pCpu}s - Mem: $pMem MB"
            }
            $clipLines += ""
            $clipLines += "Top Processes (by Memory):"
            foreach ($proc in $topMemProcs) {
                $pMem = [math]::Round($proc.WorkingSet64 / 1MB, 0)
                $pCpu = if ($null -ne $proc.CPU) { [math]::Round($proc.CPU, 1) } else { 0 }
                $clipLines += "  $($proc.ProcessName) (PID $($proc.Id)) - Mem: $pMem MB - CPU: ${pCpu}s"
            }
            ($clipLines -join "`r`n") | clip.exe
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  System info copied to clipboard." -color "Success"
            Start-Sleep -Seconds 1
            continue
        }
        return
    }
}

# Collect disk I/O latency metrics from performance counters
function Show-DiskIOMetrics {
    $diskPerf = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -OperationTimeoutSec 8 -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne "_Total" }

    if (-not $diskPerf) { return @() }

    $results = @()
    foreach ($disk in $diskPerf) {
        $diskName = $disk.Name
        if ($diskName.Length -gt 15) { $diskName = $diskName.Substring(0, 12) + "..." }

        $readLatency = [math]::Round($disk.AvgDiskSecPerRead * 1000, 1)
        $writeLatency = [math]::Round($disk.AvgDiskSecPerWrite * 1000, 1)
        $maxLatency = [math]::Max($readLatency, $writeLatency)
        $queueLength = [math]::Round($disk.AvgDiskQueueLength, 1)

        $totalBytes = $disk.DiskReadBytesPerSec + $disk.DiskWriteBytesPerSec
        if ($totalBytes -ge 1MB) {
            $throughputDisplay = "$([math]::Round($totalBytes / 1MB, 1)) MB/s"
        } elseif ($totalBytes -ge 1KB) {
            $throughputDisplay = "$([math]::Round($totalBytes / 1KB, 1)) KB/s"
        } else {
            $throughputDisplay = "$totalBytes B/s"
        }

        $results += [PSCustomObject]@{
            Name              = $diskName
            ReadLatency       = $readLatency
            WriteLatency      = $writeLatency
            MaxLatency        = $maxLatency
            LatencyDisplay    = "${readLatency}ms / ${writeLatency}ms"
            QueueLength       = $queueLength
            QueueDisplay      = "$queueLength"
            ThroughputDisplay = $throughputDisplay
        }
    }
    return $results
}

# Collect network bandwidth utilization by sampling two intervals
function Show-NetworkBandwidth {
    $upAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | Select-Object -First 5
    if (-not $upAdapters) { return @() }

    # First sample
    $sample1 = @{}
    foreach ($adp in $upAdapters) {
        $stats = Get-NetAdapterStatistics -Name $adp.Name -ErrorAction SilentlyContinue
        if ($null -ne $stats) {
            $sample1[$adp.Name] = @{
                SentBytes     = $stats.SentBytes
                ReceivedBytes = $stats.ReceivedBytes
            }
        }
    }

    Start-Sleep -Seconds 1

    # Second sample and calculate rates
    $results = @()
    foreach ($adp in $upAdapters) {
        if (-not $sample1.ContainsKey($adp.Name)) { continue }

        $stats2 = Get-NetAdapterStatistics -Name $adp.Name -ErrorAction SilentlyContinue
        if ($null -eq $stats2) { continue }

        $txRate = $stats2.SentBytes - $sample1[$adp.Name].SentBytes
        $rxRate = $stats2.ReceivedBytes - $sample1[$adp.Name].ReceivedBytes
        if ($txRate -lt 0) { $txRate = 0 }
        if ($rxRate -lt 0) { $rxRate = 0 }

        $txDisplay = if ($txRate -ge 1MB) { "$([math]::Round($txRate / 1MB, 1)) MB" } elseif ($txRate -ge 1KB) { "$([math]::Round($txRate / 1KB, 1)) KB" } else { "$txRate B" }
        $rxDisplay = if ($rxRate -ge 1MB) { "$([math]::Round($rxRate / 1MB, 1)) MB" } elseif ($rxRate -ge 1KB) { "$([math]::Round($rxRate / 1KB, 1)) KB" } else { "$rxRate B" }

        $adapterName = $adp.Name
        if ($adapterName.Length -gt 15) { $adapterName = $adapterName.Substring(0, 12) + "..." }

        $adpSpeed = if ($adp.LinkSpeed) { $adp.LinkSpeed } else { "Unknown" }
        if ($adpSpeed.Length -gt 8) { $adpSpeed = $adpSpeed.Substring(0, 8) }

        $errorTotal = $stats2.OutboundDiscardedPackets + $stats2.InboundDiscardedPackets + $stats2.OutboundPacketErrors + $stats2.InboundPacketErrors
        $hasErrors = $errorTotal -gt 0

        $results += [PSCustomObject]@{
            Name       = $adapterName
            Speed      = $adpSpeed
            TxDisplay  = $txDisplay
            RxDisplay  = $rxDisplay
            ErrorCount = $errorTotal
            HasErrors  = $hasErrors
        }
    }
    return $results
}

# Helper function for progress bar
function Get-ProgressBar {
    param(
        [double]$Percent,
        [int]$Width = 40
    )
    $filled = [math]::Floor($Percent / 100 * $Width)
    $empty = $Width - $filled
    $bar = "[" + ("█" * $filled) + ("░" * $empty) + "]"
    return $bar
}
#endregion
