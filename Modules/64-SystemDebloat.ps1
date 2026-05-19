#region ===== SYSTEM DEBLOAT AND OPTIMIZATION =====
# Module: 64-SystemDebloat
# Purpose: Remove bloatware, disable telemetry, optimize services for Windows Server and Workstation
# Profiles: Light (safe removals), Standard (recommended), Aggressive (maximum cleanup)
# All operations support WhatIf preview, undo where possible, and session change tracking.

# ────────────────────────────────────────────────────────────────────────
# Helper: Detect Windows version details for version-aware debloat
# ────────────────────────────────────────────────────────────────────────
function Get-WindowsDebloatInfo {
    $ntVer = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $build = if ($ntVer) { [int]$ntVer.CurrentBuildNumber } else { 0 }
    $displayVersion = if ($ntVer) { $ntVer.DisplayVersion } else { "" }  # "23H2", "24H2", "25H2", etc.
    $productType = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions' -ErrorAction SilentlyContinue).ProductType

    $isServer = ($productType -ne "WinNT")
    $isWin11 = (-not $isServer -and $build -ge 22000)
    $isWin10 = (-not $isServer -and $build -lt 22000 -and $build -ge 10240)

    # Map builds to known versions
    $versionTag = if ($isServer -and $build -ge 26100) { "Server2025" }
        elseif ($isServer) { "ServerOlder" }
        elseif ($build -ge 26100) { "Win11_24H2+" }      # 24H2 and later (26100+)
        elseif ($build -ge 22631) { "Win11_23H2" }        # 23H2 (22631)
        elseif ($build -ge 22621) { "Win11_22H2" }        # 22H2 (22621)
        elseif ($build -ge 22000) { "Win11_21H2" }        # Original Win11
        elseif ($build -ge 19045) { "Win10_22H2" }        # Last Win10 (19045)
        elseif ($build -ge 19041) { "Win10_Older" }
        else { "Legacy" }

    # Server Core detection (no GUI shell)
    $isServerCore = $false
    if ($isServer) {
        $serverLevels = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Server\ServerLevels' -ErrorAction SilentlyContinue
        if ($null -ne $serverLevels) {
            $hasGui = $serverLevels.'Server-Gui-Shell'
            $isServerCore = -not $hasGui
        } else {
            # Fallback: check if explorer.exe exists
            $isServerCore = -not (Test-Path "$env:SystemRoot\explorer.exe")
        }
    }

    return @{
        Build          = $build
        DisplayVersion = $displayVersion
        IsServer       = $isServer
        IsServerCore   = $isServerCore
        IsWin11        = $isWin11
        IsWin10        = $isWin10
        VersionTag     = $versionTag
    }
}

# ────────────────────────────────────────────────────────────────────────
# Helper: Get removable AppxPackages for a given profile
# ────────────────────────────────────────────────────────────────────────
function Get-RemovableAppxPackages {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet("Light","Standard","Aggressive")]
        [string]$DebloatProfile
    )

    $osInfo = Get-WindowsDebloatInfo

    # ── Light profile: obvious bloatware and rarely-used Store apps ──
    $lightPackages = @(
        "king.com.CandyCrushSaga"
        "king.com.CandyCrushSodaSaga"
        "king.com.CandyCrushFriends"
        "king.com.BubbleWitch3Saga"
        "A278AB0D.MarchofEmpires"
        "Microsoft.MicrosoftSolitaireCollection"
        "Microsoft.3DViewer"
        "Microsoft.MixedReality.Portal"
        "Microsoft.MSPaint"                       # Paint 3D (not classic Paint)
        "Microsoft.SkypeApp"
        "Microsoft.GetHelp"
        "Microsoft.Getstarted"                    # Tips
        "Microsoft.WindowsFeedbackHub"
        "Microsoft.MicrosoftOfficeHub"
    )

    # Win10-specific light removals
    if ($osInfo.IsWin10) {
        $lightPackages += @(
            "Microsoft.YourPhone"
            "Microsoft.Print3D"
            "Microsoft.OneConnect"                # Paid Wi-Fi & Cellular
            "Microsoft.Wallet"
        )
    }

    # Win11-specific light removals
    if ($osInfo.IsWin11) {
        $lightPackages += @(
            "Microsoft.YourPhone"                 # Phone Link (renamed from Your Phone)
            "MicrosoftWindows.Client.WebExperience"  # Widgets (Win11)
            "Microsoft.WindowsMeetNow"            # Meet Now / Chat
        )
    }

    # 24H2+ specific (build 26100+)
    if ($osInfo.Build -ge 26100) {
        $lightPackages += @(
            "Microsoft.Windows.Ai.Copilot.Provider"  # Copilot provider
            "Microsoft.Copilot"                       # Copilot app (24H2+)
            "MicrosoftWindows.CrossDevice"            # Cross-device experience
            "Microsoft.OutlookForWindows"             # New Outlook (replaces Mail)
        )
    }

    # 25H2+ / 26H2+ specific (build 26200+)
    if ($osInfo.Build -ge 26200) {
        $lightPackages += @(
            "MicrosoftWindows.AI.Recall"              # Windows Recall
            "Microsoft.Windows.AI.Studio"             # AI Studio
        )
    }

    # ── Standard adds media/social/Xbox apps ──
    $standardPackages = @(
        "Microsoft.ZuneMusic"                     # Groove Music / Media Player
        "Microsoft.ZuneVideo"                     # Movies & TV
        "Microsoft.People"
        "Microsoft.WindowsMaps"
        "Microsoft.Office.OneNote"                # OneNote for Windows 10
        "Microsoft.WindowsSoundRecorder"          # Voice Recorder
        "Microsoft.WindowsAlarms"
        "Microsoft.BingWeather"
        "Microsoft.BingNews"
        "Microsoft.XboxApp"
        "Microsoft.XboxGamingOverlay"
        "Microsoft.XboxGameOverlay"
        "Microsoft.XboxSpeechToTextOverlay"
        "Microsoft.XboxIdentityProvider"
        "Microsoft.Xbox.TCUI"
        "Clipchamp.Clipchamp"
    )

    # Win11 23H2+ gets Dev Home and additional Microsoft apps
    if ($osInfo.Build -ge 22631) {
        $standardPackages += @(
            "Microsoft.WindowsDevHome"            # Dev Home (23H2+)
        )
    }

    # ── Aggressive adds Edge, OneDrive, Teams consumer, Cortana ──
    $aggressivePackages = @(
        "Microsoft.MicrosoftEdge.Stable"
        "Microsoft.OneDriveSync"
        "MicrosoftTeams"                          # Teams consumer (personal)
        "Microsoft.549981C3F5F10"                 # Cortana
    )

    # Win11 aggressive: do NOT remove Microsoft.Windows.ContentDeliveryManager. It was previously
    # added here on the assumption that it only installs sponsored apps, but on Win11 22H2+ it's
    # an inbox component that the Start menu and Settings panes depend on for tile rendering and
    # lock-screen image hosting. Removing it leaves Start with empty tile placeholders and breaks
    # several Settings panes. The HKCU registry tweaks below (RotatingLockScreenOverlayEnabled,
    # SubscribedContent-*Enabled) already disable the consumer-features behavior — the package
    # itself should stay installed.
    if ($osInfo.IsWin11) {
        # (Reserved for future Win11-aggressive-only packages; ContentDeliveryManager removed
        # from this list — see comment above.)
    }

    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($pkg in $lightPackages) { $result.Add($pkg) }

    if ($DebloatProfile -eq "Standard" -or $DebloatProfile -eq "Aggressive") {
        foreach ($pkg in $standardPackages) { $result.Add($pkg) }
    }

    if ($DebloatProfile -eq "Aggressive") {
        foreach ($pkg in $aggressivePackages) { $result.Add($pkg) }
    }

    return $result
}

# ────────────────────────────────────────────────────────────────────────
# Helper: Get services that can be disabled for a given type and profile
# ────────────────────────────────────────────────────────────────────────
function Get-DisableableServices {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet("Server","Workstation")]
        [string]$Type,

        [Parameter(Mandatory=$true)]
        [ValidateSet("Light","Standard","Aggressive")]
        [string]$DebloatProfile
    )

    $services = [System.Collections.Generic.List[hashtable]]::new()

    if ($Type -eq "Workstation") {
        # Light
        $services.Add(@{ Name = "DiagTrack"; DisplayName = "Connected User Experiences and Telemetry (DiagTrack)"; Warning = $null })
        $services.Add(@{ Name = "dmwappushservice"; DisplayName = "Device Management WAP Push Service"; Warning = $null })

        if ($DebloatProfile -eq "Standard" -or $DebloatProfile -eq "Aggressive") {
            $services.Add(@{ Name = "SysMain"; DisplayName = "SysMain (Superfetch)"; Warning = "Only disable if SSD detected"; CheckSSD = $true })
        }

        if ($DebloatProfile -eq "Aggressive") {
            $services.Add(@{ Name = "WSearch"; DisplayName = "Windows Search Indexing"; Warning = "Disabling slows file search in Explorer" })
            $services.Add(@{ Name = "BITS"; DisplayName = "Background Intelligent Transfer Service"; Warning = "Breaks Windows Update and Store downloads" })
            $services.Add(@{ Name = "Spooler"; DisplayName = "Print Spooler"; Warning = "Only safe if no printers are used"; CheckPrinters = $true })
        }
    }
    elseif ($Type -eq "Server") {
        # Light
        $services.Add(@{ Name = "DiagTrack"; DisplayName = "Connected User Experiences and Telemetry (DiagTrack)"; Warning = $null })

        if ($DebloatProfile -eq "Standard" -or $DebloatProfile -eq "Aggressive") {
            $services.Add(@{ Name = "Spooler"; DisplayName = "Print Spooler"; Warning = "Only safe if not a print server"; CheckPrintServer = $true })
            $services.Add(@{ Name = "Fax"; DisplayName = "Fax Service"; Warning = $null })
            $services.Add(@{ Name = "bthserv"; DisplayName = "Bluetooth Support Service"; Warning = "Only safe if no Bluetooth hardware"; CheckBluetooth = $true })
        }

        if ($DebloatProfile -eq "Aggressive") {
            $services.Add(@{ Name = "WerSvc"; DisplayName = "Windows Error Reporting Service"; Warning = $null })
            $services.Add(@{ Name = "RemoteRegistry"; DisplayName = "Remote Registry"; Warning = "Some management tools may require this" })
        }
    }

    return $services
}

# ────────────────────────────────────────────────────────────────────────
# Helper: Get telemetry scheduled tasks to disable
# ────────────────────────────────────────────────────────────────────────
function Get-TelemetryTasks {
    $taskPaths = @(
        "\Microsoft\Windows\Application Experience\"
        "\Microsoft\Windows\Customer Experience Improvement Program\"
        "\Microsoft\Windows\Autochk\"
        "\Microsoft\Windows\DiskDiagnostic\"
        "\Microsoft\Windows\Feedback\Siuf\"
        "\Microsoft\Windows\Maps\"
        "\Microsoft\Windows\CloudExperienceHost\"
        "\Microsoft\Windows\RetailDemo\"
        "\Microsoft\Windows\MobilePC\"
    )

    # Win11 24H2+ additional telemetry/AI paths
    $osInfo = Get-WindowsDebloatInfo
    if ($osInfo.Build -ge 26100) {
        $taskPaths += @(
            "\Microsoft\Windows\Shell\"
            "\Microsoft\Windows\Cortana\"
        )
    }

    $tasks = [System.Collections.Generic.List[object]]::new()
    foreach ($taskPath in $taskPaths) {
        try {
            $found = Get-ScheduledTask -TaskPath $taskPath -ErrorAction SilentlyContinue
            if ($null -ne $found) {
                foreach ($task in @($found)) {
                    # Filter by Author. Third-party software (Dell OpenManage, Lenovo Vantage,
                    # some EDR products, custom RMM scripts) does co-locate tasks under the
                    # Microsoft\Windows\* hierarchy. Path-based disabling without an author
                    # filter silently kills those — operator's monitoring breaks overnight.
                    # We only target tasks authored by "Microsoft Corporation" or a Microsoft
                    # subnamespace; everything else stays put.
                    $author = $task.Author
                    if ($null -ne $author -and ($author -like 'Microsoft*' -or $author -eq '' -or $author -like '$(@%SystemRoot%*')) {
                        $tasks.Add($task)
                    } elseif ($null -eq $author -or $author -eq '') {
                        # Some inbox tasks have no Author populated; include only if URI matches
                        # the well-known Microsoft prefix to be safe.
                        if ($task.URI -like '\Microsoft\Windows\*') {
                            $tasks.Add($task)
                        }
                    }
                    # else: third-party task in a Microsoft path — leave alone.
                }
            }
        }
        catch {
            # Path may not exist on this OS version
        }
    }
    return $tasks
}

# ────────────────────────────────────────────────────────────────────────
# Helper: Test whether the system drive is an SSD
# ────────────────────────────────────────────────────────────────────────
function Test-SSDPresent {
    try {
        $systemDriveLetter = $env:SystemDrive.TrimEnd(":\")
        $partition = Get-Partition -DriveLetter $systemDriveLetter -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $partition) { return $false }

        $disk = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DeviceId -eq $partition.DiskNumber }
        if ($null -eq $disk) { return $false }

        # MediaType: SSD, HDD, Unspecified — also check for NVMe in FriendlyName/BusType
        if ($disk.MediaType -eq "SSD") { return $true }
        if ($disk.BusType -eq "NVMe") { return $true }
        return $false
    }
    catch {
        return $false
    }
}

# ────────────────────────────────────────────────────────────────────────
# Prompt for debloat profile (interactive only)
# ────────────────────────────────────────────────────────────────────────
function Select-DebloatProfile {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT DEBLOAT PROFILE".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  [1] Light      — Safe removals only (bloatware, basic telemetry)".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [2] Standard   — Recommended (Light + media/social apps, registry)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  [3] Aggressive — Maximum cleanup (Standard + system services)".PadRight(72))│" -color "Warning"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $profileChoice = Read-Host "  Select profile"
    $navResult = Test-NavigationCommand -UserInput $profileChoice
    if ($navResult.ShouldReturn) { return $null }

    switch ($profileChoice) {
        "1" { return "Light" }
        "2" { return "Standard" }
        "3" { return "Aggressive" }
        default {
            Write-OutputColor "  Invalid selection. Using Standard." -color "Warning"
            return "Standard"
        }
    }
}

# ────────────────────────────────────────────────────────────────────────
# Helper: Create a system restore point before debloat (best-effort)
# ────────────────────────────────────────────────────────────────────────
function New-DebloatRestorePoint {
    try {
        # System Restore is only available on workstation SKUs. The first probe was
        # comparing `$null -ne (...)` (always a [bool]) and then checking
        # `if ($null -eq $srEnabled)` which is unreachable — the srservice fallback
        # never ran. Treat $false as "not detected via cmdlet" and try the service
        # probe before giving up.
        $srEnabled = $null -ne (Get-ComputerRestorePoint -ErrorAction SilentlyContinue)
        if (-not $srEnabled) {
            $srSvc = Get-Service -Name srservice -ErrorAction SilentlyContinue
            if ($null -eq $srSvc -or $srSvc.StartType -eq 'Disabled') { return }
        }
        Write-OutputColor "  Creating restore point before debloat..." -color "Info"
        Checkpoint-Computer -Description "$($script:ToolName) Debloat $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-OutputColor "  Restore point created." -color "Success"
    }
    catch {
        Write-OutputColor "  Note: Could not create restore point (not available on Server editions)" -color "Warning"
    }
}

# ════════════════════════════════════════════════════════════════════════
# Main menu: Start-SystemDebloat
# ════════════════════════════════════════════════════════════════════════
function Start-SystemDebloat {
    while ($true) {
        if ($global:ReturnToMainMenu) { return }

        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                    SYSTEM DEBLOAT AND OPTIMIZATION").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        # Show current OS info (version-aware)
        $menuOsInfo = Get-WindowsDebloatInfo
        $osCaption = (Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec 8 -ErrorAction SilentlyContinue).Caption
        if ($null -ne $osCaption) {
            Write-OutputColor "  OS: $osCaption" -color "Info"
        }
        $isServer = $menuOsInfo.IsServer
        $modeTag = if ($menuOsInfo.IsServerCore) { "Server Core" } elseif ($isServer) { "Server" } else { "Workstation" }
        $verDisplay = if ($menuOsInfo.DisplayVersion) { " ($($menuOsInfo.DisplayVersion))" } else { "" }
        Write-OutputColor "  Mode: $modeTag | Build: $($menuOsInfo.Build)$verDisplay | Profile: $($menuOsInfo.VersionTag)" -color "Info"
        if ($menuOsInfo.IsServerCore) {
            Write-OutputColor "  Note: Server Core — AppX and UI operations will be skipped" -color "Warning"
        }
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  DEBLOAT OPTIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem -Text "[1]  Workstation Debloat (AppxPackages, telemetry, startup)"
        Write-MenuItem -Text "[2]  Server Debloat (services, optional features, telemetry)"
        Write-MenuItem -Text "[3]  Quick Scan (analyze only, no changes)"
        Write-MenuItem -Text "[4]  Custom Debloat (choose individual categories)"
        Write-MenuItem -Text "[5]  Windows UI Cleanup (version-aware)"
        Write-MenuItem -Text "[6]  Toggle OS Dark / Light Theme"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" {
                $selectedProfile = Select-DebloatProfile
                if ($null -eq $selectedProfile) { continue }
                New-DebloatRestorePoint
                Invoke-WorkstationDebloat -DebloatProfile $selectedProfile
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Press Enter to continue..." -color "Info"
                Read-Host | Out-Null
            }
            "2" {
                $selectedProfile = Select-DebloatProfile
                if ($null -eq $selectedProfile) { continue }
                New-DebloatRestorePoint
                Invoke-ServerDebloat -DebloatProfile $selectedProfile
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Press Enter to continue..." -color "Info"
                Read-Host | Out-Null
            }
            "3" {
                Show-DebloatAnalysis
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Press Enter to continue..." -color "Info"
                Read-Host | Out-Null
            }
            "4" {
                New-DebloatRestorePoint
                Invoke-CustomDebloat
            }
            "5" {
                Invoke-Win11UICleanup
                Write-PressEnter
            }
            "6" {
                Set-OSThemeMode
                Write-PressEnter
            }
            "b" { return }
            "B" { return }
            default {
                Write-OutputColor "  Invalid selection." -color "Warning"
                Start-Sleep -Milliseconds 800
            }
        }
    }
}

# ════════════════════════════════════════════════════════════════════════
# Workstation Debloat
# ════════════════════════════════════════════════════════════════════════
function Invoke-WorkstationDebloat {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet("Light","Standard","Aggressive")]
        [string]$DebloatProfile,

        [switch]$PreviewOnly
    )

    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                      WORKSTATION DEBLOAT [$DebloatProfile]").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Short-circuit on Server Core. Get-AppxPackage / Get-AppxProvisionedPackage are
    # not present on Server Core SKUs; running this path floods the transcript with
    # "term is not recognized" errors for every package candidate. Server Core
    # operators should pick the Server Debloat path instead.
    $debloatInfo = Get-WindowsDebloatInfo
    if ($null -ne $debloatInfo -and $debloatInfo.IsServerCore) {
        Write-OutputColor "  Server Core detected — Workstation Debloat is not applicable here." -color "Warning"
        Write-OutputColor "  Use 'Server Debloat' from the Debloat menu instead." -color "Info"
        return
    }

    if ($PreviewOnly) {
        Write-OutputColor "  *** PREVIEW MODE — No changes will be made ***" -color "Warning"
        Write-OutputColor "" -color "Info"
    }

    $removed = 0
    $skippedCount = 0
    $failedCount = 0

    # ── Phase 1: AppxPackage Removal ──────────────────────────────────
    Write-OutputColor "  ── AppxPackage Removal ────────────────────────────────────────────" -color "Info"
    $packages = Get-RemovableAppxPackages -DebloatProfile $DebloatProfile

    foreach ($pkgName in $packages) {
        $installed = Get-AppxPackage -Name "*$pkgName*" -AllUsers -ErrorAction SilentlyContinue
        $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$pkgName*" }

        if ($null -eq $installed -and $null -eq $provisioned) {
            Write-OutputColor "  [SKIP] $pkgName — not installed" -color "Debug"
            $skippedCount++
            continue
        }

        if ($PreviewOnly) {
            Write-OutputColor "  [WOULD REMOVE] $pkgName" -color "Info"
            $removed++
            continue
        }

        # Aggressive-only packages need extra confirmation
        $needsConfirm = $false
        if ($DebloatProfile -eq "Aggressive") {
            if ($pkgName -like "*MicrosoftEdge*") {
                Write-OutputColor "  WARNING: Removing Microsoft Edge may break web-based features." -color "Warning"
                $needsConfirm = $true
            }
            elseif ($pkgName -like "*OneDrive*") {
                Write-OutputColor "  WARNING: Removing OneDrive will delete local sync settings." -color "Warning"
                $needsConfirm = $true
            }
        }

        if ($needsConfirm) {
            if (-not (Confirm-UserAction -Message "  Remove $pkgName?")) {
                Write-OutputColor "  [SKIP] $pkgName — user declined" -color "Info"
                $skippedCount++
                continue
            }
        }

        try {
            if ($null -ne $installed) {
                $installed | Remove-AppxPackage -AllUsers -ErrorAction Stop
            }
            if ($null -ne $provisioned) {
                $provisioned | Remove-AppxProvisionedPackage -Online -ErrorAction Stop | Out-Null
            }
            Write-OutputColor "  [REMOVED] $pkgName" -color "Success"
            $removed++
            Add-SessionChange -Category "Debloat" -Description "Removed AppxPackage: $pkgName"
            # Note: AppxPackage reinstall is not always possible — undo is limited
        }
        catch {
            Write-OutputColor "  [FAILED] $pkgName — $_" -color "Error"
            $failedCount++
        }
    }

    Write-OutputColor "" -color "Info"

    # ── Phase 2: Service Optimization ─────────────────────────────────
    Write-OutputColor "  ── Service Optimization ──────────────────────────────────────────" -color "Info"
    $serviceList = Get-DisableableServices -Type "Workstation" -DebloatProfile $DebloatProfile

    foreach ($svcInfo in $serviceList) {
        # SSD check for SysMain
        if ($svcInfo.CheckSSD) {
            if (-not (Test-SSDPresent)) {
                Write-OutputColor "  [SKIP] $($svcInfo.DisplayName) — no SSD detected, keeping enabled" -color "Debug"
                $skippedCount++
                continue
            }
        }

        # Printer check for Print Spooler. Past pattern: Get-Printer misses printers added via
        # legacy port drivers (MFP scan-to-folder, ERP-vendor virtual queues), so also scan
        # the printer registry hive — ANY entry means an installed printer that may depend on
        # Spooler. We also widen the Get-Printer filter to ANY printer (not just shared) since
        # local-only printers still need Spooler.
        if ($svcInfo.CheckPrinters) {
            $printers = @(Get-Printer -ErrorAction SilentlyContinue)
            $printerRegEntries = @()
            try {
                $printerRegEntries = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers' -ErrorAction SilentlyContinue |
                    Where-Object { $_.PSChildName -notmatch '^(Microsoft|Fax|OneNote|PDF)' })
            } catch { }
            if ($printers.Count -gt 0 -or $printerRegEntries.Count -gt 0) {
                Write-OutputColor "  [SKIP] $($svcInfo.DisplayName) — $($printers.Count) Get-Printer + $($printerRegEntries.Count) reg-only printer(s) detected" -color "Debug"
                $skippedCount++
                continue
            }
        }

        $svc = Get-Service -Name $svcInfo.Name -ErrorAction SilentlyContinue
        if ($null -eq $svc) {
            Write-OutputColor "  [SKIP] $($svcInfo.DisplayName) — service not found" -color "Debug"
            $skippedCount++
            continue
        }

        # Dependent-service check. Stop-Service -Force will also stop dependents without warning;
        # disabling Spooler/BITS/SysMain can cascade-break WSUS, scan-to-folder, ERP printing,
        # and backup software that pinned a dependency. Refuse to disable if any non-Microsoft
        # or critical service depends on this one, regardless of CheckPrinters/CheckSSD results.
        $runningDependents = @(Get-Service -Name $svcInfo.Name -DependentServices -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' })
        if ($runningDependents.Count -gt 0) {
            Write-OutputColor "  [SKIP] $($svcInfo.DisplayName) — $($runningDependents.Count) running dependent service(s):" -color "Debug"
            foreach ($d in ($runningDependents | Select-Object -First 5)) {
                Write-OutputColor "         - $($d.DisplayName) ($($d.Name))" -color "Debug"
            }
            $skippedCount++
            continue
        }

        if ($svc.StartType -eq "Disabled") {
            Write-OutputColor "  [SKIP] $($svcInfo.DisplayName) — already disabled" -color "Debug"
            $skippedCount++
            continue
        }

        if ($null -ne $svcInfo.Warning) {
            Write-OutputColor "  NOTE: $($svcInfo.Warning)" -color "Warning"
        }

        if ($PreviewOnly) {
            Write-OutputColor "  [WOULD DISABLE] $($svcInfo.DisplayName) (currently: $($svc.Status)/$($svc.StartType))" -color "Info"
            $removed++
            continue
        }

        try {
            $originalStartType = $svc.StartType.ToString()
            $originalStatus = $svc.Status.ToString()

            if ($svc.Status -eq "Running") {
                Stop-Service -Name $svcInfo.Name -Force -ErrorAction Stop
            }
            Set-Service -Name $svcInfo.Name -StartupType Disabled -ErrorAction Stop

            Write-OutputColor "  [DISABLED] $($svcInfo.DisplayName) (was: $originalStartType)" -color "Success"
            $removed++

            Add-SessionChange -Category "Debloat" -Description "Disabled service: $($svcInfo.DisplayName)"
            Clear-MenuCache

            $svcNameCapture = $svcInfo.Name
            $startTypeCapture = $originalStartType
            Add-UndoAction -Category "Debloat" -Description "Disabled service $($svcInfo.DisplayName)" -UndoScript {
                param($SvcName, $StartType)
                Set-Service -Name $SvcName -StartupType $StartType -ErrorAction SilentlyContinue
                if ($StartType -eq "Automatic") {
                    Start-Service -Name $SvcName -ErrorAction SilentlyContinue
                }
            } -UndoParams @{ SvcName = $svcNameCapture; StartType = $startTypeCapture }
        }
        catch {
            Write-OutputColor "  [FAILED] $($svcInfo.DisplayName) — $_" -color "Error"
            $failedCount++
        }
    }

    Write-OutputColor "" -color "Info"

    # ── Phase 3: Telemetry Scheduled Tasks ────────────────────────────
    Write-OutputColor "  ── Telemetry Scheduled Tasks ─────────────────────────────────────" -color "Info"
    $telemetryTasks = Get-TelemetryTasks

    foreach ($task in $telemetryTasks) {
        if ($task.State -eq "Disabled") {
            Write-OutputColor "  [SKIP] $($task.TaskName) — already disabled" -color "Debug"
            $skippedCount++
            continue
        }

        if ($PreviewOnly) {
            Write-OutputColor "  [WOULD DISABLE] $($task.TaskPath)$($task.TaskName)" -color "Info"
            $removed++
            continue
        }

        try {
            $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null
            Write-OutputColor "  [DISABLED] $($task.TaskName)" -color "Success"
            $removed++
            Add-SessionChange -Category "Debloat" -Description "Disabled task: $($task.TaskName)"

            $taskPathCapture = $task.TaskPath
            $taskNameCapture = $task.TaskName
            Add-UndoAction -Category "Debloat" -Description "Disabled task $($task.TaskName)" -UndoScript {
                param($TaskPath, $TaskName)
                Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue |
                    Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
            } -UndoParams @{ TaskPath = $taskPathCapture; TaskName = $taskNameCapture }
        }
        catch {
            Write-OutputColor "  [FAILED] $($task.TaskName) — $_" -color "Error"
            $failedCount++
        }
    }

    Write-OutputColor "" -color "Info"

    # ── Phase 4: Registry Tweaks (Standard and Aggressive) ────────────
    if ($DebloatProfile -eq "Standard" -or $DebloatProfile -eq "Aggressive") {
        Write-OutputColor "  ── Registry Tweaks ───────────────────────────────────────────────" -color "Info"

        $registryTweaks = @(
            @{
                Path  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
                Name  = "DisableWindowsConsumerFeatures"
                Value = 1
                Type  = "DWord"
                Desc  = "Disable app suggestions and silently installed apps"
            }
            @{
                Path  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
                Name  = "EnableActivityFeed"
                Value = 0
                Type  = "DWord"
                Desc  = "Disable timeline/activity history"
            }
            @{
                Path  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
                Name  = "PublishUserActivities"
                Value = 0
                Type  = "DWord"
                Desc  = "Disable publishing user activities"
            }
        )

        # Aggressive-only registry tweaks
        if ($DebloatProfile -eq "Aggressive") {
            $registryTweaks += @(
                @{
                    Path  = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"
                    Name  = "BingSearchEnabled"
                    Value = 0
                    Type  = "DWord"
                    Desc  = "Disable Bing search in Start Menu"
                }
                @{
                    Path  = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                    Name  = "RotatingLockScreenOverlayEnabled"
                    Value = 0
                    Type  = "DWord"
                    Desc  = "Disable lock screen spotlight"
                }
                @{
                    Path  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
                    Name  = "DisabledByGroupPolicy"
                    Value = 1
                    Type  = "DWord"
                    Desc  = "Disable advertising ID"
                }
            )
        }

        # Version-specific registry tweaks (auto-detected)
        $osInfo = Get-WindowsDebloatInfo

        # Win11 22H2+ (build 22621+): disable additional telemetry
        if ($osInfo.Build -ge 22621) {
            $registryTweaks += @(
                @{
                    Path  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
                    Name  = "AllowTelemetry"
                    Value = 0
                    Type  = "DWord"
                    Desc  = "Minimize diagnostic data (Win11 22H2+)"
                }
                @{
                    Path  = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                    Name  = "SubscribedContent-338389Enabled"
                    Value = 0
                    Type  = "DWord"
                    Desc  = "Disable suggested content in Settings (Win11)"
                }
            )
        }

        # Win11 24H2+ (build 26100+): Copilot, Recall, AI
        if ($osInfo.Build -ge 26100) {
            $registryTweaks += @(
                @{
                    Path  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
                    Name  = "TurnOffWindowsCopilot"
                    Value = 1
                    Type  = "DWord"
                    Desc  = "Disable Copilot system-wide (24H2+ policy)"
                }
                @{
                    Path  = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                    Name  = "ShowCopilotButton"
                    Value = 0
                    Type  = "DWord"
                    Desc  = "Hide Copilot button from taskbar (24H2+)"
                }
            )
        }

        # Win11 25H2+ / 26H2+ (build 26200+): Recall, AI features
        if ($osInfo.Build -ge 26200) {
            $registryTweaks += @(
                @{
                    Path  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
                    Name  = "DisableAIDataAnalysis"
                    Value = 1
                    Type  = "DWord"
                    Desc  = "Disable Windows Recall AI analysis (25H2+)"
                }
                @{
                    Path  = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                    Name  = "RecallEnabled"
                    Value = 0
                    Type  = "DWord"
                    Desc  = "Disable Recall timeline snapshots (25H2+)"
                }
            )
        }

        # Win10 specific: disable Cortana and web search
        if ($osInfo.IsWin10) {
            $registryTweaks += @(
                @{
                    Path  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
                    Name  = "AllowCortana"
                    Value = 0
                    Type  = "DWord"
                    Desc  = "Disable Cortana (Win10)"
                }
                @{
                    Path  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
                    Name  = "DisableWebSearch"
                    Value = 1
                    Type  = "DWord"
                    Desc  = "Disable web search results in Start (Win10)"
                }
            )
        }

        # Startup bloat: Edge, OneDrive (Standard+)
        $registryTweaks += @(
            @{
                Path  = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
                Name  = "StartupBoostEnabled"
                Value = 0
                Type  = "DWord"
                Desc  = "Disable Edge startup boost (background process)"
            }
            @{
                Path  = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
                Name  = "HubsSidebarEnabled"
                Value = 0
                Type  = "DWord"
                Desc  = "Disable Edge sidebar"
            }
            @{
                Path  = "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive"
                Name  = "PreventNetworkTrafficPreUserSignIn"
                Value = 1
                Type  = "DWord"
                Desc  = "Prevent OneDrive from generating network traffic before sign-in"
            }
        )

        foreach ($tweak in $registryTweaks) {
            # Check current value
            $currentValue = $null
            $exists = $false
            if (Test-Path -LiteralPath $tweak.Path) {
                $currentValue = (Get-ItemProperty -LiteralPath $tweak.Path -Name $tweak.Name -ErrorAction SilentlyContinue).$($tweak.Name)
                if ($null -ne $currentValue) { $exists = $true }
            }

            if ($exists -and $currentValue -eq $tweak.Value) {
                Write-OutputColor "  [SKIP] $($tweak.Desc) — already set" -color "Debug"
                $skippedCount++
                continue
            }

            if ($PreviewOnly) {
                Write-OutputColor "  [WOULD SET] $($tweak.Desc)" -color "Info"
                $removed++
                continue
            }

            try {
                if (-not (Test-Path -LiteralPath $tweak.Path)) {
                    New-Item -Path $tweak.Path -Force -ErrorAction Stop | Out-Null
                }
                $previousValue = $currentValue
                $previousExists = $exists
                Set-ItemProperty -LiteralPath $tweak.Path -Name $tweak.Name -Value $tweak.Value -Type $tweak.Type -Force -ErrorAction Stop
                Write-OutputColor "  [SET] $($tweak.Desc)" -color "Success"
                $removed++

                Add-SessionChange -Category "Debloat" -Description "Registry: $($tweak.Desc)"

                $regPath = $tweak.Path
                $regName = $tweak.Name
                $regPrevious = $previousValue
                $regExisted = $previousExists
                Add-UndoAction -Category "Debloat" -Description "Registry: $($tweak.Desc)" -UndoScript {
                    param($RegPath, $RegName, $RegPrevious, $RegExisted)
                    if ($RegExisted) {
                        Set-ItemProperty -LiteralPath $RegPath -Name $RegName -Value $RegPrevious -Force -ErrorAction SilentlyContinue
                    }
                    else {
                        Remove-ItemProperty -LiteralPath $RegPath -Name $RegName -Force -ErrorAction SilentlyContinue
                    }
                } -UndoParams @{ RegPath = $regPath; RegName = $regName; RegPrevious = $regPrevious; RegExisted = $regExisted }
            }
            catch {
                Write-OutputColor "  [FAILED] $($tweak.Desc) — $_" -color "Error"
                $failedCount++
            }
        }
        Write-OutputColor "" -color "Info"
    }

    # ── Phase 5: Startup Item Cleanup (Standard and Aggressive) ───────
    if ($DebloatProfile -eq "Standard" -or $DebloatProfile -eq "Aggressive") {
        Write-OutputColor "  ── Startup Item Cleanup ───────────────────────────────────────────" -color "Info"

        # Known bloatware startup entries to auto-disable
        $startupPatterns = @(
            @{ Pattern = "OneDrive";          Desc = "OneDrive auto-start" }
            @{ Pattern = "OneDriveSetup";     Desc = "OneDrive setup" }
            @{ Pattern = "Teams";             Desc = "Teams auto-start" }
            @{ Pattern = "com.squirrel";      Desc = "Teams updater (Squirrel)" }
            @{ Pattern = "MicrosoftEdge";     Desc = "Edge auto-start" }
            @{ Pattern = "CortanaStartup";    Desc = "Cortana startup" }
            @{ Pattern = "SecurityHealth";    Desc = "Security Center notification" }
        )

        $runKeys = @(
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        )

        foreach ($runKey in $runKeys) {
            if (-not (Test-Path -LiteralPath $runKey)) { continue }
            $entries = Get-ItemProperty -LiteralPath $runKey -ErrorAction SilentlyContinue
            if ($null -eq $entries) { continue }

            foreach ($prop in $entries.PSObject.Properties) {
                if ($prop.Name -like "PS*") { continue }  # Skip PS-added metadata properties

                foreach ($bloat in $startupPatterns) {
                    if ($prop.Name -match $bloat.Pattern -or $prop.Value -match $bloat.Pattern) {
                        if ($PreviewOnly) {
                            Write-OutputColor "  [WOULD REMOVE] $($bloat.Desc): $($prop.Name)" -color "Info"
                            $removed++
                        } else {
                            try {
                                $prevValue = $prop.Value
                                $prevName  = $prop.Name
                                $prevKey   = $runKey
                                Remove-ItemProperty -LiteralPath $runKey -Name $prop.Name -Force -ErrorAction Stop
                                Write-OutputColor "  [REMOVED] $($bloat.Desc): $($prop.Name)" -color "Success"
                                $removed++
                                Add-SessionChange -Category "Debloat" -Description "Removed startup item: $($prop.Name)"
                                # Register undo. Prior to v1.98.8 $prevValue was captured but no
                                # Add-UndoAction was emitted — startup items were silently un-recoverable.
                                Add-UndoAction -Category "Debloat" -Description "Removed startup entry $($prop.Name)" -UndoScript {
                                    param($RegKey, $EntryName, $EntryValue)
                                    New-ItemProperty -LiteralPath $RegKey -Name $EntryName -Value $EntryValue -Force -ErrorAction SilentlyContinue | Out-Null
                                } -UndoParams @{ RegKey = $prevKey; EntryName = $prevName; EntryValue = $prevValue }
                            }
                            catch {
                                Write-OutputColor "  [FAILED] $($bloat.Desc): $_" -color "Error"
                                $failedCount++
                            }
                        }
                        break  # Don't match same entry against multiple patterns
                    }
                }
            }
        }

        Write-OutputColor "" -color "Info"
    }

    # ── Summary ───────────────────────────────────────────────────────
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  WORKSTATION DEBLOAT SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    $modeLabel = if ($PreviewOnly) { "Preview" } else { "Applied" }
    Write-OutputColor "  │$("  Profile:  $DebloatProfile".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Mode:     $modeLabel".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Changed:  $removed".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Skipped:  $skippedCount".PadRight(72))│" -color "Debug"
    Write-OutputColor "  │$("  Failed:   $failedCount".PadRight(72))│" -color $(if ($failedCount -gt 0) { "Error" } else { "Debug" })
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

# ════════════════════════════════════════════════════════════════════════
# Server Debloat
# ════════════════════════════════════════════════════════════════════════
function Invoke-ServerDebloat {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet("Light","Standard","Aggressive")]
        [string]$DebloatProfile,

        [switch]$PreviewOnly
    )

    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                        SERVER DEBLOAT [$DebloatProfile]").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($PreviewOnly) {
        Write-OutputColor "  *** PREVIEW MODE — No changes will be made ***" -color "Warning"
        Write-OutputColor "" -color "Info"
    }

    $changed = 0
    $skippedCount = 0
    $failedCount = 0

    # ── Phase 1: Telemetry Scheduled Tasks ────────────────────────────
    Write-OutputColor "  ── Telemetry Scheduled Tasks ─────────────────────────────────────" -color "Info"
    $telemetryTasks = Get-TelemetryTasks

    foreach ($task in $telemetryTasks) {
        if ($task.State -eq "Disabled") {
            Write-OutputColor "  [SKIP] $($task.TaskName) — already disabled" -color "Debug"
            $skippedCount++
            continue
        }

        if ($PreviewOnly) {
            Write-OutputColor "  [WOULD DISABLE] $($task.TaskPath)$($task.TaskName)" -color "Info"
            $changed++
            continue
        }

        try {
            $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null
            Write-OutputColor "  [DISABLED] $($task.TaskName)" -color "Success"
            $changed++
            Add-SessionChange -Category "Debloat" -Description "Disabled task: $($task.TaskName)"

            $taskPathCapture = $task.TaskPath
            $taskNameCapture = $task.TaskName
            Add-UndoAction -Category "Debloat" -Description "Disabled task $($task.TaskName)" -UndoScript {
                param($TaskPath, $TaskName)
                Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue |
                    Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
            } -UndoParams @{ TaskPath = $taskPathCapture; TaskName = $taskNameCapture }
        }
        catch {
            Write-OutputColor "  [FAILED] $($task.TaskName) — $_" -color "Error"
            $failedCount++
        }
    }

    Write-OutputColor "" -color "Info"

    # ── Phase 2: Xbox AppxPackages (Light) ────────────────────────────
    Write-OutputColor "  ── AppxPackage Removal ────────────────────────────────────────────" -color "Info"
    $serverPackages = @(
        "Microsoft.XboxGamingOverlay"
        "Microsoft.XboxIdentityProvider"
        "Microsoft.XboxSpeechToTextOverlay"
        "Microsoft.XboxGameOverlay"
        "Microsoft.Xbox.TCUI"
    )

    # Short-circuit on Server Core — Get-AppxPackage / Get-AppxProvisionedPackage aren't
    # registered, so without this skip the transcript fills with "term is not recognized"
    # errors for every package candidate. Matches the Workstation flow gate at line 463.
    $debloatInfo = Get-WindowsDebloatInfo
    if ($null -ne $debloatInfo -and $debloatInfo.IsServerCore) {
        Write-OutputColor "  [SKIP] AppX phase — Server Core has no Appx subsystem" -color "Debug"
        $skippedCount += $serverPackages.Count
        $serverPackages = @()
    }

    foreach ($pkgName in $serverPackages) {
        $installed = Get-AppxPackage -Name "*$pkgName*" -AllUsers -ErrorAction SilentlyContinue
        $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$pkgName*" }

        if ($null -eq $installed -and $null -eq $provisioned) {
            Write-OutputColor "  [SKIP] $pkgName — not installed" -color "Debug"
            $skippedCount++
            continue
        }

        if ($PreviewOnly) {
            Write-OutputColor "  [WOULD REMOVE] $pkgName" -color "Info"
            $changed++
            continue
        }

        try {
            if ($null -ne $installed) {
                $installed | Remove-AppxPackage -AllUsers -ErrorAction Stop
            }
            if ($null -ne $provisioned) {
                $provisioned | Remove-AppxProvisionedPackage -Online -ErrorAction Stop | Out-Null
            }
            Write-OutputColor "  [REMOVED] $pkgName" -color "Success"
            $changed++
            Add-SessionChange -Category "Debloat" -Description "Removed AppxPackage: $pkgName"
        }
        catch {
            Write-OutputColor "  [FAILED] $pkgName — $_" -color "Error"
            $failedCount++
        }
    }

    Write-OutputColor "" -color "Info"

    # ── Phase 3: Service Optimization ─────────────────────────────────
    Write-OutputColor "  ── Service Optimization ──────────────────────────────────────────" -color "Info"
    $serviceList = Get-DisableableServices -Type "Server" -DebloatProfile $DebloatProfile

    # Deduplicate by service name (Aggressive adds DiagTrack again)
    $seenServices = @{}
    $uniqueServices = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($svcInfo in $serviceList) {
        if (-not $seenServices.ContainsKey($svcInfo.Name)) {
            $seenServices[$svcInfo.Name] = $true
            $uniqueServices.Add($svcInfo)
        }
    }

    foreach ($svcInfo in $uniqueServices) {
        # Print server check. The default Shared-only filter misses local-only print queues
        # (MFP scan-to-folder workflows, ERP virtual printers). Widen to ANY printer + registry
        # hive to be safe — false-positive skip is better than killing a vendor scanner pipeline.
        if ($svcInfo.CheckPrintServer) {
            $anyPrinters = @(Get-Printer -ErrorAction SilentlyContinue)
            $printerRegEntries = @()
            try {
                $printerRegEntries = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers' -ErrorAction SilentlyContinue |
                    Where-Object { $_.PSChildName -notmatch '^(Microsoft|Fax|OneNote|PDF)' })
            } catch { }
            if ($anyPrinters.Count -gt 0 -or $printerRegEntries.Count -gt 0) {
                Write-OutputColor "  [SKIP] $($svcInfo.DisplayName) — $($anyPrinters.Count) printer(s) + $($printerRegEntries.Count) reg-only" -color "Debug"
                $skippedCount++
                continue
            }
        }

        # Bluetooth hardware check
        if ($svcInfo.CheckBluetooth) {
            $btDevice = Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $btDevice) {
                Write-OutputColor "  [SKIP] $($svcInfo.DisplayName) — Bluetooth hardware present" -color "Debug"
                $skippedCount++
                continue
            }
        }

        $svc = Get-Service -Name $svcInfo.Name -ErrorAction SilentlyContinue
        if ($null -eq $svc) {
            Write-OutputColor "  [SKIP] $($svcInfo.DisplayName) — service not found" -color "Debug"
            $skippedCount++
            continue
        }

        # Dependent-service cascade check (same as workstation path). Disabling a service with
        # running dependents triggers Stop-Service -Force to cascade-stop them; on a production
        # server this can break WSUS (BITS), backup software (BITS/VSS), file-server tooling
        # (LanmanServer dependents). Refuse if any running dependent exists.
        $runningDependents = @(Get-Service -Name $svcInfo.Name -DependentServices -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' })
        if ($runningDependents.Count -gt 0) {
            Write-OutputColor "  [SKIP] $($svcInfo.DisplayName) — $($runningDependents.Count) running dependent service(s):" -color "Debug"
            foreach ($d in ($runningDependents | Select-Object -First 5)) {
                Write-OutputColor "         - $($d.DisplayName) ($($d.Name))" -color "Debug"
            }
            $skippedCount++
            continue
        }

        if ($svc.StartType -eq "Disabled") {
            Write-OutputColor "  [SKIP] $($svcInfo.DisplayName) — already disabled" -color "Debug"
            $skippedCount++
            continue
        }

        if ($null -ne $svcInfo.Warning) {
            Write-OutputColor "  NOTE: $($svcInfo.Warning)" -color "Warning"
        }

        if ($PreviewOnly) {
            Write-OutputColor "  [WOULD DISABLE] $($svcInfo.DisplayName) (currently: $($svc.Status)/$($svc.StartType))" -color "Info"
            $changed++
            continue
        }

        try {
            $originalStartType = $svc.StartType.ToString()

            if ($svc.Status -eq "Running") {
                Stop-Service -Name $svcInfo.Name -Force -ErrorAction Stop
            }
            Set-Service -Name $svcInfo.Name -StartupType Disabled -ErrorAction Stop

            Write-OutputColor "  [DISABLED] $($svcInfo.DisplayName) (was: $originalStartType)" -color "Success"
            $changed++

            Add-SessionChange -Category "Debloat" -Description "Disabled service: $($svcInfo.DisplayName)"
            Clear-MenuCache

            $svcNameCapture = $svcInfo.Name
            $startTypeCapture = $originalStartType
            Add-UndoAction -Category "Debloat" -Description "Disabled service $($svcInfo.DisplayName)" -UndoScript {
                param($SvcName, $StartType)
                Set-Service -Name $SvcName -StartupType $StartType -ErrorAction SilentlyContinue
                if ($StartType -eq "Automatic") {
                    Start-Service -Name $SvcName -ErrorAction SilentlyContinue
                }
            } -UndoParams @{ SvcName = $svcNameCapture; StartType = $startTypeCapture }
        }
        catch {
            Write-OutputColor "  [FAILED] $($svcInfo.DisplayName) — $_" -color "Error"
            $failedCount++
        }
    }

    Write-OutputColor "" -color "Info"

    # ── Phase 4: Optional Features (Standard and Aggressive) ──────────
    if ($DebloatProfile -eq "Standard" -or $DebloatProfile -eq "Aggressive") {
        Write-OutputColor "  ── Optional Features ─────────────────────────────────────────────" -color "Info"

        $featuresToRemove = @()

        # Standard: SMB1
        $featuresToRemove += @{
            Name = "FS-SMB1"
            Desc = "SMB v1 Protocol (security risk)"
            CmdletType = "WindowsFeature"
        }

        # Aggressive extras
        if ($DebloatProfile -eq "Aggressive") {
            $featuresToRemove += @{
                Name = "Internet-Explorer-Optional-amd64"
                Desc = "Internet Explorer 11"
                CmdletType = "OptionalFeature"
            }
            $featuresToRemove += @{
                Name = "MicrosoftWindowsPowerShellV2Root"
                Desc = "PowerShell v2 Engine (security risk)"
                CmdletType = "OptionalFeature"
            }
        }

        # Registry: Disable Server Manager auto-start (Standard+)
        $smRegPath = "HKLM:\SOFTWARE\Microsoft\ServerManager"
        $smCurrent = (Get-ItemProperty -LiteralPath $smRegPath -Name "DoNotOpenServerManagerAtLogon" -ErrorAction SilentlyContinue).DoNotOpenServerManagerAtLogon
        if ($smCurrent -eq 1) {
            Write-OutputColor "  [SKIP] Server Manager auto-start — already disabled" -color "Debug"
            $skippedCount++
        }
        elseif ($PreviewOnly) {
            Write-OutputColor "  [WOULD SET] Disable Server Manager auto-start at logon" -color "Info"
            $changed++
        }
        else {
            try {
                Set-ItemProperty -LiteralPath $smRegPath -Name "DoNotOpenServerManagerAtLogon" -Value 1 -Type DWord -Force -ErrorAction Stop
                Write-OutputColor "  [SET] Server Manager auto-start disabled" -color "Success"
                $changed++
                Add-SessionChange -Category "Debloat" -Description "Disabled Server Manager auto-start"

                $prevSMValue = $smCurrent
                Add-UndoAction -Category "Debloat" -Description "Disabled Server Manager auto-start" -UndoScript {
                    param($PrevValue)
                    if ($null -ne $PrevValue) {
                        Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\ServerManager" -Name "DoNotOpenServerManagerAtLogon" -Value $PrevValue -Force -ErrorAction SilentlyContinue
                    }
                    else {
                        Remove-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\ServerManager" -Name "DoNotOpenServerManagerAtLogon" -Force -ErrorAction SilentlyContinue
                    }
                } -UndoParams @{ PrevValue = $prevSMValue }
            }
            catch {
                Write-OutputColor "  [FAILED] Server Manager auto-start — $_" -color "Error"
                $failedCount++
            }
        }

        foreach ($feature in $featuresToRemove) {
            if ($feature.CmdletType -eq "WindowsFeature") {
                # Server features via Get-WindowsFeature
                $wf = Get-WindowsFeature -Name $feature.Name -ErrorAction SilentlyContinue
                if ($null -eq $wf) {
                    Write-OutputColor "  [SKIP] $($feature.Desc) — feature not available" -color "Debug"
                    $skippedCount++
                    continue
                }
                if (-not $wf.Installed) {
                    Write-OutputColor "  [SKIP] $($feature.Desc) — not installed" -color "Debug"
                    $skippedCount++
                    continue
                }

                if ($PreviewOnly) {
                    Write-OutputColor "  [WOULD REMOVE] $($feature.Desc)" -color "Info"
                    $changed++
                    continue
                }

                try {
                    $null = Remove-WindowsFeature -Name $feature.Name -ErrorAction Stop
                    Write-OutputColor "  [REMOVED] $($feature.Desc)" -color "Success"
                    $changed++
                    Add-SessionChange -Category "Debloat" -Description "Removed feature: $($feature.Desc)"
                    # Features can be re-added but no automatic undo — note for user
                }
                catch {
                    Write-OutputColor "  [FAILED] $($feature.Desc) — $_" -color "Error"
                    $failedCount++
                }
            }
            elseif ($feature.CmdletType -eq "OptionalFeature") {
                $of = Get-WindowsOptionalFeature -Online -FeatureName $feature.Name -ErrorAction SilentlyContinue
                if ($null -eq $of) {
                    Write-OutputColor "  [SKIP] $($feature.Desc) — feature not available" -color "Debug"
                    $skippedCount++
                    continue
                }
                if ($of.State -ne "Enabled") {
                    Write-OutputColor "  [SKIP] $($feature.Desc) — not enabled" -color "Debug"
                    $skippedCount++
                    continue
                }

                if ($PreviewOnly) {
                    Write-OutputColor "  [WOULD DISABLE] $($feature.Desc)" -color "Info"
                    $changed++
                    continue
                }

                try {
                    $null = Disable-WindowsOptionalFeature -Online -FeatureName $feature.Name -NoRestart -ErrorAction Stop
                    Write-OutputColor "  [DISABLED] $($feature.Desc) (reboot may be required)" -color "Success"
                    $changed++
                    Add-SessionChange -Category "Debloat" -Description "Disabled optional feature: $($feature.Desc)"

                    $featureNameCapture = $feature.Name
                    Add-UndoAction -Category "Debloat" -Description "Disabled feature $($feature.Desc)" -UndoScript {
                        param($FeatureName)
                        Enable-WindowsOptionalFeature -Online -FeatureName $FeatureName -NoRestart -ErrorAction SilentlyContinue | Out-Null
                    } -UndoParams @{ FeatureName = $featureNameCapture }
                }
                catch {
                    Write-OutputColor "  [FAILED] $($feature.Desc) — $_" -color "Error"
                    $failedCount++
                }
            }
        }

        Write-OutputColor "" -color "Info"
    }

    # ── Phase 5: Aggressive telemetry task sweep ──────────────────────
    if ($DebloatProfile -eq "Aggressive") {
        Write-OutputColor "  ── Extended Telemetry Task Sweep ─────────────────────────────────" -color "Info"

        $extraPaths = @(
            "\Microsoft\Windows\AppID\"
            "\Microsoft\Windows\NetTrace\"
            "\Microsoft\Windows\PI\"
            "\Microsoft\Windows\WindowsUpdate\"
        )

        foreach ($extraPath in $extraPaths) {
            try {
                $extraTasks = @(Get-ScheduledTask -TaskPath $extraPath -ErrorAction SilentlyContinue | Where-Object { $_.State -ne "Disabled" })
                foreach ($task in $extraTasks) {
                    if ($PreviewOnly) {
                        Write-OutputColor "  [WOULD DISABLE] $($task.TaskPath)$($task.TaskName)" -color "Info"
                        $changed++
                        continue
                    }

                    try {
                        $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null
                        Write-OutputColor "  [DISABLED] $($task.TaskName)" -color "Success"
                        $changed++
                        Add-SessionChange -Category "Debloat" -Description "Disabled task: $($task.TaskName)"

                        $taskPathCap = $task.TaskPath
                        $taskNameCap = $task.TaskName
                        Add-UndoAction -Category "Debloat" -Description "Disabled task $($task.TaskName)" -UndoScript {
                            param($TaskPath, $TaskName)
                            Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue |
                                Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
                        } -UndoParams @{ TaskPath = $taskPathCap; TaskName = $taskNameCap }
                    }
                    catch {
                        Write-OutputColor "  [FAILED] $($task.TaskName) — $_" -color "Error"
                        $failedCount++
                    }
                }
            }
            catch {
                # Path may not exist
            }
        }

        Write-OutputColor "" -color "Info"
    }

    # ── Summary ───────────────────────────────────────────────────────
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SERVER DEBLOAT SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    $modeLabel = if ($PreviewOnly) { "Preview" } else { "Applied" }
    Write-OutputColor "  │$("  Profile:  $DebloatProfile".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Mode:     $modeLabel".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Changed:  $changed".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Skipped:  $skippedCount".PadRight(72))│" -color "Debug"
    Write-OutputColor "  │$("  Failed:   $failedCount".PadRight(72))│" -color $(if ($failedCount -gt 0) { "Error" } else { "Debug" })
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

# ════════════════════════════════════════════════════════════════════════
# Quick Scan / Preview Analysis
# ════════════════════════════════════════════════════════════════════════
function Show-DebloatAnalysis {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                        SYSTEM DEBLOAT ANALYSIS").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Scanning system..." -color "Info"
    Write-OutputColor "" -color "Info"

    # Detect OS type via the canonical helper (ProductType) rather than the Caption string,
    # which is partially localized on non-EN MUI and can mis-classify future SKUs.
    $analysisInfo = Get-WindowsDebloatInfo
    $isServer = $analysisInfo.IsServer

    # ── Removable AppxPackages ────────────────────────────────────────
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  REMOVABLE APPX PACKAGES".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $allPackageNames = Get-RemovableAppxPackages -DebloatProfile "Aggressive"
    $removableCount = 0
    $totalPackageSize = [long]0

    foreach ($pkgName in $allPackageNames) {
        $installed = Get-AppxPackage -Name "*$pkgName*" -AllUsers -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $installed) {
            $sizeStr = ""
            if ($null -ne $installed.InstallLocation -and (Test-Path -LiteralPath $installed.InstallLocation -ErrorAction SilentlyContinue)) {
                try {
                    $pkgSize = [long](Get-ChildItem -LiteralPath $installed.InstallLocation -Recurse -Force -File -ErrorAction SilentlyContinue |
                        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    $totalPackageSize += $pkgSize
                    $sizeStr = " ($([math]::Round($pkgSize/1MB, 1)) MB)"
                }
                catch {
                    $sizeStr = ""
                }
            }

            $displayName = $installed.Name
            if ($displayName.Length -gt 50) { $displayName = $displayName.Substring(0, 47) + "..." }
            Write-OutputColor "  │$("  [x] $displayName$sizeStr".PadRight(72))│" -color "Warning"
            $removableCount++
        }
    }

    if ($removableCount -eq 0) {
        Write-OutputColor "  │$("  No removable AppxPackages found.".PadRight(72))│" -color "Success"
    }
    else {
        Write-OutputColor "  │$("  ─────────────────────────────────────────".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  $removableCount package(s), ~$([math]::Round($totalPackageSize/1MB, 1)) MB".PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # ── Disableable Services ──────────────────────────────────────────
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  DISABLEABLE SERVICES".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $svcType = if ($isServer) { "Server" } else { "Workstation" }
    $candidateServices = Get-DisableableServices -Type $svcType -DebloatProfile "Aggressive"

    # Deduplicate
    $seenSvc = @{}
    $disableableCount = 0

    foreach ($svcInfo in $candidateServices) {
        if ($seenSvc.ContainsKey($svcInfo.Name)) { continue }
        $seenSvc[$svcInfo.Name] = $true

        $svc = Get-Service -Name $svcInfo.Name -ErrorAction SilentlyContinue
        if ($null -eq $svc) { continue }

        $status = $svc.Status.ToString()
        $startType = $svc.StartType.ToString()
        $stateTag = "$status/$startType"

        if ($startType -eq "Disabled") {
            Write-OutputColor "  │$("  [=] $($svcInfo.DisplayName) [$stateTag]".PadRight(72))│" -color "Debug"
        }
        else {
            Write-OutputColor "  │$("  [x] $($svcInfo.DisplayName) [$stateTag]".PadRight(72))│" -color "Warning"
            $disableableCount++
        }
    }

    Write-OutputColor "  │$("  ─────────────────────────────────────────".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  $disableableCount service(s) could be disabled".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # ── Telemetry Scheduled Tasks ─────────────────────────────────────
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  TELEMETRY SCHEDULED TASKS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $telemetryTasks = Get-TelemetryTasks
    $enabledTaskCount = 0

    foreach ($task in $telemetryTasks) {
        $stateTag = $task.State.ToString()
        $displayLine = "$($task.TaskName) [$stateTag]"
        if ($displayLine.Length -gt 68) { $displayLine = $displayLine.Substring(0, 65) + "..." }

        if ($task.State -eq "Disabled") {
            Write-OutputColor "  │$("  [=] $displayLine".PadRight(72))│" -color "Debug"
        }
        else {
            Write-OutputColor "  │$("  [x] $displayLine".PadRight(72))│" -color "Warning"
            $enabledTaskCount++
        }
    }

    if (@($telemetryTasks).Count -eq 0) {
        Write-OutputColor "  │$("  No telemetry tasks found.".PadRight(72))│" -color "Success"
    }
    else {
        Write-OutputColor "  │$("  ─────────────────────────────────────────".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  $enabledTaskCount task(s) could be disabled".PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # ── Optional Features (Server only) ───────────────────────────────
    if ($isServer) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  REMOVABLE OPTIONAL FEATURES".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        $featureChecks = @(
            @{ Name = "FS-SMB1"; Desc = "SMB v1 Protocol"; Type = "WindowsFeature" }
            @{ Name = "Internet-Explorer-Optional-amd64"; Desc = "Internet Explorer"; Type = "OptionalFeature" }
            @{ Name = "MicrosoftWindowsPowerShellV2Root"; Desc = "PowerShell v2 Engine"; Type = "OptionalFeature" }
        )

        $removableFeatureCount = 0
        foreach ($fc in $featureChecks) {
            if ($fc.Type -eq "WindowsFeature") {
                $wf = Get-WindowsFeature -Name $fc.Name -ErrorAction SilentlyContinue
                if ($null -ne $wf -and $wf.Installed) {
                    Write-OutputColor "  │$("  [x] $($fc.Desc) — installed".PadRight(72))│" -color "Warning"
                    $removableFeatureCount++
                }
                elseif ($null -ne $wf) {
                    Write-OutputColor "  │$("  [=] $($fc.Desc) — not installed".PadRight(72))│" -color "Debug"
                }
            }
            else {
                $of = Get-WindowsOptionalFeature -Online -FeatureName $fc.Name -ErrorAction SilentlyContinue
                if ($null -ne $of -and $of.State -eq "Enabled") {
                    Write-OutputColor "  │$("  [x] $($fc.Desc) — enabled".PadRight(72))│" -color "Warning"
                    $removableFeatureCount++
                }
                elseif ($null -ne $of) {
                    Write-OutputColor "  │$("  [=] $($fc.Desc) — disabled".PadRight(72))│" -color "Debug"
                }
            }
        }

        Write-OutputColor "  │$("  ─────────────────────────────────────────".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  $removableFeatureCount feature(s) could be removed".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
    }

    # ── Impact Summary ────────────────────────────────────────────────
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  ESTIMATED IMPACT SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $ssdStatus = if (Test-SSDPresent) { "SSD (SysMain safe to disable)" } else { "HDD (keep SysMain enabled)" }
    Write-OutputColor "  │$("  System Drive:          $ssdStatus".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Removable Packages:    $removableCount ($([math]::Round($totalPackageSize/1MB, 1)) MB)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Disableable Services:  $disableableCount".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Telemetry Tasks:       $enabledTaskCount".PadRight(72))│" -color "Info"

    $totalItems = $removableCount + $disableableCount + $enabledTaskCount
    $impactColor = if ($totalItems -eq 0) { "Success" } elseif ($totalItems -lt 10) { "Info" } else { "Warning" }

    # Estimate total space savings (packages + temp files + WinSxS potential)
    $estSavingsMB = [math]::Round($totalPackageSize / 1MB, 0)
    $estSavingsMB += 200  # Conservative estimate for telemetry/cache cleanup
    $estDisplay = if ($estSavingsMB -ge 1024) { "$([math]::Round($estSavingsMB / 1024, 1)) GB" } else { "$estSavingsMB MB" }

    Write-OutputColor "  │$("  ─────────────────────────────────────────".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Total actionable items: $totalItems".PadRight(72))│" -color $impactColor
    Write-OutputColor "  │$("  Estimated space savings: ~$estDisplay".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    # Return structured report for JSON output mode
    $osTypeValue = 'Workstation'
    if ($isServer) { $osTypeValue = 'Server' }
    $debloatReport = @{
        OSType              = $osTypeValue
        RemovablePackages   = $removableCount
        PackageSizeMB       = [math]::Round($totalPackageSize / 1MB, 1)
        DisableableServices = $disableableCount
        TelemetryTasks      = $enabledTaskCount
        TotalActionable     = $totalItems
    }
    return $debloatReport
}

# ════════════════════════════════════════════════════════════════════════
# Custom Debloat — pick individual categories
# ════════════════════════════════════════════════════════════════════════
function Invoke-CustomDebloat {
    # Track which categories are selected
    $selected = @{
        AppxPackages   = $false
        Services       = $false
        Tasks          = $false
        Registry       = $false
        Features       = $false
        Startup        = $false
    }

    while ($true) {
        if ($global:ReturnToMainMenu) { return }

        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                          CUSTOM DEBLOAT").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  Select categories to include, then [G] to apply." -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  CATEGORY SELECTION".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        $tag1 = if ($selected.AppxPackages) { "X" } else { " " }
        $tag2 = if ($selected.Services) { "X" } else { " " }
        $tag3 = if ($selected.Tasks) { "X" } else { " " }
        $tag4 = if ($selected.Registry) { "X" } else { " " }
        $tag5 = if ($selected.Features) { "X" } else { " " }
        $tag6 = if ($selected.Startup) { "X" } else { " " }

        Write-MenuItem -Text "[1]  [$tag1] AppxPackage Removal"
        Write-MenuItem -Text "[2]  [$tag2] Service Optimization"
        Write-MenuItem -Text "[3]  [$tag3] Scheduled Task Cleanup"
        Write-MenuItem -Text "[4]  [$tag4] Registry Tweaks"
        Write-MenuItem -Text "[5]  [$tag5] Optional Features"
        Write-MenuItem -Text "[6]  [$tag6] Startup Programs"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        $selectedCount = @($selected.Values | Where-Object { $_ -eq $true }).Count
        Write-OutputColor "  $selectedCount category(ies) selected" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [A] Select All    [G] Go (apply selected)    [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice.ToUpper()) {
            "1" { $selected.AppxPackages = -not $selected.AppxPackages }
            "2" { $selected.Services = -not $selected.Services }
            "3" { $selected.Tasks = -not $selected.Tasks }
            "4" { $selected.Registry = -not $selected.Registry }
            "5" { $selected.Features = -not $selected.Features }
            "6" { $selected.Startup = -not $selected.Startup }
            "A" {
                $allTrue = @($selected.Values | Where-Object { $_ -eq $true }).Count -eq $selected.Count
                $newVal = -not $allTrue
                $selected.AppxPackages = $newVal
                $selected.Services = $newVal
                $selected.Tasks = $newVal
                $selected.Registry = $newVal
                $selected.Features = $newVal
                $selected.Startup = $newVal
            }
            "G" {
                $activeCount = @($selected.Values | Where-Object { $_ -eq $true }).Count
                if ($activeCount -eq 0) {
                    Write-OutputColor "  No categories selected." -color "Warning"
                    Start-Sleep -Milliseconds 800
                    continue
                }

                # Select profile for the operations
                $selectedProfile = Select-DebloatProfile
                if ($null -eq $selectedProfile) { continue }

                if (-not (Confirm-UserAction -Message "  Apply $activeCount category(ies) with $selectedProfile profile?")) {
                    Write-OutputColor "  Cancelled." -color "Info"
                    Start-Sleep -Milliseconds 800
                    continue
                }

                Invoke-CustomDebloatExecution -Selected $selected -DebloatProfile $selectedProfile
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Press Enter to continue..." -color "Info"
                Read-Host | Out-Null
            }
            "B" { return }
            default {
                Write-OutputColor "  Invalid selection." -color "Warning"
                Start-Sleep -Milliseconds 800
            }
        }
    }
}

# ────────────────────────────────────────────────────────────────────────
# Execute custom debloat based on selected categories
# ────────────────────────────────────────────────────────────────────────
function Invoke-CustomDebloatExecution {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Selected,

        [Parameter(Mandatory=$true)]
        [ValidateSet("Light","Standard","Aggressive")]
        [string]$DebloatProfile
    )

    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    CUSTOM DEBLOAT EXECUTION [$DebloatProfile]").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Use Get-WindowsDebloatInfo for SKU detection (mirrors the rest of the module). The
    # prior `$osCaption -match "Server"` bypassed the canonical detection and would silently
    # mis-classify on a future SKU where the Caption text changes or gets localized.
    $debloatInfo = Get-WindowsDebloatInfo
    $isServer = $debloatInfo.IsServer
    $isServerCore = $debloatInfo.IsServerCore
    $svcType = if ($isServer) { "Server" } else { "Workstation" }

    $totalChanged = 0
    $totalSkipped = 0
    $totalFailed = 0

    # ── AppxPackage Removal ───────────────────────────────────────────
    if ($Selected.AppxPackages -and -not $isServerCore) {
        Write-OutputColor "  ── AppxPackage Removal ────────────────────────────────────────────" -color "Info"
        $packages = Get-RemovableAppxPackages -DebloatProfile $DebloatProfile

        # Custom Aggressive used to silently remove Edge / OneDrive / Teams without the extra
        # confirmation that the Workstation flow has — operators picking "Custom + Aggressive"
        # didn't get the chance to opt out. Mirror that gate here.
        if ($DebloatProfile -eq 'Aggressive') {
            $aggressivePkgs = @($packages | Where-Object { $_ -match 'MicrosoftEdge\.Stable|OneDriveSync|MicrosoftTeams|549981C3F5F10' })
            if ($aggressivePkgs.Count -gt 0) {
                Write-OutputColor "  Aggressive Custom Debloat will attempt to remove:" -color "Warning"
                foreach ($p in $aggressivePkgs) { Write-OutputColor "    - $p" -color "Warning" }
                Write-OutputColor "  These are user-facing and may be re-needed after debloat." -color "Warning"
                if (-not (Confirm-UserAction -Message "Continue removing these packages?")) {
                    $packages = @($packages | Where-Object { $_ -notin $aggressivePkgs })
                    Write-OutputColor "  Skipped Edge/OneDrive/Teams/Cortana per operator choice." -color "Info"
                }
            }
        }

        foreach ($pkgName in $packages) {
            $installed = Get-AppxPackage -Name "*$pkgName*" -AllUsers -ErrorAction SilentlyContinue
            $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$pkgName*" }

            if ($null -eq $installed -and $null -eq $provisioned) {
                $totalSkipped++
                continue
            }

            try {
                if ($null -ne $installed) {
                    $installed | Remove-AppxPackage -AllUsers -ErrorAction Stop
                }
                if ($null -ne $provisioned) {
                    $provisioned | Remove-AppxProvisionedPackage -Online -ErrorAction Stop | Out-Null
                }
                Write-OutputColor "  [REMOVED] $pkgName" -color "Success"
                $totalChanged++
                Add-SessionChange -Category "Debloat" -Description "Removed AppxPackage: $pkgName"
            }
            catch {
                Write-OutputColor "  [FAILED] $pkgName — $_" -color "Error"
                $totalFailed++
            }
        }
        Write-OutputColor "" -color "Info"
    }

    # ── Service Optimization ──────────────────────────────────────────
    if ($Selected.Services) {
        Write-OutputColor "  ── Service Optimization ──────────────────────────────────────────" -color "Info"
        $serviceList = Get-DisableableServices -Type $svcType -DebloatProfile $DebloatProfile

        $seenSvc = @{}
        foreach ($svcInfo in $serviceList) {
            if ($seenSvc.ContainsKey($svcInfo.Name)) { continue }
            $seenSvc[$svcInfo.Name] = $true

            if ($svcInfo.CheckSSD -and -not (Test-SSDPresent)) { $totalSkipped++; continue }
            if ($svcInfo.CheckPrinters) {
                $printers = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Shared -eq $true -or $_.Name -notmatch "Microsoft|Fax|OneNote|PDF" })
                if ($printers.Count -gt 0) { $totalSkipped++; continue }
            }
            if ($svcInfo.CheckPrintServer) {
                $sharedPrinters = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Shared -eq $true })
                if ($sharedPrinters.Count -gt 0) { $totalSkipped++; continue }
            }
            if ($svcInfo.CheckBluetooth) {
                $btDevice = Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($null -ne $btDevice) { $totalSkipped++; continue }
            }

            $svc = Get-Service -Name $svcInfo.Name -ErrorAction SilentlyContinue
            if ($null -eq $svc) { $totalSkipped++; continue }
            if ($svc.StartType -eq "Disabled") { $totalSkipped++; continue }

            try {
                $originalStartType = $svc.StartType.ToString()
                if ($svc.Status -eq "Running") {
                    Stop-Service -Name $svcInfo.Name -Force -ErrorAction Stop
                }
                Set-Service -Name $svcInfo.Name -StartupType Disabled -ErrorAction Stop
                Write-OutputColor "  [DISABLED] $($svcInfo.DisplayName)" -color "Success"
                $totalChanged++
                Add-SessionChange -Category "Debloat" -Description "Disabled service: $($svcInfo.DisplayName)"
                Clear-MenuCache

                $svcNameCap = $svcInfo.Name
                $startTypeCap = $originalStartType
                Add-UndoAction -Category "Debloat" -Description "Disabled service $($svcInfo.DisplayName)" -UndoScript {
                    param($SvcName, $StartType)
                    Set-Service -Name $SvcName -StartupType $StartType -ErrorAction SilentlyContinue
                    if ($StartType -eq "Automatic") {
                        Start-Service -Name $SvcName -ErrorAction SilentlyContinue
                    }
                } -UndoParams @{ SvcName = $svcNameCap; StartType = $startTypeCap }
            }
            catch {
                Write-OutputColor "  [FAILED] $($svcInfo.DisplayName) — $_" -color "Error"
                $totalFailed++
            }
        }
        Write-OutputColor "" -color "Info"
    }

    # ── Scheduled Task Cleanup ────────────────────────────────────────
    if ($Selected.Tasks) {
        Write-OutputColor "  ── Scheduled Task Cleanup ────────────────────────────────────────" -color "Info"
        $telemetryTasks = Get-TelemetryTasks

        foreach ($task in $telemetryTasks) {
            if ($task.State -eq "Disabled") { $totalSkipped++; continue }

            try {
                $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null
                Write-OutputColor "  [DISABLED] $($task.TaskName)" -color "Success"
                $totalChanged++
                Add-SessionChange -Category "Debloat" -Description "Disabled task: $($task.TaskName)"

                $taskPathCap = $task.TaskPath
                $taskNameCap = $task.TaskName
                Add-UndoAction -Category "Debloat" -Description "Disabled task $($task.TaskName)" -UndoScript {
                    param($TaskPath, $TaskName)
                    Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue |
                        Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
                } -UndoParams @{ TaskPath = $taskPathCap; TaskName = $taskNameCap }
            }
            catch {
                Write-OutputColor "  [FAILED] $($task.TaskName) — $_" -color "Error"
                $totalFailed++
            }
        }
        Write-OutputColor "" -color "Info"
    }

    # ── Registry Tweaks ───────────────────────────────────────────────
    if ($Selected.Registry) {
        Write-OutputColor "  ── Registry Tweaks ───────────────────────────────────────────────" -color "Info"

        $registryTweaks = @(
            @{
                Path  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
                Name  = "DisableWindowsConsumerFeatures"
                Value = 1
                Type  = "DWord"
                Desc  = "Disable app suggestions"
            }
            @{
                Path  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
                Name  = "EnableActivityFeed"
                Value = 0
                Type  = "DWord"
                Desc  = "Disable activity history"
            }
            @{
                Path  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
                Name  = "PublishUserActivities"
                Value = 0
                Type  = "DWord"
                Desc  = "Disable user activity publishing"
            }
        )

        if ($DebloatProfile -eq "Aggressive") {
            $registryTweaks += @(
                @{
                    Path  = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"
                    Name  = "BingSearchEnabled"
                    Value = 0
                    Type  = "DWord"
                    Desc  = "Disable Bing search in Start Menu"
                }
                @{
                    Path  = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                    Name  = "RotatingLockScreenOverlayEnabled"
                    Value = 0
                    Type  = "DWord"
                    Desc  = "Disable lock screen spotlight"
                }
                @{
                    Path  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
                    Name  = "DisabledByGroupPolicy"
                    Value = 1
                    Type  = "DWord"
                    Desc  = "Disable advertising ID"
                }
            )
        }

        foreach ($tweak in $registryTweaks) {
            $currentValue = $null
            $tweakExists = $false
            if (Test-Path -LiteralPath $tweak.Path) {
                $currentValue = (Get-ItemProperty -LiteralPath $tweak.Path -Name $tweak.Name -ErrorAction SilentlyContinue).$($tweak.Name)
                if ($null -ne $currentValue) { $tweakExists = $true }
            }

            if ($tweakExists -and $currentValue -eq $tweak.Value) {
                $totalSkipped++
                continue
            }

            try {
                if (-not (Test-Path -LiteralPath $tweak.Path)) {
                    New-Item -Path $tweak.Path -Force -ErrorAction Stop | Out-Null
                }
                $prevVal = $currentValue
                $prevExists = $tweakExists
                Set-ItemProperty -LiteralPath $tweak.Path -Name $tweak.Name -Value $tweak.Value -Type $tweak.Type -Force -ErrorAction Stop
                Write-OutputColor "  [SET] $($tweak.Desc)" -color "Success"
                $totalChanged++
                Add-SessionChange -Category "Debloat" -Description "Registry: $($tweak.Desc)"

                $rPath = $tweak.Path
                $rName = $tweak.Name
                $rPrev = $prevVal
                $rExisted = $prevExists
                Add-UndoAction -Category "Debloat" -Description "Registry: $($tweak.Desc)" -UndoScript {
                    param($RegPath, $RegName, $RegPrevious, $RegExisted)
                    if ($RegExisted) {
                        Set-ItemProperty -LiteralPath $RegPath -Name $RegName -Value $RegPrevious -Force -ErrorAction SilentlyContinue
                    }
                    else {
                        Remove-ItemProperty -LiteralPath $RegPath -Name $RegName -Force -ErrorAction SilentlyContinue
                    }
                } -UndoParams @{ RegPath = $rPath; RegName = $rName; RegPrevious = $rPrev; RegExisted = $rExisted }
            }
            catch {
                Write-OutputColor "  [FAILED] $($tweak.Desc) — $_" -color "Error"
                $totalFailed++
            }
        }
        Write-OutputColor "" -color "Info"
    }

    # ── Optional Features ─────────────────────────────────────────────
    if ($Selected.Features) {
        Write-OutputColor "  ── Optional Features ─────────────────────────────────────────────" -color "Info"

        $featuresList = @()

        if ($DebloatProfile -eq "Standard" -or $DebloatProfile -eq "Aggressive") {
            if ($isServer) {
                $featuresList += @{ Name = "FS-SMB1"; Desc = "SMB v1 Protocol"; Type = "WindowsFeature" }
            }
        }

        if ($DebloatProfile -eq "Aggressive") {
            $featuresList += @{ Name = "Internet-Explorer-Optional-amd64"; Desc = "Internet Explorer"; Type = "OptionalFeature" }
            $featuresList += @{ Name = "MicrosoftWindowsPowerShellV2Root"; Desc = "PowerShell v2 Engine"; Type = "OptionalFeature" }
        }

        if ($featuresList.Count -eq 0) {
            Write-OutputColor "  No features to remove for $DebloatProfile profile." -color "Debug"
        }

        foreach ($feature in $featuresList) {
            if ($feature.Type -eq "WindowsFeature") {
                $wf = Get-WindowsFeature -Name $feature.Name -ErrorAction SilentlyContinue
                if ($null -eq $wf -or -not $wf.Installed) { $totalSkipped++; continue }

                try {
                    $null = Remove-WindowsFeature -Name $feature.Name -ErrorAction Stop
                    Write-OutputColor "  [REMOVED] $($feature.Desc)" -color "Success"
                    $totalChanged++
                    Add-SessionChange -Category "Debloat" -Description "Removed feature: $($feature.Desc)"
                }
                catch {
                    Write-OutputColor "  [FAILED] $($feature.Desc) — $_" -color "Error"
                    $totalFailed++
                }
            }
            else {
                $of = Get-WindowsOptionalFeature -Online -FeatureName $feature.Name -ErrorAction SilentlyContinue
                if ($null -eq $of -or $of.State -ne "Enabled") { $totalSkipped++; continue }

                try {
                    $null = Disable-WindowsOptionalFeature -Online -FeatureName $feature.Name -NoRestart -ErrorAction Stop
                    Write-OutputColor "  [DISABLED] $($feature.Desc)" -color "Success"
                    $totalChanged++
                    Add-SessionChange -Category "Debloat" -Description "Disabled feature: $($feature.Desc)"

                    $fNameCap = $feature.Name
                    Add-UndoAction -Category "Debloat" -Description "Disabled feature $($feature.Desc)" -UndoScript {
                        param($FeatureName)
                        Enable-WindowsOptionalFeature -Online -FeatureName $FeatureName -NoRestart -ErrorAction SilentlyContinue | Out-Null
                    } -UndoParams @{ FeatureName = $fNameCap }
                }
                catch {
                    Write-OutputColor "  [FAILED] $($feature.Desc) — $_" -color "Error"
                    $totalFailed++
                }
            }
        }
        Write-OutputColor "" -color "Info"
    }

    # ── Startup Programs ──────────────────────────────────────────────
    if ($Selected.Startup) {
        Write-OutputColor "  ── Startup Programs ──────────────────────────────────────────────" -color "Info"

        # Read startup items from registry Run/RunOnce keys
        $startupPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
        )

        $startupItems = [System.Collections.Generic.List[object]]::new()
        foreach ($regPath in $startupPaths) {
            if (-not (Test-Path -LiteralPath $regPath)) { continue }
            $props = Get-ItemProperty -LiteralPath $regPath -ErrorAction SilentlyContinue
            if ($null -eq $props) { continue }

            $propNames = @($props.PSObject.Properties | Where-Object { $_.Name -notmatch "^PS" } | Select-Object -ExpandProperty Name)
            foreach ($propName in $propNames) {
                $startupItems.Add(@{
                    Path = $regPath
                    Name = $propName
                    Value = $props.$propName
                })
            }
        }

        if ($startupItems.Count -eq 0) {
            Write-OutputColor "  No startup programs found in registry Run keys." -color "Debug"
        }
        else {
            Write-OutputColor "  Found $($startupItems.Count) startup program(s):" -color "Info"
            $idx = 1
            foreach ($item in $startupItems) {
                $displayVal = $item.Value
                if ($displayVal.Length -gt 55) { $displayVal = $displayVal.Substring(0, 52) + "..." }
                Write-OutputColor "  [$idx] $($item.Name): $displayVal" -color "Info"
                $idx++
            }

            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Enter numbers to disable (comma-separated), or Enter to skip:" -color "Info"
            $disableInput = Read-Host "  "

            if (-not [string]::IsNullOrWhiteSpace($disableInput)) {
                $indices = $disableInput -split "," | ForEach-Object { $_.Trim() }
                foreach ($idxStr in $indices) {
                    $idxVal = 0
                    if ([int]::TryParse($idxStr, [ref]$idxVal) -and $idxVal -ge 1 -and $idxVal -le $startupItems.Count) {
                        $item = $startupItems[$idxVal - 1]
                        try {
                            $savedValue = $item.Value
                            Remove-ItemProperty -LiteralPath $item.Path -Name $item.Name -Force -ErrorAction Stop
                            Write-OutputColor "  [REMOVED] Startup: $($item.Name)" -color "Success"
                            $totalChanged++
                            Add-SessionChange -Category "Debloat" -Description "Removed startup: $($item.Name)"

                            $sPath = $item.Path
                            $sName = $item.Name
                            $sValue = $savedValue
                            Add-UndoAction -Category "Debloat" -Description "Removed startup entry $($item.Name)" -UndoScript {
                                param($Path, $Name, $Value)
                                Set-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -Force -ErrorAction SilentlyContinue
                            } -UndoParams @{ Path = $sPath; Name = $sName; Value = $sValue }
                        }
                        catch {
                            Write-OutputColor "  [FAILED] Startup: $($item.Name) — $_" -color "Error"
                            $totalFailed++
                        }
                    }
                    else {
                        Write-OutputColor "  Invalid index: $idxStr" -color "Warning"
                    }
                }
            }
            else {
                Write-OutputColor "  Startup programs skipped." -color "Info"
            }
        }
        Write-OutputColor "" -color "Info"
    }

    # ── Summary ───────────────────────────────────────────────────────
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CUSTOM DEBLOAT SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Profile:  $DebloatProfile".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Changed:  $totalChanged".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Skipped:  $totalSkipped".PadRight(72))│" -color "Debug"
    Write-OutputColor "  │$("  Failed:   $totalFailed".PadRight(72))│" -color $(if ($totalFailed -gt 0) { "Error" } else { "Debug" })
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

# ════════════════════════════════════════════════════════════════════════
# Windows 11 / Server 2025 UI Cleanup
# ════════════════════════════════════════════════════════════════════════
function Invoke-Win11UICleanup {
    Clear-Host
    Write-CenteredOutput "Windows UI Cleanup" -color "Info"

    $osInfo = Get-WindowsDebloatInfo

    # Skip on Server Core — no GUI to customize
    if ($osInfo.IsServerCore) {
        Write-OutputColor "  Server Core detected — no GUI shell available." -color "Warning"
        Write-OutputColor "  UI tweaks are not applicable on Server Core installations." -color "Info"
        return
    }

    if ($osInfo.Build -lt 22000 -and -not $osInfo.IsServer) {
        # Win10 — apply Win10-specific UI tweaks
        Write-OutputColor "  Detected Windows 10 (build $($osInfo.Build)) — applying UI preferences." -color "Info"
    } elseif ($osInfo.Build -lt 22000) {
        Write-OutputColor "  This system is older than Windows 11/Server 2025 (build $($osInfo.Build))." -color "Warning"
        Write-OutputColor "  Limited UI tweaks available." -color "Info"
    } else {
        $verLabel = if ($osInfo.DisplayVersion) { $osInfo.DisplayVersion } else { "build $($osInfo.Build)" }
        Write-OutputColor "  Detected $($osInfo.VersionTag) ($verLabel) — applying UI preferences." -color "Info"
    }
    Write-OutputColor "" -color "Info"

    $applied = 0
    $failed = 0

    # Base tweaks that apply to all Windows versions
    $tweaks = @(
        @{
            Name = "Show file extensions"
            Key  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Property = "HideFileExt"
            Value = 0
            Type = "DWord"
        }
        @{
            Name = "Show hidden files"
            Key  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Property = "Hidden"
            Value = 1
            Type = "DWord"
        }
        @{
            Name = "File Explorer opens to This PC"
            Key  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Property = "LaunchTo"
            Value = 1
            Type = "DWord"
        }
    )

    # Win11+ tweaks (build 22000+)
    if ($osInfo.Build -ge 22000) {
        $tweaks += @(
            @{
                Name = "Classic right-click context menu"
                Key  = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
                Property = "(Default)"
                Value = ""
                Type = "String"
                IsDefault = $true
            }
            @{
                Name = "Left-align taskbar"
                Key  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                Property = "TaskbarAl"
                Value = 0
                Type = "DWord"
            }
            @{
                Name = "Disable Widgets on taskbar"
                Key  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                Property = "TaskbarDa"
                Value = 0
                Type = "DWord"
            }
            @{
                Name = "Disable Chat/Teams on taskbar"
                Key  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                Property = "TaskbarMn"
                Value = 0
                Type = "DWord"
            }
            @{
                Name = "Minimize search box (icon only)"
                Key  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
                Property = "SearchboxTaskbarMode"
                Value = 1
                Type = "DWord"
            }
            @{
                Name = "Disable Copilot (user policy)"
                Key  = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"
                Property = "TurnOffWindowsCopilot"
                Value = 1
                Type = "DWord"
            }
            @{
                Name = "Disable Snap Layout flyout on maximize hover"
                Key  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                Property = "EnableSnapAssistFlyout"
                Value = 0
                Type = "DWord"
            }
            @{
                Name = "Disable Start menu recommendations"
                Key  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                Property = "Start_IrisRecommendations"
                Value = 0
                Type = "DWord"
            }
        )
    }

    # Win11 23H2+ (build 22631+): Gallery, Home, Dev Home
    if ($osInfo.Build -ge 22631) {
        $tweaks += @(
            @{
                Name = "Disable Gallery in File Explorer"
                Key  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                Property = "ShowGalleryInExplorer"
                Value = 0
                Type = "DWord"
            }
            @{
                Name = "Disable File Explorer Home page"
                Key  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                Property = "ShowHome"
                Value = 0
                Type = "DWord"
            }
        )
    }

    # Win11 24H2+ (build 26100+): Copilot button, new taskbar elements
    if ($osInfo.Build -ge 26100) {
        $tweaks += @(
            @{
                Name = "Hide Copilot button from taskbar"
                Key  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                Property = "ShowCopilotButton"
                Value = 0
                Type = "DWord"
            }
            @{
                Name = "Disable Copilot system-wide (machine policy)"
                Key  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
                Property = "TurnOffWindowsCopilot"
                Value = 1
                Type = "DWord"
            }
        )
    }

    # Win11 25H2+ (build 26200+): Recall, AI features
    if ($osInfo.Build -ge 26200) {
        $tweaks += @(
            @{
                Name = "Disable Windows Recall"
                Key  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
                Property = "DisableAIDataAnalysis"
                Value = 1
                Type = "DWord"
            }
            @{
                Name = "Disable Recall user opt-in"
                Key  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                Property = "RecallEnabled"
                Value = 0
                Type = "DWord"
            }
        )
    }

    # Win10-specific tweaks
    if ($osInfo.IsWin10) {
        $tweaks += @(
            @{
                Name = "Disable Cortana on taskbar"
                Key  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
                Property = "AllowCortana"
                Value = 0
                Type = "DWord"
            }
            @{
                Name = "Disable web search results in Start"
                Key  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
                Property = "DisableWebSearch"
                Value = 1
                Type = "DWord"
            }
            @{
                Name = "Minimize search box (icon only)"
                Key  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
                Property = "SearchboxTaskbarMode"
                Value = 1
                Type = "DWord"
            }
        )
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  APPLYING UI TWEAKS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    foreach ($tweak in $tweaks) {
        try {
            # Ensure registry key exists
            if (-not (Test-Path -LiteralPath $tweak.Key)) {
                $null = New-Item -Path $tweak.Key -Force -ErrorAction Stop
            }

            if ($tweak.IsDefault) {
                # Set the (Default) value
                $null = Set-Item -LiteralPath $tweak.Key -Value $tweak.Value -Force -ErrorAction Stop
            }
            else {
                $null = Set-ItemProperty -LiteralPath $tweak.Key -Name $tweak.Property -Value $tweak.Value -Type $tweak.Type -Force -ErrorAction Stop
            }

            $line = "  [OK] $($tweak.Name)"
            Write-OutputColor "  │$($line.PadRight(72))│" -color "Success"
            $applied++
        }
        catch {
            $line = "  [!!] $($tweak.Name): $($_.Exception.Message)"
            if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($line.PadRight(72))│" -color "Error"
            $failed++
        }
    }

    # Reset folder grouping. The prior implementation recursively removed the entire
    # FolderTypes / Streams subkeys — that nukes the user's saved per-folder view
    # preferences (custom column widths, sort orders, group-by) on top of the date-grouping
    # tweak it was supposed to deliver. Instead, target only the date-grouping property
    # (GroupView under FolderTypes\GroupBy nodes) and document that wholesale reset requires
    # an explicit opt-in. Operators who want the full nuke can do it manually via reg.exe.
    try {
        $folderTypesPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes"
        if (Test-Path -LiteralPath $folderTypesPath) {
            # Reset only the GroupView property under each folder-type subkey rather than wholesale deleting.
            Get-ChildItem -LiteralPath $folderTypesPath -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.PSChildName -eq 'TopViews' -or $_.Property -contains 'GroupView' } |
                ForEach-Object {
                    Remove-ItemProperty -LiteralPath $_.PSPath -Name 'GroupView' -Force -ErrorAction SilentlyContinue
                }
        }
        $line = "  [OK] Reset folder grouping (preserved column widths / sort orders)"
        Write-OutputColor "  │$($line.PadRight(72))│" -color "Success"
        $applied++
    }
    catch {
        $line = "  [!!] Folder view reset: $($_.Exception.Message)"
        if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($line.PadRight(72))│" -color "Error"
        $failed++
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Summary
    $summaryColor = if ($failed -eq 0) { "Success" } else { "Warning" }
    Write-OutputColor "  Applied: $applied   Failed: $failed" -color $summaryColor

    # Restart Explorer to apply
    Write-OutputColor "" -color "Info"
    if (Confirm-UserAction -Message "Restart Explorer now to apply changes?") {
        try {
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Start-Process explorer.exe
            Write-OutputColor "  Explorer restarted. Changes applied." -color "Success"
        }
        catch {
            Write-OutputColor "  Could not restart Explorer: $($_.Exception.Message)" -color "Warning"
            Write-OutputColor "  Log out and back in to apply changes." -color "Info"
        }
    }
    else {
        Write-OutputColor "  Changes saved. Log out and back in or restart Explorer to apply." -color "Info"
    }

    Add-SessionChange -Category "Debloat" -Description "Win11/2025 UI cleanup: $applied tweaks applied"
}

# ════════════════════════════════════════════════════════════════════════
# OS Dark / Light Theme Toggle
# ════════════════════════════════════════════════════════════════════════
function Set-OSThemeMode {
    Clear-Host
    Write-CenteredOutput "OS Theme Mode" -color "Info"

    $themeKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"

    # Detect current mode
    $currentApps = $null
    $currentSystem = $null
    try {
        $currentApps = (Get-ItemProperty -LiteralPath $themeKey -Name AppsUseLightTheme -ErrorAction SilentlyContinue).AppsUseLightTheme
        $currentSystem = (Get-ItemProperty -LiteralPath $themeKey -Name SystemUsesLightTheme -ErrorAction SilentlyContinue).SystemUsesLightTheme
    }
    catch { }

    $currentMode = if ($currentApps -eq 0 -and $currentSystem -eq 0) { "Dark" }
                   elseif ($currentApps -eq 1 -and $currentSystem -eq 1) { "Light" }
                   elseif ($null -eq $currentApps) { "Unknown" }
                   else { "Mixed (Apps: $(if ($currentApps -eq 0) {'Dark'} else {'Light'}), System: $(if ($currentSystem -eq 0) {'Dark'} else {'Light'}))" }

    $currentColor = if ($currentMode -eq "Dark") { "Info" } elseif ($currentMode -eq "Light") { "Warning" } else { "Debug" }
    Write-OutputColor "  Current theme: $currentMode" -color $currentColor
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-MenuItem -Text "[1]  Dark Mode  (dark apps + dark taskbar/start)"
    Write-MenuItem -Text "[2]  Light Mode (light apps + light taskbar/start)"
    Write-MenuItem -Text "[3]  Mixed: Dark Apps + Light System (taskbar/start)"
    Write-MenuItem -Text "[4]  Mixed: Light Apps + Dark System (taskbar/start)"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    $appsLight = $null
    $systemLight = $null
    $modeName = $null

    switch ($choice) {
        "1" { $appsLight = 0; $systemLight = 0; $modeName = "Dark Mode" }
        "2" { $appsLight = 1; $systemLight = 1; $modeName = "Light Mode" }
        "3" { $appsLight = 0; $systemLight = 1; $modeName = "Dark Apps + Light System" }
        "4" { $appsLight = 1; $systemLight = 0; $modeName = "Light Apps + Dark System" }
        default {
            Write-OutputColor "  Invalid selection." -color "Warning"
            return
        }
    }

    try {
        if (-not (Test-Path -LiteralPath $themeKey)) {
            $null = New-Item -Path $themeKey -Force -ErrorAction Stop
        }
        Set-ItemProperty -LiteralPath $themeKey -Name AppsUseLightTheme -Value $appsLight -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -LiteralPath $themeKey -Name SystemUsesLightTheme -Value $systemLight -Type DWord -Force -ErrorAction Stop

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Theme set to: $modeName" -color "Success"

        # Also set color prevalence for accent on taskbar in dark mode
        if ($systemLight -eq 0) {
            Set-ItemProperty -LiteralPath $themeKey -Name ColorPrevalence -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        }

        Add-SessionChange -Category "Debloat" -Description "OS theme changed to $modeName"

        # Restart Explorer to apply immediately
        Write-OutputColor "" -color "Info"
        if (Confirm-UserAction -Message "Restart Explorer now to apply?") {
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Start-Process explorer.exe
            Write-OutputColor "  Explorer restarted. Theme applied." -color "Success"
        }
        else {
            Write-OutputColor "  Theme saved. Log out and back in to fully apply." -color "Info"
        }
    }
    catch {
        Write-OutputColor "  Failed to set theme: $($_.Exception.Message)" -color "Error"
    }
}
#endregion
