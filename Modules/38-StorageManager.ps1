#region ===== STORAGE MANAGER =====
# Wrapper for Format-TransferSize (defined in 04-Navigation.ps1)
function Format-ByteSize {
    param (
        [Parameter(Mandatory=$true)]
        [long]$Bytes
    )
    return Format-TransferSize -Bytes $Bytes
}

# Function to get disk health status
function Get-DiskHealthStatus {
    param (
        [Parameter(Mandatory=$true)]
        $Disk
    )

    try {
        # Try to correlate using disk path/location
        $physicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue

        if ($physicalDisks) {
            # Try matching by serial number if available
            if ($Disk.SerialNumber) {
                $health = $physicalDisks | Where-Object { $_.SerialNumber -eq $Disk.SerialNumber } | Select-Object -First 1
                if ($health) {
                    return $health.HealthStatus
                }
            }

            # Try matching by friendly name
            if ($Disk.FriendlyName) {
                $health = $physicalDisks | Where-Object { $_.FriendlyName -eq $Disk.FriendlyName } | Select-Object -First 1
                if ($health) {
                    return $health.HealthStatus
                }
            }

            # Fallback: try to match by size (approximate)
            $diskSizeGB = [math]::Round($Disk.Size / 1GB)
            $health = $physicalDisks | Where-Object {
                [math]::Round($_.Size / 1GB) -eq $diskSizeGB
            } | Select-Object -First 1
            if ($health) {
                return $health.HealthStatus
            }
        }

        return "Unknown"
    }
    catch {
        return "Unknown"
    }
}

# Function to display all disks with details
function Show-AllDisks {
    Clear-Host
    Write-CenteredOutput "Disk Overview" -color "Info"

    Write-OutputColor "Scanning disks..." -color "Info"
    Write-OutputColor "" -color "Info"

    $disks = @(Get-Disk | Sort-Object Number)

    if ($disks.Count -eq 0) {
        Write-OutputColor "No disks found." -color "Warning"
        return
    }

    Write-OutputColor ("=" * 100) -color "Info"
    Write-OutputColor ("{0,-6} {1,-12} {2,-12} {3,-15} {4,-12} {5,-15} {6}" -f "Disk", "Status", "Health", "Size", "Style", "Partition", "Type") -color "Info"
    Write-OutputColor ("=" * 100) -color "Info"

    foreach ($disk in $disks) {
        $size = Format-ByteSize -Bytes $disk.Size
        $health = Get-DiskHealthStatus -Disk $disk
        $partStyle = if ($disk.PartitionStyle -eq "RAW") { "Not Init" } else { $disk.PartitionStyle }
        $busType = $disk.BusType

        # Color coding
        $statusColor = switch ($disk.OperationalStatus) {
            "Online" { "Success" }
            "Offline" { "Error" }
            default { "Warning" }
        }

        $healthColor = switch ($health) {
            "Healthy" { "Success" }
            "Warning" { "Warning" }
            "Unhealthy" { "Error" }
            default { "Info" }
        }

        Write-OutputColor ("{0,-6} " -f $disk.Number) -color "Info" -NoNewline
        Write-OutputColor ("{0,-12} " -f $disk.OperationalStatus) -color $statusColor -NoNewline
        Write-OutputColor ("{0,-12} " -f $health) -color $healthColor -NoNewline
        Write-OutputColor ("{0,-15} {1,-12} {2,-15} {3}" -f $size, $partStyle, $disk.NumberOfPartitions, $busType) -color "Info"

        # Show friendly name
        if ($disk.FriendlyName) {
            Write-OutputColor ("       Model: {0}" -f $disk.FriendlyName) -color "Info"
        }
    }

    Write-OutputColor ("=" * 100) -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "Total Disks: $($disks.Count)" -color "Info"
}

# Function to display partitions for a specific disk
function Show-DiskPartitions {
    param (
        [Parameter(Mandatory=$true)]
        [int]$DiskNumber
    )

    Clear-Host
    Write-CenteredOutput "Partitions on Disk $DiskNumber" -color "Info"

    $disk = Get-Disk -Number $DiskNumber -ErrorAction SilentlyContinue
    if (-not $disk) {
        Write-OutputColor "Disk $DiskNumber not found." -color "Error"
        return
    }

    Write-OutputColor "Disk: $($disk.FriendlyName)" -color "Info"
    Write-OutputColor "Size: $(Format-ByteSize -Bytes $disk.Size)" -color "Info"
    Write-OutputColor "Partition Style: $($disk.PartitionStyle)" -color "Info"
    Write-OutputColor "" -color "Info"

    $partitions = Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue

    if (-not $partitions -or $partitions.Count -eq 0) {
        Write-OutputColor "No partitions found on this disk." -color "Warning"

        if ($disk.PartitionStyle -eq "RAW") {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "This disk needs to be initialized before partitions can be created." -color "Warning"
        }
        return
    }

    Write-OutputColor ("=" * 95) -color "Info"
    Write-OutputColor ("{0,-8} {1,-8} {2,-15} {3,-15} {4,-12} {5}" -f "Part #", "Drive", "Size", "Type", "Is Active", "Offset") -color "Info"
    Write-OutputColor ("=" * 95) -color "Info"

    foreach ($part in $partitions) {
        $size = Format-ByteSize -Bytes $part.Size
        $driveLetter = if ($part.DriveLetter) { "$($part.DriveLetter):" } else { "-" }
        $offset = Format-ByteSize -Bytes $part.Offset
        $isActive = if ($part.IsActive) { "Yes" } else { "No" }

        $typeColor = switch ($part.Type) {
            "System" { "Warning" }
            "Reserved" { "Warning" }
            "Recovery" { "Warning" }
            "Basic" { "Success" }
            default { "Info" }
        }

        Write-OutputColor ("{0,-8} {1,-8} {2,-15} " -f $part.PartitionNumber, $driveLetter, $size) -color "Info" -NoNewline
        Write-OutputColor ("{0,-15} " -f $part.Type) -color $typeColor -NoNewline
        Write-OutputColor ("{0,-12} {1}" -f $isActive, $offset) -color "Info"
    }

    Write-OutputColor ("=" * 95) -color "Info"
}

# Function to display volumes with details
function Show-AllVolumes {
    Clear-Host
    Write-CenteredOutput "Volume Overview" -color "Info"

    Write-OutputColor "" -color "Info"

    $volumes = @(Get-Volume | Where-Object { $_.DriveLetter -or $_.FileSystemLabel } | Sort-Object DriveLetter)

    if ($volumes.Count -eq 0) {
        Write-OutputColor "No volumes found." -color "Warning"
        return
    }

    Write-OutputColor ("=" * 100) -color "Info"
    Write-OutputColor ("{0,-8} {1,-20} {2,-12} {3,-15} {4,-15} {5,-10} {6}" -f "Drive", "Label", "FileSystem", "Size", "Free", "% Used", "Health") -color "Info"
    Write-OutputColor ("=" * 100) -color "Info"

    foreach ($vol in $volumes) {
        $driveLetter = if ($vol.DriveLetter) { "$($vol.DriveLetter):" } else { "-" }
        $label = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { "(No Label)" }
        if ($label.Length -gt 18) { $label = $label.Substring(0, 18) + ".." }

        $size = Format-ByteSize -Bytes $vol.Size
        $free = Format-ByteSize -Bytes $vol.SizeRemaining

        $usedPercent = if ($vol.Size -gt 0) {
            [math]::Round((($vol.Size - $vol.SizeRemaining) / $vol.Size) * 100, 1)
        } else { 0 }

        # Color coding for space usage
        $usageColor = if ($usedPercent -ge 90) { "Error" }
                      elseif ($usedPercent -ge 75) { "Warning" }
                      else { "Success" }

        $healthColor = switch ($vol.HealthStatus) {
            "Healthy" { "Success" }
            "Warning" { "Warning" }
            "Unhealthy" { "Error" }
            default { "Info" }
        }

        Write-OutputColor ("{0,-8} {1,-20} {2,-12} {3,-15} {4,-15} " -f $driveLetter, $label, $vol.FileSystem, $size, $free) -color "Info" -NoNewline
        Write-OutputColor ("{0,-10} " -f "$usedPercent%") -color $usageColor -NoNewline
        Write-OutputColor ("{0}" -f $vol.HealthStatus) -color $healthColor
    }

    Write-OutputColor ("=" * 100) -color "Info"
}

# Function to select a disk
function Select-Disk {
    param (
        [string]$Prompt = "Select a disk",
        [switch]$AllowOffline,
        [switch]$OnlyUninitialized,
        [switch]$OnlyInitialized,
        [switch]$AllowOSDisk,
        [switch]$ExcludeSystemDisk
    )

    $disks = @(Get-Disk | Sort-Object Number)

    if ($OnlyUninitialized) {
        $disks = @($disks | Where-Object { $_.PartitionStyle -eq "RAW" })
    }

    if ($OnlyInitialized) {
        $disks = @($disks | Where-Object { $_.PartitionStyle -ne "RAW" })
    }

    if (-not $AllowOffline) {
        $disks = @($disks | Where-Object { $_.OperationalStatus -eq "Online" })
    }

    # Identify the OS disk (contains Windows partition)
    $osDiskNumber = $null
    try {
        $systemDrive = $env:SystemDrive.TrimEnd(':')
        $osPartition = Get-Partition -DriveLetter $systemDrive -ErrorAction SilentlyContinue
        if ($osPartition) {
            $osDiskNumber = $osPartition.DiskNumber
        }
    }
    catch {
        Write-OutputColor "  Warning: Could not identify OS disk. Proceed with caution." -color "Warning"
    }

    # Exclude OS disk for destructive operations unless explicitly allowed
    if ($ExcludeSystemDisk -and $null -ne $osDiskNumber) {
        $disks = @($disks | Where-Object { $_.Number -ne $osDiskNumber })
    }

    if ($disks.Count -eq 0) {
        Write-OutputColor "No eligible disks found." -color "Warning"
        return $null
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor $Prompt -color "Info"
    Write-OutputColor "" -color "Info"

    foreach ($disk in $disks) {
        $size = Format-ByteSize -Bytes $disk.Size
        $partStyle = if ($disk.PartitionStyle -eq "RAW") { "Not Initialized" } else { $disk.PartitionStyle }

        # Mark OS disk with warning
        $osMarker = ""
        if ($disk.Number -eq $osDiskNumber) {
            $osMarker = " [OS DISK]"
        }

        if ($osMarker -and -not $AllowOSDisk) {
            Write-OutputColor "  [$($disk.Number)] $($disk.FriendlyName) - $size ($partStyle)$osMarker" -color "Warning"
        }
        else {
            Write-OutputColor "  [$($disk.Number)] $($disk.FriendlyName) - $size ($partStyle)$osMarker" -color "Success"
        }
    }

    Write-OutputColor "" -color "Info"
    $selection = Read-Host "Enter disk number (or 'back' to cancel)"

    $navResult = Test-NavigationCommand -UserInput $selection
    if ($navResult.ShouldReturn) {
        return $null
    }

    if ($selection -match '^\d+$') {
        $selectedDisk = $disks | Where-Object { $_.Number -eq [int]$selection }
        if ($selectedDisk) {
            # Extra warning for OS disk
            if ($selectedDisk.Number -eq $osDiskNumber -and -not $AllowOSDisk) {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "!!! WARNING: This is your OPERATING SYSTEM disk !!!" -color "Error"
                Write-OutputColor "Modifying this disk may make your system unbootable!" -color "Error"
                Write-OutputColor "" -color "Info"
                if (-not (Confirm-UserAction -Message "Are you SURE you want to select the OS disk?")) {
                    Write-OutputColor "Selection cancelled." -color "Info"
                    return $null
                }
            }
            return $selectedDisk
        }
    }

    Write-OutputColor "Invalid selection." -color "Error"
    return $null
}

# Function to select a partition
function Select-Partition {
    param (
        [Parameter(Mandatory=$true)]
        [int]$DiskNumber,
        [string]$Prompt = "Select a partition",
        [switch]$AllowSystemPartitions
    )

    $partitions = Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue

    if (-not $AllowSystemPartitions) {
        # Filter out system-critical partitions
        $partitions = $partitions | Where-Object {
            $_.Type -ne "Reserved" -and
            $_.Type -ne "System" -and
            $_.Type -ne "Recovery" -and
            $_.GptType -ne "{e3c9e316-0b5c-4db8-817d-f92df00215ae}" -and  # Microsoft Reserved
            $_.GptType -ne "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" -and  # EFI System
            $_.GptType -ne "{de94bba4-06d1-4d40-a16a-bfd50179d6ac}"       # Windows Recovery
        }
    }

    if (-not $partitions -or $partitions.Count -eq 0) {
        Write-OutputColor "No eligible partitions found on disk $DiskNumber." -color "Warning"
        Write-OutputColor "(System, Reserved, and Recovery partitions are protected)" -color "Info"
        return $null
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor $Prompt -color "Info"
    Write-OutputColor "" -color "Info"

    foreach ($part in $partitions) {
        $size = Format-ByteSize -Bytes $part.Size
        $driveLetter = if ($part.DriveLetter) { "$($part.DriveLetter):" } else { "No Letter" }
        $typeDisplay = if ($part.Type) { $part.Type } else { "Basic" }
        Write-OutputColor "  [$($part.PartitionNumber)] $driveLetter - $size ($typeDisplay)" -color "Success"
    }

    Write-OutputColor "" -color "Info"
    $selection = Read-Host "Enter partition number (or 'back' to cancel)"

    $navResult = Test-NavigationCommand -UserInput $selection
    if ($navResult.ShouldReturn) {
        return $null
    }

    if ($selection -match '^\d+$') {
        $selectedPart = $partitions | Where-Object { $_.PartitionNumber -eq [int]$selection }
        if ($selectedPart) {
            return $selectedPart
        }
    }

    Write-OutputColor "Invalid selection." -color "Error"
    return $null
}

# Function to initialize a disk
function Initialize-NewDisk {
    Clear-Host
    Write-CenteredOutput "Initialize Disk" -color "Info"

    Write-OutputColor "This will initialize an uninitialized (RAW) disk." -color "Info"
    Write-OutputColor "Initializing prepares the disk for partitioning." -color "Info"
    Write-OutputColor "" -color "Info"

    # Check for offline disks first - they must be brought online before initialization
    $offlineDisks = @(Get-Disk | Where-Object { $_.OperationalStatus -eq "Offline" })
    if ($offlineDisks.Count -gt 0) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  $($offlineDisks.Count) disk(s) are currently offline." -color "Warning"
        Write-OutputColor "  Offline disks must be brought online before they can be initialized." -color "Info"
        Write-OutputColor "" -color "Info"
        if (Confirm-UserAction -Message "Bring offline disks online now?") {
            foreach ($offDisk in $offlineDisks) {
                try {
                    Set-Disk -Number $offDisk.Number -IsOffline $false -ErrorAction Stop
                    Set-Disk -Number $offDisk.Number -IsReadOnly $false -ErrorAction SilentlyContinue
                    # Verify read-only was cleared
                    $diskState = Get-Disk -Number $offDisk.Number
                    if ($diskState.IsReadOnly) {
                        Write-OutputColor "  Disk $($offDisk.Number) is online but still read-only (may need firmware/driver update)." -color "Warning"
                    }
                    else {
                        Write-OutputColor "  Disk $($offDisk.Number) ($($offDisk.FriendlyName)) brought online." -color "Success"
                    }
                }
                catch {
                    Write-OutputColor "  Failed to bring Disk $($offDisk.Number) online: $_" -color "Error"
                }
            }
            Write-OutputColor "" -color "Info"
        }
    }

    # Show only uninitialized disks
    $rawDisks = @(Get-Disk | Where-Object { $_.PartitionStyle -eq "RAW" })

    if ($rawDisks.Count -eq 0) {
        Write-OutputColor "No uninitialized disks found." -color "Warning"
        Write-OutputColor "All disks are already initialized." -color "Info"
        return
    }

    $disk = Select-Disk -Prompt "Select a disk to initialize:" -OnlyUninitialized

    if (-not $disk) {
        return
    }

    # Double-check selected disk is online
    if ($disk.OperationalStatus -eq "Offline") {
        Write-OutputColor "" -color "Warning"
        Write-OutputColor "  This disk is offline and cannot be initialized." -color "Warning"
        if (Confirm-UserAction -Message "Bring Disk $($disk.Number) online now?") {
            try {
                Set-Disk -Number $disk.Number -IsOffline $false -ErrorAction Stop
                Set-Disk -Number $disk.Number -IsReadOnly $false -ErrorAction SilentlyContinue
                Write-OutputColor "  Disk $($disk.Number) brought online." -color "Success"
            }
            catch {
                Write-OutputColor "  Failed to bring disk online: $_" -color "Error"
                return
            }
        } else {
            return
        }
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Selected: Disk $($disk.Number) - $($disk.FriendlyName)" -color "Info"
    Write-OutputColor "Size: $(Format-ByteSize -Bytes $disk.Size)" -color "Info"
    Write-OutputColor "" -color "Info"

    # Ask for partition style
    Write-OutputColor "Select partition style:" -color "Info"
    Write-OutputColor "  [1] GPT (Recommended for disks > 2TB and UEFI systems)" -color "Success"
    Write-OutputColor "  [2] MBR (Legacy, required for some older systems)" -color "Success"
    Write-OutputColor "" -color "Info"

    $styleChoice = Read-Host "Enter choice (1 or 2)"

    $partitionStyle = switch ($styleChoice) {
        "1" { "GPT" }
        "2" { "MBR" }
        default {
            Write-OutputColor "Invalid choice. Defaulting to GPT." -color "Warning"
            "GPT"
        }
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "WARNING: This will prepare the disk for use." -color "Warning"
    Write-OutputColor "Partition Style: $partitionStyle" -color "Info"

    if (-not (Confirm-UserAction -Message "Initialize Disk $($disk.Number) as $partitionStyle?")) {
        Write-OutputColor "Operation cancelled." -color "Info"
        return
    }

    try {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Initializing disk..." -color "Info"

        Initialize-Disk -Number $disk.Number -PartitionStyle $partitionStyle -ErrorAction Stop

        Write-OutputColor "Disk $($disk.Number) initialized successfully as $partitionStyle!" -color "Success"
        Add-SessionChange -Category "Storage" -Description "Initialized Disk $($disk.Number) as $partitionStyle"
    }
    catch {
        Write-OutputColor "Failed to initialize disk: $_" -color "Error"
    }
}

# Function to bring a disk online or offline
function Set-DiskOnlineStatus {
    Clear-Host
    Write-CenteredOutput "Set Disk Online/Offline" -color "Info"

    Write-OutputColor "This allows you to bring disks online or take them offline." -color "Info"
    Write-OutputColor "" -color "Info"

    $disk = Select-Disk -Prompt "Select a disk:" -AllowOffline

    if (-not $disk) {
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Selected: Disk $($disk.Number) - $($disk.FriendlyName)" -color "Info"
    Write-OutputColor "Current Status: $($disk.OperationalStatus)" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($disk.OperationalStatus -eq "Online") {
        Write-OutputColor "Options:" -color "Info"
        Write-OutputColor "  [1] Take disk OFFLINE" -color "Warning"
        Write-OutputColor "  [2] Cancel" -color "Success"

        $choice = Read-Host "Enter choice"

        if ($choice -eq "1") {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "WARNING: Taking a disk offline will make it inaccessible!" -color "Warning"
            Write-OutputColor "Any volumes on this disk will become unavailable." -color "Warning"

            if (-not (Confirm-UserAction -Message "Take Disk $($disk.Number) offline?")) {
                Write-OutputColor "Operation cancelled." -color "Info"
                return
            }

            try {
                Set-Disk -Number $disk.Number -IsOffline $true -ErrorAction Stop
                Write-OutputColor "Disk $($disk.Number) is now OFFLINE." -color "Success"
                Add-SessionChange -Category "Storage" -Description "Set Disk $($disk.Number) offline"
            }
            catch {
                Write-OutputColor "Failed to take disk offline: $_" -color "Error"
            }
        }
    }
    else {
        Write-OutputColor "Options:" -color "Info"
        Write-OutputColor "  [1] Bring disk ONLINE" -color "Success"
        Write-OutputColor "  [2] Cancel" -color "Info"

        $choice = Read-Host "Enter choice"

        if ($choice -eq "1") {
            try {
                Set-Disk -Number $disk.Number -IsOffline $false -ErrorAction Stop

                # Also clear read-only if set
                Set-Disk -Number $disk.Number -IsReadOnly $false -ErrorAction SilentlyContinue

                Write-OutputColor "Disk $($disk.Number) is now ONLINE." -color "Success"
                Add-SessionChange -Category "Storage" -Description "Set Disk $($disk.Number) online"
            }
            catch {
                Write-OutputColor "Failed to bring disk online: $_" -color "Error"
            }
        }
    }
}

# Function to clear/wipe a disk
function Clear-DiskData {
    Clear-Host
    Write-CenteredOutput "Clear Disk (Remove All Partitions)" -color "Info"

    Write-OutputColor "" -color "Info"
    Write-OutputColor "!!! WARNING !!!" -color "Error"
    Write-OutputColor "This will DESTROY ALL DATA on the selected disk!" -color "Error"
    Write-OutputColor "All partitions and data will be permanently deleted!" -color "Error"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "(OS disk is excluded from selection for safety)" -color "Info"
    Write-OutputColor "" -color "Info"

    $disk = Select-Disk -Prompt "Select a disk to clear:" -OnlyInitialized -ExcludeSystemDisk

    if (-not $disk) {
        return
    }

    # Double check it's not the OS disk
    $systemDrive = $env:SystemDrive.TrimEnd(':')
    $osPartition = Get-Partition -DriveLetter $systemDrive -ErrorAction SilentlyContinue
    if ($osPartition -and $osPartition.DiskNumber -eq $disk.Number) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "BLOCKED: Cannot clear the operating system disk!" -color "Error"
        Write-OutputColor "This would make your system unbootable." -color "Error"
        return
    }

    # Show what will be deleted
    Write-OutputColor "" -color "Info"
    Write-OutputColor "Selected: Disk $($disk.Number) - $($disk.FriendlyName)" -color "Info"
    Write-OutputColor "Size: $(Format-ByteSize -Bytes $disk.Size)" -color "Info"
    Write-OutputColor "" -color "Info"

    $partitions = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue
    if ($partitions) {
        Write-OutputColor "The following partitions will be DELETED:" -color "Warning"
        foreach ($part in $partitions) {
            $driveLetter = if ($part.DriveLetter) { "$($part.DriveLetter):" } else { "No Letter" }
            $typeInfo = if ($part.Type) { " [$($part.Type)]" } else { "" }
            Write-OutputColor "  - Partition $($part.PartitionNumber): $driveLetter ($(Format-ByteSize -Bytes $part.Size))$typeInfo" -color "Warning"
        }
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "This action CANNOT be undone!" -color "Error"
    Write-OutputColor "" -color "Info"

    # Require explicit confirmation
    Write-OutputColor "Type 'YES' (all caps) to confirm deletion:" -color "Warning"
    $confirmation = (Read-Host).Trim()

    if ($confirmation -ne "YES") {
        Write-OutputColor "Operation cancelled." -color "Info"
        return
    }

    # Double confirmation for safety
    if (-not (Confirm-UserAction -Message "FINAL WARNING: Clear Disk $($disk.Number)?")) {
        Write-OutputColor "Operation cancelled." -color "Info"
        return
    }

    try {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Clearing disk..." -color "Info"

        Clear-Disk -Number $disk.Number -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop

        Write-OutputColor "Disk $($disk.Number) cleared successfully!" -color "Success"
        Write-OutputColor "The disk is now uninitialized and ready to be set up fresh." -color "Info"
        Add-SessionChange -Category "Storage" -Description "Cleared all data from Disk $($disk.Number)"
    }
    catch {
        Write-OutputColor "Failed to clear disk: $_" -color "Error"
    }
}

# Function to create a new partition
function New-DiskPartition {
    Clear-Host
    Write-CenteredOutput "Create New Partition" -color "Info"

    Write-OutputColor "This will create a new partition on a disk." -color "Info"
    Write-OutputColor "" -color "Info"

    $disk = Select-Disk -Prompt "Select a disk:" -OnlyInitialized

    if (-not $disk) {
        return
    }

    # Check for unallocated space
    $partitions = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue
    $usedSpace = ($partitions | Measure-Object -Property Size -Sum).Sum
    if (-not $usedSpace) { $usedSpace = 0 }

    $unallocated = $disk.Size - $usedSpace

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Selected: Disk $($disk.Number) - $($disk.FriendlyName)" -color "Info"
    Write-OutputColor "Total Size: $(Format-ByteSize -Bytes $disk.Size)" -color "Info"
    Write-OutputColor "Unallocated Space: $(Format-ByteSize -Bytes $unallocated)" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($unallocated -lt 1MB) {
        Write-OutputColor "No unallocated space available on this disk." -color "Warning"
        Write-OutputColor "You may need to shrink or delete an existing partition first." -color "Info"
        return
    }

    # Ask for partition size
    Write-OutputColor "Enter partition size:" -color "Info"
    Write-OutputColor "  - Examples: '100', '100GB', '2TB', '500MB', 'MAX'" -color "Info"
    Write-OutputColor "  - Plain number defaults to GB (e.g., '100' = 100 GB)" -color "Info"
    Write-OutputColor "  - Enter 'MAX' to use all available space" -color "Info"
    Write-OutputColor "" -color "Info"

    $sizeInput = Read-Host "Partition size"

    $navResult = Test-NavigationCommand -UserInput $sizeInput
    if ($navResult.ShouldReturn) {
        return
    }

    $useMax = $false
    $partitionSize = 0

    if ($sizeInput -match '^max$') {
        $useMax = $true
        $partitionSize = $unallocated
    }
    elseif ($sizeInput -match '^(\d+(?:\.\d+)?)\s*(TB|GB|MB|T|G|M)?$') {
        $regexMatches = $matches
        $sizeNum = [double]$regexMatches[1]
        $sizeUnit = if ($regexMatches[2]) { $regexMatches[2].ToUpper() } else { "GB" }
        $partitionSize = switch ($sizeUnit) {
            { $_ -eq "TB" -or $_ -eq "T" } { [long]($sizeNum * 1TB) }
            { $_ -eq "GB" -or $_ -eq "G" } { [long]($sizeNum * 1GB) }
            { $_ -eq "MB" -or $_ -eq "M" } { [long]($sizeNum * 1MB) }
            default { [long]($sizeNum * 1GB) }
        }
        # Allow small tolerance (partition overhead) - if within 1MB of max, use max
        if ($partitionSize -gt $unallocated) {
            if (($partitionSize - $unallocated) -lt 1MB) {
                $useMax = $true
                $partitionSize = $unallocated
            } else {
                Write-OutputColor "Requested size ($(Format-ByteSize -Bytes $partitionSize)) exceeds available space." -color "Warning"
                Write-OutputColor "Maximum available: $(Format-ByteSize -Bytes $unallocated)" -color "Info"
                return
            }
        }
        if ($partitionSize -lt 1MB) {
            Write-OutputColor "Partition size must be at least 1 MB." -color "Warning"
            return
        }
    }
    else {
        Write-OutputColor "Invalid size input. Examples: '100', '2TB', '500MB', 'MAX'" -color "Error"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Partition size: $(Format-ByteSize -Bytes $partitionSize)" -color "Info"

    # Ask for drive letter using smart picker
    Write-OutputColor "" -color "Info"
    $driveLetter = Select-DriveLetterSmart
    $assignDriveLetter = $null -ne $driveLetter

    if (-not (Confirm-UserAction -Message "Create partition on Disk $($disk.Number)?")) {
        Write-OutputColor "Operation cancelled." -color "Info"
        return
    }

    try {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Creating partition..." -color "Info"

        if ($useMax) {
            $newPartition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -ErrorAction Stop
        }
        else {
            $newPartition = New-Partition -DiskNumber $disk.Number -Size $partitionSize -ErrorAction Stop
        }

        if ($assignDriveLetter -and $driveLetter) {
            Write-OutputColor "Assigning drive letter $driveLetter..." -color "Info"
            Set-Partition -DiskNumber $disk.Number -PartitionNumber $newPartition.PartitionNumber -NewDriveLetter $driveLetter -ErrorAction SilentlyContinue
        }

        Write-OutputColor "" -color "Info"
        Write-OutputColor "Partition created successfully!" -color "Success"
        Write-OutputColor "Partition Number: $($newPartition.PartitionNumber)" -color "Info"
        if ($driveLetter) {
            Write-OutputColor "Drive Letter: $driveLetter" -color "Info"
        }
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Note: The partition is not yet formatted. Use 'Format Volume' to format it." -color "Warning"

        Add-SessionChange -Category "Storage" -Description "Created partition on Disk $($disk.Number)"
    }
    catch {
        Write-OutputColor "Failed to create partition: $_" -color "Error"
    }
}

# Function to delete a partition
function Remove-DiskPartition {
    Clear-Host
    Write-CenteredOutput "Delete Partition" -color "Info"

    Write-OutputColor "" -color "Info"
    Write-OutputColor "WARNING: This will delete a partition and ALL DATA on it!" -color "Warning"
    Write-OutputColor "" -color "Info"

    $disk = Select-Disk -Prompt "Select a disk:" -OnlyInitialized

    if (-not $disk) {
        return
    }

    Show-DiskPartitions -DiskNumber $disk.Number

    $partition = Select-Partition -DiskNumber $disk.Number -Prompt "Select a partition to delete:"

    if (-not $partition) {
        return
    }

    # Warn about system/reserved partitions
    if ($partition.Type -eq "System" -or $partition.Type -eq "Reserved" -or $partition.IsBoot) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "!!! DANGER !!!" -color "Error"
        Write-OutputColor "This appears to be a system/boot partition!" -color "Error"
        Write-OutputColor "Deleting it may make your system unbootable!" -color "Error"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Are you ABSOLUTELY SURE?" -color "Error"
    }

    $driveLetter = if ($partition.DriveLetter) { "$($partition.DriveLetter):" } else { "No Letter" }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Selected: Partition $($partition.PartitionNumber) on Disk $($disk.Number)" -color "Info"
    Write-OutputColor "Drive Letter: $driveLetter" -color "Info"
    Write-OutputColor "Size: $(Format-ByteSize -Bytes $partition.Size)" -color "Info"
    Write-OutputColor "Type: $($partition.Type)" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "Type 'DELETE' (all caps) to confirm:" -color "Warning"
    $confirmation = (Read-Host).Trim()

    if ($confirmation -ne "DELETE") {
        Write-OutputColor "Operation cancelled." -color "Info"
        return
    }

    try {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Deleting partition..." -color "Info"

        Remove-Partition -DiskNumber $disk.Number -PartitionNumber $partition.PartitionNumber -Confirm:$false -ErrorAction Stop

        Write-OutputColor "Partition deleted successfully!" -color "Success"
        Add-SessionChange -Category "Storage" -Description "Deleted Partition $($partition.PartitionNumber) from Disk $($disk.Number)"
    }
    catch {
        Write-OutputColor "Failed to delete partition: $_" -color "Error"
    }
}

# Function to format a volume
function Format-DiskVolume {
    Clear-Host
    Write-CenteredOutput "Format Volume" -color "Info"

    Write-OutputColor "" -color "Info"
    Write-OutputColor "WARNING: Formatting will ERASE ALL DATA on the volume!" -color "Warning"
    Write-OutputColor "" -color "Info"

    $disk = Select-Disk -Prompt "Select a disk:" -OnlyInitialized

    if (-not $disk) {
        return
    }

    Show-DiskPartitions -DiskNumber $disk.Number

    $partition = Select-Partition -DiskNumber $disk.Number -Prompt "Select a partition to format:"

    if (-not $partition) {
        return
    }

    $driveLetter = if ($partition.DriveLetter) { "$($partition.DriveLetter):" } else { $null }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Selected: Partition $($partition.PartitionNumber) on Disk $($disk.Number)" -color "Info"
    if ($driveLetter) {
        Write-OutputColor "Drive Letter: $driveLetter" -color "Info"
    }
    Write-OutputColor "Size: $(Format-ByteSize -Bytes $partition.Size)" -color "Info"
    Write-OutputColor "" -color "Info"

    # Select file system
    Write-OutputColor "Select file system:" -color "Info"
    Write-OutputColor "  [1] NTFS (Recommended for Windows)" -color "Success"
    Write-OutputColor "  [2] ReFS (Resilient File System - for data volumes)" -color "Success"
    Write-OutputColor "  [3] exFAT (For USB drives/cross-platform)" -color "Success"
    Write-OutputColor "" -color "Info"

    $fsChoice = Read-Host "Enter choice (1-3)"

    $fileSystem = switch ($fsChoice) {
        "1" { "NTFS" }
        "2" { "ReFS" }
        "3" { "exFAT" }
        default {
            Write-OutputColor "Invalid choice. Defaulting to NTFS." -color "Warning"
            "NTFS"
        }
    }

    # Allocation unit size (only for NTFS and ReFS)
    $allocationUnitSize = $null
    if ($fileSystem -eq "NTFS" -or $fileSystem -eq "ReFS") {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Select allocation unit size:" -color "Info"
        Write-OutputColor "  [1] Default (Recommended - auto-selected based on volume size)" -color "Success"
        Write-OutputColor "  [2] 4 KB  (Best for small files)" -color "Success"
        Write-OutputColor "  [3] 8 KB" -color "Success"
        Write-OutputColor "  [4] 16 KB" -color "Success"
        Write-OutputColor "  [5] 32 KB" -color "Success"
        Write-OutputColor "  [6] 64 KB (Best for large files, databases, VHDs)" -color "Success"
        Write-OutputColor "" -color "Info"

        $ausChoice = Read-Host "Enter choice (1-6, default=1)"

        $allocationUnitSize = switch ($ausChoice) {
            "2" { 4096 }
            "3" { 8192 }
            "4" { 16384 }
            "5" { 32768 }
            "6" { 65536 }
            default { $null }  # Let Windows choose
        }
    }

    # Ask for volume label
    Write-OutputColor "" -color "Info"
    Write-OutputColor "Enter volume label (or press Enter for no label):" -color "Info"
    $volumeLabel = Read-Host "Label"
    if ([string]::IsNullOrWhiteSpace($volumeLabel)) {
        $volumeLabel = ""
    }

    # Quick format option
    Write-OutputColor "" -color "Info"
    $quickFormat = Confirm-UserAction -Message "Perform quick format? (Recommended)" -DefaultYes

    # Assign drive letter if not assigned
    $newDriveLetter = $null
    if (-not $driveLetter) {
        $newDriveLetter = Select-DriveLetterSmart
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Format Summary:" -color "Info"
    Write-OutputColor "  File System: $fileSystem" -color "Info"
    if ($allocationUnitSize) {
        Write-OutputColor "  Allocation Unit: $(Format-ByteSize -Bytes $allocationUnitSize)" -color "Info"
    }
    else {
        Write-OutputColor "  Allocation Unit: Default" -color "Info"
    }
    Write-OutputColor "  Label: $(if ($volumeLabel) { $volumeLabel } else { '(none)' })" -color "Info"
    Write-OutputColor "  Quick Format: $(if ($quickFormat) { 'Yes' } else { 'No (Full format - takes longer)' })" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "Type 'FORMAT' (all caps) to confirm:" -color "Warning"
    $confirmation = (Read-Host).Trim()

    if ($confirmation -ne "FORMAT") {
        Write-OutputColor "Operation cancelled." -color "Info"
        return
    }

    try {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Formatting volume..." -color "Info"

        # Assign drive letter first if needed
        if ($newDriveLetter) {
            Set-Partition -DiskNumber $disk.Number -PartitionNumber $partition.PartitionNumber -NewDriveLetter $newDriveLetter -ErrorAction SilentlyContinue
            # Verify drive letter was actually assigned
            $verifyPartition = Get-Partition -DiskNumber $disk.Number -PartitionNumber $partition.PartitionNumber
            if ($verifyPartition.DriveLetter -eq $newDriveLetter) {
                $driveLetter = "$newDriveLetter`:"
            }
            else {
                Write-OutputColor "  Warning: Drive letter $newDriveLetter could not be assigned (may be in use)." -color "Warning"
            }
        }

        # Get the partition again to get any updated drive letter
        $partition = Get-Partition -DiskNumber $disk.Number -PartitionNumber $partition.PartitionNumber

        # Format using partition
        $formatParams = @{
            Partition = $partition
            FileSystem = $fileSystem
            Confirm = $false
            ErrorAction = "Stop"
        }

        if ($volumeLabel) {
            $formatParams.NewFileSystemLabel = $volumeLabel
        }

        if ($allocationUnitSize) {
            $formatParams.AllocationUnitSize = $allocationUnitSize
        }

        if ($quickFormat) {
            $formatParams.Full = $false
        }
        else {
            $formatParams.Full = $true
        }

        Format-Volume @formatParams

        Write-OutputColor "" -color "Info"
        Write-OutputColor "Volume formatted successfully!" -color "Success"
        Write-OutputColor "File System: $fileSystem" -color "Info"
        if ($driveLetter) {
            Write-OutputColor "Drive Letter: $driveLetter" -color "Info"
        }

        Add-SessionChange -Category "Storage" -Description "Formatted Partition $($partition.PartitionNumber) on Disk $($disk.Number) as $fileSystem"
    }
    catch {
        Write-OutputColor "Failed to format volume: $_" -color "Error"
    }
}

# Function to extend a volume
function Expand-DiskVolume {
    Clear-Host
    Write-CenteredOutput "Extend Volume" -color "Info"

    Write-OutputColor "This extends a volume to use unallocated space on the disk." -color "Info"
    Write-OutputColor "" -color "Info"

    $disk = Select-Disk -Prompt "Select a disk:" -OnlyInitialized

    if (-not $disk) {
        return
    }

    Show-DiskPartitions -DiskNumber $disk.Number

    $partition = Select-Partition -DiskNumber $disk.Number -Prompt "Select a partition to extend:"

    if (-not $partition) {
        return
    }

    # Calculate available space (simplified - takes space after partition)
    $maxSize = $partition | Get-PartitionSupportedSize -ErrorAction SilentlyContinue

    if (-not $maxSize -or $maxSize.SizeMax -le $partition.Size) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "No additional space available to extend this partition." -color "Warning"
        Write-OutputColor "The unallocated space must be immediately after this partition." -color "Info"
        return
    }

    $availableExtend = $maxSize.SizeMax - $partition.Size

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Selected: Partition $($partition.PartitionNumber)" -color "Info"
    Write-OutputColor "Current Size: $(Format-ByteSize -Bytes $partition.Size)" -color "Info"
    Write-OutputColor "Maximum Size: $(Format-ByteSize -Bytes $maxSize.SizeMax)" -color "Info"
    Write-OutputColor "Available to Add: $(Format-ByteSize -Bytes $availableExtend)" -color "Success"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "Enter size to add:" -color "Info"
    Write-OutputColor "  - Examples: '50', '50GB', '1TB', '500MB', 'MAX'" -color "Info"
    Write-OutputColor "  - Plain number defaults to GB" -color "Info"
    Write-OutputColor "  - Enter 'MAX' to use all available space" -color "Info"
    Write-OutputColor "" -color "Info"

    $sizeInput = Read-Host "Size to add"

    $navResult = Test-NavigationCommand -UserInput $sizeInput
    if ($navResult.ShouldReturn) {
        return
    }

    $newSize = 0

    if ($sizeInput -match '^max$') {
        $newSize = $maxSize.SizeMax
    }
    elseif ($sizeInput -match '^(\d+(?:\.\d+)?)\s*(TB|GB|MB|T|G|M)?$') {
        $regexMatches = $matches
        $sizeNum = [double]$regexMatches[1]
        $sizeUnit = if ($regexMatches[2]) { $regexMatches[2].ToUpper() } else { "GB" }
        $addSize = switch ($sizeUnit) {
            { $_ -eq "TB" -or $_ -eq "T" } { [long]($sizeNum * 1TB) }
            { $_ -eq "GB" -or $_ -eq "G" } { [long]($sizeNum * 1GB) }
            { $_ -eq "MB" -or $_ -eq "M" } { [long]($sizeNum * 1MB) }
            default { [long]($sizeNum * 1GB) }
        }
        $newSize = $partition.Size + $addSize

        if ($newSize -gt $maxSize.SizeMax) {
            Write-OutputColor "Requested size ($(Format-ByteSize -Bytes $addSize)) exceeds available space." -color "Warning"
            Write-OutputColor "Maximum you can add: $(Format-ByteSize -Bytes $availableExtend)" -color "Info"
            return
        }
    }
    else {
        Write-OutputColor "Invalid size input. Examples: '50', '1TB', '500MB', 'MAX'" -color "Error"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "New partition size will be: $(Format-ByteSize -Bytes $newSize)" -color "Info"

    if (-not (Confirm-UserAction -Message "Extend partition?")) {
        Write-OutputColor "Operation cancelled." -color "Info"
        return
    }

    try {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Extending partition..." -color "Info"

        Resize-Partition -DiskNumber $disk.Number -PartitionNumber $partition.PartitionNumber -Size $newSize -ErrorAction Stop

        Write-OutputColor "Partition extended successfully!" -color "Success"
        Write-OutputColor "New Size: $(Format-ByteSize -Bytes $newSize)" -color "Info"

        Add-SessionChange -Category "Storage" -Description "Extended Partition $($partition.PartitionNumber) on Disk $($disk.Number) to $(Format-ByteSize -Bytes $newSize)"
    }
    catch {
        Write-OutputColor "Failed to extend partition: $_" -color "Error"
    }
}

# Function to shrink a volume
function Compress-DiskVolume {
    Clear-Host
    Write-CenteredOutput "Shrink Volume" -color "Info"

    Write-OutputColor "This shrinks a volume to create unallocated space." -color "Info"
    Write-OutputColor "" -color "Info"

    $disk = Select-Disk -Prompt "Select a disk:" -OnlyInitialized

    if (-not $disk) {
        return
    }

    Show-DiskPartitions -DiskNumber $disk.Number

    $partition = Select-Partition -DiskNumber $disk.Number -Prompt "Select a partition to shrink:"

    if (-not $partition) {
        return
    }

    # Get minimum size
    $sizeInfo = $partition | Get-PartitionSupportedSize -ErrorAction SilentlyContinue

    if (-not $sizeInfo) {
        Write-OutputColor "Unable to determine shrink limits for this partition." -color "Error"
        return
    }

    $currentSize = $partition.Size
    $minSize = $sizeInfo.SizeMin
    $maxShrink = $currentSize - $minSize

    if ($maxShrink -lt 1MB) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "This partition cannot be shrunk." -color "Warning"
        Write-OutputColor "There is not enough free space on the volume." -color "Info"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Selected: Partition $($partition.PartitionNumber)" -color "Info"
    Write-OutputColor "Current Size: $(Format-ByteSize -Bytes $currentSize)" -color "Info"
    Write-OutputColor "Minimum Size: $(Format-ByteSize -Bytes $minSize)" -color "Info"
    Write-OutputColor "Maximum Shrink: $(Format-ByteSize -Bytes $maxShrink)" -color "Success"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "Enter amount to shrink by:" -color "Info"
    Write-OutputColor "  Examples: '50', '50GB', '1TB', '500MB'" -color "Info"
    Write-OutputColor "  Plain number defaults to GB" -color "Info"
    Write-OutputColor "" -color "Info"

    $shrinkInput = Read-Host "Shrink by"

    $navResult = Test-NavigationCommand -UserInput $shrinkInput
    if ($navResult.ShouldReturn) {
        return
    }

    if ($shrinkInput -notmatch '^(\d+(?:\.\d+)?)\s*(TB|GB|MB|T|G|M)?$') {
        Write-OutputColor "Invalid input. Examples: '50', '1TB', '500MB'" -color "Error"
        return
    }

    $regexMatches = $matches
    $shrinkNum = [double]$regexMatches[1]
    $shrinkUnit = if ($regexMatches[2]) { $regexMatches[2].ToUpper() } else { "GB" }
    $shrinkAmount = switch ($shrinkUnit) {
        { $_ -eq "TB" -or $_ -eq "T" } { [long]($shrinkNum * 1TB) }
        { $_ -eq "GB" -or $_ -eq "G" } { [long]($shrinkNum * 1GB) }
        { $_ -eq "MB" -or $_ -eq "M" } { [long]($shrinkNum * 1MB) }
        default { [long]($shrinkNum * 1GB) }
    }

    if ($shrinkAmount -gt $maxShrink) {
        Write-OutputColor "Cannot shrink by that amount." -color "Warning"
        Write-OutputColor "Maximum shrink: $(Format-ByteSize -Bytes $maxShrink)" -color "Info"
        return
    }

    $newSize = $currentSize - $shrinkAmount

    Write-OutputColor "" -color "Info"
    Write-OutputColor "New partition size will be: $(Format-ByteSize -Bytes $newSize)" -color "Info"
    Write-OutputColor "This will free up: $(Format-ByteSize -Bytes $shrinkAmount) of space" -color "Info"

    if (-not (Confirm-UserAction -Message "Shrink partition?")) {
        Write-OutputColor "Operation cancelled." -color "Info"
        return
    }

    try {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Shrinking partition..." -color "Info"

        Resize-Partition -DiskNumber $disk.Number -PartitionNumber $partition.PartitionNumber -Size $newSize -ErrorAction Stop

        Write-OutputColor "Partition shrunk successfully!" -color "Success"
        Write-OutputColor "New Size: $(Format-ByteSize -Bytes $newSize)" -color "Info"
        Write-OutputColor "Freed Space: $(Format-ByteSize -Bytes $shrinkAmount)" -color "Info"

        Add-SessionChange -Category "Storage" -Description "Shrunk Partition $($partition.PartitionNumber) on Disk $($disk.Number) by $(Format-ByteSize -Bytes $shrinkAmount)"
    }
    catch {
        Write-OutputColor "Failed to shrink partition: $_" -color "Error"
    }
}

# Helper function to show drive letter map with color coding
# Returns hashtable of letter info: @{ Letter = @{ Status; Type; Label; DriveType } }
function Get-DriveLetterMap {
    $map = [ordered]@{}

    # Get all volumes (includes partitions and CD-ROMs)
    $volumes = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter }

    # Build map for C-Z (skip A/B - floppy reserved)
    foreach ($letter in [char[]]([char]'C'..[char]'Z')) {
        $letterStr = [string]$letter
        $vol = $volumes | Where-Object { $_.DriveLetter -eq $letterStr } | Select-Object -First 1

        if ($vol) {
            $driveType = $vol.DriveType
            $label = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { "" }
            $sizeStr = if ($vol.Size -gt 0) { Format-TransferSize -Bytes $vol.Size } else { "" }

            $map[$letterStr] = @{
                Status    = "InUse"
                DriveType = $driveType
                Label     = $label
                Size      = $sizeStr
                Volume    = $vol
            }
        } else {
            $map[$letterStr] = @{
                Status    = "Available"
                DriveType = $null
                Label     = ""
                Size      = ""
                Volume    = $null
            }
        }
    }

    return $map
}

# Helper function to display the drive letter map with color coding
function Show-DriveLetterMap {
    $map = Get-DriveLetterMap

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  DRIVE LETTER MAP".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    # Show in rows of 3
    $letters = @($map.Keys)
    for ($i = 0; $i -lt $letters.Count; $i += 3) {
        $lineParts = @()
        for ($j = $i; $j -lt [math]::Min($i + 3, $letters.Count); $j++) {
            $letter = $letters[$j]
            $info = $map[$letter]
            if ($info.Status -eq "Available") {
                $entry = "$($letter):  Available"
            } elseif ($info.DriveType -eq "CD-ROM") {
                $label = if ($info.Label) { $info.Label } else { "CD/DVD" }
                $entry = "$($letter):  $label"
            } else {
                $label = if ($info.Label) { $info.Label } else { $info.DriveType }
                $sizeInfo = if ($info.Size) { " ($($info.Size))" } else { "" }
                $entry = "$($letter):  $label$sizeInfo"
            }
            $lineParts += @{ Text = $entry.PadRight(22); Letter = $letter; Info = $info }
        }

        # Write each entry with appropriate color
        Write-Host "  │  " -NoNewline -ForegroundColor Cyan
        foreach ($part in $lineParts) {
            $color = if ($part.Info.Status -eq "Available") { "Green" }
                     elseif ($part.Info.DriveType -eq "CD-ROM") { "Yellow" }
                     else { "Red" }
            Write-Host $part.Text -NoNewline -ForegroundColor $color
        }
        # Pad remainder of line
        $totalLen = ($lineParts | ForEach-Object { $_.Text.Length } | Measure-Object -Sum).Sum
        $remaining = 70 - $totalLen
        if ($remaining -gt 0) { Write-Host (' ' * $remaining) -NoNewline }
        Write-Host "│" -ForegroundColor Cyan
    }

    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-Host "  │  " -NoNewline -ForegroundColor Cyan
    Write-Host "Green" -NoNewline -ForegroundColor Green
    Write-Host " = Available  " -NoNewline -ForegroundColor Cyan
    Write-Host "Red" -NoNewline -ForegroundColor Red
    Write-Host " = In Use  " -NoNewline -ForegroundColor Cyan
    Write-Host "Yellow" -NoNewline -ForegroundColor Yellow
    Write-Host " = CD/DVD (can be moved)" -NoNewline -ForegroundColor Cyan
    Write-Host "   │" -ForegroundColor Cyan
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    return $map
}

# Helper function to move a CD/DVD drive to a high unused letter (Z, Y, X...)
function Move-OpticalDriveLetter {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CurrentLetter
    )

    # Find a free letter starting from Z going down
    $map = Get-DriveLetterMap
    $newLetter = $null
    foreach ($letter in [char[]]('Z'..'C')) {
        $letterStr = [string]$letter
        if ($map[$letterStr].Status -eq "Available") {
            $newLetter = $letterStr
            break
        }
    }

    if (-not $newLetter) {
        Write-OutputColor "  No available drive letters to move CD/DVD to." -color "Error"
        return $false
    }

    Write-OutputColor "  Moving CD/DVD from $($CurrentLetter): to $($newLetter):..." -color "Info"

    try {
        # Use CIM to change CD-ROM drive letter
        $cimVol = Get-CimInstance -ClassName Win32_Volume -ErrorAction Stop | Where-Object {
            $_.DriveLetter -eq "$($CurrentLetter):"
        }

        if ($cimVol) {
            Set-CimInstance -InputObject $cimVol -Property @{ DriveLetter = "$($newLetter):" } -ErrorAction Stop
            Write-OutputColor "  CD/DVD drive moved from $($CurrentLetter): to $($newLetter):" -color "Success"
            return $true
        } else {
            Write-OutputColor "  Could not find CD/DVD volume to move." -color "Error"
            return $false
        }
    }
    catch {
        Write-OutputColor "  Failed to move CD/DVD drive: $_" -color "Error"
        return $false
    }
}

# Smart drive letter picker - shows map, handles CD/DVD relocation
# Returns the chosen letter or $null if cancelled
function Select-DriveLetterSmart {
    param(
        [string]$CurrentLetter = ""  # If changing existing letter
    )

    $map = Show-DriveLetterMap
    Write-OutputColor "" -color "Info"

    if ($CurrentLetter) {
        Write-OutputColor "  Current drive letter: $CurrentLetter" -color "Info"
    }
    Write-OutputColor "  Enter a drive letter (C-Z), or press Enter to skip:" -color "Info"
    Write-OutputColor "" -color "Info"

    $userResponse = Read-Host "  Drive letter"

    $navResult = Test-NavigationCommand -UserInput $userResponse
    if ($navResult.ShouldReturn) { return $null }

    if ([string]::IsNullOrWhiteSpace($userResponse)) { return $null }

    if ($userResponse -notmatch '^[A-Za-z]$') {
        Write-OutputColor "  Invalid input. Enter a single letter." -color "Error"
        return $null
    }

    $chosenLetter = "$userResponse".ToUpper()

    # Block A and B (floppy reserved)
    if ($chosenLetter -eq 'A' -or $chosenLetter -eq 'B') {
        Write-OutputColor "  Letters A and B are reserved for floppy drives." -color "Warning"
        return $null
    }

    # Check if the letter is the current letter
    if ($CurrentLetter -and $chosenLetter -eq $CurrentLetter) {
        Write-OutputColor "  That's already the current drive letter." -color "Warning"
        return $null
    }

    $info = $map[$chosenLetter]

    if ($info.Status -eq "Available") {
        return $chosenLetter
    }

    # Letter is in use - check if it's a CD/DVD that can be moved
    if ($info.DriveType -eq "CD-ROM") {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  $($chosenLetter): is used by a CD/DVD drive." -color "Warning"
        if (Confirm-UserAction -Message "Move CD/DVD to another letter and use $($chosenLetter): for this volume?") {
            if (Move-OpticalDriveLetter -CurrentLetter $chosenLetter) {
                return $chosenLetter
            } else {
                return $null
            }
        }
        return $null
    }

    # In use by a regular volume - can't use it
    Write-OutputColor "  Drive letter $chosenLetter is in use by: $($info.Label) ($($info.Size))" -color "Error"
    return $null
}

# Function to change drive letter
function Set-VolumeDriveLetter {
    Clear-Host
    Write-CenteredOutput "Change Drive Letter" -color "Info"

    Write-OutputColor "This changes or assigns a drive letter to any volume (including CD/DVD)." -color "Info"
    Write-OutputColor "" -color "Info"

    # Show all volumes with drive letters (including CD/DVD)
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT A VOLUME".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $allVolumes = @()

    # Get disk partitions with drive letters
    $partitions = Get-Partition -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -or $_.Size -gt 0 }
    foreach ($part in $partitions) {
        $letter = if ($part.DriveLetter) { "$($part.DriveLetter):" } else { "No Letter" }
        $disk = Get-Disk -Number $part.DiskNumber -ErrorAction SilentlyContinue
        $diskName = if ($disk) { $disk.FriendlyName } else { "Unknown" }
        $allVolumes += @{
            Type       = "Partition"
            Letter     = $part.DriveLetter
            Display    = "  Disk $($part.DiskNumber) Part $($part.PartitionNumber) ($letter) - $(Format-ByteSize -Bytes $part.Size) [$diskName]"
            DiskNumber = $part.DiskNumber
            PartNumber = $part.PartitionNumber
            Partition  = $part
        }
    }

    # Get CD/DVD drives
    $cdroms = Get-CimInstance -ClassName Win32_CDROMDrive -ErrorAction SilentlyContinue
    foreach ($cd in $cdroms) {
        $cdLetter = if ($cd.Drive) { $cd.Drive.TrimEnd(':') } else { $null }
        $allVolumes += @{
            Type       = "CDROM"
            Letter     = $cdLetter
            Display    = "  CD/DVD: $($cd.Name) ($($cd.Drive))"
            WmiDrive   = $cd.Drive
        }
    }

    if ($allVolumes.Count -eq 0) {
        Write-OutputColor "  │$("  No volumes found.".PadRight(72))│" -color "Warning"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        return
    }

    $idx = 1
    foreach ($vol in $allVolumes) {
        if ($vol.Type -eq "CDROM") {
            Write-MenuItem -Text "  [$idx] $($vol.Display)"
        } else {
            Write-OutputColor "  │$("  [$idx] $($vol.Display)".PadRight(72))│" -color "Info"
        }
        $idx++
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $selection = Read-Host "  Select volume"
    $navResult = Test-NavigationCommand -UserInput $selection
    if ($navResult.ShouldReturn) { return }

    if ($selection -notmatch '^\d+$' -or [int]$selection -lt 1 -or [int]$selection -gt $allVolumes.Count) {
        Write-OutputColor "  Invalid selection." -color "Error"
        return
    }

    $selected = $allVolumes[[int]$selection - 1]
    $currentLetter = if ($selected.Letter) { [string]$selected.Letter } else { "" }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Selected: $($selected.Display)" -color "Info"
    Write-OutputColor "" -color "Info"

    # Show drive letter map and options
    if ($currentLetter) {
        Write-OutputColor "  Type 'REMOVE' to remove the current letter, or select a new one:" -color "Info"
        Write-OutputColor "" -color "Info"
    }

    $map = Show-DriveLetterMap
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enter a drive letter (C-Z), 'REMOVE', or press Enter to cancel:" -color "Info"
    Write-OutputColor "" -color "Info"

    $userResponse = Read-Host "  Drive letter"
    $navResult = Test-NavigationCommand -UserInput $userResponse
    if ($navResult.ShouldReturn) { return }

    if ([string]::IsNullOrWhiteSpace($userResponse)) { return }

    # Handle REMOVE
    if ($userResponse -match '^remove$') {
        if (-not $currentLetter) {
            Write-OutputColor "  This volume doesn't have a drive letter to remove." -color "Warning"
            return
        }
        if (-not (Confirm-UserAction -Message "Remove drive letter $($currentLetter):?")) {
            return
        }
        try {
            if ($selected.Type -eq "CDROM") {
                $cimVol = Get-CimInstance -ClassName Win32_Volume -ErrorAction Stop | Where-Object { $_.DriveLetter -eq "$($currentLetter):" }
                if ($cimVol) {
                    Set-CimInstance -InputObject $cimVol -Property @{ DriveLetter = $null } -ErrorAction Stop
                    Write-OutputColor "  CD/DVD drive letter removed." -color "Success"
                    Add-SessionChange -Category "Storage" -Description "Removed CD/DVD drive letter $($currentLetter):"
                }
            } else {
                Remove-PartitionAccessPath -DiskNumber $selected.DiskNumber -PartitionNumber $selected.PartNumber -AccessPath "$($currentLetter):\" -ErrorAction Stop
                Write-OutputColor "  Drive letter removed." -color "Success"
                Add-SessionChange -Category "Storage" -Description "Removed drive letter $($currentLetter):"
            }
        }
        catch {
            Write-OutputColor "  Failed to remove drive letter: $_" -color "Error"
        }
        return
    }

    # Validate letter input
    if ($userResponse -notmatch '^[A-Za-z]$') {
        Write-OutputColor "  Invalid input." -color "Error"
        return
    }

    $newLetter = "$userResponse".ToUpper()

    if ($newLetter -eq 'A' -or $newLetter -eq 'B') {
        Write-OutputColor "  Letters A and B are reserved for floppy drives." -color "Warning"
        return
    }

    if ($currentLetter -and $newLetter -eq $currentLetter) {
        Write-OutputColor "  That's already the current drive letter." -color "Warning"
        return
    }

    $info = $map[$newLetter]
    if ($info.Status -eq "InUse") {
        if ($info.DriveType -eq "CD-ROM") {
            Write-OutputColor "  $($newLetter): is used by a CD/DVD drive." -color "Warning"
            if (Confirm-UserAction -Message "Move CD/DVD to another letter and use $($newLetter):?") {
                if (-not (Move-OpticalDriveLetter -CurrentLetter $newLetter)) {
                    return
                }
            } else {
                return
            }
        } else {
            Write-OutputColor "  Drive letter $newLetter is in use by: $($info.Label) ($($info.Size))" -color "Error"
            return
        }
    }

    if (-not (Confirm-UserAction -Message "Change drive letter to $($newLetter):?")) {
        Write-OutputColor "  Operation cancelled." -color "Info"
        return
    }

    try {
        if ($selected.Type -eq "CDROM") {
            # CD/DVD drive - use CIM
            $cimVol = Get-CimInstance -ClassName Win32_Volume -ErrorAction Stop | Where-Object {
                $_.DriveLetter -eq "$($currentLetter):"
            }
            if ($cimVol) {
                Set-CimInstance -InputObject $cimVol -Property @{ DriveLetter = "$($newLetter):" } -ErrorAction Stop
                Write-OutputColor "  CD/DVD drive letter changed to $($newLetter): successfully!" -color "Success"
                Add-SessionChange -Category "Storage" -Description "Changed CD/DVD drive letter from $($currentLetter): to $($newLetter):"
            } else {
                Write-OutputColor "  Could not find CD/DVD volume." -color "Error"
            }
        } else {
            # Disk partition
            $part = $selected.Partition
            if ($part.DriveLetter) {
                Remove-PartitionAccessPath -DiskNumber $selected.DiskNumber -PartitionNumber $selected.PartNumber -AccessPath "$($part.DriveLetter):\" -ErrorAction SilentlyContinue
            }
            Set-Partition -DiskNumber $selected.DiskNumber -PartitionNumber $selected.PartNumber -NewDriveLetter $newLetter -ErrorAction Stop
            Write-OutputColor "  Drive letter changed to $($newLetter): successfully!" -color "Success"
            Add-SessionChange -Category "Storage" -Description "Changed drive letter to $($newLetter): on Disk $($selected.DiskNumber) Partition $($selected.PartNumber)"
        }
    }
    catch {
        Write-OutputColor "  Failed to change drive letter: $_" -color "Error"
    }
}

# Function to change volume label
function Set-VolumeLabel {
    Clear-Host
    Write-CenteredOutput "Change Volume Label" -color "Info"

    Write-OutputColor "This changes the label (name) of a volume." -color "Info"
    Write-OutputColor "" -color "Info"

    # Show volumes with drive letters
    $volumes = @(Get-Volume | Where-Object { $_.DriveLetter } | Sort-Object DriveLetter)

    if ($volumes.Count -eq 0) {
        Write-OutputColor "No volumes with drive letters found." -color "Warning"
        return
    }

    Write-OutputColor "Available volumes:" -color "Info"
    Write-OutputColor "" -color "Info"

    foreach ($vol in $volumes) {
        $label = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { "(No Label)" }
        Write-OutputColor "  [$($vol.DriveLetter)] $label - $(Format-ByteSize -Bytes $vol.Size) ($($vol.FileSystem))" -color "Success"
    }

    Write-OutputColor "" -color "Info"
    $letterInput = Read-Host "Enter drive letter of volume to rename"

    $navResult = Test-NavigationCommand -UserInput $letterInput
    if ($navResult.ShouldReturn) {
        return
    }

    if ($letterInput -notmatch '^[A-Za-z]$') {
        Write-OutputColor "Invalid drive letter." -color "Error"
        return
    }

    $driveLetter = "$letterInput".ToUpper()
    $volume = Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue

    if (-not $volume) {
        Write-OutputColor "Volume not found." -color "Error"
        return
    }

    $currentLabel = if ($volume.FileSystemLabel) { $volume.FileSystemLabel } else { "(No Label)" }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Selected: $driveLetter`:" -color "Info"
    Write-OutputColor "Current Label: $currentLabel" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "Enter new label (or press Enter to clear label):" -color "Info"
    $newLabel = (Read-Host "New label").Trim()

    $navResult = Test-NavigationCommand -UserInput $newLabel
    if ($navResult.ShouldReturn) { return }

    try {
        Set-Volume -DriveLetter $driveLetter -NewFileSystemLabel $newLabel -ErrorAction Stop

        if ($newLabel) {
            Write-OutputColor "Volume label changed to '$newLabel' successfully!" -color "Success"
        }
        else {
            Write-OutputColor "Volume label cleared successfully!" -color "Success"
        }

        Add-SessionChange -Category "Storage" -Description "Changed label of $driveLetter`: to '$newLabel'"
    }
    catch {
        Write-OutputColor "Failed to change volume label: $_" -color "Error"
    }
}

# Function to show Storage Manager menu
function Show-StorageManagerMenu {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                        STORAGE MANAGER").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  VIEW".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[1]  View All Disks"
    Write-MenuItem "[2]  View All Volumes"
    Write-MenuItem "[3]  View Disk Partitions"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  DISK OPERATIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[4]  Set Disk Online/Offline"
    Write-MenuItem "[5]  Initialize Disk"
    Write-Host "  │  " -NoNewline -ForegroundColor Cyan; Write-Host "[6]  Clear Disk (Remove All Data)".PadRight(54) -NoNewline -ForegroundColor Yellow; Write-Host "⚠ DESTRUCTIVE".PadRight(16) -NoNewline -ForegroundColor Red; Write-Host "│" -ForegroundColor Cyan
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  PARTITION & VOLUME OPERATIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[7]  Create Partition"
    Write-Host "  │  " -NoNewline -ForegroundColor Cyan; Write-Host "[8]  Delete Partition".PadRight(54) -NoNewline -ForegroundColor Yellow; Write-Host "⚠ DESTRUCTIVE".PadRight(16) -NoNewline -ForegroundColor Red; Write-Host "│" -ForegroundColor Cyan
    Write-Host "  │  " -NoNewline -ForegroundColor Cyan; Write-Host "[9]  Format Volume".PadRight(54) -NoNewline -ForegroundColor Yellow; Write-Host "⚠ DESTRUCTIVE".PadRight(16) -NoNewline -ForegroundColor Red; Write-Host "│" -ForegroundColor Cyan
    Write-MenuItem "[10] Extend Volume"
    Write-MenuItem "[11] Shrink Volume"
    Write-MenuItem "[12] Change Drive Letter"
    Write-MenuItem "[13] Change Volume Label"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  [B] ◄ Back to Storage & Clustering" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to run Storage Manager
function Start-StorageManager {
    while ($true) {
        if ($global:ReturnToMainMenu) { return }
        $choice = Show-StorageManagerMenu

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) {
            return
        }

        switch ($choice) {
            "1" {
                Show-AllDisks
                Write-PressEnter
            }
            "2" {
                Show-AllVolumes
                Write-PressEnter
            }
            "3" {
                Write-OutputColor "" -color "Info"
                $diskNum = Read-Host "Enter disk number to view partitions"
                $navResult = Test-NavigationCommand -UserInput $diskNum
                if ($navResult.ShouldReturn) { continue }
                if ($diskNum -match '^\d+$') {
                    Show-DiskPartitions -DiskNumber ([int]$diskNum)
                }
                else {
                    Write-OutputColor "Invalid disk number." -color "Error"
                }
                Write-PressEnter
            }
            "4" {
                Set-DiskOnlineStatus
                Write-PressEnter
            }
            "5" {
                Initialize-NewDisk
                Write-PressEnter
            }
            "6" {
                Clear-DiskData
                Write-PressEnter
            }
            "7" {
                New-DiskPartition
                Write-PressEnter
            }
            "8" {
                Remove-DiskPartition
                Write-PressEnter
            }
            "9" {
                Format-DiskVolume
                Write-PressEnter
            }
            "10" {
                Expand-DiskVolume
                Write-PressEnter
            }
            "11" {
                Compress-DiskVolume
                Write-PressEnter
            }
            "12" {
                Set-VolumeDriveLetter
                Write-PressEnter
            }
            "13" {
                Set-VolumeLabel
                Write-PressEnter
            }
            "B" {
                return
            }
            "back" {
                return
            }
            default {
                Write-OutputColor "Invalid choice. Please enter 1-13 or B to go back." -color "Error"
                Start-Sleep -Seconds 2
            }
        }
    }
}
#endregion