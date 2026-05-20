#region ===== FIREWALL RULE TEMPLATES =====
# Function to apply firewall rule templates
function Set-FirewallRuleTemplates {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                      FIREWALL RULE TEMPLATES").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  AVAILABLE TEMPLATES".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  SERVER ROLES".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  Hyper-V Host Rules"
        Write-MenuItem "[2]  Failover Cluster Rules"
        Write-MenuItem "[3]  Hyper-V Replica Rules"
        Write-MenuItem "[4]  Live Migration Rules"
        Write-MenuItem "[5]  iSCSI Rules"
        Write-MenuItem "[6]  SMB/File Sharing Rules"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  REMOTE ACCESS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[7]  Remote Desktop (RDP)"
        Write-MenuItem "[8]  Windows Remote Management (WinRM)"
        Write-MenuItem "[9]  Allow Ping (ICMP Echo Request)"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  INFRASTRUCTURE SERVICES".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[10] NTP Time Sync (UDP 123)"
        Write-MenuItem "[11] SNMP Monitoring (UDP 161)"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  TOOLS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[12] View Current Hyper-V/Cluster Rules"
        Write-MenuItem "[13] Compare Rules Against Template"
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
            "7" { Enable-RDPFirewallRules }
            "8" { Enable-WinRMFirewallRules }
            "9" { Enable-ICMPPingRules }
            "10" { Enable-NTPFirewallRules }
            "11" { Enable-SNMPFirewallRules }
            "12" { Show-HyperVClusterFirewallRules }
            "13" { Invoke-FirewallTemplateComparison }
            { $_ -eq "b" -or $_ -eq "B" } { return }
            default { Write-OutputColor "  Invalid choice. Enter 1-13 or B." -color "Error"; Start-Sleep -Seconds 1 }
        }

        Write-PressEnter
    }
}

function Enable-HyperVFirewallRules {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enabling Hyper-V firewall rules..." -color "Info"
    $fwErrors = 0
    foreach ($group in @("Hyper-V", "Hyper-V Management Clients", "Hyper-V Replica HTTP", "Hyper-V Replica HTTPS")) {
        try {
            Enable-NetFirewallRule -DisplayGroup $group -ErrorAction Stop
        }
        catch {
            Write-OutputColor "  Warning: Could not enable '$group' rules: $_" -color "Warning"
            $fwErrors++
        }
    }
    if ($fwErrors -eq 0) {
        Write-OutputColor "  Hyper-V firewall rules enabled." -color "Success"
    } else {
        Write-OutputColor "  Hyper-V rules partially enabled ($fwErrors group(s) unavailable)." -color "Warning"
    }
    Add-SessionChange -Category "Security" -Description "Enabled Hyper-V firewall rules"
    Clear-MenuCache
    Add-UndoAction -Category "Security" -Description "Enabled Hyper-V firewall rules" -UndoScript {
        foreach ($group in @("Hyper-V", "Hyper-V Management Clients", "Hyper-V Replica HTTP", "Hyper-V Replica HTTPS")) {
            Disable-NetFirewallRule -DisplayGroup $group -ErrorAction SilentlyContinue
        }
    }
}

function Enable-ClusterFirewallRules {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enabling Failover Cluster firewall rules..." -color "Info"
    try {
        Enable-NetFirewallRule -DisplayGroup "Failover Clusters" -ErrorAction Stop
    }
    catch {
        Write-OutputColor "  Warning: Could not enable 'Failover Clusters' rules: $_" -color "Warning"
    }
    # Cluster communication ports
    $clusterRules = @(
        @{ Name = "Cluster-RPC"; Port = 135; Protocol = "TCP" }
        @{ Name = "Cluster-RPC-Dynamic"; Port = "49152-65535"; Protocol = "TCP" }
        @{ Name = "Cluster-UDP"; Port = 3343; Protocol = "UDP" }
    )
    foreach ($rule in $clusterRules) {
        $existingRule = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
        if (-not $existingRule) {
            try {
                New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound -Protocol $rule.Protocol -LocalPort $rule.Port -Action Allow -Profile Domain,Private -ErrorAction Stop | Out-Null
            }
            catch {
                Write-OutputColor "  Warning: Failed to create rule '$($rule.Name)': $_" -color "Error"
            }
        }
    }
    Write-OutputColor "  Failover Cluster firewall rules enabled." -color "Success"
    Add-SessionChange -Category "Security" -Description "Enabled Failover Cluster firewall rules"
    Clear-MenuCache
    Add-UndoAction -Category "Security" -Description "Enabled Failover Cluster firewall rules" -UndoScript {
        Disable-NetFirewallRule -DisplayGroup "Failover Clusters" -ErrorAction SilentlyContinue
        foreach ($name in @("Cluster-RPC", "Cluster-RPC-Dynamic", "Cluster-UDP")) {
            Remove-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
        }
    }
}

function Enable-ReplicaFirewallRules {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enabling Hyper-V Replica firewall rules..." -color "Info"
    foreach ($group in @("Hyper-V Replica HTTP", "Hyper-V Replica HTTPS")) {
        try { Enable-NetFirewallRule -DisplayGroup $group -ErrorAction Stop }
        catch { Write-OutputColor "  Warning: Could not enable '$group' rules: $_" -color "Warning" }
    }
    # Replica ports
    foreach ($ruleInfo in @(@{Name="Hyper-V Replica HTTP 80"; Port=80}, @{Name="Hyper-V Replica HTTPS 443"; Port=443})) {
        $existing = Get-NetFirewallRule -DisplayName $ruleInfo.Name -ErrorAction SilentlyContinue
        if (-not $existing) {
            try {
                New-NetFirewallRule -DisplayName $ruleInfo.Name -Direction Inbound -Protocol TCP -LocalPort $ruleInfo.Port -Action Allow -Profile Domain,Private -ErrorAction Stop | Out-Null
            }
            catch { Write-OutputColor "  Warning: Failed to create rule '$($ruleInfo.Name)': $_" -color "Error" }
        }
    }
    Write-OutputColor "  Hyper-V Replica firewall rules enabled." -color "Success"
    Add-SessionChange -Category "Security" -Description "Enabled Hyper-V Replica firewall rules"
    Clear-MenuCache
    Add-UndoAction -Category "Security" -Description "Enabled Hyper-V Replica firewall rules" -UndoScript {
        foreach ($group in @("Hyper-V Replica HTTP", "Hyper-V Replica HTTPS")) {
            Disable-NetFirewallRule -DisplayGroup $group -ErrorAction SilentlyContinue
        }
        foreach ($name in @("Hyper-V Replica HTTP 80", "Hyper-V Replica HTTPS 443")) {
            Remove-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
        }
    }
}

function Enable-LiveMigrationFirewallRules {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enabling Live Migration firewall rules..." -color "Info"

    # Snapshot rules that were DISABLED before this run so undo only re-disables what we enabled.
    # Past pattern: undo blindly disabled the entire "Hyper-V" + "File and Printer Sharing" groups,
    # which on a running production host severed all Hyper-V management traffic (Replica HTTP/S,
    # management clients, VM authentication) and broke any tenant SMB shares — far beyond what
    # the enable did. Capture the pre-state so undo is precise.
    $rulesEnabledByUs = @()
    foreach ($group in @("Hyper-V", "File and Printer Sharing")) {
        try {
            $preDisabled = @(Get-NetFirewallRule -DisplayGroup $group -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq $false })
            Enable-NetFirewallRule -DisplayGroup $group -ErrorAction Stop
            $rulesEnabledByUs += @($preDisabled | ForEach-Object { $_.Name })
        }
        catch { Write-OutputColor "  Warning: Could not enable '$group' rules: $_" -color "Warning" }
    }
    # Live Migration port
    $lmCreated = $false
    $lmRule = Get-NetFirewallRule -DisplayName "Hyper-V Live Migration" -ErrorAction SilentlyContinue
    if (-not $lmRule) {
        try {
            New-NetFirewallRule -DisplayName "Hyper-V Live Migration" -Direction Inbound -Protocol TCP -LocalPort 6600 -Action Allow -Profile Domain,Private -ErrorAction Stop | Out-Null
            $lmCreated = $true
        }
        catch { Write-OutputColor "  Warning: Failed to create Live Migration rule: $_" -color "Error" }
    }
    Write-OutputColor "  Live Migration firewall rules enabled." -color "Success"
    Add-SessionChange -Category "Security" -Description "Enabled Live Migration firewall rules"
    Clear-MenuCache
    Add-UndoAction -Category "Security" -Description "Enabled Live Migration firewall rules" -UndoScript {
        param($EnabledRules, $LmCreated)
        if ($EnabledRules) {
            foreach ($n in $EnabledRules) {
                Disable-NetFirewallRule -Name $n -ErrorAction SilentlyContinue
            }
        }
        if ($LmCreated) {
            Remove-NetFirewallRule -DisplayName "Hyper-V Live Migration" -ErrorAction SilentlyContinue
        }
    }.GetNewClosure() -UndoParams @{ EnabledRules = $rulesEnabledByUs; LmCreated = $lmCreated }
}

function Enable-iSCSIFirewallRules {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enabling iSCSI firewall rules..." -color "Info"
    try { Enable-NetFirewallRule -DisplayGroup "iSCSI Service" -ErrorAction Stop }
    catch { Write-OutputColor "  Warning: Could not enable 'iSCSI Service' rules: $_" -color "Warning" }
    $iscsiRule = Get-NetFirewallRule -DisplayName "iSCSI Target" -ErrorAction SilentlyContinue
    if (-not $iscsiRule) {
        try {
            New-NetFirewallRule -DisplayName "iSCSI Target" -Direction Inbound -Protocol TCP -LocalPort 3260 -Action Allow -Profile Domain,Private -ErrorAction Stop | Out-Null
        }
        catch { Write-OutputColor "  Warning: Failed to create iSCSI Target rule: $_" -color "Error" }
    }
    Write-OutputColor "  iSCSI firewall rules enabled." -color "Success"
    Add-SessionChange -Category "Security" -Description "Enabled iSCSI firewall rules"
    Clear-MenuCache
    Add-UndoAction -Category "Security" -Description "Enabled iSCSI firewall rules" -UndoScript {
        Disable-NetFirewallRule -DisplayGroup "iSCSI Service" -ErrorAction SilentlyContinue
        Remove-NetFirewallRule -DisplayName "iSCSI Target" -ErrorAction SilentlyContinue
    }
}

function Enable-SMBFirewallRules {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enabling SMB/File Sharing firewall rules..." -color "Info"
    foreach ($group in @("File and Printer Sharing", "Netlogon Service")) {
        try { Enable-NetFirewallRule -DisplayGroup $group -ErrorAction Stop }
        catch { Write-OutputColor "  Warning: Could not enable '$group' rules: $_" -color "Warning" }
    }
    Write-OutputColor "  SMB/File Sharing firewall rules enabled." -color "Success"
    Add-SessionChange -Category "Security" -Description "Enabled SMB firewall rules"
    Clear-MenuCache
    Add-UndoAction -Category "Security" -Description "Enabled SMB firewall rules" -UndoScript {
        foreach ($group in @("File and Printer Sharing", "Netlogon Service")) {
            Disable-NetFirewallRule -DisplayGroup $group -ErrorAction SilentlyContinue
        }
    }
}

function Enable-RDPFirewallRules {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enabling Remote Desktop (RDP) firewall rules..." -color "Info"
    $fwErrors = 0

    # Enable built-in RDP rule group
    try {
        Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction Stop
        Write-OutputColor "  Enabled built-in Remote Desktop rules." -color "Success"
    }
    catch {
        Write-OutputColor "  Warning: Could not enable 'Remote Desktop' rules: $_" -color "Warning"
        $fwErrors++
    }

    # Ensure custom RDP rule exists as fallback
    $rdpRule = Get-NetFirewallRule -DisplayName "RDP Inbound TCP 3389" -ErrorAction SilentlyContinue
    if (-not $rdpRule) {
        try {
            New-NetFirewallRule -DisplayName "RDP Inbound TCP 3389" -Direction Inbound `
                -Protocol TCP -LocalPort 3389 -Action Allow -Profile Domain,Private `
                -Description "Allow inbound RDP connections" -ErrorAction Stop | Out-Null
            Write-OutputColor "  Created: RDP Inbound TCP 3389 (Domain, Private)" -color "Success"
        }
        catch {
            Write-OutputColor "  Warning: Failed to create RDP rule: $_" -color "Warning"
            $fwErrors++
        }
    }

    # Also enable UDP 3389 for RDP UDP transport (faster in Windows 10+/Server 2016+)
    $rdpUdp = Get-NetFirewallRule -DisplayName "RDP Inbound UDP 3389" -ErrorAction SilentlyContinue
    if (-not $rdpUdp) {
        try {
            New-NetFirewallRule -DisplayName "RDP Inbound UDP 3389" -Direction Inbound `
                -Protocol UDP -LocalPort 3389 -Action Allow -Profile Domain,Private `
                -Description "Allow inbound RDP UDP transport" -ErrorAction Stop | Out-Null
            Write-OutputColor "  Created: RDP Inbound UDP 3389 (Domain, Private)" -color "Success"
        }
        catch {
            Write-OutputColor "  Warning: Failed to create RDP UDP rule: $_" -color "Warning"
            $fwErrors++
        }
    }

    if ($fwErrors -eq 0) {
        Write-OutputColor "  Remote Desktop firewall rules enabled." -color "Success"
    } else {
        Write-OutputColor "  RDP rules partially enabled ($fwErrors issue(s))." -color "Warning"
    }
    Add-SessionChange -Category "Security" -Description "Enabled Remote Desktop (RDP) firewall rules"
    Clear-MenuCache
    Add-UndoAction -Category "Security" -Description "Enabled RDP firewall rules" -UndoScript {
        Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
        Remove-NetFirewallRule -DisplayName "RDP Inbound TCP 3389" -ErrorAction SilentlyContinue
        Remove-NetFirewallRule -DisplayName "RDP Inbound UDP 3389" -ErrorAction SilentlyContinue
    }
}

function Enable-WinRMFirewallRules {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enabling Windows Remote Management (WinRM) firewall rules..." -color "Info"
    $fwErrors = 0

    # Enable built-in WinRM rule group
    foreach ($group in @("Windows Remote Management", "Windows Remote Management (HTTP-In)")) {
        try {
            Enable-NetFirewallRule -DisplayGroup $group -ErrorAction Stop
            Write-OutputColor "  Enabled built-in '$group' rules." -color "Success"
        }
        catch {
            # Not all systems have all groups — only warn, don't fail
        }
    }

    # WinRM HTTP (5985)
    $winrmHttp = Get-NetFirewallRule -DisplayName "WinRM HTTP Inbound" -ErrorAction SilentlyContinue
    if (-not $winrmHttp) {
        try {
            New-NetFirewallRule -DisplayName "WinRM HTTP Inbound" -Direction Inbound `
                -Protocol TCP -LocalPort 5985 -Action Allow -Profile Domain,Private `
                -Description "Allow inbound WinRM HTTP" -ErrorAction Stop | Out-Null
            Write-OutputColor "  Created: WinRM HTTP Inbound (TCP 5985, Domain/Private)" -color "Success"
        }
        catch {
            Write-OutputColor "  Warning: Failed to create WinRM HTTP rule: $_" -color "Warning"
            $fwErrors++
        }
    } else {
        Enable-NetFirewallRule -Name $winrmHttp.Name -ErrorAction SilentlyContinue
        Write-OutputColor "  Enabled: WinRM HTTP Inbound (TCP 5985)" -color "Success"
    }

    # WinRM HTTPS (5986)
    $winrmHttps = Get-NetFirewallRule -DisplayName "WinRM HTTPS Inbound" -ErrorAction SilentlyContinue
    if (-not $winrmHttps) {
        try {
            New-NetFirewallRule -DisplayName "WinRM HTTPS Inbound" -Direction Inbound `
                -Protocol TCP -LocalPort 5986 -Action Allow -Profile Domain,Private `
                -Description "Allow inbound WinRM HTTPS" -ErrorAction Stop | Out-Null
            Write-OutputColor "  Created: WinRM HTTPS Inbound (TCP 5986, Domain/Private)" -color "Success"
        }
        catch {
            Write-OutputColor "  Warning: Failed to create WinRM HTTPS rule: $_" -color "Warning"
            $fwErrors++
        }
    } else {
        Enable-NetFirewallRule -Name $winrmHttps.Name -ErrorAction SilentlyContinue
        Write-OutputColor "  Enabled: WinRM HTTPS Inbound (TCP 5986)" -color "Success"
    }

    if ($fwErrors -eq 0) {
        Write-OutputColor "  WinRM firewall rules enabled." -color "Success"
    } else {
        Write-OutputColor "  WinRM rules partially enabled ($fwErrors issue(s))." -color "Warning"
    }
    Add-SessionChange -Category "Security" -Description "Enabled WinRM firewall rules"
    Clear-MenuCache
    Add-UndoAction -Category "Security" -Description "Enabled WinRM firewall rules" -UndoScript {
        foreach ($group in @("Windows Remote Management", "Windows Remote Management (HTTP-In)")) {
            Disable-NetFirewallRule -DisplayGroup $group -ErrorAction SilentlyContinue
        }
        Remove-NetFirewallRule -DisplayName "WinRM HTTP Inbound" -ErrorAction SilentlyContinue
        Remove-NetFirewallRule -DisplayName "WinRM HTTPS Inbound" -ErrorAction SilentlyContinue
    }
}

function Enable-NTPFirewallRules {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enabling NTP Time Sync firewall rules..." -color "Info"

    # NTP uses UDP 123 for both inbound and outbound
    $ntpInbound = Get-NetFirewallRule -DisplayName "NTP Inbound UDP 123" -ErrorAction SilentlyContinue
    if (-not $ntpInbound) {
        try {
            New-NetFirewallRule -DisplayName "NTP Inbound UDP 123" -Direction Inbound `
                -Protocol UDP -LocalPort 123 -Action Allow -Profile Domain,Private `
                -Description "Allow inbound NTP time sync" -ErrorAction Stop | Out-Null
            Write-OutputColor "  Created: NTP Inbound UDP 123 (Domain, Private)" -color "Success"
        }
        catch {
            Write-OutputColor "  Warning: Failed to create NTP inbound rule: $_" -color "Warning"
        }
    } else {
        Enable-NetFirewallRule -Name $ntpInbound.Name -ErrorAction SilentlyContinue
        Write-OutputColor "  Enabled: NTP Inbound UDP 123" -color "Success"
    }

    $ntpOutbound = Get-NetFirewallRule -DisplayName "NTP Outbound UDP 123" -ErrorAction SilentlyContinue
    if (-not $ntpOutbound) {
        try {
            New-NetFirewallRule -DisplayName "NTP Outbound UDP 123" -Direction Outbound `
                -Protocol UDP -RemotePort 123 -Action Allow -Profile Domain,Private,Public `
                -Description "Allow outbound NTP time sync" -ErrorAction Stop | Out-Null
            Write-OutputColor "  Created: NTP Outbound UDP 123 (All profiles)" -color "Success"
        }
        catch {
            Write-OutputColor "  Warning: Failed to create NTP outbound rule: $_" -color "Warning"
        }
    } else {
        Enable-NetFirewallRule -Name $ntpOutbound.Name -ErrorAction SilentlyContinue
        Write-OutputColor "  Enabled: NTP Outbound UDP 123" -color "Success"
    }

    Write-OutputColor "  NTP firewall rules configured." -color "Success"
    Add-SessionChange -Category "Security" -Description "Enabled NTP firewall rules (UDP 123)"
    Clear-MenuCache
    Add-UndoAction -Category "Security" -Description "Enabled NTP firewall rules" -UndoScript {
        Remove-NetFirewallRule -DisplayName "NTP Inbound UDP 123" -ErrorAction SilentlyContinue
        Remove-NetFirewallRule -DisplayName "NTP Outbound UDP 123" -ErrorAction SilentlyContinue
    }
}

function Enable-SNMPFirewallRules {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enabling SNMP Monitoring firewall rules..." -color "Info"

    # Enable built-in SNMP rule group if present
    try {
        Enable-NetFirewallRule -DisplayGroup "SNMP Service" -ErrorAction Stop
        Write-OutputColor "  Enabled built-in SNMP Service rules." -color "Success"
    }
    catch {
        # Not all systems have the SNMP group
    }

    # SNMP agent (UDP 161 inbound)
    $snmpAgent = Get-NetFirewallRule -DisplayName "SNMP Agent UDP 161" -ErrorAction SilentlyContinue
    if (-not $snmpAgent) {
        try {
            New-NetFirewallRule -DisplayName "SNMP Agent UDP 161" -Direction Inbound `
                -Protocol UDP -LocalPort 161 -Action Allow -Profile Domain,Private `
                -Description "Allow inbound SNMP polling" -ErrorAction Stop | Out-Null
            Write-OutputColor "  Created: SNMP Agent UDP 161 (Domain, Private)" -color "Success"
        }
        catch {
            Write-OutputColor "  Warning: Failed to create SNMP agent rule: $_" -color "Warning"
        }
    } else {
        Enable-NetFirewallRule -Name $snmpAgent.Name -ErrorAction SilentlyContinue
        Write-OutputColor "  Enabled: SNMP Agent UDP 161" -color "Success"
    }

    # SNMP trap (UDP 162 inbound for receiving traps)
    $snmpTrap = Get-NetFirewallRule -DisplayName "SNMP Trap UDP 162" -ErrorAction SilentlyContinue
    if (-not $snmpTrap) {
        try {
            New-NetFirewallRule -DisplayName "SNMP Trap UDP 162" -Direction Inbound `
                -Protocol UDP -LocalPort 162 -Action Allow -Profile Domain,Private `
                -Description "Allow inbound SNMP traps" -ErrorAction Stop | Out-Null
            Write-OutputColor "  Created: SNMP Trap UDP 162 (Domain, Private)" -color "Success"
        }
        catch {
            Write-OutputColor "  Warning: Failed to create SNMP trap rule: $_" -color "Warning"
        }
    } else {
        Enable-NetFirewallRule -Name $snmpTrap.Name -ErrorAction SilentlyContinue
        Write-OutputColor "  Enabled: SNMP Trap UDP 162" -color "Success"
    }

    Write-OutputColor "  SNMP firewall rules configured." -color "Success"
    Add-SessionChange -Category "Security" -Description "Enabled SNMP firewall rules (UDP 161/162)"
    Clear-MenuCache
    Add-UndoAction -Category "Security" -Description "Enabled SNMP firewall rules" -UndoScript {
        Disable-NetFirewallRule -DisplayGroup "SNMP Service" -ErrorAction SilentlyContinue
        Remove-NetFirewallRule -DisplayName "SNMP Agent UDP 161" -ErrorAction SilentlyContinue
        Remove-NetFirewallRule -DisplayName "SNMP Trap UDP 162" -ErrorAction SilentlyContinue
    }
}

function Enable-ICMPPingRules {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enabling ICMP Ping (Echo Request) inbound rules..." -color "Info"
    Write-OutputColor "" -color "Info"

    $enabledCount = 0
    $createdCount = 0
    $enabledRuleNames = @()  # Track which specific rules we toggled so undo is precise

    # Try to enable built-in ICMPv4 Echo Request rules (Domain and Private profiles)
    $v4Rules = @(Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object {
        $_.DisplayName -like "*Echo Request*ICMPv4*" -and $_.Direction -eq "Inbound"
    })
    if ($v4Rules.Count -gt 0) {
        foreach ($rule in $v4Rules) {
            try {
                if ($rule.Enabled -ne $true) {
                    Enable-NetFirewallRule -Name $rule.Name -ErrorAction Stop
                    Write-OutputColor "  Enabled: $($rule.DisplayName)" -color "Success"
                    $enabledRuleNames += $rule.Name
                } else {
                    Write-OutputColor "  Already enabled: $($rule.DisplayName)" -color "Info"
                }
                $enabledCount++
            }
            catch {
                Write-OutputColor "  Warning: Could not enable '$($rule.DisplayName)': $_" -color "Warning"
            }
        }
    }

    # Try to enable built-in ICMPv6 Echo Request rules
    $v6Rules = @(Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object {
        $_.DisplayName -like "*Echo Request*ICMPv6*" -and $_.Direction -eq "Inbound"
    })
    if ($v6Rules.Count -gt 0) {
        foreach ($rule in $v6Rules) {
            try {
                if ($rule.Enabled -ne $true) {
                    Enable-NetFirewallRule -Name $rule.Name -ErrorAction Stop
                    Write-OutputColor "  Enabled: $($rule.DisplayName)" -color "Success"
                    $enabledRuleNames += $rule.Name
                } else {
                    Write-OutputColor "  Already enabled: $($rule.DisplayName)" -color "Info"
                }
                $enabledCount++
            }
            catch {
                Write-OutputColor "  Warning: Could not enable '$($rule.DisplayName)': $_" -color "Warning"
            }
        }
    }

    # Fallback: create custom rules if no built-in rules were found
    if ($v4Rules.Count -eq 0) {
        $existing = Get-NetFirewallRule -DisplayName "Allow ICMPv4 Ping Inbound" -ErrorAction SilentlyContinue
        if (-not $existing) {
            try {
                New-NetFirewallRule -DisplayName "Allow ICMPv4 Ping Inbound" -Direction Inbound `
                    -Protocol ICMPv4 -IcmpType 8 -Action Allow -Profile Domain,Private `
                    -Description "Allow inbound ICMP Echo Request (ping)" -ErrorAction Stop | Out-Null
                Write-OutputColor "  Created: Allow ICMPv4 Ping Inbound (Domain, Private)" -color "Success"
                $createdCount++
            }
            catch {
                Write-OutputColor "  Failed to create ICMPv4 ping rule: $_" -color "Error"
            }
        } else {
            Enable-NetFirewallRule -Name $existing.Name -ErrorAction SilentlyContinue
            Write-OutputColor "  Enabled: Allow ICMPv4 Ping Inbound" -color "Success"
            $enabledCount++
        }
    }

    if ($v6Rules.Count -eq 0) {
        $existing = Get-NetFirewallRule -DisplayName "Allow ICMPv6 Ping Inbound" -ErrorAction SilentlyContinue
        if (-not $existing) {
            try {
                New-NetFirewallRule -DisplayName "Allow ICMPv6 Ping Inbound" -Direction Inbound `
                    -Protocol ICMPv6 -IcmpType 8 -Action Allow -Profile Domain,Private `
                    -Description "Allow inbound ICMPv6 Echo Request (ping)" -ErrorAction Stop | Out-Null
                Write-OutputColor "  Created: Allow ICMPv6 Ping Inbound (Domain, Private)" -color "Success"
                $createdCount++
            }
            catch {
                Write-OutputColor "  Failed to create ICMPv6 ping rule: $_" -color "Error"
            }
        } else {
            Enable-NetFirewallRule -Name $existing.Name -ErrorAction SilentlyContinue
            Write-OutputColor "  Enabled: Allow ICMPv6 Ping Inbound" -color "Success"
            $enabledCount++
        }
    }

    Write-OutputColor "" -color "Info"
    if ($enabledCount -gt 0 -or $createdCount -gt 0) {
        Write-OutputColor "  ICMP ping rules configured ($enabledCount enabled, $createdCount created)." -color "Success"
        Write-OutputColor "  This machine should now respond to ping requests." -color "Info"
    } else {
        Write-OutputColor "  No ICMP rules were modified." -color "Warning"
    }

    Add-SessionChange -Category "Security" -Description "Enabled ICMP ping (Echo Request) inbound rules"
    Clear-MenuCache
    # Same pattern as Live Migration undo (v1.98.22): track specific Names that transitioned
    # disabled→enabled and only disable those. Prior code disabled every "Echo Request*ICMP*"
    # rule including ones enabled by GPO before RackStack ran — breaking monitoring until GPO
    # refresh. The two custom-named rules we may have created are also tracked separately.
    Add-UndoAction -Category "Security" -Description "Enabled ICMP ping rules" -UndoScript {
        param($EnabledRules)
        if ($EnabledRules) {
            foreach ($n in $EnabledRules) {
                Disable-NetFirewallRule -Name $n -ErrorAction SilentlyContinue
            }
        }
        # Remove custom rules only — by DisplayName since they're unique to this function
        Remove-NetFirewallRule -DisplayName "Allow ICMPv4 Ping Inbound" -ErrorAction SilentlyContinue
        Remove-NetFirewallRule -DisplayName "Allow ICMPv6 Ping Inbound" -ErrorAction SilentlyContinue
    }.GetNewClosure() -UndoParams @{ EnabledRules = $enabledRuleNames }
}

# Function to compare current firewall rules against a template
function Compare-FirewallTemplate {
    param([string]$TemplateName)

    if ([string]::IsNullOrWhiteSpace($TemplateName)) {
        Write-OutputColor "  No template specified" -color "Warning"
        return
    }

    # Template definitions mapping template names to their expected groups and custom rules
    $templateDefs = @{
        "Hyper-V Host" = @{
            Groups = @("Hyper-V", "Hyper-V Management Clients", "Hyper-V Replica HTTP", "Hyper-V Replica HTTPS")
            CustomRules = @()
        }
        "Failover Cluster" = @{
            Groups = @("Failover Clusters")
            CustomRules = @("Cluster-RPC", "Cluster-RPC-Dynamic", "Cluster-UDP")
        }
        "Hyper-V Replica" = @{
            Groups = @("Hyper-V Replica HTTP", "Hyper-V Replica HTTPS")
            CustomRules = @("Hyper-V Replica HTTP 80", "Hyper-V Replica HTTPS 443")
        }
        "Live Migration" = @{
            Groups = @("Hyper-V", "File and Printer Sharing")
            CustomRules = @("Hyper-V Live Migration")
        }
        "iSCSI" = @{
            Groups = @("iSCSI Service")
            CustomRules = @("iSCSI Target")
        }
        "SMB" = @{
            Groups = @("File and Printer Sharing", "Netlogon Service")
            CustomRules = @()
        }
        "RDP" = @{
            Groups = @("Remote Desktop")
            CustomRules = @("RDP Inbound TCP 3389", "RDP Inbound UDP 3389")
        }
        "WinRM" = @{
            Groups = @("Windows Remote Management")
            CustomRules = @("WinRM HTTP Inbound", "WinRM HTTPS Inbound")
        }
        "NTP" = @{
            Groups = @()
            CustomRules = @("NTP Inbound UDP 123", "NTP Outbound UDP 123")
        }
        "SNMP" = @{
            Groups = @("SNMP Service")
            CustomRules = @("SNMP Agent UDP 161", "SNMP Trap UDP 162")
        }
        "ICMP Ping" = @{
            Groups = @()
            CustomRules = @("Allow ICMPv4 Ping Inbound", "Allow ICMPv6 Ping Inbound")
        }
    }

    $template = $templateDefs[$TemplateName]
    if ($null -eq $template) {
        Write-OutputColor "  Template '$TemplateName' not found" -color "Warning"
        return
    }

    Write-OutputColor "`n  Comparing current rules vs template '$TemplateName':" -color "Info"
    Write-OutputColor "" -color "Info"

    $missing = 0
    $present = 0

    # Check rule groups
    foreach ($group in $template.Groups) {
        $rules = @(Get-NetFirewallRule -DisplayGroup $group -ErrorAction SilentlyContinue)
        if ($rules.Count -gt 0) {
            $enabledCount = @($rules | Where-Object { $_.Enabled -eq $true }).Count
            if ($enabledCount -eq $rules.Count) {
                $present++
                Write-OutputColor "  [OK] Group '$group' ($enabledCount/$($rules.Count) enabled)" -color "Success"
            } else {
                $present++
                Write-OutputColor "  [PARTIAL] Group '$group' ($enabledCount/$($rules.Count) enabled)" -color "Warning"
            }
        } else {
            $missing++
            Write-OutputColor "  [MISSING] Group '$group'" -color "Warning"
        }
    }

    # Check custom rules
    foreach ($ruleName in $template.CustomRules) {
        $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if ($null -ne $existing) {
            $present++
            $enabled = if ($existing.Enabled -eq $true) { "Enabled" } else { "Disabled" }
            Write-OutputColor "  [OK] $ruleName ($enabled)" -color "Success"
        } else {
            $missing++
            Write-OutputColor "  [MISSING] $ruleName" -color "Warning"
        }
    }

    Write-OutputColor "`n  Present: $present, Missing: $missing" -color "Info"

    if ($missing -gt 0) {
        Write-OutputColor "  Apply missing rules? [Y/N]" -color "Info"
        $response = Read-Host "  Select"
        if ($response -eq 'Y' -or $response -eq 'y') {
            return $true
        }
    }
    return $false
}

# Function to let user pick a template to compare
function Invoke-FirewallTemplateComparison {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  COMPARE FIREWALL TEMPLATE".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[1]  Hyper-V Host"
    Write-MenuItem "[2]  Failover Cluster"
    Write-MenuItem "[3]  Hyper-V Replica"
    Write-MenuItem "[4]  Live Migration"
    Write-MenuItem "[5]  iSCSI"
    Write-MenuItem "[6]  SMB"
    Write-MenuItem "[7]  RDP"
    Write-MenuItem "[8]  WinRM"
    Write-MenuItem "[9]  NTP"
    Write-MenuItem "[10] SNMP"
    Write-MenuItem "[11] ICMP Ping"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $pick = Read-Host "  Select template to compare"
    $navResult = Test-NavigationCommand -UserInput $pick
    if ($navResult.ShouldReturn) { return }

    $templateName = switch ($pick) {
        "1" { "Hyper-V Host" }
        "2" { "Failover Cluster" }
        "3" { "Hyper-V Replica" }
        "4" { "Live Migration" }
        "5" { "iSCSI" }
        "6" { "SMB" }
        "7" { "RDP" }
        "8" { "WinRM" }
        "9" { "NTP" }
        "10" { "SNMP" }
        "11" { "ICMP Ping" }
        default { $null }
    }

    if ($null -eq $templateName) {
        Write-OutputColor "  Invalid choice. Enter 1-11." -color "Error"
        return
    }

    $shouldApply = Compare-FirewallTemplate -TemplateName $templateName
    if ($shouldApply -eq $true) {
        switch ($templateName) {
            "Hyper-V Host"     { Enable-HyperVFirewallRules }
            "Failover Cluster" { Enable-ClusterFirewallRules }
            "Hyper-V Replica"  { Enable-ReplicaFirewallRules }
            "Live Migration"   { Enable-LiveMigrationFirewallRules }
            "iSCSI"            { Enable-iSCSIFirewallRules }
            "SMB"              { Enable-SMBFirewallRules }
            "RDP"              { Enable-RDPFirewallRules }
            "WinRM"            { Enable-WinRMFirewallRules }
            "NTP"              { Enable-NTPFirewallRules }
            "SNMP"             { Enable-SNMPFirewallRules }
            "ICMP Ping"        { Enable-ICMPPingRules }
        }
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
        $rules = @(Get-NetFirewallRule -DisplayGroup $group -ErrorAction SilentlyContinue)
        if ($rules.Count -gt 0) {
            $enabledCount = @($rules | Where-Object { $_.Enabled -eq $true }).Count
            $totalCount = $rules.Count
            $status = if ($enabledCount -eq $totalCount) { "All Enabled" } elseif ($enabledCount -gt 0) { "$enabledCount/$totalCount Enabled" } else { "Disabled" }
            $color = if ($enabledCount -eq $totalCount) { "Success" } elseif ($enabledCount -gt 0) { "Warning" } else { "Error" }
            Write-OutputColor "  │$("  $group : $status".PadRight(72))│" -color $color
        } else {
            Write-OutputColor "  │$("  $group : Not Found".PadRight(72))│" -color "Info"
        }
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}
#endregion