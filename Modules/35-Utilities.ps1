#region ===== UTILITY FUNCTIONS (v2.6.0) =====
# Function to compare two configuration profiles
function Compare-ConfigurationProfiles {
    Clear-Host
    Write-CenteredOutput "Compare Configuration Profiles" -color "Info"

    Write-OutputColor "  This tool compares two JSON configuration profiles." -color "Info"
    Write-OutputColor "" -color "Info"

    # Get first profile path
    Write-OutputColor "  Enter path to FIRST profile (drag and drop or type full path):" -color "Warning"
    $path1 = Read-Host
    $navResult = Test-NavigationCommand -UserInput $path1
    if ($navResult.ShouldReturn) { return }

    $path1 = $path1.Trim('"')
    if ([string]::IsNullOrWhiteSpace($path1)) {
        Write-OutputColor "  No path entered." -color "Error"
        return
    }
    if (-not (Test-Path -LiteralPath $path1)) {
        Write-OutputColor "  File not found: $path1" -color "Error"
        return
    }

    # Get second profile path
    Write-OutputColor "  Enter path to SECOND profile (drag and drop or type full path):" -color "Warning"
    $path2 = Read-Host
    $navResult = Test-NavigationCommand -UserInput $path2
    if ($navResult.ShouldReturn) { return }

    $path2 = $path2.Trim('"')
    if ([string]::IsNullOrWhiteSpace($path2)) {
        Write-OutputColor "  No path entered." -color "Error"
        return
    }
    if (-not (Test-Path -LiteralPath $path2)) {
        Write-OutputColor "  File not found: $path2" -color "Error"
        return
    }

    try {
        $profile1 = Get-Content -LiteralPath $path1 -Raw | ConvertFrom-Json
        $profile2 = Get-Content -LiteralPath $path2 -Raw | ConvertFrom-Json
    }
    catch {
        Write-OutputColor "  Error parsing JSON files: $_" -color "Error"
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
    $profile2.PSObject.Properties | ForEach-Object { if ($_.Name -notin $allProps) { $allProps += $_.Name } }
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
            $lineStr = "      Profile 1: $val1"
            if ($lineStr.Length -gt 72) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Error"
            $removed++
            $differences++
        }
        elseif (-not $hasVal1 -and $hasVal2) {
            Write-OutputColor "  │$("  [+] $prop".PadRight(72))│" -color "Success"
            $lineStr = "      Profile 2: $val2"
            if ($lineStr.Length -gt 72) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Success"
            $added++
            $differences++
        }
        elseif ($val1 -ne $val2) {
            Write-OutputColor "  │$("  [~] $prop".PadRight(72))│" -color "Warning"
            $lineStr = "      Profile 1: $val1"
            if ($lineStr.Length -gt 72) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Warning"
            $lineStr = "      Profile 2: $val2"
            if ($lineStr.Length -gt 72) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Warning"
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

    # Check network connectivity if no cached result available
    if (-not $script:LatestRelease -and -not (Test-NetworkConnectivity)) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  No network connectivity. Cannot check for updates." -color "Error"
        Write-OutputColor "  Tip: Verify network configuration and DNS settings." -color "Warning"
        Write-PressEnter
        return
    }

    try {
        # Always fetch fresh when user manually checks for updates
        $repoApiUrl = "https://api.github.com/repos/TheAbider/RackStack/releases/latest"
        $release = Invoke-RestMethod -Uri $repoApiUrl -TimeoutSec 10 -ErrorAction Stop

        # Update cached state so menu banner reflects latest check
        $remoteVersion = $release.tag_name -replace '^v', ''
        $script:UpdateCheckCompleted = $true
        $script:LatestRelease = $release
        $script:LatestVersion = $remoteVersion

        if ([version]$remoteVersion -gt [version]$script:ScriptVersion) {
            $script:UpdateAvailable = $true
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
    $assetName = if ($isExe) { "RackStack.exe" } else { "RackStack v$remoteVersion.ps1" }
    $asset = $Release.assets | Where-Object { $_.name -eq $assetName }

    # Fallback: try wildcard match if exact name not found
    if (-not $asset) {
        if ($isExe) {
            Write-OutputColor "  No .exe found in release assets." -color "Warning"
            Write-OutputColor "  Looking for .ps1 alternative..." -color "Info"
        }
        $asset = $Release.assets | Where-Object { $_.name -like "RackStack*.ps1" } | Select-Object -First 1
    }

    if (-not $asset) {
        Write-OutputColor "  No downloadable asset found in this release." -color "Error"
        Write-OutputColor "  Visit: $($Release.html_url)" -color "Info"
        return
    }

    Write-OutputColor "  Downloading $($asset.name) ($([math]::Round($asset.size / 1MB, 1)) MB)..." -color "Info"

    # Sanitize the asset name before composing the temp file path. Even though GitHub
    # asset names go through the release UI, a forged response or a name containing
    # `..\` / `/` / null byte could write outside $env:TEMP. Strip path separators
    # and reject obviously malformed names.
    $safeAssetName = [string]$asset.name
    if ($safeAssetName -match '[\\/]|\.\.|`0' -or [string]::IsNullOrWhiteSpace($safeAssetName)) {
        Write-OutputColor "  Refusing to download asset with suspicious name: '$safeAssetName'" -color "Error"
        return
    }
    $safeAssetName = $safeAssetName -replace '[^\w\.\-]', '_'
    $tempPath = Join-Path $env:TEMP "RackStack_update_$safeAssetName"

    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempPath -UseBasicParsing -ErrorAction Stop
        Write-OutputColor "  Download complete." -color "Success"
    }
    catch {
        Write-OutputColor "  Download failed: $($_.Exception.Message)" -color "Error"
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        return
    }

    # Verify the download is not empty
    if (-not (Test-Path -LiteralPath $tempPath) -or (Get-Item -LiteralPath $tempPath).Length -lt 1000) {
        Write-OutputColor "  Downloaded file appears invalid." -color "Error"
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        return
    }

    # SHA256 integrity verification
    $expectedHash = $null
    if ($Release.body) {
        # Parse SHA256 hash from release notes (format: "abcdef123...  filename")
        $hashPattern = '([0-9a-fA-F]{64})\s+' + [regex]::Escape($asset.name)
        if ($Release.body -match $hashPattern) {
            $regexMatches = $matches
            $expectedHash = $regexMatches[1].ToUpper()
        }
    }

    if ($expectedHash) {
        Write-OutputColor "  Verifying SHA256 integrity..." -color "Info"
        # Initialize so a fallback-path failure can't leave a stale $actualHash from an outer
        # scope (or pre-loop iteration) that spuriously compares equal to $expectedHash.
        $actualHash = $null
        try {
            $actualHash = (Get-FileHash -Path $tempPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpper()
        }
        catch {
            # Fallback for environments where Get-FileHash is unavailable
            $sha256 = $null
            $stream = $null
            try {
                $sha256 = [System.Security.Cryptography.SHA256]::Create()
                $stream = [System.IO.File]::OpenRead($tempPath)
                $hashBytes = $sha256.ComputeHash($stream)
                $actualHash = ($hashBytes | ForEach-Object { $_.ToString("X2") }) -join ""
            }
            catch {
                # Both paths failed (file locked by AV, no read permission, etc) — refuse to run.
                Write-OutputColor "  SHA256 hash could not be computed: $($_.Exception.Message)" -color "Error"
                Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
                return
            }
            finally {
                if ($stream) { $stream.Close() }
                if ($sha256) { $sha256.Dispose() }
            }
        }

        if ($null -eq $actualHash -or [string]::IsNullOrWhiteSpace($actualHash)) {
            Write-OutputColor "  SHA256 hash compute returned empty — refusing unverified install." -color "Error"
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
            return
        }

        if ($actualHash -eq $expectedHash) {
            $hashDisplay = if ($actualHash.Length -ge 16) { $actualHash.Substring(0,16) + "..." } else { $actualHash }
            Write-OutputColor "  SHA256 verified: $hashDisplay" -color "Success"
        }
        else {
            Write-OutputColor "  SHA256 MISMATCH - download may be corrupted or tampered with!" -color "Error"
            Write-OutputColor "  Expected: $expectedHash" -color "Error"
            Write-OutputColor "  Actual:   $actualHash" -color "Error"
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
            return
        }
    }
    else {
        Write-OutputColor "  SHA256 hash not found in release notes — skipping verification." -color "Warning"
    }

    if ($isExe) {
        # EXE self-update: write a helper batch script that replaces the exe after we exit.
        # Move the verified temp file into an admin-only-writable staging dir BEFORE building
        # the batch — this closes a TOCTOU window where a parallel process watching $env:TEMP
        # could swap the file between the SHA256 verification above and the `move /y` below.
        # Stage location: %ProgramData%\<Tool>\update\ with DACL = Administrators+SYSTEM only.
        $targetPath = $script:ScriptPath
        $stageDir = Join-Path $env:ProgramData $script:ToolName | Join-Path -ChildPath 'update'
        try {
            if (-not (Test-Path -LiteralPath $stageDir)) {
                $null = New-Item -Path $stageDir -ItemType Directory -Force -ErrorAction Stop
                # Lock down DACL — Administrators + SYSTEM only, no inheritance. Same pattern as
                # v1.98.24's batch-undo state-dir fix in 50-EntryPoint.
                $stageAcl = Get-Acl -LiteralPath $stageDir
                $stageAcl.SetAccessRuleProtection($true, $false)
                $stageAcl.Access | ForEach-Object { [void]$stageAcl.RemoveAccessRule($_) }
                $adminsSid = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544'
                $systemSid = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-18'
                $stageAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($adminsSid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
                $stageAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($systemSid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
                Set-Acl -LiteralPath $stageDir -AclObject $stageAcl -ErrorAction SilentlyContinue
            }
            $stagedPath = Join-Path $stageDir ([System.IO.Path]::GetFileName($tempPath))
            if (Test-Path -LiteralPath $stagedPath) { Remove-Item -LiteralPath $stagedPath -Force -ErrorAction SilentlyContinue }
            Move-Item -LiteralPath $tempPath -Destination $stagedPath -Force -ErrorAction Stop
            $tempPath = $stagedPath
        } catch {
            Write-OutputColor "  Warning: could not move verified binary to admin-only staging dir: $($_.Exception.Message)" -color "Warning"
            Write-OutputColor "  Continuing with TEMP path; a parallel process could theoretically swap the file." -color "Warning"
        }

        # Sanitize paths for batch file injection prevention:
        # Remove characters that could escape quoting in cmd.exe (& | < > ^ " %)
        $safeTempPath = $tempPath -replace '[&|<>^"%]', '_'
        $safeTargetPath = $targetPath -replace '[&|<>^"%]', '_'
        # If sanitization changed the paths, abort — don't create a broken batch
        if ($safeTempPath -ne $tempPath -or $safeTargetPath -ne $targetPath) {
            Write-OutputColor "  ERROR: File paths contain characters unsafe for batch update." -color "Error"
            Write-OutputColor "  Move RackStack to a path without special characters (& | < > ^ `" %)." -color "Error"
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
            return
        }
        # Embed the expected hash in the batch so the post-sleep move only proceeds if the
        # file STILL matches — closes the verify→move TOCTOU even if the staging dir DACL
        # somehow fails to apply. Uses certutil which ships on every supported Windows.
        $batchPath = Join-Path $env:TEMP "RackStack_update_$([System.IO.Path]::GetRandomFileName()).cmd"
        $batchContent = @"
@echo off
echo Updating $($script:ToolName)...
timeout /t 5 /nobreak >nul
rem Re-verify SHA256 right before the move — TOCTOU defense.
for /f "skip=1 tokens=*" %%H in ('certutil -hashfile "$tempPath" SHA256 ^| findstr /v ":"') do (
    set "ACTUAL=%%H"
    goto :hashed
)
:hashed
set "ACTUAL=%ACTUAL: =%"
if /i not "%ACTUAL%"=="$expectedHash" (
    echo SHA256 mismatch after stage — refusing to replace EXE.
    del "$tempPath" >nul 2>&1
    timeout /t 5 /nobreak >nul
    del "%~f0"
    goto :eof
)
move /y "$tempPath" "$targetPath" >nul 2>&1
if errorlevel 1 (
    echo Retry 1 - waiting for file lock to release...
    timeout /t 5 /nobreak >nul
    move /y "$tempPath" "$targetPath" >nul 2>&1
)
if errorlevel 1 (
    echo Retry 2 - final attempt...
    timeout /t 10 /nobreak >nul
    move /y "$tempPath" "$targetPath" >nul 2>&1
)
if errorlevel 1 (
    echo Update failed - could not replace file.
    del "$tempPath" >nul 2>&1
    timeout /t 5 /nobreak >nul
    goto :eof
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

        try {
            Start-Process cmd.exe -ArgumentList "/c `"$batchPath`"" -WindowStyle Hidden -ErrorAction Stop
        }
        catch {
            Remove-Item -LiteralPath $batchPath -Force -ErrorAction SilentlyContinue
            Write-OutputColor "  Failed to launch update process: $_" -color "Error"
            Write-PressEnter
            return
        }
        [Environment]::Exit(0)
    }
    else {
        # PS1 self-update: replace the script file directly
        $targetPath = $script:ScriptPath
        try {
            Copy-Item -LiteralPath $tempPath -Destination $targetPath -Force -ErrorAction Stop
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  Updated to v$remoteVersion! Restarting...".PadRight(72))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            Start-Sleep -Seconds 2
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$targetPath`"" -Verb RunAs
            [Environment]::Exit(0)
        }
        catch {
            # If the running script is locked, save alongside it
            $newPath = Join-Path $scriptDir "RackStack v$remoteVersion.ps1"
            Copy-Item -LiteralPath $tempPath -Destination $newPath -Force
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
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
        DNSChecked = $false
        Details = @()
    }

    # Test with ping. Bound it via System.Net.NetworkInformation.Ping (Test-Connection on PS 5.1
    # has no per-ping timeout and could hang ~5s per call against a black-holed IP).
    Write-OutputColor "  Testing $IPAddress..." -color "Info"
    try {
        $pinger = [System.Net.NetworkInformation.Ping]::new()
        $reply = $pinger.Send($IPAddress, 1500)
        if ($reply.Status -eq 'Success') {
            $result.InUse = $true
            $result.PingResponse = $true
            $result.Details += "IP responded to ping"
        }
        $pinger.Dispose()
    } catch {
        # Ping itself failed (bad IP format etc.) — leave InUse alone, surface in details.
        $result.Details += "Ping probe error: $($_.Exception.Message)"
    }

    # Check DNS PTR record. The prior bare catch conflated "no PTR record exists" (legitimate
    # signal that the IP is free) with "DNS server unreachable / timed out" (probe failure where
    # we can't tell). On a misconfigured forwarder the latter caused us to report "InUse = false"
    # for an IP that may have been taken — operator deployed → ARP conflict.
    # Resolve-DnsName has no built-in timeout knob; wrap in Invoke-WithTimeout.
    $dnsOutcome = Invoke-WithTimeout -TimeoutSeconds 5 -Activity "DNS PTR lookup for $IPAddress" -ScriptBlock {
        param($ip)
        Resolve-DnsName -Name $ip -Type PTR -ErrorAction Stop
    } -ArgumentList @($IPAddress)
    if ($dnsOutcome.TimedOut) {
        $result.Details += "DNS PTR check timed out (>5s) — unable to verify IP availability via DNS"
    } elseif ($dnsOutcome.Failed) {
        $errText = "$($dnsOutcome.Error)"
        # Resolve-DnsName throws different messages for "no record" vs "DNS unreachable".
        # ERROR_INVALID_NETNAME / DNS_ERROR_RCODE_NAME_ERROR == "name does not exist" → legitimate empty.
        # Other errors (DNS_ERROR_NO_DNS_SERVERS, timeout, REFUSED) → couldn't actually verify.
        if ($errText -match 'DNS name does not exist|DNS_ERROR_RCODE_NAME_ERROR|0x80004005|not found') {
            $result.DNSChecked = $true  # legit "no PTR" — IP is free per DNS
        } else {
            $result.Details += "DNS PTR check failed (not a record-not-found error): $errText"
        }
    } elseif ($dnsOutcome.Result) {
        $dns = $dnsOutcome.Result
        $result.InUse = $true
        $result.DNSEntry = $dns.NameHost
        $result.DNSChecked = $true
        $result.Details += "DNS PTR record exists: $($dns.NameHost)"
    } else {
        $result.DNSChecked = $true  # no result and no error — treat as empty
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

    Write-OutputColor "  This will apply a configuration profile to a remote server via WinRM." -color "Info"
    Write-OutputColor "" -color "Info"

    # Get remote computer name
    Write-OutputColor "  Enter the remote server name or IP:" -color "Warning"
    $remoteComputer = Read-Host
    $navResult = Test-NavigationCommand -UserInput $remoteComputer
    if ($navResult.ShouldReturn) { return }

    if ([string]::IsNullOrWhiteSpace($remoteComputer)) {
        Write-OutputColor "  No server specified." -color "Error"
        return
    }

    # Get profile path
    Write-OutputColor "  Enter path to the configuration profile JSON:" -color "Warning"
    $profilePath = Read-Host
    $navResult = Test-NavigationCommand -UserInput $profilePath
    if ($navResult.ShouldReturn) { return }

    $profilePath = $profilePath.Trim('"')
    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        Write-OutputColor "  No path entered." -color "Error"
        return
    }
    if (-not (Test-Path -LiteralPath $profilePath)) {
        Write-OutputColor "  Profile file not found: $profilePath" -color "Error"
        return
    }

    # Get credentials
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enter credentials for remote server (domain\username):" -color "Info"

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
        Write-OutputColor "  No credentials provided." -color "Error"
        return
    }

    # Pre-flight check
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Running pre-flight checks on $remoteComputer..." -color "Info"

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
        Write-OutputColor "  Failed to connect: $_" -color "Error"
        return
    }

    try {
        # Read profile content
        $profileContent = Get-Content -LiteralPath $profilePath -Raw

        # Copy profile to remote - use remote machine's temp path, not local
        Write-OutputColor "  Copying profile to remote server..." -color "Info"
        $remoteTempDir = Invoke-Command -Session $session -ScriptBlock { $env:TEMP } -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($remoteTempDir)) { $remoteTempDir = "$env:SystemRoot\Temp" }
        $remotePath = "$remoteTempDir\$($script:ToolName)ConfigProfile_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"

        Invoke-Command -Session $session -ScriptBlock {
            param($path, $content, $tempDir)
            if (-not (Test-Path $tempDir)) { New-Item -Path $tempDir -ItemType Directory -Force | Out-Null }
            # Atomic write — Invoke-Command failure mid-transfer would leave the remote with a
            # truncated profile that subsequent profile-load would reject (or worse, partially apply).
            $tmpPath = "$path.tmp"
            $content | Out-File -LiteralPath $tmpPath -Encoding UTF8 -Force
            Move-Item -LiteralPath $tmpPath -Destination $path -Force -ErrorAction Stop
        } -ArgumentList $remotePath, $profileContent, $remoteTempDir -ErrorAction Stop

        Write-OutputColor "  Profile copied to: $remotePath" -color "Success"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  To apply the profile, run the $($script:ToolFullName) on the remote server" -color "Info"
        Write-OutputColor "  and use 'Load Configuration Profile' with the path above." -color "Info"
    }
    catch {
        Write-OutputColor "  Error during remote operation: $_" -color "Error"
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

        }
        catch {
            $result.Credential.Detail = "Session failed: $($_.Exception.Message)"
        }
        finally {
            if ($session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
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
        # cmdkey.exe is the platform credential-add tool; it has no stdin/secure-string entry
        # point, so the password unavoidably appears on the command line while the process is
        # alive (visible via `Get-CimInstance Win32_Process` to any local user with
        # PROCESS_QUERY_INFORMATION). We keep the exposure window as small as possible
        # (RedirectStandardOutput suppresses cmd echo; WaitForExit caps to 10s); a future
        # iteration should P/Invoke CredWrite for true secret-handling.
        # Reject passwords containing spaces — cmdkey treats /pass:VALUE as terminated at the
        # next space, so a space-containing password would be silently truncated and the
        # stored credential would not match what the operator entered.
        $username = $Credential.UserName
        $password = $Credential.GetNetworkCredential().Password
        if ($password -match '\s') {
            Write-OutputColor "  Refusing to store credential: password contains whitespace, which cmdkey would silently truncate." -color "Error"
            $password = $null
            return $false
        }

        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = "cmdkey.exe"
        $startInfo.Arguments = "/generic:$Target /user:$username /pass:$password"
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $proc = [System.Diagnostics.Process]::Start($startInfo)
        try {
            $exited = $proc.WaitForExit(10000)
            $password = $null
            if (-not $exited) { return $false }
            return ($proc.ExitCode -eq 0)
        }
        finally {
            if ($proc) { $proc.Dispose() }
        }
    }
    catch {
        $password = $null
        Write-OutputColor "  Failed to save credential: $_" -color "Error"
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

        # Escape regex metachars in the target. Current callers pass static targets like
        # 'Config-Remote' which have no metachars, but a future target containing a dot
        # ('app.contoso.com') would silently fail to match → user re-prompted every time.
        $targetEsc = [regex]::Escape($Target)
        if ($cmdkeyOutput -match "Target: $targetEsc") {
            # Credential found — extract username and prompt with it pre-populated
            $storedUser = ""
            foreach ($line in $cmdkeyOutput) {
                if ($line -match "User:\s*(.+)$") {
                    $regexMatches = $matches
                    $storedUser = $regexMatches[1].Trim()
                    break
                }
            }
            if ($storedUser) {
                return Get-Credential -UserName $storedUser -Message "Enter password for stored credential ($storedUser)"
            }
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
        # Escape regex metachars — see Get-StoredCredential note.
        $targetEsc = [regex]::Escape($target)
        if ($cmdkeyOutput -match "Target: $targetEsc") {
            $tgtLine = "  $target"
            if ($tgtLine.Length -gt 72) { $tgtLine = $tgtLine.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($tgtLine.PadRight(72))│" -color "Success"
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
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    switch ($choice) {
        "1" {
            Write-OutputColor "" -color "Info"
            $cred = Get-Credential -Message "Enter remote server credentials"
            if ($cred) {
                if (Save-StoredCredential -Target "$($script:ToolName)Config-Remote" -Credential $cred) {
                    Write-OutputColor "  Credential saved successfully." -color "Success"
                }
            }
        }
        "2" {
            Write-OutputColor "" -color "Info"
            $cred = Get-Credential -Message "Enter domain join credentials"
            if ($cred) {
                if (Save-StoredCredential -Target "$($script:ToolName)Config-Domain" -Credential $cred) {
                    Write-OutputColor "  Credential saved successfully." -color "Success"
                }
            }
        }
        "3" {
            if (Confirm-UserAction -Message "Clear all stored credentials?") {
                foreach ($target in $credentials) {
                    $null = cmdkey /delete:$target 2>&1
                }
                Write-OutputColor "  All credentials cleared." -color "Success"
            }
        }
        "B" { return }
        default { Write-OutputColor "  Invalid selection. Enter 1-3 or B." -color "Error"; return }
    }
}

# Scheduled Task Viewer — list tasks, show status, filter by folder
function Show-ScheduledTaskViewer {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    SCHEDULED TASK VIEWER").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Gathering scheduled tasks..." -color "Info"

    try {
        $tasks = @(Get-ScheduledTask -ErrorAction Stop)
    }
    catch {
        Write-OutputColor "  Failed to query scheduled tasks: $_" -color "Error"
        return
    }

    # Filter to non-Microsoft custom tasks by default, with option to show all
    $customTasks = @($tasks | Where-Object { $_.TaskPath -notlike "\Microsoft\*" })
    $failedTasks = @($tasks | ForEach-Object {
        try {
            $info = $_ | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
            if ($null -ne $info -and $info.LastTaskResult -ne 0 -and $info.LastTaskResult -ne 267009) {
                [PSCustomObject]@{
                    Name       = $_.TaskName
                    Path       = $_.TaskPath
                    State      = $_.State
                    LastResult = $info.LastTaskResult
                    LastRun    = $info.LastRunTime
                    NextRun    = $info.NextRunTime
                }
            }
        } catch {
            Write-OutputColor "  Could not query task info for $($_.TaskName): $_" -color "Warning"
        }
    })
    $disabledTasks = @($tasks | Where-Object { $_.State -eq "Disabled" -and $_.TaskPath -notlike "\Microsoft\*" })

    # Summary
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  TASK SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Total Tasks:       $($tasks.Count)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Custom Tasks:      $($customTasks.Count) (non-Microsoft)".PadRight(72))│" -color "Info"
    $failColor = if ($failedTasks.Count -gt 0) { "Warning" } else { "Success" }
    Write-OutputColor "  │$("  Failed Last Run:   $($failedTasks.Count)".PadRight(72))│" -color $failColor
    $disColor = if ($disabledTasks.Count -gt 0) { "Warning" } else { "Info" }
    Write-OutputColor "  │$("  Disabled (Custom): $($disabledTasks.Count)".PadRight(72))│" -color $disColor
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Show custom tasks
    if ($customTasks.Count -gt 0) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  CUSTOM TASKS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        foreach ($task in $customTasks | Sort-Object TaskPath, TaskName) {
            $stateColor = switch ($task.State) {
                "Ready" { "Success" }
                "Running" { "Info" }
                "Disabled" { "Warning" }
                default { "Info" }
            }
            $info = $null
            try { $info = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue } catch { $info = $null }
            $lastRun = if ($null -ne $info -and $null -ne $info.LastRunTime -and $info.LastRunTime.Year -gt 1999) { $info.LastRunTime.ToString("MM/dd HH:mm") } else { "Never" }
            $nameStr = "$($task.TaskPath)$($task.TaskName)"
            if ($nameStr.Length -gt 44) { $nameStr = $nameStr.Substring(0, 41) + "..." }
            $line = "  $($nameStr.PadRight(44)) $($task.State.ToString().PadRight(10)) $lastRun"
            Write-OutputColor "  │$($line.PadRight(72))│" -color $stateColor
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
    }

    # Show failed tasks
    if ($failedTasks.Count -gt 0) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  FAILED TASKS (Last Run)".PadRight(72))│" -color "Warning"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        foreach ($ft in $failedTasks | Sort-Object LastRun -Descending) {
            $nameStr = "$($ft.Path)$($ft.Name)"
            if ($nameStr.Length -gt 38) { $nameStr = $nameStr.Substring(0, 35) + "..." }
            $resultHex = "0x{0:X}" -f $ft.LastResult
            $lastRun = if ($null -ne $ft.LastRun -and $ft.LastRun.Year -gt 1999) { $ft.LastRun.ToString("MM/dd HH:mm") } else { "N/A" }
            $line = "  $($nameStr.PadRight(38)) $($resultHex.PadRight(14)) $lastRun"
            Write-OutputColor "  │$($line.PadRight(72))│" -color "Warning"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }

    Add-SessionChange -Category "System" -Description "Viewed scheduled tasks ($($tasks.Count) total, $($failedTasks.Count) failed)"
}

# SMB Share Audit — list shares and check permissions
function Show-SMBShareAudit {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       SMB SHARE AUDIT").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $shares = @(Get-SmbShare -ErrorAction Stop | Where-Object { $_.Name -notlike "*$" -or $_.Name -eq "C$" -or $_.Name -eq "D$" -or $_.Name -eq "ADMIN$" })
    }
    catch {
        Write-OutputColor "  Failed to query SMB shares: $_" -color "Error"
        return
    }

    if ($shares.Count -eq 0) {
        Write-OutputColor "  No SMB shares found." -color "Info"
        return
    }

    $userShares = @($shares | Where-Object { $_.Name -notlike "*$" })
    $adminShares = @($shares | Where-Object { $_.Name -like "*$" })
    $issues = @()

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SHARE SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  User Shares:    $($userShares.Count)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Admin Shares:   $($adminShares.Count)".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Show all user-visible shares with permissions
    if ($userShares.Count -gt 0) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  USER SHARES".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        foreach ($share in $userShares | Sort-Object Name) {
            $pathStr = if ($share.Path.Length -gt 34) { $share.Path.Substring(0, 31) + "..." } else { $share.Path }
            $line = "  $($share.Name.PadRight(20)) $pathStr"
            Write-OutputColor "  │$($line.PadRight(72))│" -color "Info"

            # Check access. A permission probe failure (insufficient privileges, RPC error)
            # used to render "(could not read permissions)" without bumping $issues — the
            # final "No security issues detected" green banner was misleading on the exact
            # shares where audit was incomplete.
            try {
                $access = @(Get-SmbShareAccess -Name $share.Name -ErrorAction Stop)
                foreach ($ace in $access) {
                    $aceColor = "Info"
                    if ($ace.AccountName -match "Everyone" -and $ace.AccessRight -ne "Read") {
                        $aceColor = "Warning"
                        $issues += "Share '$($share.Name)' grants $($ace.AccessRight) to Everyone"
                    }
                    $aceLine = "    $($ace.AccountName.PadRight(30)) $($ace.AccessControlType)/$($ace.AccessRight)"
                    if ($aceLine.Length -gt 72) { $aceLine = $aceLine.Substring(0, 69) + "..." }
                    Write-OutputColor "  │$($aceLine.PadRight(72))│" -color $aceColor
                }
            } catch {
                Write-OutputColor "  │$("    (could not read permissions — audit incomplete)".PadRight(72))│" -color "Warning"
                $issues += "Share '$($share.Name)': permissions could not be audited ($($_.Exception.Message))"
            }
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
    }

    # Check encryption status
    try {
        $smbConfig = Get-SmbServerConfiguration -ErrorAction Stop
        $encryptLine = "  SMB Encryption:   $(if ($smbConfig.EncryptData) { 'Enabled' } else { 'Disabled' })"
        $encColor = if ($smbConfig.EncryptData) { "Success" } else { "Warning" }
        $smb1Line = "  SMBv1 Enabled:    $(if ($smbConfig.EnableSMB1Protocol) { 'Yes (not recommended)' } else { 'No (secure)' })"
        $smb1Color = if ($smbConfig.EnableSMB1Protocol) { "Warning" } else { "Success" }

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  SMB SECURITY".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$($encryptLine.PadRight(72))│" -color $encColor
        Write-OutputColor "  │$($smb1Line.PadRight(72))│" -color $smb1Color
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        if ($smbConfig.EnableSMB1Protocol) {
            $issues += "SMBv1 is enabled (security risk)"
        }
    } catch {
        Write-OutputColor "  Could not query SMB configuration: $_" -color "Warning"
    }

    # Issues summary
    if ($issues.Count -gt 0) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Warning"
        Write-OutputColor "  │$("  SECURITY ISSUES ($($issues.Count))".PadRight(72))│" -color "Warning"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Warning"
        foreach ($issue in $issues) {
            $issueLine = "  [!] $issue"
            if ($issueLine.Length -gt 72) { $issueLine = $issueLine.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($issueLine.PadRight(72))│" -color "Warning"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Warning"
    } else {
        Write-OutputColor "  No security issues detected." -color "Success"
    }

    Add-SessionChange -Category "System" -Description "Ran SMB share audit ($($shares.Count) shares, $($issues.Count) issues)"
}

# Installed Software Inventory — list installed programs with version, publisher, date
function Show-InstalledSoftware {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                   INSTALLED SOFTWARE INVENTORY").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Scanning installed software (registry)..." -color "Info"

    $softwareList = [System.Collections.Generic.List[PSCustomObject]]::new()
    # Per-user installs (Chrome `/silent`, NodeJS user install, Teams classic per-user) live
    # in HKCU. The original list scanned only HKLM and missed those — security-relevant
    # because a per-user install of a risky tool would not appear in compliance exports.
    $regPaths = @(
        @{ Path = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"; Scope = 'Machine' }
        @{ Path = "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"; Scope = 'Machine (WOW64)' }
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"; Scope = 'CurrentUser' }
    )

    foreach ($rp in $regPaths) {
        try {
            $entries = @(Get-ItemProperty -Path $rp.Path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne "" })
            foreach ($entry in $entries) {
                $softwareList.Add([PSCustomObject]@{
                    Name      = $entry.DisplayName
                    Version   = if ($entry.DisplayVersion) { $entry.DisplayVersion } else { "N/A" }
                    Publisher = if ($entry.Publisher) { $entry.Publisher } else { "Unknown" }
                    InstallDate = if ($entry.InstallDate -and $entry.InstallDate -match '^\d{8}$') {
                        "$($entry.InstallDate.Substring(4,2))/$($entry.InstallDate.Substring(6,2))/$($entry.InstallDate.Substring(0,4))"
                    } else { "N/A" }
                    Size      = if ($entry.EstimatedSize) { [math]::Round($entry.EstimatedSize / 1024, 1) } else { $null }
                    Scope     = $rp.Scope
                })
            }
        } catch {
            Write-OutputColor "  Could not read registry path $($rp.Path) : $_" -color "Warning"
        }
    }

    # Deduplicate by name+version
    $software = @($softwareList | Sort-Object Name, Version -Unique)

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SUMMARY: $($software.Count) programs installed".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    # Group by publisher for top publishers
    $byPublisher = $software | Group-Object Publisher | Sort-Object Count -Descending | Select-Object -First 5
    foreach ($pub in $byPublisher) {
        $pubName = if ($pub.Name -and $pub.Name.Length -gt 40) { $pub.Name.Substring(0, 37) + "..." } elseif ($pub.Name) { $pub.Name } else { "(unknown)" }
        Write-OutputColor "  │$("  $($pubName.PadRight(50)) $($pub.Count) app(s)".PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Offer search or full list
    Write-OutputColor "  [1] Show all programs" -color "Info"
    Write-OutputColor "  [2] Search by name" -color "Info"
    Write-OutputColor "  [3] Export to CSV" -color "Info"
    Write-OutputColor "  [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"
    $choice = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    switch ($choice) {
        "1" {
            Clear-Host
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  ALL INSTALLED SOFTWARE ($($software.Count))".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($app in $software | Sort-Object Name) {
                $name = if ($app.Name -and $app.Name.Length -gt 40) { $app.Name.Substring(0, 37) + "..." } elseif ($app.Name) { $app.Name } else { "(unknown)" }
                $ver = if ($app.Version -and $app.Version.Length -gt 14) { $app.Version.Substring(0, 11) + "..." } elseif ($app.Version) { $app.Version } else { "" }
                $line = "  $($name.PadRight(42)) $($ver.PadRight(14)) $($app.InstallDate)"
                Write-OutputColor "  │$($line.PadRight(72))│" -color "Info"
            }
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        }
        "2" {
            Write-OutputColor "  Enter search term:" -color "Info"
            $term = Read-Host "  Search"
            $navResult = Test-NavigationCommand -UserInput $term
            if ($navResult.ShouldReturn) { return }
            if ([string]::IsNullOrWhiteSpace($term)) { return }
            $matches_ = @($software | Where-Object { $_.Name -like "*$term*" -or $_.Publisher -like "*$term*" })
            Clear-Host
            Write-OutputColor "" -color "Info"
            $resultHeader = "  SEARCH: '$term' ($($matches_.Count) results)"
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$($resultHeader.PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            if ($matches_.Count -eq 0) {
                Write-OutputColor "  │$("  No matching software found.".PadRight(72))│" -color "Info"
            } else {
                foreach ($app in $matches_ | Sort-Object Name) {
                    $name = if ($app.Name -and $app.Name.Length -gt 40) { $app.Name.Substring(0, 37) + "..." } elseif ($app.Name) { $app.Name } else { "(unknown)" }
                    $ver = if ($app.Version -and $app.Version.Length -gt 14) { $app.Version.Substring(0, 11) + "..." } elseif ($app.Version) { $app.Version } else { "" }
                    $line = "  $($name.PadRight(42)) $($ver.PadRight(14)) $($app.InstallDate)"
                    Write-OutputColor "  │$($line.PadRight(72))│" -color "Info"
                }
            }
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        }
        "3" {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            # Sanitize $env:COMPUTERNAME for filename use (env var is process-writable).
            $hostSlug = $env:COMPUTERNAME -replace '[^\w\-]', '_'
            $csvPath = "$script:TempPath\SoftwareInventory_${hostSlug}_$timestamp.csv"
            try {
                # Atomic write — Export-Csv mid-kill produces a half-truncated CSV.
                $tmpCsv = "$csvPath.tmp"
                $software | Sort-Object Name |
                    Select-Object Name, Version, Publisher, InstallDate, @{N='SizeMB';E={$_.Size}} |
                    Export-Csv -LiteralPath $tmpCsv -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
                Move-Item -LiteralPath $tmpCsv -Destination $csvPath -Force -ErrorAction Stop
                Write-OutputColor "  Exported $($software.Count) entries to:" -color "Success"
                Write-OutputColor "  $csvPath" -color "Info"
            } catch {
                Write-OutputColor "  Export failed: $_" -color "Error"
            }
        }
        "B" { return }
        default { Write-OutputColor "  Invalid selection. Enter 1-3 or B." -color "Error"; return }
    }

    Add-SessionChange -Category "System" -Description "Viewed installed software inventory ($($software.Count) programs)"
    Write-PressEnter
}

# Certificate Expiry Checker
function Show-CertificateExpiryCheck {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                   CERTIFICATE EXPIRY CHECK").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $stores = @(
        @{ Name = "Personal (My)";    Path = "Cert:\LocalMachine\My" }
        @{ Name = "Trusted Root CA";  Path = "Cert:\LocalMachine\Root" }
        @{ Name = "Intermediate CA";  Path = "Cert:\LocalMachine\CA" }
        @{ Name = "Web Hosting";      Path = "Cert:\LocalMachine\WebHosting" }
        @{ Name = "Remote Desktop";   Path = "Cert:\LocalMachine\Remote Desktop" }
    )

    $allCerts = @()
    $now = Get-Date
    $warnDays = 90

    foreach ($store in $stores) {
        try {
            $certs = @(Get-ChildItem -Path $store.Path -ErrorAction Stop | Where-Object {
                $null -ne $_.NotAfter
            })
            foreach ($cert in $certs) {
                $daysLeft = [math]::Round(($cert.NotAfter - $now).TotalDays, 0)
                $subject = if ($cert.Subject) { $cert.Subject } else { "(no subject)" }
                if ($subject.Length -gt 40) { $subject = $subject.Substring(0, 37) + "..." }
                $allCerts += [PSCustomObject]@{
                    Store     = $store.Name
                    Subject   = $subject
                    Thumbprint = if ($cert.Thumbprint -and $cert.Thumbprint.Length -ge 16) { $cert.Thumbprint.Substring(0, 16) + "..." } else { $cert.Thumbprint }
                    Expires   = $cert.NotAfter.ToString("MM/dd/yyyy")
                    DaysLeft  = $daysLeft
                }
            }
        } catch {
            Write-OutputColor "  Could not read $($store.Name) store: $_" -color "Warning"
        }
    }

    # Separate into categories
    $expired = @($allCerts | Where-Object { $_.DaysLeft -lt 0 })
    $expiringSoon = @($allCerts | Where-Object { $_.DaysLeft -ge 0 -and $_.DaysLeft -le $warnDays })
    $valid = @($allCerts | Where-Object { $_.DaysLeft -gt $warnDays })

    # Summary
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Total Certificates:   $($allCerts.Count)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Expired:              $($expired.Count)".PadRight(72))│" -color $(if ($expired.Count -gt 0) { "Error" } else { "Success" })
    Write-OutputColor "  │$("  Expiring (≤${warnDays}d):     $($expiringSoon.Count)".PadRight(72))│" -color $(if ($expiringSoon.Count -gt 0) { "Warning" } else { "Success" })
    Write-OutputColor "  │$("  Valid:                $($valid.Count)".PadRight(72))│" -color "Success"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Show expired certs
    if ($expired.Count -gt 0) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Error"
        Write-OutputColor "  │$("  EXPIRED CERTIFICATES ($($expired.Count))".PadRight(72))│" -color "Error"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Error"
        foreach ($cert in ($expired | Sort-Object DaysLeft)) {
            $line = "  $($cert.Subject.PadRight(42)) $($cert.Expires) ($($cert.DaysLeft)d)"
            if ($line.Length -gt 72) { $line = $line.Substring(0, 72) }
            Write-OutputColor "  │$($line.PadRight(72))│" -color "Error"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Error"
        Write-OutputColor "" -color "Info"
    }

    # Show expiring soon
    if ($expiringSoon.Count -gt 0) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Warning"
        Write-OutputColor "  │$("  EXPIRING SOON ($($expiringSoon.Count))".PadRight(72))│" -color "Warning"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Warning"
        foreach ($cert in ($expiringSoon | Sort-Object DaysLeft)) {
            $line = "  $($cert.Subject.PadRight(42)) $($cert.Expires) ($($cert.DaysLeft)d)"
            if ($line.Length -gt 72) { $line = $line.Substring(0, 72) }
            Write-OutputColor "  │$($line.PadRight(72))│" -color "Warning"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Warning"
        Write-OutputColor "" -color "Info"
    }

    # Show valid certs (just count by store)
    if ($valid.Count -gt 0) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Success"
        Write-OutputColor "  │$("  VALID CERTIFICATES BY STORE".PadRight(72))│" -color "Success"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Success"
        $grouped = $valid | Group-Object Store
        foreach ($group in $grouped) {
            Write-OutputColor "  │$("  $($group.Name): $($group.Count) certificate(s)".PadRight(72))│" -color "Success"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Success"
    }

    Add-SessionChange -Category "Security" -Description "Certificate expiry check: $($expired.Count) expired, $($expiringSoon.Count) expiring soon, $($valid.Count) valid"
    Write-PressEnter
}

# VSS Writer Health Dashboard
function Show-VSSWriterStatus {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     VSS WRITER STATUS").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Querying VSS writers..." -color "Info"

    try {
        $vssOutput = vssadmin list writers 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-OutputColor "  Failed to query VSS writers (exit code $LASTEXITCODE)" -color "Error"
            return
        }
    } catch {
        Write-OutputColor "  Could not run vssadmin: $_" -color "Error"
        return
    }

    # Parse vssadmin output. vssadmin localizes its column labels and state names on non-EN
    # Windows MUI, but the bracketed numeric state code (e.g. "[1] Stable") is language-neutral.
    # Classify by StateCode (1 = Stable per VSS_WRITER_STATE enum) so a German/Japanese host
    # doesn't report all writers as "Unknown" and render the summary as 0 stable / 0 failed.
    $writers = @()
    $currentWriter = $null
    foreach ($line in $vssOutput) {
        $lineStr = "$line".Trim()
        # Writer name lines: localized "Writer name:" → fall back to *: '...' if non-EN.
        if ($lineStr -match "^Writer name:\s*'(.+)'" -or $lineStr -match "^[^:]+:\s*'(.+)'\s*$" -and $lineStr -notmatch 'State|Error|Id') {
            $regexMatches = $matches
            if ($null -ne $currentWriter) { $writers += $currentWriter }
            $currentWriter = @{ Name = $regexMatches[1]; StateCode = -1; State = "Unknown"; LastError = "No error" }
        }
        elseif ($lineStr -match "\[(\d+)\]\s*(.+)") {
            $regexMatches = $matches
            if ($null -ne $currentWriter) {
                $currentWriter.StateCode = [int]$regexMatches[1]
                $currentWriter.State = $regexMatches[2].Trim()
            }
        }
        elseif ($lineStr -match "^Last error:\s*(.+)" -or $lineStr -match "^[^:]*[Ee]rror[^:]*:\s*(.+)") {
            $regexMatches = $matches
            if ($null -ne $currentWriter) { $currentWriter.LastError = $regexMatches[1].Trim() }
        }
    }
    if ($null -ne $currentWriter) { $writers += $currentWriter }

    # VSS_WRITER_STATE code 1 = VSS_WS_STABLE (the only healthy code).
    $stable = @($writers | Where-Object { $_.StateCode -eq 1 })
    $failed = @($writers | Where-Object { $_.StateCode -ne 1 -and $_.StateCode -ne -1 })
    $unknown = @($writers | Where-Object { $_.StateCode -eq -1 })

    # Summary
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Total Writers:   $($writers.Count)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Stable:          $($stable.Count)".PadRight(72))│" -color $(if ($stable.Count -eq $writers.Count) { "Success" } else { "Info" })
    Write-OutputColor "  │$("  Failed/Other:    $($failed.Count)".PadRight(72))│" -color $(if ($failed.Count -gt 0) { "Error" } else { "Success" })
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Show failed writers first
    if ($failed.Count -gt 0) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Error"
        Write-OutputColor "  │$("  FAILED / UNSTABLE WRITERS ($($failed.Count))".PadRight(72))│" -color "Error"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Error"
        foreach ($w in $failed) {
            $wName = $w.Name
            if ($wName.Length -gt 38) { $wName = $wName.Substring(0, 35) + "..." }
            $line = "  $($wName.PadRight(40)) $($w.State)"
            if ($line.Length -gt 72) { $line = $line.Substring(0, 72) }
            Write-OutputColor "  │$($line.PadRight(72))│" -color "Error"
            if ($w.LastError -ne "No error") {
                $errLine = "    Error: $($w.LastError)"
                if ($errLine.Length -gt 72) { $errLine = $errLine.Substring(0, 69) + "..." }
                Write-OutputColor "  │$($errLine.PadRight(72))│" -color "Warning"
            }
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Error"
        Write-OutputColor "" -color "Info"
    }

    # Show all stable writers
    if ($stable.Count -gt 0) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Success"
        Write-OutputColor "  │$("  STABLE WRITERS ($($stable.Count))".PadRight(72))│" -color "Success"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Success"
        foreach ($w in $stable) {
            $wName = $w.Name
            if ($wName.Length -gt 62) { $wName = $wName.Substring(0, 59) + "..." }
            Write-OutputColor "  │$("  $wName".PadRight(72))│" -color "Success"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Success"
    }

    Add-SessionChange -Category "System" -Description "VSS writer check: $($stable.Count) stable, $($failed.Count) failed of $($writers.Count) total"
    Write-PressEnter
}

# Event Log Alert Summary (last 24 hours)
function Show-EventLogAlerts {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                  EVENT LOG ALERTS (LAST 24 HOURS)").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $cutoff = (Get-Date).AddHours(-24)
    $logs = @("System", "Application")
    $allEvents = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($logName in $logs) {
        Write-OutputColor "  Scanning $logName log..." -color "Info"
        try {
            $events = @(Get-WinEvent -FilterHashtable @{ LogName = $logName; Level = 1,2,3; StartTime = $cutoff } -MaxEvents 500 -ErrorAction Stop)
            foreach ($e in $events) { $allEvents.Add([PSCustomObject]@{ Log = $logName; Event = $e }) }
        } catch {
            if ($_.Exception.Message -notmatch "No events were found") {
                Write-OutputColor "  Could not read $logName log: $_" -color "Warning"
            }
        }
    }

    if ($allEvents.Count -eq 0) {
        Write-OutputColor "  No critical, error, or warning events in the last 24 hours." -color "Success"
        Write-OutputColor "" -color "Info"
        Add-SessionChange -Category "System" -Description "Event log alert check: 0 events in last 24h"
        return
    }

    # Group by source
    $grouped = $allEvents | Group-Object { $_.Event.ProviderName } | Sort-Object Count -Descending

    # Summary counts
    $critCount = @($allEvents | Where-Object { $_.Event.Level -eq 1 }).Count
    $errCount = @($allEvents | Where-Object { $_.Event.Level -eq 2 }).Count
    $warnCount = @($allEvents | Where-Object { $_.Event.Level -eq 3 }).Count

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Total Events:    $($allEvents.Count)".PadRight(72))│" -color "Info"
    if ($critCount -gt 0) {
        Write-OutputColor "  │$("  Critical:        $critCount".PadRight(72))│" -color "Error"
    }
    if ($errCount -gt 0) {
        Write-OutputColor "  │$("  Errors:          $errCount".PadRight(72))│" -color "Error"
    }
    if ($warnCount -gt 0) {
        Write-OutputColor "  │$("  Warnings:        $warnCount".PadRight(72))│" -color "Warning"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Top sources
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  TOP SOURCES BY EVENT COUNT".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    $topN = $grouped | Select-Object -First 15
    foreach ($g in $topN) {
        $srcName = if ($g.Name) { $g.Name } else { "Unknown" }
        if ($srcName.Length -gt 35) { $srcName = $srcName.Substring(0, 32) + "..." }
        $latestEvent = $g.Group | Sort-Object { $_.Event.TimeCreated } -Descending | Select-Object -First 1
        $age = [math]::Round(((Get-Date) - $latestEvent.Event.TimeCreated).TotalHours, 1)
        $levelName = switch ($latestEvent.Event.Level) { 1 { "CRIT" } 2 { "ERR" } 3 { "WARN" } default { "???" } }
        $lineText = "  $($srcName.PadRight(37)) $($g.Count.ToString().PadLeft(4))  ${age}h ago  $levelName"
        if ($lineText.Length -gt 72) { $lineText = $lineText.Substring(0, 72) }
        $color = switch ($latestEvent.Event.Level) { 1 { "Error" } 2 { "Error" } 3 { "Warning" } default { "Info" } }
        Write-OutputColor "  │$($lineText.PadRight(72))│" -color $color
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Show latest 10 critical/error events
    $topEvents = @($allEvents | Where-Object { $_.Event.Level -le 2 } | Sort-Object { $_.Event.TimeCreated } -Descending | Select-Object -First 10)
    if ($topEvents.Count -gt 0) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Error"
        Write-OutputColor "  │$("  LATEST CRITICAL/ERROR EVENTS (up to 10)".PadRight(72))│" -color "Error"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Error"
        foreach ($item in $topEvents) {
            $e = $item.Event
            $time = if ($e.TimeCreated) { $e.TimeCreated.ToString("MM/dd HH:mm") } else { "N/A" }
            $src = if ($e.ProviderName) { $e.ProviderName } else { "Unknown" }
            if ($src.Length -gt 22) { $src = $src.Substring(0, 19) + "..." }
            $msg = ($e.Message -split "`n")[0]
            if ($null -eq $msg) { $msg = "Event ID $($e.Id)" }
            if ($msg.Length -gt 38) { $msg = $msg.Substring(0, 35) + "..." }
            $lineText = "  $time  $($src.PadRight(22)) $msg"
            if ($lineText.Length -gt 72) { $lineText = $lineText.Substring(0, 72) }
            Write-OutputColor "  │$($lineText.PadRight(72))│" -color "Error"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Error"
    }

    Add-SessionChange -Category "System" -Description "Event log alerts: $critCount critical, $errCount errors, $warnCount warnings from $($grouped.Count) sources in last 24h"
    Write-PressEnter
}

# Uptime & Reboot History
function Show-UptimeRebootHistory {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    UPTIME & REBOOT HISTORY").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Current uptime
    $uptimeStr = "Unknown"
    try {
        $uptCim = Invoke-WithTimeout -ScriptBlock {
            Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 8 -ErrorAction Stop
        } -TimeoutSeconds 10 -Activity "Querying uptime"
        if ($uptCim.TimedOut) { throw "CIM query timed out" }
        $os = $uptCim.Result
        $lastBoot = $os.LastBootUpTime
        $uptime = (Get-Date) - $lastBoot
        $uptimeStr = ""
        if ($uptime.Days -gt 0) { $uptimeStr += "$($uptime.Days)d " }
        $uptimeStr += "$($uptime.Hours)h $($uptime.Minutes)m"

        $uptimeColor = "Success"
        if ($uptime.Days -ge 60) { $uptimeColor = "Error" }
        elseif ($uptime.Days -ge 30) { $uptimeColor = "Warning" }

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  CURRENT UPTIME".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  Last Boot:    $($lastBoot.ToString('yyyy-MM-dd HH:mm:ss'))".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Uptime:       $uptimeStr".PadRight(72))│" -color $uptimeColor
        if ($uptime.Days -ge 60) {
            Write-OutputColor "  │$("  WARNING: Server has not rebooted in $($uptime.Days) days!".PadRight(72))│" -color "Error"
        } elseif ($uptime.Days -ge 30) {
            Write-OutputColor "  │$("  NOTE: Server uptime exceeds 30 days".PadRight(72))│" -color "Warning"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    } catch {
        Write-OutputColor "  Could not determine uptime: $_" -color "Error"
    }

    Write-OutputColor "" -color "Info"

    # Reboot history from event log (Event ID 1074 = planned shutdown/restart, 6008 = unexpected)
    Write-OutputColor "  Scanning event log for reboot history..." -color "Info"

    $reboots = @()
    try {
        $shutdownEvents = @(Get-WinEvent -FilterHashtable @{ LogName = "System"; Id = 1074 } -MaxEvents 20 -ErrorAction Stop)
        foreach ($e in $shutdownEvents) {
            $reason = ($e.Message -split "`n")[0]
            if ($null -eq $reason) { $reason = "Planned restart" }
            if ($reason.Length -gt 60) { $reason = $reason.Substring(0, 57) + "..." }
            $reboots += [PSCustomObject]@{ Time = $e.TimeCreated; Type = "Planned"; Reason = $reason }
        }
    } catch {
        if ($_.Exception.Message -notmatch "No events were found") {
            Write-OutputColor "  Could not read planned shutdown events: $_" -color "Warning"
        }
    }

    try {
        $unexpectedEvents = @(Get-WinEvent -FilterHashtable @{ LogName = "System"; Id = 6008 } -MaxEvents 10 -ErrorAction Stop)
        foreach ($e in $unexpectedEvents) {
            $reboots += [PSCustomObject]@{ Time = $e.TimeCreated; Type = "UNEXPECTED"; Reason = "Unexpected shutdown (crash/power loss)" }
        }
    } catch {
        if ($_.Exception.Message -notmatch "No events were found") {
            Write-OutputColor "  Could not read unexpected shutdown events: $_" -color "Warning"
        }
    }

    $reboots = @($reboots | Sort-Object Time -Descending | Select-Object -First 15)

    $unexpectedCount = 0
    if ($reboots.Count -eq 0) {
        Write-OutputColor "  No reboot events found in the event log." -color "Info"
    } else {
        $unexpectedCount = @($reboots | Where-Object { $_.Type -eq "UNEXPECTED" }).Count
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  REBOOT HISTORY (last $($reboots.Count) events, $unexpectedCount unexpected)".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        foreach ($r in $reboots) {
            $time = $r.Time.ToString("yyyy-MM-dd HH:mm")
            $typeStr = $r.Type.PadRight(10)
            $lineText = "  $time  $typeStr"
            if ($lineText.Length -gt 72) { $lineText = $lineText.Substring(0, 72) }
            $color = if ($r.Type -eq "UNEXPECTED") { "Error" } else { "Info" }
            Write-OutputColor "  │$($lineText.PadRight(72))│" -color $color
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }

    Add-SessionChange -Category "System" -Description "Uptime check: $uptimeStr, $($reboots.Count) reboots in history ($unexpectedCount unexpected)"
    Write-PressEnter
}

# Driver Health Check
function Show-DriverHealthCheck {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       DRIVER HEALTH CHECK").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Scanning device drivers..." -color "Info"

    # Get device/driver info in one batched CIM call
    $drvCim = Invoke-WithTimeout -ScriptBlock {
        @{
            Devices = @(Get-CimInstance Win32_PnPEntity -OperationTimeoutSec 8 -ErrorAction Stop)
            SignedDrivers = @(Get-CimInstance Win32_PnPSignedDriver -OperationTimeoutSec 8 -ErrorAction SilentlyContinue)
        }
    } -TimeoutSeconds 30 -Activity "Scanning device drivers"

    $allDevices = @()
    $problemDevices = @()
    $thirdPartyDrivers = @()
    $unsignedDrivers = @()

    if ($drvCim.TimedOut) {
        Write-OutputColor "  Device driver query timed out." -color "Error"
        return
    }

    $allDevices = @($drvCim.Result.Devices)
    $problemDevices = @($allDevices | Where-Object { $_.ConfigManagerErrorCode -ne 0 })
    $signedDrivers = @($drvCim.Result.SignedDrivers)
    $thirdPartyDrivers = @($signedDrivers | Where-Object { $null -ne $_.DriverProviderName -and $_.DriverProviderName -ne "Microsoft" -and $_.DriverProviderName -ne "" })
    $unsignedDrivers = @($signedDrivers | Where-Object { $_.IsSigned -eq $false })

    # Summary
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Total Devices:         $($allDevices.Count)".PadRight(72))│" -color "Info"
    $probColor = if ($problemDevices.Count -gt 0) { "Error" } else { "Success" }
    Write-OutputColor "  │$("  Problem Devices:       $($problemDevices.Count)".PadRight(72))│" -color $probColor
    Write-OutputColor "  │$("  Third-Party Drivers:   $($thirdPartyDrivers.Count)".PadRight(72))│" -color "Info"
    $unsignedColor = if ($unsignedDrivers.Count -gt 0) { "Warning" } else { "Success" }
    Write-OutputColor "  │$("  Unsigned Drivers:      $($unsignedDrivers.Count)".PadRight(72))│" -color $unsignedColor
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Problem devices
    if ($problemDevices.Count -gt 0) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Error"
        Write-OutputColor "  │$("  PROBLEM DEVICES ($($problemDevices.Count))".PadRight(72))│" -color "Error"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Error"
        foreach ($d in $problemDevices) {
            $devName = if ($d.Name) { $d.Name } else { "Unknown Device" }
            if ($devName.Length -gt 50) { $devName = $devName.Substring(0, 47) + "..." }
            $errDesc = switch ($d.ConfigManagerErrorCode) {
                1 { "Not configured" } 3 { "Driver corrupt" } 10 { "Cannot start" }
                12 { "Resource conflict" } 22 { "Disabled" } 28 { "Driver missing" }
                31 { "Not working" } default { "Error $($d.ConfigManagerErrorCode)" }
            }
            $lineText = "  $($devName.PadRight(52)) $errDesc"
            if ($lineText.Length -gt 72) { $lineText = $lineText.Substring(0, 72) }
            Write-OutputColor "  │$($lineText.PadRight(72))│" -color "Error"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Error"
        Write-OutputColor "" -color "Info"
    }

    # Third-party drivers (oldest first, top 15)
    if ($thirdPartyDrivers.Count -gt 0) {
        $sorted = @($thirdPartyDrivers | Where-Object { $null -ne $_.DriverDate } | Sort-Object DriverDate | Select-Object -First 15)
        if ($sorted.Count -gt 0) {
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  OLDEST THIRD-PARTY DRIVERS (by date)".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($drv in $sorted) {
                $drvName = if ($drv.DeviceName) { $drv.DeviceName } else { $drv.FriendlyName }
                if ([string]::IsNullOrEmpty($drvName)) { $drvName = "Unknown" }
                if ($drvName.Length -gt 35) { $drvName = $drvName.Substring(0, 32) + "..." }
                $dateStr = if ($drv.DriverDate) { $drv.DriverDate.ToString("yyyy-MM-dd") } else { "Unknown" }
                $ver = if ($drv.DriverVersion) { $drv.DriverVersion } else { "N/A" }
                if ($ver.Length -gt 18) { $ver = $ver.Substring(0, 15) + "..." }
                $lineText = "  $($drvName.PadRight(37)) $dateStr  $ver"
                if ($lineText.Length -gt 72) { $lineText = $lineText.Substring(0, 72) }
                $ageYears = ((Get-Date) - $drv.DriverDate).TotalDays / 365
                $color = if ($ageYears -gt 3) { "Warning" } else { "Info" }
                Write-OutputColor "  │$($lineText.PadRight(72))│" -color $color
            }
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        }
    }

    Add-SessionChange -Category "System" -Description "Driver health check: $($problemDevices.Count) problems, $($thirdPartyDrivers.Count) third-party, $($unsignedDrivers.Count) unsigned of $($allDevices.Count) devices"
}

# Disk Space Analyzer
function Show-DiskSpaceAnalyzer {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                      DISK SPACE ANALYZER").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Show all volumes
    $volCim = Invoke-WithTimeout -ScriptBlock {
        @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -OperationTimeoutSec 8 -ErrorAction Stop)
    } -TimeoutSeconds 15 -Activity "Querying disk volumes"
    if ($volCim.TimedOut) {
        Write-OutputColor "  Disk volume query timed out." -color "Error"
        return
    }
    $volumes = @($volCim.Result)

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  VOLUME OVERVIEW".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    foreach ($vol in $volumes) {
        $totalGB = [math]::Round($vol.Size / 1GB, 1)
        $freeGB = [math]::Round($vol.FreeSpace / 1GB, 1)
        $usedGB = [math]::Round(($vol.Size - $vol.FreeSpace) / 1GB, 1)
        $pctUsed = if ($vol.Size -gt 0) { [math]::Round(($vol.Size - $vol.FreeSpace) / $vol.Size * 100, 0) } else { 0 }
        $label = if ($vol.VolumeName) { $vol.VolumeName } else { "Local Disk" }
        if ($label.Length -gt 15) { $label = $label.Substring(0, 12) + "..." }
        $barLen = [math]::Min([math]::Round($pctUsed / 5), 20)
        $bar = ("█" * $barLen) + ("░" * (20 - $barLen))
        $lineText = "  $($vol.DeviceID) $($label.PadRight(15)) $bar ${pctUsed}% (${freeGB}GB free/${totalGB}GB)"
        if ($lineText.Length -gt 72) { $lineText = $lineText.Substring(0, 72) }
        $color = if ($pctUsed -ge 95) { "Error" } elseif ($pctUsed -ge 85) { "Warning" } else { "Success" }
        Write-OutputColor "  │$($lineText.PadRight(72))│" -color $color
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Scan common space hogs on system drive
    $sysDrive = $env:SystemDrive
    Write-OutputColor "  Scanning common space consumers on $sysDrive ..." -color "Info"

    $knownPaths = @(
        @{ Path = "$sysDrive\Windows\Temp"; Label = "Windows Temp" }
        @{ Path = "$sysDrive\Windows\SoftwareDistribution"; Label = "Windows Update Cache" }
        @{ Path = "$sysDrive\Windows\Installer"; Label = "Windows Installer Cache" }
        @{ Path = "$sysDrive\Windows\Logs"; Label = "Windows Logs" }
        @{ Path = "$sysDrive\Windows\WinSxS"; Label = "WinSxS (Component Store)" }
        @{ Path = "$env:TEMP"; Label = "User Temp" }
        @{ Path = "$sysDrive\inetpub\logs"; Label = "IIS Logs" }
        @{ Path = "$sysDrive\ProgramData\Microsoft\Windows\WER"; Label = "Error Reports" }
    )

    $results = @()
    foreach ($item in $knownPaths) {
        if (Test-Path -LiteralPath $item.Path) {
            try {
                $sizeBytes = (Get-ChildItem -LiteralPath $item.Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                if ($null -eq $sizeBytes) { $sizeBytes = 0 }
                $results += [PSCustomObject]@{ Label = $item.Label; Path = $item.Path; SizeGB = [math]::Round($sizeBytes / 1GB, 2) }
            } catch {
                $results += [PSCustomObject]@{ Label = $item.Label; Path = $item.Path; SizeGB = 0 }
            }
        }
    }

    $results = @($results | Sort-Object SizeGB -Descending)
    $totalScanGB = 0

    if ($results.Count -gt 0) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  SPACE CONSUMERS ON $sysDrive".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        foreach ($r in $results) {
            $sizeStr = if ($r.SizeGB -ge 1) { "$($r.SizeGB) GB" } else { "$([math]::Round($r.SizeGB * 1024, 0)) MB" }
            $lineText = "  $($r.Label.PadRight(30)) $($sizeStr.PadLeft(10))   $($r.Path)"
            if ($lineText.Length -gt 72) { $lineText = $lineText.Substring(0, 72) }
            $color = if ($r.SizeGB -ge 5) { "Warning" } else { "Info" }
            Write-OutputColor "  │$($lineText.PadRight(72))│" -color $color
        }
        $totalScanGB = [math]::Round(($results | Measure-Object -Property SizeGB -Sum).Sum, 2)
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  Total scanned:                    $totalScanGB GB".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }

    Add-SessionChange -Category "System" -Description "Disk space analysis: $($volumes.Count) volumes scanned, ${totalScanGB}GB in known consumers on $sysDrive"
    Write-PressEnter
}

# Windows Update Status Dashboard
function Show-WindowsUpdateStatus {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                   WINDOWS UPDATE STATUS").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Last update install date
    $daysSince = $null
    try {
        $lastHotfix = Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $lastHotfix -and $null -ne $lastHotfix.InstalledOn) {
            $daysSince = [math]::Round(((Get-Date) - $lastHotfix.InstalledOn).TotalDays, 0)
            $color = if ($daysSince -ge 60) { "Error" } elseif ($daysSince -ge 30) { "Warning" } else { "Success" }
            Write-OutputColor "  Last update installed: $($lastHotfix.InstalledOn.ToString('yyyy-MM-dd')) ($daysSince days ago) - $($lastHotfix.HotFixID)" -color $color
        }
    } catch {
        Write-OutputColor "  Could not query hotfix history: $_" -color "Warning"
    }

    Write-OutputColor "" -color "Info"

    # Recently installed updates (last 15)
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  RECENTLY INSTALLED UPDATES".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    try {
        $hotfixes = @(Get-HotFix -ErrorAction Stop | Where-Object { $null -ne $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 15)
        if ($hotfixes.Count -eq 0) {
            Write-OutputColor "  │$("  No hotfix records found".PadRight(72))│" -color "Warning"
        } else {
            foreach ($hf in $hotfixes) {
                $date = $hf.InstalledOn.ToString("yyyy-MM-dd")
                $desc = if ($hf.Description) { $hf.Description } else { "Update" }
                if ($desc.Length -gt 28) { $desc = $desc.Substring(0, 25) + "..." }
                $lineText = "  $($hf.HotFixID.PadRight(14)) $date  $desc"
                if ($lineText.Length -gt 72) { $lineText = $lineText.Substring(0, 72) }
                Write-OutputColor "  │$($lineText.PadRight(72))│" -color "Info"
            }
        }
    } catch {
        Write-OutputColor "  │$("  Could not query hotfixes: $_".PadRight(72))│" -color "Error"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Windows Update service status
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  UPDATE SERVICE STATUS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    $services = @("wuauserv", "BITS", "CryptSvc", "TrustedInstaller")
    foreach ($svcName in $services) {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction Stop
            $statusColor = switch ($svc.Status) { "Running" { "Success" } "Stopped" { "Warning" } default { "Info" } }
            $lineText = "  $($svc.DisplayName.PadRight(40)) $($svc.Status)"
            if ($lineText.Length -gt 72) { $lineText = $lineText.Substring(0, 72) }
            Write-OutputColor "  │$($lineText.PadRight(72))│" -color $statusColor
        } catch {
            Write-OutputColor "  │$("  $svcName - Not found".PadRight(72))│" -color "Warning"
        }
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    $updateCount = if ($hotfixes) { $hotfixes.Count } else { 0 }
    $daysSinceStr = if ($null -eq $daysSince) { "unknown" } else { "$daysSince" }
    Add-SessionChange -Category "System" -Description "Windows Update status check: $updateCount recent updates, last installed $daysSinceStr days ago"
    Write-PressEnter
}

# Open Ports & Listening Services
function Show-ListeningPorts {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                 OPEN PORTS & LISTENING SERVICES").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Scanning listening ports..." -color "Info"

    try {
        $listeners = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Sort-Object LocalPort)
    } catch {
        Write-OutputColor "  Could not query TCP connections: $_" -color "Error"
        return
    }

    # Group by port and get process info
    $portInfoList = [System.Collections.Generic.List[PSCustomObject]]::new()
    $seenPorts = @{}
    foreach ($conn in $listeners) {
        $port = $conn.LocalPort
        $addr = $conn.LocalAddress
        $key = "$addr`:$port"
        if ($seenPorts.ContainsKey($key)) { continue }
        $seenPorts[$key] = $true

        $processName = "Unknown"
        try {
            $proc = Get-Process -Id $conn.OwningProcess -ErrorAction Stop
            $processName = $proc.ProcessName
        } catch {
            $processName = "PID $($conn.OwningProcess)"
        }

        $portInfoList.Add([PSCustomObject]@{
            Port = $port
            Address = $addr
            Process = $processName
            PID = $conn.OwningProcess
        })
    }
    $portInfo = @($portInfoList)

    # Summary
    $uniquePorts = @($portInfo | Select-Object -Property Port -Unique)
    Write-OutputColor "  Total listening endpoints: $($portInfo.Count) ($($uniquePorts.Count) unique ports)" -color "Info"
    Write-OutputColor "" -color "Info"

    # Well-known ports (0-1023)
    $wellKnown = @($portInfo | Where-Object { $_.Port -le 1023 })
    if ($wellKnown.Count -gt 0) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  WELL-KNOWN PORTS (0-1023)".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        foreach ($p in $wellKnown) {
            $svcLabel = switch ($p.Port) {
                22 { "SSH" } 53 { "DNS" } 80 { "HTTP" } 135 { "RPC" } 139 { "NetBIOS" }
                389 { "LDAP" } 443 { "HTTPS" } 445 { "SMB" } 636 { "LDAPS" } 993 { "IMAPS" }
                default { "" }
            }
            $procName = $p.Process
            if ($procName.Length -gt 20) { $procName = $procName.Substring(0, 17) + "..." }
            $lineText = "  $($p.Port.ToString().PadRight(7)) $($p.Address.PadRight(17)) $($procName.PadRight(22)) $svcLabel"
            if ($lineText.Length -gt 72) { $lineText = $lineText.Substring(0, 72) }
            Write-OutputColor "  │$($lineText.PadRight(72))│" -color "Info"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
    }

    # Registered/dynamic ports (1024+)
    $highPorts = @($portInfo | Where-Object { $_.Port -gt 1023 } | Sort-Object Port)
    if ($highPorts.Count -gt 0) {
        $displayPorts = @($highPorts | Select-Object -First 25)
        $header = "HIGH PORTS (1024+)"
        if ($highPorts.Count -gt 25) { $header += " — showing first 25 of $($highPorts.Count)" }
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  $header".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        foreach ($p in $displayPorts) {
            $procName = $p.Process
            if ($procName.Length -gt 20) { $procName = $procName.Substring(0, 17) + "..." }
            $lineText = "  $($p.Port.ToString().PadRight(7)) $($p.Address.PadRight(17)) $procName"
            if ($lineText.Length -gt 72) { $lineText = $lineText.Substring(0, 72) }
            Write-OutputColor "  │$($lineText.PadRight(72))│" -color "Info"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }

    # UDP listeners
    Write-OutputColor "" -color "Info"
    try {
        $udpListeners = @(Get-NetUDPEndpoint -ErrorAction Stop | Where-Object { $_.LocalAddress -ne '::' } | Sort-Object LocalPort)
        $udpSeenPorts = @{}
        $udpInfoList = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($ep in $udpListeners) {
            $key = "$($ep.LocalAddress):$($ep.LocalPort)"
            if ($udpSeenPorts.ContainsKey($key)) { continue }
            $udpSeenPorts[$key] = $true
            $processName = "Unknown"
            try {
                $proc = Get-Process -Id $ep.OwningProcess -ErrorAction Stop
                $processName = $proc.ProcessName
            } catch {
                $processName = "PID $($ep.OwningProcess)"
            }
            $null = $udpInfoList.Add([PSCustomObject]@{
                Port = $ep.LocalPort
                Address = $ep.LocalAddress
                Process = $processName
            })
        }
        if ($udpInfoList.Count -gt 0) {
            $displayUdp = @($udpInfoList | Select-Object -First 15)
            $udpHeader = "UDP LISTENERS"
            if ($udpInfoList.Count -gt 15) { $udpHeader += " - showing first 15 of $($udpInfoList.Count)" }
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  $udpHeader".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            foreach ($u in $displayUdp) {
                $procName = $u.Process
                if ($procName.Length -gt 20) { $procName = $procName.Substring(0, 17) + "..." }
                $svcLabel = switch ($u.Port) {
                    53 { "DNS" } 67 { "DHCP" } 68 { "DHCP" } 123 { "NTP" } 137 { "NetBIOS" }
                    161 { "SNMP" } 162 { "SNMP-Trap" } 500 { "IKE" } 514 { "Syslog" }
                    default { "" }
                }
                $lineText = "  $($u.Port.ToString().PadRight(7)) $($u.Address.PadRight(17)) $($procName.PadRight(22)) $svcLabel"
                if ($lineText.Length -gt 72) { $lineText = $lineText.Substring(0, 72) }
                Write-OutputColor "  │$($lineText.PadRight(72))│" -color "Info"
            }
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        }
    } catch {
        Write-OutputColor "  Could not query UDP endpoints: $_" -color "Warning"
    }

    Add-SessionChange -Category "Network" -Description "Listening ports scan: $($portInfo.Count) TCP + $($udpInfoList.Count) UDP endpoints"
    Write-PressEnter
}

# Scheduled Task Overview
function Show-ScheduledTaskOverview {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                   SCHEDULED TASK OVERVIEW").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $allTasks = @()
    try {
        $allTasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
            $_.TaskPath -notlike '\Microsoft\Windows\*' -and $_.TaskName -notlike 'User_Feed*'
        })
    }
    catch {
        Write-OutputColor "  Failed to query scheduled tasks: $($_.Exception.Message)" -color "Error"
        return
    }

    $ready = @($allTasks | Where-Object { $_.State -eq 'Ready' })
    $running = @($allTasks | Where-Object { $_.State -eq 'Running' })
    $disabled = @($allTasks | Where-Object { $_.State -eq 'Disabled' })

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Total: $(@($allTasks).Count)    Ready: $(@($ready).Count)    Running: $(@($running).Count)    Disabled: $(@($disabled).Count)".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Show failed tasks (last run result != 0 and not disabled)
    $taskInfoCollector = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($task in $allTasks) {
        $info = Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue
        if ($info) {
            $taskInfoCollector.Add([PSCustomObject]@{
                Name = $task.TaskName
                State = $task.State
                LastResult = $info.LastTaskResult
                LastRun = $info.LastRunTime
                NextRun = $info.NextRunTime
            })
        }
    }
    $taskInfoList = @($taskInfoCollector)

    $failed = @($taskInfoList | Where-Object { $_.LastResult -ne 0 -and $_.State -ne 'Disabled' -and $null -ne $_.LastRun -and $_.LastRun -ne [DateTime]::MinValue })
    if ($failed.Count -gt 0) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Error"
        Write-OutputColor "  │$("  FAILED TASKS (last run result != 0)".PadRight(72))│" -color "Error"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Error"
        foreach ($ft in $failed | Select-Object -First 15) {
            $name = if ($ft.Name.Length -gt 40) { $ft.Name.Substring(0, 37) + "..." } else { $ft.Name }
            $resultHex = "0x{0:X}" -f $ft.LastResult
            $lineText = "  $($name.PadRight(42)) Result: $resultHex"
            if ($lineText.Length -gt 72) { $lineText = $lineText.Substring(0, 72) }
            Write-OutputColor "  │$($lineText.PadRight(72))│" -color "Error"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Error"
        Write-OutputColor "" -color "Info"
    }

    # Show all non-Microsoft tasks sorted by state
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  ALL CUSTOM TASKS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    $sortedTasks = $taskInfoList | Sort-Object State, Name
    foreach ($ti in $sortedTasks | Select-Object -First 25) {
        $name = if ($ti.Name.Length -gt 35) { $ti.Name.Substring(0, 32) + "..." } else { $ti.Name }
        $stateStr = $ti.State.ToString().PadRight(10)
        $nextStr = if ($ti.NextRun -and $ti.NextRun -gt (Get-Date)) { $ti.NextRun.ToString("MM/dd HH:mm") } else { "N/A" }
        $color = switch ($ti.State) { "Ready" { "Success" } "Running" { "Info" } "Disabled" { "Debug" } default { "Warning" } }
        $lineText = "  $($name.PadRight(37)) $stateStr Next: $nextStr"
        if ($lineText.Length -gt 72) { $lineText = $lineText.Substring(0, 72) }
        Write-OutputColor "  │$($lineText.PadRight(72))│" -color $color
    }
    if (@($sortedTasks).Count -gt 25) {
        Write-OutputColor "  │$("  ... and $(@($sortedTasks).Count - 25) more tasks".PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    $failedCount = @($failed).Count
    Add-SessionChange -Category "System" -Description "Scheduled tasks: $(@($allTasks).Count) total, $failedCount failed, $(@($running).Count) running"
    Write-PressEnter
}

# Firewall Rule Summary
function Show-FirewallRuleSummary {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    FIREWALL RULE SUMMARY").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Profile status
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  FIREWALL PROFILE STATUS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    try {
        $profiles = Get-NetFirewallProfile -ErrorAction Stop
        foreach ($fwProfile in $profiles) {
            $enabled = $fwProfile.Enabled -eq $true
            $color = if ($enabled) { "Success" } else { "Error" }
            $status = if ($enabled) { "ENABLED" } else { "DISABLED" }
            $inAction = $fwProfile.DefaultInboundAction
            $outAction = $fwProfile.DefaultOutboundAction
            $lineText = "  $($fwProfile.Name.PadRight(14)) $($status.PadRight(10)) In: $($inAction.ToString().PadRight(8)) Out: $outAction"
            Write-OutputColor "  │$($lineText.PadRight(72))│" -color $color
        }
    }
    catch {
        Write-OutputColor "  │$("  Failed to query firewall profiles: $($_.Exception.Message)".PadRight(72))│" -color "Error"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Rule counts by direction
    $allRules = @()
    try {
        $allRules = @(Get-NetFirewallRule -ErrorAction Stop)
    }
    catch {
        Write-OutputColor "  Failed to query firewall rules: $($_.Exception.Message)" -color "Error"
        return
    }

    $enabledRules = @($allRules | Where-Object { $_.Enabled -eq $true })
    $disabledRules = @($allRules | Where-Object { $_.Enabled -ne $true })
    $inbound = @($enabledRules | Where-Object { $_.Direction -eq 'Inbound' })
    $outbound = @($enabledRules | Where-Object { $_.Direction -eq 'Outbound' })
    $allowIn = @($inbound | Where-Object { $_.Action -eq 'Allow' })
    $blockIn = @($inbound | Where-Object { $_.Action -eq 'Block' })
    $allowOut = @($outbound | Where-Object { $_.Action -eq 'Allow' })
    $blockOut = @($outbound | Where-Object { $_.Action -eq 'Block' })

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  RULE COUNTS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Total Rules: $(@($allRules).Count)   Enabled: $(@($enabledRules).Count)   Disabled: $(@($disabledRules).Count)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Inbound:  $(@($inbound).Count) enabled ($(@($allowIn).Count) allow, $(@($blockIn).Count) block)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Outbound: $(@($outbound).Count) enabled ($(@($allowOut).Count) allow, $(@($blockOut).Count) block)".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Recently added rules (last 30 days based on creation time approximation via display group)
    # Show top inbound allow rules by program
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  TOP INBOUND ALLOW RULES BY GROUP".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    $grouped = $allowIn | Group-Object DisplayGroup | Sort-Object Count -Descending | Select-Object -First 12
    foreach ($g in $grouped) {
        $groupName = if ($g.Name) { $g.Name } else { "(No Group)" }
        if ($groupName.Length -gt 55) { $groupName = $groupName.Substring(0, 52) + "..." }
        $lineText = "  $($groupName.PadRight(58)) $($g.Count) rules"
        Write-OutputColor "  │$($lineText.PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    Add-SessionChange -Category "Security" -Description "Firewall summary: $(@($allRules).Count) rules ($(@($enabledRules).Count) enabled), profiles: $(($profiles | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join ', ')"
    Write-PressEnter
}

# Function to show pending reboot root cause details
function Show-RebootPendingDetails {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                      REBOOT PENDING DETAILS").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $reasons = @()

    # CBS RebootPending (Windows Update / feature installs)
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
        $reason = "Component Based Servicing (CBS) — pending Windows Update or feature install"
        $reasons += $reason
        Write-OutputColor "  [!!] $reason" -color "Warning"

        # Check for specific packages pending
        $packages = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending" -ErrorAction SilentlyContinue
        if ($packages) {
            foreach ($pkg in ($packages | Select-Object -First 5)) {
                $pkgName = $pkg.PSChildName
                if ($pkgName.Length -gt 65) { $pkgName = $pkgName.Substring(0, 62) + "..." }
                Write-OutputColor "       Package: $pkgName" -color "Info"
            }
            if (@($packages).Count -gt 5) {
                Write-OutputColor "       ... and $(@($packages).Count - 5) more" -color "Info"
            }
        }
    }

    # Windows Update AutoUpdate reboot required
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
        $reason = "Windows Update — one or more updates require a reboot to complete"
        $reasons += $reason
        Write-OutputColor "  [!!] $reason" -color "Warning"
    }

    # Pending file rename operations (AV updates, in-use file replacements)
    try {
        $pfro = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($null -ne $pfro) {
            $ops = @($pfro.PendingFileRenameOperations | Where-Object { $_ -match '\S' })
            $reason = "Pending File Rename Operations — $($ops.Count) queued file operation(s)"
            $reasons += $reason
            Write-OutputColor "  [!!] $reason" -color "Warning"
            foreach ($op in ($ops | Select-Object -First 3)) {
                $opStr = if ($op.Length -gt 65) { $op.Substring(0, 62) + "..." } else { $op }
                Write-OutputColor "       $opStr" -color "Info"
            }
            if ($ops.Count -gt 3) {
                Write-OutputColor "       ... and $($ops.Count - 3) more" -color "Info"
            }
        }
    }
    catch { $null = $_ }

    # Pending computer rename
    try {
        $computerName = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName" -Name ComputerName -ErrorAction SilentlyContinue).ComputerName
        $activeComputerName = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName" -Name ComputerName -ErrorAction SilentlyContinue).ComputerName
        if ($computerName -and $activeComputerName -and $computerName -ne $activeComputerName) {
            $reason = "Pending Computer Rename — '$activeComputerName' will become '$computerName'"
            $reasons += $reason
            Write-OutputColor "  [!!] $reason" -color "Warning"
        }
    }
    catch { $null = $_ }

    # SCCM/ConfigMgr pending reboot. Detect "client genuinely absent" (expected on most boxes)
    # vs "client installed but probe failed" (RPC error, SMS Agent Host stopped, WMI repo
    # corrupt). The original bare-catch hid the latter behind the same code path as the
    # former — an operator on an SCCM-managed box could miss an actually-needed reboot
    # because the probe failed silently.
    $sccmInstalled = ($null -ne (Get-Service -Name CcmExec -ErrorAction SilentlyContinue))
    if ($sccmInstalled) {
        try {
            $ccmReboot = Invoke-CimMethod -Namespace "root\ccm\clientsdk" -ClassName "CCM_ClientUtilities" -MethodName "DetermineIfRebootPending" -ErrorAction Stop
            if ($ccmReboot -and ($ccmReboot.RebootPending -or $ccmReboot.IsHardRebootPending)) {
                $reason = "SCCM/ConfigMgr client — configuration change pending reboot"
                $reasons += $reason
                Write-OutputColor "  [!!] $reason" -color "Warning"
            }
        }
        catch {
            Write-OutputColor "  [?] SCCM client is installed but reboot-pending probe failed: $($_.Exception.Message)" -color "Warning"
            Write-OutputColor "      Check Software Center manually — RackStack could not verify SCCM state." -color "Info"
        }
    }
    # If $sccmInstalled is false, intentionally skip — SCCM absence is expected on most servers.

    # Domain join pending reboot
    try {
        $joinPending = Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\JoinDomain"
        if ($joinPending) {
            $reason = "Domain Join — pending domain membership change"
            $reasons += $reason
            Write-OutputColor "  [!!] $reason" -color "Warning"
        }
    }
    catch { $null = $_ }

    Write-OutputColor "" -color "Info"
    if ($reasons.Count -eq 0) {
        Write-OutputColor "  No pending reboot detected." -color "Success"
    } else {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  SUMMARY: $($reasons.Count) reason(s) for pending reboot".PadRight(72))│" -color "Warning"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }

    Add-SessionChange -Category "System" -Description "Reboot pending details: $($reasons.Count) reason(s) found"
    Write-PressEnter
}

# Function to show memory pressure diagnostics
function Show-MemoryDiagnostics {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     MEMORY PRESSURE DIAGNOSTICS").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Physical memory (with timeout protection)
    $memCim = Invoke-WithTimeout -ScriptBlock {
        @{
            OS     = Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 8 -ErrorAction SilentlyContinue
            PF     = Get-CimInstance Win32_PageFileUsage -OperationTimeoutSec 8 -ErrorAction SilentlyContinue
            PerfOS = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -OperationTimeoutSec 8 -ErrorAction SilentlyContinue
        }
    } -TimeoutSeconds 10 -Activity "Querying memory info"
    if ($memCim.TimedOut) {
        Write-OutputColor "  CIM query timed out. System may be under heavy load." -color "Warning"
        return
    }

    $os = $memCim.Result.OS
    if (-not $os) {
        Write-OutputColor "  Failed to query system memory information." -color "Error"
        return
    }

    $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedGB = [math]::Round($totalGB - $freeGB, 2)
    $usedPct = if ($totalGB -gt 0) { [math]::Round(($usedGB / $totalGB) * 100, 1) } else { 0 }

    $memColor = if ($usedPct -gt 90) { "Error" } elseif ($usedPct -gt 75) { "Warning" } else { "Success" }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  PHYSICAL MEMORY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Total:  $totalGB GB".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Used:   $usedGB GB ($usedPct%)".PadRight(72))│" -color $memColor
    Write-OutputColor "  │$("  Free:   $freeGB GB".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Page file
    $pageFiles = $memCim.Result.PF
    if ($pageFiles) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  PAGE FILE".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        foreach ($pf in $pageFiles) {
            $pfTotal = [math]::Round($pf.AllocatedBaseSize / 1024, 1)
            $pfUsed = [math]::Round($pf.CurrentUsage / 1024, 1)
            $pfPct = if ($pf.AllocatedBaseSize -gt 0) { [math]::Round(($pf.CurrentUsage / $pf.AllocatedBaseSize) * 100, 1) } else { 0 }
            $pfColor = if ($pfPct -gt 80) { "Warning" } else { "Info" }
            Write-OutputColor "  │$("  $($pf.Name): $pfUsed GB / $pfTotal GB ($pfPct%)".PadRight(72))│" -color $pfColor
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
    }

    # Committed memory
    $perfOS = $memCim.Result.PerfOS
    if ($perfOS) {
        $commitLimitGB = [math]::Round($perfOS.CommitLimit / 1GB, 1)
        $committedGB = [math]::Round($perfOS.CommittedBytes / 1GB, 1)
        $commitPct = if ($commitLimitGB -gt 0) { [math]::Round(($committedGB / $commitLimitGB) * 100, 1) } else { 0 }
        $commitColor = if ($commitPct -gt 90) { "Error" } elseif ($commitPct -gt 75) { "Warning" } else { "Info" }

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  COMMITTED MEMORY".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  Committed: $committedGB GB / $commitLimitGB GB ($commitPct%)".PadRight(72))│" -color $commitColor
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
    }

    # Top processes by memory
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  TOP 15 PROCESSES BY MEMORY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  PROCESS NAME                        WORKING SET   PRIVATE (MB)".PadRight(72))│" -color "Warning"
    Write-OutputColor "  │$("  $('─' * 70)".PadRight(72))│" -color "Info"

    $procs = Get-Process -ErrorAction SilentlyContinue | Sort-Object WorkingSet64 -Descending | Select-Object -First 15
    foreach ($proc in $procs) {
        $procName = if ($proc.ProcessName.Length -gt 34) { $proc.ProcessName.Substring(0, 31) + "..." } else { $proc.ProcessName.PadRight(34) }
        $wsMB = [math]::Round($proc.WorkingSet64 / 1MB, 0)
        $pmMB = if ($null -ne $proc.PrivateMemorySize64) { [math]::Round($proc.PrivateMemorySize64 / 1MB, 0) } else { 0 }
        $wsStr = "$wsMB MB".PadLeft(12)
        $pmStr = "$pmMB MB".PadLeft(12)
        Write-OutputColor "  │  $procName $wsStr $pmStr  │" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Hyper-V VM memory (if Hyper-V is installed)
    if (Test-HyperVInstalled) {
        $vms = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Running' } | Sort-Object MemoryAssigned -Descending
        if ($vms) {
            $totalVMMemGB = [math]::Round(($vms | Measure-Object -Property MemoryAssigned -Sum).Sum / 1GB, 1)
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  HYPER-V VM MEMORY (Running VMs: $(@($vms).Count), Total: $totalVMMemGB GB)".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │$("  VM NAME                         ASSIGNED    DEMAND     DYNAMIC".PadRight(72))│" -color "Warning"
            Write-OutputColor "  │$("  $('─' * 70)".PadRight(72))│" -color "Info"

            foreach ($vm in ($vms | Select-Object -First 20)) {
                $vmName = if ($vm.Name.Length -gt 30) { $vm.Name.Substring(0, 27) + "..." } else { $vm.Name.PadRight(30) }
                $assignedGB = [math]::Round($vm.MemoryAssigned / 1GB, 1)
                $demandGB = if ($null -ne $vm.MemoryDemand) { [math]::Round($vm.MemoryDemand / 1GB, 1) } else { 0 }
                $dynStr = if ($vm.DynamicMemoryEnabled) { "Yes" } else { "No" }
                Write-OutputColor "  │  $vmName $("$assignedGB GB".PadLeft(9)) $("$demandGB GB".PadLeft(9))    $($dynStr.PadRight(4))  │" -color "Info"
            }
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        }
    }

    Add-SessionChange -Category "System" -Description "Memory diagnostics: ${usedGB}GB/$($totalGB)GB ($usedPct% used)"
    Write-PressEnter
}

# Function to show currently logged on users (RDP + console sessions)
function Show-LoggedOnUsers {
    Write-OutputColor "`n  Logged-On Users:" -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $sessions = query session 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-OutputColor "  Unable to query sessions." -color "Warning"
            return
        }

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  USER SESSIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        # query session output is positional, not English. The STATE column on non-English
        # Windows MUI is translated ("Aktiv", "アクティブ", etc), so -match 'Active' returned
        # zero on de-DE/ja-JP hosts and the panel reported "Active sessions: 0" while real
        # users were logged in. Determine state from the STATE column index in the header row
        # (locale-neutral) instead.
        $activeCount = 0
        $stateColIndex = -1
        foreach ($line in $sessions) {
            $lineText = $line.ToString()
            if ([string]::IsNullOrWhiteSpace($lineText)) { continue }
            if ($lineText -match '^\s*SESSIONNAME') {
                # Find the start column of the STATE token; it's whitespace-padded so column-position is stable.
                $stateMatch = [regex]::Match($lineText, '\bSTATE\b')
                if ($stateMatch.Success) { $stateColIndex = $stateMatch.Index }
                continue
            }
            # The first session row that maps a username to a session has an "Active" state on EN
            # builds; we capture the localized active-state string from that row and then match
            # subsequent rows by string equality.
            $trimmed = $lineText.Trim()
            $stateToken = $null
            if ($stateColIndex -gt 0 -and $lineText.Length -gt $stateColIndex) {
                # Pull the STATE column slice and trim to first token.
                $stateSlice = $lineText.Substring($stateColIndex).Trim()
                if ($stateSlice -match '^\S+') { $regexMatches = $matches; $stateToken = $regexMatches[0] }
            }

            # Status detection: prefer column-slice; fall back to English Active/Disc tokens for
            # builds where SESSIONNAME wasn't parseable (some Server Core builds).
            $isActive = ($stateToken -match '^Active$|^Aktiv$|^Activo$|^Actif$|^Attivo$|^アクティブ$|^活动$') -or `
                        ($stateColIndex -lt 0 -and $trimmed -match '\bActive\b')
            $isDisc   = ($stateToken -match 'Disc') -or ($stateColIndex -lt 0 -and $trimmed -match '\bDisc')

            $color = if ($isActive) { "Success" } elseif ($isDisc) { "Warning" } else { "Info" }

            $display = "  $trimmed"
            if ($display.Length -gt 72) { $display = $display.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($display.PadRight(72))│" -color $color
            if ($isActive) { $activeCount++ }
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "  Active sessions: $activeCount" -color "Info"
    }
    catch {
        Write-OutputColor "  Failed to query sessions: $_" -color "Error"
    }
}

# Function to show current user's group memberships (useful for permission troubleshooting)
function Show-CurrentUserGroups {
    Write-OutputColor "`n  Current User Group Memberships:" -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        Write-OutputColor "  User: $($identity.Name)" -color "Info"
        Write-OutputColor "" -color "Info"

        $groups = $identity.Groups | ForEach-Object {
            try { $_.Translate([System.Security.Principal.NTAccount]).Value } catch { $_.Value }
        } | Sort-Object

        $adminGroups = @("BUILTIN\Administrators", "Domain Admins", "Enterprise Admins", "Schema Admins")

        foreach ($group in $groups) {
            $color = if ($adminGroups | Where-Object { $group -match $_ }) { "Warning" } else { "Info" }
            Write-OutputColor "    $group" -color $color
        }

        Write-OutputColor "" -color "Info"
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        Write-OutputColor "  Running as Administrator: $(if ($isAdmin) { 'Yes' } else { 'No' })" -color $(if ($isAdmin) { "Success" } else { "Warning" })
    }
    catch {
        Write-OutputColor "  Failed to enumerate groups: $_" -color "Error"
    }
}

# Function to show a quick system summary banner (hostname, IP, domain, OS, uptime)
function Show-SystemBanner {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SYSTEM SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    # Hostname + domain
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec 8 -ErrorAction SilentlyContinue
    $hostname = if ($cs) { $cs.Name } else { $env:COMPUTERNAME }
    $domain = if ($cs -and $cs.PartOfDomain) { $cs.Domain } else { "WORKGROUP" }
    Write-OutputColor "  │$("  Hostname: $hostname".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Domain:   $domain".PadRight(72))│" -color $(if ($cs -and $cs.PartOfDomain) { "Success" } else { "Warning" })

    # Primary IP
    $primaryAdapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    if ($null -ne $primaryAdapter) {
        $ip = Get-NetIPAddress -InterfaceIndex $primaryAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1
        $ipStr = if ($ip) { "$($ip.IPAddress)/$($ip.PrefixLength)" } else { "No IP" }
        Write-OutputColor "  │$("  IP:       $ipStr ($($primaryAdapter.Name))".PadRight(72))│" -color "Info"
    }

    # OS
    $ntVer = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $osName = if ($ntVer) { $ntVer.ProductName } else { "Unknown" }
    $osBuild = if ($ntVer) { "$($ntVer.CurrentBuildNumber)" } else { "" }
    $osDisplay = if ($ntVer -and $ntVer.DisplayVersion) { " ($($ntVer.DisplayVersion))" } else { "" }
    $osLine = "  OS:      $osName $osBuild$osDisplay"
    if ($osLine.Length -gt 72) { $osLine = $osLine.Substring(0, 69) + "..." }
    Write-OutputColor "  │$($osLine.PadRight(72))│" -color "Info"

    # Uptime
    try { $uptimeMs = [Environment]::TickCount64 } catch { $uptimeMs = [math]::Abs([Environment]::TickCount) }
    $uptimeDays = [math]::Floor($uptimeMs / 86400000)
    $uptimeHrs = [math]::Floor(($uptimeMs % 86400000) / 3600000)
    $uptimeStr = if ($uptimeDays -gt 0) { "${uptimeDays}d ${uptimeHrs}h" } else { "${uptimeHrs}h" }
    Write-OutputColor "  │$("  Uptime:  $uptimeStr".PadRight(72))│" -color "Info"

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}
#endregion