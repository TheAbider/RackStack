#region ===== PERFORMANCE DASHBOARD =====
# Function to show real-time performance metrics
function Show-PerformanceDashboard {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                      PERFORMANCE DASHBOARD").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # CPU
    $cpu = Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average
    $cpuAvg = [math]::Round($cpu.Average, 1)
    $cpuColor = if ($cpuAvg -lt 70) { "Success" } elseif ($cpuAvg -lt 90) { "Warning" } else { "Error" }
    $cpuBar = Get-ProgressBar -Percent $cpuAvg -Width 40

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CPU USAGE".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  $cpuBar $cpuAvg%".PadRight(72))│" -color $cpuColor
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Memory
    $os = Get-CimInstance Win32_OperatingSystem
    $totalMem = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $freeMem = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $usedMem = $totalMem - $freeMem
    $memPercent = [math]::Round(($usedMem / $totalMem) * 100, 1)
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

    $volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq "Fixed" }
    foreach ($vol in $volumes) {
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

    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 5
    foreach ($adapter in $adapters) {
        $speed = if ($adapter.LinkSpeed) { $adapter.LinkSpeed } else { "Unknown" }
        $name = if ($adapter.Name.Length -gt 30) { $adapter.Name.Substring(0,27) + "..." } else { $adapter.Name }
        Write-OutputColor "  │$("  $name - $speed".PadRight(72))│" -color "Success"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Uptime (reuse $os from memory section above)
    $bootTime = $os.LastBootUpTime
    $uptime = (Get-Date) - $bootTime
    $uptimeStr = "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SYSTEM INFO".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Uptime: $uptimeStr".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Last Boot: $($bootTime.ToString('yyyy-MM-dd HH:mm:ss'))".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    Write-PressEnter
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