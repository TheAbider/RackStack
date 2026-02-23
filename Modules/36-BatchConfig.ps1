#region ===== BATCH CONFIG GENERATOR =====
# Function to generate a batch_config.json template
function New-BatchConfigTemplate {
    Clear-Host
    Write-CenteredOutput "Generate Batch Config Template" -color "Info"

    Write-OutputColor "This will create a batch_config.json template file." -color "Info"
    Write-OutputColor "Edit the file with your settings, then place it next to the script." -color "Info"
    Write-OutputColor "The script will auto-run those settings on next launch." -color "Info"
    Write-OutputColor "" -color "Info"

    # Build the config template
    $configTemplate = @"
{
    "_README": "$($script:ToolFullName) - Batch Config Template v$($script:ScriptVersion)",
    "_INSTRUCTIONS": [
        "========================================================================",
        "                    BATCH CONFIGURATION INSTRUCTIONS                    ",
        "========================================================================",
        "",
        "1. Edit this file with your desired settings",
        "2. Save the file as 'batch_config.json' in the same folder as the script",
        "3. Run the script - it will automatically apply these settings",
        "4. Delete or rename this file after use to return to interactive mode",
        "",
        "RULES:",
        "- Set any value to null to skip that step",
        "- true/false values enable or disable that feature",
        "- Fields starting with '_' are help text and are ignored by the script",
        "",
        "FOR HYPER-V HOSTS:",
        "- Install Hyper-V and build the SET via GUI first!",
        "  SET must be built manually because NIC names vary per server.",
        "  Once SET is built, use this for IP/DNS/domain/everything else.",
        "",
        "FOR VMs:",
        "- This config works great for full unattended automation",
        "- Set ConfigType to 'VM' and fill in all fields",
        "",
        "========================================================================"
    ],

    "ConfigType": "VM",
    "_ConfigType_Help": "'VM' for virtual machines, 'HOST' for Hyper-V hosts. Host mode skips network config (build SET via GUI).",

    "Hostname": "123456-FS1",
    "_Hostname_Help": "NetBIOS name, max 15 chars. Format: SITENUMBER-ROLE (e.g., 123456-DC1, 123456-FS1, 999999-SQL1)",

    "AdapterName": "Ethernet",
    "_AdapterName_Help": "Network adapter to configure. VMs: usually 'Ethernet'. Hosts: 'vEthernet (Management)'. Run Get-NetAdapter to check.",

    "IPAddress": "10.0.1.100",
    "_IPAddress_Help": "Static IPv4 address for the management NIC",

    "SubnetCIDR": 24,
    "_SubnetCIDR_Help": "Subnet in CIDR notation: 24 = 255.255.255.0, 22 = 255.255.252.0, 16 = 255.255.0.0",

    "Gateway": "10.0.1.1",
    "_Gateway_Help": "Default gateway IP address",

    "DNS1": "8.8.8.8",
    "_DNS1_Help": "Primary DNS server",

    "DNS2": "8.8.4.4",
    "_DNS2_Help": "Secondary DNS server",

    "DomainName": "$domain",
    "_DomainName_Help": "Active Directory domain to join. Set to null or empty to skip. Will prompt for credentials at runtime.",

    "Timezone": "Pacific Standard Time",
    "_Timezone_Help": "Timezone ID: 'Pacific Standard Time', 'Mountain Standard Time', 'Central Standard Time', 'Eastern Standard Time'",

    "EnableRDP": true,
    "_EnableRDP_Help": "Enable Remote Desktop and add firewall rule (true/false)",

    "EnableWinRM": true,
    "_EnableWinRM_Help": "Enable PowerShell Remoting with Kerberos auth (true/false)",

    "ConfigureFirewall": true,
    "_ConfigureFirewall_Help": "Set firewall: Domain=Off, Private=Off, Public=On (true/false)",

    "SetPowerPlan": "High Performance",
    "_SetPowerPlan_Help": "'High Performance' (recommended), 'Balanced', or 'Power Saver'. Set to null to skip.",

    "InstallHyperV": false,
    "_InstallHyperV_Help": "Install Hyper-V role and management tools (true/false). Requires reboot. Only for hosts.",

    "InstallMPIO": false,
    "_InstallMPIO_Help": "Install Multipath I/O for SAN connectivity (true/false). Requires reboot.",

    "InstallFailoverClustering": false,
    "_InstallFailoverClustering_Help": "Install Failover Clustering role and tools (true/false). Requires reboot.",

    "CreateLocalAdmin": false,
    "_CreateLocalAdmin_Help": "Create local admin account (true/false). Will prompt for password at runtime.",

    "LocalAdminName": "$localadminaccountname",
    "_LocalAdminName_Help": "Username for the local admin account. Only used if CreateLocalAdmin is true.",

    "DisableBuiltInAdmin": false,
    "_DisableBuiltInAdmin_Help": "Disable the built-in Administrator account (true/false). Only do this after confirming other admin access works.",

    "InstallUpdates": false,
    "_InstallUpdates_Help": "Install Windows Updates (true/false). Takes 10-60+ min. Has 5-min timeout per update cycle. Recommend doing last.",

    "AutoReboot": true,
    "_AutoReboot_Help": "Automatically reboot after changes if needed (true/false). 10-second countdown before reboot.",

    "_HOST_SECTION": "========== HOST-SPECIFIC (only used when ConfigType=HOST) ==========",

    "CreateSETSwitch": false,
    "_CreateSETSwitch_Help": "Create a Switch Embedded Team (SET) virtual switch. Requires Hyper-V.",
    "SETSwitchName": "LAN-SET",
    "_SETSwitchName_Help": "Name for the SET virtual switch.",
    "SETManagementName": "Management",
    "_SETManagementName_Help": "Name for the management virtual NIC on the SET switch.",
    "SETAdapterMode": "auto",
    "_SETAdapterMode_Help": "'auto' = detect internet adapters for SET, 'manual' = prompt for selection.",

    "CustomVNICs": [],
    "_CustomVNICs_Help": "Array of virtual NICs to create on the SET switch. Each needs Name (required) and optional VLAN (1-4094). Example: [{\"Name\": \"Backup\"}, {\"Name\": \"Cluster\", \"VLAN\": 100}, {\"Name\": \"Live Migration\", \"VLAN\": 200}]",

    "StorageBackendType": "iSCSI",
    "_StorageBackendType_Help": "'iSCSI' (default), 'FC', 'S2D', 'SMB3', 'NVMeoF', or 'Local'. Controls which storage backend is configured in steps 18-19.",

    "ConfigureSharedStorage": false,
    "_ConfigureSharedStorage_Help": "Configure the shared storage backend (iSCSI NICs, FC scan, S2D enable, SMB test, NVMe scan). Backend determined by StorageBackendType.",

    "ConfigureiSCSI": false,
    "_ConfigureiSCSI_Help": "DEPRECATED: Use ConfigureSharedStorage + StorageBackendType=iSCSI. Kept for backward compat.",
    "iSCSIHostNumber": null,
    "_iSCSIHostNumber_Help": "Host number for iSCSI IP calculation (1-24). null = auto-detect from hostname.",

    "SMB3SharePath": null,
    "_SMB3SharePath_Help": "UNC path to SMB3 share (e.g., '\\\\\\\\server\\\\share'). Only used when StorageBackendType=SMB3.",

    "ConfigureMPIO": false,
    "_ConfigureMPIO_Help": "Configure MPIO multipath for the active storage backend (iSCSI or FC). S2D/SMB3/NVMe handle paths natively.",

    "InitializeHostStorage": false,
    "_InitializeHostStorage_Help": "Select a data drive, create VM storage directories, set Hyper-V default paths.",
    "HostStorageDrive": null,
    "_HostStorageDrive_Help": "Drive letter for VM storage (e.g., 'D'). null = auto-select first available non-C fixed NTFS drive.",

    "ConfigureDefenderExclusions": false,
    "_ConfigureDefenderExclusions_Help": "Add Defender exclusions for Hyper-V and VM storage paths.",

    "_ROLE_TEMPLATES_SECTION": "========== SERVER ROLE TEMPLATES ==========",

    "ServerRoleTemplate": null,
    "_ServerRoleTemplate_Help": "Role template to apply: DC, FS, WEB, DHCP, DNS, PRINT, WSUS, NPS, HV, RDS, or null to skip.",

    "_DCPROMO_SECTION": "========== DOMAIN CONTROLLER PROMOTION ==========",

    "PromoteToDC": false,
    "_PromoteToDC_Help": "Promote server to Domain Controller after domain join (true/false).",

    "DCPromoType": "NewForest",
    "_DCPromoType_Help": "'NewForest', 'AdditionalDC', or 'RODC'. Only used when PromoteToDC is true.",

    "ForestName": null,
    "_ForestName_Help": "Domain name for new forest (e.g., 'corp.contoso.com'). Only used with DCPromoType=NewForest.",

    "ForestMode": "WinThreshold",
    "_ForestMode_Help": "Forest functional level: 'Win2012R2', 'WinThreshold' (2016, default), 'Win2019', 'Win2022', 'Win2025'.",

    "DomainMode": "WinThreshold",
    "_DomainMode_Help": "Domain functional level (same options as ForestMode). Usually matches ForestMode.",

    "_DCPromo_Note": "Safe Mode (DSRM) password will be prompted at runtime for security. Cannot be stored in config."
}
"@

    # Default path
    $defaultPath = "$env:USERPROFILE\Desktop\batch_config.json"

    Write-OutputColor "Default location: $defaultPath" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Create batch config template?")) {
        Write-OutputColor "Cancelled." -color "Info"
        return
    }

    Write-OutputColor "Enter path (press Enter for default):" -color "Info"
    $customPath = Read-Host

    if ([string]::IsNullOrWhiteSpace($customPath)) {
        $savePath = $defaultPath
    }
    else {
        $savePath = $customPath
    }

    try {
        $configTemplate | Out-File -FilePath $savePath -Encoding UTF8 -Force
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Batch config template created: $savePath" -color "Success"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Next steps:" -color "Info"
        Write-OutputColor "  1. Open the file in Notepad or VS Code" -color "Success"
        Write-OutputColor "  2. Edit the values for your server" -color "Success"
        Write-OutputColor "  3. Set unwanted options to null or false" -color "Success"
        Write-OutputColor "  4. Save as 'batch_config.json' next to this script" -color "Success"
        Write-OutputColor "  5. Run the script - it auto-detects and applies the config" -color "Success"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Tip: The '_Help' fields explain each setting and are ignored." -color "Info"

        Add-SessionChange -Category "Export" -Description "Created batch config template at $savePath"
    }
    catch {
        Write-OutputColor "Failed to create file: $_" -color "Error"
    }
}

# Function to show the Batch Config submenu (template vs. generate from state)
function Show-BatchConfigMenu {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$("  BATCH CONFIG GENERATOR".PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-MenuItem "[1]  Generate Blank Template"
    Write-MenuItem "[2]  Generate from Current Server State"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $userResponse = Read-Host "  Select"
    return $userResponse
}

# Generate a batch_config.json pre-filled with the current server's live state
function Export-BatchConfigFromState {
    Clear-Host
    Write-CenteredOutput "Generate Batch Config from Current State" -color "Info"

    Write-OutputColor "This will detect the current server configuration and generate a" -color "Info"
    Write-OutputColor "batch_config.json pre-filled with live settings." -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "Gathering current server state..." -color "Info"

    try {
        # ----- Detect ConfigType -----
        $isHyperVHost = Test-HyperVInstalled
        $configType = if ($isHyperVHost) { "HOST" } else { "VM" }

        # ----- System info -----
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
        $currentHostname = $env:COMPUTERNAME
        $currentTimezone = (Get-TimeZone -ErrorAction SilentlyContinue).Id

        # ----- Network: find primary UP adapter with an IPv4 address -----
        $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" }
        $primaryAdapter = $null
        $primaryIP = $null
        $primaryDNS = $null
        $primaryGateway = $null

        foreach ($adapter in $adapters) {
            $ipInfo = Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -ne "127.0.0.1" -and $_.PrefixOrigin -ne "WellKnown" } |
                Select-Object -First 1
            if ($null -ne $ipInfo) {
                $primaryAdapter = $adapter
                $primaryIP = $ipInfo
                $primaryDNS = Get-DnsClientServerAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue
                $primaryGateway = Get-NetRoute -InterfaceAlias $adapter.Name -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1
                break
            }
        }

        $adapterName = if ($null -ne $primaryAdapter) { $primaryAdapter.Name } else { "Ethernet" }
        $ipAddress = if ($null -ne $primaryIP) { $primaryIP.IPAddress } else { $null }
        $subnetCIDR = if ($null -ne $primaryIP) { $primaryIP.PrefixLength } else { 24 }
        $gateway = if ($null -ne $primaryGateway) { $primaryGateway.NextHop } else { $null }
        $dns1 = if ($null -ne $primaryDNS -and $primaryDNS.ServerAddresses.Count -ge 1) { $primaryDNS.ServerAddresses[0] } else { $null }
        $dns2 = if ($null -ne $primaryDNS -and $primaryDNS.ServerAddresses.Count -ge 2) { $primaryDNS.ServerAddresses[1] } else { $null }

        # ----- Domain -----
        $isDomainJoined = $false
        $domainName = $null
        if ($null -ne $computerSystem -and $computerSystem.PartOfDomain) {
            $isDomainJoined = $true
            $domainName = $computerSystem.Domain
        }

        # ----- Remote access -----
        $rdpEnabled = ((Get-RDPState) -eq "Enabled")
        $winrmEnabled = ((Get-WinRMState) -eq "Enabled")

        # ----- Power plan -----
        $currentPlan = Get-CurrentPowerPlan
        $powerPlanName = $currentPlan.Name

        # ----- Features -----
        $hyperVInstalled = $isHyperVHost
        $mpioInstalled = Test-MPIOInstalled
        $clusteringInstalled = Test-FailoverClusteringInstalled

        # ----- Build the config hashtable -----
        $config = [ordered]@{
            "_README"                          = "$($script:ToolFullName) - Batch Config (generated from $currentHostname)"
            "_GeneratedAt"                     = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            "_ScriptVersion"                   = $script:ScriptVersion

            "ConfigType"                       = $configType
            "_ConfigType_Help"                 = "'VM' for virtual machines, 'HOST' for Hyper-V hosts. Host mode skips network config (build SET via GUI)."

            "Hostname"                         = $currentHostname
            "_Hostname_Help"                   = "NetBIOS name, max 15 chars. Format: SITENUMBER-ROLE (e.g., 123456-DC1, 123456-FS1)"

            "AdapterName"                      = $adapterName
            "_AdapterName_Help"                = "Network adapter to configure. VMs: usually 'Ethernet'. Hosts: 'vEthernet (Management)'. Run Get-NetAdapter to check."

            "IPAddress"                        = $ipAddress
            "_IPAddress_Help"                  = "Static IPv4 address for the management NIC"

            "SubnetCIDR"                       = $subnetCIDR
            "_SubnetCIDR_Help"                 = "Subnet in CIDR notation: 24 = 255.255.255.0, 22 = 255.255.252.0, 16 = 255.255.0.0"

            "Gateway"                          = $gateway
            "_Gateway_Help"                    = "Default gateway IP address"

            "DNS1"                             = $dns1
            "_DNS1_Help"                       = "Primary DNS server"

            "DNS2"                             = $dns2
            "_DNS2_Help"                       = "Secondary DNS server"

            "DomainName"                       = $domainName
            "_DomainName_Help"                 = "Active Directory domain to join. Set to null or empty to skip. Will prompt for credentials at runtime."

            "Timezone"                         = $currentTimezone
            "_Timezone_Help"                   = "Timezone ID: 'Pacific Standard Time', 'Mountain Standard Time', 'Central Standard Time', 'Eastern Standard Time'"

            "EnableRDP"                        = $rdpEnabled
            "_EnableRDP_Help"                  = "Enable Remote Desktop and add firewall rule (true/false)"

            "EnableWinRM"                      = $winrmEnabled
            "_EnableWinRM_Help"                = "Enable PowerShell Remoting with Kerberos auth (true/false)"

            "ConfigureFirewall"                = $true
            "_ConfigureFirewall_Help"          = "Set firewall: Domain=Off, Private=Off, Public=On (true/false)"

            "SetPowerPlan"                     = $powerPlanName
            "_SetPowerPlan_Help"               = "'High Performance' (recommended), 'Balanced', or 'Power Saver'. Set to null to skip."

            "InstallHyperV"                    = $hyperVInstalled
            "_InstallHyperV_Help"              = "Install Hyper-V role and management tools (true/false). Requires reboot. Only for hosts."

            "InstallMPIO"                      = $mpioInstalled
            "_InstallMPIO_Help"                = "Install Multipath I/O for SAN connectivity (true/false). Requires reboot."

            "InstallFailoverClustering"        = $clusteringInstalled
            "_InstallFailoverClustering_Help"  = "Install Failover Clustering role and tools (true/false). Requires reboot."

            "CreateLocalAdmin"                 = $false
            "_CreateLocalAdmin_Help"           = "Create local admin account (true/false). Will prompt for password at runtime."

            "LocalAdminName"                   = $localadminaccountname
            "_LocalAdminName_Help"             = "Username for the local admin account. Only used if CreateLocalAdmin is true."

            "DisableBuiltInAdmin"              = $false
            "_DisableBuiltInAdmin_Help"        = "Disable the built-in Administrator account (true/false). Only do this after confirming other admin access works."

            "InstallUpdates"                   = $false
            "_InstallUpdates_Help"             = "Install Windows Updates (true/false). Takes 10-60+ min. Has 5-min timeout per update cycle. Recommend doing last."

            "AutoReboot"                       = $true
            "_AutoReboot_Help"                 = "Automatically reboot after changes if needed (true/false). 10-second countdown before reboot."

            "_HOST_SECTION"                    = "========== HOST-SPECIFIC (only used when ConfigType=HOST) =========="
        }

        # ----- HOST-specific fields -----
        $setSwitchName = $null
        $setMgmtName = $null
        $hasSetSwitch = $false
        $hasISCSISessions = $false
        $storageDrive = $null

        if ($isHyperVHost) {
            # Detect SET switch
            $setSwitches = Get-VMSwitch -ErrorAction SilentlyContinue | Where-Object { $_.EmbeddedTeamingEnabled -eq $true }
            if ($null -ne $setSwitches -and @($setSwitches).Count -gt 0) {
                $hasSetSwitch = $true
                $firstSet = @($setSwitches)[0]
                $setSwitchName = $firstSet.Name
                # Find the management vNIC on the SET switch
                $mgmtNic = Get-VMNetworkAdapter -ManagementOS -SwitchName $firstSet.Name -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($null -ne $mgmtNic) {
                    $setMgmtName = $mgmtNic.Name
                }
            }

            # Detect iSCSI sessions
            $iscsiSessions = Get-IscsiSession -ErrorAction SilentlyContinue
            if ($null -ne $iscsiSessions -and @($iscsiSessions).Count -gt 0) {
                $hasISCSISessions = $true
            }

            # Detect storage drive (first non-C fixed NTFS drive)
            $dataVolume = Get-Volume -ErrorAction SilentlyContinue |
                Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.DriveLetter -ne 'C' -and $_.FileSystem -eq 'NTFS' } |
                Sort-Object DriveLetter |
                Select-Object -First 1
            if ($null -ne $dataVolume) {
                $storageDrive = [string]$dataVolume.DriveLetter
            }
        }

        $config["CreateSETSwitch"]                 = $hasSetSwitch
        $config["_CreateSETSwitch_Help"]           = "Create a Switch Embedded Team (SET) virtual switch. Requires Hyper-V."
        $config["SETSwitchName"]                   = if ($setSwitchName) { $setSwitchName } else { "LAN-SET" }
        $config["_SETSwitchName_Help"]             = "Name for the SET virtual switch."
        $config["SETManagementName"]               = if ($setMgmtName) { $setMgmtName } else { "Management" }
        $config["_SETManagementName_Help"]         = "Name for the management virtual NIC on the SET switch."
        $config["SETAdapterMode"]                  = "auto"
        $config["_SETAdapterMode_Help"]            = "'auto' = detect internet adapters for SET, 'manual' = prompt for selection."

        # Detect existing vNICs on SET (excluding Management)
        $customVNICs = @()
        if ($hasSetSwitch) {
            $setVNICs = Get-VMNetworkAdapter -ManagementOS -SwitchName $setSwitchName -ErrorAction SilentlyContinue
            foreach ($vnic in $setVNICs) {
                if ($vnic.Name -ne $setMgmtName) {
                    $vlanInfo = Get-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $vnic.Name -ErrorAction SilentlyContinue
                    $vlanId = if ($null -ne $vlanInfo -and $vlanInfo.AccessVlanId -gt 0) { $vlanInfo.AccessVlanId } else { $null }
                    $customVNICs += @{ Name = $vnic.Name; VLAN = $vlanId }
                }
            }
        }
        $config["CustomVNICs"]                     = $customVNICs
        $config["_CustomVNICs_Help"]               = "Array of virtual NICs to create on the SET switch. Each needs Name (required) and optional VLAN (1-4094)."

        $config["ConfigureiSCSI"]                  = $hasISCSISessions
        $config["_ConfigureiSCSI_Help"]            = "Configure iSCSI NICs with auto-calculated IPs based on host number."
        $config["iSCSIHostNumber"]                 = $null
        $config["_iSCSIHostNumber_Help"]           = "Host number for IP calculation (1-24). null = auto-detect from hostname."

        $config["ConfigureMPIO"]                   = ($hasISCSISessions -and $mpioInstalled)
        $config["_ConfigureMPIO_Help"]             = "Connect to iSCSI targets and configure MPIO multipath. Requires iSCSI configured first."

        $config["InitializeHostStorage"]           = ($null -ne $storageDrive)
        $config["_InitializeHostStorage_Help"]     = "Select a data drive, create VM storage directories, set Hyper-V default paths."
        $config["HostStorageDrive"]                = $storageDrive
        $config["_HostStorageDrive_Help"]          = "Drive letter for VM storage (e.g., 'D'). null = auto-select first available non-C fixed NTFS drive."

        $config["ConfigureDefenderExclusions"]     = $isHyperVHost
        $config["_ConfigureDefenderExclusions_Help"] = "Add Defender exclusions for Hyper-V and VM storage paths."

        # ----- Display summary -----
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  DETECTED CONFIGURATION".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "Config Type:  $configType"
        Write-MenuItem "Hostname:     $currentHostname"
        Write-MenuItem "Adapter:      $adapterName"
        Write-MenuItem "IP Address:   $(if ($ipAddress) { "$ipAddress/$subnetCIDR" } else { '(not detected)' })"
        Write-MenuItem "Gateway:      $(if ($gateway) { $gateway } else { '(not detected)' })"
        Write-MenuItem "DNS:          $(if ($dns1) { $dns1 } else { '(none)' })$(if ($dns2) { ", $dns2" } else { '' })"
        Write-MenuItem "Domain:       $(if ($isDomainJoined) { $domainName } else { '(not joined)' })"
        Write-MenuItem "Timezone:     $currentTimezone"
        Write-MenuItem "RDP:          $(if ($rdpEnabled) { 'Enabled' } else { 'Disabled' })"
        Write-MenuItem "WinRM:        $(if ($winrmEnabled) { 'Enabled' } else { 'Disabled' })"
        Write-MenuItem "Power Plan:   $powerPlanName"
        Write-MenuItem "Hyper-V:      $(if ($hyperVInstalled) { 'Installed' } else { 'Not Installed' })"
        Write-MenuItem "MPIO:         $(if ($mpioInstalled) { 'Installed' } else { 'Not Installed' })"
        Write-MenuItem "Clustering:   $(if ($clusteringInstalled) { 'Installed' } else { 'Not Installed' })"
        if ($isHyperVHost) {
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-MenuItem "SET Switch:   $(if ($hasSetSwitch) { $setSwitchName } else { '(none)' })"
            Write-MenuItem "Custom vNICs: $(if ($customVNICs.Count -gt 0) { "$($customVNICs.Count) detected" } else { '(none)' })"
            Write-MenuItem "iSCSI:        $(if ($hasISCSISessions) { 'Active sessions' } else { 'No sessions' })"
            Write-MenuItem "Storage:      $(if ($storageDrive) { "${storageDrive}:" } else { '(no data drive)' })"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        # ----- Prompt for save path -----
        $defaultPath = "$env:USERPROFILE\Desktop\batch_config.json"

        Write-OutputColor "Default location: $defaultPath" -color "Info"
        Write-OutputColor "" -color "Info"

        if (-not (Confirm-UserAction -Message "Save batch config from current state?")) {
            Write-OutputColor "Cancelled." -color "Info"
            return
        }

        Write-OutputColor "Enter path (press Enter for default):" -color "Info"
        $customPath = Read-Host

        if ([string]::IsNullOrWhiteSpace($customPath)) {
            $savePath = $defaultPath
        }
        else {
            $savePath = $customPath
        }

        $config | ConvertTo-Json -Depth 5 | Out-File -FilePath $savePath -Encoding UTF8 -Force

        Write-OutputColor "" -color "Info"
        Write-OutputColor "Batch config generated from current state: $savePath" -color "Success"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Next steps:" -color "Info"
        Write-OutputColor "  1. Review the generated file - all values are pre-filled" -color "Success"
        Write-OutputColor "  2. Edit Hostname and IPAddress for the target server" -color "Success"
        Write-OutputColor "  3. Set any unwanted options to null or false" -color "Success"
        Write-OutputColor "  4. Save as 'batch_config.json' next to the script on the target" -color "Success"
        Write-OutputColor "  5. Run the script - it auto-detects and applies the config" -color "Success"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Tip: This config mirrors your current server. Great for cloning to similar servers." -color "Info"

        Add-SessionChange -Category "Export" -Description "Generated batch config from current state at $savePath"
    }
    catch {
        Write-OutputColor "Failed to generate batch config: $_" -color "Error"
    }
}
#endregion