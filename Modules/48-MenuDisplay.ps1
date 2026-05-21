#region ===== MENU DISPLAY FUNCTIONS =====
# Function to display the main menu
function Show-MainMenu {
    # Retry update check if initial attempt failed (e.g., no network at startup)
    if (-not $script:UpdateCheckCompleted) {
        Test-StartupUpdateCheck
        # Auto-update on deferred check (network came up after startup)
        if ($script:AutoUpdate -and $script:UpdateAvailable -and $script:LatestRelease) {
            Write-OutputColor "  Auto-update enabled. Installing v$($script:LatestVersion)..." -color "Info"
            try {
                Install-ScriptUpdate -Release $script:LatestRelease -Auto
            }
            catch {
                Write-OutputColor "  Auto-update failed: $($_.Exception.Message)" -color "Warning"
            }
        }
    }

    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(' '.PadRight(72))║" -color "Info"
    $mainTitle = "     $($script:ToolFullName.ToUpper()) v" + $script:ScriptVersion
    if ($mainTitle.Length -gt 72) { $mainTitle = $mainTitle.Substring(0, 69) + "..." }
    Write-OutputColor "  ║$($mainTitle.PadRight(72))║" -color "Info"
    Write-OutputColor "  ║$(' '.PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Quick Health Dashboard
    $dashHost = $env:COMPUTERNAME
    if ($dashHost.Length -gt 15) { $dashHost = $dashHost.Substring(0, 12) + "..." }

    # Configurable dashboard thresholds (defaults: 70% warning, 90% critical)
    $warningThreshold = if ($null -ne $script:DashboardWarningPercent) { $script:DashboardWarningPercent } else { 70 }
    $criticalThreshold = if ($null -ne $script:DashboardCriticalPercent) { $script:DashboardCriticalPercent } else { 90 }

    $dashOS = Get-CachedValue -Key "DashOS" -FetchScript {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec 8 -ErrorAction SilentlyContinue
        if ($os) {
            $caption = $os.Caption -replace 'Microsoft ', ''
            $uptime = [DateTime]::UtcNow - $os.LastBootUpTime.ToUniversalTime()
            @{
                Caption = $caption
                Uptime  = "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"
                MemPct  = if ($os.TotalVisibleMemorySize -gt 0) { [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100) } else { 0 }
                TotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
            }
        } else { @{ Caption = "Unknown"; Uptime = "?"; MemPct = 0; TotalGB = 0 } }
    } -CacheSeconds 60

    $dashCPU = Get-CachedValue -Key "DashCPU" -FetchScript {
        try {
            $cpuMeasure = Get-CimInstance Win32_Processor -OperationTimeoutSec 8 -ErrorAction SilentlyContinue | Measure-Object -Property LoadPercentage -Average
            if ($null -ne $cpuMeasure.Average) { [math]::Round($cpuMeasure.Average) } else { 0 }
        }
        catch { 0 }
    } -CacheSeconds 15

    $dashDisk = Get-CachedValue -Key "DashDisk" -FetchScript {
        $c = Get-Volume -DriveLetter C -ErrorAction SilentlyContinue
        if ($c -and $c.Size -gt 0) {
            @{
                FreeGB  = [math]::Round($c.SizeRemaining / 1GB, 1)
                TotalGB = [math]::Round($c.Size / 1GB, 1)
                UsedPct = [math]::Round((($c.Size - $c.SizeRemaining) / $c.Size) * 100)
            }
        } else { @{ FreeGB = 0; TotalGB = 0; UsedPct = 0 } }
    } -CacheSeconds 60

    # Per-metric color variables were removed in v1.98.9 — they were assigned but never
    # consumed (the box renders the values with $worstColor below, not per-metric).
    # If you want per-metric coloring back, wire them into the Write-MenuItem -StatusColor
    # parameter at the dashboard render site.
    $worstColor = if ($dashCPU -ge $criticalThreshold -or $dashOS.MemPct -ge $criticalThreshold -or $dashDisk.UsedPct -ge $criticalThreshold) { "Error" }
                  elseif ($dashCPU -ge $warningThreshold -or $dashOS.MemPct -ge $warningThreshold -or $dashDisk.UsedPct -ge ($warningThreshold + 5)) { "Warning" }
                  else { "Success" }

    # Session changes indicator
    $changeCount = $script:SessionChanges.Count
    $undoCount = $script:UndoStack.Count
    $sessionLabel = if ($changeCount -gt 0) { "$changeCount change(s)" + $(if ($undoCount -gt 0) { ", $undoCount undoable" } else { "" }) } else { "" }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-MenuItem "$dashHost" -Status $dashOS.Caption -StatusColor "Info" -Color "Info"
    Write-MenuItem "Up: $($dashOS.Uptime)" -Status "CPU: $dashCPU%  RAM: $($dashOS.MemPct)%  C: $($dashDisk.FreeGB)GB free" -StatusColor $worstColor -Color "Info"
    if ($sessionLabel) {
        Write-MenuItem "Session" -Status $sessionLabel -StatusColor "Success" -Color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Box 1: Server Operations
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SERVER OPERATIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[1]  Configure Server"
    Write-MenuItem "[2]  Deploy Virtual Machines"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Box 2: Configuration Profiles
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CONFIGURATION PROFILES".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[3]  Save Configuration Profile"
    Write-MenuItem "[4]  Load Configuration Profile"
    Write-MenuItem "[5]  Export Configuration (Text)"
    Write-MenuItem "[6]  Generate Batch Config Template"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Box 3: System
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SYSTEM".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[7]  Settings"
    Write-MenuItem "[8]  Exit"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Update notification banner
    if ($script:UpdateAvailable -and $script:LatestVersion) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Warning"
        $updateMsg = "  UPDATE AVAILABLE: v$($script:ScriptVersion) -> v$($script:LatestVersion)  [U] to update"
        Write-OutputColor "  │$($updateMsg.PadRight(72))│" -color "Warning"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Warning"
        Write-OutputColor "" -color "Info"
    }

    # Status line
    $statusParts = @()
    $windowsRebootPending = Get-CachedValue -Key "RebootPending" -FetchScript { Test-RebootPending } -CacheSeconds 15
    if ($script:RebootNeeded -or $windowsRebootPending) {
        $statusParts += "REBOOT PENDING"
    }
    if ($script:SessionChanges.Count -gt 0) {
        $statusParts += "$($script:SessionChanges.Count) change(s) [V]iew"
    }
    $sessionDuration = (Get-Date) - $script:ScriptStartTime
    $statusParts += "Session: $($sessionDuration.Hours)h $($sessionDuration.Minutes)m"
    $statusParts += "Theme: $($script:ColorTheme)"

    Write-OutputColor "  $($statusParts -join '  |  ')" -color "Info"
    Write-OutputColor "  [R]efresh dashboard" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to display the Configure Server menu (reorganized with submenus)
function Show-ConfigureServerMenu {
    Clear-Host

    # Get quick status info for display (long cache — these only change when user installs features, which calls Clear-MenuCache)
    $hypervStatus = Get-CachedValue -Key "HyperVInstalled" -FetchScript {
        if (Test-HyperVInstalled) { "Installed" } else { "Not Installed" }
    } -CacheSeconds 300
    $mpioStatus = Get-CachedValue -Key "MPIOInstalled" -FetchScript {
        if (Test-MPIOInstalled) { "Installed" } else { "Not Installed" }
    } -CacheSeconds 300
    $clusterStatus = Get-CachedValue -Key "ClusteringInstalled" -FetchScript {
        if (Test-FailoverClusteringInstalled) { "Installed" } else { "Not Installed" }
    } -CacheSeconds 300
    $agentConfigured = Test-AgentInstallerConfigured
    $agentStatus = if (-not $agentConfigured) { "Not Configured" } else {
        Get-CachedValue -Key "AgentInstalled" -FetchScript {
            $kStatus = Test-AgentInstalled
            if ($kStatus.Installed) { "Installed" } else { "Not Installed" }
        } -CacheSeconds 300
    }

    # Compute summary counts for submenu status (exclude agent if not configured)
    $roleItems = @($hypervStatus, $mpioStatus, $clusterStatus)
    if ($agentConfigured) { $roleItems += $agentStatus }
    $rolesOK = @(@($roleItems) | Where-Object { $_ -eq "Installed" })
    $rolesTotal = if ($agentConfigured) { 4 } else { 3 }
    $rolesSummary = "$($rolesOK.Count)/$rolesTotal Installed"
    $rolesColor = if ($rolesOK.Count -eq $rolesTotal) { "Success" } elseif ($rolesOK.Count -ge 2) { "Info" } else { "Warning" }

    $rdpQuick = Get-CachedValue -Key "RDPState" -FetchScript { Get-RDPState } -CacheSeconds 60
    $winrmQuick = Get-CachedValue -Key "WinRMState" -FetchScript { Get-WinRMState } -CacheSeconds 120
    $secSummary = "RDP: $rdpQuick | WinRM: $winrmQuick"
    $secColor = if ($rdpQuick -eq "Enabled" -and $winrmQuick -match "Enabled|Running") { "Success" } else { "Warning" }

    $powerQuick = Get-CachedValue -Key "PowerPlan" -FetchScript { (Get-CurrentPowerPlan).Name }
    $sysHost = $env:COMPUTERNAME
    if ($sysHost.Length -gt 15) { $sysHost = $sysHost.Substring(0,12) + "..." }
    $sysSummary = "$sysHost | $powerQuick"
    if ($sysSummary.Length -gt 30) { $sysSummary = $sysSummary.Substring(0,27) + "..." }
    $sysColor = if ($powerQuick -match "High") { "Success" } else { "Info" }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                            CONFIGURE SERVER").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CONFIGURATION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[1]  Network Configuration ►"
    Write-OutputColor "  │$("        IP, SET Teaming, Storage/SAN, VLAN".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-MenuItem "[2]  System Configuration ►" -Status $sysSummary -StatusColor $sysColor
    Write-OutputColor "  │$("        Hostname, Domain, DCPromo, Timezone, Updates, License".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-MenuItem "[3]  Roles & Features ►" -Status $rolesSummary -StatusColor $rolesColor
    $rolesDesc = "        Hyper-V, MPIO, Failover Clustering, $($script:AgentInstaller.ToolName)"
    if ($rolesDesc.Length -gt 72) { $rolesDesc = $rolesDesc.Substring(0, 69) + "..." }
    Write-OutputColor "  │$($rolesDesc.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-MenuItem "[4]  Security & Access ►" -Status $secSummary -StatusColor $secColor
    Write-OutputColor "  │$("        RDP, WinRM, Firewall, Admin Accounts, Defender".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  TOOLS & MONITORING".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[5]  Tools & Utilities ►"
    Write-OutputColor "  │$("        NTP, Disk Cleanup, Debloat, Performance, Events, Services".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-MenuItem "[6]  Storage & Clustering ►"
    Write-OutputColor "  │$("        Storage Manager, Cluster, BitLocker, Dedup, Replica".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  OPERATIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[7]  Operations ►"
    Write-OutputColor "  │$("        VM Checkpoints, Export/Import, Cluster Dashboard, Reports".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  QUICK ACTIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[Q]  Quick Setup Wizard"
    $quickDesc = "        Guided: Hostname, Domain, $($script:AgentInstaller.ToolName), RDP, Power, License"
    if ($quickDesc.Length -gt 72) { $quickDesc = $quickDesc.Substring(0, 69) + "..." }
    Write-OutputColor "  │$($quickDesc.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-MenuItem "[8]  System Health Check"
    Write-MenuItem "[9]  Test Network Connectivity"
    Write-MenuItem "[10] Performance Dashboard"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  [B] ◄ Back to Main Menu" -color "Info"
    Write-OutputColor "" -color "Info"

    # Check both our flag AND Windows pending reboot
    $windowsRebootPending = Get-CachedValue -Key "RebootPending" -FetchScript { Test-RebootPending } -CacheSeconds 15
    if ($script:RebootNeeded -or $windowsRebootPending) {
        if ($windowsRebootPending -and -not $script:RebootNeeded) {
            Write-OutputColor "  ⚠ Windows has a pending reboot" -color "Warning"
        }
        else {
            Write-OutputColor "  ⚠ Reboot pending from changes this session" -color "Warning"
        }
        Write-OutputColor "" -color "Info"
    }

    $choice = Read-Host "  Select"
    return $choice
}

# Function to display the System Configuration submenu
function Show-SystemConfigMenu {
    Clear-Host

    $csResult = Get-CachedValue -Key "SysConfigCS" -FetchScript {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec 8 -ErrorAction SilentlyContinue
        if ($cs) { @{ Name = $cs.Name; Domain = $cs.Domain; PartOfDomain = $cs.PartOfDomain } }
        else { @{ Name = $env:COMPUTERNAME; Domain = "Unknown"; PartOfDomain = $false } }
    } -CacheSeconds 30
    $hostdisplay = $csResult.Name
    $domaindisplay = $csResult.Domain
    $isDomainJoined = $csResult.PartOfDomain
    $domainColor = if ($isDomainJoined) { "Success" } else { "Warning" }
    $hostColor = if ($hostdisplay -match '^WIN-|^DESKTOP-') { "Warning" } else { "Success" }
    $timezonedisplay = Get-CachedValue -Key "TimezoneId" -FetchScript {
        $tz = Get-TimeZone -ErrorAction SilentlyContinue
        if ($tz) { $tz.Id } else { "Unknown" }
    } -CacheSeconds 120
    $powerPlan = Get-CachedValue -Key "PowerPlan" -FetchScript { (Get-CurrentPowerPlan).Name } -CacheSeconds 60
    $powerColor = if ($powerPlan -match "High") { "Success" } else { "Warning" }
    $licStatus = Get-CachedValue -Key "LicenseActivated" -FetchScript {
        if (Test-WindowsActivated) { "Activated" } else { "Not Activated" }
    } -CacheSeconds 300
    $licColor = if ($licStatus -eq "Activated") { "Success" } else { "Warning" }

    if ($hostdisplay.Length -gt 15) { $hostdisplay = $hostdisplay.Substring(0, 12) + "..." }
    if ($domaindisplay.Length -gt 30) { $domaindisplay = $domaindisplay.Substring(0,27) + "..." }
    if ($timezonedisplay.Length -gt 30) { $timezonedisplay = $timezonedisplay.Substring(0,27) + "..." }
    if ($powerPlan.Length -gt 30) { $powerPlan = $powerPlan.Substring(0,27) + "..." }

    Write-OutputColor "" -color "Info"
    # Uptime + last boot (cheap — no CIM call; TickCount64 needs .NET 4.8+, fallback to TickCount)
    try { $uptimeMs = [Environment]::TickCount64 }
    catch { $uptimeMs = [math]::Abs([Environment]::TickCount) }
    $uptimeDays = [math]::Floor($uptimeMs / 86400000)
    $uptimeHrs = [math]::Floor(($uptimeMs % 86400000) / 3600000)
    $uptimeStr = if ($uptimeDays -gt 0) { "${uptimeDays}d ${uptimeHrs}h" } else { "${uptimeHrs}h" }
    $lastBoot = (Get-Date).AddMilliseconds(-$uptimeMs).ToString("yyyy-MM-dd HH:mm")

    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                         SYSTEM CONFIGURATION").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "  Uptime: $uptimeStr (booted $lastBoot)" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-MenuItem "[1]  Set Hostname" -Status $hostdisplay -StatusColor $hostColor
    Write-MenuItem "[2]  Join a Domain" -Status $domaindisplay -StatusColor $domainColor
    Write-MenuItem "[3]  Promote to Domain Controller ►"
    Write-MenuItem "[4]  Set Timezone" -Status $timezonedisplay -StatusColor "Info"
    $lastUpdate = Get-CachedValue -Key "LastUpdateDate" -FetchScript {
        try {
            # Fast: check last successful install from Event Log (ID 19 = installed, 20 = failed)
            $evt = Get-WinEvent -LogName 'System' -FilterXPath "*[System[Provider[@Name='Microsoft-Windows-WindowsUpdateClient'] and EventID=19]]" -MaxEvents 1 -ErrorAction SilentlyContinue
            if ($evt) {
                $days = [math]::Floor(((Get-Date) - $evt.TimeCreated).TotalDays)
                if ($days -eq 0) { "Today" } elseif ($days -eq 1) { "Yesterday" } else { "${days}d ago" }
            } else { "" }
        } catch { "" }
    } -CacheSeconds 300
    $updateColor = if ($lastUpdate -match "^\d+d" -and [int]($lastUpdate -replace 'd.*','') -gt 30) { "Warning" } else { "Info" }
    if ($lastUpdate) {
        Write-MenuItem "[5]  Windows Updates ►" -Status "Last: $lastUpdate" -StatusColor $updateColor
    } else {
        Write-MenuItem "[5]  Windows Updates ►"
    }
    Write-MenuItem "[6]  Sync Time"
    Write-MenuItem "[7]  License Server" -Status $licStatus -StatusColor $licColor
    Write-MenuItem "[8]  Set Power Plan" -Status $powerPlan -StatusColor $powerColor
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Pending reboot indicator
    $windowsRebootPending = Get-CachedValue -Key "RebootPending" -FetchScript { Test-RebootPending } -CacheSeconds 30
    if ($script:RebootNeeded -or $windowsRebootPending) {
        Write-OutputColor "  [!] Reboot pending" -color "Warning"
        Write-OutputColor "" -color "Info"
    }

    Write-OutputColor "  [B] ◄ Back to Server Config" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to display the Roles & Features submenu
function Show-RolesFeaturesMenu {
    Clear-Host

    $hypervStatus = Get-CachedValue -Key "HyperVInstalled" -FetchScript {
        if (Test-HyperVInstalled) { "Installed" } else { "Not Installed" }
    }
    $mpioStatus = Get-CachedValue -Key "MPIOInstalled" -FetchScript {
        if (Test-MPIOInstalled) { "Installed" } else { "Not Installed" }
    }
    $clusterStatus = Get-CachedValue -Key "ClusteringInstalled" -FetchScript {
        if (Test-FailoverClusteringInstalled) { "Installed" } else { "Not Installed" }
    }
    $agentConfigured = Test-AgentInstallerConfigured
    $agentStatus = if (-not $agentConfigured) { "Not Configured" } else {
        Get-CachedValue -Key "AgentInstalled" -FetchScript {
            $kStatus = Test-AgentInstalled
            if ($kStatus.Installed) { "Installed" } else { "Not Installed" }
        }
    }

    $hypervColor = if ($hypervStatus -eq "Installed") { "Success" } else { "Warning" }
    $mpioColor = if ($mpioStatus -eq "Installed") { "Success" } else { "Warning" }
    $clusterColor = if ($clusterStatus -eq "Installed") { "Success" } else { "Warning" }
    $agentColor = if ($agentStatus -eq "Installed") { "Success" } elseif ($agentStatus -eq "Not Configured") { "Debug" } else { "Warning" }

    $wsusStatusText = Get-CachedValue -Key "WSUSState" -FetchScript {
        $w = Get-WSUSStatus
        if ($w.PostInstalled) { "Ready" } elseif ($w.RoleInstalled) { "Post-install needed" } else { "Not Installed" }
    } -CacheSeconds 120
    $wsusColor = if ($wsusStatusText -eq "Ready") { "Success" } elseif ($wsusStatusText -eq "Post-install needed") { "Warning" } else { "Warning" }

    $adcsStatusText = Get-CachedValue -Key "ADCSState" -FetchScript {
        $a = Get-ADCSStatus
        if ($a.CAConfigured) { "CA configured" } elseif ($a.RoleInstalled) { "CA config needed" } else { "Not Installed" }
    } -CacheSeconds 120
    $adcsColor = if ($adcsStatusText -eq "CA configured") { "Success" } elseif ($adcsStatusText -eq "CA config needed") { "Warning" } else { "Warning" }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                           ROLES & FEATURES").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-MenuItem "[1]  Install Hyper-V" -Status $hypervStatus -StatusColor $hypervColor
    Write-MenuItem "[2]  Install MPIO" -Status $mpioStatus -StatusColor $mpioColor
    Write-MenuItem "[3]  Install Failover Clustering" -Status $clusterStatus -StatusColor $clusterColor
    Write-MenuItem "[4]  Install $($script:AgentInstaller.ToolName) Agent" -Status $agentStatus -StatusColor $agentColor
    Write-MenuItem "[5]  WSUS Update Server ►" -Status $wsusStatusText -StatusColor $wsusColor
    Write-MenuItem "[6]  Certificate Services (AD CS) ►" -Status $adcsStatusText -StatusColor $adcsColor
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back to Server Config" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to display the Security & Access submenu
function Show-SecurityAccessMenu {
    Clear-Host

    $rdpState = Get-CachedValue -Key "RDPState" -FetchScript { Get-RDPState }
    $winrmState = Get-CachedValue -Key "WinRMState" -FetchScript { Get-WinRMState }
    $firewallStates = Get-CachedValue -Key "FirewallState" -FetchScript { Get-FirewallState }
    $adminEnabled = Get-CachedValue -Key "AdminEnabled" -FetchScript {
        $adminAccount = Get-LocalUser -Name "Administrator" -ErrorAction SilentlyContinue
        if ($adminAccount) { $adminAccount.Enabled } else { "Unknown" }
    }

    $rdpColor = if ($rdpState -eq "Enabled") { "Success" } else { "Warning" }
    $winrmColor = if ($winrmState -eq "Enabled") { "Success" } else { "Warning" }
    $adminDisplay = if ($adminEnabled -eq $true) { "Enabled" } else { "Disabled" }
    $adminColor = if ($adminDisplay -eq "Disabled") { "Success" } else { "Warning" }
    $fwColor = if ($firewallStates.Domain -eq "Disabled" -and $firewallStates.Private -eq "Disabled" -and $firewallStates.Public -eq "Enabled") { "Success" } else { "Warning" }
    $fwDisplay = "D:$($firewallStates.Domain) Pr:$($firewallStates.Private) Pu:$($firewallStates.Public)"

    $defenderStatus = Get-CachedValue -Key "DefenderRT" -FetchScript {
        try {
            $mp = Get-MpComputerStatus -ErrorAction Stop
            $sigAge = $mp.AntivirusSignatureAge
            $rtLabel = if ($mp.RealTimeProtectionEnabled) { "RT:On" } else { "RT:Off" }
            $sigLabel = if ($null -ne $sigAge) { "Sigs:${sigAge}d" } else { "" }
            if ($sigLabel) { "$rtLabel $sigLabel" } else { $rtLabel }
        } catch { "N/A" }
    } -CacheSeconds 60
    $defenderColor = if ($defenderStatus -match "RT:On" -and $defenderStatus -match "Sigs:[0-2]d") { "Success" }
        elseif ($defenderStatus -match "RT:On") { "Warning" }
        elseif ($defenderStatus -eq "N/A") { "Info" }
        else { "Error" }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                          SECURITY & ACCESS").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  REMOTE ACCESS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[1]  Enable Remote Desktop" -Status $rdpState -StatusColor $rdpColor
    Write-MenuItem "[2]  Enable PowerShell Remoting" -Status $winrmState -StatusColor $winrmColor
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  FIREWALL & DEFENDER".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[3]  Configure Windows Firewall" -Status $fwDisplay -StatusColor $fwColor
    Write-MenuItem "[4]  Firewall Rule Templates"
    Write-MenuItem "[5]  Firewall Rule Search ►"
    Write-MenuItem "[6]  Defender Exclusions" -Status $defenderStatus -StatusColor $defenderColor
    Write-MenuItem "[7]  Defender Status Dashboard" -Status $defenderStatus -StatusColor $defenderColor
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  ADMIN ACCOUNTS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[8]  Add Local Admin Account"
    Write-MenuItem "[9]  Disable Built-in Admin" -Status $adminDisplay -StatusColor $adminColor
    Write-MenuItem "[10] Local Account Audit"
    Write-MenuItem "[11] Generate Strong Password"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back to Server Config" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to display the Tools & Utilities submenu
function Show-ToolsUtilitiesMenu {
    Clear-Host

    # Gather status info for display
    $ntpStatus = Get-CachedValue -Key "NTPSource" -FetchScript {
        # Read time source from W32Time registry first (locale-neutral) — w32tm /query /status
        # localizes the "Source:" label on non-EN MUI, so the English-only Select-String would
        # render "Unknown" on non-EN hosts. Falls back to w32tm only if registry lookup fails.
        try {
            $w32cfg = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' -Name 'NtpServer','Type' -ErrorAction Stop
            if ($w32cfg.Type -eq 'NoSync') {
                return "Local (NoSync)"
            } elseif ($w32cfg.NtpServer) {
                $src = ($w32cfg.NtpServer -split '\s+' | ForEach-Object { ($_ -split ',')[0] } | Where-Object { $_ }) -join ', '
                if ($src.Length -gt 25) { $src = $src.Substring(0, 22) + "..." }
                return $src
            }
        } catch { }
        try {
            $w32tmQuery = w32tm /query /status 2>&1
            $sourceLine = $w32tmQuery | Select-String "Source:"
            if ($null -ne $sourceLine) {
                $splitParts = $sourceLine.ToString().Split(":", 2)
                if ($splitParts.Count -ge 2) {
                    $src = $splitParts[1].Trim()
                    if ($src.Length -gt 25) { $src = $src.Substring(0, 22) + "..." }
                    return $src
                }
            }
            "Unknown"
        } catch { "Unknown" }
    } -CacheSeconds 60
    $ntpColor = if ($ntpStatus -match "Unknown|Free-Running|Local CMOS") { "Warning" } else { "Success" }

    $backupStatus = Get-CachedValue -Key "WSBInstalled" -FetchScript {
        if (Test-WindowsServer) {
            $feat = Get-WindowsFeature -Name Windows-Server-Backup -ErrorAction SilentlyContinue
            if ($feat -and $feat.InstallState -eq "Installed") { "Installed" } else { "Not Installed" }
        } else { "N/A" }
    } -CacheSeconds 300
    $backupColor = if ($backupStatus -eq "Installed") { "Success" } elseif ($backupStatus -eq "N/A") { "Info" } else { "Warning" }

    $arcStatus = Get-CachedValue -Key "AzureArcState" -FetchScript {
        $s = Get-AzureArcStatus
        if ($s.Connected) { "Connected" }
        elseif ($s.AgentInstalled) { "Agent only" }
        else { "Not onboarded" }
    } -CacheSeconds 120
    $arcColor = if ($arcStatus -eq "Connected") { "Success" } elseif ($arcStatus -eq "Agent only") { "Warning" } else { "Info" }

    $mdeStatus = Get-CachedValue -Key "DefenderEndpointState" -FetchScript {
        $m = Get-DefenderEndpointStatus
        if ($m.Onboarded) { "Onboarded" } else { "Not onboarded" }
    } -CacheSeconds 120
    $mdeColor = if ($mdeStatus -eq "Onboarded") { "Success" } else { "Info" }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                          TOOLS & UTILITIES").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SYSTEM TOOLS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[1]  NTP Configuration" -Status $ntpStatus -StatusColor $ntpColor
    Write-MenuItem "[2]  Disk Cleanup"
    Write-MenuItem "[14] System Debloat / Optimization ►"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  MONITORING".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[3]  Performance Dashboard"
    Write-MenuItem "[4]  Event Log Viewer"
    Write-MenuItem "[5]  Service Manager"
    Write-MenuItem "[6]  Network Diagnostics ►"

    Write-MenuItem "[7]  Server Readiness"
    Write-MenuItem "[8]  Install Server Role Template ►"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SERVER FEATURES".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[9]  Pagefile Configuration"
    Write-MenuItem "[10] SNMP Configuration"
    Write-MenuItem "[11] Windows Server Backup" -Status $backupStatus -StatusColor $backupColor
    Write-MenuItem "[12] Certificate Management ►"
    Write-MenuItem "[13] Scheduled Task Manager ►"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CLOUD & SECURITY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[15] Azure Arc Onboarding ►" -Status $arcStatus -StatusColor $arcColor
    Write-MenuItem "[16] Defender for Endpoint ►" -Status $mdeStatus -StatusColor $mdeColor
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back to Server Config" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to display the Storage & Clustering submenu
function Show-StorageClusteringMenu {
    Clear-Host

    $clusterStatus = Get-CachedValue -Key "ClusteringInstalled" -FetchScript {
        if (Test-FailoverClusteringInstalled) { "Installed" } else { "Not Installed" }
    }
    $clusterColor = if ($clusterStatus -eq "Installed") { "Success" } else { "Warning" }

    $dedupStatus = Get-CachedValue -Key "DedupInstalled" -FetchScript {
        if (Test-WindowsServer) {
            $feat = Get-WindowsFeature -Name FS-Data-Deduplication -ErrorAction SilentlyContinue
            if ($feat -and $feat.InstallState -eq "Installed") { "Installed" } else { "Not Installed" }
        } else { "N/A" }
    } -CacheSeconds 300
    $dedupColor = if ($dedupStatus -eq "Installed") { "Success" } elseif ($dedupStatus -eq "N/A") { "Info" } else { "Warning" }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                        STORAGE & CLUSTERING").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  STORAGE".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[1]  Storage Manager ►"
    Write-MenuItem "[2]  BitLocker Management"
    Write-MenuItem "[3]  Data Deduplication" -Status $dedupStatus -StatusColor $dedupColor
    Write-MenuItem "[4]  Storage Replica"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CLUSTER & REPLICATION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[5]  Cluster Management ►" -Status $clusterStatus -StatusColor $clusterColor
    Write-MenuItem "[6]  Hyper-V Replica Management ►"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back to Server Config" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to display the network configuration menu (Host vs VM choice)
function Show-NetworkMenu {
    Clear-Host

    # Quick primary IP status (cached)
    $primaryIP = Get-CachedValue -Key "PrimaryIP" -FetchScript {
        $adapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
        if ($null -ne $adapter) {
            $ip = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1
            if ($null -ne $ip) {
                $origin = if ($ip.PrefixOrigin -eq 'Dhcp') { "DHCP" } else { "Static" }
                @{ IP = "$($ip.IPAddress)/$($ip.PrefixLength)"; Origin = $origin; Adapter = $adapter.Name }
            } else { @{ IP = "No IP"; Origin = ""; Adapter = $adapter.Name } }
        } else { @{ IP = "No adapters up"; Origin = ""; Adapter = "" } }
    } -CacheSeconds 15
    $ipColor = if ($primaryIP.Origin -eq "Static") { "Success" } elseif ($primaryIP.Origin -eq "DHCP") { "Warning" } else { "Error" }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       NETWORK CONFIGURATION").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    $ipLabel = if ($primaryIP.Origin) { "$($primaryIP.IP) ($($primaryIP.Origin))" } else { $primaryIP.IP }
    Write-OutputColor "  Primary: $ipLabel" -color $ipColor
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-MenuItem "[1]  Configure Host Network"
    Write-OutputColor "  │$("        Physical adapters, SET teaming, SAN/storage".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-MenuItem "[2]  Configure Virtual Machine Network"
    Write-OutputColor "  │$("        VM IP configuration, DNS settings".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  [B] ◄ Back to Server Config" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to display the host network configuration menu
function Show-HostNetworkMenu {
    Clear-Host

    # Quick adapter summary (cached)
    $adapterSummary = Get-CachedValue -Key "AdapterSummary" -FetchScript {
        $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue)
        $up = @($adapters | Where-Object { $_.Status -eq "Up" }).Count
        $down = @($adapters | Where-Object { $_.Status -ne "Up" }).Count
        @{ Up = $up; Down = $down; Total = $adapters.Count }
    } -CacheSeconds 15
    $adapterLabel = "$($adapterSummary.Up) up"
    if ($adapterSummary.Down -gt 0) { $adapterLabel += ", $($adapterSummary.Down) down" }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     HOST NETWORK CONFIGURATION").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "  Adapters: $adapterLabel" -color $(if ($adapterSummary.Down -gt 0) { "Warning" } else { "Info" })
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-MenuItem "[1]  Virtual Switch Management ►"
    Write-OutputColor "  │$("        Create, view, or remove virtual switches (SET/External/etc)".PadRight(72))│" -color "Info"
    Write-MenuItem "[2]  Add Virtual NIC to Switch"
    Write-MenuItem "[3]  Configure IP Address"
    Write-MenuItem "[4]  Storage & SAN Management ►"
    Write-MenuItem "[5]  Rename Network Adapter"
    Write-MenuItem "[6]  Disable IPv6 (All Adapters)"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back to Networking    [M] ◄◄ Server Config" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to display the Virtual Switch Management submenu
function Show-VirtualSwitchMenu {
    Clear-Host

    # Get current switch summary (cached to avoid slow WMI query on every render)
    $switchCount = Get-CachedValue -Key "VMSwitchCount" -FetchScript {
        @(Get-VMSwitch -ErrorAction SilentlyContinue).Count
    } -CacheSeconds 30
    $switchSummary = "$switchCount switch(es)"

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     VIRTUAL SWITCH MANAGEMENT").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CREATE".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[1]  Create Switch Embedded Team (SET)" -Status "Multi-NIC teaming" -StatusColor "Info"
    Write-MenuItem "[2]  Create External Virtual Switch" -Status "Single NIC" -StatusColor "Info"
    Write-MenuItem "[3]  Create Internal Virtual Switch" -Status "Host-only" -StatusColor "Info"
    Write-MenuItem "[4]  Create Private Virtual Switch" -Status "Isolated" -StatusColor "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  MANAGE".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[5]  Show Virtual Switches" -Status $switchSummary -StatusColor "Info"
    Write-MenuItem "[6]  Remove Virtual Switch"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back to Host Network" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Helper function to display a CURRENT ADAPTER info box (72-char inner width)
# Used by Show-Host-IPNetworkMenu and Show-VM-NetworkMenu to avoid duplicated code.
function Show-AdapterInfoBox {
    param (
        [string]$AdapterName
    )

    $ipAddress    = "Not configured"
    $subnetMask   = ""
    $gateway      = "Not set"
    $dnsServers   = "Not set"
    $dhcpEnabled  = "Unknown"
    $adapterStatus = "Unknown"

    if ($AdapterName) {
        $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue
        if ($adapter) {
            $adapterStatus = $adapter.Status
            $ipConfig = Get-NetIPConfiguration -InterfaceAlias $AdapterName -ErrorAction SilentlyContinue
            if ($ipConfig) {
                if ($ipConfig.IPv4Address) {
                    $primaryIP = $ipConfig.IPv4Address | Select-Object -First 1
                    $ipAddress  = $primaryIP.IPAddress
                    $prefix     = $primaryIP.PrefixLength
                    $subnetMask = "/$prefix"
                }
                if ($ipConfig.IPv4DefaultGateway) {
                    $gateway = $ipConfig.IPv4DefaultGateway.NextHop
                }
                if ($ipConfig.DNSServer) {
                    $dnsServers = ($ipConfig.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | Select-Object -First 2 -ExpandProperty ServerAddresses) -join ", "
                    if (-not $dnsServers) { $dnsServers = "Not set" }
                }
            }
            $dhcpSetting = Get-NetIPInterface -InterfaceAlias $AdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue
            if ($dhcpSetting) {
                $dhcpEnabled = if ($dhcpSetting.Dhcp -eq "Enabled") { "DHCP" } else { "Static" }
            }
        }
    }

    $statusColor = if ($adapterStatus -eq "Up") { "Green" } else { "Yellow" }
    $dhcpColor   = if ($dhcpEnabled   -eq "Static") { "Green" } else { "Cyan" }

    $displayName = if ($AdapterName) { $AdapterName } else { "(none selected)" }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CURRENT ADAPTER".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-Host "  │  Adapter:  " -NoNewline -ForegroundColor Cyan; Write-Host $displayName.PadRight(60) -NoNewline -ForegroundColor Green; Write-Host "│" -ForegroundColor Cyan
    Write-Host "  │  Status:   " -NoNewline -ForegroundColor Cyan; Write-Host $adapterStatus.PadRight(60) -NoNewline -ForegroundColor $statusColor; Write-Host "│" -ForegroundColor Cyan
    Write-Host "  │  Mode:     " -NoNewline -ForegroundColor Cyan; Write-Host $dhcpEnabled.PadRight(60) -NoNewline -ForegroundColor $dhcpColor; Write-Host "│" -ForegroundColor Cyan
    Write-Host "  │  IP:       " -NoNewline -ForegroundColor Cyan; Write-Host "$ipAddress$subnetMask".PadRight(60) -NoNewline -ForegroundColor Cyan; Write-Host "│" -ForegroundColor Cyan
    Write-Host "  │  Gateway:  " -NoNewline -ForegroundColor Cyan; Write-Host $gateway.PadRight(60) -NoNewline -ForegroundColor Cyan; Write-Host "│" -ForegroundColor Cyan
    Write-Host "  │  DNS:      " -NoNewline -ForegroundColor Cyan; Write-Host $dnsServers.PadRight(60) -NoNewline -ForegroundColor Cyan; Write-Host "│" -ForegroundColor Cyan
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

# Function to display the Host IP network configuration menu
function Show-Host-IPNetworkMenu {
    param (
        [string]$selectedAdapterName
    )

    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       HOST IP CONFIGURATION").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Current adapter info box
    Show-AdapterInfoBox -AdapterName $selectedAdapterName
    Write-OutputColor "" -color "Info"

    # Actions box
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  ACTIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[1]  Set IP Address"
    Write-MenuItem "[2]  Set DNS"
    Write-MenuItem "[3]  Set VLAN"
    Write-MenuItem "[4]  Choose Different Adapter"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back to Host Network    [M] ◄◄ Server Config" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to display the VM network configuration menu
function Show-VM-NetworkMenu {
    param (
        [string]$selectedAdapterName
    )

    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                      VIRTUAL MACHINE NETWORK").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Current adapter info box
    Show-AdapterInfoBox -AdapterName $selectedAdapterName
    Write-OutputColor "" -color "Info"

    # Actions box
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  ACTIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[1]  Set IP Address"
    Write-MenuItem "[2]  Set DNS"
    Write-MenuItem "[3]  Disable IPv6 (All Adapters)"
    Write-MenuItem "[4]  Choose Different Adapter"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back to Networking    [M] ◄◄ Server Config" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}
#endregion