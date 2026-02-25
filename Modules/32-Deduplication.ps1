#region ===== DATA DEDUPLICATION =====
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
        switch ($choice) {
            { $_ -eq "I" -or $_ -eq "i" } {
                if (-not (Confirm-UserAction -Message "Install Data Deduplication feature?")) { return }
                try {
                    Write-OutputColor "  Installing Data Deduplication..." -color "Info"
                    Install-WindowsFeature -Name FS-Data-Deduplication -IncludeManagementTools -ErrorAction Stop
                    Write-OutputColor "  Data Deduplication installed." -color "Success"
                    Add-SessionChange -Category "System" -Description "Installed Data Deduplication"
                }
                catch {
                    Write-OutputColor "  Failed: $_" -color "Error"
                }
                Write-PressEnter
            }
            default { }
        }
        return
    }

    while ($true) {
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

        $volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq "Fixed" }
        $idx = 1
        $volList = @()
        foreach ($vol in $volumes) {
            $dedupStatus = Get-DedupStatus -Volume "$($vol.DriveLetter):" -ErrorAction SilentlyContinue
            $dedupConfig = Get-DedupVolume -Volume "$($vol.DriveLetter):" -ErrorAction SilentlyContinue
            if ($dedupConfig) {
                $enabled = $dedupConfig.Enabled
                $savedGB = if ($dedupStatus) { [math]::Round($dedupStatus.SavedSpace / 1GB, 2) } else { 0 }
                $ratio = if ($dedupStatus) { "$([math]::Round($dedupStatus.SavingsRate, 1))%" } else { "N/A" }
                $color = if ($enabled) { "Success" } else { "Warning" }
                Write-OutputColor "  │$("  [$idx] $($vol.DriveLetter): Enabled: $enabled | Saved: $savedGB GB ($ratio)".PadRight(72))│" -color $color
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
                if ($volNum -match '^\d+$' -and [int]$volNum -ge 1 -and [int]$volNum -le $volList.Count) {
                    $vol = $volList[[int]$volNum - 1]
                    Write-OutputColor "" -color "Info"
                    Write-OutputColor "  Usage Type:" -color "Info"
                    Write-OutputColor "  [1] Default (general file server)" -color "Info"
                    Write-OutputColor "  [2] Hyper-V (VHD files)" -color "Info"
                    Write-OutputColor "  [3] Backup (backup applications)" -color "Info"
                    $usageType = Read-Host "  Select type"

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
                    }
                    catch {
                        Write-OutputColor "  Failed: $_" -color "Error"
                    }
                }
            }
            "2" {
                $volNum = Read-Host "  Enter volume number to disable dedup"
                if ($volNum -match '^\d+$' -and [int]$volNum -ge 1 -and [int]$volNum -le $volList.Count) {
                    $vol = $volList[[int]$volNum - 1]
                    if (Confirm-UserAction -Message "Disable deduplication on $($vol.DriveLetter):?") {
                        try {
                            Disable-DedupVolume -Volume "$($vol.DriveLetter):" -ErrorAction Stop
                            Write-OutputColor "  Deduplication disabled on $($vol.DriveLetter):" -color "Success"
                            Add-SessionChange -Category "Storage" -Description "Disabled deduplication on $($vol.DriveLetter):"
                        }
                        catch {
                            Write-OutputColor "  Failed: $_" -color "Error"
                        }
                    }
                }
            }
            "3" {
                $volNum = Read-Host "  Enter volume number to optimize"
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
            }
            "4" {
                $volNum = Read-Host "  Enter volume number"
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
            }
            "b" { return }
            "B" { return }
        }

        Write-PressEnter
    }
}
#endregion