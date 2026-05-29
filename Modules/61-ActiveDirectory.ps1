#region ===== ACTIVE DIRECTORY PROMOTION =====
# Function to check if AD-Domain-Services feature is installed
function Test-ADDSInstalled {
    if (-not (Test-WindowsServer)) { return $false }
    try {
        $feature = Get-WindowsFeature -Name AD-Domain-Services -ErrorAction SilentlyContinue
        return ($null -ne $feature -and $feature.Installed)
    }
    catch {
        return $false
    }
}

# Function to check AD DS prerequisites before promotion
function Test-ADDSPrerequisites {
    $checks = @()

    # Check 1: Server OS
    $isServer = Test-WindowsServer
    $checks += @{
        Name   = "Windows Server OS"
        Passed = $isServer
        Detail = if ($isServer) { "Running Windows Server" } else { "AD DS requires Windows Server" }
    }

    # Check 2: Static IP configured
    $staticIP = $false
    try {
        $adapters = Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object {
            $null -ne $_.IPv4Address -and @($_.IPv4Address).Count -gt 0
        }
        foreach ($adapter in $adapters) {
            $ifIndex = $adapter.InterfaceIndex
            $ipInterface = Get-NetIPInterface -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            if ($null -ne $ipInterface -and $ipInterface.Dhcp -eq "Disabled") {
                $staticIP = $true
                break
            }
        }
    }
    catch {
        # Ignore - will show as failed
    }
    $checks += @{
        Name   = "Static IP Address"
        Passed = $staticIP
        Detail = if ($staticIP) { "Static IP configured" } else { "A static IP is required for a Domain Controller" }
    }

    # Check 3: DNS configured
    $dnsConfigured = $false
    try {
        $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.ServerAddresses.Count -gt 0 }
        if ($null -ne $dnsServers -and @($dnsServers).Count -gt 0) {
            $dnsConfigured = $true
        }
    }
    catch {
        # Ignore
    }
    $checks += @{
        Name   = "DNS Configuration"
        Passed = $dnsConfigured
        Detail = if ($dnsConfigured) { "DNS servers configured" } else { "DNS must be configured" }
    }

    # Check 4: Not already a DC. Use tri-state — a silent CIM probe failure used to leave
    # $isNotDC = $true (the default), so a degraded WMI repository would report "Server is
    # not a Domain Controller" and the user would proceed to Install-ADDSForest on a box
    # that may already be a DC. Now: only assert Pass when both probes returned non-null.
    $isNotDC = $false
    $dcCheckDetail = "Could not verify DC state (WMI probe failed)"
    try {
        $osInfo = Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 8 -ErrorAction Stop
        $compSys = Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec 8 -ErrorAction Stop
        if ($null -ne $osInfo -and $null -ne $compSys) {
            if ($osInfo.ProductType -eq 2 -or $compSys.DomainRole -ge 4) {
                $isNotDC = $false
                $dcCheckDetail = "Server is already a Domain Controller"
            } else {
                $isNotDC = $true
                $dcCheckDetail = "Server is not a Domain Controller"
            }
        }
    }
    catch {
        $dcCheckDetail = "Could not verify DC state: $($_.Exception.Message)"
    }
    $checks += @{
        Name   = "Not Already a DC"
        Passed = $isNotDC
        Detail = $dcCheckDetail
    }

    $allPassed = @($checks | Where-Object { -not $_.Passed }).Count -eq 0

    return @{
        Passed = $allPassed
        Checks = $checks
    }
}

# Function to display prerequisite check results
function Show-ADDSPrerequisiteResults {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Results
    )

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  PREREQUISITE CHECK RESULTS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    foreach ($check in $Results.Checks) {
        $status = if ($check.Passed) { "[PASS]" } else { "[FAIL]" }
        $statusColor = if ($check.Passed) { "Success" } else { "Error" }
        $line = "  $status  $($check.Name): $($check.Detail)"
        if ($line.Length -gt 69) { $line = $line.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($line.PadRight(72))│" -color $statusColor
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($Results.Passed) {
        Write-OutputColor "  All prerequisites passed." -color "Success"
    }
    else {
        Write-OutputColor "  Some prerequisites are not met. Review before proceeding." -color "Warning"
    }
}

# Function to install AD DS role if not present
function Install-ADDSRoleIfNeeded {
    if (Test-ADDSInstalled) {
        Write-OutputColor "  AD DS role is already installed." -color "Success"
        return $true
    }

    Write-OutputColor "  AD DS role is not installed." -color "Warning"
    if (-not (Confirm-UserAction -Message "Install AD-Domain-Services role now?")) {
        Write-OutputColor "  AD DS role installation cancelled." -color "Info"
        return $false
    }

    $installResult = Install-WindowsFeatureWithTimeout -FeatureName "AD-Domain-Services" -DisplayName "AD Domain Services" -IncludeManagementTools
    if ($installResult.Success) {
        Add-SessionChange -Category "AD DS" -Description "Installed AD-Domain-Services role"
        Clear-MenuCache
        return $true
    }
    else {
        return $false
    }
}

# Function to validate domain name format
function Test-ValidDomainName {
    param (
        [Parameter(Mandatory=$true)]
        [string]$DomainName
    )

    # Must contain at least one dot and valid DNS characters
    if ($DomainName -notmatch '\.') { return $false }
    if ($DomainName -notmatch '^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)+$') { return $false }
    return $true
}

# Function to extract NetBIOS name from FQDN
function Get-NetBIOSNameFromFQDN {
    param (
        [Parameter(Mandatory=$true)]
        [string]$DomainName
    )

    $parts = $DomainName.Split(".")
    return $parts[0].ToUpper()
}

# Function to show functional level selection menu
function Select-FunctionalLevel {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT FUNCTIONAL LEVEL".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem -Text "[1]  Win2012R2    (Server 2012 R2)"
    Write-MenuItem -Text "[2]  WinThreshold (Server 2016) - Default"
    Write-MenuItem -Text "[3]  Win2019      (Server 2019)"
    Write-MenuItem -Text "[4]  Win2022      (Server 2022)"
    Write-MenuItem -Text "[5]  Win2025      (Server 2025)"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $levelChoice = Read-Host "  Select (default: 2)"
    $navResult = Test-NavigationCommand -UserInput $levelChoice
    if ($navResult.ShouldReturn) { return $null }

    switch ($levelChoice) {
        "1" { return @{ Value = "Win2012R2";    Display = "Win2012R2 (Server 2012 R2)" } }
        "3" { return @{ Value = "Win2019";      Display = "Win2019 (Server 2019)" } }
        "4" { return @{ Value = "Win2022";      Display = "Win2022 (Server 2022)" } }
        "5" { return @{ Value = "Win2025";      Display = "Win2025 (Server 2025)" } }
        default { return @{ Value = "WinThreshold"; Display = "WinThreshold (Server 2016)" } }
    }
}

# Function to prompt and confirm DSRM password
function Read-DSRMPassword {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enter Directory Services Restore Mode (DSRM) password:" -color "Info"
    $dsrmPassword = Read-Host "  DSRM Password" -AsSecureString

    Write-OutputColor "  Confirm DSRM password:" -color "Info"
    $dsrmConfirm = Read-Host "  Confirm Password" -AsSecureString

    # Compare and complexity-check the password. DSRM is the most-privileged AD secret —
    # we keep the plaintext on the managed heap as briefly as possible (it still touches
    # PowerShell's heap because string ops, but we null the reference and run a forced
    # collection before returning so it's not hanging around at function exit).
    # Length-only validation in the prior implementation let "Password1" through; Install-ADDSForest
    # would then reject it ~10 minutes into the role install after the DC pre-flight had passed.
    # Now apply a 3-of-4 complexity check up front (mirrors local password complexity policy).
    $bstr1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($dsrmPassword)
    $bstr2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($dsrmConfirm)
    try {
        $plain1 = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr1)
        $plain2 = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr2)

        if ($plain1 -ne $plain2) {
            Write-OutputColor "  Passwords do not match." -color "Error"
            return $null
        }

        if ($plain1.Length -lt 14) {
            Write-OutputColor "  DSRM password must be at least 14 characters." -color "Error"
            return $null
        }

        $classes = 0
        if ($plain1 -cmatch '[a-z]') { $classes++ }
        if ($plain1 -cmatch '[A-Z]') { $classes++ }
        if ($plain1 -match '\d')      { $classes++ }
        if ($plain1 -match '[^a-zA-Z0-9]') { $classes++ }
        if ($classes -lt 3) {
            Write-OutputColor "  DSRM password must contain at least 3 of: lowercase, uppercase, digit, symbol." -color "Error"
            Write-OutputColor "  Install-ADDSForest would reject this password ~10 minutes into the role install." -color "Info"
            return $null
        }
    }
    finally {
        $plain1 = $null
        $plain2 = $null
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr1)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2)
        [GC]::Collect()
    }

    return $dsrmPassword
}

# Pre-promotion validation checks (NTP, DNS self-resolution, network connectivity)
function Test-PrePromotionReadiness {
    param (
        [string]$DomainName,
        [switch]$IsNewForest
    )

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  PRE-PROMOTION VALIDATION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $warningCount = 0

    # Check 1: NTP Sync — verify time service is running. The previous English-substring
    # match against `error|not found|stopped` would silently pass on non-EN MUI (those words
    # are localized in the w32tm output). Use the service state directly + w32tm exit code
    # as the locale-neutral signal. AD time drift is a critical replication blocker; missing
    # this check on non-EN Windows is a real bug.
    $w32timeSvc = Get-Service -Name W32Time -ErrorAction SilentlyContinue
    $w32timeRunning = ($null -ne $w32timeSvc -and $w32timeSvc.Status -eq 'Running')
    $w32tmExit = 1
    try {
        $null = w32tm /query /status 2>&1
        $w32tmExit = $LASTEXITCODE
    } catch { }
    if (-not $w32timeRunning -or $w32tmExit -ne 0) {
        Write-OutputColor "  │$("  [WARN] Windows Time Service may not be synchronized".PadRight(72))│" -color "Warning"
        Write-OutputColor "  │$("         Time drift can cause AD replication failures".PadRight(72))│" -color "Warning"
        $warningCount++
    }
    else {
        Write-OutputColor "  │$("  [OK]   Windows Time Service is running".PadRight(72))│" -color "Success"
    }

    # Check 2: DNS self-resolution — verify this server can resolve its own hostname
    $selfResolve = try { [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME) } catch { $null }
    if ($null -eq $selfResolve) {
        Write-OutputColor "  │$("  [WARN] Cannot resolve own hostname via DNS".PadRight(72))│" -color "Warning"
        Write-OutputColor "  │$("         DNS resolution issues may impact AD functionality".PadRight(72))│" -color "Warning"
        $warningCount++
    }
    else {
        $resolvedIP = @($selfResolve.AddressList | Where-Object { $_.AddressFamily -eq 'InterNetwork' })[0]
        $lineStr = "  [OK]   Hostname resolves to $resolvedIP"
        if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Success"
    }

    # Check 3: Network connectivity to existing DC (only for additional DC / RODC)
    if (-not $IsNewForest -and -not [string]::IsNullOrWhiteSpace($DomainName)) {
        # Verify the AD-specific SRV record, not just the A record. A misconfigured DNS that
        # points the domain name at a public IP will resolve via GetHostEntry but the box has
        # no AD on the other end — Install-ADDSDomainController then fails mysteriously.
        $srvFound = $false
        try {
            $srv = Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$DomainName" -Type SRV -ErrorAction Stop
            if ($srv -and @($srv | Where-Object { $_.Type -eq 'SRV' }).Count -gt 0) { $srvFound = $true }
        } catch { }
        if (-not $srvFound) {
            Write-OutputColor "  │$("  [WARN] No SRV record for _ldap._tcp.dc._msdcs.$DomainName".PadRight(72))│" -color "Warning"
            Write-OutputColor "  │$("         DNS may be pointing at a non-AD resolver.".PadRight(72))│" -color "Warning"
            $warningCount++
        }
        # Try to resolve the domain name (legacy A-record probe — kept as a secondary check)
        $domainResolve = try { [System.Net.Dns]::GetHostEntry($DomainName) } catch { $null }
        if ($null -eq $domainResolve) {
            Write-OutputColor "  │$("  [WARN] Cannot resolve domain: $DomainName".PadRight(72))│" -color "Warning"
            Write-OutputColor "  │$("         Verify DNS is configured to reach the domain".PadRight(72))│" -color "Warning"
            $warningCount++
        }
        else {
            $dcIP = @($domainResolve.AddressList | Where-Object { $_.AddressFamily -eq 'InterNetwork' })[0]
            $lineStr = "  [OK]   Domain '$DomainName' resolves to $dcIP"
            if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Success"

            # Test LDAP (port 389). WaitOne returning $true only means the wait completed —
            # for a refused connection (RST), WaitOne returns true and we'd report "reachable"
            # incorrectly. EndConnect distinguishes accept from reject.
            $ldapOk = $false
            $tcp = $null
            try {
                $tcp = New-Object System.Net.Sockets.TcpClient
                $connectResult = $tcp.BeginConnect("$dcIP", 389, $null, $null)
                if ($connectResult.AsyncWaitHandle.WaitOne(3000, $false)) {
                    try { $tcp.EndConnect($connectResult); $ldapOk = $true } catch { $ldapOk = $false }
                }
            }
            catch {
                $ldapOk = $false
            }
            finally {
                if ($null -ne $tcp) { $tcp.Close() }
            }
            if ($ldapOk) {
                Write-OutputColor "  │$("  [OK]   LDAP (port 389) reachable on $dcIP".PadRight(72))│" -color "Success"
            }
            else {
                Write-OutputColor "  │$("  [WARN] LDAP (port 389) not reachable on $dcIP".PadRight(72))│" -color "Warning"
                $warningCount++
            }

            # Test Kerberos (port 88) — same EndConnect fix as the LDAP probe above.
            $kerberosOk = $false
            $tcp = $null
            try {
                $tcp = New-Object System.Net.Sockets.TcpClient
                $connectResult = $tcp.BeginConnect("$dcIP", 88, $null, $null)
                if ($connectResult.AsyncWaitHandle.WaitOne(3000, $false)) {
                    try { $tcp.EndConnect($connectResult); $kerberosOk = $true } catch { $kerberosOk = $false }
                }
            }
            catch {
                $kerberosOk = $false
            }
            finally {
                if ($null -ne $tcp) { $tcp.Close() }
            }
            if ($kerberosOk) {
                Write-OutputColor "  │$("  [OK]   Kerberos (port 88) reachable on $dcIP".PadRight(72))│" -color "Success"
            }
            else {
                Write-OutputColor "  │$("  [WARN] Kerberos (port 88) not reachable on $dcIP".PadRight(72))│" -color "Warning"
                $warningCount++
            }
        }
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($warningCount -gt 0) {
        Write-OutputColor "  $warningCount warning(s) detected. Review before proceeding." -color "Warning"
    }
    else {
        Write-OutputColor "  All pre-promotion checks passed." -color "Success"
    }

    return $warningCount
}

# Post-promotion validation (DNS, NTDS service, SYSVOL share)
function Test-PostPromotionStatus {
    param ([string]$DomainName)

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  POST-PROMOTION VALIDATION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    # Check 1: DNS points to self (127.0.0.1 or own IP should be primary DNS)
    $dnsSelf = $false
    try {
        $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.ServerAddresses.Count -gt 0 }
        $ownIPs = @([System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).AddressList |
            Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
            ForEach-Object { $_.IPAddressToString })
        $ownIPs += "127.0.0.1"

        foreach ($dns in $dnsServers) {
            $primaryDNS = $dns.ServerAddresses[0]
            if ($primaryDNS -in $ownIPs) {
                $dnsSelf = $true
                break
            }
        }
    }
    catch {
        # Ignore
    }
    if ($dnsSelf) {
        Write-OutputColor "  │$("  [OK]   Primary DNS points to this server".PadRight(72))│" -color "Success"
    }
    else {
        Write-OutputColor "  │$("  [WARN] Primary DNS does not point to this server".PadRight(72))│" -color "Warning"
        Write-OutputColor "  │$("         Set DNS to 127.0.0.1 or this server's IP".PadRight(72))│" -color "Warning"
    }

    # Check 2: AD DS (NTDS) service is running
    $ntdsService = Get-Service NTDS -ErrorAction SilentlyContinue
    if ($null -ne $ntdsService -and $ntdsService.Status -eq "Running") {
        Write-OutputColor "  │$("  [OK]   AD DS service (NTDS) is running".PadRight(72))│" -color "Success"
    }
    else {
        $ntdsStatus = if ($null -ne $ntdsService) { "$($ntdsService.Status)" } else { "Not found" }
        Write-OutputColor "  │$("  [WARN] AD DS service (NTDS): $ntdsStatus".PadRight(72))│" -color "Warning"
        Write-OutputColor "  │$("         Service should be running after reboot".PadRight(72))│" -color "Warning"
    }

    # Check 3: SYSVOL share exists
    $sysvolShare = Get-SmbShare -Name SYSVOL -ErrorAction SilentlyContinue
    if ($null -ne $sysvolShare) {
        Write-OutputColor "  │$("  [OK]   SYSVOL share exists".PadRight(72))│" -color "Success"
    }
    else {
        Write-OutputColor "  │$("  [WARN] SYSVOL share not found (may need reboot)".PadRight(72))│" -color "Warning"
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    # Summary
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  POST-PROMOTION SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    $lineStr = "  Domain: $DomainName"
    if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
    Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Server: $env:COMPUTERNAME".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  A reboot is required to finalize promotion.".PadRight(72))│" -color "Warning"
    Write-OutputColor "  │$("  Run 'Check AD DS Status' after reboot to verify.".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

# Post-promotion replication health check
function Test-ADDSReplicationHealth {
    param([string]$DomainName)

    Write-OutputColor "" -color "Info"
    if (-not (Confirm-UserAction -Message "Run post-promotion replication health check? (requires reboot first for additional/RODC DCs)" -DefaultYes)) {
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Checking replication health..." -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        Import-Module ActiveDirectory -ErrorAction Stop

        $replPartners = @(Get-ADReplicationPartnerMetadata -Target $env:COMPUTERNAME -ErrorAction Stop)

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  POST-PROMOTION REPLICATION STATUS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        if ($replPartners.Count -eq 0) {
            Write-OutputColor "  │$("  No replication partners found (expected for first DC in forest)".PadRight(72))│" -color "Info"
        } else {
            foreach ($partner in $replPartners) {
                $partnerName = $partner.Partner -replace '^CN=NTDS Settings,CN=', '' -replace ',.*$', ''
                $lastRepl = if ($null -ne $partner.LastReplicationSuccess) {
                    $partner.LastReplicationSuccess.ToString("yyyy-MM-dd HH:mm:ss")
                } else { "Pending" }
                $lastResult = if ($partner.LastReplicationResult -eq 0) { "Success" } else { "Error ($($partner.LastReplicationResult))" }
                $resultColor = if ($partner.LastReplicationResult -eq 0) { "Success" } else { "Error" }

                $lineStr = "  Partner: $partnerName"
                if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
                Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
                Write-OutputColor "  │$("    Last: $lastRepl  Status: $lastResult".PadRight(72))│" -color $resultColor
            }
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

        # Check SYSVOL share
        Write-OutputColor "" -color "Info"
        $sysvolPath = "\\$env:COMPUTERNAME\SYSVOL"
        $sysvolOk = Test-Path $sysvolPath -ErrorAction SilentlyContinue
        if ($sysvolOk) {
            Write-OutputColor "  SYSVOL share: Available ($sysvolPath)" -color "Success"
        } else {
            Write-OutputColor "  SYSVOL share: Not yet available (may need reboot)" -color "Warning"
        }

        # Check DNS
        try {
            $dnsZone = Get-DnsServerZone -Name $DomainName -ErrorAction SilentlyContinue
            if ($null -ne $dnsZone) {
                Write-OutputColor "  DNS zone: $DomainName (Active)" -color "Success"
            } else {
                Write-OutputColor "  DNS zone: $DomainName not found (may need reboot)" -color "Warning"
            }
        }
        catch {
            Write-OutputColor "  DNS zone check: DNS Server module not available" -color "Warning"
        }
    }
    catch [Microsoft.ActiveDirectory.Management.ADException] {
        Write-OutputColor "  Replication check unavailable — reboot required to complete promotion." -color "Warning"
        Write-OutputColor "  Run 'Check AD DS Status' from the menu after reboot to verify." -color "Info"
    }
    catch {
        Write-OutputColor "  Replication check unavailable: $($_.Exception.Message)" -color "Warning"
        Write-OutputColor "  This is normal before the first reboot. Check status after reboot." -color "Info"
    }
}

# Standalone replication health monitor (accessible from menu)
function Show-ReplicationMonitor {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    AD DS REPLICATION MONITOR").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    }
    catch {
        Write-RackStackError -Code "RS-7007" -Detail "$_"
        Write-OutputColor "  Active Directory module not available." -color "Error"
        Write-OutputColor "  This server may not be a Domain Controller." -color "Warning"
        Write-PressEnter
        return
    }

    Write-OutputColor "  Querying replication partners..." -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $replPartners = @(Get-ADReplicationPartnerMetadata -Target $env:COMPUTERNAME -ErrorAction Stop)

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  REPLICATION PARTNERS ($($replPartners.Count) found)".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        if ($replPartners.Count -eq 0) {
            Write-OutputColor "  │$("  No replication partners (first/only DC in forest)".PadRight(72))│" -color "Info"
        } else {
            $maxDelta = [TimeSpan]::Zero
            $failCount = 0

            foreach ($partner in $replPartners) {
                $partnerName = $partner.Partner -replace '^CN=NTDS Settings,CN=', '' -replace ',.*$', ''
                $lastRepl = if ($null -ne $partner.LastReplicationSuccess) {
                    $partner.LastReplicationSuccess.ToString("yyyy-MM-dd HH:mm:ss")
                } else { "Never" }

                $delta = if ($null -ne $partner.LastReplicationSuccess) {
                    (Get-Date) - $partner.LastReplicationSuccess
                } else { [TimeSpan]::MaxValue }

                if ($delta -gt $maxDelta -and $delta -ne [TimeSpan]::MaxValue) { $maxDelta = $delta }

                $deltaStr = if ($delta -eq [TimeSpan]::MaxValue) { "Never" }
                    elseif ($delta.TotalMinutes -lt 1) { "$([math]::Round($delta.TotalSeconds))s ago" }
                    elseif ($delta.TotalHours -lt 1) { "$([math]::Round($delta.TotalMinutes))m ago" }
                    elseif ($delta.TotalDays -lt 1) { "$([math]::Round($delta.TotalHours, 1))h ago" }
                    else { "$([math]::Round($delta.TotalDays, 1))d ago" }

                $lastResult = if ($partner.LastReplicationResult -eq 0) { "OK" } else { "ERROR ($($partner.LastReplicationResult))" }
                if ($partner.LastReplicationResult -ne 0) { $failCount++ }

                $resultColor = if ($partner.LastReplicationResult -ne 0) { "Error" }
                    elseif ($delta.TotalMinutes -gt 30) { "Warning" }
                    else { "Success" }

                $lineStr = "  $partnerName"
                if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
                Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
                Write-OutputColor "  │$("    Last: $lastRepl ($deltaStr)  Status: $lastResult".PadRight(72))│" -color $resultColor
            }

            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $overallColor = if ($failCount -gt 0) { "Error" } elseif ($maxDelta.TotalMinutes -gt 30) { "Warning" } else { "Success" }
            $overallStatus = if ($failCount -gt 0) { "ERRORS DETECTED ($failCount partner(s) failing)" }
                elseif ($maxDelta.TotalMinutes -gt 30) { "STALE (replication >30 min old)" }
                else { "HEALTHY" }
            Write-OutputColor "  │$("  Overall: $overallStatus".PadRight(72))│" -color $overallColor
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

        # SYSVOL check
        Write-OutputColor "" -color "Info"
        $sysvolPath = "\\$env:COMPUTERNAME\SYSVOL"
        $sysvolOk = Test-Path $sysvolPath -ErrorAction SilentlyContinue
        if ($sysvolOk) {
            Write-OutputColor "  SYSVOL share: Available" -color "Success"
        } else {
            Write-OutputColor "  SYSVOL share: NOT AVAILABLE" -color "Error"
        }

        # NETLOGON check
        $netlogonPath = "\\$env:COMPUTERNAME\NETLOGON"
        $netlogonOk = Test-Path $netlogonPath -ErrorAction SilentlyContinue
        if ($netlogonOk) {
            Write-OutputColor "  NETLOGON share: Available" -color "Success"
        } else {
            Write-OutputColor "  NETLOGON share: NOT AVAILABLE" -color "Error"
        }

        # DNS zone check
        try {
            $domain = (Get-ADDomain -ErrorAction SilentlyContinue).DNSRoot
            if ($domain) {
                $dnsZone = Get-DnsServerZone -Name $domain -ErrorAction SilentlyContinue
                if ($null -ne $dnsZone) {
                    Write-OutputColor "  DNS zone ($domain): Active" -color "Success"
                } else {
                    Write-OutputColor "  DNS zone ($domain): NOT FOUND" -color "Error"
                }
            }
        }
        catch {
            Write-OutputColor "  DNS zone check: unavailable" -color "Warning"
        }

        # Offer force replication
        if ($replPartners.Count -gt 0) {
            Write-OutputColor "" -color "Info"
            if (Confirm-UserAction -Message "Force replication sync with all partners?") {
                Write-OutputColor "  Forcing replication..." -color "Info"
                try {
                    # Capture both output and exit code. repadmin returns 0 on success and emits to
                    # stdout; piping into $null hid replication failures (e.g. 8453 access-denied,
                    # 8606 insufficient-attributes) behind a green "initiated" message.
                    $global:LASTEXITCODE = 0
                    $repadminOut = repadmin /syncall /AdeP 2>&1
                    $repExit = $LASTEXITCODE
                    if ($repExit -eq 0) {
                        Write-OutputColor "  Replication sync initiated." -color "Success"
                        Add-SessionChange -Category "AD DS" -Description "Forced AD replication sync"
                        Clear-MenuCache
                    } else {
                        Write-OutputColor "  repadmin returned exit code ${repExit}:" -color "Error"
                        ($repadminOut | Select-Object -Last 5) | ForEach-Object { Write-OutputColor "    $_" -color "Warning" }
                    }
                }
                catch {
                    Write-OutputColor "  Replication sync failed: $_" -color "Error"
                }
            }
        }
    }
    catch {
        Write-OutputColor "  Replication data unavailable: $($_.Exception.Message)" -color "Error"
        Write-OutputColor "  Ensure this server is a promoted Domain Controller." -color "Warning"
    }

    Write-PressEnter
}

# Main AD DS Promotion menu
function Show-ADDSPromotionMenu {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("               AD DS DOMAIN CONTROLLER PROMOTION").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  PROMOTION OPTIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem -Text "[1]  New Forest (First DC in new domain)"
        Write-MenuItem -Text "[2]  Additional Domain Controller (Join existing domain)"
        Write-MenuItem -Text "[3]  Read-Only Domain Controller (RODC)"
        Write-MenuItem -Text "[4]  Check AD DS Status"
        Write-MenuItem -Text "[5]  Replication Health Monitor"
        Write-MenuItem -Text "[6]  Enable AD Recycle Bin"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" { Install-NewForest }
            "2" { Install-AdditionalDC }
            "3" { Install-ReadOnlyDC }
            "4" { Show-ADDSStatus }
            "5" { Show-ReplicationMonitor }
            "6" { Enable-ADRecycleBinFeature }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-6 or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Wizard to promote server as first DC in a new forest
function Install-NewForest {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    NEW FOREST — FIRST DOMAIN CONTROLLER").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Step 1: Prerequisites
    $prereqs = Test-ADDSPrerequisites
    Show-ADDSPrerequisiteResults -Results $prereqs

    if (-not $prereqs.Passed) {
        if (-not (Confirm-UserAction -Message "Continue despite prerequisite failures?")) {
            Write-OutputColor "  Promotion cancelled." -color "Info"
            Write-PressEnter
            return
        }
    }

    # Step 2: Install AD DS role if needed
    if (-not (Install-ADDSRoleIfNeeded)) {
        Write-PressEnter
        return
    }

    # Step 3: Domain name
    Write-OutputColor "" -color "Info"
    $domainName = Read-Host "  Enter domain name (e.g., corp.contoso.com)"
    $navResult = Test-NavigationCommand -UserInput $domainName
    if ($navResult.ShouldReturn) { return }

    if ([string]::IsNullOrWhiteSpace($domainName)) {
        Write-OutputColor "  Domain name is required." -color "Error"
        Write-PressEnter
        return
    }

    if (-not (Test-ValidDomainName -DomainName $domainName)) {
        Write-OutputColor "  Invalid domain name format. Must contain at least one dot and valid DNS characters." -color "Error"
        Write-PressEnter
        return
    }

    $netbiosName = Get-NetBIOSNameFromFQDN -DomainName $domainName

    # Step 4: Functional level
    $level = Select-FunctionalLevel
    if ($null -eq $level) { return }
    $forestMode = $level.Value
    $domainMode = $level.Value
    $levelDisplay = $level.Display

    # Step 5: DSRM password
    $dsrmPassword = Read-DSRMPassword
    if ($null -eq $dsrmPassword) {
        Write-PressEnter
        return
    }

    # Step 6: Summary
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  NEW FOREST CONFIGURATION SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    $lineStr = "  Domain Name:      $domainName"
    if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
    Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  NetBIOS Name:     $netbiosName".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Forest Mode:      $levelDisplay".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Domain Mode:      $levelDisplay".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Install DNS:      Yes".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Database Path:    $env:SystemRoot\NTDS".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Log Path:         $env:SystemRoot\NTDS".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  SYSVOL Path:      $env:SystemRoot\SYSVOL".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Step 7: Pre-promotion validation
    $preWarnings = Test-PrePromotionReadiness -DomainName $domainName -IsNewForest
    if ($preWarnings -gt 0) {
        if (-not (Confirm-UserAction -Message "Continue despite $preWarnings warning(s)?")) {
            Write-OutputColor "  Promotion cancelled." -color "Info"
            Write-PressEnter
            return
        }
    }

    # Step 8: Confirm
    if (-not (Confirm-UserAction -Message "Promote this server to Domain Controller?")) {
        Write-OutputColor "  Promotion cancelled." -color "Info"
        Write-PressEnter
        return
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        # New-forest promotion is ONE-WAY: demoting destroys the forest's
        # AD database on this box. Any Group Policy objects, OUs, users,
        # computer accounts, and trusts that get created downstream of
        # this promotion become orphaned on demotion.
        $capDomain  = $domainName
        $capNetBIOS = $netbiosName
        $capForest  = $forestMode
        $capDomMode = $domainMode
        $capDSRM    = $dsrmPassword
        Push-DryRunStep -Label "Promote to first DC of new forest '$capDomain'" -Category "Roles" -OneWay $true `
            -Params @{ DomainName = $capDomain; NetBIOSName = $capNetBIOS; ForestMode = $capForest; DomainMode = $capDomMode } `
            -Preflight {
                if (Test-ADDSInstalled) { "AD DS is already installed on this server" }
                else { $true }
            }.GetNewClosure() `
            -Apply {
                Import-Module ADDSDeployment -ErrorAction Stop
                Install-ADDSForest `
                    -DomainName $capDomain `
                    -ForestMode $capForest `
                    -DomainMode $capDomMode `
                    -DomainNetbiosName $capNetBIOS `
                    -SafeModeAdministratorPassword $capDSRM `
                    -InstallDns:$true `
                    -CreateDnsDelegation:$false `
                    -NoRebootOnCompletion:$true `
                    -Force:$true `
                    -ErrorAction Stop
                $script:RebootNeeded = $true
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): promote to first DC of new forest '$capDomain' (ONE-WAY)." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued DC promotion (new forest '$capDomain')"
        Write-PressEnter
        return
    }

    # Step 9: Execute
    try {
        Write-OutputColor "`n  Promoting server to Domain Controller... This will take several minutes." -color "Info"
        Write-OutputColor "  Do NOT close this window." -color "Warning"

        Import-Module ADDSDeployment -ErrorAction Stop

        Install-ADDSForest `
            -DomainName $domainName `
            -ForestMode $forestMode `
            -DomainMode $domainMode `
            -DomainNetbiosName $netbiosName `
            -SafeModeAdministratorPassword $dsrmPassword `
            -InstallDns:$true `
            -CreateDnsDelegation:$false `
            -NoRebootOnCompletion:$true `
            -Force:$true `
            -ErrorAction Stop

        Write-OutputColor "`n  Domain Controller promotion completed successfully!" -color "Success"
        $script:RebootNeeded = $true
        Add-SessionChange -Category "AD DS" -Description "Promoted to DC: New forest $domainName"
        Clear-MenuCache
        Write-OutputColor "  A reboot is required to complete the promotion." -color "Warning"

        Test-PostPromotionStatus -DomainName $domainName
        Test-ADDSReplicationHealth -DomainName $domainName
    }
    catch {
        Write-RackStackError -Code "RS-7002" -Detail "$_"
        Write-OutputColor "  Failed to promote Domain Controller: $_" -color "Error"
        Add-SessionChange -Category "AD DS" -Description "DC promotion failed: New forest $domainName - $_"
        Clear-MenuCache
    }

    Write-PressEnter
}

# Wizard to add an additional Domain Controller to an existing domain
function Install-AdditionalDC {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("              ADDITIONAL DOMAIN CONTROLLER").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Step 1: Prerequisites
    $prereqs = Test-ADDSPrerequisites
    Show-ADDSPrerequisiteResults -Results $prereqs

    if (-not $prereqs.Passed) {
        if (-not (Confirm-UserAction -Message "Continue despite prerequisite failures?")) {
            Write-OutputColor "  Promotion cancelled." -color "Info"
            Write-PressEnter
            return
        }
    }

    # Step 2: Install AD DS role if needed
    if (-not (Install-ADDSRoleIfNeeded)) {
        Write-PressEnter
        return
    }

    # Step 3: Domain to join
    Write-OutputColor "" -color "Info"
    $domainName = Read-Host "  Enter domain to join (e.g., corp.contoso.com)"
    $navResult = Test-NavigationCommand -UserInput $domainName
    if ($navResult.ShouldReturn) { return }

    if ([string]::IsNullOrWhiteSpace($domainName)) {
        Write-OutputColor "  Domain name is required." -color "Error"
        Write-PressEnter
        return
    }

    if (-not (Test-ValidDomainName -DomainName $domainName)) {
        Write-OutputColor "  Invalid domain name format." -color "Error"
        Write-PressEnter
        return
    }

    # Step 4: Domain admin credentials. In console mode (ps2exe-built RackStack) Get-Credential
    # may return a PSCredential with empty user/password instead of $null on cancel — explicitly
    # check both halves. A blank password used to make it through to Install-ADDSDomainController
    # which then blocked for many seconds before Kerberos rejected the empty secret.
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  You will need domain admin credentials." -color "Info"
    $credential = Get-Credential -Message "Enter domain admin credentials for $domainName"
    if ($null -eq $credential -or [string]::IsNullOrWhiteSpace($credential.UserName) -or $credential.Password.Length -eq 0) {
        Write-OutputColor "  Credential entry cancelled or incomplete." -color "Warning"
        Write-PressEnter
        return
    }

    # Step 5: Site name
    Write-OutputColor "" -color "Info"
    $siteName = Read-Host "  Enter AD site name (default: Default-First-Site-Name)"
    $navResult = Test-NavigationCommand -UserInput $siteName
    if ($navResult.ShouldReturn) { return }

    if ([string]::IsNullOrWhiteSpace($siteName)) {
        $siteName = "Default-First-Site-Name"
    }

    # Step 6: DSRM password
    $dsrmPassword = Read-DSRMPassword
    if ($null -eq $dsrmPassword) {
        Write-PressEnter
        return
    }

    # Step 7: Summary
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  ADDITIONAL DC CONFIGURATION SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Domain:           $domainName".PadRight(72))│" -color "Info"
    $lineStr = "  Credentials:      $($credential.UserName)"
    if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
    Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Site:             $siteName".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Install DNS:      Yes".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Database Path:    $env:SystemRoot\NTDS".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Log Path:         $env:SystemRoot\NTDS".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  SYSVOL Path:      $env:SystemRoot\SYSVOL".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Step 8: Pre-promotion validation
    $preWarnings = Test-PrePromotionReadiness -DomainName $domainName
    if ($preWarnings -gt 0) {
        if (-not (Confirm-UserAction -Message "Continue despite $preWarnings warning(s)?")) {
            Write-OutputColor "  Promotion cancelled." -color "Info"
            Write-PressEnter
            return
        }
    }

    # Step 9: Confirm
    if (-not (Confirm-UserAction -Message "Promote this server as an additional Domain Controller?")) {
        Write-OutputColor "  Promotion cancelled." -color "Info"
        Write-PressEnter
        return
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        # Additional-DC promotion is ONE-WAY in the same sense as new-forest:
        # demotion is technically possible but the replicated state (any AD
        # objects this DC originated, FRS/DFSR membership) doesn't cleanly
        # unwind.
        $capDomain = $domainName
        $capCred   = $credential
        $capSite   = $siteName
        $capDSRM   = $dsrmPassword
        Push-DryRunStep -Label "Promote to additional DC in '$capDomain' (site: $capSite)" -Category "Roles" -OneWay $true `
            -Params @{ DomainName = $capDomain; Site = $capSite } `
            -Preflight {
                if (Test-ADDSInstalled) { "AD DS is already installed on this server" }
                else { $true }
            }.GetNewClosure() `
            -Apply {
                Import-Module ADDSDeployment -ErrorAction Stop
                Install-ADDSDomainController `
                    -DomainName $capDomain `
                    -Credential $capCred `
                    -SiteName $capSite `
                    -SafeModeAdministratorPassword $capDSRM `
                    -InstallDns:$true `
                    -NoRebootOnCompletion:$true `
                    -Force:$true `
                    -ErrorAction Stop
                $script:RebootNeeded = $true
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): promote to additional DC in '$capDomain' (ONE-WAY)." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued additional DC promotion in '$capDomain'"
        Write-PressEnter
        return
    }

    # Step 10: Execute
    try {
        Write-OutputColor "`n  Promoting server as additional DC... This will take several minutes." -color "Info"
        Write-OutputColor "  Do NOT close this window." -color "Warning"

        Import-Module ADDSDeployment -ErrorAction Stop

        Install-ADDSDomainController `
            -DomainName $domainName `
            -Credential $credential `
            -SiteName $siteName `
            -SafeModeAdministratorPassword $dsrmPassword `
            -InstallDns:$true `
            -NoRebootOnCompletion:$true `
            -Force:$true `
            -ErrorAction Stop

        Write-OutputColor "`n  Additional Domain Controller promotion completed successfully!" -color "Success"
        $script:RebootNeeded = $true
        Add-SessionChange -Category "AD DS" -Description "Promoted to additional DC in domain $domainName"
        Clear-MenuCache
        Write-OutputColor "  A reboot is required to complete the promotion." -color "Warning"

        Test-PostPromotionStatus -DomainName $domainName
        Test-ADDSReplicationHealth -DomainName $domainName
    }
    catch {
        Write-OutputColor "  Failed to promote additional DC: $_" -color "Error"
        Add-SessionChange -Category "AD DS" -Description "Additional DC promotion failed: $domainName - $_"
        Clear-MenuCache
    }

    Write-PressEnter
}

# Wizard to install a Read-Only Domain Controller
function Install-ReadOnlyDC {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("              READ-ONLY DOMAIN CONTROLLER (RODC)").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Step 1: Prerequisites
    $prereqs = Test-ADDSPrerequisites
    Show-ADDSPrerequisiteResults -Results $prereqs

    if (-not $prereqs.Passed) {
        if (-not (Confirm-UserAction -Message "Continue despite prerequisite failures?")) {
            Write-OutputColor "  Promotion cancelled." -color "Info"
            Write-PressEnter
            return
        }
    }

    # Step 2: Install AD DS role if needed
    if (-not (Install-ADDSRoleIfNeeded)) {
        Write-PressEnter
        return
    }

    # Step 3: Domain to join
    Write-OutputColor "" -color "Info"
    $domainName = Read-Host "  Enter domain to join (e.g., corp.contoso.com)"
    $navResult = Test-NavigationCommand -UserInput $domainName
    if ($navResult.ShouldReturn) { return }

    if ([string]::IsNullOrWhiteSpace($domainName)) {
        Write-OutputColor "  Domain name is required." -color "Error"
        Write-PressEnter
        return
    }

    if (-not (Test-ValidDomainName -DomainName $domainName)) {
        Write-OutputColor "  Invalid domain name format." -color "Error"
        Write-PressEnter
        return
    }

    # Step 4: Domain admin credentials. In console mode (ps2exe-built RackStack) Get-Credential
    # may return a PSCredential with empty user/password instead of $null on cancel — explicitly
    # check both halves. A blank password used to make it through to Install-ADDSDomainController
    # which then blocked for many seconds before Kerberos rejected the empty secret.
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  You will need domain admin credentials." -color "Info"
    $credential = Get-Credential -Message "Enter domain admin credentials for $domainName"
    if ($null -eq $credential -or [string]::IsNullOrWhiteSpace($credential.UserName) -or $credential.Password.Length -eq 0) {
        Write-OutputColor "  Credential entry cancelled or incomplete." -color "Warning"
        Write-PressEnter
        return
    }

    # Step 5: Site name
    Write-OutputColor "" -color "Info"
    $siteName = Read-Host "  Enter AD site name (default: Default-First-Site-Name)"
    $navResult = Test-NavigationCommand -UserInput $siteName
    if ($navResult.ShouldReturn) { return }

    if ([string]::IsNullOrWhiteSpace($siteName)) {
        $siteName = "Default-First-Site-Name"
    }

    # Step 6: Delegated admin account
    Write-OutputColor "" -color "Info"
    $delegatedAdmin = Read-Host "  Enter delegated RODC admin account (e.g., DOMAIN\RODCAdmin)"
    $navResult = Test-NavigationCommand -UserInput $delegatedAdmin
    if ($navResult.ShouldReturn) { return }

    if ([string]::IsNullOrWhiteSpace($delegatedAdmin)) {
        Write-OutputColor "  No delegated admin specified. Local admin group will be used." -color "Warning"
    }

    # Step 7: DSRM password
    $dsrmPassword = Read-DSRMPassword
    if ($null -eq $dsrmPassword) {
        Write-PressEnter
        return
    }

    # Step 8: Summary
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  READ-ONLY DC CONFIGURATION SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Domain:           $domainName".PadRight(72))│" -color "Info"
    $lineStr = "  Credentials:      $($credential.UserName)"
    if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
    Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Site:             $siteName".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Read-Only:        Yes".PadRight(72))│" -color "Info"
    if (-not [string]::IsNullOrWhiteSpace($delegatedAdmin)) {
        $adminLine = "  Delegated Admin:  $delegatedAdmin"
        if ($adminLine.Length -gt 72) { $adminLine = $adminLine.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($adminLine.PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  │$("  Install DNS:      Yes".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Database Path:    $env:SystemRoot\NTDS".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Log Path:         $env:SystemRoot\NTDS".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  SYSVOL Path:      $env:SystemRoot\SYSVOL".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Step 9: Pre-promotion validation
    $preWarnings = Test-PrePromotionReadiness -DomainName $domainName
    if ($preWarnings -gt 0) {
        if (-not (Confirm-UserAction -Message "Continue despite $preWarnings warning(s)?")) {
            Write-OutputColor "  Promotion cancelled." -color "Info"
            Write-PressEnter
            return
        }
    }

    # Step 10: Confirm
    if (-not (Confirm-UserAction -Message "Promote this server as a Read-Only Domain Controller?")) {
        Write-OutputColor "  Promotion cancelled." -color "Info"
        Write-PressEnter
        return
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        $capDomain = $domainName
        $capCred   = $credential
        $capSite   = $siteName
        $capDSRM   = $dsrmPassword
        $capDel    = $delegatedAdmin
        Push-DryRunStep -Label "Promote to RODC in '$capDomain' (site: $capSite)" -Category "Roles" -OneWay $true `
            -Params @{ DomainName = $capDomain; Site = $capSite; DelegatedAdmin = $capDel } `
            -Preflight {
                if (Test-ADDSInstalled) { "AD DS is already installed on this server" }
                else { $true }
            }.GetNewClosure() `
            -Apply {
                Import-Module ADDSDeployment -ErrorAction Stop
                $rodcParams = @{
                    DomainName                    = $capDomain
                    Credential                    = $capCred
                    SiteName                      = $capSite
                    SafeModeAdministratorPassword = $capDSRM
                    ReadOnlyReplica               = $true
                    InstallDns                    = $true
                    NoRebootOnCompletion          = $true
                    Force                         = $true
                    ErrorAction                   = "Stop"
                }
                if (-not [string]::IsNullOrWhiteSpace($capDel)) {
                    $rodcParams["DelegatedAdministratorAccountName"] = $capDel
                }
                Install-ADDSDomainController @rodcParams
                $script:RebootNeeded = $true
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): promote to RODC in '$capDomain' (ONE-WAY)." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued RODC promotion in '$capDomain'"
        Write-PressEnter
        return
    }

    # Step 11: Execute
    try {
        Write-OutputColor "`n  Promoting server as RODC... This will take several minutes." -color "Info"
        Write-OutputColor "  Do NOT close this window." -color "Warning"

        Import-Module ADDSDeployment -ErrorAction Stop

        $rodcParams = @{
            DomainName                      = $domainName
            Credential                      = $credential
            SiteName                        = $siteName
            SafeModeAdministratorPassword    = $dsrmPassword
            ReadOnlyReplica                  = $true
            InstallDns                       = $true
            NoRebootOnCompletion             = $true
            Force                            = $true
            ErrorAction                      = "Stop"
        }

        if (-not [string]::IsNullOrWhiteSpace($delegatedAdmin)) {
            $rodcParams["DelegatedAdministratorAccountName"] = $delegatedAdmin
        }

        Install-ADDSDomainController @rodcParams

        Write-OutputColor "`n  Read-Only Domain Controller promotion completed successfully!" -color "Success"
        $script:RebootNeeded = $true
        Add-SessionChange -Category "AD DS" -Description "Promoted to RODC in domain $domainName"
        Clear-MenuCache
        Write-OutputColor "  A reboot is required to complete the promotion." -color "Warning"

        Test-PostPromotionStatus -DomainName $domainName
        Test-ADDSReplicationHealth -DomainName $domainName
    }
    catch {
        Write-OutputColor "  Failed to promote RODC: $_" -color "Error"
        Add-SessionChange -Category "AD DS" -Description "RODC promotion failed: $domainName - $_"
        Clear-MenuCache
    }

    Write-PressEnter
}

# Function to display current AD DS status
function Show-ADDSStatus {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                        AD DS STATUS").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # AD DS Role Status
    $addsInstalled = Test-ADDSInstalled
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  AD DS ROLE STATUS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    if ($addsInstalled) {
        Write-OutputColor "  │$("  AD-Domain-Services:  Installed".PadRight(72))│" -color "Success"
    }
    else {
        Write-OutputColor "  │$("  AD-Domain-Services:  Not Installed".PadRight(72))│" -color "Warning"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-PressEnter
        return
    }

    # Check if this server is a Domain Controller — surface probe failure as Unknown
    # so the status report doesn't silently render "Not a DC" on a degraded WMI repo.
    $isDC = $false
    $dcStateKnown = $true
    try {
        $compSys = Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec 8 -ErrorAction Stop
        $osInfo = Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 8 -ErrorAction Stop
        if ($null -ne $osInfo -and $null -ne $compSys) {
            if ($osInfo.ProductType -eq 2 -or $compSys.DomainRole -ge 4) {
                $isDC = $true
            }
        } else {
            $dcStateKnown = $false
        }
    }
    catch {
        $dcStateKnown = $false
    }
    if (-not $dcStateKnown) {
        Write-OutputColor "  │$("  DC Role:             Could not verify (WMI probe failed)".PadRight(72))│" -color "Warning"
    }

    if ($isDC) {
        Write-OutputColor "  │$("  Domain Controller:   Yes".PadRight(72))│" -color "Success"
    }
    else {
        Write-OutputColor "  │$("  Domain Controller:   No".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  This server has the AD DS role but is not promoted as a DC." -color "Info"
        Write-PressEnter
        return
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Forest and Domain information
    try {
        $forest = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
        $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  FOREST / DOMAIN INFORMATION".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        $lineStr = "  Forest Name:       $($forest.Name)"
        if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Forest Mode:       $($forest.ForestMode)".PadRight(72))│" -color "Info"
        $lineStr = "  Domain Name:       $($domain.Name)"
        if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Domain Mode:       $($domain.DomainMode)".PadRight(72))│" -color "Info"

        $dcList = $domain.DomainControllers | ForEach-Object { $_.Name }
        $dcCount = @($dcList).Count
        Write-OutputColor "  │$("  Domain Controllers: $dcCount".PadRight(72))│" -color "Info"
        foreach ($dc in $dcList) {
            $lineStr = "    - $dc"
            if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
    }
    catch {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  Could not retrieve forest/domain information.".PadRight(72))│" -color "Warning"
        $lineStr = "  Error: $($_.Exception.Message)"
        if ($lineStr.Length -gt 72) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Error"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
    }

    # FSMO Roles
    try {
        Import-Module ActiveDirectory -ErrorAction Stop

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  FSMO ROLES".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        $forestInfo = Get-ADForest -ErrorAction SilentlyContinue
        $domainInfo = Get-ADDomain -ErrorAction SilentlyContinue

        if ($null -ne $forestInfo) {
            $lineStr = "  Schema Master:       $($forestInfo.SchemaMaster)"
            if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
            $lineStr = "  Domain Naming:       $($forestInfo.DomainNamingMaster)"
            if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
        }
        if ($null -ne $domainInfo) {
            $lineStr = "  PDC Emulator:        $($domainInfo.PDCEmulator)"
            if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
            $lineStr = "  RID Master:          $($domainInfo.RIDMaster)"
            if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
            $lineStr = "  Infrastructure:      $($domainInfo.InfrastructureMaster)"
            if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
    }
    catch {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  FSMO role information unavailable (AD module not loaded).".PadRight(72))│" -color "Warning"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
    }

    # Replication Status
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $replMetadata = Get-ADReplicationPartnerMetadata -Target $env:COMPUTERNAME -ErrorAction Stop

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  REPLICATION STATUS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        foreach ($partner in $replMetadata) {
            $partnerName = $partner.Partner -replace '^CN=NTDS Settings,CN=', '' -replace ',.*$', ''
            $lastRepl = if ($null -ne $partner.LastReplicationSuccess) {
                $partner.LastReplicationSuccess.ToString("yyyy-MM-dd HH:mm:ss")
            } else {
                "Never"
            }
            $lastResult = if ($partner.LastReplicationResult -eq 0) { "Success" } else { "Error ($($partner.LastReplicationResult))" }
            $resultColor = if ($partner.LastReplicationResult -eq 0) { "Success" } else { "Error" }

            $lineStr = "  Partner: $partnerName"
            if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("    Last Success: $lastRepl  Result: $lastResult".PadRight(72))│" -color $resultColor
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }
    catch {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  Replication data unavailable.".PadRight(72))│" -color "Warning"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }

    Write-OutputColor "" -color "Info"
    Write-PressEnter
}

# Read-only: is the AD Recycle Bin optional feature enabled in this forest?
function Test-ADRecycleBinStatus {
    try {
        if ($null -eq (Get-Command -Name Get-ADOptionalFeature -ErrorAction SilentlyContinue)) {
            return [PSCustomObject]@{ Available = $false; Enabled = $false; Forest = ''; ForestMode = '' }
        }
        $forest = Get-ADForest -ErrorAction Stop
        $feat = Get-ADOptionalFeature -Filter "Name -eq 'Recycle Bin Feature'" -ErrorAction Stop
        $enabled = ($null -ne $feat -and @($feat.EnabledScopes).Count -gt 0)
        return [PSCustomObject]@{ Available = $true; Enabled = $enabled; Forest = "$($forest.Name)"; ForestMode = "$($forest.ForestMode)" }
    }
    catch {
        return [PSCustomObject]@{ Available = $false; Enabled = $false; Forest = ''; ForestMode = '' }
    }
}

# Interactive: enable the AD Recycle Bin. IRREVERSIBLE once enabled.
function Enable-ADRecycleBinFeature {
    Clear-Host
    Write-CenteredOutput "Enable AD Recycle Bin" -color "Info"
    $s = Test-ADRecycleBinStatus
    if (-not $s.Available) {
        Write-OutputColor "  Active Directory module unavailable (not a DC, or RSAT-AD-PowerShell missing)." -color "Error"; return
    }
    if ($s.Enabled) {
        Write-OutputColor "  AD Recycle Bin is already enabled for forest '$($s.Forest)'." -color "Info"; return
    }
    Write-OutputColor "  Forest: $($s.Forest)  (functional level: $($s.ForestMode))" -color "Info"
    Write-OutputColor "  WARNING: Enabling the AD Recycle Bin is PERMANENT — it cannot be disabled" -color "Warning"
    Write-OutputColor "  afterward, and requires a forest functional level of 2008 R2 or higher." -color "Warning"
    if (-not (Confirm-UserAction -Message "Enable the AD Recycle Bin for '$($s.Forest)' (irreversible)?")) {
        Write-OutputColor "  Cancelled." -color "Info"; return
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        $capForest = $s.Forest
        Push-DryRunStep -Label "Enable AD Recycle Bin ($capForest)" -Category "ActiveDirectory" -OneWay $true `
            -Params @{ Forest = $capForest } `
            -Preflight { if ((Test-ADRecycleBinStatus).Enabled) { "AD Recycle Bin already enabled" } else { $true } }.GetNewClosure() `
            -Apply {
                Enable-ADOptionalFeature -Identity 'Recycle Bin Feature' -Scope ForestOrConfigurationSet -Target $capForest -Confirm:$false -ErrorAction Stop | Out-Null
            }.GetNewClosure() `
            -Undo { Write-OutputColor "  AD Recycle Bin cannot be disabled once enabled — no undo." -color "Info" }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run, ONE-WAY): enable AD Recycle Bin." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued AD Recycle Bin enable ($capForest)"
        return
    }

    try {
        Enable-ADOptionalFeature -Identity 'Recycle Bin Feature' -Scope ForestOrConfigurationSet -Target $s.Forest -Confirm:$false -ErrorAction Stop | Out-Null
        Write-OutputColor "  AD Recycle Bin enabled for forest '$($s.Forest)'." -color "Success"
        Add-SessionChange -Category "ActiveDirectory" -Description "Enabled AD Recycle Bin ($($s.Forest))"
        Clear-MenuCache
    }
    catch {
        Write-OutputColor "  Failed to enable AD Recycle Bin: $($_.Exception.Message)" -color "Error"
    }
}

# CLI: ADRecycleBin — JSON status (read-only); interactive enable on console.
function Start-ADRecycleBin {
    if ($script:CLIOutputFormat -eq 'JSON') {
        $s = Test-ADRecycleBinStatus
        Write-Output (@{
            Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'ADRecycleBin'
            Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
            Available = $s.Available; Enabled = $s.Enabled; Forest = $s.Forest; ForestMode = $s.ForestMode
        } | ConvertTo-Json)
        return $true
    }
    Enable-ADRecycleBinFeature
    return $true
}
#endregion
