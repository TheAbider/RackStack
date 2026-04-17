#region ===== VLAN CONFIGURATION =====
# Function to configure VLAN on a Hyper-V management adapter
function Set-AdapterVLAN {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$selectedAdapterName
    )

    Clear-Host
    Write-CenteredOutput "VLAN Configuration" -color "Info"
    Write-OutputColor "  Adapter: $selectedAdapterName" -color "Info"

    Show-VLANSummary

    # Check if this is a vEthernet adapter (Hyper-V)
    if ($selectedAdapterName -notlike "vEthernet*") {
        Write-OutputColor "`nNote: VLAN tagging on physical adapters varies by manufacturer." -color "Warning"
        Write-OutputColor "  Please configure VLAN via adapter properties or manufacturer tools." -color "Info"
        Write-OutputColor "  This function only works with Hyper-V virtual adapters (vEthernet)." -color "Info"
        return
    }

    # VLAN on vEthernet requires Hyper-V
    if (-not (Test-HyperVInstalled)) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Hyper-V is required for VLAN configuration on virtual adapters." -color "Warning"
        if (Confirm-UserAction -Message "Install Hyper-V now?") {
            Install-HyperVRole
        }
        return
    }

    # Extract the VM adapter name from vEthernet (Name) - handle multiple formats
    # Format 1: "vEthernet (Management)" -> "Management"
    # Format 2: "vEthernet (Default Switch)" -> "Default Switch"
    $vmAdapterName = $selectedAdapterName
    if ($selectedAdapterName -match '^vEthernet \((.+)\)$') {
        $regexMatches = $matches
        $vmAdapterName = $regexMatches[1]
    }
    elseif ($selectedAdapterName -match '^vEthernet (.+)$') {
        $regexMatches = $matches
        $vmAdapterName = $regexMatches[1]
    }

    Write-OutputColor "Hyper-V Adapter Name: $vmAdapterName" -color "Debug"

    # Try to find the adapter in Hyper-V
    $vmAdapter = Get-VMNetworkAdapter -ManagementOS -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $vmAdapterName }

    if (-not $vmAdapter) {
        # Try finding by partial match — warn user since this is imprecise
        $candidates = @(Get-VMNetworkAdapter -ManagementOS -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$vmAdapterName*" })
        if ($candidates.Count -eq 1) {
            Write-OutputColor "  Note: Using partial match '$($candidates[0].Name)' for '$vmAdapterName'" -color "Warning"
            $vmAdapter = $candidates[0]
        } elseif ($candidates.Count -gt 1) {
            Write-OutputColor "  Multiple adapters match '$vmAdapterName':" -color "Warning"
            foreach ($c in $candidates) { Write-OutputColor "    - $($c.Name) (Switch: $($c.SwitchName))" -color "Info" }
            Write-OutputColor "  Please use exact adapter name." -color "Error"
        }
    }

    if (-not $vmAdapter) {
        Write-OutputColor "`nCould not find Hyper-V adapter matching '$vmAdapterName'" -color "Error"
        Write-OutputColor "  Available Hyper-V management adapters:" -color "Info"
        $allVMAdapters = Get-VMNetworkAdapter -ManagementOS -ErrorAction SilentlyContinue
        foreach ($a in $allVMAdapters) {
            Write-OutputColor "  - $($a.Name) (Switch: $($a.SwitchName))" -color "Info"
        }
        Write-OutputColor "`nTip: The adapter name in Hyper-V may differ from the Windows adapter name." -color "Warning"
        return
    }

    $vmAdapterName = $vmAdapter.Name  # Use the actual name found

    # Try to get current VLAN settings
    try {
        $currentVlan = Get-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $vmAdapterName -ErrorAction SilentlyContinue

        if ($currentVlan) {
            if ($currentVlan.AccessVlanId -gt 0) {
                Write-OutputColor "  Current VLAN ID: $($currentVlan.AccessVlanId) (Access Mode)" -color "Info"
            }
            elseif ($currentVlan.OperationMode -eq "Trunk") {
                Write-OutputColor "  Current Mode: Trunk (Native VLAN: $($currentVlan.NativeVlanId))" -color "Info"
            }
            else {
                Write-OutputColor "  Current VLAN: Untagged" -color "Info"
            }
        }
        else {
            Write-OutputColor "  Current VLAN: Untagged" -color "Info"
        }
    }
    catch {
        Write-OutputColor "  Current VLAN: Unable to determine" -color "Warning"
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  VLAN Options:" -color "Info"
    Write-OutputColor "1. Set Access VLAN (tag all traffic with VLAN ID)" -color "Info"
    Write-OutputColor "2. Remove VLAN (untagged traffic)" -color "Info"
    Write-OutputColor "3. Cancel" -color "Info"

    $choice = Read-Host "  Select"

    # Check for navigation
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) {
        if (Invoke-NavigationAction -NavResult $navResult) { return }
    }

    switch ($choice) {
        "1" {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Valid range: 1-4094" -color "Info"
            Write-OutputColor "  Reserved: 0 (system), 1 (default/native), 4095 (system)" -color "Debug"
            Write-OutputColor "  Legacy reserved: 1002-1005 (FDDI/Token Ring)" -color "Debug"
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Enter VLAN ID:" -color "Info"
            $vlanIdInput = Read-Host

            # Check for navigation
            $navResult = Test-NavigationCommand -UserInput $vlanIdInput
            if ($navResult.ShouldReturn) {
                if (Invoke-NavigationAction -NavResult $navResult) { return }
            }

            if (-not (Test-ValidVLANId -VLANId $vlanIdInput)) {
                Write-OutputColor "  Invalid VLAN ID. Must be between 1 and 4094." -color "Error"
                return
            }

            $vlanId = [int]$vlanIdInput

            # Warn about reserved/special ranges
            if ($vlanId -eq 1) {
                Write-OutputColor "  Note: VLAN 1 is the default/native VLAN on most switches." -color "Warning"
                Write-OutputColor "  Traffic on VLAN 1 is often untagged. Verify with your switch config." -color "Warning"
                if (-not (Confirm-UserAction -Message "Use VLAN 1?")) { return }
            }
            elseif ($vlanId -ge 1002 -and $vlanId -le 1005) {
                Write-OutputColor "  Warning: VLANs 1002-1005 are reserved for legacy FDDI/Token Ring." -color "Warning"
                Write-OutputColor "  Some switches may reject or ignore these VLANs." -color "Warning"
                if (-not (Confirm-UserAction -Message "Use VLAN $vlanId anyway?")) { return }
            }
            elseif ($vlanId -eq 4094) {
                Write-OutputColor "  Note: VLAN 4094 is commonly used for GVRP pruning." -color "Warning"
                if (-not (Confirm-UserAction -Message "Use VLAN 4094?")) { return }
            }

            try {
                $prevVlanId = if ($null -ne $currentVlan -and $currentVlan.AccessVlanId -gt 0) { $currentVlan.AccessVlanId } else { 0 }
                Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $vmAdapterName -Access -VlanId $vlanId -ErrorAction Stop
                Write-OutputColor "  VLAN $vlanId configured successfully on $selectedAdapterName" -color "Success"
                Add-SessionChange -Category "Network" -Description "Set VLAN $vlanId on $selectedAdapterName"
                Clear-MenuCache
                Add-UndoAction -Category "Network" -Description "Set VLAN $vlanId on $selectedAdapterName" -UndoScript {
                    param($AdapterName, $OldVlanId)
                    if ($OldVlanId -gt 0) {
                        Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $AdapterName -Access -VlanId $OldVlanId -ErrorAction SilentlyContinue
                    } else {
                        Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $AdapterName -Untagged -ErrorAction SilentlyContinue
                    }
                }.GetNewClosure() -UndoParams @{ AdapterName = $vmAdapterName; OldVlanId = $prevVlanId }
            }
            catch {
                Write-OutputColor "  Failed to set VLAN: $_" -color "Error"
                Write-OutputColor "  Tip: Ensure Hyper-V is properly installed and the adapter is a management OS adapter." -color "Warning"
            }
        }
        "2" {
            try {
                $prevVlanId = if ($null -ne $currentVlan -and $currentVlan.AccessVlanId -gt 0) { $currentVlan.AccessVlanId } else { 0 }
                Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $vmAdapterName -Untagged -ErrorAction Stop
                Write-OutputColor "  VLAN removed. Adapter is now untagged." -color "Success"
                Add-SessionChange -Category "Network" -Description "Removed VLAN from $selectedAdapterName"
                Clear-MenuCache
                if ($prevVlanId -gt 0) {
                    Add-UndoAction -Category "Network" -Description "Removed VLAN from $selectedAdapterName" -UndoScript {
                        param($AdapterName, $OldVlanId)
                        Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $AdapterName -Access -VlanId $OldVlanId -ErrorAction SilentlyContinue
                    }.GetNewClosure() -UndoParams @{ AdapterName = $vmAdapterName; OldVlanId = $prevVlanId }
                }
            }
            catch {
                Write-OutputColor "  Failed to remove VLAN: $_" -color "Error"
            }
        }
        "3" {
            Write-OutputColor "  VLAN configuration cancelled." -color "Info"
        }
        default {
            Write-OutputColor "  Invalid selection. Enter 1-3." -color "Error"
        }
    }
}

# Function to display current VLAN assignments across all adapters
function Show-VLANSummary {
    Write-OutputColor "`n  VLAN Configuration Summary:" -color "Info"

    try {
        $adapters = Get-NetAdapter -ErrorAction SilentlyContinue
        $vlanFound = $false

        foreach ($adapter in $adapters) {
            $vlanId = (Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword 'VlanID' -ErrorAction SilentlyContinue).RegistryValue

            if ($null -ne $vlanId -and $vlanId -ne '0' -and $vlanId -ne 0) {
                $vlanFound = $true
                Write-OutputColor "  $($adapter.Name): VLAN $vlanId ($($adapter.Status))" -color "Info"
            }
        }

        # Also check Hyper-V vNIC VLANs (skipped when Hyper-V role not installed)
        try {
            $vmNics = Get-VMNetworkAdapter -ManagementOS -ErrorAction Stop
            foreach ($nic in $vmNics) {
                if ($null -ne $nic.VlanSetting -and $nic.VlanSetting.AccessVlanId -gt 0) {
                    $vlanFound = $true
                    Write-OutputColor "  $($nic.Name) (vNIC): VLAN $($nic.VlanSetting.AccessVlanId)" -color "Info"
                }
            }
        } catch {
            if ($_.Exception.Message -notmatch 'not recognized|not installed|ObjectNotFound|not running') {
                Write-OutputColor "  vNIC VLAN enumeration skipped: $($_.Exception.Message)" -color "Debug"
            }
        }

        if (-not $vlanFound) {
            Write-OutputColor "  No VLAN assignments found" -color "Info"
        }
    } catch {
        Write-OutputColor "  Could not enumerate VLANs: $($_.Exception.Message)" -color "Warning"
    }
}
#endregion