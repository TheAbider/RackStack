#region ===== CLUSTER DASHBOARD (v2.8.0) =====
# Function to show enhanced cluster dashboard
function Show-ClusterDashboard {
    Clear-Host

    # Check if node is part of a cluster
    $cluster = Get-Cluster -ErrorAction SilentlyContinue

    if (-not $cluster) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                       CLUSTER DASHBOARD").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  This server is not part of a cluster." -color "Warning"
        Write-OutputColor "  Use Cluster Management to create or join a cluster first." -color "Info"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("           CLUSTER DASHBOARD: " + $cluster.Name.ToUpper()).PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Get cluster nodes
    $nodes = Get-ClusterNode -ErrorAction SilentlyContinue

    # NODE STATUS section
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  NODE STATUS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    foreach ($node in $nodes) {
        $vmCount = @(Get-ClusterGroup -Cluster $cluster.Name -ErrorAction SilentlyContinue |
            Where-Object { $_.GroupType -eq 'VirtualMachine' -and $_.OwnerNode -eq $node.Name }).Count

        $statusSymbol = switch ($node.State) {
            "Up" { "[●]" }
            "Paused" { "[◐]" }
            "Down" { "[○]" }
            default { "[?]" }
        }
        $stateColor = switch ($node.State) {
            "Up" { "Success" }
            "Paused" { "Warning" }
            "Down" { "Error" }
            default { "Info" }
        }
        $stateDetail = if ($node.State -eq "Paused") { "Paused" } else { $node.State.ToString() }
        $nodeLine = "  $statusSymbol $($node.Name.PadRight(20)) $($stateDetail.PadRight(12)) VMs: $vmCount"
        Write-OutputColor "  │$($nodeLine.PadRight(72))│" -color $stateColor
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # CSV STATUS section
    $csvs = Get-ClusterSharedVolume -ErrorAction SilentlyContinue
    if ($csvs) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  CLUSTER SHARED VOLUMES (CSV)".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        foreach ($csv in $csvs) {
            $partition = $csv.SharedVolumeInfo.Partition
            if (-not $partition) {
                Write-OutputColor "  │$("  $($csv.Name) - Partition info unavailable".PadRight(72))│" -color "Warning"
                continue
            }

            $totalGB = [math]::Round($partition.Size / 1GB, 0)
            $freeGB = [math]::Round($partition.FreeSpace / 1GB, 0)
            $usedGB = $totalGB - $freeGB
            $usedPct = if ($totalGB -gt 0) { [math]::Round(($usedGB / $totalGB) * 100, 0) } else { 0 }

            # Create mini progress bar
            $barWidth = 10
            $filled = [math]::Round(($usedPct / 100) * $barWidth)
            $empty = $barWidth - $filled
            $bar = "[" + ("█" * $filled) + ("░" * $empty) + "]"

            $pctColor = if ($usedPct -lt 70) { "Success" } elseif ($usedPct -lt 90) { "Warning" } else { "Error" }
            $csvName = if ($csv.Name.Length -gt 20) { $csv.Name.Substring(0,17) + "..." } else { $csv.Name.PadRight(20) }

            $csvLine = "  $csvName ${usedGB}GB/${totalGB}GB (${usedPct}%) $bar"
            Write-OutputColor "  │$($csvLine.PadRight(72))│" -color $pctColor
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
    }

    # CLUSTER RESOURCES section
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  KEY RESOURCES".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    # Show critical resources
    $resources = Get-ClusterResource -ErrorAction SilentlyContinue | Where-Object { $_.ResourceType -match "Network Name|IP Address|File Share Witness|Disk Witness" }
    foreach ($res in $resources | Select-Object -First 5) {
        $resStatus = if ($res.State -eq "Online") { "[●]" } else { "[○]" }
        $resColor = if ($res.State -eq "Online") { "Success" } else { "Error" }
        $resName = if ($res.Name.Length -gt 40) { $res.Name.Substring(0,37) + "..." } else { $res.Name.PadRight(40) }
        $resLine = "  $resStatus $resName $($res.State)"
        Write-OutputColor "  │$($resLine.PadRight(72))│" -color $resColor
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # LIVE MIGRATION section
    $migrationSettings = Get-VMHost -ErrorAction SilentlyContinue | Select-Object MaximumVirtualMachineMigrations, VirtualMachineMigrationEnabled
    if ($migrationSettings) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  LIVE MIGRATION".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        $migEnabled = if ($migrationSettings.VirtualMachineMigrationEnabled) { "Enabled" } else { "Disabled" }
        $migColor = if ($migrationSettings.VirtualMachineMigrationEnabled) { "Success" } else { "Warning" }
        Write-OutputColor "  │$("  Status: $migEnabled".PadRight(72))│" -color $migColor
        Write-OutputColor "  │$("  Max Simultaneous Migrations: $($migrationSettings.MaximumVirtualMachineMigrations)".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }

    Add-SessionChange -Category "Cluster" -Description "Viewed cluster dashboard for $($cluster.Name)"
}

# Function to drain a cluster node
function Start-ClusterNodeDrain {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                      DRAIN CLUSTER NODE").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $cluster = Get-Cluster -ErrorAction SilentlyContinue

    if (-not $cluster) {
        Write-OutputColor "  Not connected to a cluster." -color "Error"
        return
    }

    $nodes = @(Get-ClusterNode -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Up" })
    if ($nodes.Count -eq 0) {
        Write-OutputColor "  No nodes available to drain." -color "Warning"
        return
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT NODE TO DRAIN".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $index = 1
    $nodeMap = @{}
    foreach ($node in $nodes) {
        $vmCount = @(Get-ClusterGroup -Cluster $cluster.Name |
            Where-Object { $_.GroupType -eq 'VirtualMachine' -and $_.OwnerNode -eq $node.Name }).Count
        $nodeLine = "[$index]  $($node.Name.PadRight(30)) VMs: $vmCount"
        Write-OutputColor "  │  $($nodeLine.PadRight(68))│" -color "Success"
        $nodeMap["$index"] = $node.Name
        $index++
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Enter node number"
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    if (-not $nodeMap.ContainsKey($choice)) {
        Write-OutputColor "  Invalid selection." -color "Error"
        return
    }

    $selectedNode = $nodeMap[$choice]

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Draining node: $selectedNode" -color "Warning"
    Write-OutputColor "  This will migrate all VMs to other nodes and pause the node." -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Continue with drain?")) { return }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Starting node drain..." -color "Info"

    try {
        Suspend-ClusterNode -Name $selectedNode -Drain -Wait -ErrorAction Stop

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Node '$selectedNode' has been drained and paused." -color "Success"
        Add-SessionChange -Category "Cluster" -Description "Drained node $selectedNode"
    }
    catch {
        Write-OutputColor "  Error draining node: $_" -color "Error"
    }
}

# Function to resume a paused cluster node
function Resume-ClusterNodeFromDrain {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     RESUME CLUSTER NODE").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $cluster = Get-Cluster -ErrorAction SilentlyContinue

    if (-not $cluster) {
        Write-OutputColor "  Not connected to a cluster." -color "Error"
        return
    }

    $pausedNodes = @(Get-ClusterNode -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Paused" })
    if ($pausedNodes.Count -eq 0) {
        Write-OutputColor "  No paused nodes to resume." -color "Info"
        return
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  PAUSED NODES".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $index = 1
    $nodeMap = @{}
    foreach ($node in $pausedNodes) {
        $nodeLine = "[$index]  $($node.Name.PadRight(50)) PAUSED"
        Write-OutputColor "  │  $($nodeLine.PadRight(68))│" -color "Warning"
        $nodeMap["$index"] = $node.Name
        $index++
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Enter node number to resume"
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    if (-not $nodeMap.ContainsKey($choice)) {
        Write-OutputColor "  Invalid selection." -color "Error"
        return
    }

    $selectedNode = $nodeMap[$choice]

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Failback option: Move VMs back to this node after resuming?" -color "Info"
    $failback = Confirm-UserAction -Message "Enable failback?"

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Resuming node: $selectedNode..." -color "Info"

    try {
        if ($failback) {
            Resume-ClusterNode -Name $selectedNode -Failback Immediate -ErrorAction Stop
        } else {
            Resume-ClusterNode -Name $selectedNode -ErrorAction Stop
        }

        Write-OutputColor "  Node '$selectedNode' has been resumed." -color "Success"
        Add-SessionChange -Category "Cluster" -Description "Resumed node $selectedNode (failback: $failback)"
    }
    catch {
        Write-OutputColor "  Error resuming node: $_" -color "Error"
    }
}

# Function to show CSV health
function Show-CSVHealth {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       CSV HEALTH STATUS").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $cluster = Get-Cluster -ErrorAction SilentlyContinue

    if (-not $cluster) {
        Write-OutputColor "  Not connected to a cluster." -color "Error"
        return
    }

    $csvs = Get-ClusterSharedVolume -ErrorAction SilentlyContinue
    if (-not $csvs) {
        Write-OutputColor "  No Cluster Shared Volumes found." -color "Warning"
        return
    }

    foreach ($csv in $csvs) {
        $partition = $csv.SharedVolumeInfo.Partition
        $redirected = $csv.SharedVolumeInfo.FaultState
        if (-not $partition) {
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Warning"
            Write-OutputColor "  │$("  $($csv.Name) - Partition info unavailable".PadRight(72))│" -color "Warning"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Warning"
            continue
        }

        $totalGB = [math]::Round($partition.Size / 1GB, 1)
        $freeGB = [math]::Round($partition.FreeSpace / 1GB, 1)
        $usedGB = $totalGB - $freeGB
        $usedPct = if ($totalGB -gt 0) { [math]::Round(($usedGB / $totalGB) * 100, 1) } else { 0 }

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  $($csv.Name)".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        # State
        $stateColor = if ($csv.State -eq "Online") { "Success" } else { "Error" }
        Write-OutputColor "  │$("  State: $($csv.State)".PadRight(72))│" -color $stateColor

        # Owner
        Write-OutputColor "  │$("  Owner Node: $($csv.OwnerNode)".PadRight(72))│" -color "Info"

        # Space
        $spaceColor = if ($usedPct -lt 70) { "Success" } elseif ($usedPct -lt 90) { "Warning" } else { "Error" }
        Write-OutputColor "  │$("  Space: ${usedGB}GB used / ${totalGB}GB total (${usedPct}% used)".PadRight(72))│" -color $spaceColor
        Write-OutputColor "  │$("  Free: ${freeGB}GB".PadRight(72))│" -color $spaceColor

        # Redirected I/O warning
        if ($redirected -ne "NoRedirectedAccess") {
            Write-OutputColor "  │$("  ⚠ REDIRECTED I/O ACTIVE - Performance degraded!".PadRight(72))│" -color "Error"
        }

        # Low space warning
        if ($usedPct -ge 90) {
            Write-OutputColor "  │$("  ⚠ LOW SPACE WARNING - Consider expanding or cleaning up".PadRight(72))│" -color "Error"
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
    }

    Add-SessionChange -Category "Cluster" -Description "Viewed CSV health status"
}

# Function to show cluster operations submenu
function Show-ClusterOperationsMenu {
    while ($true) {
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                      CLUSTER OPERATIONS").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-MenuItem -Text "[1]  Cluster Dashboard"
        Write-MenuItem -Text "[2]  Drain Node (Pause + Migrate VMs)"
        Write-MenuItem -Text "[3]  Resume Node from Drain"
        Write-MenuItem -Text "[4]  CSV Health Status"
        Write-MenuItem -Text "[5]  Cluster Readiness Check"
        Write-MenuItem -Text "[6]  CSV Validation"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" {
                Show-ClusterDashboard
                Write-PressEnter
            }
            "2" {
                Start-ClusterNodeDrain
                Write-PressEnter
            }
            "3" {
                Resume-ClusterNodeFromDrain
                Write-PressEnter
            }
            "4" {
                Show-CSVHealth
                Write-PressEnter
            }
            "5" {
                $null = Test-ClusterReadiness
                Write-PressEnter
            }
            "6" {
                Initialize-ClusterCSV
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

# ============================================================================
# CLUSTER READINESS & CSV VALIDATION (v1.8.0)
# ============================================================================

# Pre-flight cluster readiness check
function Test-ClusterReadiness {
    $cluster = Get-Cluster -ErrorAction SilentlyContinue
    if (-not $cluster) {
        Write-OutputColor "  Not a member of any cluster." -color "Warning"
        return @{ Ready = $false; Checks = @() }
    }

    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    CLUSTER READINESS CHECK").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $checks = @()

    # 1. All nodes online
    $nodes = Get-ClusterNode -ErrorAction SilentlyContinue
    $nodesUp = @($nodes | Where-Object { $_.State -eq "Up" })
    $nodesDown = @($nodes | Where-Object { $_.State -ne "Up" })
    $nodeOK = ($nodesDown.Count -eq 0)
    $checks += @{ Check = "All Nodes Online"; Status = if ($nodeOK) { "OK" } else { "FAIL" }; Detail = "$($nodesUp.Count)/$($nodes.Count) nodes up$(if ($nodesDown.Count -gt 0) { ' (down: ' + ($nodesDown.Name -join ', ') + ')' })" }

    # 2. Quorum healthy
    $quorum = Get-ClusterQuorum -ErrorAction SilentlyContinue
    $quorumOK = ($null -ne $quorum)
    $quorumDetail = if ($quorum) { "Type: $($quorum.QuorumType)" } else { "Unable to query" }
    $checks += @{ Check = "Quorum Healthy"; Status = if ($quorumOK) { "OK" } else { "FAIL" }; Detail = $quorumDetail }

    # 3. CSVs online (no redirected I/O)
    $csvs = Get-ClusterSharedVolume -ErrorAction SilentlyContinue
    $csvOnline = $true
    $csvRedirected = $false
    if ($csvs) {
        foreach ($csv in $csvs) {
            if ($csv.State -ne "Online") { $csvOnline = $false }
            $csvState = $csv | Get-ClusterSharedVolumeState -ErrorAction SilentlyContinue
            if ($csvState -and $csvState.FileSystemRedirectedIOReason -ne "NotRedirected") { $csvRedirected = $true }
        }
    }
    $csvOK = $csvOnline -and -not $csvRedirected
    $csvDetail = if (-not $csvs) { "No CSVs found" } elseif (-not $csvOnline) { "Some CSVs offline" } elseif ($csvRedirected) { "Redirected I/O detected" } else { "$($csvs.Count) CSV(s) online, no redirected I/O" }
    $checks += @{ Check = "CSVs Online"; Status = if ($csvOK) { "OK" } elseif ($csvRedirected) { "WARN" } else { "FAIL" }; Detail = $csvDetail }

    # 4. Cluster networks up
    $networks = Get-ClusterNetwork -ErrorAction SilentlyContinue
    $networksUp = @($networks | Where-Object { $_.State -eq "Up" })
    $netOK = ($networksUp.Count -eq $networks.Count)
    $checks += @{ Check = "Cluster Networks"; Status = if ($netOK) { "OK" } else { "WARN" }; Detail = "$($networksUp.Count)/$($networks.Count) networks up" }

    # Display results
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  READINESS CHECKS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $allOK = $true
    foreach ($c in $checks) {
        $icon = switch ($c.Status) { "OK" { "[OK]" }; "WARN" { "[!!]" }; "FAIL" { "[XX]" }; default { "[??]" } }
        $color = switch ($c.Status) { "OK" { "Success" }; "WARN" { "Warning" }; "FAIL" { "Error" }; default { "Info" } }
        if ($c.Status -ne "OK") { $allOK = $false }
        $line = "  $icon $($c.Check.PadRight(22)) $($c.Detail)"
        Write-OutputColor "  │$($line.PadRight(72))│" -color $color
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($allOK) {
        Write-OutputColor "  Cluster is READY. All checks passed." -color "Success"
    }
    else {
        Write-OutputColor "  Cluster has issues. Review checks above." -color "Warning"
    }

    Add-SessionChange -Category "Cluster" -Description "Cluster readiness check ($(if ($allOK) { 'passed' } else { 'issues found' }))"

    return @{ Ready = $allOK; Checks = $checks }
}

# Validate and report on existing CSVs
function Initialize-ClusterCSV {
    $csvs = Get-ClusterSharedVolume -ErrorAction SilentlyContinue
    if (-not $csvs) {
        Write-OutputColor "  No Cluster Shared Volumes found." -color "Warning"
        return
    }

    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       CSV VALIDATION").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $issues = 0
    foreach ($csv in $csvs) {
        $partition = $csv.SharedVolumeInfo.Partition
        if (-not $partition) {
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Warning"
            Write-OutputColor "  │$("  $($csv.Name) - Partition info unavailable".PadRight(72))│" -color "Warning"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Warning"
            $issues++
            continue
        }
        $totalGB = [math]::Round($partition.Size / 1GB, 0)
        $freeGB = [math]::Round($partition.FreeSpace / 1GB, 0)
        $usedPct = if ($totalGB -gt 0) { [math]::Round(($totalGB - $freeGB) / $totalGB * 100, 0) } else { 0 }
        $fs = $partition.FileSystem

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  $($csv.Name)".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        # State
        $stateColor = if ($csv.State -eq "Online") { "Success" } else { "Error"; $issues++ }
        Write-OutputColor "  │$("  State: $($csv.State)  |  Owner: $($csv.OwnerNode)".PadRight(72))│" -color $stateColor

        # Space
        $spaceColor = if ($usedPct -lt 70) { "Success" } elseif ($usedPct -lt 90) { "Warning" } else { "Error"; $issues++ }
        Write-OutputColor "  │$("  Size: ${totalGB}GB  |  Free: ${freeGB}GB  |  Used: ${usedPct}%  |  FS: $fs".PadRight(72))│" -color $spaceColor

        # Redirected I/O
        $csvState = $csv | Get-ClusterSharedVolumeState -ErrorAction SilentlyContinue
        if ($csvState -and $csvState.FileSystemRedirectedIOReason -ne "NotRedirected") {
            Write-OutputColor "  │$("  WARNING: Redirected I/O - $($csvState.FileSystemRedirectedIOReason)".PadRight(72))│" -color "Error"
            $issues++
        }
        else {
            Write-OutputColor "  │$("  I/O: Direct (no redirection)".PadRight(72))│" -color "Success"
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
    }

    $summaryColor = if ($issues -eq 0) { "Success" } else { "Warning" }
    Write-OutputColor "  CSV VALIDATION: $($csvs.Count) volume(s) checked, $issues issue(s)" -color $summaryColor
    Add-SessionChange -Category "Cluster" -Description "CSV validation: $($csvs.Count) volumes, $issues issues"
}
#endregion