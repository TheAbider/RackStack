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

        # Verify alternate admin access exists before allowing disable
        $adminMembers = @(Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue)
        $enabledLocalAdmins = @($adminMembers | Where-Object {
            $_.ObjectClass -eq 'User' -and $_.PrincipalSource -eq 'Local'
        } | ForEach-Object {
            $userName = $_.Name -replace '^.*\\', ''
            $localUser = Get-LocalUser -Name $userName -ErrorAction SilentlyContinue
            if ($null -ne $localUser -and $localUser.Enabled -and $userName -ne 'Administrator') { $localUser }
        })

        $daCim = Invoke-WithTimeout -ScriptBlock {
            (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).PartOfDomain
        } -TimeoutSeconds 10 -Activity "Checking domain status"
        $isDomainJoined = if ($daCim.TimedOut) { $false } else { $daCim.Result }
        $hasDomainAdmins = @($adminMembers | Where-Object { $_.ObjectClass -eq 'Group' -or $_.PrincipalSource -eq 'ActiveDirectory' }).Count -gt 0

        if ($enabledLocalAdmins.Count -eq 0 -and -not ($isDomainJoined -and $hasDomainAdmins)) {
            Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Error"
            Write-OutputColor "  ║$("  BLOCKED: No alternate admin account detected!".PadRight(72))║" -color "Error"
            Write-OutputColor "  ╠════════════════════════════════════════════════════════════════════════╣" -color "Error"
            Write-OutputColor "  ║$("  Disabling the only admin account will LOCK YOU OUT.".PadRight(72))║" -color "Error"
            Write-OutputColor "  ║$("  Create another local admin account first, or join a domain.".PadRight(72))║" -color "Error"
            Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Error"
            Write-OutputColor "" -color "Info"
            return
        }

        Write-OutputColor "  Alternate admin access verified:" -color "Success"
        foreach ($admin in $enabledLocalAdmins) {
            Write-OutputColor "    Local: $($admin.Name)" -color "Success"
        }
        if ($isDomainJoined -and $hasDomainAdmins) {
            Write-OutputColor "    Domain admin group membership detected" -color "Success"
        }
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
            Add-UndoAction -Category "Security" -Description "Disabled built-in Administrator account" -UndoScript {
                Enable-LocalUser -Name "Administrator" -ErrorAction SilentlyContinue
            }
            Clear-MenuCache  # Invalidate cache after change
        }
        else {
            Write-OutputColor "Failed to disable the account." -color "Error"
            $global:DisabledAdminReboot = $false
        }
    }
    catch {
        Write-OutputColor "Failed to disable Administrator account: $_" -color "Error"
        $global:DisabledAdminReboot = $false
    }
}
#endregion