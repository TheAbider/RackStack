#region ===== HOSTNAME CONFIGURATION =====
# Function to set the hostname
function Set-HostName {
    Clear-Host
    Write-CenteredOutput "Set Hostname" -color "Info"

    $currentHostname = $env:COMPUTERNAME
    Write-OutputColor "  Current hostname: $currentHostname" -color "Info"

    # Check for pending hostname change. A bare swallow of the error masked real
    # registry-access failures on locked-down GPO hives — surface them at Debug
    # so the user can see "why is my pending-rename hint not showing?" without
    # bothering operators in the common case.
    try {
        $pendingName = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName" -ErrorAction SilentlyContinue).ComputerName
        $activeName = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName" -ErrorAction SilentlyContinue).ComputerName
        if ($pendingName -and $activeName -and $pendingName -ne $activeName) {
            Write-OutputColor "  Pending rename: $activeName -> $pendingName (reboot required)" -color "Warning"
        }
    } catch {
        Write-OutputColor "  (pending-rename probe failed: $($_.Exception.Message))" -color "Debug"
    }
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Hostname requirements:" -color "Info"
    Write-OutputColor "  - 1-15 characters" -color "Info"
    Write-OutputColor "  - Start with a letter or digit" -color "Info"
    Write-OutputColor "  - Letters, digits, and hyphens only" -color "Info"
    Write-OutputColor "  - Cannot end with a hyphen" -color "Info"
    Write-OutputColor "" -color "Info"

    $newHostname = Get-ValidatedInput -Prompt "Enter new hostname" `
        -ValidationScript {
            param($h)
            if (Test-ValidHostname -Hostname $h) { return $true }
            $reason = Get-HostnameValidationError -Hostname $h
            if ($reason) { Write-OutputColor "  $reason" -color "Warning" }
            return $false
        } `
        -ErrorMessage "Invalid hostname format."

    if ($null -eq $newHostname) {
        Write-OutputColor "  Hostname change cancelled." -color "Info"
        return
    }

    if ($newHostname -eq $currentHostname) {
        Write-OutputColor "  Hostname is already '$currentHostname'. No change needed." -color "Info"
        return
    }

    # Check if name exists in AD (informational, non-blocking)
    $adCheck = Test-ComputerNameInAD -ComputerName $newHostname
    if ($adCheck.Checked -and $adCheck.Exists) {
        Write-OutputColor "  Warning: '$newHostname' already exists in Active Directory." -color "Warning"
        Write-OutputColor "  DN: $($adCheck.DN)" -color "Warning"
        Write-OutputColor "  Renaming to a duplicate name may cause replication conflicts." -color "Warning"
        if (-not (Confirm-UserAction -Message "Continue with this name anyway?")) {
            return
        }
    }

    # Check DNS for name collision (informational, non-blocking, timeout-bounded)
    # Wrapped in Invoke-WithTimeout because Resolve-DnsName has no native timeout
    # and a slow DNS server would hang the Set-HostName menu indefinitely.
    # Invoke-WithTimeout runs the script in a fresh local runspace without closure
    # over outer variables, so we bake the hostname in via [scriptblock]::Create.
    # Safe here because $newHostname was validated by Test-ValidHostname (ASCII alnum + hyphen only).
    $dnsScript = [scriptblock]::Create("Resolve-DnsName -Name '$newHostname' -ErrorAction SilentlyContinue -DnsOnly")
    $dnsOutcome = Invoke-WithTimeout -TimeoutSeconds 5 -Activity "DNS name-collision check" -ScriptBlock $dnsScript
    if (-not $dnsOutcome.TimedOut -and -not $dnsOutcome.Failed -and $null -ne $dnsOutcome.Result) {
        $resolvedIPs = @($dnsOutcome.Result | Where-Object { $_.QueryType -eq 'A' -or $_.QueryType -eq 'AAAA' } | ForEach-Object { $_.IPAddress }) -join ', '
        if ($resolvedIPs) {
            Write-OutputColor "  Warning: '$newHostname' resolves in DNS to: $resolvedIPs" -color "Warning"
            Write-OutputColor "  This may be a stale DNS record or an active machine." -color "Warning"
            if (-not (Confirm-UserAction -Message "Continue with this name?")) {
                return
            }
        }
    }

    Write-OutputColor "`n  Hostname Change Summary:" -color "Info"
    Write-OutputColor "  Current: $env:COMPUTERNAME" -color "Info"
    Write-OutputColor "  New:     $newHostname" -color "Success"

    if ($env:COMPUTERNAME -ne $newHostname) {
        Write-OutputColor "  NOTE: A reboot will be required to apply this change" -color "Warning"
    }

    # Refuse on active cluster nodes. Renaming a clustered node without the proper
    # Remove-ClusterNode / Add-ClusterNode dance breaks the cluster name object and leaves
    # the node in a 'Down' state until manually evicted. Same guard as the 45-ConfigExport
    # Import path — applies to this interactive Set-HostName entry point too.
    try {
        $clusSvc = Get-Service -Name ClusSvc -ErrorAction SilentlyContinue
        if ($null -ne $clusSvc -and $clusSvc.Status -eq 'Running') {
            $thisNode = $null
            if (Get-Command Get-ClusterNode -ErrorAction SilentlyContinue) {
                $thisNode = Get-ClusterNode -Name $env:COMPUTERNAME -ErrorAction SilentlyContinue
            }
            if ($null -ne $thisNode) {
                Write-OutputColor "" -color "Error"
                Write-OutputColor "  REFUSING: this server is an active Failover Cluster node." -color "Error"
                Write-OutputColor "  Renaming a clustered node breaks the cluster name object — the node" -color "Error"
                Write-OutputColor "  is evicted, CSVs go inaccessible, and clustered roles fail." -color "Error"
                Write-OutputColor "  To rename: 1) evict via Failover Cluster Manager, 2) rename + reboot," -color "Warning"
                Write-OutputColor "  3) re-add to the cluster." -color "Warning"
                return
            }
        }
    } catch { }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Changing hostname: '$currentHostname' -> '$newHostname'" -color "Warning"

    if (-not (Confirm-UserAction -Message "Apply hostname change? (Requires reboot)")) {
        Write-OutputColor "  Hostname change cancelled." -color "Info"
        return
    }

    try {
        Rename-Computer -NewName $newHostname -Force -ErrorAction Stop
        Write-OutputColor "  Hostname changed to '$newHostname'. Reboot required!" -color "Success"
        $script:RebootNeeded = $true
        Add-SessionChange -Category "System" -Description "Changed hostname from '$currentHostname' to '$newHostname'"
        Clear-MenuCache
        Add-UndoAction -Category "System" -Description "Changed hostname to '$newHostname'" -UndoScript {
            param($OldName)
            Rename-Computer -NewName $OldName -Force -ErrorAction SilentlyContinue
        }.GetNewClosure() -UndoParams @{ OldName = $currentHostname }
    }
    catch {
        Write-OutputColor "  Failed to change hostname: $_" -color "Error"
    }
    Write-PressEnter
}
#endregion