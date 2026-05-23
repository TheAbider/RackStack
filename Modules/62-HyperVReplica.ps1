#region ===== HYPER-V REPLICA MANAGEMENT =====
# Functions for managing Hyper-V Replica — replication configuration, failover, and monitoring

# Check if current host is configured as a Hyper-V Replica server. Returns:
#   $true  — server is configured AND replication is enabled
#   $false — server is configured but replication is disabled
#   $null  — could not determine (Hyper-V WMI provider crashed, module mismatch after in-place upgrade)
# The previous swallow-and-return-$false hid probe failure from the caller; menus then reported
# "Not configured", the operator re-ran Set-VMReplicationServer, and overwrote the existing
# certificate / allow-list / storage path with defaults.
function Test-HyperVReplicaEnabled {
    try {
        $replicaConfig = Get-VMReplicationServer -ErrorAction Stop
        return ($null -ne $replicaConfig -and $replicaConfig.ReplicationEnabled)
    }
    catch {
        return $null
    }
}

# Check replication health for all replicated VMs
function Test-ReplicationHealth {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    REPLICATION HEALTH CHECK").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Get all replicated VMs
    $replicatedVMs = Get-VMReplication -ErrorAction SilentlyContinue
    if ($null -eq $replicatedVMs -or @($replicatedVMs).Count -eq 0) {
        Write-OutputColor "  No VM replication configured on this host." -color "Info"
        return
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  VM REPLICATION HEALTH".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $warningCount = 0
    $criticalCount = 0

    foreach ($vm in $replicatedVMs) {
        # Compare against the enum value directly. The `.ToString()` of the ReplicationHealth
        # enum returns the invariant name on most builds, but on some Hyper-V PowerShell modules
        # with Set-Culture-overridden sessions the display value gets localized — comparing the
        # localized string to literal English 'Normal'/'Warning'/'Critical' caused non-EN hosts
        # to silently fall into the default branch and report "Info" (no issue) for actual
        # Critical replications. The integer cast is invariant.
        $healthInt = -1
        try { $healthInt = [int]$vm.ReplicationHealth } catch { }
        $color = switch ($healthInt) {
            1       { "Success" }  # Normal
            2       { "Warning" }  # Warning
            3       { "Error" }    # Critical
            default { "Info" }
        }
        $status = switch ($healthInt) {
            1 { 'Normal' } 2 { 'Warning' } 3 { 'Critical' } default { "$($vm.ReplicationHealth)" }
        }

        if ($healthInt -eq 2) { $warningCount++ }
        if ($healthInt -eq 3) { $criticalCount++ }

        $lastSync = if ($null -ne $vm.LastReplicationTime -and $vm.LastReplicationTime -ne [DateTime]::MinValue) {
            $vm.LastReplicationTime.ToString("yyyy-MM-dd HH:mm:ss")
        }
        else { "Never" }

        $lineStr = "  $($vm.Name): $status (Last sync: $lastSync)"
        if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color $color

        # Check replication lag
        if ($null -ne $vm.LastReplicationTime -and $vm.LastReplicationTime -ne [DateTime]::MinValue) {
            $lag = (Get-Date) - $vm.LastReplicationTime
            if ($lag.TotalMinutes -gt 15) {
                $lagStr = "    Replication lag: $([math]::Round($lag.TotalMinutes)) minutes"
                if ($lagStr.Length -gt 69) { $lagStr = $lagStr.Substring(0, 69) + "..." }
                Write-OutputColor "  │$($lagStr.PadRight(72))│" -color "Warning"
            }
        }
    }

    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    # Overall summary
    $totalVMs = @($replicatedVMs).Count
    $overallColor = if ($criticalCount -gt 0) { "Error" } elseif ($warningCount -gt 0) { "Warning" } else { "Success" }
    $overallStatus = if ($criticalCount -gt 0) { "CRITICAL ($criticalCount VM(s) in critical state)" }
        elseif ($warningCount -gt 0) { "WARNING ($warningCount VM(s) with warnings)" }
        else { "HEALTHY (all $totalVMs VM(s) normal)" }
    Write-OutputColor "  │$("  Overall: $overallStatus".PadRight(72))│" -color $overallColor

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Total replicated VMs: $totalVMs" -color "Info"
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
        if ($script:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                     HYPER-V REPLICA MANAGEMENT").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        # Show current replica status. Test-HyperVReplicaEnabled returns $null on probe failure
        # (vs $false for "not configured"), so distinguish the two — surfacing probe failure
        # explicitly prevents the operator from re-enabling and overwriting existing config.
        $replicaEnabled = Test-HyperVReplicaEnabled
        if ($replicaEnabled -eq $true) {
            $replicaConfig = Get-VMReplicationServer -ErrorAction SilentlyContinue
            $authType = if ($null -ne $replicaConfig) { $replicaConfig.AllowedAuthenticationType } else { "Unknown" }
            Write-OutputColor "  Replica Server: Enabled ($authType)" -color "Success"
        }
        elseif ($null -eq $replicaEnabled) {
            Write-OutputColor "  Replica Server: Probe failed (Hyper-V WMI provider unavailable — re-running setup would overwrite existing config)" -color "Error"
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
        Write-MenuItem -Text "[8]  Replication Health Check"
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
            "8" {
                Test-ReplicationHealth
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
        $lineStr = "  Storage Location: $($replicaConfig.DefaultStorageLocation)"
        if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"

        $authType = $replicaConfig.AllowedAuthenticationType.ToString()
        $httpEnabled = if ($authType -match 'Kerberos|Integrated') { "Port $($replicaConfig.HttpPort)" } else { "Disabled" }
        $httpsEnabled = if ($authType -match 'Certificate|Integrated') { "Port $($replicaConfig.HttpsPort)" } else { "Disabled" }
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
            Write-OutputColor "  Invalid selection. Enter 1 or 2." -color "Error"
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
    if ($serverChoice -ne "1" -and $serverChoice -ne "2") {
        Write-OutputColor "  Invalid selection. Enter 1 or 2." -color "Error"
        return
    }
    if ($serverChoice -eq "2") {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Enter comma-separated list of primary server names/IPs:" -color "Info"
        $serverList = Read-Host "  "
        $navResult = Test-NavigationCommand -UserInput $serverList
        if ($navResult.ShouldReturn) { return }
        if ([string]::IsNullOrWhiteSpace($serverList)) {
            Write-OutputColor "  No servers specified. Cancelled." -color "Error"
            return
        }
        $script:ReplicaAllowedServers = @($serverList -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }

    # Step 3: Set storage path
    $defaultStorage = if ($script:HostVMStoragePath) { $script:HostVMStoragePath } else { "$env:SystemDrive\Hyper-V\Replica" }
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Default storage path for replica VMs (Enter for default: $defaultStorage):" -color "Info"
    $storagePath = Read-Host "  "
    $navResult = Test-NavigationCommand -UserInput $storagePath
    if ($navResult.ShouldReturn) { return }
    if (-not [string]::IsNullOrWhiteSpace($storagePath)) { $storagePath = $storagePath.Trim('"') }
    if ([string]::IsNullOrWhiteSpace($storagePath)) { $storagePath = $defaultStorage }

    # Ensure storage directory exists
    if (-not (Test-Path -LiteralPath $storagePath)) {
        try {
            New-Item -LiteralPath $storagePath -ItemType Directory -Force | Out-Null
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
    $lineStr = "  Storage Path: $storagePath"
    if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
    Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
    if ($script:ReplicaAllowedServers.Count -gt 0) {
        $lineStr = "  Allowed Servers: $($script:ReplicaAllowedServers -join ', ')"
        if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
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

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        # Re-entry: the full Set-VMReplicationServer + auth-entry registration
        # + firewall-rule configuration block runs at Commit. Operator state
        # (auth type, storage path, allowed-server list) is captured by
        # virtue of re-entering the function — those are read off
        # $script:ReplicaAllowedServers and the locals derived at the top.
        $capAuth    = $authType
        $capStorage = $storagePath
        $capAllowed = @($script:ReplicaAllowedServers)
        Push-DryRunStep -Label "Enable Hyper-V Replica Server ($capAuth, $capStorage)" -Category "Roles" -OneWay $false `
            -Params @{ AuthType = $capAuth; StoragePath = $capStorage; AllowedServers = $capAllowed } `
            -Preflight {
                if (-not (Test-HyperVInstalled)) { "Hyper-V not installed" }
                else { $true }
            } `
            -Apply { Enable-ReplicaServer } `
            -Undo  {
                Set-VMReplicationServer -ReplicationEnabled $false -ErrorAction SilentlyContinue
            }
        Write-OutputColor "  Queued (Dry-Run): enable Hyper-V Replica Server." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued Hyper-V Replica Server enable"
        return
    }

    # Execute
    try {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Configuring Hyper-V Replica Server..." -color "Info"

        # Wire the allow-list into Set-VMReplicationServer. The old code silently dropped
        # $script:ReplicaAllowedServers — calling Set-VMReplicationServer without
        # -ReplicationAllowedFromAnyServer left the server in the previous state (typically
        # trust-any-authenticated). When the user picked "Allow from specific servers only"
        # they got the EXACT OPPOSITE: an open replica receiver. Now: the per-server allow
        # list is honored by toggling -ReplicationAllowedFromAnyServer based on it AND
        # registering New-VMReplicationAuthorizationEntry rows for each allowed primary.
        $allowAny = ($script:ReplicaAllowedServers.Count -eq 0)
        Set-VMReplicationServer -ReplicationEnabled $true `
            -AllowedAuthenticationType $authType `
            -DefaultStorageLocation $storagePath `
            -ReplicationAllowedFromAnyServer $allowAny `
            -ErrorAction Stop

        if (-not $allowAny) {
            $trustGroup = "RackStackReplicaTrust"
            $authEntries = 0
            foreach ($svr in $script:ReplicaAllowedServers) {
                try {
                    # Remove any existing entry for this server first so re-running the wizard
                    # doesn't fail with "entry already exists".
                    Get-VMReplicationAuthorizationEntry -ErrorAction SilentlyContinue |
                        Where-Object { $_.AllowedPrimaryServer -eq $svr } |
                        ForEach-Object { Remove-VMReplicationAuthorizationEntry -AllowedPrimaryServer $svr -Confirm:$false -ErrorAction SilentlyContinue }
                    New-VMReplicationAuthorizationEntry -AllowedPrimaryServer $svr `
                        -ReplicaStorageLocation $storagePath `
                        -TrustGroup $trustGroup `
                        -ErrorAction Stop | Out-Null
                    $authEntries++
                } catch {
                    Write-OutputColor "  Warning: Could not register allow-list entry for '$svr': $($_.Exception.Message)" -color "Warning"
                }
            }
            Write-OutputColor "  Registered $authEntries allow-list entries (trust group: $trustGroup)." -color "Info"
        }

        # Configure firewall rules
        $fwErrors = 0
        foreach ($group in @("Hyper-V Replica HTTP", "Hyper-V Replica HTTPS")) {
            try {
                Enable-NetFirewallRule -DisplayGroup $group -ErrorAction Stop
            }
            catch {
                Write-OutputColor "  Warning: Could not enable '$group' firewall rules" -color "Warning"
                $fwErrors++
            }
        }

        Write-OutputColor "  Hyper-V Replica Server enabled successfully!" -color "Success"
        if ($fwErrors -eq 0) {
            Write-OutputColor "  Firewall rules for Hyper-V Replica have been enabled." -color "Info"
        } else {
            Write-OutputColor "  Firewall rules partially enabled ($fwErrors group(s) unavailable)." -color "Warning"
        }
        $allowDesc = if ($allowAny) { "any authenticated server" } else { "$($script:ReplicaAllowedServers.Count) allowed primary server(s)" }
        Add-SessionChange -Category "Hyper-V" -Description "Enabled Hyper-V Replica Server ($authType, storage: $storagePath, $allowDesc)"
        Clear-MenuCache
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
        $vms = @(Get-VM -ErrorAction Stop | Sort-Object Name)
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
        Write-OutputColor "  Invalid selection. Enter 1-$($vmIndex - 1)." -color "Error"
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
    $navResult = Test-NavigationCommand -UserInput $replicaServer
    if ($navResult.ShouldReturn) { return }
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
    $navResult = Test-NavigationCommand -UserInput $authChoice
    if ($navResult.ShouldReturn) { return }
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
    $navResult = Test-NavigationCommand -UserInput $freqChoice
    if ($navResult.ShouldReturn) { return }
    $freqSec = switch ($freqChoice) {
        "1" { 30 }
        "3" { 900 }
        default { 300 }
    }

    # RPO validation
    if ($freqSec -lt 30) {
        Write-OutputColor "  Minimum replication interval is 30 seconds." -color "Warning"
        $freqSec = 30
    }
    if ($freqSec -gt 900) {
        Write-OutputColor "  WARNING: RPO of $freqSec seconds means up to $([math]::Round($freqSec/60)) minutes of potential data loss" -color "Warning"
    }

    $freqDisplay = switch ($freqSec) {
        30  { "30 seconds" }
        300 { "5 minutes" }
        900 { "15 minutes" }
        default { "$freqSec seconds" }
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
    $navResult = Test-NavigationCommand -UserInput $initChoice
    if ($navResult.ShouldReturn) { return }
    # Confirm
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  REPLICATION CONFIGURATION SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    $vmLine = "  VM: $vmName"
    if ($vmLine.Length -gt 72) { $vmLine = $vmLine.Substring(0, 69) + "..." }
    Write-OutputColor "  │$($vmLine.PadRight(72))│" -color "Info"
    $lineStr = "  Replica Server: $replicaServer"
    if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
    Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Authentication: $authType (port $port)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Frequency: $freqDisplay".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Enable replication for VM '$vmName'?")) {
        Write-OutputColor "  Cancelled." -color "Info"
        return
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        # Re-entry: certificate selection + export path collection re-fire
        # at Commit. The queue captures the operator's intent (which VM,
        # which replica server, frequency, init method) but the per-step
        # interactive prompts run again at apply time. That preserves the
        # "no half-configured state on nav-return" guarantee already
        # documented in the apply path.
        $capVM      = $vmName
        $capReplica = $replicaServer
        $capFreq    = $freqDisplay
        Push-DryRunStep -Label "Enable replication for VM '$capVM' (replica: $capReplica, every $capFreq)" -Category "Roles" -OneWay $false `
            -Params @{ VM = $capVM; ReplicaServer = $capReplica; Frequency = $capFreq } `
            -Preflight {
                if (-not (Get-VM -Name $capVM -ErrorAction SilentlyContinue)) { "VM '$capVM' not found on this host" }
                else { $true }
            }.GetNewClosure() `
            -Apply { Enable-VMReplicationWizard } `
            -Undo  { Remove-VMReplication -VMName $capVM -ErrorAction SilentlyContinue }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): enable replication for VM '$capVM'." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued VM replication for '$capVM'"
        return
    }

    # Execute
    try {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Enabling replication for VM '$vmName'..." -color "Info"

        $replParams = @{
            VMName                = $vmName
            ReplicaServerName     = $replicaServer
            ReplicaServerPort     = $port
            AuthenticationType    = $authType
            ReplicationFrequencySec = $freqSec
            ErrorAction           = "Stop"
        }
        if ($authType -eq "Certificate") {
            Write-OutputColor "  Select a certificate for authentication:" -color "Info"
            # Hyper-V Replica terminates TLS in both directions during replication — the
            # certificate MUST advertise both Server Authentication (1.3.6.1.5.5.7.3.1) and
            # Client Authentication (1.3.6.1.5.5.7.3.2) EKUs, plus a private key, plus a
            # non-expired NotAfter. The prior filter (Server EKU + HasPrivateKey only) let
            # Server-only and already-expired certs through; Enable-VMReplication accepted
            # those at config time but Start-VMInitialReplication then rejected at runtime,
            # leaving VMs replication-enabled-but-never-replicating.
            $now = Get-Date
            $certs = @(Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.HasPrivateKey -and
                    $_.NotAfter -gt $now -and
                    ($_.EnhancedKeyUsageList.ObjectId -contains '1.3.6.1.5.5.7.3.1') -and
                    ($_.EnhancedKeyUsageList.ObjectId -contains '1.3.6.1.5.5.7.3.2')
                })
            if ($certs.Count -eq 0) {
                Write-OutputColor "  No suitable certificates found in Local Machine\Personal store." -color "Error"
                Write-OutputColor "  Certificate must have a private key, both Server AND Client Authentication EKUs, and a future NotAfter." -color "Info"
                return
            }
            for ($ci = 0; $ci -lt $certs.Count; $ci++) {
                Write-OutputColor "  [$($ci + 1)] $($certs[$ci].Subject) (Expires: $($certs[$ci].NotAfter.ToString('yyyy-MM-dd')))" -color "Info"
            }
            $certChoice = Read-Host "  Select certificate"
            $navResult = Test-NavigationCommand -UserInput $certChoice
            if ($navResult.ShouldReturn) { return }
            if ($certChoice -match '^\d+$' -and [int]$certChoice -ge 1 -and [int]$certChoice -le $certs.Count) {
                $replParams.CertificateThumbprint = $certs[[int]$certChoice - 1].Thumbprint
            } else {
                Write-OutputColor "  Invalid selection." -color "Error"
                return
            }
        }
        # Collect the export path BEFORE enabling replication so a nav-return on the
        # prompt doesn't leave the VM in a half-configured state (replication enabled
        # but no initial replication started).
        $exportPath = $null
        if ($initChoice -eq "2") {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Enter export path for external media:" -color "Info"
            $exportPath = Read-Host "  "
            $navResult = Test-NavigationCommand -UserInput $exportPath
            if ($navResult.ShouldReturn) { return }
            if (-not [string]::IsNullOrWhiteSpace($exportPath)) { $exportPath = $exportPath.Trim('"') }
            if ([string]::IsNullOrWhiteSpace($exportPath)) { $exportPath = "$env:SystemDrive\Hyper-V\ReplicaExport" }
        }

        Enable-VMReplication @replParams

        Write-OutputColor "  Replication enabled. Starting initial replication..." -color "Info"

        if ($initChoice -eq "2") {
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
        Clear-MenuCache
    }
    catch {
        Write-RackStackError -Code "RS-5008" -Detail "VM replication enable failed for '$vmName' to '$replicaServer': $($_.Exception.Message)"
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

    # Check replica server status (tri-state — see Test-HyperVReplicaEnabled docstring)
    $replicaEnabled = Test-HyperVReplicaEnabled
    if ($replicaEnabled -eq $true) {
        Write-OutputColor "  Replica Server: Enabled" -color "Success"
    }
    elseif ($null -eq $replicaEnabled) {
        Write-OutputColor "  Replica Server: Probe failed (Hyper-V WMI provider unavailable)" -color "Error"
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
            # Measure-VMReplication issues RPC to the replica server. If the replica is
            # unreachable the call blocks for the default WMI/RPC timeout (~10 min) and the
            # menu hangs. Wrap in Start-Job + 15s Wait-Job so an unreachable replica produces
            # a clean "(unreachable)" line instead of freezing the dashboard.
            $vmNameForJob = $repl.VMName
            $measureJob = Start-Job -ScriptBlock {
                param($n) Measure-VMReplication -VMName $n -ErrorAction SilentlyContinue
            } -ArgumentList $vmNameForJob
            $completed = Wait-Job -Job $measureJob -Timeout 15
            $stats = if ($null -ne $completed) { Receive-Job -Job $measureJob -ErrorAction SilentlyContinue } else { $null }
            Stop-Job -Job $measureJob -ErrorAction SilentlyContinue
            Remove-Job -Job $measureJob -Force -ErrorAction SilentlyContinue
            if ($null -eq $completed) {
                Write-OutputColor "  │$("  $($repl.VMName): replica unreachable (15s timeout)".PadRight(72))│" -color "Warning"
                continue
            }
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

                $lineStr = "  $($repl.VMName)"
                if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
                Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
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

# Pre-flight checks before initiating failover
function Test-FailoverPreFlight {
    param (
        [Parameter(Mandatory=$true)]
        [string]$VMName,
        [Parameter(Mandatory=$true)]
        $ReplicationInfo,
        [switch]$IsPlanned
    )

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  FAILOVER PRE-FLIGHT CHECKS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $issueCount = 0

    # Check 1: Replica VM state — compare enum integers (invariant) instead of localized strings.
    # Past pattern: localized .ToString() on non-EN Hyper-V hosts made every check fall through
    # to the catch-all, pre-flight reported "all checks passed" against a Critical-health VM,
    # and the operator authorized a failover against stale data.
    $stateInt = -1
    try { $stateInt = [int]$ReplicationInfo.State } catch { }
    $healthInt = -1
    try { $healthInt = [int]$ReplicationInfo.ReplicationHealth } catch { }
    # State enum: 1=Disabled, 2=ReadyForInitialReplication, 3=WaitingForInitialReplication,
    # 4=InitialReplicationInProgress, 5=WaitingForUpdates, 6=Replicating, 7=PreparedForFailover,
    # 8=Resynchronizing, 9=Suspended, 10=Error, 11=FailedOverWaitingCompletion, 12=FailedOver,
    # 13=...
    $replStateDisplay = "$($ReplicationInfo.State)"
    if ($stateInt -in @(6, 2, 3)) {
        Write-OutputColor "  │$("  [OK]   Replication state: $replStateDisplay".PadRight(72))│" -color "Success"
    }
    else {
        $lineStr = "  [WARN] Replication state: $replStateDisplay"
        if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Warning"
        $issueCount++
    }

    # Check 2: Replication health (1=Normal, 2=Warning, 3=Critical)
    $replHealthDisplay = "$($ReplicationInfo.ReplicationHealth)"
    if ($healthInt -eq 1) {
        Write-OutputColor "  │$("  [OK]   Replication health: Normal".PadRight(72))│" -color "Success"
    }
    elseif ($healthInt -eq 2) {
        Write-OutputColor "  │$("  [WARN] Replication health: Warning".PadRight(72))│" -color "Warning"
        $issueCount++
    }
    else {
        Write-OutputColor "  │$("  [CRIT] Replication health: $replHealthDisplay (int=$healthInt)".PadRight(72))│" -color "Error"
        $issueCount++
    }

    # Check 3: Network connectivity to replica server
    $replicaServer = "$($ReplicationInfo.ReplicaServerName)"
    if (-not [string]::IsNullOrWhiteSpace($replicaServer)) {
        $pingOk = $false
        try {
            $pingResult = Test-Connection -ComputerName $replicaServer -Count 1 -Quiet -ErrorAction SilentlyContinue
            $pingOk = $pingResult
        }
        catch {
            $pingOk = $false
        }
        if ($pingOk) {
            $lineStr = "  [OK]   Replica server reachable: $replicaServer"
            if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Success"
        }
        else {
            $lineStr = "  [WARN] Replica server unreachable: $replicaServer"
            if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Warning"
            $issueCount++
        }
    }

    # Check 4: Last replication time and potential data loss
    if ($null -ne $ReplicationInfo.LastReplicationTime -and $ReplicationInfo.LastReplicationTime -ne [DateTime]::MinValue) {
        $lastSync = $ReplicationInfo.LastReplicationTime
        $lag = (Get-Date) - $lastSync
        $lastSyncStr = $lastSync.ToString("yyyy-MM-dd HH:mm:ss")
        Write-OutputColor "  │$("  Last successful replication: $lastSyncStr".PadRight(72))│" -color "Info"

        if (-not $IsPlanned -and $lag.TotalMinutes -gt 5) {
            $lagStr = "  [WARN] Potential data loss: ~$([math]::Round($lag.TotalMinutes)) minutes"
            if ($lagStr.Length -gt 69) { $lagStr = $lagStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lagStr.PadRight(72))│" -color "Warning"
            $issueCount++
        }
    }
    else {
        Write-OutputColor "  │$("  [WARN] No successful replication recorded".PadRight(72))│" -color "Warning"
        if (-not $IsPlanned) {
            Write-OutputColor "  │$("         Unplanned failover may result in significant data loss".PadRight(72))│" -color "Warning"
        }
        $issueCount++
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    if ($issueCount -gt 0) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  $issueCount issue(s) detected. Review before proceeding." -color "Warning"
    }
    else {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  All pre-flight checks passed." -color "Success"
    }

    return $issueCount
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
        Write-OutputColor "  Invalid selection. Enter 1-$($vmIndex - 1)." -color "Error"
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

    # Failover pre-flight checks
    $preFlightIssues = Test-FailoverPreFlight -VMName $vmName -ReplicationInfo $selectedRepl
    if ($preFlightIssues -gt 0) {
        if (-not (Confirm-UserAction -Message "Continue despite $preFlightIssues issue(s)?")) {
            Write-OutputColor "  Cancelled." -color "Info"
            return
        }
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
        Clear-MenuCache

        # Offer to clean up now or later
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [C] Clean up test failover now" -color "Info"
        Write-OutputColor "  [L] Leave running for manual testing" -color "Info"
        Write-OutputColor "" -color "Info"
        $cleanChoice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $cleanChoice
        if ($navResult.ShouldReturn) { return }

        if ($cleanChoice -eq "C" -or $cleanChoice -eq "c") {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Cleaning up test failover..." -color "Info"
            Stop-VMFailover -VMName $vmName -ErrorAction Stop
            Write-OutputColor "  Test failover cleaned up successfully." -color "Success"
            Add-SessionChange -Category "Hyper-V" -Description "Cleaned up test failover for VM '$vmName'"
            Clear-MenuCache
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
        Write-OutputColor "  Invalid selection. Enter 1-$($vmIndex - 1)." -color "Error"
        return
    }

    $selectedRepl = $vmMap[$vmChoice]
    $vmName = $selectedRepl.VMName

    # Failover pre-flight checks
    $preFlightIssues = Test-FailoverPreFlight -VMName $vmName -ReplicationInfo $selectedRepl -IsPlanned
    if ($preFlightIssues -gt 0) {
        if (-not (Confirm-UserAction -Message "Continue despite $preFlightIssues issue(s)?")) {
            Write-OutputColor "  Cancelled." -color "Info"
            return
        }
    }

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
                # Planned failover is a "no data loss" operation, but `Stop-VM -Force` does a hard
                # turn-off (power cut) — dirty pages and pending I/O are lost. Attempt a graceful
                # guest-OS shutdown first with a 5-minute bound; only fall through to hard-stop if
                # the operator opts in after the timeout.
                Write-OutputColor "  Initiating graceful shutdown (up to 5 minutes)..." -color "Info"
                $gracefulSucceeded = $false
                try {
                    Stop-VM -Name $vmName -ErrorAction Stop
                    $deadline = (Get-Date).AddMinutes(5)
                    while ((Get-Date) -lt $deadline) {
                        Start-Sleep -Seconds 5
                        $vmState = (Get-VM -Name $vmName -ErrorAction SilentlyContinue).State
                        if ($vmState -eq 'Off') { $gracefulSucceeded = $true; break }
                    }
                } catch {
                    Write-OutputColor "  Graceful shutdown command failed: $($_.Exception.Message)" -color "Warning"
                }
                if (-not $gracefulSucceeded) {
                    Write-OutputColor "  Graceful shutdown did not complete within 5 minutes." -color "Warning"
                    if (Confirm-UserAction -Message "Force power-off VM (data loss risk)?") {
                        Stop-VM -Name $vmName -Force -ErrorAction Stop
                        Write-OutputColor "  VM force-stopped — uncommitted writes may be lost on the replica side." -color "Warning"
                    } else {
                        Write-OutputColor "  Cancelled. Resolve the shutdown issue and retry." -color "Info"
                        return
                    }
                } else {
                    Write-OutputColor "  VM shut down gracefully." -color "Success"
                }
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
        Clear-MenuCache
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
        Write-OutputColor "  Invalid selection. Enter 1-$($vmIndex - 1)." -color "Error"
        return
    }

    $selectedRepl = $vmMap[$vmChoice]
    $vmName = $selectedRepl.VMName

    # Get the original primary server
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enter the original primary server name (to become the new replica):" -color "Info"
    $originalServer = Read-Host "  "
    $navResult = Test-NavigationCommand -UserInput $originalServer
    if ($navResult.ShouldReturn) { return }
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

        Set-VMReplication -VMName $vmName -Reverse -ErrorAction Stop

        Write-OutputColor "  Reverse replication configured successfully!" -color "Success"
        Write-OutputColor "  VM '$vmName' replication direction has been reversed." -color "Info"
        Add-SessionChange -Category "Hyper-V" -Description "Reversed replication for VM '$vmName'"
        Clear-MenuCache
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
        Write-OutputColor "  Invalid selection. Enter 1-$($vmIndex - 1)." -color "Error"
        return
    }

    $selectedRepl = $vmMap[$vmChoice]
    $vmName = $selectedRepl.VMName

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  VM: $vmName" -color "Info"
    Write-OutputColor "  Mode: $($selectedRepl.Mode)" -color "Info"
    Write-OutputColor "  State: $($selectedRepl.State)" -color "Info"
    Write-OutputColor "" -color "Info"

    # Refuse removal during failover-in-progress states. Removing replication mid-failover
    # breaks the role pairing — Complete-VMFailover on the replica becomes impossible without
    # manual fixup, and a full resync from scratch is needed.
    $stateIntForRemove = -1
    try { $stateIntForRemove = [int]$selectedRepl.State } catch { }
    if ($stateIntForRemove -in @(7, 11)) {  # 7=PreparedForFailover, 11=FailedOverWaitingCompletion
        Write-OutputColor "" -color "Error"
        Write-OutputColor "  REFUSING: VM is in transitional failover state ($($selectedRepl.State))." -color "Error"
        Write-OutputColor "  Running Remove-VMReplication now strands the role pairing. Complete the" -color "Error"
        Write-OutputColor "  failover via Complete-VMFailover first, then retry the remove." -color "Warning"
        return
    }

    # Warn explicitly when operator is on the Replica side — Remove-VMReplication here only
    # wipes the receiver's config. The primary still thinks replication is active and will
    # fail on the next cycle. Operator likely wants to clean up on the primary instead.
    $modeStr = "$($selectedRepl.Mode)"
    if ($modeStr -eq 'Replica') {
        Write-OutputColor "" -color "Warning"
        Write-OutputColor "  CAUTION: '$vmName' is the REPLICA side of this replication." -color "Warning"
        Write-OutputColor "  Remove here only wipes the receiver. The PRIMARY still thinks replication" -color "Warning"
        Write-OutputColor "  is active and will report errors on the next cycle. To fully tear down," -color "Warning"
        Write-OutputColor "  remove from the primary host as well." -color "Info"
        Write-OutputColor "  Type REMOVE-REPLICA-ONLY to confirm (Enter to cancel):" -color "Warning"
        $replConfirm = Read-Host
        if ($replConfirm -ne 'REMOVE-REPLICA-ONLY') {
            Write-OutputColor "  Cancelled." -color "Info"
            return
        }
    }

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
        Clear-MenuCache
    }
    catch {
        Write-OutputColor "  Failed to remove replication: $_" -color "Error"
    }
}
#endregion
