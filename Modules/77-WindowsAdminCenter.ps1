#region ===== WINDOWS ADMIN CENTER (WAC GATEWAY) =====
# Install and configure the Windows Admin Center gateway on this host. WAC is
# Microsoft's browser-based management surface; this module covers the parts
# that script cleanly: install the gateway MSI, bind it to a port + TLS cert,
# open the firewall, report status, and uninstall — every step reversible.
#
# Supply chain: RackStack never runs an installer it hasn't verified. The MSI
# source is operator-controlled — an operator-provided local path (default), or
# (opt-in, confirmed) a download from Microsoft's official https://aka.ms URL —
# and in BOTH cases the file must pass an Authenticode check (signature Valid
# AND signed by "O=Microsoft Corporation") before msiexec runs, with an optional
# SHA-256 pin. A failed check deletes any downloaded file and refuses to install.
#
# Out of scope for v1 (WAC packaging/direction is in flux): extension management,
# Azure-connected / Arc-integrated WAC, post-install cert re-binding automation
# (printed as guidance), and managed-node setup (node readiness already lives in
# the WACConnectivityAudit action). This module is gateway-host-only.
#
# Secrets: none — WAC uses Windows / Azure AD auth; nothing SecureString-worthy
# is collected, so no hardened-state staging is needed.

$script:WACServiceName = 'ServerManagementGateway'
$script:WACDownloadUrl = 'https://aka.ms/WACDownload'

# Is the WAC gateway installed? Service presence is authoritative.
function Test-WACInstalled {
    return ($null -ne (Get-Service -Name $script:WACServiceName -ErrorAction SilentlyContinue))
}

# Resolve the WAC product code (GUID) from the Uninstall registry, for /x.
function Get-WACProductCode {
    foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        try {
            $match = Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | Where-Object {
                $dn = (Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue).DisplayName
                $dn -match 'Windows Admin Center'
            } | Select-Object -First 1
            if ($match) { return $match.PSChildName }
        }
        catch { }
    }
    return $null
}

# Status object (peer of Get-NPSStatus / Get-SIEMForwarderStatus).
function Get-WACStatus {
    $svc = Get-Service -Name $script:WACServiceName -ErrorAction SilentlyContinue
    $installed = ($null -ne $svc)
    $port = $null; $listening = $false
    if ($installed) {
        try { $port = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\ServerManagementExperience' -ErrorAction Stop).SmePort } catch { }
        if ($port) {
            try { $listening = [bool](Get-NetTCPConnection -State Listen -LocalPort ([int]$port) -ErrorAction SilentlyContinue) } catch { }
        }
    }
    return [PSCustomObject]@{
        Installed     = $installed
        ServiceStatus = if ($svc) { "$($svc.Status)" } else { "" }
        Port          = $port
        PortListening = $listening
    }
}

# Validate an operator-supplied MSI path (rooted, exists, .msi, no traversal/reparse).
function Test-WACSafeMsiPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($Path -match '\.\.' -or $Path.Contains([char]0) -or $Path.Length -gt 255) { return $false }
    if (-not [System.IO.Path]::IsPathRooted($Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    if ([System.IO.Path]::GetExtension($Path).ToLower() -ne '.msi') { return $false }
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $false }
    }
    catch { return $false }
    return $true
}

# Fail-closed Authenticode (+ optional SHA-256) gate. The MSI must be Valid and
# signed by Microsoft before it is ever executed.
function Test-WACMsiSignature {
    param([Parameter(Mandatory = $true)][string]$Path, [string]$ExpectedHash)
    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
        if ("$($sig.Status)" -ne 'Valid') {
            Write-OutputColor "  Authenticode signature is not Valid (status: $($sig.Status)) — refusing to install." -color "Error"
            return $false
        }
        if (($null -eq $sig.SignerCertificate) -or ($sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation')) {
            Write-OutputColor "  MSI is not signed by Microsoft Corporation — refusing to install." -color "Error"
            return $false
        }
    }
    catch {
        Write-OutputColor "  Could not verify the MSI signature: $($_.Exception.Message)" -color "Error"
        return $false
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedHash)) {
        $h = (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
        if ($h -ne $ExpectedHash.Trim()) {
            Write-OutputColor "  SHA-256 does not match the expected hash — refusing to install." -color "Error"
            return $false
        }
    }
    return $true
}

# Download the WAC MSI from Microsoft's official URL (opt-in, confirmed by caller).
# Returns the local temp path, or $null on failure (temp file deleted on failure).
function Get-WACMsiDownload {
    $dest = Join-Path $script:TempPath ("WindowsAdminCenter-" + [System.Guid]::NewGuid().ToString("N") + ".msi")
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Write-OutputColor "  Downloading the WAC MSI from $($script:WACDownloadUrl) ..." -color "Info"
        Invoke-WebRequest -Uri $script:WACDownloadUrl -OutFile $dest -UseBasicParsing -ErrorAction Stop
        return $dest
    }
    catch {
        Write-OutputColor "  Download failed: $($_.Exception.Message)" -color "Error"
        if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue }
        return $null
    }
}

# Let the operator pick an existing Server-Auth certificate by thumbprint, or
# return $null to let the installer generate a self-signed certificate.
function Select-WACCertificate {
    $serverAuth = '1.3.6.1.5.5.7.3.1'
    $certs = @(Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object {
            $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) -and
            ((@($_.EnhancedKeyUsageList).Count -eq 0) -or (@($_.EnhancedKeyUsageList | ForEach-Object { $_.ObjectId }) -contains $serverAuth))
        })
    if ($certs.Count -eq 0) {
        Write-OutputColor "  No suitable Server-Authentication certificate in LocalMachine\My." -color "Warning"
        Write-OutputColor "  The installer will generate a self-signed certificate." -color "Info"
        return $null
    }
    Write-OutputColor "  Certificates available for the WAC gateway:" -color "Info"
    for ($i = 0; $i -lt $certs.Count; $i++) {
        Write-OutputColor ("   [{0}] {1}  (expires {2})" -f ($i + 1), $certs[$i].Subject, $certs[$i].NotAfter.ToString('yyyy-MM-dd')) -color "Info"
    }
    Write-OutputColor "   [0] Generate a self-signed certificate instead" -color "Info"
    $pick = (Read-Host "  Select").Trim()
    if ($pick -eq '0' -or [string]::IsNullOrWhiteSpace($pick)) { return $null }
    if ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $certs.Count) {
        return $certs[[int]$pick - 1].Thumbprint
    }
    Write-OutputColor "  Invalid selection; the installer will generate a self-signed certificate." -color "Warning"
    return $null
}

# Open the chosen WAC TCP port (reversible — undo removes only our rule).
function Enable-WACFirewallRule {
    param([Parameter(Mandatory = $true)][int]$Port)
    $ruleName = "RackStack WAC HTTPS $Port"
    if (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue) { return }
    try {
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort $Port `
            -Action Allow -Profile Domain, Private -ErrorAction Stop | Out-Null
        Write-OutputColor "  Opened TCP $Port (Domain + Private profiles)." -color "Success"
        Add-UndoAction -Category "Security" -Description "Opened WAC firewall port $Port" -UndoScript {
            param($Name)
            Remove-NetFirewallRule -DisplayName $Name -ErrorAction SilentlyContinue
        } -UndoParams @{ Name = $ruleName }
    }
    catch {
        Write-OutputColor "  Could not open the firewall port: $($_.Exception.Message)" -color "Warning"
    }
}

# Run msiexec to install the (already-verified) WAC MSI. Returns the exit code.
function Invoke-WACInstaller {
    param([string]$Msi, [int]$Port, [string]$CertOption, [string]$Thumbprint)
    $log = Join-Path $script:TempPath ("wac-install-" + (Get-Date -Format 'yyyyMMddHHmmss') + ".log")
    $msiArgs = @('/i', $Msi, '/qn', '/norestart', "SME_PORT=$Port", "SSL_CERTIFICATE_OPTION=$CertOption")
    if ($CertOption -eq 'installed' -and -not [string]::IsNullOrWhiteSpace($Thumbprint)) {
        $msiArgs += "SME_THUMBPRINT=$Thumbprint"
    }
    $msiArgs += @('/l*v', $log)
    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
    if ($proc.ExitCode -notin @(0, 3010, 1641)) {
        Write-OutputColor "  msiexec exited $($proc.ExitCode). See log: $log" -color "Error"
    }
    return $proc.ExitCode
}

# Interactive: install + configure the WAC gateway.
function Install-WAC {
    Clear-Host
    Write-CenteredOutput "Install Windows Admin Center" -color "Info"
    if (Test-WACInstalled) {
        Write-OutputColor "  Windows Admin Center is already installed." -color "Info"; return
    }

    # --- Source: operator-provided MSI, or opt-in Microsoft download. ---
    Write-OutputColor "  Path to the Windows Admin Center MSI (blank to download from Microsoft):" -color "Info"
    $msiPath = (Read-Host).Trim().Trim('"')
    $navResult = Test-NavigationCommand -UserInput $msiPath
    if ($navResult.ShouldReturn) { return }
    $downloaded = $false
    if ([string]::IsNullOrWhiteSpace($msiPath)) {
        if (-not (Confirm-UserAction -Message "Download the WAC MSI from $($script:WACDownloadUrl)?")) {
            Write-OutputColor "  Cancelled — provide an MSI path to install offline." -color "Info"; return
        }
        $msiPath = Get-WACMsiDownload
        if (-not $msiPath) { return }
        $downloaded = $true
    }
    elseif (-not (Test-WACSafeMsiPath $msiPath)) {
        Write-OutputColor "  MSI path is invalid (must be a rooted .msi file that exists)." -color "Error"; return
    }

    # --- Verify before doing anything else. ---
    if (-not (Test-WACMsiSignature -Path $msiPath)) {
        if ($downloaded -and (Test-Path -LiteralPath $msiPath)) { Remove-Item -LiteralPath $msiPath -Force -ErrorAction SilentlyContinue }
        return
    }
    Write-OutputColor "  MSI verified (Microsoft-signed)." -color "Success"

    # --- Port + certificate. ---
    Write-OutputColor "  Gateway port [default 443; 6516 is the common alternative]:" -color "Info"
    $portIn = (Read-Host).Trim()
    $port = 443
    if ($portIn -match '^\d+$') { $port = [int]$portIn }
    if ($port -lt 1 -or $port -gt 65535) { Write-OutputColor "  Invalid port number. Enter 1-65535." -color "Error"; return }

    $thumb = Select-WACCertificate
    $certOption = if ([string]::IsNullOrWhiteSpace($thumb)) { 'generate' } else { 'installed' }

    if (-not (Confirm-UserAction -Message "Install WAC on port $port (certificate: $certOption)?")) {
        Write-OutputColor "  Cancelled." -color "Info"
        if ($downloaded -and (Test-Path -LiteralPath $msiPath)) { Remove-Item -LiteralPath $msiPath -Force -ErrorAction SilentlyContinue }
        return
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        $capMsi = $msiPath; $capPort = $port; $capOpt = $certOption; $capThumb = $thumb; $capDl = $downloaded
        Push-DryRunStep -Label "Install Windows Admin Center (port $capPort)" -Category "Roles" -OneWay $false `
            -Params @{ Port = $capPort; CertOption = $capOpt } `
            -Preflight { if (Test-WACInstalled) { "WAC already installed" } else { $true } }.GetNewClosure() `
            -Apply {
                # Re-verify the MSI at commit time — the file could have been swapped
                # between queueing and apply (TOCTOU). Never install an unverified MSI.
                if (-not (Test-WACMsiSignature -Path $capMsi)) {
                    Write-OutputColor "  MSI failed verification at apply time — aborting install." -color "Error"
                    if ($capDl -and (Test-Path -LiteralPath $capMsi)) { Remove-Item -LiteralPath $capMsi -Force -ErrorAction SilentlyContinue }
                    return
                }
                $code = Invoke-WACInstaller -Msi $capMsi -Port $capPort -CertOption $capOpt -Thumbprint $capThumb
                if ($code -in @(0, 3010, 1641)) { Enable-WACFirewallRule -Port $capPort }
                if ($capDl -and (Test-Path -LiteralPath $capMsi)) { Remove-Item -LiteralPath $capMsi -Force -ErrorAction SilentlyContinue }
            }.GetNewClosure() `
            -Undo {
                # Reverse both the install AND the firewall rule we open on apply.
                $pc = Get-WACProductCode
                if ($pc) { Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/x', $pc, '/qn', '/norestart') -Wait -PassThru | Out-Null }
                Remove-NetFirewallRule -DisplayName "RackStack WAC HTTPS $capPort" -ErrorAction SilentlyContinue
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): install Windows Admin Center." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued WAC install (port $capPort)"
        return
    }

    $code = Invoke-WACInstaller -Msi $msiPath -Port $port -CertOption $certOption -Thumbprint $thumb
    if ($downloaded -and (Test-Path -LiteralPath $msiPath)) { Remove-Item -LiteralPath $msiPath -Force -ErrorAction SilentlyContinue }
    if ($code -notin @(0, 3010, 1641)) {
        Write-OutputColor "  WAC installation failed (exit $code)." -color "Error"; return
    }

    # Post-install verification.
    $ok = $false
    for ($w = 0; $w -lt 6; $w++) { if (Test-WACInstalled) { $ok = $true; break }; Start-Sleep -Seconds 5 }
    if (-not $ok) {
        Write-OutputColor "  Installer finished but the gateway service was not detected." -color "Warning"
    }
    else {
        Write-OutputColor "  Windows Admin Center installed (port $port)." -color "Success"
    }
    if ($code -in @(3010, 1641)) {
        $script:RebootNeeded = $true
        Write-OutputColor "  A restart is required to complete installation." -color "Warning"
    }
    Enable-WACFirewallRule -Port $port
    Add-SessionChange -Category "Roles" -Description "Installed Windows Admin Center (port $port)"
    Add-UndoAction -Category "Roles" -Description "Installed Windows Admin Center" -UndoScript {
        $pc = Get-WACProductCode
        if ($pc) { Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/x', $pc, '/qn', '/norestart') -Wait -PassThru | Out-Null }
    }
    Clear-MenuCache
}

# Interactive: uninstall the WAC gateway.
function Uninstall-WAC {
    Clear-Host
    Write-CenteredOutput "Uninstall Windows Admin Center" -color "Info"
    if (-not (Test-WACInstalled)) {
        Write-OutputColor "  Windows Admin Center is not installed." -color "Info"; return
    }
    $pc = Get-WACProductCode
    if (-not $pc) {
        Write-OutputColor "  Could not resolve the WAC product code — remove it from Programs & Features." -color "Error"; return
    }
    if (-not (Confirm-UserAction -Message "Uninstall Windows Admin Center?")) {
        Write-OutputColor "  Cancelled." -color "Info"; return
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        $capPc = $pc
        Push-DryRunStep -Label "Uninstall Windows Admin Center" -Category "Roles" -OneWay $false `
            -Params @{ ProductCode = $capPc } `
            -Preflight { if (Test-WACInstalled) { $true } else { "WAC not installed" } }.GetNewClosure() `
            -Apply { Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/x', $capPc, '/qn', '/norestart') -Wait -PassThru | Out-Null }.GetNewClosure() `
            -Undo { Write-OutputColor "  (WAC re-install is not automatic — re-run Install Windows Admin Center.)" -color "Info" }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): uninstall Windows Admin Center." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued WAC uninstall"
        return
    }

    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/x', $pc, '/qn', '/norestart') -Wait -PassThru
    if ($proc.ExitCode -in @(0, 3010, 1641)) {
        Write-OutputColor "  Windows Admin Center uninstalled." -color "Success"
        if ($proc.ExitCode -in @(3010, 1641)) { $script:RebootNeeded = $true }
        Add-SessionChange -Category "Roles" -Description "Uninstalled Windows Admin Center"
        Clear-MenuCache
    }
    else {
        Write-OutputColor "  Uninstall failed (exit $($proc.ExitCode))." -color "Error"
    }
}

# Show the current WAC configuration (read-only).
function Show-WACConfig {
    Clear-Host
    Write-CenteredOutput "Windows Admin Center Status" -color "Info"
    $s = Get-WACStatus
    Write-OutputColor "  Installed       : $($s.Installed)" -color "Info"
    if ($s.Installed) {
        Write-OutputColor "  Service status  : $($s.ServiceStatus)" -color "Info"
        Write-OutputColor "  Gateway port    : $(if ($s.Port) { $s.Port } else { 'unknown' })" -color "Info"
        Write-OutputColor "  Port listening  : $($s.PortListening)" -color "Info"
        if ($s.Port) { Write-OutputColor "  URL             : https://$($env:COMPUTERNAME):$($s.Port)" -color "Info" }
    }
}

# CLI: WACStatus — read-only readiness (JSON-aware).
function Start-WACStatus {
    $s = Get-WACStatus
    if ($script:CLIOutputFormat -eq 'JSON') {
        Write-Output (@{
            Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'WACStatus'
            Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
            Installed = $s.Installed; ServiceStatus = $s.ServiceStatus; Port = $s.Port; PortListening = $s.PortListening
        } | ConvertTo-Json)
    }
    else {
        Show-WACConfig
    }
    return $true
}

# CLI: WACSetup — JSON status for automation; interactive menu on console.
function Start-WACSetup {
    if ($script:CLIOutputFormat -eq 'JSON') { return (Start-WACStatus) }
    Show-WindowsAdminCenterManagement
    return $true
}

# Windows Admin Center submenu (Roles & Features > [13]).
function Show-WindowsAdminCenterManagement {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                       WINDOWS ADMIN CENTER (WAC)").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        $s = Get-WACStatus
        $statusText = if (-not $s.Installed) { "Not Installed" } elseif ($s.ServiceStatus -eq 'Running') { "Running" } else { "Installed (stopped)" }
        $statusColor = if ($s.ServiceStatus -eq 'Running') { "Success" } else { "Warning" }

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-MenuItem "  Gateway" -Status $statusText -StatusColor $statusColor
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  Install Windows Admin Center" -Status "Verified MSI + port + certificate" -StatusColor "Info"
        Write-MenuItem "[2]  Show Status" -Status "Service, port, URL" -StatusColor "Info"
        Write-MenuItem "[3]  Uninstall" -Status "Reversible removal" -StatusColor "Info"
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
            "1" { Install-WAC; Write-PressEnter }
            "2" { Show-WACConfig; Write-PressEnter }
            "3" { Uninstall-WAC; Write-PressEnter }
            "B" { return }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-3 or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}
#endregion
