#region ===== LOCAL ADMIN ACCOUNT =====
# Function to verify local admin account creation
function Test-LocalAdminCreation {
    param([string]$Username)

    $account = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if ($null -eq $account) {
        Write-OutputColor "  WARNING: Account '$Username' was not created successfully" -color "Error"
        return $false
    }

    Write-OutputColor "  Account '$Username' created successfully" -color "Success"
    Write-OutputColor "    Enabled: $($account.Enabled)" -color "Info"
    Write-OutputColor "    Password Required: $($account.PasswordRequired)" -color "Info"

    # Check if added to Administrators group
    try {
        $adminGroup = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "\\$Username$" }
        if ($null -ne $adminGroup) {
            Write-OutputColor "    Administrator: Yes" -color "Success"
        } else {
            Write-OutputColor "    Administrator: Not in Administrators group" -color "Warning"
        }
    } catch {
        Write-OutputColor "    Could not verify group membership" -color "Warning"
    }

    return $true
}

# Function to create a new local admin account
function Add-LocalAdminAccount {
    Clear-Host
    Write-CenteredOutput "Create Local Admin Account" -color "Info"

    # Resolve from the explicit script scope so a direct-import or refactor that doesn't
    # populate the bare variable can't accidentally pick up a leaked $FullName/$localadminaccountname
    # from a parent scope (e.g., PowerShell's auto-binding for [System.IO.FileInfo].FullName).
    # Fail hard if either is missing — better to surface "config not loaded" than silently
    # create an account with a wrong name.
    $accountName = $script:localadminaccountname
    if ([string]::IsNullOrWhiteSpace($accountName)) { $accountName = $localadminaccountname }
    if ([string]::IsNullOrWhiteSpace($accountName)) {
        Write-OutputColor "  Configuration error: localadminaccountname is not set." -color "Error"
        Write-OutputColor "  Set 'LocalAdminAccountName' in defaults.json and restart $script:ToolFullName." -color "Warning"
        Write-PressEnter
        return
    }
    $accountFullName = $script:FullName
    if ([string]::IsNullOrWhiteSpace($accountFullName)) { $accountFullName = $FullName }
    if ([string]::IsNullOrWhiteSpace($accountFullName)) { $accountFullName = $accountName }

    Write-OutputColor "  Default account name: $accountName" -color "Info"

    if (-not (Confirm-UserAction -Message "Use default account name ($accountName)?" -DefaultYes)) {
        Write-OutputColor "  Enter account name (letters, numbers, underscore, hyphen; 1-20 chars):" -color "Info"
        $customName = Read-Host
        $navResult = Test-NavigationCommand -UserInput $customName
        if ($navResult.ShouldReturn) { return }

        if (-not [string]::IsNullOrWhiteSpace($customName)) {
            if ($customName -match '^[a-zA-Z][a-zA-Z0-9_-]{0,19}$') {
                $accountName = $customName

                Write-OutputColor "  Enter full name for the account:" -color "Info"
                $customFullName = Read-Host
                $navResult = Test-NavigationCommand -UserInput $customFullName
                if ($navResult.ShouldReturn) { return }
                $accountFullName = if ([string]::IsNullOrWhiteSpace($customFullName)) { $accountName } else { $customFullName }
            }
            else {
                Write-OutputColor "  Invalid account name. Using default." -color "Warning"
            }
        }
    }

    # Check for reserved/built-in names
    $reservedNames = @("Administrator", "Guest", "DefaultAccount", "WDAGUtilityAccount", "SYSTEM", "NETWORK SERVICE", "LOCAL SERVICE")
    if ($accountName -in $reservedNames) {
        Write-OutputColor "  '$accountName' is a reserved system account name. Choose a different name." -color "Error"
        return
    }

    # Check if account exists
    $existingUser = Get-LocalUser -Name $accountName -ErrorAction SilentlyContinue

    if ($existingUser) {
        Write-OutputColor "  Account '$accountName' already exists." -color "Warning"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Creating account: $accountName ($accountFullName)" -color "Info"
    Write-OutputColor "" -color "Info"

    # Get password
    $Password = Get-SecurePassword -localadminaccountname $accountName

    if ($null -eq $Password) {
        Write-OutputColor "  Account creation cancelled due to password validation failure." -color "Error"
        return
    }

    # Resolve Administrators group by SID (locale-neutral) — non-EN Windows uses
    # "Administradores" / "Administratoren" / etc., breaking hardcoded English group names.
    try {
        $adminGroupName = (Get-LocalGroup -SID 'S-1-5-32-544' -ErrorAction Stop).Name
    } catch {
        $adminGroupName = 'Administrators'
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        $capName  = $accountName
        $capFull  = $accountFullName
        $capPwd   = $Password
        $capGroup = $adminGroupName
        Push-DryRunStep -Label "Create local admin '$capName' ($capFull)" -Category "Security" -OneWay $false `
            -Params @{ Name = $capName; FullName = $capFull } `
            -Preflight {
                if (Get-LocalUser -Name $capName -ErrorAction SilentlyContinue) { "Account '$capName' already exists" }
                else { $true }
            }.GetNewClosure() `
            -Apply {
                New-LocalUser -Name $capName -FullName $capFull -Password $capPwd -PasswordNeverExpires -AccountNeverExpires -ErrorAction Stop | Out-Null
                Add-LocalGroupMember -Group $capGroup -Member $capName -ErrorAction Stop
            }.GetNewClosure() `
            -Undo {
                Remove-LocalUser -Name $capName -ErrorAction SilentlyContinue
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): create local admin '$capName'." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued create local admin '$capName'"
        Write-PressEnter
        return
    }

    try {
        # Create the user
        New-LocalUser -Name $accountName -FullName $accountFullName -Password $Password -PasswordNeverExpires -AccountNeverExpires -ErrorAction Stop | Out-Null

        # Add to Administrators group
        Add-LocalGroupMember -Group $adminGroupName -Member $accountName -ErrorAction Stop

        # Verify account creation and group membership
        Test-LocalAdminCreation -Username $accountName | Out-Null
        Add-SessionChange -Category "Security" -Description "Created local admin account '$accountName'"
        Clear-MenuCache

        # Register undo so a wrong-name typo or wrong-machine slip is recoverable through
        # the global undo system — was previously missing.
        $undoName = $accountName
        Add-UndoAction -Category "Security" -Description "Created local admin account '$accountName'" -UndoScript {
            param($N)
            Remove-LocalUser -Name $N -ErrorAction SilentlyContinue
        }.GetNewClosure() -UndoParams @{ N = $undoName }
    }
    catch {
        Write-OutputColor "  Failed to create account: $_" -color "Error"
    }
    Write-PressEnter
}
#endregion