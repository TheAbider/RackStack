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
    "_AutoReboot_Help": "Automatically reboot after changes if needed (true/false). 10-second countdown before reboot."
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
#endregion