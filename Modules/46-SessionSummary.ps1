#region ===== SESSION SUMMARY =====
# Function to show session summary
function Show-SessionSummary {
    Clear-Host
    Write-CenteredOutput "Session Summary" -color "Info"

    # Calculate runtime
    $runtime = (Get-Date) - $script:ScriptStartTime
    $runtimeStr = "{0:D2}:{1:D2}:{2:D2}" -f $runtime.Hours, $runtime.Minutes, $runtime.Seconds

    Write-OutputColor "Session Runtime: $runtimeStr" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($script:SessionChanges.Count -eq 0) {
        Write-OutputColor "No changes were made during this session." -color "Info"
    }
    else {
        Write-OutputColor "Changes made during this session:" -color "Info"
        Write-OutputColor ("-" * 60) -color "Info"

        foreach ($change in $script:SessionChanges) {
            Write-OutputColor "[$($change.Timestamp)] [$($change.Category)] $($change.Description)" -color "Success"
        }

        Write-OutputColor ("-" * 60) -color "Info"
        Write-OutputColor "Total changes: $($script:SessionChanges.Count)" -color "Info"
    }

    # Show persistent log path
    $logFile = "$script:AppConfigDir\session-log.txt"
    if (Test-Path $logFile) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Session log saved to: $logFile" -color "Info"
    }

    Write-OutputColor "" -color "Info"

    # Check both our flag AND Windows pending reboot
    $windowsRebootPending = Test-RebootPending
    if ($global:RebootNeeded -or $windowsRebootPending) {
        if ($windowsRebootPending -and -not $global:RebootNeeded) {
            Write-OutputColor "[!] Windows has a pending reboot (from previous changes)." -color "Warning"
        }
        else {
            Write-OutputColor "[!] A reboot is required to apply changes." -color "Warning"
        }
    }
}
#endregion