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
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
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

    if ($errors.Count -gt 0) {
        Write-OutputColor "Password does not meet requirements:" -color "Error"
        foreach ($err in $errors) {
            Write-OutputColor "  - $err" -color "Warning"
        }
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

    Write-OutputColor "Password Requirements:" -color "Info"
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
                    Write-OutputColor "Passwords do not match. ($remaining attempt(s) remaining)" -color "Error"
                }
                else {
                    Write-OutputColor "Passwords do not match." -color "Error"
                }
                continue
            }

            # Check for empty password
            if ([string]::IsNullOrEmpty($Pwd1Plain)) {
                if ($remaining -gt 0) {
                    Write-OutputColor "Password cannot be empty. ($remaining attempt(s) remaining)" -color "Error"
                }
                else {
                    Write-OutputColor "Password cannot be empty." -color "Error"
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

            Write-OutputColor "Password meets all requirements." -color "Success"
            return $Password1
        }
        catch {
            Write-OutputColor "Error processing password: $_" -color "Error"
            continue
        }
        finally {
            # Always clean up plaintext passwords from memory
            Clear-SecureMemory -StringRef ([ref]$Pwd1Plain)
            Clear-SecureMemory -StringRef ([ref]$Pwd2Plain)
        }
    }

    Write-OutputColor "Maximum attempts reached." -color "Critical"
    return $null
}
#endregion