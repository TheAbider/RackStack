#region ===== REMOTE ACCESS / ALWAYS-ON VPN =====
# Stand up the Windows Remote Access (RRAS) role as a VPN server and generate
# Always-On VPN client profiles. This is the gateway half of the remote-access
# stack whose RADIUS auth back end is the NPS module (73-NPS): RRAS forwards
# authentication to an NPS/RADIUS server, NPS applies the network policy.
#
# What this module scripts cleanly:
#   * Install the RemoteAccess (DirectAccess and VPN) role (reversible).
#   * Configure the role as a VPN server (Install-RemoteAccess -VpnType Vpn).
#   * Point VPN authentication at an NPS/RADIUS server (Add-RemoteAccessRadius).
#   * Generate device-tunnel / user-tunnel Always-On VPN ProfileXML from a few
#     prompts — the fiddly part of an AOVPN rollout.
#   * Show the current Remote Access / VPN configuration.
#
# The RADIUS shared secret is handled like every other credential in RackStack:
# collected as a SecureString, held only in the Apply closure, converted to
# plaintext just long enough for the Add-RemoteAccessRadius call, then zeroed.
# It is never written to the Dry-Run queue, its JSON export, or any file.
#
# Connection-request policy / NPS network-policy authoring stays in the NPS
# module and the NPS console — those are multi-object policy trees that do not
# map to a safe one-shot prompt. Generated ProfileXML is a template the operator
# deploys via PowerShell (Add-VpnConnection / the VPNv2 CSP) or Intune.

# Convert a SecureString to plaintext for the brief cmdlet call, then free it.
function ConvertFrom-RAVpnSecure {
    param([Parameter(Mandatory = $true)][System.Security.SecureString]$Secure)
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

# Is the RemoteAccess (DirectAccess and VPN) role installed?
function Test-RemoteAccessRoleInstalled {
    try {
        $f = Get-WindowsFeature -Name RemoteAccess -ErrorAction SilentlyContinue
        if ($null -ne $f -and $f.Installed) { return $true }
    }
    catch { }
    # Fallback: the RRAS service (RemoteAccess) exists once the role is installed.
    $svc = Get-Service -Name RemoteAccess -ErrorAction SilentlyContinue
    return ($null -ne $svc)
}

# Is RRAS actually configured as a VPN server (role installed AND VPN enabled)?
function Test-VpnServerConfigured {
    if (-not (Test-RemoteAccessRoleInstalled)) { return $false }
    try {
        if (Get-Command -Name Get-RemoteAccess -ErrorAction SilentlyContinue) {
            $ra = Get-RemoteAccess -ErrorAction SilentlyContinue
            if ($null -ne $ra -and "$($ra.VpnStatus)" -eq 'Installed') { return $true }
        }
    }
    catch { }
    return $false
}

function Get-RemoteAccessStatus {
    return [PSCustomObject]@{
        Installed     = (Test-RemoteAccessRoleInstalled)
        VpnConfigured = (Test-VpnServerConfigured)
    }
}

# Resolve an admin-only directory for generated Always-On VPN ProfileXML.
# Profiles describe the corporate VPN topology (server FQDNs, internal routes,
# DNS suffixes, cert-template references) and are consumed by privileged
# deployment tooling, so they belong under the shared hardened state dir
# (Get-RackStackSecureStateDir applies SetAccessRuleProtection + Admins/SYSTEM-
# only ACEs the child inherits) rather than a world-readable temp path where a
# non-admin could read or tamper with a profile before it is deployed.
function Get-AOVPNProfileDir {
    $secure = Get-RackStackSecureStateDir
    if ([string]::IsNullOrWhiteSpace($secure)) {
        # Fallback only — the hardened dir creation essentially never fails. A
        # ProfileXML describes the corporate VPN topology (server FQDNs, internal
        # routes, DNS suffixes, cert-template names); on a non-hardened path a
        # non-admin could read it for reconnaissance or tamper with it before it
        # is deployed. Warn explicitly and treat the output as sensitive.
        Write-OutputColor "  Warning: could not use the protected state directory; VPN profiles will go" -color "Warning"
        Write-OutputColor "  to a non-hardened path. The profile exposes VPN topology — restrict its ACL" -color "Warning"
        Write-OutputColor "  and verify its contents before deploying it fleet-wide." -color "Warning"
        $secure = $script:TempPath
    }
    $dir = Join-Path $secure "AOVPNProfiles"
    if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -LiteralPath $dir -ItemType Directory -Force -ErrorAction SilentlyContinue }
    return $dir
}

# Interactive: install the RemoteAccess role.
function Install-RemoteAccessRole {
    Clear-Host
    Write-CenteredOutput "Install Remote Access (VPN) Role" -color "Info"
    if (Test-RemoteAccessRoleInstalled) {
        Write-OutputColor "  Remote Access (RemoteAccess role) is already installed." -color "Info"
        return $true
    }
    if (-not (Confirm-UserAction -Message "Install the Remote Access (DirectAccess and VPN) role?")) {
        Write-OutputColor "  Cancelled." -color "Info"; return $false
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        Push-DryRunStep -Label "Install Remote Access (VPN) role" -Category "Roles" -OneWay $false `
            -Params @{ Feature = "RemoteAccess" } `
            -Preflight {
                if ((Get-WindowsFeature -Name RemoteAccess -ErrorAction SilentlyContinue).Installed) { "RemoteAccess already installed" }
                else { $true }
            }.GetNewClosure() `
            -Apply {
                # Shared timeout wrapper (runs the install in a job so a hung
                # feature install can't block the commit indefinitely).
                Install-WindowsFeatureWithTimeout -FeatureName 'RemoteAccess' -DisplayName 'Remote Access' -IncludeManagementTools | Out-Null
            }.GetNewClosure() `
            -Undo {
                Uninstall-WindowsFeature -Name RemoteAccess -ErrorAction SilentlyContinue | Out-Null
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): install Remote Access (VPN) role." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued Remote Access role install"
        return $true
    }

    $install = Install-WindowsFeatureWithTimeout -FeatureName 'RemoteAccess' -DisplayName 'Remote Access' -IncludeManagementTools
    if (-not $install.Success) {
        Write-OutputColor "  Failed to install Remote Access role." -color "Error"
        if ($install.Error) { Write-OutputColor "  $($install.Error.Trim())" -color "Error" }
        return $false
    }
    Write-OutputColor "  Remote Access role installed." -color "Success"
    if ($null -ne $install.Result -and $install.Result.RestartNeeded -eq 'Yes') {
        Write-OutputColor "  A restart is required to complete installation." -color "Warning"
    }
    Add-SessionChange -Category "Roles" -Description "Installed Remote Access (VPN) role"
    Add-UndoAction -Category "Roles" -Description "Installed Remote Access (VPN) role" -UndoScript {
        Uninstall-WindowsFeature -Name RemoteAccess -ErrorAction SilentlyContinue | Out-Null
    }
    Clear-MenuCache
    return $true
}

# Interactive: configure RRAS as a VPN server.
function Enable-VpnServer {
    Clear-Host
    Write-CenteredOutput "Configure VPN Server" -color "Info"
    if (-not (Test-RemoteAccessRoleInstalled)) {
        Write-OutputColor "  Install the Remote Access role first." -color "Error"; return
    }
    if (Test-VpnServerConfigured) {
        Write-OutputColor "  RRAS is already configured as a VPN server." -color "Info"; return
    }
    if (-not (Get-Command -Name Install-RemoteAccess -ErrorAction SilentlyContinue)) {
        Write-OutputColor "  The RemoteAccess PowerShell module is unavailable (management tools" -color "Error"
        Write-OutputColor "  may still be installing — a restart can be required). Try again later." -color "Error"
        return
    }

    Write-OutputColor "  This enables the VPN server role on RRAS (SSTP + IKEv2 by default)." -color "Info"
    if (-not (Confirm-UserAction -Message "Configure RRAS as a VPN server now?")) {
        Write-OutputColor "  Cancelled." -color "Info"; return
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        Push-DryRunStep -Label "Configure RRAS as a VPN server" -Category "Network" -OneWay $false `
            -Params @{ VpnType = "Vpn" } `
            -Preflight {
                if (Test-VpnServerConfigured) { "VPN server already configured" } else { $true }
            }.GetNewClosure() `
            -Apply {
                Install-RemoteAccess -VpnType Vpn -ErrorAction Stop | Out-Null
            }.GetNewClosure() `
            -Undo {
                Uninstall-RemoteAccess -Force -ErrorAction SilentlyContinue | Out-Null
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): configure RRAS as a VPN server." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued VPN server configuration"
        return
    }

    try {
        Install-RemoteAccess -VpnType Vpn -ErrorAction Stop | Out-Null
        Write-OutputColor "  RRAS configured as a VPN server." -color "Success"
        Add-SessionChange -Category "Network" -Description "Configured RRAS as a VPN server"
        Add-UndoAction -Category "Network" -Description "Configured RRAS as a VPN server" -UndoScript {
            Uninstall-RemoteAccess -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Clear-MenuCache
    }
    catch {
        Write-OutputColor "  Failed to configure the VPN server: $($_.Exception.Message)" -color "Error"
    }
}

# Interactive: point VPN authentication at an NPS / RADIUS server.
function Set-VpnRadiusAuth {
    Clear-Host
    Write-CenteredOutput "VPN RADIUS (NPS) Authentication" -color "Info"
    if (-not (Test-VpnServerConfigured)) {
        Write-OutputColor "  Configure the VPN server first." -color "Error"; return
    }
    if (-not (Get-Command -Name Add-RemoteAccessRadius -ErrorAction SilentlyContinue)) {
        Write-OutputColor "  The RemoteAccess PowerShell module is unavailable." -color "Error"; return
    }

    Write-OutputColor "  NPS / RADIUS server address (IPv4/IPv6/FQDN):" -color "Info"
    $server = (Read-Host).Trim()
    $navResult = Test-NavigationCommand -UserInput $server
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($server)) { Write-OutputColor "  Server cannot be empty." -color "Error"; return }

    Write-OutputColor "  RADIUS shared secret (input hidden — must match the NPS client entry):" -color "Info"
    $secure = Read-Host -AsSecureString
    if ($null -eq $secure -or $secure.Length -eq 0) { Write-OutputColor "  Shared secret cannot be empty." -color "Error"; return }

    if (-not (Confirm-UserAction -Message "Use RADIUS server '$server' for VPN authentication?")) {
        Write-OutputColor "  Cancelled." -color "Info"; return
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        $capServer = $server; $capSecure = $secure
        Push-DryRunStep -Label "Set VPN RADIUS auth -> '$capServer'" -Category "Network" -OneWay $false `
            -Params @{ Server = $capServer } `
            -Preflight { $true } `
            -Apply {
                # Secret lives only here, converted just for the cmdlet call.
                $plain = ConvertFrom-RAVpnSecure -Secure $capSecure
                Add-RemoteAccessRadius -ServerName $capServer -SharedSecret $plain -Purpose Authentication -MsgAuthenticator Enabled -ErrorAction Stop | Out-Null
                $plain = $null
                Set-VpnAuthType -Type ExternalRadius -ErrorAction SilentlyContinue | Out-Null
            }.GetNewClosure() `
            -Undo {
                # Remove the RADIUS server AND revert auth back to Windows — else
                # the VPN is left pointing at ExternalRadius with no server (a
                # broken state where every client auth fails).
                Remove-RemoteAccessRadius -ServerName $capServer -Purpose Authentication -ErrorAction SilentlyContinue | Out-Null
                Set-VpnAuthType -Type Windows -ErrorAction SilentlyContinue | Out-Null
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): set VPN RADIUS authentication." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued VPN RADIUS auth -> $capServer"
        return
    }

    try {
        $plain = ConvertFrom-RAVpnSecure -Secure $secure
        Add-RemoteAccessRadius -ServerName $server -SharedSecret $plain -Purpose Authentication -MsgAuthenticator Enabled -ErrorAction Stop | Out-Null
        $plain = $null
        Set-VpnAuthType -Type ExternalRadius -ErrorAction SilentlyContinue | Out-Null
        Write-OutputColor "  VPN authentication now uses RADIUS server '$server'." -color "Success"
        Add-SessionChange -Category "Network" -Description "Set VPN RADIUS auth -> $server"
        Add-UndoAction -Category "Network" -Description "Set VPN RADIUS auth -> $server" -UndoScript {
            param($RadiusServer)
            # Revert RADIUS server AND auth type together, or auth is left pointing
            # at ExternalRadius with no server registered (all client auth fails).
            Remove-RemoteAccessRadius -ServerName $RadiusServer -Purpose Authentication -ErrorAction SilentlyContinue | Out-Null
            Set-VpnAuthType -Type Windows -ErrorAction SilentlyContinue | Out-Null
        } -UndoParams @{ RadiusServer = $server }
        Clear-MenuCache
    }
    catch {
        $plain = $null
        Write-OutputColor "  Failed to set RADIUS authentication: $($_.Exception.Message)" -color "Error"
    }
}

# Build an Always-On VPN ProfileXML string from the collected settings.
function New-AOVPNProfileXml {
    param(
        [Parameter(Mandatory = $true)][string]$ServerFqdn,
        [Parameter(Mandatory = $true)][ValidateSet('IKEv2', 'SSTP', 'Automatic')][string]$Protocol,
        [Parameter(Mandatory = $true)][bool]$DeviceTunnel,
        [Parameter(Mandatory = $true)][bool]$ForceTunnel,
        [string]$DnsSuffix = "",
        [string[]]$Routes = @()
    )
    # User-supplied values are XML-escaped before interpolation so a stray '<',
    # '&', or '</...>' in an FQDN / DNS suffix / route can't break out of its
    # element or extend the profile with attacker-controlled markup. ($Protocol
    # is a ValidateSet value and needs no escaping.)
    $sfqdn = [System.Security.SecurityElement]::Escape($ServerFqdn)
    $sdns = [System.Security.SecurityElement]::Escape($DnsSuffix)
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<VPNProfile>')
    if (-not [string]::IsNullOrWhiteSpace($DnsSuffix)) {
        [void]$sb.AppendLine("  <DnsSuffix>$sdns</DnsSuffix>")
    }
    [void]$sb.AppendLine('  <NativeProfile>')
    [void]$sb.AppendLine("    <Servers>$sfqdn</Servers>")
    [void]$sb.AppendLine("    <NativeProtocolType>$Protocol</NativeProtocolType>")
    [void]$sb.AppendLine('    <RoutingPolicyType>' + $(if ($ForceTunnel) { 'ForceTunnel' } else { 'SplitTunnel' }) + '</RoutingPolicyType>')
    if ($DeviceTunnel) {
        # Device tunnel: machine-certificate auth (no EAP / no user interaction).
        [void]$sb.AppendLine('    <Authentication>')
        [void]$sb.AppendLine('      <MachineMethod>Certificate</MachineMethod>')
        [void]$sb.AppendLine('    </Authentication>')
    }
    else {
        # User tunnel: EAP-TLS template (operator points it at the client-auth
        # cert via the VPN client UI or a completed EapHostConfig block).
        [void]$sb.AppendLine('    <Authentication>')
        [void]$sb.AppendLine('      <UserMethod>Eap</UserMethod>')
        [void]$sb.AppendLine('      <Eap>')
        [void]$sb.AppendLine('        <Configuration>')
        [void]$sb.AppendLine('          <!-- Replace with your EAP-TLS EapHostConfig (Get-VpnConnection | Select EapConfigXmlStream). -->')
        [void]$sb.AppendLine('        </Configuration>')
        [void]$sb.AppendLine('      </Eap>')
        [void]$sb.AppendLine('    </Authentication>')
    }
    [void]$sb.AppendLine('  </NativeProfile>')
    if (-not $ForceTunnel) {
        foreach ($r in $Routes) {
            if ([string]::IsNullOrWhiteSpace($r)) { continue }
            $parts = $r.Split('/')
            $addr = [System.Security.SecurityElement]::Escape($parts[0].Trim())
            $prefix = if ($parts.Count -gt 1) { [System.Security.SecurityElement]::Escape($parts[1].Trim()) } else { "32" }
            [void]$sb.AppendLine('  <Route>')
            [void]$sb.AppendLine("    <Address>$addr</Address>")
            [void]$sb.AppendLine("    <PrefixSize>$prefix</PrefixSize>")
            [void]$sb.AppendLine('  </Route>')
        }
    }
    if ($DeviceTunnel) {
        [void]$sb.AppendLine('  <DeviceTunnel>true</DeviceTunnel>')
        [void]$sb.AppendLine('  <RegisterDNS>true</RegisterDNS>')
    }
    else {
        [void]$sb.AppendLine('  <AlwaysOn>true</AlwaysOn>')
        if (-not [string]::IsNullOrWhiteSpace($DnsSuffix)) {
            [void]$sb.AppendLine("  <TrustedNetworkDetection>$sdns</TrustedNetworkDetection>")
        }
    }
    [void]$sb.AppendLine('</VPNProfile>')
    return $sb.ToString()
}

# Interactive: generate an Always-On VPN ProfileXML and write it to disk.
function New-AlwaysOnVpnProfile {
    Clear-Host
    Write-CenteredOutput "Generate Always-On VPN Profile" -color "Info"

    Write-OutputColor "  VPN server public FQDN (must match the gateway certificate SAN):" -color "Info"
    $fqdn = (Read-Host).Trim()
    $navResult = Test-NavigationCommand -UserInput $fqdn
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($fqdn)) { Write-OutputColor "  FQDN cannot be empty." -color "Error"; return }

    Write-OutputColor "  Tunnel type — [U] User tunnel (EAP-TLS) or [D] Device tunnel (machine cert):" -color "Info"
    $tt = (Read-Host).Trim().ToUpper()
    $deviceTunnel = ($tt -eq "D")

    Write-OutputColor "  Protocol — [1] IKEv2  [2] SSTP  [3] Automatic (default 1):" -color "Info"
    $pAns = (Read-Host).Trim()
    $protocol = switch ($pAns) { "2" { "SSTP" } "3" { "Automatic" } default { "IKEv2" } }

    Write-OutputColor "  Routing — [S] Split tunnel (default) or [F] Force tunnel:" -color "Info"
    $rt = (Read-Host).Trim().ToUpper()
    $forceTunnel = ($rt -eq "F")

    Write-OutputColor "  Internal DNS suffix (e.g. corp.example.com — blank to skip):" -color "Info"
    $dnsSuffix = (Read-Host).Trim()

    $routes = @()
    if (-not $forceTunnel) {
        Write-OutputColor "  Split-tunnel routes as CIDR, comma-separated (e.g. 10.0.0.0/8,192.168.1.0/24" -color "Info"
        Write-OutputColor "  — blank to skip):" -color "Info"
        $routeInput = (Read-Host).Trim()
        if (-not [string]::IsNullOrWhiteSpace($routeInput)) {
            $routes = $routeInput.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        }
    }

    $xml = New-AOVPNProfileXml -ServerFqdn $fqdn -Protocol $protocol -DeviceTunnel $deviceTunnel `
        -ForceTunnel $forceTunnel -DnsSuffix $dnsSuffix -Routes $routes

    $dir = Get-AOVPNProfileDir
    $kind = if ($deviceTunnel) { "device" } else { "user" }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $file = Join-Path $dir "aovpn-$kind-tunnel-$stamp.xml"
    try {
        Set-Content -LiteralPath $file -Value $xml -Encoding UTF8 -ErrorAction Stop
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Generated $kind-tunnel Always-On VPN profile:" -color "Success"
        Write-OutputColor "    $file" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Deploy it with the VPNv2 CSP (Intune) or, per device, with PowerShell:" -color "Info"
        Write-OutputColor "    \$x = Get-Content '$file' -Raw" -color "Debug"
        Write-OutputColor "    Add-VpnConnection ... then apply the ProfileXML via the MDM bridge." -color "Debug"
        Add-SessionChange -Category "Network" -Description "Generated AOVPN $kind-tunnel profile for $fqdn"
    }
    catch {
        Write-OutputColor "  Failed to write the profile: $($_.Exception.Message)" -color "Error"
    }
}

# Show the current Remote Access / VPN configuration (read-only).
function Show-RemoteAccessConfig {
    Clear-Host
    Write-CenteredOutput "Remote Access / VPN Configuration" -color "Info"
    if (-not (Test-RemoteAccessRoleInstalled)) {
        Write-OutputColor "  Install the Remote Access role first." -color "Error"; return
    }
    Write-OutputColor "" -color "Info"
    try {
        if (Get-Command -Name Get-RemoteAccess -ErrorAction SilentlyContinue) {
            $ra = Get-RemoteAccess -ErrorAction SilentlyContinue
            if ($null -ne $ra) {
                Write-OutputColor "  VPN status         : $($ra.VpnStatus)" -color "Info"
                Write-OutputColor "  DA status          : $($ra.DAStatus)" -color "Info"
            }
        }
        if (Get-Command -Name Get-VpnServerConfiguration -ErrorAction SilentlyContinue) {
            $vc = Get-VpnServerConfiguration -ErrorAction SilentlyContinue
            if ($null -ne $vc) {
                Write-OutputColor "  Tunnel types       : $($vc.TunnelType -join ', ')" -color "Info"
                Write-OutputColor "  IPsec idle timeout : $($vc.IdleDisconnectSeconds)s" -color "Info"
            }
        }
        if (Get-Command -Name Get-RemoteAccessRadius -ErrorAction SilentlyContinue) {
            $rad = Get-RemoteAccessRadius -ErrorAction SilentlyContinue
            if ($null -ne $rad) {
                foreach ($r in @($rad)) {
                    Write-OutputColor "  RADIUS server      : $($r.ServerName) (purpose: $($r.Purpose))" -color "Info"
                }
            }
        }
    }
    catch {
        Write-OutputColor "  Could not read the full configuration: $($_.Exception.Message)" -color "Warning"
    }
}

# CLI entry: AlwaysOnVPNSetup — install the role + configure the VPN server (JSON-aware).
function Start-AlwaysOnVPNSetup {
    $roleInstalled = Test-RemoteAccessRoleInstalled
    if (-not $roleInstalled) {
        $install = Install-WindowsFeatureWithTimeout -FeatureName 'RemoteAccess' -DisplayName 'Remote Access' -IncludeManagementTools
        if (-not $install.Success) {
            if ($script:CLIOutputFormat -eq 'JSON') {
                Write-Output (@{ Action = 'AlwaysOnVPNSetup'; Success = $false; Stage = 'RoleInstall' } | ConvertTo-Json)
            }
            else {
                Write-OutputColor "  Remote Access role install: FAILED" -color "Error"
                if ($install.Error) { Write-OutputColor "  $($install.Error.Trim())" -color "Error" }
            }
            return $false
        }
        $roleInstalled = $true
    }

    $vpnConfigured = Test-VpnServerConfigured
    $changed = $false
    if (-not $vpnConfigured -and (Get-Command -Name Install-RemoteAccess -ErrorAction SilentlyContinue)) {
        try {
            Install-RemoteAccess -VpnType Vpn -ErrorAction Stop | Out-Null
            $vpnConfigured = $true; $changed = $true
        }
        catch {
            if ($script:CLIOutputFormat -ne 'JSON') {
                Write-OutputColor "  VPN server configuration failed: $($_.Exception.Message)" -color "Error"
            }
        }
    }

    # Success tracks the role install (the primary, idempotent action): enabling
    # the VPN server can legitimately require a reboot before Install-RemoteAccess
    # is available, so a not-yet-configured VPN is not a failure. Callers that
    # care read VpnConfigured/Changed from the JSON output below.
    $ok = [bool]($roleInstalled)
    if ($script:CLIOutputFormat -eq 'JSON') {
        Write-Output (@{
            Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'AlwaysOnVPNSetup'
            Hostname = $env:COMPUTERNAME; Success = $ok; RoleInstalled = $roleInstalled
            VpnConfigured = $vpnConfigured; Changed = $changed
        } | ConvertTo-Json)
    }
    else {
        Write-OutputColor "  Remote Access role : $(if ($roleInstalled) { 'Installed' } else { 'Not installed' })" -color $(if ($roleInstalled) { "Success" } else { "Error" })
        Write-OutputColor "  VPN server         : $(if ($vpnConfigured) { 'Configured' } else { 'Not configured' })" -color $(if ($vpnConfigured) { "Success" } else { "Warning" })
    }
    return $ok
}

# Remote Access / Always-On VPN submenu (Roles & Features > [11]).
function Show-RemoteAccessManagement {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                  REMOTE ACCESS / ALWAYS-ON VPN").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        $status = Get-RemoteAccessStatus
        $roleText = if ($status.Installed) { "Installed" } else { "Not Installed" }
        $roleColor = if ($status.Installed) { "Success" } else { "Warning" }
        $vpnText = if ($status.VpnConfigured) { "Configured" } else { "Not Configured" }
        $vpnColor = if ($status.VpnConfigured) { "Success" } else { "Warning" }

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-MenuItem "  Remote Access role" -Status $roleText -StatusColor $roleColor
        Write-MenuItem "  VPN server" -Status $vpnText -StatusColor $vpnColor
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  Install Remote Access Role" -Status "DirectAccess and VPN (RAS)" -StatusColor "Info"
        Write-MenuItem "[2]  Configure VPN Server" -Status "Enable RRAS as a VPN server" -StatusColor "Info"
        Write-MenuItem "[3]  Set RADIUS (NPS) Authentication" -Status "Forward auth to an NPS server" -StatusColor "Info"
        Write-MenuItem "[4]  Generate Always-On VPN Profile" -Status "Device / user tunnel ProfileXML" -StatusColor "Info"
        Write-MenuItem "[5]  Show Configuration" -Status "Current VPN / RADIUS settings" -StatusColor "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) {
            if (Invoke-NavigationAction -NavResult $navResult) { return }
            return
        }
        switch ("$choice".ToUpper()) {
            "1" { Install-RemoteAccessRole; Write-PressEnter }
            "2" { Enable-VpnServer; Write-PressEnter }
            "3" { Set-VpnRadiusAuth; Write-PressEnter }
            "4" { New-AlwaysOnVpnProfile; Write-PressEnter }
            "5" { Show-RemoteAccessConfig; Write-PressEnter }
            "B" { return }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-5 or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}
#endregion
