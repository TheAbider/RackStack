#region ===== MPIO INSTALLATION =====
# Function to check if MPIO is installed
function Test-MPIOInstalled {
    if (-not (Test-WindowsServer)) { return $false }
    try {
        $mpioFeature = Get-WindowsFeature -Name MultipathIO -ErrorAction SilentlyContinue
        if ($mpioFeature -and $mpioFeature.InstallState -eq "Installed") {
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

# Show MPIO status summary including claimed devices and active paths
function Show-MPIOStatusSummary {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  MPIO STATUS SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    # Check feature install state
    try {
        $mpioFeature = Get-WindowsFeature -Name MultipathIO -ErrorAction Stop
        $featureState = $mpioFeature.InstallState
        $stateColor = if ($featureState -eq "Installed") { "Success" } else { "Warning" }
        Write-OutputColor "  │$("  Feature State:    $featureState".PadRight(72))│" -color $stateColor
    }
    catch {
        Write-OutputColor "  │$("  Feature State:    Unable to query".PadRight(72))│" -color "Error"
    }

    # Check if MPIO module is available
    $mpioModule = Get-Module -ListAvailable -Name MPIO -ErrorAction SilentlyContinue
    if ($null -ne $mpioModule) {
        Write-OutputColor "  │$("  MPIO Module:      Available (v$($mpioModule.Version))".PadRight(72))│" -color "Success"

        # Try to get MPIO configuration details
        try {
            Import-Module MPIO -ErrorAction SilentlyContinue

            # Get claimed hardware IDs. Storage cmdlets can hang for minutes on a host where
            # MS DSM is wedged (common after a SAN path flap mid-claim cycle). Wrap each call
            # in Start-Job + Wait-Job (same pattern as Test-SystemDisk after v1.98.20). The
            # menu freezes silently otherwise — the only existing timeout was on MPIO_DISK_INFO.
            $claimedJob = Start-Job -ScriptBlock { Get-MSDSMSupportedHW -ErrorAction SilentlyContinue }
            $claimedDevices = if (Wait-Job -Job $claimedJob -Timeout 15) { @(Receive-Job -Job $claimedJob -ErrorAction SilentlyContinue) } else { @() }
            Stop-Job -Job $claimedJob -ErrorAction SilentlyContinue
            Remove-Job -Job $claimedJob -Force -ErrorAction SilentlyContinue
            Write-OutputColor "  │$("  Claimed Devices:  $($claimedDevices.Count) hardware ID(s)".PadRight(72))│" -color "Info"

            foreach ($device in $claimedDevices) {
                $vendor = if ($null -ne $device.VendorId) { $device.VendorId.Trim() } else { '?' }
                $product = if ($null -ne $device.ProductId) { $device.ProductId.Trim() } else { '?' }
                $vendorProduct = "$vendor / $product"
                if ($vendorProduct.Length -gt 52) { $vendorProduct = $vendorProduct.Substring(0, 49) + "..." }
                Write-OutputColor "  │$("    $vendorProduct".PadRight(72))│" -color "Info"
            }

            # Get MPIO-managed disks (same Start-Job timeout)
            $autoClaimJob = Start-Job -ScriptBlock { Get-MSDSMAutomaticClaimSettings -ErrorAction SilentlyContinue }
            $mpioDrives = if (Wait-Job -Job $autoClaimJob -Timeout 15) { @(Receive-Job -Job $autoClaimJob -ErrorAction SilentlyContinue) } else { @() }
            Stop-Job -Job $autoClaimJob -ErrorAction SilentlyContinue
            Remove-Job -Job $autoClaimJob -Force -ErrorAction SilentlyContinue
            if ($mpioDrives.Count -gt 0) {
                $autoKeys = @($mpioDrives | ForEach-Object { $_.Keys }) | Select-Object -Unique
                foreach ($key in $autoKeys) {
                    Write-OutputColor "  │$("  Auto-Claim:       $key".PadRight(72))│" -color "Info"
                }
            }

            # Get load balance policy. Returns a CIM object on some PS versions whose
            # default ToString() yields the WMI class name (e.g. "MSFT_DSMLoadBalancePolicy")
            # rather than the actual policy. Pull the .PolicyName / .Policy property explicitly.
            try {
                $lbJob = Start-Job -ScriptBlock { Get-MSDSMGlobalDefaultLoadBalancePolicy -ErrorAction SilentlyContinue }
                $lbPolicy = if (Wait-Job -Job $lbJob -Timeout 15) { Receive-Job -Job $lbJob -ErrorAction SilentlyContinue } else { $null }
                Stop-Job -Job $lbJob -ErrorAction SilentlyContinue
                Remove-Job -Job $lbJob -Force -ErrorAction SilentlyContinue
                $lbPolicyText = if ($lbPolicy -is [string]) {
                    $lbPolicy
                } elseif ($null -ne $lbPolicy) {
                    if ($lbPolicy.PSObject.Properties.Match('PolicyName').Count) { [string]$lbPolicy.PolicyName }
                    elseif ($lbPolicy.PSObject.Properties.Match('Policy').Count) { [string]$lbPolicy.Policy }
                    else { [string]$lbPolicy }
                } else { $null }
                if (-not [string]::IsNullOrWhiteSpace($lbPolicyText)) {
                    Write-OutputColor "  │$("  Load Balance:     $lbPolicyText".PadRight(72))│" -color "Info"
                }
            }
            catch { }

            # Show active MPIO paths via WMI if available
            try {
                $mpioDisks = @(Get-CimInstance -Namespace "root\wmi" -ClassName "MPIO_DISK_INFO" -OperationTimeoutSec 8 -ErrorAction SilentlyContinue)
                if ($mpioDisks.Count -gt 0) {
                    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                    Write-OutputColor "  │$("  ACTIVE MULTIPATH DISKS".PadRight(72))│" -color "Info"
                    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

                    foreach ($disk in $mpioDisks) {
                        $diskName = $disk.DeviceName
                        if ($null -ne $diskName -and $diskName.Length -gt 50) {
                            $diskName = $diskName.Substring(0, 47) + "..."
                        }
                        $pathCount = 0
                        if ($null -ne $disk.NumberDrives) {
                            $pathCount = $disk.NumberDrives
                        }
                        $pathColor = if ($pathCount -ge 2) { "Success" } else { "Warning" }
                        $diskLine = "  $diskName"
                        $pathLine = "$pathCount path(s)"
                        $combined = "$diskLine"
                        if ($combined.Length -gt 55) { $combined = $combined.Substring(0, 55) }
                        $combined = $combined.PadRight(56) + $pathLine
                        Write-OutputColor "  │$($combined.PadRight(72))│" -color $pathColor
                    }
                }
                else {
                    Write-OutputColor "  │$("  Active Paths:     No multipath disks detected".PadRight(72))│" -color "Info"
                }
            }
            catch {
                Write-OutputColor "  │$("  Active Paths:     Could not query (may need reboot)".PadRight(72))│" -color "Info"
            }
        }
        catch {
            Write-OutputColor "  │$("  Details:          Could not load MPIO module".PadRight(72))│" -color "Warning"
        }
    }
    else {
        Write-OutputColor "  │$("  MPIO Module:      Not available (reboot may be required)".PadRight(72))│" -color "Warning"
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
}

# Function to install MPIO feature
function Install-MPIOFeature {
    Clear-Host
    Write-CenteredOutput "Install MPIO" -color "Info"

    if (Test-MPIOInstalled) {
        Write-OutputColor "  MPIO (Multipath I/O) is already installed." -color "Success"
        Show-MPIOStatusSummary
        return
    }

    Write-OutputColor "  MPIO (Multipath I/O) is not currently installed." -color "Info"

    # Pre-flight validation
    $preFlightOK = Show-PreFlightCheck -Feature "MPIO"
    if (-not $preFlightOK) {
        if (-not (Confirm-UserAction -Message "Continue despite blocking issues?")) {
            Write-OutputColor "  Installation cancelled." -color "Info"
            return
        }
    }

    Write-OutputColor "  MPIO enables multiple physical paths between a server" -color "Info"
    Write-OutputColor "  and storage devices for redundancy and performance." -color "Info"
    Write-OutputColor "  A reboot will be required after installation." -color "Warning"

    if (-not (Confirm-UserAction -Message "Install MPIO now?")) {
        Write-OutputColor "  MPIO installation cancelled." -color "Info"
        return
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        Push-DryRunStep -Label "Install MPIO (Multipath I/O) (reboot required)" -Category "Roles" -OneWay $false `
            -Preflight {
                if (Test-MPIOInstalled) { "MPIO already installed" }
                else { $true }
            } `
            -Apply { Install-MPIOFeature | Out-Null } `
            -Undo  { Uninstall-WindowsFeature -Name 'MultipathIO' -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null }
        Write-OutputColor "  Queued (Dry-Run): install MPIO." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued MPIO install"
        return
    }

    try {
        Write-OutputColor "`nInstalling MPIO... This may take several minutes." -color "Info"

        $installResult = Install-WindowsFeatureWithTimeout -FeatureName "MultipathIO" -DisplayName "MPIO" -IncludeManagementTools

        if ($installResult.TimedOut) {
            Add-SessionChange -Category "System" -Description "MPIO installation timed out"
            Clear-MenuCache
            return $false
        }
        elseif ($installResult.Success) {
            Write-OutputColor "`nMPIO installed successfully!" -color "Success"

            # Post-install verification
            $mpioModule = Get-Module -ListAvailable -Name MPIO -ErrorAction SilentlyContinue
            if ($mpioModule) {
                Write-OutputColor "  MPIO management cmdlets are available." -color "Success"
            }
            else {
                Write-OutputColor "  MPIO management cmdlets will be available after reboot." -color "Info"
            }

            # Show post-install status summary
            Show-MPIOStatusSummary

            Write-OutputColor "  A reboot is required to complete the installation." -color "Warning"
            Write-OutputColor "  After rebooting, configure MPIO for your storage via:" -color "Info"
            Write-OutputColor "  - iSCSI Setup > Initialize MPIO for iSCSI" -color "Info"
            $script:RebootNeeded = $true
            Add-SessionChange -Category "System" -Description "Installed MPIO (Multipath I/O)"
            Clear-MenuCache
        }
        else {
            Write-OutputColor "  MPIO installation may not have completed successfully." -color "Error"
            if ($installResult.Error) {
                Write-OutputColor "  Details: $($installResult.Error.Trim())" -color "Error"
            }
            Add-SessionChange -Category "System" -Description "MPIO installation failed"
            Clear-MenuCache
        }
    }
    catch {
        Write-OutputColor "  Failed to install MPIO: $_" -color "Error"
    }
}
#endregion