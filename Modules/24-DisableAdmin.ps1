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
            $script:DisabledAdminReboot = $false
            Write-PressEnter
            return
        }

        if (-not $adminAccount.Enabled) {
            Write-OutputColor "  Built-in Administrator account is already disabled." -color "Info"
            $script:DisabledAdminReboot = $false
            Write-PressEnter
            return
        }

        # Verify alternate admin access exists. Resolve the Administrators group by its
        # well-known SID (S-1-5-32-544) so this works on non-English Windows. For local
        # accounts, verify via Get-LocalUser that they're enabled. For MSA/AzureAD accounts,
        # do NOT trust them blindly — a stale principal in the Administrators group (former
        # employee, AAD-revoked account, machine that lost AAD trust) counts as a "valid"
        # alternate path under the prior logic, leading to permanent lockout after reboot.
        # Require an explicit operator confirmation when MSA/AzureAD is the ONLY alternate.
        try {
            $adminGroupName = (Get-LocalGroup -SID 'S-1-5-32-544' -ErrorAction Stop).Name
        } catch {
            $adminGroupName = 'Administrators'
        }
        $adminMembers = @(Get-LocalGroupMember -Group $adminGroupName -ErrorAction SilentlyContinue)
        $verifiedLocalAdmins = @()
        $unverifiedExternalAdmins = @()
        foreach ($m in $adminMembers) {
            if ($m.ObjectClass -ne 'User') { continue }
            $rawName = [string]$m.Name
            $shortName = $rawName -replace '^.*\\', ''
            if ($shortName -eq 'Administrator') { continue }
            $source = $m.PrincipalSource
            if ($source -eq 'MicrosoftAccount' -or $source -eq 'AzureAD') {
                $unverifiedExternalAdmins += [PSCustomObject]@{ Name = $rawName; Source = $source }
                continue
            }
            $localUser = Get-LocalUser -Name $shortName -ErrorAction SilentlyContinue
            if ($null -ne $localUser -and $localUser.Enabled) {
                $verifiedLocalAdmins += $localUser
            }
        }
        $enabledLocalAdmins = $verifiedLocalAdmins

        $daCim = Invoke-WithTimeout -ScriptBlock {
            (Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec 8 -ErrorAction SilentlyContinue).PartOfDomain
        } -TimeoutSeconds 10 -Activity "Checking domain status"
        $isDomainJoined = if ($daCim.TimedOut) { $false } else { $daCim.Result }
        $hasDomainAdmins = @($adminMembers | Where-Object { $_.ObjectClass -eq 'Group' -or $_.PrincipalSource -eq 'ActiveDirectory' }).Count -gt 0

        $hasVerifiedLocal = $enabledLocalAdmins.Count -gt 0
        $hasDomainPath = $isDomainJoined -and $hasDomainAdmins
        $hasOnlyExternalUnverified = -not $hasVerifiedLocal -and -not $hasDomainPath -and $unverifiedExternalAdmins.Count -gt 0

        if (-not $hasVerifiedLocal -and -not $hasDomainPath -and $unverifiedExternalAdmins.Count -eq 0) {
            Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Error"
            Write-OutputColor "  ║$("  No alternate admin account detected.".PadRight(72))║" -color "Error"
            Write-OutputColor "  ╠════════════════════════════════════════════════════════════════════════╣" -color "Error"
            Write-OutputColor "  ║$("  Disabling the only admin account would LOCK YOU OUT.".PadRight(72))║" -color "Error"
            Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Error"
            Write-OutputColor "" -color "Info"
            # Offer to create one right here instead of just dead-ending, then come back.
            if (Confirm-UserAction -Message "Create a local admin account now?" -DefaultYes) {
                Add-LocalAdminAccount
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Local admin step complete. Re-run 'Disable built-in Administrator'" -color "Info"
                Write-OutputColor "  to finish — it will detect the new account as your fallback." -color "Info"
            } else {
                Write-OutputColor "  Create another local admin account (or join a domain) first." -color "Warning"
            }
            Write-PressEnter
            return
        }

        if ($hasOnlyExternalUnverified) {
            # MSA / AzureAD-only alternate path: cannot be locally verified as logon-capable.
            # AAD account revocation, deleted MSA, machine lost AAD trust — all leave this
            # principal still in the group while logon fails. Require typed confirm so the
            # operator acknowledges the lockout risk.
            Write-OutputColor "" -color "Critical"
            Write-OutputColor "  CAUTION: the only alternate admin path is an MSA / AzureAD account." -color "Critical"
            Write-OutputColor "  These principals can't be verified locally — if the AAD account is" -color "Warning"
            Write-OutputColor "  revoked, the MSA is stale, or the machine has lost its AAD trust," -color "Warning"
            Write-OutputColor "  no one will be able to log in after the next reboot." -color "Warning"
            foreach ($ext in $unverifiedExternalAdmins) {
                Write-OutputColor "    - $($ext.Name) [$($ext.Source)]" -color "Info"
            }
            Write-OutputColor "  Type ACCEPT-LOCKOUT-RISK to proceed (or press Enter to cancel):" -color "Critical"
            $extConfirm = Read-Host
            if ($extConfirm -ne 'ACCEPT-LOCKOUT-RISK') {
                Write-OutputColor "  Cancelled (typed confirmation did not match)." -color "Info"
                Write-PressEnter
                return
            }
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

        # Compare by SID, not by display name. Hardened environments rename the built-in to
        # something like 'svc-root' or 'RootAdmin'; the SID -500 stays. The prior name-only
        # check missed this and silently allowed the operator to disable their own session,
        # which then survives in-process but blocks all future logons.
        $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $builtInSid = $adminAccount.SID.Value
        if ($currentSid -eq $builtInSid) {
            Write-OutputColor "" -color "Warning"
            Write-OutputColor "  Note: you're logged in AS the built-in Administrator ($($adminAccount.Name))." -color "Warning"
            Write-OutputColor "  Disabling it keeps THIS session alive but blocks future logons to it —" -color "Warning"
            Write-OutputColor "  sign in as the alternate admin shown above before rebooting." -color "Warning"
            # Only demand the typed confirmation when there's no locally-verified fallback admin
            # (real lockout risk). With a verified alternate local admin present, the plain y/N
            # below is enough — you can simply log in as that account. (Operators found the long
            # typed phrase needless busywork in the common "I already made another admin" case.)
            if (-not $hasVerifiedLocal) {
                Write-OutputColor "  Type LOGGED-IN-AS-BUILTIN to confirm you understand:" -color "Critical"
                $selfConfirm = Read-Host
                if ($selfConfirm -ne 'LOGGED-IN-AS-BUILTIN') {
                    Write-OutputColor "  Cancelled." -color "Info"
                    Write-PressEnter
                    return
                }
            }
        }

        if (-not (Confirm-UserAction -Message "Disable built-in Administrator account?")) {
            Write-OutputColor "  Operation cancelled." -color "Info"
            $script:DisabledAdminReboot = $false
            Write-PressEnter
            return
        }

        if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
            Push-DryRunStep -Label "Disable built-in Administrator account" -Category "Security" -OneWay $false `
                -Preflight {
                    $a = Get-LocalUser -Name "Administrator" -ErrorAction SilentlyContinue
                    if ($null -eq $a) { "Built-in Administrator account not present" }
                    elseif (-not $a.Enabled) { "Built-in Administrator already disabled" }
                    else { $true }
                } `
                -Apply {
                    Disable-LocalUser -Name "Administrator" -ErrorAction Stop
                    $script:DisabledAdminReboot = $true
                } `
                -Undo {
                    Enable-LocalUser -Name "Administrator" -ErrorAction SilentlyContinue
                }
            Write-OutputColor "  Queued (Dry-Run): disable built-in Administrator." -color "Warning"
            Add-SessionChange -Category "DryRun" -Description "Queued disable built-in Administrator"
            Write-PressEnter
            return
        }

        Disable-LocalUser -Name "Administrator" -ErrorAction Stop

        # Verify
        $adminAccount = Get-LocalUser -Name "Administrator"
        if (-not $adminAccount.Enabled) {
            Write-OutputColor "  Built-in Administrator account has been disabled." -color "Success"
            $script:DisabledAdminReboot = $true
            Add-SessionChange -Category "Security" -Description "Disabled built-in Administrator account"
            Add-UndoAction -Category "Security" -Description "Disabled built-in Administrator account" -UndoScript {
                Enable-LocalUser -Name "Administrator" -ErrorAction SilentlyContinue
            }
            Clear-MenuCache  # Invalidate cache after change
        }
        else {
            Write-OutputColor "  Failed to disable the account." -color "Error"
            $script:DisabledAdminReboot = $false
        }
    }
    catch {
        Write-OutputColor "  Failed to disable Administrator account: $_" -color "Error"
        $script:DisabledAdminReboot = $false
    }
    Write-PressEnter
}
#endregion