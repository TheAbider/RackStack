#region ===== STORAGE MIGRATION SERVICE =====
# Installs Storage Migration Service (SMS) — Microsoft's tool for migrating
# file servers (and their shares, data, security, and even server identity)
# onto modern Windows Server or Azure.
#
# SMS has two roles:
#   * Orchestrator (feature 'SMS')       — coordinates migration jobs; one
#                                          per migration project.
#   * Proxy        (feature 'SMS-Proxy') — installed on the *destination*
#                                          Windows Server to speed transfers
#                                          (data moves locally instead of
#                                          round-tripping through the
#                                          orchestrator).
#
# Scope note: this module stands up the SMS *roles* and reports their state.
# The migration jobs themselves — Inventory -> Transfer -> Cutover, including
# the source/destination pairing and the identity-swap decision — are an
# interactive, multi-phase, per-project workflow that Microsoft drives
# through Windows Admin Center. RackStack gets SMS installed and ready; the
# job orchestration is a deliberate WAC workflow and the menu says so.
#
# Config: $script:StorageMigration (see 00-Initialization.ps1, overridable
# via rackstack.config.json "StorageMigration").

# Returns $true if the SMS orchestrator role is installed.
function Test-SMSInstalled {
    try {
        $feat = Get-WindowsFeature -Name 'SMS' -ErrorAction Stop
        return ($feat -and $feat.InstallState -eq 'Installed')
    }
    catch {
        return $false
    }
}

# Returns $true if the SMS-Proxy feature is installed.
function Test-SMSProxyInstalled {
    try {
        $feat = Get-WindowsFeature -Name 'SMS-Proxy' -ErrorAction Stop
        return ($feat -and $feat.InstallState -eq 'Installed')
    }
    catch {
        return $false
    }
}

# Query SMS state. Returns a hashtable: orchestrator/proxy install flags,
# the SMS service status, and (when available) the SMS orchestrator state
# string from Get-SMSState.
function Get-SMSStatus {
    $result = @{
        OrchestratorInstalled = $false
        ProxyInstalled        = $false
        ServiceStatus         = 'Absent'
        OrchestratorState     = ''
    }

    $result.OrchestratorInstalled = Test-SMSInstalled
    $result.ProxyInstalled = Test-SMSProxyInstalled

    $svc = Get-Service -Name 'SMS Service' -ErrorAction SilentlyContinue
    if (-not $svc) { $svc = Get-Service -Name 'SMS' -ErrorAction SilentlyContinue }
    if ($svc) { $result.ServiceStatus = [string]$svc.Status }

    if ($result.OrchestratorInstalled) {
        try {
            # Get-SMSState ships with the StorageMigrationService module once
            # the orchestrator role is installed.
            $state = Get-SMSState -ErrorAction Stop
            if ($state) { $result.OrchestratorState = [string]$state.State }
        }
        catch {
            # Role installed but the cmdlet/service is not responding yet.
        }
    }

    return $result
}

# Install the SMS orchestrator role plus its management tools.
function Install-SMSRole {
    if (Test-SMSInstalled) {
        Write-OutputColor "  The Storage Migration Service orchestrator role is already installed." -color "Info"
        return $true
    }
    if (-not (Test-WindowsServer)) {
        Write-OutputColor "  Storage Migration Service is a Windows Server role — this OS is not a server SKU." -color "Error"
        return $false
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        Push-DryRunStep -Label "Install Storage Migration Service orchestrator role" -Category "Roles" -OneWay $false `
            -Preflight {
                if (Test-SMSInstalled) { "SMS orchestrator already installed" }
                elseif (-not (Test-WindowsServer)) { "Not a Windows Server SKU" }
                else { $true }
            } `
            -Apply { Install-SMSRole | Out-Null } `
            -Undo  { Uninstall-WindowsFeature -Name 'SMS' -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null }
        Write-OutputColor "  Queued (Dry-Run): install SMS orchestrator role." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued SMS orchestrator role install"
        return $true
    }

    Write-OutputColor "  Installing the Storage Migration Service orchestrator role..." -color "Info"
    Write-OutputColor "  This can take several minutes." -color "Info"
    $install = Install-WindowsFeatureWithTimeout -FeatureName 'SMS' -DisplayName 'Storage Migration Service' -IncludeManagementTools
    if (-not $install.Success) {
        Write-OutputColor "  SMS orchestrator role install failed." -color "Error"
        if ($install.Error) { Write-OutputColor "  $($install.Error.Trim())" -color "Error" }
        return $false
    }

    if (Test-SMSInstalled) {
        Write-OutputColor "  Storage Migration Service orchestrator installed." -color "Success"
        Add-SessionChange -Category "Roles" -Description "Installed Storage Migration Service orchestrator role"
        if ($null -ne $install.Result -and $install.Result.RestartNeeded -eq 'Yes') {
            Write-OutputColor "  A restart is required to finish the install." -color "Warning"
            $script:RebootNeeded = $true
        }
        return $true
    }
    Write-OutputColor "  Role install completed but SMS is not reporting installed." -color "Error"
    return $false
}

# Install the SMS-Proxy feature. Installed on the destination Windows Server
# so migration data transfers locally rather than through the orchestrator.
function Install-SMSProxy {
    if (Test-SMSProxyInstalled) {
        Write-OutputColor "  The Storage Migration Service proxy is already installed." -color "Info"
        return $true
    }
    if (-not (Test-WindowsServer)) {
        Write-OutputColor "  SMS-Proxy is a Windows Server feature — this OS is not a server SKU." -color "Error"
        return $false
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        Push-DryRunStep -Label "Install Storage Migration Service proxy" -Category "Roles" -OneWay $false `
            -Preflight {
                if (Test-SMSProxyInstalled) { "SMS-Proxy already installed" }
                elseif (-not (Test-WindowsServer)) { "Not a Windows Server SKU" }
                else { $true }
            } `
            -Apply { Install-SMSProxy | Out-Null } `
            -Undo  { Uninstall-WindowsFeature -Name 'SMS-Proxy' -ErrorAction SilentlyContinue | Out-Null }
        Write-OutputColor "  Queued (Dry-Run): install SMS-Proxy feature." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued SMS-Proxy install"
        return $true
    }

    Write-OutputColor "  Installing the Storage Migration Service proxy..." -color "Info"
    $install = Install-WindowsFeatureWithTimeout -FeatureName 'SMS-Proxy' -DisplayName 'Storage Migration Service Proxy'
    if (-not $install.Success) {
        Write-OutputColor "  SMS-Proxy install failed." -color "Error"
        if ($install.Error) { Write-OutputColor "  $($install.Error.Trim())" -color "Error" }
        return $false
    }

    if (Test-SMSProxyInstalled) {
        Write-OutputColor "  Storage Migration Service proxy installed." -color "Success"
        Add-SessionChange -Category "Roles" -Description "Installed Storage Migration Service proxy"
        if ($null -ne $install.Result -and $install.Result.RestartNeeded -eq 'Yes') {
            Write-OutputColor "  A restart is required to finish the install." -color "Warning"
            $script:RebootNeeded = $true
        }
        return $true
    }
    Write-OutputColor "  Proxy install completed but SMS-Proxy is not reporting installed." -color "Error"
    return $false
}

# Interactive Storage Migration Service management menu.
function Show-StorageMigrationManagement {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                    STORAGE MIGRATION SERVICE").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        $status = Get-SMSStatus
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        if ($status.OrchestratorInstalled) {
            Write-OutputColor "  │$("  Orchestrator:  installed".PadRight(72))│" -color "Success"
            if ($status.OrchestratorState) {
                Write-OutputColor "  │$("  SMS state:     $($status.OrchestratorState)".PadRight(72))│" -color "Info"
            }
            Write-OutputColor "  │$("  SMS service:   $($status.ServiceStatus)".PadRight(72))│" -color "Info"
        } else {
            Write-OutputColor "  │$("  Orchestrator:  not installed".PadRight(72))│" -color "Warning"
        }
        $proxyText = if ($status.ProxyInstalled) { "installed" } else { "not installed" }
        $proxyColor = if ($status.ProxyInstalled) { "Success" } else { "Info" }
        Write-OutputColor "  │$("  Proxy:         $proxyText".PadRight(72))│" -color $proxyColor
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        # Honest guidance: SMS migration jobs are a Windows Admin Center workflow.
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  Migration jobs (Inventory > Transfer > Cutover) run from Windows".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Admin Center. RackStack installs and reports the SMS roles; open WAC".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  and add the Storage Migration Service tool to drive a migration.".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-MenuItem "[1]  Install SMS orchestrator role (this server runs the migration project)"
        Write-MenuItem "[2]  Install SMS proxy (run on the destination Windows Server)"
        Write-MenuItem "[3]  Show SMS status"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" {
                if (Confirm-UserAction -Message "  Install the SMS orchestrator role on this server?") {
                    $null = Install-SMSRole
                }
                Write-PressEnter
            }
            "2" {
                if (Confirm-UserAction -Message "  Install the SMS proxy on this server?") {
                    $null = Install-SMSProxy
                }
                Write-PressEnter
            }
            "3" {
                $s = Get-SMSStatus
                Write-OutputColor "" -color "Info"
                if ($s.OrchestratorInstalled) {
                    Write-OutputColor "  Orchestrator installed (state: $($s.OrchestratorState)). Proxy: $(if ($s.ProxyInstalled) { 'installed' } else { 'not installed' })." -color "Success"
                } else {
                    Write-OutputColor "  SMS orchestrator role is not installed." -color "Warning"
                }
                Write-PressEnter
            }
            default {
                Write-OutputColor "  Invalid selection. Enter 1-3 or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}
#endregion
