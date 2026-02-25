#region ===== EXIT AND CLEANUP =====
# Function to exit the script with optional reboot and file cleanup
function Exit-Script {
    # Save session state for potential resume (v2.8.0)
    if ($script:VMDeploymentQueue -and $script:VMDeploymentQueue.Count -gt 0) {
        Save-SessionState
    }

    # Show session summary first
    Show-SessionSummary

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Press Enter to continue to exit..." -color "Info"
    Read-Host

    Clear-Host
    Write-CenteredOutput "Script Exiting" -color "Info"

    # Check for actual Windows pending reboot OR our flag
    $windowsRebootPending = Test-RebootPending
    $rebootNeeded = $global:RebootNeeded -or $windowsRebootPending

    if ($global:DisabledAdminReboot -eq $true) {
        Write-OutputColor "As always, should you or any member of your IT Force be caught or killed, the Abider will disavow any knowledge of your actions" -color "Error"

        for ($i = 5; $i -gt 0; $i--) {
            Write-OutputColor "This script will now self destruct in $i seconds" -color "Error"
            Start-Sleep -Seconds 1
        }

        Write-OutputColor "Good luck." -color "Error"
        Clear-Host

        # Build list of paths to delete
        $pathsToDelete = [System.Collections.Generic.List[string]]::new()
        $adminFolder = [System.IO.Path]::Combine($env:SystemDrive, "Users", "Administrator")

        # 1) Find all script-related files anywhere in the Administrator profile
        if (Test-Path $adminFolder) {
            # Single file traversal for script-related files (monolithic, exe, configs)
            $allProfileFiles = Get-ChildItem -Path $adminFolder -Recurse -Force -File -ErrorAction SilentlyContinue
            $monoFiles = $allProfileFiles | Where-Object {
                $_.Name -like "$($script:ToolName) v*.ps1" -or
                $_.Name -like "$($script:ToolName)*Configuration Tool*.ps1" -or
                $_.Name -eq "$($script:ToolName).exe" -or
                $_.Name -like "$($script:ToolName)*.exe" -or
                $_.Name -eq "RackStack.ps1" -or
                $_.Name -eq "defaults.json" -or
                $_.Name -eq "defaults.example.json" -or
                $_.Name -eq "PSScriptAnalyzerSettings.psd1" -or
                $_.Name -eq "Header.ps1"
            }
            foreach ($f in $monoFiles) { $pathsToDelete.Add($f.FullName) }

            # Single directory traversal for module folders, tool folders, and test folders
            $allProfileDirs = Get-ChildItem -Path $adminFolder -Recurse -Force -Directory -ErrorAction SilentlyContinue
            foreach ($folder in $allProfileDirs) {
                if (Test-Path (Join-Path $folder.FullName "00-Initialization.ps1")) { $pathsToDelete.Add($folder.FullName) }
                elseif ($folder.Name -eq "RackStack") { $pathsToDelete.Add($folder.FullName) }
                elseif ($folder.Name -eq "Tests" -and (Test-Path (Join-Path $folder.FullName "Run-Tests.ps1"))) { $pathsToDelete.Add($folder.FullName) }
            }
        }

        # 2) Also delete the currently-running script and its parent (if modular)
        $currentScriptPath = $script:ScriptPath
        if ($currentScriptPath -and (Test-Path $currentScriptPath)) {
            $pathsToDelete.Add($currentScriptPath)
        }
        # If running modular version, also delete the Modules folder and loader
        if ($script:ModuleRoot) {
            $modulesDir = Join-Path $script:ModuleRoot "Modules"
            if (Test-Path $modulesDir) { $pathsToDelete.Add($modulesDir) }
            $loaderPath = Join-Path $script:ModuleRoot "RackStack.ps1"
            if (Test-Path $loaderPath) { $pathsToDelete.Add($loaderPath) }
            $defaultsPath = Join-Path $script:ModuleRoot "defaults.json"
            if (Test-Path $defaultsPath) { $pathsToDelete.Add($defaultsPath) }
        }

        # Clean up config directory (session logs, audit logs, etc.)
        if ($script:AppConfigDir -and (Test-Path $script:AppConfigDir)) {
            $pathsToDelete.Add($script:AppConfigDir)
        }

        # If running as EXE, also clean up adjacent files
        if ($currentScriptPath -and $currentScriptPath -match '\.exe$') {
            $exeDir = Split-Path $currentScriptPath -Parent
            $adjacentDefaults = Join-Path $exeDir "defaults.json"
            if (Test-Path $adjacentDefaults) { $pathsToDelete.Add($adjacentDefaults) }
            $adjacentExample = Join-Path $exeDir "defaults.example.json"
            if (Test-Path $adjacentExample) { $pathsToDelete.Add($adjacentExample) }
        }

        # Deduplicate paths
        $uniquePaths = $pathsToDelete | Select-Object -Unique

        # Schedule deletion after reboot using a scheduled task
        try {
            # Build cleanup commands for each path
            $cleanupCommands = "Start-Sleep 60`n"
            foreach ($p in $uniquePaths) {
                $escapedPath = $p -replace "'", "''"
                if (Test-Path $p -PathType Container) {
                    $cleanupCommands += "Remove-Item -LiteralPath '$escapedPath' -Recurse -Force -ErrorAction SilentlyContinue`n"
                } else {
                    $cleanupCommands += "Remove-Item -LiteralPath '$escapedPath' -Force -ErrorAction SilentlyContinue`n"
                }
            }
            $toolNameEsc = $script:ToolName -replace "'", "''"
            $cleanupCommands += "Unregister-ScheduledTask -TaskName '$($toolNameEsc)Cleanup' -Confirm:`$false -ErrorAction SilentlyContinue"

            $bytes = [System.Text.Encoding]::Unicode.GetBytes($cleanupCommands)
            $encoded = [Convert]::ToBase64String($bytes)

            $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -EncodedCommand $encoded"
            $trigger = New-ScheduledTaskTrigger -AtStartup
            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
            Register-ScheduledTask -TaskName "$($script:ToolName)Cleanup" -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
        }
        catch {
            Write-OutputColor "Could not schedule cleanup: $_" -color "Warning"
        }

        Restart-Computer -Force
    }
    elseif ($rebootNeeded) {
        if ($windowsRebootPending -and -not $global:RebootNeeded) {
            Write-OutputColor "Windows has a pending reboot (from previous changes)." -color "Warning"
        }
        else {
            Write-OutputColor "Changes made during this session require a reboot." -color "Warning"
        }

        if (Confirm-UserAction -Message "Reboot now to apply changes?") {
            Write-OutputColor "Rebooting the server..." -color "Warning"
            Start-Sleep -Seconds 3
            Restart-Computer -Force
        }
        else {
            Write-OutputColor "Remember to reboot later to apply all changes!" -color "Warning"
            Start-Sleep -Seconds 3
            [Environment]::Exit(0)
        }
    }
    else {
        Write-OutputColor "No reboot needed. Exiting script..." -color "Success"
        Start-Sleep -Seconds 2
        [Environment]::Exit(0)
    }
}
#endregion
