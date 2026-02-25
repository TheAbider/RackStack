#region ===== DISK CLEANUP =====
# Function to run disk cleanup
function Start-DiskCleanup {
    while ($true) {
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                         DISK CLEANUP UTILITY").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        # Calculate potential space savings
        $tempSize = 0
        $wuSize = 0
        $logsSize = 0

        # Temp files
        $tempPaths = @($env:TEMP, "C:\Windows\Temp", "C:\Windows\Prefetch")
        foreach ($path in $tempPaths) {
            if (Test-Path $path) {
                $tempSize += [long](Get-ChildItem $path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            }
        }

        # Windows Update cache
        $wuPath = "C:\Windows\SoftwareDistribution\Download"
        if (Test-Path $wuPath) {
            $wuSize = [long](Get-ChildItem $wuPath -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        }

        # CBS Logs
        $cbsPath = "C:\Windows\Logs\CBS"
        if (Test-Path $cbsPath) {
            $logsSize = [long](Get-ChildItem $cbsPath -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        }

        $totalPotential = $tempSize + $wuSize + $logsSize

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  POTENTIAL SPACE SAVINGS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  Temporary Files:        $([math]::Round($tempSize/1MB, 1)) MB".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Windows Update Cache:   $([math]::Round($wuSize/1MB, 1)) MB".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  CBS/DISM Logs:          $([math]::Round($logsSize/1MB, 1)) MB".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  ─────────────────────────────────────────".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Total Potential:        $([math]::Round($totalPotential/1MB, 1)) MB".PadRight(72))│" -color "Success"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  CLEANUP OPTIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem -Text "[1]  Quick Clean (Temp files only)"
        Write-MenuItem -Text "[2]  Standard Clean (Temp + WU Cache)"
        Write-MenuItem -Text "[3]  Deep Clean (All + Component Store)"
        Write-MenuItem -Text "[4]  Clear Windows Update Cache Only"
        Write-MenuItem -Text "[5]  Run Windows Disk Cleanup Tool"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" {
                if (Confirm-UserAction -Message "Clean temporary files?" -DefaultYes) { Invoke-QuickClean }
            }
            "2" {
                if (Confirm-UserAction -Message "Clean temp files and Windows Update cache?") { Invoke-StandardClean }
            }
            "3" {
                Write-OutputColor "  Deep Clean includes DISM /ResetBase which is irreversible." -color "Warning"
                if (Confirm-UserAction -Message "Run Deep Clean? This cannot be undone.") { Invoke-DeepClean }
            }
            "4" {
                if (Confirm-UserAction -Message "Clear Windows Update cache? (Services will be restarted)" -DefaultYes) { Clear-WindowsUpdateCache }
            }
            "5" {
                Write-OutputColor "  Launching Windows Disk Cleanup..." -color "Info"
                Start-Process cleanmgr -ArgumentList "/d C" -Wait
            }
            "b" { return }
            "B" { return }
            default { Write-OutputColor "  Invalid choice." -color "Error"; Start-Sleep -Seconds 1 }
        }

        Write-PressEnter
    }
}

function Invoke-QuickClean {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Running Quick Clean..." -color "Info"
    $cleaned = 0

    # User temp
    if (Test-Path $env:TEMP) {
        $files = Get-ChildItem $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $fileSize = $file.Length
            Remove-Item $file.FullName -Force -Recurse -ErrorAction SilentlyContinue
            if (-not (Test-Path $file.FullName)) { $cleaned += $fileSize }
        }
    }

    # Windows temp
    if (Test-Path "C:\Windows\Temp") {
        $files = Get-ChildItem "C:\Windows\Temp" -Recurse -Force -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $fileSize = $file.Length
            Remove-Item $file.FullName -Force -Recurse -ErrorAction SilentlyContinue
            if (-not (Test-Path $file.FullName)) { $cleaned += $fileSize }
        }
    }

    Write-OutputColor "  Quick Clean complete. Freed approximately $([math]::Round($cleaned/1MB, 1)) MB" -color "Success"
    Add-SessionChange -Category "System" -Description "Disk cleanup freed $([math]::Round($cleaned/1MB, 1)) MB"
}

function Invoke-StandardClean {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Running Standard Clean..." -color "Info"

    Invoke-QuickClean
    Clear-WindowsUpdateCache
}

function Invoke-DeepClean {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Running Deep Clean (this may take several minutes)..." -color "Info"

    Invoke-StandardClean

    # Component store cleanup
    Write-OutputColor "  Cleaning component store (DISM)..." -color "Info"
    $null = Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase 2>&1
    Write-OutputColor "  Component store cleanup complete." -color "Success"

    # Clear CBS logs
    if (Test-Path "C:\Windows\Logs\CBS") {
        Get-ChildItem "C:\Windows\Logs\CBS\*.log" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-OutputColor "  CBS logs cleared." -color "Success"
    }

    Add-SessionChange -Category "System" -Description "Deep disk cleanup completed"
}

function Clear-WindowsUpdateCache {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Clearing Windows Update cache..." -color "Info"

    try {
        # Stop Windows Update service
        Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
        Stop-Service bits -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        # Clear download folder
        $wuPath = "C:\Windows\SoftwareDistribution\Download"
        if (Test-Path $wuPath) {
            Get-ChildItem $wuPath -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }

        # Restart services
        Start-Service bits -ErrorAction SilentlyContinue
        Start-Service wuauserv -ErrorAction SilentlyContinue

        Write-OutputColor "  Windows Update cache cleared." -color "Success"
        Add-SessionChange -Category "System" -Description "Cleared Windows Update cache"
    }
    catch {
        Write-OutputColor "  Error clearing cache: $_" -color "Error"
        # Make sure services are restarted
        Start-Service bits -ErrorAction SilentlyContinue
        Start-Service wuauserv -ErrorAction SilentlyContinue
    }
}
#endregion