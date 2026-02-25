#region ===== STORAGE BACKENDS =====
# Supported storage backend types
$script:ValidStorageBackends = @("iSCSI", "FC", "S2D", "SMB3", "NVMeoF", "Local")

# Function to show storage backend selection menu
function Show-StorageBackendSelector {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT STORAGE BACKEND".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $current = $script:StorageBackendType
    $backends = @(
        @{ Key = "1"; Name = "iSCSI"; Desc = "iSCSI SAN with MPIO (dual-path A/B)" }
        @{ Key = "2"; Name = "FC"; Desc = "Fibre Channel SAN with MPIO" }
        @{ Key = "3"; Name = "S2D"; Desc = "Storage Spaces Direct (hyperconverged)" }
        @{ Key = "4"; Name = "SMB3"; Desc = "SMB 3.0 file share (NAS/SOFS)" }
        @{ Key = "5"; Name = "NVMeoF"; Desc = "NVMe over Fabrics" }
        @{ Key = "6"; Name = "Local"; Desc = "Local/DAS only (no shared storage)" }
    )

    foreach ($b in $backends) {
        $marker = if ($b.Name -eq $current) { " (current)" } else { "" }
        $color = if ($b.Name -eq $current) { "Success" } else { "Info" }
        Write-MenuItem "[$($b.Key)]  $($b.Name)$marker" -Status $b.Desc -StatusColor $color
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back (keep $current)" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select backend"
    return $choice
}

# Function to change storage backend type
function Set-StorageBackendType {
    $choice = Show-StorageBackendSelector

    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    $map = @{ "1" = "iSCSI"; "2" = "FC"; "3" = "S2D"; "4" = "SMB3"; "5" = "NVMeoF"; "6" = "Local" }

    if ($map.ContainsKey($choice)) {
        $newBackend = $map[$choice]
        $old = $script:StorageBackendType
        $script:StorageBackendType = $newBackend
        Write-OutputColor "  Storage backend changed: $old -> $newBackend" -color "Success"
        Add-SessionChange -Category "Storage" -Description "Changed storage backend from $old to $newBackend"
    }
    else {
        Write-OutputColor "  Invalid selection." -color "Error"
    }
}

# Function to detect current storage backend from system state
function Get-DetectedStorageBackend {
    # Check for active iSCSI sessions
    $iscsiSessions = Get-IscsiSession -ErrorAction SilentlyContinue
    if ($iscsiSessions) { return "iSCSI" }

    # Check for S2D cluster
    try {
        $s2dEnabled = Get-ClusterS2D -ErrorAction SilentlyContinue
        if ($s2dEnabled -and $s2dEnabled.State -eq "Enabled") { return "S2D" }
    }
    catch { }

    # Check for FC HBAs
    $fcAdapters = @(Get-InitiatorPort -ErrorAction SilentlyContinue | Where-Object { $_.ConnectionType -eq "Fibre Channel" })
    if ($fcAdapters.Count -gt 0) {
        # Check if FC disks are present
        $fcDisks = Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq "Fibre Channel" }
        if ($fcDisks) { return "FC" }
    }

    # Check for SMB shares used by cluster
    try {
        $clusterResources = Get-ClusterResource -ErrorAction SilentlyContinue | Where-Object { $_.ResourceType -eq "File Share Witness" }
        $smbDisks = Get-SmbMapping -ErrorAction SilentlyContinue
        if ($smbDisks) { return "SMB3" }
    }
    catch { }

    # Check for NVMe-oF
    $nvmeDisks = @(Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq "NVMe" })
    if ($nvmeDisks.Count -gt 0) { return "NVMeoF" }

    return "Local"
}

# ============================================================================
# FIBRE CHANNEL
# ============================================================================

# Function to show FC HBA information
function Show-FCAdapters {
    Clear-Host
    Write-CenteredOutput "Fibre Channel Adapters" -color "Info"

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  FC HOST BUS ADAPTERS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $fcPorts = @(Get-InitiatorPort -ErrorAction SilentlyContinue | Where-Object { $_.ConnectionType -eq "Fibre Channel" })

    if ($fcPorts.Count -gt 0) {
        $index = 1
        foreach ($port in $fcPorts) {
            $status = $port.OperationalStatus
            $color = if ($status -eq "Online") { "Success" } else { "Warning" }
            $wwpn = $port.PortAddress
            Write-OutputColor "  │$("  [$index] WWPN: $wwpn".PadRight(72))│" -color $color
            Write-OutputColor "  │$("      Status: $status | Node: $($port.NodeAddress)".PadRight(72))│" -color "Info"
            $index++
        }
    }
    else {
        Write-OutputColor "  │$("  No Fibre Channel HBAs detected.".PadRight(72))│" -color "Warning"
        Write-OutputColor "  │$("  Install FC HBA drivers and verify hardware.".PadRight(72))│" -color "Info"
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    # Show FC disks
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  FC DISK MAPPINGS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $fcDisks = Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq "Fibre Channel" }
    if ($fcDisks) {
        foreach ($disk in $fcDisks) {
            $sizeGB = [math]::Round($disk.Size / 1GB, 1)
            $lineStr = "  Disk $($disk.Number): $($disk.FriendlyName) | $sizeGB GB | $($disk.OperationalStatus)"
            if ($lineStr.Length -gt 72) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Success"
        }
    }
    else {
        Write-OutputColor "  │$("  No FC disks found. Check zoning and LUN mapping.".PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

# Function to configure MPIO for FC
function Initialize-MPIOForFC {
    Clear-Host
    Write-CenteredOutput "Initialize MPIO for Fibre Channel" -color "Info"

    if (-not (Test-MPIOInstalled)) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  MPIO (Multipath I/O) is not installed." -color "Error"
        Write-OutputColor "  Install MPIO first from Roles & Features." -color "Info"
        return $false
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  MPIO is installed. Configuring for Fibre Channel..." -color "Info"

    try {
        Write-OutputColor "  Enabling MPIO for Fibre Channel bus type..." -color "Info"
        Enable-MSDSMAutomaticClaim -BusType "Fibre Channel" -ErrorAction Stop
        Write-OutputColor "    FC automatic claim enabled." -color "Success"

        Write-OutputColor "  Setting load balance policy to Round Robin..." -color "Info"
        Set-MSDSMGlobalDefaultLoadBalancePolicy -Policy RR -ErrorAction Stop
        Write-OutputColor "    Load balance policy set." -color "Success"

        Add-SessionChange -Category "System" -Description "Configured MPIO for Fibre Channel"
        return $true
    }
    catch {
        Write-OutputColor "  Failed to configure MPIO for FC: $_" -color "Error"
        return $false
    }
}

# Function to rescan FC storage
function Invoke-FCScan {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Rescanning Fibre Channel storage..." -color "Info"
    try {
        Update-HostStorageCache -ErrorAction SilentlyContinue
        $null = Get-Disk -ErrorAction SilentlyContinue
        Write-OutputColor "  FC storage rescan complete." -color "Success"

        $fcDisks = @(Get-Disk -ErrorAction Stop | Where-Object { $_.BusType -eq "Fibre Channel" })
        Write-OutputColor "  Found $($fcDisks.Count) FC disk(s)." -color "Info"
    }
    catch {
        Write-OutputColor "  Rescan failed: $_" -color "Error"
    }
}

# Function to show FC SAN menu
function Show-FCSANMenu {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    FIBRE CHANNEL SAN MANAGEMENT").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CONFIGURATION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[1]  Show FC Adapters & Disks"
    Write-MenuItem "[2]  Rescan FC Storage"
    Write-MenuItem "[3]  Configure MPIO for FC"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  STATUS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[4]  Show FC/MPIO Status"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  [B] ◄ Back    [M] ◄◄ Server Config" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to run FC SAN menu
function Start-FCSANMenu {
    while ($true) {
        $choice = Show-FCSANMenu

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.Action -eq "exit") { Exit-Script; return }
        if ($navResult.Action -eq "back") { return }

        switch ($choice) {
            "1" { Show-FCAdapters; Write-PressEnter }
            "2" { Invoke-FCScan; Write-PressEnter }
            "3" { $null = Initialize-MPIOForFC; Write-PressEnter }
            "4" { Show-StorageBackendStatus; Write-PressEnter }
            "M" { $global:ReturnToMainMenu = $true; return }
            default {
                Write-OutputColor "Invalid choice. Please enter 1-4, B, or M." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# ============================================================================
# STORAGE SPACES DIRECT (S2D)
# ============================================================================

# Function to check if S2D is available
function Test-S2DAvailable {
    try {
        $cluster = Get-Cluster -ErrorAction SilentlyContinue
        if (-not $cluster) { return $false }
        $s2d = Get-ClusterS2D -ErrorAction SilentlyContinue
        return ($null -ne $s2d)
    }
    catch { return $false }
}

# Function to show S2D status
function Show-S2DStatus {
    Clear-Host
    Write-CenteredOutput "Storage Spaces Direct Status" -color "Info"

    Write-OutputColor "" -color "Info"

    # Cluster check
    $cluster = Get-Cluster -ErrorAction SilentlyContinue
    if (-not $cluster) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  PREREQUISITE: Failover Cluster required for S2D.".PadRight(72))│" -color "Warning"
        Write-OutputColor "  │$("  Create a cluster first, then enable Storage Spaces Direct.".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        return
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  S2D CLUSTER STATUS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Cluster: $($cluster.Name)".PadRight(72))│" -color "Success"

    try {
        $s2d = Get-ClusterS2D -ErrorAction SilentlyContinue
        if ($s2d -and $s2d.State -eq "Enabled") {
            Write-OutputColor "  │$("  S2D State: Enabled".PadRight(72))│" -color "Success"
        }
        else {
            Write-OutputColor "  │$("  S2D State: Not Enabled".PadRight(72))│" -color "Warning"
        }
    }
    catch {
        Write-OutputColor "  │$("  S2D State: Not available (Server 2016+ required)".PadRight(72))│" -color "Warning"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    # Storage Pool
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  STORAGE POOL".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $pool = Get-StoragePool -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -ne "Primordial" -and $_.IsPrimordial -eq $false }
    if ($pool) {
        foreach ($p in $pool) {
            $totalTB = [math]::Round($p.Size / 1TB, 2)
            $allocTB = [math]::Round($p.AllocatedSize / 1TB, 2)
            $healthColor = if ($p.HealthStatus -eq "Healthy") { "Success" } else { "Warning" }
            $lineStr = "  $($p.FriendlyName) | $totalTB TB total | $allocTB TB allocated"
            if ($lineStr.Length -gt 72) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color $healthColor
            Write-OutputColor "  │$("    Health: $($p.HealthStatus) | Operational: $($p.OperationalStatus)".PadRight(72))│" -color "Info"
        }
    }
    else {
        Write-OutputColor "  │$("  No storage pools found.".PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    # Virtual Disks
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  VIRTUAL DISKS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $vDisks = Get-VirtualDisk -ErrorAction SilentlyContinue
    if ($vDisks) {
        foreach ($vd in $vDisks) {
            $sizeGB = [math]::Round($vd.Size / 1GB, 1)
            $healthColor = if ($vd.HealthStatus -eq "Healthy") { "Success" } else { "Warning" }
            $lineStr = "  $($vd.FriendlyName) | $sizeGB GB | $($vd.ResiliencySettingName)"
            if ($lineStr.Length -gt 72) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color $healthColor
        }
    }
    else {
        Write-OutputColor "  │$("  No virtual disks found.".PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    # Physical Disks
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  PHYSICAL DISKS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $pDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.CanPool -eq $true -or $_.Usage -ne "AutoSelect" }
    if ($pDisks) {
        foreach ($pd in $pDisks) {
            $sizeGB = [math]::Round($pd.Size / 1GB, 1)
            $healthColor = if ($pd.HealthStatus -eq "Healthy") { "Success" } else { "Warning" }
            $mediaType = $pd.MediaType
            $lineStr = "  $($pd.FriendlyName) | $sizeGB GB | $mediaType | $($pd.Usage)"
            if ($lineStr.Length -gt 72) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color $healthColor
        }
    }
    else {
        Write-OutputColor "  │$("  No eligible physical disks found.".PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

# Function to enable S2D on a cluster
function Enable-S2DOnCluster {
    Clear-Host
    Write-CenteredOutput "Enable Storage Spaces Direct" -color "Info"

    $cluster = Get-Cluster -ErrorAction SilentlyContinue
    if (-not $cluster) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Failover Cluster is required for Storage Spaces Direct." -color "Error"
        Write-OutputColor "  Create a cluster first via Roles & Features > Failover Clustering." -color "Info"
        return
    }

    # Check if already enabled
    try {
        $s2d = Get-ClusterS2D -ErrorAction SilentlyContinue
        if ($s2d -and $s2d.State -eq "Enabled") {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  S2D is already enabled on cluster $($cluster.Name)." -color "Success"
            return
        }
    }
    catch { }

    # Check eligible disks
    $eligibleDisks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.CanPool -eq $true })
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Cluster: $($cluster.Name)" -color "Info"
    Write-OutputColor "  Eligible disks for pooling: $($eligibleDisks.Count)" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($eligibleDisks.Count -lt 2) {
        Write-OutputColor "  S2D requires at least 2 eligible disks." -color "Error"
        Write-OutputColor "  Current eligible: $($eligibleDisks.Count)" -color "Info"
        return
    }

    Write-OutputColor "  WARNING: Enabling S2D will pool all eligible disks!" -color "Warning"
    Write-OutputColor "  Data on those disks will be destroyed." -color "Warning"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Enable Storage Spaces Direct? This cannot be undone easily.")) {
        Write-OutputColor "  Cancelled." -color "Info"
        return
    }

    try {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Enabling Storage Spaces Direct... (this may take several minutes)" -color "Info"
        Enable-ClusterS2D -Confirm:$false -ErrorAction Stop
        Write-OutputColor "  Storage Spaces Direct enabled successfully!" -color "Success"
        Add-SessionChange -Category "Storage" -Description "Enabled Storage Spaces Direct on $($cluster.Name)"
    }
    catch {
        Write-OutputColor "  Failed to enable S2D: $_" -color "Error"
    }
}

# Function to create S2D virtual disk
function New-S2DVirtualDisk {
    Clear-Host
    Write-CenteredOutput "Create S2D Virtual Disk" -color "Info"

    # Check S2D is enabled
    try {
        $s2d = Get-ClusterS2D -ErrorAction SilentlyContinue
        if (-not $s2d -or $s2d.State -ne "Enabled") {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  S2D is not enabled. Enable it first." -color "Error"
            return
        }
    }
    catch {
        Write-OutputColor "  S2D not available." -color "Error"
        return
    }

    # Get storage pool
    $pool = Get-StoragePool -ErrorAction SilentlyContinue | Where-Object { $_.IsPrimordial -eq $false } | Select-Object -First 1
    if (-not $pool) {
        Write-OutputColor "  No storage pool found." -color "Error"
        return
    }

    $freeGB = [math]::Round(($pool.Size - $pool.AllocatedSize) / 1GB, 1)
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Storage Pool: $($pool.FriendlyName)" -color "Info"
    Write-OutputColor "  Free Space: $freeGB GB" -color "Info"
    Write-OutputColor "" -color "Info"

    # Get disk name
    Write-OutputColor "  Enter virtual disk name (e.g., 'CSV-Data'):" -color "Warning"
    $diskName = Read-Host "  "
    $navResult = Test-NavigationCommand -UserInput $diskName
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($diskName)) {
        Write-OutputColor "  Invalid name." -color "Error"
        return
    }

    # Get size
    Write-OutputColor "  Enter size in GB (available: $freeGB GB):" -color "Warning"
    $sizeInput = Read-Host "  "
    $sizeGB = 0
    if (-not ($sizeInput -match '^\d+$') -or -not [int]::TryParse($sizeInput, [ref]$sizeGB) -or $sizeGB -lt 1) {
        Write-OutputColor "  Invalid size." -color "Error"
        return
    }

    # Resiliency setting
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Select resiliency:" -color "Warning"
    Write-OutputColor "  [1] Mirror (2-way, recommended)" -color "Info"
    Write-OutputColor "  [2] Mirror (3-way, high redundancy)" -color "Info"
    Write-OutputColor "  [3] Parity (space efficient, slower writes)" -color "Info"
    Write-OutputColor "  [4] Simple (no redundancy, testing only)" -color "Info"
    $resChoice = Read-Host "  "

    $resiliency = switch ($resChoice) {
        "1" { "Mirror" }
        "2" { "Mirror" }
        "3" { "Parity" }
        "4" { "Simple" }
        default { "Mirror" }
    }

    $copies = if ($resChoice -eq "2") { 3 } elseif ($resiliency -eq "Mirror") { 2 } else { $null }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Creating: $diskName ($sizeGB GB, $resiliency)" -color "Info"

    if (-not (Confirm-UserAction -Message "Create this virtual disk?")) {
        Write-OutputColor "  Cancelled." -color "Info"
        return
    }

    try {
        $params = @{
            StoragePoolFriendlyName = $pool.FriendlyName
            FriendlyName = $diskName
            Size = ($sizeGB * 1GB)
            ResiliencySettingName = $resiliency
            ErrorAction = "Stop"
        }
        if ($null -ne $copies) {
            $params["NumberOfDataCopies"] = $copies
        }

        New-VirtualDisk @params
        Write-OutputColor "  Virtual disk '$diskName' created successfully!" -color "Success"
        Add-SessionChange -Category "Storage" -Description "Created S2D virtual disk: $diskName ($sizeGB GB, $resiliency)"
    }
    catch {
        Write-OutputColor "  Failed to create virtual disk: $_" -color "Error"
    }
}

# Function to show S2D menu
function Show-S2DMenu {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     STORAGE SPACES DIRECT (S2D)").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SETUP".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[1]  Enable Storage Spaces Direct"
    Write-MenuItem "[2]  Create Virtual Disk"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  STATUS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[3]  Show S2D Status"
    Write-MenuItem "[4]  Show Storage Backend Status"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  [B] ◄ Back    [M] ◄◄ Server Config" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to run S2D menu
function Start-S2DMenu {
    while ($true) {
        $choice = Show-S2DMenu

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.Action -eq "exit") { Exit-Script; return }
        if ($navResult.Action -eq "back") { return }

        switch ($choice) {
            "1" { Enable-S2DOnCluster; Write-PressEnter }
            "2" { New-S2DVirtualDisk; Write-PressEnter }
            "3" { Show-S2DStatus; Write-PressEnter }
            "4" { Show-StorageBackendStatus; Write-PressEnter }
            "M" { $global:ReturnToMainMenu = $true; return }
            default {
                Write-OutputColor "Invalid choice. Please enter 1-4, B, or M." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# ============================================================================
# SMB3 FILE SHARE
# ============================================================================

# Function to show SMB share connectivity
function Show-SMB3Status {
    Clear-Host
    Write-CenteredOutput "SMB3 File Share Status" -color "Info"

    Write-OutputColor "" -color "Info"

    # SMB Client Configuration
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SMB CLIENT CONFIGURATION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    try {
        $smbConfig = Get-SmbClientConfiguration -ErrorAction SilentlyContinue
        if ($smbConfig) {
            $encColor = if ($smbConfig.EncryptionCiphers) { "Success" } else { "Info" }
            Write-OutputColor "  │$("  Signing Required: $($smbConfig.RequireSecuritySignature)".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Multichannel: $($smbConfig.EnableMultiChannel)".PadRight(72))│" -color $encColor
        }
    }
    catch {
        Write-OutputColor "  │$("  Could not retrieve SMB client config.".PadRight(72))│" -color "Warning"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    # Active SMB Connections
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  ACTIVE SMB CONNECTIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $smbSessions = Get-SmbConnection -ErrorAction SilentlyContinue
    if ($smbSessions) {
        foreach ($session in $smbSessions) {
            $share = $session.ShareName
            $server = $session.ServerName
            $dialect = $session.Dialect
            Write-OutputColor "  │$("  \\$server\$share (SMB $dialect)".PadRight(72))│" -color "Success"
        }
    }
    else {
        Write-OutputColor "  │$("  No active SMB connections.".PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    # SMB Mappings
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  MAPPED DRIVES".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $mappings = Get-SmbMapping -ErrorAction SilentlyContinue
    if ($mappings) {
        foreach ($map in $mappings) {
            $statusColor = if ($map.Status -eq "OK") { "Success" } else { "Warning" }
            Write-OutputColor "  │$("  $($map.LocalPath) -> $($map.RemotePath) [$($map.Status)]".PadRight(72))│" -color $statusColor
        }
    }
    else {
        Write-OutputColor "  │$("  No mapped drives.".PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

# Function to test SMB share path
function Test-SMB3SharePath {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enter SMB share path (e.g., \\\\server\\share):" -color "Warning"
    $sharePath = Read-Host "  "

    $navResult = Test-NavigationCommand -UserInput $sharePath
    if ($navResult.ShouldReturn) { return }

    if ([string]::IsNullOrWhiteSpace($sharePath)) {
        Write-OutputColor "  No path entered." -color "Error"
        return
    }

    Write-OutputColor "  Testing connectivity to $sharePath..." -color "Info"

    try {
        if (Test-Path -LiteralPath $sharePath -ErrorAction Stop) {
            Write-OutputColor "  Share is accessible!" -color "Success"

            # Show share info
            $items = Get-ChildItem -LiteralPath $sharePath -ErrorAction SilentlyContinue | Measure-Object
            Write-OutputColor "  Items in share root: $($items.Count)" -color "Info"
        }
        else {
            Write-OutputColor "  Share path not accessible." -color "Error"
            Write-OutputColor "  Verify the path, network connectivity, and permissions." -color "Info"
        }
    }
    catch {
        Write-OutputColor "  Failed to access share: $_" -color "Error"
    }
}

# Function to show SMB3 menu
function Show-SMB3Menu {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     SMB3 FILE SHARE MANAGEMENT").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-MenuItem "[1]  Test SMB Share Path"
    Write-MenuItem "[2]  Show SMB3 Status"
    Write-MenuItem "[3]  Show Storage Backend Status"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  [B] ◄ Back    [M] ◄◄ Server Config" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to run SMB3 menu
function Start-SMB3Menu {
    while ($true) {
        $choice = Show-SMB3Menu

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.Action -eq "exit") { Exit-Script; return }
        if ($navResult.Action -eq "back") { return }

        switch ($choice) {
            "1" { Test-SMB3SharePath; Write-PressEnter }
            "2" { Show-SMB3Status; Write-PressEnter }
            "3" { Show-StorageBackendStatus; Write-PressEnter }
            "M" { $global:ReturnToMainMenu = $true; return }
            default {
                Write-OutputColor "Invalid choice. Please enter 1-3, B, or M." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# ============================================================================
# NVMe OVER FABRICS
# ============================================================================

# Function to show NVMe status
function Show-NVMeoFStatus {
    Clear-Host
    Write-CenteredOutput "NVMe over Fabrics Status" -color "Info"

    Write-OutputColor "" -color "Info"

    # NVMe Controllers
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  NVMe CONTROLLERS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $nvmeDisks = Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq "NVMe" }
    if ($nvmeDisks) {
        foreach ($disk in $nvmeDisks) {
            $sizeGB = [math]::Round($disk.Size / 1GB, 1)
            $healthColor = if ($disk.HealthStatus -eq "Healthy") { "Success" } else { "Warning" }
            Write-OutputColor "  │$("  Disk $($disk.Number): $($disk.FriendlyName) | $sizeGB GB".PadRight(72))│" -color $healthColor
            Write-OutputColor "  │$("    Health: $($disk.HealthStatus) | Status: $($disk.OperationalStatus)".PadRight(72))│" -color "Info"
        }
    }
    else {
        Write-OutputColor "  │$("  No NVMe disks found.".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  NVMe-oF requires: NVMe-oF initiator, fabric connectivity,".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  and target subsystem with exported namespaces.".PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    # Physical NVMe devices (local + fabric)
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  NVMe PHYSICAL DISKS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $physNvme = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq "NVMe" }
    if ($physNvme) {
        foreach ($pd in $physNvme) {
            $sizeGB = [math]::Round($pd.Size / 1GB, 1)
            $lineStr = "  $($pd.FriendlyName) | $sizeGB GB | $($pd.MediaType) | $($pd.Usage)"
            if ($lineStr.Length -gt 72) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Success"
        }
    }
    else {
        Write-OutputColor "  │$("  No NVMe physical disks detected.".PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

# Function to show NVMe-oF menu
function Show-NVMeoFMenu {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                      NVMe OVER FABRICS (NVMe-oF)").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-MenuItem "[1]  Show NVMe-oF Status"
    Write-MenuItem "[2]  Rescan NVMe Storage"
    Write-MenuItem "[3]  Show Storage Backend Status"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  [B] ◄ Back    [M] ◄◄ Server Config" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to run NVMe-oF menu
function Start-NVMeoFMenu {
    while ($true) {
        $choice = Show-NVMeoFMenu

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.Action -eq "exit") { Exit-Script; return }
        if ($navResult.Action -eq "back") { return }

        switch ($choice) {
            "1" { Show-NVMeoFStatus; Write-PressEnter }
            "2" {
                Write-OutputColor "  Rescanning NVMe storage..." -color "Info"
                Update-HostStorageCache -ErrorAction SilentlyContinue
                Write-OutputColor "  Rescan complete." -color "Success"
                Write-PressEnter
            }
            "3" { Show-StorageBackendStatus; Write-PressEnter }
            "M" { $global:ReturnToMainMenu = $true; return }
            default {
                Write-OutputColor "Invalid choice. Please enter 1-3, B, or M." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# ============================================================================
# UNIFIED STORAGE STATUS
# ============================================================================

# Function to show unified storage backend status
function Show-StorageBackendStatus {
    Clear-Host
    Write-CenteredOutput "Storage Backend Status" -color "Info"

    $backend = $script:StorageBackendType

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  ACTIVE BACKEND: $backend".PadRight(72))│" -color "Success"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    # MPIO status
    $mpioInstalled = Test-MPIOInstalled
    $mpioColor = if ($mpioInstalled) { "Success" } else { "Warning" }
    $mpioStr = if ($mpioInstalled) { "Installed" } else { "Not Installed" }
    Write-OutputColor "  │$("  MPIO: $mpioStr".PadRight(72))│" -color $mpioColor

    if ($mpioInstalled) {
        try {
            $policy = Get-MSDSMGlobalDefaultLoadBalancePolicy -ErrorAction SilentlyContinue
            $policyName = switch ($policy) {
                "RR" { "Round Robin" }
                "LQD" { "Least Queue Depth" }
                "FOO" { "Failover Only" }
                default { $policy }
            }
            Write-OutputColor "  │$("  Load Balance: $policyName".PadRight(72))│" -color "Info"
        }
        catch { }
    }

    # Backend-specific status
    switch ($backend) {
        "iSCSI" {
            $sessions = Get-IscsiSession -ErrorAction SilentlyContinue
            $sessionCount = if ($sessions) { @($sessions).Count } else { 0 }
            $iscsiDisks = Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq "iSCSI" }
            $diskCount = if ($iscsiDisks) { @($iscsiDisks).Count } else { 0 }
            Write-OutputColor "  │$("  iSCSI Sessions: $sessionCount | Disks: $diskCount".PadRight(72))│" -color "Info"
        }
        "FC" {
            $fcPorts = Get-InitiatorPort -ErrorAction SilentlyContinue | Where-Object { $_.ConnectionType -eq "Fibre Channel" }
            $portCount = if ($fcPorts) { @($fcPorts).Count } else { 0 }
            $fcDisks = Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq "Fibre Channel" }
            $diskCount = if ($fcDisks) { @($fcDisks).Count } else { 0 }
            Write-OutputColor "  │$("  FC Ports: $portCount | Disks: $diskCount".PadRight(72))│" -color "Info"
        }
        "S2D" {
            try {
                $s2d = Get-ClusterS2D -ErrorAction SilentlyContinue
                $s2dState = if ($s2d) { $s2d.State } else { "Not Available" }
                Write-OutputColor "  │$("  S2D State: $s2dState".PadRight(72))│" -color "Info"
            }
            catch {
                Write-OutputColor "  │$("  S2D: Not available (requires cluster)".PadRight(72))│" -color "Warning"
            }
        }
        "SMB3" {
            $connections = Get-SmbConnection -ErrorAction SilentlyContinue
            $connCount = if ($connections) { @($connections).Count } else { 0 }
            Write-OutputColor "  │$("  SMB Connections: $connCount".PadRight(72))│" -color "Info"
        }
        "NVMeoF" {
            $nvmeDisks = Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq "NVMe" }
            $diskCount = if ($nvmeDisks) { @($nvmeDisks).Count } else { 0 }
            Write-OutputColor "  │$("  NVMe Disks: $diskCount".PadRight(72))│" -color "Info"
        }
        "Local" {
            Write-OutputColor "  │$("  No shared storage backend configured.".PadRight(72))│" -color "Info"
        }
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    # Detected backend
    Write-OutputColor "" -color "Info"
    $detected = Get-DetectedStorageBackend
    if ($detected -ne $backend) {
        Write-OutputColor "  Note: Detected storage type is '$detected' but configured as '$backend'." -color "Warning"
    }
}

# ============================================================================
# UNIFIED STORAGE & SAN MANAGEMENT MENU
# ============================================================================

# Function to show the unified Storage & SAN Management menu
function Show-StorageSANMenu {
    Clear-Host

    $backend = $script:StorageBackendType

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     STORAGE & SAN MANAGEMENT").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  BACKEND: $backend".PadRight(72))│" -color "Success"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    switch ($backend) {
        "iSCSI" {
            Write-MenuItem "[1]  iSCSI & SAN Management ►"
            Write-OutputColor "  │$("        Configure NICs, cabling check, connect targets, MPIO".PadRight(72))│" -color "Info"
        }
        "FC" {
            Write-MenuItem "[1]  Fibre Channel Management ►"
            Write-OutputColor "  │$("        FC adapters, rescan, MPIO, status".PadRight(72))│" -color "Info"
        }
        "S2D" {
            Write-MenuItem "[1]  Storage Spaces Direct ►"
            Write-OutputColor "  │$("        Enable S2D, create virtual disks, pool status".PadRight(72))│" -color "Info"
        }
        "SMB3" {
            Write-MenuItem "[1]  SMB3 File Share Management ►"
            Write-OutputColor "  │$("        Test shares, SMB status, connections".PadRight(72))│" -color "Info"
        }
        "NVMeoF" {
            Write-MenuItem "[1]  NVMe over Fabrics ►"
            Write-OutputColor "  │$("        NVMe status, rescan, controllers".PadRight(72))│" -color "Info"
        }
        "Local" {
            Write-MenuItem "[1]  (No shared storage configured)"
        }
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  COMMON".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[2]  Show Storage Backend Status"
    Write-MenuItem "[3]  Detect Storage Backend"
    Write-MenuItem "[0]  Change Storage Backend"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  [B] ◄ Back to Host Network    [M] ◄◄ Server Config" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to run the unified Storage & SAN menu
function Start-StorageSANMenu {
    while ($true) {
        $choice = Show-StorageSANMenu

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.Action -eq "exit") { Exit-Script; return }
        if ($navResult.Action -eq "back") { return }

        switch ($choice) {
            "1" {
                switch ($script:StorageBackendType) {
                    "iSCSI"  { Start-Show-iSCSISANMenu }
                    "FC"     { Start-FCSANMenu }
                    "S2D"    { Start-S2DMenu }
                    "SMB3"   { Start-SMB3Menu }
                    "NVMeoF" { Start-NVMeoFMenu }
                    "Local"  {
                        Write-OutputColor "  No shared storage backend configured." -color "Info"
                        Write-OutputColor "  Use [0] to select a storage backend." -color "Info"
                        Write-PressEnter
                    }
                }
                if ($global:ReturnToMainMenu) { return }
            }
            "2" { Show-StorageBackendStatus; Write-PressEnter }
            "3" {
                $detected = Get-DetectedStorageBackend
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Detected storage backend: $detected" -color "Success"
                if ($detected -ne $script:StorageBackendType) {
                    Write-OutputColor "  Current setting: $($script:StorageBackendType)" -color "Info"
                    if (Confirm-UserAction -Message "Switch to detected backend ($detected)?") {
                        $old = $script:StorageBackendType
                        $script:StorageBackendType = $detected
                        Write-OutputColor "  Changed: $old -> $detected" -color "Success"
                        Add-SessionChange -Category "Storage" -Description "Auto-detected storage backend: $detected"
                    }
                }
                Write-PressEnter
            }
            "0" { Set-StorageBackendType; Write-PressEnter }
            "M" { $global:ReturnToMainMenu = $true; return }
            default {
                Write-OutputColor "Invalid choice. Please enter 0-3, B, or M." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# ============================================================================
# BATCH MODE HELPERS
# ============================================================================

# Function to configure storage backend in batch mode
function Initialize-StorageBackendBatch {
    param(
        [hashtable]$Config,
        [string]$BackendType
    )

    switch ($BackendType) {
        "iSCSI" {
            # Handled by existing batch step 18 in EntryPoint
            return $true
        }
        "FC" {
            # FC batch: rescan + MPIO
            Write-OutputColor "           Scanning for Fibre Channel storage..." -color "Info"
            Update-HostStorageCache -ErrorAction SilentlyContinue
            $fcDisks = @(Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq "Fibre Channel" })
            if ($fcDisks.Count -gt 0) {
                Write-OutputColor "           Found $($fcDisks.Count) FC disk(s)." -color "Success"
            }
            else {
                Write-OutputColor "           No FC disks found. Verify zoning and LUN mapping." -color "Warning"
            }
            return $true
        }
        "S2D" {
            # S2D batch: enable S2D if cluster exists
            $cluster = Get-Cluster -ErrorAction SilentlyContinue
            if ($cluster) {
                try {
                    $s2d = Get-ClusterS2D -ErrorAction SilentlyContinue
                    if (-not $s2d -or $s2d.State -ne "Enabled") {
                        Write-OutputColor "           Enabling Storage Spaces Direct..." -color "Info"
                        Enable-ClusterS2D -Confirm:$false -ErrorAction Stop
                        Write-OutputColor "           S2D enabled." -color "Success"
                    }
                    else {
                        Write-OutputColor "           S2D already enabled." -color "Success"
                    }
                }
                catch {
                    Write-OutputColor "           Failed to enable S2D: $_" -color "Error"
                    return $false
                }
            }
            else {
                Write-OutputColor "           No cluster found. S2D requires a failover cluster." -color "Warning"
            }
            return $true
        }
        "SMB3" {
            # SMB3 batch: test share path if provided
            $sharePath = $Config.SMB3SharePath
            if ($sharePath) {
                if (Test-Path -LiteralPath $sharePath -ErrorAction SilentlyContinue) {
                    Write-OutputColor "           SMB share accessible: $sharePath" -color "Success"
                }
                else {
                    Write-OutputColor "           SMB share not accessible: $sharePath" -color "Warning"
                }
            }
            return $true
        }
        "NVMeoF" {
            # NVMe-oF batch: rescan
            Write-OutputColor "           Scanning for NVMe-oF storage..." -color "Info"
            Update-HostStorageCache -ErrorAction SilentlyContinue
            $nvmeDisks = @(Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq "NVMe" })
            if ($nvmeDisks.Count -gt 0) {
                Write-OutputColor "           Found $($nvmeDisks.Count) NVMe disk(s)." -color "Success"
            }
            else {
                Write-OutputColor "           No NVMe disks found." -color "Warning"
            }
            return $true
        }
        "Local" {
            Write-OutputColor "           No shared storage to configure (Local mode)." -color "Info"
            return $true
        }
    }
    return $true
}

# Function to configure MPIO for any backend in batch mode
function Initialize-MPIOForBackend {
    param(
        [string]$BackendType
    )

    switch ($BackendType) {
        "iSCSI" {
            Enable-MSDSMAutomaticClaim -BusType iSCSI -ErrorAction Stop
            Set-MSDSMGlobalDefaultLoadBalancePolicy -Policy RR -ErrorAction Stop
            Write-OutputColor "           MPIO configured for iSCSI (Round Robin)." -color "Success"
        }
        "FC" {
            Enable-MSDSMAutomaticClaim -BusType "Fibre Channel" -ErrorAction Stop
            Set-MSDSMGlobalDefaultLoadBalancePolicy -Policy RR -ErrorAction Stop
            Write-OutputColor "           MPIO configured for Fibre Channel (Round Robin)." -color "Success"
        }
        "S2D" {
            Write-OutputColor "           MPIO not needed for S2D (handled by cluster)." -color "Info"
        }
        "SMB3" {
            Write-OutputColor "           MPIO not needed for SMB3 (SMB Multichannel handles paths)." -color "Info"
        }
        "NVMeoF" {
            # NVMe multipath is OS-level, not MPIO
            Write-OutputColor "           NVMe multipath handled natively by Windows." -color "Info"
        }
        "Local" {
            Write-OutputColor "           No MPIO configuration needed (Local mode)." -color "Info"
        }
    }
}
#endregion
