#region ===== BITLOCKER MANAGEMENT =====
# Function to manage BitLocker encryption
function Show-BitLockerManagement {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                      BITLOCKER MANAGEMENT").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Check if BitLocker is available
    $blAvailable = $false
    if (Test-WindowsServer) {
        # Server OS: BitLocker is an installable feature
        $blFeature = Get-WindowsFeature -Name BitLocker -ErrorAction SilentlyContinue
        if ($null -ne $blFeature -and $blFeature.InstallState -eq "Installed") {
            $blAvailable = $true
        }
    } else {
        # Client OS (Win 10/11): BitLocker is built-in, check if cmdlet is available
        if ($null -ne (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
            $blAvailable = $true
        }
    }

    if (-not $blAvailable) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        if (Test-WindowsServer) {
            Write-OutputColor "  │$("  BitLocker feature is not installed.".PadRight(72))│" -color "Warning"
        } else {
            Write-OutputColor "  │$("  BitLocker is not available on this edition of Windows.".PadRight(72))│" -color "Warning"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        if (Test-WindowsServer) {
            Write-OutputColor "  [I] Install BitLocker" -color "Success"
        }
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }
        switch ($choice) {
            { $_ -eq "I" -or $_ -eq "i" } {
                if (-not (Test-WindowsServer)) { return }
                if (-not (Confirm-UserAction -Message "Install BitLocker feature?")) { return }
                $installResult = Install-WindowsFeatureWithTimeout -FeatureName "BitLocker" -DisplayName "BitLocker" -IncludeManagementTools
                if ($installResult.Success) {
                    Write-OutputColor "  Reboot required before use." -color "Warning"
                    $global:RebootNeeded = $true
                    Add-SessionChange -Category "System" -Description "Installed BitLocker"
                    Clear-MenuCache
                }
                Write-PressEnter
            }
            default { }
        }
        return
    }

    while ($true) {
        if ($global:ReturnToMainMenu) { return }
        # Show current BitLocker status
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                      BITLOCKER MANAGEMENT").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  VOLUME ENCRYPTION STATUS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        $volumes = $null
        try {
            $volumes = @(Get-BitLockerVolume -ErrorAction Stop)
        }
        catch {
            Write-OutputColor "  │$("  BitLocker requires a reboot before it can be used.".PadRight(72))│" -color "Warning"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Please reboot and try again." -color "Warning"
            Write-PressEnter
            return
        }
        $idx = 1
        foreach ($vol in $volumes) {
            $status = $vol.ProtectionStatus
            $encryption = $vol.VolumeStatus
            $color = switch ($status) {
                "On" { "Success" }
                "Off" { "Warning" }
                default { "Info" }
            }
            Write-OutputColor "  │$("  [$idx] $($vol.MountPoint) - Protection: $status | $encryption".PadRight(72))│" -color $color
            $idx++
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  OPTIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem -Text "[1]  Enable BitLocker on a Volume"
        Write-MenuItem -Text "[2]  Disable BitLocker on a Volume"
        if (Test-WindowsServer) {
            Write-MenuItem -Text "[3]  Backup Recovery Key to AD"
        } else {
            Write-MenuItem -Text "[3]  Save Recovery Key to File"
        }
        Write-MenuItem -Text "[4]  Show Recovery Key"
        Write-MenuItem -Text "[5]  Check Encryption Progress"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" {
                $volNum = Read-Host "  Enter volume number to encrypt"
                $navResult = Test-NavigationCommand -UserInput $volNum
                if ($navResult.ShouldReturn) { return }
                if ($volNum -match '^\d+$' -and [int]$volNum -ge 1 -and [int]$volNum -le $volumes.Count) {
                    $vol = $volumes[[int]$volNum - 1]
                    if ($vol.ProtectionStatus -eq "On") {
                        Write-OutputColor "  This volume is already encrypted." -color "Warning"
                    } else {
                        Write-OutputColor "" -color "Info"
                        Write-OutputColor "  [1] TPM only (recommended)" -color "Info"
                        Write-OutputColor "  [2] TPM + PIN" -color "Info"
                        Write-OutputColor "  [3] Password only (no TPM)" -color "Info"
                        $method = Read-Host "  Select"
                        $navResult = Test-NavigationCommand -UserInput $method
                        if ($navResult.ShouldReturn) { return }

                        try {
                            switch ($method) {
                                "1" {
                                    Enable-BitLocker -MountPoint $vol.MountPoint -TpmProtector -ErrorAction Stop
                                    Add-BitLockerKeyProtector -MountPoint $vol.MountPoint -RecoveryPasswordProtector -ErrorAction Stop
                                }
                                "2" {
                                    $pin = Read-Host "  Enter PIN (6+ digits)" -AsSecureString
                                    Enable-BitLocker -MountPoint $vol.MountPoint -TpmAndPinProtector -Pin $pin -ErrorAction Stop
                                    Add-BitLockerKeyProtector -MountPoint $vol.MountPoint -RecoveryPasswordProtector -ErrorAction Stop
                                }
                                "3" {
                                    $securePassword = Read-Host "  Enter password" -AsSecureString
                                    Enable-BitLocker -MountPoint $vol.MountPoint -PasswordProtector -Password $securePassword -ErrorAction Stop
                                    Add-BitLockerKeyProtector -MountPoint $vol.MountPoint -RecoveryPasswordProtector -ErrorAction Stop
                                }
                                default {
                                    Write-OutputColor "  Invalid selection. Choose 1, 2, or 3." -color "Error"
                                }
                            }
                            if ($method -in "1","2","3") {
                                Write-OutputColor "  BitLocker enabled on $($vol.MountPoint). Encryption will begin." -color "Success"
                                Write-OutputColor "" -color "Info"
                                Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Warning"
                                Write-OutputColor "  ║$("  RECOVERY KEY — SAVE NOW".PadRight(72))║" -color "Warning"
                                Write-OutputColor "  ╠════════════════════════════════════════════════════════════════════════╣" -color "Warning"
                                Write-OutputColor "  ║$("  Without this key, encrypted data is PERMANENTLY LOST if the".PadRight(72))║" -color "Warning"
                                Write-OutputColor "  ║$("  TPM/password is unavailable (hardware change, motherboard swap).".PadRight(72))║" -color "Warning"
                                Write-OutputColor "  ╠════════════════════════════════════════════════════════════════════════╣" -color "Warning"
                                Write-OutputColor "  ║$("  Secure storage options:".PadRight(72))║" -color "Warning"
                                if (Test-WindowsServer) {
                                    Write-OutputColor "  ║$("    [3] from menu → Backup to Active Directory (recommended)".PadRight(72))║" -color "Warning"
                                } else {
                                    Write-OutputColor "  ║$("    [3] from menu → Save to file (store on separate drive/USB)".PadRight(72))║" -color "Warning"
                                }
                                Write-OutputColor "  ║$("    [4] from menu → Display key (write down, store in vault)".PadRight(72))║" -color "Warning"
                                Write-OutputColor "  ║$("  DO NOT store recovery key on the encrypted volume itself.".PadRight(72))║" -color "Warning"
                                Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Warning"
                                Write-OutputColor "" -color "Info"
                                if (-not (Confirm-UserAction -Message "Have you noted how to save the recovery key?" -DefaultYes)) {
                                    Write-OutputColor "  Please use option [3] or [4] from the menu to save your key." -color "Warning"
                                }
                                Add-SessionChange -Category "Security" -Description "Enabled BitLocker on $($vol.MountPoint)"
                            }
                        }
                        catch {
                            Write-OutputColor "  Failed: $_" -color "Error"
                        }
                    }
                }
            }
            "2" {
                $volNum = Read-Host "  Enter volume number to decrypt"
                $navResult = Test-NavigationCommand -UserInput $volNum
                if ($navResult.ShouldReturn) { return }
                if ($volNum -match '^\d+$' -and [int]$volNum -ge 1 -and [int]$volNum -le $volumes.Count) {
                    $vol = $volumes[[int]$volNum - 1]
                    if (Confirm-UserAction -Message "Disable BitLocker on $($vol.MountPoint)?") {
                        try {
                            Disable-BitLocker -MountPoint $vol.MountPoint -ErrorAction Stop
                            Write-OutputColor "  BitLocker disabled. Decryption in progress." -color "Success"
                            Add-SessionChange -Category "Security" -Description "Disabled BitLocker on $($vol.MountPoint)"
                        }
                        catch {
                            Write-OutputColor "  Failed: $_" -color "Error"
                        }
                    }
                }
            }
            "3" {
                $volNum = Read-Host "  Enter volume number"
                $navResult = Test-NavigationCommand -UserInput $volNum
                if ($navResult.ShouldReturn) { return }
                if ($volNum -match '^\d+$' -and [int]$volNum -ge 1 -and [int]$volNum -le $volumes.Count) {
                    $vol = $volumes[[int]$volNum - 1]
                    try {
                        if (Test-WindowsServer) {
                            # Server: backup to Active Directory
                            $blVolInfo = Get-BitLockerVolume -MountPoint $vol.MountPoint -ErrorAction Stop
                            if ($null -eq $blVolInfo) {
                                Write-OutputColor "  Could not retrieve BitLocker volume info." -color "Error"
                                Write-PressEnter
                                continue
                            }
                            $recoveryProtector = $blVolInfo.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" } | Select-Object -First 1
                            if ($null -eq $recoveryProtector) {
                                Write-OutputColor "  No recovery password key protector found." -color "Error"
                                Write-PressEnter
                                continue
                            }
                            Backup-BitLockerKeyProtector -MountPoint $vol.MountPoint -KeyProtectorId $recoveryProtector.KeyProtectorId -ErrorAction Stop
                            Write-OutputColor "  Recovery key backed up to Active Directory." -color "Success"
                        } else {
                            # Client: save to file
                            $savePath = Read-Host "  Enter save path (e.g., $($script:TempPath)\BitLockerKey.txt)"
                            $navResult = Test-NavigationCommand -UserInput $savePath
                            if ($navResult.ShouldReturn) { continue }
                            if ($savePath) { $savePath = $savePath.Trim('"') }
                            if ([string]::IsNullOrWhiteSpace($savePath)) {
                                $savePath = "$env:USERPROFILE\Desktop\BitLockerKey_$($vol.MountPoint -replace '[:\\]','')_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
                                Write-OutputColor "  Using default path: $savePath" -color "Info"
                            }
                            if ($savePath -match '^\\\\\w') {
                                Write-OutputColor "  WARNING: Saving BitLocker keys to a network path is a security risk!" -color "Error"
                                if (-not (Confirm-UserAction -Message "Save to network path anyway?")) { continue }
                            }
                            $saveDir = Split-Path $savePath -Parent
                            if ($saveDir -and -not (Test-Path -LiteralPath $saveDir)) {
                                Write-OutputColor "  Directory does not exist: $saveDir" -color "Error"
                                Write-PressEnter
                                continue
                            }
                            $blVol = Get-BitLockerVolume -MountPoint $vol.MountPoint
                            $keys = $blVol.KeyProtector | Where-Object { $_.RecoveryPassword }
                            if ($keys) {
                                $output = @()
                                $output += "BitLocker Recovery Key for $($vol.MountPoint)"
                                $output += "Computer: $env:COMPUTERNAME"
                                $output += "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                                $output += ""
                                foreach ($key in $keys) {
                                    $output += "Key Protector ID: $($key.KeyProtectorId)"
                                    $output += "Recovery Password: $($key.RecoveryPassword)"
                                    $output += ""
                                }
                                $output | Out-File -LiteralPath $savePath -Encoding UTF8 -ErrorAction Stop
                                Write-OutputColor "  Recovery key saved to: $savePath" -color "Success"
                                Write-OutputColor "  IMPORTANT: Store this file in a secure location!" -color "Warning"
                            } else {
                                Write-OutputColor "  No recovery password found for this volume." -color "Warning"
                            }
                        }
                    }
                    catch {
                        Write-OutputColor "  Failed: $_" -color "Error"
                    }
                }
            }
            "4" {
                $volNum = Read-Host "  Enter volume number"
                $navResult = Test-NavigationCommand -UserInput $volNum
                if ($navResult.ShouldReturn) { return }
                if ($volNum -match '^\d+$' -and [int]$volNum -ge 1 -and [int]$volNum -le $volumes.Count) {
                    $vol = $volumes[[int]$volNum - 1]
                    $blVolume = Get-BitLockerVolume -MountPoint $vol.MountPoint -ErrorAction SilentlyContinue
                    $keys = if ($null -ne $blVolume) { $blVolume.KeyProtector | Where-Object { $_.RecoveryPassword } } else { $null }
                    if ($keys) {
                        Write-OutputColor "" -color "Info"
                        Write-OutputColor "  Recovery Key(s) for $($vol.MountPoint):" -color "Warning"
                        Write-OutputColor "  NOTE: Keys will appear in the session transcript log." -color "Warning"
                        foreach ($key in $keys) {
                            Write-OutputColor "  ID: $($key.KeyProtectorId)" -color "Info"
                            Write-OutputColor "  Key: $($key.RecoveryPassword)" -color "Success"
                        }
                    }
                    else {
                        Write-OutputColor "  No recovery password found." -color "Warning"
                    }
                }
            }
            "5" {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
                Write-OutputColor "  │$("  ENCRYPTION PROGRESS".PadRight(72))│" -color "Info"
                Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                foreach ($vol in $volumes) {
                    $status = if ($vol.VolumeStatus) { $vol.VolumeStatus.ToString() } else { "Unknown" }
                    $pct = $vol.EncryptionPercentage
                    $pctColor = if ($pct -eq 100) { "Success" } elseif ($pct -gt 0) { "Warning" } else { "Info" }
                    $statusText = switch -Wildcard ($status) {
                        "FullyEncrypted"     { "Encrypted (100%)" }
                        "FullyDecrypted"     { "Not encrypted" }
                        "EncryptionInProgress" { "Encrypting... $pct%" }
                        "DecryptionInProgress" { "Decrypting... $pct%" }
                        "*Paused*"           { "Paused at $pct%" }
                        default              { "$status ($pct%)" }
                    }
                    Write-OutputColor "  │$("  $($vol.MountPoint)  $statusText".PadRight(72))│" -color $pctColor
                }
                Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            }
            { $_ -eq "b" -or $_ -eq "B" } { return }
            default { Write-OutputColor "  Invalid choice. Enter 1-5 or B." -color "Error"; Start-Sleep -Seconds 1 }
        }

        Write-PressEnter
    }
}
#endregion