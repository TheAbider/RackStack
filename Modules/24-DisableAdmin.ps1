#region ===== DISABLE BUILT-IN ADMIN =====
# Function to disable the built-in administrator account
function Disable-BuiltInAdminAccount {
    Clear-Host
    Write-CenteredOutput "Disable Built-in Administrator" -color "Info"

    try {
        $adminAccount = Get-LocalUser -Name "Administrator" -ErrorAction Stop

        if (-not $adminAccount.Enabled) {
            Write-OutputColor "Built-in Administrator account is already disabled." -color "Info"
            $global:DisabledAdminReboot = $false
            return
        }

        Write-OutputColor "The built-in Administrator account is currently ENABLED." -color "Warning"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "WARNING: Before disabling, ensure you have:" -color "Critical"
        Write-OutputColor "  1. Another local admin account to log in with" -color "Warning"
        Write-OutputColor "  2. Or domain admin access if domain-joined" -color "Warning"
        Write-OutputColor "" -color "Info"

        if (-not (Confirm-UserAction -Message "Disable built-in Administrator account?")) {
            Write-OutputColor "Operation cancelled." -color "Info"
            $global:DisabledAdminReboot = $false
            return
        }

        Disable-LocalUser -Name "Administrator" -ErrorAction Stop

        # Verify
        $adminAccount = Get-LocalUser -Name "Administrator"
        if (-not $adminAccount.Enabled) {
            Write-OutputColor "Built-in Administrator account has been disabled." -color "Success"
            $global:DisabledAdminReboot = $true
            Add-SessionChange -Category "Security" -Description "Disabled built-in Administrator account"
            Clear-MenuCache  # Invalidate cache after change
        }
        else {
            Write-OutputColor "Failed to disable the account." -color "Error"
            $global:DisabledAdminReboot = $false
        }
    }
    catch {
        Write-OutputColor "Error: $_" -color "Error"
        $global:DisabledAdminReboot = $false
    }
}
#endregion