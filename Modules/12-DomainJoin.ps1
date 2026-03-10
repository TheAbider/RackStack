#region ===== DOMAIN JOIN =====
# Function to join a domain
function Join-Domain {
    Clear-Host
    Write-CenteredOutput "Join Domain" -color "Info"

    # Check if agent is installed (required before domain join) — skip if agent not configured
    $agentStatus = Test-AgentInstalled
    if (Test-AgentInstallerConfigured -and -not $agentStatus.Installed) {
        $agentToolName = $script:AgentInstaller.ToolName
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        $agentHeader = "  $($agentToolName.ToUpper()) AGENT NOT INSTALLED"
        if ($agentHeader.Length -gt 72) { $agentHeader = $agentHeader.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($agentHeader.PadRight(72))│" -color "Warning"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        $lineStr = "  $agentToolName Agent should be installed before joining the domain."
        if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  This ensures the server checks in properly after domain join.".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        if (Confirm-UserAction -Message "Install $agentToolName Agent now?") {
            Install-Agent -ReturnAfterInstall

            # Re-check after install
            $agentStatus = Test-AgentInstalled
            if (-not $agentStatus.Installed) {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  $agentToolName Agent still not detected." -color "Warning"
                if (-not (Confirm-UserAction -Message "Continue with domain join anyway?")) {
                    return
                }
            } else {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  $agentToolName Agent installed successfully. Continuing with domain join..." -color "Success"
                Start-Sleep -Seconds 2
            }
        } elseif (-not (Confirm-UserAction -Message "Continue without $agentToolName Agent?")) {
            return
        }
        Clear-Host
        Write-CenteredOutput "Join Domain" -color "Info"
    }

    # Check current domain status
    $csCim = Invoke-WithTimeout -ScriptBlock {
        Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    } -TimeoutSeconds 10 -Activity "Checking domain status"
    $computerSystem = if ($csCim.TimedOut) { $null } else { $csCim.Result }
    if ($null -ne $computerSystem -and $computerSystem.PartOfDomain) {
        Write-OutputColor "  Server is already joined to domain: $($computerSystem.Domain)" -color "Warning"
        if (-not (Confirm-UserAction -Message "Do you want to join a different domain?")) {
            return
        }
    }
    else {
        Write-OutputColor "  Server is currently in WORKGROUP" -color "Info"
    }

    Write-OutputColor "" -color "Info"
    if ([string]::IsNullOrWhiteSpace($domain)) {
        Write-OutputColor "  No default domain configured." -color "Warning"
        Write-OutputColor "  Enter domain name (e.g., corp.local):" -color "Info"
        $targetDomain = Read-Host

        $navResult = Test-NavigationCommand -UserInput $targetDomain
        if ($navResult.ShouldReturn) { return }

        if ([string]::IsNullOrWhiteSpace($targetDomain)) {
            Write-OutputColor "  No domain entered. Cancelled." -color "Warning"
            return
        }
    }
    elseif (Confirm-UserAction -Message "Use default domain ($domain)?" -DefaultYes) {
        $targetDomain = $domain
    }
    else {
        Write-OutputColor "  Enter domain name (e.g., corp.local):" -color "Info"
        $targetDomain = Read-Host

        $navResult = Test-NavigationCommand -UserInput $targetDomain
        if ($navResult.ShouldReturn) { return }

        if ([string]::IsNullOrWhiteSpace($targetDomain)) {
            Write-OutputColor "  No domain entered. Cancelled." -color "Warning"
            return
        }
    }

    # Validate domain name format
    if ($targetDomain -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.\-]*[a-zA-Z0-9]$' -or $targetDomain -notmatch '\.') {
        Write-OutputColor "  Invalid domain name format. Expected format: corp.local" -color "Error"
        return
    }

    # Test network connectivity
    Write-OutputColor "  Testing network connectivity..." -color "Info"
    if (-not (Test-NetworkConnectivity)) {
        Write-OutputColor "  Warning: No network connectivity detected." -color "Warning"
        if (-not (Confirm-UserAction -Message "Continue anyway?")) {
            return
        }
    }

    # Test DNS resolution of target domain
    Write-OutputColor "  Resolving domain '$targetDomain'..." -color "Info"
    try {
        $dcRecords = Resolve-DnsName -Name $targetDomain -Type A -ErrorAction Stop
        if ($dcRecords) {
            $aRecord = $dcRecords | Where-Object { $_.Type -eq 'A' } | Select-Object -First 1
            if ($aRecord) {
                Write-OutputColor "  Domain resolved to $($aRecord.IPAddress)" -color "Success"
            }
        }
    }
    catch {
        Write-OutputColor "  Cannot resolve domain '$targetDomain' via DNS." -color "Error"
        Write-OutputColor "  Ensure DNS is configured to reach a domain controller." -color "Warning"
        if (-not (Confirm-UserAction -Message "Continue anyway?")) {
            return
        }
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Joining domain: $targetDomain" -color "Warning"
    Write-OutputColor "  You will need domain admin credentials." -color "Info"

    if (-not (Confirm-UserAction -Message "Proceed with domain join?")) {
        Write-OutputColor "  Domain join cancelled." -color "Info"
        return
    }

    $maxAttempts = $script:MaxRetryAttempts
    $attempt = 0

    while ($attempt -lt $maxAttempts) {
        $attempt++

        Write-OutputColor "`n  Attempt $attempt of $maxAttempts" -color "Info"

        $credential = Get-Credential -Message "Enter domain admin credentials for $targetDomain"

        if ($null -eq $credential) {
            Write-OutputColor "  Credential entry cancelled." -color "Warning"
            return
        }

        try {
            $joinResult = Invoke-WithTimeout -ScriptBlock {
                Add-Computer -DomainName $targetDomain -Credential $credential -ErrorAction Stop
            } -TimeoutSeconds 120 -Activity "Joining domain '$targetDomain'"
            if ($joinResult.TimedOut) {
                Write-OutputColor "  Domain join timed out after 2 minutes." -color "Error"
                Write-OutputColor "  The operation may still be in progress. Check Event Viewer." -color "Warning"
                continue
            }
            if ($joinResult.Error) { throw $joinResult.Error }
            Write-OutputColor "  Successfully joined domain '$targetDomain'!" -color "Success"
            Write-OutputColor "  A reboot is required to complete the domain join." -color "Warning"
            $global:RebootNeeded = $true
            Add-SessionChange -Category "System" -Description "Joined domain '$targetDomain'"
            Clear-MenuCache
            return
        }
        catch {
            $errMsg = $_.Exception.Message
            Write-OutputColor "  Failed to join domain: $errMsg" -color "Error"

            # Provide specific guidance based on error
            if ($errMsg -match "network path was not found|RPC server is unavailable") {
                Write-OutputColor "  -> Domain controller may be unreachable. Check network and DNS." -color "Warning"
            } elseif ($errMsg -match "logon failure|password|credentials") {
                Write-OutputColor "  -> Check username format (DOMAIN\User or user@domain)." -color "Warning"
            } elseif ($errMsg -match "already joined|already exists") {
                Write-OutputColor "  -> Computer account may already exist. Contact AD admin." -color "Warning"
            }

            # Check if partial join occurred (domain state changed despite error)
            $postCim = Invoke-WithTimeout -ScriptBlock {
                Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
            } -TimeoutSeconds 10 -Activity "Verifying domain join"
            $postCheck = if ($postCim.TimedOut) { $null } else { $postCim.Result }
            if ($null -ne $postCheck -and $postCheck.PartOfDomain) {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Note: Server appears to be domain-joined (to $($postCheck.Domain))." -color "Warning"
                Write-OutputColor "  A reboot may be required to complete the join." -color "Warning"
                $global:RebootNeeded = $true
                Add-SessionChange -Category "System" -Description "Joined domain '$($postCheck.Domain)' (completed after error)"
                return
            }

            if ($attempt -lt $maxAttempts) {
                Write-OutputColor "  Retrying... ($($maxAttempts - $attempt) attempt(s) remaining)" -color "Info"
            }
        }
    }

    Write-OutputColor "  Maximum attempts reached. Domain join failed." -color "Critical"
}
#endregion