#region ===== NETWORK DIAGNOSTICS =====
function Show-NetworkDiagnostics {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }
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
        Write-MenuItem "[3]  Port Test (UDP)"
        Write-MenuItem "[4]  Trace Route"
        Write-MenuItem "[5]  Subnet Ping Sweep"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  DNS & ROUTING".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[6]  DNS Lookup"
        Write-MenuItem "[7]  Flush DNS Cache"
        Write-MenuItem "[8]  Active Connections"
        Write-MenuItem "[9]  ARP Table"
        Write-MenuItem "[10] Quick Port Scan (common services)"
        Write-MenuItem "[11] Path MTU Discovery"
        Write-MenuItem "[12] Gateway Connectivity Test"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  PERFORMANCE".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[14] Network Throughput Benchmark (file copy)"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  REPAIR".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[13] Reset Network Stack"
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
            "3" { Invoke-UdpPortTest }
            "4" { Invoke-TraceRoute }
            "5" { Invoke-SubnetSweep }
            "6" { Invoke-DnsLookup }
            "7" { Invoke-FlushDnsCache }
            "8" { Show-ActiveConnections }
            "9" { Show-ArpTable }
            "10" { Invoke-QuickPortScan }
            "11" { Invoke-PathMtuDiscovery }
            "12" { Test-GatewayConnectivity }
            "13" { Invoke-NetworkStackReset }
            "14" { Invoke-NetworkThroughputBenchmark }
            "b" { return }
            "B" { return }
            "m" { $script:ReturnToMainMenu = $true; return }
            "M" { $script:ReturnToMainMenu = $true; return }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-14 or B." -color "Error"
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
        # `-ErrorAction Stop` used to promote per-packet "Request timed out" non-terminating
        # errors to terminating throws — so a single lost packet aborted the entire
        # measurement and the function returned "Ping failed" with zero statistics. The
        # whole point of the call is to measure loss% / jitter / p95 for live-migration
        # readiness, which is meaningless if any actual loss kills the run.
        $results = @(Test-Connection -ComputerName $target -Count 20 -ErrorAction SilentlyContinue)
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
        Write-RackStackError -Code "RS-2013" -Detail "$_"
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
        Write-RackStackError -Code "RS-2014" -Detail "$_"
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

    # Configurable batch size
    $batchInput = Read-Host "  Batch size (default 50, max 100) [50]"
    $navResult = Test-NavigationCommand -UserInput $batchInput
    if ($navResult.ShouldReturn) { return }
    $batchSize = 50
    if (-not [string]::IsNullOrWhiteSpace($batchInput)) {
        $parsedBatch = 0
        if ([int]::TryParse($batchInput, [ref]$parsedBatch) -and $parsedBatch -ge 1 -and $parsedBatch -le 100) {
            $batchSize = $parsedBatch
        } else {
            Write-OutputColor "  Invalid batch size (must be 1-100). Using default 50." -color "Warning"
        }
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Sweeping $subnet.$start - $subnet.$end (batch size: $batchSize)..." -color "Info"
    Write-OutputColor "" -color "Info"

    $alive = @()
    $total = $end - $start + 1

    # Use parallel jobs in batches to avoid spawning too many processes
    $allResults = [System.Collections.Generic.List[object]]::new()
    $timedOutCount = 0
    for ($batchStart = $start; $batchStart -le $end; $batchStart += $batchSize) {
        $batchEnd = [math]::Min($batchStart + $batchSize - 1, $end)
        $jobs = [System.Collections.Generic.List[object]]::new()
        # try/finally guarantees the batch's runspaces are cleaned up even if Wait-Job /
        # Receive-Job / Stop-Job throws mid-batch (closed runspace, WinRM teardown, Ctrl-C).
        # PingSweep on a /23 spawns up to 254 jobs per batch — an exception during interactive
        # sweep would otherwise orphan hundreds of background runspaces in one session.
        try {
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
        }
        finally {
            foreach ($j in $jobs) {
                try { Stop-Job -Job $j -ErrorAction SilentlyContinue } catch { }
                try { Remove-Job -Job $j -Force -ErrorAction SilentlyContinue } catch { }
            }
        }

        # Progressive display: show discovered hosts after each batch
        $batchAlive = @($allResults | Where-Object { $_.Alive })
        $lastFound = if ($batchAlive.Count -gt 0) { $batchAlive[-1].IP } else { "none yet" }
        $scannedSoFar = [math]::Min($batchEnd - $start + 1, $total)
        Write-Host "`r  Scanned $scannedSoFar/$total | Found: $($batchAlive.Count) hosts (last: $lastFound)     "
    }
    Write-OutputColor ""
    if ($timedOutCount -gt 0) {
        Write-OutputColor "  Warning: $timedOutCount ping(s) timed out" -color "Warning"
    }

    $alive = @($allResults | Where-Object { $_.Alive } | Sort-Object { ($_.IP -split '\.') | ForEach-Object { [int]$_ } })

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SWEEP RESULTS: $subnet.$start - $subnet.$end".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    if ($alive.Count -eq 0) {
        Write-OutputColor "  │$("  No hosts responded".PadRight(72))│" -color "Error"
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
        # -QuickTimeout caps each configured DNS server at 1s; default behaviour waits
        # ~15s per server in sequence (so 3 misconfigured DNS = 45s blocking). -DnsOnly
        # skips NetBIOS / LLMNR fallback which adds another tier of waits.
        $results = Resolve-DnsName -Name $target -QuickTimeout -DnsOnly -ErrorAction Stop

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

    # Configurable timeout
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Timeout: [1] 500ms (LAN)  [2] 2000ms (Default)  [3] 5000ms (WAN)" -color "Info"
    $timeoutChoice = Read-Host "  Select timeout [2]"
    $navResult = Test-NavigationCommand -UserInput $timeoutChoice
    if ($navResult.ShouldReturn) { return }
    $TimeoutMs = switch ($timeoutChoice) {
        "1" { 500 }
        "3" { 5000 }
        default { 2000 }
    }

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
        default {
            Write-OutputColor "  Invalid selection. Enter 1-4." -color "Error"
            return
        }
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Scanning $($ports.Count) ports on $target (timeout: ${TimeoutMs}ms)..." -color "Info"
    Write-OutputColor "" -color "Info"

    # Parallel port scan using jobs. Wrap in try/finally so an exception during Wait-Job /
    # Receive-Job (closed runspace, Ctrl-C) can't orphan the ~30 background runspaces.
    $jobs = [System.Collections.Generic.List[object]]::new()
    $jobResults = @{}
    try {
        foreach ($p in $ports) {
            $jobs.Add((Start-Job -ScriptBlock {
                param($IP, $Port, $Timeout)
                $tcp = $null
                try {
                    $tcp = New-Object System.Net.Sockets.TcpClient
                    $connect = $tcp.BeginConnect($IP, $Port, $null, $null)
                    $wait = $connect.AsyncWaitHandle.WaitOne($Timeout, $false)
                    if ($wait -and $tcp.Connected) {
                        $tcp.EndConnect($connect)
                        return "OPEN"
                    }
                    return "CLOSED"
                }
                catch { return "CLOSED" }
                finally { if ($tcp) { $tcp.Close() } }
            } -ArgumentList $target, $p.Port, $TimeoutMs))
        }

        $null = $jobs | Wait-Job -Timeout 15
        $timedOutJobs = @($jobs | Where-Object { $_.State -eq 'Running' })
        if ($timedOutJobs.Count -gt 0) {
            Write-OutputColor "  Warning: $($timedOutJobs.Count) port scan(s) timed out" -color "Warning"
        }

        # Collect results per-job to maintain port alignment
        for ($i = 0; $i -lt $jobs.Count; $i++) {
            if ($jobs[$i].State -eq 'Completed') {
                $jobResults[$i] = Receive-Job -Job $jobs[$i] -ErrorAction SilentlyContinue
            }
        }
    }
    finally {
        foreach ($j in $jobs) {
            try { Stop-Job -Job $j -ErrorAction SilentlyContinue } catch { }
            try { Remove-Job -Job $j -Force -ErrorAction SilentlyContinue } catch { }
        }
    }

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

function Test-PathMTU {
    param(
        [Parameter(Mandatory)]
        [string]$TargetHost
    )
    # Binary search for maximum MTU that doesn't fragment
    # Start at 1500, work down by halving
    $low = 68    # Minimum IPv4 MTU
    $high = 1500 # Standard ethernet MTU
    $bestMTU = $low

    Write-OutputColor "  Testing path MTU to $TargetHost..." -color "Info"

    # Use System.Net.NetworkInformation.Ping with PingOptions(DontFragment=$true).
    # The prior `ping.exe ... -match 'Reply from'` parsed English-only output — on
    # non-English MUI ('Réponse de', 'Antwort von', 'Respuesta desde', 'Σε αναμονή',
    # Japanese / Chinese localized output) the regex never matched, every probe was
    # treated as fragmented, and the binary search converged on MTU=68. Locale-neutral
    # via the .NET enum.
    $pinger = $null
    try {
        $pinger = [System.Net.NetworkInformation.Ping]::new()
        $pingOpts = [System.Net.NetworkInformation.PingOptions]::new()
        $pingOpts.DontFragment = $true
        $pingOpts.Ttl = 128
        while ($low -le $high) {
            $mid = [math]::Floor(($low + $high) / 2)
            # Subtract 28 bytes for IP+ICMP headers
            $pingSize = $mid - 28
            if ($pingSize -lt 0) { $pingSize = 0 }
            $buffer = New-Object byte[] $pingSize
            try {
                $reply = $pinger.Send($TargetHost, 1000, $buffer, $pingOpts)
                if ($reply.Status -eq 'Success') {
                    $bestMTU = $mid
                    $low = $mid + 1
                } else {
                    $high = $mid - 1
                }
            } catch {
                # SocketException → treat as fragmentation-needed
                $high = $mid - 1
            }
        }
    } finally {
        if ($null -ne $pinger) { $pinger.Dispose() }
    }

    Write-OutputColor "  Path MTU to ${TargetHost}: $bestMTU bytes" -color "Success"
    if ($bestMTU -lt 1500) {
        Write-OutputColor "  NOTE: MTU is below standard 1500 - may indicate tunnel/VPN overhead" -color "Warning"
    }
}

function Invoke-PathMtuDiscovery {
    Clear-Host
    Write-CenteredOutput "Path MTU Discovery" -color "Info"
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

    try {
        # Verify host is reachable first
        $pingCheck = Test-Connection -ComputerName $target -Count 1 -Quiet -ErrorAction SilentlyContinue
        if (-not $pingCheck) {
            Write-OutputColor "  Host $target is not responding to ping." -color "Error"
            Write-OutputColor "  Path MTU discovery requires ICMP connectivity." -color "Warning"
            Write-PressEnter
            return
        }

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  PATH MTU DISCOVERY".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        Test-PathMTU -TargetHost $target

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }
    catch {
        Write-OutputColor "  Path MTU discovery failed: $($_.Exception.Message)" -color "Error"
    }
    Write-PressEnter
}

function Test-UDPPort {
    param(
        [Parameter(Mandatory)][string]$TargetHost,
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutMs = 2000
    )
    try {
        $udpClient = New-Object System.Net.Sockets.UdpClient
        $udpClient.Client.ReceiveTimeout = $TimeoutMs
        $udpClient.Connect($TargetHost, $Port)
        $bytes = [System.Text.Encoding]::ASCII.GetBytes("test")
        [void]$udpClient.Send($bytes, $bytes.Length)

        # UDP is connectionless - we can only detect if ICMP unreachable comes back
        try {
            $remoteEP = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
            [void]$udpClient.Receive([ref]$remoteEP)
            Write-OutputColor "  UDP ${TargetHost}:${Port} - Response received" -color "Success"
        } catch [System.Net.Sockets.SocketException] {
            if ($_.Exception.SocketErrorCode -eq 'ConnectionReset') {
                Write-OutputColor "  UDP ${TargetHost}:${Port} - Closed (ICMP unreachable)" -color "Error"
            } else {
                Write-OutputColor "  UDP ${TargetHost}:${Port} - Open|Filtered (no response)" -color "Warning"
            }
        }
    } catch {
        Write-OutputColor "  UDP ${TargetHost}:${Port} - Error: $($_.Exception.Message)" -color "Error"
    } finally {
        if ($null -ne $udpClient) { $udpClient.Close() }
    }
}

function Invoke-UdpPortTest {
    Clear-Host
    Write-CenteredOutput "UDP Port Test" -color "Info"
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

    $portInput = Read-Host "  Enter UDP port number (e.g., 53, 123, 161)"
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

    # Configurable timeout
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Timeout: [1] 500ms (LAN)  [2] 2000ms (Default)  [3] 5000ms (WAN)" -color "Info"
    $timeoutChoice = Read-Host "  Select timeout [2]"
    $navResult = Test-NavigationCommand -UserInput $timeoutChoice
    if ($navResult.ShouldReturn) { return }
    $TimeoutMs = switch ($timeoutChoice) {
        "1" { 500 }
        "3" { 5000 }
        default { 2000 }
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Testing UDP $target`:$port (timeout: ${TimeoutMs}ms)..." -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    $lineStr = "  UDP PORT TEST: ${target}:${port}"
    if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
    Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    Test-UDPPort -TargetHost $target -Port $port -TimeoutMs $TimeoutMs

    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  NOTE: UDP is connectionless. Open|Filtered means no ICMP reject.".PadRight(72))│" -color "Info"
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
            Write-OutputColor "  │$("  No ARP entries found.".PadRight(72))│" -color "Error"
        } else {
            $header = "  IP Address".PadRight(22) + "MAC Address".PadRight(22) + "State".PadRight(14) + "IF"
            Write-MenuItem -Text $header -Color "Warning"
            Write-OutputColor "  │$("  $('─' * 70)".PadRight(72))│" -color "Info"
        }

        foreach ($entry in $arpEntries) {
            $mac = if ($entry.LinkLayerAddress) { $entry.LinkLayerAddress } else { "N/A" }
            $ifAlias = try { (Get-NetAdapter -InterfaceIndex $entry.InterfaceIndex -ErrorAction Stop).Name } catch { "$($entry.InterfaceIndex)" }
            if ($ifAlias -and $ifAlias.Length -gt 10) { $ifAlias = $ifAlias.Substring(0, 10) }
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

function Test-GatewayConnectivity {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Testing default gateway connectivity..." -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $gateways = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $null -ne $_.IPv4DefaultGateway })

        if ($gateways.Count -eq 0) {
            Write-OutputColor "  No default gateways configured." -color "Warning"
            Write-PressEnter
            return
        }

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  GATEWAY CONNECTIVITY".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        foreach ($config in $gateways) {
            $gwIp = $config.IPv4DefaultGateway.NextHop
            $adapter = $config.InterfaceAlias
            $ping = Test-Connection -ComputerName $gwIp -Count 2 -Quiet -ErrorAction SilentlyContinue

            $status = if ($ping) { "Reachable" } else { "UNREACHABLE" }
            $color = if ($ping) { "Success" } else { "Error" }

            $line = "  $adapter -> $gwIp : $status"
            if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($line.PadRight(72))│" -color $color

            # Also test latency if reachable
            if ($ping) {
                $latency = Test-Connection -ComputerName $gwIp -Count 3 -ErrorAction SilentlyContinue
                if ($null -ne $latency) {
                    # PS 5.1 returns objects with .ResponseTime; PS 7 returns PingStatus
                    # with .Latency. Without this extraction, on PS 7 Measure-Object
                    # against ResponseTime returns Average=$null and the operator sees
                    # "Avg latency: 0ms" on a healthy gateway.
                    $latencyMs = @($latency | ForEach-Object {
                        if ($null -ne $_.ResponseTime) { [double]$_.ResponseTime }
                        elseif ($null -ne $_.Latency)  { [double]$_.Latency }
                    } | Where-Object { $null -ne $_ })
                    $avgMs = if ($latencyMs.Count -gt 0) {
                        [math]::Round(($latencyMs | Measure-Object -Average).Average)
                    } else { 0 }
                    $latLine = "    Avg latency: ${avgMs}ms"
                    Write-OutputColor "  │$($latLine.PadRight(72))│" -color "Info"
                }
            }
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }
    catch {
        Write-OutputColor "  Failed to test gateway: $_" -color "Error"
    }

    Write-PressEnter
}

function Invoke-FlushDnsCache {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Flushing DNS client cache..." -color "Info"

    try {
        # Show cache stats before flush
        $cacheStats = Get-DnsClientCache -ErrorAction SilentlyContinue
        $cacheCount = @($cacheStats).Count
        if ($cacheCount -gt 0) {
            Write-OutputColor "  Current cache entries: $cacheCount" -color "Info"
        }

        Clear-DnsClientCache -ErrorAction Stop
        Write-OutputColor "  DNS client cache flushed successfully." -color "Success"

        # Also flush via ipconfig for completeness (catches any native cache)
        $null = ipconfig /flushdns 2>&1

        # Register DNS if domain-joined
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec 5 -ErrorAction SilentlyContinue
        if ($null -ne $cs -and $cs.PartOfDomain) {
            Write-OutputColor "  Registering DNS records (domain-joined)..." -color "Info"
            $null = ipconfig /registerdns 2>&1
            Write-OutputColor "  DNS registration initiated." -color "Success"
        }

        Add-SessionChange -Category "Network" -Description "Flushed DNS client cache ($cacheCount entries cleared)"
    }
    catch {
        Write-OutputColor "  Failed to flush DNS cache: $_" -color "Error"
    }

    Write-PressEnter
}

function Invoke-NetworkStackReset {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Warning"
    Write-OutputColor "  │$("  WARNING: Network Stack Reset".PadRight(72))│" -color "Warning"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Warning"
    Write-OutputColor "  │$("  This will reset Winsock catalog, TCP/IP stack, and firewall rules.".PadRight(72))│" -color "Warning"
    Write-OutputColor "  │$("  A REBOOT IS REQUIRED after this operation.".PadRight(72))│" -color "Warning"
    Write-OutputColor "  │$("  Custom firewall rules may need to be re-applied.".PadRight(72))│" -color "Warning"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Warning"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Which components do you want to reset?" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [1]  Flush DNS cache only (safe, no reboot)" -color "Info"
    Write-OutputColor "  [2]  Reset Winsock catalog (reboot required)" -color "Info"
    Write-OutputColor "  [3]  Reset TCP/IP stack (reboot required)" -color "Info"
    Write-OutputColor "  [4]  Full reset: Winsock + TCP/IP + DNS flush (reboot required)" -color "Info"
    Write-OutputColor "  [B]  Cancel" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    switch ($choice) {
        "1" {
            Invoke-FlushDnsCache
            return  # FlushDnsCache has its own PressEnter
        }
        "2" {
            Write-OutputColor "  Resetting Winsock catalog..." -color "Info"
            $result = netsh winsock reset 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-OutputColor "  Winsock reset failed: $($result -join ' ')" -color "Error"
            } else {
                Write-OutputColor "  Winsock catalog reset. REBOOT REQUIRED." -color "Warning"
                $script:RebootNeeded = $true
                Add-SessionChange -Category "Network" -Description "Reset Winsock catalog (reboot required)"
            }
        }
        "3" {
            Write-OutputColor "  Resetting TCP/IP stack..." -color "Info"
            $result = netsh int ip reset 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-OutputColor "  TCP/IP reset failed: $($result -join ' ')" -color "Error"
            } else {
                Write-OutputColor "  TCP/IP stack reset. REBOOT REQUIRED." -color "Warning"
                $script:RebootNeeded = $true
                Add-SessionChange -Category "Network" -Description "Reset TCP/IP stack (reboot required)"
            }
        }
        "4" {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Are you sure? This resets ALL network stack components. [Y/N]" -color "Warning"
            $confirm = Read-Host "  Confirm"
            if ($confirm -ne 'Y' -and $confirm -ne 'y') {
                Write-OutputColor "  Cancelled." -color "Info"
                Write-PressEnter
                return
            }

            $resetErrors = 0

            Write-OutputColor "  Flushing DNS cache..." -color "Info"
            Clear-DnsClientCache -ErrorAction SilentlyContinue
            $null = ipconfig /flushdns 2>&1
            Write-OutputColor "  DNS cache flushed." -color "Success"

            Write-OutputColor "  Resetting Winsock catalog..." -color "Info"
            $null = netsh winsock reset 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-OutputColor "  Winsock reset encountered errors." -color "Warning"
                $resetErrors++
            } else {
                Write-OutputColor "  Winsock catalog reset." -color "Success"
            }

            Write-OutputColor "  Resetting TCP/IP stack..." -color "Info"
            $null = netsh int ip reset 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-OutputColor "  TCP/IP reset encountered errors." -color "Warning"
                $resetErrors++
            } else {
                Write-OutputColor "  TCP/IP stack reset." -color "Success"
            }

            Write-OutputColor "" -color "Info"
            if ($resetErrors -eq 0) {
                Write-OutputColor "  Full network stack reset complete. REBOOT REQUIRED." -color "Warning"
            } else {
                Write-OutputColor "  Network stack reset completed with $resetErrors warning(s). REBOOT REQUIRED." -color "Warning"
            }
            $script:RebootNeeded = $true
            Add-SessionChange -Category "Network" -Description "Full network stack reset (Winsock + TCP/IP + DNS)"
        }
        default {
            Write-OutputColor "  Cancelled." -color "Info"
        }
    }

    Write-PressEnter
}

# In-box network throughput benchmark: copies a generated test file to a target
# path and back, timing each transfer. Measures the combined network + remote
# storage path (not pure wire speed) using only built-in cmdlets — no external
# binary (ntttcp/iperf are not in-box and are not auto-downloaded). All temp
# files (local source, remote copy, local read-back) are removed in a finally.
function Invoke-NetworkThroughputBenchmark {
    Clear-Host
    Write-CenteredOutput "Network Throughput Benchmark" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Measures real write + read throughput by copying a test file to a target" -color "Info"
    Write-OutputColor "  folder and back. This reflects the full network + remote storage path," -color "Info"
    Write-OutputColor "  not a pure wire-speed figure. A UNC share (\\server\share) is the typical" -color "Info"
    Write-OutputColor "  target; a local path measures the local disk." -color "Info"
    Write-OutputColor "" -color "Info"

    $target = Read-Host "  Enter target folder (UNC or local path)"
    $navResult = Test-NavigationCommand -UserInput $target
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($target)) { return }
    $target = $target.Trim('"').TrimEnd('\')

    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        Write-OutputColor "  Target folder not found or not accessible: $target" -color "Error"
        Write-PressEnter; return
    }

    $sizeMB = 256
    $sizeInput = Read-Host "  Test file size in MB (default 256, 16-4096)"
    if (-not [string]::IsNullOrWhiteSpace($sizeInput)) {
        $parsed = 0
        if ([int]::TryParse($sizeInput.Trim(), [ref]$parsed)) {
            $sizeMB = [math]::Max(16, [math]::Min(4096, $parsed))
        }
    }

    $localTemp  = Join-Path $env:TEMP ("rs_thrput_src_{0}.tmp" -f $PID)
    $remoteFile = Join-Path $target  ("rs_thrput_{0}.tmp" -f $PID)
    $readBack   = Join-Path $env:TEMP ("rs_thrput_dst_{0}.tmp" -f $PID)
    $writeMBps = 0; $readMBps = 0; $ok = $false

    try {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Generating ${sizeMB} MB test file..." -color "Info"
        # Fill a 4 MB buffer with pseudo-random bytes (so the payload is not
        # trivially compressible) and write it enough times to reach the size.
        $bufSize = 4MB
        $buffer = New-Object byte[] $bufSize
        (New-Object System.Random).NextBytes($buffer)
        $iterations = [math]::Ceiling(($sizeMB * 1MB) / $bufSize)
        $fs = [System.IO.File]::Create($localTemp)
        try { for ($i = 0; $i -lt $iterations; $i++) { $fs.Write($buffer, 0, $bufSize) } }
        finally { $fs.Close() }
        $bytes = (Get-Item -LiteralPath $localTemp).Length

        Write-OutputColor "  Measuring WRITE throughput (local -> target)..." -color "Info"
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Copy-Item -LiteralPath $localTemp -Destination $remoteFile -Force -ErrorAction Stop
        $sw.Stop()
        $writeMBps = [math]::Round(($bytes / 1MB) / [math]::Max($sw.Elapsed.TotalSeconds, 0.001), 1)

        Write-OutputColor "  Measuring READ throughput (target -> local)..." -color "Info"
        $sw.Restart()
        Copy-Item -LiteralPath $remoteFile -Destination $readBack -Force -ErrorAction Stop
        $sw.Stop()
        $readMBps = [math]::Round(($bytes / 1MB) / [math]::Max($sw.Elapsed.TotalSeconds, 0.001), 1)
        $ok = $true
    }
    catch {
        Write-OutputColor "  Throughput test failed: $($_.Exception.Message)" -color "Error"
    }
    finally {
        foreach ($p in @($localTemp, $remoteFile, $readBack)) {
            if ($p -and (Test-Path -LiteralPath $p)) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
        }
    }

    if ($ok) {
        $writeMbps = [math]::Round($writeMBps * 8, 0)
        $readMbps  = [math]::Round($readMBps * 8, 0)
        $title = "  THROUGHPUT: $target"
        if ($title.Length -gt 69) { $title = $title.Substring(0, 69) + "..." }
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$($title.PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  Test size:  ${sizeMB} MB".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Write:      ${writeMBps} MB/s  (${writeMbps} Mbps)".PadRight(72))│" -color "Success"
        Write-OutputColor "  │$("  Read:       ${readMBps} MB/s  (${readMbps} Mbps)".PadRight(72))│" -color "Success"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }
    Write-PressEnter
}
#endregion
