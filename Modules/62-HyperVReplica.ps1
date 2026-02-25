#region ===== HYPER-V REPLICA MANAGEMENT =====
# Functions for managing Hyper-V Replica — replication configuration, failover, and monitoring

# Check if current host is configured as a Hyper-V Replica server
function Test-HyperVReplicaEnabled {
    try {
        $replicaConfig = Get-VMReplicationServer -ErrorAction SilentlyContinue
        return ($null -ne $replicaConfig -and $replicaConfig.ReplicationEnabled)
    }
    catch {
        return $false
    }
}

# Main Hyper-V Replica Management menu
function Show-HyperVReplicaMenu {
    if (-not (Test-HyperVInstalled)) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  Hyper-V is not installed. Install Hyper-V first.".PadRight(72))│" -color "Error"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-PressEnter
        return
    }

    while ($true) {
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                     HYPER-V REPLICA MANAGEMENT").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        # Show current replica status
        $replicaEnabled = Test-HyperVReplicaEnabled
        if ($replicaEnabled) {
            $replicaConfig = Get-VMReplicationServer -ErrorAction SilentlyContinue
            $authType = if ($null -ne $replicaConfig) { $replicaConfig.AllowedAuthenticationType } else { "Unknown" }
            Write-OutputColor "  Replica Server: Enabled ($authType)" -color "Success"
        }
        else {
            Write-OutputColor "  Replica Server: Not configured" -color "Warning"
        }
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  REPLICA SERVER".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem -Text "[1]  Enable Replica Server (Configure this host to receive replicas)"
        Write-MenuItem -Text "[2]  Replication Status Dashboard"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  VM REPLICATION".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem -Text "[3]  Enable Replication for VM"
        Write-MenuItem -Text "[4]  Test Failover"
        Write-MenuItem -Text "[5]  Planned Failover"
        Write-MenuItem -Text "[6]  Reverse Replication"
        Write-MenuItem -Text "[7]  Remove Replication"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" {
                Enable-ReplicaServer
                Write-PressEnter
            }
            "2" {
                Show-ReplicationStatus
                Write-PressEnter
            }
            "3" {
                Enable-VMReplicationWizard
                Write-PressEnter
            }
            "4" {
                Start-TestFailover
                Write-PressEnter
            }
            "5" {
                Start-PlannedFailover
                Write-PressEnter
            }
            "6" {
                Set-ReverseReplication
                Write-PressEnter
            }
            "7" {
                Remove-VMReplicationWizard
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

# Configure this host as a Hyper-V Replica target server
function Enable-ReplicaServer {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                      ENABLE REPLICA SERVER").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Check if already enabled
    $replicaConfig = Get-VMReplicationServer -ErrorAction SilentlyContinue
    if ($null -ne $replicaConfig -and $replicaConfig.ReplicationEnabled) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  REPLICA SERVER ALREADY ENABLED".PadRight(72))│" -color "Success"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  Authentication: $($replicaConfig.AllowedAuthenticationType)".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Storage Location: $($replicaConfig.DefaultStorageLocation)".PadRight(72))│" -color "Info"

        $httpEnabled = if ($replicaConfig.HttpPort) { "Port $($replicaConfig.HttpPort)" } else { "Disabled" }
        $httpsEnabled = if ($replicaConfig.HttpsPort) { "Port $($replicaConfig.HttpsPort)" } else { "Disabled" }
        Write-OutputColor "  │$("  HTTP: $httpEnabled".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  HTTPS: $httpsEnabled".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Replica server is already configured." -color "Info"
        return
    }

    # Step 1: Choose authentication type
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  AUTHENTICATION TYPE".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  [1]  Kerberos (domain-joined environments) - HTTP port 80".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  [2]  Certificate-based (workgroup/cross-domain) - HTTPS port 443".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $authChoice = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $authChoice
    if ($navResult.ShouldReturn) { return }

    $authType = switch ($authChoice) {
        "1" { "Kerberos" }
        "2" { "Certificate" }
        default {
            Write-OutputColor "  Invalid selection." -color "Error"
            return
        }
    }

    # Step 2: Set allowed primary servers
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  ALLOWED PRIMARY SERVERS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  [1]  Allow replication from any authenticated server".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  [2]  Allow from specific servers only".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $serverChoice = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $serverChoice
    if ($navResult.ShouldReturn) { return }

    $script:ReplicaAllowedServers = @()
    if ($serverChoice -eq "2") {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Enter comma-separated list of primary server names/IPs:" -color "Info"
        $serverList = Read-Host "  "
        if ([string]::IsNullOrWhiteSpace($serverList)) {
            Write-OutputColor "  No servers specified. Cancelled." -color "Error"
            return
        }
        $script:ReplicaAllowedServers = @($serverList -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }

    # Step 3: Set storage path
    $defaultStorage = if ($script:HostVMStoragePath) { $script:HostVMStoragePath } else { "C:\Hyper-V\Replica" }
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Default storage path for replica VMs (Enter for default: $defaultStorage):" -color "Info"
    $storagePath = Read-Host "  "
    if ([string]::IsNullOrWhiteSpace($storagePath)) { $storagePath = $defaultStorage }

    # Ensure storage directory exists
    if (-not (Test-Path $storagePath)) {
        try {
            New-Item -Path $storagePath -ItemType Directory -Force | Out-Null
            Write-OutputColor "  Created directory: $storagePath" -color "Info"
        }
        catch {
            Write-OutputColor "  Failed to create directory: $_" -color "Error"
            return
        }
    }

    # Confirm
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CONFIGURATION SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Authentication: $authType".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Storage Path: $storagePath".PadRight(72))│" -color "Info"
    if ($script:ReplicaAllowedServers.Count -gt 0) {
        Write-OutputColor "  │$("  Allowed Servers: $($script:ReplicaAllowedServers -join ', ')".PadRight(72))│" -color "Info"
    }
    else {
        Write-OutputColor "  │$("  Allowed Servers: Any authenticated server".PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Enable Hyper-V Replica Server with these settings?")) {
        Write-OutputColor "  Cancelled." -color "Info"
        return
    }

    # Execute
    try {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Configuring Hyper-V Replica Server..." -color "Info"

        Set-VMReplicationServer -ReplicationEnabled $true `
            -AllowedAuthenticationType $authType `
            -DefaultStorageLocation $storagePath `
            -ErrorAction Stop

        # Configure firewall rules
        Enable-NetFirewallRule -DisplayName "Hyper-V Replica HTTP*" -ErrorAction SilentlyContinue
        Enable-NetFirewallRule -DisplayName "Hyper-V Replica HTTPS*" -ErrorAction SilentlyContinue

        Write-OutputColor "  Hyper-V Replica Server enabled successfully!" -color "Success"
        Write-OutputColor "  Firewall rules for Hyper-V Replica have been enabled." -color "Info"
        Add-SessionChange -Category "Hyper-V" -Description "Enabled Hyper-V Replica Server ($authType, storage: $storagePath)"
    }
    catch {
        Write-OutputColor "  Failed to enable Replica Server: $_" -color "Error"
    }
}

# Interactive wizard to enable replication for a VM
function Enable-VMReplicationWizard {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    ENABLE VM REPLICATION WIZARD").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Step 1: List VMs
    Write-OutputColor "  Gathering virtual machines..." -color "Info"
    try {
        $vms = Get-VM -ErrorAction Stop | Sort-Object Name
    }
    catch {
        Write-OutputColor "  Error getting VMs: $_" -color "Error"
        return
    }

    if ($vms.Count -eq 0) {
        Write-OutputColor "  No virtual machines found on this host." -color "Warning"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT VM TO REPLICATE".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  #    VM NAME                       STATE        REPLICATION".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  ---- -------------------------------- ------------ ---------------".PadRight(72))│" -color "Info"

    $vmIndex = 1
    $vmMap = @{}
    foreach ($vm in $vms) {
        $vmName = if ($vm.Name.Length -gt 32) { $vm.Name.Substring(0, 29) + "..." } else { $vm.Name.PadRight(32) }
        $state = "$($vm.State)".PadRight(12)
        $replState = if ($null -ne $vm.ReplicationState -and $vm.ReplicationState -ne "Disabled") { "$($vm.ReplicationState)" } else { "None" }
        $stateColor = switch ("$($vm.State)") {
            "Running" { "Success" }
            "Off"     { "Warning" }
            default   { "Info" }
        }
        Write-OutputColor "  │  [$($vmIndex.ToString().PadLeft(2))] $vmName $state $($replState.PadRight(15))│" -color $stateColor
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
    $vmName = $selectedVM.Name

    # Step 2: Check if already replicated
    if ($null -ne $selectedVM.ReplicationState -and $selectedVM.ReplicationState -ne "Disabled") {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  VM '$vmName' already has replication configured." -color "Warning"
        Write-OutputColor "  Current state: $($selectedVM.ReplicationState)" -color "Warning"
        Write-OutputColor "  Remove existing replication first to reconfigure." -color "Info"
        return
    }

    # Step 3: Enter replica server
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enter the replica server name or IP address:" -color "Info"
    $replicaServer = Read-Host "  "
    if ([string]::IsNullOrWhiteSpace($replicaServer)) {
        Write-OutputColor "  No server specified. Cancelled." -color "Error"
        return
    }

    # Step 4: Choose authentication type
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  AUTHENTICATION TYPE".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  [1]  Kerberos (HTTP port 80)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  [2]  Certificate (HTTPS port 443)".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $authChoice = Read-Host "  Select"
    $authType = switch ($authChoice) {
        "1" { "Kerberos" }
        "2" { "Certificate" }
        default {
            Write-OutputColor "  Invalid selection. Defaulting to Kerberos." -color "Warning"
            "Kerberos"
        }
    }
    $port = if ($authType -eq "Kerberos") { 80 } else { 443 }

    # Step 5: Test connection
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Testing connection to $replicaServer on port $port..." -color "Info"
    try {
        Test-VMReplicationConnection -ReplicaServerName $replicaServer -ReplicaServerPort $port -AuthenticationType $authType -ErrorAction Stop
        Write-OutputColor "  Connection test successful!" -color "Success"
    }
    catch {
        Write-OutputColor "  Connection test failed: $_" -color "Error"
        Write-OutputColor "  Ensure the replica server is configured and firewall rules are enabled." -color "Warning"
        if (-not (Confirm-UserAction -Message "Continue anyway?")) { return }
    }

    # Step 6: Replication frequency
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  REPLICATION FREQUENCY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  [1]  30 seconds".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  [2]  5 minutes (default)".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [3]  15 minutes".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $freqChoice = Read-Host "  Select"
    $freqSec = switch ($freqChoice) {
        "1" { 30 }
        "3" { 900 }
        default { 300 }
    }
    $freqDisplay = switch ($freqSec) {
        30  { "30 seconds" }
        300 { "5 minutes" }
        900 { "15 minutes" }
    }

    # Step 7: Initial replication method
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  INITIAL REPLICATION METHOD".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  [1]  Send over network (default)".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [2]  Send using external media".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  [3]  Use existing VM on replica server".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $initChoice = Read-Host "  Select"
    $initMethod = switch ($initChoice) {
        "2" { "OverNetwork" }  # External media requires export first
        "3" { "UseBackup" }
        default { "OverNetwork" }
    }

    # Confirm
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  REPLICATION CONFIGURATION SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  VM: $vmName".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Replica Server: $replicaServer".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Authentication: $authType (port $port)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Frequency: $freqDisplay".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Enable replication for VM '$vmName'?")) {
        Write-OutputColor "  Cancelled." -color "Info"
        return
    }

    # Execute
    try {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Enabling replication for VM '$vmName'..." -color "Info"

        Enable-VMReplication -VMName $vmName `
            -ReplicaServerName $replicaServer `
            -ReplicaServerPort $port `
            -AuthenticationType $authType `
            -ReplicationFrequencySec $freqSec `
            -ErrorAction Stop

        Write-OutputColor "  Replication enabled. Starting initial replication..." -color "Info"

        if ($initChoice -eq "2") {
            # External media — prompt for export path
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Enter export path for external media:" -color "Info"
            $exportPath = Read-Host "  "
            if ([string]::IsNullOrWhiteSpace($exportPath)) { $exportPath = "C:\Hyper-V\ReplicaExport" }
            Start-VMInitialReplication -VMName $vmName -DestinationPath $exportPath -ErrorAction Stop
            Write-OutputColor "  Initial replication exported to: $exportPath" -color "Success"
            Write-OutputColor "  Transfer this to the replica server and import it there." -color "Info"
        }
        elseif ($initChoice -eq "3") {
            Start-VMInitialReplication -VMName $vmName -UseBackup -ErrorAction Stop
            Write-OutputColor "  Initial replication set to use existing VM on replica server." -color "Success"
        }
        else {
            Start-VMInitialReplication -VMName $vmName -ErrorAction Stop
            Write-OutputColor "  Initial replication started over network." -color "Success"
            Write-OutputColor "  This may take some time depending on VM size and network speed." -color "Info"
        }

        Add-SessionChange -Category "Hyper-V" -Description "Enabled replication for VM '$vmName' to $replicaServer"
    }
    catch {
        Write-OutputColor "  Failed to enable replication: $_" -color "Error"
    }
}

# Dashboard showing all replicated VMs and their status
function Show-ReplicationStatus {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    REPLICATION STATUS DASHBOARD").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Check replica server status
    $replicaEnabled = Test-HyperVReplicaEnabled
    if ($replicaEnabled) {
        Write-OutputColor "  Replica Server: Enabled" -color "Success"
    }
    else {
        Write-OutputColor "  Replica Server: Not configured on this host" -color "Warning"
    }
    Write-OutputColor "" -color "Info"

    # Get all replicated VMs
    try {
        $replications = Get-VMReplication -ErrorAction Stop
    }
    catch {
        Write-OutputColor "  Error querying replication status: $_" -color "Error"
        return
    }

    if ($null -eq $replications -or @($replications).Count -eq 0) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  No VMs with replication configured on this host.".PadRight(72))│" -color "Warning"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        return
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  REPLICATED VIRTUAL MACHINES".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  VM NAME                STATE        HEALTH     MODE      LAST SYNC".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  ---------------------- ------------ ---------- --------- -----------".PadRight(72))│" -color "Info"

    foreach ($repl in $replications) {
        $vmName = if ($repl.VMName.Length -gt 22) { $repl.VMName.Substring(0, 19) + "..." } else { $repl.VMName.PadRight(22) }
        $state = "$($repl.State)".PadRight(12)
        $health = "$($repl.Health)".PadRight(10)
        $mode = "$($repl.Mode)".PadRight(9)
        $lastSync = if ($null -ne $repl.LastReplicationTime -and $repl.LastReplicationTime -ne [DateTime]::MinValue) {
            $repl.LastReplicationTime.ToString("MM/dd HH:mm")
        }
        else {
            "Never"
        }

        $color = switch ("$($repl.Health)") {
            "Normal"   { "Success" }
            "Warning"  { "Warning" }
            "Critical" { "Error" }
            default    { "Info" }
        }

        Write-OutputColor "  │  $vmName $state $health $mode $($lastSync.PadRight(11))│" -color $color
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Show detailed stats for each VM
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  DETAILED REPLICATION STATISTICS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    foreach ($repl in $replications) {
        try {
            $stats = Measure-VMReplication -VMName $repl.VMName -ErrorAction SilentlyContinue
            if ($null -ne $stats) {
                $pendingSize = if ($null -ne $stats.PendingReplicationSize) {
                    "{0:N2} MB" -f ($stats.PendingReplicationSize / 1MB)
                }
                else { "0 MB" }
                $avgSize = if ($null -ne $stats.AverageReplicationSize) {
                    "{0:N2} MB" -f ($stats.AverageReplicationSize / 1MB)
                }
                else { "N/A" }
                $avgLatency = if ($null -ne $stats.AverageReplicationLatency) {
                    "$($stats.AverageReplicationLatency.TotalSeconds)s"
                }
                else { "N/A" }

                Write-OutputColor "  │$("  $($repl.VMName)".PadRight(72))│" -color "Info"
                Write-OutputColor "  │$("    Pending: $pendingSize | Avg Size: $avgSize | Avg Latency: $avgLatency".PadRight(72))│" -color "Info"
            }
        }
        catch {
            Write-OutputColor "  │$("  $($repl.VMName): Unable to get detailed stats".PadRight(72))│" -color "Warning"
        }
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Total replicated VMs: $(@($replications).Count)" -color "Info"
    Write-OutputColor "  Green = Normal, Yellow = Warning, Red = Critical" -color "Info"
}

# Start a test failover for a replicated VM
function Start-TestFailover {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                          TEST FAILOVER").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Get VMs with replication
    try {
        $replications = Get-VMReplication -ErrorAction Stop | Where-Object { $_.Mode -eq "Primary" -or $_.Mode -eq "Replica" }
    }
    catch {
        Write-OutputColor "  Error querying replication: $_" -color "Error"
        return
    }

    if ($null -eq $replications -or @($replications).Count -eq 0) {
        Write-OutputColor "  No VMs with replication found on this host." -color "Warning"
        return
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT VM FOR TEST FAILOVER".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $vmIndex = 1
    $vmMap = @{}
    foreach ($repl in $replications) {
        $vmName = if ($repl.VMName.Length -gt 36) { $repl.VMName.Substring(0, 33) + "..." } else { $repl.VMName.PadRight(36) }
        Write-OutputColor "  │  [$($vmIndex.ToString().PadLeft(2))] $vmName $($repl.Mode.ToString().PadRight(10)) $($repl.Health)│" -color "Info"
        $vmMap["$vmIndex"] = $repl
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

    $selectedRepl = $vmMap[$vmChoice]
    $vmName = $selectedRepl.VMName

    # Show available recovery points
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Checking recovery points for '$vmName'..." -color "Info"
    try {
        $recoveryPoints = Get-VMReplicationCheckpoint -VMName $vmName -ErrorAction SilentlyContinue
        if ($null -ne $recoveryPoints -and @($recoveryPoints).Count -gt 0) {
            Write-OutputColor "  Available recovery points:" -color "Info"
            foreach ($rp in $recoveryPoints) {
                $rpTime = if ($null -ne $rp.CreationTime) { $rp.CreationTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "Unknown" }
                Write-OutputColor "    - $rpTime" -color "Info"
            }
        }
        else {
            Write-OutputColor "  Using latest recovery point." -color "Info"
        }
    }
    catch {
        Write-OutputColor "  Could not enumerate recovery points. Using latest available." -color "Warning"
    }

    # Confirm
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("  A test failover creates a test VM without affecting production.").PadRight(72))║" -color "Info"
    Write-OutputColor "  ║$(("  Remember to clean up the test VM when done.").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Start test failover for VM '$vmName'?")) {
        Write-OutputColor "  Cancelled." -color "Info"
        return
    }

    # Execute test failover
    try {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Starting test failover for '$vmName'..." -color "Info"

        Start-VMFailover -VMName $vmName -AsTest -ErrorAction Stop

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Test failover started successfully!" -color "Success"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  IMPORTANT: Test VM cleanup".PadRight(72))│" -color "Warning"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  1. Verify the test VM is functioning correctly".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  2. When done, run: Stop-VMFailover -VMName '$vmName'".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("     or return to this menu to clean up".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

        Add-SessionChange -Category "Hyper-V" -Description "Started test failover for VM '$vmName'"

        # Offer to clean up now or later
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [C] Clean up test failover now" -color "Info"
        Write-OutputColor "  [L] Leave running for manual testing" -color "Info"
        Write-OutputColor "" -color "Info"
        $cleanChoice = Read-Host "  Select"

        if ($cleanChoice -eq "C" -or $cleanChoice -eq "c") {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Cleaning up test failover..." -color "Info"
            Stop-VMFailover -VMName $vmName -ErrorAction Stop
            Write-OutputColor "  Test failover cleaned up successfully." -color "Success"
            Add-SessionChange -Category "Hyper-V" -Description "Cleaned up test failover for VM '$vmName'"
        }
    }
    catch {
        Write-OutputColor "  Test failover failed: $_" -color "Error"
    }
}

# Start a planned failover (controlled migration to replica)
function Start-PlannedFailover {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                        PLANNED FAILOVER").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Get VMs with replication on this host
    try {
        $replications = Get-VMReplication -ErrorAction Stop
    }
    catch {
        Write-OutputColor "  Error querying replication: $_" -color "Error"
        return
    }

    if ($null -eq $replications -or @($replications).Count -eq 0) {
        Write-OutputColor "  No VMs with replication found on this host." -color "Warning"
        return
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT VM FOR PLANNED FAILOVER".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $vmIndex = 1
    $vmMap = @{}
    foreach ($repl in $replications) {
        $vmName = if ($repl.VMName.Length -gt 36) { $repl.VMName.Substring(0, 33) + "..." } else { $repl.VMName.PadRight(36) }
        $stateColor = if ($repl.Health -eq "Normal") { "Success" } else { "Warning" }
        Write-OutputColor "  │  [$($vmIndex.ToString().PadLeft(2))] $vmName $($repl.Mode.ToString().PadRight(10)) $($repl.State)│" -color $stateColor
        $vmMap["$vmIndex"] = $repl
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

    $selectedRepl = $vmMap[$vmChoice]
    $vmName = $selectedRepl.VMName

    # Warn about shutdown
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("  WARNING: Planned failover requires the VM to be shut down.").PadRight(72))║" -color "Warning"
    Write-OutputColor "  ║$(("  The VM will be failed over to the replica server.").PadRight(72))║" -color "Warning"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Proceed with planned failover for VM '$vmName'?")) {
        Write-OutputColor "  Cancelled." -color "Info"
        return
    }

    # Check if VM is running and offer to shut down
    try {
        $vm = Get-VM -Name $vmName -ErrorAction Stop
        if ($vm.State -eq "Running") {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  VM '$vmName' is currently running." -color "Warning"
            if (Confirm-UserAction -Message "Shut down VM '$vmName' for failover?") {
                Write-OutputColor "  Shutting down VM..." -color "Info"
                Stop-VM -Name $vmName -Force -ErrorAction Stop
                Write-OutputColor "  VM shut down successfully." -color "Success"
            }
            else {
                Write-OutputColor "  Cannot proceed with planned failover while VM is running." -color "Error"
                return
            }
        }
    }
    catch {
        Write-OutputColor "  Error checking VM state: $_" -color "Error"
        return
    }

    # Execute planned failover
    try {
        Write-OutputColor "" -color "Info"

        if ($selectedRepl.Mode -eq "Primary") {
            # On the primary server — prepare for failover
            Write-OutputColor "  Preparing primary server for planned failover..." -color "Info"
            Start-VMFailover -VMName $vmName -Prepare -ErrorAction Stop
            Write-OutputColor "  Primary server prepared." -color "Success"
            Write-OutputColor "" -color "Info"

            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  NEXT STEPS (run on the REPLICA server):".PadRight(72))│" -color "Warning"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  1. Start-VMFailover -VMName '$vmName'".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  2. Complete-VMFailover -VMName '$vmName'".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  3. Start the VM on the replica server".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  4. Set up reverse replication if needed".PadRight(72))│" -color "Info"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        }
        else {
            # On the replica server — complete the failover
            Write-OutputColor "  Completing failover on replica server..." -color "Info"
            Start-VMFailover -VMName $vmName -ErrorAction Stop
            Complete-VMFailover -VMName $vmName -ErrorAction Stop
            Write-OutputColor "  Planned failover completed!" -color "Success"
            Write-OutputColor "  VM '$vmName' is now active on this server." -color "Info"
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  You may want to set up reverse replication to protect the VM." -color "Info"
        }

        Add-SessionChange -Category "Hyper-V" -Description "Planned failover for VM '$vmName' ($($selectedRepl.Mode) role)"
    }
    catch {
        Write-OutputColor "  Planned failover failed: $_" -color "Error"
    }
}

# Reverse replication direction after failover
function Set-ReverseReplication {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       REVERSE REPLICATION").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  After a failover, reverse replication changes the direction so the" -color "Info"
    Write-OutputColor "  original primary becomes the new replica target." -color "Info"
    Write-OutputColor "" -color "Info"

    # Get VMs that have been failed over
    try {
        $replications = Get-VMReplication -ErrorAction Stop | Where-Object {
            $_.State -eq "FailedOverWaitingCompletion" -or
            $_.State -eq "Suspended" -or
            $_.State -eq "Replicating" -or
            $_.State -eq "ReadyForInitialReplication"
        }
    }
    catch {
        Write-OutputColor "  Error querying replication: $_" -color "Error"
        return
    }

    if ($null -eq $replications -or @($replications).Count -eq 0) {
        # Also show all replicated VMs as candidates
        try {
            $replications = Get-VMReplication -ErrorAction Stop
        }
        catch {
            Write-OutputColor "  No VMs with replication found." -color "Warning"
            return
        }

        if ($null -eq $replications -or @($replications).Count -eq 0) {
            Write-OutputColor "  No VMs with replication found on this host." -color "Warning"
            return
        }

        Write-OutputColor "  No VMs in failover state detected. Showing all replicated VMs:" -color "Warning"
        Write-OutputColor "" -color "Info"
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT VM FOR REVERSE REPLICATION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $vmIndex = 1
    $vmMap = @{}
    foreach ($repl in $replications) {
        $vmName = if ($repl.VMName.Length -gt 32) { $repl.VMName.Substring(0, 29) + "..." } else { $repl.VMName.PadRight(32) }
        Write-OutputColor "  │  [$($vmIndex.ToString().PadLeft(2))] $vmName $("$($repl.State)".PadRight(20)) $($repl.Mode)│" -color "Info"
        $vmMap["$vmIndex"] = $repl
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

    $selectedRepl = $vmMap[$vmChoice]
    $vmName = $selectedRepl.VMName

    # Get the original primary server
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enter the original primary server name (to become the new replica):" -color "Info"
    $originalServer = Read-Host "  "
    if ([string]::IsNullOrWhiteSpace($originalServer)) {
        Write-OutputColor "  No server specified. Cancelled." -color "Error"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  VM: $vmName" -color "Info"
    Write-OutputColor "  New replica target: $originalServer" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Reverse replication for VM '$vmName'?")) {
        Write-OutputColor "  Cancelled." -color "Info"
        return
    }

    try {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Setting up reverse replication..." -color "Info"

        Set-VMReplication -VMName $vmName -Reverse -ReplicaServerName $originalServer -ErrorAction Stop

        Write-OutputColor "  Reverse replication configured successfully!" -color "Success"
        Write-OutputColor "  VM '$vmName' will now replicate to $originalServer." -color "Info"
        Add-SessionChange -Category "Hyper-V" -Description "Reversed replication for VM '$vmName' to $originalServer"
    }
    catch {
        Write-OutputColor "  Failed to reverse replication: $_" -color "Error"
    }
}

# Remove replication from a VM
function Remove-VMReplicationWizard {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       REMOVE VM REPLICATION").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Get VMs with replication
    try {
        $replications = Get-VMReplication -ErrorAction Stop
    }
    catch {
        Write-OutputColor "  Error querying replication: $_" -color "Error"
        return
    }

    if ($null -eq $replications -or @($replications).Count -eq 0) {
        Write-OutputColor "  No VMs with replication found on this host." -color "Warning"
        return
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT VM TO REMOVE REPLICATION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $vmIndex = 1
    $vmMap = @{}
    foreach ($repl in $replications) {
        $vmName = if ($repl.VMName.Length -gt 32) { $repl.VMName.Substring(0, 29) + "..." } else { $repl.VMName.PadRight(32) }
        $mode = "$($repl.Mode)".PadRight(10)
        $health = "$($repl.Health)"
        $healthColor = switch ($health) {
            "Normal"   { "Success" }
            "Warning"  { "Warning" }
            "Critical" { "Error" }
            default    { "Info" }
        }
        Write-OutputColor "  │  [$($vmIndex.ToString().PadLeft(2))] $vmName $mode $($health.PadRight(14))│" -color $healthColor
        $vmMap["$vmIndex"] = $repl
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

    $selectedRepl = $vmMap[$vmChoice]
    $vmName = $selectedRepl.VMName

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  VM: $vmName" -color "Info"
    Write-OutputColor "  Mode: $($selectedRepl.Mode)" -color "Info"
    Write-OutputColor "  State: $($selectedRepl.State)" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Remove replication for VM '$vmName'? This cannot be undone.")) {
        Write-OutputColor "  Cancelled." -color "Info"
        return
    }

    try {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Removing replication for '$vmName'..." -color "Info"

        Remove-VMReplication -VMName $vmName -ErrorAction Stop

        Write-OutputColor "  Replication removed successfully for VM '$vmName'." -color "Success"
        Add-SessionChange -Category "Hyper-V" -Description "Removed replication for VM '$vmName'"
    }
    catch {
        Write-OutputColor "  Failed to remove replication: $_" -color "Error"
    }
}
#endregion
