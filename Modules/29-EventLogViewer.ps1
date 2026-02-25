#region ===== EVENT LOG VIEWER =====
# Function to view recent event log entries
function Show-EventLogViewer {
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
                $title = "Hyper-V Events"
                $events = Get-WinEvent -LogName "Microsoft-Windows-Hyper-V-VMMS-Admin" -MaxEvents 30 -ErrorAction SilentlyContinue
            }
            "6" {
                $title = "Cluster Events"
                $events = Get-WinEvent -LogName "Microsoft-Windows-FailoverClustering/Operational" -MaxEvents 30 -ErrorAction SilentlyContinue
            }
            "b" { return }
            "B" { return }
            default { Write-OutputColor "  Invalid choice." -color "Error"; Start-Sleep -Seconds 1; continue }
        }

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
            foreach ($logEvent in $events | Select-Object -First 20) {
                $levelColor = switch ($logEvent.LevelDisplayName) {
                    "Critical" { "Error" }
                    "Error" { "Error" }
                    "Warning" { "Warning" }
                    default { "Info" }
                }
                $timeStr = $logEvent.TimeCreated.ToString("MM-dd HH:mm")
                $msg = if ($logEvent.Message -and $logEvent.Message.Length -gt 50) { $logEvent.Message.Substring(0,47) + "..." } elseif ($logEvent.Message) { $logEvent.Message } else { "(no message)" }
                $msg = $msg -replace "`r`n|`n", " "
                Write-OutputColor "  [$timeStr] $($logEvent.LevelDisplayName): $msg" -color $levelColor
            }
        }

        Write-PressEnter
    }
}
#endregion