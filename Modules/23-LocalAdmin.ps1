#region ===== LOCAL ADMIN ACCOUNT =====
# Function to create a new local admin account
function Add-LocalAdminAccount {
    Clear-Host
    Write-CenteredOutput "Create Local Admin Account" -color "Info"

    $accountName = $localadminaccountname
    $accountFullName = $FullName

    Write-OutputColor "Default account name: $localadminaccountname" -color "Info"

    if (-not (Confirm-UserAction -Message "Use default account name ($localadminaccountname)?" -DefaultYes)) {
        Write-OutputColor "Enter account name (alphanumeric, 1-20 chars):" -color "Info"
        $customName = Read-Host

        if (-not [string]::IsNullOrWhiteSpace($customName)) {
            if ($customName -match '^[a-zA-Z][a-zA-Z0-9_-]{0,19}$') {
                $accountName = $customName

                Write-OutputColor "Enter full name for the account:" -color "Info"
                $customFullName = Read-Host
                $accountFullName = if ([string]::IsNullOrWhiteSpace($customFullName)) { $accountName } else { $customFullName }
            }
            else {
                Write-OutputColor "Invalid account name. Using default." -color "Warning"
            }
        }
    }

    # Check if account exists
    $existingUser = Get-LocalUser -Name $accountName -ErrorAction SilentlyContinue

    if ($existingUser) {
        Write-OutputColor "Account '$accountName' already exists." -color "Warning"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Creating account: $accountName ($accountFullName)" -color "Info"
    Write-OutputColor "" -color "Info"

    # Get password
    $Password = Get-SecurePassword -localadminaccountname $accountName

    if ($null -eq $Password) {
        Write-OutputColor "Account creation cancelled due to password validation failure." -color "Error"
        return
    }

    try {
        # Create the user
        New-LocalUser -Name $accountName -FullName $accountFullName -Password $Password -PasswordNeverExpires -AccountNeverExpires -ErrorAction Stop | Out-Null

        # Add to Administrators group
        Add-LocalGroupMember -Group "Administrators" -Member $accountName -ErrorAction Stop

        Write-OutputColor "Account '$accountName' created and added to Administrators group." -color "Success"
        Add-SessionChange -Category "Security" -Description "Created local admin account '$accountName'"
    }
    catch {
        Write-OutputColor "Failed to create account: $_" -color "Error"
    }
}
#endregion