#region ===== WINDOWS DEFENDER EXCLUSIONS =====
# Function to configure Windows Defender exclusions for Hyper-V
function Set-DefenderExclusions {
    # Check if Windows Defender cmdlets are available (Server 2016+ only)
    if (-not (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
        Write-OutputColor "  Windows Defender PowerShell module is not available." -color "Error"
        Write-OutputColor "  This feature requires Windows Server 2016 or later." -color "Warning"
        return
    }
    try {
        $null = Get-MpComputerStatus -ErrorAction Stop
    }
    catch {
        Write-OutputColor "  Windows Defender is not available or not running." -color "Error"
        return
    }

    while ($true) {
        if ($global:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                    WINDOWS DEFENDER EXCLUSIONS").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        # Show current exclusions
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  CURRENT EXCLUSIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        $prefs = Get-MpPreference -ErrorAction SilentlyContinue
        if ($null -eq $prefs) {
            Write-OutputColor "  │$("  Unable to read Defender preferences".PadRight(72))│" -color "Warning"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            Write-PressEnter
            continue
        }
        $pathExclusions = if ($null -ne $prefs.ExclusionPath) { @($prefs.ExclusionPath) } else { @() }
        $processExclusions = if ($null -ne $prefs.ExclusionProcess) { @($prefs.ExclusionProcess) } else { @() }
        $null = $prefs.ExclusionExtension  # Suppress unused warning

        if ($pathExclusions) {
            Write-OutputColor "  │$("  Path Exclusions:".PadRight(72))│" -color "Info"
            foreach ($path in $pathExclusions | Select-Object -First 5) {
                $displayPath = if ($path.Length -gt 66) { $path.Substring(0,63) + "..." } else { $path }
                Write-OutputColor "  │$("    $displayPath".PadRight(72))│" -color "Success"
            }
            if ($pathExclusions.Count -gt 5) {
                Write-OutputColor "  │$("    ... and $($pathExclusions.Count - 5) more".PadRight(72))│" -color "Info"
            }
        } else {
            Write-OutputColor "  │$("  No path exclusions configured".PadRight(72))│" -color "Warning"
        }

        if ($processExclusions) {
            Write-OutputColor "  │$("  Process Exclusions:".PadRight(72))│" -color "Info"
            foreach ($proc in $processExclusions | Select-Object -First 3) {
                $lineStr = "    $proc"
                if ($lineStr.Length -gt 72) { $lineStr = $lineStr.Substring(0, 69) + "..." }
                Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Success"
            }
            if ($processExclusions.Count -gt 3) {
                Write-OutputColor "  │$("    ... and $($processExclusions.Count - 3) more".PadRight(72))│" -color "Info"
            }
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        # Menu options
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  OPTIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem -Text "[1]  Add Hyper-V Exclusions (Recommended)"
        Write-MenuItem -Text "[2]  Add Custom Path Exclusion"
        Write-MenuItem -Text "[3]  Add Custom Process Exclusion"
        Write-MenuItem -Text "[4]  View All Current Exclusions"
        Write-MenuItem -Text "[5]  Remove an Exclusion"
        Write-MenuItem -Text "[6]  Exclusion Status Report"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ("$choice".ToUpper()) {
            "1" {
                Add-HyperVDefenderExclusions
                Write-PressEnter
            }
            "2" {
                Write-OutputColor "" -color "Info"
                $customPath = Read-Host "  Enter path to exclude"
                $navResult = Test-NavigationCommand -UserInput $customPath
                if ($navResult.ShouldReturn) { return }
                if ($customPath) { $customPath = $customPath.Trim('"') }
                if ($customPath -and (Test-Path -LiteralPath $customPath -IsValid)) {
                    try {
                        Add-MpPreference -ExclusionPath $customPath -ErrorAction Stop
                        Write-OutputColor "  Added path exclusion: $customPath" -color "Success"
                        Add-SessionChange -Category "Security" -Description "Added Defender exclusion: $customPath"
                        Clear-MenuCache
                        Add-UndoAction -Category "Security" -Description "Added Defender exclusion: $customPath" -UndoScript {
                            param($Path)
                            Remove-MpPreference -ExclusionPath $Path -ErrorAction SilentlyContinue
                        }.GetNewClosure() -UndoParams @{ Path = $customPath }
                    }
                    catch {
                        Write-RackStackError -Code "RS-3007" -Detail "Defender exclusion failed for path '$customPath': $($_.Exception.Message)"
                        Write-OutputColor "  Failed to add exclusion: $_" -color "Error"
                    }
                } else {
                    Write-OutputColor "  Invalid path." -color "Error"
                }
                Write-PressEnter
            }
            "3" {
                Write-OutputColor "" -color "Info"
                $customProc = Read-Host "  Enter process name to exclude (e.g., myapp.exe)"
                $navResult = Test-NavigationCommand -UserInput $customProc
                if ($navResult.ShouldReturn) { return }
                if ($customProc) {
                    try {
                        Add-MpPreference -ExclusionProcess $customProc -ErrorAction Stop
                        Write-OutputColor "  Added process exclusion: $customProc" -color "Success"
                        Add-SessionChange -Category "Security" -Description "Added Defender process exclusion: $customProc"
                        Clear-MenuCache
                        Add-UndoAction -Category "Security" -Description "Added Defender process exclusion: $customProc" -UndoScript {
                            param($Proc)
                            Remove-MpPreference -ExclusionProcess $Proc -ErrorAction SilentlyContinue
                        }.GetNewClosure() -UndoParams @{ Proc = $customProc }
                    }
                    catch {
                        Write-OutputColor "  Failed to add exclusion: $_" -color "Error"
                    }
                }
                Write-PressEnter
            }
            "4" {
                Show-AllDefenderExclusions
                Write-PressEnter
            }
            "5" {
                Remove-DefenderExclusion
                Write-PressEnter
            }
            "6" {
                Show-DefenderExclusionStatus
                Write-PressEnter
            }
            "B" { return }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-6 or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Function to add recommended Hyper-V exclusions
function Add-HyperVDefenderExclusions {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  HYPER-V RECOMMENDED EXCLUSIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Paths:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("    - Default VM location (C:\ProgramData\Microsoft\Windows\Hyper-V)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("    - VM storage paths (D:\Virtual Machines, etc.)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("    - Cluster storage (C:\ClusterStorage)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  ".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Processes:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("    - vmms.exe (VM Management Service)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("    - vmwp.exe (VM Worker Process)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("    - vmsp.exe (VM Security Process)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("    - vmcompute.exe (VM Compute)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  ".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Extensions: .vhd, .vhdx, .avhd, .avhdx, .vsv, .iso".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Pre-check: warn if Hyper-V is not installed
    if (-not (Test-HyperVInstalled)) {
        Write-OutputColor "  Note: Hyper-V is not currently installed on this system." -color "Warning"
        Write-OutputColor "  These exclusions are only useful if Hyper-V will be installed." -color "Warning"
        Write-OutputColor "" -color "Info"
    }

    if (-not (Confirm-UserAction -Message "Add all recommended Hyper-V exclusions?")) {
        return
    }

    $added = 0
    $errors = 0
    $addedPaths = @()
    $addedProcesses = @()
    $addedExtensions = @()

    # Path exclusions (configurable via defaults.json DefenderExclusionPaths)
    $pathsToExclude = @($script:DefenderExclusionPaths)

    # Add custom VM storage path if set
    if ($script:HostVMStoragePath -and (Test-Path -LiteralPath $script:HostVMStoragePath)) {
        $pathsToExclude += $script:HostVMStoragePath
    }

    # Check common VM storage locations (configurable via defaults.json DefenderCommonVMPaths)
    foreach ($vmPath in $script:DefenderCommonVMPaths) {
        if (Test-Path -LiteralPath $vmPath) {
            $pathsToExclude += $vmPath
        }
    }

    # Get unique paths
    $pathsToExclude = $pathsToExclude | Select-Object -Unique

    foreach ($path in $pathsToExclude) {
        try {
            Add-MpPreference -ExclusionPath $path -ErrorAction Stop
            Write-OutputColor "  Added path: $path" -color "Success"
            $addedPaths += $path
            $added++
        }
        catch {
            if ($_.Exception.Message -notlike "*already exists*") {
                Write-OutputColor "  Failed to add path $path : $_" -color "Error"
                $errors++
            } else {
                Write-OutputColor "  Already excluded: $path" -color "Info"
            }
        }
    }

    # Process exclusions
    $processesToExclude = @(
        "vmms.exe"
        "vmwp.exe"
        "vmsp.exe"
        "vmcompute.exe"
    )

    foreach ($proc in $processesToExclude) {
        try {
            Add-MpPreference -ExclusionProcess $proc -ErrorAction Stop
            Write-OutputColor "  Added process: $proc" -color "Success"
            $addedProcesses += $proc
            $added++
        }
        catch {
            if ($_.Exception.Message -notlike "*already exists*") {
                Write-OutputColor "  Failed to add process $proc : $_" -color "Error"
                $errors++
            } else {
                Write-OutputColor "  Already excluded: $proc" -color "Info"
            }
        }
    }

    # Extension exclusions
    $extensionsToExclude = @(".vhd", ".vhdx", ".avhd", ".avhdx", ".vsv", ".iso", ".vhds")

    foreach ($ext in $extensionsToExclude) {
        try {
            Add-MpPreference -ExclusionExtension $ext -ErrorAction Stop
            Write-OutputColor "  Added extension: $ext" -color "Success"
            $addedExtensions += $ext
            $added++
        }
        catch {
            if ($_.Exception.Message -notlike "*already exists*") {
                Write-OutputColor "  Failed to add extension $ext : $_" -color "Error"
                $errors++
            } else {
                Write-OutputColor "  Already excluded: $ext" -color "Info"
            }
        }
    }

    Write-OutputColor "" -color "Info"
    if ($errors -eq 0) {
        Write-OutputColor "  Hyper-V exclusions configured successfully! ($added items)" -color "Success"
    } else {
        Write-OutputColor "  Completed with $errors errors. $added items added." -color "Warning"
    }
    Add-SessionChange -Category "Security" -Description "Configured Windows Defender Hyper-V exclusions"
    Clear-MenuCache
    if ($added -gt 0) {
        Add-UndoAction -Category "Security" -Description "Added Hyper-V Defender exclusions ($added items)" -UndoScript {
            param($Paths, $Processes, $Extensions)
            foreach ($p in $Paths) { Remove-MpPreference -ExclusionPath $p -ErrorAction SilentlyContinue }
            foreach ($p in $Processes) { Remove-MpPreference -ExclusionProcess $p -ErrorAction SilentlyContinue }
            foreach ($e in $Extensions) { Remove-MpPreference -ExclusionExtension $e -ErrorAction SilentlyContinue }
        }.GetNewClosure() -UndoParams @{ Paths = $addedPaths; Processes = $addedProcesses; Extensions = $addedExtensions }
    }
}

# Function to show all Defender exclusions
function Show-AllDefenderExclusions {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    ALL DEFENDER EXCLUSIONS").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $prefs = Get-MpPreference -ErrorAction Stop
    }
    catch {
        Write-OutputColor "  Failed to read Defender preferences: $_" -color "Error"
        return
    }

    # Path exclusions
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  PATH EXCLUSIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    if ($prefs.ExclusionPath) {
        $idx = 1
        foreach ($path in $prefs.ExclusionPath) {
            $displayPath = if ($path.Length -gt 64) { $path.Substring(0,61) + "..." } else { $path }
            Write-OutputColor "  │$("  $idx. $displayPath".PadRight(72))│" -color "Success"
            $idx++
        }
    } else {
        Write-OutputColor "  │$("  (none)".PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Process exclusions
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  PROCESS EXCLUSIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    if ($prefs.ExclusionProcess) {
        foreach ($proc in $prefs.ExclusionProcess) {
            $lineStr = "  - $proc"
            if ($lineStr.Length -gt 72) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Success"
        }
    } else {
        Write-OutputColor "  │$("  (none)".PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Extension exclusions
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  EXTENSION EXCLUSIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    if ($prefs.ExclusionExtension) {
        $extList = $prefs.ExclusionExtension -join ", "
        $lineStr = "  $extList"
        if ($lineStr.Length -gt 72) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Success"
    } else {
        Write-OutputColor "  │$("  (none)".PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

# Function to remove a Defender exclusion
function Remove-DefenderExclusion {
    try {
        $prefs = Get-MpPreference -ErrorAction Stop
    }
    catch {
        Write-OutputColor "  Failed to read Defender preferences: $_" -color "Error"
        return
    }
    $allExclusions = @()

    # Build list of all exclusions
    if ($prefs.ExclusionPath) {
        foreach ($path in $prefs.ExclusionPath) {
            $allExclusions += @{ Type = "Path"; Value = $path }
        }
    }
    if ($prefs.ExclusionProcess) {
        foreach ($proc in $prefs.ExclusionProcess) {
            $allExclusions += @{ Type = "Process"; Value = $proc }
        }
    }
    if ($prefs.ExclusionExtension) {
        foreach ($ext in $prefs.ExclusionExtension) {
            $allExclusions += @{ Type = "Extension"; Value = $ext }
        }
    }

    if ($allExclusions.Count -eq 0) {
        Write-OutputColor "  No exclusions to remove." -color "Info"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Select exclusion to remove:" -color "Info"
    $idx = 1
    foreach ($excl in $allExclusions) {
        $display = if ($excl.Value -and $excl.Value.Length -gt 55) { $excl.Value.Substring(0,52) + "..." } elseif ($excl.Value) { $excl.Value } else { "(empty)" }
        Write-OutputColor "  [$idx] ($($excl.Type)) $display" -color "Info"
        $idx++
    }
    Write-OutputColor "  [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    if ($choice -match '^\d+$') {
        $selIdx = [int]$choice - 1
        if ($selIdx -ge 0 -and $selIdx -lt $allExclusions.Count) {
            $selected = $allExclusions[$selIdx]
            try {
                switch ($selected.Type) {
                    "Path" { Remove-MpPreference -ExclusionPath $selected.Value -ErrorAction Stop }
                    "Process" { Remove-MpPreference -ExclusionProcess $selected.Value -ErrorAction Stop }
                    "Extension" { Remove-MpPreference -ExclusionExtension $selected.Value -ErrorAction Stop }
                }
                Write-OutputColor "  Removed $($selected.Type) exclusion: $($selected.Value)" -color "Success"
                Add-SessionChange -Category "Security" -Description "Removed Defender exclusion: $($selected.Value)"
                Clear-MenuCache
                Add-UndoAction -Category "Security" -Description "Removed Defender $($selected.Type) exclusion: $($selected.Value)" -UndoScript {
                    param($ExclType, $ExclValue)
                    switch ($ExclType) {
                        "Path" { Add-MpPreference -ExclusionPath $ExclValue -ErrorAction SilentlyContinue }
                        "Process" { Add-MpPreference -ExclusionProcess $ExclValue -ErrorAction SilentlyContinue }
                        "Extension" { Add-MpPreference -ExclusionExtension $ExclValue -ErrorAction SilentlyContinue }
                    }
                }.GetNewClosure() -UndoParams @{ ExclType = $selected.Type; ExclValue = $selected.Value }
            }
            catch {
                Write-OutputColor "  Failed to remove exclusion: $_" -color "Error"
            }
        }
    }
}

# Windows Defender Status Dashboard
function Show-DefenderStatus {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    WINDOWS DEFENDER STATUS").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Get Defender status
    try {
        $mpStatus = Get-MpComputerStatus -ErrorAction Stop
    } catch {
        Write-OutputColor "  Windows Defender is not available: $_" -color "Error"
        return
    }

    # Protection status
    $rtColor = if ($mpStatus.RealTimeProtectionEnabled) { "Success" } else { "Error" }
    $bhColor = if ($mpStatus.BehaviorMonitorEnabled) { "Success" } else { "Warning" }
    $ioColor = if ($mpStatus.IoavProtectionEnabled) { "Success" } else { "Warning" }
    $niColor = if ($mpStatus.NISEnabled) { "Success" } else { "Warning" }
    $amColor = if ($mpStatus.AntispywareEnabled) { "Success" } else { "Warning" }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  PROTECTION STATUS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    $rtText = if ($mpStatus.RealTimeProtectionEnabled) { "Enabled" } else { "DISABLED" }
    $bhText = if ($mpStatus.BehaviorMonitorEnabled) { "Enabled" } else { "Disabled" }
    $ioText = if ($mpStatus.IoavProtectionEnabled) { "Enabled" } else { "Disabled" }
    $niText = if ($mpStatus.NISEnabled) { "Enabled" } else { "Disabled" }
    $amText = if ($mpStatus.AntispywareEnabled) { "Enabled" } else { "Disabled" }
    Write-OutputColor "  │$("  Real-time Protection:  $rtText".PadRight(72))│" -color $rtColor
    Write-OutputColor "  │$("  Behavior Monitor:      $bhText".PadRight(72))│" -color $bhColor
    Write-OutputColor "  │$("  Download Scanning:     $ioText".PadRight(72))│" -color $ioColor
    Write-OutputColor "  │$("  Network Inspection:    $niText".PadRight(72))│" -color $niColor
    Write-OutputColor "  │$("  Antispyware:           $amText".PadRight(72))│" -color $amColor
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Signature info
    $sigAge = if ($null -ne $mpStatus.AntivirusSignatureAge) { $mpStatus.AntivirusSignatureAge } else { "Unknown" }
    $sigColor = if ($sigAge -is [int] -and $sigAge -le 1) { "Success" } elseif ($sigAge -is [int] -and $sigAge -le 7) { "Warning" } else { "Error" }
    $sigDate = if ($null -ne $mpStatus.AntivirusSignatureLastUpdated) { $mpStatus.AntivirusSignatureLastUpdated.ToString("MM/dd/yyyy HH:mm") } else { "Unknown" }
    $sigVer = if ($mpStatus.AntivirusSignatureVersion) { $mpStatus.AntivirusSignatureVersion } else { "Unknown" }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SIGNATURE STATUS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Signature Version:     $sigVer".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Last Updated:          $sigDate".PadRight(72))│" -color $sigColor
    Write-OutputColor "  │$("  Signature Age:         $sigAge day(s)".PadRight(72))│" -color $sigColor
    Write-OutputColor "  │$("  Engine Version:        $($mpStatus.AMEngineVersion)".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Scan history
    $lastFull = if ($null -ne $mpStatus.FullScanEndTime -and $mpStatus.FullScanEndTime.Year -gt 2000) { $mpStatus.FullScanEndTime.ToString("MM/dd/yyyy HH:mm") } else { "Never" }
    $lastQuick = if ($null -ne $mpStatus.QuickScanEndTime -and $mpStatus.QuickScanEndTime.Year -gt 2000) { $mpStatus.QuickScanEndTime.ToString("MM/dd/yyyy HH:mm") } else { "Never" }
    $fullAge = if ($null -ne $mpStatus.FullScanAge) { $mpStatus.FullScanAge } else { "Unknown" }
    $quickAge = if ($null -ne $mpStatus.QuickScanAge) { $mpStatus.QuickScanAge } else { "Unknown" }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SCAN HISTORY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Last Full Scan:        $lastFull ($fullAge day(s) ago)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Last Quick Scan:       $lastQuick ($quickAge day(s) ago)".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Threat detection history
    $threats = @()
    try {
        $threats = @(Get-MpThreatDetection -ErrorAction Stop)
        if ($threats.Count -gt 0) {
            $recent = @($threats | Sort-Object InitialDetectionTime -Descending | Select-Object -First 10)
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Warning"
            Write-OutputColor "  │$("  RECENT THREAT DETECTIONS ($($threats.Count) total)".PadRight(72))│" -color "Warning"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Warning"
            foreach ($threat in $recent) {
                $tName = if ($threat.ThreatName) { $threat.ThreatName } else { "Unknown" }
                if ($tName.Length -gt 42) { $tName = $tName.Substring(0, 39) + "..." }
                $tDate = if ($null -ne $threat.InitialDetectionTime) { $threat.InitialDetectionTime.ToString("MM/dd HH:mm") } else { "N/A" }
                $line = "  $($tName.PadRight(44)) $tDate"
                Write-OutputColor "  │$($line.PadRight(72))│" -color "Warning"
            }
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Warning"
        } else {
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Success"
            Write-OutputColor "  │$("  No threat detections found.".PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Success"
        }
    } catch {
        Write-OutputColor "  Could not query threat history: $_" -color "Warning"
    }

    Add-SessionChange -Category "Security" -Description "Viewed Defender status: RT=$rtText, Sig age=$sigAge days, Threats=$(@($threats).Count)"
}

# Function to show all current Defender exclusions with validation
function Show-DefenderExclusionStatus {
    Write-OutputColor "`n  Windows Defender Exclusion Status:" -color "Info"

    try {
        $prefs = Get-MpPreference -ErrorAction Stop

        $pathExclusions = @($prefs.ExclusionPath | Where-Object { $null -ne $_ })
        $extExclusions = @($prefs.ExclusionExtension | Where-Object { $null -ne $_ })
        $procExclusions = @($prefs.ExclusionProcess | Where-Object { $null -ne $_ })

        if ($pathExclusions.Count -gt 0) {
            Write-OutputColor "`n  Path Exclusions ($($pathExclusions.Count)):" -color "Info"
            foreach ($path in $pathExclusions) {
                $exists = Test-Path -LiteralPath $path -ErrorAction SilentlyContinue
                $color = if ($exists) { "Success" } else { "Warning" }
                $tag = if (-not $exists) { " [PATH NOT FOUND]" } else { "" }
                Write-OutputColor "    $path$tag" -color $color
            }
        }

        if ($extExclusions.Count -gt 0) {
            Write-OutputColor "`n  Extension Exclusions ($($extExclusions.Count)):" -color "Info"
            foreach ($ext in $extExclusions) {
                $displayExt = if ($ext.StartsWith('.')) { $ext } else { ".$ext" }
                Write-OutputColor "    $displayExt" -color "Info"
            }
        }

        if ($procExclusions.Count -gt 0) {
            Write-OutputColor "`n  Process Exclusions ($($procExclusions.Count)):" -color "Info"
            foreach ($proc in $procExclusions) {
                Write-OutputColor "    $proc" -color "Info"
            }
        }

        $total = $pathExclusions.Count + $extExclusions.Count + $procExclusions.Count
        if ($total -eq 0) {
            Write-OutputColor "  No exclusions configured" -color "Info"
        } else {
            Write-OutputColor "`n  Total exclusions: $total" -color "Info"
        }
    } catch {
        Write-OutputColor "  Cannot read Defender preferences: $($_.Exception.Message)" -color "Warning"
    }
}
#endregion