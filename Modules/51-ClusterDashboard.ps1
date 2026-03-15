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
    $clusterTitle = "           CLUSTER DASHBOARD: " + $cluster.Name.ToUpper()
    if ($clusterTitle.Length -gt 72) { $clusterTitle = $clusterTitle.Substring(0, 69) + "..." }
    Write-OutputColor "  ║$($clusterTitle.PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Get cluster nodes
    $nodes = @(Get-ClusterNode -ErrorAction SilentlyContinue)

    # Pre-fetch all cluster VM groups once (avoids N+1 query per node)
    $allVMGroups = @(Get-ClusterGroup -Cluster $cluster.Name -ErrorAction SilentlyContinue |
        Where-Object { $_.GroupType -eq 'VirtualMachine' })

    # NODE STATUS section
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  NODE STATUS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    foreach ($node in $nodes) {
        $vmCount = @($allVMGroups | Where-Object { $_.OwnerNode -eq $node.Name }).Count

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
        $stateDetail = if ($node.State -eq "Paused") { "Paused" } elseif ($node.State) { $node.State.ToString() } else { "Unknown" }
        $nodeLine = "  $statusSymbol $($node.Name.PadRight(20)) $($stateDetail.PadRight(12)) VMs: $vmCount"
        if ($nodeLine.Length -gt 69) { $nodeLine = $nodeLine.Substring(0, 69) + "..." }
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
                $lineStr = "  $($csv.Name) - Partition info unavailable"
                if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
                Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Warning"
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
            $csvName = if ($csv.Name -and $csv.Name.Length -gt 20) { $csv.Name.Substring(0,17) + "..." } elseif ($csv.Name) { $csv.Name.PadRight(20) } else { "(unknown)".PadRight(20) }

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
        $resName = if ($res.Name -and $res.Name.Length -gt 40) { $res.Name.Substring(0,37) + "..." } elseif ($res.Name) { $res.Name.PadRight(40) } else { "(unknown)".PadRight(40) }
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
        Write-OutputColor "  │  $($nodeLine.PadRight(70))│" -color "Success"
        $nodeMap["$index"] = $node.Name
        $index++
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Enter node number"
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    if (-not $nodeMap.ContainsKey($choice)) {
        Write-OutputColor "  Invalid selection. Enter 1-$($nodes.Count) or B." -color "Error"
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
        Clear-MenuCache
    }
    catch {
        Write-RackStackError -Code "RS-4009" -Detail "$_"
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
        Write-OutputColor "  │  $($nodeLine.PadRight(70))│" -color "Warning"
        $nodeMap["$index"] = $node.Name
        $index++
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Enter node number to resume"
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    if (-not $nodeMap.ContainsKey($choice)) {
        Write-OutputColor "  Invalid selection. Enter 1-$($pausedNodes.Count) or B." -color "Error"
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
        Clear-MenuCache
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
            $lineStr = "  $($csv.Name) - Partition info unavailable"
            if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Warning"
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Warning"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Warning"
            continue
        }

        $totalGB = [math]::Round($partition.Size / 1GB, 1)
        $freeGB = [math]::Round($partition.FreeSpace / 1GB, 1)
        $usedGB = $totalGB - $freeGB
        $usedPct = if ($totalGB -gt 0) { [math]::Round(($usedGB / $totalGB) * 100, 1) } else { 0 }

        $lineStr = "  $($csv.Name)"
        if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
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
        if ($global:ReturnToMainMenu) { return }
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
        Write-MenuItem -Text "[7]  Cross-Node Latency Test"
        Write-MenuItem -Text "[8]  Resource Group Status"
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
            "7" {
                Test-ClusterNetworkLatency
                Write-PressEnter
            }
            "8" {
                Show-ClusterResourceStatus
                Write-PressEnter
            }
            "b" { return }
            "B" { return }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-8 or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Function to measure network latency between cluster nodes
function Test-ClusterNetworkLatency {
    try {
        $nodes = @(Get-ClusterNode -ErrorAction Stop)
        if ($nodes.Count -lt 2) {
            Write-OutputColor "  Need at least 2 cluster nodes for latency test" -color "Warning"
            return
        }

        Write-OutputColor "`n  Cluster Node Network Latency:" -color "Info"

        $localNode = $env:COMPUTERNAME
        foreach ($node in $nodes) {
            if ($node.Name -eq $localNode) { continue }
            if ($node.State -ne 'Up') {
                Write-OutputColor "  $localNode -> $($node.Name): Node is $($node.State)" -color "Warning"
                continue
            }

            try {
                $pingResults = Test-Connection -ComputerName $node.Name -Count 4 -ErrorAction Stop
                $avg = [math]::Round(($pingResults | Measure-Object -Property ResponseTime -Average).Average, 1)
                $max = ($pingResults | Measure-Object -Property ResponseTime -Maximum).Maximum

                $color = "Success"
                if ($avg -gt 5) { $color = "Warning" }
                if ($avg -gt 20) { $color = "Error" }

                Write-OutputColor "  $localNode -> $($node.Name): Avg ${avg}ms, Max ${max}ms" -color $color
            } catch {
                Write-OutputColor "  $localNode -> $($node.Name): UNREACHABLE" -color "Error"
            }
        }

        Write-OutputColor "`n  Thresholds: Green <5ms, Yellow 5-20ms, Red >20ms" -color "Info"
    } catch {
        Write-OutputColor "  Could not test cluster latency: $($_.Exception.Message)" -color "Error"
    }
}

# Function to show all cluster resource groups and their status
function Show-ClusterResourceStatus {
    try {
        $groups = Get-ClusterGroup -ErrorAction Stop

        Write-OutputColor "`n  Cluster Resource Groups:" -color "Info"

        $offlineCount = 0
        foreach ($group in $groups) {
            $state = $group.State.ToString()
            $color = switch ($state) {
                'Online'          { "Success" }
                'PartiallyOnline' { "Warning" }
                'Offline'         { "Error"; $offlineCount++ }
                'Failed'          { "Error"; $offlineCount++ }
                default           { "Info" }
            }

            $groupName = if ($group.Name -and $group.Name.Length -gt 30) { $group.Name.Substring(0, 27) + "..." } elseif ($group.Name) { $group.Name } else { "(unknown)" }
            Write-OutputColor "  $groupName  Owner: $($group.OwnerNode)  State: $state" -color $color
        }

        $total = @($groups).Count
        Write-OutputColor "`n  Total: $total groups, $offlineCount offline/failed" -color "Info"
    } catch {
        Write-OutputColor "  Could not get cluster resources: $($_.Exception.Message)" -color "Error"
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
    $nodes = @(Get-ClusterNode -ErrorAction SilentlyContinue)
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
    $csvs = @(Get-ClusterSharedVolume -ErrorAction SilentlyContinue)
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
    $networks = @(Get-ClusterNetwork -ErrorAction SilentlyContinue)
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
        if ($line.Length -gt 69) { $line = $line.Substring(0, 69) + "..." }
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
    $csvs = @(Get-ClusterSharedVolume -ErrorAction SilentlyContinue)
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
            $lineStr = "  $($csv.Name) - Partition info unavailable"
            if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Warning"
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Warning"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Warning"
            $issues++
            continue
        }
        $totalGB = [math]::Round($partition.Size / 1GB, 0)
        $freeGB = [math]::Round($partition.FreeSpace / 1GB, 0)
        $usedPct = if ($totalGB -gt 0) { [math]::Round(($totalGB - $freeGB) / $totalGB * 100, 0) } else { 0 }
        $fs = $partition.FileSystem

        $lineStr = "  $($csv.Name)"
        if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
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

    $summaryColor = if ($issues -eq 0) { "Success" } else { "Error" }
    Write-OutputColor "  CSV VALIDATION: $($csvs.Count) volume(s) checked, $issues issue(s)" -color $summaryColor
    Add-SessionChange -Category "Cluster" -Description "CSV validation: $($csvs.Count) volumes, $issues issues"
}
#endregion