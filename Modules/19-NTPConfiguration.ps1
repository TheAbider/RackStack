#region ===== NTP CONFIGURATION =====
# Function to configure NTP time servers
function Set-NTPConfiguration {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                        NTP CONFIGURATION").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        # Get current NTP configuration (safely handle w32tm failures). `w32tm /query /status`
        # localizes the "Source:" label on non-English Windows MUI (e.g. "Quelle:" on de-DE),
        # so the English-only Select-String would render "Unknown" on non-EN hosts. Pull from
        # the W32Time registry (NtpServer value) as the language-neutral primary source, then
        # fall back to the w32tm string for environments where the registry lookup fails.
        $currentSource = "Unknown"
        try {
            $w32cfg = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' -Name 'NtpServer','Type' -ErrorAction Stop
            if ($w32cfg.Type -eq 'NoSync') {
                $currentSource = "Local clock (NoSync — no external sync configured)"
            } elseif ($w32cfg.NtpServer) {
                # NtpServer is space-separated peers, often with ',0x9' suffix flags
                $currentSource = ($w32cfg.NtpServer -split '\s+' | ForEach-Object { ($_ -split ',')[0] } | Where-Object { $_ }) -join ', '
            }
        } catch {
            try {
                $w32tmQuery = w32tm /query /status 2>&1
                $sourceLine = $w32tmQuery | Select-String "Source:"
                if ($null -ne $sourceLine) {
                    $splitParts = $sourceLine.ToString().Split(":", 2)
                    if ($splitParts.Count -ge 2) { $currentSource = $splitParts[1].Trim() }
                }
            } catch {
                $currentSource = "Unable to query (Windows Time service may not be running)"
            }
        }

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  CURRENT TIME CONFIGURATION".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        $lineStr = "  Current Time Source: $currentSource"
        if ($lineStr.Length -gt 72) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Current Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')".PadRight(72))│" -color "Info"

        $ntpCim = Invoke-WithTimeout -ScriptBlock {
            (Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec 8 -ErrorAction SilentlyContinue).PartOfDomain
        } -TimeoutSeconds 10 -Activity "Checking domain status"
        $isDomainJoined = if ($ntpCim.TimedOut) { $false } else { $ntpCim.Result }
        if ($isDomainJoined) {
            Write-OutputColor "  │$("  Domain Joined: Yes (typically syncs with DC)".PadRight(72))│" -color "Info"
        } else {
            Write-OutputColor "  │$("  Domain Joined: No".PadRight(72))│" -color "Info"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  OPTIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  Use Domain Controller (Recommended for domain-joined)"
        Write-MenuItem "[2]  Use time.windows.com (Microsoft)"
        Write-MenuItem "[3]  Use pool.ntp.org (Public NTP Pool)"
        Write-MenuItem "[4]  Use Custom NTP Server"
        Write-MenuItem "[5]  Force Time Sync Now"
        Write-MenuItem "[6]  Show Detailed Time Status"
        Write-MenuItem "[7]  View NTP Status"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" {
                if (-not $isDomainJoined) {
                    Write-OutputColor "  This server is not domain-joined." -color "Warning"
                } else {
                    Set-NTPServer -Server "NT5DS" -IsDomainType $true
                }
            }
            "2" {
                Set-NTPServer -Server "time.windows.com"
            }
            "3" {
                Set-NTPServer -Server "pool.ntp.org"
            }
            "4" {
                Write-OutputColor "" -color "Info"
                $customNTP = Read-Host "  Enter NTP server address"
                $navResult = Test-NavigationCommand -UserInput $customNTP
                if ($navResult.ShouldReturn) { return }
                if ($customNTP -and $customNTP -match '^[a-zA-Z0-9][a-zA-Z0-9\.\-]*[a-zA-Z0-9]$') {
                    Set-NTPServer -Server $customNTP
                } elseif ($customNTP) {
                    Write-OutputColor "  Invalid NTP server format. Use a hostname or IP address." -color "Error"
                }
            }
            "5" {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Forcing time synchronization..." -color "Info"
                $result = w32tm /resync /force 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-OutputColor "  Time synchronized successfully." -color "Success"
                } else {
                    Write-OutputColor "  Sync result: $result" -color "Warning"
                }
            }
            "6" {
                Show-DetailedTimeStatus
            }
            "7" {
                Show-NTPStatus
            }
            "b" { return }
            "B" { return }
            default { Write-OutputColor "  Invalid choice. Enter 1-7 or B." -color "Error"; Start-Sleep -Seconds 1 }
        }

        Write-PressEnter
    }
}

function Set-NTPServer {
    param(
        [string]$Server,
        [bool]$IsDomainType = $false
    )

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Configuring NTP server: $Server" -color "Info"

    try {
        # Capture previous NTP config for undo
        $prevNTPConfig = w32tm /query /configuration 2>&1
        $prevSource = ($prevNTPConfig | Where-Object { $_ -match 'NtpServer:' }) -replace '.*NtpServer:\s*', '' -replace '\s*\(.*', ''

        if ($IsDomainType) {
            # Configure to sync with domain hierarchy
            $null = w32tm /config /syncfromflags:DOMHIER /update 2>&1
        } else {
            # Configure manual NTP server
            $null = w32tm /config /manualpeerlist:$Server /syncfromflags:manual /reliable:yes /update 2>&1
        }

        if ($LASTEXITCODE -ne 0) {
            Write-OutputColor "  Failed to configure NTP server (exit code $LASTEXITCODE)." -color "Error"
            Write-OutputColor "  Tip: Verify the W32Time service is running and the NTP server address is reachable." -color "Warning"
            return
        }

        # Restart time service (validate it exists first)
        $w32Svc = Get-Service -Name w32time -ErrorAction SilentlyContinue
        if ($null -ne $w32Svc) {
            if ($w32Svc.Status -ne 'Running') {
                Start-Service w32time -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            } else {
                Restart-Service w32time -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
            # Verify service restarted
            $w32Svc = Get-Service -Name w32time -ErrorAction SilentlyContinue
            if ($null -ne $w32Svc -and $w32Svc.Status -ne 'Running') {
                Write-OutputColor "  WARNING: W32Time service failed to restart." -color "Warning"
            }
        } else {
            Write-OutputColor "  WARNING: W32Time service not found. Time sync may not work." -color "Warning"
        }

        # Force sync
        $null = w32tm /resync /force 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-OutputColor "  NTP configured but time sync failed (exit code $LASTEXITCODE)." -color "Warning"
        }

        Write-OutputColor "  NTP server configured successfully." -color "Success"
        Add-SessionChange -Category "System" -Description "Configured NTP server: $Server"
        Clear-MenuCache
        if ($prevSource -and -not $IsDomainType) {
            Add-UndoAction -Category "System" -Description "Configured NTP server: $Server" -UndoScript {
                param($OldServer)
                # Quote the peer list — multi-peer values like "time.windows.com time.nist.gov"
                # contain a space and were previously split into multiple args, so undo
                # silently restored only the first peer (or no peer at all).
                w32tm /config "/manualpeerlist:$OldServer" /syncfromflags:manual /reliable:yes /update 2>&1
                Restart-Service w32time -Force -ErrorAction SilentlyContinue
            }.GetNewClosure() -UndoParams @{ OldServer = $prevSource }
        }
    }
    catch {
        Write-OutputColor "  Failed to configure NTP: $_" -color "Error"
    }
}

function Show-DetailedTimeStatus {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  DETAILED TIME STATUS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $status = w32tm /query /status 2>&1
    $offsetSeconds = $null

    foreach ($line in $status) {
        $lineStr = $line.ToString()
        if ($lineStr.Trim()) {
            $displayLine = if ($lineStr.Length -gt 68) { $lineStr.Substring(0,65) + "..." } else { $lineStr }
            Write-OutputColor "  │$("  $displayLine".PadRight(72))│" -color "Info"

            # Parse phase offset (in seconds)
            if ($lineStr -match 'Phase Offset:\s*([\-\d\.]+)s') {
                $regexMatches = $matches
                $offsetSeconds = [double]$regexMatches[1]
            }
        }
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    # Time skew analysis
    if ($null -ne $offsetSeconds) {
        $absOffset = [math]::Abs($offsetSeconds)
        $offsetMs = [math]::Round($absOffset * 1000, 1)
        $direction = if ($offsetSeconds -gt 0) { "ahead" } else { "behind" }
        Write-OutputColor "" -color "Info"

        if ($absOffset -gt 30) {
            Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Error"
            Write-OutputColor "  ║$("  CRITICAL: Clock is ${offsetSeconds}s $direction NTP source!".PadRight(72))║" -color "Error"
            Write-OutputColor "  ║$("  Kerberos auth will FAIL at >5 min skew. iSCSI may corrupt data.".PadRight(72))║" -color "Error"
            Write-OutputColor "  ║$("  Run 'Force Time Sync Now' immediately.".PadRight(72))║" -color "Error"
            Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Error"
        } elseif ($absOffset -gt 1) {
            Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Warning"
            Write-OutputColor "  ║$("  WARNING: Clock skew detected — ${offsetSeconds}s $direction NTP source".PadRight(72))║" -color "Warning"
            Write-OutputColor "  ║$("  Consider running 'Force Time Sync Now' to correct.".PadRight(72))║" -color "Warning"
            Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Warning"
        } elseif ($absOffset -gt 0.1) {
            Write-OutputColor "  Clock offset: ${offsetMs}ms $direction — within acceptable range" -color "Info"
        } else {
            Write-OutputColor "  Clock offset: ${offsetMs}ms — excellent synchronization" -color "Success"
        }
    }
}

function Show-NTPStatus {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  NTP CONFIGURATION STATUS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    # Get current time source
    try {
        $source = (w32tm /query /source 2>&1).Trim()
        $color = if ($source -match 'error|Local CMOS') { "Warning" } else { "Success" }
        $lineStr = "  Time Source: $source"
        if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color $color
    } catch {
        Write-OutputColor "  │$("  Time Source: Cannot determine".PadRight(72))│" -color "Warning"
    }

    # Get sync status
    try {
        $status = w32tm /query /status 2>&1
        foreach ($line in $status) {
            $lineStr = "$line".Trim()
            if ($lineStr -match '^(Source|Last Sync|Stratum|Poll Interval):(.*)') {
                $regexMatches = $matches
                $label = $regexMatches[1].Trim()
                $value = $regexMatches[2].Trim()
                $displayLine = "  ${label}: $value"
                if ($displayLine.Length -gt 69) { $displayLine = $displayLine.Substring(0, 69) + "..." }
                Write-OutputColor "  │$($displayLine.PadRight(72))│" -color "Info"
            }
        }
    } catch {
        Write-OutputColor "  │$("  Cannot query time status".PadRight(72))│" -color "Warning"
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    # Show configured NTP peers
    try {
        $peers = w32tm /query /peers 2>&1
        $peerCount = @($peers | Where-Object { $_ -match '^Peer:' }).Count
        if ($peerCount -gt 0) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  CONFIGURED PEERS ($peerCount)".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($peerLine in $peers) {
                if ("$peerLine" -match '^Peer:\s*(.+)') {
                    $regexMatches = $matches
                    $peerName = $regexMatches[1].Trim()
                    $displayLine = "  - $peerName"
                    if ($displayLine.Length -gt 69) { $displayLine = $displayLine.Substring(0, 69) + "..." }
                    Write-OutputColor "  │$($displayLine.PadRight(72))│" -color "Info"
                }
            }
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        }
    } catch {
        # Ignore peer query failures
    }

    # Test time accuracy
    try {
        $ntpTestResult = Invoke-WithTimeout -ScriptBlock { w32tm /stripchart /computer:time.windows.com /dataonly /samples:1 2>&1 } -TimeoutSeconds 10 -Activity "Testing time accuracy"
        $ntpTest = if (-not $ntpTestResult.TimedOut) { $ntpTestResult.Result } else { $null }
        if ($null -eq $ntpTest) { Write-OutputColor "  Time accuracy test timed out (no internet?)" -color "Warning" }
        $lastLine = $ntpTest | Select-Object -Last 1
        if ("$lastLine" -match '([+-]?\d+\.\d+)s') {
            $regexMatches = $matches
            $offset = [double]$regexMatches[1]
            $offsetMs = [math]::Abs([math]::Round($offset * 1000, 0))
            $color = if ($offsetMs -lt 1000) { "Success" } elseif ($offsetMs -lt 5000) { "Warning" } else { "Error" }
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Time offset from time.windows.com: ${offsetMs}ms" -color $color
        }
    } catch {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Could not test time accuracy" -color "Warning"
    }
}
#endregion