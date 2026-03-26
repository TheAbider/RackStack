#region ===== DISK CLEANUP =====
# Function to run disk cleanup
function Start-DiskCleanup {
    while ($true) {
        if ($global:ReturnToMainMenu) { return }
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
        $tempPaths = @($env:TEMP, "$env:SystemRoot\Temp", "$env:SystemRoot\Prefetch")
        foreach ($path in $tempPaths) {
            if (Test-Path -LiteralPath $path) {
                $tempSize += [long](Get-ChildItem -LiteralPath $path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            }
        }

        # Windows Update cache
        $wuPath = "$env:SystemRoot\SoftwareDistribution\Download"
        if (Test-Path -LiteralPath $wuPath) {
            $wuSize = [long](Get-ChildItem -LiteralPath $wuPath -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        }

        # CBS Logs
        $cbsPath = "$env:SystemRoot\Logs\CBS"
        if (Test-Path -LiteralPath $cbsPath) {
            $logsSize = [long](Get-ChildItem -LiteralPath $cbsPath -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
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
        Write-MenuItem -Text "[6]  Detailed Cleanup Analysis"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  EXTENDED CLEANUP".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem -Text "[7]  Clear Windows.old"
        Write-MenuItem -Text "[8]  Clear Browser Caches"
        Write-MenuItem -Text "[9]  Empty Recycle Bin"
        Write-MenuItem -Text "[10] Clean User Profile Temp Files"
        Write-MenuItem -Text "[11] Clear Shadow Copies"
        Write-MenuItem -Text "[12] Full Enhanced Cleanup (runs all applicable)"
        Write-MenuItem -Text "[13] Enhanced Cleanup Analysis"
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
                try {
                    $cleanProc = Start-Process cleanmgr -ArgumentList "/d $($env:SystemDrive.TrimEnd(':'))" -PassThru -ErrorAction Stop
                    $null = $cleanProc | Wait-Process -Timeout 600 -ErrorAction SilentlyContinue
                    if (-not $cleanProc.HasExited) {
                        Write-OutputColor "  Disk Cleanup is still running. Continuing..." -color "Warning"
                    }
                }
                catch {
                    Write-RackStackError -Code "RS-6008" -Detail "Disk Cleanup tool failed to launch: $($_.Exception.Message)"
                    Write-OutputColor "  Failed to launch Disk Cleanup: $_" -color "Error"
                }
            }
            "6" {
                Show-CleanupAnalysis
            }
            "7" {
                Clear-WindowsOld
            }
            "8" {
                Clear-BrowserCaches
            }
            "9" {
                Invoke-RecycleBinCleanup
            }
            "10" {
                Clear-UserProfileTemp
            }
            "11" {
                Clear-ShadowCopies
            }
            "12" {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Full Enhanced Cleanup will run all applicable cleanup operations." -color "Warning"
                Write-OutputColor "  This includes: Quick Clean, WU Cache, Browser Caches, Recycle Bin," -color "Warning"
                Write-OutputColor "  User Profile Temp, Windows.old (if present), and Shadow Copies." -color "Warning"
                Write-OutputColor "" -color "Info"
                if (Confirm-UserAction -Message "Run Full Enhanced Cleanup? Some operations are irreversible.") {
                    Invoke-FullEnhancedCleanup
                }
            }
            "13" {
                Show-EnhancedCleanupAnalysis
            }
            "b" { return }
            "B" { return }
            default { Write-OutputColor "  Invalid choice. Enter 1-13 or B." -color "Error"; Start-Sleep -Seconds 1 }
        }

        Write-PressEnter
    }
}

function Invoke-QuickClean {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Running Quick Clean..." -color "Info"
    $cleaned = 0
    $fileCount = 0
    $lastUpdate = [DateTime]::Now

    $tempPaths = @($env:TEMP, "$env:SystemRoot\Temp")
    foreach ($tempPath in $tempPaths) {
        if (Test-Path -LiteralPath $tempPath) {
            $files = Get-ChildItem -LiteralPath $tempPath -Recurse -Force -File -ErrorAction SilentlyContinue
            foreach ($file in $files) {
                try {
                    $fileSize = $file.Length
                    Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                    $cleaned += $fileSize
                    $fileCount++
                }
                catch { $null = $_ }
                # Progress update every 500ms
                if (([DateTime]::Now - $lastUpdate).TotalMilliseconds -gt 500) {
                    $cleanedMB = [math]::Round($cleaned / 1MB, 1)
                    Write-Host "`r  Cleaning: $fileCount files deleted ($cleanedMB MB freed)..." -NoNewline
                    $lastUpdate = [DateTime]::Now
                }
            }
        }
    }

    Write-Host "`r$(' ' * 72)" -NoNewline
    Write-Host "`r" -NoNewline
    Write-OutputColor "  Quick Clean complete. Freed $([math]::Round($cleaned/1MB, 1)) MB ($fileCount files)" -color "Success"
    Add-SessionChange -Category "System" -Description "Disk cleanup freed $([math]::Round($cleaned/1MB, 1)) MB ($fileCount files)"
    Clear-MenuCache
    Write-PressEnter
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

    # Component store cleanup (with progress spinner)
    $dismResult = Invoke-WithTimeout -ScriptBlock {
        $output = Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase 2>&1
        @{ ExitCode = $LASTEXITCODE; Output = $output }
    } -TimeoutSeconds 1800 -Activity "Cleaning component store (DISM)"
    if ($dismResult.TimedOut) {
        Write-OutputColor "  DISM timed out after 30 minutes." -color "Warning"
    } elseif ($dismResult.Result.ExitCode -ne 0) {
        Write-OutputColor "  Component store cleanup failed (exit code $($dismResult.Result.ExitCode))." -color "Error"
    } else {
        Write-OutputColor "  Component store cleanup complete." -color "Success"
    }

    # Clear CBS logs
    if (Test-Path -LiteralPath "$env:SystemRoot\Logs\CBS") {
        Get-ChildItem -Path "$env:SystemRoot\Logs\CBS\*.log" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-OutputColor "  CBS logs cleared." -color "Success"
    }

    Add-SessionChange -Category "System" -Description "Deep disk cleanup completed"
    Clear-MenuCache
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
        $wuPath = "$env:SystemRoot\SoftwareDistribution\Download"
        if (Test-Path -LiteralPath $wuPath) {
            Get-ChildItem -LiteralPath $wuPath -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction SilentlyContinue }
        }

        Write-OutputColor "  Windows Update cache cleared." -color "Success"
        Add-SessionChange -Category "System" -Description "Cleared Windows Update cache"
        Clear-MenuCache
    }
    catch {
        Write-OutputColor "  Error clearing cache: $_" -color "Error"
    }
    finally {
        # Always restart services regardless of success/failure
        Start-Service bits -ErrorAction SilentlyContinue
        Start-Service wuauserv -ErrorAction SilentlyContinue
    }
}

# Function to show detailed disk cleanup analysis
function Show-CleanupAnalysis {
    Write-OutputColor "`n  Disk Cleanup Analysis:" -color "Info"

    $totalSavings = 0

    # Windows Update cache
    $wuPath = "$env:SystemRoot\SoftwareDistribution\Download"
    if (Test-Path -LiteralPath $wuPath) {
        $wuSize = [long](Get-ChildItem -LiteralPath $wuPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        $wuMB = [math]::Round($wuSize / 1MB, 0)
        $totalSavings += $wuSize
        Write-OutputColor "  Windows Update Cache: ${wuMB} MB" -color $(if ($wuMB -gt 100) { "Warning" } else { "Info" })
    }

    # Temp files
    $tempPaths = @($env:TEMP, "$env:SystemRoot\Temp")
    $tempTotal = 0
    foreach ($tempPath in $tempPaths) {
        if (Test-Path -LiteralPath $tempPath) {
            $tempSize = [long](Get-ChildItem -LiteralPath $tempPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            $tempTotal += $tempSize
        }
    }
    $tempMB = [math]::Round($tempTotal / 1MB, 0)
    $totalSavings += $tempTotal
    Write-OutputColor "  Temp Files: ${tempMB} MB" -color $(if ($tempMB -gt 500) { "Warning" } else { "Info" })

    # CBS logs
    $cbsPath = "$env:SystemRoot\Logs\CBS"
    if (Test-Path -LiteralPath $cbsPath) {
        $cbsSize = [long](Get-ChildItem -LiteralPath $cbsPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        $cbsMB = [math]::Round($cbsSize / 1MB, 0)
        $totalSavings += $cbsSize
        Write-OutputColor "  CBS Logs: ${cbsMB} MB" -color $(if ($cbsMB -gt 200) { "Warning" } else { "Info" })
    }

    $totalMB = [math]::Round($totalSavings / 1MB, 0)
    $totalGB = [math]::Round($totalSavings / 1GB, 1)
    Write-OutputColor "`n  Potential savings: ${totalMB} MB (${totalGB} GB)" -color $(if ($totalGB -gt 1) { "Warning" } else { "Success" })
}

function Clear-WindowsOld {
    Write-OutputColor "" -color "Info"
    $winOldPath = "$env:SystemDrive\Windows.old"

    if (-not (Test-Path -LiteralPath $winOldPath)) {
        Write-OutputColor "  Windows.old directory not found. Nothing to clean." -color "Info"
        return
    }

    # Calculate size
    Write-OutputColor "  Calculating Windows.old size..." -color "Info"
    $winOldSize = [long](Get-ChildItem -LiteralPath $winOldPath -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    $winOldGB = [math]::Round($winOldSize / 1GB, 2)
    Write-OutputColor "  Windows.old size: $winOldGB GB" -color "Warning"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  WARNING: This will permanently remove the previous Windows installation." -color "Warning"
    Write-OutputColor "  You will NOT be able to roll back to the previous version of Windows." -color "Warning"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Remove Windows.old ($winOldGB GB)? This is irreversible.")) {
        Write-OutputColor "  Operation cancelled." -color "Info"
        return
    }

    Write-OutputColor "  Taking ownership and removing Windows.old..." -color "Info"
    try {
        # Take ownership
        $null = takeown /F $winOldPath /R /A /D Y 2>&1
        $null = icacls $winOldPath /grant Administrators:F /T /C /Q 2>&1

        # Remove the directory
        Remove-Item -LiteralPath $winOldPath -Recurse -Force -ErrorAction Stop
        Write-OutputColor "  Windows.old removed. Freed $winOldGB GB." -color "Success"
        Add-SessionChange -Category "System" -Description "Removed Windows.old, freed $winOldGB GB"
        Clear-MenuCache
    }
    catch {
        Write-OutputColor "  Failed to remove Windows.old: $_" -color "Error"
        Write-OutputColor "  Try running Windows Disk Cleanup (option 5) with 'Previous Windows installations' checked." -color "Info"
    }
}

function Clear-BrowserCaches {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Browser Cache Cleanup" -color "Info"
    Write-OutputColor "  ─────────────────────" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  NOTE: Close all browsers before proceeding for best results." -color "Warning"
    Write-OutputColor "" -color "Info"

    $totalCleaned = 0
    $browsersFound = 0

    # Edge
    $edgeCachePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    if (Test-Path -LiteralPath $edgeCachePath) {
        $browsersFound++
        $edgeSize = [long](Get-ChildItem -Path "$edgeCachePath\*\Cache\*" -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        $edgeCodeSize = [long](Get-ChildItem -Path "$edgeCachePath\*\Code Cache\*" -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        $edgeTotal = $edgeSize + $edgeCodeSize
        $edgeMB = [math]::Round($edgeTotal / 1MB, 1)
        Write-OutputColor "  Microsoft Edge cache: $edgeMB MB" -color "Info"

        if ($edgeTotal -gt 0) {
            if (Confirm-UserAction -Message "Clear Edge cache ($edgeMB MB)?" -DefaultYes) {
                $cleaned = 0
                Get-ChildItem -Path "$edgeCachePath\*\Cache\*" -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        $fileLen = $_.Length
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                        $cleaned += $fileLen
                    }
                    catch { $null = $_ }
                }
                Get-ChildItem -Path "$edgeCachePath\*\Code Cache\*" -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        $fileLen = $_.Length
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                        $cleaned += $fileLen
                    }
                    catch { $null = $_ }
                }
                $cleanedMB = [math]::Round($cleaned / 1MB, 1)
                Write-OutputColor "  Edge cache cleared: $cleanedMB MB freed." -color "Success"
                $totalCleaned += $cleaned
            }
        }
    }

    # Chrome
    $chromeCachePath = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    if (Test-Path -LiteralPath $chromeCachePath) {
        $browsersFound++
        $chromeSize = [long](Get-ChildItem -Path "$chromeCachePath\*\Cache\*" -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        $chromeCodeSize = [long](Get-ChildItem -Path "$chromeCachePath\*\Code Cache\*" -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        $chromeTotal = $chromeSize + $chromeCodeSize
        $chromeMB = [math]::Round($chromeTotal / 1MB, 1)
        Write-OutputColor "  Google Chrome cache: $chromeMB MB" -color "Info"

        if ($chromeTotal -gt 0) {
            if (Confirm-UserAction -Message "Clear Chrome cache ($chromeMB MB)?" -DefaultYes) {
                $cleaned = 0
                Get-ChildItem -Path "$chromeCachePath\*\Cache\*" -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        $fileLen = $_.Length
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                        $cleaned += $fileLen
                    }
                    catch { $null = $_ }
                }
                Get-ChildItem -Path "$chromeCachePath\*\Code Cache\*" -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        $fileLen = $_.Length
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                        $cleaned += $fileLen
                    }
                    catch { $null = $_ }
                }
                $cleanedMB = [math]::Round($cleaned / 1MB, 1)
                Write-OutputColor "  Chrome cache cleared: $cleanedMB MB freed." -color "Success"
                $totalCleaned += $cleaned
            }
        }
    }

    # Firefox
    $firefoxProfilePath = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path -LiteralPath $firefoxProfilePath) {
        $browsersFound++
        $firefoxSize = [long](Get-ChildItem -Path "$firefoxProfilePath\*\cache2\*" -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        $firefoxMB = [math]::Round($firefoxSize / 1MB, 1)
        Write-OutputColor "  Mozilla Firefox cache: $firefoxMB MB" -color "Info"

        if ($firefoxSize -gt 0) {
            if (Confirm-UserAction -Message "Clear Firefox cache ($firefoxMB MB)?" -DefaultYes) {
                $cleaned = 0
                Get-ChildItem -Path "$firefoxProfilePath\*\cache2\*" -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        $fileLen = $_.Length
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                        $cleaned += $fileLen
                    }
                    catch { $null = $_ }
                }
                $cleanedMB = [math]::Round($cleaned / 1MB, 1)
                Write-OutputColor "  Firefox cache cleared: $cleanedMB MB freed." -color "Success"
                $totalCleaned += $cleaned
            }
        }
    }

    if ($browsersFound -eq 0) {
        Write-OutputColor "  No browser cache directories found." -color "Info"
        return
    }

    if ($totalCleaned -gt 0) {
        $totalCleanedMB = [math]::Round($totalCleaned / 1MB, 1)
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Total browser cache freed: $totalCleanedMB MB" -color "Success"
        Add-SessionChange -Category "System" -Description "Cleared browser caches, freed $totalCleanedMB MB"
        Clear-MenuCache
    } else {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  No browser cache files were removed." -color "Info"
    }
}

function Invoke-RecycleBinCleanup {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Recycle Bin Cleanup" -color "Info"
    Write-OutputColor "  ───────────────────" -color "Info"
    Write-OutputColor "" -color "Info"

    # Estimate recycle bin size using COM object
    $recycleBinSize = 0
    $recycleBinCount = 0
    try {
        $shell = New-Object -ComObject Shell.Application
        $recycleBin = $shell.NameSpace(0x0A)
        if ($null -ne $recycleBin) {
            $items = $recycleBin.Items()
            $recycleBinCount = $items.Count
            foreach ($item in $items) {
                try {
                    $recycleBinSize += $recycleBin.GetDetailsOf($item, 2) -replace '[^\d]', ''
                }
                catch { $null = $_ }
            }
        }
    }
    catch {
        Write-OutputColor "  Could not estimate recycle bin size." -color "Warning"
    }
    finally {
        if ($null -ne $shell) {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
        }
    }

    if ($recycleBinCount -eq 0) {
        Write-OutputColor "  Recycle Bin is empty. Nothing to clean." -color "Info"
        return
    }

    Write-OutputColor "  Recycle Bin contains approximately $recycleBinCount item(s)." -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Empty the Recycle Bin?" -DefaultYes)) {
        Write-OutputColor "  Operation cancelled." -color "Info"
        return
    }

    try {
        # Try PowerShell 5.1+ cmdlet first
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-OutputColor "  Recycle Bin emptied successfully." -color "Success"
        Add-SessionChange -Category "System" -Description "Emptied Recycle Bin ($recycleBinCount items)"
        Clear-MenuCache
    }
    catch {
        # Fallback: use COM Shell.Application
        try {
            $shell = New-Object -ComObject Shell.Application
            $recycleBin = $shell.NameSpace(0x0A)
            if ($null -ne $recycleBin) {
                foreach ($item in $recycleBin.Items()) {
                    try {
                        Remove-Item -LiteralPath $item.Path -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    catch { $null = $_ }
                }
            }
            Write-OutputColor "  Recycle Bin emptied (COM fallback)." -color "Success"
            Add-SessionChange -Category "System" -Description "Emptied Recycle Bin ($recycleBinCount items)"
            Clear-MenuCache
        }
        catch {
            Write-OutputColor "  Failed to empty Recycle Bin: $_" -color "Error"
        }
        finally {
            if ($null -ne $shell) {
                [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
            }
        }
    }
}

function Clear-UserProfileTemp {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  User Profile Temp Cleanup" -color "Info"
    Write-OutputColor "  ─────────────────────────" -color "Info"
    Write-OutputColor "" -color "Info"

    $currentUser = $env:USERNAME
    $profilesPath = "$env:SystemDrive\Users"
    $totalCleaned = 0
    $totalFiles = 0

    $subPaths = @(
        "AppData\Local\Temp",
        "AppData\Local\CrashDumps",
        "AppData\Local\D3DSCache",
        "AppData\Local\Microsoft\Windows\INetCache"
    )

    $userProfiles = Get-ChildItem -LiteralPath $profilesPath -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -notin @('Public', 'Default', 'Default User', 'All Users')
    }

    if ($null -eq $userProfiles -or @($userProfiles).Count -eq 0) {
        Write-OutputColor "  No user profiles found." -color "Info"
        return
    }

    # Scan and display per-profile sizes
    $profileData = @()
    foreach ($userProfile in $userProfiles) {
        $profileSize = 0
        $isCurrentUser = ($userProfile.Name -eq $currentUser)
        foreach ($subPath in $subPaths) {
            $fullPath = Join-Path -Path $userProfile.FullName -ChildPath $subPath
            if (Test-Path -LiteralPath $fullPath) {
                # Skip current user's Temp (files in use)
                if ($isCurrentUser -and $subPath -eq "AppData\Local\Temp") {
                    continue
                }
                $profileSize += [long](Get-ChildItem -LiteralPath $fullPath -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            }
        }
        $profileMB = [math]::Round($profileSize / 1MB, 1)
        $skipNote = if ($isCurrentUser) { " (Temp skipped - in use)" } else { "" }
        Write-OutputColor "  $($userProfile.Name): $profileMB MB$skipNote" -color $(if ($profileMB -gt 100) { "Warning" } else { "Info" })
        $profileData += @{ Name = $userProfile.Name; Size = $profileSize; IsCurrentUser = $isCurrentUser; Path = $userProfile.FullName }
    }

    $grandTotal = ($profileData | ForEach-Object { $_.Size } | Measure-Object -Sum).Sum
    $grandTotalMB = [math]::Round($grandTotal / 1MB, 1)
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Total cleanable: $grandTotalMB MB" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($grandTotal -eq 0) {
        Write-OutputColor "  No temp files to clean." -color "Info"
        return
    }

    if (-not (Confirm-UserAction -Message "Clean user profile temp files ($grandTotalMB MB)?" -DefaultYes)) {
        Write-OutputColor "  Operation cancelled." -color "Info"
        return
    }

    foreach ($pd in $profileData) {
        if ($pd.Size -eq 0) { continue }
        $profileCleaned = 0
        $profileFiles = 0

        foreach ($subPath in $subPaths) {
            $fullPath = Join-Path -Path $pd.Path -ChildPath $subPath
            if (-not (Test-Path -LiteralPath $fullPath)) { continue }

            # Skip current user's Temp
            if ($pd.IsCurrentUser -and $subPath -eq "AppData\Local\Temp") {
                continue
            }

            $files = Get-ChildItem -LiteralPath $fullPath -Recurse -Force -File -ErrorAction SilentlyContinue
            foreach ($file in $files) {
                try {
                    $fileSize = $file.Length
                    Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                    $profileCleaned += $fileSize
                    $profileFiles++
                }
                catch { $null = $_ }
            }
        }

        if ($profileCleaned -gt 0) {
            $cleanedMB = [math]::Round($profileCleaned / 1MB, 1)
            Write-OutputColor "  $($pd.Name): freed $cleanedMB MB ($profileFiles files)" -color "Success"
            $totalCleaned += $profileCleaned
            $totalFiles += $profileFiles
        }
    }

    $totalCleanedMB = [math]::Round($totalCleaned / 1MB, 1)
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  User profile cleanup complete. Freed $totalCleanedMB MB ($totalFiles files)" -color "Success"
    Add-SessionChange -Category "System" -Description "User profile temp cleanup freed $totalCleanedMB MB ($totalFiles files)"
    Clear-MenuCache
}

function Clear-ShadowCopies {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Shadow Copy (Restore Point) Cleanup" -color "Info"
    Write-OutputColor "  ────────────────────────────────────" -color "Info"
    Write-OutputColor "" -color "Info"

    # List current shadow copies
    try {
        $vssOutput = vssadmin list shadows 2>&1
        $shadowCount = @($vssOutput | Select-String -Pattern "Shadow Copy ID:" -ErrorAction SilentlyContinue).Count

        if ($shadowCount -eq 0) {
            Write-OutputColor "  No shadow copies found. Nothing to clean." -color "Info"
            return
        }

        Write-OutputColor "  Found $shadowCount shadow copy/copies." -color "Info"

        # Estimate storage used by shadow copies
        $vssStorageOutput = vssadmin list shadowstorage 2>&1
        $usedMatch = $vssStorageOutput | Select-String -Pattern "Used Shadow Copy Storage space:\s*(.+)" -ErrorAction SilentlyContinue
        if ($null -ne $usedMatch) {
            $usedStorage = $usedMatch.Matches[0].Groups[1].Value.Trim()
            Write-OutputColor "  Shadow copy storage used: $usedStorage" -color "Info"
        }
    }
    catch {
        Write-OutputColor "  Could not enumerate shadow copies: $_" -color "Error"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  WARNING: This will remove ALL shadow copies (restore points)." -color "Warning"
    Write-OutputColor "  You will NOT be able to use System Restore to roll back." -color "Warning"
    Write-OutputColor "  This operation CANNOT be undone." -color "Warning"
    Write-OutputColor "" -color "Info"

    # Explicit confirmation (no DefaultYes)
    if (-not (Confirm-UserAction -Message "Delete ALL shadow copies? This is irreversible.")) {
        Write-OutputColor "  Operation cancelled." -color "Info"
        return
    }

    try {
        $deleteOutput = vssadmin delete shadows /all /quiet 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-OutputColor "  All shadow copies deleted successfully." -color "Success"
            Add-SessionChange -Category "System" -Description "Deleted $shadowCount shadow copies (restore points)"
            Clear-MenuCache
        } else {
            Write-OutputColor "  Shadow copy deletion may have partially failed." -color "Warning"
            Write-OutputColor "  vssadmin output: $deleteOutput" -color "Warning"
        }
    }
    catch {
        Write-OutputColor "  Failed to delete shadow copies: $_" -color "Error"
    }
}

function Show-EnhancedCleanupAnalysis {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  ENHANCED DISK CLEANUP ANALYSIS".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Run standard analysis first
    Show-CleanupAnalysis

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Extended Analysis:" -color "Info"
    Write-OutputColor "  ──────────────────" -color "Info"

    $extendedTotal = 0
    $shadowCount = 0

    # Windows.old
    $winOldPath = "$env:SystemDrive\Windows.old"
    if (Test-Path -LiteralPath $winOldPath) {
        $winOldSize = [long](Get-ChildItem -LiteralPath $winOldPath -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        $winOldGB = [math]::Round($winOldSize / 1GB, 2)
        $extendedTotal += $winOldSize
        Write-OutputColor "  Windows.old: $winOldGB GB" -color "Warning"
    } else {
        Write-OutputColor "  Windows.old: Not present" -color "Info"
    }

    # Browser caches
    $browserTotal = 0
    $edgeCachePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    if (Test-Path -LiteralPath $edgeCachePath) {
        $edgeSize = [long](Get-ChildItem -Path "$edgeCachePath\*\Cache\*" -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        $edgeCodeSize = [long](Get-ChildItem -Path "$edgeCachePath\*\Code Cache\*" -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        $browserTotal += $edgeSize + $edgeCodeSize
        $edgeMB = [math]::Round(($edgeSize + $edgeCodeSize) / 1MB, 1)
        Write-OutputColor "  Edge cache: $edgeMB MB" -color $(if ($edgeMB -gt 200) { "Warning" } else { "Info" })
    }

    $chromeCachePath = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    if (Test-Path -LiteralPath $chromeCachePath) {
        $chromeSize = [long](Get-ChildItem -Path "$chromeCachePath\*\Cache\*" -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        $chromeCodeSize = [long](Get-ChildItem -Path "$chromeCachePath\*\Code Cache\*" -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        $browserTotal += $chromeSize + $chromeCodeSize
        $chromeMB = [math]::Round(($chromeSize + $chromeCodeSize) / 1MB, 1)
        Write-OutputColor "  Chrome cache: $chromeMB MB" -color $(if ($chromeMB -gt 200) { "Warning" } else { "Info" })
    }

    $firefoxProfilePath = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path -LiteralPath $firefoxProfilePath) {
        $firefoxSize = [long](Get-ChildItem -Path "$firefoxProfilePath\*\cache2\*" -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        $browserTotal += $firefoxSize
        $firefoxMB = [math]::Round($firefoxSize / 1MB, 1)
        Write-OutputColor "  Firefox cache: $firefoxMB MB" -color $(if ($firefoxMB -gt 200) { "Warning" } else { "Info" })
    }

    if ($browserTotal -eq 0) {
        Write-OutputColor "  Browser caches: No caches found" -color "Info"
    }
    $extendedTotal += $browserTotal

    # Recycle Bin estimate
    $recycleBinCount = 0
    try {
        $shell = New-Object -ComObject Shell.Application
        $recycleBin = $shell.NameSpace(0x0A)
        if ($null -ne $recycleBin) {
            $recycleBinCount = $recycleBin.Items().Count
        }
    }
    catch { $null = $_ }
    finally {
        if ($null -ne $shell) {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
        }
    }
    Write-OutputColor "  Recycle Bin: $recycleBinCount item(s)" -color $(if ($recycleBinCount -gt 50) { "Warning" } else { "Info" })

    # Shadow copies
    try {
        $vssOutput = vssadmin list shadows 2>&1
        $shadowCount = @($vssOutput | Select-String -Pattern "Shadow Copy ID:" -ErrorAction SilentlyContinue).Count
        Write-OutputColor "  Shadow copies: $shadowCount" -color $(if ($shadowCount -gt 3) { "Warning" } else { "Info" })

        $vssStorageOutput = vssadmin list shadowstorage 2>&1
        $usedMatch = $vssStorageOutput | Select-String -Pattern "Used Shadow Copy Storage space:\s*(.+)" -ErrorAction SilentlyContinue
        if ($null -ne $usedMatch) {
            $usedStorage = $usedMatch.Matches[0].Groups[1].Value.Trim()
            Write-OutputColor "  Shadow copy storage used: $usedStorage" -color "Info"
        }
    }
    catch {
        Write-OutputColor "  Shadow copies: Could not enumerate" -color "Warning"
    }

    # User profile temp sizes
    $userTempTotal = 0
    $profilesPath = "$env:SystemDrive\Users"
    $currentUser = $env:USERNAME
    $subPaths = @(
        "AppData\Local\Temp",
        "AppData\Local\CrashDumps",
        "AppData\Local\D3DSCache",
        "AppData\Local\Microsoft\Windows\INetCache"
    )

    $userProfiles = Get-ChildItem -LiteralPath $profilesPath -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -notin @('Public', 'Default', 'Default User', 'All Users')
    }

    foreach ($userProfile in $userProfiles) {
        $profileSize = 0
        $isCurrentUser = ($userProfile.Name -eq $currentUser)
        foreach ($subPath in $subPaths) {
            $fullPath = Join-Path -Path $userProfile.FullName -ChildPath $subPath
            if (Test-Path -LiteralPath $fullPath) {
                if ($isCurrentUser -and $subPath -eq "AppData\Local\Temp") { continue }
                $profileSize += [long](Get-ChildItem -LiteralPath $fullPath -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            }
        }
        $userTempTotal += $profileSize
        $profileMB = [math]::Round($profileSize / 1MB, 1)
        $skipNote = if ($isCurrentUser) { " (Temp skipped)" } else { "" }
        if ($profileMB -gt 0) {
            Write-OutputColor "  User temp ($($userProfile.Name)): $profileMB MB$skipNote" -color $(if ($profileMB -gt 100) { "Warning" } else { "Info" })
        }
    }
    $extendedTotal += $userTempTotal

    # Grand total
    $extendedMB = [math]::Round($extendedTotal / 1MB, 0)
    $extendedGB = [math]::Round($extendedTotal / 1GB, 1)
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Extended potential savings: ${extendedMB} MB (${extendedGB} GB)" -color $(if ($extendedGB -gt 1) { "Warning" } else { "Success" })
    Write-OutputColor "  (Shadow copy and Recycle Bin sizes not included in total)" -color "Info"

    # Return structured report for JSON output mode
    $winOldSizeValue = 0
    if (Test-Path -LiteralPath "$env:SystemDrive\Windows.old") { $winOldSizeValue = [math]::Round($winOldSize / 1MB, 1) }
    $cleanupReport = @{
        WindowsOld      = @{
            Present = (Test-Path -LiteralPath "$env:SystemDrive\Windows.old")
            SizeMB  = $winOldSizeValue
        }
        BrowserCacheMB  = [math]::Round($browserTotal / 1MB, 1)
        RecycleBinItems = $recycleBinCount
        ShadowCopies    = $shadowCount
        UserTempMB      = [math]::Round($userTempTotal / 1MB, 1)
        TotalSavingsMB  = $extendedMB
        TotalSavingsGB  = $extendedGB
    }
    return $cleanupReport
}

function Invoke-FullEnhancedCleanup {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  FULL ENHANCED CLEANUP".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $totalFreed = 0

    # Capture pre-cleanup disk space for final comparison
    $preDiskFree = try { (Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -OperationTimeoutSec 8 -ErrorAction SilentlyContinue).FreeSpace } catch { $null }

    # 1. Quick Clean (temp files)
    Write-OutputColor "  [1/7] Quick Clean (temp files)..." -color "Info"
    $beforeTemp = (Get-PSDrive -Name C -ErrorAction SilentlyContinue).Free
    Invoke-QuickClean
    $afterTemp = (Get-PSDrive -Name C -ErrorAction SilentlyContinue).Free
    $tempFreed = $afterTemp - $beforeTemp
    if ($tempFreed -gt 0) { $totalFreed += $tempFreed }

    # 2. Windows Update Cache
    Write-OutputColor "  [2/7] Windows Update Cache..." -color "Info"
    Clear-WindowsUpdateCache

    # 3. Browser Caches (auto-confirm)
    Write-OutputColor "  [3/7] Browser Caches..." -color "Info"
    $browserPaths = @()
    $edgeCachePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    if (Test-Path -LiteralPath $edgeCachePath) {
        $browserPaths += "$edgeCachePath\*\Cache\*"
        $browserPaths += "$edgeCachePath\*\Code Cache\*"
    }
    $chromeCachePath = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    if (Test-Path -LiteralPath $chromeCachePath) {
        $browserPaths += "$chromeCachePath\*\Cache\*"
        $browserPaths += "$chromeCachePath\*\Code Cache\*"
    }
    $firefoxProfilePath = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path -LiteralPath $firefoxProfilePath) {
        $browserPaths += "$firefoxProfilePath\*\cache2\*"
    }

    $browserCleaned = 0
    foreach ($bp in $browserPaths) {
        Get-ChildItem -Path $bp -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $fileLen = $_.Length
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                $browserCleaned += $fileLen
            }
            catch { $null = $_ }
        }
    }
    if ($browserCleaned -gt 0) {
        $browserMB = [math]::Round($browserCleaned / 1MB, 1)
        Write-OutputColor "  Browser caches cleared: $browserMB MB freed." -color "Success"
        Add-SessionChange -Category "System" -Description "Full cleanup: browser caches freed $browserMB MB"
    } else {
        Write-OutputColor "  No browser cache files to clean." -color "Info"
    }

    # 4. Recycle Bin
    Write-OutputColor "  [4/7] Recycle Bin..." -color "Info"
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-OutputColor "  Recycle Bin emptied." -color "Success"
    }
    catch {
        try {
            $shell = New-Object -ComObject Shell.Application
            $recycleBin = $shell.NameSpace(0x0A)
            if ($null -ne $recycleBin) {
                foreach ($item in $recycleBin.Items()) {
                    try { Remove-Item -LiteralPath $item.Path -Recurse -Force -ErrorAction SilentlyContinue }
                    catch { $null = $_ }
                }
            }
            Write-OutputColor "  Recycle Bin emptied (COM fallback)." -color "Success"
        }
        catch {
            Write-OutputColor "  Could not empty Recycle Bin: $_" -color "Warning"
        }
        finally {
            if ($null -ne $shell) {
                [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
            }
        }
    }

    # 5. User Profile Temp
    Write-OutputColor "  [5/7] User Profile Temp Files..." -color "Info"
    $currentUser = $env:USERNAME
    $subPaths = @(
        "AppData\Local\Temp",
        "AppData\Local\CrashDumps",
        "AppData\Local\D3DSCache",
        "AppData\Local\Microsoft\Windows\INetCache"
    )
    $profileCleaned = 0
    $userProfiles = Get-ChildItem -LiteralPath "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -notin @('Public', 'Default', 'Default User', 'All Users')
    }
    foreach ($userProfile in $userProfiles) {
        $isCurrentUser = ($userProfile.Name -eq $currentUser)
        foreach ($subPath in $subPaths) {
            if ($isCurrentUser -and $subPath -eq "AppData\Local\Temp") { continue }
            $fullPath = Join-Path -Path $userProfile.FullName -ChildPath $subPath
            if (Test-Path -LiteralPath $fullPath) {
                Get-ChildItem -LiteralPath $fullPath -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        $fileLen = $_.Length
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                        $profileCleaned += $fileLen
                    }
                    catch { $null = $_ }
                }
            }
        }
    }
    if ($profileCleaned -gt 0) {
        $profileMB = [math]::Round($profileCleaned / 1MB, 1)
        Write-OutputColor "  User profile temp cleaned: $profileMB MB freed." -color "Success"
        Add-SessionChange -Category "System" -Description "Full cleanup: user profile temp freed $profileMB MB"
    } else {
        Write-OutputColor "  No user profile temp files to clean." -color "Info"
    }

    # 6. Windows.old (if present)
    Write-OutputColor "  [6/7] Windows.old..." -color "Info"
    if (Test-Path -LiteralPath "$env:SystemDrive\Windows.old") {
        $winOldSize = [long](Get-ChildItem -LiteralPath "$env:SystemDrive\Windows.old" -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        $winOldGB = [math]::Round($winOldSize / 1GB, 2)
        Write-OutputColor "  Windows.old found ($winOldGB GB)." -color "Warning"
        if (Confirm-UserAction -Message "Remove Windows.old ($winOldGB GB)? This is irreversible.") {
            try {
                $null = takeown /F "$env:SystemDrive\Windows.old" /R /A /D Y 2>&1
                $null = icacls "$env:SystemDrive\Windows.old" /grant Administrators:F /T /C /Q 2>&1
                Remove-Item -LiteralPath "$env:SystemDrive\Windows.old" -Recurse -Force -ErrorAction Stop
                Write-OutputColor "  Windows.old removed: $winOldGB GB freed." -color "Success"
                Add-SessionChange -Category "System" -Description "Full cleanup: removed Windows.old ($winOldGB GB)"
            }
            catch {
                Write-OutputColor "  Failed to remove Windows.old: $_" -color "Error"
            }
        } else {
            Write-OutputColor "  Skipped Windows.old removal." -color "Info"
        }
    } else {
        Write-OutputColor "  Windows.old not present. Skipping." -color "Info"
    }

    # 7. Shadow Copies
    Write-OutputColor "  [7/7] Shadow Copies..." -color "Info"
    try {
        $vssOutput = vssadmin list shadows 2>&1
        $shadowCount = @($vssOutput | Select-String -Pattern "Shadow Copy ID:" -ErrorAction SilentlyContinue).Count
        if ($shadowCount -gt 0) {
            Write-OutputColor "  Found $shadowCount shadow copy/copies." -color "Warning"
            Write-OutputColor "  WARNING: Deleting shadow copies removes ALL restore points and CANNOT be undone." -color "Warning"
            if (Confirm-UserAction -Message "Delete ALL shadow copies?") {
                $null = vssadmin delete shadows /all /quiet 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-OutputColor "  Shadow copies deleted." -color "Success"
                    Add-SessionChange -Category "System" -Description "Full cleanup: deleted $shadowCount shadow copies"
                } else {
                    Write-OutputColor "  Shadow copy deletion may have partially failed." -color "Warning"
                }
            } else {
                Write-OutputColor "  Skipped shadow copy deletion." -color "Info"
            }
        } else {
            Write-OutputColor "  No shadow copies found. Skipping." -color "Info"
        }
    }
    catch {
        Write-OutputColor "  Could not process shadow copies: $_" -color "Warning"
    }

    # Final disk space comparison
    Write-OutputColor "" -color "Info"
    try {
        $postDisk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -OperationTimeoutSec 8 -ErrorAction SilentlyContinue
        if ($null -ne $preDiskFree -and $null -ne $postDisk) {
            $freedMB = [math]::Round(($postDisk.FreeSpace - $preDiskFree) / 1MB)
            if ($freedMB -gt 0) {
                $freedDisplay = if ($freedMB -ge 1024) { "$([math]::Round($freedMB / 1024, 1)) GB" } else { "$freedMB MB" }
                Write-OutputColor "  Total space recovered: $freedDisplay" -color "Success"
            }
        }
    } catch { }
    Write-OutputColor "  Full Enhanced Cleanup complete." -color "Success"
    Add-SessionChange -Category "System" -Description "Full Enhanced Cleanup completed"
    Clear-MenuCache
}
#endregion