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
        $checkpoints = @(Get-VMSnapshot @params -ErrorAction Stop | Sort-Object VMName, CreationTime)

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
    Write-OutputColor "  │$("  VM NAME               CHECKPOINT NAME           CREATED        SIZE".PadRight(72))│" -color "Info"
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
        Write-OutputColor "  No VMs available for checkpoint." -color "Error"
        return
    }

    # Display VMs
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT VM".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $vmIndex = 1
    $vmMap = @{}
    foreach ($vm in $vms) {
        $stateColor = if ($vm.State -eq 'Running') { "Success" } else { "Warning" }
        $vmDisplay = "[$vmIndex]  $($vm.Name.PadRight(40)) $($vm.State)"
        Write-OutputColor "  │  $($vmDisplay.PadRight(70))│" -color $stateColor
        $vmMap["$vmIndex"] = $vm
        $vmIndex++
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $vmChoice = Read-Host "  Enter VM number"
    $navResult = Test-NavigationCommand -UserInput $vmChoice
    if ($navResult.ShouldReturn) { return }

    if (-not $vmMap.ContainsKey($vmChoice)) {
        Write-OutputColor "  Invalid selection. Enter 1-$($vms.Count) or B." -color "Error"
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
    Write-OutputColor "  │$("  CHECKPOINT TYPE".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  [1]  Production (Recommended) - Uses VSS for app-consistent state".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [2]  Standard - Saves current memory state (faster)".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    $typeChoice = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $typeChoice
    if ($navResult.ShouldReturn) { return }
    $cpType = if ($typeChoice -eq "2") { "Standard" } else { "Production" }

    # Confirm
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  VM: $($selectedVM.Name)" -color "Info"
    Write-OutputColor "  Checkpoint: $cpName" -color "Info"
    Write-OutputColor "  Type: $cpType" -color "Info"
    Write-OutputColor "" -color "Info"

    # Disk space validation (skip for UNC paths)
    try {
        $vmPath = $selectedVM.Path
        if (-not $vmPath) { $vmPath = $selectedVM.ConfigurationLocation }
        if ($vmPath -and $vmPath -match '^[A-Za-z]:') {
            $driveLetter = $vmPath.Substring(0, 2)
            $volume = Get-Volume -DriveLetter $driveLetter.TrimEnd(':') -ErrorAction SilentlyContinue
            if ($null -ne $volume) {
                $freeGB = [math]::Round($volume.SizeRemaining / 1GB, 1)
                $totalGB = [math]::Round($volume.Size / 1GB, 1)
                $freePercent = if ($totalGB -gt 0) { [math]::Round(($freeGB / $totalGB) * 100, 1) } else { 0 }
                $ramGB = [math]::Round($selectedVM.MemoryAssigned / 1GB, 1)
                if ($ramGB -eq 0) { $ramGB = [math]::Round($selectedVM.MemoryStartup / 1GB, 1) }

                Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
                Write-OutputColor "  │$("  STORAGE CHECK: $driveLetter".PadRight(72))│" -color "Info"
                Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                Write-OutputColor "  │$("  Free Space:    ${freeGB} GB / ${totalGB} GB ($freePercent%)".PadRight(72))│" -color "Info"
                Write-OutputColor "  │$("  VM RAM:        ${ramGB} GB (checkpoint may use up to this amount)".PadRight(72))│" -color "Info"
                Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
                Write-OutputColor "" -color "Info"

                if ($freeGB -lt 10 -or ($ramGB -gt 0 -and $freeGB -lt ($ramGB * 1.5))) {
                    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Warning"
                    Write-OutputColor "  ║$("  WARNING: Low disk space! Checkpoint may fill the volume.".PadRight(72))║" -color "Warning"
                    Write-OutputColor "  ║$("  If storage fills during checkpoint, the VM may become inaccessible.".PadRight(72))║" -color "Warning"
                    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Warning"
                    Write-OutputColor "" -color "Info"
                }
            }
        }
    }
    catch {
        # Non-fatal — proceed without space check
    }

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
        Clear-MenuCache
    }
    catch {
        Write-RackStackError -Code "RS-5005" -Detail "$_"
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
        Write-OutputColor "  No checkpoints available to restore." -color "Error"
        return
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT CHECKPOINT TO RESTORE".PadRight(72))│" -color "Info"
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
        Write-OutputColor "  Invalid selection. Enter 1-$($result.Checkpoints.Count) or B." -color "Error"
        return
    }

    $selectedCP = $cpMap[$cpChoice]

    # Verify the VM still exists and resolve current state. Restoring against a renamed/
    # replaced VM (same name, different VMId) would silently target the wrong guest.
    $liveVm = $null
    try {
        if ($selectedCP.VMId) {
            $liveVm = Get-VM -Id $selectedCP.VMId -ErrorAction SilentlyContinue
        }
        if (-not $liveVm) {
            $liveVm = Get-VM -Name $selectedCP.VMName -ErrorAction SilentlyContinue
        }
    } catch { }
    if (-not $liveVm) {
        Write-OutputColor "  VM '$($selectedCP.VMName)' no longer exists on this host. Refusing to restore." -color "Error"
        return
    }
    if ($liveVm.VMId -ne $selectedCP.VMId) {
        Write-OutputColor "  VM '$($selectedCP.VMName)' exists but VMId has changed since checkpoint was taken." -color "Error"
        Write-OutputColor "  This is a different VM with the same name. Refusing to restore." -color "Error"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("  WARNING: This will restore the VM to a previous state!").PadRight(72))║" -color "Warning"
    Write-OutputColor "  ║$(("  All changes since the checkpoint will be LOST.").PadRight(72))║" -color "Warning"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  VM: $($selectedCP.VMName)" -color "Info"
    Write-OutputColor "  Current state: $($liveVm.State)" -color $(if ($liveVm.State -eq 'Running') { "Critical" } else { "Info" })
    Write-OutputColor "  Checkpoint: $($selectedCP.Name)" -color "Info"
    Write-OutputColor "  Created: $($selectedCP.CreationTime)" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($liveVm.State -eq 'Running') {
        Write-OutputColor "  CRITICAL: VM is currently RUNNING." -color "Critical"
        Write-OutputColor "  Restoring will terminate the live workload — in-flight transactions" -color "Warning"
        Write-OutputColor "  (DB commits, file writes, AD replication) will be lost. The VM will" -color "Warning"
        Write-OutputColor "  revert to the checkpoint state as if power was cut." -color "Warning"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Type RESTORE to confirm restoring a running VM:" -color "Warning"
        $confirm = Read-Host
        if ($confirm -ne 'RESTORE') {
            Write-OutputColor "  Restore cancelled (did not type RESTORE)." -color "Info"
            return
        }
    } else {
        if (-not (Confirm-UserAction -Message "Are you SURE you want to restore this checkpoint?")) { return }
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Restoring checkpoint..." -color "Info"

    try {
        Restore-VMSnapshot -VMSnapshot $selectedCP -Confirm:$false -ErrorAction Stop

        Write-OutputColor "  Checkpoint restored successfully!" -color "Success"
        Add-SessionChange -Category "VM" -Description "Restored checkpoint '$($selectedCP.Name)' on VM '$($selectedCP.VMName)'"
        Clear-MenuCache
    }
    catch {
        Write-RackStackError -Code "RS-5005" -Detail "$_"
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
        Write-OutputColor "  No checkpoints available to delete." -color "Error"
        return
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT CHECKPOINT TO DELETE".PadRight(72))│" -color "Info"
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
        $totalCp = $result.Checkpoints.Count

        # Group by VM and surface oldest/newest per VM so the operator sees what they're
        # about to wipe. Past incident: a second admin's pre-patch snapshot got nuked in
        # a "cleanup" sweep because the prompt didn't show per-VM detail.
        $byVm = $result.Checkpoints | Group-Object VMName
        Write-OutputColor "" -color "Warning"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Critical"
        Write-OutputColor "  ║  DESTRUCTIVE: About to delete ALL $totalCp checkpoint(s) across $($byVm.Count) VM(s)" -color "Critical"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Critical"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Per-VM breakdown:" -color "Info"
        $now = Get-Date
        $recentCount = 0
        $runningVMCount = 0
        foreach ($g in ($byVm | Sort-Object Name)) {
            $oldest = ($g.Group | Sort-Object CreationTime | Select-Object -First 1).CreationTime
            $newest = ($g.Group | Sort-Object CreationTime -Descending | Select-Object -First 1).CreationTime
            $newestAge = ($now - $newest).TotalMinutes
            if ($newestAge -lt 60) { $recentCount++ }
            $vmState = ""
            try {
                $vm = Get-VM -Name $g.Name -ErrorAction SilentlyContinue
                if ($vm) {
                    $vmState = " [$($vm.State)]"
                    if ($vm.State -eq 'Running') { $runningVMCount++ }
                }
            } catch { }
            $lineStr = "  $($g.Name)$vmState : $($g.Count) checkpoint(s), oldest=$($oldest.ToString('yyyy-MM-dd HH:mm')), newest=$($newest.ToString('yyyy-MM-dd HH:mm'))"
            if ($lineStr.Length -gt 100) { $lineStr = $lineStr.Substring(0, 97) + "..." }
            $color = if ($newestAge -lt 60) { "Critical" } else { "Info" }
            Write-OutputColor $lineStr -color $color
        }

        if ($recentCount -gt 0) {
            Write-OutputColor "" -color "Critical"
            Write-OutputColor "  WARNING: $recentCount VM(s) have a checkpoint less than 1 hour old." -color "Critical"
            Write-OutputColor "  Another admin may have just taken a pre-change snapshot." -color "Warning"
        }
        if ($runningVMCount -gt 0) {
            Write-OutputColor "" -color "Warning"
            Write-OutputColor "  NOTE: $runningVMCount running VM(s) will see live AVHDX merges." -color "Warning"
            Write-OutputColor "  Concurrent merges can spike storage latency and cause guest I/O timeouts." -color "Warning"
            Write-OutputColor "  Deletions will be sequential (one VM's chain at a time) to limit blast radius." -color "Info"
        }

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Type DELETE $totalCp to confirm (must match exactly):" -color "Critical"
        $confirmInput = Read-Host
        if ($confirmInput -ne "DELETE $totalCp") {
            Write-OutputColor "  Cancelled (confirmation did not match)." -color "Info"
            return
        }

        Write-OutputColor "" -color "Info"
        $deleted = 0
        $errors = 0
        # Process one VM's chain to completion before starting the next — this caps concurrent
        # AVHDX merges to a single VM, preventing the merge-storm pattern where parallel merges
        # across many VMs saturate storage and cause guest OS I/O timeouts.
        foreach ($vmGroup in ($byVm | Sort-Object Name)) {
            # Within a VM, delete children before parents (descending CreationTime) so leaves
            # merge first. Hyper-V handles ordering internally too, but this is a safe hint.
            $vmCheckpoints = @($vmGroup.Group | Sort-Object CreationTime -Descending)
            foreach ($cp in $vmCheckpoints) {
                Write-OutputColor "  Deleting: $($cp.VMName) - $($cp.Name)..." -color "Info"
                try {
                    Remove-VMSnapshot -VMSnapshot $cp -Confirm:$false -ErrorAction Stop
                    $deleted++
                }
                catch {
                    Write-OutputColor "    Error: $_" -color "Error"
                    $errors++
                }
            }
            # Wait for this VM's merges to complete before moving to the next VM. Without this
            # the loop fires deletes back-to-back across VMs, defeating the sequential intent.
            try {
                $vm = Get-VM -Name $vmGroup.Name -ErrorAction SilentlyContinue
                if ($vm) {
                    $waitStart = Get-Date
                    while ($vm.Status -match 'Merging|Updating' -and ((Get-Date) - $waitStart).TotalMinutes -lt 30) {
                        Start-Sleep -Seconds 5
                        $vm = Get-VM -Name $vmGroup.Name -ErrorAction SilentlyContinue
                        if (-not $vm) { break }
                    }
                }
            } catch { }
        }
        Write-OutputColor "" -color "Info"
        $resultColor = if ($errors -eq 0) { "Success" } else { "Warning" }
        Write-OutputColor "  Deleted $deleted of $totalCp checkpoints ($errors errors)." -color $resultColor
        Add-SessionChange -Category "VM" -Description "Deleted $deleted VM checkpoints (bulk)"
        Clear-MenuCache
    }
    elseif ($cpMap.ContainsKey($cpChoice)) {
        $selectedCP = $cpMap[$cpChoice]

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  VM: $($selectedCP.VMName)" -color "Info"
        Write-OutputColor "  Checkpoint: $($selectedCP.Name)" -color "Info"
        Write-OutputColor "" -color "Info"

        if (-not (Confirm-UserAction -Message "Delete this checkpoint?")) { return }

        try {
            Remove-VMSnapshot -VMSnapshot $selectedCP -Confirm:$false -ErrorAction Stop
            Write-OutputColor "  Checkpoint deleted successfully!" -color "Success"
            Add-SessionChange -Category "VM" -Description "Deleted checkpoint '$($selectedCP.Name)' from VM '$($selectedCP.VMName)'"
            Clear-MenuCache
        }
        catch {
            Write-OutputColor "  Error deleting checkpoint: $_" -color "Error"
        }
    }
    else {
        Write-OutputColor "  Invalid selection. Enter 1-$($result.Checkpoints.Count), A, or B." -color "Error"
    }
}

# Function to show checkpoint age warnings
function Show-CheckpointAgeWarnings {
    try {
        # On hosts with hundreds of VMs, Get-VMSnapshot -VMName * blocks for minutes
        # with no progress indicator. Pre-check VM count and warn / cap before the slow
        # call. Past incident: cluster node with 300+ VMs froze terminal for ~3 minutes.
        $vmCount = 0
        try { $vmCount = @(Get-VM -ErrorAction SilentlyContinue).Count } catch { }
        if ($vmCount -gt 100) {
            Write-OutputColor "" -color "Warning"
            Write-OutputColor "  This host has $vmCount VMs. Scanning all checkpoints may take 1-3 minutes." -color "Warning"
            if (-not (Confirm-UserAction -Message "Scan checkpoints across all $vmCount VMs?")) {
                Write-OutputColor "  Scan skipped." -color "Info"
                return
            }
        }

        $cpResult = Invoke-WithTimeout -ScriptBlock {
            Get-VMSnapshot -VMName * -ErrorAction SilentlyContinue
        } -TimeoutSeconds 120 -Activity "Scanning VM checkpoints"

        if ($cpResult.TimedOut) {
            Write-OutputColor "  Checkpoint scan timed out after 120s. Try scanning per-VM instead." -color "Warning"
            return
        }
        if ($cpResult.Failed) {
            Write-OutputColor "  Checkpoint scan failed: $($cpResult.Error)" -color "Error"
            return
        }
        $checkpoints = $cpResult.Result
        if ($null -eq $checkpoints -or @($checkpoints).Count -eq 0) {
            Write-OutputColor "  No VM checkpoints found" -color "Success"
            return
        }

        $oldCount = 0
        $totalSize = 0

        Write-OutputColor "`n  VM Checkpoint Age Report:" -color "Info"

        foreach ($cp in $checkpoints) {
            $age = (Get-Date) - $cp.CreationTime
            $vmName = $cp.VMName
            $cpName = if ($cp.Name.Length -gt 30) { $cp.Name.Substring(0, 27) + "..." } else { $cp.Name }

            $color = "Success"
            $warning = ""
            if ($age.TotalDays -gt 30) {
                $color = "Error"
                $warning = " [CRITICAL: $([math]::Round($age.TotalDays)) days old]"
                $oldCount++
            } elseif ($age.TotalDays -gt 7) {
                $color = "Warning"
                $warning = " [$([math]::Round($age.TotalDays)) days old]"
                $oldCount++
            }

            # Show size if available
            $sizeLabel = ""
            if ($cp.SizeOfSystemFiles -and $cp.SizeOfSystemFiles -gt 0) {
                $sizeGB = [math]::Round($cp.SizeOfSystemFiles / 1GB, 1)
                $sizeLabel = " (${sizeGB} GB)"
                $totalSize += $cp.SizeOfSystemFiles
            }
            Write-OutputColor "  $vmName / $cpName - Created: $($cp.CreationTime.ToString('yyyy-MM-dd'))$warning$sizeLabel" -color $color
        }

        Write-OutputColor "`n  Total checkpoints: $(@($checkpoints).Count)" -color "Info"
        if ($totalSize -gt 0) {
            Write-OutputColor "  Total checkpoint disk usage: $([math]::Round($totalSize / 1GB, 1)) GB" -color "Info"
        }
        if ($oldCount -gt 0) {
            Write-OutputColor "  WARNING: $oldCount checkpoint(s) older than 7 days" -color "Warning"
            Write-OutputColor "  Old checkpoints degrade VM performance and consume disk space" -color "Warning"
        } else {
            Write-OutputColor "  All checkpoints are recent" -color "Success"
        }
    } catch {
        Write-OutputColor "  Could not check VM checkpoints: $($_.Exception.Message)" -color "Error"
    }
}

# Function to show VM Checkpoint Management menu
function Show-VMCheckpointManagement {
    param(
        [string]$ComputerName = $null,
        [System.Management.Automation.PSCredential]$Credential = $null
    )

    # Pre-check: Hyper-V must be installed
    if (-not $ComputerName -and -not (Test-HyperVInstalled)) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Hyper-V is not installed on this host." -color "Error"
        Write-OutputColor "  Install Hyper-V from Roles & Features before managing checkpoints." -color "Warning"
        return
    }

    while ($true) {
        if ($script:ReturnToMainMenu) { return }
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
        Write-MenuItem -Text "[5]  Checkpoint Age Warnings"
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
            "5" {
                Clear-Host
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
                Write-OutputColor "  ║$(("                     CHECKPOINT AGE WARNINGS").PadRight(72))║" -color "Info"
                Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
                Write-OutputColor "" -color "Info"
                Show-CheckpointAgeWarnings
                Write-PressEnter
            }
            "b" { return }
            "B" { return }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-5 or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}
#endregion