#region ===== VM EXPORT/IMPORT (v2.8.0) =====
# Function to export VM with progress tracking
function Export-VMWizard {
    param(
        [string]$ComputerName = $null,
        [System.Management.Automation.PSCredential]$Credential = $null
    )

    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                          EXPORT VM").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Get list of VMs
    $vmParams = @{}
    if ($ComputerName) { $vmParams['ComputerName'] = $ComputerName }
    if ($Credential) { $vmParams['Credential'] = $Credential }

    try {
        $vms = @(Get-VM @vmParams -ErrorAction Stop | Sort-Object Name)
    }
    catch {
        Write-OutputColor "  Error getting VMs: $_" -color "Error"
        return
    }

    if ($vms.Count -eq 0) {
        Write-OutputColor "  No VMs available for export." -color "Error"
        return
    }

    # Display VMs
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT VM TO EXPORT".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $vmIndex = 1
    $vmMap = @{}
    foreach ($vm in $vms) {
        $stateColor = if ($vm.State -eq 'Running') { "Success" } elseif ($vm.State -eq 'Off') { "Warning" } else { "Info" }
        # Get-VHD accepts -ComputerName but NOT -Credential — splatting $vmParams as-is
        # (which carries Credential) caused a silent parameter-binding failure on every
        # iteration when a remote credential was set, so size always rendered as "N/A".
        # Build a Get-VHD-safe splat that only includes ComputerName.
        $vhdParams = @{}
        if ($vmParams.ContainsKey('ComputerName')) { $vhdParams['ComputerName'] = $vmParams['ComputerName'] }
        $vhdSizes = ($vm.HardDrives | ForEach-Object { (Get-VHD $_.Path @vhdParams -ErrorAction SilentlyContinue).FileSize } | Measure-Object -Sum)
        $sizeStr = if ($null -ne $vhdSizes.Sum -and $vhdSizes.Sum -gt 0) { "{0:N0}GB" -f ($vhdSizes.Sum / 1GB) } else { "N/A" }
        $vmDisplay = "[$vmIndex]  $($vm.Name.PadRight(35)) $($vm.State.ToString().PadRight(10)) $sizeStr"
        Write-OutputColor "  │  $($vmDisplay.PadRight(70))│" -color $stateColor
        $vmMap["$vmIndex"] = $vm
        $vmIndex++
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $vmChoice = Read-Host "  Enter VM number"
    $navResult = Test-NavigationCommand -UserInput $vmChoice
    if ($navResult.ShouldReturn) { return }

    if (-not $vmMap.ContainsKey($vmChoice)) {
        Write-OutputColor "  Invalid selection. Enter 1-$($vms.Count) or B." -color "Error"
        return
    }

    $selectedVM = $vmMap[$vmChoice]

    # Get export path
    $defaultPath = if ($script:HostVMStoragePath) { Join-Path $script:HostVMStoragePath "Exports" } else { Join-Path $script:TempPath "VMExports" }
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Export destination (Enter for default: $defaultPath):" -color "Info"
    $exportPath = Read-Host "  "
    $navResult = Test-NavigationCommand -UserInput $exportPath
    if ($navResult.ShouldReturn) { return }
    if (-not [string]::IsNullOrWhiteSpace($exportPath)) { $exportPath = $exportPath.Trim('"') }
    if ([string]::IsNullOrWhiteSpace($exportPath)) { $exportPath = $defaultPath }

    # Ensure export directory exists
    if (-not (Test-Path -LiteralPath $exportPath)) {
        Write-OutputColor "  Creating export directory: $exportPath" -color "Info"
        try {
            $null = New-Item -LiteralPath $exportPath -ItemType Directory -Force -ErrorAction Stop
        }
        catch {
            Write-OutputColor "  Failed to create export directory: $_" -color "Error"
            return
        }
    }

    # Disk space pre-check on export destination (skip for UNC paths)
    try {
        if ($exportPath -match '^[A-Za-z]:') {
            $exportDriveLetter = $exportPath.Substring(0, 1)
            $exportVolume = Get-Volume -DriveLetter $exportDriveLetter -ErrorAction SilentlyContinue
            if ($null -ne $exportVolume) {
                $freeGB = [math]::Round($exportVolume.SizeRemaining / 1GB, 1)
                # Estimate needed: sum of VHD file sizes
                $vhdSizes = @($selectedVM.HardDrives | ForEach-Object { (Get-VHD $_.Path @vmParams -ErrorAction SilentlyContinue).FileSize })
                $neededGB = if ($null -ne ($vhdSizes | Measure-Object -Sum).Sum) { [math]::Round(($vhdSizes | Measure-Object -Sum).Sum / 1GB, 1) } else { 0 }
                if ($neededGB -gt 0 -and $freeGB -lt ($neededGB * 1.2)) {
                    Write-OutputColor "" -color "Info"
                    Write-OutputColor "  WARNING: Low disk space on ${exportDriveLetter}: drive!" -color "Warning"
                    Write-OutputColor "  Free: ${freeGB} GB | Estimated need: ~${neededGB} GB" -color "Warning"
                }
            }
        }
    } catch {
        Write-OutputColor "  Could not verify disk space: $_" -color "Warning"
    }

    # Warning if VM is running
    if ($selectedVM.State -eq 'Running') {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Note: Exporting a running VM will create a live export." -color "Warning"
        Write-OutputColor "  For best results, consider shutting down the VM first." -color "Warning"
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  VM: $($selectedVM.Name)" -color "Info"
    Write-OutputColor "  Destination: $exportPath" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Start export?")) { return }

    # Estimate export size from VHD file sizes
    $vmSize = 0
    $vhdDrives = @(Get-VMHardDiskDrive -VMName $selectedVM.Name -ErrorAction SilentlyContinue)
    foreach ($vhdDrive in $vhdDrives) {
        if ($null -ne $vhdDrive.Path -and (Test-Path -LiteralPath $vhdDrive.Path)) {
            $vmSize += (Get-Item -LiteralPath $vhdDrive.Path).Length
        }
    }
    $estimateGB = [math]::Round($vmSize / 1GB, 1)
    if ($estimateGB -gt 0) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Estimated export size: ${estimateGB} GB" -color "Info"
    }

    # Pre-check: refuse to clobber an existing export. Hyper-V's Export-VM behavior on a
    # collision is version-dependent — Server 2019+ throws "already exists" but some 2016/2022
    # configurations silently merge over the existing Virtual Hard Disks folder, producing a
    # Frankenstein export of mixed-timestamp VHDs. Past pattern: operator re-exports after a
    # config change; second attempt corrupts the first.
    #
    # CRITICAL: refuse if the VM name contains path-separator characters. Hyper-V allows
    # backslash / forward-slash / `..\` in the VM .Name property — a maliciously-imported
    # VM named `..\..\System32` would cause `Join-Path $exportPath $name` to resolve outside
    # the export root, and the Remove-Item -Recurse -Force below would then nuke whatever
    # lives at that resolved path. Validate before composing the path.
    if ($selectedVM.Name -match '[\\/]' -or $selectedVM.Name -match '\.\.' -or $selectedVM.Name -match '[\x00-\x1f]') {
        Write-OutputColor "" -color "Error"
        Write-OutputColor "  REFUSING: VM name contains path-separator or unsafe characters: '$($selectedVM.Name)'" -color "Error"
        Write-OutputColor "  This is a path-traversal guard. Rename the VM before exporting." -color "Warning"
        return
    }
    $targetFolder = Join-Path $exportPath $selectedVM.Name
    # Defense-in-depth: verify the resolved targetFolder is actually under $exportPath.
    try {
        $exportRootResolved = (Resolve-Path -LiteralPath $exportPath -ErrorAction Stop).Path.TrimEnd('\') + '\'
        $combinedFull = [System.IO.Path]::GetFullPath($targetFolder)
        if (-not $combinedFull.StartsWith($exportRootResolved, [StringComparison]::OrdinalIgnoreCase)) {
            Write-OutputColor "  REFUSING: target folder '$combinedFull' escapes export root '$exportRootResolved'." -color "Error"
            return
        }
    } catch { }
    if (Test-Path -LiteralPath $targetFolder) {
        Write-OutputColor "" -color "Warning"
        Write-OutputColor "  Export folder already exists: $targetFolder" -color "Warning"
        try {
            $existingSize = (Get-ChildItem -LiteralPath $targetFolder -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $existingGB = [math]::Round($existingSize / 1GB, 2)
            Write-OutputColor "  Existing size: ${existingGB} GB" -color "Info"
        } catch { }
        Write-OutputColor "  Re-exporting would mix new VHDs with the existing export contents." -color "Warning"
        if (-not (Confirm-UserAction -Message "Delete existing export folder and re-export?")) {
            Write-OutputColor "  Cancelled. Move/rename the existing folder and retry." -color "Info"
            return
        }
        try {
            Remove-Item -LiteralPath $targetFolder -Recurse -Force -ErrorAction Stop
        } catch {
            Write-OutputColor "  Failed to remove existing folder: $($_.Exception.Message)" -color "Error"
            return
        }
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Starting export (this may take a while; press ESC to cancel)..." -color "Info"

    try {
        # Use a job for background progress
        $exportJob = Start-Job -ScriptBlock {
            param($VMName, $Path, $Computer, [System.Management.Automation.PSCredential]$RemoteCred)
            $params = @{ Name = $VMName; Path = $Path }
            if ($Computer) { $params['ComputerName'] = $Computer }
            if ($RemoteCred) { $params['Credential'] = $RemoteCred }
            Export-VM @params -ErrorAction Stop
        } -ArgumentList $selectedVM.Name, $exportPath, $ComputerName, $Credential

        # Wait with progress indication - track export folder size
        $spinChars = @('|', '/', '-', '\')
        $spinIndex = 0
        $exportElapsed = 0
        $lastExportSize = 0
        $lastExportSpeedCheck = 0
        $exportSpeedBps = 0
        $exportFolder = Join-Path $exportPath $selectedVM.Name

        $maxElapsedSeconds = 4 * 3600  # 4-hour hard cap; warn-and-confirm before resetting
        $maxElapsedConfirmed = $false
        $cancelRequested = $false
        while ($exportJob.State -eq 'Running') {
            # Operator cancel via ESC. Stop-Job alone doesn't abort the underlying vmms.exe export
            # operation — Hyper-V keeps writing files in the host's vmms process even after the
            # PowerShell job is killed. We can't fully abort the WMI export without WMI tear-down,
            # but at least surface to the operator that the job will keep running in the background
            # and offer a tear-down path. The Confirm-UserAction below uses the same convention.
            try {
                if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and [Console]::KeyAvailable) {
                    $k = [Console]::ReadKey($true)
                    if ($k.Key -eq [ConsoleKey]::Escape) {
                        Write-Host ""
                        Write-OutputColor "  ESC pressed. NOTE: Hyper-V will continue exporting in the background until done." -color "Warning"
                        Write-OutputColor "  To fully cancel, you must restart vmms.exe (will disrupt all VMs) or wait it out." -color "Warning"
                        if (Confirm-UserAction -Message "Stop watching this export? (Hyper-V vmms keeps running)") {
                            $cancelRequested = $true
                            break
                        }
                    }
                }
            } catch { }
            # 4-hour cap with one-time confirm to extend
            if ($exportElapsed -gt $maxElapsedSeconds -and -not $maxElapsedConfirmed) {
                Write-Host ""
                Write-OutputColor "  Export has been running for over 4 hours." -color "Warning"
                if (-not (Confirm-UserAction -Message "Continue watching (Hyper-V keeps running regardless)?")) {
                    $cancelRequested = $true
                    break
                }
                $maxElapsedConfirmed = $true
            }

            $currentSize = 0
            if (Test-Path -LiteralPath $exportFolder) {
                try {
                    $measured = Get-ChildItem -LiteralPath $exportFolder -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
                    if ($null -ne $measured.Sum) { $currentSize = $measured.Sum }
                } catch { $currentSize = 0 }
            }

            if ($exportElapsed -gt 0 -and ($exportElapsed - $lastExportSpeedCheck) -ge 3) {
                $bytesInInterval = $currentSize - $lastExportSize
                $intervalSecs = $exportElapsed - $lastExportSpeedCheck
                if ($intervalSecs -gt 0 -and $bytesInInterval -ge 0) {
                    $exportSpeedBps = $bytesInInterval / $intervalSecs
                }
                $lastExportSize = $currentSize
                $lastExportSpeedCheck = $exportElapsed
            }

            $spin = $spinChars[$spinIndex % 4]
            $spinIndex++
            $progressParams = @{
                CurrentBytes     = $currentSize
                Activity         = "Exporting"
                SpeedBytesPerSec = $exportSpeedBps
                ElapsedSeconds   = $exportElapsed
                SpinChar         = $spin
            }
            if ($vmSize -gt 0) { $progressParams['TotalBytes'] = $vmSize }
            Write-ProgressBar @progressParams
            Start-Sleep -Seconds 1
            $exportElapsed++
        }
        Write-Host ""

        $null = Receive-Job -Job $exportJob -ErrorAction Stop
        Remove-Job -Job $exportJob

        # Get final export size for completion summary
        $finalExportSize = 0
        if (Test-Path -LiteralPath $exportFolder) {
            try {
                $measured = Get-ChildItem -LiteralPath $exportFolder -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
                if ($null -ne $measured.Sum) { $finalExportSize = $measured.Sum }
            } catch { $finalExportSize = 0 }
        }
        Write-TransferComplete -TotalBytes $finalExportSize -ElapsedSeconds $exportElapsed -Activity "Export"
        $totalMinutes = [math]::Round($exportElapsed / 60, 1)
        $finalGB = [math]::Round($finalExportSize / 1GB, 1)
        Write-OutputColor "  Completed in ${totalMinutes} min | Final size: ${finalGB} GB" -color "Success"
        Write-OutputColor "  Location: $exportPath\$($selectedVM.Name)" -color "Info"
        Add-SessionChange -Category "VM" -Description "Exported VM '$($selectedVM.Name)' to $exportPath (${finalGB} GB, ${totalMinutes} min)"
        Clear-MenuCache
    }
    catch {
        Write-RackStackError -Code "RS-5006" -Detail "$_"
        Write-OutputColor "  Error exporting VM: $_" -color "Error"
    }
    finally {
        if ($exportJob) {
            Stop-Job -Job $exportJob -ErrorAction SilentlyContinue
            Remove-Job -Job $exportJob -Force -ErrorAction SilentlyContinue
        }
    }
}

# Function to import VM
function Import-VMWizard {
    param(
        [string]$ComputerName = $null,
        [System.Management.Automation.PSCredential]$Credential = $null
    )

    # Note: ComputerName/Credential reserved for future remote import support
    $null = $ComputerName
    $null = $Credential

    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                          IMPORT VM").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Enter path to VM export folder or .vmcx file:" -color "Info"
    Write-OutputColor "  (Drag and drop, or type full path)" -color "Info"
    $importPath = Read-Host "  "
    $navResult = Test-NavigationCommand -UserInput $importPath
    if ($navResult.ShouldReturn) { return }

    $importPath = $importPath.Trim('"')
    if ([string]::IsNullOrWhiteSpace($importPath)) {
        Write-OutputColor "  No path entered." -color "Error"
        return
    }

    if (-not (Test-Path -LiteralPath $importPath)) {
        Write-OutputColor "  Path not found: $importPath" -color "Error"
        return
    }

    # Find .vmcx file
    $vmcxPath = $null
    if ($importPath -match '\.vmcx$') {
        $vmcxPath = $importPath
    }
    else {
        $vmcxFiles = @(Get-ChildItem -LiteralPath $importPath -Filter "*.vmcx" -Recurse -ErrorAction SilentlyContinue)
        if ($vmcxFiles.Count -eq 1) {
            $vmcxPath = $vmcxFiles[0].FullName
        }
        elseif ($vmcxFiles.Count -gt 1) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Multiple .vmcx files found. Select one:" -color "Info"
            $index = 1
            $vmcxMap = @{}
            foreach ($f in $vmcxFiles) {
                Write-OutputColor "    [$index] $($f.FullName)" -color "Info"
                $vmcxMap["$index"] = $f.FullName
                $index++
            }
            $vchoice = Read-Host "  Select"
            $navResult = Test-NavigationCommand -UserInput $vchoice
            if ($navResult.ShouldReturn) { return }
            if ($vmcxMap.ContainsKey($vchoice)) {
                $vmcxPath = $vmcxMap[$vchoice]
            }
        }
    }

    if (-not $vmcxPath) {
        Write-OutputColor "  No .vmcx file found in the specified path." -color "Error"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Found VM configuration: $vmcxPath" -color "Success"
    Write-OutputColor "" -color "Info"

    # Import mode
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  IMPORT MODE".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  [1]  Copy - Create new VM with new unique ID (recommended)".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [2]  Register - Use existing files in place".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    $modeChoice = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $modeChoice
    if ($navResult.ShouldReturn) { return }
    $copyMode = $modeChoice -ne "2"

    if ($copyMode) {
        # Get destination for copy
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Destination for VM files (Enter for default: $script:HostVMStoragePath):" -color "Info"
        $destPath = Read-Host "  "
        $navResult = Test-NavigationCommand -UserInput $destPath
        if ($navResult.ShouldReturn) { return }
        if (-not [string]::IsNullOrWhiteSpace($destPath)) { $destPath = $destPath.Trim('"') }
        if ([string]::IsNullOrWhiteSpace($destPath)) { $destPath = $script:HostVMStoragePath }

        # Hard validation — without these, Import-VM defaults VHD destination to
        # %ProgramData%\Microsoft\Windows\Hyper-V on some builds and unspools multi-TB VHDs
        # onto the system drive, filling C: until Windows hard-stops.
        if ([string]::IsNullOrWhiteSpace($destPath)) {
            Write-OutputColor "" -color "Error"
            Write-OutputColor "  Destination path is empty and no default configured." -color "Error"
            Write-OutputColor "  Configure $script:ToolFullName 'Host Storage Setup' first, or type a destination." -color "Info"
            return
        }
        if (-not (Test-Path -LiteralPath $destPath)) {
            try {
                $null = New-Item -LiteralPath $destPath -ItemType Directory -Force -ErrorAction Stop
                Write-OutputColor "  Created destination: $destPath" -color "Info"
            } catch {
                Write-OutputColor "  Cannot create destination '$destPath': $($_.Exception.Message)" -color "Error"
                return
            }
        }
        # Free-space check (parity with export-side check). Skip for UNC paths.
        if ($destPath -match '^[A-Za-z]:') {
            try {
                $destLetter = $destPath.Substring(0, 1)
                $destVolume = Get-Volume -DriveLetter $destLetter -ErrorAction SilentlyContinue
                if ($destVolume) {
                    $freeGB = [math]::Round($destVolume.SizeRemaining / 1GB, 1)
                    # Compute source-VHD size as a rough minimum
                    $sourceFolder = Split-Path $vmcxPath -Parent | Split-Path -Parent
                    $needGB = 0
                    try {
                        $measured = Get-ChildItem -LiteralPath $sourceFolder -Recurse -Filter '*.vhd*' -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
                        if ($measured.Sum) { $needGB = [math]::Round($measured.Sum / 1GB, 1) }
                    } catch { }
                    if ($needGB -gt 0 -and $freeGB -lt ($needGB * 1.1)) {
                        Write-OutputColor "" -color "Error"
                        Write-OutputColor "  Insufficient free space: ${freeGB} GB on ${destLetter}:, need ~${needGB} GB + 10% headroom." -color "Error"
                        return
                    }
                }
            } catch { }
        }
    }

    # Pre-import: check for duplicate VM name on this host. Hyper-V allows duplicate names
    # (uniqueness is on VMId, not Name). Past pattern: operator imports backup of DC01 onto
    # a host already running DC01; both VMs exist; powering up the import without realizing
    # the live one is still running causes AD USN rollback / SID collision / DHCP corruption.
    try {
        $cmp = Compare-VM -Path $vmcxPath -ErrorAction SilentlyContinue
        if ($cmp -and $cmp.VM -and $cmp.VM.Name) {
            $existingByName = @(Get-VM -Name $cmp.VM.Name -ErrorAction SilentlyContinue)
            if ($existingByName.Count -gt 0) {
                Write-OutputColor "" -color "Warning"
                Write-OutputColor "  WARNING: A VM named '$($cmp.VM.Name)' already exists on this host:" -color "Warning"
                foreach ($v in $existingByName) {
                    Write-OutputColor "    - $($v.Name) (Id $($v.VMId), State $($v.State))" -color "Info"
                }
                Write-OutputColor "  Importing will create a second VM with the same name. Powering both on can cause" -color "Critical"
                Write-OutputColor "  identity collisions (AD USN rollback, DHCP scope corruption, duplicate SPNs)." -color "Critical"
                if (-not (Confirm-UserAction -Message "Continue with duplicate-name import?")) {
                    Write-OutputColor "  Cancelled. Rename the existing VM or use a different export." -color "Info"
                    return
                }
            }
            # Surface Compare-VM incompatibilities (missing vSwitch, CPU features, parent VHDs).
            if ($cmp.Incompatibilities -and $cmp.Incompatibilities.Count -gt 0) {
                Write-OutputColor "" -color "Warning"
                Write-OutputColor "  Compare-VM detected $($cmp.Incompatibilities.Count) incompatibility(ies):" -color "Warning"
                foreach ($inc in ($cmp.Incompatibilities | Select-Object -First 8)) {
                    Write-OutputColor "    - $($inc.Message)" -color "Warning"
                }
                if (-not (Confirm-UserAction -Message "Continue with incompatible config (may require manual fixup post-import)?")) {
                    return
                }
            }
        }
    } catch {
        Write-OutputColor "  Warning: Compare-VM pre-check failed: $($_.Exception.Message). Proceeding cautiously." -color "Warning"
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Importing VM..." -color "Info"

    try {
        $importParams = @{ Path = $vmcxPath }
        if ($copyMode) {
            $importParams['Copy'] = $true
            $importParams['GenerateNewId'] = $true
            $importParams['VirtualMachinePath'] = $destPath
            $importParams['VhdDestinationPath'] = $destPath
        }

        $importedVM = Import-VM @importParams -ErrorAction Stop

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  VM imported successfully!" -color "Success"
        Write-OutputColor "  Name: $($importedVM.Name)" -color "Info"
        Write-OutputColor "  ID: $($importedVM.Id)" -color "Info"
        Add-SessionChange -Category "VM" -Description "Imported VM '$($importedVM.Name)'"
        Clear-MenuCache
    }
    catch {
        Write-RackStackError -Code "RS-5006" -Detail "$_"
        Write-OutputColor "  Error importing VM: $_" -color "Error"
    }
}

# Function to show VM Export/Import menu
function Show-VMExportImportMenu {
    param(
        [string]$ComputerName = $null,
        [System.Management.Automation.PSCredential]$Credential = $null
    )

    # Pre-check: Hyper-V must be installed
    if (-not $ComputerName -and -not (Test-HyperVInstalled)) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Hyper-V is not installed on this host." -color "Error"
        Write-OutputColor "  Install Hyper-V from Roles & Features before exporting/importing VMs." -color "Warning"
        return
    }

    while ($true) {
        if ($script:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                        VM EXPORT / IMPORT").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-MenuItem -Text "[1]  Export VM"
        Write-MenuItem -Text "[2]  Import VM"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" {
                Export-VMWizard -ComputerName $ComputerName -Credential $Credential
                Write-PressEnter
            }
            "2" {
                Import-VMWizard -ComputerName $ComputerName -Credential $Credential
                Write-PressEnter
            }
            "b" { return }
            "B" { return }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-2 or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}
#endregion