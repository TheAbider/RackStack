#region ===== HYPER-V INSTALLATION =====
# Function to verify Hyper-V installation status
function Test-HyperVInstallation {
    Write-OutputColor "`n  Verifying Hyper-V installation..." -color "Info"

    $checks = @()

    # Check feature installation
    $feature = Get-WindowsFeature -Name Hyper-V -ErrorAction SilentlyContinue
    if ($null -ne $feature -and $feature.Installed) {
        Write-OutputColor "  Hyper-V Role: Installed" -color "Success"
        $checks += $true
    } else {
        Write-RackStackError -Code "RS-4001"
        $checks += $false
    }

    # Check management tools
    $mgmt = Get-WindowsFeature -Name Hyper-V-Tools -ErrorAction SilentlyContinue
    if ($null -ne $mgmt -and $mgmt.Installed) {
        Write-OutputColor "  Management Tools: Installed" -color "Success"
    } else {
        Write-OutputColor "  Management Tools: Not installed" -color "Warning"
    }

    # Check vmms service
    $vmms = Get-Service vmms -ErrorAction SilentlyContinue
    if ($null -ne $vmms) {
        $svcColor = if ($vmms.Status -eq 'Running') { "Success" } else { "Warning" }
        Write-OutputColor "  VMMS Service: $($vmms.Status)" -color $svcColor
    } else {
        Write-OutputColor "  VMMS Service: Not found (reboot may be required)" -color "Warning"
    }

    # Check virtualization support
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -OperationTimeoutSec 8 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $cpu) {
            $virtEnabled = $cpu.VirtualizationFirmwareEnabled
            $color = if ($virtEnabled) { "Success" } else { "Error" }
            Write-OutputColor "  CPU Virtualization: $(if ($virtEnabled) { 'Enabled' } else { 'Disabled in BIOS' })" -color $color
        }
    } catch {
        # Ignore on older systems
    }

    $passed = @($checks | Where-Object { $_ -eq $true }).Count
    $total = @($checks).Count
    Write-OutputColor "`n  Verification: $passed/$total checks passed" -color $(if ($passed -eq $total) { "Success" } else { "Warning" })
}

# Function to install Hyper-V role
function Install-HyperVRole {
    Clear-Host
    Write-CenteredOutput "Install Hyper-V" -color "Info"

    # Check if already installed using the working function
    if (Test-HyperVInstalled) {
        Write-OutputColor "  Hyper-V is already installed." -color "Success"
        return
    }

    # Detect if this is Windows Server or Windows Client
    $osCim = Invoke-WithTimeout -ScriptBlock {
        Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec 8 -ErrorAction SilentlyContinue
    } -TimeoutSeconds 10 -Activity "Detecting OS type"
    $osInfo = if ($osCim.TimedOut) { $null } else { $osCim.Result }
    if (-not $osInfo) {
        Write-OutputColor "  Could not detect OS type via CIM." -color "Error"
        return
    }
    $isServer = $osInfo.ProductType -ne 1  # 1 = Workstation, 2 = Domain Controller, 3 = Server

    Write-OutputColor "  Hyper-V is not currently installed." -color "Info"
    Write-OutputColor "  Operating System: $($osInfo.Caption)" -color "Info"

    # Pre-flight validation
    $preFlightOK = Show-PreFlightCheck -Feature "Hyper-V"
    if (-not $preFlightOK) {
        if (-not (Confirm-UserAction -Message "Continue despite blocking issues?")) {
            Write-OutputColor "  Installation cancelled." -color "Info"
            return
        }
    }

    Write-OutputColor "  Hyper-V will be installed with management tools." -color "Info"
    Write-OutputColor "  A reboot will be required after installation." -color "Warning"

    if (-not (Confirm-UserAction -Message "Install Hyper-V now?")) {
        Write-OutputColor "  Hyper-V installation cancelled." -color "Info"
        return
    }

    try {
        Write-OutputColor "`nInstalling Hyper-V... This may take several minutes." -color "Info"

        if ($isServer) {
            # Windows Server - use Install-WindowsFeature
            $installResult = Install-WindowsFeatureWithTimeout -FeatureName "Hyper-V" -DisplayName "Hyper-V" -IncludeManagementTools

            if ($installResult.TimedOut) {
                Add-SessionChange -Category "System" -Description "Hyper-V installation timed out"
                Clear-MenuCache
                return
            }
            elseif ($installResult.Success) {
                Write-OutputColor "`nHyper-V installed successfully!" -color "Success"
                Test-HyperVInstallation
                $global:RebootNeeded = $true
                Add-SessionChange -Category "System" -Description "Installed Hyper-V role"
                Clear-MenuCache
                # Hint about nested virtualization if running in a VM
                try {
                    $csModel = (Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec 5 -ErrorAction SilentlyContinue).Model
                    if ($csModel -match 'Virtual|Hyper-V|VMware|KVM|QEMU') {
                        Write-OutputColor "" -color "Info"
                        Write-OutputColor "  Tip: This appears to be a virtual machine." -color "Info"
                        Write-OutputColor "  For nested VMs, enable on the host:" -color "Info"
                        Write-OutputColor "  Set-VMProcessor -VMName <ThisVM> -ExposeVirtualizationExtensions `$true" -color "Success"
                    }
                } catch { }
            }
            else {
                Write-OutputColor "  Hyper-V installation may not have completed successfully." -color "Error"
                Add-SessionChange -Category "System" -Description "Hyper-V installation failed"
                Clear-MenuCache
            }
        }
        else {
            # Windows Client (10/11) - use Enable-WindowsOptionalFeature
            $elapsed = 0
            $installJob = Start-Job -ScriptBlock {
                Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart -ErrorAction Stop
            }

            while ($installJob.State -eq "Running") {
                Show-ProgressMessage -Activity "Installing Hyper-V" -Status "Please wait..." -SecondsElapsed $elapsed
                Start-Sleep -Seconds 1
                $elapsed++
                if ($elapsed -gt $script:FeatureInstallTimeoutSeconds) {
                    Stop-Job $installJob -ErrorAction SilentlyContinue
                    Remove-Job $installJob -Force -ErrorAction SilentlyContinue
                    Write-Host ""
                    Complete-ProgressMessage -Activity "Hyper-V installation" -Status "Timed out" -Failed
                    Write-OutputColor "  Installation timed out after 30 minutes." -color "Error"
                    Add-SessionChange -Category "System" -Description "Hyper-V installation timed out (Windows Client)"
                    Clear-MenuCache
                    return
                }
            }
            Write-Host ""  # New line after progress

            $result = Receive-Job $installJob -ErrorAction SilentlyContinue
            $jobFailed = $installJob.State -eq "Failed"
            $jobError = $null
            try {
                if ($installJob.ChildJobs.Count -gt 0) {
                    $jobError = $installJob.ChildJobs[0].Error | Out-String
                    if ($jobError) { $jobError = $jobError.Trim() }
                }
            } catch {
                Write-OutputColor "  Could not extract job error details: $_" -color "Warning"
            }
            if ($jobFailed -and -not $jobError) {
                $jobError = "Job failed without error details. Check Windows Event Log."
            }
            Remove-Job $installJob -Force -ErrorAction SilentlyContinue

            if ($jobError -or $jobFailed) {
                Complete-ProgressMessage -Activity "Hyper-V installation" -Status "Failed" -Failed
                Write-OutputColor "  Error: $jobError" -color "Error"
                Add-SessionChange -Category "System" -Description "Hyper-V installation failed (Windows Client)"
                Clear-MenuCache

                # Check for common issues
                if ($jobError -match '0x800F0906|source files could not be found') {
                    Write-OutputColor "  Tip: You may need to enable Windows Features through Settings > Apps > Optional Features" -color "Warning"
                }
                elseif ($jobError -match "0x80070422") {
                    Write-OutputColor "  Tip: Windows Update service may need to be running" -color "Warning"
                }
            }
            else {
                Complete-ProgressMessage -Activity "Hyper-V installation" -Status "Complete" -Success
                Write-OutputColor "`nHyper-V installed successfully!" -color "Success"
                Test-HyperVInstallation
                Write-OutputColor "  A reboot is required to complete the installation." -color "Warning"
                $global:RebootNeeded = $true
                Add-SessionChange -Category "System" -Description "Installed Hyper-V (Windows Client)"
                Clear-MenuCache  # Invalidate cache after change
            }
        }
    }
    catch {
        Write-OutputColor "  Failed to install Hyper-V: $_" -color "Error"
    }
}
#endregion