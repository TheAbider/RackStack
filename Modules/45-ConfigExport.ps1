#region ===== CONFIGURATION EXPORT =====
function Export-ServerConfiguration {
    Clear-Host
    Write-CenteredOutput "Export Configuration" -color "Info"

    Write-OutputColor "This will export the current server configuration to a text file." -color "Info"
    Write-OutputColor "" -color "Info"

    # Default filename
    $hostname = $env:COMPUTERNAME
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $defaultPath = "$env:USERPROFILE\Desktop\${hostname}_Config_$timestamp.txt"

    Write-OutputColor "Default export path: $defaultPath" -color "Info"

    if (Confirm-UserAction -Message "Use default path?" -DefaultYes) {
        $exportPath = $defaultPath
    }
    else {
        Write-OutputColor "Enter export path (full path with filename):" -color "Info"
        $exportPath = Read-Host
        if ([string]::IsNullOrWhiteSpace($exportPath)) {
            $exportPath = $defaultPath
        }
    }

    Write-OutputColor "`nGathering configuration..." -color "Info"

    try {
        $config = @()
        $config += "=" * 80
        $config += "SERVER CONFIGURATION EXPORT"
        $config += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $config += "Script Version: $($script:ScriptVersion)"
        $config += "=" * 80
        $config += ""

        # System Info
        $config += "### SYSTEM INFORMATION ###"
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $proc = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
        $config += "Hostname:       $($computerSystem.Name)"
        $config += "Domain:         $($computerSystem.Domain)"
        $config += "Part of Domain: $($computerSystem.PartOfDomain)"
        $config += "OS:             $($os.Caption)"
        $config += "OS Build:       $($os.BuildNumber)"
        $config += "Timezone:       $((Get-TimeZone).DisplayName)"
        $config += "CPU:            $($proc.Name)"
        $config += "CPU Cores:      $($proc.NumberOfCores) cores / $($proc.NumberOfLogicalProcessors) logical"
        $config += "Total RAM:      $([math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 1)) GB"
        $config += ""

        # Licensing
        $config += "### LICENSING ###"
        try {
            $licenseInfo = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationId='$($script:WindowsLicensingAppId)' AND LicenseStatus=1" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($licenseInfo) {
                $config += "License Status: Activated"
                $config += "Product Name:   $($licenseInfo.Name)"
                $config += "Description:    $($licenseInfo.Description)"
            } else {
                $config += "License Status: Not Activated"
            }
        }
        catch {
            $config += "License Status: Unable to determine"
        }
        $config += ""

        # Power Plan
        $config += "### POWER PLAN ###"
        $currentPlan = Get-CurrentPowerPlan
        $config += "Active Plan: $($currentPlan.Name)"
        $config += ""

        # Network Configuration
        $config += "### NETWORK CONFIGURATION ###"
        $adapters = Get-NetAdapter -ErrorAction Stop
        # Batch all network queries upfront (avoids N+1 query pattern per adapter)
        $allIPv4 = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $allDNS = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $allGateways = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
        $allBindings = Get-NetAdapterBinding -ComponentId 'ms_tcpip6' -ErrorAction SilentlyContinue

        foreach ($adapter in $adapters) {
            $config += ""
            $config += "Adapter: $($adapter.Name)"
            $config += "  Description:  $($adapter.InterfaceDescription)"
            $config += "  Status:       $($adapter.Status)"
            $config += "  Link Speed:   $($adapter.LinkSpeed)"
            $config += "  MAC Address:  $($adapter.MacAddress)"

            $ipConfig = $allIPv4 | Where-Object { $_.InterfaceAlias -eq $adapter.Name }
            if ($ipConfig) {
                $config += "  IPv4 Address: $($ipConfig.IPAddress)/$($ipConfig.PrefixLength)"
            }

            $dns = $allDNS | Where-Object { $_.InterfaceAlias -eq $adapter.Name }
            if ($dns -and $dns.ServerAddresses) {
                $config += "  DNS Servers:  $($dns.ServerAddresses -join ', ')"
            }

            $gateway = $allGateways | Where-Object { $_.InterfaceAlias -eq $adapter.Name }
            if ($gateway) {
                $config += "  Gateway:      $($gateway.NextHop)"
            }

            # VLAN info
            $vlan = Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword "VlanID" -ErrorAction SilentlyContinue
            if ($vlan -and $vlan.RegistryValue -and $vlan.RegistryValue[0] -ne "0") {
                $config += "  VLAN ID:      $($vlan.RegistryValue[0])"
            }

            # IPv6 status
            $ipv6Binding = $allBindings | Where-Object { $_.Name -eq $adapter.Name }
            if ($ipv6Binding) {
                $config += "  IPv6:         $(if ($ipv6Binding.Enabled) { 'Enabled' } else { 'Disabled' })"
            }
        }
        $config += ""

        # Remote Access
        $config += "### REMOTE ACCESS ###"
        $config += "RDP Status:    $(Get-RDPState)"
        $config += "WinRM Status:  $(Get-WinRMState)"
        $config += ""

        # Firewall Status
        $config += "### FIREWALL STATUS ###"
        $fwState = Get-FirewallState
        $config += "Domain Profile:  $($fwState.Domain)"
        $config += "Private Profile: $($fwState.Private)"
        $config += "Public Profile:  $($fwState.Public)"
        $config += ""

        # MPIO
        $config += "### MPIO (MULTIPATH I/O) ###"
        if (Test-MPIOInstalled) {
            $config += "MPIO: Installed"
            $mpioDevices = Get-MSDSMSupportedHW -ErrorAction SilentlyContinue
            if ($mpioDevices) {
                $config += "  Supported Hardware:"
                foreach ($dev in $mpioDevices) {
                    $config += "    $($dev.VendorId.Trim()) - $($dev.ProductId.Trim())"
                }
            }
        } else {
            $config += "MPIO: Not Installed"
        }
        $config += ""

        # Failover Clustering
        $config += "### FAILOVER CLUSTERING ###"
        if (Test-FailoverClusteringInstalled) {
            $config += "Failover Clustering: Installed"
            $cluster = Get-Cluster -ErrorAction SilentlyContinue
            if ($cluster) {
                $config += "  Cluster Name: $($cluster.Name)"
                $nodes = Get-ClusterNode -ErrorAction SilentlyContinue
                if ($nodes) {
                    $config += "  Nodes:"
                    foreach ($node in $nodes) {
                        $config += "    $($node.Name) | State: $($node.State)"
                    }
                }
            } else {
                $config += "  Not a member of any cluster"
            }
        } else {
            $config += "Failover Clustering: Not Installed"
        }
        $config += ""

        # Local Administrators
        $config += "### LOCAL ADMINISTRATORS ###"
        $admins = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue
        foreach ($admin in $admins) {
            $config += "  $($admin.Name) ($($admin.ObjectClass))"
        }
        $builtInAdmin = Get-LocalUser -Name "Administrator" -ErrorAction SilentlyContinue
        if ($builtInAdmin) {
            $config += "  Built-in Administrator: $(if ($builtInAdmin.Enabled) { 'Enabled' } else { 'Disabled' })"
        }
        $config += ""

        # Storage
        $config += "### STORAGE ###"
        $disks = Get-Disk -ErrorAction SilentlyContinue
        foreach ($disk in $disks) {
            $sizeDisplay = if ($disk.Size -ge 1TB) { "$([math]::Round($disk.Size / 1TB, 2)) TB" } else { "$([math]::Round($disk.Size / 1GB, 1)) GB" }
            $config += "  Disk $($disk.Number): $($disk.FriendlyName) | $sizeDisplay | $($disk.PartitionStyle) | $($disk.OperationalStatus)"
        }
        $config += ""
        $volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | Sort-Object DriveLetter -ErrorAction SilentlyContinue
        foreach ($vol in $volumes) {
            $totalGB = [math]::Round($vol.Size / 1GB, 1)
            $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 1)
            $usedPct = if ($vol.Size -gt 0) { [math]::Round((($vol.Size - $vol.SizeRemaining) / $vol.Size) * 100, 0) } else { 0 }
            $label = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { "(No Label)" }
            $config += "  $($vol.DriveLetter): $label | $($vol.FileSystem) | $freeGB GB free / $totalGB GB ($usedPct% used)"
        }
        $config += ""

        # Hyper-V Info
        $config += "### HYPER-V STATUS ###"
        if (Test-HyperVInstalled) {
            $config += "Hyper-V: Installed"

            $vmSwitches = Get-VMSwitch -ErrorAction SilentlyContinue
            if ($vmSwitches) {
                $config += ""
                $config += "  Virtual Switches:"
                foreach ($sw in $vmSwitches) {
                    $teamMembers = ""
                    if ($sw.EmbeddedTeamingEnabled) {
                        $teamNics = (Get-VMSwitchTeam -Name $sw.Name -ErrorAction SilentlyContinue).NetAdapterInterfaceDescription -join ", "
                        if ($teamNics) { $teamMembers = " | Team: $teamNics" }
                    }
                    $config += "    $($sw.Name) (Type: $($sw.SwitchType))$teamMembers"
                }
            }

            $vms = Get-VM -ErrorAction SilentlyContinue
            if ($vms) {
                $config += ""
                $config += "  Virtual Machines: $($vms.Count) total"
                foreach ($vm in $vms | Sort-Object Name) {
                    $memGB = [math]::Round($vm.MemoryAssigned / 1GB, 1)
                    $config += "    $($vm.Name) | State: $($vm.State) | CPU: $($vm.ProcessorCount) | RAM: ${memGB}GB"
                }
            }
            else {
                $config += "  Virtual Machines: None"
            }
        }
        else {
            $config += "Hyper-V: Not Installed"
        }
        $config += ""

        # Session changes
        if ($script:SessionChanges.Count -gt 0) {
            $config += "### CHANGES THIS SESSION ###"
            foreach ($change in $script:SessionChanges) {
                $config += "  [$($change.Timestamp)] [$($change.Category)] $($change.Description)"
            }
            $config += ""
        }

        $config += "=" * 80
        $config += "END OF CONFIGURATION EXPORT"
        $config += "=" * 80

        # Write to file
        $config | Out-File -FilePath $exportPath -Encoding UTF8 -Force

        Write-OutputColor "`nConfiguration exported successfully!" -color "Success"
        Write-OutputColor "File: $exportPath" -color "Info"
        Add-SessionChange -Category "Export" -Description "Exported configuration to $exportPath"
    }
    catch {
        Write-OutputColor "Failed to export configuration: $_" -color "Error"
    }
}

# Function to save configuration profile as JSON for cloning to other servers
function Save-ConfigurationProfile {
    Clear-Host
    Write-CenteredOutput "Save Configuration Profile" -color "Info"

    Write-OutputColor "This will save the current server's configuration as a JSON profile" -color "Info"
    Write-OutputColor "that can be loaded onto other servers to clone settings." -color "Info"
    Write-OutputColor "" -color "Info"

    # Gather current configuration
    Write-OutputColor "Gathering current configuration..." -color "Info"

    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    $timezone = Get-TimeZone
    $powerPlan = Get-CurrentPowerPlan

    # Get primary adapter info
    $primaryAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    $primaryIP = $null
    $primaryDNS = $null

    if ($primaryAdapter) {
        $primaryIP = Get-NetIPAddress -InterfaceAlias $primaryAdapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.PrefixOrigin -ne "WellKnown" } | Select-Object -First 1
        $primaryDNS = Get-DnsClientServerAddress -InterfaceAlias $primaryAdapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue
    }

    $configProfile = [ordered]@{
        "_ProfileInfo" = [ordered]@{
            "CreatedFrom" = $env:COMPUTERNAME
            "CreatedAt" = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            "ScriptVersion" = $script:ScriptVersion
            "Description" = "Configuration profile - edit Hostname, IPAddress, and Gateway before applying to a new server"
        }
        "Hostname" = $null  # Intentionally null - user should set for new server
        "_Hostname_Help" = "Set to the new server's hostname (max 15 chars, e.g., 123456-FS1)"
        "Network" = [ordered]@{
            "AdapterName" = if ($primaryAdapter) { $primaryAdapter.Name } else { "Ethernet" }
            "IPAddress" = $null  # Intentionally null - user should set for new server
            "SubnetCIDR" = if ($primaryIP) { $primaryIP.PrefixLength } else { 24 }
            "Gateway" = $null  # Intentionally null - user should set for new server
            "DNS1" = if ($primaryDNS -and $primaryDNS.ServerAddresses.Count -ge 1) { $primaryDNS.ServerAddresses[0] } else { $script:DNSPresets["Google DNS"][0] }
            "DNS2" = if ($primaryDNS -and $primaryDNS.ServerAddresses.Count -ge 2) { $primaryDNS.ServerAddresses[1] } else { $script:DNSPresets["Google DNS"][1] }
        }
        "Domain" = [ordered]@{
            "JoinDomain" = $computerSystem.PartOfDomain
            "DomainName" = if ($computerSystem.PartOfDomain) { $computerSystem.Domain } else { $script:Domain }
            "_Note" = "Domain join will prompt for credentials when applied"
        }
        "Timezone" = $timezone.Id
        "RDP" = [ordered]@{
            "Enable" = ((Get-RDPState) -eq "Enabled")
        }
        "WinRM" = [ordered]@{
            "Enable" = ((Get-WinRMState) -eq "Enabled")
            "_Note" = "PowerShell Remoting with Kerberos authentication"
        }
        "Firewall" = [ordered]@{
            "ConfigureRecommended" = $true
            "_Note" = "Recommended: Domain=Disabled, Private=Disabled, Public=Enabled"
        }
        "PowerPlan" = $powerPlan.Name
        "InstallHyperV" = [ordered]@{
            "Install" = (Test-HyperVInstalled)
            "_Note" = "Set to true to install Hyper-V role. Requires reboot."
        }
        "InstallMPIO" = [ordered]@{
            "Install" = (Test-MPIOInstalled)
            "_Note" = "Set to true to install MPIO (Multipath I/O). Requires reboot."
        }
        "InstallFailoverClustering" = [ordered]@{
            "Install" = (Test-FailoverClusteringInstalled)
            "_Note" = "Set to true to install Failover Clustering. Requires reboot."
        }
        "LocalAdmin" = [ordered]@{
            "CreateAccount" = $false
            "AccountName" = $script:LocalAdminAccountName
            "FullName" = $script:FullName
            "_Note" = "Set CreateAccount to true - will prompt for password when applying"
        }
        "BuiltInAdmin" = [ordered]@{
            "Disable" = $false
            "_Note" = "Only disable after confirming other admin access works"
        }
        "InstallUpdates" = [ordered]@{
            "Install" = $false
            "_Note" = "Set to true to install Windows Updates (can take 10-60+ min)"
        }
    }

    # Default path
    $hostname = $env:COMPUTERNAME
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $defaultPath = "$env:USERPROFILE\Desktop\${hostname}_Profile_$timestamp.json"

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Default save location: $defaultPath" -color "Info"

    if (Confirm-UserAction -Message "Use default path?" -DefaultYes) {
        $savePath = $defaultPath
    }
    else {
        Write-OutputColor "Enter save path (full path with filename):" -color "Info"
        $savePath = Read-Host
        if ([string]::IsNullOrWhiteSpace($savePath)) {
            $savePath = $defaultPath
        }
    }

    try {
        $configProfile | ConvertTo-Json -Depth 10 | Out-File -FilePath $savePath -Encoding UTF8 -Force

        Write-OutputColor "" -color "Info"
        Write-OutputColor "Configuration profile saved successfully!" -color "Success"
        Write-OutputColor "File: $savePath" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "To use this profile on another server:" -color "Info"
        Write-OutputColor "  1. Copy the JSON file to the new server" -color "Success"
        Write-OutputColor "  2. Edit the file: set Hostname, IPAddress, Gateway" -color "Success"
        Write-OutputColor "  3. Run this script and choose 'Load Configuration Profile'" -color "Success"
        Write-OutputColor "  4. Review the settings preview, then confirm to apply" -color "Success"

        Add-SessionChange -Category "Export" -Description "Saved configuration profile to $savePath"
    }
    catch {
        Write-OutputColor "Failed to save profile: $_" -color "Error"
    }
}

# Function to load and apply configuration profile from JSON
function Import-ConfigurationProfile {
    Clear-Host
    Write-CenteredOutput "Load Configuration Profile" -color "Info"

    Write-OutputColor "This will apply settings from a previously saved configuration profile." -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "Enter the path to the profile JSON file:" -color "Info"
    $profilePath = Read-Host

    # Check for navigation
    $navResult = Test-NavigationCommand -UserInput $profilePath
    if ($navResult.ShouldReturn) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        Write-OutputColor "No path entered." -color "Warning"
        return
    }

    if (-not (Test-Path $profilePath)) {
        Write-OutputColor "File not found: $profilePath" -color "Error"
        return
    }

    try {
        $configProfile = Get-Content $profilePath -Raw | ConvertFrom-Json

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │  PROFILE INFO                                                        │" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        $piSource = if ($configProfile._ProfileInfo.CreatedFrom) { $configProfile._ProfileInfo.CreatedFrom } else { "Unknown" }
        $piCreated = if ($configProfile._ProfileInfo.CreatedAt) { $configProfile._ProfileInfo.CreatedAt } else { "Unknown" }
        $piVersion = if ($configProfile._ProfileInfo.ScriptVersion) { $configProfile._ProfileInfo.ScriptVersion } else { "Unknown" }
        Write-OutputColor "  │  Source:   $($piSource.PadRight(60))│" -color "Info"
        Write-OutputColor "  │  Created:  $($piCreated.PadRight(60))│" -color "Info"
        Write-OutputColor "  │  Version:  $($piVersion.PadRight(60))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │  SETTINGS TO APPLY                                                   │" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        # Hostname
        if ($configProfile.Hostname) {
            Write-MenuItem -Text "Hostname:     $($configProfile.Hostname)"
        } else {
            Write-MenuItem -Text "Hostname:     (not set - will skip)" -Color "Warning"
        }

        # Network
        if ($configProfile.Network.IPAddress -and $configProfile.Network.Gateway) {
            Write-MenuItem -Text "IP Address:   $($configProfile.Network.IPAddress)/$($configProfile.Network.SubnetCIDR)"
            Write-MenuItem -Text "Gateway:      $($configProfile.Network.Gateway)"
            Write-MenuItem -Text "Adapter:      $($configProfile.Network.AdapterName)"
        } else {
            Write-MenuItem -Text "Network:      (IP/Gateway not set - will skip)" -Color "Warning"
        }
        Write-MenuItem -Text "DNS:          $($configProfile.Network.DNS1), $($configProfile.Network.DNS2)"

        # System
        Write-MenuItem -Text "Timezone:     $($configProfile.Timezone)"
        Write-MenuItem -Text "Power Plan:   $($configProfile.PowerPlan)"

        # Remote Access
        $rdpAction = if ($configProfile.RDP.Enable) { "Enable" } else { "Skip" }
        Write-MenuItem -Text "RDP:          $rdpAction"

        $winrmAction = if ($configProfile.WinRM -and $configProfile.WinRM.Enable) { "Enable" } else { "Skip" }
        Write-MenuItem -Text "WinRM:        $winrmAction"

        # Firewall
        $fwAction = if ($configProfile.Firewall.ConfigureRecommended) { "Configure (D:Off Pr:Off Pu:On)" } else { "Skip" }
        Write-MenuItem -Text "Firewall:     $fwAction"

        # Hyper-V
        if ($configProfile.InstallHyperV -and $configProfile.InstallHyperV.Install) {
            Write-MenuItem -Text "Hyper-V:      Install (reboot required)" -Color "Warning"
        }

        # MPIO
        if ($configProfile.InstallMPIO -and $configProfile.InstallMPIO.Install) {
            Write-MenuItem -Text "MPIO:         Install (reboot required)" -Color "Warning"
        }

        # Failover Clustering
        if ($configProfile.InstallFailoverClustering -and $configProfile.InstallFailoverClustering.Install) {
            Write-MenuItem -Text "Clustering:   Install (reboot required)" -Color "Warning"
        }

        # Local Admin
        if ($configProfile.LocalAdmin -and $configProfile.LocalAdmin.CreateAccount) {
            $adminName = if ($configProfile.LocalAdmin.AccountName) { $configProfile.LocalAdmin.AccountName } else { $localadminaccountname }
            Write-MenuItem -Text "Local Admin:  Create '$adminName' (will prompt for pwd)"
        }

        # Disable Built-in Admin
        if ($configProfile.BuiltInAdmin -and $configProfile.BuiltInAdmin.Disable) {
            Write-MenuItem -Text "Built-in Admin: Disable" -Color "Warning"
        }

        # Domain
        if ($configProfile.Domain.JoinDomain) {
            Write-MenuItem -Text "Domain:       $($configProfile.Domain.DomainName) (will prompt for creds)"
        }

        # Updates
        if ($configProfile.InstallUpdates -and $configProfile.InstallUpdates.Install) {
            Write-MenuItem -Text "Updates:      Install (may take 10-60+ min)" -Color "Warning"
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        if (-not (Confirm-UserAction -Message "Apply these settings?")) {
            Write-OutputColor "Profile import cancelled." -color "Info"
            return
        }

        $changesApplied = 0
        $errors = 0

        Write-OutputColor "" -color "Info"

        # Apply hostname
        if ($configProfile.Hostname -and $configProfile.Hostname -ne $env:COMPUTERNAME) {
            Write-OutputColor "  [1/13] Setting hostname to '$($configProfile.Hostname)'..." -color "Info"
            try {
                if (Test-ValidHostname -Hostname $configProfile.Hostname) {
                    Rename-Computer -NewName $configProfile.Hostname -Force -ErrorAction Stop
                    $global:RebootNeeded = $true
                    $changesApplied++
                    Write-OutputColor "        Hostname set. Reboot required." -color "Success"
                    Add-SessionChange -Category "System" -Description "Set hostname to $($configProfile.Hostname)"
                } else {
                    Write-OutputColor "        Invalid hostname format: $($configProfile.Hostname)" -color "Error"
                    $errors++
                }
            }
            catch {
                Write-OutputColor "        Failed: $_" -color "Error"
                $errors++
            }
        } else {
            Write-OutputColor "  [1/13] Hostname: skipped" -color "Debug"
        }

        # Apply network settings
        if ($configProfile.Network.IPAddress -and $configProfile.Network.Gateway) {
            Write-OutputColor "  [2/13] Configuring network..." -color "Info"
            try {
                $adapterName = $configProfile.Network.AdapterName
                Remove-NetIPAddress -InterfaceAlias $adapterName -Confirm:$false -ErrorAction SilentlyContinue
                Remove-NetRoute -InterfaceAlias $adapterName -Confirm:$false -ErrorAction SilentlyContinue

                New-NetIPAddress -InterfaceAlias $adapterName -IPAddress $configProfile.Network.IPAddress `
                    -PrefixLength $configProfile.Network.SubnetCIDR -DefaultGateway $configProfile.Network.Gateway -ErrorAction Stop

                $dnsServers = @($configProfile.Network.DNS1)
                if ($configProfile.Network.DNS2) { $dnsServers += $configProfile.Network.DNS2 }
                Set-DnsClientServerAddress -InterfaceAlias $adapterName -ServerAddresses $dnsServers -ErrorAction Stop

                $changesApplied++
                Write-OutputColor "        Network configured." -color "Success"
                Add-SessionChange -Category "Network" -Description "Set IP $($configProfile.Network.IPAddress)/$($configProfile.Network.SubnetCIDR) on $adapterName"
            }
            catch {
                Write-OutputColor "        Failed: $_" -color "Error"
                $errors++
            }
        } else {
            Write-OutputColor "  [2/13] Network: skipped (IP/Gateway not set)" -color "Debug"
        }

        # Apply timezone
        if ($configProfile.Timezone) {
            Write-OutputColor "  [3/13] Setting timezone to '$($configProfile.Timezone)'..." -color "Info"
            try {
                Set-TimeZone -Id $configProfile.Timezone -ErrorAction Stop
                $changesApplied++
                Write-OutputColor "        Timezone set." -color "Success"
                Add-SessionChange -Category "System" -Description "Set timezone to $($configProfile.Timezone)"
            }
            catch {
                Write-OutputColor "        Failed: $_" -color "Error"
                $errors++
            }
        } else {
            Write-OutputColor "  [3/13] Timezone: skipped" -color "Debug"
        }

        # Enable RDP
        if ($configProfile.RDP.Enable) {
            Write-OutputColor "  [4/13] Enabling Remote Desktop..." -color "Info"
            try {
                Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -ErrorAction Stop
                Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
                $changesApplied++
                Write-OutputColor "        RDP enabled." -color "Success"
                Add-SessionChange -Category "System" -Description "Enabled RDP"
                Clear-MenuCache
            }
            catch {
                Write-OutputColor "        Failed: $_" -color "Error"
                $errors++
            }
        } else {
            Write-OutputColor "  [4/13] RDP: skipped" -color "Debug"
        }

        # Enable WinRM
        if ($configProfile.WinRM -and $configProfile.WinRM.Enable) {
            Write-OutputColor "  [5/13] Enabling PowerShell Remoting..." -color "Info"
            try {
                Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction Stop
                Set-Item WSMan:\localhost\Service\Auth\Kerberos -Value $true -ErrorAction SilentlyContinue
                $changesApplied++
                Write-OutputColor "        WinRM enabled." -color "Success"
                Add-SessionChange -Category "System" -Description "Enabled PowerShell Remoting"
                Clear-MenuCache
            }
            catch {
                Write-OutputColor "        Failed: $_" -color "Error"
                $errors++
            }
        } else {
            Write-OutputColor "  [5/13] WinRM: skipped" -color "Debug"
        }

        # Configure firewall
        if ($configProfile.Firewall.ConfigureRecommended) {
            Write-OutputColor "  [6/13] Configuring firewall..." -color "Info"
            try {
                Set-NetFirewallProfile -Profile Domain -Enabled False -ErrorAction Stop
                Set-NetFirewallProfile -Profile Private -Enabled False -ErrorAction Stop
                Set-NetFirewallProfile -Profile Public -Enabled True -ErrorAction Stop
                $changesApplied++
                Write-OutputColor "        Firewall configured (Domain:Off Private:Off Public:On)." -color "Success"
                Add-SessionChange -Category "Security" -Description "Configured firewall profiles"
                Clear-MenuCache
            }
            catch {
                Write-OutputColor "        Failed: $_" -color "Error"
                $errors++
            }
        } else {
            Write-OutputColor "  [6/13] Firewall: skipped" -color "Debug"
        }

        # Set power plan
        if ($configProfile.PowerPlan) {
            Write-OutputColor "  [7/13] Setting power plan to '$($configProfile.PowerPlan)'..." -color "Info"
            if ($script:PowerPlanGUID.ContainsKey($configProfile.PowerPlan)) {
                powercfg /setactive $script:PowerPlanGUID[$configProfile.PowerPlan] 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Write-OutputColor "        Failed to set power plan (exit code $LASTEXITCODE)." -color "Warning"
                } else {
                    $changesApplied++
                    Write-OutputColor "        Power plan set." -color "Success"
                    Add-SessionChange -Category "System" -Description "Set power plan to $($configProfile.PowerPlan)"
                }
                Clear-MenuCache
            } else {
                Write-OutputColor "        Unknown power plan: $($configProfile.PowerPlan)" -color "Warning"
            }
        } else {
            Write-OutputColor "  [7/13] Power plan: skipped" -color "Debug"
        }

        # Install Hyper-V
        if ($configProfile.InstallHyperV -and $configProfile.InstallHyperV.Install -and -not (Test-HyperVInstalled)) {
            Write-OutputColor "  [8/13] Installing Hyper-V..." -color "Info"
            try {
                Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -ErrorAction Stop
                $global:RebootNeeded = $true
                $changesApplied++
                Write-OutputColor "        Hyper-V installed. Reboot required." -color "Success"
                Add-SessionChange -Category "System" -Description "Installed Hyper-V"
                Clear-MenuCache
            }
            catch {
                Write-OutputColor "        Failed: $_" -color "Error"
                $errors++
            }
        } else {
            $hvMsg = if (Test-HyperVInstalled) { "already installed" } else { "not requested" }
            Write-OutputColor "  [8/13] Hyper-V: skipped ($hvMsg)" -color "Debug"
        }

        # Install MPIO
        if ($configProfile.InstallMPIO -and $configProfile.InstallMPIO.Install -and -not (Test-MPIOInstalled)) {
            Write-OutputColor "  [9/13] Installing MPIO..." -color "Info"
            try {
                Install-WindowsFeature -Name Multipath-IO -ErrorAction Stop
                $global:RebootNeeded = $true
                $changesApplied++
                Write-OutputColor "         MPIO installed. Reboot required." -color "Success"
                Add-SessionChange -Category "System" -Description "Installed MPIO"
                Clear-MenuCache
            }
            catch {
                Write-OutputColor "         Failed: $_" -color "Error"
                $errors++
            }
        } else {
            $mpioMsg = if (Test-MPIOInstalled) { "already installed" } else { "not requested" }
            Write-OutputColor "  [9/13] MPIO: skipped ($mpioMsg)" -color "Debug"
        }

        # Install Failover Clustering
        if ($configProfile.InstallFailoverClustering -and $configProfile.InstallFailoverClustering.Install -and -not (Test-FailoverClusteringInstalled)) {
            Write-OutputColor "  [10/13] Installing Failover Clustering..." -color "Info"
            try {
                Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools -ErrorAction Stop
                $global:RebootNeeded = $true
                $changesApplied++
                Write-OutputColor "          Failover Clustering installed. Reboot required." -color "Success"
                Add-SessionChange -Category "System" -Description "Installed Failover Clustering"
                Clear-MenuCache
            }
            catch {
                Write-OutputColor "          Failed: $_" -color "Error"
                $errors++
            }
        } else {
            $clusterMsg = if (Test-FailoverClusteringInstalled) { "already installed" } else { "not requested" }
            Write-OutputColor "  [10/13] Failover Clustering: skipped ($clusterMsg)" -color "Debug"
        }

        # Create local admin account
        if ($configProfile.LocalAdmin -and $configProfile.LocalAdmin.CreateAccount) {
            $adminName = if ($configProfile.LocalAdmin.AccountName) { $configProfile.LocalAdmin.AccountName } else { $localadminaccountname }
            Write-OutputColor "  [11/13] Creating local admin '$adminName'..." -color "Info"
            try {
                $existingUser = Get-LocalUser -Name $adminName -ErrorAction SilentlyContinue
                if ($existingUser) {
                    Write-OutputColor "        Account '$adminName' already exists." -color "Warning"
                } else {
                    Write-OutputColor "        Enter password for $adminName" -color "Info"
                    $securePassword = Read-Host -Prompt "        Password" -AsSecureString
                    $fullName = if ($configProfile.LocalAdmin.FullName) { $configProfile.LocalAdmin.FullName } else { $adminName }
                    New-LocalUser -Name $adminName -Password $securePassword -FullName $fullName -Description "Local Admin" -PasswordNeverExpires -ErrorAction Stop | Out-Null
                    Add-LocalGroupMember -Group "Administrators" -Member $adminName -ErrorAction Stop
                    Write-OutputColor "        Local admin '$adminName' created." -color "Success"
                    $changesApplied++
                    Add-SessionChange -Category "Security" -Description "Created local admin account '$adminName'"
                }
            }
            catch {
                Write-OutputColor "        Failed: $_" -color "Error"
                $errors++
            }
        } else {
            Write-OutputColor "  [11/13] Local admin: skipped" -color "Debug"
        }

        # Disable built-in Administrator
        if ($configProfile.BuiltInAdmin -and $configProfile.BuiltInAdmin.Disable) {
            Write-OutputColor "  [12/13] Disabling built-in Administrator..." -color "Info"
            try {
                $builtInAdmin = Get-LocalUser -Name "Administrator" -ErrorAction Stop
                if ($builtInAdmin.Enabled) {
                    Disable-LocalUser -Name "Administrator" -ErrorAction Stop
                    Write-OutputColor "        Built-in Administrator disabled." -color "Success"
                    $changesApplied++
                    Add-SessionChange -Category "Security" -Description "Disabled built-in Administrator account"
                } else {
                    Write-OutputColor "        Already disabled." -color "Debug"
                }
            }
            catch {
                Write-OutputColor "        Failed: $_" -color "Error"
                $errors++
            }
        } else {
            Write-OutputColor "  [12/13] Disable built-in admin: skipped" -color "Debug"
        }

        # Domain join (always last among quick tasks - prompts for creds)
        if ($configProfile.Domain.JoinDomain -and -not (Get-CimInstance -ClassName Win32_ComputerSystem).PartOfDomain) {
            Write-OutputColor "  [13/13] Joining domain '$($configProfile.Domain.DomainName)'..." -color "Info"
            Write-OutputColor "        Enter domain credentials:" -color "Info"
            try {
                $domainCred = Get-Credential -Message "Enter credentials to join $($configProfile.Domain.DomainName)"
                if ($domainCred) {
                    Add-Computer -DomainName $configProfile.Domain.DomainName -Credential $domainCred -Force -ErrorAction Stop
                    $global:RebootNeeded = $true
                    $changesApplied++
                    Write-OutputColor "        Joined domain. Reboot required." -color "Success"
                    Add-SessionChange -Category "System" -Description "Joined domain $($configProfile.Domain.DomainName)"
                }
            }
            catch {
                Write-OutputColor "        Failed: $_" -color "Error"
                $errors++
            }
        } else {
            Write-OutputColor "  [13/13] Domain join: skipped" -color "Debug"
        }

        # Summary
        Write-OutputColor "" -color "Info"
        Write-OutputColor ("  " + "=" * 55) -color "Info"
        $resultColor = if ($errors -eq 0) { "Success" } else { "Warning" }
        Write-OutputColor "  Profile applied: $changesApplied succeeded, $errors failed" -color $resultColor
        Write-OutputColor ("  " + "=" * 55) -color "Info"

        if ($global:RebootNeeded) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  ⚠ Reboot required to complete changes." -color "Warning"
        }

        # Install updates last (long running)
        if ($configProfile.InstallUpdates -and $configProfile.InstallUpdates.Install) {
            Write-OutputColor "" -color "Info"
            if (Confirm-UserAction -Message "Install Windows Updates now? (can take 10-60+ min)") {
                Install-WindowsUpdates
            } else {
                Write-OutputColor "  Updates skipped. Run from Configure Server menu later." -color "Info"
            }
        }

        Add-SessionChange -Category "Import" -Description "Applied configuration profile from $profilePath ($changesApplied changes)"
    }
    catch {
        Write-OutputColor "Failed to load profile: $_" -color "Error"
        Write-OutputColor "Make sure the file is valid JSON." -color "Info"
    }
}
# Compare current server state against a saved configuration profile
function Compare-ConfigurationDrift {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProfilePath
    )

    if (-not (Test-Path $ProfilePath)) {
        Write-OutputColor "  Profile not found: $ProfilePath" -color "Error"
        return $null
    }

    try {
        $savedProfile = Get-Content $ProfilePath -Raw | ConvertFrom-Json
    }
    catch {
        Write-OutputColor "  Failed to parse profile: $_" -color "Error"
        return $null
    }
    $results = [ordered]@{}

    # Hostname
    if ($null -ne $savedProfile.Hostname -and $savedProfile.Hostname -ne "") {
        $results["Hostname"] = @{
            Expected = $savedProfile.Hostname
            Current  = $env:COMPUTERNAME
            Match    = ($savedProfile.Hostname -eq $env:COMPUTERNAME)
        }
    }

    # Network
    $primaryAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    if ($primaryAdapter) {
        $currentIP = (Get-NetIPAddress -InterfaceAlias $primaryAdapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.PrefixOrigin -ne "WellKnown" } | Select-Object -First 1).IPAddress
        $currentDNS = (Get-DnsClientServerAddress -InterfaceAlias $primaryAdapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
        $currentGW = (Get-NetRoute -InterfaceAlias $primaryAdapter.Name -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop

        if ($savedProfile.Network) {
            if ($null -ne $savedProfile.Network.IPAddress -and $savedProfile.Network.IPAddress -ne "") {
                $results["IPAddress"] = @{
                    Expected = $savedProfile.Network.IPAddress
                    Current  = $currentIP
                    Match    = ($savedProfile.Network.IPAddress -eq $currentIP)
                }
            }
            if ($null -ne $savedProfile.Network.Gateway -and $savedProfile.Network.Gateway -ne "") {
                $results["Gateway"] = @{
                    Expected = $savedProfile.Network.Gateway
                    Current  = $currentGW
                    Match    = ($savedProfile.Network.Gateway -eq $currentGW)
                }
            }
            if ($savedProfile.Network.DNS1) {
                $expectedDNS = @($savedProfile.Network.DNS1)
                if ($savedProfile.Network.DNS2) { $expectedDNS += $savedProfile.Network.DNS2 }
                $results["DNS"] = @{
                    Expected = ($expectedDNS -join ", ")
                    Current  = ($currentDNS -join ", ")
                    Match    = (($expectedDNS -join ",") -eq ($currentDNS -join ","))
                }
            }
        }
    }

    # Domain membership
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    if ($savedProfile.Domain -and $savedProfile.Domain.DomainName) {
        $currentDomain = if ($cs.PartOfDomain) { $cs.Domain } else { "(workgroup)" }
        $results["Domain"] = @{
            Expected = $savedProfile.Domain.DomainName
            Current  = $currentDomain
            Match    = ($cs.PartOfDomain -and $cs.Domain -eq $savedProfile.Domain.DomainName)
        }
    }

    # Timezone
    if ($savedProfile.Timezone) {
        $currentTZ = (Get-TimeZone).Id
        $results["Timezone"] = @{
            Expected = $savedProfile.Timezone
            Current  = $currentTZ
            Match    = ($savedProfile.Timezone -eq $currentTZ)
        }
    }

    # RDP
    if ($savedProfile.RDP) {
        $currentRDP = Get-RDPState
        $expectedRDP = if ($savedProfile.RDP.Enable) { "Enabled" } else { "Disabled" }
        $results["RDP"] = @{
            Expected = $expectedRDP
            Current  = $currentRDP
            Match    = ($expectedRDP -eq $currentRDP)
        }
    }

    # WinRM
    if ($savedProfile.WinRM) {
        $currentWinRM = Get-WinRMState
        $expectedWinRM = if ($savedProfile.WinRM.Enable) { "Enabled" } else { "Disabled" }
        $results["WinRM"] = @{
            Expected = $expectedWinRM
            Current  = $currentWinRM
            Match    = ($expectedWinRM -eq $currentWinRM)
        }
    }

    # Power Plan
    if ($savedProfile.PowerPlan) {
        $currentPlan = (Get-CurrentPowerPlan).Name
        $results["PowerPlan"] = @{
            Expected = $savedProfile.PowerPlan
            Current  = $currentPlan
            Match    = ($savedProfile.PowerPlan -eq $currentPlan)
        }
    }

    # Hyper-V
    if ($savedProfile.InstallHyperV -and $savedProfile.InstallHyperV.Install) {
        $hvInstalled = Test-HyperVInstalled
        $results["Hyper-V"] = @{
            Expected = "Installed"
            Current  = if ($hvInstalled) { "Installed" } else { "Not Installed" }
            Match    = $hvInstalled
        }
    }

    # MPIO
    if ($savedProfile.InstallMPIO -and $savedProfile.InstallMPIO.Install) {
        $mpioInstalled = Test-MPIOInstalled
        $results["MPIO"] = @{
            Expected = "Installed"
            Current  = if ($mpioInstalled) { "Installed" } else { "Not Installed" }
            Match    = $mpioInstalled
        }
    }

    # Failover Clustering
    if ($savedProfile.InstallFailoverClustering -and $savedProfile.InstallFailoverClustering.Install) {
        $fcInstalled = Test-FailoverClusteringInstalled
        $results["FailoverClustering"] = @{
            Expected = "Installed"
            Current  = if ($fcInstalled) { "Installed" } else { "Not Installed" }
            Match    = $fcInstalled
        }
    }

    return $results
}

# Display drift detection results in a formatted report
function Show-DriftReport {
    param(
        [Parameter(Mandatory=$true)]
        [System.Collections.Specialized.OrderedDictionary]$DriftResults
    )

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     CONFIGURATION DRIFT REPORT").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌──────────────────────┬────────────────────────┬────────────────────────┬────────┐" -color "Info"
    Write-OutputColor "  │ Setting              │ Expected               │ Current                │ Status │" -color "Info"
    Write-OutputColor "  ├──────────────────────┼────────────────────────┼────────────────────────┼────────┤" -color "Info"

    $matchCount = 0
    $driftCount = 0
    $totalCount = 0

    foreach ($key in $DriftResults.Keys) {
        $item = $DriftResults[$key]
        $totalCount++

        $expected = if ($item.Expected) { "$($item.Expected)" } else { "(not set)" }
        $current = if ($item.Current) { "$($item.Current)" } else { "(not set)" }
        $settingName = $key.PadRight(20).Substring(0, 20)
        $expectedStr = $expected.PadRight(22)
        if ($expectedStr.Length -gt 22) { $expectedStr = $expectedStr.Substring(0, 19) + "..." }
        $currentStr = $current.PadRight(22)
        if ($currentStr.Length -gt 22) { $currentStr = $currentStr.Substring(0, 19) + "..." }

        if ($item.Match) {
            $status = " OK   "
            $color = "Success"
            $matchCount++
        } else {
            $status = " DRIFT"
            $color = "Error"
            $driftCount++
        }

        Write-OutputColor "  │ $settingName │ $expectedStr │ $currentStr │$status│" -color $color
    }

    Write-OutputColor "  └──────────────────────┴────────────────────────┴────────────────────────┴────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $summaryColor = if ($driftCount -eq 0) { "Success" } else { "Warning" }
    Write-OutputColor "  Summary: $totalCount checked, $matchCount match, $driftCount drifted" -color $summaryColor
}

# Interactive drift check — prompts for profile, shows report, offers to apply fixes
function Start-DriftCheck {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    CONFIGURATION DRIFT CHECK").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  This compares the current server state against a saved profile" -color "Info"
    Write-OutputColor "  and highlights any settings that have drifted from the expected values." -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enter the path to a configuration profile JSON file:" -color "Info"
    $profilePath = Read-Host "  "

    $navResult = Test-NavigationCommand -UserInput $profilePath
    if ($navResult.ShouldReturn) { return }

    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        Write-OutputColor "  No path entered." -color "Warning"
        return
    }

    if (-not (Test-Path $profilePath)) {
        Write-OutputColor "  File not found: $profilePath" -color "Error"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Analyzing configuration drift..." -color "Info"

    $driftResults = Compare-ConfigurationDrift -ProfilePath $profilePath
    if ($null -eq $driftResults) { return }

    Show-DriftReport -DriftResults $driftResults

    # Check if there are any drifted settings
    $drifted = @()
    foreach ($key in $driftResults.Keys) {
        if (-not $driftResults[$key].Match) {
            $drifted += $key
        }
    }

    if ($drifted.Count -gt 0) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Drifted settings: $($drifted -join ', ')" -color "Warning"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  To fix drift, re-apply the profile using Load Configuration Profile" -color "Info"
        Write-OutputColor "  from the Settings menu." -color "Info"
    } else {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  No drift detected — server matches the saved profile." -color "Success"
    }
}

# ============================================================================
# DRIFT BASELINE PERSISTENCE (v1.7.1)
# ============================================================================

# Save current server state as a drift baseline JSON file
function Save-DriftBaseline {
    param(
        [string]$Description = ""
    )

    $baselineDir = "$script:AppConfigDir\baselines"
    if (-not (Test-Path $baselineDir)) {
        $null = New-Item -Path $baselineDir -ItemType Directory -Force -ErrorAction SilentlyContinue
    }

    $hostname = $env:COMPUTERNAME
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $baselinePath = Join-Path $baselineDir "${hostname}_${timestamp}.json"

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
        $tz = Get-TimeZone
        $powerPlan = Get-CurrentPowerPlan
        $fwState = Get-FirewallState
        $rdpState = Get-RDPState
        $winrmState = Get-WinRMState

        # Network adapters
        $adapters = @()
        foreach ($adapter in (Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" })) {
            $ip = Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
            $dns = (Get-DnsClientServerAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
            $adapters += @{
                Name = $adapter.Name
                IP = if ($ip) { $ip.IPAddress } else { $null }
                Prefix = if ($ip) { $ip.PrefixLength } else { $null }
                DNS = $dns
            }
        }

        # Installed features
        $features = @()
        if (Test-HyperVInstalled) { $features += "Hyper-V" }
        if (Test-MPIOInstalled) { $features += "MPIO" }
        if (Test-FailoverClusteringInstalled) { $features += "FailoverClustering" }

        # VM switches
        $switches = @()
        $vmSwitches = Get-VMSwitch -ErrorAction SilentlyContinue
        if ($vmSwitches) {
            foreach ($sw in $vmSwitches) {
                $switches += @{ Name = $sw.Name; Type = $sw.SwitchType.ToString() }
            }
        }

        $baseline = [ordered]@{
            _BaselineInfo = [ordered]@{
                Hostname = $hostname
                CapturedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                ScriptVersion = $script:ScriptVersion
                Description = $Description
            }
            Hostname = $hostname
            Domain = $cs.Domain
            PartOfDomain = $cs.PartOfDomain
            Timezone = $tz.Id
            PowerPlan = $powerPlan.Name
            RDP = $rdpState
            WinRM = $winrmState
            FirewallDomain = $fwState.Domain
            FirewallPrivate = $fwState.Private
            FirewallPublic = $fwState.Public
            NetworkAdapters = $adapters
            InstalledFeatures = $features
            VMSwitches = $switches
        }

        $baseline | ConvertTo-Json -Depth 5 | Out-File -FilePath $baselinePath -Encoding UTF8 -Force
        Add-SessionChange -Category "Drift" -Description "Saved drift baseline to $baselinePath"
        return $baselinePath
    }
    catch {
        Write-OutputColor "  Failed to save baseline: $_" -color "Error"
        return $null
    }
}

# List saved drift baselines
function Get-DriftBaselines {
    $baselineDir = "$script:AppConfigDir\baselines"
    if (-not (Test-Path $baselineDir)) { return @() }

    $files = Get-ChildItem -Path $baselineDir -Filter "*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    $baselines = @()

    foreach ($file in $files) {
        try {
            $data = Get-Content $file.FullName -Raw | ConvertFrom-Json
            $baselines += @{
                Path = $file.FullName
                FileName = $file.Name
                Hostname = $data._BaselineInfo.Hostname
                CapturedAt = $data._BaselineInfo.CapturedAt
                Description = $data._BaselineInfo.Description
                Size = $file.Length
            }
        }
        catch {
            $baselines += @{ Path = $file.FullName; FileName = $file.Name; Hostname = "?"; CapturedAt = "?"; Description = "Parse error" }
        }
    }
    return $baselines
}

# Compare two baseline files
function Compare-DriftHistory {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Baseline1Path,
        [Parameter(Mandatory=$true)]
        [string]$Baseline2Path
    )

    if (-not (Test-Path $Baseline1Path) -or -not (Test-Path $Baseline2Path)) {
        Write-OutputColor "  One or both baseline files not found." -color "Error"
        return $null
    }

    try {
        $b1 = Get-Content $Baseline1Path -Raw | ConvertFrom-Json
        $b2 = Get-Content $Baseline2Path -Raw | ConvertFrom-Json

        $changes = @()
        $skipKeys = @("_BaselineInfo", "NetworkAdapters", "VMSwitches", "InstalledFeatures")
        $allProps = @()
        $b1.PSObject.Properties | Where-Object { $_.Name -notin $skipKeys } | ForEach-Object { $allProps += $_.Name }
        $b2.PSObject.Properties | Where-Object { $_.Name -notin $skipKeys -and $_.Name -notin $allProps } | ForEach-Object { $allProps += $_.Name }

        foreach ($prop in $allProps) {
            $val1 = "$($b1.$prop)"
            $val2 = "$($b2.$prop)"
            if ($val1 -ne $val2) {
                $changes += @{ Setting = $prop; Before = $val1; After = $val2 }
            }
        }

        # Compare features
        $feat1 = @($b1.InstalledFeatures)
        $feat2 = @($b2.InstalledFeatures)
        $addedFeats = @($feat2 | Where-Object { $_ -notin $feat1 })
        $removedFeats = @($feat1 | Where-Object { $_ -notin $feat2 })
        if ($addedFeats.Count -gt 0) { $changes += @{ Setting = "Features Added"; Before = ""; After = $addedFeats -join ", " } }
        if ($removedFeats.Count -gt 0) { $changes += @{ Setting = "Features Removed"; Before = $removedFeats -join ", "; After = "" } }

        return @{
            Baseline1 = $b1._BaselineInfo
            Baseline2 = $b2._BaselineInfo
            Changes = $changes
            HasChanges = ($changes.Count -gt 0)
        }
    }
    catch {
        Write-OutputColor "  Error comparing baselines: $_" -color "Error"
        return $null
    }
}

# Show drift trend — timeline of setting changes across baselines
function Show-DriftTrend {
    $baselines = Get-DriftBaselines
    if ($baselines.Count -lt 2) {
        Write-OutputColor "  Need at least 2 baselines to show trends. Currently have $($baselines.Count)." -color "Warning"
        return
    }

    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       DRIFT TREND TIMELINE").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Compare each consecutive pair
    $sortedBaselines = $baselines | Sort-Object { $_.CapturedAt }

    for ($i = 1; $i -lt $sortedBaselines.Count; $i++) {
        $prev = $sortedBaselines[$i - 1]
        $curr = $sortedBaselines[$i]

        $comparison = Compare-DriftHistory -Baseline1Path $prev.Path -Baseline2Path $curr.Path
        if ($null -eq $comparison) { continue }

        $timeLabel = "$($prev.CapturedAt) -> $($curr.CapturedAt)"
        if ($comparison.HasChanges) {
            Write-OutputColor "  $timeLabel  [$($comparison.Changes.Count) change(s)]" -color "Warning"
            foreach ($change in $comparison.Changes) {
                Write-OutputColor "    $($change.Setting): '$($change.Before)' -> '$($change.After)'" -color "Info"
            }
        }
        else {
            Write-OutputColor "  $timeLabel  [no changes]" -color "Success"
        }
        Write-OutputColor "" -color "Info"
    }

    Add-SessionChange -Category "Drift" -Description "Viewed drift trend ($($sortedBaselines.Count) baselines)"
}

# Interactive drift detection submenu (v1.7.1)
function Show-DriftDetectionMenu {
    while ($true) {
        if ($global:ReturnToMainMenu) { return }

        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                       DRIFT DETECTION").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  [1] Check drift against profile" -color "Info"
        Write-OutputColor "  [2] Save baseline snapshot" -color "Info"
        Write-OutputColor "  [3] View saved baselines" -color "Info"
        Write-OutputColor "  [4] Compare two baselines" -color "Info"
        Write-OutputColor "  [5] Show drift trend timeline" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" {
                Start-DriftCheck
                Write-PressEnter
            }
            "2" {
                Write-OutputColor "  Enter description (optional):" -color "Info"
                $desc = Read-Host "  "
                $path = Save-DriftBaseline -Description $desc
                if ($path) {
                    Write-OutputColor "  Baseline saved: $path" -color "Success"
                }
                Write-PressEnter
            }
            "3" {
                $baselines = Get-DriftBaselines
                if ($baselines.Count -eq 0) {
                    Write-OutputColor "  No baselines found." -color "Warning"
                }
                else {
                    Write-OutputColor "  Saved baselines ($($baselines.Count)):" -color "Info"
                    Write-OutputColor "" -color "Info"
                    $idx = 1
                    foreach ($bl in $baselines) {
                        Write-OutputColor "  [$idx] $($bl.Hostname)  $($bl.CapturedAt)  $($bl.Description)" -color "Info"
                        $idx++
                    }
                }
                Write-PressEnter
            }
            "4" {
                $baselines = Get-DriftBaselines
                if ($baselines.Count -lt 2) {
                    Write-OutputColor "  Need at least 2 baselines to compare." -color "Warning"
                    Write-PressEnter
                    continue
                }
                Write-OutputColor "  Available baselines:" -color "Info"
                $idx = 1
                foreach ($bl in $baselines) {
                    Write-OutputColor "  [$idx] $($bl.Hostname) $($bl.CapturedAt)" -color "Info"
                    $idx++
                }
                Write-OutputColor "" -color "Info"
                $first = Read-Host "  First baseline number"
                $second = Read-Host "  Second baseline number"
                $fi = ($first -as [int]) - 1
                $si = ($second -as [int]) - 1
                if ($fi -ge 0 -and $fi -lt $baselines.Count -and $si -ge 0 -and $si -lt $baselines.Count) {
                    $comparison = Compare-DriftHistory -Baseline1Path $baselines[$fi].Path -Baseline2Path $baselines[$si].Path
                    if ($comparison) {
                        if ($comparison.HasChanges) {
                            Write-OutputColor "  $($comparison.Changes.Count) difference(s) found:" -color "Warning"
                            foreach ($c in $comparison.Changes) {
                                Write-OutputColor "    $($c.Setting): '$($c.Before)' -> '$($c.After)'" -color "Info"
                            }
                        }
                        else {
                            Write-OutputColor "  No differences found." -color "Success"
                        }
                    }
                }
                else {
                    Write-OutputColor "  Invalid selection." -color "Error"
                }
                Write-PressEnter
            }
            "5" {
                Show-DriftTrend
                Write-PressEnter
            }
            "b" { return }
            "B" { return }
            default {
                Write-OutputColor "  Invalid choice." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}
#endregion