#region ===== EVENT LOG VIEWER =====
# Function to view recent event log entries
function Show-EventLogViewer {
    $lastEvents = $null

    while ($true) {
        if ($global:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                       EVENT LOG VIEWER").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  VIEW OPTIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  Critical & Error Events (Last 24h)"
        Write-MenuItem "[2]  System Log Events"
        Write-MenuItem "[3]  Application Log Events"
        Write-MenuItem "[4]  Security Log (Audit Failures)"
        Write-MenuItem "[5]  Hyper-V Events"
        Write-MenuItem "[6]  Cluster Events"
        Write-MenuItem "[7]  Custom Search"
        Write-MenuItem "[8]  Export Last Results to CSV"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        $events = $null
        $title = ""

        switch ($choice) {
            "1" {
                $title = "Critical & Error Events (Last 24h)"
                $events = Get-WinEvent -FilterHashtable @{LogName='System','Application'; Level=1,2; StartTime=(Get-Date).AddHours(-24)} -MaxEvents 50 -ErrorAction SilentlyContinue
            }
            "2" {
                $title = "System Log Events"
                $events = Get-WinEvent -LogName System -MaxEvents 30 -ErrorAction SilentlyContinue
            }
            "3" {
                $title = "Application Log Events"
                $events = Get-WinEvent -LogName Application -MaxEvents 30 -ErrorAction SilentlyContinue
            }
            "4" {
                $title = "Security Audit Failures"
                $events = Get-WinEvent -FilterHashtable @{LogName='Security'; Keywords=4503599627370496} -MaxEvents 30 -ErrorAction SilentlyContinue
            }
            "5" {
                if (-not (Test-HyperVInstalled)) {
                    Write-OutputColor "  Hyper-V is not installed. Event log not available." -color "Warning"
                    Write-PressEnter
                    continue
                }
                $title = "Hyper-V Events"
                $events = Get-WinEvent -LogName "Microsoft-Windows-Hyper-V-VMMS-Admin" -MaxEvents 30 -ErrorAction SilentlyContinue
            }
            "6" {
                if (-not (Test-FailoverClusteringInstalled)) {
                    Write-OutputColor "  Failover Clustering is not installed. Event log not available." -color "Warning"
                    Write-PressEnter
                    continue
                }
                $title = "Cluster Events"
                $events = Get-WinEvent -LogName "Microsoft-Windows-FailoverClustering/Operational" -MaxEvents 30 -ErrorAction SilentlyContinue
            }
            "7" {
                # Custom Search
                $searchResult = Show-EventLogCustomSearch
                if ($searchResult) {
                    $events = $searchResult.Events
                    $title = $searchResult.Title
                }
            }
            "8" {
                # Export last results to CSV
                if (-not $lastEvents) {
                    Write-OutputColor "  No results to export. Run a query first." -color "Warning"
                    Write-PressEnter
                    continue
                }
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $csvPath = "$script:TempPath\EventLog_$timestamp.csv"
                try {
                    $lastEvents | Select-Object TimeCreated, LevelDisplayName, Id, ProviderName, Message |
                        Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
                    Write-OutputColor "  Exported $(@($lastEvents).Count) events to:" -color "Success"
                    Write-OutputColor "  $csvPath" -color "Info"
                }
                catch {
                    Write-OutputColor "  Export failed: $_" -color "Error"
                }
                Write-PressEnter
                continue
            }
            default { Write-OutputColor "  Invalid choice. Enter 1-8 or B." -color "Error"; Start-Sleep -Seconds 1; continue }
        }

        if ($choice -eq "8") { continue }

        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  $title".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        if (-not $events) {
            Write-OutputColor "  No events found." -color "Info"
        }
        else {
            $lastEvents = $events
            foreach ($logEvent in $events | Select-Object -First 20) {
                $levelColor = switch ($logEvent.LevelDisplayName) {
                    "Critical" { "Error" }
                    "Error" { "Error" }
                    "Warning" { "Warning" }
                    default { "Info" }
                }
                $timeStr = if ($logEvent.TimeCreated) { $logEvent.TimeCreated.ToString("MM-dd HH:mm") } else { "N/A" }
                $msg = if ($logEvent.Message -and $logEvent.Message.Length -gt 50) { $logEvent.Message.Substring(0,47) + "..." } elseif ($logEvent.Message) { $logEvent.Message } else { "(no message)" }
                $msg = $msg -replace "`r`n|`n", " "
                Write-OutputColor "  [$timeStr] $($logEvent.LevelDisplayName): $msg" -color $levelColor
            }
        }

        Write-PressEnter
    }
}

# Custom event log search
function Show-EventLogCustomSearch {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CUSTOM EVENT LOG SEARCH".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Log name
    Write-OutputColor "  Log name [System/Application/Security/or custom]:" -color "Info"
    Write-OutputColor "  (Press Enter for System)" -color "Info"
    $logName = Read-Host "  Log"
    $navResult = Test-NavigationCommand -UserInput $logName
    if ($navResult.ShouldReturn) { return $null }
    if (-not $logName) { $logName = "System" }

    # Keyword filter
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Keyword filter (source or message substring, blank for none):" -color "Info"
    $keyword = Read-Host "  Keyword"
    $navResult = Test-NavigationCommand -UserInput $keyword
    if ($navResult.ShouldReturn) { return $null }

    # Event ID filter
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Event ID filter (blank for none):" -color "Info"
    $eventIdStr = Read-Host "  Event ID"
    $navResult = Test-NavigationCommand -UserInput $eventIdStr
    if ($navResult.ShouldReturn) { return $null }

    # Time range
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Time range:  [1] 1h  [2] 6h  [3] 24h  [4] 7d  [5] All" -color "Info"
    $timeChoice = Read-Host "  Range"
    $navResult = Test-NavigationCommand -UserInput $timeChoice
    if ($navResult.ShouldReturn) { return $null }
    $startTime = switch ($timeChoice) {
        "1" { (Get-Date).AddHours(-1) }
        "2" { (Get-Date).AddHours(-6) }
        "3" { (Get-Date).AddHours(-24) }
        "4" { (Get-Date).AddDays(-7) }
        default { $null }
    }

    # Build filter
    $filter = @{ LogName = $logName }
    if ($startTime) { $filter['StartTime'] = $startTime }
    if ($eventIdStr -match '^\d+$') { $filter['ID'] = [int]$eventIdStr }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Searching..." -color "Info"

    try {
        $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents 100 -ErrorAction Stop)
    }
    catch {
        if ($_.Exception.Message -like "*No events were found*") {
            $events = @()
        } else {
            Write-OutputColor "  Search error: $_" -color "Error"
            Write-PressEnter
            return $null
        }
    }

    # Apply keyword filter on source/message
    if ($keyword -and $events.Count -gt 0) {
        $events = @($events | Where-Object {
            ($_.ProviderName -like "*$keyword*") -or
            ($_.Message -and $_.Message -like "*$keyword*")
        })
    }

    $titleParts = @("Custom: $logName")
    if ($keyword) { $titleParts += "keyword='$keyword'" }
    if ($eventIdStr) { $titleParts += "ID=$eventIdStr" }
    $title = $titleParts -join " | "

    return @{ Events = $events; Title = $title }
}
#endregion
