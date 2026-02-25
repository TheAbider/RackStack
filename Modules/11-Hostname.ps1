#region ===== HOSTNAME CONFIGURATION =====
# Function to set the hostname
function Set-HostName {
    Clear-Host
    Write-CenteredOutput "Set Hostname" -color "Info"

    $currentHostname = $env:COMPUTERNAME
    Write-OutputColor "Current hostname: $currentHostname" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "Hostname requirements:" -color "Info"
    Write-OutputColor "  - 1-15 characters" -color "Info"
    Write-OutputColor "  - Start with a letter or digit" -color "Info"
    Write-OutputColor "  - Letters, digits, and hyphens only" -color "Info"
    Write-OutputColor "  - Cannot end with a hyphen" -color "Info"
    Write-OutputColor "" -color "Info"

    $newHostname = Get-ValidatedInput -Prompt "Enter new hostname" `
        -ValidationScript { param($h) Test-ValidHostname -Hostname $h } `
        -ErrorMessage "Invalid hostname format. See requirements above."

    if ($null -eq $newHostname) {
        Write-OutputColor "Hostname change cancelled." -color "Warning"
        return
    }

    if ($newHostname -eq $currentHostname) {
        Write-OutputColor "Hostname is already '$currentHostname'. No change needed." -color "Info"
        return
    }

    # Check if name exists in AD (informational, non-blocking)
    $adCheck = Test-ComputerNameInAD -ComputerName $newHostname
    if ($adCheck.Checked -and $adCheck.Exists) {
        Write-OutputColor "  Note: '$newHostname' already exists in Active Directory." -color "Warning"
        Write-OutputColor "  DN: $($adCheck.DN)" -color "Warning"
        if (-not (Confirm-UserAction -Message "Continue with this name anyway?")) {
            return
        }
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Changing hostname: '$currentHostname' -> '$newHostname'" -color "Warning"

    if (-not (Confirm-UserAction -Message "Apply hostname change? (Requires reboot)")) {
        Write-OutputColor "Hostname change cancelled." -color "Info"
        return
    }

    try {
        Rename-Computer -NewName $newHostname -Force -ErrorAction Stop
        Write-OutputColor "Hostname changed to '$newHostname'. Reboot required!" -color "Success"
        $global:RebootNeeded = $true
        Add-SessionChange -Category "System" -Description "Changed hostname from '$currentHostname' to '$newHostname'"
    }
    catch {
        Write-OutputColor "Failed to change hostname: $_" -color "Error"
    }
}
#endregion