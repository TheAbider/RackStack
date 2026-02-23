#region ===== MENU RUNNER FUNCTIONS =====
# Function to run the main menu
function Start-Show-Mainmenu {
    while ($true) {
        # Reset the "return to main menu" flag
        $global:ReturnToMainMenu = $false

        $choice = Show-MainMenu

        # Check for navigation commands
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.Action -eq "exit") {
            Exit-Script
            return
        }

        switch ($choice) {
            "1" {
                Start-Show-ConfigureServerMenu
            }
            "2" {
                Start-VMDeployment
            }
            "3" {
                Save-ConfigurationProfile
                Write-PressEnter
            }
            "4" {
                Import-ConfigurationProfile
                Write-PressEnter
            }
            "5" {
                Export-ServerConfiguration
                Write-PressEnter
            }
            "6" {
                $batchChoice = Show-BatchConfigMenu
                switch ($batchChoice) {
                    "1" {
                        New-BatchConfigTemplate
                        Write-PressEnter
                    }
                    "2" {
                        Export-BatchConfigFromState
                        Write-PressEnter
                    }
                    { $_ -eq "B" -or $_ -eq "b" -or $_ -eq "back" } {
                        # Back to main menu
                    }
                    default {
                        if ($batchChoice) {
                            Write-OutputColor "Invalid choice. Please enter 1, 2, or B." -color "Error"
                            Start-Sleep -Seconds 2
                        }
                    }
                }
            }
            "7" {
                Start-Show-SettingsMenu
            }
            "8" {
                Exit-Script
                return
            }
            "exit" {
                Exit-Script
                return
            }
            "quit" {
                Exit-Script
                return
            }
            { $_ -eq "U" -or $_ -eq "u" } {
                if ($script:UpdateAvailable) {
                    Test-ScriptUpdate
                }
                else {
                    Test-ScriptUpdate
                }
            }
            "help" {
                Show-Help
                Write-PressEnter
            }
            default {
                Write-OutputColor "Invalid choice. Please enter a number between 1 and 8." -color "Error"
                Start-Sleep -Seconds 2
            }
        }
    }
}

# Function to run the Configure Server menu
# Function to run the Configure Server menu (reorganized with submenus)
function Start-Show-ConfigureServerMenu {
    while ($true) {
        if ($global:ReturnToMainMenu) {
            return
        }

        $choice = Show-ConfigureServerMenu

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.Action -eq "exit") {
            Exit-Script
            return
        }
        if ($navResult.Action -eq "back") {
            return
        }

        switch ($choice) {
            "1" {
                Start-Show-NetworkMenu
                if ($global:ReturnToMainMenu) {
                    $global:ReturnToMainMenu = $false
                }
            }
            "2" {
                Start-Show-SystemConfigMenu
                if ($global:ReturnToMainMenu) {
                    $global:ReturnToMainMenu = $false
                }
            }
            "3" {
                Start-Show-RolesFeaturesMenu
                if ($global:ReturnToMainMenu) {
                    $global:ReturnToMainMenu = $false
                }
            }
            "4" {
                Start-Show-SecurityAccessMenu
                if ($global:ReturnToMainMenu) {
                    $global:ReturnToMainMenu = $false
                }
            }
            "5" {
                Start-Show-ToolsUtilitiesMenu
                if ($global:ReturnToMainMenu) {
                    $global:ReturnToMainMenu = $false
                }
            }
            "6" {
                Start-Show-StorageClusteringMenu
                if ($global:ReturnToMainMenu) {
                    $global:ReturnToMainMenu = $false
                }
            }
            "7" {
                Show-OperationsMenu
                if ($global:ReturnToMainMenu) {
                    $global:ReturnToMainMenu = $false
                }
            }
            "8" {
                Show-SystemHealthCheck
                Write-PressEnter
            }
            "9" {
                Test-AllConnectivity
                Write-PressEnter
            }
            "10" {
                Show-PerformanceDashboard
            }
            { $_ -eq "Q" -or $_ -eq "q" } {
                Show-QuickSetupWizard
                Write-PressEnter
            }
            "back" {
                return
            }
            default {
                Write-OutputColor "Invalid choice. Please enter 1-10, Q, or B to go back." -color "Error"
                Start-Sleep -Seconds 2
            }
        }
    }
}

# Function to run the System Configuration submenu
function Start-Show-SystemConfigMenu {
    while ($true) {
        if ($global:ReturnToMainMenu) { return }

        $choice = Show-SystemConfigMenu

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.Action -eq "exit") { Exit-Script; return }
        if ($navResult.Action -eq "back") { return }

        switch ($choice) {
            "1" { Set-HostName; Write-PressEnter }
            "2" { Join-Domain; Write-PressEnter }
            "3" { Show-ADDSPromotionMenu }
            "4" { Set-ServerTimeZone; Write-PressEnter }
            "5" { Install-WindowsUpdates; Write-PressEnter }
            "6" { Register-ServerLicense; Write-PressEnter }
            "7" { Set-ServerPowerPlan; Write-PressEnter }
            "back" { return }
            default {
                Write-OutputColor "Invalid choice. Please enter 1-7 or B." -color "Error"
                Start-Sleep -Seconds 2
            }
        }
    }
}

# Function to run the Roles & Features submenu
function Start-Show-RolesFeaturesMenu {
    while ($true) {
        if ($global:ReturnToMainMenu) { return }

        $choice = Show-RolesFeaturesMenu

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.Action -eq "exit") { Exit-Script; return }
        if ($navResult.Action -eq "back") { return }

        switch ($choice) {
            "1" { Install-HyperVRole; Write-PressEnter }
            "2" { Install-MPIOFeature; Write-PressEnter }
            "3" { Install-FailoverClusteringFeature; Write-PressEnter }
            "4" { Install-KaseyaAgent; Write-PressEnter }
            "back" { return }
            default {
                Write-OutputColor "Invalid choice. Please enter 1-4 or B." -color "Error"
                Start-Sleep -Seconds 2
            }
        }
    }
}

# Function to run the Security & Access submenu
function Start-Show-SecurityAccessMenu {
    while ($true) {
        if ($global:ReturnToMainMenu) { return }

        $choice = Show-SecurityAccessMenu

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.Action -eq "exit") { Exit-Script; return }
        if ($navResult.Action -eq "back") { return }

        switch ($choice) {
            "1" { Enable-RDP; Write-PressEnter }
            "2" { Enable-PowerShellRemoting; Write-PressEnter }
            "3" { Disable-WindowsFirewallDomainPrivate; Write-PressEnter }
            "4" { Set-FirewallRuleTemplates; Write-PressEnter }
            "5" { Set-DefenderExclusions; Write-PressEnter }
            "6" { Add-LocalAdminAccount; Write-PressEnter }
            "7" { Disable-BuiltInAdminAccount; Write-PressEnter }
            "back" { return }
            default {
                Write-OutputColor "Invalid choice. Please enter 1-7 or B." -color "Error"
                Start-Sleep -Seconds 2
            }
        }
    }
}

# Function to run the Tools & Utilities submenu
function Start-Show-ToolsUtilitiesMenu {
    while ($true) {
        if ($global:ReturnToMainMenu) { return }

        $choice = Show-ToolsUtilitiesMenu

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.Action -eq "exit") { Exit-Script; return }
        if ($navResult.Action -eq "back") { return }

        switch ($choice) {
            "1" { Set-NTPConfiguration; Write-PressEnter }
            "2" { Start-DiskCleanup; Write-PressEnter }
            "3" { Show-PerformanceDashboard }
            "4" { Show-EventLogViewer; Write-PressEnter }
            "5" { Show-ServiceManager }
            "6" { Show-NetworkDiagnostics }
            "7" { Show-ServerReadiness; Write-PressEnter }
            "8" { Show-RoleTemplateSelector }
            "9" { Set-PagefileConfiguration }
            "10" { Set-SNMPConfiguration }
            "11" { Install-WindowsServerBackup; Write-PressEnter }
            "12" { Show-CertificateMenu }
            "back" { return }
            default {
                Write-OutputColor "Invalid choice. Please enter 1-12 or B." -color "Error"
                Start-Sleep -Seconds 2
            }
        }
    }
}

# Function to run the Storage & Clustering submenu
function Start-Show-StorageClusteringMenu {
    while ($true) {
        if ($global:ReturnToMainMenu) { return }

        $choice = Show-StorageClusteringMenu

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.Action -eq "exit") { Exit-Script; return }
        if ($navResult.Action -eq "back") { return }

        switch ($choice) {
            "1" { Start-StorageManager }
            "2" { Show-BitLockerManagement; Write-PressEnter }
            "3" { Show-DeduplicationManagement; Write-PressEnter }
            "4" { Show-StorageReplicaManagement; Write-PressEnter }
            "5" { Show-ClusterManagementMenu; Write-PressEnter }
            "6" { Show-HyperVReplicaMenu }
            "back" { return }
            default {
                Write-OutputColor "Invalid choice. Please enter 1-6 or B." -color "Error"
                Start-Sleep -Seconds 2
            }
        }
    }
}

# Function to run the network configuration menu
function Start-Show-NetworkMenu {
    while ($true) {
        # Check if we need to return to main menu
        if ($global:ReturnToMainMenu) {
            return
        }

        $networkChoice = Show-NetworkMenu

        # Check for navigation commands
        $navResult = Test-NavigationCommand -UserInput $networkChoice
        if ($navResult.Action -eq "exit") {
            Exit-Script
            return
        }
        if ($navResult.Action -eq "back") {
            return
        }

        switch ($networkChoice) {
            "1" {
                Start-Show-HostNetworkMenu
                # Check if we need to bubble up to main menu
                if ($global:ReturnToMainMenu) {
                    return
                }
            }
            "2" {
                Start-Show-VM-NetworkMenu
                # Check if we need to bubble up to main menu
                if ($global:ReturnToMainMenu) {
                    return
                }
            }
            "back" {
                return
            }
            default {
                Write-OutputColor "Invalid choice. Please enter 1-2 or B to go back." -color "Error"
                Start-Sleep -Seconds 2
            }
        }
    }
}

# Function to run the host network configuration menu
function Start-Show-HostNetworkMenu {
    while ($true) {
        # Check if a reboot is pending
        if (Test-RebootPending) {
            Clear-Host
            Write-CenteredOutput "Configure Host Network" -color "Info"
            Write-OutputColor "A reboot is pending. Please reboot the server and rerun the script." -color "Error"
            Write-PressEnter
            return
        }

        # Check if Hyper-V is installed
        if (-not (Test-HyperVInstalled)) {
            Clear-Host
            Write-CenteredOutput "Configure Host Network" -color "Info"
            Write-OutputColor "Hyper-V is not installed." -color "Warning"

            if (Confirm-UserAction -Message "Install Hyper-V now?") {
                Write-OutputColor "Installing Hyper-V..." -color "Info"
                try {
                    $result = Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -ErrorAction Stop
                    if ($result.RestartNeeded -eq "Yes") {
                        $global:RebootNeeded = $true
                        Add-SessionChange -Category "Roles" -Description "Installed Hyper-V (reboot required)"
                        Write-OutputColor "Hyper-V installed. A reboot is required." -color "Success"
                        Write-PressEnter
                    } else {
                        Add-SessionChange -Category "Roles" -Description "Installed Hyper-V"
                        Write-OutputColor "Hyper-V installed successfully." -color "Success"
                        Write-PressEnter
                    }
                } catch {
                    Write-OutputColor "Failed to install Hyper-V: $_" -color "Error"
                    Write-PressEnter
                }
                return
            }
            else {
                return
            }
        }

        $hostNetworkChoice = Show-HostNetworkMenu

        # Check for navigation commands
        $navResult = Test-NavigationCommand -UserInput $hostNetworkChoice
        if ($navResult.Action -eq "exit") {
            Exit-Script
            return
        }
        if ($navResult.Action -eq "back") {
            return
        }

        switch ($hostNetworkChoice) {
            "1" {
                New-SwitchEmbeddedTeam -SwitchName $SwitchName -ManagementName $ManagementName
                Write-PressEnter
            }
            "2" {
                Add-CustomVNIC
                Write-PressEnter
            }
            "3" {
                Start-Show-HostNetworkIPMenu
                # Check if we need to bubble up to main menu
                if ($global:ReturnToMainMenu) {
                    return
                }
            }
            "4" {
                Start-StorageSANMenu
                # Check if we need to bubble up to main menu
                if ($global:ReturnToMainMenu) {
                    return
                }
            }
            "5" {
                Rename-NetworkAdapter
                Write-PressEnter
            }
            "6" {
                Disable-AllIPv6
                Write-PressEnter
            }
            "M" {
                # Set flag to return all the way to main menu
                $global:ReturnToMainMenu = $true
                return
            }
            default {
                Write-OutputColor "Invalid choice. Please enter 1-6, B, or M." -color "Error"
                Start-Sleep -Seconds 2
            }
        }
    }
}

# Function to run the host IP network configuration menu
function Start-Show-HostNetworkIPMenu {
    $selectedAdapterName = Select-Host-Network-Adapter

    if ($null -eq $selectedAdapterName) {
        Write-PressEnter
        return
    }

    while ($true) {
        $vmNetworkChoice = Show-Host-IPNetworkMenu -selectedAdapterName $selectedAdapterName

        switch ($vmNetworkChoice) {
            "1" {
                Set-VMIPAddress -selectedAdapterName $selectedAdapterName
                Write-PressEnter
            }
            "2" {
                Set-VMDNSAddress -selectedAdapterName $selectedAdapterName
                Write-PressEnter
            }
            "3" {
                Set-AdapterVLAN -selectedAdapterName $selectedAdapterName
                Write-PressEnter
            }
            "4" {
                $newAdapter = Select-Host-Network-Adapter
                if ($null -ne $newAdapter) {
                    $selectedAdapterName = $newAdapter
                }
            }
            "M" {
                # Set flag to return all the way to main menu
                $global:ReturnToMainMenu = $true
                return
            }
            "back" {
                return
            }
            default {
                Write-OutputColor "Invalid choice. Please enter 1-4, B, or M." -color "Error"
                Start-Sleep -Seconds 2
            }
        }
    }
}

# Function to run the VM network configuration menu
function Start-Show-VM-NetworkMenu {
    $selectedAdapterName = Select-VM-Network-Adapter

    if ($null -eq $selectedAdapterName) {
        Write-PressEnter
        return
    }

    while ($true) {
        $vmNetworkChoice = Show-VM-NetworkMenu -selectedAdapterName $selectedAdapterName

        switch ($vmNetworkChoice) {
            "1" {
                Set-VMIPAddress -selectedAdapterName $selectedAdapterName
                Write-PressEnter
            }
            "2" {
                Set-VMDNSAddress -selectedAdapterName $selectedAdapterName
                Write-PressEnter
            }
            "3" {
                Disable-AllIPv6
                Write-PressEnter
            }
            "4" {
                $newAdapter = Select-VM-Network-Adapter
                if ($null -ne $newAdapter) {
                    $selectedAdapterName = $newAdapter
                }
            }
            "M" {
                # Set flag to return all the way to main menu
                $global:ReturnToMainMenu = $true
                return
            }
            "back" {
                return
            }
            default {
                Write-OutputColor "Invalid choice. Please enter 1-4, B, or M." -color "Error"
                Start-Sleep -Seconds 2
            }
        }
    }
}
#endregion