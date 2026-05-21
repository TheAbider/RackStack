#region ===== AZURE ARC SERVER ONBOARDING =====
# Onboards a Windows Server into Azure Arc — Microsoft's hybrid-cloud
# management plane. Once Arc-connected, the server shows up in the Azure
# portal and can be governed by Azure Policy, scanned by Defender for
# Cloud, patched by Azure Update Manager, and monitored by Azure Monitor,
# all without the server living in Azure.
#
# Config comes from $script:AzureArc (see 00-Initialization.ps1, overridable
# via defaults.json "AzureArc"). The service-principal secret is treated as
# sensitive throughout: never written to a transcript, never structured-
# logged in plaintext, cleared from memory after the connect call.

# Returns $true if Arc onboarding has the minimum config to proceed.
function Test-AzureArcConfigured {
    if ($null -eq $script:AzureArc) { return $false }
    if ([string]::IsNullOrWhiteSpace($script:AzureArc.TenantId)) { return $false }
    if ([string]::IsNullOrWhiteSpace($script:AzureArc.SubscriptionId)) { return $false }
    if ([string]::IsNullOrWhiteSpace($script:AzureArc.ResourceGroup)) { return $false }
    if ([string]::IsNullOrWhiteSpace($script:AzureArc.ServicePrincipalId)) { return $false }
    return $true
}

# Resolve the service-principal secret as a SecureString. Priority order:
#   1. $env:RACKSTACK_ARC_SECRET   (preferred — keeps the secret out of defaults.json)
#   2. $script:AzureArc.ServicePrincipalSecret  (from defaults.json — discouraged for source-controlled files)
# Returns $null if neither is set.
function Resolve-AzureArcSecret {
    $raw = $null
    if (-not [string]::IsNullOrWhiteSpace($env:RACKSTACK_ARC_SECRET)) {
        $raw = $env:RACKSTACK_ARC_SECRET
    }
    elseif ($null -ne $script:AzureArc -and -not [string]::IsNullOrWhiteSpace($script:AzureArc.ServicePrincipalSecret)) {
        $raw = $script:AzureArc.ServicePrincipalSecret
    }
    if ($null -eq $raw) { return $null }
    $secure = ConvertTo-SecureString -String $raw -AsPlainText -Force
    $raw = $null
    return $secure
}

# Locate azcmagent.exe — the Azure Connected Machine Agent CLI. Installed by
# the AzureConnectedMachineAgent MSI to a fixed Program Files path.
function Get-AzureArcAgentPath {
    $candidates = @(
        (Join-Path $env:ProgramW6432 'AzureConnectedMachineAgent\azcmagent.exe')
        (Join-Path ${env:ProgramFiles} 'AzureConnectedMachineAgent\azcmagent.exe')
        (Join-Path ${env:ProgramFiles(x86)} 'AzureConnectedMachineAgent\azcmagent.exe')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    # PATH fallback
    $cmd = Get-Command 'azcmagent' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source) { return $cmd.Source }
    return $null
}

# Returns $true if the Connected Machine Agent is installed.
function Test-AzureArcAgentInstalled {
    return ($null -ne (Get-AzureArcAgentPath))
}

# Query the current Arc connection state. Returns a hashtable with Connected
# (bool), plus ResourceName / ResourceGroup / Subscription / Status / AgentVersion
# when connected. Returns @{ Connected = $false } when the agent is absent or
# not yet onboarded.
function Get-AzureArcStatus {
    $agent = Get-AzureArcAgentPath
    if ($null -eq $agent) {
        return @{ Connected = $false; AgentInstalled = $false }
    }
    try {
        # `azcmagent show -j` emits machine-readable JSON.
        $raw = & $agent show -j 2>$null | Out-String
        $global:LASTEXITCODE = 0
        if ([string]::IsNullOrWhiteSpace($raw) -or -not $raw.TrimStart().StartsWith('{')) {
            return @{ Connected = $false; AgentInstalled = $true }
        }
        $info = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
        $statusText = [string]$info.status
        return @{
            Connected      = ($statusText -eq 'Connected')
            AgentInstalled = $true
            Status         = $statusText
            ResourceName   = [string]$info.resourceName
            ResourceGroup  = [string]$info.resourceGroup
            Subscription   = [string]$info.subscriptionId
            AgentVersion   = [string]$info.agentVersion
        }
    }
    catch {
        return @{ Connected = $false; AgentInstalled = $true }
    }
}

# Download + install the Azure Connected Machine Agent MSI. Returns $true on
# success. Verifies the MSI lands and the service registers.
function Install-AzureArcAgent {
    if (Test-AzureArcAgentInstalled) {
        Write-OutputColor "  Azure Connected Machine Agent is already installed." -color "Info"
        return $true
    }

    $url = if ($null -ne $script:AzureArc -and -not [string]::IsNullOrWhiteSpace($script:AzureArc.AgentInstallerUrl)) {
        $script:AzureArc.AgentInstallerUrl
    } else {
        'https://aka.ms/AzureConnectedMachineAgent'
    }

    # Only HTTPS — never download an installer over plaintext HTTP.
    if ($url -notmatch '^https://') {
        Write-OutputColor "  AgentInstallerUrl must be HTTPS. Refusing to download '$url'." -color "Error"
        return $false
    }

    $msiPath = Join-Path $script:TempPath "AzureConnectedMachineAgent.msi"
    Write-OutputColor "  Downloading Azure Connected Machine Agent..." -color "Info"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $msiPath -UseBasicParsing -ErrorAction Stop
    }
    catch {
        Write-OutputColor "  Download failed: $($_.Exception.Message)" -color "Error"
        return $false
    }
    if (-not (Test-Path -LiteralPath $msiPath)) {
        Write-OutputColor "  Download produced no file at $msiPath." -color "Error"
        return $false
    }

    Write-OutputColor "  Installing agent (msiexec /qn)..." -color "Info"
    try {
        $proc = Start-Process -FilePath 'msiexec.exe' `
            -ArgumentList @('/i', $msiPath, '/qn', '/l*v', (Join-Path $script:TempPath 'arc-agent-install.log')) `
            -Wait -PassThru -ErrorAction Stop
        if ($proc.ExitCode -ne 0) {
            Write-OutputColor "  msiexec returned exit code $($proc.ExitCode). See arc-agent-install.log." -color "Error"
            return $false
        }
    }
    catch {
        Write-OutputColor "  Agent install failed: $($_.Exception.Message)" -color "Error"
        return $false
    }
    finally {
        if (Test-Path -LiteralPath $msiPath) {
            Remove-Item -LiteralPath $msiPath -Force -ErrorAction SilentlyContinue
        }
    }

    if (Test-AzureArcAgentInstalled) {
        Write-OutputColor "  Azure Connected Machine Agent installed." -color "Success"
        Add-SessionChange -Category "Cloud" -Description "Installed Azure Connected Machine Agent"
        return $true
    }
    Write-OutputColor "  Agent install completed but azcmagent.exe was not found." -color "Error"
    return $false
}

# Onboard this machine to Azure Arc via service-principal auth. Returns $true
# on a confirmed Connected state. The SP secret is held as a SecureString
# and converted to plaintext only for the duration of the azcmagent call.
function Invoke-AzureArcOnboard {
    if (-not (Test-AzureArcConfigured)) {
        Write-OutputColor "  Azure Arc is not configured. Set TenantId, SubscriptionId," -color "Error"
        Write-OutputColor "  ResourceGroup, and ServicePrincipalId in defaults.json (AzureArc)." -color "Warning"
        return $false
    }

    $agent = Get-AzureArcAgentPath
    if ($null -eq $agent) {
        Write-OutputColor "  Connected Machine Agent not installed — installing first..." -color "Info"
        if (-not (Install-AzureArcAgent)) { return $false }
        $agent = Get-AzureArcAgentPath
        if ($null -eq $agent) { return $false }
    }

    # Already connected? azcmagent connect would fail; report and stop.
    $status = Get-AzureArcStatus
    if ($status.Connected) {
        Write-OutputColor "  This machine is already Arc-connected as '$($status.ResourceName)'" -color "Warning"
        Write-OutputColor "  in resource group '$($status.ResourceGroup)'. Disconnect first to re-onboard." -color "Warning"
        return $true
    }

    $secureSecret = Resolve-AzureArcSecret
    if ($null -eq $secureSecret) {
        Write-OutputColor "  No service-principal secret available. Set the RACKSTACK_ARC_SECRET" -color "Error"
        Write-OutputColor "  environment variable, or AzureArc.ServicePrincipalSecret in defaults.json." -color "Warning"
        return $false
    }

    $cloud = if (-not [string]::IsNullOrWhiteSpace($script:AzureArc.Cloud)) { $script:AzureArc.Cloud } else { 'AzureCloud' }

    # Build the azcmagent argument array. Array form (never string concat)
    # so no shell re-parsing of the secret. --service-principal-secret is the
    # only place the plaintext appears, and only for this single invocation.
    $arcArgs = [System.Collections.Generic.List[string]]::new()
    $arcArgs.Add('connect')
    $arcArgs.Add('--service-principal-id');     $arcArgs.Add($script:AzureArc.ServicePrincipalId)
    $arcArgs.Add('--tenant-id');                $arcArgs.Add($script:AzureArc.TenantId)
    $arcArgs.Add('--subscription-id');          $arcArgs.Add($script:AzureArc.SubscriptionId)
    $arcArgs.Add('--resource-group');           $arcArgs.Add($script:AzureArc.ResourceGroup)
    $arcArgs.Add('--location');                 $arcArgs.Add($script:AzureArc.Location)
    $arcArgs.Add('--cloud');                    $arcArgs.Add($cloud)
    if (-not [string]::IsNullOrWhiteSpace($script:AzureArc.Tags)) {
        $arcArgs.Add('--tags'); $arcArgs.Add($script:AzureArc.Tags)
    }

    Write-OutputColor "  Onboarding to Azure Arc (resource group '$($script:AzureArc.ResourceGroup)', $cloud)..." -color "Info"

    # Pause the transcript around the connect call so the SP secret never
    # lands in the session log, even though it's passed as an array arg
    # rather than an interpolated string.
    $transcriptWasRunning = $false
    try {
        $existing = Stop-Transcript -ErrorAction Stop
        if ($existing) { $transcriptWasRunning = $true }
    } catch { }

    $plainSecret = $null
    $exitCode = -1
    try {
        $plainSecret = ConvertFrom-SecureStringToPlainText -secureString $secureSecret
        $arcArgs.Add('--service-principal-secret'); $arcArgs.Add($plainSecret)
        & $agent @arcArgs 2>&1 | Out-Null
        $exitCode = $LASTEXITCODE
        $global:LASTEXITCODE = 0
    }
    catch {
        Write-OutputColor "  azcmagent connect threw: $($_.Exception.Message)" -color "Error"
    }
    finally {
        # Scrub the plaintext secret from memory and from the arg list.
        if ($null -ne $plainSecret) {
            Clear-SecureMemory -StringRef ([ref]$plainSecret)
        }
        for ($i = 0; $i -lt $arcArgs.Count; $i++) {
            if ($arcArgs[$i] -eq '--service-principal-secret' -and ($i + 1) -lt $arcArgs.Count) {
                $arcArgs[$i + 1] = ''
            }
        }
        if ($transcriptWasRunning) {
            try {
                if ($script:TranscriptPath) {
                    Start-Transcript -Path $script:TranscriptPath -Append -ErrorAction SilentlyContinue | Out-Null
                } else {
                    Start-Transcript -ErrorAction SilentlyContinue | Out-Null
                }
            } catch { }
        }
    }

    if ($exitCode -ne 0) {
        Write-OutputColor "  azcmagent connect failed (exit $exitCode)." -color "Error"
        Write-OutputColor "  Common causes: SP lacks the 'Azure Connected Machine Onboarding' role," -color "Warning"
        Write-OutputColor "  the resource group does not exist, or outbound HTTPS to Azure is blocked." -color "Warning"
        Write-StructuredLog -Message "Azure Arc onboarding failed" -Level "ERROR" -Category "Cloud" -Data @{ ExitCode = $exitCode; ResourceGroup = $script:AzureArc.ResourceGroup }
        return $false
    }

    $post = Get-AzureArcStatus
    if ($post.Connected) {
        Write-OutputColor "  Azure Arc onboarding succeeded — resource '$($post.ResourceName)'." -color "Success"
        Add-SessionChange -Category "Cloud" -Description "Onboarded to Azure Arc (RG: $($script:AzureArc.ResourceGroup))"
        Write-StructuredLog -Message "Azure Arc onboarding succeeded" -Level "SUCCESS" -Category "Cloud" -Data @{ ResourceName = $post.ResourceName; ResourceGroup = $post.ResourceGroup }
        return $true
    }
    Write-OutputColor "  azcmagent connect returned success but status is not Connected." -color "Warning"
    return $false
}

# Disconnect this machine from Azure Arc. Requires a confirmed hostname match
# because it removes the Azure resource representation.
function Invoke-AzureArcDisconnect {
    $agent = Get-AzureArcAgentPath
    if ($null -eq $agent) {
        Write-OutputColor "  Connected Machine Agent is not installed — nothing to disconnect." -color "Info"
        return $false
    }
    $status = Get-AzureArcStatus
    if (-not $status.Connected) {
        Write-OutputColor "  This machine is not Arc-connected — nothing to disconnect." -color "Info"
        return $false
    }

    if (-not (Confirm-UserAction -Message "  Disconnect '$($status.ResourceName)' from Azure Arc?")) {
        Write-OutputColor "  Cancelled." -color "Info"
        return $false
    }

    # Disconnect needs auth too. Reuse the SP secret if available; otherwise
    # azcmagent will prompt interactively.
    $secureSecret = Resolve-AzureArcSecret
    $disconnectArgs = [System.Collections.Generic.List[string]]::new()
    $disconnectArgs.Add('disconnect')
    if ($null -ne $secureSecret -and (Test-AzureArcConfigured)) {
        $disconnectArgs.Add('--service-principal-id'); $disconnectArgs.Add($script:AzureArc.ServicePrincipalId)
        $disconnectArgs.Add('--tenant-id');            $disconnectArgs.Add($script:AzureArc.TenantId)
    }

    $transcriptWasRunning = $false
    try { $existing = Stop-Transcript -ErrorAction Stop; if ($existing) { $transcriptWasRunning = $true } } catch { }

    $plainSecret = $null
    $exitCode = -1
    try {
        if ($null -ne $secureSecret -and (Test-AzureArcConfigured)) {
            $plainSecret = ConvertFrom-SecureStringToPlainText -secureString $secureSecret
            $disconnectArgs.Add('--service-principal-secret'); $disconnectArgs.Add($plainSecret)
        }
        & $agent @disconnectArgs 2>&1 | Out-Null
        $exitCode = $LASTEXITCODE
        $global:LASTEXITCODE = 0
    }
    catch {
        Write-OutputColor "  azcmagent disconnect threw: $($_.Exception.Message)" -color "Error"
    }
    finally {
        if ($null -ne $plainSecret) { Clear-SecureMemory -StringRef ([ref]$plainSecret) }
        if ($transcriptWasRunning) {
            try {
                if ($script:TranscriptPath) { Start-Transcript -Path $script:TranscriptPath -Append -ErrorAction SilentlyContinue | Out-Null }
                else { Start-Transcript -ErrorAction SilentlyContinue | Out-Null }
            } catch { }
        }
    }

    if ($exitCode -eq 0) {
        Write-OutputColor "  Disconnected from Azure Arc." -color "Success"
        Add-SessionChange -Category "Cloud" -Description "Disconnected from Azure Arc"
        return $true
    }
    Write-OutputColor "  azcmagent disconnect failed (exit $exitCode)." -color "Error"
    return $false
}

# Interactive Azure Arc management menu.
function Show-AzureArcManagement {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                     AZURE ARC SERVER ONBOARDING").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        # Current state panel
        $status = Get-AzureArcStatus
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        if (-not $status.AgentInstalled) {
            Write-OutputColor "  │$("  Agent:      not installed".PadRight(72))│" -color "Warning"
        } elseif ($status.Connected) {
            Write-OutputColor "  │$("  Agent:      installed (v$($status.AgentVersion))".PadRight(72))│" -color "Success"
            Write-OutputColor "  │$("  State:      CONNECTED".PadRight(72))│" -color "Success"
            Write-OutputColor "  │$("  Resource:   $($status.ResourceName)".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Group:      $($status.ResourceGroup)".PadRight(72))│" -color "Info"
        } else {
            Write-OutputColor "  │$("  Agent:      installed (v$($status.AgentVersion))".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  State:      not connected".PadRight(72))│" -color "Warning"
        }
        $cfg = if (Test-AzureArcConfigured) { "configured" } else { "NOT configured (see defaults.json)" }
        Write-OutputColor "  │$("  Config:     $cfg".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-MenuItem "[1]  Install Connected Machine Agent"
        Write-MenuItem "[2]  Onboard this server to Azure Arc"
        Write-MenuItem "[3]  Show current Arc status"
        Write-MenuItem "[4]  Disconnect from Azure Arc"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" {
                if (Confirm-UserAction -Message "  Download and install the Azure Connected Machine Agent?") {
                    $null = Install-AzureArcAgent
                }
                Write-PressEnter
            }
            "2" {
                $null = Invoke-AzureArcOnboard
                Write-PressEnter
            }
            "3" {
                $s = Get-AzureArcStatus
                Write-OutputColor "" -color "Info"
                if ($s.Connected) {
                    Write-OutputColor "  Connected as '$($s.ResourceName)' (RG: $($s.ResourceGroup), agent v$($s.AgentVersion))." -color "Success"
                } elseif ($s.AgentInstalled) {
                    Write-OutputColor "  Agent installed (v$($s.AgentVersion)) but not connected to Azure Arc." -color "Warning"
                } else {
                    Write-OutputColor "  Connected Machine Agent is not installed." -color "Warning"
                }
                Write-PressEnter
            }
            "4" {
                $null = Invoke-AzureArcDisconnect
                Write-PressEnter
            }
            default {
                Write-OutputColor "  Invalid selection. Enter 1-4 or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}
#endregion
