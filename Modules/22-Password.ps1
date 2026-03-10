#region ===== PASSWORD FUNCTIONS =====
# Function to convert SecureString to plain text with proper BSTR handling
function ConvertFrom-SecureStringToPlainText {
    param (
        [Parameter(Mandatory=$true)]
        [System.Security.SecureString]$secureString
    )

    $bstr = [IntPtr]::Zero
    try {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        # Always free the BSTR to prevent memory leaks
        if ($bstr -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

# Function to securely clear a string from memory
function Clear-SecureMemory {
    param (
        [ref]$StringRef
    )

    if ($null -ne $StringRef.Value -and $StringRef.Value -is [string]) {
        # Overwrite the string content (best effort - .NET strings are immutable)
        $StringRef.Value = $null
    }
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}

# Function to check password complexity
function Test-PasswordComplexity {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$InputString  # Password to validate (plain text required for complexity check)
    )

    $minLength = $script:MinPasswordLength
    $errors = @()

    if ($InputString.Length -lt $minLength) {
        $errors += "At least $minLength characters long"
    }
    if ($InputString -cnotmatch "[A-Z]") {
        $errors += "At least one uppercase letter (A-Z)"
    }
    if ($InputString -cnotmatch "[a-z]") {
        $errors += "At least one lowercase letter (a-z)"
    }
    if ($InputString -notmatch "\d") {
        $errors += "At least one number (0-9)"
    }
    if ($InputString -notmatch '[!@#$%^&*()_+\-=\[\]{}|;:,.<>?]') {
        $errors += "At least one special character (!@#$%^&*...)"
    }

    # Visual checklist showing pass/fail per requirement
    $hasLength  = $InputString.Length -ge $minLength
    $hasUpper   = $InputString -cmatch "[A-Z]"
    $hasLower   = $InputString -cmatch "[a-z]"
    $hasDigit   = $InputString -match "\d"
    $hasSpecial = $InputString -match '[!@#$%^&*()_+\-=\[\]{}|;:,.<>?]'

    if ($errors.Count -gt 0) {
        Write-OutputColor "  Password check:" -color "Info"
        Write-OutputColor "    $(if($hasLength){'[OK]'}else{'[  ]'}) Length ($($InputString.Length)/$minLength chars)" -color $(if($hasLength){"Success"}else{"Error"})
        Write-OutputColor "    $(if($hasUpper){'[OK]'}else{'[  ]'}) Uppercase letter" -color $(if($hasUpper){"Success"}else{"Error"})
        Write-OutputColor "    $(if($hasLower){'[OK]'}else{'[  ]'}) Lowercase letter" -color $(if($hasLower){"Success"}else{"Error"})
        Write-OutputColor "    $(if($hasDigit){'[OK]'}else{'[  ]'}) Number" -color $(if($hasDigit){"Success"}else{"Error"})
        Write-OutputColor "    $(if($hasSpecial){'[OK]'}else{'[  ]'}) Special character" -color $(if($hasSpecial){"Success"}else{"Error"})
        return $false
    }
    return $true
}

# Function to securely get password input with proper memory cleanup
function Get-SecurePassword {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$localadminaccountname,
        [ValidateRange(1,10)]
        [int]$maxAttempts = 3
    )

    $minLength = $script:MinPasswordLength

    Write-OutputColor "  Password Requirements:" -color "Info"
    Write-OutputColor "  - Minimum $minLength characters" -color "Info"
    Write-OutputColor "  - At least 1 uppercase letter" -color "Info"
    Write-OutputColor "  - At least 1 lowercase letter" -color "Info"
    Write-OutputColor "  - At least 1 number" -color "Info"
    Write-OutputColor "  - At least 1 special character" -color "Info"
    Write-OutputColor "" -color "Info"

    $attempts = 0

    while ($attempts -lt $maxAttempts) {
        $attempts++
        $remaining = $maxAttempts - $attempts

        $Password1 = Read-Host -Prompt "Enter password for $localadminaccountname" -AsSecureString
        $Password2 = Read-Host -Prompt "Confirm password" -AsSecureString

        $Pwd1Plain = $null
        $Pwd2Plain = $null

        try {
            $Pwd1Plain = ConvertFrom-SecureStringToPlainText -secureString $Password1
            $Pwd2Plain = ConvertFrom-SecureStringToPlainText -secureString $Password2

            # Check if passwords match
            if ($Pwd1Plain -ne $Pwd2Plain) {
                if ($remaining -gt 0) {
                    Write-OutputColor "  Passwords do not match. ($remaining attempt(s) remaining)" -color "Error"
                }
                else {
                    Write-OutputColor "  Passwords do not match." -color "Error"
                }
                continue
            }

            # Check for empty password
            if ([string]::IsNullOrEmpty($Pwd1Plain)) {
                if ($remaining -gt 0) {
                    Write-OutputColor "  Password cannot be empty. ($remaining attempt(s) remaining)" -color "Error"
                }
                else {
                    Write-OutputColor "  Password cannot be empty." -color "Error"
                }
                continue
            }

            # Check complexity
            if (-not (Test-PasswordComplexity -InputString $Pwd1Plain)) {
                if ($remaining -gt 0) {
                    Write-OutputColor "($remaining attempt(s) remaining)" -color "Warning"
                }
                continue
            }

            Write-OutputColor "  Password meets all requirements." -color "Success"
            return $Password1
        }
        catch {
            Write-OutputColor "  Error processing password: $_" -color "Error"
            continue
        }
        finally {
            # Always clean up plaintext passwords from memory
            Clear-SecureMemory -StringRef ([ref]$Pwd1Plain)
            Clear-SecureMemory -StringRef ([ref]$Pwd2Plain)
        }
    }

    Write-OutputColor "  Maximum attempts reached." -color "Critical"
    return $null
}
# Function to audit local user accounts for password and login status
function Show-LocalAccountAudit {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     LOCAL ACCOUNT AUDIT").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $users = @(Get-LocalUser -ErrorAction Stop)
    }
    catch {
        Write-OutputColor "  Error retrieving local accounts: $_" -color "Error"
        return
    }

    if ($users.Count -eq 0) {
        Write-OutputColor "  No local user accounts found." -color "Warning"
        return
    }

    $now = Get-Date
    $issues = 0

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    $acctHeader = "  LOCAL USER ACCOUNTS ($($users.Count))"
    Write-OutputColor "  │$($acctHeader.PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    foreach ($user in ($users | Sort-Object Name)) {
        $enabled = $user.Enabled
        $statusTag = if ($enabled) { "Enabled " } else { "Disabled" }

        # Password age
        $pwdAge = if ($null -ne $user.PasswordLastSet) {
            $days = [math]::Floor(($now - $user.PasswordLastSet).TotalDays)
            "${days}d ago"
        } else { "Never set" }

        # Last logon
        $lastLogon = if ($null -ne $user.LastLogon) {
            $logonDays = [math]::Floor(($now - $user.LastLogon).TotalDays)
            if ($logonDays -eq 0) { "Today" } else { "${logonDays}d ago" }
        } else { "Never" }

        # Password expiry
        $pwdExpires = if ($user.PasswordNeverExpires) {
            "Never"
        } elseif ($null -ne $user.PasswordLastSet) {
            try {
                $maxPwdAge = (Get-LocalUser $user.Name -ErrorAction SilentlyContinue).PasswordExpires
                if ($null -ne $maxPwdAge) {
                    $expiryDays = [math]::Floor(($maxPwdAge - $now).TotalDays)
                    if ($expiryDays -lt 0) { "EXPIRED" } else { "${expiryDays}d" }
                } else { "N/A" }
            } catch { "N/A" }
        } else { "N/A" }

        # Determine color based on issues
        $color = "Success"
        $flags = @()
        if (-not $enabled) { $color = "Info" }
        if ($null -ne $user.PasswordLastSet) {
            $pwdDays = [math]::Floor(($now - $user.PasswordLastSet).TotalDays)
            if ($pwdDays -gt 365) { $color = "Error"; $flags += "OLD PWD"; $issues++ }
            elseif ($pwdDays -gt 90) { $color = "Warning"; $flags += "AGING" }
        }
        if ($pwdExpires -eq "EXPIRED") { $color = "Error"; $flags += "EXPIRED"; $issues++ }
        if ($lastLogon -eq "Never" -and $enabled) { $flags += "NO LOGIN" }
        if ($null -ne $user.LastLogon) {
            $logonDays = [math]::Floor(($now - $user.LastLogon).TotalDays)
            if ($logonDays -gt 90 -and $enabled) { $flags += "STALE"; $issues++ }
        }

        $flagStr = if ($flags.Count -gt 0) { " [" + ($flags -join ", ") + "]" } else { "" }
        $nameStr = $user.Name
        if ($nameStr.Length -gt 20) { $nameStr = $nameStr.Substring(0, 17) + "..." }
        $line = "  $($statusTag) $($nameStr.PadRight(20)) Pwd: $($pwdAge.PadRight(10)) Login: $($lastLogon.PadRight(8))$flagStr"
        if ($line.Length -gt 72) { $line = $line.Substring(0, 72) }
        Write-OutputColor "  │$($line.PadRight(72))│" -color $color
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    # Summary
    Write-OutputColor "" -color "Info"
    if ($issues -gt 0) {
        Write-OutputColor "  $issues issue(s) found — review flagged accounts above." -color "Warning"
    } else {
        Write-OutputColor "  All accounts look healthy." -color "Success"
    }

    Add-SessionChange -Category "Security" -Description "Ran local account audit ($($users.Count) accounts, $issues issues)"
    Write-PressEnter
}
#endregion