#region ===== WINDOWS DEFENDER EXCLUSIONS =====
# Function to configure Windows Defender exclusions for Hyper-V
function Set-DefenderExclusions {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    WINDOWS DEFENDER EXCLUSIONS").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

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

    # Show current exclusions
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CURRENT EXCLUSIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $prefs = Get-MpPreference
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
            Write-OutputColor "  │$("    $proc".PadRight(72))│" -color "Success"
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
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    switch ($choice) {
        "1" {
            Add-HyperVDefenderExclusions
        }
        "2" {
            Write-OutputColor "" -color "Info"
            $customPath = Read-Host "  Enter path to exclude"
            $navResult = Test-NavigationCommand -UserInput $customPath
            if ($navResult.ShouldReturn) { continue }
            if ($customPath -and (Test-Path $customPath -IsValid)) {
                try {
                    Add-MpPreference -ExclusionPath $customPath -ErrorAction Stop
                    Write-OutputColor "  Added path exclusion: $customPath" -color "Success"
                    Add-SessionChange -Category "Security" -Description "Added Defender exclusion: $customPath"
                }
                catch {
                    Write-OutputColor "  Failed to add exclusion: $_" -color "Error"
                }
            } else {
                Write-OutputColor "  Invalid path." -color "Error"
            }
        }
        "3" {
            Write-OutputColor "" -color "Info"
            $customProc = Read-Host "  Enter process name to exclude (e.g., myapp.exe)"
            $navResult = Test-NavigationCommand -UserInput $customProc
            if ($navResult.ShouldReturn) { continue }
            if ($customProc) {
                try {
                    Add-MpPreference -ExclusionProcess $customProc -ErrorAction Stop
                    Write-OutputColor "  Added process exclusion: $customProc" -color "Success"
                    Add-SessionChange -Category "Security" -Description "Added Defender process exclusion: $customProc"
                }
                catch {
                    Write-OutputColor "  Failed to add exclusion: $_" -color "Error"
                }
            }
        }
        "4" {
            Show-AllDefenderExclusions
        }
        "5" {
            Remove-DefenderExclusion
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

    if (-not (Confirm-UserAction -Message "Add all recommended Hyper-V exclusions?")) {
        return
    }

    $added = 0
    $errors = 0

    # Path exclusions (configurable via defaults.json DefenderExclusionPaths)
    $pathsToExclude = @($script:DefenderExclusionPaths)

    # Add custom VM storage path if set
    if ($script:HostVMStoragePath -and (Test-Path $script:HostVMStoragePath)) {
        $pathsToExclude += $script:HostVMStoragePath
    }

    # Check common VM storage locations (configurable via defaults.json DefenderCommonVMPaths)
    foreach ($vmPath in $script:DefenderCommonVMPaths) {
        if (Test-Path $vmPath) {
            $pathsToExclude += $vmPath
        }
    }

    # Get unique paths
    $pathsToExclude = $pathsToExclude | Select-Object -Unique

    foreach ($path in $pathsToExclude) {
        try {
            Add-MpPreference -ExclusionPath $path -ErrorAction Stop
            Write-OutputColor "  Added path: $path" -color "Success"
            $added++
        }
        catch {
            if ($_.Exception.Message -notlike "*already exists*") {
                Write-OutputColor "  Failed to add path $path : $_" -color "Warning"
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
            $added++
        }
        catch {
            if ($_.Exception.Message -notlike "*already exists*") {
                Write-OutputColor "  Failed to add process $proc : $_" -color "Warning"
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
            $added++
        }
        catch {
            if ($_.Exception.Message -notlike "*already exists*") {
                Write-OutputColor "  Failed to add extension $ext : $_" -color "Warning"
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
}

# Function to show all Defender exclusions
function Show-AllDefenderExclusions {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    ALL DEFENDER EXCLUSIONS").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $prefs = Get-MpPreference

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
            Write-OutputColor "  │$("  - $proc".PadRight(72))│" -color "Success"
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
        Write-OutputColor "  │$("  $extList".PadRight(72))│" -color "Success"
    } else {
        Write-OutputColor "  │$("  (none)".PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    Write-PressEnter
}

# Function to remove a Defender exclusion
function Remove-DefenderExclusion {
    $prefs = Get-MpPreference
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
        $display = if ($excl.Value.Length -gt 55) { $excl.Value.Substring(0,52) + "..." } else { $excl.Value }
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
            }
            catch {
                Write-OutputColor "  Failed to remove exclusion: $_" -color "Error"
            }
        }
    }
}
#endregion