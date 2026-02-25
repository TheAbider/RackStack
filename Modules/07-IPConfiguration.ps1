#region ===== IP CONFIGURATION FUNCTIONS =====
# Function to convert subnet mask to CIDR prefix
function Convert-SubnetMaskToPrefix {
    param (
        [Parameter(Mandatory=$true)]
        [string]$SubnetMask
    )

    try {
        $octets = $SubnetMask -split '\.'
        if ($octets.Count -ne 4) { return $null }

        $binary = ($octets | ForEach-Object { [convert]::ToString([int]$_, 2).PadLeft(8, '0') }) -join ''

        # Count the 1s
        $prefix = ($binary.ToCharArray() | Where-Object { $_ -eq '1' }).Count

        # Verify it's a valid mask (contiguous 1s)
        if ($binary -notmatch '^1*0*$') {
            return $null
        }

        return $prefix
    }
    catch {
        return $null
    }
}

# Function to get IP address and subnet with proper handling
function Get-IPAddressAndSubnet {
    param (
        [string]$Prompt = "Enter IP address (e.g., 192.168.1.100/24 or 192.168.1.100)"
    )

    Write-OutputColor $Prompt -color "Info"
    $ipInput = Read-Host

    $navResult = Test-NavigationCommand -UserInput $ipInput
    if ($navResult.ShouldReturn) { return $null }

    if ([string]::IsNullOrWhiteSpace($ipInput)) {
        Write-OutputColor "No IP address entered." -color "Error"
        return $null
    }

    # Check if CIDR notation is included
    if ($ipInput -match '^(.+)/(\d+)$') {
        $regexMatches = $matches
        $ipAddress = $regexMatches[1]
        $cidr = [int]$regexMatches[2]

        if (-not (Test-ValidIPAddress -IPAddress $ipAddress)) {
            Write-OutputColor "Invalid IP address format. Must be X.X.X.X (e.g., 192.168.1.100)" -color "Error"
            return $null
        }

        if ($cidr -lt 0 -or $cidr -gt 32) {
            Write-OutputColor "Invalid CIDR prefix. Must be between 0-32 (common: 24=/24, 16=/16, 8=/8)" -color "Error"
            return $null
        }

        return @($ipAddress, $cidr)
    }
    else {
        # No CIDR, need subnet mask
        $ipAddress = $ipInput

        if (-not (Test-ValidIPAddress -IPAddress $ipAddress)) {
            Write-OutputColor "Invalid IP address format. Must be X.X.X.X (e.g., 192.168.1.100)" -color "Error"
            return $null
        }

        Write-OutputColor "Enter subnet mask (e.g., 255.255.255.0) or CIDR prefix (e.g., 24):" -color "Info"
        $subnetInput = Read-Host

        $navResult = Test-NavigationCommand -UserInput $subnetInput
        if ($navResult.ShouldReturn) { return $null }

        if ([string]::IsNullOrWhiteSpace($subnetInput)) {
            Write-OutputColor "No subnet entered." -color "Error"
            return $null
        }

        # Check if it's just a number (CIDR)
        if ($subnetInput -match '^\d{1,2}$') {
            $cidr = [int]$subnetInput
            if ($cidr -lt 0 -or $cidr -gt 32) {
                Write-OutputColor "Invalid CIDR prefix. Must be between 0-32 (common: 24, 16, 8)" -color "Error"
                return $null
            }
            return @($ipAddress, $cidr)
        }
        else {
            # It's a subnet mask
            $cidr = Convert-SubnetMaskToPrefix -SubnetMask $subnetInput
            if ($null -eq $cidr) {
                Write-OutputColor "Invalid subnet mask. Must be X.X.X.X (e.g., 255.255.255.0 = /24)" -color "Error"
                return $null
            }
            return @($ipAddress, $cidr)
        }
    }
}

# Function to get gateway address
function Get-GatewayAddress {
    Write-OutputColor "Enter default gateway (e.g., 192.168.1.1):" -color "Info"
    $gateway = Read-Host

    $navResult = Test-NavigationCommand -UserInput $gateway
    if ($navResult.ShouldReturn) { return $null }

    if ([string]::IsNullOrWhiteSpace($gateway)) {
        Write-OutputColor "No gateway entered." -color "Error"
        return $null
    }

    if (-not (Test-ValidIPAddress -IPAddress $gateway)) {
        Write-OutputColor "Invalid gateway format. Must be X.X.X.X (e.g., 192.168.1.1)" -color "Error"
        return $null
    }

    return $gateway
}

# Function to configure IP on an adapter for VMs
function Set-VMIPAddress {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$selectedAdapterName
    )

    # Get current IP configuration
    $currentIP = Get-NetIPAddress -InterfaceAlias $selectedAdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($currentIP) {
        Write-OutputColor "Current IP: $($currentIP.IPAddress)/$($currentIP.PrefixLength)" -color "Info"
    }

    # Get IP and subnet
    $ipResult = Get-IPAddressAndSubnet
    if ($null -eq $ipResult) {
        return
    }

    $ipAddress = $ipResult[0]
    $cidr = $ipResult[1]

    # Check if IP is already in use (informational, non-blocking)
    $ipCheck = Test-IPAddressInUse -IPAddress $ipAddress
    if ($ipCheck.InUse) {
        Write-OutputColor "  Warning: $ipAddress appears to be in use!" -color "Warning"
        if ($ipCheck.DNSEntry) {
            Write-OutputColor "  Responding host: $($ipCheck.DNSEntry)" -color "Warning"
        }
        if (-not (Confirm-UserAction -Message "Continue with this IP anyway?")) {
            return
        }
    }

    # Get gateway
    $gateway = Get-GatewayAddress
    if ($null -eq $gateway) {
        return
    }

    # Confirm before applying
    Write-OutputColor "`nConfiguration to apply:" -color "Info"
    Write-OutputColor "  Adapter: $selectedAdapterName" -color "Info"
    Write-OutputColor "  IP: $ipAddress/$cidr" -color "Info"
    Write-OutputColor "  Gateway: $gateway" -color "Info"
    Write-OutputColor "`nWarning: This may disconnect your session!" -color "Critical"

    if (-not (Confirm-UserAction -Message "Apply this configuration?")) {
        Write-OutputColor "Configuration cancelled." -color "Warning"
        return
    }

    try {
        # Save current config for rollback
        $previousIP = Get-NetIPAddress -InterfaceAlias $selectedAdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
        $previousRoute = Get-NetRoute -InterfaceAlias $selectedAdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' }

        # Remove existing IPv4 configuration only
        Remove-NetIPAddress -InterfaceAlias $selectedAdapterName -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute -InterfaceAlias $selectedAdapterName -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue

        # Apply new configuration
        try {
            New-NetIPAddress -InterfaceAlias $selectedAdapterName -IPAddress $ipAddress -PrefixLength $cidr -DefaultGateway $gateway -ErrorAction Stop
        }
        catch {
            # Rollback: restore previous IP if new one fails
            Write-OutputColor "Failed to apply new IP: $_" -color "Error"
            if ($null -ne $previousIP) {
                Write-OutputColor "Restoring previous IP configuration..." -color "Warning"
                try {
                    $rollbackParams = @{
                        InterfaceAlias = $selectedAdapterName
                        IPAddress      = $previousIP.IPAddress
                        PrefixLength   = $previousIP.PrefixLength
                        ErrorAction    = 'Stop'
                    }
                    if ($null -ne $previousRoute) {
                        $rollbackParams.DefaultGateway = $previousRoute.NextHop
                    }
                    New-NetIPAddress @rollbackParams
                    Write-OutputColor "Previous IP restored: $($previousIP.IPAddress)/$($previousIP.PrefixLength)" -color "Success"
                }
                catch {
                    Write-OutputColor "WARNING: Could not restore previous IP. Adapter may need manual configuration." -color "Critical"
                }
            }
            return
        }

        # Disable IPv6
        Disable-NetAdapterBinding -Name $selectedAdapterName -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue

        Write-OutputColor "IP configuration applied successfully!" -color "Success"
        Add-SessionChange -Category "Network" -Description "Set IP $ipAddress/$cidr on $selectedAdapterName"

        # Wait for address to leave Tentative state (DAD takes 1-3 seconds)
        $dadWait = 0
        while ($dadWait -lt 10) {
            Start-Sleep -Seconds 1
            $dadWait++
            $addrObj = Get-NetIPAddress -InterfaceAlias $selectedAdapterName -IPAddress $ipAddress -ErrorAction SilentlyContinue
            if ($null -ne $addrObj -and $addrObj.AddressState -eq 'Preferred') { break }
        }

        # Show updated configuration
        Show-AdapterStatus -AdapterName $selectedAdapterName

        # Test connectivity to gateway (non-blocking, informational only)
        Write-OutputColor "`nTesting connectivity to gateway..." -color "Info"
        $pingResult = Test-Connection -ComputerName $gateway -Count 2 -Quiet -ErrorAction SilentlyContinue
        if ($pingResult) {
            Write-OutputColor "Gateway is reachable." -color "Success"
        }
        else {
            Write-OutputColor "Gateway not reachable (this may be normal if VLAN not yet configured)." -color "Warning"
        }
    }
    catch {
        Write-OutputColor "Failed to apply IP configuration: $_" -color "Error"
    }
}

# Function to configure DNS on an adapter
function Set-VMDNSAddress {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$selectedAdapterName
    )

    # Helper function to set DNS from preset
    function Set-DNSFromPreset {
        param (
            [string]$AdapterName,
            [string]$PresetName,
            [string[]]$Servers
        )
        try {
            Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ServerAddresses $Servers -ErrorAction Stop
            Write-OutputColor "DNS servers set: $($Servers -join ', ')" -color "Success"
            Add-SessionChange -Category "Network" -Description "Set DNS on $AdapterName to $PresetName"

            # Add to undo stack
            Add-UndoAction -Category "Network" -Description "DNS change on $AdapterName" -UndoScript {
                param($Adapter)
                Set-DnsClientServerAddress -InterfaceAlias $Adapter -ResetServerAddresses
            }.GetNewClosure() -UndoParams @{ Adapter = $AdapterName }

            return $true
        }
        catch {
            Write-OutputColor "Failed to set DNS: $_" -color "Error"
            return $false
        }
    }

    # Get current DNS
    $currentDNS = Get-DnsClientServerAddress -InterfaceAlias $selectedAdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($currentDNS -and $currentDNS.ServerAddresses) {
        Write-OutputColor "Current DNS: $($currentDNS.ServerAddresses -join ', ')" -color "Info"
    }

    # Build dynamic preset list from $script:DNSPresets
    $presetList = @($script:DNSPresets.GetEnumerator() | Sort-Object Key)
    $presetCount = $presetList.Count

    Write-OutputColor "`nDNS Configuration Options:" -color "Info"
    for ($i = 0; $i -lt $presetCount; $i++) {
        $entry = $presetList[$i]
        Write-OutputColor "$($i + 1). $($entry.Key) ($($entry.Value -join ', '))" -color "Info"
    }
    $customNum = $presetCount + 1
    $dhcpNum = $presetCount + 2
    $cancelNum = $presetCount + 3
    Write-OutputColor "$customNum. Enter custom DNS servers" -color "Info"
    Write-OutputColor "$dhcpNum. Use DHCP for DNS" -color "Info"
    Write-OutputColor "$cancelNum. Cancel" -color "Info"
    $choice = Read-Host "  Select"

    # Check for navigation commands
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) {
        if (Invoke-NavigationAction -NavResult $navResult) { return }
    }

    $success = $false
    $choiceNum = 0
    if ([int]::TryParse($choice, [ref]$choiceNum)) {
        if ($choiceNum -ge 1 -and $choiceNum -le $presetCount) {
            # Preset selection
            $selected = $presetList[$choiceNum - 1]
            $success = Set-DNSFromPreset -AdapterName $selectedAdapterName -PresetName $selected.Key -Servers @($selected.Value)
        }
        elseif ($choiceNum -eq $customNum) {
            # Custom DNS entry
            Write-OutputColor "Enter primary DNS server:" -color "Info"
            $dns1 = Read-Host

            # Check for navigation
            $navResult = Test-NavigationCommand -UserInput $dns1
            if ($navResult.ShouldReturn) {
                if (Invoke-NavigationAction -NavResult $navResult) { return }
            }

            if ([string]::IsNullOrWhiteSpace($dns1) -or -not (Test-ValidIPAddress -IPAddress $dns1)) {
                Write-OutputColor "Invalid DNS server address. Must be in format: X.X.X.X (e.g., 8.8.8.8)" -color "Error"
                return
            }

            $dnsServers = @($dns1)

            if (Confirm-UserAction -Message "Add a secondary DNS server?") {
                Write-OutputColor "Enter secondary DNS server:" -color "Info"
                $dns2 = Read-Host

                if (-not [string]::IsNullOrWhiteSpace($dns2)) {
                    if (Test-ValidIPAddress -IPAddress $dns2) {
                        $dnsServers += $dns2
                    }
                    else {
                        Write-OutputColor "Invalid secondary DNS. Continuing with primary only." -color "Warning"
                    }
                }
            }

            $success = Set-DNSFromPreset -AdapterName $selectedAdapterName -PresetName "Custom ($($dnsServers -join ', '))" -Servers $dnsServers
        }
        elseif ($choiceNum -eq $dhcpNum) {
            # DHCP
            try {
                Set-DnsClientServerAddress -InterfaceAlias $selectedAdapterName -ResetServerAddresses -ErrorAction Stop
                Write-OutputColor "DNS set to use DHCP." -color "Success"
                Add-SessionChange -Category "Network" -Description "Set DNS on $selectedAdapterName to DHCP"
                $success = $true
            }
            catch {
                Write-OutputColor "Failed to reset DNS: $_" -color "Error"
            }
        }
        else {
            Write-OutputColor "DNS configuration cancelled." -color "Info"
            return
        }
    }
    else {
        Write-OutputColor "DNS configuration cancelled." -color "Info"
        return
    }

    # Show updated status after any successful DNS change
    if ($success) {
        Show-AdapterStatus -AdapterName $selectedAdapterName
    }
}

# Function to disable IPv6 on all adapters
function Disable-AllIPv6 {
    Clear-Host
    Write-CenteredOutput "Disable IPv6 on All Adapters" -color "Info"

    $adapters = Get-NetAdapter

    Write-OutputColor "`nThis will disable IPv6 on all network adapters." -color "Warning"
    Write-OutputColor "Adapters to be modified:" -color "Info"

    foreach ($adapter in $adapters) {
        $ipv6Binding = Get-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
        $status = if ($ipv6Binding.Enabled) { "IPv6 Enabled" } else { "IPv6 Disabled" }
        $color = if ($ipv6Binding.Enabled) { "Warning" } else { "Success" }
        Write-OutputColor "  - $($adapter.Name): $status" -color $color
    }

    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Disable IPv6 on all adapters?")) {
        Write-OutputColor "Operation cancelled." -color "Info"
        return
    }

    $successCount = 0
    $totalCount = @($adapters).Count

    foreach ($adapter in $adapters) {
        try {
            Disable-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
            $successCount++
            Write-OutputColor "Disabled IPv6 on $($adapter.Name)" -color "Success"
        }
        catch {
            Write-OutputColor "Failed to disable IPv6 on $($adapter.Name): $_" -color "Error"
        }
    }

    Write-OutputColor "`nIPv6 disabled on $successCount of $totalCount adapters." -color "Success"
    Add-SessionChange -Category "Network" -Description "Disabled IPv6 on $successCount adapters"
}

# Function to rename a network adapter
function Rename-NetworkAdapter {
    Clear-Host
    Write-CenteredOutput "Rename Network Adapter" -color "Info"

    # Get all adapters
    $adapters = Get-NetAdapter | Sort-Object Name

    if ($null -eq $adapters -or @($adapters).Count -eq 0) {
        Write-OutputColor "No network adapters found." -color "Error"
        return
    }

    Write-OutputColor "Available adapters:" -color "Info"
    Write-OutputColor "" -color "Info"

    $index = 1
    $adapterMap = @{}
    foreach ($adapter in $adapters) {
        $adapterMap[$index] = $adapter
        $status = if ($adapter.Status -eq "Up") { "[UP]" } else { "[DOWN]" }
        $statusColor = if ($adapter.Status -eq "Up") { "Success" } else { "Warning" }
        Write-OutputColor "  $index. $($adapter.Name) $status - $($adapter.InterfaceDescription)" -color $statusColor
        $index++
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Enter the number of the adapter to rename (or 'back' to cancel):" -color "Info"
    $selection = Read-Host

    # Check for navigation
    $navResult = Test-NavigationCommand -UserInput $selection
    if ($navResult.ShouldReturn) {
        return
    }

    if (-not ($selection -match '^\d+$') -or -not $adapterMap.ContainsKey([int]$selection)) {
        Write-OutputColor "Invalid selection." -color "Error"
        return
    }

    $selectedAdapter = $adapterMap[[int]$selection]
    $oldName = $selectedAdapter.Name

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Selected: $oldName" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "Enter new name for the adapter:" -color "Info"
    $newName = Read-Host

    # Check for navigation
    $navResult = Test-NavigationCommand -UserInput $newName
    if ($navResult.ShouldReturn) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($newName)) {
        Write-OutputColor "No name entered. Operation cancelled." -color "Warning"
        return
    }

    # Validate name (no special characters that would cause issues)
    if ($newName -match '[\\\/\:\*\?\"\<\>\|]') {
        Write-OutputColor "Invalid characters in name. Avoid: \ / : * ? `" < > |" -color "Error"
        return
    }

    # Check if name already exists
    $existingAdapter = Get-NetAdapter -Name $newName -ErrorAction SilentlyContinue
    if ($existingAdapter) {
        Write-OutputColor "An adapter with the name '$newName' already exists." -color "Error"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Rename '$oldName' to '$newName'?" -color "Warning"

    if (-not (Confirm-UserAction -Message "Proceed with rename?")) {
        Write-OutputColor "Operation cancelled." -color "Info"
        return
    }

    try {
        Rename-NetAdapter -Name $oldName -NewName $newName -ErrorAction Stop
        Write-OutputColor "Adapter renamed successfully: '$oldName' -> '$newName'" -color "Success"
        Add-SessionChange -Category "Network" -Description "Renamed adapter '$oldName' to '$newName'"

        # Add to undo stack
        Add-UndoAction -Category "Network" -Description "Rename adapter '$oldName' to '$newName'" -UndoScript {
            param($OldN, $NewN)
            Rename-NetAdapter -Name $NewN -NewName $OldN -ErrorAction Stop
        }.GetNewClosure() -UndoParams @{ OldN = $oldName; NewN = $newName }
    }
    catch {
        Write-OutputColor "Failed to rename adapter: $_" -color "Error"
    }
}
#endregion