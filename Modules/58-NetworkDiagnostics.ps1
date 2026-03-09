#region ===== NETWORK DIAGNOSTICS =====
function Show-NetworkDiagnostics {
    while ($true) {
        if ($global:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                       NETWORK DIAGNOSTICS").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  CONNECTIVITY".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  Ping Host"
        Write-MenuItem "[2]  Port Test (TCP)"
        Write-MenuItem "[3]  Trace Route"
        Write-MenuItem "[4]  Subnet Ping Sweep"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  DNS & ROUTING".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[5]  DNS Lookup"
        Write-MenuItem "[6]  Active Connections"
        Write-MenuItem "[7]  ARP Table"
        Write-MenuItem "[8]  Quick Port Scan (common services)"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  [B] ◄ Back    [M] ◄◄ Server Config" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" { Invoke-PingHost }
            "2" { Invoke-PortTest }
            "3" { Invoke-TraceRoute }
            "4" { Invoke-SubnetSweep }
            "5" { Invoke-DnsLookup }
            "6" { Show-ActiveConnections }
            "7" { Show-ArpTable }
            "8" { Invoke-QuickPortScan }
            "b" { return }
            "B" { return }
            "m" { $global:ReturnToMainMenu = $true; return }
            "M" { $global:ReturnToMainMenu = $true; return }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-8 or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

function Invoke-PingHost {
    Clear-Host
    Write-CenteredOutput "Ping Host" -color "Info"
    Write-OutputColor "" -color "Info"
    $target = Read-Host "  Enter hostname or IP"
    $navResult = Test-NavigationCommand -UserInput $target
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($target)) { return }
    $target = $target.Trim('"')

    if ($target -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.\-:]*$') {
        Write-OutputColor "  Invalid hostname or IP format." -color "Error"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Pinging $target (20 packets)..." -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $results = @(Test-Connection -ComputerName $target -Count 20 -ErrorAction Stop)
        $sent = 20
        $received = $results.Count
        $lost = $sent - $received
        $lossPercent = [math]::Round(($lost / $sent) * 100, 1)

        # Extract latency values
        $latencies = @($results | ForEach-Object {
            if ($null -ne $_.ResponseTime) { [double]$_.ResponseTime }
            elseif ($null -ne $_.Latency) { [double]$_.Latency }
        } | Where-Object { $null -ne $_ })

        $lineStr = "  PING RESULTS: $target"
        if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        if ($latencies.Count -gt 0) {
            $sorted = @($latencies | Sort-Object)
            $minMs = $sorted[0]
            $maxMs = $sorted[-1]
            $avgMs = [math]::Round(($latencies | Measure-Object -Average).Average, 1)
            $p95Index = [math]::Min([math]::Ceiling($sorted.Count * 0.95) - 1, $sorted.Count - 1)
            $p95Ms = $sorted[$p95Index]

            # Standard deviation
            $sumSqDiff = 0
            foreach ($lat in $latencies) { $sumSqDiff += [math]::Pow($lat - $avgMs, 2) }
            $stdDev = [math]::Round([math]::Sqrt($sumSqDiff / $latencies.Count), 1)

            # Jitter (average difference between consecutive pings)
            $jitter = 0
            if ($latencies.Count -gt 1) {
                $diffs = for ($i = 1; $i -lt $latencies.Count; $i++) {
                    [math]::Abs($latencies[$i] - $latencies[$i-1])
                }
                $jitter = [math]::Round(($diffs | Measure-Object -Average).Average, 1)
            }

            # Color thresholds (for live migration / iSCSI compatibility)
            $avgColor = if ($avgMs -gt 100) { "Error" } elseif ($avgMs -gt 50) { "Warning" } else { "Success" }
            $p95Color = if ($p95Ms -gt 200) { "Error" } elseif ($p95Ms -gt 100) { "Warning" } else { "Success" }
            $lossColor = if ($lossPercent -gt 5) { "Error" } elseif ($lossPercent -gt 0) { "Warning" } else { "Success" }
            $jitterColor = if ($jitter -gt 50) { "Error" } elseif ($jitter -gt 20) { "Warning" } else { "Success" }

            Write-OutputColor "  │$("  Packets: $sent sent, $received received, $lost lost ($lossPercent% loss)".PadRight(72))│" -color $lossColor
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Min:        ${minMs}ms".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Max:        ${maxMs}ms".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Average:    ${avgMs}ms".PadRight(72))│" -color $avgColor
            Write-OutputColor "  │$("  P95:        ${p95Ms}ms".PadRight(72))│" -color $p95Color
            Write-OutputColor "  │$("  Std Dev:    ${stdDev}ms".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Jitter:     ${jitter}ms".PadRight(72))│" -color $jitterColor
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

            # Thresholds guide
            if ($p95Ms -gt 100 -or $lossPercent -gt 0) {
                Write-OutputColor "  │$("  THRESHOLDS  (for Hyper-V live migration / iSCSI)".PadRight(72))│" -color "Warning"
                Write-OutputColor "  │$("  Avg <50ms = Good  |  P95 <100ms = Good  |  Loss 0% = Good".PadRight(72))│" -color "Info"
            } else {
                Write-OutputColor "  │$("  Network quality: Good for live migration and iSCSI".PadRight(72))│" -color "Success"
            }
        } else {
            Write-OutputColor "  │$("  All $sent packets lost (100% loss)".PadRight(72))│" -color "Error"
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }
    catch {
        Write-OutputColor "  Ping failed: $($_.Exception.Message)" -color "Error"
    }
    Write-PressEnter
}

function Invoke-PortTest {
    Clear-Host
    Write-CenteredOutput "TCP Port Test" -color "Info"
    Write-OutputColor "" -color "Info"
    $target = Read-Host "  Enter hostname or IP"
    $navResult = Test-NavigationCommand -UserInput $target
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($target)) { return }
    $target = $target.Trim('"')
    if ($target -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.\-:]*$') {
        Write-OutputColor "  Invalid hostname or IP format." -color "Error"
        return
    }

    $portInput = Read-Host "  Enter port number (e.g., 80, 443, 3389)"
    $navResult = Test-NavigationCommand -UserInput $portInput
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($portInput)) { return }
    $port = 0
    if (-not [int]::TryParse($portInput, [ref]$port)) {
        Write-OutputColor "  Invalid port number." -color "Error"
        return
    }
    if ($port -lt 1 -or $port -gt 65535) {
        Write-OutputColor "  Port must be between 1 and 65535." -color "Error"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Testing $target`:$port ..." -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $result = Test-NetConnection -ComputerName $target -Port $port -WarningAction SilentlyContinue
        $status = if ($result.TcpTestSucceeded) { "OPEN" } else { "CLOSED/FILTERED" }
        $statusColor = if ($result.TcpTestSucceeded) { "Success" } else { "Error" }

        $lineStr = "  PORT TEST: ${target}:${port}"
        if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem -Text "  Target:       $target"
        Write-MenuItem -Text "  Remote IP:    $($result.RemoteAddress)"
        Write-MenuItem -Text "  Port:         $port"
        Write-OutputColor "  │$("  Status:       $status".PadRight(72))│" -color $statusColor
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }
    catch {
        Write-OutputColor "  Port test failed: $($_.Exception.Message)" -color "Error"
    }
    Write-PressEnter
}

function Invoke-TraceRoute {
    Clear-Host
    Write-CenteredOutput "Trace Route" -color "Info"
    Write-OutputColor "" -color "Info"
    $target = Read-Host "  Enter hostname or IP"
    $navResult = Test-NavigationCommand -UserInput $target
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($target)) { return }
    $target = $target.Trim('"')
    if ($target -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.\-:]*$') {
        Write-OutputColor "  Invalid hostname or IP format." -color "Error"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Tracing route to $target ..." -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $result = Test-NetConnection -ComputerName $target -TraceRoute -WarningAction SilentlyContinue
        $lineStr = "  TRACE ROUTE: $target ($($result.RemoteAddress))"
        if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        $hop = 1
        foreach ($ip in $result.TraceRoute) {
            $hopLine = "  Hop $($hop.ToString().PadLeft(2)):  $ip"
            try {
                $dns = [System.Net.Dns]::GetHostEntry($ip).HostName
                if ($dns -and $dns -ne $ip) { $hopLine += " ($dns)" }
            } catch {}
            Write-MenuItem -Text $hopLine
            $hop++
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }
    catch {
        Write-OutputColor "  Trace route failed: $($_.Exception.Message)" -color "Error"
    }
    Write-PressEnter
}

function Invoke-SubnetSweep {
    Clear-Host
    Write-CenteredOutput "Subnet Ping Sweep" -color "Info"
    Write-OutputColor "" -color "Info"

    # Auto-detect subnet from primary adapter
    $adapter = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1
    $defaultSubnet = if ($adapter) {
        $parts = $adapter.IPAddress.Split('.')
        if ($parts.Count -ge 3) { "$($parts[0]).$($parts[1]).$($parts[2])" } else { "" }
    } else { "" }

    $prompt = "  Enter subnet base (e.g., 192.168.1)"
    if ($defaultSubnet) { $prompt += " [$defaultSubnet]" }
    $subnet = Read-Host $prompt
    $navResult = Test-NavigationCommand -UserInput $subnet
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($subnet) -and $defaultSubnet) { $subnet = $defaultSubnet }
    if ([string]::IsNullOrWhiteSpace($subnet)) { return }
    if ($subnet -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}$') {
        Write-OutputColor "  Invalid subnet format. Use X.X.X (e.g., 192.168.1)" -color "Error"
        Write-PressEnter
        return
    }

    $startInput = Read-Host "  Start IP (last octet) [1]"
    $navResult = Test-NavigationCommand -UserInput $startInput
    if ($navResult.ShouldReturn) { return }
    $endInput = Read-Host "  End IP (last octet) [254]"
    $navResult = Test-NavigationCommand -UserInput $endInput
    if ($navResult.ShouldReturn) { return }
    $startVal = 0
    $endVal = 0
    if ([string]::IsNullOrWhiteSpace($startInput)) { $startVal = 1 }
    elseif (-not [int]::TryParse($startInput, [ref]$startVal) -or $startVal -lt 1 -or $startVal -gt 254) {
        Write-OutputColor "  Invalid start octet (must be 1-254)." -color "Error"
        return
    }
    if ([string]::IsNullOrWhiteSpace($endInput)) { $endVal = 254 }
    elseif (-not [int]::TryParse($endInput, [ref]$endVal) -or $endVal -lt 1 -or $endVal -gt 254) {
        Write-OutputColor "  Invalid end octet (must be 1-254)." -color "Error"
        return
    }
    $start = $startVal
    $end = $endVal

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Sweeping $subnet.$start - $subnet.$end ..." -color "Info"
    Write-OutputColor "" -color "Info"

    $alive = @()
    $total = $end - $start + 1
    $batchSize = 50

    # Use parallel jobs in batches to avoid spawning too many processes
    $allResults = [System.Collections.Generic.List[object]]::new()
    $timedOutCount = 0
    for ($batchStart = $start; $batchStart -le $end; $batchStart += $batchSize) {
        $batchEnd = [math]::Min($batchStart + $batchSize - 1, $end)
        $jobs = [System.Collections.Generic.List[object]]::new()
        for ($i = $batchStart; $i -le $batchEnd; $i++) {
            $ip = "$subnet.$i"
            $jobs.Add((Start-Job -ScriptBlock {
                param($IP)
                $result = Test-Connection -ComputerName $IP -Count 1 -Quiet -ErrorAction SilentlyContinue
                [PSCustomObject]@{ IP = $IP; Alive = $result }
            } -ArgumentList $ip))
        }
        $completed = ($batchStart - $start)
        Write-Host "`r  Scanning $completed/$total hosts..." -NoNewline
        $null = $jobs | Wait-Job -Timeout 30
        $timedOut = @($jobs | Where-Object { $_.State -eq 'Running' })
        $timedOutCount += $timedOut.Count
        foreach ($j in $jobs) {
            if ($j.State -eq 'Completed') {
                $r = Receive-Job -Job $j -ErrorAction SilentlyContinue
                if ($r) { $allResults.Add($r) }
            }
        }
        $jobs | Stop-Job -ErrorAction SilentlyContinue
        $jobs | Remove-Job -Force
    }
    Write-Host ""
    if ($timedOutCount -gt 0) {
        Write-OutputColor "  Warning: $timedOutCount ping(s) timed out" -color "Warning"
    }

    $alive = @($allResults | Where-Object { $_.Alive } | Sort-Object { ($_.IP -split '\.') | ForEach-Object { [int]$_ } })

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SWEEP RESULTS: $subnet.$start - $subnet.$end".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    if ($alive.Count -eq 0) {
        Write-OutputColor "  │$("  No hosts responded".PadRight(72))│" -color "Warning"
    } else {
        foreach ($host_ in $alive) {
            $hostLine = "  $($host_.IP)"
            try {
                $dns = [System.Net.Dns]::GetHostEntry($host_.IP).HostName
                if ($dns -and $dns -ne $host_.IP) { $hostLine += " ($dns)" }
            } catch {}
            Write-MenuItem -Text $hostLine
        }
    }

    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem -Text "  $($alive.Count) of $total hosts alive"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-PressEnter
}

function Invoke-DnsLookup {
    Clear-Host
    Write-CenteredOutput "DNS Lookup" -color "Info"
    Write-OutputColor "" -color "Info"
    $target = Read-Host "  Enter hostname or IP to resolve"
    $navResult = Test-NavigationCommand -UserInput $target
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($target)) { return }
    $target = $target.Trim('"')
    if ($target -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.\-:]*$') {
        Write-OutputColor "  Invalid hostname or IP format." -color "Error"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Resolving $target ..." -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $results = Resolve-DnsName -Name $target -ErrorAction Stop

        $lineStr = "  DNS RESULTS: $target"
        if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        foreach ($r in $results) {
            $type = $r.QueryType
            $data = switch ($type) {
                "A"     { $r.IPAddress }
                "AAAA"  { $r.IPAddress }
                "CNAME" { $r.NameHost }
                "MX"    { "$($r.NameExchange) (Priority: $($r.Preference))" }
                "NS"    { $r.NameHost }
                "PTR"   { $r.NameHost }
                "SOA"   { "$($r.PrimaryServer) (Serial: $($r.SerialNumber))" }
                "TXT"   { ($r.Strings -join ' ') }
                default { if ($r) { "$r" } else { "(unknown)" } }
            }
            $line = "  [$type]  $data"
            Write-MenuItem -Text $line
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }
    catch {
        Write-OutputColor "  DNS lookup failed: $($_.Exception.Message)" -color "Error"
    }
    Write-PressEnter
}

function Show-ActiveConnections {
    Clear-Host
    Write-CenteredOutput "Active Connections" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Fetching active TCP connections..." -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $connections = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
            Where-Object { $_.RemoteAddress -ne '127.0.0.1' -and $_.RemoteAddress -ne '::1' } |
            Sort-Object RemoteAddress |
            Select-Object -First 40)

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  ACTIVE TCP CONNECTIONS (Established)".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        if ($connections.Count -eq 0) {
            Write-OutputColor "  │$("  No active remote connections found.".PadRight(72))│" -color "Warning"
        } else {
            $header = "  Local".PadRight(26) + "Remote".PadRight(26) + "PID"
            Write-MenuItem -Text $header -Color "Warning"
            Write-OutputColor "  │$("  $('─' * 70)".PadRight(72))│" -color "Info"
        }

        foreach ($c in $connections) {
            $local = "$($c.LocalAddress):$($c.LocalPort)"
            $remote = "$($c.RemoteAddress):$($c.RemotePort)"
            $proc = try { (Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue).ProcessName } catch { $c.OwningProcess }
            $line = "  $($local.PadRight(24))$($remote.PadRight(24))$proc"
            Write-MenuItem -Text $line
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "  Showing up to 40 established connections." -color "Info"
    }
    catch {
        Write-OutputColor "  Failed: $($_.Exception.Message)" -color "Error"
    }
    Write-PressEnter
}

function Invoke-QuickPortScan {
    Clear-Host
    Write-CenteredOutput "Quick Port Scan" -color "Info"
    Write-OutputColor "" -color "Info"
    $target = Read-Host "  Enter hostname or IP"
    $navResult = Test-NavigationCommand -UserInput $target
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($target)) { return }
    $target = $target.Trim('"')
    if ($target -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.\-:]*$') {
        Write-OutputColor "  Invalid hostname or IP format." -color "Error"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT PORT SET".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  [1] Standard (RDP, SMB, WinRM, HTTP, HTTPS, DNS, SSH)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  [2] Hyper-V / Cluster (Live Migration, Cluster, iSCSI, SMB)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  [3] Domain Controller (LDAP, Kerberos, DNS, RPC, GC)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  [4] All (comprehensive scan)".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $setChoice = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $setChoice
    if ($navResult.ShouldReturn) { return }

    $ports = switch ($setChoice) {
        "1" { @(
            @{Port=22;   Name="SSH"},
            @{Port=53;   Name="DNS"},
            @{Port=80;   Name="HTTP"},
            @{Port=443;  Name="HTTPS"},
            @{Port=445;  Name="SMB"},
            @{Port=3389; Name="RDP"},
            @{Port=5985; Name="WinRM"},
            @{Port=5986; Name="WinRM-S"}
        )}
        "2" { @(
            @{Port=445;  Name="SMB"},
            @{Port=3260; Name="iSCSI"},
            @{Port=3343; Name="Cluster"},
            @{Port=5985; Name="WinRM"},
            @{Port=6600; Name="LiveMig"},
            @{Port=2049; Name="NFS"},
            @{Port=3389; Name="RDP"}
        )}
        "3" { @(
            @{Port=53;   Name="DNS"},
            @{Port=88;   Name="Kerberos"},
            @{Port=135;  Name="RPC"},
            @{Port=389;  Name="LDAP"},
            @{Port=445;  Name="SMB"},
            @{Port=464;  Name="Kpasswd"},
            @{Port=636;  Name="LDAPS"},
            @{Port=3268; Name="GC"},
            @{Port=3269; Name="GC-SSL"}
        )}
        "4" { @(
            @{Port=22;   Name="SSH"},
            @{Port=53;   Name="DNS"},
            @{Port=80;   Name="HTTP"},
            @{Port=88;   Name="Kerberos"},
            @{Port=135;  Name="RPC"},
            @{Port=389;  Name="LDAP"},
            @{Port=443;  Name="HTTPS"},
            @{Port=445;  Name="SMB"},
            @{Port=636;  Name="LDAPS"},
            @{Port=3260; Name="iSCSI"},
            @{Port=3268; Name="GC"},
            @{Port=3343; Name="Cluster"},
            @{Port=3389; Name="RDP"},
            @{Port=5985; Name="WinRM"},
            @{Port=6600; Name="LiveMig"}
        )}
        default { return }
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Scanning $($ports.Count) ports on $target ..." -color "Info"
    Write-OutputColor "" -color "Info"

    # Parallel port scan using jobs
    $jobs = [System.Collections.Generic.List[object]]::new()
    foreach ($p in $ports) {
        $jobs.Add((Start-Job -ScriptBlock {
            param($IP, $Port)
            $tcp = $null
            try {
                $tcp = New-Object System.Net.Sockets.TcpClient
                $connect = $tcp.BeginConnect($IP, $Port, $null, $null)
                $wait = $connect.AsyncWaitHandle.WaitOne(2000, $false)
                if ($wait -and $tcp.Connected) {
                    $tcp.EndConnect($connect)
                    return "OPEN"
                }
                return "CLOSED"
            }
            catch { return "CLOSED" }
            finally { if ($tcp) { $tcp.Close() } }
        } -ArgumentList $target, $p.Port))
    }

    $null = $jobs | Wait-Job -Timeout 15
    $timedOutJobs = @($jobs | Where-Object { $_.State -eq 'Running' })
    if ($timedOutJobs.Count -gt 0) {
        Write-OutputColor "  Warning: $($timedOutJobs.Count) port scan(s) timed out" -color "Warning"
    }

    # Collect results per-job to maintain port alignment
    $jobResults = @{}
    for ($i = 0; $i -lt $jobs.Count; $i++) {
        if ($jobs[$i].State -eq 'Completed') {
            $jobResults[$i] = Receive-Job -Job $jobs[$i] -ErrorAction SilentlyContinue
        }
    }
    $jobs | Stop-Job -ErrorAction SilentlyContinue
    $jobs | Remove-Job -Force

    # Display results
    $lineStr = "  PORT SCAN: $target"
    if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    $header = "  Port".PadRight(10) + "Service".PadRight(14) + "Status"
    Write-MenuItem -Text $header -Color "Warning"
    Write-OutputColor "  │$("  $('─' * 70)".PadRight(72))│" -color "Info"

    $openCount = 0
    for ($i = 0; $i -lt $ports.Count; $i++) {
        $status = if ($jobResults.ContainsKey($i)) { $jobResults[$i] } else { "TIMEOUT" }
        $statusColor = if ($status -eq "OPEN") { "Success" } else { "Error" }
        if ($status -eq "OPEN") { $openCount++ }
        $line = "  $($ports[$i].Port.ToString().PadRight(8))$($ports[$i].Name.PadRight(14))$status"
        Write-OutputColor "  │$($line.PadRight(72))│" -color $statusColor
    }

    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  $openCount of $($ports.Count) ports open".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-PressEnter
}

function Show-ArpTable {
    Clear-Host
    Write-CenteredOutput "ARP Table" -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $arpEntries = @(Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.State -ne 'Unreachable' -and $_.IPAddress -ne '255.255.255.255' } |
            Sort-Object IPAddress)

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  ARP TABLE (IPv4)".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        if ($arpEntries.Count -eq 0) {
            Write-OutputColor "  │$("  No ARP entries found.".PadRight(72))│" -color "Warning"
        } else {
            $header = "  IP Address".PadRight(22) + "MAC Address".PadRight(22) + "State".PadRight(14) + "IF"
            Write-MenuItem -Text $header -Color "Warning"
            Write-OutputColor "  │$("  $('─' * 70)".PadRight(72))│" -color "Info"
        }

        foreach ($entry in $arpEntries) {
            $mac = if ($entry.LinkLayerAddress) { $entry.LinkLayerAddress } else { "N/A" }
            $ifAlias = try { (Get-NetAdapter -InterfaceIndex $entry.InterfaceIndex -ErrorAction Stop).Name } catch { "$($entry.InterfaceIndex)" }
            if ($ifAlias.Length -gt 10) { $ifAlias = $ifAlias.Substring(0, 10) }
            $stateStr = if ($entry.State) { $entry.State.ToString() } else { "Unknown" }
            $line = "  $($entry.IPAddress.PadRight(20))$($mac.PadRight(20))$($stateStr.PadRight(14))$ifAlias"
            Write-MenuItem -Text $line
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }
    catch {
        Write-OutputColor "  Failed: $($_.Exception.Message)" -color "Error"
    }
    Write-PressEnter
}
#endregion