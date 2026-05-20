#region ===== ISO DOWNLOAD =====
# Function to get the ISO storage path based on deployment mode
function Get-ISOStoragePath {
    if ($script:VMDeploymentMode -eq "Cluster") {
        return $script:ClusterISOPath
    }
    return $script:HostISOPath
}

# Function to check if an ISO is already downloaded
function Test-CachedISO {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$OSVersion
    )

    $isoPath = Get-ISOStoragePath

    # Search local disk for any ISO matching the OS version
    if (Test-Path -LiteralPath $isoPath) {
        $found = Get-ChildItem -LiteralPath $isoPath -Filter "*$OSVersion*.iso" -File -ErrorAction SilentlyContinue | Select-Object -First 1
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

# Function to download an ISO from FileServer
function Get-ServerISO {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$OSVersion
    )

    $isoPath = Get-ISOStoragePath

    # Check network connectivity before attempting download
    if (-not (Test-NetworkConnectivity)) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  No network connectivity. Cannot download ISO." -color "Error"
        Write-OutputColor "  Tip: Verify network configuration and DNS settings." -color "Warning"
        return $null
    }

    # Validate the ISO storage path is configured
    if (-not $isoPath) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ISO storage path not configured." -color "Error"
        Write-OutputColor "  Run 'Host Storage Setup' first to configure storage." -color "Warning"
        return $null
    }

    # Ensure ISO directory exists
    if (-not (Test-Path -LiteralPath $isoPath)) {
        try {
            New-Item -Path $isoPath -ItemType Directory -Force | Out-Null
            Write-OutputColor "  Created ISO directory: $isoPath" -color "Success"
        }
        catch {
            Write-OutputColor "  Failed to create ISO directory: $_" -color "Error"
            return $null
        }
    }

    # Discover the ISO file from FileServer
    $driveFile = Find-FileServerFile -FolderPath $script:FileServer.ISOsFolder -Keyword $OSVersion -Extension "iso"
    if (-not $driveFile) {
        Write-OutputColor "  No ISO found for Server $OSVersion in FileServer." -color "Error"
        Write-OutputColor "  Upload an ISO containing '$OSVersion' in the filename to the ISOs folder." -color "Warning"
        return $null
    }

    # Check if already downloaded
    $cached = Test-CachedISO -OSVersion $OSVersion

    if ($cached.Exists) {
        # Integrity check: size mismatch = corrupt. Use a 1 MB tolerance because
        # alignment differences from SMB/CDN copies aren't real corruption. Multi-GB
        # ISO caches were being silently deleted on byte-level drift.
        $remoteSize = Get-FileServerFileSize -FilePath $driveFile.FilePath
        if ($remoteSize -gt 0 -and [math]::Abs($cached.Size - $remoteSize) -gt 1MB) {
            Remove-Item -LiteralPath $cached.Path -Force -ErrorAction SilentlyContinue
            $cached = @{ Exists = $false; Path = $null; Size = 0 }
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

            if (Confirm-UserAction -Message "Replace local ISO with newer version?") {
                Remove-Item -LiteralPath $cached.Path -Force -ErrorAction SilentlyContinue
                $cached = @{ Exists = $false; Path = $null; Size = 0 }
            }
        }
    }

    if ($cached.Exists) {
        $sizeGB = [math]::Round($cached.Size / 1GB, 2)
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  ISO ALREADY DOWNLOADED".PadRight(72))│" -color "Success"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │  File: $($cached.FileName.Substring(0, [Math]::Min(63, $cached.FileName.Length)).PadRight(63))│" -color "Info"
        Write-OutputColor "  │  Size: $("${sizeGB} GB".PadRight(63))│" -color "Info"
        Write-OutputColor "  │  Path: $($cached.Path.Substring(0, [Math]::Min(63, $cached.Path.Length)).PadRight(63))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  [1] Use existing ISO (no action needed)" -color "Success"
        Write-OutputColor "  [2] Re-download (replace existing)" -color "Success"
        Write-OutputColor "  [3] Cancel" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return $null }

        switch ($choice) {
            "1" {
                Write-OutputColor "  ISO is ready at: $($cached.Path)" -color "Success"
                return $cached.Path
            }
            "2" {
                # Keep the old ISO until the new one verifies. If we delete first and the
                # re-download fails (network drop, FileServer outage, disk full mid-write),
                # the operator has neither a working ISO nor a fallback. Rename to .old so
                # the new download lands cleanly; remove .old only after success below.
                $oldPath = $cached.Path
                $oldRenamed = "$oldPath.old"
                try {
                    if (Test-Path -LiteralPath $oldRenamed) {
                        Remove-Item -LiteralPath $oldRenamed -Force -ErrorAction SilentlyContinue
                    }
                    Move-Item -LiteralPath $oldPath -Destination $oldRenamed -Force -ErrorAction Stop
                    Write-OutputColor "  Existing ISO renamed to '$([System.IO.Path]::GetFileName($oldRenamed))' as a fallback." -color "Info"
                    $script:_isoRollbackPath = $oldRenamed
                } catch {
                    Write-OutputColor "  Could not rename existing ISO: $($_.Exception.Message)" -color "Warning"
                    Write-OutputColor "  Re-downloading anyway — if download fails, the existing ISO remains in place." -color "Warning"
                    $script:_isoRollbackPath = $null
                }
            }
            default { return $null }
        }
    }

    # Pre-check: verify destination has enough free space (skip for UNC paths)
    if ($isoPath -match '^[A-Za-z]:') {
        $isoDriveLetter = $isoPath.Substring(0, 1)
        $isoVolume = Get-Volume -DriveLetter $isoDriveLetter -ErrorAction SilentlyContinue
        if ($isoVolume) {
            $freeGB = [math]::Round($isoVolume.SizeRemaining / 1GB, 1)
            if ($freeGB -lt 10) {
                Write-OutputColor "  ERROR: Only $freeGB GB free on ${isoDriveLetter}: drive." -color "Error"
                Write-OutputColor "  Not enough space for ISO download (4-6 GB typically needed)." -color "Warning"
                return $null
            }
        }
    }

    # Download the ISO
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Downloading Server $OSVersion ISO from FileServer..." -color "Info"
    Write-OutputColor "  File: $($driveFile.FileName)" -color "Info"
    Write-OutputColor "  Destination: $isoPath" -color "Info"
    Write-OutputColor "  ISOs are typically 4-6 GB. This will take a while." -color "Warning"
    Write-OutputColor "" -color "Info"

    $result = Get-FileServerFile -FilePath $driveFile.FilePath -DestinationPath $isoPath -FileName $driveFile.FileName -TimeoutSeconds $script:LargeFileDownloadTimeoutSeconds

    if ($result.Success) {
        Write-OutputColor "  ISO downloaded and verified!" -color "Success"
        Write-OutputColor "  Path: $($result.FilePath)" -color "Info"
        # Clean up the .old rollback file now that the new download verified
        if ($script:_isoRollbackPath -and (Test-Path -LiteralPath $script:_isoRollbackPath)) {
            Remove-Item -LiteralPath $script:_isoRollbackPath -Force -ErrorAction SilentlyContinue
        }
        $script:_isoRollbackPath = $null
        Add-SessionChange -Category "ISO Download" -Description "Downloaded Server $OSVersion ISO to $isoPath"
        Clear-MenuCache
        return $result.FilePath
    }
    else {
        Write-OutputColor "  Failed to download ISO: $($result.Error)" -color "Error"
        # Roll back the rename if we have a saved .old to restore
        if ($script:_isoRollbackPath -and (Test-Path -LiteralPath $script:_isoRollbackPath)) {
            try {
                $restorePath = $script:_isoRollbackPath -replace '\.old$', ''
                Move-Item -LiteralPath $script:_isoRollbackPath -Destination $restorePath -Force -ErrorAction Stop
                Write-OutputColor "  Restored previous ISO from rollback: $restorePath" -color "Info"
            } catch {
                Write-OutputColor "  Could not restore previous ISO: $($_.Exception.Message)" -color "Warning"
                Write-OutputColor "  Fallback at: $script:_isoRollbackPath (rename manually to .iso)" -color "Info"
            }
        }
        $script:_isoRollbackPath = $null
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Troubleshooting:" -color "Warning"
        Write-OutputColor "  - Ensure FileServer is accessible" -color "Info"
        Write-OutputColor "  - Check network connectivity and available disk space" -color "Info"
        return $null
    }
}

# Function to show ISO management menu
function Show-ISODownloadMenu {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       ISO DOWNLOAD MANAGER").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $isoPath = Get-ISOStoragePath
    if (-not $isoPath) { $isoPath = "(not configured)" }

    # Show status
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │  ISO STORAGE: $($isoPath.PadRight(57))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    foreach ($ver in @("2025", "2022", "2019")) {
        $cached = Test-CachedISO -OSVersion $ver
        if ($cached.Exists) {
            $sizeGB = [math]::Round($cached.Size / 1GB, 2)
            $statusText = "Server $ver    ${sizeGB} GB    $($cached.LastModified.ToString('yyyy-MM-dd'))"
            Write-OutputColor "  │  [OK] $($statusText.PadRight(65))│" -color "Success"
        }
        else {
            # Check if file exists in FileServer
            $driveFile = Find-FileServerFile -FolderPath $script:FileServer.ISOsFolder -Keyword $ver -Extension "iso"
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
    Write-OutputColor "  │$("   [1]  Download Server 2025 ISO".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("   [2]  Download Server 2022 ISO".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("   [3]  Download Server 2019 ISO".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("   [4]  Download All Missing ISOs".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("   [5]  Show ISO Inventory".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("   [6]  ◄ Back".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to run ISO download menu loop
function Start-ISODownload {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }
        $choice = Show-ISODownloadMenu

        switch ($choice) {
            "1" {
                Get-ServerISO -OSVersion "2025"
                Write-PressEnter
            }
            "2" {
                Get-ServerISO -OSVersion "2022"
                Write-PressEnter
            }
            "3" {
                Get-ServerISO -OSVersion "2019"
                Write-PressEnter
            }
            "4" {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Downloading all missing ISOs..." -color "Info"
                foreach ($ver in @("2025", "2022", "2019")) {
                    $cached = Test-CachedISO -OSVersion $ver
                    if (-not $cached.Exists) {
                        Write-OutputColor "" -color "Info"
                        Write-OutputColor "  --- Server $ver ---" -color "Info"
                        Get-ServerISO -OSVersion $ver
                    }
                    else {
                        Write-OutputColor "  Server ${ver}: Already downloaded, skipping." -color "Info"
                    }
                }
                Write-PressEnter
            }
            "5" {
                Show-ISOInventory
                Write-PressEnter
            }
            "6" {
                return
            }
            default {
                $navResult = Test-NavigationCommand -UserInput $choice
                if ($navResult.ShouldReturn) { return }
                Write-OutputColor "  Invalid selection. Enter 1-6 or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Function to show all downloaded ISOs with details
function Show-ISOInventory {
    # Use Get-ISOStoragePath so the inventory correctly resolves to the cluster ISO
    # path when running on a clustered host. The previous direct read of
    # $script:HostISOPath ignored cluster mode and reported "no ISOs" even when ISOs
    # were sitting on the cluster shared volume.
    $isoPath = Get-ISOStoragePath
    if ([string]::IsNullOrWhiteSpace($isoPath) -or -not (Test-Path -LiteralPath $isoPath)) {
        Write-OutputColor "  ISO directory not configured or doesn't exist" -color "Warning"
        return
    }

    $isos = @(Get-ChildItem -LiteralPath $isoPath -Filter '*.iso' -ErrorAction SilentlyContinue)

    if ($isos.Count -eq 0) {
        Write-OutputColor "  No ISO files found in $isoPath" -color "Info"
        return
    }

    Write-OutputColor "`n  ISO Inventory ($($isos.Count) files):" -color "Info"

    $totalSize = 0
    foreach ($iso in $isos | Sort-Object Name) {
        $sizeGB = [math]::Round($iso.Length / 1GB, 1)
        $totalSize += $iso.Length
        $age = (Get-Date) - $iso.LastWriteTime
        $ageStr = if ($age.TotalDays -gt 365) { "$([math]::Round($age.TotalDays / 365, 0))y old" }
                  elseif ($age.TotalDays -gt 30) { "$([math]::Round($age.TotalDays / 30, 0))mo old" }
                  else { "$([math]::Round($age.TotalDays, 0))d old" }

        Write-OutputColor "  $($iso.Name)  ${sizeGB} GB  ($ageStr)" -color "Info"
    }

    $totalGB = [math]::Round($totalSize / 1GB, 1)
    Write-OutputColor "`n  Total: ${totalGB} GB across $($isos.Count) ISO(s)" -color "Info"
}
#endregion