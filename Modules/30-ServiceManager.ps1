#region ===== SERVICE MANAGER =====
# Function to manage Windows services
function Show-ServiceManager {
    while ($true) {
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                        SERVICE MANAGER").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        # Key services to monitor
        $keyServices = @(
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
        )

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  KEY SERVICES STATUS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        $idx = 1
        $serviceList = @()
        foreach ($svc in $keyServices) {
            $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
            if ($service) {
                $status = $service.Status
                $color = if ($status -eq "Running") { "Success" } elseif ($status -eq "Stopped") { "Warning" } else { "Info" }
                $displayName = if ($svc.DisplayName.Length -gt 45) { $svc.DisplayName.Substring(0,42) + "..." } else { $svc.DisplayName }
                Write-OutputColor "  │$("  [$idx] $displayName : $status".PadRight(72))│" -color $color
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
        Write-MenuItem -Text "[A]  Search All Services"
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
                if ($num -match '^\d+$' -and [int]$num -ge 1 -and [int]$num -le $serviceList.Count) {
                    $svc = $serviceList[[int]$num - 1]
                    try {
                        Start-Service -Name $svc.Name -ErrorAction Stop
                        Write-OutputColor "  Started $($svc.DisplayName)" -color "Success"
                        Add-SessionChange -Category "System" -Description "Started service: $($svc.Name)"
                    }
                    catch {
                        Write-OutputColor "  Failed: $_" -color "Error"
                    }
                }
            }
            "^[Tt]$" {
                $num = Read-Host "  Enter service number to stop"
                if ($num -match '^\d+$' -and [int]$num -ge 1 -and [int]$num -le $serviceList.Count) {
                    $svc = $serviceList[[int]$num - 1]
                    if (-not (Confirm-UserAction -Message "Stop service '$($svc.DisplayName)'?")) { continue }
                    try {
                        Stop-Service -Name $svc.Name -Force -ErrorAction Stop
                        Write-OutputColor "  Stopped $($svc.DisplayName)" -color "Success"
                        Add-SessionChange -Category "System" -Description "Stopped service: $($svc.Name)"
                    }
                    catch {
                        Write-OutputColor "  Failed: $_" -color "Error"
                    }
                }
            }
            "^[Rr]$" {
                $num = Read-Host "  Enter service number to restart"
                if ($num -match '^\d+$' -and [int]$num -ge 1 -and [int]$num -le $serviceList.Count) {
                    $svc = $serviceList[[int]$num - 1]
                    if (-not (Confirm-UserAction -Message "Restart service '$($svc.DisplayName)'?")) { continue }
                    try {
                        Restart-Service -Name $svc.Name -Force -ErrorAction Stop
                        Write-OutputColor "  Restarted $($svc.DisplayName)" -color "Success"
                        Add-SessionChange -Category "System" -Description "Restarted service: $($svc.Name)"
                    }
                    catch {
                        Write-OutputColor "  Failed: $_" -color "Error"
                    }
                }
            }
            "^[Aa]$" {
                $search = Read-Host "  Enter service name to search"
                if ($search) {
                    $found = Get-Service | Where-Object { $_.Name -like "*$search*" -or $_.DisplayName -like "*$search*" } | Select-Object -First 10
                    if ($found) {
                        Write-OutputColor "" -color "Info"
                        foreach ($s in $found) {
                            $color = if ($s.Status -eq "Running") { "Success" } else { "Warning" }
                            Write-OutputColor "  $($s.Name) - $($s.DisplayName) : $($s.Status)" -color $color
                        }
                    }
                    else {
                        Write-OutputColor "  No services found matching '$search'" -color "Warning"
                    }
                }
            }
            "^[Bb]$" { return }
        }

        Write-PressEnter
    }
}
#endregion