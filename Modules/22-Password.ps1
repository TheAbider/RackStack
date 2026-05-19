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
    # Reject passwords starting with problematic characters:
    # $ = Unix crypt hash prefix, PowerShell variable sigil, breaks interpolation
    # # = comment character in many config formats
    # - = can be misinterpreted as a command flag/switch
    # ' or " = breaks quoting in scripts, config files, and command lines
    if ($InputString -match '^[\$#\-''"]') {
        $errors += "Cannot start with `$ # - ' or `" (breaks scripts/configs)"
    }

    # Visual checklist showing pass/fail per requirement
    $hasLength  = $InputString.Length -ge $minLength
    $hasUpper   = $InputString -cmatch "[A-Z]"
    $hasLower   = $InputString -cmatch "[a-z]"
    $hasDigit   = $InputString -match "\d"
    $hasSpecial = $InputString -match '[!@#$%^&*()_+\-=\[\]{}|;:,.<>?]'
    $safeStart  = $InputString -notmatch '^[\$#\-''"]'

    if ($errors.Count -gt 0) {
        Write-OutputColor "  Password check:" -color "Info"
        Write-OutputColor "    $(if($hasLength){'[OK]'}else{'[  ]'}) Length ($($InputString.Length)/$minLength chars)" -color $(if($hasLength){"Success"}else{"Error"})
        Write-OutputColor "    $(if($hasUpper){'[OK]'}else{'[  ]'}) Uppercase letter" -color $(if($hasUpper){"Success"}else{"Error"})
        Write-OutputColor "    $(if($hasLower){'[OK]'}else{'[  ]'}) Lowercase letter" -color $(if($hasLower){"Success"}else{"Error"})
        Write-OutputColor "    $(if($hasDigit){'[OK]'}else{'[  ]'}) Number" -color $(if($hasDigit){"Success"}else{"Error"})
        Write-OutputColor "    $(if($hasSpecial){'[OK]'}else{'[  ]'}) Special character" -color $(if($hasSpecial){"Success"}else{"Error"})
        Write-OutputColor "    $(if($safeStart){'[OK]'}else{'[  ]'}) Safe starting character" -color $(if($safeStart){"Success"}else{"Error"})
        return $false
    }
    return $true
}

# Function to display visual password strength feedback
function Show-PasswordStrength {
    param([SecureString]$SecurePassword)

    # Convert SecureString to check strength (clear from memory after)
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
    try {
        $plainText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)

        $score = 0
        $feedback = @()

        # Length scoring — bucket instead of exact length so transcripts don't narrow the search space
        if ($plainText.Length -ge 14) { $score += 3; $feedback += "Length: Excellent (14+ chars)" }
        elseif ($plainText.Length -ge 10) { $score += 2; $feedback += "Length: Good (10-13 chars)" }
        elseif ($plainText.Length -ge 8) { $score += 1; $feedback += "Length: Fair (8-9 chars)" }
        else { $feedback += "Length: Too short (<8 chars)" }

        # Complexity scoring
        if ($plainText -cmatch '[A-Z]') { $score++; $feedback += "Uppercase: Yes" }
        else { $feedback += "Uppercase: Missing" }

        if ($plainText -cmatch '[a-z]') { $score++; $feedback += "Lowercase: Yes" }
        else { $feedback += "Lowercase: Missing" }

        if ($plainText -match '[0-9]') { $score++; $feedback += "Numbers: Yes" }
        else { $feedback += "Numbers: Missing" }

        if ($plainText -match '[^a-zA-Z0-9]') { $score++; $feedback += "Special chars: Yes" }
        else { $feedback += "Special chars: Missing" }

        # Display strength bar
        $maxScore = 7
        $barLength = 20
        $filled = [math]::Round(($score / $maxScore) * $barLength)
        $bar = ([char]0x2588).ToString() * $filled + ([char]0x2591).ToString() * ($barLength - $filled)

        $strengthLabel = if ($score -ge 6) { "Strong" } elseif ($score -ge 4) { "Moderate" } elseif ($score -ge 2) { "Weak" } else { "Very Weak" }
        $color = if ($score -ge 6) { "Success" } elseif ($score -ge 4) { "Warning" } else { "Error" }

        Write-OutputColor "  Strength: [$bar] $strengthLabel ($score/$maxScore)" -color $color
        foreach ($item in $feedback) {
            $itemColor = if ($item -match 'Missing|Too short') { "Warning" } else { "Info" }
            Write-OutputColor "    $item" -color $itemColor
        }
    } finally {
        $plainText = $null
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
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
    Write-OutputColor "  - Cannot start with `$ # - ' or `"" -color "Info"
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

            # Show password strength feedback
            Write-OutputColor "" -color "Info"
            Show-PasswordStrength -SecurePassword $Password1

            Write-OutputColor "" -color "Info"
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
                $maxPwdAge = $user.PasswordExpires
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
    Clear-MenuCache
    Write-PressEnter
}

# Function to generate a strong random password
function New-StrongPassword {
    param([int]$Length = 16)

    if ($Length -lt 12) { $Length = 12 }
    if ($Length -gt 128) { $Length = 128 }

    $upper = "ABCDEFGHJKLMNPQRSTUVWXYZ"    # No I, O (ambiguous)
    $lower = "abcdefghjkmnpqrstuvwxyz"      # No i, l, o (ambiguous)
    $digits = "23456789"                     # No 0, 1 (ambiguous)
    $special = "!@#%^&*-_=+"                 # Safe special chars

    # Use cryptographic RNG for secure index generation. Use rejection sampling
    # against an unbiased-modulo cap so we don't introduce modulo bias on non-
    # power-of-2 alphabets (24/22/8/11 chars). Also use UInt32 to avoid the
    # 1-in-4-billion Int32.MinValue overflow that [math]::Abs would throw on.
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $cryptoRandom = {
        param([int]$Max)
        if ($Max -le 0) { throw "cryptoRandom: Max must be > 0" }
        $bytes = New-Object byte[] 4
        $limit = [uint32]([uint32]::MaxValue - ([uint32]::MaxValue % [uint32]$Max))
        # Bounded loop instead of while($true) so a degenerate RNG can't hang
        # indefinitely. Expected iterations for rejection sampling: ~2 for typical
        # alphabet sizes (24/22/8/11). 100 is a generous ceiling.
        for ($attempt = 0; $attempt -lt 100; $attempt++) {
            $rng.GetBytes($bytes)
            $val = [BitConverter]::ToUInt32($bytes, 0)
            if ($val -lt $limit) { return [int]($val % [uint32]$Max) }
        }
        throw "cryptoRandom: rejection sampling failed after 100 attempts (RNG returning out-of-range values)"
    }

    # Ensure at least one of each type
    $password = @(
        $upper[(& $cryptoRandom $upper.Length)]
        $lower[(& $cryptoRandom $lower.Length)]
        $digits[(& $cryptoRandom $digits.Length)]
        $special[(& $cryptoRandom $special.Length)]
    )

    $allChars = $upper + $lower + $digits + $special
    for ($i = $password.Count; $i -lt $Length; $i++) {
        $password += $allChars[(& $cryptoRandom $allChars.Length)]
    }

    # Shuffle using Fisher-Yates with crypto RNG
    for ($i = $password.Count - 1; $i -gt 0; $i--) {
        $j = & $cryptoRandom ($i + 1)
        $temp = $password[$i]; $password[$i] = $password[$j]; $password[$j] = $temp
    }
    $rng.Dispose()
    $password = $password -join ''

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  GENERATED PASSWORD".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    # Stop transcript (if running) around the password display so the plaintext doesn't get
    # archived to disk. Start-Transcript captures every Write-Host/Write-Output line verbatim
    # including the box rendering. Past pattern: operator generates a password during an
    # admin session with transcripts enabled — plaintext ends up in the log on disk indefinitely.
    $transcriptWasRunning = $false
    try {
        $existing = Stop-Transcript -ErrorAction Stop
        if ($existing) { $transcriptWasRunning = $true }
    } catch { }
    # Write directly to the console (bypasses Write-OutputColor's transcript-routing).
    [Console]::WriteLine()
    [Console]::WriteLine("  │  $($password.PadRight(72).Substring(0,72))│")
    Write-OutputColor "  │$("  Length: $Length | Complexity: Upper+Lower+Digit+Special".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    if ($transcriptWasRunning) {
        try {
            $transcriptPath = if ($script:TranscriptPath) { $script:TranscriptPath } else { $null }
            if ($transcriptPath) {
                Start-Transcript -Path $transcriptPath -Append -ErrorAction SilentlyContinue | Out-Null
            } else {
                Start-Transcript -ErrorAction SilentlyContinue | Out-Null
            }
        } catch { }
    }

    # Copy to clipboard with auto-clear timer. Uses [Threading.Timer] in the same
    # runspace rather than Start-Job, because Start-Job's -ArgumentList holds the
    # plaintext password in job metadata until the host exits (the previous
    # implementation also never cleaned the job up). Threading.Timer captures via
    # closure inside this process only.
    try {
        Set-Clipboard -Value $password -ErrorAction Stop
        $clipTTL = 60
        $expectedClip = $password
        $timerCallback = [System.Threading.TimerCallback]{
            param($state)
            try {
                $current = Get-Clipboard -Raw -ErrorAction Stop
                if ($current -eq $state) {
                    Set-Clipboard -Value '' -ErrorAction Stop
                }
            } catch { }
        }
        # Timer is fire-once (period = -1). Reference is intentionally not held;
        # GC will reclaim after the callback fires.
        $null = New-Object System.Threading.Timer($timerCallback, $expectedClip, ($clipTTL * 1000), [System.Threading.Timeout]::Infinite)
        Write-OutputColor "  Copied to clipboard (auto-clears in ${clipTTL}s while this window is open)." -color "Success"
    }
    catch {
        Write-OutputColor "  Tip: Select and copy the password above." -color "Info"
    }

    return $password
}
#endregion