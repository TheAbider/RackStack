#region ===== FIREWALL RULE TEMPLATES =====
# Function to apply firewall rule templates
function Set-FirewallRuleTemplates {
    while ($true) {
        if ($global:ReturnToMainMenu) { return }
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
        Write-MenuItem "[8]  Compare Rules Against Template"
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
            "8" { Invoke-FirewallTemplateComparison }
            { $_ -eq "b" -or $_ -eq "B" } { return }
            default { Write-OutputColor "  Invalid choice. Enter 1-8 or B." -color "Error"; Start-Sleep -Seconds 1 }
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
    foreach ($group in @("Hyper-V", "File and Printer Sharing")) {
        try { Enable-NetFirewallRule -DisplayGroup $group -ErrorAction Stop }
        catch { Write-OutputColor "  Warning: Could not enable '$group' rules: $_" -color "Warning" }
    }
    # Live Migration port
    $lmRule = Get-NetFirewallRule -DisplayName "Hyper-V Live Migration" -ErrorAction SilentlyContinue
    if (-not $lmRule) {
        try {
            New-NetFirewallRule -DisplayName "Hyper-V Live Migration" -Direction Inbound -Protocol TCP -LocalPort 6600 -Action Allow -Profile Domain,Private -ErrorAction Stop | Out-Null
        }
        catch { Write-OutputColor "  Warning: Failed to create Live Migration rule: $_" -color "Error" }
    }
    Write-OutputColor "  Live Migration firewall rules enabled." -color "Success"
    Add-SessionChange -Category "Security" -Description "Enabled Live Migration firewall rules"
    Clear-MenuCache
    Add-UndoAction -Category "Security" -Description "Enabled Live Migration firewall rules" -UndoScript {
        foreach ($group in @("Hyper-V", "File and Printer Sharing")) {
            Disable-NetFirewallRule -DisplayGroup $group -ErrorAction SilentlyContinue
        }
        Remove-NetFirewallRule -DisplayName "Hyper-V Live Migration" -ErrorAction SilentlyContinue
    }
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
        $response = Read-Host "  Choice"
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
        default { $null }
    }

    if ($null -eq $templateName) {
        Write-OutputColor "  Invalid choice. Enter 1-6." -color "Error"
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