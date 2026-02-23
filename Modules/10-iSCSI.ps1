#region ===== iSCSI CONFIGURATION =====
# Function to extract host number from hostname (e.g., "123456-HV2" → 2)
function Get-HostNumberFromHostname {
    param (
        [string]$Hostname = $env:COMPUTERNAME
    )

    # Pattern: -HV{number} or -HVN{number} at end
    if ($Hostname -match '-HV(\d+)$') {
        $regexMatches = $matches
        return [int]$regexMatches[1]
    }

    # Pattern: HV{number} anywhere
    if ($Hostname -match 'HV(\d+)') {
        $regexMatches = $matches
        return [int]$regexMatches[1]
    }

    # Pattern: -H{number} at end
    if ($Hostname -match '-H(\d+)$') {
        $regexMatches = $matches
        return [int]$regexMatches[1]
    }

    return $null
}

# Function to calculate iSCSI IP based on host number and port
# Formula: 172.16.1.{(host# + 1) * 10 + port#}
# Host 1, Port 1 → 172.16.1.21 | Host 1, Port 2 → 172.16.1.22
# Host 24, Port 1 → 172.16.1.251 | Host 24, Port 2 → 172.16.1.252
function Get-iSCSIAutoIP {
    param (
        [Parameter(Mandatory=$true)]
        [int]$HostNumber,  # 1-24
        [Parameter(Mandatory=$true)]
        [int]$PortNumber   # 1 or 2
    )

    if ($HostNumber -lt 1 -or $HostNumber -gt 24) {
        return $null  # Out of range
    }

    if ($PortNumber -lt 1 -or $PortNumber -gt 2) {
        return $null
    }

    # Formula: {subnet}.{(host# + 1) * 10 + port#}
    $lastOctet = (($HostNumber + 1) * 10) + $PortNumber
    return "$($script:iSCSISubnet).$lastOctet"
}

# Function to test SAN target connectivity
function Test-SANTargetConnectivity {
    param (
        [string]$Subnet = $script:iSCSISubnet
    )

    Write-OutputColor "Scanning for SAN targets on $Subnet.x network..." -color "Info"

    # SAN IP assignments from configurable target mappings
    $sanIPs = @()
    foreach ($mapping in $script:SANTargetMappings) {
        $sanIPs += @{ IP = "$Subnet.$($mapping.Suffix)"; Label = $mapping.Label; Reachable = $false }
    }

    foreach ($san in $sanIPs) {
        Write-Host "  Testing $($san.IP) ($($san.Label))... " -NoNewline
        $san.Reachable = Test-Connection -ComputerName $san.IP -Count 1 -Quiet -ErrorAction SilentlyContinue
        if ($san.Reachable) {
            Write-Host "OK" -ForegroundColor Green
        }
        else {
            Write-Host "NO RESPONSE" -ForegroundColor Yellow
        }
    }

    return $sanIPs
}

# Function to show iSCSI auto-configuration menu
function Show-iSCSIAutoConfigMenu {
    Clear-Host
    Write-CenteredOutput "iSCSI Configuration Mode" -color "Info"

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$("                        iSCSI CONFIGURATION").PadRight(72)║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-MenuItem "[A]  Auto-configure (recommended for standard Hyper-V hosts)"
    Write-MenuItem "[M]  Manual configuration (current behavior)"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Auto-configure will:" -color "Info"
    Write-OutputColor "    - Detect host number from hostname (e.g., HV2 -> Host #2)" -color "Info"
    Write-OutputColor "    - Calculate IPs automatically: $($script:iSCSISubnet).{host}1, $($script:iSCSISubnet).{host}2" -color "Info"
    Write-OutputColor "    - Ask you to identify A-side and B-side NICs" -color "Info"
    Write-OutputColor "    - Configure both adapters with correct IPs" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to auto-configure iSCSI adapters
function Set-iSCSIAutoConfiguration {
    Clear-Host
    Write-CenteredOutput "iSCSI Auto-Configuration" -color "Info"

    # Step 1: Detect host number from hostname
    $hostNumber = Get-HostNumberFromHostname
    $hostname = $env:COMPUTERNAME

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  HOST DETECTION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Hostname: $hostname".PadRight(72))│" -color "Info"

    if ($null -eq $hostNumber) {
        Write-OutputColor "  │$("  Host Number: NOT DETECTED".PadRight(72))│" -color "Warning"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Could not detect host number from hostname." -color "Warning"
        Write-OutputColor "  Expected format: XXXXXX-HV# (e.g., 123456-HV1, 123456-HV2)" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  Enter host number manually (1-24) or 'back' to cancel:" -color "Warning"
        $manualInput = Read-Host
        $navResult = Test-NavigationCommand -UserInput $manualInput
        if ($navResult.ShouldReturn) { return }

        if ($manualInput -match '^\d+$' -and [int]$manualInput -ge 1 -and [int]$manualInput -le 24) {
            $hostNumber = [int]$manualInput
        }
        else {
            Write-OutputColor "  Invalid host number. Must be 1-24." -color "Error"
            return
        }
    }
    else {
        Write-OutputColor "  │$("  Host Number: $hostNumber".PadRight(72))│" -color "Success"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }

    # Step 2: Calculate IPs
    $ip1 = Get-iSCSIAutoIP -HostNumber $hostNumber -PortNumber 1
    $ip2 = Get-iSCSIAutoIP -HostNumber $hostNumber -PortNumber 2

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CALCULATED IP ADDRESSES".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Port 1 (A-side): $ip1/24".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Port 2 (B-side): $ip2/24".PadRight(72))│" -color "Success"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Step 3: Find iSCSI candidate adapters
    $adapters = Get-NetAdapter | Where-Object {
        $_.Name -notlike "vEthernet*" -and
        $_.InterfaceDescription -notlike "*Hyper-V*" -and
        $_.InterfaceDescription -notlike "*Virtual*"
    }

    # Check if we have candidates from SET auto-detection
    if ($script:iSCSICandidateAdapters -and $script:iSCSICandidateAdapters.Count -gt 0) {
        Write-OutputColor "  Using adapters identified during SET configuration:" -color "Info"
        $adapters = $script:iSCSICandidateAdapters | ForEach-Object { $_.Adapter }
    }

    if ($adapters.Count -lt 2) {
        Write-OutputColor "  Not enough adapters found for dual-path iSCSI configuration." -color "Error"
        Write-OutputColor "  Found $($adapters.Count) adapter(s), need at least 2." -color "Error"
        return
    }

    # Display available adapters
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  AVAILABLE iSCSI ADAPTERS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $adapterList = @()
    $index = 1
    foreach ($adapter in $adapters) {
        $adapterList += @{ Index = $index; Adapter = $adapter }
        $status = if ($adapter.Status -eq "Up") { "[UP]" } else { "[DOWN]" }
        $line = "  [$index] $($adapter.Name) - $($adapter.InterfaceDescription) $status"
        $color = if ($adapter.Status -eq "Up") { "Success" } else { "Warning" }
        Write-OutputColor "  │$($line.PadRight(72))│" -color $color
        $index++
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Step 4: Select A-side NIC
    Write-OutputColor "  Which adapter connects to the A-side switch (SAN A controller)?" -color "Warning"
    Write-OutputColor "  Enter adapter number (or 'back' to cancel):" -color "Info"
    $aSideInput = Read-Host
    $navResult = Test-NavigationCommand -UserInput $aSideInput
    if ($navResult.ShouldReturn) { return }

    if (-not ($aSideInput -match '^\d+$') -or [int]$aSideInput -lt 1 -or [int]$aSideInput -gt $adapterList.Count) {
        Write-OutputColor "  Invalid selection." -color "Error"
        return
    }
    $aSideAdapter = ($adapterList | Where-Object { $_.Index -eq [int]$aSideInput }).Adapter
    if ($null -eq $aSideAdapter) {
        Write-OutputColor "  Failed to find selected A-side adapter." -color "Error"
        return
    }

    # Step 5: Select B-side NIC
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Which adapter connects to the B-side switch (SAN B controller)?" -color "Warning"
    Write-OutputColor "  Enter adapter number (or 'back' to cancel):" -color "Info"
    $bSideInput = Read-Host
    $navResult = Test-NavigationCommand -UserInput $bSideInput
    if ($navResult.ShouldReturn) { return }

    if (-not ($bSideInput -match '^\d+$') -or [int]$bSideInput -lt 1 -or [int]$bSideInput -gt $adapterList.Count) {
        Write-OutputColor "  Invalid selection." -color "Error"
        return
    }
    if ($bSideInput -eq $aSideInput) {
        Write-OutputColor "  Cannot use the same adapter for both sides." -color "Error"
        return
    }
    $bSideAdapter = ($adapterList | Where-Object { $_.Index -eq [int]$bSideInput }).Adapter
    if ($null -eq $bSideAdapter) {
        Write-OutputColor "  Failed to find selected B-side adapter." -color "Error"
        return
    }

    # Step 6: Confirm configuration
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CONFIGURATION SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  A-side: $($aSideAdapter.Name) -> $ip1/24".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  B-side: $($bSideAdapter.Name) -> $ip2/24".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Gateway: None (iSCSI isolated network)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  IPv6: Will be disabled".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Apply this iSCSI configuration?")) {
        Write-OutputColor "  Configuration cancelled." -color "Info"
        return
    }

    # Step 7: Apply configuration
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Applying iSCSI configuration..." -color "Info"
    $aSideOK = $false
    $bSideOK = $false

    # Configure A-side
    try {
        Write-OutputColor "  Configuring $($aSideAdapter.Name) with $ip1/24..." -color "Info"
        Remove-NetIPAddress -InterfaceAlias $aSideAdapter.Name -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute -InterfaceAlias $aSideAdapter.Name -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceAlias $aSideAdapter.Name -IPAddress $ip1 -PrefixLength 24 -ErrorAction Stop
        Disable-NetAdapterBinding -Name $aSideAdapter.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
        Write-OutputColor "    A-side adapter configured successfully." -color "Success"
        $aSideOK = $true
    }
    catch {
        Write-OutputColor "    Failed to configure A-side adapter: $_" -color "Error"
    }

    # Configure B-side
    try {
        Write-OutputColor "  Configuring $($bSideAdapter.Name) with $ip2/24..." -color "Info"
        Remove-NetIPAddress -InterfaceAlias $bSideAdapter.Name -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute -InterfaceAlias $bSideAdapter.Name -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceAlias $bSideAdapter.Name -IPAddress $ip2 -PrefixLength 24 -ErrorAction Stop
        Disable-NetAdapterBinding -Name $bSideAdapter.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
        Write-OutputColor "    B-side adapter configured successfully." -color "Success"
        $bSideOK = $true
    }
    catch {
        Write-OutputColor "    Failed to configure B-side adapter: $_" -color "Error"
    }

    if ($aSideOK -and $bSideOK) {
        Add-SessionChange -Category "Network" -Description "Configured iSCSI: A-side $ip1, B-side $ip2"
    } elseif ($aSideOK -or $bSideOK) {
        $partial = if ($aSideOK) { "A-side $ip1 OK, B-side failed" } else { "A-side failed, B-side $ip2 OK" }
        Write-OutputColor "  Warning: Partial configuration - $partial" -color "Warning"
        Write-OutputColor "  Dual-path iSCSI requires both sides. Fix the failed adapter." -color "Warning"
        Add-SessionChange -Category "Network" -Description "iSCSI PARTIAL: $partial"
    } else {
        Write-OutputColor "  Both iSCSI adapters failed to configure." -color "Error"
        Add-SessionChange -Category "Network" -Description "iSCSI configuration failed (both sides)"
    }

    # Step 8: Test SAN connectivity
    Write-OutputColor "" -color "Info"
    if (Confirm-UserAction -Message "Test SAN target connectivity now?") {
        Write-OutputColor "" -color "Info"
        $sanResults = Test-SANTargetConnectivity
        $reachableCount = ($sanResults | Where-Object { $_.Reachable }).Count

        Write-OutputColor "" -color "Info"
        if ($reachableCount -gt 0) {
            Write-OutputColor "  Found $reachableCount reachable SAN target(s)." -color "Success"
        }
        else {
            Write-OutputColor "  No SAN targets responded." -color "Warning"
            Write-OutputColor "  This may be normal if SAN is not yet configured or online." -color "Info"
        }
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  iSCSI Auto-Configuration Complete!" -color "Success"
}

# Function to configure a single iSCSI adapter
function Set-iSCSIAdapter {
    param (
        [Parameter(Mandatory=$true)]
        $nic
    )

    Write-OutputColor "`n--- Configuring iSCSI Adapter: $($nic.Name) ---" -color "Info"
    Write-OutputColor "Status: $($nic.Status)" -color $(if ($nic.Status -eq "Up") { "Success" } else { "Warning" })

    # Get current configuration
    $currentIP = Get-NetIPAddress -InterfaceAlias $nic.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($currentIP) {
        Write-OutputColor "Current IP: $($currentIP.IPAddress)/$($currentIP.PrefixLength)" -color "Info"
    }
    else {
        Write-OutputColor "Current IP: None configured" -color "Info"
    }

    # Get IP and subnet for iSCSI
    $ipResult = Get-IPAddressAndSubnet -Prompt "Enter iSCSI IP address (e.g., 10.0.0.100/24)"

    if ($null -eq $ipResult) {
        Write-OutputColor "Skipping $($nic.Name)..." -color "Warning"
        return
    }

    $ipAddress = $ipResult[0]
    $cidr = $ipResult[1]

    # Confirm before applying
    Write-OutputColor "`nConfiguration for $($nic.Name):" -color "Info"
    Write-OutputColor "  IP: $ipAddress/$cidr" -color "Info"
    Write-OutputColor "  Gateway: None (iSCSI traffic only)" -color "Info"
    Write-OutputColor "  IPv6: Will be disabled" -color "Info"

    $confirmation = Read-Host "Proceed with these values? (yes or no)"

    $navResult = Test-NavigationCommand -UserInput $confirmation
    if ($navResult.ShouldReturn) { return }

    if ($confirmation -notmatch '^(y|yes)$') {
        Write-OutputColor "Skipping $($nic.Name)..." -color "Warning"
        return
    }

    try {
        # Remove existing IPs
        Remove-NetIPAddress -InterfaceAlias $nic.Name -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute -InterfaceAlias $nic.Name -Confirm:$false -ErrorAction SilentlyContinue

        # Set static IP (no gateway for iSCSI)
        New-NetIPAddress -InterfaceAlias $nic.Name -IPAddress $ipAddress -PrefixLength $cidr -ErrorAction Stop

        # Disable IPv6
        Disable-NetAdapterBinding -Name $nic.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue

        Write-OutputColor "iSCSI configuration applied to $($nic.Name)" -color "Success"
    }
    catch {
        Write-OutputColor "Failed to configure $($nic.Name): $_" -color "Error"
    }
}

# Function to configure iSCSI adapters
function Set-iSCSIConfiguration {
    # Show auto-config menu
    $choice = Show-iSCSIAutoConfigMenu

    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    switch -Regex ($choice) {
        '^[Aa]$' {
            Set-iSCSIAutoConfiguration
        }
        '^[Mm]$' {
            # Manual mode - original behavior
            Clear-Host
            Write-CenteredOutput "iSCSI NIC Configuration (Manual)" -color "Info"

            Write-OutputColor "`nThis will configure network adapters for iSCSI storage traffic." -color "Info"
            Write-OutputColor "iSCSI NICs should NOT have a default gateway configured." -color "Warning"
            Write-OutputColor "" -color "Info"

            $selectedAdapters = Select-iSCSI-Adapters

            if ($null -eq $selectedAdapters) {
                Write-OutputColor "No adapters selected for iSCSI configuration." -color "Warning"
                return
            }

            $totalCount = @($selectedAdapters).Count

            foreach ($adapter in $selectedAdapters) {
                Set-iSCSIAdapter -nic $adapter
            }

            Write-OutputColor "`niSCSI Configuration Complete" -color "Success"
            Write-OutputColor "Processed: $totalCount adapter(s)" -color "Info"
        }
        '^[Bb]$' {
            return
        }
        default {
            Write-OutputColor "Invalid selection." -color "Error"
        }
    }
}

# Function to get SAN target IPs for a specific host
# Server 1: .10 (A0), .11 (B1) | Server 2: .12 (B0), .13 (A1) | etc.
# All SAN target pairs - rebuilt by Initialize-SANTargetPairs (called from Import-Defaults)
# Default initialization using $script:iSCSISubnet (refreshed at startup by Import-Defaults)
$script:SANTargetPairs = @(
    @{ Index = 0; A = "$($script:iSCSISubnet).10"; B = "$($script:iSCSISubnet).11"; ALabel = "A0"; BLabel = "B1"; Labels = "A0/B1" },
    @{ Index = 1; A = "$($script:iSCSISubnet).13"; B = "$($script:iSCSISubnet).12"; ALabel = "A1"; BLabel = "B0"; Labels = "A1/B0" },
    @{ Index = 2; A = "$($script:iSCSISubnet).14"; B = "$($script:iSCSISubnet).15"; ALabel = "A2"; BLabel = "B3"; Labels = "A2/B3" },
    @{ Index = 3; A = "$($script:iSCSISubnet).17"; B = "$($script:iSCSISubnet).16"; ALabel = "A3"; BLabel = "B2"; Labels = "A3/B2" }
)

# Function to get SAN target pairs in retry order for a specific host
# Host 1 (A0/B1): → A2/B3 → A1/B0 → A3/B2
# Host 2 (A1/B0): → A3/B2 → A0/B1 → A2/B3
# Host 3 (A2/B3): → A0/B1 → A3/B2 → A1/B0
# Host 4 (A3/B2): → A1/B0 → A2/B3 → A0/B1
function Get-SANTargetsForHost {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateRange(1,24)]
        [int]$HostNumber,
        [switch]$AllPairsInRetryOrder
    )

    # Primary pair index based on host number (1-4 cycles)
    $primaryIndex = ($HostNumber - 1) % 4

    if (-not $AllPairsInRetryOrder) {
        # Just return primary pair
        return $script:SANTargetPairs[$primaryIndex]
    }

    # Return all pairs in retry order:
    # Primary → Primary+2 → remaining two in order
    $retryOrder = @()

    # 1. Primary pair
    $retryOrder += $script:SANTargetPairs[$primaryIndex]

    # 2. Primary + 2 (mod 4)
    $secondIndex = ($primaryIndex + 2) % 4
    $retryOrder += $script:SANTargetPairs[$secondIndex]

    # 3. Remaining two pairs (the ones not yet added)
    $usedIndices = @($primaryIndex, $secondIndex)
    for ($i = 0; $i -lt 4; $i++) {
        if ($i -notin $usedIndices) {
            $retryOrder += $script:SANTargetPairs[$i]
        }
    }

    return $retryOrder
}

# Function to find reachable SAN targets with auto-retry
function Find-ReachableSANTargets {
    param (
        [Parameter(Mandatory=$true)]
        [int]$HostNumber
    )

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Finding reachable SAN targets for Host #$HostNumber..." -color "Info"

    # Get all pairs in retry order
    $allPairs = Get-SANTargetsForHost -HostNumber $HostNumber -AllPairsInRetryOrder

    $attemptNum = 1
    foreach ($pair in $allPairs) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Attempt $attemptNum/4: Testing $($pair.Labels) ($($pair.A), $($pair.B))..." -color "Info"

        # Test A-side
        Write-Host "    Pinging A-side ($($pair.A))... " -NoNewline
        $aReachable = Test-Connection -ComputerName $pair.A -Count 1 -Quiet -ErrorAction SilentlyContinue
        if ($aReachable) {
            Write-Host "OK" -ForegroundColor Green
        } else {
            Write-Host "NO RESPONSE" -ForegroundColor Yellow
        }

        # Test B-side
        Write-Host "    Pinging B-side ($($pair.B))... " -NoNewline
        $bReachable = Test-Connection -ComputerName $pair.B -Count 1 -Quiet -ErrorAction SilentlyContinue
        if ($bReachable) {
            Write-Host "OK" -ForegroundColor Green
        } else {
            Write-Host "NO RESPONSE" -ForegroundColor Yellow
        }

        # If both are reachable, return this pair
        if ($aReachable -and $bReachable) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Found reachable pair: $($pair.Labels)" -color "Success"
            return @{
                Pair = $pair
                AReachable = $true
                BReachable = $true
                Success = $true
            }
        }

        # If at least one is reachable, note it but continue trying
        if ($aReachable -or $bReachable) {
            Write-OutputColor "    Partial connectivity - trying next pair..." -color "Warning"
        } else {
            Write-OutputColor "    No connectivity - trying next pair..." -color "Warning"
        }

        $attemptNum++
    }

    # No fully reachable pair found
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  No fully reachable SAN target pair found." -color "Error"
    Write-OutputColor "  Please verify iSCSI network connectivity." -color "Warning"

    return @{
        Pair = $null
        AReachable = $false
        BReachable = $false
        Success = $false
    }
}

# Function to disable a NIC for identification purposes
function Disable-NICForIdentification {
    param (
        [Parameter(Mandatory=$true)]
        $Adapter
    )

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Disabling $($Adapter.Name) for identification..." -color "Warning"
    Write-OutputColor "  Watch your switch port lights to identify which NIC this is." -color "Info"

    try {
        Disable-NetAdapter -Name $Adapter.Name -Confirm:$false -ErrorAction Stop
        Write-OutputColor "  NIC disabled. Press Enter when ready to re-enable..." -color "Warning"
        Read-Host
        Enable-NetAdapter -Name $Adapter.Name -Confirm:$false -ErrorAction Stop
        Write-OutputColor "  NIC re-enabled." -color "Success"
    }
    catch {
        Write-OutputColor "  Error managing adapter: $_" -color "Error"
        # Try to re-enable in case of error
        Enable-NetAdapter -Name $Adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
    }
}

# Function to show NIC identification menu
function Show-NICIdentificationMenu {
    param (
        [array]$Adapters
    )

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  NIC IDENTIFICATION HELPER".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  This will temporarily disable a NIC so you can identify it by".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  watching which port light goes out on your switch.".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $index = 1
    foreach ($adapter in $Adapters) {
        $status = if ($adapter.Status -eq "Up") { "[UP]" } else { "[DOWN]" }
        Write-OutputColor "  [$index] Disable $($adapter.Name) $status" -color "Success"
        $index++
    }
    Write-OutputColor "  [R] Refresh adapter list" -color "Info"
    Write-OutputColor "  [B] ◄ Back (done identifying)" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select adapter to disable for identification"
    return $choice
}

# Function to connect to iSCSI targets
function Connect-iSCSITargets {
    param (
        [Parameter(Mandatory=$true)]
        [string[]]$TargetPortalAddresses,
        [int]$TargetPortalPort = 3260
    )

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Connecting to iSCSI targets..." -color "Info"

    foreach ($portal in $TargetPortalAddresses) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Processing portal: $portal" -color "Info"

        try {
            # Check if portal already exists
            $existingPortal = Get-IscsiTargetPortal -TargetPortalAddress $portal -ErrorAction SilentlyContinue

            if (-not $existingPortal) {
                Write-OutputColor "    Registering target portal..." -color "Info"
                New-IscsiTargetPortal -TargetPortalAddress $portal -TargetPortalPortNumber $TargetPortalPort -ErrorAction Stop
            }
            else {
                Write-OutputColor "    Portal already registered." -color "Info"
            }

            # Discover targets
            $targets = Get-IscsiTarget | Where-Object { $_.IsConnected -eq $false }

            if ($targets) {
                foreach ($target in $targets) {
                    Write-OutputColor "    Connecting to target: $($target.NodeAddress)..." -color "Info"
                    try {
                        Connect-IscsiTarget -NodeAddress $target.NodeAddress -TargetPortalAddress $portal `
                            -IsPersistent $true -IsMultipathEnabled $true -ErrorAction Stop
                        Write-OutputColor "    Connected successfully!" -color "Success"
                    }
                    catch {
                        Write-OutputColor "    Failed to connect: $_" -color "Warning"
                    }
                }
            }
            else {
                Write-OutputColor "    No disconnected targets found for this portal." -color "Info"
            }
        }
        catch {
            Write-OutputColor "    Failed to process portal: $_" -color "Error"
        }
    }
}

# Function to initialize MPIO for iSCSI
function Initialize-MPIOForISCSI {
    Clear-Host
    Write-CenteredOutput "Initialize MPIO for iSCSI" -color "Info"

    # Check if MPIO is installed
    if (-not (Test-MPIOInstalled)) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  PREREQUISITE MISSING".PadRight(72))│" -color "Warning"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  MPIO (Multipath I/O) is not installed.".PadRight(72))│" -color "Error"
        Write-OutputColor "  │$("  ".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  MPIO is required for iSCSI multipath connections to your SAN.".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  A reboot will be required after installation.".PadRight(72))│" -color "Warning"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [I] Install MPIO now" -color "Success"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return $false }

        if ($choice -eq "I" -or $choice -eq "i") {
            Install-MPIOFeature
            Write-PressEnter

            # Recheck after install attempt
            if (Test-MPIOInstalled) {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  MPIO installed! A reboot is required before MPIO can be configured." -color "Warning"
                Write-OutputColor "  After rebooting, return here to initialize MPIO for iSCSI." -color "Info"
            }
            return $false
        }
        return $false
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  MPIO is installed. Configuring for iSCSI..." -color "Info"

    try {
        # Enable MPIO for iSCSI devices
        Write-OutputColor "  Enabling MPIO for iSCSI bus type..." -color "Info"
        Enable-MSDSMAutomaticClaim -BusType iSCSI -ErrorAction Stop
        Write-OutputColor "    iSCSI automatic claim enabled." -color "Success"

        # Set load balance policy to Round Robin
        Write-OutputColor "  Setting load balance policy to Round Robin..." -color "Info"
        Set-MSDSMGlobalDefaultLoadBalancePolicy -Policy RR -ErrorAction Stop
        Write-OutputColor "    Load balance policy set." -color "Success"

        # Show supported hardware
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  MPIO Supported Hardware:" -color "Info"
        $supportedHW = Get-MSDSMSupportedHW -ErrorAction SilentlyContinue
        if ($supportedHW) {
            foreach ($hw in $supportedHW) {
                Write-OutputColor "    $($hw.VendorId.Trim()) - $($hw.ProductId.Trim())" -color "Success"
            }
        }
        else {
            Write-OutputColor "    No hardware registered yet (will auto-detect on iSCSI connection)" -color "Info"
        }

        Add-SessionChange -Category "System" -Description "Configured MPIO for iSCSI"
        return $true
    }
    catch {
        Write-OutputColor "  Failed to configure MPIO: $_" -color "Error"
        return $false
    }
}

# Function to show iSCSI status
function Show-iSCSIStatus {
    Clear-Host
    Write-CenteredOutput "iSCSI & MPIO Status" -color "Info"

    Write-OutputColor "" -color "Info"

    # iSCSI Sessions
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  iSCSI SESSIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $sessions = Get-IscsiSession -ErrorAction SilentlyContinue
    if ($sessions) {
        foreach ($session in $sessions) {
            $line = "  $($session.TargetNodeAddress)"
            Write-OutputColor "  │$($line.PadRight(72))│" -color "Success"
            Write-OutputColor "  │$("    Portal: $($session.TargetPortalAddress):$($session.TargetPortalPortNumber)".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("    Persistent: $($session.IsPersistent) | Connected: $($session.IsConnected)".PadRight(72))│" -color "Info"
        }
    }
    else {
        Write-OutputColor "  │$("  No active iSCSI sessions".PadRight(72))│" -color "Warning"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    # iSCSI Targets
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  iSCSI TARGETS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $targets = Get-IscsiTarget -ErrorAction SilentlyContinue
    if ($targets) {
        foreach ($target in $targets) {
            $status = if ($target.IsConnected) { "[CONNECTED]" } else { "[DISCONNECTED]" }
            $color = if ($target.IsConnected) { "Success" } else { "Warning" }
            # Truncate long IQN names
            $iqn = $target.NodeAddress
            if ($iqn.Length -gt 60) { $iqn = $iqn.Substring(0, 57) + "..." }
            Write-OutputColor "  │$("  $iqn $status".PadRight(72))│" -color $color
        }
    }
    else {
        Write-OutputColor "  │$("  No iSCSI targets discovered".PadRight(72))│" -color "Warning"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    # MPIO Status
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  MPIO STATUS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    if (Test-MPIOInstalled) {
        Write-OutputColor "  │$("  MPIO: Installed".PadRight(72))│" -color "Success"

        try {
            $policy = Get-MSDSMGlobalDefaultLoadBalancePolicy -ErrorAction SilentlyContinue
            $policyName = switch ($policy) {
                "RR" { "Round Robin" }
                "LQD" { "Least Queue Depth" }
                "FOO" { "Failover Only" }
                "LB" { "Least Blocks" }
                "WP" { "Weighted Paths" }
                default { $policy }
            }
            Write-OutputColor "  │$("  Load Balance Policy: $policyName".PadRight(72))│" -color "Info"
        }
        catch {
            Write-OutputColor "  │$("  Load Balance Policy: Unknown".PadRight(72))│" -color "Warning"
        }

        # Show MPIO disks
        $mpioDisks = Get-MSDSMAutomaticClaimSettings -ErrorAction SilentlyContinue
        if ($mpioDisks) {
            Write-OutputColor "  │$("  iSCSI Auto-Claim: Enabled".PadRight(72))│" -color "Success"
        }
    }
    else {
        Write-OutputColor "  │$("  MPIO: Not Installed".PadRight(72))│" -color "Warning"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    # iSCSI Disk Mappings
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  DISK MAPPINGS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $iscsiDisks = Get-Disk | Where-Object { $_.BusType -eq "iSCSI" } -ErrorAction SilentlyContinue
    if ($iscsiDisks) {
        foreach ($disk in $iscsiDisks) {
            $sizeGB = [math]::Round($disk.Size / 1GB, 1)
            $status = $disk.OperationalStatus
            Write-OutputColor "  │$("  Disk $($disk.Number): $($disk.FriendlyName) | $sizeGB GB | $status".PadRight(72))│" -color "Success"
        }
    }
    else {
        Write-OutputColor "  │$("  No iSCSI disks found".PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

# Function to disconnect iSCSI targets
function Disconnect-iSCSITargets {
    Clear-Host
    Write-CenteredOutput "Disconnect iSCSI Targets" -color "Info"

    $sessions = Get-IscsiSession -ErrorAction SilentlyContinue

    if (-not $sessions) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  No active iSCSI sessions to disconnect." -color "Info"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Active iSCSI Sessions:" -color "Info"
    Write-OutputColor "" -color "Info"

    $index = 1
    foreach ($session in $sessions) {
        $iqn = $session.TargetNodeAddress
        if ($iqn.Length -gt 50) { $iqn = $iqn.Substring(0, 47) + "..." }
        Write-OutputColor "  [$index] $iqn" -color "Info"
        Write-OutputColor "      Portal: $($session.TargetPortalAddress)" -color "Info"
        $index++
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [A] Disconnect ALL sessions" -color "Warning"
    Write-OutputColor "  [B] ◄ Back (keep sessions)" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select session to disconnect"

    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    if ($choice -match '^[Aa]$') {
        if (Confirm-UserAction -Message "Disconnect ALL iSCSI sessions? This may cause data loss if disks are in use!") {
            foreach ($session in $sessions) {
                try {
                    Disconnect-IscsiTarget -NodeAddress $session.TargetNodeAddress -Confirm:$false -ErrorAction Stop
                    Write-OutputColor "  Disconnected: $($session.TargetNodeAddress)" -color "Success"
                }
                catch {
                    Write-OutputColor "  Failed to disconnect: $_" -color "Error"
                }
            }
        }
    }
    elseif ($choice -match '^\d+$') {
        $selectedIndex = [int]$choice
        if ($selectedIndex -ge 1 -and $selectedIndex -le $sessions.Count) {
            $selectedSession = $sessions[$selectedIndex - 1]
            if (Confirm-UserAction -Message "Disconnect session to $($selectedSession.TargetNodeAddress)?") {
                try {
                    Disconnect-IscsiTarget -NodeAddress $selectedSession.TargetNodeAddress -Confirm:$false -ErrorAction Stop
                    Write-OutputColor "  Disconnected successfully." -color "Success"
                }
                catch {
                    Write-OutputColor "  Failed to disconnect: $_" -color "Error"
                }
            }
        }
        else {
            Write-OutputColor "  Invalid selection." -color "Error"
        }
    }
}

# Function to show iSCSI & SAN Management menu
function Show-iSCSISANMenu {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                      iSCSI & SAN MANAGEMENT").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CONFIGURATION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[1]  Configure iSCSI NICs"
    Write-MenuItem "[2]  Identify NICs (disable/enable for switch ID)"
    Write-MenuItem "[3]  Discover SAN Targets (ping test)"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CONNECTION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[4]  Connect to iSCSI Targets"
    Write-MenuItem "[5]  Configure MPIO Multipath"
    Write-MenuItem "[6]  Show iSCSI/MPIO Status"
    Write-MenuItem "[7]  Disconnect iSCSI Targets"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  [B] ◄ Back to Host Network    [M] ◄◄ Server Config" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to run iSCSI & SAN Management menu
function Start-Show-iSCSISANMenu {
    while ($true) {
        $choice = Show-iSCSISANMenu

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
                Set-iSCSIConfiguration
                Write-PressEnter
            }
            "2" {
                # NIC identification helper
                $adapters = Get-NetAdapter | Where-Object {
                    $_.Name -notlike "vEthernet*" -and
                    $_.InterfaceDescription -notlike "*Hyper-V*" -and
                    $_.InterfaceDescription -notlike "*Virtual*"
                }

                if (-not $adapters -or $adapters.Count -eq 0) {
                    Write-OutputColor "  No physical adapters found." -color "Error"
                    Write-PressEnter
                }
                else {
                    while ($true) {
                        $identifyChoice = Show-NICIdentificationMenu -Adapters $adapters
                        if ($identifyChoice -match '^[Bb]$') {
                            break
                        }
                        elseif ($identifyChoice -match '^[Rr]$') {
                            # Refresh adapter list
                            $adapters = Get-NetAdapter | Where-Object {
                                $_.Name -notlike "vEthernet*" -and
                                $_.InterfaceDescription -notlike "*Hyper-V*" -and
                                $_.InterfaceDescription -notlike "*Virtual*"
                            }
                            continue
                        }
                        elseif ($identifyChoice -match '^\d+$') {
                            $idx = [int]$identifyChoice
                            if ($idx -ge 1 -and $idx -le $adapters.Count) {
                                Disable-NICForIdentification -Adapter $adapters[$idx - 1]
                                # Refresh after enable
                                $adapters = Get-NetAdapter | Where-Object {
                                    $_.Name -notlike "vEthernet*" -and
                                    $_.InterfaceDescription -notlike "*Hyper-V*" -and
                                    $_.InterfaceDescription -notlike "*Virtual*"
                                }
                            }
                        }
                    }
                }
            }
            "3" {
                Write-OutputColor "" -color "Info"
                $null = Test-SANTargetConnectivity
                Write-PressEnter
            }
            "4" {
                # Connect to iSCSI Targets
                Clear-Host
                Write-CenteredOutput "Connect to iSCSI Targets" -color "Info"

                $hostNumber = Get-HostNumberFromHostname
                if ($hostNumber) {
                    # Show primary and retry order
                    $allPairs = Get-SANTargetsForHost -HostNumber $hostNumber -AllPairsInRetryOrder
                    Write-OutputColor "" -color "Info"
                    Write-OutputColor "  Host #$hostNumber SAN target priority:" -color "Info"
                    $priority = 1
                    foreach ($pair in $allPairs) {
                        $marker = if ($priority -eq 1) { "(Primary)" } else { "" }
                        Write-OutputColor "    $priority. $($pair.Labels) - A:$($pair.A) B:$($pair.B) $marker" -color "Info"
                        $priority++
                    }
                    Write-OutputColor "" -color "Info"

                    Write-OutputColor "  [A] Auto-detect (ping test with retry)" -color "Success"
                    Write-OutputColor "  [M] Manual (enter IPs)" -color "Success"
                    Write-OutputColor "  [P] Use primary pair ($($allPairs[0].Labels)) without testing" -color "Success"
                    Write-OutputColor "  [B] ◄ Back" -color "Info"
                    Write-OutputColor "" -color "Info"

                    $connectChoice = Read-Host "  Select"

                    switch -Regex ($connectChoice) {
                        '^[Aa]$' {
                            # Auto-detect with retry
                            $result = Find-ReachableSANTargets -HostNumber $hostNumber
                            if ($result.Success) {
                                Write-OutputColor "" -color "Info"
                                if (Confirm-UserAction -Message "Connect to $($result.Pair.Labels)?") {
                                    Connect-iSCSITargets -TargetPortalAddresses @($result.Pair.A, $result.Pair.B)
                                }
                            }
                        }
                        '^[Mm]$' {
                            Write-OutputColor "" -color "Info"
                            Write-OutputColor "  Enter target portal IPs (comma-separated):" -color "Warning"
                            $manualTargets = Read-Host
                            if (-not [string]::IsNullOrWhiteSpace($manualTargets)) {
                                $targetList = $manualTargets -split ',' | ForEach-Object { $_.Trim() }
                                Connect-iSCSITargets -TargetPortalAddresses $targetList
                            }
                        }
                        '^[Pp]$' {
                            Write-OutputColor "" -color "Info"
                            Write-OutputColor "  Connecting to primary pair: $($allPairs[0].Labels)" -color "Info"
                            Connect-iSCSITargets -TargetPortalAddresses @($allPairs[0].A, $allPairs[0].B)
                        }
                        '^[Bb]$' {
                            # Back - do nothing
                        }
                    }
                }
                else {
                    Write-OutputColor "" -color "Info"
                    Write-OutputColor "  Could not detect host number from hostname." -color "Warning"
                    Write-OutputColor "  Expected format: XXXXXX-HV# (e.g., 123456-HV1)" -color "Info"
                    Write-OutputColor "" -color "Info"

                    Write-OutputColor "  Enter host number manually (1-24) or target IPs:" -color "Warning"
                    $manualInput = Read-Host

                    if ($manualInput -match '^\d+$' -and [int]$manualInput -ge 1 -and [int]$manualInput -le 24) {
                        # User entered a host number
                        $hostNumber = [int]$manualInput
                        $result = Find-ReachableSANTargets -HostNumber $hostNumber
                        if ($result.Success) {
                            Write-OutputColor "" -color "Info"
                            if (Confirm-UserAction -Message "Connect to $($result.Pair.Labels)?") {
                                Connect-iSCSITargets -TargetPortalAddresses @($result.Pair.A, $result.Pair.B)
                            }
                        }
                    }
                    elseif (-not [string]::IsNullOrWhiteSpace($manualInput)) {
                        # User entered IPs
                        $targetList = $manualInput -split ',' | ForEach-Object { $_.Trim() }
                        Connect-iSCSITargets -TargetPortalAddresses $targetList
                    }
                }
                Write-PressEnter
            }
            "5" {
                $null = Initialize-MPIOForISCSI
                Write-PressEnter
            }
            "6" {
                Show-iSCSIStatus
                Write-PressEnter
            }
            "7" {
                Disconnect-iSCSITargets
                Write-PressEnter
            }
            "M" {
                $global:ReturnToMainMenu = $true
                return
            }
            default {
                Write-OutputColor "Invalid choice. Please enter 1-7, B, or M." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}
#endregion