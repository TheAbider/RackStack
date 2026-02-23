#region ===== FIREWALL RULE TEMPLATES =====
# Function to apply firewall rule templates
function Set-FirewallRuleTemplates {
    while ($true) {
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                      FIREWALL RULE TEMPLATES").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  AVAILABLE TEMPLATES".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  Hyper-V Host Rules"
        Write-MenuItem "[2]  Failover Cluster Rules"
        Write-MenuItem "[3]  Hyper-V Replica Rules"
        Write-MenuItem "[4]  Live Migration Rules"
        Write-MenuItem "[5]  iSCSI Rules"
        Write-MenuItem "[6]  SMB/File Sharing Rules"
        Write-MenuItem "[7]  View Current Hyper-V/Cluster Rules"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" { Enable-HyperVFirewallRules }
            "2" { Enable-ClusterFirewallRules }
            "3" { Enable-ReplicaFirewallRules }
            "4" { Enable-LiveMigrationFirewallRules }
            "5" { Enable-iSCSIFirewallRules }
            "6" { Enable-SMBFirewallRules }
            "7" { Show-HyperVClusterFirewallRules }
            "b" { return }
            "B" { return }
            default { Write-OutputColor "  Invalid choice." -color "Error"; Start-Sleep -Seconds 1 }
        }

        Write-PressEnter
    }
}

function Enable-HyperVFirewallRules {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enabling Hyper-V firewall rules..." -color "Info"
    try {
        Enable-NetFirewallRule -DisplayGroup "Hyper-V" -ErrorAction SilentlyContinue
        Enable-NetFirewallRule -DisplayGroup "Hyper-V Management Clients" -ErrorAction SilentlyContinue
        Enable-NetFirewallRule -DisplayGroup "Hyper-V Replica HTTP" -ErrorAction SilentlyContinue
        Enable-NetFirewallRule -DisplayGroup "Hyper-V Replica HTTPS" -ErrorAction SilentlyContinue
        Write-OutputColor "  Hyper-V firewall rules enabled." -color "Success"
        Add-SessionChange -Category "Security" -Description "Enabled Hyper-V firewall rules"
    }
    catch {
        Write-OutputColor "  Error: $_" -color "Error"
    }
}

function Enable-ClusterFirewallRules {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enabling Failover Cluster firewall rules..." -color "Info"
    try {
        Enable-NetFirewallRule -DisplayGroup "Failover Clusters" -ErrorAction SilentlyContinue
        # Cluster communication ports
        $clusterRules = @(
            @{ Name = "Cluster-RPC"; Port = 135; Protocol = "TCP" }
            @{ Name = "Cluster-RPC-Dynamic"; Port = "49152-65535"; Protocol = "TCP" }
            @{ Name = "Cluster-UDP"; Port = 3343; Protocol = "UDP" }
        )
        foreach ($rule in $clusterRules) {
            $existingRule = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
            if (-not $existingRule) {
                New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound -Protocol $rule.Protocol -LocalPort $rule.Port -Action Allow -Profile Domain,Private -ErrorAction SilentlyContinue | Out-Null
            }
        }
        Write-OutputColor "  Failover Cluster firewall rules enabled." -color "Success"
        Add-SessionChange -Category "Security" -Description "Enabled Failover Cluster firewall rules"
    }
    catch {
        Write-OutputColor "  Error: $_" -color "Error"
    }
}

function Enable-ReplicaFirewallRules {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enabling Hyper-V Replica firewall rules..." -color "Info"
    try {
        Enable-NetFirewallRule -DisplayGroup "Hyper-V Replica HTTP" -ErrorAction SilentlyContinue
        Enable-NetFirewallRule -DisplayGroup "Hyper-V Replica HTTPS" -ErrorAction SilentlyContinue
        # Replica ports
        $replicaRule80 = Get-NetFirewallRule -DisplayName "Hyper-V Replica HTTP 80" -ErrorAction SilentlyContinue
        if (-not $replicaRule80) {
            New-NetFirewallRule -DisplayName "Hyper-V Replica HTTP 80" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow -Profile Domain,Private -ErrorAction SilentlyContinue | Out-Null
        }
        $replicaRule443 = Get-NetFirewallRule -DisplayName "Hyper-V Replica HTTPS 443" -ErrorAction SilentlyContinue
        if (-not $replicaRule443) {
            New-NetFirewallRule -DisplayName "Hyper-V Replica HTTPS 443" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow -Profile Domain,Private -ErrorAction SilentlyContinue | Out-Null
        }
        Write-OutputColor "  Hyper-V Replica firewall rules enabled." -color "Success"
        Add-SessionChange -Category "Security" -Description "Enabled Hyper-V Replica firewall rules"
    }
    catch {
        Write-OutputColor "  Error: $_" -color "Error"
    }
}

function Enable-LiveMigrationFirewallRules {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enabling Live Migration firewall rules..." -color "Info"
    try {
        Enable-NetFirewallRule -DisplayGroup "Hyper-V" -ErrorAction SilentlyContinue
        # Live Migration port
        $lmRule = Get-NetFirewallRule -DisplayName "Hyper-V Live Migration" -ErrorAction SilentlyContinue
        if (-not $lmRule) {
            New-NetFirewallRule -DisplayName "Hyper-V Live Migration" -Direction Inbound -Protocol TCP -LocalPort 6600 -Action Allow -Profile Domain,Private -ErrorAction SilentlyContinue | Out-Null
        }
        # SMB for shared-nothing live migration
        Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing" -ErrorAction SilentlyContinue
        Write-OutputColor "  Live Migration firewall rules enabled." -color "Success"
        Add-SessionChange -Category "Security" -Description "Enabled Live Migration firewall rules"
    }
    catch {
        Write-OutputColor "  Error: $_" -color "Error"
    }
}

function Enable-iSCSIFirewallRules {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enabling iSCSI firewall rules..." -color "Info"
    try {
        Enable-NetFirewallRule -DisplayGroup "iSCSI Service" -ErrorAction SilentlyContinue
        $iscsiRule = Get-NetFirewallRule -DisplayName "iSCSI Target" -ErrorAction SilentlyContinue
        if (-not $iscsiRule) {
            New-NetFirewallRule -DisplayName "iSCSI Target" -Direction Inbound -Protocol TCP -LocalPort 3260 -Action Allow -Profile Domain,Private -ErrorAction SilentlyContinue | Out-Null
        }
        Write-OutputColor "  iSCSI firewall rules enabled." -color "Success"
        Add-SessionChange -Category "Security" -Description "Enabled iSCSI firewall rules"
    }
    catch {
        Write-OutputColor "  Error: $_" -color "Error"
    }
}

function Enable-SMBFirewallRules {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enabling SMB/File Sharing firewall rules..." -color "Info"
    try {
        Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing" -ErrorAction SilentlyContinue
        Enable-NetFirewallRule -DisplayGroup "Netlogon Service" -ErrorAction SilentlyContinue
        Write-OutputColor "  SMB/File Sharing firewall rules enabled." -color "Success"
        Add-SessionChange -Category "Security" -Description "Enabled SMB firewall rules"
    }
    catch {
        Write-OutputColor "  Error: $_" -color "Error"
    }
}

function Show-HyperVClusterFirewallRules {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  HYPER-V & CLUSTER FIREWALL RULES".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $groups = @("Hyper-V", "Hyper-V Management Clients", "Hyper-V Replica HTTP", "Hyper-V Replica HTTPS", "Failover Clusters", "iSCSI Service", "File and Printer Sharing")

    foreach ($group in $groups) {
        $rules = Get-NetFirewallRule -DisplayGroup $group -ErrorAction SilentlyContinue
        if ($rules) {
            $enabledCount = ($rules | Where-Object { $_.Enabled -eq $true }).Count
            $totalCount = $rules.Count
            $status = if ($enabledCount -eq $totalCount) { "All Enabled" } elseif ($enabledCount -gt 0) { "$enabledCount/$totalCount Enabled" } else { "Disabled" }
            $color = if ($enabledCount -eq $totalCount) { "Success" } elseif ($enabledCount -gt 0) { "Warning" } else { "Error" }
            Write-OutputColor "  │$("  $group : $status".PadRight(72))│" -color $color
        }
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-PressEnter
}
#endregion