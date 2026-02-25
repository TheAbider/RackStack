#region ===== STORAGE REPLICA =====
# Function to manage Storage Replica
function Show-StorageReplicaManagement {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       STORAGE REPLICA").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Storage Replica requires Windows Server 2016 or later (Datacenter edition)
    if (-not $script:IsServer2016OrLater) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  Storage Replica requires Windows Server 2016 or later.".PadRight(72))│" -color "Error"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        return
    }

    # Check if Storage Replica is installed
    $srFeature = if (Test-WindowsServer) { Get-WindowsFeature -Name Storage-Replica -ErrorAction SilentlyContinue } else { $null }
    if (-not $srFeature -or $srFeature.InstallState -ne "Installed") {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  Storage Replica is not installed.".PadRight(72))│" -color "Warning"
        Write-OutputColor "  │$("  ".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Storage Replica provides synchronous or asynchronous replication".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  between servers or clusters for disaster recovery.".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Requires Windows Server Datacenter edition.".PadRight(72))│" -color "Warning"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [I] Install Storage Replica" -color "Success"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        switch ($choice) {
            { $_ -eq "I" -or $_ -eq "i" } {
                if (-not (Confirm-UserAction -Message "Install Storage Replica feature?")) { return }
                try {
                    Write-OutputColor "  Installing Storage Replica..." -color "Info"
                    Install-WindowsFeature -Name Storage-Replica -IncludeManagementTools -ErrorAction Stop
                    Write-OutputColor "  Storage Replica installed. Reboot required." -color "Success"
                    $global:RebootNeeded = $true
                    Add-SessionChange -Category "System" -Description "Installed Storage Replica"
                }
                catch {
                    Write-OutputColor "  Failed: $_" -color "Error"
                }
                Write-PressEnter
            }
            default { }
        }
        return
    }

    while ($true) {
        # Show current SR partnerships
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                       STORAGE REPLICA").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  STORAGE REPLICA PARTNERSHIPS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        $partnerships = @(Get-SRPartnership -ErrorAction SilentlyContinue)
        if ($partnerships.Count -gt 0) {
            foreach ($p in $partnerships) {
                $status = if ($p.ReplicationMode -eq "Synchronous") { "Sync" } else { "Async" }
                $lineStr = "  $($p.SourceComputerName) -> $($p.DestinationComputerName) [$status]"
                if ($lineStr.Length -gt 72) { $lineStr = $lineStr.Substring(0, 69) + "..." }
                Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Success"
            }
        }
        else {
            Write-OutputColor "  │$("  No Storage Replica partnerships configured.".PadRight(72))│" -color "Warning"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  OPTIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem -Text "[1]  Create New Partnership"
        Write-MenuItem -Text "[2]  Test Replication Topology"
        Write-MenuItem -Text "[3]  Show Replication Status"
        Write-MenuItem -Text "[4]  Remove Partnership"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Creating Storage Replica partnership requires:" -color "Info"
                Write-OutputColor "  - Source server, volume, and log volume" -color "Info"
                Write-OutputColor "  - Destination server, volume, and log volume" -color "Info"
                Write-OutputColor "  - Replication group name" -color "Info"
                Write-OutputColor "" -color "Info"

                $srcServer = Read-Host "  Source server name"
                $srcVol = Read-Host "  Source data volume (e.g., E:)"
                $srcLog = Read-Host "  Source log volume (e.g., F:)"
                $destServer = Read-Host "  Destination server name"
                $destVol = Read-Host "  Destination data volume (e.g., E:)"
                $destLog = Read-Host "  Destination log volume (e.g., F:)"
                $rgName = Read-Host "  Replication group name"

                Write-OutputColor "" -color "Info"
                Write-OutputColor "  [1] Synchronous (zero data loss)" -color "Info"
                Write-OutputColor "  [2] Asynchronous (better performance)" -color "Info"
                $mode = Read-Host "  Select replication mode"
                $repMode = if ($mode -eq "1") { "Synchronous" } else { "Asynchronous" }

                if (Confirm-UserAction -Message "Create Storage Replica partnership?") {
                    try {
                        New-SRPartnership -SourceComputerName $srcServer -SourceRGName $rgName `
                            -SourceVolumeName $srcVol -SourceLogVolumeName $srcLog `
                            -DestinationComputerName $destServer -DestinationRGName "${rgName}-Dest" `
                            -DestinationVolumeName $destVol -DestinationLogVolumeName $destLog `
                            -ReplicationMode $repMode -ErrorAction Stop

                        Write-OutputColor "  Storage Replica partnership created!" -color "Success"
                        Add-SessionChange -Category "Storage" -Description "Created SR partnership: $srcServer -> $destServer"
                    }
                    catch {
                        Write-OutputColor "  Failed: $_" -color "Error"
                    }
                }
            }
            "2" {
                Write-OutputColor "" -color "Info"
                $srcServer = Read-Host "  Source server"
                $destServer = Read-Host "  Destination server"
                $srcVol = Read-Host "  Source volume"
                $destVol = Read-Host "  Destination volume"

                Write-OutputColor "  Testing replication topology..." -color "Info"
                try {
                    $null = Test-SRTopology -SourceComputerName $srcServer -SourceVolumeName $srcVol `
                        -DestinationComputerName $destServer -DestinationVolumeName $destVol `
                        -DurationInMinutes 1 -ErrorAction Stop
                    Write-OutputColor "  Topology test complete. Check report for results." -color "Success"
                }
                catch {
                    Write-OutputColor "  Test failed: $_" -color "Error"
                }
            }
            "3" {
                $groups = Get-SRGroup -ErrorAction SilentlyContinue
                if ($groups) {
                    foreach ($g in $groups) {
                        $srGroup = Get-SRGroup -Name $g.Name -ErrorAction SilentlyContinue
                        $replStatus = if ($null -ne $srGroup) { $srGroup.Replicas } else { $null }
                        Write-OutputColor "" -color "Info"
                        Write-OutputColor "  Group: $($g.Name)" -color "Info"
                        foreach ($r in $replStatus) {
                            $syncPct = if ($r.NumOfBytesRemaining -and $r.PartitionSize) {
                                [math]::Round((1 - ($r.NumOfBytesRemaining / $r.PartitionSize)) * 100, 1)
                            } else { "N/A" }
                            $syncDisplay = if ($syncPct -eq "N/A") { "N/A" } else { "$syncPct%" }
                            Write-OutputColor "    $($r.DataVolume): Sync: $syncDisplay, Remaining: $([math]::Round($r.NumOfBytesRemaining / 1GB, 2)) GB" -color "Info"
                        }
                    }
                }
                else {
                    Write-OutputColor "  No replication groups found." -color "Warning"
                }
            }
            "4" {
                if (-not $partnerships) {
                    Write-OutputColor "  No partnerships to remove." -color "Warning"
                } else {
                    Write-OutputColor "" -color "Info"
                    $idx = 1
                    foreach ($p in $partnerships) {
                        Write-OutputColor "  [$idx] $($p.SourceComputerName) -> $($p.DestinationComputerName)" -color "Info"
                        $idx++
                    }
                    $pNum = Read-Host "  Select partnership to remove"
                    if ($pNum -match '^\d+$' -and [int]$pNum -ge 1 -and [int]$pNum -le $partnerships.Count) {
                        $sel = $partnerships[[int]$pNum - 1]
                        if (Confirm-UserAction -Message "Remove this partnership?") {
                            try {
                                Get-SRPartnership | Where-Object { $_.SourceComputerName -eq $sel.SourceComputerName } | Remove-SRPartnership -ErrorAction Stop
                                Write-OutputColor "  Partnership removed." -color "Success"
                            }
                            catch {
                                Write-OutputColor "  Failed: $_" -color "Error"
                            }
                        }
                    }
                }
            }
            "b" { return }
            "B" { return }
        }

        Write-PressEnter
    }
}
#endregion