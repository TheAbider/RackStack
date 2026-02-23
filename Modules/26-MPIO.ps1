#region ===== MPIO INSTALLATION =====
# Function to check if MPIO is installed
function Test-MPIOInstalled {
    if (-not (Test-WindowsServer)) { return $false }
    try {
        $mpioFeature = Get-WindowsFeature -Name MultipathIO -ErrorAction SilentlyContinue
        if ($mpioFeature -and $mpioFeature.InstallState -eq "Installed") {
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

# Function to install MPIO feature
function Install-MPIOFeature {
    Clear-Host
    Write-CenteredOutput "Install MPIO" -color "Info"

    if (Test-MPIOInstalled) {
        Write-OutputColor "MPIO (Multipath I/O) is already installed." -color "Success"
        return
    }

    Write-OutputColor "MPIO (Multipath I/O) is not currently installed." -color "Info"

    # Pre-flight validation
    $preFlightOK = Show-PreFlightCheck -Feature "MPIO"
    if (-not $preFlightOK) {
        if (-not (Confirm-UserAction -Message "Continue despite blocking issues?")) {
            Write-OutputColor "Installation cancelled." -color "Info"
            return
        }
    }

    Write-OutputColor "MPIO enables multiple physical paths between a server" -color "Info"
    Write-OutputColor "and storage devices for redundancy and performance." -color "Info"
    Write-OutputColor "A reboot will be required after installation." -color "Warning"

    if (-not (Confirm-UserAction -Message "Install MPIO now?")) {
        Write-OutputColor "MPIO installation cancelled." -color "Info"
        return
    }

    try {
        Write-OutputColor "`nInstalling MPIO... This may take several minutes." -color "Info"

        $installResult = Install-WindowsFeatureWithTimeout -FeatureName "MultipathIO" -DisplayName "MPIO" -IncludeManagementTools

        if ($installResult.TimedOut) {
            Add-SessionChange -Category "System" -Description "MPIO installation timed out"
            return $false
        }
        elseif ($installResult.Success) {
            Write-OutputColor "`nMPIO installed successfully!" -color "Success"
            Write-OutputColor "A reboot is required to complete the installation." -color "Warning"
            $global:RebootNeeded = $true
            Add-SessionChange -Category "System" -Description "Installed MPIO (Multipath I/O)"
            Clear-MenuCache
        }
        else {
            Write-OutputColor "MPIO installation may not have completed successfully." -color "Error"
            Add-SessionChange -Category "System" -Description "MPIO installation failed"
        }
    }
    catch {
        Write-OutputColor "Failed to install MPIO: $_" -color "Error"
    }
}
#endregion