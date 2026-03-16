#region ===== FIREWALL CONFIGURATION =====
# Function to configure Windows Firewall
function Disable-WindowsFirewallDomainPrivate {
    Clear-Host
    Write-CenteredOutput "Windows Firewall" -color "Info"

    # Get current status
    $profiles = @("Domain", "Private", "Public")

    Write-OutputColor "  Current firewall status:" -color "Info"
    foreach ($fwProfile in $profiles) {
        $state = (Get-NetFirewallProfile -Profile $fwProfile -ErrorAction SilentlyContinue).Enabled
        $isEnabled = ($state -eq $true)
        $stateText = if ($isEnabled) { "Enabled" } else { "Disabled" }
        $color = switch ($fwProfile) {
            "Public" { if ($isEnabled) { "Success" } else { "Warning" } }
            default { if ($isEnabled) { "Warning" } else { "Success" } }
        }
        Write-OutputColor "  $fwProfile : $stateText" -color $color
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [1] Apply recommended (Domain=Off, Private=Off, Public=On)" -color "Success"
    Write-OutputColor "  [2] Toggle individual profile" -color "Info"
    Write-OutputColor "  [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    # Capture previous state for undo
    $previousStates = @{}
    foreach ($fwProfile in $profiles) {
        $previousStates[$fwProfile] = (Get-NetFirewallProfile -Profile $fwProfile -ErrorAction SilentlyContinue).Enabled -eq $true
    }

    switch ($choice) {
        "1" {
            if (-not (Confirm-UserAction -Message "Apply recommended firewall configuration?")) {
                Write-OutputColor "  Firewall configuration cancelled." -color "Info"
                return
            }

            try {
                Set-NetFirewallProfile -Profile Domain -Enabled False -ErrorAction Stop
                Write-OutputColor "  Domain firewall: Disabled" -color "Success"
                Set-NetFirewallProfile -Profile Private -Enabled False -ErrorAction Stop
                Write-OutputColor "  Private firewall: Disabled" -color "Success"
                Set-NetFirewallProfile -Profile Public -Enabled True -ErrorAction Stop
                Write-OutputColor "  Public firewall: Enabled" -color "Success"

                Add-SessionChange -Category "Security" -Description "Configured firewall (Domain/Private disabled, Public enabled)"
                Clear-MenuCache
                # Register undo
                Add-UndoAction -Category "Security" -Description "Firewall: Domain/Private disabled, Public enabled" -UndoScript {
                    param($States)
                    foreach ($p in $States.Keys) {
                        Set-NetFirewallProfile -Profile $p -Enabled $States[$p] -ErrorAction SilentlyContinue
                    }
                }.GetNewClosure() -UndoParams @{ States = $previousStates }
            }
            catch {
                Write-OutputColor "  Failed to configure firewall: $_" -color "Error"
            }
        }
        "2" {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Select profile to toggle:" -color "Info"
            $idx = 1
            foreach ($fwProfile in $profiles) {
                $state = if ($previousStates[$fwProfile]) { "Enabled" } else { "Disabled" }
                Write-OutputColor "  [$idx] $fwProfile (currently: $state)" -color "Info"
                $idx++
            }
            Write-OutputColor "" -color "Info"
            $profileChoice = Read-Host "  Select (1-3)"
            $navResult = Test-NavigationCommand -UserInput $profileChoice
            if ($navResult.ShouldReturn) { return }

            $selectedProfile = switch ($profileChoice) {
                "1" { "Domain" }
                "2" { "Private" }
                "3" { "Public" }
                default { $null }
            }

            if (-not $selectedProfile) {
                Write-OutputColor "  Invalid choice. Enter 1-3." -color "Error"
                return
            }

            $currentState = $previousStates[$selectedProfile]
            $newState = -not $currentState
            $action = if ($newState) { "Enable" } else { "Disable" }

            if (-not (Confirm-UserAction -Message "$action $selectedProfile firewall profile?")) {
                return
            }

            try {
                Set-NetFirewallProfile -Profile $selectedProfile -Enabled $newState -ErrorAction Stop
                $stateText = if ($newState) { "Enabled" } else { "Disabled" }
                Write-OutputColor "  $selectedProfile firewall: $stateText" -color "Success"
                Add-SessionChange -Category "Security" -Description "Firewall $selectedProfile profile: $stateText"
                Clear-MenuCache
                Add-UndoAction -Category "Security" -Description "Firewall $selectedProfile toggled to $stateText" -UndoScript {
                    param($Prof, $OldState)
                    Set-NetFirewallProfile -Profile $Prof -Enabled $OldState -ErrorAction SilentlyContinue
                }.GetNewClosure() -UndoParams @{ Prof = $selectedProfile; OldState = $currentState }
            }
            catch {
                Write-OutputColor "  Failed: $_" -color "Error"
            }
        }
        default { return }
    }
}

# Firewall Rule Search & Browser
function Show-FirewallRuleSearch {
    while ($true) {
        if ($global:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                    FIREWALL RULE SEARCH").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  SEARCH OPTIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  Search by Name"
        Write-MenuItem "[2]  Search by Port"
        Write-MenuItem "[3]  Show All Enabled Inbound Allow Rules"
        Write-MenuItem "[4]  Show All Block Rules"
        Write-MenuItem "[5]  Show Recently Created Rules"
        Write-MenuItem "[6]  Export All Rules to CSV"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        $rules = $null
        $title = ""

        switch ($choice) {
            "1" {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Enter search term (supports wildcards: *sql*, *rdp*):" -color "Info"
                $searchTerm = Read-Host "  Search"
                $navResult = Test-NavigationCommand -UserInput $searchTerm
                if ($navResult.ShouldReturn) { return }
                if ([string]::IsNullOrWhiteSpace($searchTerm)) { continue }
                if ($searchTerm -notlike "*`**") { $searchTerm = "*$searchTerm*" }
                $title = "Rules matching '$searchTerm'"
                try {
                    $rules = @(Get-NetFirewallRule -DisplayName $searchTerm -ErrorAction Stop)
                } catch {
                    if ($_.Exception.Message -like "*No MSFT_NetFirewallRule*" -or $_.Exception.Message -like "*No matching*") {
                        $rules = @()
                    } else {
                        Write-OutputColor "  Search failed: $_" -color "Error"
                        Write-PressEnter
                        continue
                    }
                }
            }
            "2" {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Enter port number (e.g., 443, 3389, 5985):" -color "Info"
                $portStr = Read-Host "  Port"
                $navResult = Test-NavigationCommand -UserInput $portStr
                if ($navResult.ShouldReturn) { return }
                if ($portStr -notmatch '^\d+$' -or [int]$portStr -lt 1 -or [int]$portStr -gt 65535) {
                    Write-OutputColor "  Invalid port number. Enter 1-65535." -color "Error"
                    Start-Sleep -Seconds 1
                    continue
                }
                $title = "Rules for port $portStr"
                try {
                    $portFilters = @(Get-NetFirewallPortFilter -ErrorAction Stop | Where-Object {
                        $_.LocalPort -eq $portStr -or $_.RemotePort -eq $portStr
                    })
                    if ($portFilters.Count -gt 0) {
                        $ruleIds = @($portFilters | ForEach-Object { $_.InstanceID })
                        $rules = @(Get-NetFirewallRule -ErrorAction Stop | Where-Object { $_.InstanceID -in $ruleIds })
                    } else {
                        $rules = @()
                    }
                } catch {
                    Write-OutputColor "  Search failed: $_" -color "Error"
                    Write-PressEnter
                    continue
                }
            }
            "3" {
                $title = "Enabled Inbound Allow Rules"
                try {
                    $rules = @(Get-NetFirewallRule -Direction Inbound -Action Allow -Enabled True -ErrorAction Stop)
                } catch {
                    Write-OutputColor "  Query failed: $_" -color "Error"
                    Write-PressEnter
                    continue
                }
            }
            "4" {
                $title = "Block Rules (All)"
                try {
                    $rules = @(Get-NetFirewallRule -Action Block -ErrorAction Stop)
                } catch {
                    Write-OutputColor "  Query failed: $_" -color "Error"
                    Write-PressEnter
                    continue
                }
            }
            "5" {
                $title = "Custom / Recently Created Rules"
                try {
                    $allRules = @(Get-NetFirewallRule -ErrorAction Stop)
                    # Non-default rules (no Microsoft group, or user-created)
                    $rules = @($allRules | Where-Object {
                        [string]::IsNullOrEmpty($_.DisplayGroup) -or $_.DisplayGroup -notlike "@*"
                    })
                } catch {
                    Write-OutputColor "  Query failed: $_" -color "Error"
                    Write-PressEnter
                    continue
                }
            }
            "6" {
                Export-FirewallRuleAudit
                Write-PressEnter
                continue
            }
            default { continue }
        }

        # Display results
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        $titleLine = "  $title ($(@($rules).Count) results)"
        if ($titleLine.Length -gt 72) { $titleLine = $titleLine.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($titleLine.PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        if ($null -eq $rules -or @($rules).Count -eq 0) {
            Write-OutputColor "  │$("  No matching rules found.".PadRight(72))│" -color "Info"
        } else {
            $displayRules = @($rules) | Sort-Object DisplayName | Select-Object -First 40
            foreach ($rule in $displayRules) {
                $dir = if ($rule.Direction -eq "Inbound") { "IN " } else { "OUT" }
                $act = if ($rule.Action -eq "Allow") { "ALLOW" } else { "BLOCK" }
                $ena = if ($rule.Enabled -eq $true) { "" } else { " [OFF]" }
                $actColor = if ($rule.Action -eq "Allow") { "Success" } else { "Warning" }
                $name = $rule.DisplayName
                if ($name.Length -gt 46) { $name = $name.Substring(0, 43) + "..." }
                $line = "  $dir $($act.PadRight(6)) $name$ena"
                if ($line.Length -gt 72) { $line = $line.Substring(0, 72) }
                Write-OutputColor "  │$($line.PadRight(72))│" -color $actColor
            }
            if (@($rules).Count -gt 40) {
                $moreLine = "  ... and $(@($rules).Count - 40) more rules"
                if ($moreLine.Length -gt 72) { $moreLine = $moreLine.Substring(0, 69) + "..." }
                Write-OutputColor "  │$($moreLine.PadRight(72))│" -color "Info"
            }
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

        Add-SessionChange -Category "Security" -Description "Searched firewall rules: $title"
        Clear-MenuCache
        Write-PressEnter
    }
}

# Firewall Rule Audit Export
function Export-FirewallRuleAudit {
    param(
        [string]$OutputPath
    )

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = Join-Path $script:TempPath "firewall-audit-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
    }

    Write-OutputColor "`n  Exporting firewall rules..." -color "Info"

    try {
        $rules = Get-NetFirewallRule -ErrorAction Stop

        $export = @()
        foreach ($rule in $rules) {
            $portFilter = $rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
            $addrFilter = $rule | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue

            $export += [PSCustomObject]@{
                Name          = $rule.Name
                DisplayName   = $rule.DisplayName
                Direction     = $rule.Direction.ToString()
                Action        = $rule.Action.ToString()
                Enabled       = $rule.Enabled.ToString()
                Profile       = $rule.Profile.ToString()
                Protocol      = if ($null -ne $portFilter) { $portFilter.Protocol } else { 'Any' }
                LocalPort     = if ($null -ne $portFilter) { $portFilter.LocalPort -join ',' } else { 'Any' }
                RemoteAddress = if ($null -ne $addrFilter) { $addrFilter.RemoteAddress -join ',' } else { 'Any' }
            }
        }

        $export | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8

        $enabledCount = @($rules | Where-Object { $_.Enabled -eq $true }).Count
        $totalCount = @($rules).Count
        Write-OutputColor "  Exported $totalCount rules ($enabledCount enabled) to:" -color "Success"
        Write-OutputColor "  $OutputPath" -color "Info"
        Add-SessionChange -Category "Security" -Description "Exported firewall rules to CSV"
        Clear-MenuCache
    } catch {
        Write-OutputColor "  Failed to export: $($_.Exception.Message)" -color "Error"
    }
}
#endregion