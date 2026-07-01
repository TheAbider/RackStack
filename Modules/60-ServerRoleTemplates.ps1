#region ===== SERVER ROLE TEMPLATES =====
# JSON-driven system for installing common Windows Server roles and features

# Populate built-in role templates (variable declared as $null in 00-Initialization.ps1)
$script:ServerRoleTemplates = @{
    "DC" = @{
        FullName       = "Domain Controller"
        Description    = "Active Directory Domain Services with DNS and management tools"
        Features       = @("AD-Domain-Services", "DNS", "RSAT-AD-Tools", "RSAT-DNS-Server", "GPMC")
        PostInstall    = "Invoke-DCPromoWizard"
        RequiresReboot = $true
        ServerOnly     = $true
    }
    "FS" = @{
        FullName       = "File Server"
        Description    = "File and Storage Services with deduplication and DFS"
        Features       = @("FS-FileServer", "FS-Data-Deduplication", "FS-DFS-Namespace", "FS-DFS-Replication", "FS-Resource-Manager")
        PostInstall    = $null
        RequiresReboot = $false
        ServerOnly     = $true
    }
    "WEB" = @{
        FullName       = "Web Server (IIS)"
        Description    = "IIS with ASP.NET, management console, and common modules"
        Features       = @("Web-Server", "Web-Asp-Net45", "Web-Mgmt-Console", "Web-Scripting-Tools", "Web-Security", "Web-Filtering")
        PostInstall    = $null
        RequiresReboot = $false
        ServerOnly     = $true
    }
    "DHCP" = @{
        FullName       = "DHCP Server"
        Description    = "DHCP Server with management tools"
        Features       = @("DHCP", "RSAT-DHCP")
        PostInstall    = "Start-DHCPPostInstall"
        RequiresReboot = $false
        ServerOnly     = $true
    }
    "DNS" = @{
        FullName       = "DNS Server"
        Description    = "DNS Server with management tools"
        Features       = @("DNS", "RSAT-DNS-Server")
        PostInstall    = $null
        RequiresReboot = $false
        ServerOnly     = $true
    }
    "PRINT" = @{
        FullName       = "Print Server"
        Description    = "Print and Document Services (Print Server role service + management tools)"
        Features       = @("Print-Services", "Print-Server")
        PostInstall    = "Start-PrintServerPostInstall"
        RequiresReboot = $false
        ServerOnly     = $true
    }
    "WSUS" = @{
        FullName       = "WSUS Server"
        Description    = "Windows Server Update Services"
        Features       = @("UpdateServices", "UpdateServices-RSAT", "UpdateServices-UI")
        PostInstall    = "Start-WSUSPostInstall"
        RequiresReboot = $true
        ServerOnly     = $true
    }
    "NPS" = @{
        FullName       = "Network Policy Server (RADIUS)"
        Description    = "NPS for RADIUS authentication (WiFi/VPN)"
        Features       = @("NPAS", "RSAT-NPAS")
        PostInstall    = $null
        RequiresReboot = $false
        ServerOnly     = $true
    }
    "HV" = @{
        FullName       = "Hyper-V Host"
        Description    = "Hyper-V with management tools and MPIO"
        Features       = @("Hyper-V", "Hyper-V-PowerShell", "RSAT-Hyper-V-Tools", "Multipath-IO")
        PostInstall    = $null
        RequiresReboot = $true
        ServerOnly     = $true
    }
    "RDS" = @{
        FullName       = "Remote Desktop Services"
        Description    = "RDS Session Host with licensing"
        Features       = @("RDS-RD-Server", "RDS-Licensing", "RSAT-RDS-Tools")
        PostInstall    = $null
        RequiresReboot = $true
        ServerOnly     = $true
    }
}

# Custom role templates (loaded from defaults.json or user-defined)
$script:CustomRoleTemplates = @{}

# Validate a user-provided custom role template from defaults.json
function Test-CustomRoleTemplate {
    param(
        [Parameter(Mandatory=$true)]
        [object]$Template,

        [Parameter(Mandatory=$true)]
        [string]$TemplateName
    )

    $requiredFields = @('FullName', 'Description', 'Features', 'RequiresReboot', 'ServerOnly')
    $issues = @()

    foreach ($field in $requiredFields) {
        $value = $Template.$field
        if ($null -eq $value) {
            $issues += "Missing required field: $field"
        }
    }

    # Validate Features is an array
    if ($null -ne $Template.Features -and $Template.Features -isnot [array]) {
        $issues += "Features must be an array"
    }
    elseif ($null -ne $Template.Features -and @($Template.Features).Count -eq 0) {
        $issues += "Features array is empty"
    }

    # Validate boolean fields
    if ($null -ne $Template.RequiresReboot -and $Template.RequiresReboot -isnot [bool]) {
        $issues += "RequiresReboot must be true or false (got: $($Template.RequiresReboot))"
    }

    if ($null -ne $Template.ServerOnly -and $Template.ServerOnly -isnot [bool]) {
        $issues += "ServerOnly must be true or false (got: $($Template.ServerOnly))"
    }

    # Validate PostInstall. Must be a single token (no spaces / no args) that starts
    # with an approved setup verb so a malicious defaults.json can't smuggle an
    # arbitrary cmdlet through `& $template.PostInstall`.
    if ($null -ne $Template.PostInstall) {
        if ($Template.PostInstall -isnot [string]) {
            $issues += "PostInstall must be a function name string or null (got: $($Template.PostInstall.GetType().Name))"
        }
        elseif ($Template.PostInstall -notmatch '^(Start|Invoke|Initialize|Configure)-[A-Za-z][A-Za-z0-9]+$') {
            $issues += "PostInstall '$($Template.PostInstall)' rejected: must match ^(Start|Invoke|Initialize|Configure)-Verb pattern (single token, no arguments)"
        }
    }

    if (@($issues).Count -gt 0) {
        Write-OutputColor "  Custom template '$TemplateName' has $(@($issues).Count) issue(s):" -color "Error"
        foreach ($issue in $issues) {
            Write-OutputColor "    - $issue" -color "Error"
        }
        return $false
    }

    Write-OutputColor "  Custom template '$TemplateName' validated successfully" -color "Success"
    return $true
}

# Interactive menu for selecting and installing server role templates
function Show-RoleTemplateSelector {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                      SERVER ROLE TEMPLATES").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        # Build ordered list of built-in templates
        $sortedKeys = $script:ServerRoleTemplates.Keys | Sort-Object { $script:ServerRoleTemplates[$_].FullName }
        $menuIndex = 1
        $menuMap = @{}

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  BUILT-IN TEMPLATES".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        foreach ($key in $sortedKeys) {
            $template = $script:ServerRoleTemplates[$key]
            $status = Get-RoleTemplateStatus -Template $template
            $statusText = $status.Status
            $statusColor = switch ($statusText) {
                "Installed"     { "Success" }
                "Not Installed" { "Warning" }
                default         { "Info" }  # Partial
            }
            $label = "[$menuIndex]  $($template.FullName) ($key)"
            Write-MenuItem $label -Status $statusText -StatusColor $statusColor
            $menuMap[$menuIndex] = @{ Key = $key; Source = "builtin" }
            $menuIndex++
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

        # Show custom templates if any exist
        if ($script:CustomRoleTemplates.Count -gt 0) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  CUSTOM TEMPLATES".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

            $customKeys = $script:CustomRoleTemplates.Keys | Sort-Object { $script:CustomRoleTemplates[$_].FullName }
            foreach ($key in $customKeys) {
                $template = $script:CustomRoleTemplates[$key]
                $status = Get-RoleTemplateStatus -Template $template
                $statusText = $status.Status
                $statusColor = switch ($statusText) {
                    "Installed"     { "Success" }
                    "Not Installed" { "Warning" }
                    default         { "Info" }
                }
                $label = "[$menuIndex]  $($template.FullName) ($key)"
                Write-MenuItem $label -Status $statusText -StatusColor $statusColor
                $menuMap[$menuIndex] = @{ Key = $key; Source = "custom" }
                $menuIndex++
            }

            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        }

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [R] Show All Installed Roles" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch -Regex ($choice) {
            "^[Bb]$" { return }
            "^[Rr]$" { Show-InstalledRoles }
            "^\d+$" {
                $num = [int]$choice
                if ($menuMap.ContainsKey($num)) {
                    $selected = $menuMap[$num]
                    Install-ServerRoleTemplate -TemplateKey $selected.Key
                }
                else {
                    Write-OutputColor "  Invalid selection. Enter 1-$($menuIndex - 1), R, or B." -color "Error"
                    Start-Sleep -Seconds 1
                }
            }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-$($menuIndex - 1), R, or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Install all features defined in a server role template
function Install-ServerRoleTemplate {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$TemplateKey
    )

    # Look up template from built-in or custom collections
    $template = $null
    if ($script:ServerRoleTemplates.ContainsKey($TemplateKey)) {
        $template = $script:ServerRoleTemplates[$TemplateKey]
    }
    elseif ($script:CustomRoleTemplates.ContainsKey($TemplateKey)) {
        $template = $script:CustomRoleTemplates[$TemplateKey]
    }

    if ($null -eq $template) {
        Write-OutputColor "  Template '$TemplateKey' not found." -color "Error"
        Write-PressEnter
        return
    }

    $fullName = $template.FullName

    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    $lineStr = "                INSTALL: $fullName"
    if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
    Write-OutputColor "  ║$($lineStr.PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  $($template.Description)" -color "Info"
    Write-OutputColor "" -color "Info"

    # Check if server-only template on client OS
    if ($template.ServerOnly -eq $true) {
        if (-not (Test-WindowsServer)) {
            Write-OutputColor "  This role template requires Windows Server." -color "Error"
            Write-OutputColor "  Current OS is a client/workstation and cannot install server roles." -color "Error"
            Write-PressEnter
            return
        }
    }

    # Get current status of each feature
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  FEATURES TO INSTALL".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $status = Get-RoleTemplateStatus -Template $template
    $featuresToInstall = @()

    foreach ($feat in $status.Features) {
        if ($feat.Installed) {
            Write-MenuItem $feat.Name -Status "Installed" -StatusColor "Success"
        }
        else {
            Write-MenuItem $feat.Name -Status "Not Installed" -StatusColor "Warning"
            $featuresToInstall += $feat.Name
        }
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Check if everything is already installed
    if ($featuresToInstall.Count -eq 0) {
        Write-OutputColor "  All features for $fullName are already installed." -color "Success"
        Write-PressEnter
        return
    }

    Write-OutputColor "  Features to install: $($featuresToInstall.Count) of $($status.Total)" -color "Info"

    if ($template.RequiresReboot) {
        Write-OutputColor "  A reboot will be required after installation." -color "Warning"
    }
    Write-OutputColor "" -color "Info"

    # Confirm with user
    if (-not (Confirm-UserAction -Message "Install $fullName role template?")) {
        Write-OutputColor "  Installation cancelled." -color "Info"
        Write-PressEnter
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Installing features... This may take several minutes." -color "Info"
    Write-OutputColor "" -color "Info"

    $successCount = 0
    $failCount = 0
    $failures = @()

    foreach ($featureName in $featuresToInstall) {
        $installResult = Install-WindowsFeatureWithTimeout -FeatureName $featureName -DisplayName $featureName -IncludeManagementTools
        if ($installResult.Success) {
            Write-OutputColor "  [OK]  $featureName" -color "Success"
            $successCount++
        }
        else {
            # Surface the ACTUAL reason instead of a bare "Failed" — this is what tells the operator
            # why e.g. Print Server didn't install (missing source files, edition, WSUS block, etc.).
            $reason = if ($installResult.TimedOut) {
                "installation timed out"
            } elseif ($installResult.Error) {
                ($installResult.Error -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1).Trim()
            } else {
                "unknown error (the role may be unavailable on this edition, or its source files are missing)"
            }
            Write-OutputColor "  [XX]  $featureName - $reason" -color "Error"
            $failures += @{ Feature = $featureName; Reason = $reason }
            $failCount++
        }
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  INSTALLATION SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Succeeded: $successCount".PadRight(72))│" -color "Success"

    if ($failCount -gt 0) {
        Write-OutputColor "  │$("  Failed:    $failCount".PadRight(72))│" -color "Error"
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($failCount -gt 0) {
        Write-OutputColor "  Why it failed:" -color "Error"
        foreach ($f in $failures) {
            Write-OutputColor "    - $($f.Feature): $($f.Reason)" -color "Warning"
        }
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Common causes: the role's source files aren't on the system (install from" -color "Info"
        Write-OutputColor "  Windows Update or point -Source at a mounted ISO's SxS folder), WSUS/Group" -color "Info"
        Write-OutputColor "  Policy is blocking the feature source, or the role isn't offered on this" -color "Info"
        Write-OutputColor "  Windows edition. The exact error above says which." -color "Info"
        Write-OutputColor "" -color "Info"
    }

    # Set reboot flag if needed
    if ($template.RequiresReboot -and $successCount -gt 0) {
        $script:RebootNeeded = $true
        Write-OutputColor "  A reboot is required to complete the installation." -color "Warning"
    }

    # Handle post-install function. Re-verify the allowed-verb pattern at invocation
    # time too (defense-in-depth in case a future built-in template introduces an
    # unexpected value that Test-CustomRoleTemplate didn't run against).
    if ($null -ne $template.PostInstall -and $successCount -gt 0) {
        if ($template.PostInstall -notmatch '^(Start|Invoke|Initialize|Configure)-[A-Za-z][A-Za-z0-9]+$') {
            Write-OutputColor "  Refusing to run post-install '$($template.PostInstall)': name doesn't match allowed verb pattern." -color "Error"
            return
        }
        # Validate function exists before attempting to call it
        $postInstallCmd = Get-Command $template.PostInstall -ErrorAction SilentlyContinue
        if ($null -eq $postInstallCmd) {
            Write-OutputColor "  Post-install function '$($template.PostInstall)' not found." -color "Warning"
            Write-OutputColor "  This may be a custom template referencing a missing function." -color "Warning"
        }
        elseif ($template.RequiresReboot) {
            Write-OutputColor "  Post-install step: $($template.PostInstall)" -color "Info"
            Write-OutputColor "  Run this after rebooting to complete configuration." -color "Warning"
        }
        else {
            Write-OutputColor "  Running post-install: $($template.PostInstall)..." -color "Info"
            try {
                & $template.PostInstall
            }
            catch {
                Write-OutputColor "  Post-install error: $_" -color "Error"
            }
        }
    }

    # Track session change
    if ($successCount -gt 0) {
        Add-SessionChange -Category "Roles" -Description "Installed role template: $fullName ($successCount features)"
        Clear-MenuCache
    }

    Write-PressEnter
}

# Display all installed Windows Server roles and features
function Show-InstalledRoles {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     INSTALLED ROLES & FEATURES").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Test-WindowsServer)) {
        Write-OutputColor "  This feature requires Windows Server." -color "Error"
        Write-OutputColor "  Client OS does not support Get-WindowsFeature." -color "Warning"
        Write-PressEnter
        return
    }

    try {
        $installedFeatures = @(Get-WindowsFeature -ErrorAction Stop | Where-Object { $_.Installed })

        if ($null -eq $installedFeatures -or $installedFeatures.Count -eq 0) {
            Write-OutputColor "  No roles or features are currently installed." -color "Warning"
            Write-PressEnter
            return
        }

        # Group by feature type
        $roles = @($installedFeatures | Where-Object { $_.FeatureType -eq "Role" })
        $roleServices = @($installedFeatures | Where-Object { $_.FeatureType -eq "Role Service" })
        $features = @($installedFeatures | Where-Object { $_.FeatureType -eq "Feature" })

        if ($roles.Count -gt 0) {
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  ROLES ($($roles.Count))".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($role in $roles) {
                Write-MenuItem "  $($role.DisplayName)" -Status $role.Name -StatusColor "Success"
            }
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            Write-OutputColor "" -color "Info"
        }

        if ($roleServices.Count -gt 0) {
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  ROLE SERVICES ($($roleServices.Count))".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($svc in $roleServices) {
                Write-MenuItem "  $($svc.DisplayName)" -Status $svc.Name -StatusColor "Info"
            }
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            Write-OutputColor "" -color "Info"
        }

        if ($features.Count -gt 0) {
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  FEATURES ($($features.Count))".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($feat in $features) {
                Write-MenuItem "  $($feat.DisplayName)" -Status $feat.Name -StatusColor "Info"
            }
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        }
    }
    catch {
        Write-OutputColor "  Error retrieving installed features: $_" -color "Error"
    }

    Write-PressEnter
}

# Get the install status of all features in a role template
function Get-RoleTemplateStatus {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Template
    )

    $featureList = @()
    $installedCount = 0
    $totalCount = $Template.Features.Count

    foreach ($featureName in $Template.Features) {
        $installed = $false
        try {
            if (Test-WindowsServer) {
                $wf = Get-WindowsFeature -Name $featureName -ErrorAction SilentlyContinue
                if ($null -ne $wf -and $wf.InstallState -eq "Installed") {
                    $installed = $true
                }
            }
        }
        catch {
            # Feature check failed - treat as not installed
        }

        if ($installed) { $installedCount++ }
        $featureList += @{
            Name      = $featureName
            Installed = $installed
        }
    }

    $statusText = if ($installedCount -eq $totalCount) {
        "Installed"
    }
    elseif ($installedCount -gt 0) {
        "Partial ($installedCount/$totalCount)"
    }
    else {
        "Not Installed"
    }

    return @{
        Installed = $installedCount
        Total     = $totalCount
        Status    = $statusText
        Features  = $featureList
    }
}

# Post-install guidance for DHCP Server
function Start-DHCPPostInstall {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  DHCP POST-INSTALL CONFIGURATION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$('  The DHCP Server role has been installed. Next steps:'.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('  1. Authorize the DHCP server in Active Directory'.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('     Run: Add-DhcpServerInDC -DnsName [FQDN] -IPAddress [IP]'.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('  2. Create DHCP scopes for your subnets'.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('     Use DHCP Management Console or PowerShell'.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('  3. Configure scope options (gateway, DNS, domain name)'.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('  4. Complete the DHCP post-install wizard in Server Manager'.PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-PressEnter
}

# Post-install guidance for WSUS Server
function Start-WSUSPostInstall {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  WSUS POST-INSTALL CONFIGURATION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$('  WSUS has been installed. Next steps:'.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('  1. Run the WSUS post-installation task:'.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('     wsusutil.exe postinstall CONTENT_DIR=D:\WSUS'.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('     (from C:\Program Files\Update Services\Tools\)'.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('  2. Choose a content storage directory with adequate space'.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('     (at least 20-40 GB recommended)'.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('  3. Open the WSUS Console and run the configuration wizard'.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('     - Select products and classifications'.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('     - Set synchronization schedule'.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('     - Configure auto-approval rules'.PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-PressEnter
}

# Post-install guidance for Print Server. Installing the role only adds the service; this points the
# operator at the actual "set up printers" next steps so it feels like a finished setup, and offers
# to open the Print Management console.
function Start-PrintServerPostInstall {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Print Server role installed. To finish setting it up:" -color "Success"
    Write-OutputColor "    - Open Print Management (printmanagement.msc) to add printers and drivers." -color "Info"
    Write-OutputColor "    - Add a TCP/IP port:  Add-PrinterPort -Name <ip> -PrinterHostAddress <ip>" -color "Info"
    Write-OutputColor "    - Add a printer:      Add-Printer -Name <name> -DriverName <driver> -PortName <ip>" -color "Info"
    Write-OutputColor "    - Share it:           Set-Printer -Name <name> -Shared `$true -ShareName <share>" -color "Info"
    Write-OutputColor "" -color "Info"
    if (Confirm-UserAction -Message "Open the Print Management console now?") {
        try {
            Start-Process "printmanagement.msc" -ErrorAction Stop
            Write-OutputColor "  Print Management opened." -color "Success"
        }
        catch {
            Write-OutputColor "  Could not open Print Management: $($_.Exception.Message)" -color "Warning"
            Write-OutputColor "  Open it manually from Server Manager > Tools > Print Management." -color "Info"
        }
    }
}

# Stub for DC promotion - directs user to the AD DS Promotion module
function Invoke-DCPromoWizard {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  DOMAIN CONTROLLER PROMOTION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$('  AD DS has been installed. To promote this server:'.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('  Use the AD DS Promotion menu (Module 61) or run manually:'.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('  New forest:'.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('    Install-ADDSForest -DomainName [domain.local]'.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('  Additional DC in existing domain:'.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('    Install-ADDSDomainController -DomainName [domain.local]'.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('  A reboot is required before promotion can proceed.'.PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-PressEnter
}
#endregion
