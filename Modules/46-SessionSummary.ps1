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
    $durationStr = Format-SessionDuration -Duration $runtime
    $totalLine = "  Total: $($script:SessionChanges.Count) change(s)  |  Session: $durationStr"
    if ($totalLine.Length -gt 72) { $totalLine = $totalLine.Substring(0, 69) + "..." }
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$($totalLine.PadRight(72))│" -color "Info"

    # Show reboot status in quick view
    $windowsRebootPending = Test-RebootPending
    if ($global:RebootNeeded -or $windowsRebootPending) {
        $rebootLine = "  Reboot Required: Yes"
        Write-OutputColor "  │$($rebootLine.PadRight(72))│" -color "Warning"
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

# Function to format session duration in human-readable format
function Format-SessionDuration {
    param([TimeSpan]$Duration)

    if ($Duration.TotalHours -ge 1) {
        $hours = [int][math]::Floor($Duration.TotalHours)
        $minutes = $Duration.Minutes
        if ($minutes -gt 0) {
            return "$hours hour$(if ($hours -ne 1) { 's' }) $minutes minute$(if ($minutes -ne 1) { 's' })"
        }
        return "$hours hour$(if ($hours -ne 1) { 's' })"
    }
    $minutes = [int][math]::Floor($Duration.TotalMinutes)
    if ($minutes -lt 1) { return "< 1 minute" }
    return "$minutes minute$(if ($minutes -ne 1) { 's' })"
}

# Function to identify reboot reasons from session changes
function Get-RebootReasons {
    $reasons = [System.Collections.Generic.List[string]]::new()

    foreach ($change in $script:SessionChanges) {
        $desc = $change.Description
        if ($desc -match 'hostname.*changed|Changed hostname') {
            $reasons.Add("Hostname change")
        }
        elseif ($desc -match 'Joined domain|domain join') {
            $reasons.Add("Domain join")
        }
        elseif ($desc -match 'Hyper-V install') {
            $reasons.Add("Hyper-V installation")
        }
        elseif ($desc -match 'MPIO install') {
            $reasons.Add("MPIO installation")
        }
        elseif ($desc -match 'Failover Clustering install') {
            $reasons.Add("Failover Clustering installation")
        }
        elseif ($desc -match 'Windows update') {
            $reasons.Add("Windows Updates")
        }
        elseif ($desc -match 'BitLocker') {
            $reasons.Add("BitLocker configuration")
        }
        elseif ($desc -match 'Storage Replica') {
            $reasons.Add("Storage Replica installation")
        }
        elseif ($desc -match 'Disabled built-in Administrator') {
            $reasons.Add("Administrator account disabled")
        }
    }

    # Deduplicate
    return @($reasons | Select-Object -Unique)
}

# Function to show session summary
function Show-SessionSummary {
    Clear-Host
    Write-CenteredOutput "Session Summary" -color "Info"

    # Calculate runtime
    $runtime = (Get-Date) - $script:ScriptStartTime
    $runtimeStr = "{0:D2}:{1:D2}:{2:D2}" -f [int][math]::Floor($runtime.TotalHours), $runtime.Minutes, $runtime.Seconds
    $durationStr = Format-SessionDuration -Duration $runtime

    # Check reboot status
    $windowsRebootPending = Test-RebootPending
    $rebootNeeded = $global:RebootNeeded -or $windowsRebootPending
    $rebootReasons = @()
    if ($global:RebootNeeded) {
        $rebootReasons = @(Get-RebootReasons)
    }

    # Display box-drawing summary
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌───────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("                          SESSION SUMMARY".PadRight(75))│" -color "Info"
    Write-OutputColor "  ├───────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $changeLine = "  Changes Made: $($script:SessionChanges.Count)"
    Write-OutputColor "  │$($changeLine.PadRight(75))│" -color "Info"

    $durationLine = "  Duration: $durationStr"
    Write-OutputColor "  │$($durationLine.PadRight(75))│" -color "Info"

    Write-OutputColor "  │$(' '.PadRight(75))│" -color "Info"

    if ($script:SessionChanges.Count -eq 0) {
        Write-OutputColor "  │$("  No changes were made during this session.".PadRight(75))│" -color "Info"
    }
    else {
        Write-OutputColor "  │$("  Operations:".PadRight(75))│" -color "Info"

        foreach ($change in $script:SessionChanges) {
            $opLine = "    [+] $($change.Description)"
            if ($opLine.Length -gt 75) { $opLine = $opLine.Substring(0, 72) + "..." }
            Write-OutputColor "  │$($opLine.PadRight(75))│" -color "Success"
        }
    }

    Write-OutputColor "  │$(' '.PadRight(75))│" -color "Info"

    if ($rebootNeeded) {
        Write-OutputColor "  │$("  Reboot Required: Yes".PadRight(75))│" -color "Warning"
        if ($rebootReasons.Count -gt 0) {
            foreach ($reason in $rebootReasons) {
                $reasonLine = "    - $reason"
                Write-OutputColor "  │$($reasonLine.PadRight(75))│" -color "Warning"
            }
        }
        if ($windowsRebootPending -and -not $global:RebootNeeded) {
            Write-OutputColor "  │$("    - Windows pending reboot (from previous changes)".PadRight(75))│" -color "Warning"
        }
        elseif ($windowsRebootPending -and $global:RebootNeeded) {
            Write-OutputColor "  │$("    - Windows also has a pending reboot".PadRight(75))│" -color "Warning"
        }
    }
    else {
        Write-OutputColor "  │$("  Reboot Required: No".PadRight(75))│" -color "Success"
    }

    Write-OutputColor "  └───────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Detailed breakdown by category
    if ($script:SessionChanges.Count -gt 0) {
        Write-OutputColor "  Detailed Breakdown:" -color "Info"
        Write-OutputColor "  $("-" * 60)" -color "Info"

        $categories = @($script:SessionChanges | Group-Object -Property Category)
        foreach ($cat in $categories) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  $($cat.Name) ($($cat.Count)):" -color "Info"
            foreach ($change in $cat.Group) {
                Write-OutputColor "    [$($change.Timestamp)] $($change.Description)" -color "Success"
            }
        }

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  $("-" * 60)" -color "Info"
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
            # Compute once so the txt and json export filenames share the same timestamp
            # suffix. The previous two separate Get-Date calls drifted by 1+ seconds when
            # the operator paused between prompts, producing unpaired filenames.
            $exportTsSuffix = Get-Date -Format 'yyyyMMdd_HHmmss'
            # Sanitize $env:COMPUTERNAME before embedding in a filename. The env var is
            # user-writable on the calling process — `..\` in the filename would otherwise
            # escape Desktop and could overwrite arbitrary operator-writable files.
            $hostSlug = $env:COMPUTERNAME -replace '[^\w\-]', '_'
            $summaryPath = "$env:USERPROFILE\Desktop\${hostSlug}_Session_$exportTsSuffix.txt"
            try {
                $summaryLines = @("Session Summary - $(Get-Date)", "Runtime: $runtimeStr ($durationStr)", "")
                foreach ($change in $script:SessionChanges) {
                    $summaryLines += "[$($change.Timestamp)] [$($change.Category)] $($change.Description)"
                }
                if ($rebootNeeded) {
                    $summaryLines += ""
                    $summaryLines += "Reboot Required: Yes"
                    foreach ($reason in $rebootReasons) {
                        $summaryLines += "  - $reason"
                    }
                }
                # Atomic write-then-rename — operator-visible export, a kill mid-write would
                # leave a confusing truncated file paired with the JSON sibling below.
                $tmpTxt = "$summaryPath.tmp"
                try {
                    $summaryLines | Out-File -LiteralPath $tmpTxt -Encoding UTF8 -Force -ErrorAction Stop
                    Move-Item -LiteralPath $tmpTxt -Destination $summaryPath -Force -ErrorAction Stop
                } catch {
                    if (Test-Path -LiteralPath $tmpTxt) { Remove-Item -LiteralPath $tmpTxt -Force -ErrorAction SilentlyContinue }
                    throw
                }
                Write-OutputColor "  Summary exported to: $summaryPath" -color "Success"
            }
            catch {
                Write-OutputColor "  Failed to export: $_" -color "Error"
            }

            # Offer JSON export for automation. Reuse $exportTsSuffix from the txt export
            # above so paired files have matching timestamps.
            if (Confirm-UserAction -Message "Also export as JSON (for automation)?") {
                $jsonPath = "$env:USERPROFILE\Desktop\${hostSlug}_Session_$exportTsSuffix.json"
                try {
                    $tmpJson = "$jsonPath.tmp"
                    @{
                        Hostname = $env:COMPUTERNAME
                        SessionStart = $script:ScriptStartTime.ToString("yyyy-MM-ddTHH:mm:ss")
                        Runtime = $runtimeStr
                        Duration = $durationStr
                        ChangeCount = $script:SessionChanges.Count
                        RebootRequired = $rebootNeeded
                        RebootReasons = $rebootReasons
                        Changes = @($script:SessionChanges | ForEach-Object {
                            @{ Timestamp = $_.Timestamp; Category = $_.Category; Description = $_.Description }
                        })
                    } | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $tmpJson -Encoding UTF8 -Force -ErrorAction Stop
                    Move-Item -LiteralPath $tmpJson -Destination $jsonPath -Force -ErrorAction Stop
                    Write-OutputColor "  JSON export: $jsonPath" -color "Success"
                }
                catch {
                    if (Test-Path -LiteralPath "$jsonPath.tmp") { Remove-Item -LiteralPath "$jsonPath.tmp" -Force -ErrorAction SilentlyContinue }
                    Write-OutputColor "  Failed to export JSON: $_" -color "Error"
                }
            }
        }
    }

    Write-OutputColor "" -color "Info"

    # Final reboot warning
    if ($rebootNeeded) {
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