#region ===== NTP CONFIGURATION =====
# Function to configure NTP time servers
function Set-NTPConfiguration {
    while ($true) {
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                        NTP CONFIGURATION").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        # Get current NTP configuration (safely handle w32tm failures)
        $currentSource = "Unknown"
        try {
            $w32tmQuery = w32tm /query /status 2>&1
            $sourceLine = $w32tmQuery | Select-String "Source:"
            if ($null -ne $sourceLine) {
                $currentSource = $sourceLine.ToString().Split(":", 2)[1].Trim()
            }
        } catch {
            $currentSource = "Unable to query (Windows Time service may not be running)"
        }

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  CURRENT TIME CONFIGURATION".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        $lineStr = "  Current Time Source: $currentSource"
        if ($lineStr.Length -gt 72) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Current Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')".PadRight(72))│" -color "Info"

        $isDomainJoined = (Get-CimInstance -ClassName Win32_ComputerSystem).PartOfDomain
        if ($isDomainJoined) {
            Write-OutputColor "  │$("  Domain Joined: Yes (typically syncs with DC)".PadRight(72))│" -color "Info"
        } else {
            Write-OutputColor "  │$("  Domain Joined: No".PadRight(72))│" -color "Info"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  OPTIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  Use Domain Controller (Recommended for domain-joined)"
        Write-MenuItem "[2]  Use time.windows.com (Microsoft)"
        Write-MenuItem "[3]  Use pool.ntp.org (Public NTP Pool)"
        Write-MenuItem "[4]  Use Custom NTP Server"
        Write-MenuItem "[5]  Force Time Sync Now"
        Write-MenuItem "[6]  Show Detailed Time Status"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" {
                if (-not $isDomainJoined) {
                    Write-OutputColor "  This server is not domain-joined." -color "Warning"
                } else {
                    Set-NTPServer -Server "NT5DS" -IsDomainType $true
                }
            }
            "2" {
                Set-NTPServer -Server "time.windows.com"
            }
            "3" {
                Set-NTPServer -Server "pool.ntp.org"
            }
            "4" {
                Write-OutputColor "" -color "Info"
                $customNTP = Read-Host "  Enter NTP server address"
                if ($customNTP) {
                    Set-NTPServer -Server $customNTP
                }
            }
            "5" {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Forcing time synchronization..." -color "Info"
                $result = w32tm /resync /force 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-OutputColor "  Time synchronized successfully." -color "Success"
                } else {
                    Write-OutputColor "  Sync result: $result" -color "Warning"
                }
            }
            "6" {
                Show-DetailedTimeStatus
            }
            "b" { return }
            "B" { return }
            default { Write-OutputColor "  Invalid choice." -color "Error"; Start-Sleep -Seconds 1 }
        }

        Write-PressEnter
    }
}

function Set-NTPServer {
    param(
        [string]$Server,
        [bool]$IsDomainType = $false
    )

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Configuring NTP server: $Server" -color "Info"

    try {
        if ($IsDomainType) {
            # Configure to sync with domain hierarchy
            $null = w32tm /config /syncfromflags:DOMHIER /update 2>&1
        } else {
            # Configure manual NTP server
            $null = w32tm /config /manualpeerlist:$Server /syncfromflags:manual /reliable:yes /update 2>&1
        }

        if ($LASTEXITCODE -ne 0) {
            Write-OutputColor "  Failed to configure NTP server (exit code $LASTEXITCODE)." -color "Error"
            return
        }

        # Restart time service
        Restart-Service w32time -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        # Force sync
        $null = w32tm /resync /force 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-OutputColor "  NTP configured but time sync failed (exit code $LASTEXITCODE)." -color "Warning"
        }

        Write-OutputColor "  NTP server configured successfully." -color "Success"
        Add-SessionChange -Category "System" -Description "Configured NTP server: $Server"
    }
    catch {
        Write-OutputColor "  Failed to configure NTP: $_" -color "Error"
    }
}

function Show-DetailedTimeStatus {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  DETAILED TIME STATUS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $status = w32tm /query /status 2>&1
    foreach ($line in $status) {
        $lineStr = $line.ToString()
        if ($lineStr.Trim()) {
            $displayLine = if ($lineStr.Length -gt 68) { $lineStr.Substring(0,65) + "..." } else { $lineStr }
            Write-OutputColor "  │$("  $displayLine".PadRight(72))│" -color "Info"
        }
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-PressEnter
}
#endregion