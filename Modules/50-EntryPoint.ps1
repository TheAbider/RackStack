#region ===== SCRIPT ENTRY POINT =====
# Start transcript logging
function Start-ScriptTranscript {
    # Ensure temp directory exists
    $tempPath = $script:TempPath
    if (-not (Test-Path $tempPath)) {
        try {
            New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
        }
        catch {
            # Fall back to user temp if we can't create directory
            $tempPath = $env:TEMP
        }
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $hostname = $env:COMPUTERNAME
    $script:TranscriptPath = Join-Path $tempPath "$($script:ToolName)Config_${hostname}_${timestamp}.log"

    try {
        Start-Transcript -Path $script:TranscriptPath -Append | Out-Null
        return $true
    }
    catch {
        # Transcript might already be running
        return $false
    }
}

# Stop transcript logging
function Stop-ScriptTranscript {
    try {
        Stop-Transcript | Out-Null
    }
    catch {
        # Ignore if transcript wasn't running
    }
}

# Clean up old transcript files (older than 30 days)
function Remove-OldTranscripts {
    param(
        [int]$DaysToKeep = 30
    )

    $tempPath = $script:TempPath
    if (-not (Test-Path $tempPath)) { return }

    try {
        $cutoffDate = (Get-Date).AddDays(-$DaysToKeep)
        $oldLogs = Get-ChildItem -Path $tempPath -Filter "$($script:ToolName)Config_*.log" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoffDate }

        if ($oldLogs) {
            $count = $oldLogs.Count
            $oldLogs | Remove-Item -Force -ErrorAction SilentlyContinue
            Write-OutputColor "Cleaned up $count old transcript(s) (older than $DaysToKeep days)" -color "Debug"
        }
    }
    catch {
        # Silently ignore cleanup errors
    }
}

# Function to ensure the script is running with elevated privileges
function Assert-Elevation {
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-OutputColor "This script requires administrative privileges. Restarting with elevation..." -color "Error"
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        Exit
    }
    else {
        # Size and maximize console window before any output
        Initialize-ConsoleWindow

        # Start transcript logging
        $transcriptStarted = Start-ScriptTranscript
        if ($transcriptStarted -and $script:TranscriptPath) {
            Write-OutputColor "Transcript logging to: $($script:TranscriptPath)" -color "Debug"
        }

        # Clean up old transcripts (older than 30 days)
        Remove-OldTranscripts -DaysToKeep 30

        Write-OutputColor "Script is running with elevated privileges." -color "Success"

        # Check for session to restore (v2.8.0)
        $null = Restore-SessionState

        # Load environment defaults and custom licenses from defaults.json
        Import-Defaults

        # Silent update check (non-blocking, 5s timeout)
        Test-StartupUpdateCheck

        # Auto-update: if enabled and update available, install without prompting
        if ($script:AutoUpdate -and $script:UpdateAvailable -and $script:LatestRelease) {
            Write-OutputColor "  Auto-update enabled. Installing v$($script:LatestVersion)..." -color "Info"
            try {
                Install-ScriptUpdate -Release $script:LatestRelease -Auto
            }
            catch {
                Write-OutputColor "  Auto-update failed: $($_.Exception.Message)" -color "Warning"
            }
        }

        Start-Show-Mainmenu

        # Stop transcript when done
        Stop-ScriptTranscript
    }
}

# Validate batch config before execution
function Test-BatchConfig {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Config
    )

    $errors = [System.Collections.ArrayList]::new()
    $warnings = [System.Collections.ArrayList]::new()

    # ConfigType validation
    if ($Config.ConfigType) {
        $validTypes = @("VM", "HOST")
        if ($Config.ConfigType.ToUpper() -notin $validTypes) {
            $null = $errors.Add("ConfigType '$($Config.ConfigType)' is invalid. Must be 'VM' or 'HOST'.")
        }
    }

    # Hostname validation
    if ($Config.Hostname) {
        if (-not (Test-ValidHostname -Hostname $Config.Hostname)) {
            $null = $errors.Add("Hostname '$($Config.Hostname)' is invalid. Must be 1-15 alphanumeric characters (hyphens allowed, not at start/end).")
        }
    } else {
        $null = $warnings.Add("Hostname is not set. Server will keep its current name.")
    }

    # IP address fields
    $ipFields = @("IPAddress", "Gateway", "DNS1", "DNS2")
    foreach ($field in $ipFields) {
        if ($Config[$field] -and $Config[$field] -is [string] -and $Config[$field].Trim() -ne "") {
            if (-not (Test-ValidIPAddress -IPAddress $Config[$field])) {
                $null = $errors.Add("$field '$($Config[$field])' is not a valid IPv4 address.")
            }
        }
    }

    # SubnetCIDR range
    if ($null -ne $Config.SubnetCIDR) {
        $cidr = $Config.SubnetCIDR -as [int]
        if ($null -eq $cidr -or $cidr -lt 1 -or $cidr -gt 32) {
            $null = $errors.Add("SubnetCIDR '$($Config.SubnetCIDR)' is invalid. Must be an integer between 1 and 32.")
        }
    }

    # Network consistency: IP requires Gateway
    if ($Config.IPAddress -and -not $Config.Gateway) {
        $null = $errors.Add("IPAddress is set but Gateway is missing. Both are required for network configuration.")
    }
    if ($Config.Gateway -and -not $Config.IPAddress) {
        $null = $errors.Add("Gateway is set but IPAddress is missing. Both are required for network configuration.")
    }

    # Boolean fields validation
    $boolFields = @("EnableRDP", "EnableWinRM", "ConfigureFirewall", "InstallHyperV",
                    "InstallMPIO", "InstallFailoverClustering", "CreateLocalAdmin",
                    "DisableBuiltInAdmin", "InstallUpdates", "AutoReboot")
    foreach ($field in $boolFields) {
        if ($null -ne $Config[$field] -and $Config[$field] -isnot [bool]) {
            $null = $errors.Add("$field must be true or false (got '$($Config[$field])').")
        }
    }

    # Power plan validation
    if ($Config.SetPowerPlan) {
        if (-not $script:PowerPlanGUID.ContainsKey($Config.SetPowerPlan)) {
            $validPlans = ($script:PowerPlanGUID.Keys | Sort-Object) -join "', '"
            $null = $errors.Add("SetPowerPlan '$($Config.SetPowerPlan)' is invalid. Valid options: '$validPlans'.")
        }
    }

    # HOST mode warnings
    if ($Config.ConfigType -and $Config.ConfigType.ToUpper() -eq "HOST") {
        if (-not $Config.InstallHyperV) {
            $null = $warnings.Add("ConfigType is HOST but InstallHyperV is not enabled.")
        }
        if ($Config.IPAddress -and -not $Config.AdapterName) {
            $null = $warnings.Add("HOST mode with IP config but no AdapterName. Network config will be skipped.")
        }
        if ($Config.CreateSETSwitch -and -not $Config.InstallHyperV) {
            $null = $warnings.Add("CreateSETSwitch requires Hyper-V. SET creation may fail.")
        }
    }

    # HOST-specific field validation
    if ($Config.SETAdapterMode -and $Config.SETAdapterMode -notin @("auto", "manual")) {
        $null = $errors.Add("SETAdapterMode must be 'auto' or 'manual' (got '$($Config.SETAdapterMode)').")
    }
    if ($null -ne $Config.iSCSIHostNumber -and $Config.iSCSIHostNumber -isnot [bool]) {
        $hostNum = $Config.iSCSIHostNumber -as [int]
        if ($null -eq $hostNum -or $hostNum -lt 1 -or $hostNum -gt 24) {
            $null = $errors.Add("iSCSIHostNumber must be 1-24 or null (got '$($Config.iSCSIHostNumber)').")
        }
    }
    if ($Config.HostStorageDrive) {
        $dl = "$($Config.HostStorageDrive)".ToUpper()
        if ($dl -notmatch '^[A-Z]$' -or $dl -eq 'C') {
            $null = $errors.Add("HostStorageDrive must be a single letter A-Z (not C). Got '$($Config.HostStorageDrive)'.")
        }
    }

    # DisableBuiltInAdmin without CreateLocalAdmin
    if ($Config.DisableBuiltInAdmin -and -not $Config.CreateLocalAdmin) {
        $null = $warnings.Add("DisableBuiltInAdmin is set without CreateLocalAdmin. Ensure another admin account exists.")
    }

    return @{
        IsValid  = ($errors.Count -eq 0)
        Errors   = @($errors)
        Warnings = @($warnings)
    }
}

# Check for batch mode parameters passed via environment variables or a config file
# This is a simpler approach than full param() block which has issues with functions
function Start-BatchMode {
    param(
        [hashtable]$Config
    )

    # Start transcript for batch mode too
    $null = Start-ScriptTranscript

    # Load environment defaults and custom licenses from defaults.json (no wizard in batch mode)
    Import-Defaults

    Write-OutputColor "" -color "Info"
    Write-OutputColor ("=" * 65) -color "Info"
    Write-OutputColor "  $($script:ToolFullName.ToUpper()) v$($script:ScriptVersion) - BATCH MODE" -color "Info"
    Write-OutputColor ("=" * 65) -color "Info"
    Write-OutputColor "" -color "Info"

    # Validate config before proceeding
    $validation = Test-BatchConfig -Config $Config
    if ($validation.Warnings.Count -gt 0) {
        Write-OutputColor "  WARNINGS:" -color "Warning"
        foreach ($w in $validation.Warnings) {
            Write-OutputColor "    - $w" -color "Warning"
        }
        Write-OutputColor "" -color "Info"
    }
    if (-not $validation.IsValid) {
        Write-OutputColor "  VALIDATION ERRORS:" -color "Error"
        foreach ($e in $validation.Errors) {
            Write-OutputColor "    - $e" -color "Error"
        }
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Batch mode aborted. Fix the errors above and try again." -color "Critical"
        Stop-ScriptTranscript
        return
    }

    $configType = if ($Config.ConfigType) { $Config.ConfigType.ToUpper() } else { "VM" }
    Write-OutputColor "  Config Type: $configType" -color "Info"
    Write-OutputColor "  Started:     $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -color "Info"
    Write-OutputColor "" -color "Info"

    $stepNum = 0
    $totalSteps = 19
    $changesApplied = 0
    $errors = 0

    # Step 1: Set hostname
    $stepNum++
    if ($Config.Hostname) {
        Write-OutputColor "  [$stepNum/$totalSteps] Setting hostname to '$($Config.Hostname)'..." -color "Info"
        if (Test-ValidHostname -Hostname $Config.Hostname) {
            try {
                Rename-Computer -NewName $Config.Hostname -Force -ErrorAction Stop
                Write-OutputColor "           Hostname set. Reboot required." -color "Success"
                $global:RebootNeeded = $true
                $changesApplied++
                Add-SessionChange -Category "System" -Description "Set hostname to $($Config.Hostname)"
            }
            catch {
                Write-OutputColor "           Failed: $_" -color "Error"
                $errors++
            }
        }
        else {
            Write-OutputColor "           Invalid hostname: $($Config.Hostname)" -color "Error"
            $errors++
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Hostname: skipped (not set)" -color "Debug"
    }

    # Step 2: Configure network (skip for HOST mode unless adapter is specified)
    $stepNum++
    $skipNetwork = ($configType -eq "HOST" -and -not $Config.AdapterName)
    if (-not $skipNetwork -and $Config.IPAddress -and $Config.Gateway) {
        $adapterName = if ($Config.AdapterName) { $Config.AdapterName } else { "Ethernet" }
        Write-OutputColor "  [$stepNum/$totalSteps] Configuring network on '$adapterName'..." -color "Info"
        try {
            # Validate inputs
            if (-not (Test-ValidIPAddress -IPAddress $Config.IPAddress)) {
                throw "Invalid IP address: $($Config.IPAddress)"
            }
            if (-not (Test-ValidIPAddress -IPAddress $Config.Gateway)) {
                throw "Invalid gateway: $($Config.Gateway)"
            }

            $cidr = if ($Config.SubnetCIDR) { [int]$Config.SubnetCIDR } else { 24 }

            # Clear existing config
            Remove-NetIPAddress -InterfaceAlias $adapterName -Confirm:$false -ErrorAction SilentlyContinue
            Remove-NetRoute -InterfaceAlias $adapterName -Confirm:$false -ErrorAction SilentlyContinue

            # Set IP
            New-NetIPAddress -InterfaceAlias $adapterName -IPAddress $Config.IPAddress `
                -PrefixLength $cidr -DefaultGateway $Config.Gateway -ErrorAction Stop

            # Set DNS
            $dnsServers = @()
            if ($Config.DNS1) { $dnsServers += $Config.DNS1 }
            if ($Config.DNS2) { $dnsServers += $Config.DNS2 }
            if ($dnsServers.Count -gt 0) {
                Set-DnsClientServerAddress -InterfaceAlias $adapterName -ServerAddresses $dnsServers
            }

            Write-OutputColor "           IP: $($Config.IPAddress)/$cidr  GW: $($Config.Gateway)" -color "Success"
            if ($dnsServers.Count -gt 0) {
                Write-OutputColor "           DNS: $($dnsServers -join ', ')" -color "Success"
            }
            $changesApplied++
            Add-SessionChange -Category "Network" -Description "Set IP $($Config.IPAddress)/$cidr on $adapterName"
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
    }
    else {
        $reason = if ($skipNetwork) { "HOST mode - configure SET via GUI" } else { "IP/Gateway not set" }
        Write-OutputColor "  [$stepNum/$totalSteps] Network: skipped ($reason)" -color "Debug"
    }

    # Step 3: Set timezone
    $stepNum++
    if ($Config.Timezone) {
        Write-OutputColor "  [$stepNum/$totalSteps] Setting timezone to '$($Config.Timezone)'..." -color "Info"
        try {
            Set-TimeZone -Id $Config.Timezone -ErrorAction Stop
            Write-OutputColor "           Timezone set." -color "Success"
            $changesApplied++
            Add-SessionChange -Category "System" -Description "Set timezone to $($Config.Timezone)"
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Timezone: skipped" -color "Debug"
    }

    # Step 4: Enable RDP
    $stepNum++
    if ($Config.EnableRDP) {
        Write-OutputColor "  [$stepNum/$totalSteps] Enabling Remote Desktop..." -color "Info"
        try {
            Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -ErrorAction Stop
            Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
            Write-OutputColor "           RDP enabled." -color "Success"
            $changesApplied++
            Add-SessionChange -Category "System" -Description "Enabled RDP"
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] RDP: skipped" -color "Debug"
    }

    # Step 5: Enable WinRM
    $stepNum++
    if ($Config.EnableWinRM) {
        Write-OutputColor "  [$stepNum/$totalSteps] Enabling PowerShell Remoting..." -color "Info"
        try {
            Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction Stop
            Set-Item WSMan:\localhost\Service\Auth\Kerberos -Value $true -ErrorAction SilentlyContinue
            Write-OutputColor "           WinRM enabled with Kerberos auth." -color "Success"
            $changesApplied++
            Add-SessionChange -Category "System" -Description "Enabled PowerShell Remoting"
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] WinRM: skipped" -color "Debug"
    }

    # Step 6: Configure firewall
    $stepNum++
    if ($Config.ConfigureFirewall) {
        Write-OutputColor "  [$stepNum/$totalSteps] Configuring firewall..." -color "Info"
        try {
            Set-NetFirewallProfile -Profile Domain -Enabled False -ErrorAction Stop
            Set-NetFirewallProfile -Profile Private -Enabled False -ErrorAction Stop
            Set-NetFirewallProfile -Profile Public -Enabled True -ErrorAction Stop
            Write-OutputColor "           Firewall: Domain=Off Private=Off Public=On" -color "Success"
            $changesApplied++
            Add-SessionChange -Category "Security" -Description "Configured firewall profiles"
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Firewall: skipped" -color "Debug"
    }

    # Step 7: Set power plan
    $stepNum++
    if ($Config.SetPowerPlan) {
        Write-OutputColor "  [$stepNum/$totalSteps] Setting power plan to '$($Config.SetPowerPlan)'..." -color "Info"
        if ($script:PowerPlanGUID.ContainsKey($Config.SetPowerPlan)) {
            powercfg /setactive $script:PowerPlanGUID[$Config.SetPowerPlan] 2>&1 | Out-Null
            Write-OutputColor "           Power plan set." -color "Success"
            $changesApplied++
            Add-SessionChange -Category "System" -Description "Set power plan to $($Config.SetPowerPlan)"
        }
        else {
            Write-OutputColor "           Unknown plan: $($Config.SetPowerPlan)" -color "Warning"
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Power plan: skipped" -color "Debug"
    }

    # Step 8: Install Hyper-V
    $stepNum++
    if ($Config.InstallHyperV -and -not (Test-HyperVInstalled)) {
        if (-not (Test-WindowsServer)) {
            Write-OutputColor "  [$stepNum/$totalSteps] Hyper-V: skipped (requires Windows Server)" -color "Warning"
            $errors++
        } else {
            Write-OutputColor "  [$stepNum/$totalSteps] Installing Hyper-V..." -color "Info"
            try {
                Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -ErrorAction Stop
                Write-OutputColor "           Hyper-V installed. Reboot required." -color "Success"
                $global:RebootNeeded = $true
                $changesApplied++
                Add-SessionChange -Category "System" -Description "Installed Hyper-V"
            }
            catch {
                Write-OutputColor "           Failed: $_" -color "Error"
                $errors++
            }
        }
    }
    else {
        $reason = if (Test-HyperVInstalled) { "already installed" } else { "not requested" }
        Write-OutputColor "  [$stepNum/$totalSteps] Hyper-V: skipped ($reason)" -color "Debug"
    }

    # Step 9: Install MPIO
    $stepNum++
    if ($Config.InstallMPIO -and -not (Test-MPIOInstalled)) {
        if (-not (Test-WindowsServer)) {
            Write-OutputColor "  [$stepNum/$totalSteps] MPIO: skipped (requires Windows Server)" -color "Warning"
            $errors++
        } else {
            Write-OutputColor "  [$stepNum/$totalSteps] Installing MPIO..." -color "Info"
            try {
                Install-WindowsFeature -Name Multipath-IO -ErrorAction Stop
                Write-OutputColor "           MPIO installed. Reboot required." -color "Success"
                $global:RebootNeeded = $true
                $changesApplied++
                Add-SessionChange -Category "System" -Description "Installed MPIO"
            }
            catch {
                Write-OutputColor "           Failed: $_" -color "Error"
                $errors++
            }
        }
    }
    else {
        $reason = if ($Config.InstallMPIO -and (Test-MPIOInstalled)) { "already installed" } else { "not requested" }
        Write-OutputColor "  [$stepNum/$totalSteps] MPIO: skipped ($reason)" -color "Debug"
    }

    # Step 10: Install Failover Clustering
    $stepNum++
    if ($Config.InstallFailoverClustering -and -not (Test-FailoverClusteringInstalled)) {
        if (-not (Test-WindowsServer)) {
            Write-OutputColor "  [$stepNum/$totalSteps] Failover Clustering: skipped (requires Windows Server)" -color "Warning"
            $errors++
        } else {
            Write-OutputColor "  [$stepNum/$totalSteps] Installing Failover Clustering..." -color "Info"
            try {
                Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools -ErrorAction Stop
                Write-OutputColor "           Failover Clustering installed. Reboot required." -color "Success"
                $global:RebootNeeded = $true
                $changesApplied++
                Add-SessionChange -Category "System" -Description "Installed Failover Clustering"
            }
            catch {
                Write-OutputColor "           Failed: $_" -color "Error"
                $errors++
            }
        }
    }
    else {
        $reason = if ($Config.InstallFailoverClustering -and (Test-FailoverClusteringInstalled)) { "already installed" } else { "not requested" }
        Write-OutputColor "  [$stepNum/$totalSteps] Failover Clustering: skipped ($reason)" -color "Debug"
    }

    # Step 11: Create local admin account
    $stepNum++
    if ($Config.CreateLocalAdmin) {
        $adminName = if ($Config.LocalAdminName) { $Config.LocalAdminName } else { $localadminaccountname }
        Write-OutputColor "  [$stepNum/$totalSteps] Creating local admin '$adminName'..." -color "Info"
        try {
            $existingUser = Get-LocalUser -Name $adminName -ErrorAction SilentlyContinue
            if ($existingUser) {
                Write-OutputColor "           Account '$adminName' already exists." -color "Warning"
            } else {
                $securePassword = Read-Host -Prompt "           Enter password for $adminName" -AsSecureString
                New-LocalUser -Name $adminName -Password $securePassword -FullName $adminName -Description "Local Admin" -PasswordNeverExpires -ErrorAction Stop | Out-Null
                Add-LocalGroupMember -Group "Administrators" -Member $adminName -ErrorAction Stop
                Write-OutputColor "           Local admin '$adminName' created and added to Administrators." -color "Success"
                $changesApplied++
                Add-SessionChange -Category "Security" -Description "Created local admin account '$adminName'"
            }
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Local admin: skipped" -color "Debug"
    }

    # Step 12: Disable built-in Administrator
    $stepNum++
    if ($Config.DisableBuiltInAdmin) {
        Write-OutputColor "  [$stepNum/$totalSteps] Disabling built-in Administrator..." -color "Info"
        try {
            $builtInAdmin = Get-LocalUser -Name "Administrator" -ErrorAction Stop
            if ($builtInAdmin.Enabled) {
                Disable-LocalUser -Name "Administrator" -ErrorAction Stop
                Write-OutputColor "           Built-in Administrator disabled." -color "Success"
                $changesApplied++
                Add-SessionChange -Category "Security" -Description "Disabled built-in Administrator account"
            } else {
                Write-OutputColor "           Already disabled." -color "Debug"
            }
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Disable built-in admin: skipped" -color "Debug"
    }

    # Step 13: Join domain (prompts for credentials - do near end)
    $stepNum++
    $isDomainJoined = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).PartOfDomain
    if ($Config.DomainName -and -not $isDomainJoined) {
        Write-OutputColor "  [$stepNum/$totalSteps] Joining domain '$($Config.DomainName)'..." -color "Info"
        try {
            $domainCred = Get-Credential -Message "Enter credentials to join $($Config.DomainName)"
            if ($domainCred) {
                Add-Computer -DomainName $Config.DomainName -Credential $domainCred -Force -ErrorAction Stop
                Write-OutputColor "           Joined domain. Reboot required." -color "Success"
                $global:RebootNeeded = $true
                $changesApplied++
                Add-SessionChange -Category "System" -Description "Joined domain $($Config.DomainName)"
            }
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
    }
    else {
        $reason = if ($isDomainJoined) { "already joined" } else { "not specified" }
        Write-OutputColor "  [$stepNum/$totalSteps] Domain join: skipped ($reason)" -color "Debug"
    }

    # Step 14: Install updates (long running - always last)
    $stepNum++
    if ($Config.InstallUpdates) {
        Write-OutputColor "  [$stepNum/$totalSteps] Installing Windows Updates (this may take a while)..." -color "Info"
        try {
            Install-WindowsUpdates
            $changesApplied++
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Windows Updates: skipped" -color "Debug"
    }

    # Step 15: Initialize Host Storage
    $stepNum++
    if ($Config.InitializeHostStorage -and $configType -eq "HOST") {
        Write-OutputColor "  [$stepNum/$totalSteps] Initializing host storage..." -color "Info"
        try {
            $driveLetter = $Config.HostStorageDrive
            if (-not $driveLetter) {
                # Auto-select first available non-C fixed NTFS drive
                $autoVol = Get-Volume -ErrorAction SilentlyContinue | Where-Object {
                    $_.DriveLetter -and $_.DriveLetter -ne 'C' -and $_.DriveType -eq 'Fixed' -and $_.FileSystem -eq 'NTFS'
                } | Select-Object -First 1
                if ($autoVol) { $driveLetter = $autoVol.DriveLetter }
            }
            if ($driveLetter) {
                $script:SelectedHostDrive = "$($driveLetter):"
                $script:HostVMStoragePath = "$($driveLetter):\Virtual Machines"
                $script:HostISOPath = "$($driveLetter):\ISOs"
                $script:VHDCachePath = "$($driveLetter):\Virtual Machines\_BaseImages"
                foreach ($folder in @($script:HostVMStoragePath, $script:HostISOPath, $script:VHDCachePath)) {
                    if (-not (Test-Path $folder)) {
                        New-Item -Path $folder -ItemType Directory -Force | Out-Null
                    }
                }
                # Set Hyper-V defaults if available
                $vmHost = Get-VMHost -ErrorAction SilentlyContinue
                if ($vmHost) {
                    Set-VMHost -VirtualMachinePath $script:HostVMStoragePath -ErrorAction SilentlyContinue
                    Set-VMHost -VirtualHardDiskPath $script:HostVMStoragePath -ErrorAction SilentlyContinue
                }
                Update-DefenderVMPaths
                $script:StorageInitialized = $true
                Write-OutputColor "           Storage initialized on $($driveLetter):" -color "Success"
                $changesApplied++
                Add-SessionChange -Category "Host Storage" -Description "Initialized $($driveLetter): for VM storage"
            } else {
                Write-OutputColor "           No suitable data drive found." -color "Warning"
            }
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Host storage: skipped" -color "Debug"
    }

    # Step 16: Create SET Switch
    $stepNum++
    if ($Config.CreateSETSwitch -and $configType -eq "HOST") {
        Write-OutputColor "  [$stepNum/$totalSteps] Creating SET switch '$($Config.SETSwitchName)'..." -color "Info"
        try {
            $switchName = if ($Config.SETSwitchName) { $Config.SETSwitchName } else { $SwitchName }
            $mgmtName = if ($Config.SETManagementName) { $Config.SETManagementName } else { $ManagementName }
            # Find adapters with internet for SET
            $internetAdapters = Test-AdapterInternetConnectivity | Where-Object { $_.HasInternet }
            if ($internetAdapters.Count -ge 1) {
                $adapterNames = @($internetAdapters | ForEach-Object { $_.Name })
                New-VMSwitch -Name $switchName -NetAdapterName $adapterNames -EnableEmbeddedTeaming $true -AllowManagementOS $true -ErrorAction Stop
                Set-VMSwitchTeam -Name $switchName -LoadBalancingAlgorithm Dynamic -ErrorAction SilentlyContinue
                # Wait for management adapter
                for ($wait = 0; $wait -lt 15; $wait++) {
                    $vnic = Get-VMNetworkAdapter -ManagementOS -Name $switchName -ErrorAction SilentlyContinue
                    if ($vnic) { break }
                    Start-Sleep -Seconds 1
                }
                Rename-VMNetworkAdapter -ManagementOS -Name $switchName -NewName $mgmtName -ErrorAction SilentlyContinue
                # Store non-internet adapters for iSCSI
                $script:iSCSICandidateAdapters = Test-AdapterInternetConnectivity | Where-Object { -not $_.HasInternet }
                Write-OutputColor "           SET '$switchName' created with $($adapterNames.Count) adapter(s)." -color "Success"
                $changesApplied++
                Add-SessionChange -Category "Network" -Description "Created SET '$switchName'"
            } else {
                Write-OutputColor "           No adapters with internet found for SET." -color "Warning"
            }
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] SET switch: skipped" -color "Debug"
    }

    # Step 17: Configure iSCSI
    $stepNum++
    if ($Config.ConfigureiSCSI -and $configType -eq "HOST") {
        Write-OutputColor "  [$stepNum/$totalSteps] Configuring iSCSI..." -color "Info"
        try {
            $hostNum = $Config.iSCSIHostNumber
            if ($null -eq $hostNum) {
                $hostNum = Get-HostNumberFromHostname
            }
            if ($null -ne $hostNum -and $hostNum -ge 1 -and $hostNum -le 24) {
                $ip1 = Get-iSCSIAutoIP -HostNumber $hostNum -PortNumber 1
                $ip2 = Get-iSCSIAutoIP -HostNumber $hostNum -PortNumber 2
                # Find iSCSI candidate adapters (non-internet, non-virtual)
                $iscsiAdapters = @()
                if ($script:iSCSICandidateAdapters) {
                    $iscsiAdapters = $script:iSCSICandidateAdapters | ForEach-Object { $_.Adapter }
                } else {
                    $iscsiAdapters = Get-NetAdapter | Where-Object {
                        $_.Name -notlike "vEthernet*" -and
                        $_.InterfaceDescription -notlike "*Hyper-V*" -and
                        $_.InterfaceDescription -notlike "*Virtual*"
                    }
                }
                if ($iscsiAdapters.Count -ge 2) {
                    $aSide = $iscsiAdapters[0]
                    $bSide = $iscsiAdapters[1]
                    # Configure A-side
                    Remove-NetIPAddress -InterfaceAlias $aSide.Name -Confirm:$false -ErrorAction SilentlyContinue
                    Remove-NetRoute -InterfaceAlias $aSide.Name -Confirm:$false -ErrorAction SilentlyContinue
                    New-NetIPAddress -InterfaceAlias $aSide.Name -IPAddress $ip1 -PrefixLength 24 -ErrorAction Stop
                    Disable-NetAdapterBinding -Name $aSide.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
                    # Configure B-side
                    Remove-NetIPAddress -InterfaceAlias $bSide.Name -Confirm:$false -ErrorAction SilentlyContinue
                    Remove-NetRoute -InterfaceAlias $bSide.Name -Confirm:$false -ErrorAction SilentlyContinue
                    New-NetIPAddress -InterfaceAlias $bSide.Name -IPAddress $ip2 -PrefixLength 24 -ErrorAction Stop
                    Disable-NetAdapterBinding -Name $bSide.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
                    Write-OutputColor "           iSCSI configured: A=$ip1, B=$ip2" -color "Success"
                    $changesApplied++
                    Add-SessionChange -Category "Network" -Description "Configured iSCSI: A-side $ip1, B-side $ip2"
                } else {
                    Write-OutputColor "           Not enough iSCSI adapters found (need 2, found $($iscsiAdapters.Count))." -color "Warning"
                }
            } else {
                Write-OutputColor "           Could not determine host number for iSCSI." -color "Warning"
            }
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] iSCSI: skipped" -color "Debug"
    }

    # Step 18: Configure MPIO
    $stepNum++
    if ($Config.ConfigureMPIO -and $configType -eq "HOST") {
        Write-OutputColor "  [$stepNum/$totalSteps] Configuring MPIO for iSCSI..." -color "Info"
        try {
            if (Test-MPIOInstalled) {
                Enable-MSDSMAutomaticClaim -BusType iSCSI -ErrorAction Stop
                Set-MSDSMGlobalDefaultLoadBalancePolicy -Policy RR -ErrorAction Stop
                Write-OutputColor "           MPIO configured (Round Robin)." -color "Success"
                $changesApplied++
                Add-SessionChange -Category "System" -Description "Configured MPIO for iSCSI"
            } else {
                Write-OutputColor "           MPIO not installed. Install it first (step 9)." -color "Warning"
            }
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] MPIO config: skipped" -color "Debug"
    }

    # Step 19: Configure Defender Exclusions
    $stepNum++
    if ($Config.ConfigureDefenderExclusions -and $configType -eq "HOST") {
        Write-OutputColor "  [$stepNum/$totalSteps] Configuring Defender exclusions..." -color "Info"
        try {
            $allPaths = @($script:DefenderExclusionPaths) + @($script:DefenderCommonVMPaths)
            $addedCount = 0
            foreach ($path in $allPaths) {
                if ($path) {
                    Add-MpPreference -ExclusionPath $path -ErrorAction SilentlyContinue
                    $addedCount++
                }
            }
            # Add process exclusions
            $defenderProcesses = @("vmms.exe", "vmwp.exe", "vmcompute.exe")
            foreach ($proc in $defenderProcesses) {
                Add-MpPreference -ExclusionProcess $proc -ErrorAction SilentlyContinue
            }
            Write-OutputColor "           Added $addedCount path exclusions and $($defenderProcesses.Count) process exclusions." -color "Success"
            $changesApplied++
            Add-SessionChange -Category "Security" -Description "Configured Defender exclusions for Hyper-V"
        }
        catch {
            Write-OutputColor "           Failed: $_" -color "Error"
            $errors++
        }
    }
    else {
        Write-OutputColor "  [$stepNum/$totalSteps] Defender exclusions: skipped" -color "Debug"
    }

    # Summary
    Write-OutputColor "" -color "Info"
    Write-OutputColor ("=" * 65) -color "Info"
    $resultColor = if ($errors -eq 0) { "Success" } else { "Warning" }
    Write-OutputColor "  BATCH MODE COMPLETE: $changesApplied succeeded, $errors failed" -color $resultColor
    Write-OutputColor "  Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -color "Info"
    Write-OutputColor ("=" * 65) -color "Info"
    Write-OutputColor "" -color "Info"

    # Show session summary
    Show-SessionSummary

    # Stop transcript
    Stop-ScriptTranscript

    # Auto-reboot if needed and configured
    if ($global:RebootNeeded -and $Config.AutoReboot) {
        Write-OutputColor "Rebooting in 10 seconds... (Ctrl+C to cancel)" -color "Warning"
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    }
    elseif ($global:RebootNeeded) {
        Write-OutputColor "⚠ Reboot required to complete changes. AutoReboot is disabled." -color "Warning"
        Write-OutputColor "  Run 'Restart-Computer' when ready." -color "Info"
    }
}

# Check for batch config file (only if script path is valid)
if ($script:ScriptPath) {
    $scriptDir = Split-Path -Parent $script:ScriptPath
    $batchConfigPath = Join-Path $scriptDir "batch_config.json"
    if (Test-Path $batchConfigPath) {
        # Verify elevation before batch mode
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-Host "ERROR: Batch mode requires administrator privileges." -ForegroundColor Red
            Exit 1
        }
        try {
            $batchConfig = Get-Content $batchConfigPath -Raw | ConvertFrom-Json
            $configHash = @{}
            $batchConfig.PSObject.Properties | ForEach-Object { $configHash[$_.Name] = $_.Value }
            Start-BatchMode -Config $configHash
            Exit
        }
        catch {
            Write-OutputColor "Failed to load batch config: $_" -color "Error"
        }
    }
}

#endregion