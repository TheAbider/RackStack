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

    $accountName = $localadminaccountname
    $accountFullName = $FullName

    Write-OutputColor "  Default account name: $localadminaccountname" -color "Info"

    if (-not (Confirm-UserAction -Message "Use default account name ($localadminaccountname)?" -DefaultYes)) {
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

    try {
        # Create the user
        New-LocalUser -Name $accountName -FullName $accountFullName -Password $Password -PasswordNeverExpires -AccountNeverExpires -ErrorAction Stop | Out-Null

        # Add to Administrators group
        Add-LocalGroupMember -Group "Administrators" -Member $accountName -ErrorAction Stop

        # Verify account creation and group membership
        Test-LocalAdminCreation -Username $accountName | Out-Null
        Add-SessionChange -Category "Security" -Description "Created local admin account '$accountName'"
        Clear-MenuCache
    }
    catch {
        Write-OutputColor "  Failed to create account: $_" -color "Error"
    }
    Write-PressEnter
}
#endregion