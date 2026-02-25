#region ===== FAILOVER CLUSTERING INSTALLATION =====
# Function to check if Failover Clustering is installed
function Test-FailoverClusteringInstalled {
    if (-not (Test-WindowsServer)) { return $false }
    try {
        $clusterFeature = Get-WindowsFeature -Name Failover-Clustering -ErrorAction SilentlyContinue
        if ($clusterFeature -and $clusterFeature.InstallState -eq "Installed") {
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

# Function to install Failover Clustering feature
function Install-FailoverClusteringFeature {
    Clear-Host
    Write-CenteredOutput "Install Failover Clustering" -color "Info"

    if (Test-FailoverClusteringInstalled) {
        Write-OutputColor "Failover Clustering is already installed." -color "Success"
        return
    }

    Write-OutputColor "Failover Clustering is not currently installed." -color "Info"

    # Pre-flight validation
    $preFlightOK = Show-PreFlightCheck -Feature "FailoverClustering"
    if (-not $preFlightOK) {
        if (-not (Confirm-UserAction -Message "Continue despite blocking issues?")) {
            Write-OutputColor "Installation cancelled." -color "Info"
            return
        }
    }

    Write-OutputColor "Failover Clustering enables high availability by allowing" -color "Info"
    Write-OutputColor "multiple servers to work together as a cluster." -color "Info"
    Write-OutputColor "A reboot may be required after installation." -color "Warning"

    if (-not (Confirm-UserAction -Message "Install Failover Clustering now?")) {
        Write-OutputColor "Failover Clustering installation cancelled." -color "Info"
        return
    }

    try {
        Write-OutputColor "`nInstalling Failover Clustering... This may take several minutes." -color "Info"

        $installResult = Install-WindowsFeatureWithTimeout -FeatureName "Failover-Clustering" -DisplayName "Failover Clustering" -IncludeManagementTools

        if ($installResult.TimedOut) {
            Add-SessionChange -Category "System" -Description "Failover Clustering installation timed out"
            return $false
        }
        elseif ($installResult.Success) {
            Write-OutputColor "`nFailover Clustering installed successfully!" -color "Success"
            $global:RebootNeeded = $true
            Add-SessionChange -Category "System" -Description "Installed Failover Clustering"
            Clear-MenuCache
        }
        else {
            Write-OutputColor "Failover Clustering installation may not have completed successfully." -color "Error"
        }
    }
    catch {
        Write-OutputColor "Failed to install Failover Clustering: $_" -color "Error"
    }
}

# Function to show Cluster Management menu
function Show-ClusterManagementMenu {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       CLUSTER MANAGEMENT").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Check if clustering is installed
    if (-not (Test-FailoverClusteringInstalled)) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  PREREQUISITE MISSING".PadRight(72))│" -color "Warning"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  Failover Clustering is not installed.".PadRight(72))│" -color "Error"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [I] Install Failover Clustering now" -color "Success"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        if ($choice -eq "I" -or $choice -eq "i") {
            Install-FailoverClusteringFeature
            Write-PressEnter
        }
        return
    }

    # Check if node is part of a cluster
    $cluster = Get-Cluster -ErrorAction SilentlyContinue

    if ($cluster) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  CURRENT CLUSTER".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  Name: $($cluster.Name)".PadRight(72))│" -color "Success"
        $nodes = (Get-ClusterNode -ErrorAction SilentlyContinue) -join ", "
        Write-OutputColor "  │$("  Nodes: $nodes".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    } else {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  This server is not part of a cluster.".PadRight(72))│" -color "Warning"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CLUSTER OPTIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem -Text "[1]  Create New Cluster"
    Write-MenuItem -Text "[2]  Join Existing Cluster"
    Write-MenuItem -Text "[3]  Validate Cluster Configuration"
    Write-MenuItem -Text "[4]  Manage Cluster Shared Volumes (CSV)"
    Write-MenuItem -Text "[5]  Configure Live Migration"
    Write-MenuItem -Text "[6]  Configure Quorum/Witness"
    Write-MenuItem -Text "[7]  Show Cluster Status"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    switch ($choice) {
        "1" { New-ClusterWizard }
        "2" { Add-NodeToCluster }
        "3" { Test-ClusterValidation }
        "4" { Edit-ClusterSharedVolume }
        "5" { Set-LiveMigrationSettings }
        "6" { Set-ClusterQuorum }
        "7" { Show-ClusterStatus }
    }
}

# Function to create a new cluster
function New-ClusterWizard {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                      CREATE NEW CLUSTER").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Check if already in a cluster
    $existingCluster = Get-Cluster -ErrorAction SilentlyContinue
    if ($existingCluster) {
        Write-OutputColor "  This server is already part of cluster: $($existingCluster.Name)" -color "Warning"
        Write-OutputColor "  Remove from cluster first before creating a new one." -color "Info"
        return
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CLUSTER CONFIGURATION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Enter the details for the new cluster.".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  All nodes must have Failover Clustering installed.".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Get cluster name
    $clusterName = Read-Host "  Enter cluster name (e.g., HV-Cluster)"
    $navResult = Test-NavigationCommand -UserInput $clusterName
    if ($navResult.ShouldReturn) { return }
    if (-not $clusterName) {
        Write-OutputColor "  Cluster name is required." -color "Error"
        return
    }

    # Get cluster IP
    $clusterIP = Read-Host "  Enter cluster IP address (e.g., 192.168.1.100)"
    $navResult = Test-NavigationCommand -UserInput $clusterIP
    if ($navResult.ShouldReturn) { return }
    if (-not (Test-ValidIPAddress -IPAddress $clusterIP)) {
        Write-OutputColor "  Invalid IP address." -color "Error"
        return
    }

    # Get nodes
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enter node names (comma-separated, include this server):" -color "Info"
    Write-OutputColor "  Example: HV1,HV2,HV3" -color "Info"
    $nodesInput = Read-Host "  Nodes"
    $navResult = Test-NavigationCommand -UserInput $nodesInput
    if ($navResult.ShouldReturn) { return }

    $nodes = @($nodesInput -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    if ($nodes.Count -lt 1) {
        Write-OutputColor "  At least one node is required." -color "Error"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CLUSTER SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Name: $clusterName".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  IP: $clusterIP".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Nodes: $($nodes -join ', ')".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Option to validate first
    Write-OutputColor "  [V] Validate cluster configuration first (recommended)" -color "Info"
    Write-OutputColor "  [C] Create cluster without validation" -color "Warning"
    Write-OutputColor "  [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $action = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $action
    if ($navResult.ShouldReturn) { return }

    if ($action -eq "V" -or $action -eq "v") {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Running cluster validation (this may take several minutes)..." -color "Info"
        try {
            Test-Cluster -Node $nodes -ReportName "ClusterValidation_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            Write-OutputColor "  Validation complete. Check the report for any issues." -color "Success"
            Write-OutputColor "" -color "Info"
            if (-not (Confirm-UserAction -Message "Proceed with cluster creation?")) {
                return
            }
        }
        catch {
            Write-OutputColor "  Validation failed: $_" -color "Error"
            if (-not (Confirm-UserAction -Message "Proceed anyway?")) {
                return
            }
        }
    }
    elseif ($action -ne "C" -and $action -ne "c") {
        return
    }

    # Create the cluster
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Creating cluster..." -color "Info"

    try {
        New-Cluster -Name $clusterName -Node $nodes -StaticAddress $clusterIP -ErrorAction Stop
        Write-OutputColor "  Cluster '$clusterName' created successfully!" -color "Success"
        Add-SessionChange -Category "Cluster" -Description "Created cluster $clusterName with nodes: $($nodes -join ', ')"
    }
    catch {
        Write-OutputColor "  Failed to create cluster: $_" -color "Error"
    }
}

# Function to join an existing cluster
function Add-NodeToCluster {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     JOIN EXISTING CLUSTER").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Check if already in a cluster
    $existingCluster = Get-Cluster -ErrorAction SilentlyContinue
    if ($existingCluster) {
        Write-OutputColor "  This server is already part of cluster: $($existingCluster.Name)" -color "Warning"
        return
    }

    $clusterName = Read-Host "  Enter cluster name to join"
    $navResult = Test-NavigationCommand -UserInput $clusterName
    if ($navResult.ShouldReturn) { return }

    if (-not $clusterName) {
        Write-OutputColor "  Cluster name is required." -color "Error"
        return
    }

    Write-OutputColor "" -color "Info"
    if (-not (Confirm-UserAction -Message "Add this server to cluster '$clusterName'?")) {
        return
    }

    try {
        Write-OutputColor "  Adding node to cluster..." -color "Info"
        Add-ClusterNode -Cluster $clusterName -Name $env:COMPUTERNAME -ErrorAction Stop
        Write-OutputColor "  Successfully joined cluster '$clusterName'!" -color "Success"
        Add-SessionChange -Category "Cluster" -Description "Joined cluster $clusterName"
    }
    catch {
        Write-OutputColor "  Failed to join cluster: $_" -color "Error"
    }
}

# Function to run cluster validation
function Test-ClusterValidation {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    CLUSTER VALIDATION").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Enter node names to validate (comma-separated):" -color "Info"
    Write-OutputColor "  Leave blank to validate this server only." -color "Info"
    Write-OutputColor "" -color "Info"

    $nodesInput = Read-Host "  Nodes"

    $nodes = if ($nodesInput) {
        @($nodesInput -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    } else {
        @($env:COMPUTERNAME)
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Running cluster validation on: $($nodes -join ', ')" -color "Info"
    Write-OutputColor "  This may take several minutes..." -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $reportPath = "$($script:TempPath)\ClusterValidation_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Test-Cluster -Node $nodes -ReportName $reportPath
        Write-OutputColor "  Validation complete!" -color "Success"
        Write-OutputColor "  Report saved to: $reportPath.htm" -color "Info"
    }
    catch {
        Write-OutputColor "  Validation error: $_" -color "Error"
    }
}

# Function to manage Cluster Shared Volumes
function Edit-ClusterSharedVolume {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                  CLUSTER SHARED VOLUMES (CSV)").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Check if in a cluster
    try {
        $null = Get-Cluster -ErrorAction Stop
    }
    catch {
        Write-OutputColor "  This server is not part of a cluster." -color "Warning"
        return
    }

    # Show current CSVs
    $csvs = @(Get-ClusterSharedVolume -ErrorAction SilentlyContinue)
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CURRENT CLUSTER SHARED VOLUMES".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    if ($csvs.Count -gt 0) {
        foreach ($csv in $csvs) {
            $state = $csv.State
            $color = if ($state -eq "Online") { "Success" } else { "Warning" }
            $info = $csv.SharedVolumeInfo
            $freeGB = if ($info) { [math]::Round($info.Partition.FreeSpace / 1GB, 1) } else { "N/A" }
            $totalGB = if ($info) { [math]::Round($info.Partition.Size / 1GB, 1) } else { "N/A" }
            Write-OutputColor "  │$("  $($csv.Name) | $state | Free: $freeGB GB / $totalGB GB".PadRight(72))│" -color $color
        }
    }
    else {
        Write-OutputColor "  │$("  No Cluster Shared Volumes configured".PadRight(72))│" -color "Warning"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  OPTIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem -Text "[1]  Add Disk to CSV"
    Write-MenuItem -Text "[2]  Remove Disk from CSV"
    Write-MenuItem -Text "[3]  Show Available Cluster Disks"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    switch ($choice) {
        "1" {
            # Show available cluster disks
            $clusterDisks = @(Get-ClusterResource | Where-Object { $_.ResourceType -eq "Physical Disk" -and $_.OwnerGroup -ne "Cluster Shared Volume" })
            if ($clusterDisks.Count -eq 0) {
                Write-OutputColor "  No available cluster disks to add." -color "Warning"
                return
            }

            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Available cluster disks:" -color "Info"
            $idx = 1
            foreach ($disk in $clusterDisks) {
                Write-OutputColor "  [$idx] $($disk.Name) - $($disk.State)" -color "Info"
                $idx++
            }
            Write-OutputColor "" -color "Info"

            $diskChoice = Read-Host "  Select disk number"
            if ($diskChoice -match '^\d+$') {
                $selIdx = [int]$diskChoice - 1
                if ($selIdx -ge 0 -and $selIdx -lt $clusterDisks.Count) {
                    $selectedDisk = $clusterDisks[$selIdx]
                    try {
                        Add-ClusterSharedVolume -Name $selectedDisk.Name -ErrorAction Stop
                        Write-OutputColor "  Added $($selectedDisk.Name) to Cluster Shared Volumes." -color "Success"
                        Add-SessionChange -Category "Cluster" -Description "Added $($selectedDisk.Name) to CSV"
                    }
                    catch {
                        Write-OutputColor "  Failed: $_" -color "Error"
                    }
                }
            }
        }
        "2" {
            if ($csvs.Count -eq 0) {
                Write-OutputColor "  No CSVs to remove." -color "Warning"
                return
            }

            Write-OutputColor "" -color "Info"
            $idx = 1
            foreach ($csv in $csvs) {
                Write-OutputColor "  [$idx] $($csv.Name)" -color "Info"
                $idx++
            }
            Write-OutputColor "" -color "Info"

            $csvChoice = Read-Host "  Select CSV number to remove"
            if ($csvChoice -match '^\d+$') {
                $selIdx = [int]$csvChoice - 1
                if ($selIdx -ge 0 -and $selIdx -lt $csvs.Count) {
                    $selectedCSV = $csvs[$selIdx]
                    if (Confirm-UserAction -Message "Remove $($selectedCSV.Name) from CSV?") {
                        try {
                            Remove-ClusterSharedVolume -Name $selectedCSV.Name -ErrorAction Stop
                            Write-OutputColor "  Removed $($selectedCSV.Name) from CSV." -color "Success"
                        }
                        catch {
                            Write-OutputColor "  Failed: $_" -color "Error"
                        }
                    }
                }
            }
        }
        "3" {
            $allDisks = Get-ClusterResource | Where-Object { $_.ResourceType -eq "Physical Disk" }
            if ($allDisks) {
                Write-OutputColor "" -color "Info"
                foreach ($disk in $allDisks) {
                    $inCSV = if ($disk.OwnerGroup -eq "Cluster Shared Volume") { "[CSV]" } else { "" }
                    Write-OutputColor "  $($disk.Name) - $($disk.State) $inCSV" -color "Info"
                }
            } else {
                Write-OutputColor "  No cluster disks found." -color "Warning"
            }
        }
    }
}

# Function to configure Live Migration settings
function Set-LiveMigrationSettings {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                   LIVE MIGRATION SETTINGS").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Get current settings - requires Hyper-V
    $vmHost = Get-VMHost -ErrorAction SilentlyContinue
    if (-not $vmHost) {
        Write-OutputColor "  Hyper-V is required for Live Migration configuration." -color "Warning"
        Write-OutputColor "" -color "Info"
        if (-not (Test-HyperVInstalled)) {
            if (Confirm-UserAction -Message "Install Hyper-V now?") {
                Install-HyperVRole
                if (-not (Test-HyperVInstalled)) {
                    Write-OutputColor "  Hyper-V requires a reboot. Please try again after rebooting." -color "Warning"
                }
            }
        } else {
            Write-OutputColor "  Hyper-V is installed but not accessible. A reboot may be required." -color "Warning"
        }
        return
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CURRENT SETTINGS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Live Migration Enabled: $($vmHost.VirtualMachineMigrationEnabled)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Simultaneous Migrations: $($vmHost.MaximumVirtualMachineMigrations)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Authentication: $($vmHost.VirtualMachineMigrationAuthenticationType)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Performance Option: $($vmHost.VirtualMachineMigrationPerformanceOption)".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  OPTIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem -Text "[1]  Enable Live Migration"
    Write-MenuItem -Text "[2]  Set Simultaneous Migrations"
    Write-MenuItem -Text "[3]  Set Authentication Type"
    Write-MenuItem -Text "[4]  Set Performance Option"
    Write-MenuItem -Text "[5]  Configure Allowed Networks"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    switch ($choice) {
        "1" {
            try {
                Enable-VMMigration -ErrorAction Stop
                Write-OutputColor "  Live Migration enabled." -color "Success"
                Add-SessionChange -Category "Hyper-V" -Description "Enabled Live Migration"
            }
            catch {
                Write-OutputColor "  Failed: $_" -color "Error"
            }
        }
        "2" {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Current: $($vmHost.MaximumVirtualMachineMigrations)" -color "Info"
            $newCount = Read-Host "  Enter number of simultaneous migrations (1-10)"
            if ($newCount -match '^\d+$' -and [int]$newCount -ge 1 -and [int]$newCount -le 10) {
                try {
                    Set-VMHost -MaximumVirtualMachineMigrations ([int]$newCount) -ErrorAction Stop
                    Write-OutputColor "  Set to $newCount simultaneous migrations." -color "Success"
                    Add-SessionChange -Category "Hyper-V" -Description "Set Live Migration to $newCount simultaneous"
                }
                catch {
                    Write-OutputColor "  Failed: $_" -color "Error"
                }
            } else {
                Write-OutputColor "  Invalid number." -color "Error"
            }
        }
        "3" {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  [1] CredSSP (requires delegation setup)" -color "Info"
            Write-OutputColor "  [2] Kerberos (recommended for domain environments)" -color "Info"
            Write-OutputColor "" -color "Info"
            $authChoice = Read-Host "  Select authentication type"
            $authType = switch ($authChoice) {
                "1" { "CredSSP" }
                "2" { "Kerberos" }
                default { $null }
            }
            if ($authType) {
                try {
                    Set-VMHost -VirtualMachineMigrationAuthenticationType $authType -ErrorAction Stop
                    Write-OutputColor "  Authentication set to $authType." -color "Success"
                    Add-SessionChange -Category "Hyper-V" -Description "Set Live Migration auth to $authType"
                }
                catch {
                    Write-OutputColor "  Failed: $_" -color "Error"
                }
            }
        }
        "4" {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  [1] TCP/IP (compatible, slower)" -color "Info"
            Write-OutputColor "  [2] Compression (balanced)" -color "Info"
            Write-OutputColor "  [3] SMB (fastest, requires SMB Direct)" -color "Info"
            Write-OutputColor "" -color "Info"
            $perfChoice = Read-Host "  Select performance option"
            $perfOption = switch ($perfChoice) {
                "1" { "TCPIP" }
                "2" { "Compression" }
                "3" { "SMB" }
                default { $null }
            }
            if ($perfOption) {
                try {
                    Set-VMHost -VirtualMachineMigrationPerformanceOption $perfOption -ErrorAction Stop
                    Write-OutputColor "  Performance option set to $perfOption." -color "Success"
                    Add-SessionChange -Category "Hyper-V" -Description "Set Live Migration performance to $perfOption"
                }
                catch {
                    Write-OutputColor "  Failed: $_" -color "Error"
                }
            }
        }
        "5" {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Current allowed networks for Live Migration:" -color "Info"
            $networks = $vmHost.VirtualMachineMigrationNetworks
            if ($networks) {
                foreach ($net in $networks) {
                    Write-OutputColor "    $net" -color "Info"
                }
            } else {
                Write-OutputColor "    Any network (not restricted)" -color "Warning"
            }
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Enter subnet to add (e.g., 192.168.1.0/24) or leave blank:" -color "Info"
            $newNet = Read-Host "  Subnet"
            if ($newNet) {
                try {
                    Add-VMMigrationNetwork -Subnet $newNet -ErrorAction Stop
                    Write-OutputColor "  Added $newNet to allowed networks." -color "Success"
                }
                catch {
                    Write-OutputColor "  Failed: $_" -color "Error"
                }
            }
        }
    }
}

# Function to configure cluster quorum
function Set-ClusterQuorum {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     CLUSTER QUORUM SETTINGS").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $cluster = Get-Cluster -ErrorAction Stop
        $quorum = Get-ClusterQuorum -ErrorAction Stop
    }
    catch {
        Write-OutputColor "  This server is not part of a cluster." -color "Warning"
        return
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CURRENT QUORUM CONFIGURATION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Cluster: $($cluster.Name)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Quorum Type: $($quorum.QuorumType)".PadRight(72))│" -color "Info"
    if ($quorum.QuorumResource) {
        Write-OutputColor "  │$("  Quorum Resource: $($quorum.QuorumResource.Name)".PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  QUORUM OPTIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem -Text "[1]  Node Majority (no witness)"
    Write-MenuItem -Text "[2]  Node and Disk Majority"
    Write-MenuItem -Text "[3]  Node and File Share Majority"
    Write-MenuItem -Text "[4]  Cloud Witness (Azure)"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    switch ($choice) {
        "1" {
            try {
                Set-ClusterQuorum -NodeMajority -ErrorAction Stop
                Write-OutputColor "  Quorum set to Node Majority." -color "Success"
                Add-SessionChange -Category "Cluster" -Description "Set quorum to Node Majority"
            }
            catch {
                Write-OutputColor "  Failed: $_" -color "Error"
            }
        }
        "2" {
            $disks = @(Get-ClusterResource | Where-Object { $_.ResourceType -eq "Physical Disk" })
            if ($disks.Count -eq 0) {
                Write-OutputColor "  No cluster disks available for disk witness." -color "Warning"
                Write-OutputColor "  Add a shared disk to the cluster first, or use File Share" -color "Info"
                Write-OutputColor "  Witness [3] or Cloud Witness [4] instead." -color "Info"
                Write-PressEnter
                return
            }
            Write-OutputColor "" -color "Info"
            $idx = 1
            foreach ($disk in $disks) {
                Write-OutputColor "  [$idx] $($disk.Name)" -color "Info"
                $idx++
            }
            Write-OutputColor "" -color "Info"
            $diskChoice = Read-Host "  Select disk number"
            if ($diskChoice -match '^\d+$') {
                $selIdx = [int]$diskChoice - 1
                if ($selIdx -ge 0 -and $selIdx -lt $disks.Count) {
                    try {
                        Set-ClusterQuorum -NodeAndDiskMajority $disks[$selIdx].Name -ErrorAction Stop
                        Write-OutputColor "  Quorum set to Node and Disk Majority." -color "Success"
                        Add-SessionChange -Category "Cluster" -Description "Set quorum to Node and Disk Majority"
                    }
                    catch {
                        Write-OutputColor "  Failed: $_" -color "Error"
                    }
                }
            }
        }
        "3" {
            Write-OutputColor "" -color "Info"
            $sharePath = Read-Host "  Enter file share path (e.g., \\server\witness)"
            if ($sharePath) {
                try {
                    Set-ClusterQuorum -NodeAndFileShareMajority $sharePath -ErrorAction Stop
                    Write-OutputColor "  Quorum set to Node and File Share Majority." -color "Success"
                    Add-SessionChange -Category "Cluster" -Description "Set quorum to File Share Witness: $sharePath"
                }
                catch {
                    Write-OutputColor "  Failed: $_" -color "Error"
                }
            }
        }
        "4" {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Cloud Witness requires an Azure Storage Account." -color "Info"
            Write-OutputColor "" -color "Info"
            $accountName = Read-Host "  Azure Storage Account Name"
            $accessKeySecure = Read-Host "  Access Key" -AsSecureString
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($accessKeySecure)
            try {
                $accessKey = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            } finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
            if ($accountName -and $accessKey) {
                try {
                    Set-ClusterQuorum -CloudWitness -AccountName $accountName -AccessKey $accessKey -ErrorAction Stop
                    Write-OutputColor "  Quorum set to Cloud Witness." -color "Success"
                    Add-SessionChange -Category "Cluster" -Description "Set quorum to Cloud Witness"
                }
                catch {
                    Write-OutputColor "  Failed: $_" -color "Error"
                }
                finally {
                    $accessKey = $null
                }
            }
        }
    }
}

# Function to show cluster status
function Show-ClusterStatus {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                        CLUSTER STATUS").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $cluster = Get-Cluster -ErrorAction Stop
    }
    catch {
        Write-OutputColor "  This server is not part of a cluster." -color "Warning"
        Write-PressEnter
        return
    }

    # Cluster info
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CLUSTER: $($cluster.Name)".PadRight(72))│" -color "Success"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Nodes
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  NODES".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    $nodes = Get-ClusterNode -ErrorAction SilentlyContinue
    foreach ($node in $nodes) {
        $color = if ($node.State -eq "Up") { "Success" } else { "Error" }
        Write-OutputColor "  │$("  $($node.Name) - $($node.State)".PadRight(72))│" -color $color
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Resources
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CLUSTER RESOURCES".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    $resources = Get-ClusterResource -ErrorAction SilentlyContinue | Select-Object -First 10
    foreach ($res in $resources) {
        $color = if ($res.State -eq "Online") { "Success" } elseif ($res.State -eq "Offline") { "Warning" } else { "Error" }
        $resName = if ($res.Name.Length -gt 40) { $res.Name.Substring(0,37) + "..." } else { $res.Name }
        Write-OutputColor "  │$("  $resName - $($res.State)".PadRight(72))│" -color $color
    }
    $totalResources = (Get-ClusterResource -ErrorAction SilentlyContinue).Count
    if ($totalResources -gt 10) {
        Write-OutputColor "  │$("  ... and $($totalResources - 10) more resources".PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    Write-PressEnter
}
#endregion