#region ===== NETWORK ADAPTER FUNCTIONS =====
function Select-PhysicalAdapters {
    while ($true) {
        Clear-Host
        Write-CenteredOutput "Select Physical Adapters" -color "Info"

        # Show ALL physical adapters (up and down) for SET selection
        $adapters = Get-NetAdapter | Where-Object {
            $_.Name -notlike "vEthernet*" -and
            $_.InterfaceDescription -notlike "*Hyper-V*" -and
            $_.InterfaceDescription -notlike "*Virtual*"
        }

        if ($null -eq $adapters -or @($adapters).Count -eq 0) {
            Write-OutputColor "No physical adapters found." -color "Error"
            return $null
        }

        # Calculate dynamic column widths
        $columnWidths = @{
            Index = [Math]::Max(5, ($adapters.InterfaceIndex | ForEach-Object { $_.ToString().Length } | Measure-Object -Maximum).Maximum)
            Name = [Math]::Max(12, ($adapters.Name | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum)
            Description = [Math]::Max(15, ($adapters.InterfaceDescription | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum)
            Status = 8
        }

        Show-AdaptersTable -adapters $adapters -columnWidths $columnWidths

        Write-OutputColor "Enter adapter index numbers separated by commas (e.g., 1,2) or type 'all' for all adapters:" -color "Warning"
        Write-OutputColor "(Type 'R' to refresh, 'back' to cancel)" -color "Debug"
        $selection = Read-Host

        # Check for refresh
        if ($selection -match '^[Rr]$' -or $selection -eq 'refresh') {
            continue
        }

        # Check for navigation commands
        $navResult = Test-NavigationCommand -UserInput $selection
        if ($navResult.ShouldReturn) {
            return $null
        }

        if ([string]::IsNullOrWhiteSpace($selection)) {
            return $null
        }

        if ($selection -match '^(all|a)$') {
            return $adapters
        }

        $selectedIndexes = $selection -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
        $selectedAdapters = $adapters | Where-Object { $_.InterfaceIndex -in $selectedIndexes }

        if ($null -eq $selectedAdapters -or @($selectedAdapters).Count -eq 0) {
            Write-OutputColor "No valid adapters selected." -color "Error"
            Start-Sleep -Seconds 1
            continue
        }

        return $selectedAdapters
    }
}

# Function to select a host network adapter (vEthernet adapters)
function Select-Host-Network-Adapter {
    while ($true) {
        Clear-Host
        Write-CenteredOutput "Select Host Network Adapter" -color "Info"

        # Show ALL vEthernet adapters (up and down)
        $adapters = Get-NetAdapter | Where-Object { $_.Name -like "vEthernet*" }

        if ($null -eq $adapters -or @($adapters).Count -eq 0) {
            Write-OutputColor "No virtual adapters found. Please create a Switch Embedded Team first." -color "Error"
            return $null
        }

        # Calculate dynamic column widths
        $columnWidths = @{
            Index = [Math]::Max(5, ($adapters.InterfaceIndex | ForEach-Object { $_.ToString().Length } | Measure-Object -Maximum).Maximum)
            Name = [Math]::Max(12, ($adapters.Name | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum)
            Description = [Math]::Max(15, ($adapters.InterfaceDescription | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum)
            Status = 8
        }

        Show-AdaptersTable -adapters $adapters -columnWidths $columnWidths

        Write-OutputColor "Enter adapter Index, or 'R' to refresh, 'B' to go back:" -color "Warning"
        $selection = Read-Host

        # Check for refresh
        if ($selection -eq 'R' -or $selection -eq 'r' -or $selection -eq 'refresh') {
            continue
        }

        # Check for back
        if ($selection -eq 'B' -or $selection -eq 'b' -or $selection -eq 'back') {
            return $null
        }

        if ([string]::IsNullOrWhiteSpace($selection)) {
            return $null
        }

        if ($selection -notmatch '^\d+$') {
            Write-OutputColor "Invalid selection. Press Enter to try again..." -color "Error"
            Read-Host
            continue
        }

        $selectedAdapter = $adapters | Where-Object { $_.InterfaceIndex -eq [int]$selection }

        if ($null -eq $selectedAdapter) {
            Write-OutputColor "Invalid selection. Press Enter to try again..." -color "Error"
            Read-Host
            continue
        }

        return $selectedAdapter.Name
    }
}

# Function to select a VM network adapter (non-vEthernet adapters)
function Select-VM-Network-Adapter {
    while ($true) {
        Clear-Host
        Write-CenteredOutput "Select VM Network Adapter" -color "Info"

        # Show ALL non-vEthernet adapters (up and down)
        $adapters = Get-NetAdapter | Where-Object { $_.Name -notlike "vEthernet*" }

        if ($null -eq $adapters -or @($adapters).Count -eq 0) {
            Write-OutputColor "No network adapters found." -color "Error"
            return $null
        }

        # Calculate dynamic column widths
        $columnWidths = @{
            Index = [Math]::Max(5, ($adapters.InterfaceIndex | ForEach-Object { $_.ToString().Length } | Measure-Object -Maximum).Maximum)
            Name = [Math]::Max(12, ($adapters.Name | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum)
            Description = [Math]::Max(15, ($adapters.InterfaceDescription | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum)
            Status = 8
        }

        Show-AdaptersTable -adapters $adapters -columnWidths $columnWidths

        Write-OutputColor "Enter adapter Index, or 'R' to refresh, 'B' to go back:" -color "Warning"
        $selection = Read-Host

        # Check for refresh
        if ($selection -eq 'R' -or $selection -eq 'r' -or $selection -eq 'refresh') {
            continue
        }

        # Check for back
        if ($selection -eq 'B' -or $selection -eq 'b' -or $selection -eq 'back') {
            return $null
        }

        if ([string]::IsNullOrWhiteSpace($selection)) {
            return $null
        }

        if ($selection -notmatch '^\d+$') {
            Write-OutputColor "Invalid selection. Press Enter to try again..." -color "Error"
            Read-Host
            continue
        }

        $selectedAdapter = $adapters | Where-Object { $_.InterfaceIndex -eq [int]$selection }

        if ($null -eq $selectedAdapter) {
            Write-OutputColor "Invalid selection. Press Enter to try again..." -color "Error"
            Read-Host
            continue
        }

        return $selectedAdapter.Name
    }
}

# Function to select iSCSI adapters (shows all adapters including down)
function Select-iSCSI-Adapters {
    while ($true) {
        Clear-Host
        Write-CenteredOutput "Select iSCSI Adapters" -color "Info"

        # Show ALL physical adapters regardless of status (up and down)
        $adapters = Get-NetAdapter | Where-Object {
            $_.Name -notlike "vEthernet*" -and
            $_.InterfaceDescription -notlike "*Hyper-V*"
        }

        if ($null -eq $adapters -or @($adapters).Count -eq 0) {
            Write-OutputColor "No adapters found for iSCSI configuration." -color "Error"
            return $null
        }

        # Calculate dynamic column widths
        $columnWidths = @{
            Index = [Math]::Max(5, ($adapters.InterfaceIndex | ForEach-Object { $_.ToString().Length } | Measure-Object -Maximum).Maximum)
            Name = [Math]::Max(12, ($adapters.Name | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum)
            Description = [Math]::Max(15, ($adapters.InterfaceDescription | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum)
            Status = 8
        }

        Show-AdaptersTable -adapters $adapters -columnWidths $columnWidths

        Write-OutputColor "Enter adapter index numbers for iSCSI (comma-separated, e.g., 1,2):" -color "Warning"
        Write-OutputColor "(Type 'R' to refresh, 'back' to cancel)" -color "Debug"
        $selection = Read-Host

        # Check for refresh
        if ($selection -match '^[Rr]$' -or $selection -eq 'refresh') {
            continue
        }

        # Check for navigation commands
        $navResult = Test-NavigationCommand -UserInput $selection
        if ($navResult.ShouldReturn) {
            return $null
        }

        if ([string]::IsNullOrWhiteSpace($selection)) {
            return $null
        }

        $selectedIndexes = $selection -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
        $selectedAdapters = $adapters | Where-Object { $_.InterfaceIndex -in $selectedIndexes }

        if ($null -eq $selectedAdapters -or @($selectedAdapters).Count -eq 0) {
            Write-OutputColor "No valid adapters selected." -color "Error"
            Start-Sleep -Seconds 1
            continue
        }

        return $selectedAdapters
    }
}

# Function to format link speed for display
function Format-LinkSpeed {
    param (
        [Parameter(Mandatory=$true)]
        $SpeedBps
    )

    if ($null -eq $SpeedBps -or $SpeedBps -eq 0 -or $SpeedBps -eq "") {
        return "N/A"
    }

    try {
        # Convert from bps to readable format
        $speed = [decimal]$SpeedBps

        if ($speed -ge 1000000000000) {
            return "{0:N0} Tbps" -f ($speed / 1000000000000)
        }
        elseif ($speed -ge 1000000000) {
            return "{0:N0} Gbps" -f ($speed / 1000000000)
        }
        elseif ($speed -ge 1000000) {
            return "{0:N0} Mbps" -f ($speed / 1000000)
        }
        elseif ($speed -ge 1000) {
            return "{0:N0} Kbps" -f ($speed / 1000)
        }
        else {
            return "{0:N0} bps" -f $speed
        }
    }
    catch {
        return "N/A"
    }
}

# Function to display adapters in a formatted table
function Show-AdaptersTable {
    param (
        [Parameter(Mandatory=$true)]
        $adapters,
        [Parameter(Mandatory=$true)]
        [hashtable]$columnWidths
    )

    # Add Speed column width and widen Status for "Disconnected"
    $speedWidth = 10
    $statusWidth = 12  # Wide enough for "Disconnected"
    $totalWidth = $columnWidths.Index + $columnWidths.Name + $columnWidths.Description + $statusWidth + $speedWidth + 16
    $separator = "-" * $totalWidth

    $headerFormat = "| {0,-$($columnWidths.Index)} | {1,-$($columnWidths.Name)} | {2,-$($columnWidths.Description)} | {3,-$($statusWidth)} | {4,-$($speedWidth)} |"

    Write-OutputColor $separator -color "Info"
    Write-OutputColor ($headerFormat -f "Index", "Name", "Description", "Status", "Speed") -color "Info"
    Write-OutputColor $separator -color "Info"

    foreach ($adapter in $adapters) {
        $desc = $adapter.InterfaceDescription
        if ($desc.Length -gt $columnWidths.Description) {
            $desc = $desc.Substring(0, $columnWidths.Description - 3) + "..."
        }

        # Get link speed - use Speed property (in bps), not LinkSpeed
        $speedValue = $adapter.Speed
        if ($adapter.Status -ne "Up") {
            $speed = "N/A"
        }
        else {
            $speed = Format-LinkSpeed -SpeedBps $speedValue
        }

        # Color based on status
        $statusColor = switch ($adapter.Status) {
            "Up" { "Success" }
            "Down" { "Error" }
            "Disabled" { "Error" }
            default { "Warning" }
        }

        Write-OutputColor ($headerFormat -f $adapter.InterfaceIndex, $adapter.Name, $desc, $adapter.Status, $speed) -color $statusColor
    }

    Write-OutputColor $separator -color "Info"
}

# Function to show current adapter status after configuration
function Show-AdapterStatus {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$AdapterName
    )

    Write-OutputColor "`n--- Updated Configuration ---" -color "Info"

    $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue
    if (-not $adapter) {
        Write-OutputColor "Could not retrieve adapter status." -color "Warning"
        return
    }

    Write-OutputColor "Adapter: $AdapterName" -color "Info"
    Write-OutputColor "Status: $($adapter.Status)" -color $(if ($adapter.Status -eq "Up") { "Success" } else { "Warning" })

    $ipConfig = Get-NetIPAddress -InterfaceAlias $AdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ipConfig) {
        Write-OutputColor "IPv4: $($ipConfig.IPAddress)/$($ipConfig.PrefixLength)" -color "Success"
    }

    $gateway = Get-NetRoute -InterfaceAlias $AdapterName -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
    if ($gateway) {
        Write-OutputColor "Gateway: $($gateway.NextHop)" -color "Success"
    }

    $dns = Get-DnsClientServerAddress -InterfaceAlias $AdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($dns -and $dns.ServerAddresses) {
        Write-OutputColor "DNS: $($dns.ServerAddresses -join ', ')" -color "Success"
    }

    Write-OutputColor "-----------------------------" -color "Info"
}
#endregion