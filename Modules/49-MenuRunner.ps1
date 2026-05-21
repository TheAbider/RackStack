#region ===== MENU RUNNER FUNCTIONS =====
# Function to run the main menu
function Start-Show-Mainmenu {
    while ($true) {
        # Reset the "return to main menu" flag
        $script:ReturnToMainMenu = $false

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
                    "3" {
                        New-ScenarioBatchConfig
                        Write-PressEnter
                    }
                    { $_ -eq "B" -or $_ -eq "b" -or $_ -eq "back" } {
                        # Back to main menu
                    }
                    default {
                        $navResult = Test-NavigationCommand -UserInput $batchChoice
                        if ($navResult.Action -eq "exit") { Exit-Script; return }
                        if ($navResult.Action -eq "home") { $script:ReturnToMainMenu = $true; return }
                        if ($batchChoice) {
                            Write-OutputColor "  Invalid choice. Enter 1, 2, 3, or B." -color "Error"
                            Start-Sleep -Milliseconds 500
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
                Test-ScriptUpdate
            }
            { $_ -eq "V" -or $_ -eq "v" } {
                Show-QuickSessionChanges
                Write-PressEnter
            }
            { $_ -eq "R" -or $_ -eq "r" -or $_ -eq "refresh" } {
                Write-OutputColor "  Refreshing..." -color "Info"
                Clear-MenuCache
                # continue will redisplay the menu with fresh data
            }
            { $_ -eq "help" -or $_ -like "help *" } {
                if ($choice -like "help *") {
                    $helpKeyword = $choice.Substring(5).Trim()
                    Search-HelpTopics -Keyword $helpKeyword
                } else {
                    Show-Help
                }
                Write-PressEnter
            }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-8, [U]pdate, [V]iew, or [R]efresh." -color "Error"
                Start-Sleep -Milliseconds 500
            }
        }
    }
}

# Function to run the Configure Server menu
function Start-Show-ConfigureServerMenu {
    while ($true) {
        if ($script:ReturnToMainMenu) {
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
        if ($navResult.Action -eq "home") {
            $script:ReturnToMainMenu = $true
            return
        }

        switch ($choice) {
            "1" {
                Start-Show-NetworkMenu
                if ($script:ReturnToMainMenu) { return }
            }
            "2" {
                Start-Show-SystemConfigMenu
                if ($script:ReturnToMainMenu) { return }
            }
            "3" {
                Start-Show-RolesFeaturesMenu
                if ($script:ReturnToMainMenu) { return }
            }
            "4" {
                Start-Show-SecurityAccessMenu
                if ($script:ReturnToMainMenu) { return }
            }
            "5" {
                Start-Show-ToolsUtilitiesMenu
                if ($script:ReturnToMainMenu) { return }
            }
            "6" {
                Start-Show-StorageClusteringMenu
                if ($script:ReturnToMainMenu) { return }
            }
            "7" {
                Show-OperationsMenu
                if ($script:ReturnToMainMenu) { return }
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
                Write-OutputColor "  Invalid choice. Enter 1-10, Q, or B to go back." -color "Error"
                Start-Sleep -Milliseconds 500
            }
        }
    }
}

# Function to run the System Configuration submenu
function Start-Show-SystemConfigMenu {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }

        $choice = Show-SystemConfigMenu

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.Action -eq "exit") { Exit-Script; return }
        if ($navResult.Action -eq "back") { return }
        if ($navResult.Action -eq "home") { $script:ReturnToMainMenu = $true; return }

        switch ($choice) {
            "1" { Set-HostName }
            "2" { Join-Domain; Write-PressEnter }
            "3" { Show-ADDSPromotionMenu }
            "4" { Set-ServerTimeZone; Write-PressEnter }
            "5" { Show-WindowsUpdatesMenu }
            "6" { Sync-SystemTime; Write-PressEnter }
            "7" { Register-ServerLicense }
            "8" { Set-ServerPowerPlan; Write-PressEnter }
            "back" { return }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-8 or B." -color "Error"
                Start-Sleep -Milliseconds 500
            }
        }
    }
}

# Function to run the Roles & Features submenu
function Start-Show-RolesFeaturesMenu {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }

        $choice = Show-RolesFeaturesMenu

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.Action -eq "exit") { Exit-Script; return }
        if ($navResult.Action -eq "back") { return }
        if ($navResult.Action -eq "home") { $script:ReturnToMainMenu = $true; return }

        switch ($choice) {
            "1" { Install-HyperVRole; Write-PressEnter }
            "2" { Install-MPIOFeature; Write-PressEnter }
            "3" { Install-FailoverClusteringFeature; Write-PressEnter }
            "4" { Install-Agent }
            "5" { Show-WSUSManagement }
            "back" { return }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-5 or B." -color "Error"
                Start-Sleep -Milliseconds 500
            }
        }
    }
}

# Function to run the Security & Access submenu
function Start-Show-SecurityAccessMenu {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }

        $choice = Show-SecurityAccessMenu

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.Action -eq "exit") { Exit-Script; return }
        if ($navResult.Action -eq "back") { return }
        if ($navResult.Action -eq "home") { $script:ReturnToMainMenu = $true; return }

        switch ($choice) {
            "1" { Enable-RDP; Write-PressEnter }
            "2" { Enable-PowerShellRemoting; Write-PressEnter }
            "3" { Disable-WindowsFirewallDomainPrivate; Write-PressEnter }
            "4" { Set-FirewallRuleTemplates }
            "5" { Show-FirewallRuleSearch }
            "6" { Set-DefenderExclusions }
            "7" { Show-DefenderStatus; Write-PressEnter }
            "8" { Add-LocalAdminAccount }
            "9" { Disable-BuiltInAdminAccount }
            "10" { Show-LocalAccountAudit }
            "11" { New-StrongPassword; Write-PressEnter }
            "back" { return }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-11 or B." -color "Error"
                Start-Sleep -Milliseconds 500
            }
        }
    }
}

# Function to run the Tools & Utilities submenu
function Start-Show-ToolsUtilitiesMenu {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }

        $choice = Show-ToolsUtilitiesMenu

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.Action -eq "exit") { Exit-Script; return }
        if ($navResult.Action -eq "back") { return }
        if ($navResult.Action -eq "home") { $script:ReturnToMainMenu = $true; return }

        switch ($choice) {
            "1" { Set-NTPConfiguration }
            "2" { Start-DiskCleanup }
            "3" { Show-PerformanceDashboard }
            "4" { Show-EventLogViewer }
            "5" { Show-ServiceManager }
            "6" { Show-NetworkDiagnostics }
            "7" { Show-ServerReadiness }
            "8" { Show-RoleTemplateSelector }
            "9" { Set-PagefileConfiguration }
            "10" { Set-SNMPConfiguration }
            "11" { Install-WindowsServerBackup; Write-PressEnter }
            "12" { Show-CertificateMenu }
            "13" { Show-ScheduledTaskManager }
            "14" { Start-SystemDebloat }
            "15" { Show-AzureArcManagement }
            "16" { Show-DefenderEndpointManagement }
            "back" { return }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-16 or B." -color "Error"
                Start-Sleep -Milliseconds 500
            }
        }
    }
}

# Function to run the Storage & Clustering submenu
function Start-Show-StorageClusteringMenu {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }

        $choice = Show-StorageClusteringMenu

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.Action -eq "exit") { Exit-Script; return }
        if ($navResult.Action -eq "back") { return }
        if ($navResult.Action -eq "home") { $script:ReturnToMainMenu = $true; return }

        switch ($choice) {
            "1" { Start-StorageManager }
            "2" { Show-BitLockerManagement }
            "3" { Show-DeduplicationManagement }
            "4" { Show-StorageReplicaManagement }
            "5" { Show-ClusterManagementMenu }
            "6" { Show-HyperVReplicaMenu }
            "back" { return }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-6 or B." -color "Error"
                Start-Sleep -Milliseconds 500
            }
        }
    }
}

# Function to run the network configuration menu
function Start-Show-NetworkMenu {
    while ($true) {
        # Check if we need to return to main menu
        if ($script:ReturnToMainMenu) {
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
        if ($navResult.Action -eq "home") {
            $script:ReturnToMainMenu = $true
            return
        }

        switch ($networkChoice) {
            "1" {
                Start-Show-HostNetworkMenu
                if ($script:ReturnToMainMenu) { return }
            }
            "2" {
                Start-Show-VM-NetworkMenu
                if ($script:ReturnToMainMenu) { return }
            }
            "back" {
                return
            }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-2 or B to go back." -color "Error"
                Start-Sleep -Milliseconds 500
            }
        }
    }
}

# Function to run the host network configuration menu
function Start-Show-HostNetworkMenu {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }
        # Check if a reboot is pending (cached to avoid repeated registry reads in loop)
        $rebootPending = Get-CachedValue -Key "RebootPending" -FetchScript { Test-RebootPending } -CacheSeconds 15
        if ($rebootPending) {
            Clear-Host
            Write-CenteredOutput "Configure Host Network" -color "Info"
            Write-OutputColor "  A reboot is pending. Please reboot the server and rerun the script." -color "Error"
            Write-PressEnter
            return
        }

        # Check if Hyper-V is installed (use same cache key as menu display)
        $hvInstalled = Get-CachedValue -Key "HyperVInstalled" -FetchScript { Test-HyperVInstalled } -CacheSeconds 300
        if (-not $hvInstalled) {
            Clear-Host
            Write-CenteredOutput "Configure Host Network" -color "Info"
            Write-OutputColor "  Hyper-V is not installed." -color "Warning"

            if (Confirm-UserAction -Message "Install Hyper-V now?") {
                $installResult = Install-WindowsFeatureWithTimeout -FeatureName "Hyper-V" -DisplayName "Hyper-V" -IncludeManagementTools
                if ($installResult.Success) {
                    $script:RebootNeeded = $true
                    Add-SessionChange -Category "Roles" -Description "Installed Hyper-V (reboot required)"
                    Clear-MenuCache
                    Write-OutputColor "  A reboot is required." -color "Warning"
                }
                Write-PressEnter
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
        if ($navResult.Action -eq "home") {
            $script:ReturnToMainMenu = $true
            return
        }

        switch ($hostNetworkChoice) {
            "1" {
                Start-Show-VirtualSwitchMenu
                if ($script:ReturnToMainMenu) { return }
            }
            "2" {
                Add-CustomVNIC
                Write-PressEnter
            }
            "3" {
                Start-Show-HostNetworkIPMenu
                if ($script:ReturnToMainMenu) { return }
            }
            "4" {
                Start-StorageSANMenu
                if ($script:ReturnToMainMenu) { return }
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
                $script:ReturnToMainMenu = $true
                return
            }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-6, B, or M." -color "Error"
                Start-Sleep -Milliseconds 500
            }
        }
    }
}

# Function to run the Virtual Switch Management submenu
function Start-Show-VirtualSwitchMenu {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }

        $choice = Show-VirtualSwitchMenu

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.Action -eq "exit") { Exit-Script; return }
        if ($navResult.Action -eq "back") { return }
        if ($navResult.Action -eq "home") { $script:ReturnToMainMenu = $true; return }

        switch ($choice) {
            "1" { New-SwitchEmbeddedTeam -SwitchName $script:SwitchName -ManagementName $script:ManagementName; Write-PressEnter }
            "2" { New-StandardVSwitch -SwitchType "External"; Write-PressEnter }
            "3" { New-StandardVSwitch -SwitchType "Internal"; Write-PressEnter }
            "4" { New-StandardVSwitch -SwitchType "Private"; Write-PressEnter }
            "5" { Show-VirtualSwitches; Write-PressEnter }
            "6" { Remove-VirtualSwitch; Write-PressEnter }
            "back" { return }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-6 or B." -color "Error"
                Start-Sleep -Milliseconds 500
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
        if ($script:ReturnToMainMenu) { return }
        $vmNetworkChoice = Show-Host-IPNetworkMenu -selectedAdapterName $selectedAdapterName

        $navResult = Test-NavigationCommand -UserInput $vmNetworkChoice
        if ($navResult.Action -eq "exit") { Exit-Script; return }
        if ($navResult.Action -eq "back") { return }
        if ($navResult.Action -eq "home") { $script:ReturnToMainMenu = $true; return }

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
                $script:ReturnToMainMenu = $true
                return
            }
            "back" {
                return
            }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-4, B, or M." -color "Error"
                Start-Sleep -Milliseconds 500
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
        if ($script:ReturnToMainMenu) { return }
        $vmNetworkChoice = Show-VM-NetworkMenu -selectedAdapterName $selectedAdapterName

        $navResult = Test-NavigationCommand -UserInput $vmNetworkChoice
        if ($navResult.Action -eq "exit") { Exit-Script; return }
        if ($navResult.Action -eq "back") { return }
        if ($navResult.Action -eq "home") { $script:ReturnToMainMenu = $true; return }

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
                $script:ReturnToMainMenu = $true
                return
            }
            "back" {
                return
            }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-4, B, or M." -color "Error"
                Start-Sleep -Milliseconds 500
            }
        }
    }
}
#endregion