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
                CPU = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
                OS  = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
            }
        } -TimeoutSeconds 10 -Activity "Refreshing metrics"

        if ($cimResult.TimedOut) {
            Write-OutputColor "  WMI/CIM query timed out. Press [R] to retry." -color "Warning"
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
            $clipLines += "Network:"
            foreach ($adapter in $adapters) {
                $clipLines += "  $($adapter.Name) - $($adapter.LinkSpeed)"
            }
            $clipLines += ""
            $clipLines += "Top Processes (by CPU):"
            foreach ($proc in $topProcs) {
                $pCpu = if ($null -ne $proc.CPU) { [math]::Round($proc.CPU, 1) } else { 0 }
                $pMem = [math]::Round($proc.WorkingSet64 / 1MB, 0)
                $clipLines += "  $($proc.ProcessName) (PID $($proc.Id)) - CPU: ${pCpu}s - Mem: $pMem MB"
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
