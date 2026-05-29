#region ===== BITLOCKER MANAGEMENT =====
# Function to verify BitLocker recovery keys are properly backed up
function Test-BitLockerRecoveryBackup {
    try {
        $volumes = Get-BitLockerVolume -ErrorAction SilentlyContinue
        if ($null -eq $volumes) {
            Write-OutputColor "  BitLocker not available or no encrypted volumes" -color "Info"
            return
        }

        foreach ($vol in $volumes) {
            $mountPoint = $vol.MountPoint
            $status = $vol.VolumeStatus.ToString()

            if ($status -eq 'FullyDecrypted') { continue }

            Write-OutputColor "`n  Volume: $mountPoint ($status)" -color "Info"

            $protectors = $vol.KeyProtector
            $hasRecoveryPassword = $false
            $hasTPM = $false

            foreach ($protector in $protectors) {
                $type = $protector.KeyProtectorType.ToString()
                switch ($type) {
                    'RecoveryPassword' {
                        $hasRecoveryPassword = $true
                        Write-OutputColor "    Recovery Password: $($protector.KeyProtectorId)" -color "Success"
                    }
                    'Tpm' {
                        $hasTPM = $true
                        Write-OutputColor "    TPM Protector: Present" -color "Success"
                    }
                    'TpmPin' {
                        $hasTPM = $true
                        Write-OutputColor "    TPM+PIN Protector: Present" -color "Success"
                    }
                    default {
                        Write-OutputColor "    $type Protector: Present" -color "Info"
                    }
                }
            }

            if (-not $hasRecoveryPassword) {
                Write-OutputColor "    WARNING: No recovery password protector found!" -color "Error"
                Write-OutputColor "    Run: Add-BitLockerKeyProtector -MountPoint $mountPoint -RecoveryPasswordProtector" -color "Warning"
            }

            # Check if recovery key is backed up to AD
            try {
                $adComputer = Get-ADComputer $env:COMPUTERNAME -ErrorAction Stop
                $adBackup = Get-ADObject -Filter "objectClass -eq 'msFVE-RecoveryInformation'" -SearchBase $adComputer.DistinguishedName -ErrorAction SilentlyContinue
                if ($null -ne $adBackup) {
                    Write-OutputColor "    AD Backup: Found ($(@($adBackup).Count) key(s))" -color "Success"
                } else {
                    Write-OutputColor "    AD Backup: No recovery keys found in AD" -color "Warning"
                }
            } catch {
                Write-OutputColor "    AD Backup: Cannot verify (not domain-joined or AD tools not available)" -color "Info"
            }
        }
    } catch {
        Write-OutputColor "  BitLocker check failed: $($_.Exception.Message)" -color "Error"
    }
}

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
                    $script:RebootNeeded = $true
                    Add-SessionChange -Category "System" -Description "Installed BitLocker"
                    Clear-MenuCache
                }
                Write-PressEnter
            }
            default { Write-OutputColor "  Invalid selection. Enter I or B." -color "Error"; Start-Sleep -Seconds 1 }
        }
        return
    }

    while ($true) {
        if ($script:ReturnToMainMenu) { return }
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
        Write-MenuItem -Text "[6]  Verify Recovery Key Backup"
        Write-MenuItem -Text "[7]  VHDX Encryption-at-Rest Audit"
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

                        # Validate TPM before TPM-based methods
                        if ($method -in "1","2") {
                            $tpm = Get-Tpm -ErrorAction SilentlyContinue
                            if ($null -eq $tpm -or -not $tpm.TpmPresent) {
                                Write-OutputColor "  No TPM detected on this system." -color "Error"
                                Write-OutputColor "  Use option [3] (Password only) for non-TPM systems." -color "Info"
                                Write-PressEnter
                                continue
                            }
                            if (-not $tpm.TpmReady) {
                                Write-OutputColor "  TPM is present but not ready (may need initialization in BIOS)." -color "Warning"
                                if (-not (Confirm-UserAction -Message "Attempt anyway?")) { continue }
                            }
                        }

                        if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
                            # BitLocker enable is ONE-WAY: turning it off triggers a
                            # full-volume decryption that takes hours and produces no
                            # captured Undo scriptblock that can be safely re-applied.
                            # PIN / password is collected NOW (at queue time) so the
                            # Apply scriptblock holds the SecureString in the queue
                            # and the operator doesn't have to re-enter it at Commit.
                            $capMount = $vol.MountPoint
                            $capMethod = $method
                            $capPin = $null
                            $capPwd = $null
                            if ($method -eq "2") { $capPin = Read-Host "  Enter PIN (6+ digits)" -AsSecureString }
                            elseif ($method -eq "3") { $capPwd = Read-Host "  Enter password" -AsSecureString }
                            Push-DryRunStep -Label "Enable BitLocker on $capMount (method $capMethod)" -Category "Security" -OneWay $true `
                                -Params @{ MountPoint = $capMount; Method = $capMethod } `
                                -Preflight {
                                    $v = Get-BitLockerVolume -MountPoint $capMount -ErrorAction SilentlyContinue
                                    if ($null -eq $v) { "Volume $capMount not BitLocker-eligible" }
                                    elseif ($v.ProtectionStatus -eq "On") { "Volume $capMount already protected" }
                                    else { $true }
                                }.GetNewClosure() `
                                -Apply {
                                    switch ($capMethod) {
                                        "1" { Enable-BitLocker -MountPoint $capMount -TpmProtector -ErrorAction Stop }
                                        "2" { Enable-BitLocker -MountPoint $capMount -TpmAndPinProtector -Pin $capPin -ErrorAction Stop }
                                        "3" { Enable-BitLocker -MountPoint $capMount -PasswordProtector -Password $capPwd -ErrorAction Stop }
                                    }
                                    Add-BitLockerKeyProtector -MountPoint $capMount -RecoveryPasswordProtector -ErrorAction Stop
                                }.GetNewClosure()
                            Write-OutputColor "  Queued (Dry-Run): enable BitLocker on $capMount (method $capMethod, ONE-WAY)." -color "Warning"
                            Add-SessionChange -Category "DryRun" -Description "Queued BitLocker enable on $capMount"
                            continue
                        }

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
                                Clear-MenuCache
                            }
                        }
                        catch {
                            Write-RackStackError -Code "RS-3005" -Detail "$_"
                            Write-OutputColor "  Failed: $_" -color "Error"
                        }
                    }
                } else {
                    Write-OutputColor "  Invalid selection. Enter 1-$($volumes.Count)." -color "Error"
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
                            Clear-MenuCache
                        }
                        catch {
                            Write-OutputColor "  Failed: $_" -color "Error"
                        }
                    }
                } else {
                    Write-OutputColor "  Invalid selection. Enter 1-$($volumes.Count)." -color "Error"
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
                                Write-OutputColor "  Tip: Ensure BitLocker is enabled on this volume and try again after a reboot." -color "Warning"
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
                                # Atomic write-then-rename. Without this, a process kill (Ctrl+C,
                                # power loss, AV quarantine) mid-Out-File could truncate the
                                # recovery-key file to 0 bytes. BitLocker recovery keys are
                                # disaster-recovery-only; an empty file means the operator can't
                                # unlock the drive when BitLocker enters recovery mode.
                                $tmpSavePath = "$savePath.tmp"
                                try {
                                    $output | Out-File -LiteralPath $tmpSavePath -Encoding UTF8 -ErrorAction Stop
                                    Move-Item -LiteralPath $tmpSavePath -Destination $savePath -Force -ErrorAction Stop
                                } catch {
                                    if (Test-Path -LiteralPath $tmpSavePath) { Remove-Item -LiteralPath $tmpSavePath -Force -ErrorAction SilentlyContinue }
                                    throw
                                }
                                Write-OutputColor "  Recovery key saved to: $savePath" -color "Success"
                                Write-OutputColor "  IMPORTANT: Store this file in a secure location!" -color "Warning"
                            } else {
                                Write-OutputColor "  No recovery password found for this volume." -color "Warning"
                            }
                        }
                    }
                    catch {
                        Write-RackStackError -Code "RS-3008" -Detail "$_"
                        Write-OutputColor "  Failed: $_" -color "Error"
                    }
                } else {
                    Write-OutputColor "  Invalid selection. Enter 1-$($volumes.Count)." -color "Error"
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
                        # Pause transcript around the recovery-key display. Without this, the key
                        # gets written verbatim to the session transcript log on disk — which lives
                        # in $env:TEMP for up to 30 days. A BitLocker recovery key in a plaintext
                        # log file defeats the entire point of whole-disk encryption: anyone who
                        # reads the log can decrypt the drive. Same pattern as 22-Password's
                        # generated-password display (v1.98.24 fix).
                        $transcriptWasRunning = $false
                        try {
                            $existing = Stop-Transcript -ErrorAction Stop
                            if ($existing) { $transcriptWasRunning = $true }
                        } catch { }
                        foreach ($key in $keys) {
                            # Write directly to console (bypasses Write-OutputColor's transcript-routing).
                            [Console]::WriteLine()
                            [Console]::WriteLine("  ID:  $($key.KeyProtectorId)")
                            [Console]::WriteLine("  Key: $($key.RecoveryPassword)")
                        }
                        [Console]::WriteLine()
                        if ($transcriptWasRunning) {
                            try {
                                if ($script:TranscriptPath) {
                                    Start-Transcript -Path $script:TranscriptPath -Append -ErrorAction SilentlyContinue | Out-Null
                                } else {
                                    Start-Transcript -ErrorAction SilentlyContinue | Out-Null
                                }
                            } catch { }
                        }
                        Write-OutputColor "  (Recovery key displayed above bypassed transcript logging.)" -color "Info"
                    }
                    else {
                        Write-OutputColor "  No recovery password found." -color "Warning"
                    }
                } else {
                    Write-OutputColor "  Invalid selection. Enter 1-$($volumes.Count)." -color "Error"
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
            "6" {
                Clear-Host
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
                Write-OutputColor "  ║$(("                   RECOVERY KEY BACKUP VERIFICATION").PadRight(72))║" -color "Info"
                Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
                Write-OutputColor "" -color "Info"
                Test-BitLockerRecoveryBackup
            }
            "7" { Show-VHDXEncryptionAudit }
            { $_ -eq "b" -or $_ -eq "B" } { return }
            default { Write-OutputColor "  Invalid choice. Enter 1-7 or B." -color "Error"; Start-Sleep -Seconds 1 }
        }

        Write-PressEnter
    }
}

# Read-only encryption-at-rest verification: report whether each VHD/VHDX
# backing a Hyper-V VM sits on a BitLocker-protected volume. No changes made.
function Get-VHDXEncryptionStatus {
    $paths = New-Object System.Collections.Generic.List[string]
    try {
        if (Get-Command -Name Get-VM -ErrorAction SilentlyContinue) {
            foreach ($d in (Get-VM -ErrorAction SilentlyContinue | Get-VMHardDiskDrive -ErrorAction SilentlyContinue)) {
                if (-not [string]::IsNullOrWhiteSpace($d.Path)) { $paths.Add($d.Path) }
            }
        }
    }
    catch { }
    $unique = @($paths | Sort-Object -Unique)
    # Cache volume -> protection status from BitLocker once.
    $blByMount = @{}
    try { foreach ($v in (Get-BitLockerVolume -ErrorAction SilentlyContinue)) { $blByMount["$($v.MountPoint)"] = "$($v.ProtectionStatus)" } } catch { }
    $results = @()
    foreach ($p in $unique) {
        $root = $null
        try { $root = ([System.IO.Path]::GetPathRoot($p)).TrimEnd('\') } catch { }
        $prot = if ($root -and $blByMount.ContainsKey($root)) { $blByMount[$root] } else { "Unknown" }
        $results += [PSCustomObject]@{
            Path = $p; Volume = $root; Protection = $prot; Encrypted = ($prot -eq 'On')
        }
    }
    return $results
}

# Interactive display of the VHDX encryption-at-rest audit.
function Show-VHDXEncryptionAudit {
    Clear-Host
    Write-CenteredOutput "VHDX Encryption-at-Rest Audit" -color "Info"
    if ($null -eq (Get-Command -Name Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
        Write-OutputColor "  BitLocker is not available on this system." -color "Warning"; return
    }
    $r = @(Get-VHDXEncryptionStatus)
    if ($r.Count -eq 0) {
        Write-OutputColor "  No VHD/VHDX virtual disks found (no Hyper-V VMs, or none attached)." -color "Info"; return
    }
    Write-OutputColor "" -color "Info"
    foreach ($item in $r) {
        $label = if ($item.Encrypted) { "ENCRYPTED" } elseif ($item.Protection -eq 'Off') { "UNENCRYPTED" } else { "UNKNOWN" }
        $c = if ($item.Encrypted) { "Success" } elseif ($item.Protection -eq 'Off') { "Error" } else { "Warning" }
        Write-OutputColor ("  [{0}] {1}" -f $label, $item.Path) -color $c
        Write-OutputColor ("           volume: $(if ($item.Volume) { $item.Volume } else { 'unresolved (CSV/UNC/remote)' })") -color "Debug"
    }
    $enc = @($r | Where-Object { $_.Encrypted }).Count
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  $enc of $($r.Count) virtual disk(s) sit on BitLocker-protected volumes." -color "Info"
    Write-OutputColor "  'Unknown' volumes (CSV / UNC / remote storage) are not enumerable by Get-BitLockerVolume." -color "Debug"
}

# CLI entry: VHDXEncryptionAudit — read-only, JSON-aware.
function Start-VHDXEncryptionAudit {
    $r = @(Get-VHDXEncryptionStatus)
    if ($script:CLIOutputFormat -eq 'JSON') {
        Write-Output (@{
            Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'VHDXEncryptionAudit'
            Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
            TotalDisks = $r.Count; EncryptedDisks = @($r | Where-Object { $_.Encrypted }).Count
            Disks = @($r | ForEach-Object { @{ Path = $_.Path; Volume = $_.Volume; Protection = $_.Protection; Encrypted = $_.Encrypted } })
        } | ConvertTo-Json -Depth 5)
    }
    else {
        Show-VHDXEncryptionAudit
    }
    return $true
}
#endregion