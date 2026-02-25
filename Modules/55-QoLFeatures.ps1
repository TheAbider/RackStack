#region ===== QOL FEATURES (v2.8.0) =====
# Initialize QoL directories and files
function Initialize-AppConfigDir {
    if (-not (Test-Path $script:AppConfigDir)) {
        $null = New-Item -Path $script:AppConfigDir -ItemType Directory -Force
    }
}

# Load favorites from file
function Import-Favorites {
    Initialize-AppConfigDir
    if (Test-Path $script:FavoritesPath) {
        try {
            $script:Favorites = Get-Content $script:FavoritesPath -Raw | ConvertFrom-Json
            if (-not $script:Favorites) { $script:Favorites = @() }
        }
        catch {
            $script:Favorites = @()
        }
    }
}

# Save favorites to file
function Export-Favorites {
    Initialize-AppConfigDir
    try {
        $script:Favorites | ConvertTo-Json -Depth 10 | Out-File $script:FavoritesPath -Encoding UTF8 -Force
    }
    catch {
        Write-OutputColor "  Warning: Could not save favorites: $($_.Exception.Message)" -color "Warning"
    }
}

# Dispatch map: maps favorite names to executable function names
$script:FavoriteDispatch = @{
    "Configure SET"              = "New-SwitchEmbeddedTeam"
    "Add Virtual NIC"            = "Add-CustomVNIC"
    "Test iSCSI Cabling"         = "Test-iSCSICabling"
    "Set IP Address"             = "Set-StaticIP"
    "Set DNS"                    = "Set-DNSServers"
    "Set Hostname"               = "Set-Hostname"
    "Join Domain"                = "Join-Domain"
    "Install Hyper-V"            = "Install-HyperVRole"
    "Install MPIO"               = "Install-MPIOFeature"
    "Enable RDP"                 = "Enable-RDP"
    "Enable WinRM"               = "Enable-WinRM"
    "Configure Firewall"         = "Configure-Firewall"
    "Defender Exclusions"        = "Set-DefenderExclusions"
    "Add Local Admin"            = "Add-LocalAdmin"
    "Host Storage Setup"         = "Initialize-HostStorage"
    "iSCSI Configuration"        = "Set-iSCSIConfiguration"
    "Storage Backend Status"      = "Show-StorageBackendStatus"
    "FC Adapters"                 = "Show-FCAdapters"
    "S2D Status"                  = "Show-S2DStatus"
    "Change Storage Backend"      = "Set-StorageBackendType"
    "VM Deployment"              = "Show-VMDeploymentMenu"
    "Pagefile Configuration"     = "Set-PagefileConfiguration"
    "SNMP Configuration"         = "Set-SNMPConfiguration"
    "Performance Dashboard"      = "Show-PerformanceDashboard"
    "Cluster Dashboard"          = "Show-ClusterDashboard"
    "NTP Configuration"          = "Set-NTPConfiguration"
    "Windows Updates"            = "Install-WindowsUpdates"
    "License Server"             = "Show-LicenseMenu"
    "Set Power Plan"             = "Set-PowerPlan"
    "Storage Manager"            = "Show-StorageMenu"
    "BitLocker Management"       = "Show-BitLockerMenu"
    "Certificate Management"     = "Show-CertificateMenu"
    "Network Diagnostics"        = "Show-NetworkDiagnostics"
    "HTML Health Report"         = "Export-HTMLHealthReport"
    "HTML Readiness Report"      = "Export-HTMLReadinessReport"
    "Windows Server Backup"      = "Install-WindowsServerBackup"
    "VHD Management"             = "Show-VHDManagementMenu"
    "Configuration Drift Check"  = "Start-DriftCheck"
}

# Add a favorite
function Add-Favorite {
    param(
        [string]$Name,
        [string]$MenuPath,
        [string]$Description = "",
        [string]$FunctionName = ""
    )

    Import-Favorites

    # Auto-detect function name from dispatch map if not provided
    if (-not $FunctionName -and $script:FavoriteDispatch.ContainsKey($Name)) {
        $FunctionName = $script:FavoriteDispatch[$Name]
    }

    $favorite = @{
        Name = $Name
        MenuPath = $MenuPath
        FunctionName = $FunctionName
        Description = $Description
        AddedDate = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }

    $script:Favorites += $favorite
    Export-Favorites
}

# Function to show favorites menu
function Show-Favorites {
    Import-Favorites

    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                          FAVORITES").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($script:Favorites.Count -eq 0) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  No favorites saved yet.".PadRight(72))│" -color "Warning"
        Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  To add a favorite, use [F] Add Favorite from Settings menu.".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }
    else {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  YOUR FAVORITES".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        $index = 1
        foreach ($fav in $script:Favorites) {
            if ($null -eq $fav.Name) { $fav.Name = "Unknown" }
            if ($null -eq $fav.MenuPath) { $fav.MenuPath = "" }
            $favName = if ($fav.Name.Length -gt 40) { $fav.Name.Substring(0,37) + "..." } else { $fav.Name.PadRight(40) }
            $favPath = if ($fav.MenuPath.Length -gt 25) { $fav.MenuPath.Substring(0,22) + "..." } else { $fav.MenuPath.PadRight(25) }
            Write-OutputColor "  │  [$index]  $favName $favPath│" -color "Success"
            $index++
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [A] Add Favorite    [D] Delete Favorite    [C] Clear All" -color "Info"
    Write-OutputColor "  [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    switch -Regex ($choice) {
        '^[Aa]$' {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Enter favorite name:" -color "Info"
            $name = Read-Host "  "
            if ([string]::IsNullOrWhiteSpace($name)) { return }

            Write-OutputColor "  Enter menu path (e.g., 'Configure Server > Network > SET'):" -color "Info"
            $path = Read-Host "  "
            if ([string]::IsNullOrWhiteSpace($path)) { return }

            Add-Favorite -Name $name -MenuPath $path
            Write-OutputColor "  Favorite added!" -color "Success"
            Start-Sleep -Seconds 1
        }
        '^[Dd]$' {
            if ($script:Favorites.Count -eq 0) { return }
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Enter number to delete:" -color "Info"
            $delNum = Read-Host "  "
            if ($delNum -notmatch '^\d+$') { return }
            $delIndex = [int]$delNum - 1
            if ($delIndex -ge 0 -and $delIndex -lt $script:Favorites.Count) {
                $tempFavorites = @()
                for ($i = 0; $i -lt $script:Favorites.Count; $i++) {
                    if ($i -ne $delIndex) { $tempFavorites += $script:Favorites[$i] }
                }
                $script:Favorites = $tempFavorites
                Export-Favorites
                Write-OutputColor "  Favorite deleted." -color "Success"
                Start-Sleep -Seconds 1
            }
        }
        '^[Cc]$' {
            if (Confirm-UserAction -Message "Clear all favorites?") {
                $script:Favorites = @()
                Export-Favorites
                Write-OutputColor "  All favorites cleared." -color "Success"
                Start-Sleep -Seconds 1
            }
        }
        '^[Bb]$' { return }
        '^\d+$' {
            $favIndex = [int]$choice - 1
            if ($favIndex -ge 0 -and $favIndex -lt $script:Favorites.Count) {
                $selectedFav = $script:Favorites[$favIndex]
                $funcName = $selectedFav.FunctionName
                if ($funcName -and (Get-Command $funcName -ErrorAction SilentlyContinue)) {
                    & $funcName
                } else {
                    Write-OutputColor "  Navigate to: $($selectedFav.MenuPath)" -color "Info"
                    Write-PressEnter
                }
            } else {
                Write-OutputColor "  Invalid selection." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Record a command in the history
function Add-CommandHistory {
    param(
        [string]$Command,
        [string]$Category = "General"
    )
    if ([string]::IsNullOrWhiteSpace($Command)) { return }
    $script:CommandHistory += @{
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Command   = $Command
        Category  = $Category
    }
    # Auto-export periodically (every 10 entries)
    if ($script:CommandHistory.Count % 10 -eq 0) {
        Export-CommandHistory
    }
}

# Load command history from file
function Import-CommandHistory {
    Initialize-AppConfigDir
    if (Test-Path $script:HistoryPath) {
        try {
            $script:CommandHistory = Get-Content $script:HistoryPath -Raw | ConvertFrom-Json
            if (-not $script:CommandHistory) { $script:CommandHistory = @() }
        }
        catch {
            $script:CommandHistory = @()
        }
    }
}

# Save command history to file
function Export-CommandHistory {
    Initialize-AppConfigDir
    try {
        # Keep only last MaxHistoryItems
        if ($script:CommandHistory.Count -gt $script:MaxHistoryItems) {
            $script:CommandHistory = $script:CommandHistory | Select-Object -Last $script:MaxHistoryItems
        }
        $script:CommandHistory | ConvertTo-Json -Depth 10 | Out-File $script:HistoryPath -Encoding UTF8 -Force
    }
    catch {
        Write-OutputColor "  Warning: Could not save command history: $($_.Exception.Message)" -color "Warning"
    }
}

# Function to show command history
function Show-CommandHistory {
    Import-CommandHistory

    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       COMMAND HISTORY").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($script:CommandHistory.Count -eq 0) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  No command history yet.".PadRight(72))│" -color "Warning"
        Write-OutputColor "  │$("  History is recorded as you use the tool.".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }
    else {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  RECENT COMMANDS (last 20)".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        # Show last 20
        $recentHistory = $script:CommandHistory | Select-Object -Last 20
        $index = 1
        foreach ($cmd in $recentHistory) {
            $cmdStr = if ($cmd.Command.Length -gt 40) { $cmd.Command.Substring(0,37) + "..." } else { $cmd.Command.PadRight(40) }
            $timeStr = if ($cmd.Timestamp -and $cmd.Timestamp.Length -ge 16) { $cmd.Timestamp.Substring(5,11) } else { "           " }
            Write-OutputColor "  │  [$($index.ToString().PadLeft(2))] $cmdStr $timeStr│" -color "Info"
            $index++
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Total history entries: $($script:CommandHistory.Count)" -color "Info"
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [C] Clear History    [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    switch ("$choice".ToUpper()) {
        "C" {
            if (Confirm-UserAction -Message "Clear all command history?") {
                $script:CommandHistory = @()
                Export-CommandHistory
                Write-OutputColor "  History cleared." -color "Success"
                Start-Sleep -Seconds 1
            }
        }
        "B" { return }
    }
}

# Save session state for resume
function Save-SessionState {
    Initialize-AppConfigDir

    $sessionState = @{
        SavedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        VMDeploymentQueue = $script:VMDeploymentQueue
        SelectedHostDrive = $script:SelectedHostDrive
        StorageInitialized = $script:StorageInitialized
        SessionChanges = $script:SessionChanges
        ColorTheme = $script:ColorTheme
    }

    try {
        $sessionState | ConvertTo-Json -Depth 10 | Out-File $script:SessionStatePath -Encoding UTF8 -Force
    }
    catch {
        Write-OutputColor "  Warning: Could not save session state: $($_.Exception.Message)" -color "Warning"
    }
}

# Restore session state
function Restore-SessionState {
    if (-not (Test-Path $script:SessionStatePath)) { return $false }

    try {
        $sessionState = Get-Content $script:SessionStatePath -Raw | ConvertFrom-Json

        # Check if session is recent (within 24 hours)
        $savedTime = [datetime]::ParseExact($sessionState.SavedAt, "yyyy-MM-dd HH:mm:ss", $null)
        $hoursSinceSave = ((Get-Date) - $savedTime).TotalHours

        if ($hoursSinceSave -gt 24) {
            # Session too old, delete it
            Remove-Item $script:SessionStatePath -Force -ErrorAction SilentlyContinue
            return $false
        }

        # Check if there's anything worth restoring
        $queueCount = if ($sessionState.VMDeploymentQueue) { $sessionState.VMDeploymentQueue.Count } else { 0 }
        $changesCount = if ($sessionState.SessionChanges) { $sessionState.SessionChanges.Count } else { 0 }

        if ($queueCount -eq 0 -and $changesCount -eq 0) {
            Remove-Item $script:SessionStatePath -Force -ErrorAction SilentlyContinue
            return $false
        }

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  PREVIOUS SESSION FOUND".PadRight(72))│" -color "Warning"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  Saved: $($sessionState.SavedAt)".PadRight(72))│" -color "Info"
        if ($queueCount -gt 0) {
            Write-OutputColor "  │$("  VM Deployment Queue: $queueCount VM(s) pending".PadRight(72))│" -color "Success"
        }
        if ($changesCount -gt 0) {
            Write-OutputColor "  │$("  Session Changes: $changesCount change(s) recorded".PadRight(72))│" -color "Info"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        if (Confirm-UserAction -Message "Restore previous session?") {
            if ($sessionState.VMDeploymentQueue) {
                $script:VMDeploymentQueue = @($sessionState.VMDeploymentQueue)
            }
            if ($sessionState.SelectedHostDrive) {
                $script:SelectedHostDrive = $sessionState.SelectedHostDrive
            }
            if ($sessionState.StorageInitialized) {
                $script:StorageInitialized = $sessionState.StorageInitialized
            }
            if ($sessionState.ColorTheme) {
                $script:ColorTheme = $sessionState.ColorTheme
            }

            Write-OutputColor "  Session restored!" -color "Success"
            Start-Sleep -Seconds 1

            # Clear the saved session
            Remove-Item $script:SessionStatePath -Force -ErrorAction SilentlyContinue
            return $true
        }
        else {
            # User declined, clear the session
            Remove-Item $script:SessionStatePath -Force -ErrorAction SilentlyContinue
            return $false
        }
    }
    catch {
        Remove-Item $script:SessionStatePath -Force -ErrorAction SilentlyContinue
        return $false
    }
}

# Configure pagefile settings (system managed, custom size, or move to different drive)
function Set-PagefileConfiguration {
    # --- Section: Main Configuration Loop ---
    while ($true) {
        Clear-Host

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                      PAGEFILE CONFIGURATION").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        # --- Section: Retrieve Current Pagefile Status ---
        # Read current pagefile settings
        $pagefileSettings = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue
        $pagefileUsage = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue
        $compSys = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        $autoManaged = if ($null -ne $compSys) { $compSys.AutomaticManagedPagefile } else { $false }

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  CURRENT PAGEFILE STATUS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        if ($autoManaged) {
            Write-OutputColor "  │$("  Mode:       System Managed (Automatic)".PadRight(72))│" -color "Success"
        }
        else {
            Write-OutputColor "  │$("  Mode:       Custom / Manual".PadRight(72))│" -color "Info"
        }

        if ($null -ne $pagefileUsage) {
            foreach ($pf in $pagefileUsage) {
                $pfPath = "$($pf.Name)"
                $pfAllocated = "$($pf.AllocatedBaseSize) MB"
                $pfCurrent = "$($pf.CurrentUsage) MB"
                $pfPeak = "$($pf.PeakUsage) MB"
                Write-OutputColor "  │$("  Location:   $pfPath".PadRight(72))│" -color "Info"
                Write-OutputColor "  │$("  Allocated:  $pfAllocated".PadRight(72))│" -color "Info"
                Write-OutputColor "  │$("  Current:    $pfCurrent".PadRight(72))│" -color "Info"
                Write-OutputColor "  │$("  Peak:       $pfPeak".PadRight(72))│" -color "Info"
            }
        }
        else {
            Write-OutputColor "  │$("  No pagefile information available.".PadRight(72))│" -color "Warning"
        }

        if (-not $autoManaged -and $null -ne $pagefileSettings) {
            foreach ($pfs in $pagefileSettings) {
                $initMB = $pfs.InitialSize
                $maxMB = $pfs.MaximumSize
                if ($initMB -eq 0 -and $maxMB -eq 0) {
                    Write-OutputColor "  │$("  Size:       System managed on $($pfs.Name)".PadRight(72))│" -color "Info"
                }
                else {
                    Write-OutputColor "  │$("  Initial:    $initMB MB  /  Maximum: $maxMB MB".PadRight(72))│" -color "Info"
                }
            }
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        # --- Section: Display Menu Options ---
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  OPTIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  System Managed (Automatic)"
        Write-MenuItem "[2]  Custom Size"
        Write-MenuItem "[3]  Move to Different Drive"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        # --- Section: Option Dispatch ---
        switch ("$choice".ToUpper()) {
            "1" {
                # Set to system managed
                if ($autoManaged) {
                    Write-OutputColor "  Pagefile is already system managed." -color "Info"
                    Write-PressEnter
                    continue
                }
                if (-not (Confirm-UserAction -Message "Set pagefile to System Managed? (requires reboot)")) { continue }

                try {
                    # Enable automatic managed pagefile
                    $compSysObj = Get-CimInstance Win32_ComputerSystem
                    Set-CimInstance -InputObject $compSysObj -Property @{ AutomaticManagedPagefile = $true } -ErrorAction Stop
                    Write-OutputColor "  Pagefile set to System Managed (Automatic)." -color "Success"
                    Write-OutputColor "  A reboot is required for changes to take effect." -color "Warning"
                    $global:RebootNeeded = $true
                    Add-SessionChange -Category "System" -Description "Set pagefile to System Managed (Automatic)"
                }
                catch {
                    Write-OutputColor "  Failed to set pagefile: $_" -color "Error"
                }
                Write-PressEnter
            }
            "2" {
                # Custom size
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Enter initial size in MB (minimum 1024):" -color "Info"
                $initialInput = Read-Host "  "
                if (-not ($initialInput -match '^\d+$')) {
                    Write-OutputColor "  Invalid input. Must be a number." -color "Error"
                    Write-PressEnter
                    continue
                }
                $initialMB = [int]$initialInput
                if ($initialMB -lt 1024) {
                    Write-OutputColor "  Minimum initial size is 1024 MB." -color "Error"
                    Write-PressEnter
                    continue
                }

                Write-OutputColor "  Enter maximum size in MB (must be >= initial size):" -color "Info"
                $maxInput = Read-Host "  "
                if (-not ($maxInput -match '^\d+$')) {
                    Write-OutputColor "  Invalid input. Must be a number." -color "Error"
                    Write-PressEnter
                    continue
                }
                $maxMB = [int]$maxInput
                if ($maxMB -lt $initialMB) {
                    Write-OutputColor "  Maximum size must be >= initial size ($initialMB MB)." -color "Error"
                    Write-PressEnter
                    continue
                }

                # Validate against available disk space on current pagefile drive
                $currentDrive = "C:"
                if ($null -ne $pagefileUsage -and $pagefileUsage.Count -gt 0) {
                    $pfName = "$($pagefileUsage[0].Name)"
                    if ($pfName -match '^([A-Z]:)') {
                        $currentDrive = $matches[0]
                    }
                }
                $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$currentDrive'" -ErrorAction SilentlyContinue
                if ($null -ne $disk) {
                    $freeSpaceMB = [math]::Floor($disk.FreeSpace / 1MB)
                    if ($maxMB -gt $freeSpaceMB) {
                        Write-OutputColor "  Maximum size ($maxMB MB) exceeds available space on $currentDrive ($freeSpaceMB MB free)." -color "Error"
                        Write-PressEnter
                        continue
                    }
                }

                if (-not (Confirm-UserAction -Message "Set pagefile to ${initialMB}MB - ${maxMB}MB on $currentDrive ? (requires reboot)")) { continue }

                try {
                    # Disable automatic management first
                    $compSysObj = Get-CimInstance Win32_ComputerSystem
                    if ($compSysObj.AutomaticManagedPagefile) {
                        Set-CimInstance -InputObject $compSysObj -Property @{ AutomaticManagedPagefile = $false } -ErrorAction Stop
                    }

                    # Remove existing pagefile settings
                    $existingSettings = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue
                    if ($null -ne $existingSettings) {
                        foreach ($existing in $existingSettings) {
                            Remove-CimInstance -InputObject $existing -ErrorAction SilentlyContinue
                        }
                    }

                    # Create new pagefile setting
                    $pfPath = "$currentDrive\pagefile.sys"
                    $null = New-CimInstance -ClassName Win32_PageFileSetting -Property @{
                        Name = $pfPath
                        InitialSize = $initialMB
                        MaximumSize = $maxMB
                    } -ErrorAction Stop

                    Write-OutputColor "  Pagefile set to ${initialMB}MB - ${maxMB}MB on $currentDrive." -color "Success"
                    Write-OutputColor "  A reboot is required for changes to take effect." -color "Warning"
                    $global:RebootNeeded = $true
                    Add-SessionChange -Category "System" -Description "Set custom pagefile: ${initialMB}MB - ${maxMB}MB on $currentDrive"
                }
                catch {
                    Write-OutputColor "  Failed to configure pagefile: $_" -color "Error"
                }
                Write-PressEnter
            }
            "3" {
                # Move to different drive
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Available drives:" -color "Info"
                Write-OutputColor "" -color "Info"

                $drives = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue)
                if ($drives.Count -eq 0) {
                    Write-OutputColor "  No fixed drives found." -color "Error"
                    Write-PressEnter
                    continue
                }

                $driveIndex = 1
                foreach ($drv in $drives) {
                    $freeGB = [math]::Round($drv.FreeSpace / 1GB, 1)
                    $totalGB = [math]::Round($drv.Size / 1GB, 1)
                    Write-OutputColor "  [$driveIndex] $($drv.DeviceID)  Free: ${freeGB} GB / Total: ${totalGB} GB" -color "Info"
                    $driveIndex++
                }

                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Select target drive number:" -color "Info"
                $driveChoice = Read-Host "  "
                if (-not ($driveChoice -match '^\d+$') -or [int]$driveChoice -lt 1 -or [int]$driveChoice -gt $drives.Count) {
                    Write-OutputColor "  Invalid selection." -color "Error"
                    Write-PressEnter
                    continue
                }

                $targetDrive = $drives[[int]$driveChoice - 1]
                $targetLetter = $targetDrive.DeviceID

                # Check free space (at least 4 GB for pagefile)
                $targetFreeGB = [math]::Round($targetDrive.FreeSpace / 1GB, 1)
                if ($targetFreeGB -lt 4) {
                    Write-OutputColor "  Insufficient free space on $targetLetter (${targetFreeGB} GB). Need at least 4 GB." -color "Error"
                    Write-PressEnter
                    continue
                }

                if (-not (Confirm-UserAction -Message "Move pagefile to $targetLetter ? (requires reboot)")) { continue }

                try {
                    # Disable automatic management
                    $compSysObj = Get-CimInstance Win32_ComputerSystem
                    if ($compSysObj.AutomaticManagedPagefile) {
                        Set-CimInstance -InputObject $compSysObj -Property @{ AutomaticManagedPagefile = $false } -ErrorAction Stop
                    }

                    # Remove existing pagefile settings
                    $existingSettings = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue
                    if ($null -ne $existingSettings) {
                        foreach ($existing in $existingSettings) {
                            Remove-CimInstance -InputObject $existing -ErrorAction SilentlyContinue
                        }
                    }

                    # Create new pagefile on target drive (system managed size: 0/0)
                    $pfPath = "$targetLetter\pagefile.sys"
                    $null = New-CimInstance -ClassName Win32_PageFileSetting -Property @{
                        Name = $pfPath
                        InitialSize = 0
                        MaximumSize = 0
                    } -ErrorAction Stop

                    Write-OutputColor "  Pagefile moved to $targetLetter (system managed size)." -color "Success"
                    Write-OutputColor "  A reboot is required for changes to take effect." -color "Warning"
                    $global:RebootNeeded = $true
                    Add-SessionChange -Category "System" -Description "Moved pagefile to $targetLetter"
                }
                catch {
                    Write-OutputColor "  Failed to move pagefile: $_" -color "Error"
                }
                Write-PressEnter
            }
            "B" { return }
            default {
                Write-OutputColor "  Invalid choice. Please enter 1-3 or B." -color "Error"
                Start-Sleep -Seconds 2
            }
        }
    }
}

# Configure SNMP service (Server OS only)
function Set-SNMPConfiguration {
    # --- Section: OS Validation ---
    if (-not (Test-WindowsServer)) {
        Write-OutputColor "  SNMP configuration requires Windows Server." -color "Warning"
        return
    }

    # --- Section: Main Configuration Loop ---
    while ($true) {
        Clear-Host

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                       SNMP CONFIGURATION").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        # --- Section: Feature Installation Check ---
        # Check if SNMP feature is installed
        $snmpFeature = Get-WindowsFeature -Name "SNMP-Service" -ErrorAction SilentlyContinue
        $snmpInstalled = ($null -ne $snmpFeature -and $snmpFeature.InstallState -eq "Installed")

        if (-not $snmpInstalled) {
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  SNMP Service is not installed.".PadRight(72))│" -color "Warning"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            Write-OutputColor "" -color "Info"

            if (Confirm-UserAction -Message "Install SNMP Service now?") {
                $installResult = Install-WindowsFeatureWithTimeout -FeatureName "SNMP-Service" -DisplayName "SNMP Service" -IncludeManagementTools

                if ($installResult.TimedOut) {
                    Write-OutputColor "  SNMP installation timed out." -color "Error"
                    Add-SessionChange -Category "System" -Description "SNMP Service installation timed out"
                    Write-PressEnter
                    return
                }
                elseif ($installResult.Success) {
                    Write-OutputColor "  SNMP Service installed successfully!" -color "Success"
                    Add-SessionChange -Category "System" -Description "Installed SNMP Service"
                    Clear-MenuCache
                }
                else {
                    Write-OutputColor "  SNMP Service installation failed." -color "Error"
                    Add-SessionChange -Category "System" -Description "SNMP Service installation failed"
                    Write-PressEnter
                    return
                }
            }
            else {
                return
            }
        }

        # --- Section: Configuration Menu Display ---
        # SNMP is installed - show configuration menu
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  SNMP MANAGEMENT".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  Add Community String"
        Write-MenuItem "[2]  Remove Community String"
        Write-MenuItem "[3]  Configure Permitted Managers"
        Write-MenuItem "[4]  View Current Configuration"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        # --- Section: Option Dispatch ---
        switch ("$choice".ToUpper()) {
            "1" {
                # Add community string
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\ValidCommunities"
                if (-not (Test-Path $regPath)) {
                    $null = New-Item -Path $regPath -Force -ErrorAction SilentlyContinue
                }

                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Enter community string name:" -color "Info"
                $communityName = Read-Host "  "
                if ([string]::IsNullOrWhiteSpace($communityName)) {
                    Write-OutputColor "  Community string name cannot be empty." -color "Error"
                    Write-PressEnter
                    continue
                }

                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Permission level:" -color "Info"
                Write-OutputColor "  [1] READ ONLY  (4)  - Recommended for monitoring" -color "Info"
                Write-OutputColor "  [2] READ WRITE (8)" -color "Info"
                $permChoice = Read-Host "  Select"

                $permValue = switch ($permChoice) {
                    "1" { 4 }
                    "2" { 8 }
                    default { 4 }
                }
                $permName = if ($permValue -eq 4) { "READ ONLY" } else { "READ WRITE" }

                try {
                    New-ItemProperty -Path $regPath -Name $communityName -Value $permValue -PropertyType DWord -Force -ErrorAction Stop | Out-Null
                    Write-OutputColor "  Community string '$communityName' added with $permName permission." -color "Success"
                    Add-SessionChange -Category "System" -Description "Added SNMP community string '$communityName' ($permName)"

                    # Restart SNMP service to apply
                    Restart-Service -Name "SNMP" -Force -ErrorAction SilentlyContinue
                    Write-OutputColor "  SNMP service restarted." -color "Info"
                }
                catch {
                    Write-OutputColor "  Failed to add community string: $_" -color "Error"
                }
                Write-PressEnter
            }
            "2" {
                # Remove community string
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\ValidCommunities"
                if (-not (Test-Path $regPath)) {
                    Write-OutputColor "  No community strings configured." -color "Info"
                    Write-PressEnter
                    continue
                }

                $communities = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                $propNames = @($communities.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | Select-Object -ExpandProperty Name)

                if ($propNames.Count -eq 0) {
                    Write-OutputColor "  No community strings configured." -color "Info"
                    Write-PressEnter
                    continue
                }

                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Current community strings:" -color "Info"
                $csIndex = 1
                foreach ($prop in $propNames) {
                    $permVal = $communities.$prop
                    $permStr = if ($permVal -eq 4) { "READ ONLY" } elseif ($permVal -eq 8) { "READ WRITE" } else { "Value=$permVal" }
                    Write-OutputColor "  [$csIndex] $prop ($permStr)" -color "Info"
                    $csIndex++
                }

                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Enter number to remove (or B to cancel):" -color "Info"
                $removeChoice = Read-Host "  "
                if ("$removeChoice".ToUpper() -eq "B" -or [string]::IsNullOrWhiteSpace($removeChoice)) { continue }

                if (-not ($removeChoice -match '^\d+$') -or [int]$removeChoice -lt 1 -or [int]$removeChoice -gt $propNames.Count) {
                    Write-OutputColor "  Invalid selection." -color "Error"
                    Write-PressEnter
                    continue
                }

                $removeName = $propNames[[int]$removeChoice - 1]
                if (Confirm-UserAction -Message "Remove community string '$removeName'?") {
                    try {
                        Remove-ItemProperty -Path $regPath -Name $removeName -Force -ErrorAction Stop
                        Write-OutputColor "  Community string '$removeName' removed." -color "Success"
                        Add-SessionChange -Category "System" -Description "Removed SNMP community string '$removeName'"
                        Restart-Service -Name "SNMP" -Force -ErrorAction SilentlyContinue
                        Write-OutputColor "  SNMP service restarted." -color "Info"
                    }
                    catch {
                        Write-OutputColor "  Failed to remove community string: $_" -color "Error"
                    }
                }
                Write-PressEnter
            }
            "3" {
                # Configure permitted managers
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\PermittedManagers"
                if (-not (Test-Path $regPath)) {
                    $null = New-Item -Path $regPath -Force -ErrorAction SilentlyContinue
                }

                # Show current permitted managers
                $managers = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                $managerProps = @($managers.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | Select-Object -ExpandProperty Name)

                Write-OutputColor "" -color "Info"
                if ($managerProps.Count -eq 0) {
                    Write-OutputColor "  No permitted managers configured (all hosts can poll)." -color "Warning"
                }
                else {
                    Write-OutputColor "  Current permitted managers:" -color "Info"
                    foreach ($mgr in $managerProps) {
                        Write-OutputColor "    $mgr = $($managers.$mgr)" -color "Info"
                    }
                }

                Write-OutputColor "" -color "Info"
                Write-OutputColor "  [A] Add Manager    [R] Remove All    [B] Back" -color "Info"
                $mgrChoice = Read-Host "  Select"

                switch ("$mgrChoice".ToUpper()) {
                    "A" {
                        Write-OutputColor "  Enter manager IP or hostname:" -color "Info"
                        $mgrHost = Read-Host "  "
                        if ([string]::IsNullOrWhiteSpace($mgrHost)) { continue }

                        # Find next available number
                        $nextNum = 1
                        while ($managerProps -contains "$nextNum") { $nextNum++ }

                        try {
                            New-ItemProperty -Path $regPath -Name "$nextNum" -Value $mgrHost -PropertyType String -Force -ErrorAction Stop | Out-Null
                            Write-OutputColor "  Permitted manager '$mgrHost' added." -color "Success"
                            Add-SessionChange -Category "System" -Description "Added SNMP permitted manager '$mgrHost'"
                            Restart-Service -Name "SNMP" -Force -ErrorAction SilentlyContinue
                        }
                        catch {
                            Write-OutputColor "  Failed to add manager: $_" -color "Error"
                        }
                        Write-PressEnter
                    }
                    "R" {
                        if ($managerProps.Count -eq 0) { continue }
                        if (Confirm-UserAction -Message "Remove all permitted managers? (all hosts will be able to poll)") {
                            try {
                                foreach ($prop in $managerProps) {
                                    Remove-ItemProperty -Path $regPath -Name $prop -Force -ErrorAction SilentlyContinue
                                }
                                Write-OutputColor "  All permitted managers removed." -color "Success"
                                Add-SessionChange -Category "System" -Description "Removed all SNMP permitted managers"
                                Restart-Service -Name "SNMP" -Force -ErrorAction SilentlyContinue
                            }
                            catch {
                                Write-OutputColor "  Failed to remove managers: $_" -color "Error"
                            }
                            Write-PressEnter
                        }
                    }
                }
            }
            "4" {
                # View current configuration
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
                Write-OutputColor "  │$("  SNMP SERVICE STATUS".PadRight(72))│" -color "Info"
                Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

                # Service status
                $snmpSvc = Get-Service -Name "SNMP" -ErrorAction SilentlyContinue
                $svcStatus = if ($null -ne $snmpSvc) { "$($snmpSvc.Status)" } else { "Not Found" }
                $svcColor = if ($svcStatus -eq "Running") { "Success" } else { "Warning" }
                Write-OutputColor "  │$("  Service:    $svcStatus".PadRight(72))│" -color $svcColor

                # Community strings
                $commRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\ValidCommunities"
                if (Test-Path $commRegPath) {
                    $commProps = Get-ItemProperty -Path $commRegPath -ErrorAction SilentlyContinue
                    $commNames = @($commProps.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | Select-Object -ExpandProperty Name)
                    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
                    Write-OutputColor "  │$("  COMMUNITY STRINGS ($($commNames.Count))".PadRight(72))│" -color "Info"
                    foreach ($cName in $commNames) {
                        $cPermVal = $commProps.$cName
                        $cPermStr = if ($cPermVal -eq 4) { "READ ONLY" } elseif ($cPermVal -eq 8) { "READ WRITE" } else { "Permission=$cPermVal" }
                        Write-OutputColor "  │$("    $cName ($cPermStr)".PadRight(72))│" -color "Info"
                    }
                }
                else {
                    Write-OutputColor "  │$("  No community strings configured.".PadRight(72))│" -color "Warning"
                }

                # Permitted managers
                $mgrRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\PermittedManagers"
                if (Test-Path $mgrRegPath) {
                    $mgrProps = Get-ItemProperty -Path $mgrRegPath -ErrorAction SilentlyContinue
                    $mgrNames = @($mgrProps.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | Select-Object -ExpandProperty Name)
                    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
                    Write-OutputColor "  │$("  PERMITTED MANAGERS ($($mgrNames.Count))".PadRight(72))│" -color "Info"
                    if ($mgrNames.Count -eq 0) {
                        Write-OutputColor "  │$("    (none - all hosts can poll)".PadRight(72))│" -color "Warning"
                    }
                    else {
                        foreach ($mName in $mgrNames) {
                            Write-OutputColor "  │$("    $($mgrProps.$mName)".PadRight(72))│" -color "Info"
                        }
                    }
                }

                Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
                Write-PressEnter
            }
            "B" { return }
            default {
                Write-OutputColor "  Invalid choice. Please enter 1-4 or B." -color "Error"
                Start-Sleep -Seconds 2
            }
        }
    }
}

# Install Windows Server Backup feature (Server OS only)
function Install-WindowsServerBackup {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    WINDOWS SERVER BACKUP").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Test-WindowsServer)) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  Windows Server Backup requires Windows Server OS.".PadRight(72))│" -color "Warning"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        return
    }

    # Check if already installed
    $wsbFeature = Get-WindowsFeature -Name "Windows-Server-Backup" -ErrorAction SilentlyContinue
    if ($null -ne $wsbFeature -and $wsbFeature.InstallState -eq "Installed") {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  Windows Server Backup is already installed.".PadRight(72))│" -color "Success"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Use 'wbadmin' from an elevated command prompt to manage backups:".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("    wbadmin get versions     - List available backups".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("    wbadmin get items        - List items in a backup".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("    wbadmin start backup     - Start a one-time backup".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("    wbadmin start recovery   - Start a recovery operation".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Or open 'Windows Server Backup' from Server Manager > Tools.".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        return
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  Windows Server Backup is not installed.".PadRight(72))│" -color "Warning"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  This feature provides backup and recovery capabilities for".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Windows Server including volumes, files, and system state.".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Install Windows Server Backup?")) {
        Write-OutputColor "  Installation cancelled." -color "Info"
        return
    }

    try {
        Write-OutputColor "  Installing Windows Server Backup... This may take several minutes." -color "Info"

        $installResult = Install-WindowsFeatureWithTimeout -FeatureName "Windows-Server-Backup" -DisplayName "Windows Server Backup" -IncludeManagementTools

        if ($installResult.TimedOut) {
            Write-OutputColor "  Installation timed out." -color "Error"
            Add-SessionChange -Category "System" -Description "Windows Server Backup installation timed out"
            return
        }
        elseif ($installResult.Success) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  Windows Server Backup installed successfully!".PadRight(72))│" -color "Success"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Getting started with wbadmin:".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("    wbadmin get versions     - List available backups".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("    wbadmin get items        - List items in a backup".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("    wbadmin start backup     - Start a one-time backup".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("    wbadmin start recovery   - Start a recovery operation".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Or open 'Windows Server Backup' from Server Manager > Tools.".PadRight(72))│" -color "Info"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            Add-SessionChange -Category "System" -Description "Installed Windows Server Backup"
            Clear-MenuCache
        }
        else {
            Write-OutputColor "  Windows Server Backup installation failed." -color "Error"
            Add-SessionChange -Category "System" -Description "Windows Server Backup installation failed"
        }
    }
    catch {
        Write-OutputColor "  Failed to install Windows Server Backup: $_" -color "Error"
    }
}

# Certificate management submenu
function Show-CertificateMenu {
    while ($true) {
        if ($global:ReturnToMainMenu) { return }
        Clear-Host

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                      CERTIFICATE MANAGEMENT").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  ACTIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  View Certificates"
        Write-MenuItem "[2]  Check Expiring Certificates (30 days)"
        Write-MenuItem "[3]  Export Certificate"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ("$choice".ToUpper()) {
            "1" {
                # View certificates
                Clear-Host
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
                Write-OutputColor "  ║$(("                    LOCAL MACHINE CERTIFICATES").PadRight(72))║" -color "Info"
                Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
                Write-OutputColor "" -color "Info"

                $certs = @(Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue)

                if ($certs.Count -eq 0) {
                    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
                    Write-OutputColor "  │$("  No certificates found in LocalMachine\My store.".PadRight(72))│" -color "Warning"
                    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
                }
                else {
                    Write-OutputColor "  Found $($certs.Count) certificate(s) in LocalMachine\My:" -color "Info"
                    Write-OutputColor "" -color "Info"

                    $certIndex = 1
                    foreach ($cert in $certs) {
                        $subject = if ($cert.Subject.Length -gt 50) { $cert.Subject.Substring(0, 47) + "..." } else { "$($cert.Subject)" }
                        $thumbprint = "$($cert.Thumbprint)"
                        $expiry = $cert.NotAfter.ToString("yyyy-MM-dd")
                        $isExpired = ($cert.NotAfter -lt (Get-Date))
                        $statusText = if ($isExpired) { "EXPIRED" } else { "Valid" }
                        $statusColor = if ($isExpired) { "Error" } else { "Success" }

                        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
                        Write-OutputColor "  │$("  [$certIndex] $subject".PadRight(72))│" -color "Info"
                        Write-OutputColor "  │$("      Thumbprint: $thumbprint".PadRight(72))│" -color "Info"
                        Write-OutputColor "  │$("      Expires:    $expiry  [$statusText]".PadRight(72))│" -color $statusColor
                        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
                        $certIndex++
                    }
                }
                Write-PressEnter
            }
            "2" {
                # Check expiring certificates
                Clear-Host
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
                Write-OutputColor "  ║$(("                   EXPIRING CERTIFICATES (30 DAYS)").PadRight(72))║" -color "Info"
                Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
                Write-OutputColor "" -color "Info"

                $certs = @(Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue)
                $thresholdDate = (Get-Date).AddDays(30)
                $expiringCerts = @($certs | Where-Object { $_.NotAfter -le $thresholdDate })
                $expiredCerts = @($expiringCerts | Where-Object { $_.NotAfter -lt (Get-Date) })
                $soonExpiring = @($expiringCerts | Where-Object { $_.NotAfter -ge (Get-Date) })

                Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
                Write-OutputColor "  │$("  SUMMARY".PadRight(72))│" -color "Info"
                Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                Write-OutputColor "  │$("  Total certificates:    $($certs.Count)".PadRight(72))│" -color "Info"

                $expiredColor = if ($expiredCerts.Count -gt 0) { "Error" } else { "Success" }
                Write-OutputColor "  │$("  Already expired:       $($expiredCerts.Count)".PadRight(72))│" -color $expiredColor

                $soonColor = if ($soonExpiring.Count -gt 0) { "Warning" } else { "Success" }
                Write-OutputColor "  │$("  Expiring within 30d:   $($soonExpiring.Count)".PadRight(72))│" -color $soonColor
                Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

                if ($expiringCerts.Count -gt 0) {
                    Write-OutputColor "" -color "Info"
                    foreach ($cert in $expiringCerts) {
                        $subject = if ($cert.Subject.Length -gt 50) { $cert.Subject.Substring(0, 47) + "..." } else { "$($cert.Subject)" }
                        $expiry = $cert.NotAfter.ToString("yyyy-MM-dd HH:mm")
                        $isExpired = ($cert.NotAfter -lt (Get-Date))
                        $daysLeft = [math]::Ceiling(($cert.NotAfter - (Get-Date)).TotalDays)
                        $statusText = if ($isExpired) { "EXPIRED" } else { "$daysLeft days left" }
                        $statusColor = if ($isExpired) { "Error" } else { "Warning" }

                        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
                        Write-OutputColor "  │$("  $subject".PadRight(72))│" -color $statusColor
                        Write-OutputColor "  │$("    Thumbprint: $($cert.Thumbprint)".PadRight(72))│" -color "Info"
                        Write-OutputColor "  │$("    Expires:    $expiry  [$statusText]".PadRight(72))│" -color $statusColor
                        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
                    }
                }
                else {
                    Write-OutputColor "" -color "Info"
                    Write-OutputColor "  No certificates expiring within 30 days." -color "Success"
                }
                Write-PressEnter
            }
            "3" {
                # Export certificate
                $certs = @(Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue)
                if ($certs.Count -eq 0) {
                    Write-OutputColor "  No certificates found to export." -color "Warning"
                    Write-PressEnter
                    continue
                }

                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Certificates available for export:" -color "Info"
                Write-OutputColor "" -color "Info"

                $certIndex = 1
                foreach ($cert in $certs) {
                    $subject = if ($cert.Subject.Length -gt 50) { $cert.Subject.Substring(0, 47) + "..." } else { "$($cert.Subject)" }
                    Write-OutputColor "  [$certIndex] $subject" -color "Info"
                    Write-OutputColor "       Thumbprint: $($cert.Thumbprint)" -color "Info"
                    $certIndex++
                }

                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Enter certificate number to export (or B to cancel):" -color "Info"
                $certChoice = Read-Host "  "
                if ("$certChoice".ToUpper() -eq "B" -or [string]::IsNullOrWhiteSpace($certChoice)) { continue }

                if (-not ($certChoice -match '^\d+$') -or [int]$certChoice -lt 1 -or [int]$certChoice -gt $certs.Count) {
                    Write-OutputColor "  Invalid selection." -color "Error"
                    Write-PressEnter
                    continue
                }

                $selectedCert = $certs[[int]$certChoice - 1]

                # Determine export path
                $exportDir = $script:TempPath
                if (-not (Test-Path $exportDir)) {
                    $null = New-Item -Path $exportDir -ItemType Directory -Force -ErrorAction SilentlyContinue
                }

                $safeName = "$($selectedCert.Thumbprint)".Substring(0, 8)
                $exportPath = Join-Path $exportDir "$safeName.cer"

                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Export path: $exportPath" -color "Info"
                Write-OutputColor "  (Certificate will be exported as DER-encoded .cer, no private key)" -color "Info"

                if (-not (Confirm-UserAction -Message "Export this certificate?")) { continue }

                try {
                    $null = Export-Certificate -Cert $selectedCert -FilePath $exportPath -Type CERT -Force -ErrorAction Stop
                    Write-OutputColor "  Certificate exported to: $exportPath" -color "Success"
                    Add-SessionChange -Category "System" -Description "Exported certificate $($selectedCert.Thumbprint) to $exportPath"
                }
                catch {
                    Write-OutputColor "  Failed to export certificate: $_" -color "Error"
                }
                Write-PressEnter
            }
            "B" { return }
            default {
                Write-OutputColor "  Invalid choice. Please enter 1-3 or B." -color "Error"
                Start-Sleep -Seconds 2
            }
        }
    }
}

# Show Operations submenu