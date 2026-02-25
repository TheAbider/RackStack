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
        Write-OutputColor "  No VMs available for export." -color "Warning"
        return
    }

    # Display VMs
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT VM TO EXPORT").PadRight(72)│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $vmIndex = 1
    $vmMap = @{}
    foreach ($vm in $vms) {
        $stateColor = if ($vm.State -eq 'Running') { "Success" } elseif ($vm.State -eq 'Off') { "Warning" } else { "Info" }
        $vhdSizes = ($vm.HardDrives | ForEach-Object { (Get-VHD $_.Path -ErrorAction SilentlyContinue).FileSize } | Measure-Object -Sum)
        $sizeStr = if ($null -ne $vhdSizes.Sum -and $vhdSizes.Sum -gt 0) { "{0:N0}GB" -f ($vhdSizes.Sum / 1GB) } else { "N/A" }
        $vmDisplay = "[$vmIndex]  $($vm.Name.PadRight(35)) $($vm.State.ToString().PadRight(10)) $sizeStr"
        Write-OutputColor "  │  $($vmDisplay.PadRight(68))│" -color $stateColor
        $vmMap["$vmIndex"] = $vm
        $vmIndex++
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $vmChoice = Read-Host "  Enter VM number"
    $navResult = Test-NavigationCommand -UserInput $vmChoice
    if ($navResult.ShouldReturn) { return }

    if (-not $vmMap.ContainsKey($vmChoice)) {
        Write-OutputColor "  Invalid selection." -color "Error"
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
    if ([string]::IsNullOrWhiteSpace($exportPath)) { $exportPath = $defaultPath }

    # Ensure export directory exists
    if (-not (Test-Path -LiteralPath $exportPath)) {
        Write-OutputColor "  Creating export directory: $exportPath" -color "Info"
        $null = New-Item -Path $exportPath -ItemType Directory -Force
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

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Starting export (this may take a while)..." -color "Info"

    try {
        # Use a job for background progress
        $exportJob = Start-Job -ScriptBlock {
            param($VMName, $Path, $Computer)
            if ($Computer) {
                Export-VM -Name $VMName -Path $Path -ComputerName $Computer
            } else {
                Export-VM -Name $VMName -Path $Path
            }
        } -ArgumentList $selectedVM.Name, $exportPath, $ComputerName

        # Wait with progress indication - track export folder size
        $spinChars = @('|', '/', '-', '\')
        $spinIndex = 0
        $exportElapsed = 0
        $lastExportSize = 0
        $lastExportSpeedCheck = 0
        $exportSpeedBps = 0
        $exportFolder = Join-Path $exportPath $selectedVM.Name

        while ($exportJob.State -eq 'Running') {
            $currentSize = 0
            if (Test-Path $exportFolder) {
                try {
                    $measured = Get-ChildItem -Path $exportFolder -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
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
            Write-ProgressBar -CurrentBytes $currentSize -Activity "Exporting" -SpeedBytesPerSec $exportSpeedBps -ElapsedSeconds $exportElapsed -SpinChar $spin
            Start-Sleep -Seconds 1
            $exportElapsed++
        }
        Write-Host ""

        $null = Receive-Job -Job $exportJob -ErrorAction Stop
        Remove-Job -Job $exportJob

        # Get final export size for completion summary
        $finalExportSize = 0
        if (Test-Path $exportFolder) {
            try {
                $measured = Get-ChildItem -Path $exportFolder -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
                if ($null -ne $measured.Sum) { $finalExportSize = $measured.Sum }
            } catch { $finalExportSize = 0 }
        }
        Write-TransferComplete -TotalBytes $finalExportSize -ElapsedSeconds $exportElapsed -Activity "Export"
        Write-OutputColor "  Location: $exportPath\$($selectedVM.Name)" -color "Info"
        Add-SessionChange -Category "VM" -Description "Exported VM '$($selectedVM.Name)' to $exportPath"
    }
    catch {
        Write-OutputColor "  Error exporting VM: $_" -color "Error"
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
            $vchoice = Read-Host "  Enter number"
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
    Write-OutputColor "  │$("  IMPORT MODE").PadRight(72)│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  [1]  Copy - Create new VM with new unique ID (recommended)".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [2]  Register - Use existing files in place".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    $modeChoice = Read-Host "  Select"
    $copyMode = $modeChoice -ne "2"

    if ($copyMode) {
        # Get destination for copy
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Destination for VM files (Enter for default: $script:HostVMStoragePath):" -color "Info"
        $destPath = Read-Host "  "
        if ([string]::IsNullOrWhiteSpace($destPath)) { $destPath = $script:HostVMStoragePath }
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
    }
    catch {
        Write-OutputColor "  Error importing VM: $_" -color "Error"
    }
}

# Function to show VM Export/Import menu
function Show-VMExportImportMenu {
    param(
        [string]$ComputerName = $null,
        [System.Management.Automation.PSCredential]$Credential = $null
    )

    while ($true) {
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
                Write-OutputColor "  Invalid choice." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}
#endregion