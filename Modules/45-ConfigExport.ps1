#region ===== CONFIGURATION EXPORT =====
function Export-ServerConfiguration {
    Clear-Host
    Write-CenteredOutput "Export Configuration" -color "Info"

    Write-OutputColor "  This will export the current server configuration to a text file." -color "Info"
    Write-OutputColor "" -color "Info"

    # Default filename
    $hostname = $env:COMPUTERNAME
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $defaultPath = "$env:USERPROFILE\Desktop\${hostname}_Config_$timestamp.txt"

    Write-OutputColor "  Default export path: $defaultPath" -color "Info"

    if (Confirm-UserAction -Message "Use default path?" -DefaultYes) {
        $exportPath = $defaultPath
    }
    else {
        Write-OutputColor "  Enter export path (full path with filename):" -color "Info"
        $exportPath = Read-Host
        $navResult = Test-NavigationCommand -UserInput $exportPath
        if ($navResult.ShouldReturn) { return }
        if (-not [string]::IsNullOrWhiteSpace($exportPath)) { $exportPath = $exportPath.Trim('"') }
        if ([string]::IsNullOrWhiteSpace($exportPath)) {
            $exportPath = $defaultPath
        }
    }

    # Validate export path directory
    $exportDir = Split-Path -Parent $exportPath
    if ($exportDir -and -not (Test-Path -LiteralPath $exportDir)) {
        Write-OutputColor "  Directory does not exist: $exportDir" -color "Error"
        return
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

        # System Info (batch CIM with timeout)
        $config += "### SYSTEM INFORMATION ###"
        $sysInfo = Invoke-WithTimeout -ScriptBlock {
            @{
                CS   = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
                OS   = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
                CPU  = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
            }
        } -TimeoutSeconds 15 -Activity "Querying system info"
        if ($sysInfo.TimedOut) {
            $config += "(CIM query timed out — system info unavailable)"
        } else {
            $computerSystem = $sysInfo.Result.CS
            $os = $sysInfo.Result.OS
            $proc = $sysInfo.Result.CPU
            $config += "Hostname:       $(if ($computerSystem) { $computerSystem.Name } else { $env:COMPUTERNAME })"
            $config += "Domain:         $(if ($computerSystem) { $computerSystem.Domain } else { 'Unknown' })"
            $config += "Part of Domain: $(if ($computerSystem) { $computerSystem.PartOfDomain } else { 'Unknown' })"
            $config += "OS:             $(if ($os) { $os.Caption } else { 'Unknown' })"
            $config += "OS Build:       $(if ($os) { $os.BuildNumber } else { 'Unknown' })"
            $config += "Timezone:       $((Get-TimeZone).DisplayName)"
            $config += "CPU:            $(if ($proc) { $proc.Name } else { 'Unknown' })"
            $config += "CPU Cores:      $(if ($proc) { "$($proc.NumberOfCores) cores / $($proc.NumberOfLogicalProcessors) logical" } else { 'Unknown' })"
            $config += "Total RAM:      $(if ($computerSystem) { "$([math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 1)) GB" } else { 'Unknown' })"
        }
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

            # Adapter speed negotiation state
            try {
                $physAdapter = Get-NetAdapterHardwareInfo -Name $adapter.Name -ErrorAction SilentlyContinue
                if ($null -ne $physAdapter) {
                    $adapterAdv = Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword "*SpeedDuplex" -ErrorAction SilentlyContinue
                    $mediaType = $adapter.MediaType
                    if ($mediaType) {
                        $config += "  Media Type:   $mediaType"
                    }
                    if ($null -ne $adapterAdv -and $adapterAdv.DisplayValue) {
                        $config += "  Speed/Duplex: $($adapterAdv.DisplayValue)"
                    }
                    # Flag if running below max capability
                    $linkSpeedStr = $adapter.LinkSpeed
                    if ($linkSpeedStr -match '(\d+(\.\d+)?)\s*(Gbps|Mbps)') {
                        $regexMatches = $matches
                        $linkVal = [double]$regexMatches[1]
                        $linkUnit = $regexMatches[3]
                        $linkMbps = if ($linkUnit -eq "Gbps") { $linkVal * 1000 } else { $linkVal }
                        $maxSpeed = Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword "*SpeedDuplex" -ErrorAction SilentlyContinue
                        if ($null -ne $maxSpeed -and $maxSpeed.ValidRegistryValues) {
                            $maxOptions = @($maxSpeed.ValidDisplayValues | Where-Object { $_ -match '\d' })
                            if ($maxOptions.Count -gt 0) {
                                $lastOption = $maxOptions[-1]
                                if ($lastOption -match '10\s*Gbps|10000' -and $linkMbps -lt 10000) {
                                    $config += "  ** WARNING:   Running below max speed (capable of 10 Gbps)"
                                }
                            }
                        }
                    }
                }
            }
            catch {
                # Adapter speed details unavailable — skip silently
            }

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
        try {
            $rdpPort = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name PortNumber -ErrorAction Stop).PortNumber
            $config += "RDP Port:      $rdpPort"
        } catch {}
        $config += "WinRM Status:  $(Get-WinRMState)"
        $config += ""

        # Key Services
        $config += "### KEY SERVICES ###"
        $servicesToCheck = @('wuauserv', 'WinRM', 'vmms', 'ClusSvc', 'MSiSCSI', 'W32Time', 'WinDefend', 'Spooler', 'DNS', 'NTDS')
        foreach ($svcName in $servicesToCheck) {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($svc) {
                $startTag = switch ($svc.StartType) { "Automatic" { "Auto" } "Manual" { "Manual" } "Disabled" { "Disabled" } default { $svc.StartType } }
                $config += "  $($svc.DisplayName): $($svc.Status) [$startTag]"
            }
        }
        $config += ""

        # Firewall Status
        $config += "### FIREWALL STATUS ###"
        $fwState = Get-FirewallState
        $config += "Domain Profile:  $($fwState.Domain)"
        $config += "Private Profile: $($fwState.Private)"
        $config += "Public Profile:  $($fwState.Public)"
        try {
            $fwRules = @(Get-NetFirewallRule -Enabled True -ErrorAction SilentlyContinue)
            $fwInbound = @($fwRules | Where-Object { $_.Direction -eq "Inbound" }).Count
            $fwOutbound = @($fwRules | Where-Object { $_.Direction -eq "Outbound" }).Count
            $config += "Enabled Rules:   $($fwRules.Count) total ($fwInbound inbound, $fwOutbound outbound)"
        }
        catch {
            $config += "Enabled Rules:   Unable to enumerate"
        }
        $config += ""

        # MPIO
        $config += "### MPIO (MULTIPATH I/O) ###"
        if (Test-MPIOInstalled) {
            $config += "MPIO: Installed"
            $mpioDevices = Get-MSDSMSupportedHW -ErrorAction SilentlyContinue
            if ($mpioDevices) {
                $config += "  Supported Hardware:"
                foreach ($dev in $mpioDevices) {
                    $vendor = if ($dev.VendorId) { $dev.VendorId.Trim() } else { "Unknown" }
                    $product = if ($dev.ProductId) { $dev.ProductId.Trim() } else { "Unknown" }
                    $config += "    $vendor - $product"
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

        # Security Baseline
        $config += "### SECURITY BASELINE ###"
        try {
            $secureBoot = Confirm-SecureBootUEFI -ErrorAction Stop
            $config += "Secure Boot:   $(if ($secureBoot) { 'Enabled' } else { 'Disabled' })"
        } catch {
            $config += "Secure Boot:   N/A (BIOS or check unavailable)"
        }
        try {
            $uacKey = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -ErrorAction Stop
            $config += "UAC:           $(if ($uacKey.EnableLUA -eq 1) { 'Enabled' } else { 'Disabled' })"
        } catch {
            $config += "UAC:           Unknown"
        }
        try {
            $defender = Get-MpComputerStatus -ErrorAction Stop
            $config += "Defender:      $(if ($defender.AntivirusEnabled) { 'Enabled' } else { 'Disabled' })"
            $config += "Real-time:     $(if ($defender.RealTimeProtectionEnabled) { 'Enabled' } else { 'Disabled' })"
            if ($null -ne $defender.AntivirusSignatureLastUpdated) {
                $config += "Signatures:    $($defender.AntivirusSignatureLastUpdated.ToString('yyyy-MM-dd HH:mm'))"
            }
        } catch {
            $config += "Defender:      Unavailable"
        }
        $config += ""

        # BitLocker
        $config += "### BITLOCKER STATUS ###"
        try {
            $blVolumes = Get-BitLockerVolume -ErrorAction SilentlyContinue
            if ($null -ne $blVolumes) {
                foreach ($blVol in $blVolumes) {
                    $protectors = @($blVol.KeyProtector | ForEach-Object { $_.KeyProtectorType }) -join ", "
                    if (-not $protectors) { $protectors = "None" }
                    $config += "  $($blVol.MountPoint) | Encryption: $($blVol.VolumeStatus) | Protection: $($blVol.ProtectionStatus) | Protectors: $protectors"
                }
            } else {
                $config += "BitLocker: Not available (cmdlet not found or no volumes)"
            }
        }
        catch {
            $config += "BitLocker: Unable to query (may require elevated privileges or Server edition)"
        }
        $config += ""

        # Event Log Configuration
        $config += "### EVENT LOG CONFIGURATION ###"
        try {
            $logNames = @("Application", "System", "Security")
            foreach ($logName in $logNames) {
                $logConfig = Get-WinEvent -ListLog $logName -ErrorAction SilentlyContinue
                if ($null -ne $logConfig) {
                    $maxSizeMB = [math]::Round($logConfig.MaximumSizeInBytes / 1MB, 1)
                    $config += "  $logName | Max Size: ${maxSizeMB} MB | Mode: $($logConfig.LogMode)"
                }
            }
        }
        catch {
            $config += "  (Unable to query event log configuration: $_)"
        }
        $config += ""

        # Time Sync
        $config += "### TIME SYNCHRONIZATION ###"
        $config += "System Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        try {
            $timeSource = & w32tm /query /source 2>&1
            if ($LASTEXITCODE -eq 0) {
                $config += "NTP Source:  $timeSource"
            } else {
                $config += "NTP Source:  Unable to determine"
            }
        }
        catch {
            $config += "NTP Source:  w32tm not available"
        }
        try {
            $syncStatus = & w32tm /query /status 2>&1
            if ($LASTEXITCODE -eq 0) {
                $lastSync = $syncStatus | Select-String "Last Successful Sync Time"
                if ($lastSync) {
                    $config += "Last Sync:   $($lastSync.ToString().Split(':',2)[1].Trim())"
                }
            }
        }
        catch {
            # Time sync status unavailable — skip silently
        }
        $config += ""

        # Storage
        $config += "### STORAGE ###"
        try {
            $disks = Get-Disk -ErrorAction Stop
            foreach ($disk in $disks) {
                $sizeDisplay = if ($disk.Size -ge 1TB) { "$([math]::Round($disk.Size / 1TB, 2)) TB" } else { "$([math]::Round($disk.Size / 1GB, 1)) GB" }
                $config += "  Disk $($disk.Number): $($disk.FriendlyName) | $sizeDisplay | $($disk.PartitionStyle) | $($disk.OperationalStatus)"
            }
        }
        catch {
            $config += "  (Unable to enumerate disks: $_)"
        }
        $config += ""
        try {
            $volumes = Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | Sort-Object DriveLetter
            foreach ($vol in $volumes) {
                $totalGB = [math]::Round($vol.Size / 1GB, 1)
                $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 1)
                $usedPct = if ($vol.Size -gt 0) { [math]::Round((($vol.Size - $vol.SizeRemaining) / $vol.Size) * 100, 0) } else { 0 }
                $label = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { "(No Label)" }
                $config += "  $($vol.DriveLetter): $label | $($vol.FileSystem) | $freeGB GB free / $totalGB GB ($usedPct% used)"
            }
        }
        catch {
            $config += "  (Unable to enumerate volumes: $_)"
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
                    $teamDetails = ""
                    if ($sw.EmbeddedTeamingEnabled) {
                        try {
                            $setTeam = Get-VMSwitchTeam -Name $sw.Name -ErrorAction SilentlyContinue
                            if ($null -ne $setTeam) {
                                $teamNics = $setTeam.NetAdapterInterfaceDescription -join ", "
                                if ($teamNics) { $teamMembers = " | Team: $teamNics" }
                                $lbAlgo = $setTeam.LoadBalancingAlgorithm
                                if ($lbAlgo) { $teamDetails = " | LB: $lbAlgo" }
                            }
                        }
                        catch {
                            # SET team query failed — skip details
                        }
                    }
                    $config += "    $($sw.Name) (Type: $($sw.SwitchType))$teamMembers$teamDetails"
                }
            }

            $vms = @(Get-VM -ErrorAction SilentlyContinue)
            if ($vms.Count -gt 0) {
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
        $config | Out-File -LiteralPath $exportPath -Encoding UTF8 -Force

        Write-OutputColor "`nConfiguration exported successfully!" -color "Success"
        Write-OutputColor "  File: $exportPath" -color "Info"
        Add-SessionChange -Category "Export" -Description "Exported configuration to $exportPath"
    }
    catch {
        Write-OutputColor "  Failed to export configuration: $_" -color "Error"
    }
}

# Function to save configuration profile as JSON for cloning to other servers
function Save-ConfigurationProfile {
    Clear-Host
    Write-CenteredOutput "Save Configuration Profile" -color "Info"

    Write-OutputColor "  This will save the current server's configuration as a JSON profile" -color "Info"
    Write-OutputColor "  that can be loaded onto other servers to clone settings." -color "Info"
    Write-OutputColor "" -color "Info"

    # Gather current configuration
    Write-OutputColor "  Gathering current configuration..." -color "Info"

    $csCim = Invoke-WithTimeout -ScriptBlock {
        Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    } -TimeoutSeconds 10 -Activity "Querying computer system"
    $computerSystem = if ($csCim.TimedOut) { $null } else { $csCim.Result }
    $timezone = Get-TimeZone
    $powerPlan = Get-CurrentPowerPlan

    # Get primary adapter info
    $primaryAdapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
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
            "JoinDomain" = if ($null -ne $computerSystem) { $computerSystem.PartOfDomain } else { $false }
            "DomainName" = if ($null -ne $computerSystem -and $computerSystem.PartOfDomain) { $computerSystem.Domain } else { $script:Domain }
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
    Write-OutputColor "  Default save location: $defaultPath" -color "Info"

    if (Confirm-UserAction -Message "Use default path?" -DefaultYes) {
        $savePath = $defaultPath
    }
    else {
        Write-OutputColor "  Enter save path (full path with filename):" -color "Info"
        $savePath = Read-Host
        $navResult = Test-NavigationCommand -UserInput $savePath
        if ($navResult.ShouldReturn) { return }
        if (-not [string]::IsNullOrWhiteSpace($savePath)) { $savePath = $savePath.Trim('"') }
        if ([string]::IsNullOrWhiteSpace($savePath)) {
            $savePath = $defaultPath
        }
    }

    try {
        $configProfile | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $savePath -Encoding UTF8 -Force

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Configuration profile saved successfully!" -color "Success"
        Write-OutputColor "  File: $savePath" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  To use this profile on another server:" -color "Info"
        Write-OutputColor "  1. Copy the JSON file to the new server" -color "Success"
        Write-OutputColor "  2. Edit the file: set Hostname, IPAddress, Gateway" -color "Success"
        Write-OutputColor "  3. Run this script and choose 'Load Configuration Profile'" -color "Success"
        Write-OutputColor "  4. Review the settings preview, then confirm to apply" -color "Success"

        Add-SessionChange -Category "Export" -Description "Saved configuration profile to $savePath"
    }
    catch {
        Write-OutputColor "  Failed to save profile: $_" -color "Error"
    }
}

# Function to load and apply configuration profile from JSON
function Import-ConfigurationProfile {
    Clear-Host
    Write-CenteredOutput "Load Configuration Profile" -color "Info"

    Write-OutputColor "  This will apply settings from a previously saved configuration profile." -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enter the path to the profile JSON file:" -color "Info"
    $profilePath = Read-Host

    # Check for navigation
    $navResult = Test-NavigationCommand -UserInput $profilePath
    if ($navResult.ShouldReturn) {
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($profilePath)) { $profilePath = $profilePath.Trim('"') }
    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        Write-OutputColor "  No path entered." -color "Warning"
        return
    }

    if (-not (Test-Path -LiteralPath $profilePath)) {
        Write-OutputColor "  File not found: $profilePath" -color "Error"
        return
    }

    try {
        $configProfile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json

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
            Write-OutputColor "  Profile import cancelled." -color "Info"
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
                    Clear-MenuCache
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
                Remove-NetIPAddress -InterfaceAlias $adapterName -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
                Remove-NetRoute -InterfaceAlias $adapterName -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue

                New-NetIPAddress -InterfaceAlias $adapterName -IPAddress $configProfile.Network.IPAddress `
                    -PrefixLength $configProfile.Network.SubnetCIDR -DefaultGateway $configProfile.Network.Gateway -ErrorAction Stop

                $dnsServers = @($configProfile.Network.DNS1)
                if ($configProfile.Network.DNS2) { $dnsServers += $configProfile.Network.DNS2 }
                Set-DnsClientServerAddress -InterfaceAlias $adapterName -ServerAddresses $dnsServers -ErrorAction Stop

                $changesApplied++
                Write-OutputColor "        Network configured." -color "Success"
                Add-SessionChange -Category "Network" -Description "Set IP $($configProfile.Network.IPAddress)/$($configProfile.Network.SubnetCIDR) on $adapterName"
                Clear-MenuCache
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
                Microsoft.PowerShell.Management\Set-TimeZone -Id $configProfile.Timezone -ErrorAction Stop
                $changesApplied++
                Write-OutputColor "        Timezone set." -color "Success"
                Add-SessionChange -Category "System" -Description "Set timezone to $($configProfile.Timezone)"
                Clear-MenuCache
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
                    Write-OutputColor "        Failed to set power plan (exit code $LASTEXITCODE)." -color "Error"
                } else {
                    $changesApplied++
                    Write-OutputColor "        Power plan set." -color "Success"
                    Add-SessionChange -Category "System" -Description "Set power plan to $($configProfile.PowerPlan)"
                }
                Clear-MenuCache
            } else {
                Write-OutputColor "        Unknown power plan: $($configProfile.PowerPlan)" -color "Error"
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
                    Clear-MenuCache
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
                    Clear-MenuCache
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
        $domCim = Invoke-WithTimeout -ScriptBlock {
            Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
        } -TimeoutSeconds 10 -Activity "Checking domain status"
        $domCs = if ($domCim.TimedOut) { $null } else { $domCim.Result }
        if ($configProfile.Domain.JoinDomain -and $null -ne $domCs -and -not $domCs.PartOfDomain) {
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
                    Clear-MenuCache
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
        Clear-MenuCache
    }
    catch {
        Write-OutputColor "  Failed to load profile: $_" -color "Error"
        Write-OutputColor "  Make sure the file is valid JSON." -color "Info"
    }
}
# Compare current server state against a saved configuration profile
function Compare-ConfigurationDrift {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProfilePath
    )

    if (-not (Test-Path -LiteralPath $ProfilePath)) {
        Write-OutputColor "  Profile not found: $ProfilePath" -color "Error"
        return $null
    }

    try {
        $savedProfile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
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
    $primaryAdapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
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
    $driftCim = Invoke-WithTimeout -ScriptBlock {
        Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    } -TimeoutSeconds 10 -Activity "Checking domain membership"
    $cs = if ($driftCim.TimedOut) { $null } else { $driftCim.Result }
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

# Remediate drifted settings by applying fixes from a baseline profile
function Invoke-Remediation {
    <#
    .SYNOPSIS
        Compares current state to a baseline profile and applies fixes for drifted settings.
        Returns structured remediation results.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProfilePath
    )

    # Load the profile for reference during fixes
    try {
        $savedProfile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
    } catch {
        Write-OutputColor "  Failed to parse profile: $_" -color "Error"
        return $null
    }

    # Run drift comparison
    $driftResults = Compare-ConfigurationDrift -ProfilePath $ProfilePath
    if ($null -eq $driftResults) { return $null }

    # Filter for drifted items only
    $driftedKeys = @()
    foreach ($key in $driftResults.Keys) {
        if (-not $driftResults[$key].Match) {
            $driftedKeys += $key
        }
    }

    if ($driftedKeys.Count -eq 0) {
        Write-OutputColor "  No drift detected — server matches baseline." -color "Success"
        return @{
            Total          = 0
            Fixed          = 0
            Skipped        = 0
            Failed         = 0
            Manual         = 0
            RebootRequired = $false
            Items          = @()
        }
    }

    Write-OutputColor "  Found $($driftedKeys.Count) drifted setting(s). Remediating..." -color "Warning"
    Write-OutputColor "" -color "Info"

    # Remediation order (safe first, reboot-required last)
    $remediationOrder = @(
        'Timezone', 'PowerPlan', 'RDP', 'WinRM', 'DNS',
        'IPAddress', 'Gateway',
        'Hyper-V', 'MPIO', 'FailoverClustering',
        'Domain', 'Hostname'
    )
    $rebootSettings = @('Hostname', 'Domain', 'Hyper-V', 'MPIO', 'FailoverClustering')

    $items = [System.Collections.Generic.List[object]]::new()
    $fixedCount = 0
    $skippedCount = 0
    $failedCount = 0
    $manualCount = 0
    $rebootNeeded = $false

    # Process in order, skip keys that aren't drifted
    $orderedKeys = @($remediationOrder | Where-Object { $driftedKeys -contains $_ })
    # Add any drifted keys not in our order (future-proofing)
    foreach ($k in $driftedKeys) {
        if ($orderedKeys -notcontains $k) { $orderedKeys += $k }
    }

    # Get primary adapter for network fixes
    $primaryAdapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    $adapterName = if ($primaryAdapter) { $primaryAdapter.Name } else { $null }

    foreach ($key in $orderedKeys) {
        $drift = $driftResults[$key]
        $expected = $drift.Expected
        $current = $drift.Current

        # Skip Gateway if IPAddress is also drifted (they'll be fixed together)
        if ($key -eq 'Gateway' -and $driftedKeys -contains 'IPAddress') {
            $items.Add(@{
                Setting  = $key
                Expected = $expected
                Current  = $current
                Action   = "Skipped"
                Detail   = "Applied with IPAddress"
            })
            $skippedCount++
            continue
        }

        # Domain always requires manual intervention (needs credentials)
        if ($key -eq 'Domain') {
            Write-OutputColor "  [MANUAL] $key — requires credentials (cannot auto-remediate)" -color "Warning"
            $items.Add(@{
                Setting  = $key
                Expected = $expected
                Current  = $current
                Action   = "Manual"
                Detail   = "Domain join requires credentials"
            })
            $manualCount++
            continue
        }

        try {
            $detail = ""
            switch ($key) {
                'Timezone' {
                    Write-OutputColor "  [FIX] Timezone: $current → $expected" -color "Info"
                    Microsoft.PowerShell.Management\Set-TimeZone -Id $expected -ErrorAction Stop
                    $detail = "Set timezone to $expected"
                    Add-SessionChange -Category "Remediation" -Description $detail
                }
                'PowerPlan' {
                    Write-OutputColor "  [FIX] PowerPlan: $current → $expected" -color "Info"
                    if ($script:PowerPlanGUID.ContainsKey($expected)) {
                        $ppOutput = powercfg /setactive $script:PowerPlanGUID[$expected] 2>&1
                        $detail = "Set power plan to $expected"
                    } else {
                        throw "Unknown power plan: $expected"
                    }
                    Add-SessionChange -Category "Remediation" -Description $detail
                }
                'RDP' {
                    Write-OutputColor "  [FIX] RDP: $current → $expected" -color "Info"
                    if ($expected -eq "Enabled") {
                        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -ErrorAction Stop
                        Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
                        $detail = "Enabled RDP"
                    } else {
                        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 1 -ErrorAction Stop
                        Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
                        $detail = "Disabled RDP"
                    }
                    Add-SessionChange -Category "Remediation" -Description $detail
                }
                'WinRM' {
                    Write-OutputColor "  [FIX] WinRM: $current → $expected" -color "Info"
                    if ($expected -eq "Enabled") {
                        Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction Stop
                        $detail = "Enabled WinRM"
                    } else {
                        Disable-PSRemoting -Force -ErrorAction SilentlyContinue
                        $detail = "Disabled WinRM"
                    }
                    Add-SessionChange -Category "Remediation" -Description $detail
                }
                'DNS' {
                    if (-not $adapterName) { throw "No active network adapter found" }
                    Write-OutputColor "  [FIX] DNS: $current → $expected" -color "Info"
                    $dnsServers = @()
                    if ($savedProfile.Network.DNS1) { $dnsServers += $savedProfile.Network.DNS1 }
                    if ($savedProfile.Network.DNS2) { $dnsServers += $savedProfile.Network.DNS2 }
                    Set-DnsClientServerAddress -InterfaceAlias $adapterName -ServerAddresses $dnsServers -ErrorAction Stop
                    $detail = "Set DNS to $($dnsServers -join ', ')"
                    Add-SessionChange -Category "Remediation" -Description $detail
                }
                'IPAddress' {
                    if (-not $adapterName) { throw "No active network adapter found" }
                    $newIP = $savedProfile.Network.IPAddress
                    $newGW = $savedProfile.Network.Gateway
                    $cidr = if ($savedProfile.Network.SubnetCIDR) { [int]$savedProfile.Network.SubnetCIDR } else { 24 }
                    Write-OutputColor "  [FIX] IPAddress: $current → $newIP (/$cidr, GW: $newGW)" -color "Info"
                    Remove-NetIPAddress -InterfaceAlias $adapterName -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
                    Remove-NetRoute -InterfaceAlias $adapterName -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
                    if ($newGW) {
                        New-NetIPAddress -InterfaceAlias $adapterName -IPAddress $newIP -PrefixLength $cidr -DefaultGateway $newGW -ErrorAction Stop | Out-Null
                    } else {
                        New-NetIPAddress -InterfaceAlias $adapterName -IPAddress $newIP -PrefixLength $cidr -ErrorAction Stop | Out-Null
                    }
                    $detail = "Set IP to $newIP/$cidr$(if ($newGW) { " GW $newGW" })"
                    Add-SessionChange -Category "Remediation" -Description $detail
                }
                'Gateway' {
                    # Standalone gateway fix (only if IP wasn't also drifted)
                    if (-not $adapterName) { throw "No active network adapter found" }
                    Write-OutputColor "  [FIX] Gateway: $current → $expected" -color "Info"
                    Remove-NetRoute -InterfaceAlias $adapterName -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue
                    New-NetRoute -InterfaceAlias $adapterName -DestinationPrefix "0.0.0.0/0" -NextHop $expected -ErrorAction Stop | Out-Null
                    $detail = "Set default gateway to $expected"
                    Add-SessionChange -Category "Remediation" -Description $detail
                }
                'Hyper-V' {
                    if ($expected -eq "Installed") {
                        Write-OutputColor "  [FIX] Hyper-V: Installing..." -color "Info"
                        Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -ErrorAction Stop | Out-Null
                        $rebootNeeded = $true
                        $detail = "Installed Hyper-V (reboot required)"
                    } else {
                        $detail = "Skipped — uninstalling features is destructive"
                        $items.Add(@{ Setting = $key; Expected = $expected; Current = $current; Action = "Skipped"; Detail = $detail })
                        $skippedCount++
                        Write-OutputColor "  [SKIP] $key — $detail" -color "Warning"
                        continue
                    }
                    Add-SessionChange -Category "Remediation" -Description $detail
                }
                'MPIO' {
                    if ($expected -eq "Installed") {
                        Write-OutputColor "  [FIX] MPIO: Installing..." -color "Info"
                        Install-WindowsFeature -Name Multipath-IO -ErrorAction Stop | Out-Null
                        $rebootNeeded = $true
                        $detail = "Installed MPIO (reboot required)"
                    } else {
                        $detail = "Skipped — uninstalling features is destructive"
                        $items.Add(@{ Setting = $key; Expected = $expected; Current = $current; Action = "Skipped"; Detail = $detail })
                        $skippedCount++
                        Write-OutputColor "  [SKIP] $key — $detail" -color "Warning"
                        continue
                    }
                    Add-SessionChange -Category "Remediation" -Description $detail
                }
                'FailoverClustering' {
                    if ($expected -eq "Installed") {
                        Write-OutputColor "  [FIX] FailoverClustering: Installing..." -color "Info"
                        Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools -ErrorAction Stop | Out-Null
                        $rebootNeeded = $true
                        $detail = "Installed Failover Clustering (reboot required)"
                    } else {
                        $detail = "Skipped — uninstalling features is destructive"
                        $items.Add(@{ Setting = $key; Expected = $expected; Current = $current; Action = "Skipped"; Detail = $detail })
                        $skippedCount++
                        Write-OutputColor "  [SKIP] $key — $detail" -color "Warning"
                        continue
                    }
                    Add-SessionChange -Category "Remediation" -Description $detail
                }
                'Hostname' {
                    Write-OutputColor "  [FIX] Hostname: $current → $expected" -color "Info"
                    if (Test-ValidHostname -Hostname $expected) {
                        Rename-Computer -NewName $expected -Force -ErrorAction Stop
                        $rebootNeeded = $true
                        $detail = "Renamed to $expected (reboot required)"
                    } else {
                        throw "Invalid hostname: $expected"
                    }
                    Add-SessionChange -Category "Remediation" -Description $detail
                }
                default {
                    # Unknown drift key — skip
                    $items.Add(@{ Setting = $key; Expected = $expected; Current = $current; Action = "Skipped"; Detail = "No remediation handler" })
                    $skippedCount++
                    Write-OutputColor "  [SKIP] $key — no remediation handler" -color "Warning"
                    continue
                }
            }

            # If we got here, the fix succeeded
            if ($rebootSettings -contains $key) { $rebootNeeded = $true }
            $items.Add(@{
                Setting  = $key
                Expected = $expected
                Current  = $current
                Action   = "Fixed"
                Detail   = $detail
            })
            $fixedCount++
            Write-OutputColor "  [OK] $key remediated" -color "Success"

        } catch {
            $items.Add(@{
                Setting  = $key
                Expected = $expected
                Current  = $current
                Action   = "Failed"
                Detail   = $_.Exception.Message
            })
            $failedCount++
            Write-OutputColor "  [FAIL] $key — $_" -color "Error"
        }
    }

    return @{
        Total          = $driftedKeys.Count
        Fixed          = $fixedCount
        Skipped        = $skippedCount
        Failed         = $failedCount
        Manual         = $manualCount
        RebootRequired = $rebootNeeded
        Items          = @($items)
    }
}

# Display remediation results in a formatted report
function Show-RemediationReport {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Result
    )

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ── Remediation Summary ──" -color "Info"
    Write-OutputColor "  Total drifted: $($Result.Total)  Fixed: $($Result.Fixed)  Failed: $($Result.Failed)  Skipped: $($Result.Skipped)  Manual: $($Result.Manual)" -color $(if ($Result.Failed -eq 0) { 'Success' } else { 'Warning' })

    if ($Result.Items.Count -gt 0) {
        Write-OutputColor "" -color "Info"
        foreach ($item in $Result.Items) {
            $icon = switch ($item.Action) {
                'Fixed'   { '[FIXED]' }
                'Failed'  { '[FAIL] ' }
                'Skipped' { '[SKIP] ' }
                'Manual'  { '[MANUAL]' }
                default   { '[----] ' }
            }
            $itemColor = switch ($item.Action) {
                'Fixed'   { 'Success' }
                'Failed'  { 'Error' }
                'Skipped' { 'Warning' }
                'Manual'  { 'Warning' }
                default   { 'Info' }
            }
            Write-OutputColor "  $icon $($item.Setting.PadRight(22)) $($item.Detail)" -color $itemColor
        }
    }

    if ($Result.RebootRequired) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ** One or more changes require a reboot to take effect. **" -color "Warning"
    }
    Write-OutputColor "" -color "Info"
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

    if (-not [string]::IsNullOrWhiteSpace($profilePath)) { $profilePath = $profilePath.Trim('"') }
    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        Write-OutputColor "  No path entered." -color "Warning"
        return
    }

    if (-not (Test-Path -LiteralPath $profilePath)) {
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
    if (-not (Test-Path -LiteralPath $baselineDir)) {
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

        # Network adapters (batch queries to avoid N+1)
        $adapters = @()
        $allIPv4 = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $allDns = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue
        foreach ($adapter in (Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" })) {
            $ip = $allIPv4 | Where-Object { $_.InterfaceAlias -eq $adapter.Name } | Select-Object -First 1
            $dns = ($allDns | Where-Object { $_.InterfaceAlias -eq $adapter.Name }).ServerAddresses
            $adapters += @{
                Name = $adapter.Name
                IP = if ($ip) { $ip.IPAddress } else { $null }
                Prefix = if ($ip) { $ip.PrefixLength } else { $null }
                DNS = $dns
                LinkSpeed = $adapter.LinkSpeed
                MediaType = $adapter.MediaType
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
                $swInfo = @{ Name = $sw.Name; Type = $sw.SwitchType.ToString(); EmbeddedTeaming = $sw.EmbeddedTeamingEnabled }
                if ($sw.EmbeddedTeamingEnabled) {
                    try {
                        $setTeam = Get-VMSwitchTeam -Name $sw.Name -ErrorAction SilentlyContinue
                        if ($null -ne $setTeam) {
                            $swInfo["TeamNicNames"] = @($setTeam.NetAdapterInterfaceDescription)
                            $swInfo["LoadBalancingAlgorithm"] = $setTeam.LoadBalancingAlgorithm.ToString()
                        }
                    }
                    catch {
                        # SET team query failed — skip details
                    }
                }
                $switches += $swInfo
            }
        }

        # Firewall rule counts
        $fwRuleCounts = [ordered]@{}
        try {
            $fwRulesAll = @(Get-NetFirewallRule -Enabled True -ErrorAction SilentlyContinue)
            $fwRuleCounts["Total"] = $fwRulesAll.Count
            $fwRuleCounts["Inbound"] = @($fwRulesAll | Where-Object { $_.Direction -eq "Inbound" }).Count
            $fwRuleCounts["Outbound"] = @($fwRulesAll | Where-Object { $_.Direction -eq "Outbound" }).Count
        }
        catch {
            $fwRuleCounts["Total"] = -1
        }

        # BitLocker volumes
        $bitlockerVolumes = @()
        try {
            $blVolumes = Get-BitLockerVolume -ErrorAction SilentlyContinue
            if ($null -ne $blVolumes) {
                foreach ($blVol in $blVolumes) {
                    $protectors = @($blVol.KeyProtector | ForEach-Object { $_.KeyProtectorType.ToString() })
                    $bitlockerVolumes += @{
                        MountPoint = $blVol.MountPoint
                        VolumeStatus = $blVol.VolumeStatus.ToString()
                        ProtectionStatus = $blVol.ProtectionStatus.ToString()
                        KeyProtectorTypes = $protectors
                    }
                }
            }
        }
        catch {
            # BitLocker unavailable — skip
        }

        # Event log configuration
        $eventLogs = @()
        try {
            foreach ($logName in @("Application", "System", "Security")) {
                $logConfig = Get-WinEvent -ListLog $logName -ErrorAction SilentlyContinue
                if ($null -ne $logConfig) {
                    $eventLogs += @{
                        Name = $logName
                        MaxSizeBytes = $logConfig.MaximumSizeInBytes
                        LogMode = $logConfig.LogMode.ToString()
                    }
                }
            }
        }
        catch {
            # Event log query failed — skip
        }

        # Time synchronization
        $timeSync = [ordered]@{
            SystemTime = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        }
        try {
            $timeSource = & w32tm /query /source 2>&1
            if ($LASTEXITCODE -eq 0) {
                $timeSync["NTPSource"] = "$timeSource"
            }
        }
        catch {
            # w32tm not available
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
            FirewallRuleCounts = $fwRuleCounts
            BitLockerVolumes = $bitlockerVolumes
            EventLogs = $eventLogs
            TimeSync = $timeSync
        }

        $baseline | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $baselinePath -Encoding UTF8 -Force
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
    if (-not (Test-Path -LiteralPath $baselineDir)) { return @() }

    $files = Get-ChildItem -LiteralPath $baselineDir -Filter "*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    $baselines = @()

    foreach ($file in $files) {
        try {
            $data = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
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

    if (-not (Test-Path -LiteralPath $Baseline1Path) -or -not (Test-Path -LiteralPath $Baseline2Path)) {
        Write-OutputColor "  One or both baseline files not found." -color "Error"
        return $null
    }

    try {
        $b1 = Get-Content -LiteralPath $Baseline1Path -Raw | ConvertFrom-Json
        $b2 = Get-Content -LiteralPath $Baseline2Path -Raw | ConvertFrom-Json

        $changes = @()
        $skipKeys = @("_BaselineInfo", "NetworkAdapters", "VMSwitches", "InstalledFeatures", "FirewallRuleCounts", "BitLockerVolumes", "EventLogs", "TimeSync")
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

        # Compare firewall rule counts
        if ($b1.FirewallRuleCounts -and $b2.FirewallRuleCounts) {
            foreach ($countProp in @("Total", "Inbound", "Outbound")) {
                $fc1 = "$($b1.FirewallRuleCounts.$countProp)"
                $fc2 = "$($b2.FirewallRuleCounts.$countProp)"
                if ($fc1 -ne $fc2) {
                    $changes += @{ Setting = "FW Rules ($countProp)"; Before = $fc1; After = $fc2 }
                }
            }
        }

        # Compare BitLocker volumes
        if ($b1.BitLockerVolumes -or $b2.BitLockerVolumes) {
            $blVols1 = @($b1.BitLockerVolumes)
            $blVols2 = @($b2.BitLockerVolumes)
            foreach ($blv in $blVols2) {
                $matching = $blVols1 | Where-Object { $_.MountPoint -eq $blv.MountPoint }
                if ($null -ne $matching) {
                    if ("$($matching.ProtectionStatus)" -ne "$($blv.ProtectionStatus)") {
                        $changes += @{ Setting = "BitLocker $($blv.MountPoint) Protection"; Before = "$($matching.ProtectionStatus)"; After = "$($blv.ProtectionStatus)" }
                    }
                    if ("$($matching.VolumeStatus)" -ne "$($blv.VolumeStatus)") {
                        $changes += @{ Setting = "BitLocker $($blv.MountPoint) Encryption"; Before = "$($matching.VolumeStatus)"; After = "$($blv.VolumeStatus)" }
                    }
                } else {
                    $changes += @{ Setting = "BitLocker $($blv.MountPoint)"; Before = "(not present)"; After = "$($blv.ProtectionStatus)" }
                }
            }
        }

        # Compare event log configuration
        if ($b1.EventLogs -or $b2.EventLogs) {
            $logs1 = @($b1.EventLogs)
            $logs2 = @($b2.EventLogs)
            foreach ($log2 in $logs2) {
                $log1 = $logs1 | Where-Object { $_.Name -eq $log2.Name }
                if ($null -ne $log1) {
                    if ("$($log1.MaxSizeBytes)" -ne "$($log2.MaxSizeBytes)") {
                        $changes += @{ Setting = "$($log2.Name) Log MaxSize"; Before = "$($log1.MaxSizeBytes)"; After = "$($log2.MaxSizeBytes)" }
                    }
                    if ("$($log1.LogMode)" -ne "$($log2.LogMode)") {
                        $changes += @{ Setting = "$($log2.Name) Log Mode"; Before = "$($log1.LogMode)"; After = "$($log2.LogMode)" }
                    }
                }
            }
        }

        # Compare time sync source
        if ($b1.TimeSync -and $b2.TimeSync) {
            $ntp1 = "$($b1.TimeSync.NTPSource)"
            $ntp2 = "$($b2.TimeSync.NTPSource)"
            if ($ntp1 -ne $ntp2) {
                $changes += @{ Setting = "NTP Source"; Before = $ntp1; After = $ntp2 }
            }
        }

        # Compare adapter link speeds
        if ($b1.NetworkAdapters -and $b2.NetworkAdapters) {
            foreach ($a2 in @($b2.NetworkAdapters)) {
                $a1 = @($b1.NetworkAdapters) | Where-Object { $_.Name -eq $a2.Name }
                if ($null -ne $a1) {
                    if ("$($a1.LinkSpeed)" -ne "$($a2.LinkSpeed)") {
                        $changes += @{ Setting = "$($a2.Name) LinkSpeed"; Before = "$($a1.LinkSpeed)"; After = "$($a2.LinkSpeed)" }
                    }
                }
            }
        }

        # Compare VM switch teaming
        if ($b1.VMSwitches -and $b2.VMSwitches) {
            foreach ($sw2 in @($b2.VMSwitches)) {
                $sw1 = @($b1.VMSwitches) | Where-Object { $_.Name -eq $sw2.Name }
                if ($null -ne $sw1) {
                    $team1 = if ($sw1.TeamNicNames) { ($sw1.TeamNicNames -join ", ") } else { "" }
                    $team2 = if ($sw2.TeamNicNames) { ($sw2.TeamNicNames -join ", ") } else { "" }
                    if ($team1 -ne $team2) {
                        $changes += @{ Setting = "vSwitch $($sw2.Name) Team"; Before = $team1; After = $team2 }
                    }
                    if ("$($sw1.LoadBalancingAlgorithm)" -ne "$($sw2.LoadBalancingAlgorithm)") {
                        $changes += @{ Setting = "vSwitch $($sw2.Name) LB"; Before = "$($sw1.LoadBalancingAlgorithm)"; After = "$($sw2.LoadBalancingAlgorithm)" }
                    }
                } else {
                    $changes += @{ Setting = "vSwitch $($sw2.Name)"; Before = "(not present)"; After = "Added ($($sw2.Type))" }
                }
            }
        }

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
    $baselines = @(Get-DriftBaselines)
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
    $sortedBaselines = @($baselines | Sort-Object { $_.CapturedAt })

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
        Write-OutputColor "  [B] ◄ Back" -color "Info"
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
                $navResult = Test-NavigationCommand -UserInput $desc
                if ($navResult.ShouldReturn) { continue }
                $path = Save-DriftBaseline -Description $desc
                if ($path) {
                    Write-OutputColor "  Baseline saved: $path" -color "Success"
                }
                Write-PressEnter
            }
            "3" {
                $baselines = @(Get-DriftBaselines)
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
                $baselines = @(Get-DriftBaselines)
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
                $navResult = Test-NavigationCommand -UserInput $first
                if ($navResult.ShouldReturn) { continue }
                $second = Read-Host "  Second baseline number"
                $navResult = Test-NavigationCommand -UserInput $second
                if ($navResult.ShouldReturn) { continue }
                if ($first -notmatch '^\d+$' -or $second -notmatch '^\d+$') {
                    Write-OutputColor "  Invalid input — enter numeric baseline numbers." -color "Error"
                    Write-PressEnter
                    continue
                }
                $fi = [int]$first - 1
                $si = [int]$second - 1
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
                    Write-OutputColor "  Invalid selection. Enter 1-$($baselines.Count)." -color "Error"
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
                Write-OutputColor "  Invalid choice. Enter 1-5 or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# ════════════════════════════════════════════════════════════════════════
# Server Inventory — non-interactive structured data for CLI/JSON output
# ════════════════════════════════════════════════════════════════════════
function Get-ServerInventory {
    Write-OutputColor "  Gathering server inventory..." -color "Info"

    $inventory = [ordered]@{
        Timestamp = (Get-Date).ToString('o')
        Hostname  = $env:COMPUTERNAME
    }

    # System info (batch CIM with timeout)
    $sysInfo = Invoke-WithTimeout -ScriptBlock {
        @{
            CS   = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
            OS   = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
            CPU  = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
            BIOS = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue
            MB   = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction SilentlyContinue
        }
    } -TimeoutSeconds 15 -Activity "Querying system info"

    if (-not $sysInfo.TimedOut) {
        $cs  = $sysInfo.Result.CS
        $os  = $sysInfo.Result.OS
        $cpu = $sysInfo.Result.CPU
        $bios = $sysInfo.Result.BIOS
        $mb   = $sysInfo.Result.MB

        $inventory.System = [ordered]@{
            Domain         = if ($cs) { $cs.Domain } else { '' }
            PartOfDomain   = if ($cs) { [bool]$cs.PartOfDomain } else { $false }
            Manufacturer   = if ($cs) { $cs.Manufacturer } else { '' }
            Model          = if ($cs) { $cs.Model } else { '' }
            SerialNumber   = if ($bios) { $bios.SerialNumber } else { '' }
            BIOSVersion    = if ($bios) { $bios.SMBIOSBIOSVersion } else { '' }
            Motherboard    = if ($mb) { "$($mb.Manufacturer) $($mb.Product)" } else { '' }
        }
        $inventory.OS = [ordered]@{
            Caption   = if ($os) { $os.Caption } else { '' }
            Version   = if ($os) { $os.Version } else { '' }
            Build     = if ($os) { $os.BuildNumber } else { '' }
            Arch      = if ($os) { $os.OSArchitecture } else { '' }
            InstallDate = if ($os -and $os.InstallDate) { $os.InstallDate.ToString('o') } else { '' }
            LastBoot    = if ($os -and $os.LastBootUpTime) { $os.LastBootUpTime.ToString('o') } else { '' }
        }
        $inventory.CPU = [ordered]@{
            Name           = if ($cpu) { $cpu.Name.Trim() } else { '' }
            Cores          = if ($cpu) { $cpu.NumberOfCores } else { 0 }
            LogicalCores   = if ($cpu) { $cpu.NumberOfLogicalProcessors } else { 0 }
        }
        $totalRAM = 0
        if ($cs) { $totalRAM = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) }
        $inventory.MemoryGB = $totalRAM
    } else {
        $inventory.System = @{ Error = 'CIM query timed out' }
        $inventory.OS = @{ Error = 'CIM query timed out' }
        $inventory.CPU = @{ Error = 'CIM query timed out' }
        $inventory.MemoryGB = 0
    }
    Write-OutputColor "  [+] System info" -color "Debug"

    # Timezone and power plan
    $inventory.Timezone = (Get-TimeZone).Id
    $inventory.PowerPlan = Get-CurrentPowerPlan

    # Licensing
    try {
        $lic = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationId='$($script:WindowsLicensingAppId)' AND LicenseStatus=1" -ErrorAction SilentlyContinue | Select-Object -First 1
        $inventory.Licensing = [ordered]@{
            Activated   = ($null -ne $lic)
            Edition     = if ($lic) { $lic.Name } else { '' }
            Channel     = if ($lic) { $lic.Description } else { '' }
        }
    } catch {
        $inventory.Licensing = @{ Activated = $false; Error = $_.Exception.Message }
    }
    Write-OutputColor "  [+] Licensing" -color "Debug"

    # Network adapters
    $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue)
    $adapterList = @()
    foreach ($a in $adapters) {
        $ips = @(Get-NetIPAddress -InterfaceIndex $a.ifIndex -ErrorAction SilentlyContinue | Where-Object { $_.AddressFamily -eq 'IPv4' })
        $dns = @(Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ServerAddresses -ErrorAction SilentlyContinue)
        $adapterList += [ordered]@{
            Name        = $a.Name
            Description = $a.InterfaceDescription
            Status      = $a.Status
            MacAddress  = $a.MacAddress
            Speed       = if ($a.LinkSpeed) { $a.LinkSpeed } else { '' }
            IPv4        = @($ips | ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" })
            DNS         = @($dns)
            VLAN        = if ($a.VlanID) { $a.VlanID } else { $null }
        }
    }
    $inventory.NetworkAdapters = $adapterList
    Write-OutputColor "  [+] Network adapters ($($adapterList.Count))" -color "Debug"

    # Disks and volumes
    $diskInfo = Invoke-WithTimeout -ScriptBlock {
        @{
            Disks   = @(Get-Disk -ErrorAction SilentlyContinue)
            Volumes = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter })
        }
    } -TimeoutSeconds 10 -Activity "Querying storage"

    if (-not $diskInfo.TimedOut) {
        $diskList = @()
        foreach ($d in $diskInfo.Result.Disks) {
            $diskList += [ordered]@{
                Number       = $d.Number
                FriendlyName = $d.FriendlyName
                SizeGB       = [math]::Round($d.Size / 1GB, 1)
                PartStyle    = "$($d.PartitionStyle)"
                BusType      = "$($d.BusType)"
                Status       = "$($d.OperationalStatus)"
            }
        }
        $inventory.Disks = $diskList

        $volList = @()
        foreach ($v in $diskInfo.Result.Volumes) {
            $volList += [ordered]@{
                Drive      = "$($v.DriveLetter):"
                Label      = if ($v.FileSystemLabel) { $v.FileSystemLabel } else { '' }
                FileSystem = if ($v.FileSystem) { $v.FileSystem } else { '' }
                SizeGB     = [math]::Round($v.Size / 1GB, 1)
                FreeGB     = [math]::Round($v.SizeRemaining / 1GB, 1)
            }
        }
        $inventory.Volumes = $volList
    } else {
        $inventory.Disks = @()
        $inventory.Volumes = @()
    }
    Write-OutputColor "  [+] Storage" -color "Debug"

    # Installed roles/features
    $inventory.Roles = [ordered]@{
        IsServer           = Test-WindowsServer
        HyperV             = Test-HyperVInstalled
        FailoverClustering = Test-FailoverClusteringInstalled
        MPIO               = Test-MPIOInstalled
    }

    # Additional role detection via Get-WindowsFeature (Server only)
    if ($inventory.Roles.IsServer) {
        try {
            $installedFeatures = @(Get-WindowsFeature -ErrorAction SilentlyContinue | Where-Object { $_.Installed })
            $inventory.InstalledFeatures = @($installedFeatures | ForEach-Object { $_.Name })
        } catch {
            $inventory.InstalledFeatures = @()
        }
    }
    Write-OutputColor "  [+] Roles and features" -color "Debug"

    # Remote access
    $inventory.RemoteAccess = [ordered]@{
        RDP   = Get-RDPState
        WinRM = Get-WinRMState
    }

    # Firewall
    $inventory.Firewall = Get-FirewallState

    # Uptime
    $lastBoot = $null
    if ($inventory.OS -and $inventory.OS.LastBoot -and $inventory.OS.LastBoot -ne '') {
        try { $lastBoot = [datetime]$inventory.OS.LastBoot } catch {}
    }
    if ($lastBoot) {
        $inventory.UptimeDays = [math]::Round(((Get-Date) - $lastBoot).TotalDays, 1)
    } else {
        $inventory.UptimeDays = $null
    }

    Write-OutputColor "  Inventory complete." -color "Success"
    return $inventory
}

# Register a Windows Scheduled Task to run Export on a recurring schedule
function Register-ScheduledExport {
    param(
        [Parameter(Mandatory=$true)]
        [string]$OutputDir,
        [Parameter(Mandatory=$true)]
        [ValidateSet('Hourly', 'Daily', 'Weekly')]
        [string]$Frequency,
        [string]$Sections,
        [string]$OutputFormat = 'JSON'
    )

    $taskName = "$($script:ToolName)-ScheduledExport"
    $taskPath = "\$($script:ToolName)\"

    # Validate output directory
    if (-not (Test-Path -LiteralPath $OutputDir -PathType Container)) {
        try {
            New-Item -Path $OutputDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-OutputColor "  Created output directory: $OutputDir" -color "Success"
        } catch {
            Write-OutputColor "  ERROR: Cannot create output directory: $OutputDir" -color "Error"
            return $false
        }
    }

    # Resolve the script path for the scheduled task action
    $exePath = $script:ScriptPath
    if (-not $exePath) {
        Write-OutputColor "  ERROR: Cannot determine script path for scheduled task." -color "Error"
        return $false
    }

    # Build the argument string
    $configArg = $OutputDir
    if ($Sections) { $configArg = "$OutputDir|$Sections" }
    $isExe = $exePath -match '\.exe$'

    if ($isExe) {
        $actionExe = $exePath
        $actionArgs = "-Action Export -Config `"$configArg`" -OutputFormat $OutputFormat -Silent"
    } else {
        $actionExe = "powershell.exe"
        $actionArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$exePath`" -Action Export -Config `"$configArg`" -OutputFormat $OutputFormat -Silent"
    }

    # Build the trigger based on frequency
    switch ($Frequency) {
        'Hourly' {
            $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Hours 1)
        }
        'Daily' {
            $trigger = New-ScheduledTaskTrigger -Daily -At "02:00AM" -DaysInterval 1
        }
        'Weekly' {
            $trigger = New-ScheduledTaskTrigger -Weekly -At "02:00AM" -DaysOfWeek Monday
        }
    }

    $action = New-ScheduledTaskAction -Execute $actionExe -Argument $actionArgs
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1)

    # Remove existing task if present
    try {
        $existing = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
        if ($null -ne $existing) {
            Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false -ErrorAction Stop
            Write-OutputColor "  Removed existing scheduled export task." -color "Info"
        }
    } catch { }

    try {
        Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "$($script:ToolFullName) Scheduled Export ($Frequency) - Output: $OutputDir" -ErrorAction Stop | Out-Null
        Write-OutputColor "  Scheduled export task registered successfully." -color "Success"
        Write-OutputColor "  Task:      $taskPath$taskName" -color "Info"
        Write-OutputColor "  Frequency: $Frequency" -color "Info"
        Write-OutputColor "  Output:    $OutputDir" -color "Info"
        if ($Sections) {
            Write-OutputColor "  Sections:  $Sections" -color "Info"
        }
        return $true
    } catch {
        Write-OutputColor "  ERROR: Failed to register scheduled task: $($_.Exception.Message)" -color "Error"
        return $false
    }
}

# Unregister the scheduled export task
function Unregister-ScheduledExport {
    $taskName = "$($script:ToolName)-ScheduledExport"
    $taskPath = "\$($script:ToolName)\"

    try {
        $existing = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
        if ($null -eq $existing) {
            Write-OutputColor "  No scheduled export task found." -color "Warning"
            return $false
        }
        Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false -ErrorAction Stop
        Write-OutputColor "  Scheduled export task removed successfully." -color "Success"
        return $true
    } catch {
        Write-OutputColor "  ERROR: Failed to remove scheduled task: $($_.Exception.Message)" -color "Error"
        return $false
    }
}

# Get the status of the scheduled export task
function Get-ScheduledExportStatus {
    $taskName = "$($script:ToolName)-ScheduledExport"
    $taskPath = "\$($script:ToolName)\"

    try {
        $task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
        if ($null -eq $task) {
            return @{
                Registered = $false
                TaskName   = $taskName
            }
        }

        $taskInfo = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        $lastRun = if ($null -ne $taskInfo -and $null -ne $taskInfo.LastRunTime -and $taskInfo.LastRunTime.Year -gt 1999) {
            $taskInfo.LastRunTime.ToString("yyyy-MM-ddTHH:mm:ss")
        } else { $null }
        $nextRun = if ($null -ne $taskInfo -and $null -ne $taskInfo.NextRunTime -and $taskInfo.NextRunTime.Year -gt 1999) {
            $taskInfo.NextRunTime.ToString("yyyy-MM-ddTHH:mm:ss")
        } else { $null }
        $lastResult = if ($null -ne $taskInfo) { $taskInfo.LastTaskResult } else { $null }

        return @{
            Registered  = $true
            TaskName    = "$taskPath$taskName"
            State       = "$($task.State)"
            Description = $task.Description
            LastRun     = $lastRun
            LastResult  = $lastResult
            NextRun     = $nextRun
        }
    } catch {
        return @{
            Registered = $false
            TaskName   = $taskName
            Error      = $_.Exception.Message
        }
    }
}

# Rotate export files - keep only the N most recent
function Invoke-ExportRotation {
    param(
        [Parameter(Mandatory=$true)]
        [string]$OutputDir,
        [int]$KeepCount = 30
    )

    if (-not (Test-Path -LiteralPath $OutputDir -PathType Container)) {
        return @{ Removed = 0; Kept = 0 }
    }

    $files = @(Get-ChildItem -Path $OutputDir -Filter "*.json" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    $removed = 0
    if ($files.Count -gt $KeepCount) {
        $toRemove = @($files | Select-Object -Skip $KeepCount)
        foreach ($f in $toRemove) {
            try {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                $removed++
            } catch { }
        }
    }

    return @{
        Removed = $removed
        Kept    = [math]::Min($files.Count, $KeepCount)
    }
}

# Default thresholds for Watch action (used when no -Config is provided)
function Get-DefaultWatchThresholds {
    return @{
        CPU          = @{ MaxPercent = 90 }
        Memory       = @{ MaxPercent = 90 }
        Disk         = @{ MaxUsedPercent = 95 }
        Uptime       = @{ MaxDays = 60 }
        Certificates = @{ MinDaysToExpiry = 7 }
        Services     = @{ RequireRunning = @() }
        Events       = @{ MaxCriticalCount = 0; HoursBack = 24 }
    }
}

# Run threshold checks and return structured results
function Test-WatchThresholds {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Thresholds
    )

    $checks = [System.Collections.Generic.List[object]]::new()

    # CPU check
    if ($Thresholds.CPU -and $null -ne $Thresholds.CPU.MaxPercent) {
        $cpuVal = $null
        try {
            $cpuCim = Invoke-WithTimeout -ScriptBlock {
                (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Measure-Object -Property LoadPercentage -Average).Average
            } -TimeoutSeconds $script:Timeouts.CIMQuery -Activity "CPU check"
            if (-not $cpuCim.TimedOut -and $null -ne $cpuCim.Result) {
                $cpuVal = [math]::Round($cpuCim.Result, 1)
            }
        } catch { }
        if ($null -ne $cpuVal) {
            $status = if ($cpuVal -gt $Thresholds.CPU.MaxPercent) { "ALERT" } else { "OK" }
            $checks.Add(@{ Category = "CPU"; Check = "CPU usage"; Value = $cpuVal; Threshold = $Thresholds.CPU.MaxPercent; Unit = "%"; Status = $status })
        }
    }

    # Query Win32_OperatingSystem once for memory + uptime checks (avoid duplicate CIM query)
    $watchOS = $null
    if (($Thresholds.Memory -and $null -ne $Thresholds.Memory.MaxPercent) -or ($Thresholds.Uptime -and $null -ne $Thresholds.Uptime.MaxDays)) {
        try {
            $osCim = Invoke-WithTimeout -ScriptBlock {
                Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
            } -TimeoutSeconds $script:Timeouts.CIMQuery -Activity "Memory/uptime check"
            if (-not $osCim.TimedOut) { $watchOS = $osCim.Result }
        } catch { }
    }

    # Memory check
    if ($Thresholds.Memory -and $null -ne $Thresholds.Memory.MaxPercent) {
        $memVal = $null
        if ($null -ne $watchOS) {
            $totalMB = $watchOS.TotalVisibleMemorySize / 1024
            $freeMB = $watchOS.FreePhysicalMemory / 1024
            if ($totalMB -gt 0) {
                $memVal = [math]::Round((($totalMB - $freeMB) / $totalMB) * 100, 1)
            }
        }
        if ($null -ne $memVal) {
            $status = if ($memVal -gt $Thresholds.Memory.MaxPercent) { "ALERT" } else { "OK" }
            $checks.Add(@{ Category = "Memory"; Check = "Memory usage"; Value = $memVal; Threshold = $Thresholds.Memory.MaxPercent; Unit = "%"; Status = $status })
        }
    }

    # Disk check
    if ($Thresholds.Disk -and $null -ne $Thresholds.Disk.MaxUsedPercent) {
        try {
            $diskCim = Invoke-WithTimeout -ScriptBlock {
                Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
            } -TimeoutSeconds $script:Timeouts.CIMQuery -Activity "Disk check"
            if (-not $diskCim.TimedOut -and $null -ne $diskCim.Result) {
                foreach ($disk in @($diskCim.Result)) {
                    if ($disk.Size -gt 0) {
                        $usedPct = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1)
                        $status = if ($usedPct -gt $Thresholds.Disk.MaxUsedPercent) { "ALERT" } else { "OK" }
                        $checks.Add(@{ Category = "Disk"; Check = "$($disk.DeviceID) usage"; Value = $usedPct; Threshold = $Thresholds.Disk.MaxUsedPercent; Unit = "%"; Status = $status })
                    }
                }
            }
        } catch { }
    }

    # Uptime check (reuses $watchOS from memory check)
    if ($Thresholds.Uptime -and $null -ne $Thresholds.Uptime.MaxDays) {
        if ($null -ne $watchOS -and $null -ne $watchOS.LastBootUpTime) {
            $uptimeDays = [math]::Round(((Get-Date) - $watchOS.LastBootUpTime).TotalDays, 1)
            $status = if ($uptimeDays -gt $Thresholds.Uptime.MaxDays) { "ALERT" } else { "OK" }
            $checks.Add(@{ Category = "Uptime"; Check = "Days since reboot"; Value = $uptimeDays; Threshold = $Thresholds.Uptime.MaxDays; Unit = "days"; Status = $status })
        }
    }

    # Certificate check
    if ($Thresholds.Certificates -and $null -ne $Thresholds.Certificates.MinDaysToExpiry) {
        try {
            $stores = @('My', 'WebHosting', 'Remote Desktop')
            $minDays = $Thresholds.Certificates.MinDaysToExpiry
            $expiringCerts = 0
            foreach ($store in $stores) {
                $certs = @(Get-ChildItem "Cert:\LocalMachine\$store" -ErrorAction SilentlyContinue | Where-Object { $_.NotAfter })
                foreach ($cert in $certs) {
                    $daysLeft = [math]::Round(($cert.NotAfter - (Get-Date)).TotalDays, 0)
                    if ($daysLeft -le $minDays) { $expiringCerts++ }
                }
            }
            $status = if ($expiringCerts -gt 0) { "ALERT" } else { "OK" }
            $checks.Add(@{ Category = "Certificates"; Check = "Certs expiring within $minDays days"; Value = $expiringCerts; Threshold = 0; Unit = "certs"; Status = $status })
        } catch { }
    }

    # Service check
    if ($Thresholds.Services -and $Thresholds.Services.RequireRunning -and @($Thresholds.Services.RequireRunning).Count -gt 0) {
        $failedSvcs = [System.Collections.Generic.List[string]]::new()
        foreach ($svcName in @($Thresholds.Services.RequireRunning)) {
            try {
                $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                if ($null -ne $svc -and $svc.Status -ne 'Running') {
                    $failedSvcs.Add($svcName)
                }
            } catch { }
        }
        $status = if ($failedSvcs.Count -gt 0) { "ALERT" } else { "OK" }
        $detail = if ($failedSvcs.Count -gt 0) { $failedSvcs -join ', ' } else { "all running" }
        $checks.Add(@{ Category = "Services"; Check = "Required services"; Value = $failedSvcs.Count; Threshold = 0; Unit = "stopped"; Status = $status; Detail = $detail })
    }

    # Event check
    if ($Thresholds.Events -and $null -ne $Thresholds.Events.MaxCriticalCount) {
        $hoursBack = if ($null -ne $Thresholds.Events.HoursBack) { $Thresholds.Events.HoursBack } else { 24 }
        $startTime = (Get-Date).AddHours(-$hoursBack)
        $critCount = 0
        try {
            $critEvents = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1; StartTime = $startTime } -MaxEvents 100 -ErrorAction SilentlyContinue)
            $critCount += $critEvents.Count
            $critEventsApp = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Level = 1; StartTime = $startTime } -MaxEvents 100 -ErrorAction SilentlyContinue)
            $critCount += $critEventsApp.Count
        } catch { }
        $status = if ($critCount -gt $Thresholds.Events.MaxCriticalCount) { "ALERT" } else { "OK" }
        $checks.Add(@{ Category = "Events"; Check = "Critical events (${hoursBack}h)"; Value = $critCount; Threshold = $Thresholds.Events.MaxCriticalCount; Unit = "events"; Status = $status })
    }

    return @($checks)
}

# Save a baseline Export to a directory with hostname-tagged filename
function Save-ExportBaseline {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BaselineDir,
        [Parameter(Mandatory=$true)]
        [hashtable]$ExportData
    )

    if (-not (Test-Path -LiteralPath $BaselineDir -PathType Container)) {
        try {
            New-Item -Path $BaselineDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        } catch {
            Write-OutputColor "  ERROR: Cannot create baseline directory: $BaselineDir" -color "Error"
            return $null
        }
    }

    $hostname = if ($ExportData.Hostname) { $ExportData.Hostname } else { $env:COMPUTERNAME }
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $fileName = "${hostname}_baseline_${timestamp}.json"
    $filePath = Join-Path $BaselineDir $fileName

    # Add baseline metadata
    $ExportData['IsBaseline'] = $true
    $ExportData['BaselineTimestamp'] = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")

    try {
        $ExportData | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $filePath -Encoding UTF8 -Force
        return $filePath
    } catch {
        Write-OutputColor "  ERROR: Failed to save baseline: $($_.Exception.Message)" -color "Error"
        return $null
    }
}

# Get the most recent baseline for a hostname from a directory
function Get-LatestBaseline {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BaselineDir,
        [string]$Hostname
    )

    if (-not (Test-Path -LiteralPath $BaselineDir -PathType Container)) {
        return $null
    }

    $pattern = if ($Hostname) { "${Hostname}_baseline_*.json" } else { "*_baseline_*.json" }
    $files = @(Get-ChildItem -Path $BaselineDir -Filter $pattern -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)

    if ($files.Count -eq 0) { return $null }
    return $files[0].FullName
}

# Send alert notification via webhook (Slack, Teams, or generic JSON POST)
function Send-AlertWebhook {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Config,
        [Parameter(Mandatory=$true)]
        [hashtable]$AlertData
    )

    if (-not $Config.URL) {
        return @{ Channel = 'Webhook'; Success = $false; Error = 'No URL configured' }
    }

    try {
        $template = if ($Config.BodyTemplate) { $Config.BodyTemplate } else { 'payload' }
        $hostname = if ($AlertData.Hostname) { $AlertData.Hostname } else { $env:COMPUTERNAME }
        $summary = "RackStack Alert on $hostname — $($AlertData.AlertCount) alert(s) detected"

        switch ($template) {
            'slack' {
                $body = @{ text = $summary } | ConvertTo-Json -Depth 5
            }
            'teams' {
                $body = @{
                    '@type' = 'MessageCard'
                    summary = $summary
                    themeColor = 'FF0000'
                    title = $summary
                    text = "Action: $($AlertData.Action)`nTimestamp: $($AlertData.Timestamp)`nAlerts: $($AlertData.AlertCount)"
                } | ConvertTo-Json -Depth 5
            }
            default {
                $body = $AlertData | ConvertTo-Json -Depth 10
            }
        }

        $params = @{
            Uri         = $Config.URL
            Method      = if ($Config.Method) { $Config.Method } else { 'POST' }
            Body        = $body
            ContentType = 'application/json'
            ErrorAction = 'Stop'
        }
        if ($Config.Headers) {
            $headers = @{}
            foreach ($prop in $Config.Headers.PSObject.Properties) { $headers[$prop.Name] = $prop.Value }
            $params['Headers'] = $headers
        }

        Invoke-RestMethod @params | Out-Null
        return @{ Channel = 'Webhook'; Success = $true; Error = $null }
    } catch {
        return @{ Channel = 'Webhook'; Success = $false; Error = $_.Exception.Message }
    }
}

# Send alert notification via email (SMTP)
function Send-AlertEmail {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Config,
        [Parameter(Mandatory=$true)]
        [hashtable]$AlertData
    )

    if (-not $Config.SmtpServer -or -not $Config.To -or -not $Config.From) {
        return @{ Channel = 'Email'; Success = $false; Error = 'Missing SmtpServer, To, or From' }
    }

    try {
        $hostname = if ($AlertData.Hostname) { $AlertData.Hostname } else { $env:COMPUTERNAME }
        $subject = "RackStack Alert: $hostname — $($AlertData.AlertCount) alert(s)"
        $bodyLines = @(
            "RackStack Alert Notification"
            "============================"
            ""
            "Hostname:  $hostname"
            "Action:    $($AlertData.Action)"
            "Timestamp: $($AlertData.Timestamp)"
            "Alerts:    $($AlertData.AlertCount)"
            ""
        )
        if ($AlertData.Checks) {
            $bodyLines += "Check Details:"
            $bodyLines += "─────────────"
            foreach ($chk in $AlertData.Checks) {
                $bodyLines += "  $($chk.Check): $($chk.Value) $($chk.Unit) [$($chk.Status)]"
            }
        }
        if ($AlertData.TotalChanges) {
            $bodyLines += "Changes:   $($AlertData.TotalChanges) across $($AlertData.ChangedSections -join ', ')"
        }

        $mailParams = @{
            From       = $Config.From
            To         = @($Config.To)
            Subject    = $subject
            Body       = ($bodyLines -join "`r`n")
            SmtpServer = $Config.SmtpServer
            ErrorAction = 'Stop'
        }
        if ($Config.SmtpPort) { $mailParams['Port'] = $Config.SmtpPort }
        if ($Config.UseSsl) { $mailParams['UseSsl'] = $true }

        Send-MailMessage @mailParams
        return @{ Channel = 'Email'; Success = $true; Error = $null }
    } catch {
        return @{ Channel = 'Email'; Success = $false; Error = $_.Exception.Message }
    }
}

# Send alert notification to Windows Event Log
function Send-AlertEventLog {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Config,
        [Parameter(Mandatory=$true)]
        [hashtable]$AlertData
    )

    try {
        $logName = if ($Config.LogName) { $Config.LogName } else { 'Application' }
        $source = if ($Config.Source) { $Config.Source } else { 'RackStack' }

        # Create event source if it doesn't exist
        if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
            New-EventLog -LogName $logName -Source $source -ErrorAction Stop
        }

        $hostname = if ($AlertData.Hostname) { $AlertData.Hostname } else { $env:COMPUTERNAME }
        $message = "RackStack Alert on $hostname`r`nAction: $($AlertData.Action)`r`nAlerts: $($AlertData.AlertCount)`r`nTimestamp: $($AlertData.Timestamp)"

        $entryType = if ($AlertData.AlertCount -gt 0) { 'Warning' } else { 'Information' }
        Write-EventLog -LogName $logName -Source $source -EventId 1000 -EntryType $entryType -Message $message -ErrorAction Stop

        return @{ Channel = 'EventLog'; Success = $true; Error = $null }
    } catch {
        return @{ Channel = 'EventLog'; Success = $false; Error = $_.Exception.Message }
    }
}

# Dispatch alert to all enabled channels
function Invoke-AlertDispatch {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$AlertConfig,
        [Parameter(Mandatory=$true)]
        [hashtable]$AlertData
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $channels = $AlertConfig.Channels

    if ($null -ne $channels.Webhook -and $channels.Webhook.Enabled) {
        $whConfig = @{}
        foreach ($prop in $channels.Webhook.PSObject.Properties) { $whConfig[$prop.Name] = $prop.Value }
        $results.Add((Send-AlertWebhook -Config $whConfig -AlertData $AlertData))
    }
    if ($null -ne $channels.Email -and $channels.Email.Enabled) {
        $emConfig = @{}
        foreach ($prop in $channels.Email.PSObject.Properties) { $emConfig[$prop.Name] = $prop.Value }
        $results.Add((Send-AlertEmail -Config $emConfig -AlertData $AlertData))
    }
    if ($null -ne $channels.EventLog -and $channels.EventLog.Enabled) {
        $elConfig = @{}
        foreach ($prop in $channels.EventLog.PSObject.Properties) { $elConfig[$prop.Name] = $prop.Value }
        $results.Add((Send-AlertEventLog -Config $elConfig -AlertData $AlertData))
    }

    $successCount = @($results | Where-Object { $_.Success }).Count
    $failCount = @($results | Where-Object { -not $_.Success }).Count

    return @{
        Dispatched   = $results.Count
        Succeeded    = $successCount
        Failed       = $failCount
        ChannelResults = @($results)
    }
}

# Resolve fleet targets from array, .txt file, or .json file
function Get-FleetTargets {
    param(
        [Parameter(Mandatory=$true)]
        $Targets
    )

    # If already an array, return validated
    if ($Targets -is [array]) {
        return @($Targets | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
    }

    # If a string path, load from file
    $targetPath = "$Targets"
    if (-not (Test-Path -LiteralPath $targetPath)) {
        Write-OutputColor "  ERROR: Targets file not found: $targetPath" -color "Error"
        return $null
    }

    if ($targetPath -match '\.json$') {
        try {
            $content = Get-Content -LiteralPath $targetPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            return @($content | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { "$_".Trim() })
        } catch {
            Write-OutputColor "  ERROR: Failed to parse targets JSON: $($_.Exception.Message)" -color "Error"
            return $null
        }
    } else {
        # Treat as .txt — one hostname per line
        try {
            $lines = @(Get-Content -LiteralPath $targetPath -ErrorAction Stop)
            return @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() })
        } catch {
            Write-OutputColor "  ERROR: Failed to read targets file: $($_.Exception.Message)" -color "Error"
            return $null
        }
    }
}

# Execute a RackStack action against multiple remote hosts via WinRM
function Invoke-FleetAction {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Targets,
        [Parameter(Mandatory=$true)]
        [string]$Action,
        [string]$ActionConfig,
        [string]$ActionTier,
        [int]$Parallel = 5,
        [int]$TimeoutSeconds = 300
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $exePath = $script:ScriptPath
    if (-not $exePath) { $exePath = "RackStack.exe" }

    $scriptBlock = {
        param($rackExe, $rackAction, $rackConfig, $rackTier)
        $cmdArgs = @($rackExe, '-Action', $rackAction, '-OutputFormat', 'JSON', '-Silent')
        if ($rackConfig) { $cmdArgs += @('-Config', $rackConfig) }
        if ($rackTier) { $cmdArgs += @('-Tier', $rackTier) }
        try {
            $output = & $cmdArgs[0] $cmdArgs[1..($cmdArgs.Count-1)] 2>&1
            return @{ Output = ($output -join "`n"); ExitCode = $LASTEXITCODE }
        } catch {
            return @{ Output = $_.Exception.Message; ExitCode = 99 }
        }
    }

    # Process in batches for throttling
    $batchSize = if ($Parallel -gt 0) { $Parallel } else { 5 }
    for ($i = 0; $i -lt $Targets.Count; $i += $batchSize) {
        $batch = @($Targets[$i..[math]::Min($i + $batchSize - 1, $Targets.Count - 1)])
        $jobs = @()

        foreach ($target in $batch) {
            $startTime = Get-Date
            try {
                $job = Invoke-Command -ComputerName $target -ScriptBlock $scriptBlock `
                    -ArgumentList $exePath, $Action, $ActionConfig, $ActionTier `
                    -AsJob -ErrorAction Stop
                $jobs += @{ Job = $job; Target = $target; StartTime = $startTime }
            } catch {
                $results.Add(@{
                    Hostname = $target
                    Status   = 'Failed'
                    ExitCode = 99
                    Duration = 0
                    Error    = $_.Exception.Message
                    Result   = $null
                })
            }
        }

        # Wait for batch jobs
        foreach ($entry in $jobs) {
            $completed = $entry.Job | Wait-Job -Timeout $TimeoutSeconds -ErrorAction SilentlyContinue
            $duration = [math]::Round(((Get-Date) - $entry.StartTime).TotalSeconds, 1)

            if ($null -eq $completed -or $entry.Job.State -eq 'Running') {
                $entry.Job | Stop-Job -ErrorAction SilentlyContinue
                $entry.Job | Remove-Job -Force -ErrorAction SilentlyContinue
                $results.Add(@{
                    Hostname = $entry.Target
                    Status   = 'Timeout'
                    ExitCode = 99
                    Duration = $duration
                    Error    = "Timed out after ${TimeoutSeconds}s"
                    Result   = $null
                })
            } else {
                try {
                    $jobResult = $entry.Job | Receive-Job -ErrorAction Stop
                    $parsed = $null
                    if ($jobResult.Output) {
                        try { $parsed = $jobResult.Output | ConvertFrom-Json -ErrorAction Stop } catch { }
                    }
                    $exitCode = if ($null -ne $jobResult.ExitCode) { $jobResult.ExitCode } else { 0 }
                    $results.Add(@{
                        Hostname = $entry.Target
                        Status   = if ($exitCode -eq 0) { 'Success' } else { 'Failed' }
                        ExitCode = $exitCode
                        Duration = $duration
                        Error    = $null
                        Result   = $parsed
                    })
                } catch {
                    $results.Add(@{
                        Hostname = $entry.Target
                        Status   = 'Failed'
                        ExitCode = 99
                        Duration = $duration
                        Error    = $_.Exception.Message
                        Result   = $null
                    })
                }
                $entry.Job | Remove-Job -Force -ErrorAction SilentlyContinue
            }
        }
    }

    return @($results)
}

# Save fleet scan results to individual JSON files and summary
function Save-FleetResults {
    param(
        [Parameter(Mandatory=$true)]
        [string]$OutputDir,
        [Parameter(Mandatory=$true)]
        [array]$Results,
        [string]$Action
    )

    if (-not (Test-Path -LiteralPath $OutputDir -PathType Container)) {
        try {
            New-Item -Path $OutputDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        } catch {
            Write-OutputColor "  ERROR: Cannot create output directory: $OutputDir" -color "Error"
            return $null
        }
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

    # Save per-host results
    foreach ($r in $Results) {
        if ($null -ne $r.Result) {
            $hostFile = Join-Path $OutputDir "$($r.Hostname)_${Action}_${timestamp}.json"
            $r.Result | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $hostFile -Encoding UTF8 -Force
        }
    }

    # Save fleet summary
    $summaryFile = Join-Path $OutputDir "fleet_${Action}_${timestamp}.json"
    $summary = @{
        Action    = $Action
        Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        Total     = $Results.Count
        Succeeded = @($Results | Where-Object { $_.Status -eq 'Success' }).Count
        Failed    = @($Results | Where-Object { $_.Status -eq 'Failed' }).Count
        TimedOut  = @($Results | Where-Object { $_.Status -eq 'Timeout' }).Count
        Results   = $Results
    }
    $summary | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $summaryFile -Encoding UTF8 -Force

    return $summaryFile
}
#endregion