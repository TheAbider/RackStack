#region ===== NETWORK DIAGNOSTICS =====
function Show-NetworkDiagnostics {
    while ($true) {
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
            "b" { return }
            "B" { return }
            "m" { $global:ReturnToMainMenu = $true; return }
            "M" { $global:ReturnToMainMenu = $true; return }
            default {
                Write-OutputColor "  Invalid choice." -color "Error"
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

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Pinging $target ..." -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $results = Test-Connection -ComputerName $target -Count 4 -ErrorAction Stop
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  PING RESULTS: $target".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        foreach ($r in $results) {
            $addr = if ($r.IPV4Address) { $r.IPV4Address.ToString() } elseif ($r.Address) { $r.Address } else { "N/A" }
            $ms = if ($null -ne $r.ResponseTime) { $r.ResponseTime } elseif ($null -ne $r.Latency) { $r.Latency } else { "?" }
            $line = "  Reply from $addr - ${ms}ms"
            Write-MenuItem -Text $line
        }
        $avgMeasure = $results | ForEach-Object { if ($null -ne $_.ResponseTime) { $_.ResponseTime } elseif ($null -ne $_.Latency) { $_.Latency } else { 0 } } | Measure-Object -Average
        $avg = if ($null -ne $avgMeasure.Average) { $avgMeasure.Average } else { 0 }
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem -Text "  Average: $([math]::Round($avg, 1))ms"
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

    $portInput = Read-Host "  Enter port number (e.g., 80, 443, 3389)"
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

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  PORT TEST: ${target}:${port}".PadRight(72))│" -color "Info"
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

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Tracing route to $target ..." -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $result = Test-NetConnection -ComputerName $target -TraceRoute -WarningAction SilentlyContinue
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  TRACE ROUTE: $target ($($result.RemoteAddress))".PadRight(72))│" -color "Info"
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
    $adapter = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1
    $defaultSubnet = if ($adapter) {
        $parts = $adapter.IPAddress.Split('.')
        "$($parts[0]).$($parts[1]).$($parts[2])"
    } else { "" }

    $prompt = "  Enter subnet base (e.g., 192.168.1)"
    if ($defaultSubnet) { $prompt += " [$defaultSubnet]" }
    $subnet = Read-Host $prompt
    if ([string]::IsNullOrWhiteSpace($subnet) -and $defaultSubnet) { $subnet = $defaultSubnet }
    if ([string]::IsNullOrWhiteSpace($subnet)) { return }

    $startInput = Read-Host "  Start IP (last octet) [1]"
    $endInput = Read-Host "  End IP (last octet) [254]"
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

    # Use parallel jobs for speed
    $jobs = @()
    for ($i = $start; $i -le $end; $i++) {
        $ip = "$subnet.$i"
        $jobs += Start-Job -ScriptBlock {
            param($IP)
            $result = Test-Connection -ComputerName $IP -Count 1 -Quiet -ErrorAction SilentlyContinue
            [PSCustomObject]@{ IP = $IP; Alive = $result }
        } -ArgumentList $ip
    }

    Write-OutputColor "  Waiting for $($jobs.Count) pings to complete..." -color "Info"
    $results = $jobs | Wait-Job -Timeout 30 | Receive-Job
    $jobs | Remove-Job -Force

    $alive = @($results | Where-Object { $_.Alive } | Sort-Object { ($_.IP -split '\.') | ForEach-Object { [int]$_ } })

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

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Resolving $target ..." -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $results = Resolve-DnsName -Name $target -ErrorAction Stop

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  DNS RESULTS: $target".PadRight(72))│" -color "Info"
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
                default { $r.ToString() }
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
        $connections = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
            Where-Object { $_.RemoteAddress -ne '127.0.0.1' -and $_.RemoteAddress -ne '::1' } |
            Sort-Object RemoteAddress |
            Select-Object -First 40

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  ACTIVE TCP CONNECTIONS (Established)".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        $header = "  Local".PadRight(26) + "Remote".PadRight(26) + "PID"
        Write-MenuItem -Text $header -Color "Warning"
        Write-OutputColor "  │$("  $('─' * 70)".PadRight(72))│" -color "Info"

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

function Show-ArpTable {
    Clear-Host
    Write-CenteredOutput "ARP Table" -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $arpEntries = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.State -ne 'Unreachable' -and $_.IPAddress -ne '255.255.255.255' } |
            Sort-Object IPAddress

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  ARP TABLE (IPv4)".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        $header = "  IP Address".PadRight(22) + "MAC Address".PadRight(22) + "State".PadRight(14) + "IF"
        Write-MenuItem -Text $header -Color "Warning"
        Write-OutputColor "  │$("  $('─' * 70)".PadRight(72))│" -color "Info"

        foreach ($entry in $arpEntries) {
            $mac = if ($entry.LinkLayerAddress) { $entry.LinkLayerAddress } else { "N/A" }
            $ifAlias = try { (Get-NetAdapter -InterfaceIndex $entry.InterfaceIndex -ErrorAction SilentlyContinue).Name } catch { $entry.InterfaceIndex }
            if ($ifAlias.Length -gt 10) { $ifAlias = $ifAlias.Substring(0, 10) }
            $line = "  $($entry.IPAddress.PadRight(20))$($mac.PadRight(20))$($entry.State.ToString().PadRight(14))$ifAlias"
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