#region ===== NETWORK POLICY SERVER (NPS / RADIUS) =====
# Install and configure Network Policy Server — Windows' RADIUS server, used
# for 802.1X (wired/wireless NAC), VPN authentication, and as the auth back end
# for Always-On VPN. This module covers the parts that script cleanly:
#   * Install the NPAS (Network Policy and Access Services) role (reversible).
#   * Register RADIUS clients (switches / APs / VPN gateways) via `netsh nps`.
#   * Back up / restore the full NPS configuration via `netsh nps export|import`.
#   * Show the current NPS configuration.
#
# Shared secrets are handled like other credentials in RackStack: collected as
# a SecureString, held only in the Apply closure, and converted to plaintext
# just long enough for the netsh call — never written to the Dry-Run queue or
# its JSON export. (netsh does pass the secret on its own command line for the
# duration of the call; that's a netsh limitation, run in an admin context.)
#
# Connection-request / network-policy authoring is left to the NPS console or a
# restored config backup — those are multi-object policy trees that don't map
# to a safe one-shot prompt.

# Convert a SecureString to plaintext for the brief netsh call, then free it.
function ConvertFrom-NPSSecure {
    param([Parameter(Mandatory = $true)][System.Security.SecureString]$Secure)
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

# Is the NPAS / Network Policy Server role installed?
function Test-NPSRoleInstalled {
    try {
        $f = Get-WindowsFeature -Name NPAS -ErrorAction SilentlyContinue
        if ($null -ne $f -and $f.Installed) { return $true }
    }
    catch { }
    # Fallback: the NPS service (IAS) exists once the role is installed.
    $svc = Get-Service -Name IAS -ErrorAction SilentlyContinue
    return ($null -ne $svc)
}

function Get-NPSStatus {
    return [PSCustomObject]@{ Installed = (Test-NPSRoleInstalled) }
}

# Run a `netsh nps ...` command, returning $true on success (exit 0) and
# surfacing netsh's own output on failure.
function Invoke-NetshNps {
    param([Parameter(Mandatory = $true)][string[]]$NetshArgs)
    $out = & netsh nps @NetshArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-OutputColor "  netsh nps failed: $($out -join ' ')" -color "Error"
        return $false
    }
    return $true
}

# Interactive: install the NPS role.
function Install-NPSRole {
    Clear-Host
    Write-CenteredOutput "Install Network Policy Server" -color "Info"
    if (Test-NPSRoleInstalled) {
        Write-OutputColor "  NPS (NPAS role) is already installed." -color "Info"
        return $true
    }
    if (-not (Confirm-UserAction -Message "Install the Network Policy and Access Services (NPAS) role?")) {
        Write-OutputColor "  Cancelled." -color "Info"; return $false
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        Push-DryRunStep -Label "Install NPS (NPAS) role" -Category "Roles" -OneWay $false `
            -Params @{ Feature = "NPAS" } `
            -Preflight {
                if ((Get-WindowsFeature -Name NPAS -ErrorAction SilentlyContinue).Installed) { "NPAS already installed" }
                else { $true }
            }.GetNewClosure() `
            -Apply {
                # Shared timeout wrapper (runs the install in a job so a hung
                # feature install can't block the commit indefinitely).
                Install-WindowsFeatureWithTimeout -FeatureName 'NPAS' -DisplayName 'Network Policy Server' -IncludeManagementTools | Out-Null
            }.GetNewClosure() `
            -Undo {
                Uninstall-WindowsFeature -Name NPAS -ErrorAction SilentlyContinue | Out-Null
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): install NPS (NPAS) role." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued NPS role install"
        return $true
    }

    $install = Install-WindowsFeatureWithTimeout -FeatureName 'NPAS' -DisplayName 'Network Policy Server' -IncludeManagementTools
    if (-not $install.Success) {
        Write-OutputColor "  Failed to install NPS role." -color "Error"
        if ($install.Error) { Write-OutputColor "  $($install.Error.Trim())" -color "Error" }
        return $false
    }
    Write-OutputColor "  NPS role installed." -color "Success"
    if ($null -ne $install.Result -and $install.Result.RestartNeeded -eq 'Yes') {
        Write-OutputColor "  A restart is required to complete installation." -color "Warning"
    }
    Add-SessionChange -Category "Roles" -Description "Installed NPS (NPAS) role"
    Add-UndoAction -Category "Roles" -Description "Installed NPS (NPAS) role" -UndoScript {
        Uninstall-WindowsFeature -Name NPAS -ErrorAction SilentlyContinue | Out-Null
    }
    Clear-MenuCache
    return $true
}

# Interactive: register a RADIUS client.
function Add-NPSRadiusClient {
    Clear-Host
    Write-CenteredOutput "Add RADIUS Client" -color "Info"
    if (-not (Test-NPSRoleInstalled)) {
        Write-OutputColor "  Install the NPS role first." -color "Error"; return
    }

    Write-OutputColor "  Friendly name for the RADIUS client (e.g. Core-Switch-1):" -color "Info"
    $name = (Read-Host).Trim()
    $navResult = Test-NavigationCommand -UserInput $name
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($name)) { Write-OutputColor "  Name cannot be empty." -color "Error"; return }

    Write-OutputColor "  Client address (IPv4/IPv6/FQDN):" -color "Info"
    $address = (Read-Host).Trim()
    if ([string]::IsNullOrWhiteSpace($address)) { Write-OutputColor "  Address cannot be empty." -color "Error"; return }

    Write-OutputColor "  Shared secret (input hidden):" -color "Info"
    $secure = Read-Host -AsSecureString
    if ($null -eq $secure -or $secure.Length -eq 0) { Write-OutputColor "  Shared secret cannot be empty." -color "Error"; return }

    if (-not (Confirm-UserAction -Message "Add RADIUS client '$name' ($address)?")) {
        Write-OutputColor "  Cancelled." -color "Info"; return
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        $capName = $name; $capAddress = $address; $capSecure = $secure
        Push-DryRunStep -Label "Add RADIUS client '$capName' ($capAddress)" -Category "Network" -OneWay $false `
            -Params @{ Name = $capName; Address = $capAddress } `
            -Preflight { $true } `
            -Apply {
                # Secret lives only here, converted just for the netsh call.
                $plain = ConvertFrom-NPSSecure -Secure $capSecure
                [void](Invoke-NetshNps -NetshArgs @("add", "client", "name=$capName", "address=$capAddress", "state=enable", "sharedsecret=$plain"))
                $plain = $null
            }.GetNewClosure() `
            -Undo {
                [void](Invoke-NetshNps -NetshArgs @("delete", "client", "name=$capName"))
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): add RADIUS client '$capName'." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued RADIUS client '$capName'"
        return
    }

    $plain = ConvertFrom-NPSSecure -Secure $secure
    $ok = Invoke-NetshNps -NetshArgs @("add", "client", "name=$name", "address=$address", "state=enable", "sharedsecret=$plain")
    $plain = $null
    if ($ok) {
        Write-OutputColor "  RADIUS client '$name' added." -color "Success"
        Add-SessionChange -Category "Network" -Description "Added RADIUS client '$name' ($address)"
        Add-UndoAction -Category "Network" -Description "Added RADIUS client '$name'" -UndoScript {
            param($ClientName)
            [void](Invoke-NetshNps -NetshArgs @("delete", "client", "name=$ClientName"))
        } -UndoParams @{ ClientName = $name }
        Clear-MenuCache
    }
}

# Show the current NPS configuration (verbose dump from netsh).
function Show-NPSConfig {
    Clear-Host
    Write-CenteredOutput "NPS Configuration" -color "Info"
    if (-not (Test-NPSRoleInstalled)) {
        Write-OutputColor "  Install the NPS role first." -color "Error"; return
    }
    Write-OutputColor "" -color "Info"
    $out = & netsh nps show config 2>&1
    foreach ($line in $out) { Write-OutputColor "  $line" -color "Info" }
}

# Resolve an admin-only directory for NPS config backups. NPS exports can
# contain RADIUS shared secrets in clear text (exportPSK=YES), so the backup
# dir MUST be locked to Administrators + SYSTEM. We nest it under the shared
# hardened state dir (Get-RackStackSecureStateDir applies SetAccessRuleProtection
# + Admins/SYSTEM-only ACEs that the child inherits), rather than a bare
# %ProgramData% path which inherits BUILTIN\Users:Read.
function Get-NPSBackupDir {
    $secure = Get-RackStackSecureStateDir
    if ([string]::IsNullOrWhiteSpace($secure)) {
        # Hardened state dir unavailable — fall back to a temp dir but warn the
        # operator that the backup is NOT admin-locked.
        Write-OutputColor "  Warning: could not use the protected state directory; NPS backups will" -color "Warning"
        Write-OutputColor "  go to a non-hardened path — treat any PSK-included export as sensitive." -color "Warning"
        $secure = $script:TempPath
    }
    $dir = Join-Path $secure "NPSBackups"
    if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -LiteralPath $dir -ItemType Directory -Force -ErrorAction SilentlyContinue }
    return $dir
}

# Interactive: export the NPS configuration to an XML backup.
function Export-NPSConfig {
    Clear-Host
    Write-CenteredOutput "Export NPS Configuration" -color "Info"
    if (-not (Test-NPSRoleInstalled)) {
        Write-OutputColor "  Install the NPS role first." -color "Error"; return
    }
    $dir = Get-NPSBackupDir
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $file = Join-Path $dir "nps-config-$stamp.xml"

    Write-OutputColor "  Include shared secrets in the export? (the file would then contain" -color "Warning"
    Write-OutputColor "  RADIUS client secrets in clear text — keep it protected)." -color "Warning"
    $pskAnswer = Read-Host "  Include secrets? [y/N]"
    $exportPsk = if ("$pskAnswer".Trim().ToUpper() -eq "Y") { "YES" } else { "NO" }

    if (Invoke-NetshNps -NetshArgs @("export", "filename=$file", "exportPSK=$exportPsk")) {
        Write-OutputColor "  Exported NPS config to:" -color "Success"
        Write-OutputColor "    $file  (secrets included: $exportPsk)" -color "Info"
        Add-SessionChange -Category "Network" -Description "Exported NPS config (PSK=$exportPsk)"
    }
}

# Interactive: import an NPS configuration from an XML backup (overwrites).
function Import-NPSConfig {
    Clear-Host
    Write-CenteredOutput "Import NPS Configuration" -color "Info"
    if (-not (Test-NPSRoleInstalled)) {
        Write-OutputColor "  Install the NPS role first." -color "Error"; return
    }
    Write-OutputColor "  Path to an NPS config XML (from a prior export):" -color "Info"
    $file = (Read-Host).Trim().Trim('"')
    $navResult = Test-NavigationCommand -UserInput $file
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($file) -or -not (Test-Path -LiteralPath $file)) {
        Write-OutputColor "  File not found." -color "Error"; return
    }

    Write-OutputColor "" -color "Warning"
    Write-OutputColor "  Importing OVERWRITES the current NPS configuration (clients + policies)." -color "Warning"
    if (-not (Confirm-UserAction -Message "Import NPS config from this file?")) {
        Write-OutputColor "  Cancelled." -color "Info"; return
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        $capFile = $file
        # Snapshot the current config first so the import can be rolled back.
        $capPre = Join-Path (Get-NPSBackupDir) "nps-preimport-$(Get-Date -Format 'yyyyMMdd-HHmmss').xml"
        Push-DryRunStep -Label "Import NPS config from '$([System.IO.Path]::GetFileName($capFile))'" -Category "Network" -OneWay $false `
            -Params @{ File = $capFile } `
            -Preflight {
                if (Test-Path -LiteralPath $capFile) { $true } else { "Import file '$capFile' not found" }
            }.GetNewClosure() `
            -Apply {
                [void](Invoke-NetshNps -NetshArgs @("export", "filename=$capPre", "exportPSK=YES"))
                [void](Invoke-NetshNps -NetshArgs @("import", "filename=$capFile"))
            }.GetNewClosure() `
            -Undo {
                if (Test-Path -LiteralPath $capPre) { [void](Invoke-NetshNps -NetshArgs @("import", "filename=$capPre")) }
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): import NPS config." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued NPS config import"
        return
    }

    # Capture the current config so the operator can roll back.
    $preFile = Join-Path (Get-NPSBackupDir) "nps-preimport-$(Get-Date -Format 'yyyyMMdd-HHmmss').xml"
    [void](Invoke-NetshNps -NetshArgs @("export", "filename=$preFile", "exportPSK=YES"))
    if (Invoke-NetshNps -NetshArgs @("import", "filename=$file")) {
        Write-OutputColor "  NPS configuration imported." -color "Success"
        Write-OutputColor "  Pre-import backup: $preFile" -color "Info"
        Add-SessionChange -Category "Network" -Description "Imported NPS config from $file"
        Add-UndoAction -Category "Network" -Description "Imported NPS config" -UndoScript {
            param($PrePath)
            if (Test-Path -LiteralPath $PrePath) { [void](& netsh nps import filename="$PrePath" 2>&1) }
        } -UndoParams @{ PrePath = $preFile }
        Clear-MenuCache
    }
}

# CLI entry: NPSSetup — install the NPS role (JSON-aware).
function Start-NPSSetup {
    if (Test-NPSRoleInstalled) {
        if ($script:CLIOutputFormat -eq 'JSON') { Write-Output (@{ Action = 'NPSSetup'; Installed = $true; Changed = $false } | ConvertTo-Json) }
        else { Write-OutputColor "  NPS (NPAS) role already installed." -color "Info" }
        return $true
    }
    $install = Install-WindowsFeatureWithTimeout -FeatureName 'NPAS' -DisplayName 'Network Policy Server' -IncludeManagementTools
    $ok = [bool]$install.Success
    if ($script:CLIOutputFormat -eq 'JSON') {
        $restart = if ($null -ne $install.Result) { "$($install.Result.RestartNeeded)" } else { "" }
        Write-Output (@{
            Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'NPSSetup'
            Hostname = $env:COMPUTERNAME; Success = $ok; RestartNeeded = $restart
        } | ConvertTo-Json)
    }
    else {
        Write-OutputColor "  NPS role install: $(if ($ok) { 'OK' } else { 'FAILED' })" -color $(if ($ok) { "Success" } else { "Error" })
        if (-not $ok -and $install.Error) { Write-OutputColor "  $($install.Error.Trim())" -color "Error" }
    }
    return $ok
}

# Network Policy Server submenu (Roles & Features > [10]).
function Show-NPSManagement {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                  NETWORK POLICY SERVER (NPS / RADIUS)").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        $installed = Test-NPSRoleInstalled
        $statusText = if ($installed) { "Installed" } else { "Not Installed" }
        $statusColor = if ($installed) { "Success" } else { "Warning" }

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-MenuItem "  NPS role" -Status $statusText -StatusColor $statusColor
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  Install NPS Role" -Status "Network Policy and Access Services" -StatusColor "Info"
        Write-MenuItem "[2]  Add RADIUS Client" -Status "Register a switch / AP / VPN gateway" -StatusColor "Info"
        Write-MenuItem "[3]  Show NPS Configuration" -Status "Current clients + policies" -StatusColor "Info"
        Write-MenuItem "[4]  Export Configuration" -Status "Back up NPS config to XML" -StatusColor "Info"
        Write-MenuItem "[5]  Import Configuration" -Status "Restore from an XML backup" -StatusColor "Info"
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
            "1" { Install-NPSRole; Write-PressEnter }
            "2" { Add-NPSRadiusClient; Write-PressEnter }
            "3" { Show-NPSConfig; Write-PressEnter }
            "4" { Export-NPSConfig; Write-PressEnter }
            "5" { Import-NPSConfig; Write-PressEnter }
            "B" { return }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-5 or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}
#endregion
