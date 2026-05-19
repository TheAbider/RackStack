#region ===== VHD MANAGEMENT =====
# Function to get the cache path based on deployment mode
function Get-VHDCachePath {
    if ($script:VMDeploymentMode -eq "Cluster") {
        return $script:ClusterVHDCachePath
    }
    return $script:VHDCachePath
}

# Function to show OS version selection for VHD/ISO downloads
function Show-OSVersionMenu {
    param (
        [string]$Title = "SELECT WINDOWS SERVER VERSION"
    )

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │  $($Title.PadRight(70))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │                                                                        │" -color "Info"
    Write-OutputColor "  │   [1]  Windows Server 2025                                             │" -color "Success"
    Write-OutputColor "  │   [2]  Windows Server 2022                                             │" -color "Success"
    Write-OutputColor "  │   [3]  Windows Server 2019                                             │" -color "Success"
    Write-OutputColor "  │                                                                        │" -color "Info"
    Write-OutputColor "  │   [4]  ◄ Back                                                          │" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select version"

    switch ($choice) {
        "1" { return "2025" }
        "2" { return "2022" }
        "3" { return "2019" }
        "4" { return $null }
        default {
            $navResult = Test-NavigationCommand -UserInput $choice
            if ($navResult.ShouldReturn) { return $null }
            Write-OutputColor "  Invalid choice. Enter 1-4." -color "Error"
            return $null
        }
    }
}

# Function to check if a sysprepped VHD is already cached locally
function Test-CachedVHD {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$OSVersion
    )

    $cachePath = Get-VHDCachePath

    # Search local disk for any VHDX matching the OS version
    if (Test-Path -LiteralPath $cachePath) {
        $found = Get-ChildItem -LiteralPath $cachePath -Filter "*$OSVersion*.vhdx" -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            return @{
                Exists = $true
                Path = $found.FullName
                FileName = $found.Name
                Size = $found.Length
                LastModified = $found.LastWriteTime
            }
        }
    }

    return @{ Exists = $false; Path = $null; Size = 0 }
}

# Function to download a sysprepped VHD from FileServer
function Get-SyspreppedVHD {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$OSVersion
    )

    $cachePath = Get-VHDCachePath

    # Discover the VHD file from FileServer
    $driveFile = Find-FileServerFile -FolderPath $script:FileServer.VHDsFolder -Keyword $OSVersion -Extension "vhdx"
    if (-not $driveFile) {
        Write-OutputColor "  No VHD found for Server $OSVersion in FileServer." -color "Error"
        Write-OutputColor "  Upload a VHDX containing '$OSVersion' in the filename to the VHDs folder." -color "Warning"
        return $null
    }

    # Check if already cached
    $cached = Test-CachedVHD -OSVersion $OSVersion

    $sizeMismatch = $false
    if ($cached.Exists) {
        # Integrity check: size mismatch = corrupt or incomplete transfer.
        # Use a 1 MB tolerance because some transfer paths (SMB sparse-copy, certain
        # CDN edge nodes) introduce small alignment differences without actually
        # corrupting the content. Anything bigger than 1 MB is a real discrepancy.
        $remoteSize = Get-FileServerFileSize -FilePath $driveFile.FilePath
        if ($remoteSize -gt 0 -and [math]::Abs($cached.Size - $remoteSize) -gt 1MB) {
            Write-OutputColor "  Cached VHD size mismatch (local: $([math]::Round($cached.Size/1GB, 2))GB, remote: $([math]::Round($remoteSize/1GB, 2))GB)" -color "Warning"
            if (Confirm-UserAction -Message "Delete mismatched cache and re-download?") {
                Remove-Item -LiteralPath $cached.Path -Force -ErrorAction SilentlyContinue
                $cached = @{ Exists = $false; Path = $null; Size = 0 }
            } else {
                $sizeMismatch = $true
            }
        }

        # Integrity check: filename mismatch = newer version available
        if ($cached.Exists -and $cached.FileName -ne $driveFile.FileName) {
            $sizeGB = [math]::Round($cached.Size / 1GB, 2)
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  [UP] UPDATE AVAILABLE".PadRight(72))│" -color "Warning"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            $localName = if ($cached.FileName) { $cached.FileName.Substring(0, [Math]::Min(62, $cached.FileName.Length)) } else { "(unknown)" }
            $remoteName = if ($driveFile.FileName) { $driveFile.FileName.Substring(0, [Math]::Min(62, $driveFile.FileName.Length)) } else { "(unknown)" }
            Write-OutputColor "  │  Local:  $($localName.PadRight(62))│" -color "Info"
            Write-OutputColor "  │  Remote: $($remoteName.PadRight(62))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            Write-OutputColor "" -color "Info"

            if (Confirm-UserAction -Message "Replace local VHD with newer version?") {
                Remove-Item -LiteralPath $cached.Path -Force -ErrorAction SilentlyContinue
                $cached = @{ Exists = $false; Path = $null; Size = 0 }
            }
        }
    }

    if ($cached.Exists) {
        $sizeGB = [math]::Round($cached.Size / 1GB, 2)
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  CACHED VHD FOUND".PadRight(72))│" -color "Success"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        $cachedFileName = if ($cached.FileName) { $cached.FileName.Substring(0, [Math]::Min(63, $cached.FileName.Length)) } else { "(unknown)" }
        $cachedPath = if ($cached.Path) { $cached.Path.Substring(0, [Math]::Min(63, $cached.Path.Length)) } else { "(unknown)" }
        Write-OutputColor "  │  File: $($cachedFileName.PadRight(63))│" -color "Info"
        Write-OutputColor "  │  Size: $("${sizeGB} GB".PadRight(63))│" -color "Info"
        Write-OutputColor "  │  Date: $($cached.LastModified.ToString('yyyy-MM-dd HH:mm').PadRight(63))│" -color "Info"
        Write-OutputColor "  │  Path: $($cachedPath.PadRight(63))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        if ($sizeMismatch) {
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Warning"
            Write-OutputColor "  │$("  WARNING: Size mismatch detected — cached VHD may be corrupt".PadRight(72))│" -color "Error"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Warning"
            Write-OutputColor "" -color "Info"
        }
        Write-OutputColor "  [1] Use this cached VHD$(if ($sizeMismatch) { ' (NOT RECOMMENDED)' })" -color $(if ($sizeMismatch) { "Warning" } else { "Success" })
        Write-OutputColor "  [2] Re-download (replace cached copy)" -color "Success"
        Write-OutputColor "  [3] Cancel" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return $null }

        switch ($choice) {
            "1" { return $cached.Path }
            "2" {
                Write-OutputColor "  Removing old cached VHD..." -color "Info"
                Remove-Item -LiteralPath $cached.Path -Force -ErrorAction SilentlyContinue
                # Continue to download below
            }
            default { return $null }
        }
    }

    # Pre-check: verify destination has enough free space
    if (-not $cachePath) {
        Write-OutputColor "  VHD cache path not configured. Run Host Storage Setup first." -color "Error"
        return $null
    }
    if ($cachePath -match '^[A-Za-z]:') {
        $destDriveLetter = $cachePath.Substring(0, 1)
        $destVolume = Get-Volume -DriveLetter $destDriveLetter -ErrorAction SilentlyContinue
        if ($destVolume) {
            $freeGB = [math]::Round($destVolume.SizeRemaining / 1GB, 1)
            if ($freeGB -lt 60) {
                Write-OutputColor "  WARNING: Only $freeGB GB free on ${destDriveLetter}: drive." -color "Warning"
                Write-OutputColor "  VHD downloads are typically 30-50 GB." -color "Warning"
                if (-not (Confirm-UserAction -Message "Continue with download anyway?")) {
                    return $null
                }
            }
        }
    }

    # Download the VHD
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Downloading sysprepped Server $OSVersion VHD from FileServer..." -color "Info"
    Write-OutputColor "  File: $($driveFile.FileName)" -color "Info"
    Write-OutputColor "  This is a large file and may take a while depending on connection speed." -color "Warning"
    Write-OutputColor "" -color "Info"

    $result = Get-FileServerFile -FilePath $driveFile.FilePath -DestinationPath $cachePath -FileName $driveFile.FileName -TimeoutSeconds $script:LargeFileDownloadTimeoutSeconds

    if ($result.Success) {
        Write-OutputColor "  VHD downloaded, verified, and cached successfully." -color "Success"
        return $result.FilePath
    }
    else {
        Write-OutputColor "  Failed to download VHD: $($result.Error)" -color "Error"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Troubleshooting:" -color "Warning"
        Write-OutputColor "  - Ensure FileServer is accessible" -color "Info"
        Write-OutputColor "  - Check network connectivity" -color "Info"
        return $null
    }
}

# Function to copy a cached dynamic VHD to a VM's folder and convert to fixed
function Copy-VHDForVM {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceVHDPath,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationFolder,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$VMName,

        [string]$DiskLabel = "OS"
    )

    # Path-traversal guard — VMName and DiskLabel are operator-supplied and would escape
    # $DestinationFolder via `..\` otherwise. Copy-Item / Move-Item below land at the resolved
    # path; without this guard a malicious VM name could trash arbitrary writable files.
    if ($VMName -match '[\\/]' -or $VMName -match '\.\.' -or $VMName -match '[\x00-\x1f]') {
        throw "VMName contains path-separator or unsafe characters: '$VMName'."
    }
    if ($DiskLabel -match '[\\/]' -or $DiskLabel -match '\.\.' -or $DiskLabel -match '[\x00-\x1f]') {
        throw "DiskLabel contains path-separator or unsafe characters: '$DiskLabel'."
    }
    $destFileName = "${VMName}_${DiskLabel}.vhdx"
    $destPath = Join-Path $DestinationFolder $destFileName

    # Ensure destination directory exists
    if (-not (Test-Path -LiteralPath $DestinationFolder)) {
        try {
            New-Item -LiteralPath $DestinationFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        catch {
            Write-OutputColor "  Failed to create destination directory: $_" -color "Error"
            return $null
        }
    }

    # Pre-check: verify destination has enough free space for VHD copy
    $sourceItem = Get-Item -LiteralPath $SourceVHDPath -ErrorAction SilentlyContinue
    if ($null -ne $sourceItem -and $DestinationFolder -match '^[A-Za-z]:') {
        $destDriveLetter = $DestinationFolder.Substring(0, 1)
        $destVolume = Get-Volume -DriveLetter $destDriveLetter -ErrorAction SilentlyContinue
        if ($null -ne $destVolume) {
            $requiredBytes = $sourceItem.Length
            $freeBytes = $destVolume.SizeRemaining
            if ($requiredBytes -gt $freeBytes) {
                $reqGB = [math]::Round($requiredBytes / 1GB, 1)
                $freeGB = [math]::Round($freeBytes / 1GB, 1)
                Write-OutputColor "  Insufficient disk space on ${destDriveLetter}: drive." -color "Error"
                Write-OutputColor "  Required: $reqGB GB | Available: $freeGB GB" -color "Error"
                Write-OutputColor "  Tip: Free up space or choose a different storage path." -color "Warning"
                return $null
            }
        }
    }

    Write-OutputColor "  Copying base VHD to VM folder..." -color "Info"
    Write-OutputColor "  Source: $SourceVHDPath" -color "Info"
    Write-OutputColor "  Dest:   $destPath" -color "Info"
    Write-OutputColor "" -color "Info"

    # Pre-declare so the finally block's `if ($copyJob)` / `if ($convertJob)` can
    # reference them safely under StrictMode even if the try throws before they're
    # assigned (e.g., a failure inside Start-Job's parameter validation).
    $copyJob = $null
    $convertJob = $null
    try {
        # Copy the file first
        $copyJob = Start-Job -ScriptBlock {
            param($src, $dst)
            Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop
        } -ArgumentList $SourceVHDPath, $destPath

        $sourceItem = Get-Item -LiteralPath $SourceVHDPath -ErrorAction SilentlyContinue
        $sourceSize = if ($null -ne $sourceItem) { $sourceItem.Length } else { 0 }
        $copyElapsed = 0
        $lastCopySize = 0
        $lastCopySpeedCheck = 0
        $copySpeedBps = 0

        # Cap copy at 4 hours. Without a timeout, a network share lost mid-copy or a
        # deduplication driver stuck on the destination volume hangs the loop indefinitely
        # — operator can't Ctrl-C cleanly because Copy-Item runs out-of-process inside the
        # Start-Job. Stop the job and surface a clear error on timeout.
        $copyMaxSeconds = 14400
        $copyStalledThreshold = 600  # 10 minutes of zero progress = stalled
        $copyLastProgressSize = 0
        $copyLastProgressAt = 0
        while ($copyJob.State -eq "Running") {
            $currentSize = 0
            if (Test-Path -LiteralPath $destPath) {
                try { $currentSize = (Get-Item -LiteralPath $destPath -ErrorAction SilentlyContinue).Length } catch { $currentSize = 0 }
            }

            if ($copyElapsed -gt 0 -and ($copyElapsed - $lastCopySpeedCheck) -ge 3) {
                $bytesInInterval = $currentSize - $lastCopySize
                $intervalSecs = $copyElapsed - $lastCopySpeedCheck
                if ($intervalSecs -gt 0 -and $bytesInInterval -ge 0) {
                    $copySpeedBps = $bytesInInterval / $intervalSecs
                }
                $lastCopySize = $currentSize
                $lastCopySpeedCheck = $copyElapsed
            }

            Write-ProgressBar -CurrentBytes $currentSize -TotalBytes $sourceSize -SpeedBytesPerSec $copySpeedBps -ElapsedSeconds $copyElapsed
            Start-Sleep -Seconds 1
            $copyElapsed++

            # Track progress to detect a stall (no growth for 10 minutes).
            if ($currentSize -gt $copyLastProgressSize) {
                $copyLastProgressSize = $currentSize
                $copyLastProgressAt = $copyElapsed
            }
            if ($copyElapsed -gt $copyMaxSeconds) {
                Write-Host ""
                Write-OutputColor "  Copy exceeded $($copyMaxSeconds / 3600) hour timeout — aborting." -color "Error"
                try { Stop-Job $copyJob -ErrorAction SilentlyContinue } catch {}
                try { Remove-Job $copyJob -Force -ErrorAction SilentlyContinue } catch {}
                $copyJob = $null
                return $null
            }
            if ($copyElapsed -gt 300 -and ($copyElapsed - $copyLastProgressAt) -gt $copyStalledThreshold) {
                Write-Host ""
                Write-OutputColor "  Copy stalled (no progress for $($copyStalledThreshold / 60) min) — aborting." -color "Error"
                try { Stop-Job $copyJob -ErrorAction SilentlyContinue } catch {}
                try { Remove-Job $copyJob -Force -ErrorAction SilentlyContinue } catch {}
                $copyJob = $null
                return $null
            }
        }
        Write-Host ""

        $null = Receive-Job $copyJob -ErrorAction SilentlyContinue
        $copyState = $copyJob.State
        Remove-Job $copyJob -Force -ErrorAction SilentlyContinue

        if ($copyState -eq "Failed" -or -not (Test-Path -LiteralPath $destPath)) {
            Write-OutputColor "  Failed to copy VHD." -color "Error"
            return $null
        }

        $copySize = (Get-Item -LiteralPath $destPath -ErrorAction SilentlyContinue).Length
        Write-TransferComplete -TotalBytes $copySize -ElapsedSeconds $copyElapsed -Activity "Copy"
        Write-OutputColor "" -color "Info"

        # Now convert from dynamic to fixed
        Write-OutputColor "  Converting VHD from dynamic to fixed size..." -color "Info"
        Write-OutputColor "  This can take several minutes for large VHDs." -color "Warning"
        Write-OutputColor "" -color "Info"

        $fixedPath = $destPath -replace '\.vhdx$', '_fixed.vhdx'

        $convertJob = Start-Job -ScriptBlock {
            param($src, $dst)
            Convert-VHD -Path $src -DestinationPath $dst -VHDType Fixed -ErrorAction Stop
        } -ArgumentList $destPath, $fixedPath

        $convertElapsed = 0
        $lastConvertSize = 0
        $lastConvertSpeedCheck = 0
        $convertSpeedBps = 0
        $spinChars = @('|', '/', '-', '\')
        $spinIndex = 0

        # Cap convert at 4 hours, with a 15-min no-progress stall detector.
        $convertMaxSeconds = 14400
        $convertStalledThreshold = 900
        $convertLastProgressSize = 0
        $convertLastProgressAt = 0
        while ($convertJob.State -eq "Running") {
            $currentSize = 0
            if (Test-Path -LiteralPath $fixedPath) {
                try { $currentSize = (Get-Item -LiteralPath $fixedPath -ErrorAction SilentlyContinue).Length } catch { $currentSize = 0 }
            }

            if ($convertElapsed -gt 0 -and ($convertElapsed - $lastConvertSpeedCheck) -ge 3) {
                $bytesInInterval = $currentSize - $lastConvertSize
                $intervalSecs = $convertElapsed - $lastConvertSpeedCheck
                if ($intervalSecs -gt 0 -and $bytesInInterval -ge 0) {
                    $convertSpeedBps = $bytesInInterval / $intervalSecs
                }
                $lastConvertSize = $currentSize
                $lastConvertSpeedCheck = $convertElapsed
            }

            $spin = $spinChars[$spinIndex % 4]
            $spinIndex++
            Write-ProgressBar -CurrentBytes $currentSize -Activity "Converting to fixed" -SpeedBytesPerSec $convertSpeedBps -ElapsedSeconds $convertElapsed -SpinChar $spin
            Start-Sleep -Seconds 2
            $convertElapsed += 2

            if ($currentSize -gt $convertLastProgressSize) {
                $convertLastProgressSize = $currentSize
                $convertLastProgressAt = $convertElapsed
            }
            if ($convertElapsed -gt $convertMaxSeconds) {
                Write-Host ""
                Write-OutputColor "  Convert exceeded $($convertMaxSeconds / 3600) hour timeout — aborting." -color "Error"
                try { Stop-Job $convertJob -ErrorAction SilentlyContinue } catch {}
                try { Remove-Job $convertJob -Force -ErrorAction SilentlyContinue } catch {}
                $convertJob = $null
                return $null
            }
            if ($convertElapsed -gt 300 -and ($convertElapsed - $convertLastProgressAt) -gt $convertStalledThreshold) {
                Write-Host ""
                Write-OutputColor "  Convert stalled (no progress for $($convertStalledThreshold / 60) min) — aborting." -color "Error"
                try { Stop-Job $convertJob -ErrorAction SilentlyContinue } catch {}
                try { Remove-Job $convertJob -Force -ErrorAction SilentlyContinue } catch {}
                $convertJob = $null
                return $null
            }
        }
        Write-Host ""

        $null = Receive-Job $convertJob -ErrorAction SilentlyContinue
        $convertState = $convertJob.State
        Remove-Job $convertJob -Force -ErrorAction SilentlyContinue

        if ($convertState -eq "Failed" -or -not (Test-Path -LiteralPath $fixedPath)) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Warning"
            Write-OutputColor "  ║$("  VHD CONVERSION FAILED — Dynamic VHD will be used instead".PadRight(72))║" -color "Warning"
            Write-OutputColor "  ╠════════════════════════════════════════════════════════════════════════╣" -color "Warning"
            Write-OutputColor "  ║$("  Dynamic VHDs have LOWER I/O performance than fixed VHDs.".PadRight(72))║" -color "Warning"
            Write-OutputColor "  ║$("  This may cause slower VM performance, especially for databases".PadRight(72))║" -color "Warning"
            Write-OutputColor "  ║$("  and high-IOPS workloads.".PadRight(72))║" -color "Warning"
            Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Warning"
            Write-OutputColor "" -color "Info"

            Write-OutputColor "  [1] Use dynamic VHD anyway (lower performance)" -color "Warning"
            Write-OutputColor "  [2] Retry conversion" -color "Success"
            Write-OutputColor "  [3] Cancel deployment" -color "Info"
            Write-OutputColor "" -color "Info"
            $fallbackChoice = Read-Host "  Select"
            $navResult = Test-NavigationCommand -UserInput $fallbackChoice
            if ($navResult.ShouldReturn) { return }

            if ($fallbackChoice -eq "2") {
                Write-OutputColor "  Retrying conversion..." -color "Info"
                # Wrap retry-job lifecycle in try/finally so a Wait-Job / Receive-Job
                # exception (closed runspace, Ctrl-C) can't leave the Convert-VHD job alive.
                # Convert-VHD jobs hold large memory-mapped IO and a leak accumulates across
                # multi-VM deployments. The outer function's finally only covers $copyJob /
                # $convertJob, not this retry job.
                $retryJob = $null
                try {
                    $retryJob = Start-Job -ScriptBlock {
                        param($src, $dst)
                        Convert-VHD -Path $src -DestinationPath $dst -VHDType Fixed -ErrorAction Stop
                    } -ArgumentList $destPath, $fixedPath
                    $null = $retryJob | Wait-Job -Timeout 600
                    $null = Receive-Job $retryJob -ErrorAction SilentlyContinue
                    $retryState = $retryJob.State
                    if ($retryState -ne "Failed" -and (Test-Path -LiteralPath $fixedPath)) {
                        Write-OutputColor "  Retry succeeded!" -color "Success"
                        # Fall through to the move logic below
                    } else {
                        Write-OutputColor "  Retry also failed. Using dynamic VHD." -color "Warning"
                        Add-SessionChange -Category "VM" -Description "VHD conversion failed for $VMName — using dynamic VHD (lower performance)"
                        return $destPath
                    }
                }
                catch {
                    Write-OutputColor "  Retry failed: $_" -color "Error"
                    Add-SessionChange -Category "VM" -Description "VHD conversion failed for $VMName — using dynamic VHD (lower performance)"
                    return $destPath
                }
                finally {
                    if ($null -ne $retryJob) {
                        try { Stop-Job -Job $retryJob -ErrorAction SilentlyContinue } catch { }
                        try { Remove-Job -Job $retryJob -Force -ErrorAction SilentlyContinue } catch { }
                    }
                }
            }
            elseif ($fallbackChoice -eq "3") {
                Write-OutputColor "  Deployment cancelled." -color "Info"
                Remove-Item -LiteralPath $destPath -Force -ErrorAction SilentlyContinue
                return $null
            }
            else {
                Add-SessionChange -Category "VM" -Description "VHD conversion failed for $VMName — using dynamic VHD (lower performance)"
                return $destPath
            }
        }

        # Move the fixed file to the final name (overwrites the dynamic copy)
        $finalPath = Join-Path $DestinationFolder $destFileName
        try {
            Move-Item -LiteralPath $fixedPath -Destination $finalPath -Force -ErrorAction Stop
        }
        catch {
            Write-OutputColor "  Warning: Could not rename converted VHD: $_" -color "Warning"
        }

        if (Test-Path -LiteralPath $finalPath) {
            $finalSize = (Get-Item -LiteralPath $finalPath).Length
            $sizeGB = [math]::Round($finalSize / 1GB, 2)
            Write-OutputColor "  Conversion complete! Fixed VHD: ${sizeGB} GB" -color "Success"
            Write-OutputColor "  Dynamic copy deleted. Master base image untouched." -color "Info"
            return $finalPath
        }
        elseif (Test-Path -LiteralPath $fixedPath) {
            # Move failed but fixed file still exists at _fixed path - use it directly
            $finalSize = (Get-Item -LiteralPath $fixedPath).Length
            $sizeGB = [math]::Round($finalSize / 1GB, 2)
            Write-OutputColor "  Conversion complete! Fixed VHD: ${sizeGB} GB" -color "Success"
            return $fixedPath
        }
        else {
            Write-OutputColor "  Warning: Could not verify final VHD path." -color "Warning"
            return $null
        }
    }
    catch {
        Write-RackStackError -Code "RS-5009" -Detail "$_"
        Write-OutputColor "  Error during VHD copy/convert: $_" -color "Error"
        return $null
    }
    finally {
        if ($copyJob) { Stop-Job $copyJob -ErrorAction SilentlyContinue; Remove-Job -Job $copyJob -Force -ErrorAction SilentlyContinue }
        if ($convertJob) { Stop-Job $convertJob -ErrorAction SilentlyContinue; Remove-Job -Job $convertJob -Force -ErrorAction SilentlyContinue }
    }
}

# Function to show VHD management menu
function Show-VHDManagementMenu {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    SYSPREPPED VHD MANAGEMENT").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $cachePath = Get-VHDCachePath

    # Show cached VHDs status
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$(("  CACHED BASE IMAGES (" + $cachePath.Substring(0, [Math]::Min(48, $cachePath.Length)) + ")").PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    foreach ($ver in @("2025", "2022", "2019")) {
        $cached = Test-CachedVHD -OSVersion $ver
        if ($cached.Exists) {
            $sizeGB = [math]::Round($cached.Size / 1GB, 2)
            $statusText = "Server $ver    ${sizeGB} GB    $($cached.LastModified.ToString('yyyy-MM-dd'))"
            Write-OutputColor "  │  [OK] $($statusText.PadRight(65))│" -color "Success"
        }
        else {
            # Check if file exists in FileServer
            $driveFile = Find-FileServerFile -FolderPath $script:FileServer.VHDsFolder -Keyword $ver -Extension "vhdx"
            if ($driveFile) {
                Write-OutputColor "  │$("  [--] Server $ver    Available for download".PadRight(72))│" -color "Warning"
            }
            else {
                Write-OutputColor "  │$("  [--] Server $ver    Not uploaded".PadRight(72))│" -color "Warning"
            }
        }
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  OPTIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("   [1]  Download Server 2025 VHD".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("   [2]  Download Server 2022 VHD".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("   [3]  Download Server 2019 VHD".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("   [4]  Download All Missing VHDs".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("   [5]  VHD Health Check".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("   [6]  Optimize VHD (compact dynamic VHD)".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("   [7]  Show Windows Sysprep VHD Guide".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("   [8]  Show Linux cloud-init VHD Guide".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("   [9]  ◄ Back".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to run VHD management menu loop
# Function to display the sysprep VHD creation guide
function Show-SysprepGuide {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$("  HOW TO CREATE A SYSPREPPED VHD FOR DEPLOYMENT".PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  This guide walks through creating a sysprepped base VHD that can be" -color "Info"
    Write-OutputColor "  cloned for rapid VM deployment. Create one per OS version." -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  STEP 1: CREATE A TEMPLATE VM".PadRight(72))│" -color "Success"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  1. Create a new Gen 2 VM in Hyper-V with these settings:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     - Name: TEMPLATE-2025 (or 2022, 2019)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     - Memory: 4 GB (just for the install)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     - Disk: 150 GB DYNAMIC (important - must be dynamic!)".PadRight(72))│" -color "Warning"
    Write-OutputColor "  │$("     - Network: Connect to a switch with internet access".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  2. Mount the Windows Server ISO to the VM".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  3. Start the VM and install Windows Server:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     - Choose 'Datacenter (Desktop Experience)' edition".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     - Set a temporary administrator password".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  STEP 2: CONFIGURE THE TEMPLATE".PadRight(72))│" -color "Success"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  After Windows installs and you're at the desktop:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  1. Install ALL Windows Updates (repeat until none remain)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     - Settings > Update & Security > Windows Update".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     - Reboot and check again until fully patched".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  2. (Optional) Install common features/roles:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     - .NET Framework 4.8 (if not already present)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     - Any baseline agents or tools you want on all servers".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     - DO NOT install roles like AD DS, DHCP, etc.".PadRight(72))│" -color "Warning"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  3. (Optional) Set power plan to High Performance:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  4. (Optional) Enable Remote Desktop:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  5. Clean up temp files:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     cleanmgr /d $($env:SystemDrive.TrimEnd(':')) /VERYLOWDISK  (or run Disk Cleanup)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     Remove-Item $env:SystemRoot\Temp\* -Recurse -Force".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     Remove-Item $env:TEMP\* -Recurse -Force".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-PressEnter -Message "  Press Enter for next page..."

    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  STEP 3: RUN SYSPREP".PadRight(72))│" -color "Success"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  IMPORTANT: This is the critical step. Sysprep generalizes Windows".PadRight(72))│" -color "Warning"
    Write-OutputColor "  │$("  so it can be cloned to multiple machines.".PadRight(72))│" -color "Warning"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  1. Open PowerShell as Administrator on the template VM".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  2. Run Sysprep:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     /shutdown /mode:vm".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Flags explained:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     /generalize  - Removes unique system info (SID, etc.)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     /oobe        - Triggers mini-setup on next boot".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     /shutdown    - Shuts down VM when done (DON'T start it again!)".PadRight(72))│" -color "Warning"
    Write-OutputColor "  │$("     /mode:vm     - Optimized for VM cloning (faster, skips HW detect)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  3. Wait for the VM to shut down automatically".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     DO NOT start the VM again after sysprep!".PadRight(72))│" -color "Error"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  STEP 4: EXPORT AND UPLOAD THE VHD".PadRight(72))│" -color "Success"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  After the VM shuts down from sysprep:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  1. Find the VHDX file:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     - Check the VM's settings in Hyper-V Manager for the VHD path".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     - It's usually in D:\Virtual Machines\TEMPLATE-2025\".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  2. Rename the VHDX appropriately:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     Server2025_Sysprepped.vhdx".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     Server2022_Sysprepped.vhdx".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     Server2019_Sysprepped.vhdx".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  3. Upload to the FileServer VHDs folder:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     - Include the OS version year in the filename (e.g. 2025)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     - Ensure FileServer is configured in defaults.json".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     - The script discovers files automatically from the server".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-PressEnter -Message "  Press Enter for next page..."

    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  TIPS & BEST PRACTICES".PadRight(72))│" -color "Success"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  - Keep the VHD as DYNAMIC (not fixed) in FileServer".PadRight(72))│" -color "Warning"
    Write-OutputColor "  │$("    This tool will convert to fixed when deploying to each VM".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("    Dynamic VHDs are much smaller to download (30-50 GB vs 150 GB)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  - Update the VHD quarterly after new Windows updates".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("    1. Clone the sysprepped VHD to a new temp VM".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("    2. Boot it, install updates, re-sysprep, re-upload".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  - Use 150 GB for the OS disk (matches our standard templates)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("    The dynamic VHD will only use space for actual data".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  - DO NOT join the template to a domain before sysprep".PadRight(72))│" -color "Warning"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  - DO NOT install site-specific agents or software".PadRight(72))│" -color "Warning"
    Write-OutputColor "  │$("    Those are per-site and should be installed after deployment".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  - DO NOT change the default admin password to your production one".PadRight(72))│" -color "Warning"
    Write-OutputColor "  │$("    Sysprep will prompt for a new password on first boot".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  FILESERVER AUTO-DISCOVERY:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Files are discovered automatically from the VHDs folder.".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Just upload the VHDX and include the year (2025/2022/2019)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  in the filename. No manual file ID configuration needed.".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  QUICK REFERENCE - SYSPREP COMMAND".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$('  C:\Windows\System32\Sysprep\sysprep.exe'.PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("      /generalize /oobe /shutdown /mode:vm".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

function Show-LinuxVHDGuide {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$("  HOW TO CREATE A LINUX cloud-init VHD FOR DEPLOYMENT".PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  This guide walks through creating a cloud-init enabled Linux VHD" -color "Info"
    Write-OutputColor "  that can be cloned for rapid VM deployment." -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  STEP 1: CREATE A TEMPLATE VM".PadRight(72))│" -color "Success"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  1. Create a new Gen 2 VM in Hyper-V:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     - Name: TEMPLATE-Ubuntu2404 (or Rocky9, Debian12)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     - Memory: 2-4 GB".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     - Disk: 100 GB DYNAMIC (important - must be dynamic!)".PadRight(72))│" -color "Warning"
    Write-OutputColor "  │$("     - Network: Connect to a switch with internet access".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     - Secure Boot: Microsoft UEFI Certificate Authority".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  2. Mount the ISO and install the OS (minimal/server install)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     - Ubuntu Server, Rocky Linux, or Debian are recommended".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     - Install OpenSSH server during setup".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  STEP 2: INSTALL AND CONFIGURE cloud-init".PadRight(72))│" -color "Success"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Ubuntu/Debian:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("    sudo apt update && sudo apt install -y cloud-init".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Rocky/RHEL:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("    sudo dnf install -y cloud-init".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Enable Hyper-V datasource in /etc/cloud/cloud.cfg:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("    datasource_list: [ Azure, None ]".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Install Hyper-V guest tools:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("    Ubuntu:  sudo apt install -y linux-tools-virtual".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("    Rocky:   sudo dnf install -y hyperv-daemons".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-PressEnter -Message "  Press Enter for next page..."

    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  STEP 3: CLEAN UP FOR TEMPLATING".PadRight(72))│" -color "Success"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Run these commands to generalize the VM:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  1. Clean cloud-init state:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     sudo cloud-init clean --logs".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  2. Remove SSH host keys (regenerated on first boot):".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     sudo rm -f /etc/ssh/ssh_host_*".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  3. Truncate machine-id (regenerated on first boot):".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     sudo truncate -s 0 /etc/machine-id".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("     sudo rm -f /var/lib/dbus/machine-id".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  4. Clear bash history:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     history -c && cat /dev/null > ~/.bash_history".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  5. Shut down (DO NOT start again!):".PadRight(72))│" -color "Warning"
    Write-OutputColor "  │$("     sudo shutdown -h now".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  STEP 4: EXPORT THE VHDX".PadRight(72))│" -color "Success"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  1. Copy the VHDX from the template VM folder.".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  2. Rename appropriately:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     Ubuntu2404_CloudInit.vhdx".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     Rocky9_CloudInit.vhdx".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     Debian12_CloudInit.vhdx".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  3. Upload to FileServer VHDs folder (if configured)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  TIPS".PadRight(72))│" -color "Success"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  - Keep the VHD as DYNAMIC for storage (converted on deploy)".PadRight(72))│" -color "Warning"
    Write-OutputColor "  │$("  - Use Secure Boot with 'Microsoft UEFI Certificate Authority'".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("    (NOT 'Microsoft Windows' -- that's for Windows only)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  - DO NOT join a domain or install site-specific software".PadRight(72))│" -color "Warning"
    Write-OutputColor "  │$("  - cloud-init will set hostname and network on first boot".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

function Show-VHDHealthStatus {
    Write-OutputColor "`n  VHD Health Check:" -color "Info"

    try {
        # Get all VMs and their VHDs
        $vms = @(Get-VM -ErrorAction SilentlyContinue)
        if ($vms.Count -eq 0) {
            Write-OutputColor "  No VMs found (Hyper-V may not be installed)" -color "Warning"
            return
        }

        $issues = 0
        foreach ($vm in $vms) {
            $vhds = @(Get-VMHardDiskDrive -VMName $vm.Name -ErrorAction SilentlyContinue)
            foreach ($vhd in $vhds) {
                if ([string]::IsNullOrWhiteSpace($vhd.Path)) { continue }

                try {
                    $vhdInfo = Get-VHD -Path $vhd.Path -ErrorAction Stop
                    $vmName = if ($vm.Name.Length -gt 20) { $vm.Name.Substring(0, 17) + "..." } else { $vm.Name }
                    $fileName = Split-Path -Leaf $vhd.Path
                    if ($fileName.Length -gt 30) { $fileName = $fileName.Substring(0, 27) + "..." }

                    # Check for issues
                    $sizeGB = [math]::Round($vhdInfo.FileSize / 1GB, 1)
                    $maxGB = [math]::Round($vhdInfo.Size / 1GB, 1)
                    $usagePercent = if ($vhdInfo.Size -gt 0) { [math]::Round(($vhdInfo.FileSize / $vhdInfo.Size) * 100, 0) } else { 0 }

                    $color = "Success"
                    $warning = ""

                    if ($usagePercent -gt 90) {
                        $color = "Error"
                        $warning = " [NEARLY FULL]"
                        $issues++
                    } elseif ($usagePercent -gt 75) {
                        $color = "Warning"
                        $warning = " [${usagePercent}% used]"
                    }

                    # Check if VHD is fragmented (dynamic disks only)
                    if ($vhdInfo.VhdType -eq 'Dynamic' -and $null -ne $vhdInfo.FragmentationPercentage -and $vhdInfo.FragmentationPercentage -gt 30) {
                        $color = "Warning"
                        $warning += " [Fragmented: $($vhdInfo.FragmentationPercentage)%]"
                        $issues++
                    }

                    Write-OutputColor "  $vmName  $fileName  ${sizeGB}/${maxGB} GB ($($vhdInfo.VhdType))$warning" -color $color
                } catch {
                    Write-OutputColor "  $($vm.Name)  $($vhd.Path): Cannot read VHD info" -color "Error"
                    $issues++
                }
            }
        }

        if ($issues -eq 0) {
            Write-OutputColor "`n  All VHDs healthy" -color "Success"
        } else {
            Write-OutputColor "`n  $issues issue(s) found" -color "Warning"
        }
    } catch {
        Write-OutputColor "  VHD health check failed: $($_.Exception.Message)" -color "Error"
    }
}

function Start-VHDManagement {
    while ($true) {
        if ($global:ReturnToMainMenu) { return }
        $choice = Show-VHDManagementMenu

        switch ($choice) {
            "1" {
                Get-SyspreppedVHD -OSVersion "2025"
                Write-PressEnter
            }
            "2" {
                Get-SyspreppedVHD -OSVersion "2022"
                Write-PressEnter
            }
            "3" {
                Get-SyspreppedVHD -OSVersion "2019"
                Write-PressEnter
            }
            "4" {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Downloading all missing VHDs..." -color "Info"
                foreach ($ver in @("2025", "2022", "2019")) {
                    $cached = Test-CachedVHD -OSVersion $ver
                    if (-not $cached.Exists) {
                        Write-OutputColor "" -color "Info"
                        Write-OutputColor "  --- Server $ver ---" -color "Info"
                        Get-SyspreppedVHD -OSVersion $ver
                    }
                    else {
                        Write-OutputColor "  Server ${ver}: Already cached, skipping." -color "Info"
                    }
                }
                Write-PressEnter
            }
            "5" {
                Show-VHDHealthStatus
                Write-PressEnter
            }
            "6" {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Enter full path to VHD/VHDX file (or 'back' to cancel):" -color "Info"
                $vhdPath = Read-Host "  Path"
                $navResult = Test-NavigationCommand -UserInput $vhdPath
                if (-not $navResult.ShouldReturn -and -not [string]::IsNullOrWhiteSpace($vhdPath)) {
                    $vhdPath = $vhdPath.Trim('"', "'")
                    Optimize-VHDFile -VHDPath $vhdPath
                }
                Write-PressEnter
            }
            "7" {
                Show-SysprepGuide
                Write-PressEnter
            }
            "8" {
                Show-LinuxVHDGuide
                Write-PressEnter
            }
            "9" {
                return
            }
            default {
                $navResult = Test-NavigationCommand -UserInput $choice
                if ($navResult.ShouldReturn) { return }
            }
        }
    }
}

# Function to optimize/compact a VHD (reduce size of dynamic VHDs)
function Optimize-VHDFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$VHDPath
    )

    if (-not (Test-Path -LiteralPath $VHDPath)) {
        Write-OutputColor "  VHD not found: $VHDPath" -color "Error"
        return
    }

    try {
        $vhdInfo = Get-VHD -Path $VHDPath -ErrorAction Stop

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  VHD: $(Split-Path $VHDPath -Leaf)" -color "Info"
        Write-OutputColor "  Type: $($vhdInfo.VhdType)" -color "Info"
        Write-OutputColor "  Current size: $([math]::Round($vhdInfo.FileSize / 1GB, 2)) GB" -color "Info"
        Write-OutputColor "  Maximum size: $([math]::Round($vhdInfo.Size / 1GB, 2)) GB" -color "Info"

        if ($null -ne $vhdInfo.FragmentationPercentage) {
            Write-OutputColor "  Fragmentation: $($vhdInfo.FragmentationPercentage)%" -color $(if ($vhdInfo.FragmentationPercentage -gt 30) { "Warning" } else { "Info" })
        }

        if ($vhdInfo.Attached) {
            Write-OutputColor "  VHD is currently attached. Dismount before optimizing." -color "Error"
            return
        }

        # CRITICAL: $vhdInfo.Attached only reports host-side mounts (Mount-VHD), NOT VHDs
        # attached to a running Hyper-V VM. Optimize-VHD demands exclusive access — running
        # it against a VM-backing VHDX with in-flight guest writes can corrupt the guest's
        # filesystem. Refuse if any VM has this VHD attached, especially while running.
        try {
            $vhdLiteral = (Resolve-Path -LiteralPath $VHDPath -ErrorAction Stop).Path
            $attachedVMs = @(Get-VMHardDiskDrive -VMName * -ErrorAction SilentlyContinue | Where-Object {
                try { (Resolve-Path -LiteralPath $_.Path -ErrorAction Stop).Path -eq $vhdLiteral } catch { $false }
            })
            if ($attachedVMs.Count -gt 0) {
                foreach ($att in $attachedVMs) {
                    $vm = Get-VM -Name $att.VMName -ErrorAction SilentlyContinue
                    $vmState = if ($null -ne $vm) { $vm.State } else { 'Unknown' }
                    Write-OutputColor "  VHD is attached to VM '$($att.VMName)' (State: $vmState)." -color "Error"
                    if ($vmState -eq 'Running' -or $vmState -eq 'Paused') {
                        Write-OutputColor "  REFUSING to optimize — Optimize-VHD against a running VM's disk can corrupt the guest." -color "Error"
                    } else {
                        Write-OutputColor "  Detach the VHD from the VM (or shut down + Remove-VMHardDiskDrive) before optimizing." -color "Warning"
                    }
                }
                return
            }
        } catch {
            Write-OutputColor "  Could not verify VM attachment status: $($_.Exception.Message)" -color "Warning"
            Write-OutputColor "  Refusing to optimize as fail-safe — could not prove the VHD is unattached." -color "Error"
            return
        }

        if ($vhdInfo.VhdType -ne 'Dynamic') {
            Write-OutputColor "  Only dynamic VHDs can be compacted. This is a $($vhdInfo.VhdType) VHD." -color "Warning"
            return
        }

        Write-OutputColor "" -color "Info"
        if (-not (Confirm-UserAction -Message "Optimize this VHD? (may take several minutes)")) { return }

        Write-OutputColor "  Optimizing VHD..." -color "Info"
        Optimize-VHD -Path $VHDPath -Mode Full -ErrorAction Stop

        $postInfo = Get-VHD -Path $VHDPath -ErrorAction SilentlyContinue
        if ($null -ne $postInfo) {
            $savedMB = [math]::Round(($vhdInfo.FileSize - $postInfo.FileSize) / 1MB)
            Write-OutputColor "  Optimization complete." -color "Success"
            Write-OutputColor "  New size: $([math]::Round($postInfo.FileSize / 1GB, 2)) GB" -color "Success"
            if ($savedMB -gt 0) {
                Write-OutputColor "  Space saved: $savedMB MB" -color "Success"
            }
        }
        Add-SessionChange -Category "Storage" -Description "Optimized VHD: $(Split-Path $VHDPath -Leaf)"
    }
    catch {
        Write-OutputColor "  VHD optimization failed: $_" -color "Error"
    }
}
#endregion