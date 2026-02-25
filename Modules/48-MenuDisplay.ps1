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
    Write-OutputColor "  ║$(("     $($script:ToolFullName.ToUpper()) v" + $script:ScriptVersion).PadRight(72))║" -color "Info"
    Write-OutputColor "  ║$(' '.PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Quick Health Dashboard
    $dashHost = $env:COMPUTERNAME
    $dashOS = Get-CachedValue -Key "DashOS" -FetchScript {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $caption = $os.Caption -replace 'Microsoft ', ''
            $uptime = (Get-Date) - $os.LastBootUpTime
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
            $cpuMeasure = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Measure-Object -Property LoadPercentage -Average
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

    # Build dashboard lines
    $cpuColor = if ($dashCPU -lt 70) { "Success" } elseif ($dashCPU -lt 90) { "Warning" } else { "Error" }
    $memColor = if ($dashOS.MemPct -lt 70) { "Success" } elseif ($dashOS.MemPct -lt 90) { "Warning" } else { "Error" }
    $diskColor = if ($dashDisk.UsedPct -lt 75) { "Success" } elseif ($dashDisk.UsedPct -lt 90) { "Warning" } else { "Error" }

    $worstColor = if ($dashCPU -ge 90 -or $dashOS.MemPct -ge 90 -or $dashDisk.UsedPct -ge 90) { "Error" }
                  elseif ($dashCPU -ge 70 -or $dashOS.MemPct -ge 70 -or $dashDisk.UsedPct -ge 75) { "Warning" }
                  else { "Success" }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-MenuItem "$dashHost" -Status $dashOS.Caption -StatusColor "Info" -Color "Info"
    Write-MenuItem "Up: $($dashOS.Uptime)" -Status "CPU: $dashCPU%  RAM: $($dashOS.MemPct)%  C: $($dashDisk.FreeGB)GB free" -StatusColor $worstColor -Color "Info"
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
    $windowsRebootPending = Test-RebootPending
    if ($global:RebootNeeded -or $windowsRebootPending) {
        $statusParts += "REBOOT PENDING"
    }
    if ($script:SessionChanges.Count -gt 0) {
        $statusParts += "$($script:SessionChanges.Count) change(s)"
    }
    $statusParts += "Theme: $($script:ColorTheme)"

    Write-OutputColor "  $($statusParts -join '  |  ')" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to display the Configure Server menu (reorganized with submenus)
function Show-ConfigureServerMenu {
    Clear-Host

    # Get quick status info for display
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

    # Compute summary counts for submenu status (exclude agent if not configured)
    $roleItems = @($hypervStatus, $mpioStatus, $clusterStatus)
    if ($agentConfigured) { $roleItems += $agentStatus }
    $rolesOK = @(@($roleItems) | Where-Object { $_ -eq "Installed" })
    $rolesTotal = if ($agentConfigured) { 4 } else { 3 }
    $rolesSummary = "$($rolesOK.Count)/$rolesTotal Installed"
    $rolesColor = if ($rolesOK.Count -eq $rolesTotal) { "Success" } elseif ($rolesOK.Count -ge 2) { "Info" } else { "Warning" }

    $rdpQuick = Get-CachedValue -Key "RDPState" -FetchScript { Get-RDPState }
    $winrmQuick = Get-CachedValue -Key "WinRMState" -FetchScript { Get-WinRMState }
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
    Write-MenuItem "[2]  System Configuration â–º" -Status $sysSummary -StatusColor $sysColor
    Write-OutputColor "  │$("        Hostname, Domain, DCPromo, Timezone, Updates, License".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-MenuItem "[3]  Roles & Features ►" -Status $rolesSummary -StatusColor $rolesColor
    Write-OutputColor "  │$(("        Hyper-V, MPIO, Failover Clustering, $($script:AgentInstaller.ToolName)").PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-MenuItem "[4]  Security & Access ►" -Status $secSummary -StatusColor $secColor
    Write-OutputColor "  │$("        RDP, WinRM, Firewall, Admin Accounts, Defender".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  TOOLS & MONITORING".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[5]  Tools & Utilities ►"
    Write-OutputColor "  │$("        NTP, Disk Cleanup, Performance, Events, Services".PadRight(72))│" -color "Info"
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
    Write-OutputColor "  │$(("        Guided: Hostname, Domain, $($script:AgentInstaller.ToolName), RDP, Power, License").PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-MenuItem "[8]  System Health Check"
    Write-MenuItem "[9]  Test Network Connectivity"
    Write-MenuItem "[10] Performance Dashboard"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  [B] ◄ Back to Main Menu" -color "Info"
    Write-OutputColor "" -color "Info"

    # Check both our flag AND Windows pending reboot
    $windowsRebootPending = Test-RebootPending
    if ($global:RebootNeeded -or $windowsRebootPending) {
        if ($windowsRebootPending -and -not $global:RebootNeeded) {
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

    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $hostdisplay = if ($computerSystem) { $computerSystem.Name } else { $env:COMPUTERNAME }
    $domaindisplay = if ($computerSystem) { $computerSystem.Domain } else { "Unknown" }
    $tzObj = Get-TimeZone -ErrorAction SilentlyContinue
    $timezonedisplay = if ($tzObj) { $tzObj.Id } else { "Unknown" }
    $powerPlan = Get-CachedValue -Key "PowerPlan" -FetchScript { (Get-CurrentPowerPlan).Name }
    $powerColor = if ($powerPlan -match "High") { "Success" } else { "Warning" }

    if ($hostdisplay.Length -gt 30) { $hostdisplay = $hostdisplay.Substring(0,27) + "..." }
    if ($domaindisplay.Length -gt 30) { $domaindisplay = $domaindisplay.Substring(0,27) + "..." }
    if ($timezonedisplay.Length -gt 30) { $timezonedisplay = $timezonedisplay.Substring(0,27) + "..." }
    if ($powerPlan.Length -gt 30) { $powerPlan = $powerPlan.Substring(0,27) + "..." }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                         SYSTEM CONFIGURATION").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-MenuItem "[1]  Set Hostname" -Status $hostdisplay -StatusColor "Info"
    Write-MenuItem "[2]  Join a Domain" -Status $domaindisplay -StatusColor "Info"
    Write-MenuItem "[3]  Promote to Domain Controller ►"
    Write-MenuItem "[4]  Set Timezone" -Status $timezonedisplay -StatusColor "Info"
    Write-MenuItem "[5]  Install Windows Updates"
    $licStatus = Get-CachedValue -Key "LicenseActivated" -FetchScript {
        if (Test-WindowsActivated) { "Activated" } else { "Not Activated" }
    }
    $licColor = if ($licStatus -eq "Activated") { "Success" } else { "Warning" }
    Write-MenuItem "[6]  License Server" -Status $licStatus -StatusColor $licColor
    Write-MenuItem "[7]  Set Power Plan" -Status $powerPlan -StatusColor $powerColor
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
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
    $adminDisplay = if ($adminEnabled -eq $true -or $adminEnabled -eq "True") { "Enabled" } else { "Disabled" }
    $adminColor = if ($adminDisplay -eq "Disabled") { "Success" } else { "Warning" }
    $fwColor = if ($firewallStates.Domain -eq "Disabled" -and $firewallStates.Private -eq "Disabled" -and $firewallStates.Public -eq "Enabled") { "Success" } else { "Warning" }
    $fwDisplay = "D:$($firewallStates.Domain) Pr:$($firewallStates.Private) Pu:$($firewallStates.Public)"

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
    Write-MenuItem "[5]  Defender Exclusions"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  ADMIN ACCOUNTS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[6]  Add Local Admin Account"
    Write-MenuItem "[7]  Disable Built-in Admin" -Status $adminDisplay -StatusColor $adminColor
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

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                          TOOLS & UTILITIES").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SYSTEM TOOLS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[1]  NTP Configuration"
    Write-MenuItem "[2]  Disk Cleanup"
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
    Write-MenuItem "[11] Windows Server Backup"
    Write-MenuItem "[12] Certificate Management ►"
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
    Write-MenuItem "[3]  Data Deduplication"
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

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       NETWORK CONFIGURATION").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
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

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     HOST NETWORK CONFIGURATION").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
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

    # Get current switch summary
    $switches = @(Get-VMSwitch -ErrorAction SilentlyContinue)
    $switchSummary = "$($switches.Count) switch(es)"

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
                    $ipAddress  = $ipConfig.IPv4Address.IPAddress
                    $prefix     = $ipConfig.IPv4Address.PrefixLength
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

    $statusColor = if ($adapterStatus -eq "Up") { "Success" } else { "Warning" }
    $dhcpColor   = if ($dhcpEnabled   -eq "Static") { "Success" } else { "Info" }

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