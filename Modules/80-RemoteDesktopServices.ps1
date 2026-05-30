#region ===== REMOTE DESKTOP SERVICES =====
# RDS role lifecycle + Per-Device/Per-User licensing-mode configuration, plus a
# read-only audit. The licensing MODE has a 120-day grace period before CALs are
# required, so configuring it (and the license-server name) is the useful, safe
# first step for a single-host RDS.
#
# Deliberately deferred (documented, not silently dropped):
#  - Full session-collection deployment (New-RDSessionDeployment): it reconfigures
#    the server into an RDS deployment and requires a reboot — too heavy to ship
#    without validation on a real server.
#  - CAL / license-key activation: done in RD Licensing Manager against a license
#    agreement; that key material is sensitive and best entered in the GUI.
# As a result this module handles NO license key and holds no secret.

# Map of the RDS licensing-mode DWORD values used by the policy registry.
$script:RDSLicenseModeMap = @{ 2 = 'Per Device'; 4 = 'Per User' }

# Report whether the RDS Session Host / Licensing role features are installed and
# whether the RemoteDesktop management tooling is present at all.
function Test-RDSRoleInstalled {
    $r = @{ SessionHost = $false; Licensing = $false; ToolsAvailable = $false }
    $r.ToolsAvailable = [bool](Get-Command Get-RDLicenseConfiguration -ErrorAction SilentlyContinue)
    try {
        if (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue) {
            $sh  = Get-WindowsFeature -Name 'RDS-RD-Server' -ErrorAction SilentlyContinue
            $lic = Get-WindowsFeature -Name 'RDS-Licensing' -ErrorAction SilentlyContinue
            if ($sh)  { $r.SessionHost = ($sh.InstallState  -eq 'Installed') }
            if ($lic) { $r.Licensing   = ($lic.InstallState -eq 'Installed') }
        }
    } catch {}
    return $r
}

# Read the RDS licensing mode + license-server list from the policy registry.
function Get-RDSLicenseMode {
    $p = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
    $res = [PSCustomObject]@{ Mode = 'Not configured (120-day grace)'; ModeValue = $null; LicenseServers = '' }
    try {
        $cfg = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
        if ($cfg -and $null -ne $cfg.LicensingMode) {
            $res.ModeValue = [int]$cfg.LicensingMode
            $res.Mode = if ($script:RDSLicenseModeMap.ContainsKey([int]$cfg.LicensingMode)) { $script:RDSLicenseModeMap[[int]$cfg.LicensingMode] } else { "Unknown ($($cfg.LicensingMode))" }
        }
        if ($cfg -and $cfg.LicenseServers) { $res.LicenseServers = "$($cfg.LicenseServers)" }
    } catch {}
    return $res
}

# Read-only RDS posture: role state + licensing mode/servers.
function Get-RDSStatus {
    $roles = Test-RDSRoleInstalled
    $lic   = Get-RDSLicenseMode
    return [PSCustomObject]@{
        ToolsAvailable       = $roles.ToolsAvailable
        SessionHostInstalled = $roles.SessionHost
        LicensingInstalled   = $roles.Licensing
        LicenseMode          = $lic.Mode
        LicenseModeValue     = $lic.ModeValue
        LicenseServers       = $lic.LicenseServers
    }
}

# Reversible: install the RD Session Host + RD Licensing role features. Captures
# which were missing so the session undo removes only the ones this action added.
function Install-RDSRoles {
    $roles = Test-RDSRoleInstalled
    if ($roles.SessionHost -and $roles.Licensing) {
        Write-OutputColor "  RD Session Host and RD Licensing roles are already installed." -color "Info"
        return $true
    }
    if (-not (Test-WindowsServer)) {
        Write-OutputColor "  Remote Desktop Services is a Windows Server role — this OS is not a server SKU." -color "Error"
        return $false
    }
    $needSh  = -not $roles.SessionHost
    $needLic = -not $roles.Licensing

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        $addSh = $needSh; $addLic = $needLic
        Push-DryRunStep -Label "Install RDS roles (Session Host + Licensing)" -Category "Roles" -OneWay $false `
            -Preflight { if (-not (Test-WindowsServer)) { "Not a Windows Server SKU" } else { $true } }.GetNewClosure() `
            -Apply { Install-RDSRoles | Out-Null }.GetNewClosure() `
            -Undo {
                if ($addLic) { Uninstall-WindowsFeature -Name 'RDS-Licensing' -ErrorAction SilentlyContinue | Out-Null }
                if ($addSh)  { Uninstall-WindowsFeature -Name 'RDS-RD-Server' -ErrorAction SilentlyContinue | Out-Null }
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): install RDS roles." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued RDS role install"
        return $true
    }

    $ok = $true
    if ($needSh) {
        Write-OutputColor "  Installing RD Session Host (RDS-RD-Server)..." -color "Info"
        $r1 = Install-WindowsFeatureWithTimeout -FeatureName 'RDS-RD-Server' -DisplayName 'RD Session Host' -IncludeManagementTools
        if (-not $r1.Success) { $ok = $false; Write-OutputColor "  RD Session Host install failed." -color "Error"; if ($r1.Error) { Write-OutputColor "  $($r1.Error.Trim())" -color "Error" } }
    }
    if ($needLic -and $ok) {
        Write-OutputColor "  Installing RD Licensing (RDS-Licensing)..." -color "Info"
        $r2 = Install-WindowsFeatureWithTimeout -FeatureName 'RDS-Licensing' -DisplayName 'RD Licensing' -IncludeManagementTools
        if (-not $r2.Success) { $ok = $false; Write-OutputColor "  RD Licensing install failed." -color "Error"; if ($r2.Error) { Write-OutputColor "  $($r2.Error.Trim())" -color "Error" } }
    }

    if ($ok) {
        Write-OutputColor "  RDS roles installed. A reboot may be required before the Session Host is usable." -color "Success"
        Add-SessionChange -Category "Roles" -Description "Installed RDS roles (Session Host + Licensing)"
        Clear-MenuCache
        # The Dry-Run queue owns undo when it re-invokes this during apply.
        if (-not $script:ApplyingDryRunQueue) {
            $undoSh = $needSh; $undoLic = $needLic
            Add-UndoAction -Category "Roles" -Description "Installed RDS roles" -UndoScript {
                param($RemoveSh, $RemoveLic)
                if ($RemoveLic) { Uninstall-WindowsFeature -Name 'RDS-Licensing' -ErrorAction SilentlyContinue | Out-Null }
                if ($RemoveSh)  { Uninstall-WindowsFeature -Name 'RDS-RD-Server' -ErrorAction SilentlyContinue | Out-Null }
            } -UndoParams @{ RemoveSh = $undoSh; RemoveLic = $undoLic }
        }
    }
    return $ok
}

# Reversible: set the RDS licensing mode + license-server list via the policy
# registry (the same values the "Set licensing mode" / "license servers" GPOs
# write, which the Session Host honours). No license key is involved.
function Set-RDSLicenseMode {
    param(
        [Parameter(Mandatory)] [ValidateSet('PerDevice', 'PerUser')] [string]$Mode,
        [Parameter(Mandatory)] [string]$LicenseServer
    )
    $server = $LicenseServer.Trim()
    if ($server -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.\-]*$') {
        Write-OutputColor "  Invalid license server name (use a hostname/FQDN)." -color "Error"; return
    }
    $modeValue = if ($Mode -eq 'PerDevice') { 2 } else { 4 }
    $p = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'

    # Capture prior values (null = value/key absent) for a faithful undo.
    $priorMode = $null; $priorServers = $null
    if (Test-Path $p) {
        $cur = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
        if ($cur -and $null -ne $cur.LicensingMode) { $priorMode = [int]$cur.LicensingMode }
        if ($cur -and $cur.LicenseServers) { $priorServers = "$($cur.LicenseServers)" }
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        $mv = $modeValue; $sv = $server; $pm = $priorMode; $ps = $priorServers; $path = $p
        Push-DryRunStep -Label "Set RDS licensing: $Mode via $server" -Category "Roles" -OneWay $false `
            -Params @{ Mode = $Mode; LicenseServer = $server } `
            -Preflight { $true }.GetNewClosure() `
            -Apply {
                if (-not (Test-Path $path)) { New-Item -Path $path -Force -ErrorAction SilentlyContinue | Out-Null }
                Set-ItemProperty -Path $path -Name 'LicensingMode' -Value $mv -Type DWord -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $path -Name 'LicenseServers' -Value $sv -Type String -ErrorAction SilentlyContinue
            }.GetNewClosure() `
            -Undo {
                if ($null -ne $pm) { Set-ItemProperty -Path $path -Name 'LicensingMode' -Value $pm -Type DWord -ErrorAction SilentlyContinue }
                else { Remove-ItemProperty -Path $path -Name 'LicensingMode' -ErrorAction SilentlyContinue }
                if ($null -ne $ps) { Set-ItemProperty -Path $path -Name 'LicenseServers' -Value $ps -Type String -ErrorAction SilentlyContinue }
                else { Remove-ItemProperty -Path $path -Name 'LicenseServers' -ErrorAction SilentlyContinue }
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): set RDS licensing mode to $Mode ($server)." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued RDS licensing-mode change"
        return
    }

    try {
        if (-not (Test-Path $p)) { New-Item -Path $p -Force -ErrorAction Stop | Out-Null }
        Set-ItemProperty -Path $p -Name 'LicensingMode' -Value $modeValue -Type DWord -ErrorAction Stop
        Set-ItemProperty -Path $p -Name 'LicenseServers' -Value $server -Type String -ErrorAction Stop
        Write-OutputColor "  RDS licensing set: $Mode via $server." -color "Success"
        Write-OutputColor "  Activate the license server and install CALs in RD Licensing Manager (licmgr)." -color "Info"
        Add-SessionChange -Category "Roles" -Description "Set RDS licensing mode to $Mode ($server)"
        Clear-MenuCache
        Add-UndoAction -Category "Roles" -Description "Set RDS licensing mode to $Mode" -UndoScript {
            param($Path, $PriorMode, $PriorServers)
            if ($null -ne $PriorMode) { Set-ItemProperty -Path $Path -Name 'LicensingMode' -Value $PriorMode -Type DWord -ErrorAction SilentlyContinue }
            else { Remove-ItemProperty -Path $Path -Name 'LicensingMode' -ErrorAction SilentlyContinue }
            if ($null -ne $PriorServers) { Set-ItemProperty -Path $Path -Name 'LicenseServers' -Value $PriorServers -Type String -ErrorAction SilentlyContinue }
            else { Remove-ItemProperty -Path $Path -Name 'LicenseServers' -ErrorAction SilentlyContinue }
        } -UndoParams @{ Path = $p; PriorMode = $priorMode; PriorServers = $priorServers }
    }
    catch {
        Write-OutputColor "  Failed to set RDS licensing mode: $($_.Exception.Message)" -color "Error"
    }
}

# Interactive: RDS audit + optional role install + optional licensing-mode config.
function Show-RDSManagement {
    Clear-Host
    Write-CenteredOutput "Remote Desktop Services" -color "Info"
    $s = Get-RDSStatus
    $shColor  = if ($s.SessionHostInstalled) { "Success" } else { "Warning" }
    $licColor = if ($s.LicensingInstalled) { "Success" } else { "Warning" }
    $modeColor = if ($s.LicenseModeValue) { "Success" } else { "Warning" }
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  RDS STATUS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  RD Session Host  : $(if ($s.SessionHostInstalled) { 'Installed' } else { 'Not installed' })".PadRight(72))│" -color $shColor
    Write-OutputColor "  │$("  RD Licensing     : $(if ($s.LicensingInstalled) { 'Installed' } else { 'Not installed' })".PadRight(72))│" -color $licColor
    Write-OutputColor "  │$("  Licensing mode   : $($s.LicenseMode)".PadRight(72))│" -color $modeColor
    if ($s.LicenseServers) {
        $line = "  License servers  : $($s.LicenseServers)"
        if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($line.PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Full session-collection deployment and CAL activation are out of scope here:" -color "Info"
    Write-OutputColor "  use Server Manager (RDS deployment) and RD Licensing Manager (CALs) for those." -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not ($s.SessionHostInstalled -and $s.LicensingInstalled)) {
        if (Confirm-UserAction -Message "Install the RD Session Host + RD Licensing roles?") { Install-RDSRoles }
    }

    if (Confirm-UserAction -Message "Configure the RDS licensing mode now?") {
        $modeChoice = (Read-Host "  Licensing mode (1 = Per Device, 2 = Per User)").Trim()
        $mode = switch ($modeChoice) { '1' { 'PerDevice' } '2' { 'PerUser' } default { $null } }
        if (-not $mode) {
            Write-OutputColor "  Cancelled — enter 1 or 2." -color "Info"
        } else {
            $server = (Read-Host "  RD license server hostname/FQDN").Trim()
            if ([string]::IsNullOrWhiteSpace($server)) { Write-OutputColor "  Cancelled — no server entered." -color "Info" }
            else { Set-RDSLicenseMode -Mode $mode -LicenseServer $server }
        }
    }
    Write-PressEnter
}

# CLI: RDSAudit — read-only RDS posture (JSON-aware).
function Start-RDSAudit {
    $s = Get-RDSStatus
    if ($script:CLIOutputFormat -eq 'JSON') {
        Write-Output (@{
            Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'RDSAudit'
            Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
            SessionHostInstalled = $s.SessionHostInstalled
            LicensingInstalled = $s.LicensingInstalled
            LicenseMode = $s.LicenseMode
            LicenseServers = $s.LicenseServers
        } | ConvertTo-Json)
    }
    else { Show-RDSManagement }
    return $true
}
#endregion
