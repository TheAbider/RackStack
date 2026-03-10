#region ===== SESSION SUMMARY =====
# Quick inline view of session changes (accessible from main menu via [V])
function Show-QuickSessionChanges {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SESSION CHANGES".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    if ($script:SessionChanges.Count -eq 0) {
        Write-OutputColor "  │$("  No changes made this session.".PadRight(72))│" -color "Info"
    } else {
        $categories = @($script:SessionChanges | Group-Object -Property Category)
        foreach ($cat in $categories) {
            $catLine = "  $($cat.Name) ($($cat.Count))"
            if ($catLine.Length -gt 72) { $catLine = $catLine.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($catLine.PadRight(72))│" -color "Info"
            foreach ($change in $cat.Group) {
                $changeLine = "    $($change.Description)"
                if ($changeLine.Length -gt 72) { $changeLine = $changeLine.Substring(0, 69) + "..." }
                Write-OutputColor "  │$($changeLine.PadRight(72))│" -color "Success"
            }
        }
    }

    $runtime = (Get-Date) - $script:ScriptStartTime
    $totalLine = "  Total: $($script:SessionChanges.Count) change(s)  |  Session: $($runtime.Hours)h $($runtime.Minutes)m"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$($totalLine.PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

# Function to show session summary
function Show-SessionSummary {
    Clear-Host
    Write-CenteredOutput "Session Summary" -color "Info"

    # Calculate runtime
    $runtime = (Get-Date) - $script:ScriptStartTime
    $runtimeStr = "{0:D2}:{1:D2}:{2:D2}" -f [int][math]::Floor($runtime.TotalHours), $runtime.Minutes, $runtime.Seconds

    Write-OutputColor "  Session Runtime: $runtimeStr" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($script:SessionChanges.Count -eq 0) {
        Write-OutputColor "  No changes were made during this session." -color "Info"
    }
    else {
        Write-OutputColor "  Changes made during this session:" -color "Info"
        Write-OutputColor ("-" * 60) -color "Info"

        # Group by category for easier scanning
        $categories = @($script:SessionChanges | Group-Object -Property Category)
        foreach ($cat in $categories) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  $($cat.Name) ($($cat.Count)):" -color "Info"
            foreach ($change in $cat.Group) {
                Write-OutputColor "    [$($change.Timestamp)] $($change.Description)" -color "Success"
            }
        }

        Write-OutputColor "" -color "Info"
        Write-OutputColor ("-" * 60) -color "Info"
        Write-OutputColor "  Total: $($script:SessionChanges.Count) change(s) across $($categories.Count) category(ies)" -color "Info"
    }

    # Show persistent log path
    $logFile = "$script:AppConfigDir\session-log.txt"
    if (Test-Path -LiteralPath $logFile) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Session log saved to: $logFile" -color "Info"
    }

    # Offer to export summary to Desktop
    if ($script:SessionChanges.Count -gt 0) {
        Write-OutputColor "" -color "Info"
        if (Confirm-UserAction -Message "Export session summary to Desktop?") {
            $summaryPath = "$env:USERPROFILE\Desktop\$($env:COMPUTERNAME)_Session_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
            try {
                $summaryLines = @("Session Summary - $(Get-Date)", "Runtime: $runtimeStr", "")
                foreach ($change in $script:SessionChanges) {
                    $summaryLines += "[$($change.Timestamp)] [$($change.Category)] $($change.Description)"
                }
                $summaryLines | Out-File -LiteralPath $summaryPath -Encoding UTF8 -Force
                Write-OutputColor "  Summary exported to: $summaryPath" -color "Success"
            }
            catch {
                Write-OutputColor "  Failed to export: $_" -color "Error"
            }

            # Offer JSON export for automation
            if (Confirm-UserAction -Message "Also export as JSON (for automation)?") {
                $jsonPath = "$env:USERPROFILE\Desktop\$($env:COMPUTERNAME)_Session_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
                try {
                    @{
                        Hostname = $env:COMPUTERNAME
                        SessionStart = $script:ScriptStartTime.ToString("yyyy-MM-ddTHH:mm:ss")
                        Runtime = $runtimeStr
                        ChangeCount = $script:SessionChanges.Count
                        Changes = @($script:SessionChanges | ForEach-Object {
                            @{ Timestamp = $_.Timestamp; Category = $_.Category; Description = $_.Description }
                        })
                    } | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $jsonPath -Encoding UTF8 -Force
                    Write-OutputColor "  JSON export: $jsonPath" -color "Success"
                }
                catch {
                    Write-OutputColor "  Failed to export JSON: $_" -color "Error"
                }
            }
        }
    }

    Write-OutputColor "" -color "Info"

    # Check both our flag AND Windows pending reboot
    $windowsRebootPending = Test-RebootPending
    if ($global:RebootNeeded -or $windowsRebootPending) {
        if ($global:RebootNeeded -and $windowsRebootPending) {
            Write-OutputColor "[!] Reboot required (this session + Windows pending reboot)." -color "Warning"
        } elseif ($windowsRebootPending) {
            Write-OutputColor "[!] Windows has a pending reboot (from previous changes)." -color "Warning"
        } else {
            Write-OutputColor "[!] A reboot is required to apply changes from this session." -color "Warning"
        }
    }
}
#endregion