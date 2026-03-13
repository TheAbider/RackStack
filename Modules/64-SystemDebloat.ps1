#region ===== SYSTEM DEBLOAT AND OPTIMIZATION =====
# Module: 64-SystemDebloat
# Purpose: Remove bloatware, disable telemetry, optimize services for Windows Server and Workstation
# Profiles: Light (safe removals), Standard (recommended), Aggressive (maximum cleanup)
# All operations support WhatIf preview, undo where possible, and session change tracking.

# ────────────────────────────────────────────────────────────────────────
# Helper: Get removable AppxPackages for a given profile
# ────────────────────────────────────────────────────────────────────────
function Get-RemovableAppxPackages {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet("Light","Standard","Aggressive")]
        [string]$DebloatProfile
    )

    # Light profile: obvious bloatware and rarely-used Store apps
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
        "Microsoft.YourPhone"
        "Microsoft.GetHelp"
        "Microsoft.Getstarted"                    # Tips
        "Microsoft.WindowsFeedbackHub"
        "Microsoft.MicrosoftOfficeHub"
    )

    # Standard adds media/social/Xbox apps
    $standardPackages = @(
        "Microsoft.ZuneMusic"                     # Groove Music
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

    # Aggressive adds Edge, OneDrive, Teams consumer, Cortana
    $aggressivePackages = @(
        "Microsoft.MicrosoftEdge.Stable"
        "Microsoft.OneDriveSync"
        "MicrosoftTeams"                          # Teams consumer (personal)
        "Microsoft.549981C3F5F10"                 # Cortana
    )

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
            $services.Add(@{ Name = "DiagTrack"; DisplayName = "Connected User Experiences"; Warning = $null })
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
    )

    $tasks = [System.Collections.Generic.List[object]]::new()
    foreach ($taskPath in $taskPaths) {
        try {
            $found = Get-ScheduledTask -TaskPath $taskPath -ErrorAction SilentlyContinue
            if ($null -ne $found) {
                foreach ($task in @($found)) {
                    $tasks.Add($task)
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

        # Show current OS info
        $osCaption = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
        if ($null -ne $osCaption) {
            Write-OutputColor "  OS: $osCaption" -color "Info"
        }
        $isServer = ($null -ne $osCaption) -and ($osCaption -match "Server")
        $modeTag = if ($isServer) { "Server detected" } else { "Workstation detected" }
        Write-OutputColor "  Mode: $modeTag" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  DEBLOAT OPTIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem -Text "[1]  Workstation Debloat (AppxPackages, telemetry, startup)"
        Write-MenuItem -Text "[2]  Server Debloat (services, optional features, telemetry)"
        Write-MenuItem -Text "[3]  Quick Scan (analyze only, no changes)"
        Write-MenuItem -Text "[4]  Custom Debloat (choose individual categories)"
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
                Invoke-WorkstationDebloat -Profile $selectedProfile
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Press Enter to continue..." -color "Info"
                Read-Host | Out-Null
            }
            "2" {
                $selectedProfile = Select-DebloatProfile
                if ($null -eq $selectedProfile) { continue }
                Invoke-ServerDebloat -Profile $selectedProfile
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
                Invoke-CustomDebloat
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

    if ($PreviewOnly) {
        Write-OutputColor "  *** PREVIEW MODE — No changes will be made ***" -color "Warning"
        Write-OutputColor "" -color "Info"
    }

    $removed = 0
    $skippedCount = 0
    $failedCount = 0

    # ── Phase 1: AppxPackage Removal ──────────────────────────────────
    Write-OutputColor "  ── AppxPackage Removal ────────────────────────────────────────────" -color "Info"
    $packages = Get-RemovableAppxPackages -Profile $DebloatProfile

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
    $serviceList = Get-DisableableServices -Type "Workstation" -Profile $DebloatProfile

    foreach ($svcInfo in $serviceList) {
        # SSD check for SysMain
        if ($svcInfo.CheckSSD) {
            if (-not (Test-SSDPresent)) {
                Write-OutputColor "  [SKIP] $($svcInfo.DisplayName) — no SSD detected, keeping enabled" -color "Debug"
                $skippedCount++
                continue
            }
        }

        # Printer check for Print Spooler
        if ($svcInfo.CheckPrinters) {
            $printers = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Shared -eq $true -or $_.Name -notmatch "Microsoft|Fax|OneNote|PDF" })
            if ($printers.Count -gt 0) {
                Write-OutputColor "  [SKIP] $($svcInfo.DisplayName) — $($printers.Count) printer(s) detected" -color "Debug"
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
                Set-Service -Name $svcNameCapture -StartupType $startTypeCapture -ErrorAction SilentlyContinue
                if ($startTypeCapture -eq "Automatic") {
                    Start-Service -Name $svcNameCapture -ErrorAction SilentlyContinue
                }
            }
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
                Get-ScheduledTask -TaskPath $taskPathCapture -TaskName $taskNameCapture -ErrorAction SilentlyContinue |
                    Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
            }
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
                    if ($regExisted) {
                        Set-ItemProperty -LiteralPath $regPath -Name $regName -Value $regPrevious -Force -ErrorAction SilentlyContinue
                    }
                    else {
                        Remove-ItemProperty -LiteralPath $regPath -Name $regName -Force -ErrorAction SilentlyContinue
                    }
                }
            }
            catch {
                Write-OutputColor "  [FAILED] $($tweak.Desc) — $_" -color "Error"
                $failedCount++
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
                Get-ScheduledTask -TaskPath $taskPathCapture -TaskName $taskNameCapture -ErrorAction SilentlyContinue |
                    Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
            }
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
    $serviceList = Get-DisableableServices -Type "Server" -Profile $DebloatProfile

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
        # Print server check
        if ($svcInfo.CheckPrintServer) {
            $sharedPrinters = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Shared -eq $true })
            if ($sharedPrinters.Count -gt 0) {
                Write-OutputColor "  [SKIP] $($svcInfo.DisplayName) — $($sharedPrinters.Count) shared printer(s) found" -color "Debug"
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
                Set-Service -Name $svcNameCapture -StartupType $startTypeCapture -ErrorAction SilentlyContinue
                if ($startTypeCapture -eq "Automatic") {
                    Start-Service -Name $svcNameCapture -ErrorAction SilentlyContinue
                }
            }
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
                    if ($null -ne $prevSMValue) {
                        Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\ServerManager" -Name "DoNotOpenServerManagerAtLogon" -Value $prevSMValue -Force -ErrorAction SilentlyContinue
                    }
                    else {
                        Remove-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\ServerManager" -Name "DoNotOpenServerManagerAtLogon" -Force -ErrorAction SilentlyContinue
                    }
                }
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
                        Enable-WindowsOptionalFeature -Online -FeatureName $featureNameCapture -NoRestart -ErrorAction SilentlyContinue | Out-Null
                    }
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
                            Get-ScheduledTask -TaskPath $taskPathCap -TaskName $taskNameCap -ErrorAction SilentlyContinue |
                                Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
                        }
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

    # Detect OS type
    $osCaption = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
    $isServer = ($null -ne $osCaption) -and ($osCaption -match "Server")

    # ── Removable AppxPackages ────────────────────────────────────────
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  REMOVABLE APPX PACKAGES".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $allPackageNames = Get-RemovableAppxPackages -Profile "Aggressive"
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
    $candidateServices = Get-DisableableServices -Type $svcType -Profile "Aggressive"

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
    Write-OutputColor "  │$("  ─────────────────────────────────────────".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Total actionable items: $totalItems".PadRight(72))│" -color $impactColor
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

                Invoke-CustomDebloatExecution -Selected $selected -Profile $selectedProfile
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

    $osCaption = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
    $isServer = ($null -ne $osCaption) -and ($osCaption -match "Server")
    $svcType = if ($isServer) { "Server" } else { "Workstation" }

    $totalChanged = 0
    $totalSkipped = 0
    $totalFailed = 0

    # ── AppxPackage Removal ───────────────────────────────────────────
    if ($Selected.AppxPackages) {
        Write-OutputColor "  ── AppxPackage Removal ────────────────────────────────────────────" -color "Info"
        $packages = Get-RemovableAppxPackages -Profile $DebloatProfile

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
        $serviceList = Get-DisableableServices -Type $svcType -Profile $DebloatProfile

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
                    Set-Service -Name $svcNameCap -StartupType $startTypeCap -ErrorAction SilentlyContinue
                    if ($startTypeCap -eq "Automatic") {
                        Start-Service -Name $svcNameCap -ErrorAction SilentlyContinue
                    }
                }
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
                    Get-ScheduledTask -TaskPath $taskPathCap -TaskName $taskNameCap -ErrorAction SilentlyContinue |
                        Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
                }
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
                    if ($rExisted) {
                        Set-ItemProperty -LiteralPath $rPath -Name $rName -Value $rPrev -Force -ErrorAction SilentlyContinue
                    }
                    else {
                        Remove-ItemProperty -LiteralPath $rPath -Name $rName -Force -ErrorAction SilentlyContinue
                    }
                }
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
                        Enable-WindowsOptionalFeature -Online -FeatureName $fNameCap -NoRestart -ErrorAction SilentlyContinue | Out-Null
                    }
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

        # Read startup items from registry Run keys
        $startupPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
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
                                Set-ItemProperty -LiteralPath $sPath -Name $sName -Value $sValue -Force -ErrorAction SilentlyContinue
                            }
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
#endregion
