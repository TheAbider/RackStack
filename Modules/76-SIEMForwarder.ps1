#region ===== SIEM LOG FORWARDER =====
# Ship Windows logs to a SIEM. This completes the security-operations arc
# (NPS auth -> Always-On VPN gateway -> CIS compliance scan -> log shipping).
# It covers the parts that script cleanly and safely:
#   * Windows Event Forwarding (WEF) source-initiated forwarding — the built-in,
#     vendor-neutral, zero-supply-chain path: point this server at a WEC
#     collector (no agent, no token; WEF uses machine/Kerberos auth).
#   * Splunk Universal Forwarder — write outputs.conf / inputs.conf for an
#     ALREADY-INSTALLED forwarder. RackStack never downloads or installs Splunk.
#   * Elastic Winlogbeat — write winlogbeat.yml for an ALREADY-INSTALLED beat.
#   * Microsoft Sentinel — READ-ONLY readiness check (is this host Azure Arc-
#     connected?) plus the exact operator commands to deploy the Azure Monitor
#     Agent extension + a Data Collection Rule. No Az/az calls are made here.
#
# Supply chain: this module installs NO third-party binaries. For Splunk/Elastic
# it only writes config for an agent the operator already installed. Secrets
# (Splunk HEC token, Winlogbeat API key) are collected as SecureString, held
# only in the Apply closure, converted to plaintext just long enough to write
# the config file, then zeroed — never in the Dry-Run queue, its JSON export,
# or any log. A config file that embeds a token is written under the hardened
# Admins/SYSTEM-only state dir first, then placed, and flagged sensitive.

# Convert a SecureString to plaintext for the brief config write, then free it.
function ConvertFrom-SIEMSecure {
    param([Parameter(Mandatory = $true)][System.Security.SecureString]$Secure)
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

# WEF SubscriptionManager Group Policy registry key (source-initiated).
$script:WEFSubMgrPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\EventForwarding\SubscriptionManager'

# Reject an operator-supplied path that tries to traverse out / is malformed.
# Returns $true if the path is a safe, rooted, existing directory.
function Test-SIEMSafeDir {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($Path -match '\.\.' -or $Path.Contains([char]0) -or $Path.Length -gt 255) { return $false }
    if (-not [System.IO.Path]::IsPathRooted($Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    # Reject reparse points (symlink/junction): a pre-staged link at the agent
    # config dir could redirect a token-bearing write to an attacker location.
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $false }
    }
    catch { return $false }
    return $true
}

# Hardened directory for token-bearing config staging + backups of replaced
# config (Admins/SYSTEM-only DACL via Get-RackStackSecureStateDir).
function Get-SIEMSecureDir {
    $secure = Get-RackStackSecureStateDir
    if ([string]::IsNullOrWhiteSpace($secure)) {
        Write-OutputColor "  Warning: could not use the protected state directory; SIEM config" -color "Warning"
        Write-OutputColor "  backups will go to a non-hardened path — they may embed a token, treat" -color "Warning"
        Write-OutputColor "  as sensitive and restrict the ACL." -color "Warning"
        $secure = $script:TempPath
    }
    $dir = Join-Path $secure "SIEMConfig"
    if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -LiteralPath $dir -ItemType Directory -Force -ErrorAction SilentlyContinue }
    return $dir
}

# --- Read-only status probes -------------------------------------------------

# Is WEF source forwarding configured (SubscriptionManager value present)?
function Test-WEFConfigured {
    try {
        if (-not (Test-Path -LiteralPath $script:WEFSubMgrPath)) { return $false }
        $vals = Get-ItemProperty -LiteralPath $script:WEFSubMgrPath -ErrorAction Stop
        foreach ($p in $vals.PSObject.Properties) {
            if ($p.Name -notmatch '^PS' -and "$($p.Value)" -match 'Server=') { return $true }
        }
    }
    catch { }
    return $false
}

# Is the WinRM service running (required for WEF source-initiated pull)?
function Test-WinRMReady {
    $svc = Get-Service -Name WinRM -ErrorAction SilentlyContinue
    return ($null -ne $svc -and $svc.Status -eq 'Running')
}

# Detect an already-installed Splunk Universal Forwarder; resolve SPLUNK_HOME.
function Test-SplunkForwarderInstalled {
    param([string]$SplunkHome)
    $splunkHome = $SplunkHome
    if ([string]::IsNullOrWhiteSpace($splunkHome)) {
        $svc = Get-CimInstance Win32_Service -Filter "Name='SplunkForwarder'" -ErrorAction SilentlyContinue
        if ($svc -and $svc.PathName) {
            # PathName may be quoted ("C:\...\bin\splunkd.exe" args) or unquoted
            # (C:\...\bin\splunkd.exe args) — handle both, taking the path up to .exe.
            $pn = $svc.PathName.Trim()
            if ($pn.StartsWith('"')) { $exe = ($pn -replace '^"([^"]+)".*$', '$1') }
            else { $exe = ($pn -replace '^(.*?\.exe).*$', '$1') }
            try { $splunkHome = (Split-Path (Split-Path $exe -Parent) -Parent) } catch { }
        }
    }
    $configDir = if ($splunkHome) { Join-Path $splunkHome 'etc\system\local' } else { $null }
    return [PSCustomObject]@{
        Installed = ($null -ne (Get-Service -Name 'SplunkForwarder' -ErrorAction SilentlyContinue))
        SplunkHome = $splunkHome
        ConfigDir = $configDir
    }
}

# Detect an already-installed Elastic Winlogbeat; resolve its config dir.
function Test-WinlogbeatInstalled {
    param([string]$ConfigDir)
    $dir = $ConfigDir
    if ([string]::IsNullOrWhiteSpace($dir)) {
        $svc = Get-CimInstance Win32_Service -Filter "Name='winlogbeat'" -ErrorAction SilentlyContinue
        if ($svc -and $svc.PathName) {
            $exe = ($svc.PathName -replace '^"?([^"]+\.exe).*$', '$1')
            try { $dir = (Split-Path $exe -Parent) } catch { }
        }
    }
    return [PSCustomObject]@{
        Installed = ($null -ne (Get-Service -Name 'winlogbeat' -ErrorAction SilentlyContinue))
        ConfigDir = $dir
    }
}

# Sentinel readiness: is this host Azure Arc-connected (AMA prerequisite)?
function Test-SIEMArcReady {
    if (-not (Get-Command -Name Get-AzureArcStatus -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{ Connected = $false; ResourceName = ''; ResourceGroup = '' }
    }
    try {
        $arc = Get-AzureArcStatus
        return [PSCustomObject]@{
            Connected = [bool]$arc.Connected
            ResourceName = "$($arc.ResourceName)"
            ResourceGroup = "$($arc.ResourceGroup)"
        }
    }
    catch { return [PSCustomObject]@{ Connected = $false; ResourceName = ''; ResourceGroup = '' } }
}

# Composite status for the menu / CLI.
function Get-SIEMForwarderStatus {
    return [PSCustomObject]@{
        WEFConfigured = (Test-WEFConfigured)
        WinRMReady    = (Test-WinRMReady)
        SplunkInstalled = (Test-SplunkForwarderInstalled).Installed
        WinlogbeatInstalled = (Test-WinlogbeatInstalled).Installed
        ArcConnected  = (Test-SIEMArcReady).Connected
    }
}

# --- WEF source-initiated forwarding ----------------------------------------

# Ensure the WinRM service is Automatic + Running (the only source-side
# requirement for WEF source-initiated pull). Reversible.
function Enable-WEFSourceForwarding {
    Clear-Host
    Write-CenteredOutput "Enable WEF (WinRM service)" -color "Info"
    if (Test-WinRMReady) {
        Write-OutputColor "  WinRM is already running — the source side is ready for WEF." -color "Info"
        return $true
    }
    if (-not (Confirm-UserAction -Message "Set WinRM to Automatic and start it (required for WEF forwarding)?")) {
        Write-OutputColor "  Cancelled." -color "Info"; return $false
    }
    $svc = Get-Service -Name WinRM -ErrorAction SilentlyContinue
    $priorStart = if ($svc) { "$($svc.StartType)" } else { "Manual" }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        $capPrior = $priorStart
        Push-DryRunStep -Label "Enable WinRM for WEF (Automatic + Start)" -Category "Security" -OneWay $false `
            -Params @{ Service = "WinRM"; PriorStartType = $capPrior } `
            -Preflight { $true } `
            -Apply {
                Set-Service -Name WinRM -StartupType Automatic -ErrorAction SilentlyContinue
                Start-Service -Name WinRM -ErrorAction SilentlyContinue
            }.GetNewClosure() `
            -Undo {
                Set-Service -Name WinRM -StartupType $capPrior -ErrorAction SilentlyContinue
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): enable WinRM for WEF." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued WinRM enable for WEF"
        return $true
    }

    try {
        Set-Service -Name WinRM -StartupType Automatic -ErrorAction Stop
        Start-Service -Name WinRM -ErrorAction Stop
        Write-OutputColor "  WinRM is Automatic and running." -color "Success"
        Add-SessionChange -Category "Security" -Description "Enabled WinRM for WEF forwarding"
        Add-UndoAction -Category "Security" -Description "Enabled WinRM for WEF" -UndoScript {
            param($PriorStart)
            Set-Service -Name WinRM -StartupType $PriorStart -ErrorAction SilentlyContinue
        } -UndoParams @{ PriorStart = $priorStart }
        Clear-MenuCache
        return $true
    }
    catch {
        Write-OutputColor "  Failed to enable WinRM: $($_.Exception.Message)" -color "Error"
        return $false
    }
}

# Point this server at a WEF collector (write the SubscriptionManager value).
function Set-WEFCollector {
    Clear-Host
    Write-CenteredOutput "Set WEF Collector" -color "Info"
    Write-OutputColor "  Collector WS-Man URL (e.g. http://wec.corp.local:5985/wsman/SubscriptionManager/WEC):" -color "Info"
    $url = (Read-Host).Trim()
    $navResult = Test-NavigationCommand -UserInput $url
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($url)) { Write-OutputColor "  URL cannot be empty." -color "Error"; return }
    $uri = $null
    if (-not [System.Uri]::TryCreate($url, [System.UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http', 'https')) {
        Write-OutputColor "  URL must be an absolute http/https WS-Man address." -color "Error"; return
    }

    Write-OutputColor "  Refresh interval in seconds [default 60]:" -color "Info"
    $refreshIn = (Read-Host).Trim()
    $refresh = 60
    if ($refreshIn -match '^\d+$') { $regexMatches = $matches; $refresh = [int]$refreshIn }
    $value = "Server=$url,Refresh=$refresh"

    if (-not (Confirm-UserAction -Message "Point WEF at '$url' (refresh ${refresh}s)?")) {
        Write-OutputColor "  Cancelled." -color "Info"; return
    }

    # Capture the prior value (under name "1") so Undo can restore exactly.
    $prior = $null
    try { if (Test-Path -LiteralPath $script:WEFSubMgrPath) { $prior = (Get-ItemProperty -LiteralPath $script:WEFSubMgrPath -Name '1' -ErrorAction SilentlyContinue).'1' } } catch { }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        $capValue = $value; $capPrior = $prior
        Push-DryRunStep -Label "Set WEF collector -> '$url'" -Category "Security" -OneWay $false `
            -Params @{ Collector = $url; Refresh = $refresh } `
            -Preflight { $true } `
            -Apply {
                if (-not (Test-Path -LiteralPath $script:WEFSubMgrPath)) { $null = New-Item -Path $script:WEFSubMgrPath -Force -ErrorAction SilentlyContinue }
                Set-ItemProperty -LiteralPath $script:WEFSubMgrPath -Name '1' -Value $capValue -ErrorAction SilentlyContinue
            }.GetNewClosure() `
            -Undo {
                if ($null -ne $capPrior) { Set-ItemProperty -LiteralPath $script:WEFSubMgrPath -Name '1' -Value $capPrior -ErrorAction SilentlyContinue }
                else { Remove-ItemProperty -LiteralPath $script:WEFSubMgrPath -Name '1' -ErrorAction SilentlyContinue }
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): set WEF collector." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued WEF collector -> $url"
        return
    }

    try {
        if (-not (Test-Path -LiteralPath $script:WEFSubMgrPath)) { $null = New-Item -Path $script:WEFSubMgrPath -Force -ErrorAction Stop }
        Set-ItemProperty -LiteralPath $script:WEFSubMgrPath -Name '1' -Value $value -ErrorAction Stop
        Write-OutputColor "  WEF collector set: $url" -color "Success"
        Write-OutputColor "  (WEF source-initiated uses machine/Kerberos auth — no token stored.)" -color "Info"
        Add-SessionChange -Category "Security" -Description "Set WEF collector -> $url"
        Add-UndoAction -Category "Security" -Description "Set WEF collector" -UndoScript {
            param($Path, $Prior)
            if ($null -ne $Prior) { Set-ItemProperty -LiteralPath $Path -Name '1' -Value $Prior -ErrorAction SilentlyContinue }
            else { Remove-ItemProperty -LiteralPath $Path -Name '1' -ErrorAction SilentlyContinue }
        } -UndoParams @{ Path = $script:WEFSubMgrPath; Prior = $prior }
        Clear-MenuCache
    }
    catch {
        Write-OutputColor "  Failed to set WEF collector: $($_.Exception.Message)" -color "Error"
    }
}

# Remove the WEF collector configuration.
function Remove-WEFCollector {
    Clear-Host
    Write-CenteredOutput "Remove WEF Collector" -color "Info"
    if (-not (Test-WEFConfigured)) {
        Write-OutputColor "  No WEF collector is configured." -color "Info"; return
    }
    if (-not (Confirm-UserAction -Message "Remove the WEF SubscriptionManager configuration?")) {
        Write-OutputColor "  Cancelled." -color "Info"; return
    }
    # Capture the prior value so the removal can be rolled back.
    $prior = $null
    try { $prior = (Get-ItemProperty -LiteralPath $script:WEFSubMgrPath -Name '1' -ErrorAction SilentlyContinue).'1' } catch { }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        $capPrior = $prior
        Push-DryRunStep -Label "Remove WEF collector" -Category "Security" -OneWay $false `
            -Params @{ Action = "RemoveWEFCollector" } `
            -Preflight { $true } `
            -Apply { Remove-ItemProperty -LiteralPath $script:WEFSubMgrPath -Name '1' -ErrorAction SilentlyContinue }.GetNewClosure() `
            -Undo { if ($null -ne $capPrior) { Set-ItemProperty -LiteralPath $script:WEFSubMgrPath -Name '1' -Value $capPrior -ErrorAction SilentlyContinue } }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): remove WEF collector." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued WEF collector removal"
        return
    }

    try {
        Remove-ItemProperty -LiteralPath $script:WEFSubMgrPath -Name '1' -ErrorAction SilentlyContinue
        Write-OutputColor "  WEF collector configuration removed." -color "Success"
        Add-SessionChange -Category "Security" -Description "Removed WEF collector"
        Add-UndoAction -Category "Security" -Description "Removed WEF collector" -UndoScript {
            param($Path, $Prior)
            if ($null -ne $Prior) { Set-ItemProperty -LiteralPath $Path -Name '1' -Value $Prior -ErrorAction SilentlyContinue }
        } -UndoParams @{ Path = $script:WEFSubMgrPath; Prior = $prior }
        Clear-MenuCache
    }
    catch {
        Write-OutputColor "  Failed to remove WEF collector: $($_.Exception.Message)" -color "Error"
    }
}

# --- Splunk Universal Forwarder (config-file only) --------------------------

# Atomically write a config file: stage in the hardened dir, back up the prior
# file there, then place at the target. Returns @{ Ok; Backup; Target } so the
# caller can register an Undo that RESTORES the prior file (not just deletes the
# new one). Backup is $null when no prior file existed. The backup lives in the
# Admins/SYSTEM-only state dir, so a restore path carries no secret in undo state.
function Write-SIEMConfigFile {
    param([string]$TargetPath, [string]$Content)
    $secureDir = Get-SIEMSecureDir
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
    $leaf = [System.IO.Path]::GetFileName($TargetPath)
    $backup = $null
    if (Test-Path -LiteralPath $TargetPath) {
        # A prior config exists — it MUST be backed up before we overwrite it, or an Undo can't
        # restore it. The old code copied with -EA SilentlyContinue and still returned the backup
        # path even if the copy failed; Restore-SIEMConfig then saw the (missing) backup, fell
        # through, and DELETED the live config on undo instead of restoring the prior one. Fail
        # closed: if we can't take the backup, don't overwrite the existing config at all.
        $backup = Join-Path $secureDir "$leaf.$stamp.bak"
        try {
            Copy-Item -LiteralPath $TargetPath -Destination $backup -Force -ErrorAction Stop
        }
        catch {
            Write-OutputColor "  Failed to back up existing $leaf; leaving it in place: $($_.Exception.Message)" -color "Error"
            return @{ Ok = $false; Backup = $null; Target = $TargetPath }
        }
        Write-OutputColor "  Backed up existing $leaf to: $backup" -color "Info"
    }
    $stage = Join-Path $secureDir "$leaf.$stamp.stage"
    try {
        Set-Content -LiteralPath $stage -Value $Content -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $stage -Destination $TargetPath -Force -ErrorAction Stop
        return @{ Ok = $true; Backup = $backup; Target = $TargetPath }
    }
    catch {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Force -ErrorAction SilentlyContinue }
        Write-OutputColor "  Failed to write $leaf : $($_.Exception.Message)" -color "Error"
        return @{ Ok = $false; Backup = $backup; Target = $TargetPath }
    }
}

# Restore (or remove) config targets from an Undo restore-list. Each entry is
# @{ Target; Backup }: restore the backup if one exists, else remove the file
# the Apply created (so the prior state is reinstated either way). Paths only —
# no secret material is held in the restore list.
function Restore-SIEMConfig {
    param([array]$Restores)
    foreach ($r in @($Restores)) {
        if (-not $r) { continue }
        if ($r.Backup -and (Test-Path -LiteralPath $r.Backup)) {
            Copy-Item -LiteralPath $r.Backup -Destination $r.Target -Force -ErrorAction SilentlyContinue
        }
        elseif (Test-Path -LiteralPath $r.Target) {
            Remove-Item -LiteralPath $r.Target -Force -ErrorAction SilentlyContinue
        }
    }
}

# Write outputs.conf (HEC) + inputs.conf for an already-installed Splunk UF.
function Set-SplunkForwarderOutputs {
    Clear-Host
    Write-CenteredOutput "Configure Splunk Forwarder" -color "Info"
    $detect = Test-SplunkForwarderInstalled
    if (-not $detect.Installed) {
        Write-OutputColor "  No Splunk Universal Forwarder service detected." -color "Error"
        Write-OutputColor "  Install the forwarder first; RackStack only writes its config." -color "Info"
        return
    }
    $splunkHome = $detect.SplunkHome
    if (-not (Test-SIEMSafeDir $splunkHome)) {
        Write-OutputColor "  SPLUNK_HOME path to the installed forwarder (e.g. C:\Program Files\SplunkUniversalForwarder):" -color "Info"
        $splunkHome = (Read-Host).Trim().Trim('"')
        if (-not (Test-SIEMSafeDir $splunkHome)) { Write-OutputColor "  Path not found or invalid." -color "Error"; return }
    }
    $configDir = Join-Path $splunkHome 'etc\system\local'
    if (-not (Test-Path -LiteralPath $configDir)) { Write-OutputColor "  Config dir not found: $configDir" -color "Error"; return }

    Write-OutputColor "  HTTP Event Collector (HEC) URL (e.g. https://splunk.corp:8088):" -color "Info"
    $hecUrl = (Read-Host).Trim()
    $uri = $null
    if (-not [System.Uri]::TryCreate($hecUrl, [System.UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http', 'https')) {
        Write-OutputColor "  HEC URL must be an absolute http/https address." -color "Error"; return
    }
    Write-OutputColor "  HEC token (input hidden):" -color "Info"
    $secure = Read-Host -AsSecureString
    if ($null -eq $secure -or $secure.Length -eq 0) { Write-OutputColor "  Token cannot be empty." -color "Error"; return }

    if (-not (Confirm-UserAction -Message "Write Splunk outputs.conf + inputs.conf to '$configDir'?")) {
        Write-OutputColor "  Cancelled." -color "Info"; return
    }

    $inputs = "[WinEventLog://Security]`r`ndisabled = 0`r`n`r`n[WinEventLog://System]`r`ndisabled = 0`r`n`r`n[WinEventLog://Application]`r`ndisabled = 0`r`n"
    $outputsPath = Join-Path $configDir 'outputs.conf'
    $inputsPath = Join-Path $configDir 'inputs.conf'

    # Returns @{ Ok; Restores } — Restores is a list of @{Target;Backup} (paths
    # only) so callers can register an Undo that reinstates the prior config.
    $doWrite = {
        param($CapUrl, $CapSecure, $CapOutputsPath, $CapInputsPath, $CapInputs)
        $plain = ConvertFrom-SIEMSecure -Secure $CapSecure
        $outputs = "[httpout]`r`nhttpEventCollectorToken = $plain`r`nuri = $CapUrl`r`n"
        $plain = $null
        $r1 = Write-SIEMConfigFile -TargetPath $CapOutputsPath -Content $outputs
        $outputs = $null
        $r2 = Write-SIEMConfigFile -TargetPath $CapInputsPath -Content $CapInputs
        return @{ Ok = ($r1.Ok -and $r2.Ok); Restores = @(@{ Target = $r1.Target; Backup = $r1.Backup }, @{ Target = $r2.Target; Backup = $r2.Backup }) }
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        $capUrl = $hecUrl; $capSecure = $secure; $capOut = $outputsPath; $capIn = $inputsPath; $capInputs = $inputs; $capWrite = $doWrite
        $capUndo = @{ Restores = @() }
        Push-DryRunStep -Label "Write Splunk forwarder config (HEC $capUrl)" -Category "Security" -OneWay $false `
            -Params @{ HECUrl = $capUrl; ConfigDir = $configDir } `
            -Preflight { $true } `
            -Apply {
                $res = & $capWrite $capUrl $capSecure $capOut $capIn $capInputs
                $capUndo.Restores = $res.Restores
            }.GetNewClosure() `
            -Undo {
                # Reinstate the prior config (restore each backup, or remove the
                # file we created if there was no prior) — never leave a worse state.
                Restore-SIEMConfig -Restores $capUndo.Restores
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): write Splunk forwarder config." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued Splunk forwarder config"
        return
    }

    $result = & $doWrite $hecUrl $secure $outputsPath $inputsPath $inputs
    $secure = $null
    if ($result.Ok) {
        Write-OutputColor "  Splunk forwarder config written to: $configDir" -color "Success"
        Write-OutputColor "  NOTE: outputs.conf embeds the HEC token in clear text — the file is" -color "Warning"
        Write-OutputColor "  protected by the config dir's ACL; restart the forwarder to apply." -color "Warning"
        Add-SessionChange -Category "Security" -Description "Wrote Splunk forwarder config (HEC $hecUrl)"
        Add-UndoAction -Category "Security" -Description "Wrote Splunk forwarder config" -UndoScript {
            param($Restores)
            Restore-SIEMConfig -Restores $Restores
        } -UndoParams @{ Restores = $result.Restores }
        Clear-MenuCache
    }
}

# --- Elastic Winlogbeat (config-file only) ----------------------------------

function Set-WinlogbeatConfig {
    Clear-Host
    Write-CenteredOutput "Configure Winlogbeat" -color "Info"
    $detect = Test-WinlogbeatInstalled
    if (-not $detect.Installed) {
        Write-OutputColor "  No Winlogbeat service detected." -color "Error"
        Write-OutputColor "  Install Winlogbeat first; RackStack only writes its config." -color "Info"
        return
    }
    $dir = $detect.ConfigDir
    if (-not (Test-SIEMSafeDir $dir)) {
        Write-OutputColor "  Winlogbeat config directory (where winlogbeat.yml lives):" -color "Info"
        $dir = (Read-Host).Trim().Trim('"')
        if (-not (Test-SIEMSafeDir $dir)) { Write-OutputColor "  Path not found or invalid." -color "Error"; return }
    }

    Write-OutputColor "  Elasticsearch host:port (e.g. https://elastic.corp:9200):" -color "Info"
    $esHost = (Read-Host).Trim()
    if ([string]::IsNullOrWhiteSpace($esHost)) { Write-OutputColor "  Host cannot be empty." -color "Error"; return }
    Write-OutputColor "  Elasticsearch API key (id:key, input hidden):" -color "Info"
    $secure = Read-Host -AsSecureString
    if ($null -eq $secure -or $secure.Length -eq 0) { Write-OutputColor "  API key cannot be empty." -color "Error"; return }

    if (-not (Confirm-UserAction -Message "Write winlogbeat.yml to '$dir'?")) {
        Write-OutputColor "  Cancelled." -color "Info"; return
    }

    $ymlPath = Join-Path $dir 'winlogbeat.yml'
    $doWrite = {
        param($CapHost, $CapSecure, $CapYmlPath)
        $plain = ConvertFrom-SIEMSecure -Secure $CapSecure
        $yml = "winlogbeat.event_logs:`r`n  - name: Security`r`n  - name: System`r`n  - name: Application`r`n`r`noutput.elasticsearch:`r`n  hosts: [`"$CapHost`"]`r`n  api_key: `"$plain`"`r`n"
        $plain = $null
        $r = Write-SIEMConfigFile -TargetPath $CapYmlPath -Content $yml
        $yml = $null
        return @{ Ok = $r.Ok; Restores = @(@{ Target = $r.Target; Backup = $r.Backup }) }
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        $capHost = $esHost; $capSecure = $secure; $capYml = $ymlPath; $capWrite = $doWrite
        $capUndo = @{ Restores = @() }
        Push-DryRunStep -Label "Write winlogbeat.yml ($capHost)" -Category "Security" -OneWay $false `
            -Params @{ ElasticHost = $capHost; ConfigPath = $capYml } `
            -Preflight { $true } `
            -Apply {
                $res = & $capWrite $capHost $capSecure $capYml
                $capUndo.Restores = $res.Restores
            }.GetNewClosure() `
            -Undo { Restore-SIEMConfig -Restores $capUndo.Restores }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): write winlogbeat.yml." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued winlogbeat.yml"
        return
    }

    $result = & $doWrite $esHost $secure $ymlPath
    $secure = $null
    if ($result.Ok) {
        Write-OutputColor "  winlogbeat.yml written to: $dir" -color "Success"
        Write-OutputColor "  NOTE: the file embeds the API key in clear text — protected by the" -color "Warning"
        Write-OutputColor "  config dir ACL; restart the winlogbeat service to apply." -color "Warning"
        Add-SessionChange -Category "Security" -Description "Wrote winlogbeat.yml ($esHost)"
        Add-UndoAction -Category "Security" -Description "Wrote winlogbeat.yml" -UndoScript {
            param($Restores)
            Restore-SIEMConfig -Restores $Restores
        } -UndoParams @{ Restores = $result.Restores }
        Clear-MenuCache
    }
}

# --- Microsoft Sentinel (read-only pointer) ---------------------------------

function Show-SentinelForwardingGuidance {
    Clear-Host
    Write-CenteredOutput "Sentinel / Azure Monitor Agent" -color "Info"
    $arc = Test-SIEMArcReady
    if (-not $arc.Connected) {
        Write-OutputColor "  This host is NOT Azure Arc-connected. The Azure Monitor Agent (AMA)" -color "Warning"
        Write-OutputColor "  requires Arc on non-Azure servers — onboard it first via Roles & Features" -color "Info"
        Write-OutputColor "  > Azure Arc (or -Action AzureArcEnroll), then return here." -color "Info"
        return
    }
    Write-OutputColor "  Arc-connected as: $($arc.ResourceName) (RG: $($arc.ResourceGroup))" -color "Success"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Deploy the Azure Monitor Agent + associate a Data Collection Rule from a" -color "Info"
    Write-OutputColor "  machine with the Az module / az CLI (not run here):" -color "Info"
    Write-OutputColor "    az connectedmachine extension create --name AzureMonitorWindowsAgent" -color "Debug"
    Write-OutputColor ("      --machine-name {0} --resource-group {1}" -f $arc.ResourceName, $arc.ResourceGroup) -color "Debug"
    Write-OutputColor "      --publisher Microsoft.Azure.Monitor --type AzureMonitorWindowsAgent" -color "Debug"
    Write-OutputColor "    az monitor data-collection rule association create --name <assoc-name>" -color "Debug"
    Write-OutputColor "      --rule-id <DCR_ID> --resource <ARC_MACHINE_RESOURCE_ID>" -color "Debug"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  The DCR routes Windows events to your Sentinel/Log Analytics workspace." -color "Info"
}

# --- CLI entries -------------------------------------------------------------

# CLI: SIEMStatus — read-only readiness (JSON-aware).
function Start-SIEMStatus {
    $s = Get-SIEMForwarderStatus
    if ($script:CLIOutputFormat -eq 'JSON') {
        Write-Output (@{
            Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'SIEMStatus'
            Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
            WEFConfigured = $s.WEFConfigured; WinRMReady = $s.WinRMReady
            SplunkInstalled = $s.SplunkInstalled; WinlogbeatInstalled = $s.WinlogbeatInstalled
            ArcConnected = $s.ArcConnected
        } | ConvertTo-Json)
    }
    else {
        Write-OutputColor "  WEF configured     : $($s.WEFConfigured)" -color "Info"
        Write-OutputColor "  WinRM ready        : $($s.WinRMReady)" -color "Info"
        Write-OutputColor "  Splunk forwarder   : $(if ($s.SplunkInstalled) { 'Installed' } else { 'Not detected' })" -color "Info"
        Write-OutputColor "  Winlogbeat         : $(if ($s.WinlogbeatInstalled) { 'Installed' } else { 'Not detected' })" -color "Info"
        Write-OutputColor "  Azure Arc          : $(if ($s.ArcConnected) { 'Connected' } else { 'Not connected' })" -color "Info"
    }
    return $true
}

# CLI: SIEMSetup — JSON readiness for automation; interactive menu in console.
function Start-SIEMSetup {
    if ($script:CLIOutputFormat -eq 'JSON') {
        return (Start-SIEMStatus)
    }
    Show-SIEMForwarderManagement
    return $true
}

# SIEM Log Forwarder submenu (Roles & Features > [12]).
function Show-SIEMForwarderManagement {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                          SIEM LOG FORWARDER").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        $s = Get-SIEMForwarderStatus
        $wefText = if ($s.WEFConfigured) { "Configured" } else { "Not Configured" }
        $wefColor = if ($s.WEFConfigured) { "Success" } else { "Warning" }

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-MenuItem "  Windows Event Forwarding" -Status $wefText -StatusColor $wefColor
        Write-MenuItem "  WinRM" -Status $(if ($s.WinRMReady) { "Running" } else { "Stopped" }) -StatusColor $(if ($s.WinRMReady) { "Success" } else { "Warning" })
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  Enable WinRM for WEF" -Status "Source-side readiness" -StatusColor "Info"
        Write-MenuItem "[2]  Set WEF Collector" -Status "Point at a WEC collector (no token)" -StatusColor "Info"
        Write-MenuItem "[3]  Remove WEF Collector" -Status "Reversible teardown" -StatusColor "Info"
        Write-MenuItem "[4]  Configure Splunk Forwarder" -Status "Write outputs.conf / inputs.conf" -StatusColor "Info"
        Write-MenuItem "[5]  Configure Winlogbeat" -Status "Write winlogbeat.yml" -StatusColor "Info"
        Write-MenuItem "[6]  Sentinel (AMA) Readiness" -Status "Arc check + deploy guidance" -StatusColor "Info"
        Write-MenuItem "[7]  Show Forwarder Status" -Status "Current readiness" -StatusColor "Info"
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
            "1" { Enable-WEFSourceForwarding; Write-PressEnter }
            "2" { Set-WEFCollector; Write-PressEnter }
            "3" { Remove-WEFCollector; Write-PressEnter }
            "4" { Set-SplunkForwarderOutputs; Write-PressEnter }
            "5" { Set-WinlogbeatConfig; Write-PressEnter }
            "6" { Show-SentinelForwardingGuidance; Write-PressEnter }
            "7" { Start-SIEMStatus | Out-Null; Write-PressEnter }
            "B" { return }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-7 or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}
#endregion
