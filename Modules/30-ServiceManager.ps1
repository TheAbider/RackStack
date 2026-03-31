#region ===== SERVICE MANAGER =====
# Function to show service dependency tree
function Show-ServiceDependencies {
    param([string]$ServiceName)

    if ([string]::IsNullOrWhiteSpace($ServiceName)) {
        Write-OutputColor "  Enter service name:" -color "Info"
        $ServiceName = Read-Host "  Service"
        $navResult = Test-NavigationCommand -UserInput $ServiceName
        if ($navResult.ShouldReturn) { return }
    }

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($null -eq $service) {
        $service = Get-Service -DisplayName "*$ServiceName*" -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($null -eq $service) {
        Write-OutputColor "  Service '$ServiceName' not found" -color "Warning"
        return
    }

    Write-OutputColor "`n  Service: $($service.DisplayName) ($($service.Name))" -color "Info"
    Write-OutputColor "  Status: $($service.Status)" -color $(if ($service.Status -eq 'Running') { "Success" } else { "Warning" })

    # Dependencies (services this service depends ON)
    $deps = @($service.ServicesDependedOn)
    if ($deps.Count -gt 0) {
        Write-OutputColor "`n  Depends on ($($deps.Count)):" -color "Info"
        foreach ($dep in $deps) {
            $depStatus = $dep.Status.ToString()
            $color = if ($depStatus -eq 'Running') { "Success" } else { "Error" }
            Write-OutputColor "    -> $($dep.DisplayName) ($depStatus)" -color $color
        }
    }

    # Dependents (services that depend on THIS service)
    $dependents = @($service.DependentServices)
    if ($dependents.Count -gt 0) {
        Write-OutputColor "`n  Required by ($($dependents.Count)):" -color "Info"
        foreach ($dep in $dependents) {
            $depStatus = $dep.Status.ToString()
            $color = if ($depStatus -eq 'Running') { "Success" } else { "Warning" }
            Write-OutputColor "    <- $($dep.DisplayName) ($depStatus)" -color $color
        }
    }

    if ($deps.Count -eq 0 -and $dependents.Count -eq 0) {
        Write-OutputColor "  No dependencies" -color "Info"
    }
}

# Function to manage Windows services
function Show-ServiceManager {
    while ($true) {
        if ($global:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                        SERVICE MANAGER").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        # Key services to monitor (configurable via defaults.json)
        $keyServices = if ($script:Defaults.MonitoredServices) {
            $script:Defaults.MonitoredServices
        } else {
            @(
                @{ Name = "vmms"; DisplayName = "Hyper-V Virtual Machine Management" }
                @{ Name = "vmcompute"; DisplayName = "Hyper-V Host Compute Service" }
                @{ Name = "ClusSvc"; DisplayName = "Cluster Service" }
                @{ Name = "MSiSCSI"; DisplayName = "Microsoft iSCSI Initiator Service" }
                @{ Name = "WinRM"; DisplayName = "Windows Remote Management" }
                @{ Name = "DNS"; DisplayName = "DNS Client" }
                @{ Name = "DHCP"; DisplayName = "DHCP Client" }
                @{ Name = "wuauserv"; DisplayName = "Windows Update" }
                @{ Name = "Spooler"; DisplayName = "Print Spooler" }
                @{ Name = "W32Time"; DisplayName = "Windows Time" }
                @{ Name = "LanmanServer"; DisplayName = "Server (SMB)" }
                @{ Name = "LanmanWorkstation"; DisplayName = "Workstation (SMB Client)" }
                @{ Name = "EventLog"; DisplayName = "Windows Event Log" }
                @{ Name = "Netlogon"; DisplayName = "Netlogon" }
                @{ Name = "NTDS"; DisplayName = "Active Directory Domain Services" }
            )
        }

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  KEY SERVICES STATUS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        $idx = 1
        $serviceList = @()
        foreach ($svc in $keyServices) {
            $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
            if ($service) {
                $status = $service.Status
                $startType = $service.StartType
                $startTag = switch ($startType) {
                    "Automatic" { "Auto" }
                    "Manual"    { "Manual" }
                    "Disabled"  { "Disabled" }
                    default     { $startType }
                }
                # Color logic: Running+Auto=green, Stopped+Auto=red (misconfigured), Stopped+Manual=yellow, Disabled=gray
                $color = if ($status -eq "Running") {
                    "Success"
                } elseif ($status -eq "Stopped" -and $startType -eq "Automatic") {
                    "Error"
                } elseif ($startType -eq "Disabled") {
                    "Info"
                } else {
                    "Warning"
                }
                $dn = if ($service.DisplayName) { $service.DisplayName } elseif ($svc.DisplayName) { $svc.DisplayName } else { $svc.Name }
                $displayName = if ($dn.Length -gt 35) { $dn.Substring(0,32) + "..." } else { $dn }
                $svcLine = "  [$idx] $displayName : $status [$startTag]"
                if ($svcLine.Length -gt 72) { $svcLine = $svcLine.Substring(0, 69) + "..." }
                Write-OutputColor "  │$($svcLine.PadRight(72))│" -color $color
                $serviceList += $service
                $idx++
            }
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  OPTIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem -Text "[S]  Start a Service (enter number)"
        Write-MenuItem -Text "[T]  Stop a Service (enter number)"
        Write-MenuItem -Text "[R]  Restart a Service (enter number)"
        Write-MenuItem -Text "[C]  Change Startup Type (enter number)"
        Write-MenuItem -Text "[A]  Search All Services"
        Write-MenuItem -Text "[E]  Show Failed Services (Auto + Stopped)"
        Write-MenuItem -Text "[D]  View Service Dependencies"
        Write-MenuItem -Text "[F]  Find Service Dependencies (by name)"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch -Regex ($choice) {
            "^[Ss]$" {
                $num = Read-Host "  Enter service number to start"
                $navResult = Test-NavigationCommand -UserInput $num
                if ($navResult.ShouldReturn) { return }
                if ($num -match '^\d+$' -and [int]$num -ge 1 -and [int]$num -le $serviceList.Count) {
                    $svc = $serviceList[[int]$num - 1]
                    try {
                        $prevStatus = $svc.Status
                        Start-Service -Name $svc.Name -ErrorAction Stop
                        Write-OutputColor "  Started $($svc.DisplayName)" -color "Success"
                        Add-SessionChange -Category "System" -Description "Started service: $($svc.Name)"
                        Clear-MenuCache
                        if ($prevStatus -eq 'Stopped') {
                            Add-UndoAction -Category "System" -Description "Started service: $($svc.Name)" -UndoScript {
                                param($SvcName)
                                Stop-Service -Name $SvcName -Force -ErrorAction SilentlyContinue
                            }.GetNewClosure() -UndoParams @{ SvcName = $svc.Name }
                        }
                    }
                    catch {
                        Write-OutputColor "  Failed: $_" -color "Error"
                    }
                }
                else {
                    Write-OutputColor "  Invalid selection. Enter 1-$($serviceList.Count)." -color "Error"
                }
            }
            "^[Tt]$" {
                $num = Read-Host "  Enter service number to stop"
                $navResult = Test-NavigationCommand -UserInput $num
                if ($navResult.ShouldReturn) { return }
                if ($num -match '^\d+$' -and [int]$num -ge 1 -and [int]$num -le $serviceList.Count) {
                    $svc = $serviceList[[int]$num - 1]
                    # Warn about critical services
                    $criticalServices = @('NTDS', 'DNS', 'DFSR', 'LanmanServer', 'W32Time', 'ClusSvc', 'vmms', 'wuauserv')
                    if ($svc.Name -in $criticalServices) {
                        Write-OutputColor "" -color "Info"
                        Write-OutputColor "  *** CRITICAL SERVICE ***" -color "Error"
                        Write-OutputColor "  '$($svc.DisplayName)' is a critical infrastructure service." -color "Error"
                        Write-OutputColor "  Stopping it may cause service outages or cluster failovers." -color "Error"
                    }

                    # Warn about dependent services
                    $dependents = @(Get-Service -Name $svc.Name -DependentServices -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' })
                    if ($dependents.Count -gt 0) {
                        Write-OutputColor "" -color "Info"
                        Write-OutputColor "  WARNING: $($dependents.Count) running service(s) depend on $($svc.DisplayName):" -color "Warning"
                        foreach ($dep in $dependents) {
                            Write-OutputColor "    - $($dep.DisplayName) ($($dep.Name))" -color "Warning"
                        }
                        Write-OutputColor "  These will also be stopped." -color "Warning"
                        Write-OutputColor "" -color "Info"
                    }
                    if (-not (Confirm-UserAction -Message "Stop service '$($svc.DisplayName)'?")) { continue }
                    try {
                        Stop-Service -Name $svc.Name -Force -ErrorAction Stop
                        Write-OutputColor "  Stopped $($svc.DisplayName)" -color "Success"
                        Add-SessionChange -Category "System" -Description "Stopped service: $($svc.Name)"
                        Clear-MenuCache
                        Add-UndoAction -Category "System" -Description "Stopped service: $($svc.Name)" -UndoScript {
                            param($SvcName)
                            Start-Service -Name $SvcName -ErrorAction SilentlyContinue
                        }.GetNewClosure() -UndoParams @{ SvcName = $svc.Name }
                    }
                    catch {
                        Write-OutputColor "  Failed: $_" -color "Error"
                    }
                }
                else {
                    Write-OutputColor "  Invalid selection. Enter 1-$($serviceList.Count)." -color "Error"
                }
            }
            "^[Rr]$" {
                $num = Read-Host "  Enter service number to restart"
                $navResult = Test-NavigationCommand -UserInput $num
                if ($navResult.ShouldReturn) { return }
                if ($num -match '^\d+$' -and [int]$num -ge 1 -and [int]$num -le $serviceList.Count) {
                    $svc = $serviceList[[int]$num - 1]
                    # Warn about dependent services
                    $dependents = @(Get-Service -Name $svc.Name -DependentServices -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' })
                    if ($dependents.Count -gt 0) {
                        Write-OutputColor "" -color "Info"
                        Write-OutputColor "  WARNING: $($dependents.Count) running service(s) depend on $($svc.DisplayName):" -color "Warning"
                        foreach ($dep in $dependents) {
                            Write-OutputColor "    - $($dep.DisplayName) ($($dep.Name))" -color "Warning"
                        }
                        Write-OutputColor "  These will also be restarted." -color "Warning"
                        Write-OutputColor "" -color "Info"
                    }
                    if (-not (Confirm-UserAction -Message "Restart service '$($svc.DisplayName)'?")) { continue }
                    try {
                        Restart-Service -Name $svc.Name -Force -ErrorAction Stop
                        Write-OutputColor "  Restarted $($svc.DisplayName)" -color "Success"
                        Add-SessionChange -Category "System" -Description "Restarted service: $($svc.Name)"
                        Clear-MenuCache
                    }
                    catch {
                        Write-OutputColor "  Failed: $_" -color "Error"
                    }
                }
                else {
                    Write-OutputColor "  Invalid selection. Enter 1-$($serviceList.Count)." -color "Error"
                }
            }
            "^[Cc]$" {
                $num = Read-Host "  Enter service number to change startup type"
                $navResult = Test-NavigationCommand -UserInput $num
                if ($navResult.ShouldReturn) { return }
                if ($num -match '^\d+$' -and [int]$num -ge 1 -and [int]$num -le $serviceList.Count) {
                    $svc = $serviceList[[int]$num - 1]
                    Write-OutputColor "" -color "Info"
                    Write-OutputColor "  Service: $($svc.DisplayName)" -color "Info"
                    Write-OutputColor "  Current Startup: $($svc.StartType)" -color "Info"
                    Write-OutputColor "" -color "Info"
                    Write-OutputColor "  [1] Automatic" -color "Info"
                    Write-OutputColor "  [2] Manual" -color "Info"
                    Write-OutputColor "  [3] Disabled" -color "Info"
                    Write-OutputColor "" -color "Info"
                    $typeChoice = Read-Host "  Select new startup type"
                    $navResult = Test-NavigationCommand -UserInput $typeChoice
                    if ($navResult.ShouldReturn) { return }
                    $newType = switch ($typeChoice) {
                        "1" { "Automatic" }
                        "2" { "Manual" }
                        "3" { "Disabled" }
                        default { $null }
                    }
                    if ($null -ne $newType) {
                        if (-not (Confirm-UserAction -Message "Set '$($svc.DisplayName)' startup to $newType`?")) { continue }
                        try {
                            $prevStartType = $svc.StartType
                            Set-Service -Name $svc.Name -StartupType $newType -ErrorAction Stop
                            Write-OutputColor "  Set $($svc.DisplayName) startup type to $newType" -color "Success"
                            Add-SessionChange -Category "System" -Description "Changed service startup: $($svc.Name) -> $newType"
                            Clear-MenuCache
                            Add-UndoAction -Category "System" -Description "Changed $($svc.Name) startup to $newType" -UndoScript {
                                param($SvcName, $OldType)
                                Set-Service -Name $SvcName -StartupType $OldType -ErrorAction SilentlyContinue
                            }.GetNewClosure() -UndoParams @{ SvcName = $svc.Name; OldType = $prevStartType.ToString() }
                        }
                        catch {
                            Write-OutputColor "  Failed: $_" -color "Error"
                        }
                    }
                }
                else {
                    Write-OutputColor "  Invalid selection. Enter 1-$($serviceList.Count)." -color "Error"
                }
            }
            "^[Aa]$" {
                $search = Read-Host "  Enter service name to search"
                $navResult = Test-NavigationCommand -UserInput $search
                if ($navResult.ShouldReturn) { return }
                if ($search) {
                    $found = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$search*" -or $_.DisplayName -like "*$search*" } | Select-Object -First 10
                    if ($found) {
                        Write-OutputColor "" -color "Info"
                        foreach ($s in $found) {
                            $startTag = switch ($s.StartType) { "Automatic" { "Auto" } "Manual" { "Manual" } "Disabled" { "Disabled" } default { $s.StartType } }
                            $color = if ($s.Status -eq "Running") { "Success" } elseif ($s.Status -eq "Stopped" -and $s.StartType -eq "Automatic") { "Error" } else { "Warning" }
                            Write-OutputColor "  $($s.Name) - $($s.DisplayName) : $($s.Status) [$startTag]" -color $color
                        }
                    }
                    else {
                        Write-OutputColor "  No services found matching '$search'" -color "Warning"
                    }
                }
            }
            "^[Ee]$" {
                $failedSvcs = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -eq 'Stopped' })
                Write-OutputColor "" -color "Info"
                if ($failedSvcs.Count -eq 0) {
                    Write-OutputColor "  All automatic services are running." -color "Success"
                } else {
                    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
                    Write-OutputColor "  │$("  FAILED SERVICES (Automatic + Stopped): $($failedSvcs.Count)".PadRight(72))│" -color "Error"
                    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                    foreach ($fs in $failedSvcs | Sort-Object DisplayName) {
                        $dispName = if ($fs.DisplayName.Length -gt 45) { $fs.DisplayName.Substring(0, 42) + "..." } else { $fs.DisplayName }
                        $fsLine = "  $($fs.Name.PadRight(24)) $dispName"
                        if ($fsLine.Length -gt 72) { $fsLine = $fsLine.Substring(0, 72) }
                        Write-OutputColor "  │$($fsLine.PadRight(72))│" -color "Error"
                    }
                    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
                }
                Write-PressEnter
            }
            "^[Dd]$" {
                $num = Read-Host "  Enter service number to view dependencies"
                $navResult = Test-NavigationCommand -UserInput $num
                if ($navResult.ShouldReturn) { return }
                if ($num -match '^\d+$' -and [int]$num -ge 1 -and [int]$num -le $serviceList.Count) {
                    $svc = $serviceList[[int]$num - 1]
                    Write-OutputColor "" -color "Info"
                    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
                    $treeHeader = "  DEPENDENCY TREE: $($svc.DisplayName)"
                    if ($treeHeader.Length -gt 72) { $treeHeader = $treeHeader.Substring(0, 69) + "..." }
                    Write-OutputColor "  │$($treeHeader.PadRight(72))│" -color "Info"
                    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

                    # Services this one depends on (required by)
                    $requires = @(Get-Service -Name $svc.Name -RequiredServices -ErrorAction SilentlyContinue)
                    if ($requires.Count -gt 0) {
                        $reqHeader = "  DEPENDS ON ($($requires.Count)):"
                        Write-OutputColor "  │$($reqHeader.PadRight(72))│" -color "Info"
                        foreach ($req in $requires) {
                            $reqColor = if ($req.Status -eq "Running") { "Success" } else { "Warning" }
                            $reqLine = "    $($req.DisplayName) ($($req.Name)) - $($req.Status)"
                            if ($reqLine.Length -gt 70) { $reqLine = $reqLine.Substring(0, 67) + "..." }
                            Write-OutputColor "  │$($reqLine.PadRight(72))│" -color $reqColor
                        }
                    } else {
                        Write-OutputColor "  │$("  DEPENDS ON: (none)".PadRight(72))│" -color "Info"
                    }

                    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"

                    # Services that depend on this one
                    $dependents = @(Get-Service -Name $svc.Name -DependentServices -ErrorAction SilentlyContinue)
                    if ($dependents.Count -gt 0) {
                        $depHeader = "  DEPENDED ON BY ($($dependents.Count)):"
                        Write-OutputColor "  │$($depHeader.PadRight(72))│" -color "Info"
                        foreach ($dep in $dependents) {
                            $depColor = if ($dep.Status -eq "Running") { "Success" } else { "Warning" }
                            $depLine = "    $($dep.DisplayName) ($($dep.Name)) - $($dep.Status)"
                            if ($depLine.Length -gt 70) { $depLine = $depLine.Substring(0, 67) + "..." }
                            Write-OutputColor "  │$($depLine.PadRight(72))│" -color $depColor
                        }
                    } else {
                        Write-OutputColor "  │$("  DEPENDED ON BY: (none)".PadRight(72))│" -color "Info"
                    }

                    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
                }
                else {
                    Write-OutputColor "  Invalid selection. Enter 1-$($serviceList.Count)." -color "Error"
                }
            }
            "^[Ff]$" {
                Show-ServiceDependencies
            }
            "^[Bb]$" { return }
        }

        Write-PressEnter
    }
}
#endregion