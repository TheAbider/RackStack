#region ===== HOST STORAGE SETUP =====
# Generate Defender VM exclusion paths based on current host drive
function Update-DefenderVMPaths {
    $drive = $script:SelectedHostDrive  # e.g. "D:"
    $script:DefenderCommonVMPaths = @(
        "$drive\Virtual Machines"
        "$drive\Hyper-V"
        "$drive\ISOs"
        "$drive\Virtual Machines\_BaseImages"
    )
    # Also add cluster paths if they exist
    if (Test-Path "C:\ClusterStorage") {
        $csvVolumes = Get-ChildItem "C:\ClusterStorage" -Directory -ErrorAction SilentlyContinue
        foreach ($vol in $csvVolumes) {
            $script:DefenderCommonVMPaths += "$($vol.FullName)\Virtual Machines"
        }
    }
}

# Function to check if a drive letter is a CD/DVD/ISO mounted drive
function Test-OpticalDrive {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$DriveLetter
    )

    $letter = $DriveLetter.TrimEnd(':')

    # Check WMI for CD-ROM drives
    $cdDrives = Get-CimInstance -ClassName Win32_CDROMDrive -ErrorAction SilentlyContinue
    foreach ($cd in $cdDrives) {
        if ($cd.Drive -and $cd.Drive.TrimEnd(':') -eq $letter) {
            return @{ IsOptical = $true; Type = "CD/DVD"; Name = $cd.Caption }
        }
    }

    # Check volumes for removable/CD-ROM type
    $volume = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
    if ($volume) {
        if ($volume.DriveType -eq "CD-ROM") {
            return @{ IsOptical = $true; Type = "CD-ROM"; Name = $volume.FileSystemLabel }
        }
    }

    # Check disk drive type
    $partition = Get-Partition -DriveLetter $letter -ErrorAction SilentlyContinue
    if ($partition) {
        $disk = Get-Disk -Number $partition.DiskNumber -ErrorAction SilentlyContinue
        if ($disk -and $disk.BusType -eq "ATAPI") {
            return @{ IsOptical = $true; Type = "ATAPI/Optical"; Name = $disk.FriendlyName }
        }
    }

    return @{ IsOptical = $false; Type = $null; Name = $null }
}

# Function to find the next available drive letter (starting from Z: working backwards, skipping D)
function Get-NextAvailableDriveLetter {
    param (
        [string[]]$Exclude = @()
    )

    $usedLetters = @()
    $usedLetters += (Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | ForEach-Object { $_.DriveLetter })
    $usedLetters += (Get-CimInstance -ClassName Win32_CDROMDrive -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Drive) { $_.Drive.TrimEnd(':') }
    })
    $usedLetters += $Exclude

    # Try Z, Y, X... down to E (skip A, B, C, D)
    foreach ($letter in 'Z','Y','X','W','V','U','T','S','R','Q','P','O','N','M','L','K','J','I','H','G','F','E') {
        if ($letter -notin $usedLetters) {
            return $letter
        }
    }

    return $null
}

# Function to remount a CD/DVD drive from D: to another letter
function Move-OpticalDriveFromD {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  The D: drive is currently assigned to a CD/DVD or ISO mount." -color "Warning"
    Write-OutputColor "  D: needs to be free for VM data storage." -color "Info"
    Write-OutputColor "" -color "Info"

    $newLetter = Get-NextAvailableDriveLetter
    if (-not $newLetter) {
        Write-OutputColor "  ERROR: No available drive letters to reassign the optical drive." -color "Error"
        return $false
    }

    Write-OutputColor "  The optical drive will be moved from D: to ${newLetter}:" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Remount the optical/DVD drive from D: to ${newLetter}:?")) {
        Write-OutputColor "  Cancelled. D: drive is still occupied by optical drive." -color "Warning"
        return $false
    }

    try {
        # Try using diskpart-style approach via WMI/CIM
        $volume = Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter='D:'" -ErrorAction SilentlyContinue

        if ($volume) {
            # Change the drive letter
            Set-CimInstance -InputObject $volume -Property @{ DriveLetter = "${newLetter}:" } -ErrorAction Stop
            Write-OutputColor "  Optical drive moved from D: to ${newLetter}: successfully!" -color "Success"
            return $true
        }
        else {
            # Fallback: use mountvol approach
            Write-OutputColor "  Attempting alternative method..." -color "Info"

            # Get the volume GUID for D: (re-query since first attempt returned $null)
            $volGuid = (Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter='D:'" -ErrorAction SilentlyContinue).DeviceID

            if ($volGuid) {
                # Remove D: mount point
                mountvol D: /D 2>$null
                # Mount at new letter
                mountvol "${newLetter}:" $volGuid 2>$null

                if (Test-Path "${newLetter}:\") {
                    Write-OutputColor "  Optical drive moved from D: to ${newLetter}: successfully!" -color "Success"
                    return $true
                }
            }

            Write-OutputColor "  Could not automatically remount. Please use Disk Management." -color "Warning"
            return $false
        }
    }
    catch {
        Write-OutputColor "  Failed to remount optical drive: $_" -color "Error"
        Write-OutputColor "  You may need to do this manually in Disk Management." -color "Warning"
        return $false
    }
}

# Function to validate and set up D: drive for host VM storage
function Initialize-HostStorage {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       HOST STORAGE SETUP").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Step 1: Find all valid data drives (not C:, not optical, not < 20GB)
    Write-OutputColor "  Scanning for available data drives..." -color "Info"
    Write-OutputColor "" -color "Info"

    # First, check if D: is an optical drive and offer to remount it
    if (Test-Path "D:\") {
        $opticalCheck = Test-OpticalDrive -DriveLetter "D"
        if ($opticalCheck.IsOptical) {
            Write-OutputColor "  D: is currently a $($opticalCheck.Type) drive ($($opticalCheck.Name))." -color "Warning"
            Write-OutputColor "  D: is the standard data drive letter for Hyper-V hosts." -color "Info"
            Write-OutputColor "" -color "Info"
            if (Confirm-UserAction -Message "Remount the optical drive off D: to free it up?") {
                $remounted = Move-OpticalDriveFromD
                if ($remounted) {
                    Write-OutputColor "  DVD drive moved off D: successfully." -color "Success"
                }
                else {
                    Write-OutputColor "  Could not auto-remount. You can do this in Disk Management." -color "Warning"
                }
                Write-OutputColor "" -color "Info"
            }
        }
    }

    # Gather valid data drives
    $validDrives = @()
    $volumes = Get-Volume -ErrorAction SilentlyContinue | Where-Object {
        $_.DriveLetter -and
        $_.DriveLetter -ne 'C' -and
        $_.DriveType -eq 'Fixed' -and
        $_.FileSystem -eq 'NTFS'
    }

    foreach ($vol in $volumes) {
        $letter = $vol.DriveLetter
        # Skip optical drives
        $optCheck = Test-OpticalDrive -DriveLetter $letter
        if ($optCheck.IsOptical) { continue }

        # Check disk size
        $partition = Get-Partition -DriveLetter $letter -ErrorAction SilentlyContinue
        if (-not $partition) { continue }
        $disk = Get-Disk -Number $partition.DiskNumber -ErrorAction SilentlyContinue
        if (-not $disk) { continue }
        $diskSizeGB = [math]::Round($disk.Size / 1GB, 1)
        if ($diskSizeGB -lt 20) { continue }

        $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 1)
        $totalGB = [math]::Round($vol.Size / 1GB, 1)

        $validDrives += @{
            Letter = $letter
            Label = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { "Local Disk" }
            TotalGB = $totalGB
            FreeGB = $freeGB
            DiskName = $disk.FriendlyName
            BusType = $disk.BusType
        }
    }

    if ($validDrives.Count -eq 0) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Warning"
        Write-OutputColor "  │$("  NO VALID DATA DRIVES FOUND".PadRight(72))│" -color "Error"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │                                                                        │" -color "Info"
        Write-OutputColor "  │$("  No NTFS data drives found (excluding C: and drives < 20GB).".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  You need a formatted data drive for Hyper-V VM storage.".PadRight(72))│" -color "Info"
        Write-OutputColor "  │                                                                        │" -color "Info"
        Write-OutputColor "  │  Steps:                                                                │" -color "Info"
        Write-OutputColor "  │   1. Open Disk Management                                              │" -color "Info"
        Write-OutputColor "  │   2. Initialize and format a data disk as NTFS                         │" -color "Info"
        Write-OutputColor "  │   3. Assign it a drive letter (D: recommended)                         │" -color "Info"
        Write-OutputColor "  │   4. Come back and run this option again                               │" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        if (Confirm-UserAction -Message "Open Disk Management now?") {
            Start-Process "diskmgmt.msc" -ErrorAction SilentlyContinue
            Write-OutputColor "  Disk Management opened. Set up a data drive and run this again." -color "Info"
        }
        return $false
    }

    # Step 2: Let user select which drive to use
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  AVAILABLE DATA DRIVES".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $index = 1
    foreach ($drv in $validDrives) {
        $recommended = if ($drv.Letter -eq 'D') { " (Recommended)" } else { "" }
        $driveInfo = "$($drv.Letter):  $($drv.Label)  |  $($drv.TotalGB) GB total  |  $($drv.FreeGB) GB free$recommended"
        $color = if ($drv.Letter -eq 'D') { "Success" } else { "Info" }
        Write-OutputColor "  │  [$index]  $($driveInfo.PadRight(64))│" -color $color
        $index++
    }

    Write-OutputColor "  │                                                                        │" -color "Info"
    $diskMgmtIndex = $index
    $diskMgmtLine = "  │  [$diskMgmtIndex]  Open Disk Management (need a different drive)"
    Write-OutputColor "$($diskMgmtLine.PadRight(75))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "   [0] ◄ Back - No Changes" -color "Info"
    Write-OutputColor "" -color "Info"

    $driveChoice = Read-Host "  Select drive for VM storage"

    $navResult = Test-NavigationCommand -UserInput $driveChoice
    if ($navResult.ShouldReturn) { return $false }

    if ($driveChoice -eq "0") {
        Write-OutputColor "  No changes made." -color "Info"
        return $false
    }

    if ($driveChoice -match '^\d+$') {
        $choiceNum = [int]$driveChoice
        if ($choiceNum -eq $diskMgmtIndex) {
            Start-Process "diskmgmt.msc" -ErrorAction SilentlyContinue
            Write-OutputColor "  Disk Management opened." -color "Info"
            return $false
        }
        if ($choiceNum -lt 1 -or $choiceNum -gt $validDrives.Count) {
            Write-OutputColor "  Invalid choice." -color "Error"
            return $false
        }
    }
    else {
        $navResult = Test-NavigationCommand -UserInput $driveChoice
        if ($navResult.ShouldReturn) { return $false }
        Write-OutputColor "  Invalid choice." -color "Error"
        return $false
    }

    $selectedDrive = $validDrives[$choiceNum - 1]
    $driveLetter = $selectedDrive.Letter

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Selected drive: $($driveLetter):" -color "Success"
    Write-OutputColor "" -color "Info"

    # Step 3: Update all storage path variables to use the selected drive
    $script:SelectedHostDrive = "$($driveLetter):"
    $script:HostVMStoragePath = "$($driveLetter):\Virtual Machines"
    $script:HostISOPath = "$($driveLetter):\ISOs"
    $script:VHDCachePath = "$($driveLetter):\Virtual Machines\_BaseImages"

    # Step 4: Create folder structure
    Write-OutputColor "  Setting up folder structure on $($driveLetter): drive..." -color "Info"
    Write-OutputColor "" -color "Info"

    $foldersToCreate = @(
        $script:HostVMStoragePath,
        $script:HostISOPath,
        $script:VHDCachePath
    )

    foreach ($folder in $foldersToCreate) {
        if (-not (Test-Path $folder)) {
            try {
                New-Item -Path $folder -ItemType Directory -Force | Out-Null
                Write-OutputColor "  Created: $folder" -color "Success"
            }
            catch {
                Write-OutputColor "  Failed to create: $folder - $_" -color "Error"
            }
        }
        else {
            Write-OutputColor "  Exists:  $folder" -color "Info"
        }
    }

    Write-OutputColor "" -color "Info"

    # Step 5: Set Hyper-V default paths
    Write-OutputColor "  Configuring Hyper-V default paths..." -color "Info"

    try {
        $vmHost = Get-VMHost -ErrorAction SilentlyContinue
        if ($vmHost) {
            $currentVMPath = $vmHost.VirtualMachinePath
            $currentVHDPath = $vmHost.VirtualHardDiskPath
            $targetVMPath = $script:HostVMStoragePath
            $targetVHDPath = $script:HostVMStoragePath

            $changed = $false

            if ($currentVMPath -ne $targetVMPath) {
                Set-VMHost -VirtualMachinePath $targetVMPath -ErrorAction Stop
                Write-OutputColor "  Default VM path:  $currentVMPath -> $targetVMPath" -color "Success"
                $changed = $true
            }
            else {
                Write-OutputColor "  Default VM path already set: $targetVMPath" -color "Info"
            }

            if ($currentVHDPath -ne $targetVHDPath) {
                Set-VMHost -VirtualHardDiskPath $targetVHDPath -ErrorAction Stop
                Write-OutputColor "  Default VHD path: $currentVHDPath -> $targetVHDPath" -color "Success"
                $changed = $true
            }
            else {
                Write-OutputColor "  Default VHD path already set: $targetVHDPath" -color "Info"
            }

            if ($changed) {
                Add-SessionChange -Category "Host Storage" -Description "Set Hyper-V default paths to $targetVMPath"
            }
        }
        else {
            Write-OutputColor "  Hyper-V not detected. Default paths will be set after Hyper-V is installed." -color "Warning"
        }
    }
    catch {
        Write-OutputColor "  Failed to set Hyper-V defaults: $_" -color "Error"
        Write-OutputColor "  You can set these manually in Hyper-V Settings." -color "Info"
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  HOST STORAGE SETUP COMPLETE".PadRight(72))│" -color "Success"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    $vmPathDisplay = $script:HostVMStoragePath.PadRight(56)
    $basePathDisplay = $script:VHDCachePath.PadRight(56)
    $isoPathDisplay = $script:HostISOPath.PadRight(56)
    Write-OutputColor "  │  VM Storage:   $vmPathDisplay│" -color "Info"
    Write-OutputColor "  │  Base Images:  $basePathDisplay│" -color "Info"
    Write-OutputColor "  │  ISOs:         $isoPathDisplay│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    # Update Defender exclusion paths to match the selected drive
    Update-DefenderVMPaths

    Add-SessionChange -Category "Host Storage" -Description "Initialized $($driveLetter): drive for VM storage"
    $script:StorageInitialized = $true

    return $true
}
#endregion