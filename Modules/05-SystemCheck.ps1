#region ===== SYSTEM CHECK FUNCTIONS =====
# Check if running on Windows Server (vs client/workstation)
function Test-WindowsServer {
    try {
        # Registry first (faster, immune to WMI hangs)
        $productType = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions' -ErrorAction Stop).ProductType
        return ($productType -ne "WinNT")  # WinNT = Workstation, ServerNT/LanmanNT = Server/DC
    }
    catch {
        try {
            $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
            if ($null -eq $osInfo) { return $false }
            return ($osInfo.ProductType -ne 1)
        }
        catch { return $false }
    }
}

# Centralized Windows activation check (replaces duplicate CIM queries across modules)
function Test-WindowsActivated {
    try {
        $license = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationId='$($script:WindowsLicensingAppId)' AND LicenseStatus=1" -ErrorAction SilentlyContinue
        return ($null -ne $license)
    }
    catch {
        return $false
    }
}

# Function to check if Hyper-V is installed
function Test-HyperVInstalled {
    try {
        # Check if this is Windows Server or Windows Client
        $isServer = Test-WindowsServer

        if ($isServer) {
            # Windows Server - check using Get-WindowsFeature
            $hypervFeature = Get-WindowsFeature -Name Hyper-V -ErrorAction SilentlyContinue
            if ($hypervFeature -and $hypervFeature.InstallState -eq "Installed") {
                return $true
            }
        }
        else {
            # Windows Client - check using Get-WindowsOptionalFeature
            $hypervFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -ErrorAction SilentlyContinue
            if ($hypervFeature -and $hypervFeature.State -eq "Enabled") {
                return $true
            }
        }

        return $false
    }
    catch {
        return $false
    }
}

# Function to check if reboot is pending
function Test-RebootPending {
    $rebootKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    )

    foreach ($path in $rebootKeys) {
        if (Test-Path $path) {
            return $true
        }
    }

    # PendingFileRenameOperations is a registry value, not a key — Test-Path won't find it
    try {
        $pfro = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($null -ne $pfro) {
            return $true
        }
    }
    catch {
        # Ignore errors
    }

    # Check for pending computer rename
    try {
        $computerName = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName" -Name ComputerName -ErrorAction SilentlyContinue
        $activeComputerName = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName" -Name ComputerName -ErrorAction SilentlyContinue

        if ($computerName -and $activeComputerName -and $computerName.ComputerName -ne $activeComputerName.ComputerName) {
            return $true
        }
    }
    catch {
        # Ignore errors
    }

    # Check for pending RunOnce actions
    try {
        $runOnce = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -ErrorAction SilentlyContinue
        if ($null -ne $runOnce) {
            # Filter out the default PS properties to check for actual values
            $valueNames = @($runOnce.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }).Count
            if ($valueNames -gt 0) {
                return $true
            }
        }
    }
    catch {
        # Ignore errors
    }

    return $false
}

# Function to check available disk space
function Test-MinimumDiskSpace {
    param(
        [string]$DriveLetter = $env:SystemDrive.TrimEnd(':'),
        [int]$MinimumGB = 5
    )
    try {
        $drive = Get-PSDrive -Name $DriveLetter -ErrorAction Stop
        $freeGB = [math]::Round($drive.Free / 1GB, 1)
        if ($freeGB -lt $MinimumGB) {
            Write-OutputColor "  WARNING: Drive ${DriveLetter}: has only ${freeGB} GB free (minimum: ${MinimumGB} GB)" -color "Warning"
            return $false
        }
        return $true
    } catch {
        return $true  # Don't block if we can't check
    }
}

# Function to verify minimum PowerShell version
function Test-PowerShellVersion {
    $minMajor = 5
    $minMinor = 1
    $current = $PSVersionTable.PSVersion
    if ($current.Major -lt $minMajor -or ($current.Major -eq $minMajor -and $current.Minor -lt $minMinor)) {
        Write-OutputColor "  WARNING: PowerShell $($current.Major).$($current.Minor) detected. Minimum required: $minMajor.$minMinor" -color "Warning"
        return $false
    }
    return $true
}

# Function to check Hyper-V minimum hardware requirements
function Test-HyperVMinimumSpecs {
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        $mem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue

        $issues = @()

        if ($null -ne $cpu -and $cpu.NumberOfLogicalProcessors -lt 2) {
            $issues += "CPU: $($cpu.NumberOfLogicalProcessors) logical processors (minimum: 2)"
        }

        if ($null -ne $mem) {
            $totalGB = [math]::Round($mem.TotalPhysicalMemory / 1GB, 1)
            if ($totalGB -lt 4) {
                $issues += "RAM: ${totalGB} GB installed (minimum: 4 GB for Hyper-V)"
            }
        }

        if ($issues.Count -gt 0) {
            Write-OutputColor "  Hyper-V minimum spec warnings:" -color "Warning"
            foreach ($issue in $issues) {
                Write-OutputColor "    - $issue" -color "Warning"
            }
            return $false
        }
        return $true
    } catch {
        return $true  # Don't block if we can't check
    }
}

# Function to test network connectivity
function Test-NetworkConnectivity {
    param (
        [string]$Target = $script:DefaultConnectivityTarget
    )

    try {
        $ping = Test-Connection -ComputerName $Target -Count 1 -Quiet -ErrorAction SilentlyContinue
        return $ping
    }
    catch {
        return $false
    }
}

# Function to check RDP state
function Get-RDPState {
    try {
        $rdpStatus = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -ErrorAction SilentlyContinue
        if ($null -ne $rdpStatus -and $rdpStatus.fDenyTSConnections -eq 0) {
            return "Enabled"
        }
        else {
            return "Disabled"
        }
    }
    catch {
        return "Unknown"
    }
}

# Function to get WinRM/PowerShell Remoting state
function Get-WinRMState {
    try {
        $winrmService = Get-Service -Name WinRM -ErrorAction SilentlyContinue
        if ($null -eq $winrmService) {
            return "N/A"
        }

        if ($winrmService.Status -ne "Running") {
            return "Disabled"
        }

        # Service is running — check if fully configured (not just default state)
        $checks = 0
        $passed = 0

        # 1. Listener configured
        $checks++
        try {
            $listener = Get-ChildItem -Path WSMan:\localhost\Listener -ErrorAction Stop 2>$null
            if ($listener) { $passed++ }
        } catch {}

        # 2. Service set to Automatic (not just manually started)
        $checks++
        if ($winrmService.StartType -eq 'Automatic') { $passed++ }

        # 3. PSSession configuration exists (Enable-PSRemoting creates these)
        $checks++
        try {
            $sessions = @(Get-PSSessionConfiguration -ErrorAction Stop 2>$null)
            if ($sessions.Count -gt 0) { $passed++ }
        } catch {}

        # 4. WinRM firewall rules enabled
        $checks++
        try {
            $fwRules = @(Get-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction Stop |
                Where-Object { $_.Enabled -eq $true -and $_.Direction -eq 'Inbound' })
            if ($fwRules.Count -gt 0) { $passed++ }
        } catch {}

        if ($passed -eq $checks) {
            return "Enabled"
        } elseif ($passed -gt 0) {
            return "Partial"
        } else {
            return "Partial"
        }
    }
    catch {
        return "Unknown"
    }
}

# Function to get firewall state
function Get-FirewallState {
    try {
        # Registry first (faster, immune to WMI/CIM hangs)
        $fwBase = 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy'
        $domainEnabled  = (Get-ItemProperty "$fwBase\DomainProfile"  -Name EnableFirewall -ErrorAction Stop).EnableFirewall
        $privateEnabled = (Get-ItemProperty "$fwBase\StandardProfile" -Name EnableFirewall -ErrorAction Stop).EnableFirewall
        $publicEnabled  = (Get-ItemProperty "$fwBase\PublicProfile"  -Name EnableFirewall -ErrorAction Stop).EnableFirewall
        return @{
            Domain  = if ($domainEnabled -eq 1) { "Enabled" } else { "Disabled" }
            Private = if ($privateEnabled -eq 1) { "Enabled" } else { "Disabled" }
            Public  = if ($publicEnabled -eq 1) { "Enabled" } else { "Disabled" }
        }
    }
    catch {
        # Fallback to cmdlet if registry path doesn't exist
        try {
            $domainProfile  = Get-NetFirewallProfile -Profile Domain -ErrorAction SilentlyContinue
            $privateProfile = Get-NetFirewallProfile -Profile Private -ErrorAction SilentlyContinue
            $publicProfile  = Get-NetFirewallProfile -Profile Public -ErrorAction SilentlyContinue
            return @{
                Domain  = if ($null -ne $domainProfile -and $domainProfile.Enabled -eq $true) { "Enabled" } else { "Disabled" }
                Private = if ($null -ne $privateProfile -and $privateProfile.Enabled -eq $true) { "Enabled" } else { "Disabled" }
                Public  = if ($null -ne $publicProfile -and $publicProfile.Enabled -eq $true) { "Enabled" } else { "Disabled" }
            }
        }
        catch {
            return @{
                Domain  = "Unknown"
                Private = "Unknown"
                Public  = "Unknown"
            }
        }
    }
}

# Function to test all connectivity
function Test-AllConnectivity {
    Clear-Host
    Write-CenteredOutput "Network Connectivity Test" -color "Info"

    Write-OutputColor "  Testing network connectivity..." -color "Info"
    Write-OutputColor "" -color "Info"

    $results = @()

    # Get default gateway
    $gateway = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop

    # Test targets - universal + first entry from each custom DNS preset
    $targets = @(
        @{ Name = "Default Gateway"; Target = $gateway; Critical = $true }
        @{ Name = "Google DNS"; Target = "8.8.8.8"; Critical = $false }
        @{ Name = "Cloudflare DNS"; Target = "1.1.1.1"; Critical = $false }
    )
    # Add first IP from each custom (non-built-in) DNS preset
    $builtinDNSNames = @("Google DNS", "Cloudflare", "OpenDNS", "Quad9")
    foreach ($key in $script:DNSPresets.Keys) {
        if ($key -notin $builtinDNSNames -and $script:DNSPresets[$key].Count -gt 0) {
            $targets += @{ Name = "$key Primary"; Target = $script:DNSPresets[$key][0]; Critical = $false }
        }
    }

    foreach ($item in $targets) {
        if ([string]::IsNullOrWhiteSpace($item.Target)) {
            Write-OutputColor "[ ? ] $($item.Name): Not configured" -color "Warning"
            continue
        }

        Write-Host "Testing $($item.Name) ($($item.Target))... " -NoNewline

        $pingResult = Test-Connection -ComputerName $item.Target -Count 1 -ErrorAction SilentlyContinue

        if ($pingResult) {
            # Get latency
            $latency = $pingResult.ResponseTime
            Write-Host ""
            Write-OutputColor "[OK ] $($item.Name) ($($item.Target)) - ${latency}ms" -color "Success"
            $results += @{ Name = $item.Name; Status = "OK"; Latency = $latency }
        }
        else {
            Write-Host ""
            $color = if ($item.Critical) { "Error" } else { "Warning" }
            Write-OutputColor "[FAIL] $($item.Name) ($($item.Target)) - Not reachable" -color $color
            $results += @{ Name = $item.Name; Status = "FAIL"; Latency = $null }
        }
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor ("-" * 50) -color "Info"

    # Summary
    $okCount = @($results | Where-Object { $_.Status -eq "OK" }).Count
    $failCount = @($results | Where-Object { $_.Status -eq "FAIL" }).Count

    if ($failCount -eq 0) {
        Write-OutputColor "  All connectivity tests passed!" -color "Success"
    }
    elseif ($okCount -gt 0) {
        Write-OutputColor "  Partial connectivity: $okCount passed, $failCount failed" -color "Warning"
    }
    else {
        Write-OutputColor "  No connectivity! Check network configuration." -color "Error"
    }

    # DNS resolution test
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Testing DNS resolution..." -color "Info"
    try {
        $dnsTest = Resolve-DnsName -Name "google.com" -Type A -ErrorAction Stop
        Write-OutputColor "[OK ] DNS resolution working (google.com -> $(($dnsTest | Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress }) -join ', '))" -color "Success"
    }
    catch {
        Write-OutputColor "[FAIL] DNS resolution failed" -color "Error"
    }
}

# Function to get current power plan
function Get-CurrentPowerPlan {
    try {
        $activePlan = powercfg /getactivescheme
        if ($activePlan -match 'Power Scheme GUID: ([a-f0-9-]+)\s+\((.+)\)') {
            $regexMatches = $matches
            return @{
                GUID = $regexMatches[1]
                Name = $regexMatches[2]
            }
        }
        return @{ GUID = "Unknown"; Name = "Unknown" }
    }
    catch {
        return @{ GUID = "Unknown"; Name = "Unknown" }
    }
}

# Function to configure power plan
function Set-ServerPowerPlan {
    Clear-Host
    Write-CenteredOutput "Power Plan Configuration" -color "Info"

    $currentPlan = Get-CurrentPowerPlan
    Write-OutputColor "  Current Power Plan: $($currentPlan.Name)" -color "Info"
    Write-OutputColor "" -color "Info"

    $powerPlans = @{
        "1" = @{ GUID = $script:PowerPlanGUID["High Performance"]; Name = "High Performance" }
        "2" = @{ GUID = $script:PowerPlanGUID["Balanced"]; Name = "Balanced" }
        "3" = @{ GUID = $script:PowerPlanGUID["Power Saver"]; Name = "Power Saver" }
    }

    Write-OutputColor "  Available Power Plans:" -color "Info"
    Write-OutputColor "  1. High Performance (Recommended for servers)" -color "Success"
    Write-OutputColor "  2. Balanced" -color "Info"
    Write-OutputColor "  3. Power Saver" -color "Info"
    Write-OutputColor "  4. Cancel" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"

    # Check for navigation
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) {
        if (Invoke-NavigationAction -NavResult $navResult) { return }
    }

    if ($choice -eq "4" -or [string]::IsNullOrWhiteSpace($choice)) {
        Write-OutputColor "  Power plan not changed." -color "Info"
        return
    }

    if (-not $powerPlans.ContainsKey($choice)) {
        Write-OutputColor "  Invalid selection. Enter 1-4." -color "Error"
        return
    }

    $selectedPlan = $powerPlans[$choice]

    if ($selectedPlan.GUID -eq $currentPlan.GUID) {
        Write-OutputColor "  Power plan is already set to $($selectedPlan.Name)." -color "Info"
        return
    }

    try {
        # Set the power plan
        $null = powercfg /setactive $selectedPlan.GUID 2>&1

        # Verify it was set
        $newPlan = Get-CurrentPowerPlan
        if ($newPlan.GUID -eq $selectedPlan.GUID) {
            Write-OutputColor "  Power plan set to: $($selectedPlan.Name)" -color "Success"
            Add-SessionChange -Category "System" -Description "Set power plan to $($selectedPlan.Name)"
            Add-UndoAction -Category "System" -Description "Set power plan to $($selectedPlan.Name)" -UndoScript {
                param($OldGUID)
                powercfg /setactive $OldGUID
            }.GetNewClosure() -UndoParams @{ OldGUID = $currentPlan.GUID }
            Clear-MenuCache  # Invalidate cache after change
        }
        else {
            Write-OutputColor "  Failed to set power plan. May need to run as administrator." -color "Error"
        }
    }
    catch {
        Write-OutputColor "  Error setting power plan: $_" -color "Error"
    }
}

# Shared helper for installing a Windows feature with a job and timeout
# Returns @{ Success=$bool; TimedOut=$bool; Result=$jobResult }
function Install-WindowsFeatureWithTimeout {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$FeatureName,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName,

        [switch]$IncludeManagementTools
    )

    $elapsed = 0
    $scriptBlock = if ($IncludeManagementTools) {
        { param($name) Install-WindowsFeature -Name $name -IncludeManagementTools -ErrorAction Stop }
    } else {
        { param($name) Install-WindowsFeature -Name $name -ErrorAction Stop }
    }

    $installJob = Start-Job -ScriptBlock $scriptBlock -ArgumentList $FeatureName

    while ($installJob.State -eq "Running") {
        Show-ProgressMessage -Activity "Installing $DisplayName" -Status "Please wait..." -SecondsElapsed $elapsed
        Start-Sleep -Seconds 1
        $elapsed++
        if ($elapsed -gt $script:FeatureInstallTimeoutSeconds) {
            Stop-Job $installJob -ErrorAction SilentlyContinue
            Remove-Job $installJob -Force -ErrorAction SilentlyContinue
            Write-Host ""
            Complete-ProgressMessage -Activity "$DisplayName installation" -Status "Timed out" -Failed
            Write-OutputColor "  Installation timed out after 30 minutes." -color "Error"
            return @{ Success = $false; TimedOut = $true; Result = $null }
        }
    }
    Write-Host ""

    $result = Receive-Job $installJob -ErrorAction SilentlyContinue
    $jobFailed = $installJob.State -eq "Failed"
    # Extract job errors before removing the job (lost otherwise)
    $jobError = $null
    if ($jobFailed) {
        try {
            if ($installJob.ChildJobs.Count -gt 0) {
                $jobError = $installJob.ChildJobs[0].Error | Out-String
            }
        } catch {
            Write-OutputColor "  Could not extract job error details: $_" -color "Warning"
        }
        if (-not $jobError) { $jobError = "Job failed without error details. Check Windows Event Log." }
    }
    Remove-Job $installJob -Force -ErrorAction SilentlyContinue

    # Install-WindowsFeature returns a CimInstance with ExitCode, not a hashtable with .Success
    $succeeded = (-not $jobFailed) -and ($null -ne $result) -and
        ($result.ExitCode -eq 'Success' -or $result.ExitCode -eq 'NoChangeNeeded' -or
         $null -ne $result.RestartNeeded)

    if ($succeeded) {
        Complete-ProgressMessage -Activity "$DisplayName installation" -Status "Complete" -Success
        return @{ Success = $true; TimedOut = $false; Result = $result; Error = $null }
    }
    else {
        Complete-ProgressMessage -Activity "$DisplayName installation" -Status "Failed" -Failed
        if ($jobError) {
            Write-OutputColor "  Error details: $($jobError.Trim())" -color "Error"
        }
        return @{ Success = $false; TimedOut = $false; Result = $result; Error = $jobError }
    }
}

# Pre-flight prerequisite checks for feature installations
function Test-FeaturePrerequisites {
    param([string]$Feature)

    $checks = @()

    # Common check: pending reboot
    $rebootPending = Test-RebootPending
    $checks += @{
        Name    = "Pending Reboot"
        Status  = if ($rebootPending) { "Fail" } else { "Pass" }
        Message = if ($rebootPending) { "Reboot required before installing features" } else { "No reboot pending" }
    }

    # Common check: PowerShell version
    $psVersionOK = Test-PowerShellVersion
    $checks += @{
        Name    = "PowerShell Version"
        Status  = if ($psVersionOK) { "Pass" } else { "Fail" }
        Message = if ($psVersionOK) { "PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)" } else { "PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor) (minimum 5.1 required)" }
    }

    # Common check: disk space
    $diskOK = Test-MinimumDiskSpace
    $checks += @{
        Name    = "Disk Space"
        Status  = if ($diskOK) { "Pass" } else { "Warn" }
        Message = if ($diskOK) { "Sufficient free space on system drive" } else { "Low disk space on system drive" }
    }

    switch ($Feature) {
        "Hyper-V" {
            # Batch CIM queries with timeout (immune to WMI hangs)
            $hvCim = Invoke-WithTimeout -ScriptBlock {
                @{
                    CPU  = Get-CimInstance -ClassName Win32_Processor -OperationTimeoutSec 8 -ErrorAction SilentlyContinue | Select-Object -First 1
                    CS   = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
                    Disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
                }
            } -TimeoutSeconds 10 -Activity "Checking Hyper-V prerequisites"

            if ($hvCim.TimedOut) {
                $cpu = $null; $cs = $null; $sysDisk = $null
            } else {
                $cpu = $hvCim.Result.CPU; $cs = $hvCim.Result.CS; $sysDisk = $hvCim.Result.Disk
            }

            # CPU cores
            $cores = if ($cpu) { $cpu.NumberOfCores } else { 0 }
            $checks += @{
                Name    = "CPU Cores"
                Status  = if ($cores -ge 4) { "Pass" } elseif ($cores -ge 2) { "Warn" } else { "Fail" }
                Message = if ($cores -ge 4) { "$cores cores (4+ recommended)" } elseif ($cores -ge 2) { "$cores cores (minimum met, 4+ recommended)" } else { "$cores cores (minimum 2 required)" }
            }

            # Virtualization support
            $vtEnabled = if ($cpu) { $cpu.VirtualizationFirmwareEnabled } else { $false }
            $checks += @{
                Name    = "CPU Virtualization"
                Status  = if ($vtEnabled) { "Pass" } else { "Fail" }
                Message = if ($vtEnabled) { "VT-x/AMD-V enabled in firmware" } else { "VT-x/AMD-V not detected - enable in BIOS/UEFI" }
            }

            # RAM
            $ramGB = if ($cs) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) } else { 0 }
            $checks += @{
                Name    = "Physical RAM"
                Status  = if ($ramGB -ge 8) { "Pass" } elseif ($ramGB -ge 4) { "Warn" } else { "Fail" }
                Message = if ($ramGB -ge 8) { "${ramGB} GB (8+ recommended)" } elseif ($ramGB -ge 4) { "${ramGB} GB (minimum met, 8+ recommended for VMs)" } else { "${ramGB} GB (minimum 4 GB required)" }
            }

            # Disk space
            $freeGB = if ($sysDisk) { [math]::Round($sysDisk.FreeSpace / 1GB, 1) } else { 0 }
            $checks += @{
                Name    = "Disk Space (C:)"
                Status  = if ($freeGB -ge 20) { "Pass" } elseif ($freeGB -ge 10) { "Warn" } else { "Fail" }
                Message = if ($freeGB -ge 20) { "${freeGB} GB free" } elseif ($freeGB -ge 10) { "${freeGB} GB free (20+ GB recommended)" } else { "${freeGB} GB free (minimum 10 GB required)" }
            }

            # Hyper-V minimum hardware specs
            $hvSpecsOK = Test-HyperVMinimumSpecs
            $checks += @{
                Name    = "Hardware Specs"
                Status  = if ($hvSpecsOK) { "Pass" } else { "Warn" }
                Message = if ($hvSpecsOK) { "CPU and RAM meet Hyper-V minimums" } else { "Hardware below recommended Hyper-V minimums" }
            }
        }

        "MPIO" {
            # Must be Windows Server
            $isServer = Test-WindowsServer
            $checks += @{
                Name    = "Windows Server"
                Status  = if ($isServer) { "Pass" } else { "Fail" }
                Message = if ($isServer) { "Server OS detected" } else { "MPIO requires Windows Server" }
            }

            # Check for multiple network paths (iSCSI NICs)
            $physicalNICs = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" })
            $checks += @{
                Name    = "Physical NICs"
                Status  = if ($physicalNICs.Count -ge 3) { "Pass" } elseif ($physicalNICs.Count -ge 2) { "Warn" } else { "Fail" }
                Message = if ($physicalNICs.Count -ge 3) { "$($physicalNICs.Count) up (management + multipath)" } elseif ($physicalNICs.Count -ge 2) { "$($physicalNICs.Count) up (minimum for multipath)" } else { "$($physicalNICs.Count) up (need 2+ for multipath)" }
            }
        }

        "FailoverClustering" {
            # Must be Windows Server
            $isServer = Test-WindowsServer
            $checks += @{
                Name    = "Windows Server"
                Status  = if ($isServer) { "Pass" } else { "Fail" }
                Message = if ($isServer) { "Server OS detected" } else { "Failover Clustering requires Windows Server" }
            }

            # Domain membership (with timeout protection)
            $fcCim = Invoke-WithTimeout -ScriptBlock {
                Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec 8 -ErrorAction SilentlyContinue
            } -TimeoutSeconds 10 -Activity "Checking cluster prerequisites"
            $cs = if ($fcCim.TimedOut) { $null } else { $fcCim.Result }
            $inDomain = if ($cs) { $cs.PartOfDomain } else { $false }
            $checks += @{
                Name    = "Domain Joined"
                Status  = if ($inDomain) { "Pass" } else { "Fail" }
                Message = if ($inDomain) { "Joined to $($cs.Domain)" } else { "Failover Clustering requires Active Directory domain membership" }
            }

            # Hyper-V (recommended for Hyper-V clusters)
            $hvInstalled = Test-HyperVInstalled
            $checks += @{
                Name    = "Hyper-V Role"
                Status  = if ($hvInstalled) { "Pass" } else { "Warn" }
                Message = if ($hvInstalled) { "Installed (ready for Hyper-V cluster)" } else { "Not installed (install first for Hyper-V clusters)" }
            }
        }

        "iSCSI" {
            # Physical NICs for iSCSI paths
            $physicalNICs = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" })
            $checks += @{
                Name    = "Physical NICs"
                Status  = if ($physicalNICs.Count -ge 3) { "Pass" } elseif ($physicalNICs.Count -ge 2) { "Warn" } else { "Fail" }
                Message = if ($physicalNICs.Count -ge 3) { "$($physicalNICs.Count) up (management + 2 iSCSI paths)" } elseif ($physicalNICs.Count -ge 2) { "$($physicalNICs.Count) up (limited multipath)" } else { "Need 3+ NICs (1 mgmt + 2 iSCSI)" }
            }

            # iSCSI service
            $iscsiSvc = Get-Service -Name MSiSCSI -ErrorAction SilentlyContinue
            $checks += @{
                Name    = "iSCSI Service"
                Status  = if ($iscsiSvc -and $iscsiSvc.Status -eq "Running") { "Pass" } elseif ($iscsiSvc) { "Warn" } else { "Fail" }
                Message = if ($iscsiSvc -and $iscsiSvc.Status -eq "Running") { "MSiSCSI running" } elseif ($iscsiSvc) { "MSiSCSI installed but $($iscsiSvc.Status)" } else { "MSiSCSI service not found" }
            }
        }
    }

    return $checks
}

# Display pre-flight check results and return $true if no blocking failures
function Show-PreFlightCheck {
    param([string]$Feature)

    $checks = Test-FeaturePrerequisites -Feature $Feature

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Pre-Flight Check: $Feature" -color "Info"
    Write-OutputColor "  $('-' * 50)" -color "Info"

    $hasBlocker = $false
    foreach ($check in $checks) {
        $icon = switch ($check.Status) {
            "Pass" { "[OK]" }
            "Warn" { "[!!]" }
            "Fail" { "[XX]" }
        }
        $color = switch ($check.Status) {
            "Pass" { "Success" }
            "Warn" { "Warning" }
            "Fail" { "Error" }
        }
        Write-OutputColor "  $icon $($check.Name): $($check.Message)" -color $color
        if ($check.Status -eq "Fail") { $hasBlocker = $true }
    }

    Write-OutputColor "  $('-' * 50)" -color "Info"

    if ($hasBlocker) {
        Write-OutputColor "  [!] Blocking issues detected. Resolve before installing." -color "Error"
        Write-OutputColor "" -color "Info"
        return $false
    }

    $warnings = @($checks | Where-Object { $_.Status -eq "Warn" })
    if ($warnings.Count -gt 0) {
        Write-OutputColor "  $($warnings.Count) warning(s) - installation can proceed" -color "Warning"
    }
    else {
        Write-OutputColor "  All checks passed" -color "Success"
    }
    Write-OutputColor "" -color "Info"
    return $true
}
#endregion