#region ===== AGENT INSTALLER =====
# Check if agent installer feature is configured (FileServer + non-default ToolName)
function Test-AgentInstallerConfigured {
    # Must have FileServer configured to download agents
    if (-not (Test-FileServerConfigured)) { return $false }
    # ToolName must be customized from the built-in "MSP" default
    if ($script:AgentInstaller.ToolName -eq "MSP") { return $false }
    return $true
}

# Function to check if the configured agent is installed
function Test-AgentInstalled {
    # Check for agent service
    $agentService = Get-Service -Name $script:AgentInstaller.ServiceName -ErrorAction SilentlyContinue
    if ($agentService) {
        return @{ Installed = $true; Status = $agentService.Status; ServiceName = $agentService.Name }
    }

    # Check configured installation paths
    foreach ($path in $script:AgentInstaller.InstallPaths) {
        $expandedPath = [Environment]::ExpandEnvironmentVariables($path)
        if (Test-Path $expandedPath) {
            return @{ Installed = $true; Status = "Files Found"; Path = $expandedPath }
        }
    }

    return @{ Installed = $false }
}

# Function to get agent installers from FileServer (with caching)
function Get-AgentInstallerList {
    param([switch]$ForceRefresh)

    # Check cache
    if (-not $ForceRefresh -and $script:AgentInstallerCache -and $script:AgentInstallerCacheTime) {
        $cacheAge = (Get-Date) - $script:AgentInstallerCacheTime
        if ($cacheAge.TotalMinutes -lt $script:CacheTTLMinutes) {
            return $script:AgentInstallerCache
        }
    }

    Write-OutputColor "  Fetching agent list from FileServer..." -color "Info"

    try {
        $files = Get-FileServerFiles -FolderPath $script:AgentInstaller.FolderName -ForceRefresh:$ForceRefresh
        $agents = @()

        foreach ($file in $files) {
            $fileName = $file.FileName

            if ($fileName -match $script:AgentInstaller.FilePattern) {
                $parsed = ConvertFrom-AgentFilename -FileName $fileName
                if ($parsed.Valid) {
                    $agents += @{
                        FilePath = $file.FilePath
                        FileName = $fileName
                        SiteNumbers = $parsed.SiteNumbers
                        SiteName = $parsed.SiteName
                        DisplayName = $parsed.DisplayName
                    }
                }
            }
        }

        # Deduplicate agents with same site numbers + name (e.g., .staging variants)
        $seen = @{}
        $unique = @()
        foreach ($a in $agents) {
            $key = ((@($a.SiteNumbers) -join ',') + '|' + $a.SiteName).ToLower()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $unique += $a
            }
        }
        $agents = $unique

        # Update cache
        $script:AgentInstallerCache = $agents
        $script:AgentInstallerCacheTime = Get-Date

        Write-OutputColor "  Found $($agents.Count) $($script:AgentInstaller.ToolName) agents." -color "Success"
        return $agents
    }
    catch {
        Write-OutputColor "  Failed to fetch agent list: $($_.Exception.Message)" -color "Error"
        return @()
    }
}

# Parse agent filename to extract site numbers and name
# Supports any prefix followed by .{numbers}[-{name}].exe (e.g., Tool_org.1001-sitename.exe)
# Numbers can be separated by - or _ for multi-site agents
# Falls back to extracting 3+ digit sequences from anywhere in the filename
function ConvertFrom-AgentFilename {
    param([string]$FileName)

    $result = @{ SiteNumbers = @(); SiteName = ""; DisplayName = ""; RawName = $FileName; Valid = $false }

    # Must be an exe
    if ($FileName -notmatch '\.exe$') {
        return $result
    }

    # Remove any suffix like .staging, .workstations before .exe
    $cleanName = $FileName -replace '\.(staging|workstations|linac-workstations)\.exe$', '.exe'

    # Primary pattern: anything.{numbers}[-{name}].exe
    # The dot-then-digit anchor finds the site number section regardless of prefix format
    # Numbers can be separated by _ or - and the name part is optional
    # When hyphens separate both numbers and name, regex backtracking resolves the ambiguity
    if ($cleanName -match '\.(\d[\d_-]*)(?:-([a-zA-Z][a-zA-Z0-9\-]*))?\.exe$') {
        $regexMatches = $matches
        $numbersPart = $regexMatches[1]
        $namePart = if ($regexMatches[2]) { $regexMatches[2] } else { "" }

        # Split numbers by - or _ and filter to valid numbers only
        $numbers = $numbersPart -split '[-_]' | Where-Object { $_ -match '^\d+$' }

        if ($numbers.Count -gt 0) {
            $result.SiteNumbers = @($numbers)
            $result.SiteName = $namePart
            $result.Valid = $true

            # Build display name
            if ($namePart) {
                $result.DisplayName = "$namePart (Sites: $($numbers -join ', '))"
            } else {
                $result.DisplayName = "Site $($numbers -join ', ')"
            }
            return $result
        }
    }

    # Fallback: extract any 3+ digit sequences from the filename
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $digitMatches = [regex]::Matches($baseName, '\d{3,}')
    if ($digitMatches.Count -gt 0) {
        $result.SiteNumbers = @($digitMatches | ForEach-Object { $_.Value })
        $result.SiteName = $baseName
        $result.DisplayName = $baseName
        $result.Valid = $true
    } elseif ($baseName -match '^(\d+)') {
        $regexMatches = $matches
        $result.SiteNumbers = @($regexMatches[1])
        $result.SiteName = $baseName
        $result.DisplayName = $baseName
        $result.Valid = $true
    } elseif ($baseName) {
        $result.SiteName = $baseName
        $result.DisplayName = $baseName
        $result.Valid = $true
    }

    return $result
}

# Search for agent by site number or name (supports partial matching)
function Search-AgentInstaller {
    param(
        [string]$SearchTerm,
        [array]$Agents
    )

    if (-not $Agents -or $Agents.Count -eq 0) {
        return @()
    }

    $results = @()

    # Normalize search term - remove leading zeros for number searches
    $normalizedSearch = $SearchTerm.TrimStart('0')
    $isNumeric = $SearchTerm -match '^\d+$'

    foreach ($agent in $Agents) {
        $matched = $false

        if ($isNumeric -and $normalizedSearch) {
            # Search by site number — partial/substring matching
            foreach ($siteNum in @($agent.SiteNumbers)) {
                $normalizedSiteNum = ([string]$siteNum).TrimStart('0')
                # Exact match (with zero normalization)
                if ($normalizedSiteNum -eq $normalizedSearch -or $siteNum -eq $SearchTerm) {
                    $matched = $true
                    break
                }
                # Partial match — search term appears anywhere in site number
                if ($normalizedSiteNum -like "*$normalizedSearch*") {
                    $matched = $true
                    break
                }
            }
        } elseif ($isNumeric) {
            # Search for "0" or "00" etc — exact match only (no partial)
            foreach ($siteNum in @($agent.SiteNumbers)) {
                if ($siteNum -eq $SearchTerm) {
                    $matched = $true
                    break
                }
            }
        }

        if (-not $matched) {
            # Search by site name (partial match, case insensitive)
            if ($agent.SiteName -and $agent.SiteName -like "*$SearchTerm*") {
                $matched = $true
            }
        }

        if (-not $matched) {
            # Fallback: search raw filename (catches anything the parser missed)
            if ($agent.FileName -like "*$SearchTerm*") {
                $matched = $true
            }
        }

        if ($matched) {
            $results += $agent
        }
    }

    return $results
}

# Extract site number from hostname
function Get-SiteNumberFromHostname {
    $hostname = $env:COMPUTERNAME

    # Hostname format: 001001-HV1, 001001-FS1, etc. (site number at start, then dash)
    if ($hostname -match '^(\d{3,6})-') {
        $regexMatches = $matches
        return $regexMatches[1]
    }

    return $null
}

# Show list of all agents
function Show-AgentInstallerList {
    param([array]$Agents)

    if (-not $Agents -or $Agents.Count -eq 0) {
        Write-OutputColor "  No agents found in FileServer folder." -color "Warning"
        return $null
    }

    $toolName = $script:AgentInstaller.ToolName

    # Sort by first site number numerically (smallest to largest)
    $allAgents = $Agents | Sort-Object {
        $firstSite = if ($_.SiteNumbers -and $_.SiteNumbers.Count -gt 0) { [string]@($_.SiteNumbers)[0] } else { "9999999" }
        [int]($firstSite.TrimStart('0') -replace '^$','0')
    }
    $displayAgents = $allAgents
    $searchFilter = $null

    $pageSize = 25
    $currentPage = 0

    while ($true) {
        $totalPages = [math]::Max(1, [math]::Ceiling($displayAgents.Count / $pageSize))
        if ($currentPage -ge $totalPages) { $currentPage = 0 }
        $startIdx = $currentPage * $pageSize
        $endIdx = [math]::Min($startIdx + $pageSize - 1, $displayAgents.Count - 1)

        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        if ($searchFilter) {
            $header = "  SEARCH: '$searchFilter' ($($displayAgents.Count) results) - Page $($currentPage + 1) of $totalPages"
        } else {
            $header = "  AVAILABLE $($toolName.ToUpper()) AGENTS ($($displayAgents.Count) total) - Page $($currentPage + 1) of $totalPages"
        }
        Write-OutputColor "  │$($header.PadRight(72))│" -color "Success"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        if ($displayAgents.Count -eq 0) {
            Write-OutputColor "  │$("  No agents match '$searchFilter'".PadRight(72))│" -color "Warning"
        } else {
            for ($i = $startIdx; $i -le $endIdx; $i++) {
                $agent = $displayAgents[$i]
                $num = $i + 1
                $siteNums = if ($agent.SiteNumbers -and $agent.SiteNumbers.Count -gt 0) {
                    ($agent.SiteNumbers -join ',').PadRight(20)
                } else { "".PadRight(20) }
                $siteName = if ($agent.SiteName) { $agent.SiteName }
                            elseif ($agent.DisplayName) { $agent.DisplayName }
                            else { [System.IO.Path]::GetFileNameWithoutExtension($agent.FileName) }
                if ($siteName.Length -gt 30) { $siteName = $siteName.Substring(0, 27) + "..." }
                $siteName = $siteName.PadRight(30)
                $display = "  [$num] $siteNums $siteName"
                Write-OutputColor "  │$($display.PadRight(72))│" -color "Info"
            }
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        # Navigation hints
        $nav = @()
        if ($currentPage -gt 0) { $nav += "[P] ◄ Prev" }
        if ($currentPage -lt $totalPages - 1) { $nav += "[N] Next ►" }
        $nav += "[S] Search"
        if ($searchFilter) { $nav += "[A] Show All" }
        $nav += "[B] ◄ Back"
        Write-OutputColor "  Enter number to select, or: $($nav -join '  ')" -color "Info"

        $selection = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $selection
        if ($navResult.ShouldReturn) { return $null }

        switch ("$selection".ToUpper()) {
            'N' { if ($currentPage -lt $totalPages - 1) { $currentPage++ } }
            'P' { if ($currentPage -gt 0) { $currentPage-- } }
            'S' {
                Write-OutputColor "  Enter site number or name to filter:" -color "Info"
                $searchFilter = Read-Host "  Search"
                $navResult = Test-NavigationCommand -UserInput $searchFilter
                if ($navResult.ShouldReturn) { $searchFilter = $null; continue }
                if ($searchFilter) {
                    $displayAgents = @(Search-AgentInstaller -SearchTerm $searchFilter -Agents $allAgents)
                    $currentPage = 0
                } else {
                    $searchFilter = $null
                    $displayAgents = $allAgents
                }
            }
            'A' {
                $searchFilter = $null
                $displayAgents = $allAgents
                $currentPage = 0
            }
            'B' { return $null }
            default {
                if ($selection -match '^\d+$') {
                    $idx = [int]$selection - 1
                    if ($idx -ge 0 -and $idx -lt $displayAgents.Count) {
                        return $displayAgents[$idx]
                    }
                    Write-OutputColor "  Invalid number. Valid range: 1-$($displayAgents.Count)" -color "Warning"
                    Start-Sleep -Seconds 1
                }
            }
        }
    }
}

# Install selected agent
function Install-SelectedAgent {
    param([hashtable]$Agent)

    if (-not $Agent) { return }

    $toolName = $script:AgentInstaller.ToolName
    $tempPath = Join-Path $env:TEMP $Agent.FileName

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECTED AGENT".PadRight(72))│" -color "Success"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Site Name:    $($Agent.SiteName)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Site Numbers: $($Agent.SiteNumbers -join ', ')".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  File:         $($Agent.FileName)".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Download and install this $toolName Agent?")) {
        Write-OutputColor "  Installation cancelled." -color "Info"
        return
    }

    # Download using Get-FileServerFile (from FILESERVER DOWNLOAD region)
    $dlResult = Get-FileServerFile -FilePath $Agent.FilePath -DestinationPath $env:TEMP -FileName $Agent.FileName

    if (-not $dlResult.Success -or -not (Test-Path $tempPath)) {
        Write-OutputColor "  Failed to download installer. $($dlResult.Error)" -color "Error"
        return
    }

    # Run installer
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Running $toolName Agent installer..." -color "Info"
    Write-OutputColor "  This may take several minutes." -color "Info"

    $installTimeout = $script:AgentInstaller.TimeoutSeconds

    try {
        $elapsed = 0
        $installJob = Start-Job -ScriptBlock {
            param($installerPath, $argString)
            try {
                $process = Start-Process -FilePath $installerPath -ArgumentList $argString -Wait -PassThru -ErrorAction Stop
                return @{ Success = $true; ExitCode = $process.ExitCode }
            }
            catch {
                return @{ Success = $false; Error = $_.Exception.Message }
            }
        } -ArgumentList $tempPath, $script:AgentInstaller.InstallArgs

        while ($installJob.State -eq "Running") {
            Show-ProgressMessage -Activity "Installing $toolName Agent" -Status "Please wait..." -SecondsElapsed $elapsed
            Start-Sleep -Seconds 1
            $elapsed++

            if ($elapsed -gt $installTimeout) {
                Stop-Job $installJob -ErrorAction SilentlyContinue
                Remove-Job $installJob -Force -ErrorAction SilentlyContinue
                Write-Host ""
                Write-OutputColor "  Installation timed out after $installTimeout seconds." -color "Warning"
                Add-SessionChange -Category "Software" -Description "$toolName Agent installation timed out after ${installTimeout}s"
                return
            }
        }
        Write-Host ""

        $result = Receive-Job $installJob
        Remove-Job $installJob -Force -ErrorAction SilentlyContinue

        if (-not $result.Success) {
            Write-OutputColor "  Installer failed to launch: $($result.Error)" -color "Error"
            return
        }

        $exitCode = $result.ExitCode
        $exitDesc = switch ($exitCode) {
            0       { "Success" }
            1641    { "Reboot initiated by installer" }
            3010    { "Success (reboot required)" }
            1602    { "User cancelled" }
            1603    { "Fatal error during installation" }
            default { "Error (code $exitCode)" }
        }

        # Determine if install was successful based on configured success codes
        $installOK = $exitCode -in $script:AgentInstaller.SuccessExitCodes

        # Post-install service verification
        $serviceStatus = "Not checked"
        $serviceColor = "Warning"
        $overallStatus = "UNKNOWN"
        $overallColor = "Warning"

        if ($installOK) {
            # Poll for agent service to appear
            $verifyElapsed = 0
            $verifyTimeout = 60
            $agentResult = $null

            while ($verifyElapsed -lt $verifyTimeout) {
                Show-ProgressMessage -Activity "Waiting for $toolName Agent service" -Status "Verifying..." -SecondsElapsed $verifyElapsed
                Start-Sleep -Seconds 2
                $verifyElapsed += 2

                $agentResult = Test-AgentInstalled
                if ($agentResult.Installed) {
                    break
                }
            }
            Write-Host ""

            if ($null -ne $agentResult -and $agentResult.Installed) {
                if ($agentResult.Status -eq "Running") {
                    $serviceStatus = "Running"
                    $serviceColor = "Success"
                    $overallStatus = "SUCCESS"
                    $overallColor = "Success"
                } else {
                    $serviceStatus = "$($agentResult.Status) (may need time to start)"
                    $serviceColor = "Warning"
                    $overallStatus = "INSTALLED"
                    $overallColor = "Success"
                }
            } else {
                $serviceStatus = "Not detected (may need reboot or manual check)"
                $serviceColor = "Warning"
                $overallStatus = "NEEDS VERIFICATION"
                $overallColor = "Warning"
            }
        } else {
            if ($exitCode -eq 1602) {
                $overallStatus = "CANCELLED"
                $overallColor = "Warning"
            } else {
                $overallStatus = "FAILED"
                $overallColor = "Error"
            }
            $serviceStatus = "N/A"
        }

        # Display result box
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  INSTALLATION RESULT".PadRight(72))│" -color $overallColor
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  Agent:     $($Agent.DisplayName)".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Install:   $exitDesc".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Service:   $serviceStatus".PadRight(72))│" -color $serviceColor
        Write-OutputColor "  │$("  Status:    $overallStatus".PadRight(72))│" -color $overallColor
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

        if ($installOK) {
            Add-SessionChange -Category "Software" -Description "Installed $toolName Agent ($($Agent.SiteName))"
            # Clear menu cache so Roles & Features shows updated status
            $script:MenuCache["AgentInstalled"] = $null
            $script:MenuCache["AgentInstalled_LastUpdate"] = $null
        }

        if ($exitCode -eq 3010 -or $exitCode -eq 1641) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  A reboot is required to complete the installation." -color "Warning"
            $global:RebootNeeded = $true
        }
    }
    finally {
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
    }
}

# Main agent installation menu
function Install-Agent {
    param(
        [switch]$ReturnAfterInstall,  # Returns after successful install (for domain join flow)
        [switch]$Unattended           # Non-interactive: auto-detect from hostname, install if single match
    )

    $toolName = $script:AgentInstaller.ToolName

    # --- Section: Unattended Mode (batch/automated installs) ---
    if ($Unattended) {
        if (-not (Test-AgentInstallerConfigured)) {
            Write-OutputColor "  $toolName agent: not configured (skipped)" -color "Debug"
            return
        }
        $agentStatus = Test-AgentInstalled
        if ($agentStatus.Installed) {
            Write-OutputColor "  $toolName agent: already installed" -color "Debug"
            return
        }
        $detectedSite = Get-SiteNumberFromHostname
        if (-not $detectedSite) {
            Write-OutputColor "  $toolName agent: no site number in hostname (skipped)" -color "Warning"
            return
        }
        $agents = Get-AgentInstallerList
        $matchingAgents = @(Search-AgentInstaller -SearchTerm $detectedSite -Agents $agents)
        if ($matchingAgents.Count -eq 1) {
            Write-OutputColor "  $toolName agent: auto-detected site $detectedSite, installing..." -color "Info"
            Install-SelectedAgent -Agent $matchingAgents[0]
        } elseif ($matchingAgents.Count -gt 1) {
            Write-OutputColor "  $toolName agent: $($matchingAgents.Count) matches for site $detectedSite (skipped — needs manual selection)" -color "Warning"
        } else {
            Write-OutputColor "  $toolName agent: no match for site $detectedSite (skipped)" -color "Warning"
        }
        return
    }

    # --- Section: Pre-check - Feature Configuration ---
    if (-not (Test-AgentInstallerConfigured)) {
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                     AGENT INSTALLER NOT CONFIGURED").PadRight(72))║" -color "Warning"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"
        if (-not (Test-FileServerConfigured)) {
            Write-OutputColor "  FileServer is not configured. Agent downloads require a configured" -color "Warning"
            Write-OutputColor "  file server in defaults.json (FileServer.BaseURL)." -color "Warning"
        }
        if ($script:AgentInstaller.ToolName -eq "MSP") {
            Write-OutputColor "  Agent installer has not been customized. Set AgentInstaller.ToolName" -color "Warning"
            Write-OutputColor "  in defaults.json or company defaults to enable this feature." -color "Warning"
        }
        Write-OutputColor "" -color "Info"
        Write-PressEnter
        return
    }

    # --- Section: Initialization ---
    $hostname = $env:COMPUTERNAME

    # --- Section: Step 0 - Pending Hostname Change Check ---
    # STEP 0: Check for pending hostname change (requires reboot before agent install)
    $pendingName = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName" -ErrorAction SilentlyContinue).ComputerName
    $activeName = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName" -ErrorAction SilentlyContinue).ComputerName
    if ($pendingName -and $activeName -and $pendingName -ne $activeName) {
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$("                        REBOOT REQUIRED".PadRight(72))║" -color "Warning"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  PENDING HOSTNAME CHANGE".PadRight(72))│" -color "Warning"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  Current Name:  $activeName".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Pending Name:  $pendingName".PadRight(72))│" -color "Success"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  A hostname change is pending. The server must be rebooted before" -color "Warning"
        Write-OutputColor "  installing $toolName Agent so the correct hostname is used." -color "Warning"
        Write-OutputColor "" -color "Info"
        if (Confirm-UserAction -Message "Reboot now to apply hostname change?") {
            Add-SessionChange -Category "System" -Description "Rebooting to apply hostname change before $toolName install"
            Restart-Computer -Force
        }
        Write-PressEnter
        return
    }

    # --- Section: Step 1 - Validate Hostname Format ---
    # STEP 1: Check if hostname is a default Windows name
    if ($hostname -match '^WIN-' -or $hostname -match '^DESKTOP-' -or $hostname -match '^YOURSERVERNAME') {
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$("                    HOSTNAME NOT CONFIGURED".PadRight(72))║" -color "Warning"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  The server hostname appears to be a default Windows name:" -color "Warning"
        Write-OutputColor "  Current hostname: $hostname" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Please set the hostname before installing $toolName Agent." -color "Info"
        Write-OutputColor "  The hostname should include your site number (e.g., 001001-HV1)." -color "Info"
        Write-OutputColor "" -color "Info"

        if (Confirm-UserAction -Message "Would you like to set the hostname now?") {
            Set-HostName
            # Hostname change requires reboot - offer it
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Hostname changes require a reboot to take effect." -color "Warning"
            if (Confirm-UserAction -Message "Reboot now to apply hostname change?") {
                Add-SessionChange -Category "System" -Description "Set hostname and initiated reboot for $toolName install"
                Restart-Computer -Force
            }
        }
        return
    }

    # --- Section: Step 2 - Check Existing Installation ---
    # STEP 2: Check if agent is already installed
    $agentStatus = Test-AgentInstalled
    if ($agentStatus.Installed) {
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$("                    $($toolName.ToUpper()) ALREADY INSTALLED".PadRight(72))║" -color "Success"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  $toolName Agent is already installed on this server." -color "Success"
        Write-OutputColor "  Status: $($agentStatus.Status)" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-PressEnter
        return
    }

    # --- Section: Step 3 - Auto-detect Site and Match Agent ---
    # STEP 3: Try to match hostname to a site - offer quick install
    $detectedSite = Get-SiteNumberFromHostname
    if ($detectedSite) {
        Write-OutputColor "  Checking for agents matching site $detectedSite..." -color "Info"
        $agents = Get-AgentInstallerList
        $matchingAgents = Search-AgentInstaller -SearchTerm $detectedSite -Agents $agents

        if ($matchingAgents.Count -gt 0) {
            Clear-Host
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
            Write-OutputColor "  ║$("                  $($toolName.ToUpper()) AGENT MATCH FOUND".PadRight(72))║" -color "Success"
            Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
            Write-OutputColor "" -color "Info"

            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  DETECTED MATCH".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Hostname:       $hostname".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Detected Site:  $detectedSite".PadRight(72))│" -color "Info"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            Write-OutputColor "" -color "Info"

            if ($matchingAgents.Count -eq 1) {
                $agent = $matchingAgents[0]
                Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
                Write-OutputColor "  │$("  MATCHING AGENT".PadRight(72))│" -color "Success"
                Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                Write-OutputColor "  │$("  Site Numbers:   $($agent.SiteNumbers -join ', ')".PadRight(72))│" -color "Info"
                Write-OutputColor "  │$("  Site Name:      $($agent.SiteName)".PadRight(72))│" -color "Info"
                Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
                Write-OutputColor "" -color "Info"

                if (Confirm-UserAction -Message "Install this $toolName Agent now?") {
                    Install-SelectedAgent -Agent $agent
                    Write-PressEnter
                    if ($ReturnAfterInstall) { return }
                } else {
                    Write-OutputColor "" -color "Info"
                    Write-OutputColor "  Continuing to full agent menu..." -color "Info"
                    Start-Sleep -Seconds 1
                }
            } else {
                Write-OutputColor "  Found $($matchingAgents.Count) agents for site $detectedSite. Please select:" -color "Info"
                $selected = Show-AgentInstallerList -Agents $matchingAgents
                if ($selected) {
                    Install-SelectedAgent -Agent $selected
                    Write-PressEnter
                    if ($ReturnAfterInstall) { return }
                }
            }
        } else {
            # No match found for detected site - offer to change hostname
            Clear-Host
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
            Write-OutputColor "  ║$("                    NO AGENT MATCH FOR HOSTNAME".PadRight(72))║" -color "Warning"
            Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  HOSTNAME CHECK".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Current Hostname:  $hostname".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Detected Site#:    $detectedSite".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Agent Match:       Not Found".PadRight(72))│" -color "Warning"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  No $toolName agent found for site $detectedSite in FileServer." -color "Info"
            Write-OutputColor "  This may mean:" -color "Info"
            Write-OutputColor "    - The hostname needs to be corrected" -color "Info"
            Write-OutputColor "    - A new agent needs to be added (contact $($script:SupportContact))" -color "Info"
            Write-OutputColor "" -color "Info"

            if (Confirm-UserAction -Message "Would you like to change the hostname?") {
                Set-HostName
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Hostname changes require a reboot to take effect." -color "Warning"
                if (Confirm-UserAction -Message "Reboot now to apply hostname change?") {
                    Add-SessionChange -Category "System" -Description "Changed hostname and initiated reboot for $toolName install"
                    Restart-Computer -Force
                }
                return
            }

            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Continuing to full agent menu..." -color "Info"
            Start-Sleep -Seconds 1
        }
    } else {
        # --- Section: Step 3b - No Site Detection Fallback ---
        # No site number detected in hostname - offer to set it
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$("                  NO SITE NUMBER IN HOSTNAME".PadRight(72))║" -color "Warning"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  HOSTNAME CHECK".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  Current Hostname:  $hostname".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Detected Site#:    None - no 3+ digit number found".PadRight(72))│" -color "Warning"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Your hostname does not contain a site number (e.g., 001001-HV1)." -color "Info"
        Write-OutputColor "  Setting a hostname with your site number enables auto-detection." -color "Info"
        Write-OutputColor "" -color "Info"

        if (Confirm-UserAction -Message "Would you like to set the hostname now?") {
            Set-HostName
            if ($global:RebootNeeded) {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Hostname changes require a reboot to take effect." -color "Warning"
                Write-OutputColor "  $toolName Agent must be installed after reboot." -color "Warning"
                Write-OutputColor "" -color "Info"
                if (Confirm-UserAction -Message "Reboot now to apply hostname change?") {
                    Add-SessionChange -Category "System" -Description "Changed hostname and initiated reboot for $toolName install"
                    Restart-Computer -Force
                }
                return
            }
        }

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Continuing to full agent menu..." -color "Info"
        Start-Sleep -Seconds 1
    }

    # --- Section: Step 4 - Full Agent Selection Menu ---
    # STEP 4: Full menu for manual selection
    while ($true) {
        Clear-Host

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$("                    $($toolName.ToUpper()) AGENT INSTALLER".PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        # Show current status
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  STATUS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  Hostname:     $hostname".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  $($toolName):$((' ' * [math]::Max(1, 14 - $toolName.Length)))Not Installed".PadRight(72))│" -color "Warning"
        if ($detectedSite) {
            Write-OutputColor "  │$("  Detected Site: $detectedSite (no agent match)".PadRight(72))│" -color "Warning"
        } else {
            Write-OutputColor "  │$("  Detected Site: Unable to detect from hostname".PadRight(72))│" -color "Warning"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  AGENT SELECTION".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  [L] List All Agents         - Browse and select from full list".PadRight(72))│" -color "Success"
        Write-OutputColor "  │$("  [S] Search                  - Find by site number or name".PadRight(72))│" -color "Success"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  [R] Refresh Cache           - Re-fetch agent list from FileServer".PadRight(72))│" -color "Success"
        Write-OutputColor "  │$("  [B] ◄ Back".PadRight(72))│" -color "Success"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ("$choice".ToUpper()) {
            'L' {
                $agents = Get-AgentInstallerList
                $selected = Show-AgentInstallerList -Agents $agents
                if ($selected) {
                    Install-SelectedAgent -Agent $selected
                    Write-PressEnter
                    if ($ReturnAfterInstall) { return }
                }
            }
            'S' {
                $agents = Get-AgentInstallerList
                if ($agents.Count -eq 0) {
                    Write-OutputColor "  No agents available." -color "Warning"
                    Write-PressEnter
                    continue
                }

                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Enter site number (e.g., 1001, 2005) or name (e.g., mainoffice, westbranch):" -color "Info"
                $searchTerm = Read-Host "  Search"

                $navResult = Test-NavigationCommand -UserInput $searchTerm
                if ($navResult.ShouldReturn) { continue }

                $results = Search-AgentInstaller -SearchTerm $searchTerm -Agents $agents

                if ($results.Count -eq 0) {
                    Write-OutputColor "" -color "Info"
                    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
                    Write-OutputColor "  │$("  NO MATCHING AGENTS FOUND".PadRight(72))│" -color "Warning"
                    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                    Write-OutputColor "  │$("  Search term: $searchTerm".PadRight(72))│" -color "Info"
                    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
                    Write-OutputColor "  │$("  If this is a new site, please contact $($script:SupportContact) to add the agent".PadRight(72))│" -color "Info"
                    Write-OutputColor "  │$("  to the FileServer $($script:AgentInstaller.FolderName) folder.".PadRight(72))│" -color "Info"
                    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
                    Write-PressEnter
                }
                elseif ($results.Count -eq 1) {
                    Install-SelectedAgent -Agent $results[0]
                    Write-PressEnter
                    if ($ReturnAfterInstall) { return }
                }
                else {
                    Write-OutputColor "  Found $($results.Count) matching agents:" -color "Success"
                    $selected = Show-AgentInstallerList -Agents $results
                    if ($selected) {
                        Install-SelectedAgent -Agent $selected
                        Write-PressEnter
                        if ($ReturnAfterInstall) { return }
                    }
                }
            }
            'R' {
                $null = Get-AgentInstallerList -ForceRefresh
                Write-PressEnter
            }
            'B' { return }
        }
    }
}

# ============================================================================
# MULTI-AGENT SUPPORT (v1.8.0)
# ============================================================================

# Get all agent configs (primary + additional agents from defaults.json)
function Get-AllAgentConfigs {
    $configs = @()

    # Primary agent
    $configs += @{
        ToolName = $script:AgentInstaller.ToolName
        FolderName = $script:AgentInstaller.FolderName
        FilePattern = $script:AgentInstaller.FilePattern
        ServiceName = $script:AgentInstaller.ServiceName
        InstallArgs = $script:AgentInstaller.InstallArgs
        InstallPaths = $script:AgentInstaller.InstallPaths
        SuccessExitCodes = $script:AgentInstaller.SuccessExitCodes
        TimeoutSeconds = $script:AgentInstaller.TimeoutSeconds
        IsPrimary = $true
    }

    # Additional agents from defaults.json
    if ($script:AdditionalAgents -and $script:AdditionalAgents.Count -gt 0) {
        foreach ($agent in $script:AdditionalAgents) {
            $configs += @{
                ToolName = $agent.ToolName
                FolderName = if ($agent.FolderName) { $agent.FolderName } else { "Agents" }
                FilePattern = if ($agent.FilePattern) { $agent.FilePattern } else { "$($agent.ToolName).*\.exe$" }
                ServiceName = if ($agent.ServiceName) { $agent.ServiceName } else { "$($agent.ToolName)*" }
                InstallArgs = if ($agent.InstallArgs) { $agent.InstallArgs } else { "/s /norestart" }
                InstallPaths = if ($agent.InstallPaths) { @($agent.InstallPaths) } else { @() }
                SuccessExitCodes = if ($agent.SuccessExitCodes) { @($agent.SuccessExitCodes) } else { @(0) }
                TimeoutSeconds = if ($agent.TimeoutSeconds) { $agent.TimeoutSeconds } else { 300 }
                IsPrimary = $false
            }
        }
    }

    return $configs
}

# Generic agent installed check by config
function Test-AgentInstalledByConfig {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$AgentConfig
    )

    # Check for agent service
    $agentService = Get-Service -Name $AgentConfig.ServiceName -ErrorAction SilentlyContinue
    if ($agentService) {
        return @{ Installed = $true; Status = $agentService.Status; ServiceName = $agentService.Name }
    }

    # Check configured installation paths
    foreach ($path in $AgentConfig.InstallPaths) {
        $expandedPath = [Environment]::ExpandEnvironmentVariables($path)
        if (Test-Path $expandedPath) {
            return @{ Installed = $true; Status = "Files Found"; Path = $expandedPath }
        }
    }

    return @{ Installed = $false }
}

# Show agent management menu — status of all agents, install/uninstall per agent
function Show-AgentManagement {
    param([switch]$ReturnAfterInstall)

    # If no additional agents configured, fall back to original menu
    $allConfigs = Get-AllAgentConfigs
    if ($allConfigs.Count -le 1) {
        Install-Agent -ReturnAfterInstall:$ReturnAfterInstall
        return
    }

    while ($true) {
        if ($global:ReturnToMainMenu) { return }

        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                       AGENT MANAGEMENT").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  AGENT STATUS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        $idx = 1
        foreach ($config in $allConfigs) {
            $status = Test-AgentInstalledByConfig -AgentConfig $config
            $statusText = if ($status.Installed) {
                if ($status.Status -eq "Running") { "Installed & Running" } else { "Installed ($($status.Status))" }
            } else { "Not Installed" }
            $color = if ($status.Installed -and $status.Status -eq "Running") { "Success" } elseif ($status.Installed) { "Warning" } else { "Error" }
            $icon = if ($status.Installed) { "[OK]" } else { "[--]" }
            $primary = if ($config.IsPrimary) { " (primary)" } else { "" }
            $line = "  $icon [$idx] $($config.ToolName)$primary`: $statusText"
            Write-OutputColor "  │$($line.PadRight(72))│" -color $color
            $idx++
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  Enter agent number to install, or:" -color "Info"
        Write-OutputColor "  [A] Install all missing agents" -color "Info"
        Write-OutputColor "  [B] Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        if ($choice -eq 'A' -or $choice -eq 'a') {
            foreach ($config in $allConfigs) {
                $status = Test-AgentInstalledByConfig -AgentConfig $config
                if (-not $status.Installed) {
                    Write-OutputColor "  --- Installing $($config.ToolName) ---" -color "Info"
                    if ($config.IsPrimary) {
                        Install-Agent -ReturnAfterInstall
                    }
                    else {
                        Write-OutputColor "  $($config.ToolName) requires manual installation from FileServer." -color "Info"
                        Write-OutputColor "  Service: $($config.ServiceName)" -color "Info"
                    }
                }
            }
            Write-PressEnter
        }
        elseif ($choice -match '^\d+$') {
            $num = [int]$choice - 1
            if ($num -ge 0 -and $num -lt $allConfigs.Count) {
                $selectedConfig = $allConfigs[$num]
                if ($selectedConfig.IsPrimary) {
                    Install-Agent -ReturnAfterInstall:$ReturnAfterInstall
                    if ($ReturnAfterInstall) { return }
                }
                else {
                    Write-OutputColor "  $($selectedConfig.ToolName) requires manual installation." -color "Info"
                    Write-OutputColor "  Service: $($selectedConfig.ServiceName)" -color "Info"
                    Write-PressEnter
                }
            }
            else {
                Write-OutputColor "  Invalid selection." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
        elseif ($choice -eq 'b' -or $choice -eq 'B') {
            return
        }
    }
}
#endregion
