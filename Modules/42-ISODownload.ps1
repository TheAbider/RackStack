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
    if (Test-Path $isoPath) {
        $found = Get-ChildItem -Path $isoPath -Filter "*$OSVersion*.iso" -File -ErrorAction SilentlyContinue | Select-Object -First 1
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

    # Validate the ISO storage path is configured
    if (-not $isoPath) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ISO storage path not configured." -color "Error"
        Write-OutputColor "  Run 'Host Storage Setup' first to configure storage." -color "Warning"
        return $null
    }

    # Ensure ISO directory exists
    if (-not (Test-Path $isoPath)) {
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
        # Integrity check: size mismatch = corrupt, silently delete
        $remoteSize = Get-FileServerFileSize -FilePath $driveFile.FilePath
        if ($remoteSize -gt 0 -and $cached.Size -ne $remoteSize) {
            Remove-Item $cached.Path -Force -ErrorAction SilentlyContinue
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
                Remove-Item $cached.Path -Force -ErrorAction SilentlyContinue
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

        switch ($choice) {
            "1" {
                Write-OutputColor "  ISO is ready at: $($cached.Path)" -color "Success"
                return $cached.Path
            }
            "2" {
                Write-OutputColor "  Removing old ISO..." -color "Info"
                Remove-Item $cached.Path -Force -ErrorAction SilentlyContinue
            }
            default { return $null }
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
        Add-SessionChange -Category "ISO Download" -Description "Downloaded Server $OSVersion ISO to $isoPath"
        return $result.FilePath
    }
    else {
        Write-OutputColor "  Failed to download ISO: $($result.Error)" -color "Error"
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
    Write-OutputColor "  │$("   [5]  ◄ Back".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to run ISO download menu loop
function Start-ISODownload {
    while ($true) {
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