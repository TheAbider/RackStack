#region ===== OFFLINE VHD CUSTOMIZATION =====
# Function to customize a sysprepped VHD before first boot
# This mounts the VHD, injects registry settings, and unmounts it
# so the VM boots with pre-applied configuration
function Set-OfflineVHDConfiguration {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$VHDPath,

        [string]$ComputerName = $null,

        [string]$TimeZoneId = $null,

        [bool]$EnableRDP = $true
    )

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  OFFLINE VHD CUSTOMIZATION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │  Applying settings to VHD before first boot...                         │" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Verify VHD exists
    if (-not (Test-Path $VHDPath)) {
        Write-OutputColor "  VHD not found: $VHDPath" -color "Error"
        return $false
    }

    $mountedVHD = $null
    $systemHiveLoaded = $false
    $softwareHiveLoaded = $false

    try {
        # Step 1: Mount the VHD
        Write-OutputColor "  Mounting VHD..." -color "Info"
        $mountedVHD = Mount-VHD -Path $VHDPath -Passthru -ErrorAction Stop

        # Wait a moment for the volume to become available
        Start-Sleep -Seconds 3

        # Get the drive letter assigned to the mounted VHD
        $disk = $mountedVHD | Get-Disk
        $partitions = $disk | Get-Partition | Where-Object { $_.DriveLetter }

        # Find the Windows partition (the one with \Windows folder)
        $windowsDrive = $null
        foreach ($part in $partitions) {
            $testPath = "$($part.DriveLetter):\Windows"
            if (Test-Path $testPath) {
                $windowsDrive = "$($part.DriveLetter):"
                break
            }
        }

        if (-not $windowsDrive) {
            # Try to assign a drive letter if none assigned
            $freeLetter = Get-NextAvailableDriveLetter
            if ($freeLetter) {
                $mainPartition = $disk | Get-Partition | Where-Object { $_.Size -gt 10GB } | Select-Object -First 1
                if ($mainPartition) {
                    Set-Partition -DiskNumber $mainPartition.DiskNumber -PartitionNumber $mainPartition.PartitionNumber -NewDriveLetter $freeLetter -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                    $windowsDrive = "${freeLetter}:"
                }
            }

            if (-not $windowsDrive -or -not (Test-Path "$windowsDrive\Windows")) {
                Write-OutputColor "  Could not find Windows partition in mounted VHD." -color "Error"
                Dismount-VHD -Path $VHDPath -ErrorAction SilentlyContinue
                return $false
            }
        }

        Write-OutputColor "  VHD mounted at: $windowsDrive" -color "Success"

        # Step 2: Load registry hives
        $offlineSystemHive = "$windowsDrive\Windows\System32\config\SYSTEM"
        $offlineSoftwareHive = "$windowsDrive\Windows\System32\config\SOFTWARE"

        # Load SYSTEM hive
        if (Test-Path $offlineSystemHive) {
            Write-OutputColor "  Loading SYSTEM registry hive..." -color "Info"
            reg load "HKLM\OFFLINE_SYSTEM" $offlineSystemHive 2>$null
            if ($LASTEXITCODE -eq 0) {
                $systemHiveLoaded = $true
            }
            else {
                Write-OutputColor "  Warning: Could not load SYSTEM hive." -color "Warning"
            }
        }

        # Load SOFTWARE hive
        if (Test-Path $offlineSoftwareHive) {
            Write-OutputColor "  Loading SOFTWARE registry hive..." -color "Info"
            reg load "HKLM\OFFLINE_SOFTWARE" $offlineSoftwareHive 2>$null
            if ($LASTEXITCODE -eq 0) {
                $softwareHiveLoaded = $true
            }
            else {
                Write-OutputColor "  Warning: Could not load SOFTWARE hive." -color "Warning"
            }
        }

        # Track partial failures for summary
        $offlineStepsApplied = 0
        $offlineStepsFailed = 0

        # Step 3: Apply computer name
        if ($ComputerName -and $systemHiveLoaded) {
            Write-OutputColor "  Setting computer name to: $ComputerName" -color "Info"
            try {
                # Set computer name in SYSTEM\ControlSet001\Control\ComputerName
                Set-ItemProperty -Path "HKLM:\OFFLINE_SYSTEM\ControlSet001\Control\ComputerName\ComputerName" -Name "ComputerName" -Value $ComputerName -ErrorAction Stop
                Set-ItemProperty -Path "HKLM:\OFFLINE_SYSTEM\ControlSet001\Control\ComputerName\ActiveComputerName" -Name "ComputerName" -Value $ComputerName -ErrorAction Stop

                # Also set in TCP/IP hostname
                Set-ItemProperty -Path "HKLM:\OFFLINE_SYSTEM\ControlSet001\Services\Tcpip\Parameters" -Name "Hostname" -Value $ComputerName -ErrorAction Stop
                Set-ItemProperty -Path "HKLM:\OFFLINE_SYSTEM\ControlSet001\Services\Tcpip\Parameters" -Name "NV Hostname" -Value $ComputerName -ErrorAction Stop

                Write-OutputColor "  Computer name set." -color "Success"
                $offlineStepsApplied++
            }
            catch {
                Write-OutputColor "  WARNING: Could not set computer name: $_" -color "Warning"
                $offlineStepsFailed++
            }
        }

        # Step 4: Enable Remote Desktop
        if ($EnableRDP -and $systemHiveLoaded -and $softwareHiveLoaded) {
            Write-OutputColor "  Enabling Remote Desktop..." -color "Info"
            try {
                # Enable RDP in the SYSTEM hive
                Set-ItemProperty -Path "HKLM:\OFFLINE_SYSTEM\ControlSet001\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -Type DWord -ErrorAction Stop

                # Enable NLA (Network Level Authentication) - more secure
                Set-ItemProperty -Path "HKLM:\OFFLINE_SYSTEM\ControlSet001\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1 -Type DWord -ErrorAction Stop

                # Enable RDP firewall rule by setting up the registry
                Set-ItemProperty -Path "HKLM:\OFFLINE_SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Name "fDenyTSConnections" -Value 0 -Type DWord -Force -ErrorAction Stop

                Write-OutputColor "  Remote Desktop enabled." -color "Success"
                $offlineStepsApplied++
            }
            catch {
                Write-OutputColor "  WARNING: Could not enable RDP: $_" -color "Warning"
                $offlineStepsFailed++
            }
        }

        # Step 5: Set timezone
        if ($TimeZoneId -and $systemHiveLoaded) {
            Write-OutputColor "  Setting timezone to: $TimeZoneId" -color "Info"
            try {
                $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId)
                if ($tz) {
                    Set-ItemProperty -Path "HKLM:\OFFLINE_SYSTEM\ControlSet001\Control\TimeZoneInformation" -Name "TimeZoneKeyName" -Value $TimeZoneId -ErrorAction Stop
                    Set-ItemProperty -Path "HKLM:\OFFLINE_SYSTEM\ControlSet001\Control\TimeZoneInformation" -Name "StandardName" -Value $tz.StandardName -ErrorAction Stop
                    Set-ItemProperty -Path "HKLM:\OFFLINE_SYSTEM\ControlSet001\Control\TimeZoneInformation" -Name "DaylightName" -Value $tz.DaylightName -ErrorAction Stop
                    Write-OutputColor "  Timezone set." -color "Success"
                    $offlineStepsApplied++
                }
            }
            catch {
                Write-OutputColor "  WARNING: Could not set timezone: $_" -color "Warning"
                $offlineStepsFailed++
            }
        }

        # Step 6: Set power plan to High Performance
        if ($softwareHiveLoaded) {
            Write-OutputColor "  Setting power plan to High Performance..." -color "Info"
            try {
                $powerKey = "HKLM:\OFFLINE_SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel\NameSpace\{025A5937-A6BE-4686-A844-36FE4BEC8B6D}"
                if (-not (Test-Path $powerKey)) {
                    New-Item -Path $powerKey -Force -ErrorAction Stop | Out-Null
                }
                $highPerfGUID = $script:PowerPlanGUID["High Performance"]
                Set-ItemProperty -Path "HKLM:\OFFLINE_SOFTWARE\Microsoft\Windows\CurrentVersion\PowerCfg" -Name "LastActiveScheme" -Value $highPerfGUID -Force -ErrorAction Stop
                Write-OutputColor "  Power plan configured." -color "Success"
                $offlineStepsApplied++
            }
            catch {
                Write-OutputColor "  WARNING: Power plan will need to be set after first boot." -color "Warning"
                $offlineStepsFailed++
            }
        }

        # Report partial failure summary
        if ($offlineStepsFailed -gt 0) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Offline customization: $offlineStepsApplied succeeded, $offlineStepsFailed failed" -color "Warning"
            Write-OutputColor "  Failed settings will need to be configured after first boot." -color "Warning"
        }

        # Step 7: Create a first-boot script to enable RDP firewall rule and other post-sysprep tasks
        Write-OutputColor "  Creating first-boot configuration script..." -color "Info"
        try {
            $firstBootScript = @"
# $($script:ToolName) First-Boot Configuration Script
# Auto-generated by $($script:ToolFullName) v$($script:ScriptVersion)
# This script runs once after sysprep completes and configures remaining settings

# Enable RDP firewall rules
try {
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0
} catch { }

# Set power plan to High Performance
try {
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
} catch { }

# Enable PowerShell Remoting
try {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction SilentlyContinue
} catch { }

# Clean up - delete this script after running
Remove-Item -Path `$MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
"@
            $scriptFolder = "$windowsDrive\Windows\Setup\Scripts"
            if (-not (Test-Path $scriptFolder)) {
                New-Item -Path $scriptFolder -ItemType Directory -Force | Out-Null
            }

            # SetupComplete.cmd runs automatically after Windows Setup/Sysprep completes
            $setupCompletePath = "$scriptFolder\SetupComplete.cmd"
            $psScriptPath = "$scriptFolder\$($script:ToolName)FirstBoot.ps1"

            # Write the PowerShell script
            Set-Content -Path $psScriptPath -Value $firstBootScript -Encoding UTF8 -Force -ErrorAction SilentlyContinue

            # Write SetupComplete.cmd to call our PowerShell script
            $cmdContent = "@echo off`r`npowershell.exe -ExecutionPolicy Bypass -File `"$($psScriptPath.Replace($windowsDrive, '%SystemDrive%'))`""
            Set-Content -Path $setupCompletePath -Value $cmdContent -Force -ErrorAction SilentlyContinue

            Write-OutputColor "  First-boot script created at: $scriptFolder" -color "Success"
        }
        catch {
            Write-OutputColor "  Note: First-boot script creation failed. Some settings may need manual config." -color "Warning"
        }

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Offline customization complete!" -color "Success"

        return $true
    }
    catch {
        Write-OutputColor "  Error during offline customization: $_" -color "Error"
        return $false
    }
    finally {
        # CRITICAL: Always unload hives and dismount VHD
        Write-OutputColor "  Cleaning up..." -color "Info"

        if ($systemHiveLoaded) {
            [gc]::Collect()
            Start-Sleep -Seconds 1
            reg unload "HKLM\OFFLINE_SYSTEM" 2>$null
        }
        if ($softwareHiveLoaded) {
            [gc]::Collect()
            Start-Sleep -Seconds 1
            reg unload "HKLM\OFFLINE_SOFTWARE" 2>$null
        }
        if ($mountedVHD) {
            Start-Sleep -Seconds 2
            Dismount-VHD -Path $VHDPath -ErrorAction SilentlyContinue
            Write-OutputColor "  VHD dismounted." -color "Info"
        }
    }
}

# Function to prompt for offline customization options
function Show-OfflineCustomizationPrompt {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$VHDPath,

        [string]$VMName = $null
    )

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  PRE-BOOT CUSTOMIZATION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │  The VHD can be customized before the VM boots for the first time.     │" -color "Info"
    Write-OutputColor "  │  This reduces manual configuration after the VM starts.                │" -color "Info"
    Write-OutputColor "  │                                                                        │" -color "Info"
    Write-OutputColor "  │  Settings that will be applied:                                        │" -color "Info"
    Write-OutputColor "  │   - Computer name (from VM name)                                       │" -color "Info"
    Write-OutputColor "  │   - Enable Remote Desktop                                              │" -color "Info"
    Write-OutputColor "  │   - Set timezone                                                       │" -color "Info"
    Write-OutputColor "  │   - High Performance power plan                                        │" -color "Info"
    Write-OutputColor "  │   - Enable PowerShell Remoting (first-boot script)                     │" -color "Info"
    Write-OutputColor "  │   - Enable RDP firewall rules (first-boot script)                      │" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Apply pre-boot customization to the VHD?")) {
        Write-OutputColor "  Skipping offline customization. VM will boot with default settings." -color "Info"
        return $false
    }

    # Get timezone
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Select timezone for the VM:" -color "Info"
    Write-OutputColor "  [1] Eastern Standard Time" -color "Success"
    Write-OutputColor "  [2] Central Standard Time" -color "Success"
    Write-OutputColor "  [3] Mountain Standard Time" -color "Success"
    Write-OutputColor "  [4] Pacific Standard Time" -color "Success"
    Write-OutputColor "  [5] Use host timezone ($(((Get-TimeZone).Id)))" -color "Success"
    Write-OutputColor "  [6] Skip timezone" -color "Info"
    Write-OutputColor "" -color "Info"

    $tzChoice = Read-Host "  Select timezone"

    $timezone = switch ($tzChoice) {
        "1" { "Eastern Standard Time" }
        "2" { "Central Standard Time" }
        "3" { "Mountain Standard Time" }
        "4" { "Pacific Standard Time" }
        "5" { (Get-TimeZone).Id }
        default { $null }
    }

    # Apply customization
    $result = Set-OfflineVHDConfiguration -VHDPath $VHDPath `
        -ComputerName $VMName `
        -TimeZoneId $timezone `
        -EnableRDP $true

    return $result
}
#endregion