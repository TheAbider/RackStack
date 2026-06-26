#region ===== WINDOWS UPDATES =====
# Function to display recent Windows Update history
function Show-UpdateHistory {
    param([int]$Count = 20)

    Write-OutputColor "`n  Recent Windows Update History:" -color "Info"

    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $historyCount = $searcher.GetTotalHistoryCount()

        if ($historyCount -eq 0) {
            Write-OutputColor "  No update history found" -color "Warning"
            return
        }

        $history = $searcher.QueryHistory(0, [math]::Min($Count, $historyCount))

        foreach ($update in $history) {
            $status = switch ($update.ResultCode) {
                2 { "Succeeded" }
                3 { "Succeeded with errors" }
                4 { "Failed" }
                5 { "Aborted" }
                default { "Unknown" }
            }
            $color = switch ($update.ResultCode) {
                2 { "Success" }
                3 { "Warning" }
                4 { "Error" }
                default { "Info" }
            }

            $date = $update.Date.ToString('yyyy-MM-dd HH:mm')
            # Extract KB number if present
            $kb = ""
            if ($update.Title -match '(KB\d+)') { $regexMatches = $matches; $kb = " [$($regexMatches[1])]" }
            $maxTitleLen = 55 - $kb.Length
            $title = if ($update.Title -and $update.Title.Length -gt $maxTitleLen) { $update.Title.Substring(0, $maxTitleLen - 3) + "..." } elseif ($update.Title) { $update.Title } else { "(unknown)" }
            Write-OutputColor "  $date  $status  $title$kb" -color $color
        }

        Write-OutputColor "`n  Showing $([math]::Min($Count, $historyCount)) of $historyCount total updates" -color "Info"
    } catch {
        Write-OutputColor "  Could not retrieve update history: $($_.Exception.Message)" -color "Warning"
    }
}

# Function to display Windows Updates menu
function Show-WindowsUpdatesMenu {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                          WINDOWS UPDATES").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-MenuItem "[1]  Install Windows Updates"
        Write-MenuItem "[2]  View Update History"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" { Install-WindowsUpdates }
            "2" {
                Show-UpdateHistory
                Write-PressEnter
            }
            "b" { return }
            "B" { return }
            default { Write-OutputColor "  Invalid choice. Enter 1-2 or B." -color "Error"; Start-Sleep -Seconds 1 }
        }
    }
}

# Function to install Windows updates with timeout protection
function Install-WindowsUpdates {
    Clear-Host
    Write-CenteredOutput "Windows Updates" -color "Info"

    # Check network connectivity
    Write-OutputColor "  Checking network connectivity..." -color "Info"
    if (-not (Test-NetworkConnectivity)) {
        Write-OutputColor "  No network connectivity detected. Cannot check for updates." -color "Error"
        Write-OutputColor "  Tip: Verify network configuration and DNS settings." -color "Warning"
        return
    }

    Write-OutputColor "  Network connectivity confirmed." -color "Success"
    Write-OutputColor "" -color "Info"

    # Pre-flight: PSWindowsUpdate installs from the PowerShell Gallery. On locked-down
    # networks that block it, Install-Module hangs for many minutes with no feedback (no
    # disk/CPU/network — it's stuck on a dropped TLS connect). If the module isn't already
    # present and the gallery isn't reachable, fail fast with actionable guidance instead.
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        if (-not (Test-NetworkConnectivity -Target 'www.powershellgallery.com')) {
            Write-OutputColor "  PSWindowsUpdate isn't installed and the PowerShell Gallery" -color "Error"
            Write-OutputColor "  (www.powershellgallery.com:443) isn't reachable from this server." -color "Error"
            Write-OutputColor "  Allow it through the firewall/proxy, or pre-install PSWindowsUpdate" -color "Warning"
            Write-OutputColor "  on this host, then retry. (Updates can still go via WSUS/SCCM/sconfig.)" -color "Warning"
            return
        }
    }

    try {
        # Suppress all PackageManagement/NuGet confirmation prompts
        $savedConfirmPref = $ConfirmPreference
        $ConfirmPreference = 'None'
        $needsRedraw = $false

        try {
            # Always ensure NuGet provider is bootstrapped (skip check — the check itself can prompt)
            $nuget = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue |
                Where-Object { $_.Version -ge [version]'2.8.5.201' }
            if (-not $nuget) {
                Write-OutputColor "  Installing NuGet provider..." -color "Info"
                $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ForceBootstrap -Confirm:$false -ErrorAction Stop
                $needsRedraw = $true
            }

            # Install PSWindowsUpdate module if needed
            $psWindowsUpdate = Get-Module -ListAvailable -Name PSWindowsUpdate
            if (-not $psWindowsUpdate) {
                Write-OutputColor "  Installing PSWindowsUpdate module..." -color "Info"
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
                Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck -Confirm:$false -ErrorAction Stop
                $needsRedraw = $true
            }
        }
        finally {
            $ConfirmPreference = $savedConfirmPref
        }

        Import-Module PSWindowsUpdate -ErrorAction Stop

        # Redraw header if module installation pushed it off screen
        if ($needsRedraw) {
            Clear-Host
            Write-CenteredOutput "Windows Updates" -color "Info"
        }

        # Check for updates with timeout and progress
        $timeoutSeconds = $script:UpdateTimeoutSeconds
        Write-OutputColor "  Checking for available updates (timeout: $($timeoutSeconds / 60) minutes)..." -color "Info"

        $job = Start-Job -ScriptBlock {
            Import-Module PSWindowsUpdate
            Get-WindowsUpdate -AcceptAll
        }

        # Show progress while waiting
        $elapsed = 0
        while ($job.State -eq "Running" -and $elapsed -lt $timeoutSeconds) {
            Show-ProgressMessage -Activity "Checking for updates" -Status "Scanning..." -SecondsElapsed $elapsed
            Start-Sleep -Seconds 1
            $elapsed++
        }
        Write-Host ""  # New line after progress

        if ($job.State -eq "Running") {
            Stop-Job $job -ErrorAction SilentlyContinue
            Remove-Job $job -Force -ErrorAction SilentlyContinue
            Complete-ProgressMessage -Activity "Update check" -Status "Timed out after $($timeoutSeconds / 60) minutes" -Failed
            Write-OutputColor "  This may indicate network issues or Windows Update service problems." -color "Warning"
            return
        }

        # Check if the scan job itself failed (don't misreport as "up to date")
        $scanJobFailed = $job.State -eq "Failed"
        $updates = Receive-Job $job -ErrorAction SilentlyContinue
        $scanError = $null
        if ($scanJobFailed) {
            try {
                if ($job.ChildJobs.Count -gt 0) { $scanError = $job.ChildJobs[0].Error | Out-String }
            } catch {
                Write-OutputColor "  Could not extract scan error details: $_" -color "Warning"
            }
        }
        Remove-Job $job -Force -ErrorAction SilentlyContinue

        if ($scanJobFailed) {
            Complete-ProgressMessage -Activity "Update check" -Status "Failed" -Failed
            Write-OutputColor "  Update scan failed. Cannot determine update status." -color "Error"
            if ($scanError) { Write-OutputColor "  Error: $($scanError.Trim())" -color "Error" }
            Write-OutputColor "  Tip: Check Windows Update service (wuauserv) and try again." -color "Warning"
            return
        }

        Complete-ProgressMessage -Activity "Update check" -Status "Complete" -Success

        if ($null -eq $updates -or @($updates).Count -eq 0) {
            Write-OutputColor "  No updates available. System is up to date!" -color "Success"
            return
        }

        $updateCount = @($updates).Count
        Write-OutputColor "  Found $updateCount update(s) available." -color "Info"

        # Group by category. Driver updates need explicit operator consent — bundling NIC /
        # storage driver upgrades with a routine cumulative on a Hyper-V host is how operators
        # lose console access after reboot (new NIC driver regresses RoCE/RDMA on the SET team
        # carrying SMB Direct → S2D resync stalls → VMs unresponsive). List per-category counts
        # so the operator sees what's actually about to install.
        $driverUpdates = @($updates | Where-Object {
            $cats = @()
            try { $cats = @($_.Categories | ForEach-Object { $_.Name }) } catch { }
            $cats -contains 'Drivers' -or $cats -contains 'Driver'
        })
        $featureUpdates = @($updates | Where-Object {
            $cats = @()
            try { $cats = @($_.Categories | ForEach-Object { $_.Name }) } catch { }
            $cats -contains 'Upgrades' -or $cats -contains 'Feature Packs'
        })
        $qualityUpdates = @($updates | Where-Object { $_ -notin $driverUpdates -and $_ -notin $featureUpdates })

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Update breakdown:" -color "Info"
        Write-OutputColor "    Quality / Security / Cumulative : $($qualityUpdates.Count)" -color "Info"
        Write-OutputColor "    Drivers                        : $($driverUpdates.Count)" -color $(if ($driverUpdates.Count -gt 0) { 'Warning' } else { 'Info' })
        Write-OutputColor "    Feature upgrades               : $($featureUpdates.Count)" -color $(if ($featureUpdates.Count -gt 0) { 'Warning' } else { 'Info' })
        Write-OutputColor "" -color "Info"

        # List updates
        Write-OutputColor "Available updates:" -color "Info"
        foreach ($update in $updates) {
            $size = if ($update.Size) { " ($([math]::Round($update.Size / 1MB, 1)) MB)" } else { "" }
            $catTag = ''
            try {
                $catNames = @($update.Categories | ForEach-Object { $_.Name })
                if ($catNames -contains 'Drivers' -or $catNames -contains 'Driver') { $catTag = ' [DRIVER]' }
                elseif ($catNames -contains 'Upgrades' -or $catNames -contains 'Feature Packs') { $catTag = ' [FEATURE]' }
            } catch { }
            $clr = if ($catTag) { 'Warning' } else { 'Info' }
            Write-OutputColor "  - $($update.Title)$size$catTag" -color $clr
        }
        Write-OutputColor "" -color "Info"

        # Two install paths: quality-only (safer, default) vs everything-including-drivers
        # (requires explicit second confirm). Driver updates on a production Hyper-V host
        # bundled into a cumulative-install rollout commonly brick NIC/storage paths.
        $installCategoriesFilter = $null
        if ($driverUpdates.Count -gt 0 -or $featureUpdates.Count -gt 0) {
            Write-OutputColor "  [1] Install QUALITY updates only ($($qualityUpdates.Count) update(s)) — RECOMMENDED" -color "Success"
            Write-OutputColor "  [2] Install ALL updates ($updateCount, includes drivers/feature upgrades)" -color "Warning"
            Write-OutputColor "  [3] Cancel" -color "Info"
            $installChoice = Read-Host "  Select"
            $navResult = Test-NavigationCommand -UserInput $installChoice
            if ($navResult.ShouldReturn) { return }
            switch ($installChoice) {
                "1" {
                    if ($qualityUpdates.Count -eq 0) {
                        Write-OutputColor "  No quality updates to install." -color "Info"
                        return
                    }
                    $installCategoriesFilter = @('Security Updates', 'Critical Updates', 'Update Rollups', 'Updates', 'Definition Updates')
                }
                "2" {
                    Write-OutputColor "" -color "Critical"
                    Write-OutputColor "  Installing $($driverUpdates.Count) driver and $($featureUpdates.Count) feature update(s)" -color "Warning"
                    Write-OutputColor "  bundled with quality updates can regress NIC/storage paths post-reboot." -color "Warning"
                    Write-OutputColor "  Type INSTALL-ALL to confirm:" -color "Critical"
                    $allConfirm = Read-Host
                    if ($allConfirm -ne 'INSTALL-ALL') {
                        Write-OutputColor "  Cancelled." -color "Info"
                        return
                    }
                    $installCategoriesFilter = $null  # don't filter
                }
                default {
                    Write-OutputColor "  Update installation cancelled." -color "Warning"
                    return
                }
            }
        } else {
            if (-not (Confirm-UserAction -Message "Install all $updateCount quality update(s)?")) {
                Write-OutputColor "  Update installation cancelled." -color "Warning"
                return
            }
        }

        if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
            # Updates that are pending at queue time may differ from updates
            # pending at commit time — the catalog and the operator's intent
            # ("quality only" vs "all") are captured, but the actual update
            # set is re-scanned at apply. Re-entry preserves the full job
            # progress UI and the TiWorker poll on timeout.
            $capFilter = $installCategoriesFilter
            $capCount  = $updateCount
            $filterLabel = if ($null -ne $capFilter) { "$($capFilter.Count) categor(y/ies)" } else { "all updates" }
            Push-DryRunStep -Label "Install Windows Updates ($capCount pending, filter: $filterLabel)" -Category "System" -OneWay $false `
                -Params @{ PendingCount = $capCount; CategoryFilter = $capFilter } `
                -Preflight {
                    if (-not (Test-NetworkConnectivity)) { "No network connectivity — update install will fail" }
                    else { $true }
                } `
                -Apply { Install-WindowsUpdates }
            Write-OutputColor "  Queued (Dry-Run): install Windows Updates ($filterLabel)." -color "Warning"
            Add-SessionChange -Category "DryRun" -Description "Queued Windows Updates install"
            return
        }

        Write-OutputColor "`nInstalling updates... This may take a while." -color "Warning"
        Write-OutputColor "  Please do not restart the computer during this process." -color "Critical"
        Write-OutputColor "" -color "Info"

        # Install updates with progress
        $installJob = $null
        $installJob = Start-Job -ScriptBlock {
            param($CatFilter)
            Import-Module PSWindowsUpdate
            if ($null -ne $CatFilter -and $CatFilter.Count -gt 0) {
                Install-WindowsUpdate -AcceptAll -IgnoreReboot -Category $CatFilter
            } else {
                Install-WindowsUpdate -AcceptAll -IgnoreReboot
            }
        } -ArgumentList (,$installCategoriesFilter)

        $elapsed = 0
        $maxInstallTime = 3600  # 1 hour max for install
        while ($installJob.State -eq "Running" -and $elapsed -lt $maxInstallTime) {
            Show-ProgressMessage -Activity "Installing updates" -Status "In progress" -SecondsElapsed $elapsed
            Start-Sleep -Seconds 1
            $elapsed++
        }
        Write-Host ""  # New line after progress

        if ($installJob.State -eq "Running") {
            Write-OutputColor "  Installation timed out after $([math]::Floor($maxInstallTime / 60)) minutes. Stopping job." -color "Warning"
            Stop-Job $installJob -ErrorAction SilentlyContinue
            # Stop-Job kills the PSWindowsUpdate runspace but NOT the out-of-process TiWorker.exe
            # that PSWindowsUpdate invokes via COM. If TiWorker is mid-SXS-commit and we reboot
            # now, the next boot hits "Stage 3 of 3" and rolls back — sometimes leaving CBS in
            # a broken state that needs `dism /restorehealth`. Poll for TiWorker exit (capped
            # at 2× the install timeout) before declaring "timed out".
            $maxTiWorkerWait = $maxInstallTime * 2
            $tiwElapsed = 0
            while ($tiwElapsed -lt $maxTiWorkerWait) {
                $tiw = Get-Process -Name TiWorker -ErrorAction SilentlyContinue
                if ($null -eq $tiw) { break }
                if ($tiwElapsed -eq 0) {
                    Write-OutputColor "  Waiting for TiWorker.exe to finish committing changes before declaring timeout..." -color "Warning"
                }
                Show-ProgressMessage -Activity "Waiting for TiWorker" -Status "still running" -SecondsElapsed $tiwElapsed
                Start-Sleep -Seconds 5
                $tiwElapsed += 5
            }
            Write-OutputColor ""
            if ($tiwElapsed -ge $maxTiWorkerWait) {
                Write-OutputColor "  TiWorker.exe is STILL running after extended wait. Reboot WILL roll back." -color "Critical"
                Write-OutputColor "  Wait for it to exit (or use 'sfc /verifyonly' to check CBS health) before rebooting." -color "Warning"
            }
        }
        else {
            Complete-ProgressMessage -Activity "Update installation" -Status "Complete" -Success
        }

        $installResult = Receive-Job $installJob -ErrorAction SilentlyContinue
        $installState = $installJob.State
        $installError = $null
        if ($installState -eq "Failed") {
            try {
                if ($installJob.ChildJobs.Count -gt 0) { $installError = $installJob.ChildJobs[0].Error | Out-String }
            } catch { $null = $_ }
        }
        Remove-Job $installJob -Force -ErrorAction SilentlyContinue

        # Treat anything that isn't "Completed" as a non-success: jobs that hit the
        # one-hour timeout cap are stopped via Stop-Job which leaves the state at
        # "Stopped", not "Failed". Falling through to the success branch on a Stopped
        # job produced a fake "Installed N updates" session change and falsely flagged
        # RebootNeeded — exactly what this guard was meant to prevent.
        if ($installState -ne "Completed") {
            $reasonText = switch ($installState) {
                "Stopped" { "timed out after $([math]::Floor($maxInstallTime / 60)) minutes" }
                "Failed"  { "encountered errors" }
                default   { "did not complete (state: $installState)" }
            }
            Write-OutputColor "`nWindows update installation $reasonText." -color "Warning"
            if ($installError) { Write-OutputColor "  Error: $($installError.Trim())" -color "Error" }
            Write-OutputColor "  Some updates may not have been installed. Check Windows Update settings." -color "Warning"
        }
        else {
            Write-OutputColor "`nWindows updates installation complete!" -color "Success"
            Write-OutputColor "  A reboot may be required to complete the installation." -color "Warning"
            $script:RebootNeeded = $true
            Add-SessionChange -Category "System" -Description "Installed $updateCount Windows update(s)"
            Clear-MenuCache
        }
    }
    catch {
        Write-RackStackError -Code "RS-1009" -Detail "Windows Update operation failed: $($_.Exception.Message)"
        Write-OutputColor "  Failed to install updates: $_" -color "Error"
        Write-OutputColor "  Tip: Try running Windows Update manually via Settings." -color "Warning"
    }
    finally {
        if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
        if ($installJob) { Remove-Job -Job $installJob -Force -ErrorAction SilentlyContinue }
    }
    Write-PressEnter
}
#endregion
