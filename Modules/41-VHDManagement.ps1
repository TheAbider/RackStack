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
    Write-OutputColor "  │  $($Title.PadRight(71))│" -color "Info"
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
            Write-OutputColor "  Invalid choice." -color "Error"
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
    if (Test-Path $cachePath) {
        $found = Get-ChildItem -Path $cachePath -Filter "*$OSVersion*.vhdx" -File -ErrorAction SilentlyContinue | Select-Object -First 1
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

    if ($cached.Exists) {
        # Integrity check: size mismatch = corrupt or incomplete transfer
        $remoteSize = Get-FileServerFileSize -FilePath $driveFile.FilePath
        if ($remoteSize -gt 0 -and $cached.Size -ne $remoteSize) {
            Write-OutputColor "  Cached VHD size mismatch (local: $([math]::Round($cached.Size/1GB, 2))GB, remote: $([math]::Round($remoteSize/1GB, 2))GB)" -color "Warning"
            if (Confirm-UserAction -Message "Delete mismatched cache and re-download?") {
                Remove-Item $cached.Path -Force -ErrorAction SilentlyContinue
                $cached = @{ Exists = $false; Path = $null; Size = 0 }
            }
        }

        # Integrity check: filename mismatch = newer version available
        if ($cached.Exists -and $cached.FileName -ne $driveFile.FileName) {
            $sizeGB = [math]::Round($cached.Size / 1GB, 2)
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  [UP] UPDATE AVAILABLE".PadRight(72))│" -color "Warning"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
            Write-OutputColor "  │  Local:  $($cached.FileName.Substring(0, [Math]::Min(62, $cached.FileName.Length)).PadRight(62))│" -color "Info"
            Write-OutputColor "  │  Remote: $($driveFile.FileName.Substring(0, [Math]::Min(62, $driveFile.FileName.Length)).PadRight(62))│" -color "Success"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            Write-OutputColor "" -color "Info"

            if (Confirm-UserAction -Message "Replace local VHD with newer version?") {
                Remove-Item $cached.Path -Force -ErrorAction SilentlyContinue
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
        Write-OutputColor "  │  File: $($cached.FileName.Substring(0, [Math]::Min(63, $cached.FileName.Length)).PadRight(63))│" -color "Info"
        Write-OutputColor "  │  Size: $("${sizeGB} GB".PadRight(63))│" -color "Info"
        Write-OutputColor "  │  Date: $($cached.LastModified.ToString('yyyy-MM-dd HH:mm').PadRight(63))│" -color "Info"
        Write-OutputColor "  │  Path: $($cached.Path.Substring(0, [Math]::Min(63, $cached.Path.Length)).PadRight(63))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  [1] Use this cached VHD" -color "Success"
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
                Remove-Item $cached.Path -Force -ErrorAction SilentlyContinue
                # Continue to download below
            }
            default { return $null }
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

    $destFileName = "${VMName}_${DiskLabel}.vhdx"
    $destPath = Join-Path $DestinationFolder $destFileName

    # Ensure destination directory exists
    if (-not (Test-Path $DestinationFolder)) {
        New-Item -Path $DestinationFolder -ItemType Directory -Force | Out-Null
    }

    Write-OutputColor "  Copying base VHD to VM folder..." -color "Info"
    Write-OutputColor "  Source: $SourceVHDPath" -color "Info"
    Write-OutputColor "  Dest:   $destPath" -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        # Copy the file first
        $copyJob = Start-Job -ScriptBlock {
            param($src, $dst)
            Copy-Item -Path $src -Destination $dst -Force -ErrorAction Stop
        } -ArgumentList $SourceVHDPath, $destPath

        $sourceSize = (Get-Item $SourceVHDPath -ErrorAction SilentlyContinue).Length
        $copyElapsed = 0
        $lastCopySize = 0
        $lastCopySpeedCheck = 0
        $copySpeedBps = 0

        while ($copyJob.State -eq "Running") {
            $currentSize = 0
            if (Test-Path $destPath) {
                try { $currentSize = (Get-Item $destPath -ErrorAction SilentlyContinue).Length } catch { $currentSize = 0 }
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
        }
        Write-Host ""

        $null = Receive-Job $copyJob -ErrorAction SilentlyContinue
        $copyState = $copyJob.State
        Remove-Job $copyJob -Force -ErrorAction SilentlyContinue

        if ($copyState -eq "Failed" -or -not (Test-Path $destPath)) {
            Write-OutputColor "  Failed to copy VHD." -color "Error"
            return $null
        }

        $copySize = (Get-Item $destPath -ErrorAction SilentlyContinue).Length
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

        while ($convertJob.State -eq "Running") {
            $currentSize = 0
            if (Test-Path $fixedPath) {
                try { $currentSize = (Get-Item $fixedPath -ErrorAction SilentlyContinue).Length } catch { $currentSize = 0 }
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
        }
        Write-Host ""

        $null = Receive-Job $convertJob -ErrorAction SilentlyContinue
        $convertState = $convertJob.State
        Remove-Job $convertJob -Force -ErrorAction SilentlyContinue

        if ($convertState -eq "Failed" -or -not (Test-Path $fixedPath)) {
            Write-OutputColor "  Failed to convert VHD to fixed. Using dynamic copy instead." -color "Warning"
            return $destPath
        }

        # Move the fixed file to the final name (the clean name without _fixed)
        $finalPath = Join-Path $DestinationFolder $destFileName
        Move-Item -Path $fixedPath -Destination $finalPath -Force -ErrorAction SilentlyContinue

        if (Test-Path $finalPath) {
            # Delete the dynamic copy only after move succeeded
            Remove-Item $destPath -Force -ErrorAction SilentlyContinue
            $finalSize = (Get-Item $finalPath).Length
            $sizeGB = [math]::Round($finalSize / 1GB, 2)
            Write-OutputColor "  Conversion complete! Fixed VHD: ${sizeGB} GB" -color "Success"
            Write-OutputColor "  Dynamic copy deleted. Master base image untouched." -color "Info"
            return $finalPath
        }
        elseif (Test-Path $fixedPath) {
            # Move failed but fixed file still exists at _fixed path - use it directly
            $finalSize = (Get-Item $fixedPath).Length
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
        Write-OutputColor "  Error during VHD copy/convert: $_" -color "Error"
        return $null
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
    Write-OutputColor "  │$("   [5]  Show Windows Sysprep VHD Guide".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("   [6]  Show Linux cloud-init VHD Guide".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("   [7]  ◄ Back".PadRight(72))│" -color "Info"
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
    Write-OutputColor "  │$("     cleanmgr /d C /VERYLOWDISK  (or run Disk Cleanup)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     Remove-Item C:\Windows\Temp\* -Recurse -Force".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("     Remove-Item $env:TEMP\* -Recurse -Force".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Press Enter for next page..." -color "Info"
    Read-Host | Out-Null

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

    Write-OutputColor "  Press Enter for next page..." -color "Info"
    Read-Host | Out-Null

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

    Write-OutputColor "  Press Enter for next page..." -color "Info"
    Read-Host | Out-Null

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

function Start-VHDManagement {
    while ($true) {
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
                Show-SysprepGuide
                Write-PressEnter
            }
            "6" {
                Show-LinuxVHDGuide
                Write-PressEnter
            }
            "7" {
                return
            }
            default {
                $navResult = Test-NavigationCommand -UserInput $choice
                if ($navResult.ShouldReturn) { return }
            }
        }
    }
}
#endregion