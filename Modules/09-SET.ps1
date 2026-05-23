#region ===== SWITCH EMBEDDED TEAMING =====
# Function to test which adapters have internet connectivity
function Test-AdapterInternetConnectivity {
    param (
        [string]$Target = $script:DefaultConnectivityTarget
    )

    $results = @()

    # Get physical adapters that are UP and not virtual
    $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
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
        Write-OutputColor "  Testing adapter internet connectivity..." -color "Info"

        $results = @(Test-AdapterInternetConnectivity)

        if ($results.Count -eq 0) {
            Write-OutputColor "  No physical adapters found." -color "Error"
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
            if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($line.PadRight(72))│" -color $color
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        # Select adapters with internet
        $internetAdapters = @($results | Where-Object { $_.HasInternet })
        $noInternetAdapters = @($results | Where-Object { -not $_.HasInternet })

        if ($internetAdapters.Count -eq 0) {
            Write-OutputColor "  No adapters with internet connectivity found." -color "Warning"
            Write-OutputColor "  Please use manual selection or check network configuration." -color "Info"
            return $null
        }

        Write-OutputColor "  Adapters with internet (will be used for SET):" -color "Success"
        foreach ($adapter in $internetAdapters) {
            Write-OutputColor "  - $($adapter.Name) ($($adapter.IPAddress))" -color "Success"
        }

        if ($noInternetAdapters.Count -gt 0) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Adapters WITHOUT internet (candidates for iSCSI):" -color "Warning"
            foreach ($adapter in $noInternetAdapters) {
                Write-OutputColor "  - $($adapter.Name)" -color "Warning"
            }
            # Store for later iSCSI configuration
            $script:iSCSICandidateAdapters = $noInternetAdapters
        }

        Write-OutputColor "" -color "Info"
        if (-not (Confirm-UserAction -Message "Use adapters with internet for SET?")) {
            Write-OutputColor "  Selection cancelled." -color "Info"
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
        Write-OutputColor "  Invalid selection. Enter A, M, or B." -color "Error"
        return $null
    }
}

# Function to verify SET team health after creation
function Test-SetTeamHealth {
    param([string]$SwitchName)

    $team = Get-VMSwitchTeam -Name $SwitchName -ErrorAction SilentlyContinue
    if ($null -eq $team) {
        Write-OutputColor "  WARNING: Could not verify SET team health" -color "Warning"
        return $false
    }

    $members = @($team.NetAdapterInterfaceDescription)
    $allHealthy = $true
    foreach ($member in $members) {
        $adapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -eq $member }
        if ($null -eq $adapter -or $adapter.Status -ne 'Up') {
            Write-OutputColor "  WARNING: Team member '$member' is not Up" -color "Warning"
            $allHealthy = $false
        }
    }

    if ($allHealthy) {
        Write-OutputColor "  SET team '$SwitchName': All $($members.Count) members healthy" -color "Success"
    }
    return $allHealthy
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
        Write-OutputColor "  Existing external switch found: '$($existingSwitch.Name)'" -color "Warning"

        if ($existingSwitch.EmbeddedTeamingEnabled) {
            Write-OutputColor "  This switch has embedded teaming enabled." -color "Info"
            $teamNics = (Get-VMSwitchTeam -Name $existingSwitch.Name -ErrorAction SilentlyContinue).NetAdapterInterfaceDescription
            if ($teamNics) {
                Write-OutputColor "  Team members: $($teamNics -join ', ')" -color "Info"
            }
        }

        # Check for VMs connected to this switch
        $connectedVMs = @(Get-VM -ErrorAction SilentlyContinue | Where-Object {
            $_ | Get-VMNetworkAdapter -ErrorAction SilentlyContinue | Where-Object { $_.SwitchName -eq $existingSwitch.Name }
        })
        if ($connectedVMs.Count -gt 0) {
            Write-OutputColor "  WARNING: $($connectedVMs.Count) VM(s) are connected to this switch:" -color "Warning"
            foreach ($vm in $connectedVMs) {
                Write-OutputColor "  - $($vm.Name) ($($vm.State))" -color "Warning"
            }
        }

        if (-not (Confirm-UserAction -Message "`nRemove existing switch and create new SET?")) {
            Write-OutputColor "  Keeping existing configuration." -color "Info"
            return
        }

        Write-OutputColor "  Removing existing switch..." -color "Warning"
        Remove-VMSwitch -Name $existingSwitch.Name -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    # Clear stale iSCSI candidate adapters from previous runs
    $script:iSCSICandidateAdapters = @()

    Write-OutputColor "`nSelect physical adapters for the Switch Embedded Team:" -color "Info"
    Write-OutputColor "  Note: Select at least 2 adapters for redundancy" -color "Warning"
    Write-OutputColor "" -color "Info"

    # Use smart selection with auto-detect option
    $selectedAdapters = Select-PhysicalAdaptersSmart

    if ($null -eq $selectedAdapters -or @($selectedAdapters).Count -eq 0) {
        Write-OutputColor "  No adapters selected. Aborting SET creation." -color "Error"
        return
    }

    $adapterCount = @($selectedAdapters).Count

    if ($adapterCount -eq 1) {
        Write-OutputColor "`nWarning: Only 1 adapter selected. No redundancy!" -color "Critical"
        if (-not (Confirm-UserAction -Message "Continue with single adapter?")) {
            Write-OutputColor "  SET creation cancelled." -color "Info"
            return
        }
    }

    Write-OutputColor "`nSelected adapters:" -color "Info"
    foreach ($adapter in $selectedAdapters) {
        Write-OutputColor "  - $($adapter.Name) ($($adapter.InterfaceDescription)) [$($adapter.Status)] - $($adapter.LinkSpeed)" -color "Success"
    }

    # Check for link speed mismatch
    if ($adapterCount -gt 1) {
        $speeds = @($selectedAdapters | ForEach-Object { $_.LinkSpeed })
        $uniqueSpeeds = @($speeds | Select-Object -Unique)
        if ($uniqueSpeeds.Count -gt 1) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Warning: Selected adapters have mismatched link speeds!" -color "Critical"
            foreach ($adapter in $selectedAdapters) {
                Write-OutputColor "  - $($adapter.Name): $($adapter.LinkSpeed)" -color "Warning"
            }
            Write-OutputColor "  SET performance will be limited to the slowest adapter." -color "Warning"
        }
    }

    # Check if any selected adapters are already bound to a VM switch
    $existingSwitches = @(Get-VMSwitch -ErrorAction SilentlyContinue)
    foreach ($adapter in $selectedAdapters) {
        $boundSwitch = $existingSwitches | Where-Object {
            $_.NetAdapterInterfaceDescriptions -contains $adapter.InterfaceDescription
        }
        if ($null -ne $boundSwitch) {
            Write-OutputColor "  '$($adapter.Name)' is already bound to VM switch '$($boundSwitch.Name)'." -color "Error"
            Write-OutputColor "  Remove it from the existing switch first." -color "Warning"
            return
        }
    }

    # Warn if any selected adapter currently owns the default route — creating the SET will
    # briefly rebind the physical adapter into the vSwitch and (despite -AllowManagementOS)
    # the IP migration commonly fails, leaving the box reachable only via console / iLO.
    try {
        $defaultRouteIfs = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | ForEach-Object { $_.InterfaceAlias })
        $atRiskAdapters = @($selectedAdapters | Where-Object { $_.Name -in $defaultRouteIfs })
        if ($atRiskAdapters.Count -gt 0) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  WARNING: $(($atRiskAdapters | ForEach-Object { $_.Name }) -join ', ') owns the default route." -color "Warning"
            Write-OutputColor "  Creating SET will briefly disconnect remote sessions on that adapter." -color "Warning"
            Write-OutputColor "  Confirm you have console / iLO / out-of-band access before continuing." -color "Warning"
            if (-not (Confirm-UserAction -Message "Proceed with SET creation on the default-route adapter?")) {
                Write-OutputColor "  SET creation cancelled." -color "Info"
                return
            }
        }
    } catch { }

    if (-not (Confirm-UserAction -Message "`nCreate Switch Embedded Team with these adapters?")) {
        Write-OutputColor "  SET creation cancelled." -color "Info"
        return
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        $capName     = $SwitchName
        $capAdapters = @($selectedAdapters.Name)
        Push-DryRunStep -Label "Create SET vSwitch '$capName' on $($capAdapters -join ', ')" -Category "Network" -OneWay $false `
            -Params @{ SwitchName = $capName; Adapters = $capAdapters } `
            -Preflight {
                if (Get-VMSwitch -Name $capName -ErrorAction SilentlyContinue) { "Switch '$capName' already exists" }
                else { $true }
            }.GetNewClosure() `
            -Apply {
                New-VMSwitch -Name $capName -NetAdapterName $capAdapters -EnableEmbeddedTeaming $true -AllowManagementOS $true -ErrorAction Stop | Out-Null
                Set-VMSwitchTeam -Name $capName -LoadBalancingAlgorithm Dynamic -ErrorAction SilentlyContinue
            }.GetNewClosure() `
            -Undo {
                Remove-VMSwitch -Name $capName -Force -ErrorAction SilentlyContinue
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): create SET vSwitch '$capName'." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued SET vSwitch '$capName' creation"
        return
    }

    try {
        Write-OutputColor "  Creating VM Switch '$SwitchName'..." -color "Info"
        $adapterNames = $selectedAdapters.Name
        New-VMSwitch -Name $SwitchName -NetAdapterName $adapterNames -EnableEmbeddedTeaming $true -AllowManagementOS $true -ErrorAction Stop

        Write-OutputColor "  Setting load balancing algorithm to Dynamic..." -color "Info"
        Set-VMSwitchTeam -Name $SwitchName -LoadBalancingAlgorithm Dynamic -ErrorAction SilentlyContinue

        Write-OutputColor "  Waiting for management adapter to appear..." -color "Info"
        # Extend the wait window — VMM provider warm-up can take 60-90s on cold hosts. The
        # prior 6-attempt exponential cap topped out around ~31s and frequently logged
        # "may need to rename manually" on perfectly fine hosts where the vNIC just hadn't
        # bound yet.
        $vnicReady = $false
        $vnicDeadline = (Get-Date).AddSeconds(90)
        while ((Get-Date) -lt $vnicDeadline) {
            $vnic = Get-VMNetworkAdapter -ManagementOS -SwitchName $SwitchName -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $vnic) { $vnicReady = $true; break }
            Start-Sleep -Seconds 2
        }

        if ($vnicReady) {
            # Use $script:ManagementName (defaults.json override-able) rather than the
            # function param default of "Management" — operators who set defaults.json
            # ManagementName were having it silently ignored by this SET branch even
            # though the External-switch branch already used $script:ManagementName.
            $resolvedMgmtName = if ($script:ManagementName) { $script:ManagementName } else { $ManagementName }
            Write-OutputColor "  Renaming management adapter to '$resolvedMgmtName'..." -color "Info"
            try {
                Rename-VMNetworkAdapter -ManagementOS -Name $SwitchName -NewName $resolvedMgmtName -ErrorAction Stop
            } catch {
                Write-OutputColor "  Rename failed: $($_.Exception.Message). Adapter still has its default name '$SwitchName' — rename manually if needed." -color "Warning"
            }
        } else {
            Write-OutputColor "  Management adapter not yet available after 90s. You may need to rename it manually." -color "Warning"
        }

        # Verify SET team health
        Test-SetTeamHealth -SwitchName $SwitchName

        Write-OutputColor "`nSwitch Embedded Team created successfully!" -color "Success"
        Write-OutputColor "  Switch Name: $SwitchName" -color "Info"
        Write-OutputColor "  Management NIC: vEthernet ($ManagementName)" -color "Info"
        Add-SessionChange -Category "Network" -Description "Created SET '$SwitchName' with $adapterCount adapters"
        Clear-MenuCache

        # Check if there are iSCSI candidate adapters from auto-detection
        if ($script:iSCSICandidateAdapters -and $script:iSCSICandidateAdapters.Count -gt 0) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  iSCSI CONFIGURATION AVAILABLE".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  The following adapters were not used for SET (no internet):".PadRight(72))│" -color "Info"
            foreach ($candidate in $script:iSCSICandidateAdapters) {
                $lineStr = "    - $($candidate.Name)"
                if ($lineStr.Length -gt 72) { $lineStr = $lineStr.Substring(0, 69) + "..." }
                Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Warning"
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
        Write-RackStackError -Code "RS-2005" -Detail "$_"
        Write-OutputColor "  Attempting to clean up partially created switch..." -color "Warning"
        Remove-VMSwitch -Name $SwitchName -Force -ErrorAction SilentlyContinue
        Write-OutputColor "  SET creation failed. Partially created switch has been cleaned up." -color "Error"
        Write-OutputColor "  Tip: Make sure Hyper-V is installed and adapters are not in use." -color "Warning"
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
        Write-OutputColor "  No external virtual switch found." -color "Error"
        Write-OutputColor "  Please create a virtual switch first (SET or External)." -color "Warning"
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
        $navResult = Test-NavigationCommand -UserInput $swChoice
        if ($navResult.ShouldReturn) { return }
        if ($swChoice -match '^\d+$' -and [int]$swChoice -ge 1 -and [int]$swChoice -le $externalSwitches.Count) {
            $existingSwitch = $externalSwitches[[int]$swChoice - 1]
        } else {
            Write-OutputColor "  Invalid selection. Enter 1-$($externalSwitches.Count)." -color "Error"
            return
        }
    }

    $typeLabel = if ($existingSwitch.EmbeddedTeamingEnabled) { "SET" } else { "External" }
    Write-OutputColor "  Using switch: $($existingSwitch.Name) ($typeLabel)" -color "Success"

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
                $navResult = Test-NavigationCommand -UserInput $vnicName
                if ($navResult.ShouldReturn) { return }
                if ([string]::IsNullOrWhiteSpace($vnicName)) {
                    Write-OutputColor "  Name cannot be empty." -color "Error"
                    return
                }
            }
            default {
                Write-OutputColor "  Invalid selection. Enter 1-5 or B." -color "Error"
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

        Write-OutputColor "  Removing existing vNIC '$vnicName'..." -color "Info"
        Remove-VMNetworkAdapter -ManagementOS -Name $vnicName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        # Verify removal succeeded
        $stillExists = Get-VMNetworkAdapter -ManagementOS -Name $vnicName -ErrorAction SilentlyContinue
        if ($stillExists) {
            Write-OutputColor "  Could not remove existing vNIC '$vnicName' (may be in use). Aborting." -color "Error"
            return
        }
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        $capSwitch = $existingSwitch.Name
        $capVnic   = $vnicName
        Push-DryRunStep -Label "Add vNIC '$capVnic' to switch '$capSwitch'" -Category "Network" -OneWay $false `
            -Params @{ Switch = $capSwitch; vNIC = $capVnic } `
            -Preflight {
                if (-not (Get-VMSwitch -Name $capSwitch -ErrorAction SilentlyContinue)) { "Switch '$capSwitch' not found" }
                else { $true }
            }.GetNewClosure() `
            -Apply {
                Add-VMNetworkAdapter -ManagementOS -SwitchName $capSwitch -Name $capVnic -ErrorAction Stop
            }.GetNewClosure() `
            -Undo {
                Remove-VMNetworkAdapter -ManagementOS -Name $capVnic -ErrorAction SilentlyContinue
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): add vNIC '$capVnic' to switch '$capSwitch'." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued vNIC '$capVnic' add to '$capSwitch'"
        return
    }

    # Create the vNIC
    try {
        Write-OutputColor "`nCreating virtual NIC '$vnicName'..." -color "Info"
        Add-VMNetworkAdapter -ManagementOS -SwitchName $existingSwitch.Name -Name $vnicName -ErrorAction Stop
        Write-OutputColor "  vNIC created: vEthernet ($vnicName)" -color "Success"
    }
    catch {
        Write-OutputColor "  Failed to create virtual NIC: $_" -color "Error"
        return
    }

    # Optional: Configure VLAN
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Set a VLAN ID? (Enter to skip, or 1-4094):" -color "Info"
    $vlanInput = Read-Host "  "
    $navResult = Test-NavigationCommand -UserInput $vlanInput
    if ($navResult.ShouldReturn) { return }
    if ($vlanInput -match '^\d+$') {
        $vlanId = [int]$vlanInput
        if ($vlanId -ge 1 -and $vlanId -le 4094) {
            try {
                Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $vnicName -Access -VlanId $vlanId -ErrorAction Stop
                Write-OutputColor "  VLAN $vlanId set on '$vnicName'." -color "Success"
            }
            catch {
                Write-OutputColor "  Failed to set VLAN: $_" -color "Error"
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
    $navResult = Test-NavigationCommand -UserInput $ipChoice
    if ($navResult.ShouldReturn) { return }
    if ($ipChoice -match '^[Yy]') {
        $ipResult = Get-IPAddressAndSubnet -Prompt "Enter IP address (e.g., 10.0.100.1/24)"
        if ($null -ne $ipResult) {
            $ipAddress = $ipResult[0]
            $cidr = $ipResult[1]
            $adapterAlias = "vEthernet ($vnicName)"
            try {
                # Scoped removal: only wipe Manual-origin IPs (not DHCP-leased) on this brand-new
                # vNIC. The unscoped `-AddressFamily IPv4` wipe would yank any IP the operator
                # had pre-assigned for staging, plus every IPv4 route. Brand-new vNICs typically
                # have nothing, but defense-in-depth — a re-run after a failed configure step
                # used to wipe the half-set state including any secondary IP.
                $preexistingIPs = @(Get-NetIPAddress -InterfaceAlias $adapterAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.PrefixOrigin -eq 'Manual' })
                foreach ($pre in $preexistingIPs) {
                    Remove-NetIPAddress -InterfaceAlias $adapterAlias -IPAddress $pre.IPAddress -Confirm:$false -ErrorAction SilentlyContinue
                }
                Remove-NetRoute -InterfaceAlias $adapterAlias -DestinationPrefix '0.0.0.0/0' -Confirm:$false -ErrorAction SilentlyContinue
                New-NetIPAddress -InterfaceAlias $adapterAlias -IPAddress $ipAddress -PrefixLength $cidr -ErrorAction Stop
                Write-OutputColor "  IP $ipAddress/$cidr set on '$vnicName'." -color "Success"
            }
            catch {
                Write-OutputColor "  Failed to set IP: $_" -color "Error"
            }
        }
    }

    $vlanMsg = if ($vlanInput -match '^\d+$' -and [int]$vlanInput -ge 1 -and [int]$vlanInput -le 4094) { " VLAN $vlanInput" } else { "" }
    Add-SessionChange -Category "Network" -Description "Added vNIC '$vnicName'$vlanMsg to SET '$($existingSwitch.Name)'"
    Clear-MenuCache

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Virtual NIC '$vnicName' created successfully!" -color "Success"
    Write-PressEnter
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
        $navResult = Test-NavigationCommand -UserInput $userInput
        if ($navResult.ShouldReturn) { return }
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

                    $adapters = @(Get-NetAdapter -ErrorAction Stop | Where-Object {
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
                    $navResult = Test-NavigationCommand -UserInput $adChoice
                    if ($navResult.ShouldReturn) { return }
                    if ($adChoice -match '^\d+$' -and [int]$adChoice -ge 1 -and [int]$adChoice -le $adapters.Count) {
                        $AdapterName = $adapters[[int]$adChoice - 1].Name
                    } else {
                        Write-OutputColor "  Invalid selection. Enter 1-$($adapters.Count)." -color "Error"
                        return
                    }
                }

                if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
                    $capName    = $SwitchName
                    $capAdapter = $AdapterName
                    $capMgmt    = $script:ManagementName
                    Push-DryRunStep -Label "Create External vSwitch '$capName' on '$capAdapter'" -Category "Network" -OneWay $false `
                        -Params @{ SwitchName = $capName; Adapter = $capAdapter } `
                        -Preflight {
                            if (Get-VMSwitch -Name $capName -ErrorAction SilentlyContinue) { "Switch '$capName' already exists" }
                            elseif (-not (Get-NetAdapter -Name $capAdapter -ErrorAction SilentlyContinue)) { "Adapter '$capAdapter' not found" }
                            else { $true }
                        }.GetNewClosure() `
                        -Apply {
                            New-VMSwitch -Name $capName -NetAdapterName $capAdapter -AllowManagementOS $true -ErrorAction Stop | Out-Null
                            $vnic = Get-VMNetworkAdapter -ManagementOS -Name $capName -ErrorAction SilentlyContinue
                            if ($vnic) {
                                Rename-VMNetworkAdapter -ManagementOS -Name $capName -NewName $capMgmt -ErrorAction SilentlyContinue
                            }
                        }.GetNewClosure() `
                        -Undo {
                            Remove-VMSwitch -Name $capName -Force -ErrorAction SilentlyContinue
                        }.GetNewClosure()
                    Write-OutputColor "  Queued (Dry-Run): create External vSwitch '$capName' on '$capAdapter'." -color "Warning"
                    Add-SessionChange -Category "DryRun" -Description "Queued External vSwitch '$capName' creation"
                    return
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
                    # $script:ManagementName is initialized in 00-Initialization.ps1 and
                    # overridable via defaults.json. The bare `$ManagementName` here was a
                    # typo that silently no-op'd the rename on every External vSwitch.
                    Rename-VMNetworkAdapter -ManagementOS -Name $SwitchName -NewName $script:ManagementName -ErrorAction SilentlyContinue
                }

                Write-OutputColor "  External switch '$SwitchName' created!" -color "Success"
                Add-SessionChange -Category "Network" -Description "Created External switch '$SwitchName' on $AdapterName"
                Clear-MenuCache
            }
            "Internal" {
                if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
                    $capName = $SwitchName
                    Push-DryRunStep -Label "Create Internal vSwitch '$capName'" -Category "Network" -OneWay $false `
                        -Params @{ SwitchName = $capName; Type = 'Internal' } `
                        -Preflight {
                            if (Get-VMSwitch -Name $capName -ErrorAction SilentlyContinue) { "Switch '$capName' already exists" }
                            else { $true }
                        }.GetNewClosure() `
                        -Apply { New-VMSwitch -Name $capName -SwitchType Internal -ErrorAction Stop | Out-Null }.GetNewClosure() `
                        -Undo  { Remove-VMSwitch -Name $capName -Force -ErrorAction SilentlyContinue }.GetNewClosure()
                    Write-OutputColor "  Queued (Dry-Run): create Internal vSwitch '$capName'." -color "Warning"
                    Add-SessionChange -Category "DryRun" -Description "Queued Internal vSwitch '$capName' creation"
                    return
                }
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Creating Internal switch '$SwitchName'..." -color "Info"
                New-VMSwitch -Name $SwitchName -SwitchType Internal -ErrorAction Stop
                Write-OutputColor "  Internal switch '$SwitchName' created!" -color "Success"
                Write-OutputColor "  Note: Host gets a vEthernet adapter. No physical NIC used." -color "Info"
                Add-SessionChange -Category "Network" -Description "Created Internal switch '$SwitchName'"
                Clear-MenuCache
            }
            "Private" {
                if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
                    $capName = $SwitchName
                    Push-DryRunStep -Label "Create Private vSwitch '$capName'" -Category "Network" -OneWay $false `
                        -Params @{ SwitchName = $capName; Type = 'Private' } `
                        -Preflight {
                            if (Get-VMSwitch -Name $capName -ErrorAction SilentlyContinue) { "Switch '$capName' already exists" }
                            else { $true }
                        }.GetNewClosure() `
                        -Apply { New-VMSwitch -Name $capName -SwitchType Private -ErrorAction Stop | Out-Null }.GetNewClosure() `
                        -Undo  { Remove-VMSwitch -Name $capName -Force -ErrorAction SilentlyContinue }.GetNewClosure()
                    Write-OutputColor "  Queued (Dry-Run): create Private vSwitch '$capName'." -color "Warning"
                    Add-SessionChange -Category "DryRun" -Description "Queued Private vSwitch '$capName' creation"
                    return
                }
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Creating Private switch '$SwitchName'..." -color "Info"
                New-VMSwitch -Name $SwitchName -SwitchType Private -ErrorAction Stop
                Write-OutputColor "  Private switch '$SwitchName' created!" -color "Success"
                Write-OutputColor "  Note: VMs can only communicate with each other. No host access." -color "Info"
                Add-SessionChange -Category "Network" -Description "Created Private switch '$SwitchName'"
                Clear-MenuCache
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

        $swName = "  $($sw.Name)"
        if ($swName.Length -gt 40) { $swName = $swName.Substring(0, 37) + "..." }
        $typeLbl = $typeLabel
        if ($typeLbl.Length -gt 32) { $typeLbl = $typeLbl.Substring(0, 29) + "..." }
        Write-OutputColor "  │$($swName.PadRight(40))$($typeLbl.PadRight(32))│" -color $color

        # Show management adapters on this switch
        $mgmtAdapters = Get-VMNetworkAdapter -ManagementOS -SwitchName $sw.Name -ErrorAction SilentlyContinue
        if ($mgmtAdapters) {
            foreach ($adapter in $mgmtAdapters) {
                $vlanInfo = Get-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $adapter.Name -ErrorAction SilentlyContinue
                $vlanStr = if ($null -ne $vlanInfo -and $vlanInfo.AccessVlanId -gt 0) { " VLAN $($vlanInfo.AccessVlanId)" } else { "" }
                $lineStr = "    └ vEthernet ($($adapter.Name))$vlanStr"
                if ($lineStr.Length -gt 72) { $lineStr = $lineStr.Substring(0, 69) + "..." }
                Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
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
        Write-OutputColor "  Invalid selection. Enter 1-$($switches.Count) or B." -color "Error"
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
        Clear-MenuCache
    }
    catch {
        Write-OutputColor "  Failed to remove switch: $_" -color "Error"
    }
}
#endregion