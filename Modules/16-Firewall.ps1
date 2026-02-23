#region ===== FIREWALL CONFIGURATION =====
# Function to configure Windows Firewall
function Disable-WindowsFirewallDomainPrivate {
    Clear-Host
    Write-CenteredOutput "Windows Firewall" -color "Info"

    # Get current status
    $profiles = @("Domain", "Private", "Public")

    Write-OutputColor "Current firewall status:" -color "Info"
    foreach ($fwProfile in $profiles) {
        $state = (Get-NetFirewallProfile -Profile $fwProfile -ErrorAction SilentlyContinue).Enabled
        $stateText = if ($state) { "Enabled" } else { "Disabled" }
        $color = switch ($fwProfile) {
            "Public" { if ($state) { "Success" } else { "Warning" } }
            default { if ($state) { "Warning" } else { "Success" } }
        }
        Write-OutputColor "  $fwProfile : $stateText" -color $color
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Recommended configuration:" -color "Info"
    Write-OutputColor "  Domain  : Disabled (for internal network)" -color "Info"
    Write-OutputColor "  Private : Disabled (for internal network)" -color "Info"
    Write-OutputColor "  Public  : Enabled (for security)" -color "Info"

    if (-not (Confirm-UserAction -Message "`nApply recommended firewall configuration?")) {
        Write-OutputColor "Firewall configuration cancelled." -color "Info"
        return
    }

    try {
        # Disable Domain profile
        $domainProfile = Get-NetFirewallProfile -Profile Domain
        if ($domainProfile.Enabled) {
            Set-NetFirewallProfile -Profile Domain -Enabled False -ErrorAction Stop
            Write-OutputColor "Domain firewall disabled." -color "Success"
        }
        else {
            Write-OutputColor "Domain firewall already disabled." -color "Info"
        }

        # Disable Private profile
        $privateProfile = Get-NetFirewallProfile -Profile Private
        if ($privateProfile.Enabled) {
            Set-NetFirewallProfile -Profile Private -Enabled False -ErrorAction Stop
            Write-OutputColor "Private firewall disabled." -color "Success"
        }
        else {
            Write-OutputColor "Private firewall already disabled." -color "Info"
        }

        # Enable Public profile
        $publicProfile = Get-NetFirewallProfile -Profile Public
        if (-not $publicProfile.Enabled) {
            Set-NetFirewallProfile -Profile Public -Enabled True -ErrorAction Stop
            Write-OutputColor "Public firewall enabled." -color "Success"
        }
        else {
            Write-OutputColor "Public firewall already enabled." -color "Info"
        }

        Add-SessionChange -Category "Security" -Description "Configured firewall (Domain/Private disabled, Public enabled)"
        Clear-MenuCache  # Invalidate cache after change
    }
    catch {
        Write-OutputColor "Failed to configure firewall: $_" -color "Error"
    }
}
#endregion