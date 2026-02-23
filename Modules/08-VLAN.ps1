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
    Write-OutputColor "Adapter: $selectedAdapterName" -color "Info"

    # Check if this is a vEthernet adapter (Hyper-V)
    if ($selectedAdapterName -notlike "vEthernet*") {
        Write-OutputColor "`nNote: VLAN tagging on physical adapters varies by manufacturer." -color "Warning"
        Write-OutputColor "Please configure VLAN via adapter properties or manufacturer tools." -color "Info"
        Write-OutputColor "This function only works with Hyper-V virtual adapters (vEthernet)." -color "Info"
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
        # Try finding by partial match
        $vmAdapter = Get-VMNetworkAdapter -ManagementOS -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$vmAdapterName*" }
    }

    if (-not $vmAdapter) {
        Write-OutputColor "`nCould not find Hyper-V adapter matching '$vmAdapterName'" -color "Error"
        Write-OutputColor "Available Hyper-V management adapters:" -color "Info"
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
                Write-OutputColor "Current VLAN ID: $($currentVlan.AccessVlanId) (Access Mode)" -color "Info"
            }
            elseif ($currentVlan.OperationMode -eq "Trunk") {
                Write-OutputColor "Current Mode: Trunk (Native VLAN: $($currentVlan.NativeVlanId))" -color "Info"
            }
            else {
                Write-OutputColor "Current VLAN: Untagged" -color "Info"
            }
        }
        else {
            Write-OutputColor "Current VLAN: Untagged" -color "Info"
        }
    }
    catch {
        Write-OutputColor "Current VLAN: Unable to determine" -color "Warning"
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "VLAN Options:" -color "Info"
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
            Write-OutputColor "Enter VLAN ID (1-4094):" -color "Info"
            $vlanIdInput = Read-Host

            # Check for navigation
            $navResult = Test-NavigationCommand -UserInput $vlanIdInput
            if ($navResult.ShouldReturn) {
                if (Invoke-NavigationAction -NavResult $navResult) { return }
            }

            if (-not (Test-ValidVLANId -VLANId $vlanIdInput)) {
                Write-OutputColor "Invalid VLAN ID. Must be between 1 and 4094." -color "Error"
                return
            }

            $vlanId = [int]$vlanIdInput

            try {
                Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $vmAdapterName -Access -VlanId $vlanId -ErrorAction Stop
                Write-OutputColor "VLAN $vlanId configured successfully on $selectedAdapterName" -color "Success"
                Add-SessionChange -Category "Network" -Description "Set VLAN $vlanId on $selectedAdapterName"
            }
            catch {
                Write-OutputColor "Failed to set VLAN: $_" -color "Error"
                Write-OutputColor "Tip: Ensure Hyper-V is properly installed and the adapter is a management OS adapter." -color "Warning"
            }
        }
        "2" {
            try {
                Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $vmAdapterName -Untagged -ErrorAction Stop
                Write-OutputColor "VLAN removed. Adapter is now untagged." -color "Success"
                Add-SessionChange -Category "Network" -Description "Removed VLAN from $selectedAdapterName"
            }
            catch {
                Write-OutputColor "Failed to remove VLAN: $_" -color "Error"
            }
        }
        default {
            Write-OutputColor "VLAN configuration cancelled." -color "Info"
        }
    }
}
#endregion