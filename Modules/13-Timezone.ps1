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

# Get a formatted UTC offset string for a timezone (e.g., "UTC-05:00" or "UTC+05:30")
function Get-TimezoneOffsetString {
    param(
        [Parameter(Mandatory=$true)]
        [System.TimeZoneInfo]$TimeZoneInfo
    )

    $offset = $TimeZoneInfo.BaseUtcOffset
    $sign = if ($offset -lt [TimeSpan]::Zero) { "-" } else { "+" }
    return "UTC${sign}$("{0:D2}:{1:D2}" -f [math]::Abs($offset.Hours), [math]::Abs($offset.Minutes))"
}

# Show a comparison of current timezone vs expected/target timezone
function Show-TimezoneComparison {
    param(
        [Parameter(Mandatory=$true)]
        [string]$TargetTimezoneId
    )

    try {
        $currentTz = Get-TimeZone
        $targetTz = Get-TimeZone -Id $TargetTimezoneId -ErrorAction Stop

        $currentOffset = Get-TimezoneOffsetString -TimeZoneInfo $currentTz
        $targetOffset = Get-TimezoneOffsetString -TimeZoneInfo $targetTz

        $currentDst = if ($currentTz.SupportsDaylightSavingTime) { "Yes" } else { "No" }
        $targetDst = if ($targetTz.SupportsDaylightSavingTime) { "Yes" } else { "No" }

        $currentLocal = [System.TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $currentTz).ToString("HH:mm:ss")
        $targetLocal = [System.TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $targetTz).ToString("HH:mm:ss")

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌─────────────────────┬──────────────────────────┬──────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  ".PadRight(21))│$("  CURRENT".PadRight(26))│$("  TARGET".PadRight(26))│" -color "Info"
        Write-OutputColor "  ├─────────────────────┼──────────────────────────┼──────────────────────────┤" -color "Info"

        $currentIdShort = if ($currentTz.Id.Length -gt 24) { $currentTz.Id.Substring(0, 21) + "..." } else { $currentTz.Id }
        $targetIdShort = if ($targetTz.Id.Length -gt 24) { $targetTz.Id.Substring(0, 21) + "..." } else { $targetTz.Id }
        Write-OutputColor "  │$("  Timezone".PadRight(21))│$("  $currentIdShort".PadRight(26))│$("  $targetIdShort".PadRight(26))│" -color "Info"

        Write-OutputColor "  │$("  UTC Offset".PadRight(21))│$("  $currentOffset".PadRight(26))│$("  $targetOffset".PadRight(26))│" -color "Info"
        Write-OutputColor "  │$("  DST Observed".PadRight(21))│$("  $currentDst".PadRight(26))│$("  $targetDst".PadRight(26))│" -color "Info"
        Write-OutputColor "  │$("  Local Time Now".PadRight(21))│$("  $currentLocal".PadRight(26))│$("  $targetLocal".PadRight(26))│" -color "Info"

        # Show time difference
        $diffMinutes = ($targetTz.BaseUtcOffset - $currentTz.BaseUtcOffset).TotalMinutes
        if ($diffMinutes -ne 0) {
            $diffSign = if ($diffMinutes -gt 0) { "+" } else { "" }
            $diffLabel = "${diffSign}$([math]::Round($diffMinutes)) min"
            Write-OutputColor "  │$("  Difference".PadRight(21))│$(" ".PadRight(26))│$("  $diffLabel".PadRight(26))│" -color "Info"
        }
        else {
            Write-OutputColor "  │$("  Difference".PadRight(21))│$(" ".PadRight(26))│$("  Same offset".PadRight(26))│" -color "Info"
        }

        Write-OutputColor "  └─────────────────────┴──────────────────────────┴──────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
    }
    catch {
        # If comparison fails, skip silently — not critical
    }
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
        $currentOffset = Get-TimezoneOffsetString -TimeZoneInfo $currentTz
        $isDst = $currentTz.IsDaylightSavingTime([DateTime]::Now)
        $dstLabel = if ($isDst) { " (DST active)" } else { "" }
        Write-OutputColor "  Current timezone: $($currentTz.DisplayName)" -color "Info"
        Write-OutputColor "  UTC offset: $currentOffset$dstLabel" -color "Info"
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
            "^[Aa]$" { Show-AllSystemTimezones }
            "^\d+$" {
                $num = [int]$choice
                if ($num -ge 1 -and $num -le $regionKeys.Count) {
                    Show-RegionTimezones -RegionName $regionKeys[$num - 1]
                }
                else {
                    Write-OutputColor "  Invalid selection. Enter 1-$($regionKeys.Count), A, or B." -color "Error"
                    Start-Sleep -Seconds 1
                }
            }
            default {
                Write-OutputColor "  Invalid selection. Enter 1-$($regionKeys.Count), A, or B." -color "Error"
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
        $currentOffset = Get-TimezoneOffsetString -TimeZoneInfo $currentTz
        $isDst = $currentTz.IsDaylightSavingTime([DateTime]::Now)
        $dstLabel = if ($isDst) { " (DST active)" } else { "" }
        Write-OutputColor "  Current timezone: $($currentTz.DisplayName)" -color "Info"
        Write-OutputColor "  UTC offset: $currentOffset$dstLabel" -color "Info"
        Write-OutputColor "" -color "Info"

        $timezones = $script:TimezoneRegions[$RegionName]

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  $RegionName TIMEZONES".ToUpper().PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        for ($i = 0; $i -lt $timezones.Count; $i++) {
            $tz = $timezones[$i]
            $marker = if ($tz.Id -eq $currentTz.Id) { " <-- Current" } else { "" }
            $prefix = "  [$($i + 1)]  "
            $maxDisplay = 72 - $prefix.Length - $marker.Length
            $display = if ($tz.Display.Length -gt $maxDisplay) { $tz.Display.Substring(0, $maxDisplay - 3) + "..." } else { $tz.Display }
            $label = "$prefix$display$marker"
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
            "^\d+$" {
                $num = [int]$choice
                if ($num -ge 1 -and $num -le $timezones.Count) {
                    Set-SelectedTimezone -TimezoneId $timezones[$num - 1].Id
                    return
                }
                else {
                    Write-OutputColor "  Invalid selection. Enter 1-$($timezones.Count) or B." -color "Error"
                    Start-Sleep -Seconds 1
                }
            }
            default {
                Write-OutputColor "  Invalid selection. Enter 1-$($timezones.Count) or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Browse all system timezones with pagination
function Show-AllSystemTimezones {
    $allTz = @(Get-TimeZone -ListAvailable | Sort-Object BaseUtcOffset)
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
            if ($label.Length -gt 72) { $label = $label.Substring(0, 69) + "..." }
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
                    Write-OutputColor "  Invalid selection. Enter a valid timezone number, N, P, or B." -color "Error"
                    Start-Sleep -Seconds 1
                }
            }
            default {
                Write-OutputColor "  Invalid selection. Enter a valid timezone number, N, P, or B." -color "Error"
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

    # Show comparison of current vs target before applying
    Show-TimezoneComparison -TargetTimezoneId $TimezoneId

    try {
        # Use the full cmdlet path to avoid recursion
        $prevTzId = $currentTz.Id
        Microsoft.PowerShell.Management\Set-TimeZone -Id $TimezoneId -ErrorAction Stop
        $newTz = Get-TimeZone

        # Verify the change actually took effect
        if ($newTz.Id -ne $TimezoneId) {
            Write-OutputColor "  Timezone change may not have applied correctly." -color "Warning"
            Write-OutputColor "  Expected: $TimezoneId" -color "Warning"
            Write-OutputColor "  Actual:   $($newTz.Id)" -color "Warning"
        }
        else {
            $newOffset = Get-TimezoneOffsetString -TimeZoneInfo $newTz
            Write-OutputColor "  Timezone set to: $($newTz.DisplayName) ($newOffset)" -color "Success"
        }
        Add-SessionChange -Category "System" -Description "Set timezone to $($newTz.DisplayName)"
        Clear-MenuCache
        Add-UndoAction -Category "System" -Description "Set timezone to $($newTz.DisplayName)" -UndoScript {
            param($OldTzId)
            Microsoft.PowerShell.Management\Set-TimeZone -Id $OldTzId -ErrorAction SilentlyContinue
        }.GetNewClosure() -UndoParams @{ OldTzId = $prevTzId }

        # Sync time after timezone change
        Sync-SystemTime -Reason "after timezone change"
    }
    catch {
        Write-OutputColor "  Failed to set timezone: $_" -color "Error"
    }

    Write-PressEnter
}

# Standalone time sync — callable from menu without changing timezone
function Sync-SystemTime {
    param(
        [string]$Reason = ""
    )

    $w32timeSvc = Get-Service -Name W32Time -ErrorAction SilentlyContinue
    if ($null -eq $w32timeSvc) {
        Write-OutputColor "  Windows Time service not found on this system." -color "Error"
        return
    }

    # Verify w32tm command is available
    if (-not (Get-Command w32tm -ErrorAction SilentlyContinue)) {
        Write-OutputColor "  w32tm command not found. Cannot sync time." -color "Error"
        return
    }

    # Show current time and NTP source before sync
    $currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-OutputColor "  Current system time: $currentTime" -color "Info"

    $ntpSource = w32tm /query /source 2>&1
    if ($LASTEXITCODE -eq 0 -and $ntpSource -notmatch "error|not found") {
        Write-OutputColor "  NTP source: $($ntpSource.Trim())" -color "Info"
    }
    Write-OutputColor "" -color "Info"

    if ($w32timeSvc.Status -ne "Running") {
        Write-OutputColor "  Starting Windows Time service..." -color "Info"
        Start-Service W32Time -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    Write-OutputColor "  Synchronizing system time..." -color "Info"
    $syncResult = w32tm /resync 2>&1
    $syncExitCode = $LASTEXITCODE
    $syncText = $syncResult -join ' '

    if ($syncExitCode -eq 0) {
        $newTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-OutputColor "  Time synchronized successfully." -color "Success"
        Write-OutputColor "  Updated system time: $newTime" -color "Info"
        $desc = if ($Reason) { "Time synchronized $Reason" } else { "Time synchronized manually" }
        Add-SessionChange -Category "System" -Description $desc
    }
    else {
        if ($syncText -match "service has not been started|not running") {
            Write-OutputColor "  Windows Time service is not running." -color "Warning"
            Write-OutputColor "  Run: Start-Service W32Time" -color "Info"
        } elseif ($syncText -match "no time data|peer not reachable") {
            Write-OutputColor "  NTP server unreachable. Check:" -color "Warning"
            Write-OutputColor "    1. Network connectivity" -color "Info"
            Write-OutputColor "    2. Firewall allows UDP port 123 outbound" -color "Info"
            Write-OutputColor "    3. NTP server is configured (use NTP Configuration menu)" -color "Info"
        } else {
            Write-OutputColor "  Time sync result: $syncText" -color "Warning"
        }
    }
}
#endregion
