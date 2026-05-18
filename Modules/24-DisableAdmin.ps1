#region ===== DISABLE BUILT-IN ADMIN =====
# Show the current status of the built-in Administrator account
function Show-AdminAccountStatus {
    try {
        $adminAccount = Get-LocalUser -Name "Administrator" -ErrorAction Stop

        $statusLabel = if ($adminAccount.Enabled) { "ENABLED" } else { "DISABLED" }
        $statusColor = if ($adminAccount.Enabled) { "Warning" } else { "Success" }

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  BUILT-IN ADMINISTRATOR ACCOUNT STATUS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  Account Name:     $($adminAccount.Name)".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Status:           $statusLabel".PadRight(72))│" -color $statusColor

        # Last logon info
        $lastLogon = $adminAccount.LastLogon
        $logonStr = if ($null -ne $lastLogon -and $lastLogon -ne [DateTime]::MinValue) {
            $lastLogon.ToString("yyyy-MM-dd HH:mm:ss")
        } else { "Never" }
        Write-OutputColor "  │$("  Last Logon:       $logonStr".PadRight(72))│" -color "Info"

        # Password last set
        $pwdLastSet = $adminAccount.PasswordLastSet
        $pwdStr = if ($null -ne $pwdLastSet -and $pwdLastSet -ne [DateTime]::MinValue) {
            $pwdLastSet.ToString("yyyy-MM-dd HH:mm:ss")
        } else { "Never" }
        Write-OutputColor "  │$("  Password Set:     $pwdStr".PadRight(72))│" -color "Info"

        # Password expires?
        $pwdExpires = if ($adminAccount.PasswordExpires) { "Yes" } else { "No" }
        Write-OutputColor "  │$("  Password Expires: $pwdExpires".PadRight(72))│" -color "Info"

        # SID (to confirm it's the real built-in, SID ends in -500)
        $sid = $adminAccount.SID.Value
        $isBuiltIn = $sid.EndsWith("-500")
        $builtInLabel = if ($isBuiltIn) { "Yes (SID ends in -500)" } else { "No" }
        Write-OutputColor "  │$("  Built-in Account: $builtInLabel".PadRight(72))│" -color "Info"

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        return $adminAccount
    }
    catch {
        Write-OutputColor "  Could not retrieve Administrator account status: $_" -color "Error"
        return $null
    }
}

# Function to disable the built-in administrator account
function Disable-BuiltInAdminAccount {
    Clear-Host
    Write-CenteredOutput "Disable Built-in Administrator" -color "Info"

    try {
        # Show current account status
        $adminAccount = Show-AdminAccountStatus

        if ($null -eq $adminAccount) {
            $global:DisabledAdminReboot = $false
            Write-PressEnter
            return
        }

        if (-not $adminAccount.Enabled) {
            Write-OutputColor "  Built-in Administrator account is already disabled." -color "Info"
            $global:DisabledAdminReboot = $false
            Write-PressEnter
            return
        }

        # Verify alternate admin access exists before allowing disable. Filter on
        # PrincipalSource = 'Local' so Microsoft Account-backed admins
        # (e.g. 'MicrosoftAccount\alice@outlook.com') and AzureAD-joined accounts
        # ARE counted as alternate logon paths and not silently regex-stripped to
        # a username that then fails Get-LocalUser. The previous filter could falsely
        # report "no alternate admin" on an MSA-only home/workgroup host.
        $adminMembers = @(Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue)
        $enabledLocalAdmins = @($adminMembers | Where-Object {
            $_.ObjectClass -eq 'User'
        } | ForEach-Object {
            $rawName = [string]$_.Name
            $shortName = $rawName -replace '^.*\\', ''
            $source = $_.PrincipalSource
            # MSA / AzureAD principals count as alternate admins as long as they're
            # not the built-in 'Administrator'. Local accounts re-verified via
            # Get-LocalUser so we know they're actually enabled.
            if ($source -eq 'MicrosoftAccount' -or $source -eq 'AzureAD') {
                if ($shortName -ne 'Administrator') {
                    [PSCustomObject]@{ Name = $rawName; Enabled = $true; Source = $source }
                }
                return
            }
            $localUser = Get-LocalUser -Name $shortName -ErrorAction SilentlyContinue
            if ($null -ne $localUser -and $localUser.Enabled -and $shortName -ne 'Administrator') { $localUser }
        })

        $daCim = Invoke-WithTimeout -ScriptBlock {
            (Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec 8 -ErrorAction SilentlyContinue).PartOfDomain
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
            Write-PressEnter
            return
        }

        # Show who will retain admin access
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  ALTERNATE ADMIN ACCESS (verified)".PadRight(72))│" -color "Success"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        foreach ($admin in $enabledLocalAdmins) {
            Write-OutputColor "  │$("  Local User:  $($admin.Name)".PadRight(72))│" -color "Success"
        }
        if ($isDomainJoined -and $hasDomainAdmins) {
            Write-OutputColor "  │$("  Domain:      Admin group membership detected".PadRight(72))│" -color "Success"
        }
        $totalAlternate = $enabledLocalAdmins.Count + $(if ($isDomainJoined -and $hasDomainAdmins) { 1 } else { 0 })
        Write-OutputColor "  │$("  Total:       $totalAlternate alternate admin path(s)".PadRight(72))│" -color "Success"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        # Check if current session is running as the built-in Administrator
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name -replace '^.*\\', ''
        if ($currentUser -eq 'Administrator') {
            Write-OutputColor "  NOTE: You are currently logged in as Administrator." -color "Warning"
            Write-OutputColor "  You will need to log in with an alternate account after disabling." -color "Warning"
            Write-OutputColor "" -color "Info"
        }

        if (-not (Confirm-UserAction -Message "Disable built-in Administrator account?")) {
            Write-OutputColor "  Operation cancelled." -color "Info"
            $global:DisabledAdminReboot = $false
            Write-PressEnter
            return
        }

        Disable-LocalUser -Name "Administrator" -ErrorAction Stop

        # Verify
        $adminAccount = Get-LocalUser -Name "Administrator"
        if (-not $adminAccount.Enabled) {
            Write-OutputColor "  Built-in Administrator account has been disabled." -color "Success"
            $global:DisabledAdminReboot = $true
            Add-SessionChange -Category "Security" -Description "Disabled built-in Administrator account"
            Add-UndoAction -Category "Security" -Description "Disabled built-in Administrator account" -UndoScript {
                Enable-LocalUser -Name "Administrator" -ErrorAction SilentlyContinue
            }
            Clear-MenuCache  # Invalidate cache after change
        }
        else {
            Write-OutputColor "  Failed to disable the account." -color "Error"
            $global:DisabledAdminReboot = $false
        }
    }
    catch {
        Write-OutputColor "  Failed to disable Administrator account: $_" -color "Error"
        $global:DisabledAdminReboot = $false
    }
    Write-PressEnter
}
#endregion