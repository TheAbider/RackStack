#region ===== WINDOWS UPDATES =====
# Function to install Windows updates with timeout protection
function Install-WindowsUpdates {
    Clear-Host
    Write-CenteredOutput "Windows Updates" -color "Info"

    # Check network connectivity
    Write-OutputColor "Checking network connectivity..." -color "Info"
    if (-not (Test-NetworkConnectivity)) {
        Write-OutputColor "No network connectivity detected. Cannot check for updates." -color "Error"
        Write-OutputColor "Tip: Verify network configuration and DNS settings." -color "Warning"
        return
    }

    Write-OutputColor "Network connectivity confirmed." -color "Success"
    Write-OutputColor "" -color "Info"

    try {
        # Install NuGet provider if needed
        $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $nuget) {
            Write-OutputColor "Installing NuGet provider..." -color "Info"
            Install-PackageProvider -Name NuGet -Force -ErrorAction Stop | Out-Null
        }

        # Install PSWindowsUpdate module if needed
        $psWindowsUpdate = Get-Module -ListAvailable -Name PSWindowsUpdate
        if (-not $psWindowsUpdate) {
            Write-OutputColor "Installing PSWindowsUpdate module..." -color "Info"
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
            Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck -ErrorAction Stop
        }

        Import-Module PSWindowsUpdate -ErrorAction Stop

        # Check for updates with timeout and progress
        $timeoutSeconds = $script:UpdateTimeoutSeconds
        Write-OutputColor "Checking for available updates (timeout: $($timeoutSeconds / 60) minutes)..." -color "Info"

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
            Write-OutputColor "This may indicate network issues or Windows Update service problems." -color "Warning"
            return
        }

        Complete-ProgressMessage -Activity "Update check" -Status "Complete" -Success

        $updates = Receive-Job $job
        Remove-Job $job -Force -ErrorAction SilentlyContinue

        if ($null -eq $updates -or @($updates).Count -eq 0) {
            Write-OutputColor "No updates available. System is up to date!" -color "Success"
            return
        }

        $updateCount = @($updates).Count
        Write-OutputColor "Found $updateCount update(s) available." -color "Info"

        # List updates
        Write-OutputColor "`nAvailable updates:" -color "Info"
        foreach ($update in $updates) {
            $size = if ($update.Size) { " ($([math]::Round($update.Size / 1MB, 1)) MB)" } else { "" }
            Write-OutputColor "  - $($update.Title)$size" -color "Info"
        }
        Write-OutputColor "" -color "Info"

        if (-not (Confirm-UserAction -Message "Install all $updateCount update(s)?")) {
            Write-OutputColor "Update installation cancelled." -color "Warning"
            return
        }

        Write-OutputColor "`nInstalling updates... This may take a while." -color "Warning"
        Write-OutputColor "Please do not restart the computer during this process." -color "Critical"
        Write-OutputColor "" -color "Info"

        # Install updates with progress
        $installJob = Start-Job -ScriptBlock {
            Import-Module PSWindowsUpdate
            Install-WindowsUpdate -AcceptAll -IgnoreReboot
        }

        $elapsed = 0
        $maxInstallTime = 3600  # 1 hour max for install
        while ($installJob.State -eq "Running" -and $elapsed -lt $maxInstallTime) {
            $minutes = [math]::Floor($elapsed / 60)
            $seconds = $elapsed % 60
            Show-ProgressMessage -Activity "Installing updates" -Status "$minutes min $seconds sec" -SecondsElapsed $elapsed
            Start-Sleep -Seconds 1
            $elapsed++
        }
        Write-Host ""  # New line after progress

        if ($installJob.State -eq "Running") {
            Write-OutputColor "Installation timed out after $([math]::Floor($maxInstallTime / 60)) minutes. Stopping job." -color "Warning"
            Stop-Job $installJob -ErrorAction SilentlyContinue
        }
        else {
            Complete-ProgressMessage -Activity "Update installation" -Status "Complete" -Success
        }

        $installResult = Receive-Job $installJob -ErrorAction SilentlyContinue
        $installState = $installJob.State
        Remove-Job $installJob -Force -ErrorAction SilentlyContinue

        if ($installState -eq "Failed") {
            Write-OutputColor "`nWindows update installation encountered errors." -color "Warning"
            Write-OutputColor "Some updates may not have been installed. Check Windows Update settings." -color "Warning"
        }
        else {
            Write-OutputColor "`nWindows updates installation complete!" -color "Success"
        }
        Write-OutputColor "A reboot may be required to complete the installation." -color "Warning"
        $global:RebootNeeded = $true
        Add-SessionChange -Category "System" -Description "Installed $updateCount Windows update(s)"
    }
    catch {
        Write-OutputColor "Failed to install updates: $_" -color "Error"
        Write-OutputColor "Tip: Try running Windows Update manually via Settings." -color "Warning"
    }
    finally {
        if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
        if ($installJob) { Remove-Job -Job $installJob -Force -ErrorAction SilentlyContinue }
    }
}
#endregion