#region ===== TIMEZONE CONFIGURATION =====
# World timezone configuration with continent-based drill-down

# Curated timezone data organized by region
$script:TimezoneRegions = [ordered]@{
    "North America" = @(
        @{ Id = "Newfoundland Standard Time";    Display = "Newfoundland (UTC-03:30)" }
        @{ Id = "Atlantic Standard Time";        Display = "Atlantic (UTC-04:00)" }
        @{ Id = "Eastern Standard Time";         Display = "Eastern (UTC-05:00)" }
        @{ Id = "Central Standard Time";         Display = "Central (UTC-06:00)" }
        @{ Id = "Mountain Standard Time";        Display = "Mountain (UTC-07:00)" }
        @{ Id = "US Mountain Standard Time";     Display = "Arizona (UTC-07:00, no DST)" }
        @{ Id = "Pacific Standard Time";         Display = "Pacific (UTC-08:00)" }
        @{ Id = "Alaskan Standard Time";         Display = "Alaska (UTC-09:00)" }
        @{ Id = "Hawaiian Standard Time";        Display = "Hawaii (UTC-10:00)" }
        @{ Id = "Samoa Standard Time";           Display = "Samoa (UTC-11:00)" }
        @{ Id = "Canada Central Standard Time";  Display = "Saskatchewan (UTC-06:00, no DST)" }
        @{ Id = "Mountain Standard Time (Mexico)"; Display = "Mexico - Chihuahua (UTC-07:00)" }
        @{ Id = "Central Standard Time (Mexico)"; Display = "Mexico City (UTC-06:00)" }
    )
    "South America" = @(
        @{ Id = "E. South America Standard Time"; Display = "Brasilia (UTC-03:00)" }
        @{ Id = "Argentina Standard Time";        Display = "Buenos Aires (UTC-03:00)" }
        @{ Id = "SA Pacific Standard Time";       Display = "Bogota / Lima (UTC-05:00)" }
        @{ Id = "Venezuela Standard Time";        Display = "Caracas (UTC-04:00)" }
        @{ Id = "Central Brazilian Standard Time"; Display = "Cuiaba (UTC-04:00)" }
        @{ Id = "SA Eastern Standard Time";       Display = "Cayenne (UTC-03:00)" }
        @{ Id = "SA Western Standard Time";       Display = "Georgetown / La Paz (UTC-04:00)" }
        @{ Id = "Pacific SA Standard Time";       Display = "Santiago (UTC-04:00)" }
        @{ Id = "Montevideo Standard Time";       Display = "Montevideo (UTC-03:00)" }
    )
    "Europe" = @(
        @{ Id = "GMT Standard Time";             Display = "London (UTC+00:00)" }
        @{ Id = "W. Europe Standard Time";       Display = "Amsterdam / Berlin (UTC+01:00)" }
        @{ Id = "Romance Standard Time";         Display = "Brussels / Paris (UTC+01:00)" }
        @{ Id = "Central European Standard Time"; Display = "Warsaw / Budapest (UTC+01:00)" }
        @{ Id = "GTB Standard Time";             Display = "Bucharest (UTC+02:00)" }
        @{ Id = "FLE Standard Time";             Display = "Helsinki / Kyiv (UTC+02:00)" }
        @{ Id = "Turkey Standard Time";          Display = "Athens / Istanbul (UTC+03:00)" }
        @{ Id = "Russian Standard Time";         Display = "Moscow (UTC+03:00)" }
        @{ Id = "Greenwich Standard Time";       Display = "Reykjavik (UTC+00:00)" }
    )
    "Africa" = @(
        @{ Id = "South Africa Standard Time";    Display = "Johannesburg (UTC+02:00)" }
        @{ Id = "Egypt Standard Time";           Display = "Cairo (UTC+02:00)" }
        @{ Id = "W. Central Africa Standard Time"; Display = "Lagos (UTC+01:00)" }
        @{ Id = "E. Africa Standard Time";       Display = "Nairobi (UTC+03:00)" }
        @{ Id = "Morocco Standard Time";         Display = "Casablanca (UTC+01:00)" }
        @{ Id = "Namibia Standard Time";         Display = "Windhoek (UTC+02:00)" }
    )
    "Asia" = @(
        @{ Id = "Arabian Standard Time";         Display = "Dubai (UTC+04:00)" }
        @{ Id = "India Standard Time";           Display = "India (UTC+05:30)" }
        @{ Id = "SE Asia Standard Time";         Display = "Bangkok / Jakarta (UTC+07:00)" }
        @{ Id = "China Standard Time";           Display = "Beijing (UTC+08:00)" }
        @{ Id = "Singapore Standard Time";       Display = "Singapore (UTC+08:00)" }
        @{ Id = "Tokyo Standard Time";           Display = "Tokyo (UTC+09:00)" }
        @{ Id = "Korea Standard Time";           Display = "Seoul (UTC+09:00)" }
        @{ Id = "Israel Standard Time";          Display = "Jerusalem (UTC+02:00)" }
        @{ Id = "Pakistan Standard Time";        Display = "Karachi (UTC+05:00)" }
        @{ Id = "Central Asia Standard Time";    Display = "Astana / Dhaka (UTC+06:00)" }
        @{ Id = "Taipei Standard Time";          Display = "Taipei (UTC+08:00)" }
    )
    "Oceania/Pacific" = @(
        @{ Id = "AUS Eastern Standard Time";     Display = "Sydney (UTC+10:00)" }
        @{ Id = "AUS Central Standard Time";     Display = "Darwin (UTC+09:30)" }
        @{ Id = "Cen. Australia Standard Time";  Display = "Adelaide (UTC+09:30)" }
        @{ Id = "E. Australia Standard Time";    Display = "Brisbane (UTC+10:00, no DST)" }
        @{ Id = "W. Australia Standard Time";    Display = "Perth (UTC+08:00)" }
        @{ Id = "New Zealand Standard Time";     Display = "Auckland (UTC+12:00)" }
        @{ Id = "Fiji Standard Time";            Display = "Fiji (UTC+12:00)" }
        @{ Id = "Tonga Standard Time";           Display = "Tonga (UTC+13:00)" }
        @{ Id = "West Pacific Standard Time";    Display = "Guam (UTC+10:00)" }
    )
    "UTC/Manual" = @(
        @{ Id = "UTC"; Display = "UTC (UTC+00:00)" }
    )
}

# Entry point — same function name, no caller changes needed
function Set-ServerTimeZone {
    # If TimeZoneRegion is set and valid, skip region picker
    if ($script:TimeZoneRegion -and $script:TimezoneRegions.Contains($script:TimeZoneRegion)) {
        Show-RegionTimezones -RegionName $script:TimeZoneRegion
        return
    }

    Show-TimezoneRegionPicker
}

# Display the 7 regions for the user to pick
function Show-TimezoneRegionPicker {
    while ($true) {
        if ($global:ReturnToMainMenu) { return }
        Clear-Host
        Write-CenteredOutput "Set Timezone" -color "Info"

        $currentTz = Get-TimeZone
        Write-OutputColor "  Current timezone: $($currentTz.DisplayName)" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  SELECT A REGION".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        $regionKeys = @($script:TimezoneRegions.Keys)
        for ($i = 0; $i -lt $regionKeys.Count; $i++) {
            $regionName = $regionKeys[$i]
            $count = $script:TimezoneRegions[$regionName].Count
            $label = "  [$($i + 1)]  $regionName ($count timezones)"
            Write-OutputColor "  │$($label.PadRight(72))│" -color "Info"
        }

        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  [A]  Show all system timezones".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"

        # Check for navigation
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) {
            if (Invoke-NavigationAction -NavResult $navResult) { return }
        }

        switch -Regex ($choice) {
            "^[Bb]$" { return }
            "^[Aa]$" { Show-AllSystemTimezones }
            "^\d+$" {
                $num = [int]$choice
                if ($num -ge 1 -and $num -le $regionKeys.Count) {
                    Show-RegionTimezones -RegionName $regionKeys[$num - 1]
                }
                else {
                    Write-OutputColor "  Invalid selection." -color "Error"
                    Start-Sleep -Seconds 1
                }
            }
            default {
                Write-OutputColor "  Invalid choice." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Display curated timezones for a specific region
function Show-RegionTimezones {
    param (
        [Parameter(Mandatory=$true)]
        [string]$RegionName
    )

    while ($true) {
        if ($global:ReturnToMainMenu) { return }
        Clear-Host
        Write-CenteredOutput "Set Timezone - $RegionName" -color "Info"

        $currentTz = Get-TimeZone
        Write-OutputColor "  Current timezone: $($currentTz.DisplayName)" -color "Info"
        Write-OutputColor "" -color "Info"

        $timezones = $script:TimezoneRegions[$RegionName]

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  $RegionName TIMEZONES".ToUpper().PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        for ($i = 0; $i -lt $timezones.Count; $i++) {
            $tz = $timezones[$i]
            $marker = if ($tz.Id -eq $currentTz.Id) { " <-- Current" } else { "" }
            $label = "  [$($i + 1)]  $($tz.Display)$marker"
            Write-OutputColor "  │$($label.PadRight(72))│" -color "Info"
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"

        # Check for navigation
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) {
            if (Invoke-NavigationAction -NavResult $navResult) { return }
        }

        switch -Regex ($choice) {
            "^[Bb]$" { return }
            "^\d+$" {
                $num = [int]$choice
                if ($num -ge 1 -and $num -le $timezones.Count) {
                    Set-SelectedTimezone -TimezoneId $timezones[$num - 1].Id
                    return
                }
                else {
                    Write-OutputColor "  Invalid selection." -color "Error"
                    Start-Sleep -Seconds 1
                }
            }
            default {
                Write-OutputColor "  Invalid choice." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Browse all system timezones with pagination
function Show-AllSystemTimezones {
    $allTz = Get-TimeZone -ListAvailable | Sort-Object BaseUtcOffset
    $currentTz = Get-TimeZone
    $pageSize = 20
    $page = 0
    $totalPages = [math]::Ceiling($allTz.Count / $pageSize)

    while ($true) {
        if ($global:ReturnToMainMenu) { return }
        Clear-Host
        Write-CenteredOutput "All System Timezones" -color "Info"

        Write-OutputColor "  Current timezone: $($currentTz.DisplayName)" -color "Info"
        Write-OutputColor "  Page $($page + 1) of $totalPages ($($allTz.Count) total)" -color "Info"
        Write-OutputColor "" -color "Info"

        $startIndex = $page * $pageSize
        $endIndex = [math]::Min($startIndex + $pageSize, $allTz.Count) - 1

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"

        for ($i = $startIndex; $i -le $endIndex; $i++) {
            $tz = $allTz[$i]
            $offset = $tz.BaseUtcOffset
            $sign = if ($offset -lt [TimeSpan]::Zero) { "-" } else { "+" }
            $offsetStr = "UTC${sign}$("{0:D2}:{1:D2}" -f [math]::Abs($offset.Hours), $offset.Minutes)"
            $marker = if ($tz.Id -eq $currentTz.Id) { " <-- Current" } else { "" }
            $num = $i + 1
            $label = "  [$num]  $offsetStr  $($tz.Id)$marker"
            if ($label.Length -gt 74) { $label = $label.Substring(0, 71) + "..." }
            Write-OutputColor "  │$($label.PadRight(72))│" -color "Info"
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        $navOptions = @()
        if ($page -lt $totalPages - 1) { $navOptions += "[N]ext" }
        if ($page -gt 0) { $navOptions += "[P]rev" }
        $navOptions += "[B]ack"
        Write-OutputColor "  $($navOptions -join '  ')" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select number or navigate"

        # Check for navigation
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) {
            if (Invoke-NavigationAction -NavResult $navResult) { return }
        }

        switch -Regex ($choice) {
            "^[Bb]$" { return }
            "^[Nn]$" {
                if ($page -lt $totalPages - 1) { $page++ }
            }
            "^[Pp]$" {
                if ($page -gt 0) { $page-- }
            }
            "^\d+$" {
                $num = [int]$choice
                if ($num -ge 1 -and $num -le $allTz.Count) {
                    Set-SelectedTimezone -TimezoneId $allTz[$num - 1].Id
                    return
                }
                else {
                    Write-OutputColor "  Invalid selection." -color "Error"
                    Start-Sleep -Seconds 1
                }
            }
            default {
                Write-OutputColor "  Invalid choice." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Shared logic: apply timezone, sync time, track session change
function Set-SelectedTimezone {
    param (
        [Parameter(Mandatory=$true)]
        [string]$TimezoneId
    )

    $currentTz = Get-TimeZone

    if ($TimezoneId -eq $currentTz.Id) {
        Write-OutputColor "  Timezone is already set to $($currentTz.DisplayName)." -color "Info"
        Write-PressEnter
        return
    }

    try {
        # Use the full cmdlet path to avoid recursion
        Microsoft.PowerShell.Management\Set-TimeZone -Id $TimezoneId -ErrorAction Stop
        $newTz = Get-TimeZone
        Write-OutputColor "  Timezone set to: $($newTz.DisplayName)" -color "Success"
        Add-SessionChange -Category "System" -Description "Set timezone to $($newTz.DisplayName)"

        # Sync time
        Write-OutputColor "  Synchronizing system time..." -color "Info"
        $null = w32tm /resync 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-OutputColor "  Time synchronized successfully." -color "Success"
        }
        else {
            Write-OutputColor "  Time sync may have failed. Check network connectivity." -color "Warning"
        }
    }
    catch {
        Write-OutputColor "  Failed to set timezone: $_" -color "Error"
    }

    Write-PressEnter
}
#endregion
