#region ===== TIMEZONE CONFIGURATION =====
# Function to set the timezone
function Set-ServerTimeZone {
    Clear-Host
    Write-CenteredOutput "Set Timezone" -color "Info"

    $currentTz = Get-TimeZone
    Write-OutputColor "Current timezone: $($currentTz.DisplayName)" -color "Info"
    Write-OutputColor "" -color "Info"

    # Define timezone options
    $timezones = @{
        "1"  = @{ Id = "Newfoundland Standard Time"; Display = "Newfoundland (GMT-03:30)" }
        "2"  = @{ Id = "Atlantic Standard Time"; Display = "Atlantic (GMT-04:00)" }
        "3"  = @{ Id = "Eastern Standard Time"; Display = "Eastern (GMT-05:00)" }
        "4"  = @{ Id = "Central Standard Time"; Display = "Central (GMT-06:00)" }
        "5"  = @{ Id = "Mountain Standard Time"; Display = "Mountain (GMT-07:00)" }
        "6"  = @{ Id = "US Mountain Standard Time"; Display = "Arizona (GMT-07:00, no DST)" }
        "7"  = @{ Id = "Pacific Standard Time"; Display = "Pacific (GMT-08:00)" }
        "8"  = @{ Id = "Alaskan Standard Time"; Display = "Alaska (GMT-09:00)" }
        "9"  = @{ Id = "Hawaiian Standard Time"; Display = "Hawaii (GMT-10:00)" }
        "10" = @{ Id = "Samoa Standard Time"; Display = "Samoa (GMT-11:00)" }
        "11" = @{ Id = "UTC"; Display = "UTC (GMT+00:00)" }
    }

    Write-OutputColor "Available timezones:" -color "Info"
    foreach ($key in ($timezones.Keys | Sort-Object { [int]$_ })) {
        $tz = $timezones[$key]
        $marker = if ($tz.Id -eq $currentTz.Id) { " <-- Current" } else { "" }
        Write-OutputColor "  $key. $($tz.Display)$marker" -color "Info"
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Enter selection (1-11):" -color "Info"
    $selection = Read-Host

    # Check for navigation
    $navResult = Test-NavigationCommand -UserInput $selection
    if ($navResult.ShouldReturn) {
        if (Invoke-NavigationAction -NavResult $navResult) { return }
    }

    if ([string]::IsNullOrWhiteSpace($selection) -or -not $timezones.ContainsKey($selection)) {
        Write-OutputColor "Invalid selection. Timezone not changed." -color "Warning"
        return
    }

    $selectedTz = $timezones[$selection]

    if ($selectedTz.Id -eq $currentTz.Id) {
        Write-OutputColor "Timezone is already set to $($selectedTz.Display)." -color "Info"
        return
    }

    try {
        # Use the full cmdlet path to avoid recursion
        Microsoft.PowerShell.Management\Set-TimeZone -Id $selectedTz.Id -ErrorAction Stop
        Write-OutputColor "Timezone set to: $($selectedTz.Display)" -color "Success"
        Add-SessionChange -Category "System" -Description "Set timezone to $($selectedTz.Display)"

        # Sync time
        Write-OutputColor "Synchronizing system time..." -color "Info"
        $null = w32tm /resync 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-OutputColor "Time synchronized successfully." -color "Success"
        }
        else {
            Write-OutputColor "Time sync may have failed. Check network connectivity." -color "Warning"
        }
    }
    catch {
        Write-OutputColor "Failed to set timezone: $_" -color "Error"
    }
}
#endregion