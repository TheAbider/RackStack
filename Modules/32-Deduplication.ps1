#region ===== DATA DEDUPLICATION =====
# Function to show deduplication savings report across all volumes
function Show-DedupSavings {
    try {
        $dedupVolumes = Get-DedupStatus -ErrorAction Stop
        if ($null -eq $dedupVolumes -or @($dedupVolumes).Count -eq 0) {
            Write-OutputColor "  No deduplication-enabled volumes found" -color "Info"
            return
        }

        Write-OutputColor "`n  Deduplication Savings Report:" -color "Info"

        foreach ($vol in $dedupVolumes) {
            $savings = if ($null -ne $vol.SavedSpace) { [math]::Round($vol.SavedSpace / 1GB, 1) } else { 0 }
            $ratio = if ($null -ne $vol.OptimizedFilesCount) { $vol.OptimizedFilesCount } else { 0 }
            $rate = if ($null -ne $vol.SavingsRate) { $vol.SavingsRate } else { 0 }

            $color = if ($rate -gt 30) { "Success" } elseif ($rate -gt 10) { "Info" } else { "Warning" }
            Write-OutputColor "`n  Volume: $($vol.Volume)" -color "Info"
            Write-OutputColor "    Space Saved: ${savings} GB ($rate% savings rate)" -color $color
            Write-OutputColor "    Optimized Files: $ratio" -color "Info"
            Write-OutputColor "    Last Optimization: $($vol.LastOptimizationTime)" -color "Info"
        }
    } catch {
        Write-OutputColor "  Deduplication not available: $($_.Exception.Message)" -color "Error"
    }
}

# Function to manage Data Deduplication
function Show-DeduplicationManagement {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                      DATA DEDUPLICATION").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Check if Dedup is installed
    $dedupFeature = if (Test-WindowsServer) { Get-WindowsFeature -Name FS-Data-Deduplication -ErrorAction SilentlyContinue } else { $null }
    if (-not $dedupFeature -or $dedupFeature.InstallState -ne "Installed") {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  Data Deduplication is not installed.".PadRight(72))│" -color "Warning"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [I] Install Data Deduplication" -color "Success"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }
        switch ($choice) {
            { $_ -eq "I" -or $_ -eq "i" } {
                if (-not (Confirm-UserAction -Message "Install Data Deduplication feature?")) { return }
                $installResult = Install-WindowsFeatureWithTimeout -FeatureName "FS-Data-Deduplication" -DisplayName "Data Deduplication" -IncludeManagementTools
                if ($installResult.Success) {
                    Add-SessionChange -Category "System" -Description "Installed Data Deduplication"
                    Clear-MenuCache
                }
                Write-PressEnter
            }
            default { Write-OutputColor "  Invalid selection. Enter I or B." -color "Error"; Start-Sleep -Seconds 1 }
        }
        return
    }

    while ($true) {
        if ($global:ReturnToMainMenu) { return }
        # Show current dedup status
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                      DATA DEDUPLICATION").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  DEDUPLICATION STATUS BY VOLUME".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        $volumes = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveType -eq "Fixed" }
        $idx = 1
        $volList = @()
        foreach ($vol in $volumes) {
            $dedupStatus = Get-DedupStatus -Volume "$($vol.DriveLetter):" -ErrorAction SilentlyContinue
            $dedupConfig = Get-DedupVolume -Volume "$($vol.DriveLetter):" -ErrorAction SilentlyContinue
            if ($dedupConfig) {
                $enabled = $dedupConfig.Enabled
                $savedGB = if ($dedupStatus) { [math]::Round($dedupStatus.SavedSpace / 1GB, 2) } else { 0 }
                $ratio = if ($dedupStatus) { "$([math]::Round($dedupStatus.SavingsRate, 1))%" } else { "N/A" }
                $lastOpt = if ($dedupStatus -and $dedupStatus.LastOptimizationTime) {
                    $delta = (Get-Date) - $dedupStatus.LastOptimizationTime
                    if ($delta.TotalHours -lt 1) { "$([math]::Round($delta.TotalMinutes))m ago" }
                    elseif ($delta.TotalDays -lt 1) { "$([math]::Round($delta.TotalHours, 1))h ago" }
                    else { "$([math]::Round($delta.TotalDays, 1))d ago" }
                } else { "Never" }
                $color = if ($enabled) { "Success" } else { "Warning" }
                Write-OutputColor "  │$("  [$idx] $($vol.DriveLetter): Enabled: $enabled | Saved: $savedGB GB ($ratio)".PadRight(72))│" -color $color
                Write-OutputColor "  │$("      Last optimized: $lastOpt".PadRight(72))│" -color "Debug"
            }
            else {
                Write-OutputColor "  │$("  [$idx] $($vol.DriveLetter): Not configured".PadRight(72))│" -color "Warning"
            }
            $volList += $vol
            $idx++
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  OPTIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem -Text "[1]  Enable Deduplication on Volume"
        Write-MenuItem -Text "[2]  Disable Deduplication on Volume"
        Write-MenuItem -Text "[3]  Start Deduplication Job Now"
        Write-MenuItem -Text "[4]  Show Deduplication Statistics"
        Write-MenuItem -Text "[5]  Show Savings Report"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" {
                $volNum = Read-Host "  Enter volume number to enable dedup"
                $navResult = Test-NavigationCommand -UserInput $volNum
                if ($navResult.ShouldReturn) { return }
                if ($volNum -match '^\d+$' -and [int]$volNum -ge 1 -and [int]$volNum -le $volList.Count) {
                    $vol = $volList[[int]$volNum - 1]
                    Write-OutputColor "" -color "Info"
                    Write-OutputColor "  Usage Type:" -color "Info"
                    Write-OutputColor "  [1] Default (general file server)" -color "Info"
                    Write-OutputColor "  [2] Hyper-V (VHD files)" -color "Info"
                    Write-OutputColor "  [3] Backup (backup applications)" -color "Info"
                    $usageType = Read-Host "  Select type"
                    $navResult = Test-NavigationCommand -UserInput $usageType
                    if ($navResult.ShouldReturn) { return }

                    $usage = switch ($usageType) {
                        "1" { "Default" }
                        "2" { "HyperV" }
                        "3" { "Backup" }
                        default { "Default" }
                    }

                    try {
                        Enable-DedupVolume -Volume "$($vol.DriveLetter):" -UsageType $usage -ErrorAction Stop
                        Write-OutputColor "  Deduplication enabled on $($vol.DriveLetter): with $usage profile." -color "Success"
                        Add-SessionChange -Category "Storage" -Description "Enabled deduplication on $($vol.DriveLetter):"
                        Clear-MenuCache
                    }
                    catch {
                        Write-OutputColor "  Failed: $_" -color "Error"
                    }
                }
                else { Write-OutputColor "  Invalid selection. Enter 1-$($volList.Count)." -color "Error" }
            }
            "2" {
                $volNum = Read-Host "  Enter volume number to disable dedup"
                $navResult = Test-NavigationCommand -UserInput $volNum
                if ($navResult.ShouldReturn) { return }
                if ($volNum -match '^\d+$' -and [int]$volNum -ge 1 -and [int]$volNum -le $volList.Count) {
                    $vol = $volList[[int]$volNum - 1]
                    if (Confirm-UserAction -Message "Disable deduplication on $($vol.DriveLetter):?") {
                        try {
                            Disable-DedupVolume -Volume "$($vol.DriveLetter):" -ErrorAction Stop
                            Write-OutputColor "  Deduplication disabled on $($vol.DriveLetter):" -color "Success"
                            Add-SessionChange -Category "Storage" -Description "Disabled deduplication on $($vol.DriveLetter):"
                            Clear-MenuCache
                        }
                        catch {
                            Write-OutputColor "  Failed: $_" -color "Error"
                        }
                    }
                }
                else { Write-OutputColor "  Invalid selection. Enter 1-$($volList.Count)." -color "Error" }
            }
            "3" {
                $volNum = Read-Host "  Enter volume number to optimize"
                $navResult = Test-NavigationCommand -UserInput $volNum
                if ($navResult.ShouldReturn) { return }
                if ($volNum -match '^\d+$' -and [int]$volNum -ge 1 -and [int]$volNum -le $volList.Count) {
                    $vol = $volList[[int]$volNum - 1]
                    try {
                        Write-OutputColor "  Starting optimization job..." -color "Info"
                        Start-DedupJob -Volume "$($vol.DriveLetter):" -Type Optimization -ErrorAction Stop
                        Write-OutputColor "  Optimization job started on $($vol.DriveLetter):" -color "Success"
                    }
                    catch {
                        Write-OutputColor "  Failed: $_" -color "Error"
                    }
                }
                else { Write-OutputColor "  Invalid selection. Enter 1-$($volList.Count)." -color "Error" }
            }
            "4" {
                $volNum = Read-Host "  Enter volume number"
                $navResult = Test-NavigationCommand -UserInput $volNum
                if ($navResult.ShouldReturn) { return }
                if ($volNum -match '^\d+$' -and [int]$volNum -ge 1 -and [int]$volNum -le $volList.Count) {
                    $vol = $volList[[int]$volNum - 1]
                    $stats = Get-DedupStatus -Volume "$($vol.DriveLetter):" -ErrorAction SilentlyContinue
                    if ($stats) {
                        Write-OutputColor "" -color "Info"
                        Write-OutputColor "  Deduplication Statistics for $($vol.DriveLetter):" -color "Info"
                        Write-OutputColor "  ─────────────────────────────────────────" -color "Info"
                        Write-OutputColor "  Optimized Files: $($stats.OptimizedFilesCount)" -color "Info"
                        Write-OutputColor "  In-Policy Files: $($stats.InPolicyFilesCount)" -color "Info"
                        Write-OutputColor "  Saved Space: $([math]::Round($stats.SavedSpace / 1GB, 2)) GB" -color "Success"
                        Write-OutputColor "  Savings Rate: $([math]::Round($stats.SavingsRate, 1))%" -color "Success"
                        Write-OutputColor "  Last Optimization: $($stats.LastOptimizationTime)" -color "Info"
                    }
                    else {
                        Write-OutputColor "  No statistics available." -color "Warning"
                    }
                }
                else { Write-OutputColor "  Invalid selection. Enter 1-$($volList.Count)." -color "Error" }
            }
            "5" {
                Show-DedupSavings
            }
            { $_ -eq "b" -or $_ -eq "B" } { return }
            default { Write-OutputColor "  Invalid choice. Enter 1-5 or B." -color "Error"; Start-Sleep -Seconds 1 }
        }

        Write-PressEnter
    }
}
#endregion