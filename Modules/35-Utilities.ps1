#region ===== UTILITY FUNCTIONS (v2.6.0) =====
# Function to compare two configuration profiles
function Compare-ConfigurationProfiles {
    Clear-Host
    Write-CenteredOutput "Compare Configuration Profiles" -color "Info"

    Write-OutputColor "This tool compares two JSON configuration profiles." -color "Info"
    Write-OutputColor "" -color "Info"

    # Get first profile path
    Write-OutputColor "Enter path to FIRST profile (drag and drop or type full path):" -color "Warning"
    $path1 = Read-Host
    $navResult = Test-NavigationCommand -UserInput $path1
    if ($navResult.ShouldReturn) { return }

    $path1 = $path1.Trim('"')
    if (-not (Test-Path $path1)) {
        Write-OutputColor "File not found: $path1" -color "Error"
        return
    }

    # Get second profile path
    Write-OutputColor "Enter path to SECOND profile (drag and drop or type full path):" -color "Warning"
    $path2 = Read-Host
    $navResult = Test-NavigationCommand -UserInput $path2
    if ($navResult.ShouldReturn) { return }

    $path2 = $path2.Trim('"')
    if (-not (Test-Path $path2)) {
        Write-OutputColor "File not found: $path2" -color "Error"
        return
    }

    try {
        $profile1 = Get-Content $path1 -Raw | ConvertFrom-Json
        $profile2 = Get-Content $path2 -Raw | ConvertFrom-Json
    }
    catch {
        Write-OutputColor "Error parsing JSON files: $_" -color "Error"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$("  PROFILE COMPARISON RESULTS".PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Profile 1: $(Split-Path $path1 -Leaf)" -color "Info"
    Write-OutputColor "  Profile 2: $(Split-Path $path2 -Leaf)" -color "Info"
    Write-OutputColor "" -color "Info"

    # Compare properties
    $allProps = @()
    $profile1.PSObject.Properties | ForEach-Object { $allProps += $_.Name }
    $profile2.PSObject.Properties | ForEach-Object { if ($_ -notin $allProps) { $allProps += $_.Name } }
    $allProps = $allProps | Where-Object { $_ -notlike "_*" } | Sort-Object -Unique

    $differences = 0
    $added = 0
    $removed = 0
    $changed = 0

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  DIFFERENCES".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    foreach ($prop in $allProps) {
        $val1 = $profile1.$prop
        $val2 = $profile2.$prop

        $hasVal1 = $null -ne $val1
        $hasVal2 = $null -ne $val2

        if ($hasVal1 -and -not $hasVal2) {
            Write-OutputColor "  │$("  [-] $prop".PadRight(72))│" -color "Error"
            Write-OutputColor "  │$("      Profile 1: $val1".PadRight(72))│" -color "Error"
            $removed++
            $differences++
        }
        elseif (-not $hasVal1 -and $hasVal2) {
            Write-OutputColor "  │$("  [+] $prop".PadRight(72))│" -color "Success"
            Write-OutputColor "  │$("      Profile 2: $val2".PadRight(72))│" -color "Success"
            $added++
            $differences++
        }
        elseif ($val1 -ne $val2) {
            Write-OutputColor "  │$("  [~] $prop".PadRight(72))│" -color "Warning"
            Write-OutputColor "  │$("      Profile 1: $val1".PadRight(72))│" -color "Warning"
            Write-OutputColor "  │$("      Profile 2: $val2".PadRight(72))│" -color "Warning"
            $changed++
            $differences++
        }
    }

    if ($differences -eq 0) {
        Write-OutputColor "  │$("  No differences found - profiles are identical".PadRight(72))│" -color "Success"
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Summary
    Write-OutputColor "  Summary: $differences difference(s) found" -color "Info"
    if ($added -gt 0) { Write-OutputColor "    [+] Added in Profile 2: $added" -color "Success" }
    if ($removed -gt 0) { Write-OutputColor "    [-] Removed in Profile 2: $removed" -color "Error" }
    if ($changed -gt 0) { Write-OutputColor "    [~] Changed: $changed" -color "Warning" }
}

# Silent update check - runs on launch and retries if network was unavailable
function Test-StartupUpdateCheck {
    # Skip if already completed successfully
    if ($script:UpdateCheckCompleted) { return }

    # Throttle retries to once per 60 seconds
    if ($script:UpdateCheckLastAttempt -and ((Get-Date) - $script:UpdateCheckLastAttempt).TotalSeconds -lt 60) { return }
    $script:UpdateCheckLastAttempt = Get-Date

    try {
        $repoApiUrl = "https://api.github.com/repos/TheAbider/RackStack/releases/latest"
        $release = Invoke-RestMethod -Uri $repoApiUrl -TimeoutSec 5 -ErrorAction Stop
        $remoteVersion = $release.tag_name -replace '^v', ''

        $script:UpdateCheckCompleted = $true
        if ([version]$remoteVersion -gt [version]$script:ScriptVersion) {
            $script:UpdateAvailable = $true
            $script:LatestVersion = $remoteVersion
            $script:LatestRelease = $release
        }
    }
    catch {
        # Silently ignore - will retry on next menu refresh
    }
}

# Function to check for script updates via GitHub releases
function Test-ScriptUpdate {
    Clear-Host
    Write-CenteredOutput "Check for Updates" -color "Info"

    Write-OutputColor "  Current Version: $($script:ScriptVersion)" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Checking GitHub for updates..." -color "Info"

    try {
        # Use cached release from startup check if available, otherwise fetch fresh
        if ($script:LatestRelease) {
            $release = $script:LatestRelease
        }
        else {
            $repoApiUrl = "https://api.github.com/repos/TheAbider/RackStack/releases/latest"
            $release = Invoke-RestMethod -Uri $repoApiUrl -TimeoutSec 10 -ErrorAction Stop
        }
        $remoteVersion = $release.tag_name -replace '^v', ''

        if ([version]$remoteVersion -gt [version]$script:ScriptVersion) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  UPDATE AVAILABLE!".PadRight(72))│" -color "Success"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  Current: v$($script:ScriptVersion)".PadRight(72))│" -color "Warning"
            Write-OutputColor "  │$("  Latest:  v$remoteVersion".PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

            # Show release notes
            if ($release.body) {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Release notes:" -color "Info"
                foreach ($line in ($release.body -split "`n" | Select-Object -First 15)) {
                    $cleanLine = $line.Trim() -replace '^#+\s*', '' -replace '^\*\s*', '  - '
                    if ($cleanLine) {
                        Write-OutputColor "    $cleanLine" -color "Info"
                    }
                }
            }

            Write-OutputColor "" -color "Info"
            if (Confirm-UserAction -Message "Download and install update?") {
                try {
                    Install-ScriptUpdate -Release $release
                }
                catch {
                    Write-OutputColor "  Update failed: $($_.Exception.Message)" -color "Error"
                }
            }
        }
        else {
            Write-OutputColor "  You are running the latest version!" -color "Success"
            # Clear the banner since we're up to date
            $script:UpdateAvailable = $false
        }
    }
    catch {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Unable to check for updates." -color "Warning"
        Write-OutputColor "  Error: $($_.Exception.Message)" -color "Debug"
    }

    Write-PressEnter
}

# Function to download and install an update from a GitHub release
function Install-ScriptUpdate {
    param (
        [Parameter(Mandatory)]
        [object]$Release,
        [switch]$Auto
    )

    $remoteVersion = $Release.tag_name -replace '^v', ''
    $isExe = $script:ScriptPath -like "*.exe"
    $scriptDir = Split-Path $script:ScriptPath
    $scriptName = Split-Path $script:ScriptPath -Leaf

    # Find the right asset to download
    $assetName = if ($isExe) { "RackStack.exe" } else { "RackStack.v$remoteVersion.ps1" }
    $asset = $Release.assets | Where-Object { $_.name -eq $assetName }

    # Fallback: try the monolithic ps1 if exe not found
    if (-not $asset -and $isExe) {
        Write-OutputColor "  No .exe found in release assets." -color "Warning"
        Write-OutputColor "  Looking for .ps1 alternative..." -color "Info"
        $asset = $Release.assets | Where-Object { $_.name -like "RackStack*.ps1" } | Select-Object -First 1
    }

    if (-not $asset) {
        Write-OutputColor "  No downloadable asset found in this release." -color "Error"
        Write-OutputColor "  Visit: $($Release.html_url)" -color "Info"
        return
    }

    Write-OutputColor "  Downloading $($asset.name) ($([math]::Round($asset.size / 1MB, 1)) MB)..." -color "Info"

    $tempPath = Join-Path $env:TEMP "RackStack_update_$($asset.name)"

    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempPath -UseBasicParsing -ErrorAction Stop
        Write-OutputColor "  Download complete." -color "Success"
    }
    catch {
        Write-OutputColor "  Download failed: $($_.Exception.Message)" -color "Error"
        return
    }

    # Verify the download is not empty
    if (-not (Test-Path $tempPath) -or (Get-Item $tempPath).Length -lt 1000) {
        Write-OutputColor "  Downloaded file appears invalid." -color "Error"
        Remove-Item $tempPath -ErrorAction SilentlyContinue
        return
    }

    if ($isExe) {
        # EXE self-update: write a helper batch script that replaces the exe after we exit
        $targetPath = $script:ScriptPath
        $batchPath = Join-Path $env:TEMP "RackStack_update.cmd"
        $batchContent = @"
@echo off
echo Updating RackStack...
timeout /t 2 /nobreak >nul
move /y "$tempPath" "$targetPath"
if errorlevel 1 (
    echo Update failed - file may be in use. Retrying...
    timeout /t 3 /nobreak >nul
    move /y "$tempPath" "$targetPath"
)
echo Update complete. Restarting...
start "" "$targetPath"
del "%~f0"
"@
        [System.IO.File]::WriteAllText($batchPath, $batchContent)

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  Update ready! RackStack will restart automatically.".PadRight(72))│" -color "Success"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        if (-not $Auto) {
            Write-OutputColor "  Press Enter to apply update and restart..." -color "Info"
            Read-Host
        }

        Start-Process cmd.exe -ArgumentList "/c `"$batchPath`"" -WindowStyle Hidden
        [Environment]::Exit(0)
    }
    else {
        # PS1 self-update: replace the script file directly
        $targetPath = $script:ScriptPath
        try {
            Copy-Item -Path $tempPath -Destination $targetPath -Force -ErrorAction Stop
            Remove-Item $tempPath -ErrorAction SilentlyContinue
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  Updated to v$remoteVersion! Please restart the tool.".PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        }
        catch {
            # If the running script is locked, save alongside it
            $newPath = Join-Path $scriptDir "RackStack v$remoteVersion.ps1"
            Copy-Item -Path $tempPath -Destination $newPath -Force
            Remove-Item $tempPath -ErrorAction SilentlyContinue
            Write-OutputColor "  Could not replace running script." -color "Warning"
            Write-OutputColor "  New version saved as: $newPath" -color "Info"
        }
    }
}

# Function to check if computer name exists in Active Directory
function Test-ComputerNameInAD {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName
    )

    try {
        # Check if RSAT AD module is available
        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            return @{
                Checked = $false
                Exists = $false
                Message = "Active Directory module not available"
                DN = $null
            }
        }

        Import-Module ActiveDirectory -ErrorAction Stop

        $computer = Get-ADComputer -Identity $ComputerName -ErrorAction Stop
        return @{
            Checked = $true
            Exists = $true
            Message = "Computer '$ComputerName' already exists in AD"
            DN = $computer.DistinguishedName
        }
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        return @{
            Checked = $true
            Exists = $false
            Message = "Computer name is available"
            DN = $null
        }
    }
    catch {
        return @{
            Checked = $false
            Exists = $false
            Message = "Unable to check AD: $_"
            DN = $null
        }
    }
}

# Function to check if an IP address is already in use
function Test-IPAddressInUse {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$IPAddress
    )

    $result = @{
        InUse = $false
        PingResponse = $false
        DNSEntry = $null
        Details = @()
    }

    # Test with ping
    Write-OutputColor "  Testing $IPAddress..." -color "Info"

    $ping = Test-Connection -ComputerName $IPAddress -Count 1 -Quiet -ErrorAction SilentlyContinue
    if ($ping) {
        $result.InUse = $true
        $result.PingResponse = $true
        $result.Details += "IP responded to ping"
    }

    # Check DNS PTR record
    try {
        $dns = Resolve-DnsName -Name $IPAddress -Type PTR -ErrorAction Stop
        if ($dns) {
            $result.InUse = $true
            $result.DNSEntry = $dns.NameHost
            $result.Details += "DNS PTR record exists: $($dns.NameHost)"
        }
    }
    catch {
        # No PTR record - that's fine
    }

    # Check ARP cache
    $arp = Get-NetNeighbor -IPAddress $IPAddress -ErrorAction SilentlyContinue
    if ($arp -and $arp.State -ne "Unreachable") {
        $result.Details += "ARP entry found: $($arp.LinkLayerAddress) ($($arp.State))"
    }

    return $result
}

# Function to apply configuration profile to remote server
function Invoke-RemoteProfileApply {
    Clear-Host
    Write-CenteredOutput "Remote Profile Application" -color "Info"

    Write-OutputColor "This will apply a configuration profile to a remote server via WinRM." -color "Info"
    Write-OutputColor "" -color "Info"

    # Get remote computer name
    Write-OutputColor "Enter the remote server name or IP:" -color "Warning"
    $remoteComputer = Read-Host
    $navResult = Test-NavigationCommand -UserInput $remoteComputer
    if ($navResult.ShouldReturn) { return }

    if ([string]::IsNullOrWhiteSpace($remoteComputer)) {
        Write-OutputColor "No server specified." -color "Error"
        return
    }

    # Get profile path
    Write-OutputColor "Enter path to the configuration profile JSON:" -color "Warning"
    $profilePath = Read-Host
    $navResult = Test-NavigationCommand -UserInput $profilePath
    if ($navResult.ShouldReturn) { return }

    $profilePath = $profilePath.Trim('"')
    if (-not (Test-Path $profilePath)) {
        Write-OutputColor "Profile file not found: $profilePath" -color "Error"
        return
    }

    # Get credentials
    Write-OutputColor "" -color "Info"
    Write-OutputColor "Enter credentials for remote server (domain\username):" -color "Info"

    # Try to get stored credential first
    $storedCred = Get-StoredCredential -Target "$($script:ToolName)Config-Remote"
    if ($storedCred) {
        if (Confirm-UserAction -Message "Use stored credential ($($storedCred.UserName))?") {
            $credential = $storedCred
        }
        else {
            $credential = Get-Credential
        }
    }
    else {
        $credential = Get-Credential
    }

    if (-not $credential) {
        Write-OutputColor "No credentials provided." -color "Error"
        return
    }

    # Pre-flight check
    Write-OutputColor "" -color "Info"
    Write-OutputColor "Running pre-flight checks on $remoteComputer..." -color "Info"

    $preflight = Test-RemoteReadiness -ComputerName $remoteComputer -Credential $credential
    Show-PreflightResults -Results $preflight

    if (-not $preflight.AllPassed) {
        if (-not (Confirm-UserAction -Message "Pre-flight checks failed. Continue anyway?")) {
            return
        }
    }

    # Establish session for file copy
    try {
        $session = New-PSSession -ComputerName $remoteComputer -Credential $credential -ErrorAction Stop
    }
    catch {
        Write-OutputColor "Failed to connect: $_" -color "Error"
        return
    }

    try {
        # Read profile content
        $profileContent = Get-Content $profilePath -Raw

        # Copy profile to remote
        Write-OutputColor "Copying profile to remote server..." -color "Info"
        $remotePath = "$($script:TempPath)\$($script:ToolName)ConfigProfile_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"

        Invoke-Command -Session $session -ScriptBlock {
            param($path, $content, $tempDir)
            if (-not (Test-Path $tempDir)) { New-Item -Path $tempDir -ItemType Directory -Force | Out-Null }
            $content | Out-File -FilePath $path -Encoding UTF8 -Force
        } -ArgumentList $remotePath, $profileContent, $script:TempPath

        Write-OutputColor "Profile copied to: $remotePath" -color "Success"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "To apply the profile, run the $($script:ToolFullName) on the remote server" -color "Info"
        Write-OutputColor "and use 'Load Configuration Profile' with the path above." -color "Info"
    }
    catch {
        Write-OutputColor "Error during remote operation: $_" -color "Error"
    }
    finally {
        Remove-PSSession $session -ErrorAction SilentlyContinue
    }
}

# Pre-flight check for remote server connectivity
function Test-RemoteReadiness {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ComputerName,
        [pscredential]$Credential
    )

    $result = @{
        ComputerName = $ComputerName
        Ping = @{ Passed = $false; Detail = "" }
        WinRMPort = @{ Passed = $false; Detail = "" }
        WSMan = @{ Passed = $false; Detail = "" }
        Credential = @{ Passed = $false; Detail = "" }
        PSVersion = @{ Passed = $false; Detail = "" }
        AllPassed = $false
    }

    # Step 1: Ping
    try {
        $pingResult = Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction SilentlyContinue
        $result.Ping.Passed = $pingResult
        $result.Ping.Detail = if ($pingResult) { "Host is reachable" } else { "Host did not respond to ICMP" }
    }
    catch {
        $result.Ping.Detail = "Ping failed: $($_.Exception.Message)"
    }

    # Step 2: WinRM port (5985)
    try {
        $tcpTest = Test-NetConnection -ComputerName $ComputerName -Port 5985 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $result.WinRMPort.Passed = $tcpTest.TcpTestSucceeded
        $result.WinRMPort.Detail = if ($tcpTest.TcpTestSucceeded) { "Port 5985 is open" } else { "Port 5985 is closed or filtered" }
    }
    catch {
        $result.WinRMPort.Detail = "Port test failed: $($_.Exception.Message)"
    }

    # Step 3: Test-WSMan
    try {
        $wsmanParams = @{ ComputerName = $ComputerName; ErrorAction = "Stop" }
        if ($Credential) { $wsmanParams.Credential = $Credential }
        $wsmanResult = Test-WSMan @wsmanParams
        $result.WSMan.Passed = ($null -ne $wsmanResult)
        $result.WSMan.Detail = if ($wsmanResult) { "WSMan responding (protocol $($wsmanResult.ProtocolVersion))" } else { "WSMan not responding" }
    }
    catch {
        $result.WSMan.Detail = "WSMan failed: $($_.Exception.Message)"
    }

    # Step 4: Credential test via session
    if ($result.WSMan.Passed) {
        try {
            $sessionParams = @{ ComputerName = $ComputerName; ErrorAction = "Stop" }
            if ($Credential) { $sessionParams.Credential = $Credential }
            $session = New-PSSession @sessionParams
            $result.Credential.Passed = $true
            $result.Credential.Detail = "Session established as $($session.Availability)"

            # Step 5: PS version
            try {
                $remoteVersion = Invoke-Command -Session $session -ScriptBlock { $PSVersionTable.PSVersion.ToString() } -ErrorAction Stop
                $result.PSVersion.Passed = $true
                $result.PSVersion.Detail = "PowerShell $remoteVersion"
            }
            catch {
                $result.PSVersion.Detail = "Could not query PS version: $($_.Exception.Message)"
            }

            Remove-PSSession $session -ErrorAction SilentlyContinue
        }
        catch {
            $result.Credential.Detail = "Session failed: $($_.Exception.Message)"
        }
    }
    else {
        $result.Credential.Detail = "Skipped (WSMan not available)"
        $result.PSVersion.Detail = "Skipped (no session)"
    }

    $result.AllPassed = $result.Ping.Passed -and $result.WinRMPort.Passed -and
                        $result.WSMan.Passed -and $result.Credential.Passed -and $result.PSVersion.Passed

    return $result
}

# Display pre-flight check results
function Show-PreflightResults {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Results
    )

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Pre-flight Results: $($Results.ComputerName)" -color "Info"
    Write-OutputColor "  $("-" * 50)" -color "Info"

    $checks = @(
        @{ Name = "Ping"; Data = $Results.Ping }
        @{ Name = "WinRM Port (5985)"; Data = $Results.WinRMPort }
        @{ Name = "WSMan Service"; Data = $Results.WSMan }
        @{ Name = "Credentials"; Data = $Results.Credential }
        @{ Name = "PowerShell Version"; Data = $Results.PSVersion }
    )

    foreach ($check in $checks) {
        $status = if ($check.Data.Passed) { "[OK]" } else { "[FAIL]" }
        $color = if ($check.Data.Passed) { "Success" } else { "Error" }
        Write-OutputColor "  $status $($check.Name): $($check.Data.Detail)" -color $color
    }

    Write-OutputColor "" -color "Info"
    if ($Results.AllPassed) {
        Write-OutputColor "  All checks passed. Remote server is ready." -color "Success"
    }
    else {
        Write-OutputColor "  Some checks failed. Remote operations may not work." -color "Warning"
    }
    Write-OutputColor "" -color "Info"
}

# Function to save credentials to Windows Credential Manager
function Save-StoredCredential {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Target,
        [Parameter(Mandatory=$true)]
        [PSCredential]$Credential
    )

    try {
        # Use cmdkey for credential storage
        $username = $Credential.UserName
        $password = $Credential.GetNetworkCredential().Password

        $null = cmdkey /generic:$Target /user:$username /pass:$password 2>&1
        return $true
    }
    catch {
        Write-OutputColor "Failed to save credential: $_" -color "Error"
        return $false
    }
}

# Function to retrieve stored credentials
function Get-StoredCredential {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Target
    )

    try {
        # Check if credential exists
        $cmdkeyOutput = cmdkey /list:$Target 2>&1

        if ($cmdkeyOutput -match "Target: $Target") {
            # Credential exists - prompt for it since we can't retrieve password directly
            # In a real implementation, you'd use the CredentialManager module
            return $null  # Return null to trigger re-prompt
        }
        return $null
    }
    catch {
        return $null
    }
}

# Function to manage stored credentials
function Show-CredentialManager {
    Clear-Host
    Write-CenteredOutput "Credential Manager" -color "Info"

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  STORED CREDENTIALS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    # List tool-related credentials
    $credentials = @(
        "$($script:ToolName)Config-Remote",
        "$($script:ToolName)Config-Domain"
    )

    $found = $false
    foreach ($target in $credentials) {
        $cmdkeyOutput = cmdkey /list:$target 2>&1 | Out-String
        if ($cmdkeyOutput -match "Target: $target") {
            Write-OutputColor "  │$("  $target".PadRight(72))│" -color "Success"
            $found = $true
        }
    }

    if (-not $found) {
        Write-OutputColor "  │$("  No stored credentials found".PadRight(72))│" -color "Info"
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  [1] Add/Update Remote Server Credential" -color "Success"
    Write-OutputColor "  [2] Add/Update Domain Join Credential" -color "Success"
    Write-OutputColor "  [3] Clear All Stored Credentials" -color "Success"
    Write-OutputColor "  [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"

    switch ($choice) {
        "1" {
            Write-OutputColor "" -color "Info"
            $cred = Get-Credential -Message "Enter remote server credentials"
            if ($cred) {
                if (Save-StoredCredential -Target "$($script:ToolName)Config-Remote" -Credential $cred) {
                    Write-OutputColor "Credential saved successfully." -color "Success"
                }
            }
        }
        "2" {
            Write-OutputColor "" -color "Info"
            $cred = Get-Credential -Message "Enter domain join credentials"
            if ($cred) {
                if (Save-StoredCredential -Target "$($script:ToolName)Config-Domain" -Credential $cred) {
                    Write-OutputColor "Credential saved successfully." -color "Success"
                }
            }
        }
        "3" {
            if (Confirm-UserAction -Message "Clear all stored credentials?") {
                foreach ($target in $credentials) {
                    $null = cmdkey /delete:$target 2>&1
                }
                Write-OutputColor "All credentials cleared." -color "Success"
            }
        }
        "B" { return }
        default { return }
    }
}
#endregion