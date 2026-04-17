#region ===== STORAGE REPLICA =====
# Function to show Storage Replica partnership health
function Show-ReplicaPartnershipHealth {
    try {
        $partnerships = Get-SRPartnership -ErrorAction Stop
        if ($null -eq $partnerships -or @($partnerships).Count -eq 0) {
            Write-OutputColor "  No Storage Replica partnerships configured" -color "Info"
            return
        }

        Write-OutputColor "`n  Storage Replica Partnership Health:" -color "Info"

        foreach ($partnership in $partnerships) {
            $srcGroup = $partnership.SourceRGName
            $destGroup = $partnership.DestinationRGName
            $destComp = $partnership.DestinationComputerName

            Write-OutputColor "`n  Partnership: $srcGroup -> $destGroup" -color "Info"
            Write-OutputColor "  Destination: $destComp" -color "Info"

            # Get replication group details
            try {
                $srGroup = Get-SRGroup -Name $srcGroup -ErrorAction Stop
                foreach ($vol in $srGroup.Replicas) {
                    $status = $vol.ReplicationStatus
                    $color = switch ($status) {
                        'ContinuouslyReplicating' { "Success" }
                        'InitialBlockCopy'        { "Warning" }
                        default                   { "Error" }
                    }
                    Write-OutputColor "    Volume: $($vol.DataVolume) -> Status: $status" -color $color

                    if ($null -ne $vol.NumOfBytesRemaining -and $vol.NumOfBytesRemaining -gt 0) {
                        $remainGB = [math]::Round($vol.NumOfBytesRemaining / 1GB, 1)
                        Write-OutputColor "    Bytes remaining: ${remainGB} GB" -color "Warning"
                    }
                }
            } catch {
                Write-OutputColor "    Could not get replication details: $($_.Exception.Message)" -color "Warning"
            }
        }
    } catch {
        Write-OutputColor "  Storage Replica not available: $($_.Exception.Message)" -color "Warning"
    }
}

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
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }
        switch ($choice) {
            { $_ -eq "I" -or $_ -eq "i" } {
                if (-not (Confirm-UserAction -Message "Install Storage Replica feature?")) { return }
                try {
                    Write-OutputColor "  Installing Storage Replica... This may take several minutes." -color "Info"
                    $installResult = Install-WindowsFeatureWithTimeout -FeatureName "Storage-Replica" -DisplayName "Storage Replica" -IncludeManagementTools
                    if ($installResult.TimedOut) {
                        Write-OutputColor "  Installation timed out." -color "Error"
                        Add-SessionChange -Category "System" -Description "Storage Replica installation timed out"
                        Clear-MenuCache
                    }
                    elseif ($installResult.Success) {
                        Write-OutputColor "  Storage Replica installed. Reboot required." -color "Success"
                        $global:RebootNeeded = $true
                        Add-SessionChange -Category "System" -Description "Installed Storage Replica"
                        Clear-MenuCache
                    }
                    else {
                        Write-OutputColor "  Storage Replica installation may not have completed successfully." -color "Error"
                        if ($installResult.Error) { Write-OutputColor "  Details: $($installResult.Error.Trim())" -color "Error" }
                        Add-SessionChange -Category "System" -Description "Storage Replica installation failed"
                        Clear-MenuCache
                    }
                }
                catch {
                    Write-OutputColor "  Storage Replica operation failed: $_" -color "Error"
                }
                Write-PressEnter
            }
            default { }
        }
        return
    }

    while ($true) {
        if ($global:ReturnToMainMenu) { return }
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
        Write-MenuItem -Text "[5]  Partnership Health Check"
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
                $navResult = Test-NavigationCommand -UserInput $srcServer
                if ($navResult.ShouldReturn) { return }
                $srcVol = Read-Host "  Source data volume (e.g., E:)"
                $navResult = Test-NavigationCommand -UserInput $srcVol
                if ($navResult.ShouldReturn) { return }
                $srcLog = Read-Host "  Source log volume (e.g., F:)"
                $navResult = Test-NavigationCommand -UserInput $srcLog
                if ($navResult.ShouldReturn) { return }
                $destServer = Read-Host "  Destination server name"
                $navResult = Test-NavigationCommand -UserInput $destServer
                if ($navResult.ShouldReturn) { return }
                $destVol = Read-Host "  Destination data volume (e.g., E:)"
                $navResult = Test-NavigationCommand -UserInput $destVol
                if ($navResult.ShouldReturn) { return }
                $destLog = Read-Host "  Destination log volume (e.g., F:)"
                $navResult = Test-NavigationCommand -UserInput $destLog
                if ($navResult.ShouldReturn) { return }
                $rgName = Read-Host "  Replication group name"
                $navResult = Test-NavigationCommand -UserInput $rgName
                if ($navResult.ShouldReturn) { return }

                # Validate all required fields
                if ([string]::IsNullOrWhiteSpace($srcServer) -or [string]::IsNullOrWhiteSpace($destServer) -or
                    [string]::IsNullOrWhiteSpace($srcVol) -or [string]::IsNullOrWhiteSpace($destVol) -or
                    [string]::IsNullOrWhiteSpace($srcLog) -or [string]::IsNullOrWhiteSpace($destLog) -or
                    [string]::IsNullOrWhiteSpace($rgName)) {
                    Write-OutputColor "  All fields are required. Partnership creation cancelled." -color "Error"
                    continue
                }

                # Validate volume format (drive letter with colon)
                $validVolumes = $true
                foreach ($vol in @($srcVol, $destVol, $srcLog, $destLog)) {
                    if ($vol -notmatch '^[A-Za-z]:$') {
                        Write-OutputColor "  Invalid volume format '$vol'. Expected format: E:" -color "Error"
                        $validVolumes = $false
                    }
                }
                if (-not $validVolumes) { continue }

                Write-OutputColor "" -color "Info"
                Write-OutputColor "  [1] Synchronous (zero data loss)" -color "Info"
                Write-OutputColor "  [2] Asynchronous (better performance)" -color "Info"
                $mode = Read-Host "  Select replication mode"
                $navResult = Test-NavigationCommand -UserInput $mode
                if ($navResult.ShouldReturn) {
                    if (Invoke-NavigationAction -NavResult $navResult) { return }
                    continue
                }
                $repMode = if ($mode -eq "1") { "Synchronous" } elseif ($mode -eq "2") { "Asynchronous" } else {
                    Write-OutputColor "  Invalid choice. Enter 1 or 2." -color "Error"
                    Start-Sleep -Seconds 1
                    continue
                }

                if (Confirm-UserAction -Message "Create Storage Replica partnership?") {
                    try {
                        New-SRPartnership -SourceComputerName $srcServer -SourceRGName $rgName `
                            -SourceVolumeName $srcVol -SourceLogVolumeName $srcLog `
                            -DestinationComputerName $destServer -DestinationRGName "${rgName}-Dest" `
                            -DestinationVolumeName $destVol -DestinationLogVolumeName $destLog `
                            -ReplicationMode $repMode -ErrorAction Stop

                        Write-OutputColor "  Storage Replica partnership created!" -color "Success"
                        Add-SessionChange -Category "Storage" -Description "Created SR partnership: $srcServer -> $destServer"
                        Clear-MenuCache

                        # Register manual-only undo — removing an SR partnership breaks replication.
                        # Runs only if user explicitly invokes "Undo last change".
                        $srcEsc = $srcServer -replace "'", "''"
                        $rgEsc = $rgName -replace "'", "''"
                        Add-UndoAction -Category "Storage" -Description "Remove SR partnership '$rgName' (breaks replication)" -UndoScript {
                            param($SrcServer, $RGName)
                            Write-Host "  Removing SR partnership '$RGName' on '$SrcServer'..." -ForegroundColor Yellow
                            Remove-SRPartnership -SourceComputerName $SrcServer -SourceRGName $RGName -Confirm:$false -ErrorAction Stop
                        }.GetNewClosure() -UndoParams @{ SrcServer = $srcEsc; RGName = $rgEsc }
                    }
                    catch {
                        Write-OutputColor "  Failed: $_" -color "Error"
                    }
                }
            }
            "2" {
                Write-OutputColor "" -color "Info"
                $srcServer = Read-Host "  Source server"
                $navResult = Test-NavigationCommand -UserInput $srcServer
                if ($navResult.ShouldReturn) { return }
                $destServer = Read-Host "  Destination server"
                $navResult = Test-NavigationCommand -UserInput $destServer
                if ($navResult.ShouldReturn) { return }
                $srcVol = Read-Host "  Source volume"
                $navResult = Test-NavigationCommand -UserInput $srcVol
                if ($navResult.ShouldReturn) { return }
                $destVol = Read-Host "  Destination volume"
                $navResult = Test-NavigationCommand -UserInput $destVol
                if ($navResult.ShouldReturn) { return }

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
                            $syncPct = if ($null -ne $r.NumOfBytesRemaining -and $null -ne $r.PartitionSize -and $r.PartitionSize -gt 0) {
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
                    $navResult = Test-NavigationCommand -UserInput $pNum
                    if ($navResult.ShouldReturn) { return }
                    if ($pNum -match '^\d+$' -and [int]$pNum -ge 1 -and [int]$pNum -le $partnerships.Count) {
                        $sel = $partnerships[[int]$pNum - 1]
                        $matchedParts = @(Get-SRPartnership | Where-Object {
                            $_.SourceComputerName -eq $sel.SourceComputerName -and
                            $_.DestinationComputerName -eq $sel.DestinationComputerName -and
                            $_.SourceRGName -eq $sel.SourceRGName
                        })
                        if ($matchedParts.Count -gt 1) {
                            Write-OutputColor "  WARNING: $($matchedParts.Count) partnerships match source '$($sel.SourceComputerName)'" -color "Warning"
                        }
                        if (Confirm-UserAction -Message "Remove $(if ($matchedParts.Count -gt 1) { "all $($matchedParts.Count) matching " })partnership(s)?") {
                            try {
                                $matchedParts | Remove-SRPartnership -Confirm:$false -ErrorAction Stop
                                Write-OutputColor "  Removed $($matchedParts.Count) partnership(s)." -color "Success"
                            }
                            catch {
                                Write-OutputColor "  Failed: $_" -color "Error"
                            }
                        }
                    }
                    else { Write-OutputColor "  Invalid selection. Enter 1-$($partnerships.Count)." -color "Error" }
                }
            }
            "5" {
                Show-ReplicaPartnershipHealth
            }
            { $_ -eq "b" -or $_ -eq "B" } { return }
            default { Write-OutputColor "  Invalid choice. Enter 1-5 or B." -color "Error"; Start-Sleep -Seconds 1 }
        }

        Write-PressEnter
    }
}
#endregion