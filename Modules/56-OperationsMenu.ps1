#region ===== OPERATIONS MENU =====
function Show-OperationsMenu {
    param(
        [string]$ComputerName = $null,
        [System.Management.Automation.PSCredential]$Credential = $null
    )

    while ($true) {
        if ($global:ReturnToMainMenu) { return }

        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                          OPERATIONS").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  VM OPERATIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  VM Checkpoint Management"
        Write-MenuItem "[2]  VM Export / Import"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  CLUSTER OPERATIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[3]  Cluster Dashboard"
        Write-MenuItem "[4]  Cluster Operations (Drain/Resume)"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  REMOTE MANAGEMENT".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[5]  Remote PowerShell Session"
        Write-MenuItem "[6]  Remote Server Health Check"
        Write-MenuItem "[7]  Remote Service Manager"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  REPORTS & TOOLS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[8]  Generate HTML Health Report"
        Write-MenuItem "[9]  Generate HTML Readiness Report"
        Write-MenuItem "[10] Export Profile Comparison (HTML)"
        Write-MenuItem "[11] Network Diagnostics ►"
        Write-MenuItem "[12] Configuration Drift Check"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  [B] ◄ Back to Server Config" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" {
                Show-VMCheckpointManagement -ComputerName $ComputerName -Credential $Credential
            }
            "2" {
                Show-VMExportImportMenu -ComputerName $ComputerName -Credential $Credential
            }
            "3" {
                Show-ClusterDashboard
                Write-PressEnter
            }
            "4" {
                Show-ClusterOperationsMenu
            }
            "5" {
                Invoke-RemotePSSession
            }
            "6" {
                Invoke-RemoteHealthCheck
            }
            "7" {
                Invoke-RemoteServiceManager
            }
            "8" {
                Export-HTMLHealthReport
                Write-PressEnter
            }
            "9" {
                Export-HTMLReadinessReport
                Write-PressEnter
            }
            "10" {
                Export-ProfileComparisonHTML
                Write-PressEnter
            }
            "11" {
                Show-NetworkDiagnostics
            }
            "12" {
                Start-DriftCheck
                Write-PressEnter
            }
            "b" { return }
            "B" { return }
            default {
                Write-OutputColor "  Invalid choice." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

function Invoke-RemotePSSession {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       REMOTE POWERSHELL SESSION").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $target = Read-Host "  Enter remote server name or IP"
    $navResult = Test-NavigationCommand -UserInput $target
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($target)) { return }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Testing connectivity to $target ..." -color "Info"

    $testResult = Test-NetConnection -ComputerName $target -Port 5985 -WarningAction SilentlyContinue
    if (-not $testResult.TcpTestSucceeded) {
        Write-OutputColor "  WinRM port (5985) not reachable on $target" -color "Error"
        Write-OutputColor "  Ensure WinRM is enabled: Enable-PSRemoting -Force" -color "Warning"
        Write-PressEnter
        return
    }

    Write-OutputColor "  WinRM port open. Connecting..." -color "Success"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  NOTE: Type 'exit' to return to this tool." -color "Warning"
    Write-OutputColor "" -color "Info"

    try {
        $useCredential = Read-Host "  Use alternate credentials? [Y/N]"
        if ($useCredential -eq 'Y' -or $useCredential -eq 'y') {
            $cred = Get-Credential -Message "Credentials for $target"
            Enter-PSSession -ComputerName $target -Credential $cred
        } else {
            Enter-PSSession -ComputerName $target
        }
    }
    catch {
        Write-OutputColor "  Connection failed: $($_.Exception.Message)" -color "Error"
        Write-PressEnter
    }
}

function Invoke-RemoteHealthCheck {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       REMOTE SERVER HEALTH CHECK").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $target = Read-Host "  Enter remote server name or IP"
    $navResult = Test-NavigationCommand -UserInput $target
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($target)) { return }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Gathering health data from $target ..." -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $health = Invoke-Command -ComputerName $target -ScriptBlock {
            $os = Get-CimInstance Win32_OperatingSystem
            $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
            $totalMem = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
            $freeMem = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
            $usedMem = $totalMem - $freeMem
            $memPct = [math]::Round(($usedMem / $totalMem) * 100, 1)
            $uptime = (Get-Date) - $os.LastBootUpTime
            $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
                @{
                    Drive = $_.DeviceID
                    SizeGB = [math]::Round($_.Size / 1GB, 1)
                    FreeGB = [math]::Round($_.FreeSpace / 1GB, 1)
                    UsedPct = if ($_.Size -gt 0) { [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1) } else { 0 }
                }
            }
            @{
                Hostname = $env:COMPUTERNAME
                OS = $os.Caption
                CPU = $cpu
                TotalMemGB = $totalMem
                UsedMemGB = $usedMem
                MemPct = $memPct
                Uptime = "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"
                Disks = $disks
            }
        } -ErrorAction Stop

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  REMOTE HEALTH: $($health.Hostname) ($target)".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "  OS:          $($health.OS)"
        Write-MenuItem "  Uptime:      $($health.Uptime)"

        $cpuColor = if ($health.CPU -lt 70) { "Green" } elseif ($health.CPU -lt 90) { "Yellow" } else { "Red" }
        Write-Host "  │  " -NoNewline -ForegroundColor Cyan; Write-Host "  CPU:         $($health.CPU)%".PadRight(70) -NoNewline -ForegroundColor $cpuColor; Write-Host "│" -ForegroundColor Cyan

        $memColor = if ($health.MemPct -lt 70) { "Green" } elseif ($health.MemPct -lt 90) { "Yellow" } else { "Red" }
        Write-Host "  │  " -NoNewline -ForegroundColor Cyan; Write-Host "  Memory:      $($health.UsedMemGB)/$($health.TotalMemGB) GB ($($health.MemPct)%)".PadRight(70) -NoNewline -ForegroundColor $memColor; Write-Host "│" -ForegroundColor Cyan

        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  DISK USAGE".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        foreach ($d in $health.Disks) {
            $diskColor = if ($d.UsedPct -lt 70) { "Green" } elseif ($d.UsedPct -lt 90) { "Yellow" } else { "Red" }
            $diskLine = "  $($d.Drive)  $($d.FreeGB) GB free / $($d.SizeGB) GB ($($d.UsedPct)% used)"
            Write-Host "  │  " -NoNewline -ForegroundColor Cyan; Write-Host $diskLine.PadRight(70) -NoNewline -ForegroundColor $diskColor; Write-Host "│" -ForegroundColor Cyan
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }
    catch {
        Write-OutputColor "  Failed to connect: $($_.Exception.Message)" -color "Error"
        Write-OutputColor "  Ensure WinRM is enabled and you have permissions." -color "Warning"
    }
    Write-PressEnter
}

function Invoke-RemoteServiceManager {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                         REMOTE SERVICE MANAGER").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $target = Read-Host "  Enter remote server name or IP"
    $navResult = Test-NavigationCommand -UserInput $target
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($target)) { return }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Fetching services from $target ..." -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $services = Get-Service -ComputerName $target -ErrorAction Stop |
            Where-Object { $_.Status -eq 'Running' -or $_.StartType -eq 'Automatic' } |
            Sort-Object Status, DisplayName |
            Select-Object -First 40

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  SERVICES: $target".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        $header = "  Status".PadRight(12) + "Name".PadRight(22) + "Display Name"
        Write-Host "  │  " -NoNewline -ForegroundColor Cyan; Write-Host $header.PadRight(70) -NoNewline -ForegroundColor Yellow; Write-Host "│" -ForegroundColor Cyan
        Write-OutputColor "  │$("  $('─' * 70)".PadRight(72))│" -color "Info"

        foreach ($svc in $services) {
            $statusColor = if ($svc.Status -eq 'Running') { "Green" } else { "Red" }
            $displayName = if ($svc.DisplayName.Length -gt 34) { $svc.DisplayName.Substring(0, 31) + "..." } else { $svc.DisplayName }
            $line = "  $($svc.Status.ToString().PadRight(10))$($svc.ServiceName.PadRight(22))$displayName"
            Write-Host "  │  " -NoNewline -ForegroundColor Cyan; Write-Host $line.PadRight(70) -NoNewline -ForegroundColor $statusColor; Write-Host "│" -ForegroundColor Cyan
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

        Write-OutputColor "" -color "Info"
        $svcAction = Read-Host "  Enter service name to start/stop/restart (or B to go back)"
        $navResult = Test-NavigationCommand -UserInput $svcAction
        if ($navResult.ShouldReturn) { return }
        if ([string]::IsNullOrWhiteSpace($svcAction) -or $svcAction -eq 'B' -or $svcAction -eq 'b') { return }

        $action = Read-Host "  Action: [S]tart, [T]op, [R]estart"
        switch ($action) {
            { $_ -eq 'S' -or $_ -eq 's' } {
                try {
                    Get-Service -ComputerName $target -Name $svcAction -ErrorAction Stop | Start-Service -ErrorAction Stop
                    Write-OutputColor "  Service '$svcAction' started." -color "Success"
                }
                catch {
                    Write-OutputColor "  Failed to start service '$svcAction': $($_.Exception.Message)" -color "Error"
                }
            }
            { $_ -eq 'T' -or $_ -eq 't' } {
                try {
                    Get-Service -ComputerName $target -Name $svcAction -ErrorAction Stop | Stop-Service -Force -ErrorAction Stop
                    Write-OutputColor "  Service '$svcAction' stopped." -color "Success"
                }
                catch {
                    Write-OutputColor "  Failed to stop service '$svcAction': $($_.Exception.Message)" -color "Error"
                }
            }
            { $_ -eq 'R' -or $_ -eq 'r' } {
                try {
                    Get-Service -ComputerName $target -Name $svcAction -ErrorAction Stop | Restart-Service -Force -ErrorAction Stop
                    Write-OutputColor "  Service '$svcAction' restarted." -color "Success"
                }
                catch {
                    Write-OutputColor "  Failed to restart service '$svcAction': $($_.Exception.Message)" -color "Error"
                }
            }
        }
    }
    catch {
        Write-OutputColor "  Failed: $($_.Exception.Message)" -color "Error"
    }
    Write-PressEnter
}

# Initialize SAN target pairs from configured iSCSI subnet
function Initialize-SANTargetPairs {
    $sub = $script:iSCSISubnet
    $mappings = $script:SANTargetMappings
    $script:SANTargetPairs = @()
    # Build pairs from consecutive mapping entries (A, B alternating)
    for ($i = 0; $i -lt $mappings.Count - 1; $i += 2) {
        $script:SANTargetPairs += @{
            Index  = [int]($i / 2)
            A      = "$sub.$($mappings[$i].Suffix)"
            B      = "$sub.$($mappings[$i + 1].Suffix)"
            ALabel = $mappings[$i].Label
            BLabel = $mappings[$i + 1].Label
            Labels = "$($mappings[$i].Label)/$($mappings[$i + 1].Label)"
        }
    }
}

# Import environment defaults from defaults.json (merges with built-in generics)
function Import-Defaults {

    # Run first-run wizard if no defaults.json exists (skip in batch mode)
    if (-not (Test-Path $script:DefaultsPath)) {
        $batchConfig = Join-Path $script:ModuleRoot "batch_config.json"
        if (-not (Test-Path $batchConfig)) {
            Show-FirstRunWizard
        }
    }

    # Built-in generic defaults
    $builtinDefaults = @{
        Domain             = ""
        LocalAdminName     = "localadmin"
        LocalAdminFullName = "Local Administrator"
        SwitchName         = "LAN-SET"
        ManagementName     = "Management"
        BackupName         = "Backup"
        DNSPresets         = @{}
        FileServer = @{
            BaseURL      = ""
            ClientId     = ""
            ClientSecret = ""
            ISOsFolder   = "ISOs"
            VHDsFolder   = "VirtualHardDrives"
            AgentFolder  = "Agents"
        }
        iSCSISubnet        = "172.16.1"
        StorageBackendType = "iSCSI"
    }

    # Start with built-in defaults
    $merged = $builtinDefaults.Clone()

    # Merge from file if it exists
    if (Test-Path $script:DefaultsPath) {
        try {
            $fileDefaults = Get-Content $script:DefaultsPath -Raw | ConvertFrom-Json
            foreach ($prop in $fileDefaults.PSObject.Properties) {
                if ($prop.Name -like "_*") { continue }  # Skip metadata fields
                if ($null -ne $prop.Value -and $prop.Value -ne "") {
                    $merged[$prop.Name] = $prop.Value
                }
            }
        }
        catch {
            Write-OutputColor "Warning: Could not read defaults.json: $_" -color "Warning"
        }
    }

    # Apply tool identity from defaults
    if ($merged.ToolName) {
        $script:ToolName = $merged.ToolName
    }
    if ($merged.ToolFullName) {
        $script:ToolFullName = $merged.ToolFullName
    }
    if ($merged.SupportContact) {
        $script:SupportContact = $merged.SupportContact
    }

    # Derive config directory name and re-derive dependent paths
    $script:ConfigDirName = "$($script:ToolName)config".ToLower()
    $script:AppConfigDir = "$env:USERPROFILE\.$($script:ConfigDirName)"
    $script:FavoritesPath = "$script:AppConfigDir\favorites.json"
    $script:HistoryPath = "$script:AppConfigDir\history.json"
    $script:SessionStatePath = "$script:AppConfigDir\session.json"

    # Apply merged values to script variables
    $script:domain = $merged.Domain
    $domain = $merged.Domain
    $script:localadminaccountname = $merged.LocalAdminName
    $localadminaccountname = $merged.LocalAdminName
    $script:FullName = $merged.LocalAdminFullName
    $FullName = $merged.LocalAdminFullName
    $script:SwitchName = $merged.SwitchName
    $SwitchName = $merged.SwitchName
    $script:ManagementName = $merged.ManagementName
    $ManagementName = $merged.ManagementName
    $script:BackupName = $merged.BackupName
    $BackupName = $merged.BackupName
    $script:iSCSISubnet = $merged.iSCSISubnet

    # Override storage backend type
    if ($merged.StorageBackendType -and $merged.StorageBackendType -in $script:ValidStorageBackends) {
        $script:StorageBackendType = $merged.StorageBackendType
    }

    # Override auto-update flag
    if ($null -ne $merged.AutoUpdate) {
        $script:AutoUpdate = [bool]$merged.AutoUpdate
    }

    # Override temp path
    if ($merged.TempPath) {
        $script:TempPath = $merged.TempPath
    }

    # Override SAN target mappings
    if ($merged.SANTargetMappings -and $merged.SANTargetMappings -is [array]) {
        $script:SANTargetMappings = @()
        foreach ($mapping in $merged.SANTargetMappings) {
            if ($mapping -is [PSCustomObject]) {
                $script:SANTargetMappings += @{ Suffix = [int]$mapping.Suffix; Label = $mapping.Label }
            } else {
                $script:SANTargetMappings += $mapping
            }
        }
    }

    # Override Defender exclusion paths
    if ($merged.DefenderExclusionPaths -and $merged.DefenderExclusionPaths -is [array]) {
        $script:DefenderExclusionPaths = @($merged.DefenderExclusionPaths)
    }
    if ($merged.DefenderCommonVMPaths -and $merged.DefenderCommonVMPaths -is [array]) {
        $script:DefenderCommonVMPaths = @($merged.DefenderCommonVMPaths)
    } else {
        # Auto-generate from current host drive if not overridden
        Update-DefenderVMPaths
    }

    # Override storage paths
    if ($merged.StoragePaths) {
        $sp = $merged.StoragePaths
        if ($sp -is [PSCustomObject]) {
            if ($sp.HostVMStoragePath)    { $script:HostVMStoragePath = $sp.HostVMStoragePath }
            if ($sp.HostISOPath)          { $script:HostISOPath = $sp.HostISOPath }
            if ($sp.ClusterISOPath)       { $script:ClusterISOPath = $sp.ClusterISOPath }
            if ($sp.VHDCachePath)         { $script:VHDCachePath = $sp.VHDCachePath }
            if ($sp.ClusterVHDCachePath)  { $script:ClusterVHDCachePath = $sp.ClusterVHDCachePath }
            if ($sp.SelectedHostDrive)    { $script:SelectedHostDrive = $sp.SelectedHostDrive }
        }
    }

    # Override agent installer config
    if ($merged.AgentInstaller) {
        $ai = $merged.AgentInstaller
        if ($ai -is [PSCustomObject]) {
            foreach ($prop in $ai.PSObject.Properties) {
                if ($prop.Name -like '_*') { continue }
                if ($prop.Name -eq 'SuccessExitCodes' -and $prop.Value -is [array]) {
                    $script:AgentInstaller[$prop.Name] = @($prop.Value | ForEach-Object { [int]$_ })
                }
                elseif ($prop.Name -eq 'InstallPaths' -and $prop.Value -is [array]) {
                    $script:AgentInstaller[$prop.Name] = @($prop.Value)
                }
                elseif ($prop.Name -eq 'TimeoutSeconds') {
                    $script:AgentInstaller[$prop.Name] = [int]$prop.Value
                }
                else {
                    $script:AgentInstaller[$prop.Name] = $prop.Value
                }
            }
        }
    }

    # Merge custom DNS presets into the built-in presets
    $customDNS = $merged.DNSPresets
    if ($customDNS) {
        if ($customDNS -is [PSCustomObject]) {
            foreach ($prop in $customDNS.PSObject.Properties) {
                $script:DNSPresets[$prop.Name] = @($prop.Value)
            }
        }
        elseif ($customDNS -is [hashtable]) {
            foreach ($key in $customDNS.Keys) {
                $script:DNSPresets[$key] = @($customDNS[$key])
            }
        }
    }

    # Update FileServer settings
    $acCloud = $merged.FileServer
    if ($acCloud) {
        if ($acCloud -is [PSCustomObject]) {
            foreach ($prop in $acCloud.PSObject.Properties) {
                $script:FileServer[$prop.Name] = $prop.Value
            }
        }
        elseif ($acCloud -is [hashtable]) {
            foreach ($key in $acCloud.Keys) {
                $script:FileServer[$key] = $acCloud[$key]
            }
        }
        # Backward compat: remap old KaseyaFolder key to AgentFolder
        if ($script:FileServer.ContainsKey("KaseyaFolder") -and -not $script:FileServer.ContainsKey("AgentFolder")) {
            $script:FileServer["AgentFolder"] = $script:FileServer["KaseyaFolder"]
        }
        $script:FileServer.Remove("KaseyaFolder") 2>$null
    }

    # Import custom license keys from defaults.json
    $script:CustomKMSKeys = @{}
    $script:CustomAVMAKeys = @{}
    if ((Test-Path $script:DefaultsPath)) {
        try {
            $fileData = Get-Content $script:DefaultsPath -Raw | ConvertFrom-Json
            if ($fileData.CustomKMSKeys) {
                foreach ($verProp in $fileData.CustomKMSKeys.PSObject.Properties) {
                    $editionHash = @{}
                    foreach ($edProp in $verProp.Value.PSObject.Properties) {
                        $editionHash[$edProp.Name] = $edProp.Value
                    }
                    $script:CustomKMSKeys[$verProp.Name] = $editionHash
                }
            }
            if ($fileData.CustomAVMAKeys) {
                foreach ($verProp in $fileData.CustomAVMAKeys.PSObject.Properties) {
                    $editionHash = @{}
                    foreach ($edProp in $verProp.Value.PSObject.Properties) {
                        $editionHash[$edProp.Name] = $edProp.Value
                    }
                    $script:CustomAVMAKeys[$verProp.Name] = $editionHash
                }
            }

            # Import VM naming convention
            if ($fileData.VMNaming) {
                foreach ($prop in $fileData.VMNaming.PSObject.Properties) {
                    if ($prop.Name -like '_*') { continue }
                    $script:VMNaming[$prop.Name] = $prop.Value
                }
            }

            # Import custom VM templates (merge with built-in StandardVMTemplates)
            if ($null -eq $script:BuiltInVMTemplates) {
                # Snapshot built-in templates on first call (deep clone)
                $script:BuiltInVMTemplates = @{}
                foreach ($k in $script:StandardVMTemplates.Keys) {
                    $clone = @{}
                    foreach ($field in $script:StandardVMTemplates[$k].Keys) {
                        $val = $script:StandardVMTemplates[$k][$field]
                        if ($val -is [array]) {
                            $arrClone = @()
                            foreach ($item in $val) {
                                if ($item -is [hashtable]) {
                                    $arrClone += ($item.Clone())
                                } else {
                                    $arrClone += $item
                                }
                            }
                            $clone[$field] = $arrClone
                        } else {
                            $clone[$field] = $val
                        }
                    }
                    $script:BuiltInVMTemplates[$k] = $clone
                }
            } else {
                # Restore built-in templates before re-merging
                foreach ($k in $script:BuiltInVMTemplates.Keys) {
                    $clone = @{}
                    foreach ($field in $script:BuiltInVMTemplates[$k].Keys) {
                        $val = $script:BuiltInVMTemplates[$k][$field]
                        if ($val -is [array]) {
                            $arrClone = @()
                            foreach ($item in $val) {
                                if ($item -is [hashtable]) {
                                    $arrClone += ($item.Clone())
                                } else {
                                    $arrClone += $item
                                }
                            }
                            $clone[$field] = $arrClone
                        } else {
                            $clone[$field] = $val
                        }
                    }
                    $script:StandardVMTemplates[$k] = $clone
                }
            }

            $script:CustomVMTemplates = @{}
            if ($fileData.CustomVMTemplates) {
                foreach ($tplProp in $fileData.CustomVMTemplates.PSObject.Properties) {
                    if ($tplProp.Name -like '_*') { continue }
                    $tplData = @{}
                    foreach ($fp in $tplProp.Value.PSObject.Properties) {
                        if ($fp.Name -eq 'Disks' -and $fp.Value -is [array]) {
                            # Convert PSCustomObject[] to hashtable[]
                            $diskArr = @()
                            foreach ($diskObj in $fp.Value) {
                                $diskHash = @{}
                                foreach ($dp in $diskObj.PSObject.Properties) {
                                    $diskHash[$dp.Name] = $dp.Value
                                }
                                $diskArr += $diskHash
                            }
                            $tplData[$fp.Name] = $diskArr
                        } else {
                            $tplData[$fp.Name] = $fp.Value
                        }
                    }
                    $script:CustomVMTemplates[$tplProp.Name] = $tplData

                    # Merge into StandardVMTemplates
                    if ($script:StandardVMTemplates.ContainsKey($tplProp.Name)) {
                        # Existing template: field-level merge (partial override)
                        foreach ($field in $tplData.Keys) {
                            $script:StandardVMTemplates[$tplProp.Name][$field] = $tplData[$field]
                        }
                    } else {
                        # New template: add with defaults for optional fields
                        $newTpl = $tplData.Clone()
                        if (-not $newTpl.ContainsKey('SortOrder'))        { $newTpl['SortOrder'] = 100 }
                        if (-not $newTpl.ContainsKey('GuestServices'))    { $newTpl['GuestServices'] = $true }
                        if (-not $newTpl.ContainsKey('TimeSyncWithHost')) { $newTpl['TimeSyncWithHost'] = $true }
                        if (-not $newTpl.ContainsKey('Notes'))           { $newTpl['Notes'] = "" }
                        $script:StandardVMTemplates[$tplProp.Name] = $newTpl
                    }
                }
            }

            # Import custom role templates (merge with built-in ServerRoleTemplates)
            $script:CustomRoleTemplates = @{}
            if ($fileData.CustomRoleTemplates) {
                foreach ($tplProp in $fileData.CustomRoleTemplates.PSObject.Properties) {
                    if ($tplProp.Name -like '_*') { continue }
                    $tplData = @{}
                    foreach ($fp in $tplProp.Value.PSObject.Properties) {
                        if ($fp.Name -eq 'Features' -and $fp.Value -is [array]) {
                            $tplData[$fp.Name] = @($fp.Value)
                        } else {
                            $tplData[$fp.Name] = $fp.Value
                        }
                    }
                    $script:CustomRoleTemplates[$tplProp.Name] = $tplData
                }
            }

            # Import custom VM defaults (for non-template VMs)
            $script:CustomVMDefaults = @{}
            if ($fileData.CustomVMDefaults) {
                foreach ($prop in $fileData.CustomVMDefaults.PSObject.Properties) {
                    if ($prop.Name -like '_*') { continue }
                    $script:CustomVMDefaults[$prop.Name] = $prop.Value
                }
            }
        }
        catch {
            Write-OutputColor "  Warning: Could not load VM defaults from defaults.json: $($_.Exception.Message)" -color "Warning"
        }
    }

    # Rebuild SAN target pairs from configured subnet
    Initialize-SANTargetPairs
}

# Export current defaults to defaults.json (includes custom license keys)
function Export-Defaults {

    # Gather custom DNS presets (exclude built-in ones)
    $builtinDNSNames = @("Google DNS", "Cloudflare", "OpenDNS", "Quad9")
    $customDNS = @{}
    foreach ($key in $script:DNSPresets.Keys) {
        if ($key -notin $builtinDNSNames) {
            $customDNS[$key] = $script:DNSPresets[$key]
        }
    }

    $defaults = [ordered]@{
        "_description"       = "Environment defaults for $($script:ToolFullName)"
        ToolName             = $script:ToolName
        ToolFullName         = $script:ToolFullName
        SupportContact       = $script:SupportContact
        Domain               = if ($script:domain) { $script:domain } else { $domain }
        LocalAdminName       = if ($script:localadminaccountname) { $script:localadminaccountname } else { $localadminaccountname }
        LocalAdminFullName   = if ($script:FullName) { $script:FullName } else { $FullName }
        SwitchName           = if ($script:SwitchName) { $script:SwitchName } else { $SwitchName }
        ManagementName       = if ($script:ManagementName) { $script:ManagementName } else { $ManagementName }
        BackupName           = if ($script:BackupName) { $script:BackupName } else { $BackupName }
        DNSPresets           = $customDNS
        FileServer          = $script:FileServer
        iSCSISubnet          = $script:iSCSISubnet
        StorageBackendType   = $script:StorageBackendType
        CustomKMSKeys        = $script:CustomKMSKeys
        CustomAVMAKeys       = $script:CustomAVMAKeys
        CustomVMTemplates    = $script:CustomVMTemplates
        CustomVMDefaults     = $script:CustomVMDefaults
    }

    try {
        $defaults | ConvertTo-Json -Depth 5 | Out-File $script:DefaultsPath -Encoding UTF8 -Force
    }
    catch {
        Write-OutputColor "Failed to save defaults: $_" -color "Error"
    }
}

# Import-CustomLicenses is handled by Import-Defaults (licenses stored in defaults.json)
# This wrapper exists for backward compatibility
function Import-CustomLicenses {
    # License keys are loaded as part of Import-Defaults from defaults.json
    # No separate file needed
}

# Export-CustomLicenses saves via Export-Defaults (licenses stored in defaults.json)
function Export-CustomLicenses {
    Export-Defaults
}

# Settings menu: Edit Environment Defaults
function Show-EditDefaults {
    while ($true) {
        Clear-Host

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                      ENVIRONMENT DEFAULTS").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        # Gather custom DNS presets
        $builtinDNSNames = @("Google DNS", "Cloudflare", "OpenDNS", "Quad9")
        $customDNSCount = 0
        foreach ($key in $script:DNSPresets.Keys) {
            if ($key -notin $builtinDNSNames) { $customDNSCount++ }
        }

        $domainDisplay = if ($domain) { $domain } else { "(not set)" }
        $acDisplay = if ($script:FileServer.BaseURL) { "Configured" } else { "(not set)" }

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  CURRENT VALUES".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  Domain" -Status $domainDisplay -StatusColor "Info"
        Write-MenuItem "[2]  Local Admin Name" -Status $localadminaccountname -StatusColor "Info"
        Write-MenuItem "[3]  Local Admin Full Name" -Status $FullName -StatusColor "Info"
        Write-MenuItem "[4]  Switch/NIC Names" -Status "$SwitchName / $ManagementName / $BackupName" -StatusColor "Info"
        Write-MenuItem "[5]  Custom DNS Presets" -Status "$customDNSCount custom preset(s)" -StatusColor "Info"
        Write-MenuItem "[6]  FileServer Settings" -Status $acDisplay -StatusColor "Info"
        Write-MenuItem "[7]  iSCSI Subnet" -Status "$($script:iSCSISubnet).x" -StatusColor "Info"
        Write-MenuItem "[8]  Storage Backend" -Status $script:StorageBackendType -StatusColor "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  [S] Save to defaults.json" -color "Info"
        Write-OutputColor "  [R] Reset to generic defaults" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) {
            if (Invoke-NavigationAction -NavResult $navResult) { return }
        }

        switch ("$choice".ToUpper()) {
            "1" {
                Write-OutputColor "Enter domain name (e.g., contoso.local) or leave empty to clear:" -color "Info"
                $val = Read-Host
                $domain = $val
                $script:domain = $val
            }
            "2" {
                Write-OutputColor "Enter local admin account name:" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) {
                    $localadminaccountname = $val
                    $script:localadminaccountname = $val
                }
            }
            "3" {
                Write-OutputColor "Enter local admin full name:" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) {
                    $FullName = $val
                    $script:FullName = $val
                }
            }
            "4" {
                Write-OutputColor "Enter SET name (current: $SwitchName):" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) { $SwitchName = $val; $script:SwitchName = $val }

                Write-OutputColor "Enter Management NIC name (current: $ManagementName):" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) { $ManagementName = $val; $script:ManagementName = $val }

                Write-OutputColor "Enter Backup NIC name (current: $BackupName):" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) { $BackupName = $val; $script:BackupName = $val }
            }
            "5" {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "Current DNS Presets:" -color "Info"
                $presetIndex = 1
                foreach ($key in $script:DNSPresets.Keys) {
                    $marker = if ($key -in $builtinDNSNames) { " (built-in)" } else { " (custom)" }
                    Write-OutputColor "  $presetIndex. $key ($($script:DNSPresets[$key] -join ', '))$marker" -color "Info"
                    $presetIndex++
                }
                Write-OutputColor "" -color "Info"
                Write-OutputColor "[A] Add custom DNS preset  [D] Delete custom preset  [B] Back" -color "Info"
                $dnsChoice = Read-Host "  Select"

                switch ("$dnsChoice".ToUpper()) {
                    "A" {
                        Write-OutputColor "Enter preset name (e.g., 'Company DNS'):" -color "Info"
                        $presetName = Read-Host
                        if (-not [string]::IsNullOrWhiteSpace($presetName)) {
                            Write-OutputColor "Enter primary DNS server IP:" -color "Info"
                            $dns1 = Read-Host
                            Write-OutputColor "Enter secondary DNS server IP (or leave empty):" -color "Info"
                            $dns2 = Read-Host
                            $servers = @($dns1)
                            if (-not [string]::IsNullOrWhiteSpace($dns2)) { $servers += $dns2 }
                            $script:DNSPresets[$presetName] = $servers
                            Write-OutputColor "Added DNS preset '$presetName'." -color "Success"
                        }
                    }
                    "D" {
                        Write-OutputColor "Enter name of custom preset to delete:" -color "Info"
                        $delName = Read-Host
                        if ($delName -in $builtinDNSNames) {
                            Write-OutputColor "Cannot delete built-in presets." -color "Error"
                        }
                        elseif ($script:DNSPresets.Contains($delName)) {
                            $script:DNSPresets.Remove($delName)
                            Write-OutputColor "Deleted '$delName'." -color "Success"
                        }
                        else {
                            Write-OutputColor "Preset not found." -color "Error"
                        }
                    }
                }
                Start-Sleep -Seconds 1
            }
            "6" {
                Write-OutputColor "Enter FileServer base URL:" -color "Info"
                Write-OutputColor "  Leave empty to disable cloud features." -color "Debug"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.BaseURL = $val }
                elseif ($val -eq "") { $script:FileServer.BaseURL = "" }

                Write-OutputColor "Enter CF-Access-Client-Id:" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.ClientId = $val }

                Write-OutputColor "Enter CF-Access-Client-Secret:" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.ClientSecret = $val }

                Write-OutputColor "Enter ISOs subfolder name (default: ISOs):" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.ISOsFolder = $val }

                Write-OutputColor "Enter VHDs subfolder name (default: VirtualHardDrives):" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.VHDsFolder = $val }

                Write-OutputColor "Enter agent installer subfolder name (default: Agents):" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.AgentFolder = $val }
            }
            "7" {
                Write-OutputColor "Enter iSCSI subnet (first 3 octets, e.g., 172.16.1):" -color "Info"
                $val = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($val)) {
                    $script:iSCSISubnet = $val
                    Initialize-SANTargetPairs
                    Write-OutputColor "iSCSI subnet set to $val.x" -color "Success"
                }
            }
            "8" {
                Set-StorageBackendType
            }
            "S" {
                Export-Defaults
                Write-OutputColor "Defaults saved to $($script:DefaultsPath)" -color "Success"
                Start-Sleep -Seconds 1
            }
            "R" {
                if (Confirm-UserAction -Message "Reset all defaults to generic values?") {
                    $domain = ""; $script:domain = ""
                    $localadminaccountname = "localadmin"; $script:localadminaccountname = "localadmin"
                    $FullName = "Local Administrator"; $script:FullName = "Local Administrator"
                    $SwitchName = "LAN-SET"; $script:SwitchName = "LAN-SET"
                    $ManagementName = "Management"; $script:ManagementName = "Management"
                    $BackupName = "Backup"; $script:BackupName = "Backup"
                    $script:iSCSISubnet = "172.16.1"
                    $script:StorageBackendType = "iSCSI"

                    # Remove custom DNS presets
                    $toRemove = @()
                    foreach ($key in $script:DNSPresets.Keys) {
                        if ($key -notin $builtinDNSNames) { $toRemove += $key }
                    }
                    foreach ($key in $toRemove) { $script:DNSPresets.Remove($key) }

                    $script:FileServer = @{ BaseURL = ""; ClientId = ""; ClientSecret = ""; ISOsFolder = "ISOs"; VHDsFolder = "VirtualHardDrives"; AgentFolder = "Agents" }
                    Initialize-SANTargetPairs

                    Write-OutputColor "Defaults reset to generic values." -color "Success"
                    Start-Sleep -Seconds 1
                }
            }
            "B" { return }
            default {
                Write-OutputColor "Invalid choice." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Settings menu: Edit Custom Licenses
function Show-EditLicenses {
    while ($true) {
        Clear-Host

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                        CUSTOM LICENSE KEYS").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        $kmsCount = 0
        foreach ($ver in $script:CustomKMSKeys.Keys) {
            foreach ($ed in $script:CustomKMSKeys[$ver].Keys) { $kmsCount++ }
        }
        $avmaCount = 0
        foreach ($ver in $script:CustomAVMAKeys.Keys) {
            foreach ($ed in $script:CustomAVMAKeys[$ver].Keys) { $avmaCount++ }
        }

        Write-OutputColor "  Custom KMS keys: $kmsCount    Custom AVMA keys: $avmaCount" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-MenuItem "[A]  Add custom license key"
        Write-MenuItem "[D]  Delete custom license key"
        Write-MenuItem "[V]  View all keys (built-in + custom)"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  [S] Save to licenses.json" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) {
            if (Invoke-NavigationAction -NavResult $navResult) { return }
        }

        switch ("$choice".ToUpper()) {
            "A" {
                Write-OutputColor "License type:" -color "Info"
                Write-OutputColor "  1. KMS (for hosts)" -color "Info"
                Write-OutputColor "  2. AVMA (for VMs on Datacenter hosts)" -color "Info"
                $typeChoice = Read-Host "  Select"

                Write-OutputColor "Enter Windows Server version (e.g., Windows Server 2022):" -color "Info"
                $version = Read-Host

                Write-OutputColor "Enter edition (e.g., Datacenter, Standard):" -color "Info"
                $edition = Read-Host

                Write-OutputColor "Enter product key (XXXXX-XXXXX-XXXXX-XXXXX-XXXXX):" -color "Info"
                $key = Read-Host

                if (-not [string]::IsNullOrWhiteSpace($version) -and -not [string]::IsNullOrWhiteSpace($edition) -and -not [string]::IsNullOrWhiteSpace($key)) {
                    if ($typeChoice -eq "1") {
                        if (-not $script:CustomKMSKeys.ContainsKey($version)) {
                            $script:CustomKMSKeys[$version] = @{}
                        }
                        $script:CustomKMSKeys[$version][$edition] = $key.ToUpper()
                        Write-OutputColor "Added custom KMS key for $version $edition." -color "Success"
                    }
                    else {
                        if (-not $script:CustomAVMAKeys.ContainsKey($version)) {
                            $script:CustomAVMAKeys[$version] = @{}
                        }
                        $script:CustomAVMAKeys[$version][$edition] = $key.ToUpper()
                        Write-OutputColor "Added custom AVMA key for $version $edition." -color "Success"
                    }
                }
                else {
                    Write-OutputColor "All fields are required." -color "Error"
                }
                Start-Sleep -Seconds 1
            }
            "D" {
                Write-OutputColor "Delete from: 1. KMS  2. AVMA" -color "Info"
                $typeChoice = Read-Host "  Select"
                $targetKeys = if ($typeChoice -eq "1") { $script:CustomKMSKeys } else { $script:CustomAVMAKeys }
                $typeName = if ($typeChoice -eq "1") { "KMS" } else { "AVMA" }

                if ($targetKeys.Count -eq 0) {
                    Write-OutputColor "No custom $typeName keys to delete." -color "Warning"
                }
                else {
                    $idx = 1
                    $keyList = @()
                    foreach ($ver in $targetKeys.Keys) {
                        foreach ($ed in $targetKeys[$ver].Keys) {
                            Write-OutputColor "  $idx. $ver - ${ed}: $($targetKeys[$ver][$ed])" -color "Info"
                            $keyList += @{ Version = $ver; Edition = $ed }
                            $idx++
                        }
                    }
                    Write-OutputColor "Enter number to delete (or B to cancel):" -color "Info"
                    $delChoice = Read-Host
                    if ($delChoice -match '^\d+$') {
                        $delIdx = [int]$delChoice - 1
                        if ($delIdx -ge 0 -and $delIdx -lt $keyList.Count) {
                            $item = $keyList[$delIdx]
                            $targetKeys[$item.Version].Remove($item.Edition)
                            if ($targetKeys[$item.Version].Count -eq 0) {
                                $targetKeys.Remove($item.Version)
                            }
                            Write-OutputColor "Deleted." -color "Success"
                        }
                    }
                }
                Start-Sleep -Seconds 1
            }
            "V" {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Built-in keys are shown in gray, custom keys in green." -color "Info"
                Write-OutputColor "" -color "Info"

                # Show custom KMS keys
                if ($script:CustomKMSKeys.Count -gt 0) {
                    Write-OutputColor "  Custom KMS Keys:" -color "Success"
                    foreach ($ver in $script:CustomKMSKeys.Keys) {
                        foreach ($ed in $script:CustomKMSKeys[$ver].Keys) {
                            Write-OutputColor "    $ver - $ed : $($script:CustomKMSKeys[$ver][$ed])" -color "Success"
                        }
                    }
                    Write-OutputColor "" -color "Info"
                }

                # Show custom AVMA keys
                if ($script:CustomAVMAKeys.Count -gt 0) {
                    Write-OutputColor "  Custom AVMA Keys:" -color "Success"
                    foreach ($ver in $script:CustomAVMAKeys.Keys) {
                        foreach ($ed in $script:CustomAVMAKeys[$ver].Keys) {
                            Write-OutputColor "    $ver - $ed : $($script:CustomAVMAKeys[$ver][$ed])" -color "Success"
                        }
                    }
                    Write-OutputColor "" -color "Info"
                }

                if ($script:CustomKMSKeys.Count -eq 0 -and $script:CustomAVMAKeys.Count -eq 0) {
                    Write-OutputColor "  No custom license keys configured." -color "Debug"
                }

                Write-OutputColor "  (Built-in Microsoft KB keys are always available)" -color "Debug"
                Write-PressEnter
            }
            "S" {
                Export-CustomLicenses
                Write-OutputColor "Licenses saved to $($script:DefaultsPath)" -color "Success"
                Start-Sleep -Seconds 1
            }
            "B" { return }
            default {
                Write-OutputColor "Invalid choice." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# First-run configuration wizard
function Show-FirstRunWizard {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    FIRST-RUN CONFIGURATION").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Welcome! No environment defaults file was found." -color "Info"
    Write-OutputColor "  You can configure company-specific settings now, or use generic defaults." -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Settings can be changed later from: Settings > Edit Environment Defaults" -color "Debug"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Configure environment defaults now?")) {
        # User declined - save generic defaults so wizard won't run again
        Export-Defaults
        Write-OutputColor "  Generic defaults saved. You can configure later in Settings." -color "Info"
        Start-Sleep -Seconds 2
        return
    }

    Write-OutputColor "" -color "Info"

    # Domain
    Write-OutputColor "  Enter your primary domain (e.g., contoso.local) or press Enter to skip:" -color "Info"
    $val = Read-Host "  Domain"
    if (-not [string]::IsNullOrWhiteSpace($val)) {
        $domain = $val
        $script:domain = $val
    }

    # Local admin
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enter local admin account name (default: localadmin):" -color "Info"
    $val = Read-Host "  Admin name"
    if (-not [string]::IsNullOrWhiteSpace($val)) {
        $localadminaccountname = $val
        $script:localadminaccountname = $val
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enter local admin full name (default: Local Administrator):" -color "Info"
    $val = Read-Host "  Full name"
    if (-not [string]::IsNullOrWhiteSpace($val)) {
        $FullName = $val
        $script:FullName = $val
    }

    # Custom DNS
    Write-OutputColor "" -color "Info"
    if (Confirm-UserAction -Message "Add a custom DNS preset (e.g., company DNS servers)?") {
        Write-OutputColor "  Enter preset name (e.g., 'Company DNS'):" -color "Info"
        $presetName = Read-Host "  Name"
        if (-not [string]::IsNullOrWhiteSpace($presetName)) {
            Write-OutputColor "  Enter primary DNS server IP:" -color "Info"
            $dns1 = Read-Host "  Primary"
            Write-OutputColor "  Enter secondary DNS server IP (or press Enter to skip):" -color "Info"
            $dns2 = Read-Host "  Secondary"
            $servers = @($dns1)
            if (-not [string]::IsNullOrWhiteSpace($dns2)) { $servers += $dns2 }
            $script:DNSPresets[$presetName] = $servers
            Write-OutputColor "  Added DNS preset '$presetName'." -color "Success"
        }
    }

    # FileServer
    Write-OutputColor "" -color "Info"
    if (Confirm-UserAction -Message "Configure FileServer for ISO/VHD/agent downloads?") {
        Write-OutputColor "  Enter FileServer base URL:" -color "Info"
        $val = Read-Host "  URL"
        if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.BaseURL = $val }

        Write-OutputColor "  Enter CF-Access-Client-Id:" -color "Info"
        $val = Read-Host "  ClientId"
        if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.ClientId = $val }

        Write-OutputColor "  Enter CF-Access-Client-Secret:" -color "Info"
        $val = Read-Host "  Secret"
        if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.ClientSecret = $val }

        Write-OutputColor "  Enter ISOs subfolder name (default: ISOs):" -color "Info"
        $val = Read-Host "  ISOs"
        if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.ISOsFolder = $val }

        Write-OutputColor "  Enter VHDs subfolder name (default: VirtualHardDrives):" -color "Info"
        $val = Read-Host "  VHDs"
        if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.VHDsFolder = $val }

        Write-OutputColor "  Enter agent installer subfolder name (default: Agents):" -color "Info"
        $val = Read-Host "  Agents"
        if (-not [string]::IsNullOrWhiteSpace($val)) { $script:FileServer.AgentFolder = $val }
    }

    # iSCSI Subnet
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enter iSCSI subnet (first 3 octets, default: 172.16.1):" -color "Info"
    $val = Read-Host "  Subnet"
    if (-not [string]::IsNullOrWhiteSpace($val)) {
        $script:iSCSISubnet = $val
        Initialize-SANTargetPairs
    }

    # Save
    Export-Defaults
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Configuration saved to $($script:DefaultsPath)" -color "Success"
    Write-OutputColor "  You can edit these anytime from: Settings > Edit Environment Defaults" -color "Info"
    Write-PressEnter
}
#endregion