#region ===== VM CHECKPOINT MANAGEMENT (v2.8.0) =====
# Function to list VM checkpoints
function Get-VMCheckpointList {
    param(
        [string]$ComputerName = $null,
        [string]$VMName = $null,
        [System.Management.Automation.PSCredential]$Credential = $null
    )

    $params = @{}
    if ($ComputerName) { $params['ComputerName'] = $ComputerName }
    if ($Credential) { $params['Credential'] = $Credential }
    if ($VMName) { $params['VMName'] = $VMName }

    try {
        $checkpoints = @(Get-VMCheckpoint @params -ErrorAction Stop | Sort-Object VMName, CreationTime)

        if ($checkpoints.Count -eq 0) {
            return @{ Success = $true; Checkpoints = @(); Message = "No checkpoints found" }
        }

        return @{ Success = $true; Checkpoints = $checkpoints; Message = "$($checkpoints.Count) checkpoint(s) found" }
    }
    catch {
        return @{ Success = $false; Checkpoints = @(); Message = "Error: $_" }
    }
}

# Function to display checkpoint list
function Show-VMCheckpointList {
    param(
        [string]$ComputerName = $null,
        [System.Management.Automation.PSCredential]$Credential = $null
    )

    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                         VM CHECKPOINT LIST").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Gathering checkpoints..." -color "Info"

    $result = Get-VMCheckpointList -ComputerName $ComputerName -Credential $Credential

    if (-not $result.Success) {
        Write-OutputColor "  $($result.Message)" -color "Error"
        return
    }

    if ($result.Checkpoints.Count -eq 0) {
        Write-OutputColor "  No checkpoints found on this host." -color "Info"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  VM NAME               CHECKPOINT NAME           CREATED        SIZE").PadRight(72)│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    foreach ($cp in $result.Checkpoints) {
        $vmName = if ($cp.VMName.Length -gt 20) { $cp.VMName.Substring(0,17) + "..." } else { $cp.VMName.PadRight(20) }
        $cpName = if ($cp.Name.Length -gt 24) { $cp.Name.Substring(0,21) + "..." } else { $cp.Name.PadRight(24) }
        $created = $cp.CreationTime.ToString("MM/dd HH:mm")
        $sizeGB = if ($cp.SizeOfSystemFiles) { "{0:N1}GB" -f ($cp.SizeOfSystemFiles / 1GB) } else { "N/A" }

        $color = if ($cp.CheckpointType -eq "Production") { "Success" } else { "Info" }
        Write-OutputColor "  │  $vmName $cpName $created  $($sizeGB.PadLeft(8))  │" -color $color
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Total: $($result.Checkpoints.Count) checkpoint(s)" -color "Info"
    Write-OutputColor "  Green = Production checkpoints, Cyan = Standard checkpoints" -color "Info"
}

# Function to create a new checkpoint
function New-VMCheckpointWizard {
    param(
        [string]$ComputerName = $null,
        [System.Management.Automation.PSCredential]$Credential = $null
    )

    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       CREATE VM CHECKPOINT").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Get list of VMs
    $vmParams = @{}
    if ($ComputerName) { $vmParams['ComputerName'] = $ComputerName }
    if ($Credential) { $vmParams['Credential'] = $Credential }

    try {
        $vms = @(Get-VM @vmParams -ErrorAction Stop | Where-Object { $_.State -eq 'Running' -or $_.State -eq 'Off' } | Sort-Object Name)
    }
    catch {
        Write-OutputColor "  Error getting VMs: $_" -color "Error"
        return
    }

    if ($vms.Count -eq 0) {
        Write-OutputColor "  No VMs available for checkpoint." -color "Warning"
        return
    }

    # Display VMs
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT VM").PadRight(72)│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $vmIndex = 1
    $vmMap = @{}
    foreach ($vm in $vms) {
        $stateColor = if ($vm.State -eq 'Running') { "Success" } else { "Warning" }
        $vmDisplay = "[$vmIndex]  $($vm.Name.PadRight(40)) $($vm.State)"
        Write-OutputColor "  │  $($vmDisplay.PadRight(68))│" -color $stateColor
        $vmMap["$vmIndex"] = $vm
        $vmIndex++
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $vmChoice = Read-Host "  Enter VM number"
    $navResult = Test-NavigationCommand -UserInput $vmChoice
    if ($navResult.ShouldReturn) { return }

    if (-not $vmMap.ContainsKey($vmChoice)) {
        Write-OutputColor "  Invalid selection." -color "Error"
        return
    }

    $selectedVM = $vmMap[$vmChoice]

    # Get checkpoint name
    $defaultName = "Checkpoint_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Checkpoint name (Enter for default: $defaultName):" -color "Info"
    $cpName = Read-Host "  "
    if ([string]::IsNullOrWhiteSpace($cpName)) { $cpName = $defaultName }

    # Choose checkpoint type
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CHECKPOINT TYPE").PadRight(72)│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  [1]  Production (Recommended) - Uses VSS for app-consistent state".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [2]  Standard - Saves current memory state (faster)".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    $typeChoice = Read-Host "  Select"
    $cpType = if ($typeChoice -eq "2") { "Standard" } else { "Production" }

    # Confirm
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  VM: $($selectedVM.Name)" -color "Info"
    Write-OutputColor "  Checkpoint: $cpName" -color "Info"
    Write-OutputColor "  Type: $cpType" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Create checkpoint?")) { return }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Creating checkpoint..." -color "Info"

    try {
        $cpParams = @{
            VM = $selectedVM
            Name = $cpName
            SnapshotType = $cpType
        }
        if ($ComputerName) { $cpParams['ComputerName'] = $ComputerName }

        Checkpoint-VM @cpParams -ErrorAction Stop

        Write-OutputColor "  Checkpoint created successfully!" -color "Success"
        Add-SessionChange -Category "VM" -Description "Created $cpType checkpoint '$cpName' on VM '$($selectedVM.Name)'"
    }
    catch {
        Write-OutputColor "  Error creating checkpoint: $_" -color "Error"
    }
}

# Function to restore a checkpoint
function Restore-VMCheckpointWizard {
    param(
        [string]$ComputerName = $null,
        [System.Management.Automation.PSCredential]$Credential = $null
    )

    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                      RESTORE VM CHECKPOINT").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $result = Get-VMCheckpointList -ComputerName $ComputerName -Credential $Credential

    if (-not $result.Success -or $result.Checkpoints.Count -eq 0) {
        Write-OutputColor "  No checkpoints available to restore." -color "Warning"
        return
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT CHECKPOINT TO RESTORE").PadRight(72)│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $cpIndex = 1
    $cpMap = @{}
    foreach ($cp in $result.Checkpoints) {
        $vmName = if ($cp.VMName.Length -gt 18) { $cp.VMName.Substring(0,15) + "..." } else { $cp.VMName.PadRight(18) }
        $cpName = if ($cp.Name.Length -gt 24) { $cp.Name.Substring(0,21) + "..." } else { $cp.Name.PadRight(24) }
        $created = $cp.CreationTime.ToString("MM/dd HH:mm")

        Write-OutputColor "  │  [$($cpIndex.ToString().PadLeft(2))] $vmName $cpName $created  │" -color "Info"
        $cpMap["$cpIndex"] = $cp
        $cpIndex++
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $cpChoice = Read-Host "  Enter checkpoint number"
    $navResult = Test-NavigationCommand -UserInput $cpChoice
    if ($navResult.ShouldReturn) { return }

    if (-not $cpMap.ContainsKey($cpChoice)) {
        Write-OutputColor "  Invalid selection." -color "Error"
        return
    }

    $selectedCP = $cpMap[$cpChoice]

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("  WARNING: This will restore the VM to a previous state!").PadRight(72))║" -color "Warning"
    Write-OutputColor "  ║$(("  All changes since the checkpoint will be LOST.").PadRight(72))║" -color "Warning"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  VM: $($selectedCP.VMName)" -color "Info"
    Write-OutputColor "  Checkpoint: $($selectedCP.Name)" -color "Info"
    Write-OutputColor "  Created: $($selectedCP.CreationTime)" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Are you SURE you want to restore this checkpoint?")) { return }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Restoring checkpoint..." -color "Info"

    try {
        Restore-VMCheckpoint -VMCheckpoint $selectedCP -Confirm:$false -ErrorAction Stop

        Write-OutputColor "  Checkpoint restored successfully!" -color "Success"
        Add-SessionChange -Category "VM" -Description "Restored checkpoint '$($selectedCP.Name)' on VM '$($selectedCP.VMName)'"
    }
    catch {
        Write-OutputColor "  Error restoring checkpoint: $_" -color "Error"
    }
}

# Function to delete checkpoints
function Remove-VMCheckpointWizard {
    param(
        [string]$ComputerName = $null,
        [System.Management.Automation.PSCredential]$Credential = $null
    )

    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       DELETE VM CHECKPOINT").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $result = Get-VMCheckpointList -ComputerName $ComputerName -Credential $Credential

    if (-not $result.Success -or $result.Checkpoints.Count -eq 0) {
        Write-OutputColor "  No checkpoints available to delete." -color "Warning"
        return
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT CHECKPOINT TO DELETE").PadRight(72)│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $cpIndex = 1
    $cpMap = @{}
    foreach ($cp in $result.Checkpoints) {
        $vmName = if ($cp.VMName.Length -gt 18) { $cp.VMName.Substring(0,15) + "..." } else { $cp.VMName.PadRight(18) }
        $cpName = if ($cp.Name.Length -gt 24) { $cp.Name.Substring(0,21) + "..." } else { $cp.Name.PadRight(24) }
        $created = $cp.CreationTime.ToString("MM/dd HH:mm")

        Write-OutputColor "  │  [$($cpIndex.ToString().PadLeft(2))] $vmName $cpName $created  │" -color "Info"
        $cpMap["$cpIndex"] = $cp
        $cpIndex++
    }

    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  [A]  Delete ALL checkpoints (cleanup)".PadRight(72))│" -color "Warning"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $cpChoice = Read-Host "  Enter checkpoint number or 'A' for all"
    $navResult = Test-NavigationCommand -UserInput $cpChoice
    if ($navResult.ShouldReturn) { return }

    if ("$cpChoice".ToUpper() -eq "A") {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  This will delete ALL $($result.Checkpoints.Count) checkpoints!" -color "Warning"
        if (-not (Confirm-UserAction -Message "Delete all checkpoints?")) { return }

        Write-OutputColor "" -color "Info"
        $deleted = 0
        foreach ($cp in $result.Checkpoints) {
            Write-OutputColor "  Deleting: $($cp.VMName) - $($cp.Name)..." -color "Info"
            try {
                Remove-VMCheckpoint -VMCheckpoint $cp -Confirm:$false -ErrorAction Stop
                $deleted++
            }
            catch {
                Write-OutputColor "    Error: $_" -color "Error"
            }
        }
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Deleted $deleted of $($result.Checkpoints.Count) checkpoints." -color "Success"
        Add-SessionChange -Category "VM" -Description "Deleted $deleted VM checkpoints"
    }
    elseif ($cpMap.ContainsKey($cpChoice)) {
        $selectedCP = $cpMap[$cpChoice]

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  VM: $($selectedCP.VMName)" -color "Info"
        Write-OutputColor "  Checkpoint: $($selectedCP.Name)" -color "Info"
        Write-OutputColor "" -color "Info"

        if (-not (Confirm-UserAction -Message "Delete this checkpoint?")) { return }

        try {
            Remove-VMCheckpoint -VMCheckpoint $selectedCP -Confirm:$false -ErrorAction Stop
            Write-OutputColor "  Checkpoint deleted successfully!" -color "Success"
            Add-SessionChange -Category "VM" -Description "Deleted checkpoint '$($selectedCP.Name)' from VM '$($selectedCP.VMName)'"
        }
        catch {
            Write-OutputColor "  Error deleting checkpoint: $_" -color "Error"
        }
    }
    else {
        Write-OutputColor "  Invalid selection." -color "Error"
    }
}

# Function to show VM Checkpoint Management menu
function Show-VMCheckpointManagement {
    param(
        [string]$ComputerName = $null,
        [System.Management.Automation.PSCredential]$Credential = $null
    )

    while ($true) {
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                      VM CHECKPOINT MANAGEMENT").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        if ($ComputerName) {
            Write-OutputColor "  Connected to: $ComputerName" -color "Info"
            Write-OutputColor "" -color "Info"
        }

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-MenuItem -Text "[1]  List All Checkpoints"
        Write-MenuItem -Text "[2]  Create Checkpoint"
        Write-MenuItem -Text "[3]  Restore Checkpoint"
        Write-MenuItem -Text "[4]  Delete Checkpoint"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" {
                Show-VMCheckpointList -ComputerName $ComputerName -Credential $Credential
                Write-PressEnter
            }
            "2" {
                New-VMCheckpointWizard -ComputerName $ComputerName -Credential $Credential
                Write-PressEnter
            }
            "3" {
                Restore-VMCheckpointWizard -ComputerName $ComputerName -Credential $Credential
                Write-PressEnter
            }
            "4" {
                Remove-VMCheckpointWizard -ComputerName $ComputerName -Credential $Credential
                Write-PressEnter
            }
            "b" { return }
            "B" { return }
            default {
                Write-OutputColor "  Invalid choice." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}
#endregion