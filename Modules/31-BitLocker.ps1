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
        switch ($choice) {
            { $_ -eq "I" -or $_ -eq "i" } {
                if (-not (Test-WindowsServer)) { return }
                if (-not (Confirm-UserAction -Message "Install BitLocker feature?")) { return }
                try {
                    Write-OutputColor "  Installing BitLocker..." -color "Info"
                    Install-WindowsFeature -Name BitLocker -IncludeManagementTools -ErrorAction Stop
                    Write-OutputColor "  BitLocker installed. Reboot required before use." -color "Success"
                    $global:RebootNeeded = $true
                    Add-SessionChange -Category "System" -Description "Installed BitLocker"
                }
                catch {
                    Write-OutputColor "  Failed: $_" -color "Error"
                }
                Write-PressEnter
            }
            default { }
        }
        return
    }

    while ($true) {
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
                if ($volNum -match '^\d+$' -and [int]$volNum -ge 1 -and [int]$volNum -le $volumes.Count) {
                    $vol = $volumes[[int]$volNum - 1]
                    if ($vol.ProtectionStatus -eq "On") {
                        Write-OutputColor "  This volume is already encrypted." -color "Warning"
                    } else {
                        Write-OutputColor "" -color "Info"
                        Write-OutputColor "  [1] TPM only (recommended)" -color "Info"
                        Write-OutputColor "  [2] TPM + PIN" -color "Info"
                        Write-OutputColor "  [3] Password only (no TPM)" -color "Info"
                        $method = Read-Host "  Select encryption method"

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
                            }
                            Write-OutputColor "  BitLocker enabled on $($vol.MountPoint). Encryption will begin." -color "Success"
                            Write-OutputColor "  IMPORTANT: Save your recovery key!" -color "Warning"
                            Add-SessionChange -Category "Security" -Description "Enabled BitLocker on $($vol.MountPoint)"
                        }
                        catch {
                            Write-OutputColor "  Failed: $_" -color "Error"
                        }
                    }
                }
            }
            "2" {
                $volNum = Read-Host "  Enter volume number to decrypt"
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
                if ($volNum -match '^\d+$' -and [int]$volNum -ge 1 -and [int]$volNum -le $volumes.Count) {
                    $vol = $volumes[[int]$volNum - 1]
                    try {
                        if (Test-WindowsServer) {
                            # Server: backup to Active Directory
                            $blVolInfo = Get-BitLockerVolume -MountPoint $vol.MountPoint
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
                            $savePath = Read-Host "  Enter save path (e.g., C:\Temp\BitLockerKey.txt)"
                            $navResult = Test-NavigationCommand -UserInput $savePath
                            if ($navResult.ShouldReturn) { continue }
                            if ([string]::IsNullOrWhiteSpace($savePath)) {
                                $savePath = "$env:USERPROFILE\Desktop\BitLockerKey_$($vol.MountPoint -replace '[:\\]','')_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
                                Write-OutputColor "  Using default path: $savePath" -color "Info"
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
                                $output | Out-File -FilePath $savePath -Encoding UTF8 -ErrorAction Stop
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
                if ($volNum -match '^\d+$' -and [int]$volNum -ge 1 -and [int]$volNum -le $volumes.Count) {
                    $vol = $volumes[[int]$volNum - 1]
                    $keys = (Get-BitLockerVolume -MountPoint $vol.MountPoint).KeyProtector | Where-Object { $_.RecoveryPassword }
                    if ($keys) {
                        Write-OutputColor "" -color "Info"
                        Write-OutputColor "  Recovery Key(s) for $($vol.MountPoint):" -color "Warning"
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
            "b" { return }
            "B" { return }
        }

        Write-PressEnter
    }
}
#endregion