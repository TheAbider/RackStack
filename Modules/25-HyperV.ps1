#region ===== HYPER-V INSTALLATION =====
# Function to install Hyper-V role
function Install-HyperVRole {
    Clear-Host
    Write-CenteredOutput "Install Hyper-V" -color "Info"

    # Check if already installed using the working function
    if (Test-HyperVInstalled) {
        Write-OutputColor "Hyper-V is already installed." -color "Success"
        return
    }

    # Detect if this is Windows Server or Windows Client
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    $isServer = $osInfo.ProductType -ne 1  # 1 = Workstation, 2 = Domain Controller, 3 = Server

    Write-OutputColor "Hyper-V is not currently installed." -color "Info"
    Write-OutputColor "Operating System: $($osInfo.Caption)" -color "Info"

    # Pre-flight validation
    $preFlightOK = Show-PreFlightCheck -Feature "Hyper-V"
    if (-not $preFlightOK) {
        if (-not (Confirm-UserAction -Message "Continue despite blocking issues?")) {
            Write-OutputColor "Installation cancelled." -color "Info"
            return
        }
    }

    Write-OutputColor "Hyper-V will be installed with management tools." -color "Info"
    Write-OutputColor "A reboot will be required after installation." -color "Warning"

    if (-not (Confirm-UserAction -Message "Install Hyper-V now?")) {
        Write-OutputColor "Hyper-V installation cancelled." -color "Info"
        return
    }

    try {
        Write-OutputColor "`nInstalling Hyper-V... This may take several minutes." -color "Info"

        if ($isServer) {
            # Windows Server - use Install-WindowsFeature
            $installResult = Install-WindowsFeatureWithTimeout -FeatureName "Hyper-V" -DisplayName "Hyper-V" -IncludeManagementTools

            if ($installResult.TimedOut) {
                Add-SessionChange -Category "System" -Description "Hyper-V installation timed out"
                return
            }
            elseif ($installResult.Success) {
                Write-OutputColor "`nHyper-V installed successfully!" -color "Success"
                $global:RebootNeeded = $true
                Add-SessionChange -Category "System" -Description "Installed Hyper-V role"
                Clear-MenuCache
            }
            else {
                Write-OutputColor "Hyper-V installation may not have completed successfully." -color "Error"
                Add-SessionChange -Category "System" -Description "Hyper-V installation failed"
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
                    return
                }
            }
            Write-Host ""  # New line after progress

            $result = Receive-Job $installJob -ErrorAction SilentlyContinue
            $jobError = $installJob.ChildJobs[0].Error
            Remove-Job $installJob -Force -ErrorAction SilentlyContinue

            if ($jobError) {
                Complete-ProgressMessage -Activity "Hyper-V installation" -Status "Failed" -Failed
                Write-OutputColor "Error: $jobError" -color "Error"
                Add-SessionChange -Category "System" -Description "Hyper-V installation failed (Windows Client)"

                # Check for common issues
                if ($jobError -match "0x800F0906\|source files could not be found") {
                    Write-OutputColor "Tip: You may need to enable Windows Features through Settings > Apps > Optional Features" -color "Warning"
                }
                elseif ($jobError -match "0x80070422") {
                    Write-OutputColor "Tip: Windows Update service may need to be running" -color "Warning"
                }
            }
            else {
                Complete-ProgressMessage -Activity "Hyper-V installation" -Status "Complete" -Success
                Write-OutputColor "`nHyper-V installed successfully!" -color "Success"
                Write-OutputColor "A reboot is required to complete the installation." -color "Warning"
                $global:RebootNeeded = $true
                Add-SessionChange -Category "System" -Description "Installed Hyper-V (Windows Client)"
                Clear-MenuCache  # Invalidate cache after change
            }
        }
    }
    catch {
        Write-OutputColor "Failed to install Hyper-V: $_" -color "Error"
    }
}
#endregion