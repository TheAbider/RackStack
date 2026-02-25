#region ===== SWITCH EMBEDDED TEAMING =====
# Function to test which adapters have internet connectivity
function Test-AdapterInternetConnectivity {
    param (
        [string]$Target = $script:DefaultConnectivityTarget
    )

    $results = @()

    # Get physical adapters that are UP and not virtual
    $adapters = Get-NetAdapter | Where-Object {
        $_.Status -eq "Up" -and
        $_.Name -notlike "vEthernet*" -and
        $_.InterfaceDescription -notlike "*Hyper-V*" -and
        $_.InterfaceDescription -notlike "*Virtual*"
    }

    foreach ($adapter in $adapters) {
        # Get IPv4 address for this adapter
        $ip = (Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress | Select-Object -First 1

        if ($ip) {
            # Test connectivity using this adapter's IP as source
            try {
                if ($PSVersionTable.PSVersion.Major -ge 6) {
                    # PowerShell 6+ supports -Source
                    $canPing = Test-Connection -Source $ip -ComputerName $Target -Count 1 -Quiet -ErrorAction Stop
                } else {
                    # PS 5.x: use ping.exe -S to bind to source adapter IP
                    $pingResult = ping.exe -S $ip $Target -n 1 -w 1000 2>$null
                    $canPing = ($LASTEXITCODE -eq 0)
                }
            }
            catch {
                $pingResult = ping.exe -S $ip $Target -n 1 -w 1000 2>$null
                $canPing = ($LASTEXITCODE -eq 0)
            }

            $results += @{
                Adapter = $adapter
                IPAddress = $ip
                HasInternet = $canPing
                Name = $adapter.Name
                Index = $adapter.InterfaceIndex
            }
        }
        else {
            $results += @{
                Adapter = $adapter
                IPAddress = $null
                HasInternet = $false
                Name = $adapter.Name
                Index = $adapter.InterfaceIndex
            }
        }
    }

    return $results
}

# Function to select physical adapters with auto-detection option
function Select-PhysicalAdaptersSmart {
    Clear-Host
    Write-CenteredOutput "Select Physical Adapters for SET" -color "Info"

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECTION MODE".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem -Text "[A]  Auto-detect (use NICs with internet connectivity) (Recommended)"
    Write-MenuItem -Text "[M]  Manual selection (choose specific adapters)"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"

    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return $null }

    if ($choice -match '^[Aa]$') {
        # Auto-detect mode
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Testing adapter internet connectivity..." -color "Info"

        $results = @(Test-AdapterInternetConnectivity)

        if ($results.Count -eq 0) {
            Write-OutputColor "No physical adapters found." -color "Error"
            return $null
        }

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  ADAPTER CONNECTIVITY RESULTS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        foreach ($result in $results) {
            $status = if ($result.HasInternet) { "[INTERNET]" } else { "[NO INTERNET]" }
            $color = if ($result.HasInternet) { "Success" } else { "Warning" }
            $ip = if ($result.IPAddress) { $result.IPAddress } else { "No IP" }
            $line = "  $($result.Name) | $ip | $status"
            Write-OutputColor "  │$($line.PadRight(72))│" -color $color
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        # Select adapters with internet
        $internetAdapters = @($results | Where-Object { $_.HasInternet })
        $noInternetAdapters = @($results | Where-Object { -not $_.HasInternet })

        if ($internetAdapters.Count -eq 0) {
            Write-OutputColor "No adapters with internet connectivity found." -color "Warning"
            Write-OutputColor "Please use manual selection or check network configuration." -color "Info"
            return $null
        }

        Write-OutputColor "Adapters with internet (will be used for SET):" -color "Success"
        foreach ($adapter in $internetAdapters) {
            Write-OutputColor "  - $($adapter.Name) ($($adapter.IPAddress))" -color "Success"
        }

        if ($noInternetAdapters.Count -gt 0) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "Adapters WITHOUT internet (candidates for iSCSI):" -color "Warning"
            foreach ($adapter in $noInternetAdapters) {
                Write-OutputColor "  - $($adapter.Name)" -color "Warning"
            }
            # Store for later iSCSI configuration
            $script:iSCSICandidateAdapters = $noInternetAdapters
        }

        Write-OutputColor "" -color "Info"
        if (-not (Confirm-UserAction -Message "Use adapters with internet for SET?")) {
            Write-OutputColor "Selection cancelled." -color "Info"
            return $null
        }

        # Return the actual adapter objects
        return $internetAdapters | ForEach-Object { $_.Adapter }
    }
    elseif ($choice -match '^[Mm]$') {
        # Manual mode - use existing function
        return Select-PhysicalAdapters
    }
    else {
        Write-OutputColor "Invalid selection." -color "Error"
        return $null
    }
}

# Function to configure Switch Embedded Teaming (SET)
function New-SwitchEmbeddedTeam {
    param (
        [string]$SwitchName = "LAN-SET",
        [string]$ManagementName = "Management"
    )

    Clear-Host
    Write-CenteredOutput "Switch Embedded Team Configuration" -color "Info"

    # SET requires Windows Server 2016 or later
    if (-not $script:IsServer2016OrLater) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Switch Embedded Teaming requires Windows Server 2016 or later." -color "Error"
        Write-OutputColor "  On Server 2012 R2, use NIC Teaming (LBFO) via Server Manager instead." -color "Warning"
        Write-OutputColor "" -color "Info"
        return
    }

    # SET requires Hyper-V to be installed
    if (-not (Test-HyperVInstalled)) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Hyper-V is required for Switch Embedded Teaming." -color "Warning"
        Write-OutputColor "  SET creates a Hyper-V virtual switch with NIC teaming built in." -color "Info"
        Write-OutputColor "" -color "Info"
        if (Confirm-UserAction -Message "Install Hyper-V now?") {
            Install-HyperVRole
            if (-not (Test-HyperVInstalled)) {
                Write-OutputColor "  Hyper-V requires a reboot before SET can be configured." -color "Warning"
                return
            }
        } else {
            return
        }
    }

    # Check for existing SET
    $existingSwitch = Get-VMSwitch -ErrorAction SilentlyContinue | Where-Object { $_.SwitchType -eq "External" } | Select-Object -First 1

    if ($existingSwitch) {
        Write-OutputColor "Existing external switch found: '$($existingSwitch.Name)'" -color "Warning"

        if ($existingSwitch.EmbeddedTeamingEnabled) {
            Write-OutputColor "This switch has embedded teaming enabled." -color "Info"
            $teamNics = (Get-VMSwitchTeam -Name $existingSwitch.Name -ErrorAction SilentlyContinue).NetAdapterInterfaceDescription
            if ($teamNics) {
                Write-OutputColor "Team members: $($teamNics -join ', ')" -color "Info"
            }
        }

        # Check for VMs connected to this switch
        $connectedVMs = @(Get-VM -ErrorAction SilentlyContinue | Where-Object {
            $_ | Get-VMNetworkAdapter -ErrorAction SilentlyContinue | Where-Object { $_.SwitchName -eq $existingSwitch.Name }
        })
        if ($connectedVMs.Count -gt 0) {
            Write-OutputColor "WARNING: $($connectedVMs.Count) VM(s) are connected to this switch:" -color "Warning"
            foreach ($vm in $connectedVMs) {
                Write-OutputColor "  - $($vm.Name) ($($vm.State))" -color "Warning"
            }
        }

        if (-not (Confirm-UserAction -Message "`nRemove existing switch and create new SET?")) {
            Write-OutputColor "Keeping existing configuration." -color "Info"
            return
        }

        Write-OutputColor "Removing existing switch..." -color "Warning"
        Remove-VMSwitch -Name $existingSwitch.Name -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    Write-OutputColor "`nSelect physical adapters for the Switch Embedded Team:" -color "Info"
    Write-OutputColor "Note: Select at least 2 adapters for redundancy" -color "Warning"
    Write-OutputColor "" -color "Info"

    # Use smart selection with auto-detect option
    $selectedAdapters = Select-PhysicalAdaptersSmart

    if ($null -eq $selectedAdapters -or @($selectedAdapters).Count -eq 0) {
        Write-OutputColor "No adapters selected. Aborting SET creation." -color "Error"
        return
    }

    $adapterCount = @($selectedAdapters).Count

    if ($adapterCount -eq 1) {
        Write-OutputColor "`nWarning: Only 1 adapter selected. No redundancy!" -color "Critical"
        if (-not (Confirm-UserAction -Message "Continue with single adapter?")) {
            Write-OutputColor "SET creation cancelled." -color "Info"
            return
        }
    }

    Write-OutputColor "`nSelected adapters:" -color "Info"
    foreach ($adapter in $selectedAdapters) {
        Write-OutputColor "  - $($adapter.Name) ($($adapter.InterfaceDescription)) [$($adapter.Status)]" -color "Success"
    }

    if (-not (Confirm-UserAction -Message "`nCreate Switch Embedded Team with these adapters?")) {
        Write-OutputColor "SET creation cancelled." -color "Info"
        return
    }

    try {
        Write-OutputColor "Creating VM Switch '$SwitchName'..." -color "Info"
        $adapterNames = $selectedAdapters.Name
        New-VMSwitch -Name $SwitchName -NetAdapterName $adapterNames -EnableEmbeddedTeaming $true -AllowManagementOS $true -ErrorAction Stop

        Write-OutputColor "Setting load balancing algorithm to Dynamic..." -color "Info"
        Set-VMSwitchTeam -Name $SwitchName -LoadBalancingAlgorithm Dynamic -ErrorAction SilentlyContinue

        Write-OutputColor "Waiting for management adapter to appear..." -color "Info"
        $vnicReady = $false
        for ($wait = 0; $wait -lt 15; $wait++) {
            $vnic = Get-VMNetworkAdapter -ManagementOS -Name $SwitchName -ErrorAction SilentlyContinue
            if ($vnic) { $vnicReady = $true; break }
            Start-Sleep -Seconds 1
        }

        if ($vnicReady) {
            Write-OutputColor "Renaming management adapter to '$ManagementName'..." -color "Info"
            Rename-VMNetworkAdapter -ManagementOS -Name $SwitchName -NewName $ManagementName -ErrorAction SilentlyContinue
        } else {
            Write-OutputColor "Management adapter not yet available. You may need to rename it manually." -color "Warning"
        }

        Write-OutputColor "`nSwitch Embedded Team created successfully!" -color "Success"
        Write-OutputColor "Switch Name: $SwitchName" -color "Info"
        Write-OutputColor "Management NIC: vEthernet ($ManagementName)" -color "Info"
        Add-SessionChange -Category "Network" -Description "Created SET '$SwitchName' with $adapterCount adapters"

        # Check if there are iSCSI candidate adapters from auto-detection
        if ($script:iSCSICandidateAdapters -and $script:iSCSICandidateAdapters.Count -gt 0) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  iSCSI CONFIGURATION AVAILABLE".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  The following adapters were not used for SET (no internet):".PadRight(72))│" -color "Info"
            foreach ($candidate in $script:iSCSICandidateAdapters) {
                Write-OutputColor "  │$("    - $($candidate.Name)".PadRight(72))│" -color "Warning"
            }
            Write-OutputColor "  │$("  These may be your iSCSI adapters for SAN connectivity.".PadRight(72))│" -color "Info"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            Write-OutputColor "" -color "Info"

            if (Confirm-UserAction -Message "Configure iSCSI on these adapters now?") {
                Set-iSCSIConfiguration
            }
        }
    }
    catch {
        Write-OutputColor "Failed to create Switch Embedded Team: $_" -color "Error"
        Write-OutputColor "Tip: Make sure Hyper-V is installed and adapters are not in use." -color "Warning"
    }
}

# Function to add a custom virtual NIC to an existing External or SET switch
function Add-CustomVNIC {
    param (
        [string]$PresetName = ""
    )

    Clear-Host
    Write-CenteredOutput "Add Virtual NIC to Switch" -color "Info"

    # Find existing External switches (SET or standard)
    $externalSwitches = @(Get-VMSwitch -ErrorAction SilentlyContinue | Where-Object { $_.SwitchType -eq "External" })

    if ($externalSwitches.Count -eq 0) {
        Write-OutputColor "No external virtual switch found." -color "Error"
        Write-OutputColor "Please create a virtual switch first (SET or External)." -color "Warning"
        return
    }

    # If multiple external switches, let user pick
    if ($externalSwitches.Count -eq 1) {
        $existingSwitch = $externalSwitches[0]
    } else {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Multiple external switches found:" -color "Info"
        $swIdx = 1
        foreach ($sw in $externalSwitches) {
            $typeLabel = if ($sw.EmbeddedTeamingEnabled) { "SET" } else { "External" }
            Write-OutputColor "  [$swIdx]  $($sw.Name) ($typeLabel)" -color "Info"
            $swIdx++
        }
        Write-OutputColor "" -color "Info"
        $swChoice = Read-Host "  Select switch"
        if ($swChoice -match '^\d+$' -and [int]$swChoice -ge 1 -and [int]$swChoice -le $externalSwitches.Count) {
            $existingSwitch = $externalSwitches[[int]$swChoice - 1]
        } else {
            Write-OutputColor "  Invalid selection." -color "Error"
            return
        }
    }

    $typeLabel = if ($existingSwitch.EmbeddedTeamingEnabled) { "SET" } else { "External" }
    Write-OutputColor "Using switch: $($existingSwitch.Name) ($typeLabel)" -color "Success"

    # Show existing management adapters
    $existingAdapters = Get-VMNetworkAdapter -ManagementOS -SwitchName $existingSwitch.Name -ErrorAction SilentlyContinue
    if ($existingAdapters) {
        Write-OutputColor "`nExisting virtual NICs on SET:" -color "Info"
        foreach ($adapter in $existingAdapters) {
            $vlanInfo = Get-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $adapter.Name -ErrorAction SilentlyContinue
            $vlanStr = if ($null -ne $vlanInfo -and $vlanInfo.AccessVlanId -gt 0) { " (VLAN $($vlanInfo.AccessVlanId))" } else { "" }
            Write-OutputColor "  - $($adapter.Name)$vlanStr" -color "Info"
        }
    }

    # Determine vNIC name
    $vnicName = $PresetName
    if (-not $vnicName) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  SELECT VNIC TYPE".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  Backup         — backup/replication traffic"
        Write-MenuItem "[2]  Cluster        — cluster heartbeat"
        Write-MenuItem "[3]  Live Migration — VM live migration"
        Write-MenuItem "[4]  Storage        — storage traffic"
        Write-MenuItem "[5]  Custom...      — enter any name"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" { $vnicName = "Backup" }
            "2" { $vnicName = "Cluster" }
            "3" { $vnicName = "Live Migration" }
            "4" { $vnicName = "Storage" }
            "5" {
                Write-OutputColor "  Enter vNIC name:" -color "Info"
                $vnicName = Read-Host "  "
                if ([string]::IsNullOrWhiteSpace($vnicName)) {
                    Write-OutputColor "  Name cannot be empty." -color "Error"
                    return
                }
            }
            default {
                Write-OutputColor "  Invalid selection." -color "Error"
                return
            }
        }
    }

    # Check if vNIC with that name already exists
    $vnicExists = $existingAdapters | Where-Object { $_.Name -eq $vnicName }
    if ($vnicExists) {
        Write-OutputColor "`nVirtual NIC '$vnicName' already exists on this SET." -color "Warning"
        if (-not (Confirm-UserAction -Message "Remove and recreate it?")) {
            return
        }

        Write-OutputColor "Removing existing vNIC '$vnicName'..." -color "Info"
        Remove-VMNetworkAdapter -ManagementOS -Name $vnicName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        # Verify removal succeeded
        $stillExists = Get-VMNetworkAdapter -ManagementOS -Name $vnicName -ErrorAction SilentlyContinue
        if ($stillExists) {
            Write-OutputColor "Could not remove existing vNIC '$vnicName' (may be in use). Aborting." -color "Error"
            return
        }
    }

    # Create the vNIC
    try {
        Write-OutputColor "`nCreating virtual NIC '$vnicName'..." -color "Info"
        Add-VMNetworkAdapter -ManagementOS -SwitchName $existingSwitch.Name -Name $vnicName -ErrorAction Stop
        Write-OutputColor "  vNIC created: vEthernet ($vnicName)" -color "Success"
    }
    catch {
        Write-OutputColor "Failed to create virtual NIC: $_" -color "Error"
        return
    }

    # Optional: Configure VLAN
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Set a VLAN ID? (Enter to skip, or 1-4094):" -color "Info"
    $vlanInput = Read-Host "  "
    if ($vlanInput -match '^\d+$') {
        $vlanId = [int]$vlanInput
        if ($vlanId -ge 1 -and $vlanId -le 4094) {
            try {
                Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $vnicName -Access -VlanId $vlanId -ErrorAction Stop
                Write-OutputColor "  VLAN $vlanId set on '$vnicName'." -color "Success"
            }
            catch {
                Write-OutputColor "  Failed to set VLAN: $_" -color "Warning"
            }
        }
        else {
            Write-OutputColor "  Invalid VLAN ID (must be 1-4094). Skipping." -color "Warning"
        }
    }

    # Optional: Configure IP
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Configure IP address now? (Y/N, default N):" -color "Info"
    $ipChoice = Read-Host "  "
    if ($ipChoice -match '^[Yy]') {
        $ipResult = Get-IPAddressAndSubnet -Prompt "Enter IP address (e.g., 10.0.100.1/24)"
        if ($null -ne $ipResult) {
            $ipAddress = $ipResult[0]
            $cidr = $ipResult[1]
            $adapterAlias = "vEthernet ($vnicName)"
            try {
                Remove-NetIPAddress -InterfaceAlias $adapterAlias -Confirm:$false -ErrorAction SilentlyContinue
                Remove-NetRoute -InterfaceAlias $adapterAlias -Confirm:$false -ErrorAction SilentlyContinue
                New-NetIPAddress -InterfaceAlias $adapterAlias -IPAddress $ipAddress -PrefixLength $cidr -ErrorAction Stop
                Write-OutputColor "  IP $ipAddress/$cidr set on '$vnicName'." -color "Success"
            }
            catch {
                Write-OutputColor "  Failed to set IP: $_" -color "Warning"
            }
        }
    }

    $vlanMsg = if ($vlanInput -match '^\d+$' -and [int]$vlanInput -ge 1 -and [int]$vlanInput -le 4094) { " VLAN $vlanInput" } else { "" }
    Add-SessionChange -Category "Network" -Description "Added vNIC '$vnicName'$vlanMsg to SET '$($existingSwitch.Name)'"

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Virtual NIC '$vnicName' created successfully!" -color "Success"
}

# Function to add multiple vNICs in one session
function Add-MultipleVNICs {
    $createdVNICs = @()

    while ($true) {
        Add-CustomVNIC

        # Check what was just created (by looking at session changes)
        $lastChange = $script:SessionChanges | Select-Object -Last 1
        if ($null -ne $lastChange -and $lastChange.Description -match "Added vNIC '([^']+)'") {
            $regexMatches = $matches
            $createdVNICs += $regexMatches[1]
        }

        Write-OutputColor "" -color "Info"
        if (-not (Confirm-UserAction -Message "Add another virtual NIC?")) {
            break
        }
    }

    if ($createdVNICs.Count -gt 0) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  SUMMARY: Created $($createdVNICs.Count) virtual NIC(s)".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        foreach ($name in $createdVNICs) {
            Write-OutputColor "  │$("  - $name".PadRight(72))│" -color "Success"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }
}

# Function to add a backup NIC to an existing SET (backward-compatible wrapper)
function Add-BackupNIC {
    param (
        [string]$BackupName = "Backup"
    )

    Add-CustomVNIC -PresetName $BackupName
}

# Function to create a standard (non-SET) virtual switch
function New-StandardVSwitch {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet("External", "Internal", "Private")]
        [string]$SwitchType,
        [string]$SwitchName = "",
        [string]$AdapterName = ""
    )

    Clear-Host
    Write-CenteredOutput "Create $SwitchType Virtual Switch" -color "Info"

    # Hyper-V required for all switch types
    if (-not (Test-HyperVInstalled)) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Hyper-V is required for virtual switches." -color "Warning"
        Write-OutputColor "" -color "Info"
        if (Confirm-UserAction -Message "Install Hyper-V now?") {
            Install-HyperVRole
            if (-not (Test-HyperVInstalled)) {
                Write-OutputColor "  Hyper-V requires a reboot before switches can be created." -color "Warning"
                return
            }
        } else {
            return
        }
    }

    # Get switch name
    if (-not $SwitchName) {
        $defaultName = switch ($SwitchType) {
            "External"  { "LAN" }
            "Internal"  { "InternalSwitch" }
            "Private"   { "PrivateSwitch" }
        }
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Enter switch name (default: $defaultName):" -color "Info"
        $userInput = Read-Host "  "
        $SwitchName = if ([string]::IsNullOrWhiteSpace($userInput)) { $defaultName } else { $userInput }
    }

    # Check for existing switch with same name
    $existing = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-OutputColor "  A switch named '$SwitchName' already exists." -color "Warning"
        if (-not (Confirm-UserAction -Message "Remove it and create a new one?")) {
            return
        }
        Remove-VMSwitch -Name $SwitchName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    try {
        switch ($SwitchType) {
            "External" {
                # Need a physical adapter
                if (-not $AdapterName) {
                    Write-OutputColor "" -color "Info"
                    Write-OutputColor "  Select a physical adapter for the External switch:" -color "Info"
                    Write-OutputColor "" -color "Info"

                    $adapters = @(Get-NetAdapter | Where-Object {
                        $_.Status -eq "Up" -and
                        $_.Name -notlike "vEthernet*" -and
                        $_.InterfaceDescription -notlike "*Hyper-V*" -and
                        $_.InterfaceDescription -notlike "*Virtual*"
                    })

                    if ($adapters.Count -eq 0) {
                        Write-OutputColor "  No physical adapters available." -color "Error"
                        return
                    }

                    $idx = 1
                    foreach ($adapter in $adapters) {
                        $ip = (Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress | Select-Object -First 1
                        $ipStr = if ($ip) { $ip } else { "No IP" }
                        Write-OutputColor "  [$idx]  $($adapter.Name) - $($adapter.InterfaceDescription) ($ipStr)" -color "Info"
                        $idx++
                    }
                    Write-OutputColor "" -color "Info"

                    $adChoice = Read-Host "  Select adapter"
                    if ($adChoice -match '^\d+$' -and [int]$adChoice -ge 1 -and [int]$adChoice -le $adapters.Count) {
                        $AdapterName = $adapters[[int]$adChoice - 1].Name
                    } else {
                        Write-OutputColor "  Invalid selection." -color "Error"
                        return
                    }
                }

                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Creating External switch '$SwitchName' on '$AdapterName'..." -color "Info"
                New-VMSwitch -Name $SwitchName -NetAdapterName $AdapterName -AllowManagementOS $true -ErrorAction Stop

                # Rename management adapter
                $vnicReady = $false
                for ($wait = 0; $wait -lt 15; $wait++) {
                    $vnic = Get-VMNetworkAdapter -ManagementOS -Name $SwitchName -ErrorAction SilentlyContinue
                    if ($vnic) { $vnicReady = $true; break }
                    Start-Sleep -Seconds 1
                }
                if ($vnicReady) {
                    Rename-VMNetworkAdapter -ManagementOS -Name $SwitchName -NewName "Management" -ErrorAction SilentlyContinue
                }

                Write-OutputColor "  External switch '$SwitchName' created!" -color "Success"
                Add-SessionChange -Category "Network" -Description "Created External switch '$SwitchName' on $AdapterName"
            }
            "Internal" {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Creating Internal switch '$SwitchName'..." -color "Info"
                New-VMSwitch -Name $SwitchName -SwitchType Internal -ErrorAction Stop
                Write-OutputColor "  Internal switch '$SwitchName' created!" -color "Success"
                Write-OutputColor "  Note: Host gets a vEthernet adapter. No physical NIC used." -color "Info"
                Add-SessionChange -Category "Network" -Description "Created Internal switch '$SwitchName'"
            }
            "Private" {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Creating Private switch '$SwitchName'..." -color "Info"
                New-VMSwitch -Name $SwitchName -SwitchType Private -ErrorAction Stop
                Write-OutputColor "  Private switch '$SwitchName' created!" -color "Success"
                Write-OutputColor "  Note: VMs can only communicate with each other. No host access." -color "Info"
                Add-SessionChange -Category "Network" -Description "Created Private switch '$SwitchName'"
            }
        }
    }
    catch {
        Write-OutputColor "  Failed to create switch: $_" -color "Error"
    }
}

# Function to show all virtual switches with details
function Show-VirtualSwitches {
    Clear-Host
    Write-CenteredOutput "Virtual Switches" -color "Info"

    $switches = @(Get-VMSwitch -ErrorAction SilentlyContinue)

    if ($switches.Count -eq 0) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  No virtual switches found." -color "Warning"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  VIRTUAL SWITCHES ($($switches.Count))".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    foreach ($sw in $switches) {
        $typeLabel = $sw.SwitchType.ToString()
        if ($sw.SwitchType -eq "External" -and $sw.EmbeddedTeamingEnabled) {
            $typeLabel = "SET"
            $teamNics = @((Get-VMSwitchTeam -Name $sw.Name -ErrorAction SilentlyContinue).NetAdapterInterfaceDescription)
            if ($teamNics) { $typeLabel += " ($($teamNics.Count) NICs)" }
        }
        elseif ($sw.SwitchType -eq "External") {
            $adapter = (Get-VMSwitchTeam -Name $sw.Name -ErrorAction SilentlyContinue).NetAdapterInterfaceDescription
            if (-not $adapter) {
                $adapter = $sw.NetAdapterInterfaceDescription
            }
            if ($adapter) { $typeLabel += " ($adapter)" }
        }

        $color = switch ($sw.SwitchType.ToString()) {
            "External" { "Success" }
            "Internal" { "Info" }
            "Private"  { "Warning" }
            default    { "Info" }
        }

        Write-OutputColor "  │$("  $($sw.Name)".PadRight(40))$($typeLabel.PadRight(32))│" -color $color

        # Show management adapters on this switch
        $mgmtAdapters = Get-VMNetworkAdapter -ManagementOS -SwitchName $sw.Name -ErrorAction SilentlyContinue
        if ($mgmtAdapters) {
            foreach ($adapter in $mgmtAdapters) {
                $vlanInfo = Get-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $adapter.Name -ErrorAction SilentlyContinue
                $vlanStr = if ($null -ne $vlanInfo -and $vlanInfo.AccessVlanId -gt 0) { " VLAN $($vlanInfo.AccessVlanId)" } else { "" }
                Write-OutputColor "  │$("    └ vEthernet ($($adapter.Name))$vlanStr".PadRight(72))│" -color "Info"
            }
        }
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

# Function to remove a virtual switch with safety checks
function Remove-VirtualSwitch {
    Clear-Host
    Write-CenteredOutput "Remove Virtual Switch" -color "Info"

    $switches = @(Get-VMSwitch -ErrorAction SilentlyContinue)

    if ($switches.Count -eq 0) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  No virtual switches found." -color "Warning"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Select a switch to remove:" -color "Info"
    Write-OutputColor "" -color "Info"

    $idx = 1
    foreach ($sw in $switches) {
        $typeLabel = $sw.SwitchType.ToString()
        if ($sw.SwitchType -eq "External" -and $sw.EmbeddedTeamingEnabled) { $typeLabel = "SET" }
        Write-OutputColor "  [$idx]  $($sw.Name) ($typeLabel)" -color "Info"
        $idx++
    }
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"

    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    if (-not ($choice -match '^\d+$') -or [int]$choice -lt 1 -or [int]$choice -gt $switches.Count) {
        Write-OutputColor "  Invalid selection." -color "Error"
        return
    }

    $targetSwitch = $switches[[int]$choice - 1]

    # Safety check: any VMs connected to this switch?
    $connectedVMs = Get-VMNetworkAdapter -All -ErrorAction SilentlyContinue | Where-Object { $_.SwitchName -eq $targetSwitch.Name -and -not $_.IsManagementOs }
    if ($connectedVMs) {
        $vmNames = ($connectedVMs | Select-Object -ExpandProperty VMName -Unique) -join ", "
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  WARNING: These VMs are connected to '$($targetSwitch.Name)':" -color "Critical"
        Write-OutputColor "  $vmNames" -color "Warning"
        Write-OutputColor "  Removing this switch will disconnect their network adapters." -color "Warning"
        Write-OutputColor "" -color "Info"
    }

    if (-not (Confirm-UserAction -Message "Remove switch '$($targetSwitch.Name)'? This cannot be undone.")) {
        Write-OutputColor "  Cancelled." -color "Info"
        return
    }

    try {
        Remove-VMSwitch -Name $targetSwitch.Name -Force -ErrorAction Stop
        Write-OutputColor "  Switch '$($targetSwitch.Name)' removed." -color "Success"
        Add-SessionChange -Category "Network" -Description "Removed virtual switch '$($targetSwitch.Name)'"
    }
    catch {
        Write-OutputColor "  Failed to remove switch: $_" -color "Error"
    }
}
#endregion