#region ===== EXIT AND CLEANUP =====
# Function to exit the script with optional reboot and file cleanup
function Exit-Script {
    # Wrap cleanup in try/finally so an exception in Show-SessionSummary or any
    # interactive prompt doesn't bypass credential disposal and transcript-stop.
    try {
        # Save session state for potential resume (v2.8.0)
        if ($script:VMDeploymentQueue -and $script:VMDeploymentQueue.Count -gt 0) {
            Save-SessionState
        }
    } catch { }

    try {
        # Defense-in-depth: release any SecureString credentials held in script scope
        # so they don't linger in memory longer than necessary. Cover every credential
        # field the tool is known to populate during a session.
        $credFields = @('VMDeploymentCredential','DomainJoinCredential','LocalAdminCredential','AgentInstallCredential','DSRMCredential')
        foreach ($field in $credFields) {
            $val = Get-Variable -Scope Script -Name $field -ValueOnly -ErrorAction SilentlyContinue
            if ($null -ne $val) {
                try { if ($val.Password) { $val.Password.Dispose() } } catch { }
                Set-Variable -Scope Script -Name $field -Value $null -ErrorAction SilentlyContinue
            }
        }
    } catch { }

    # Clean up temporary session files
    try {
        $stateFile = Join-Path $script:TempPath "session-state.json"
        if (Test-Path -LiteralPath $stateFile) {
            Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue
        }

        $undoFile = Join-Path $script:TempPath "batch-undo.json"
        if (Test-Path -LiteralPath $undoFile) {
            Remove-Item -LiteralPath $undoFile -Force -ErrorAction SilentlyContinue
        }
    } catch { }

    # Show session summary first (wrapped so any rendering failure doesn't skip the rest)
    try { Show-SessionSummary } catch { }

    # Notify about old transcript files
    try {
        if ($null -ne $script:TempPath -and (Test-Path -LiteralPath $script:TempPath)) {
            $oldTranscripts = @(Get-ChildItem -LiteralPath $script:TempPath -Filter '*.log' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) })
            if ($oldTranscripts.Count -gt 0) {
                Write-OutputColor "  Tip: $($oldTranscripts.Count) transcript(s) older than 30 days in $($script:TempPath)" -color "Info"
            }
        }
    } catch { }

    # Explicitly stop the transcript so a Restart-Computer doesn't truncate it.
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }

    # Skip the interactive "Press Enter" prompt under non-interactive callers
    # (Silent / batch / headless / scripted / `irm | iex` pipelines).
    if (-not $script:CLISilent -and -not $script:NonInteractive -and -not $script:CLIQuiet) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Press Enter to continue to exit..." -color "Info"
        try { Read-Host | Out-Null } catch { }
    }

    Clear-Host
    Write-CenteredOutput "Script Exiting" -color "Info"

    # Check for actual Windows pending reboot OR our flag
    $windowsRebootPending = Test-RebootPending
    $rebootNeeded = $global:RebootNeeded -or $windowsRebootPending

    if ($global:DisabledAdminReboot -eq $true) {
        # Pre-flight: refuse to self-destruct while Hyper-V VMs are mid-migrate or storage ops
        # are in flight. Restart-Computer -Force only suppresses the logged-on-user prompt; it
        # doesn't wait for in-progress vmms operations to drain, so a Ctrl-C → exit during a
        # live migration leaves the VM in an unrecoverable state.
        try {
            $migratingVMs = @(Get-VM -ErrorAction SilentlyContinue | Where-Object {
                $_.Status -match 'Migrating|Saving|Pending' -or $_.State -eq 'Migrating'
            })
            if ($migratingVMs.Count -gt 0) {
                Write-OutputColor "" -color "Error"
                Write-OutputColor "  REFUSING self-destruct: $($migratingVMs.Count) VM(s) in transitional state:" -color "Error"
                foreach ($vm in $migratingVMs) {
                    Write-OutputColor "    - $($vm.Name) [$($vm.State) / $($vm.Status)]" -color "Error"
                }
                Write-OutputColor "  Wait for VMs to settle before exiting." -color "Warning"
                Write-PressEnter
                return
            }
        } catch { }

        Write-OutputColor "" -color "Critical"
        Write-OutputColor "  WARNING: about to schedule a post-reboot SYSTEM deletion of tool files." -color "Critical"
        Write-OutputColor "  This is a destructive operation that cannot be undone after reboot." -color "Warning"
        Write-OutputColor "  Type the computer name '$env:COMPUTERNAME' to confirm:" -color "Critical"
        $hostConfirm = Read-Host
        if ($hostConfirm -ne $env:COMPUTERNAME) {
            Write-OutputColor "  Cancelled (hostname did not match)." -color "Info"
            return
        }

        Write-OutputColor "  As always, should you or any member of your IT Force be caught or killed, the Abider will disavow any knowledge of your actions" -color "Error"

        for ($i = 5; $i -gt 0; $i--) {
            Write-Host "`r  This script will now self destruct in $i seconds   " -ForegroundColor Red -NoNewline
            Start-Sleep -Seconds 1
        }
        Write-Host ""

        Write-OutputColor "  Good luck." -color "Error"

        # Build list of paths to delete. Narrowed heuristics: only target folders whose path
        # contains $script:ToolName literally so sibling Pester repos / customer migration
        # scripts / third-party tooling that happens to contain a 00-Initialization.ps1 or a
        # generic Tests/ folder aren't wiped along with us.
        $pathsToDelete = [System.Collections.Generic.List[string]]::new()
        $adminFolder = [System.IO.Path]::Combine($env:SystemDrive, "Users", "Administrator")
        $toolName = $script:ToolName

        if (Test-Path -LiteralPath $adminFolder) {
            $allProfileFiles = Get-ChildItem -LiteralPath $adminFolder -Recurse -Force -File -ErrorAction SilentlyContinue
            $monoFiles = $allProfileFiles | Where-Object {
                ($_.Name -like "$toolName v*.ps1") -or
                ($_.Name -like "$toolName*Configuration Tool*.ps1") -or
                ($_.Name -eq "$toolName.exe") -or
                ($_.Name -like "$toolName*.exe") -or
                # Only treat the listed config files as ours when they sit inside a directory
                # whose path contains the tool name — protects unrelated dev work in other repos.
                ((($_.Name -eq "RackStack.ps1") -or ($_.Name -eq "defaults.json") -or ($_.Name -eq "defaults.example.json") -or ($_.Name -eq "PSScriptAnalyzerSettings.psd1") -or ($_.Name -eq "Header.ps1")) -and ($_.DirectoryName -like "*$toolName*"))
            }
            foreach ($f in $monoFiles) { $pathsToDelete.Add($f.FullName) }

            $allProfileDirs = Get-ChildItem -LiteralPath $adminFolder -Recurse -Force -Directory -ErrorAction SilentlyContinue
            foreach ($folder in $allProfileDirs) {
                # Only delete folders whose path explicitly contains the tool name. The prior
                # heuristic "any folder containing 00-Initialization.ps1" caught unrelated
                # PowerShell projects (Pester fixtures, customer migration scripts) and
                # "any folder named Tests" caught literally every Tests folder under the profile.
                if ($folder.FullName -notlike "*$toolName*") { continue }
                if (Test-Path -LiteralPath (Join-Path $folder.FullName "00-Initialization.ps1")) { $pathsToDelete.Add($folder.FullName) }
                elseif ($folder.Name -eq $toolName) { $pathsToDelete.Add($folder.FullName) }
                elseif ($folder.Name -eq "Tests" -and (Test-Path -LiteralPath (Join-Path $folder.FullName "Run-Tests.ps1"))) { $pathsToDelete.Add($folder.FullName) }
            }
        }

        $currentScriptPath = $script:ScriptPath
        if ($currentScriptPath -and (Test-Path -LiteralPath $currentScriptPath)) {
            $pathsToDelete.Add($currentScriptPath)
        }
        if ($script:ModuleRoot) {
            $modulesDir = Join-Path $script:ModuleRoot "Modules"
            if (Test-Path -LiteralPath $modulesDir) { $pathsToDelete.Add($modulesDir) }
            $loaderPath = Join-Path $script:ModuleRoot "RackStack.ps1"
            if (Test-Path -LiteralPath $loaderPath) { $pathsToDelete.Add($loaderPath) }
            $defaultsPath = Join-Path $script:ModuleRoot "defaults.json"
            if (Test-Path -LiteralPath $defaultsPath) { $pathsToDelete.Add($defaultsPath) }
        }

        # AppConfigDir cleanup — only if the directory's path matches the tool name (defensive
        # check; AppConfigDir is configured at init and shouldn't drift, but a wrong defaults.json
        # value pointing at C:\ would otherwise wipe everything).
        if ($script:AppConfigDir -and (Test-Path -LiteralPath $script:AppConfigDir) -and $script:AppConfigDir -like "*$($script:ConfigDirName)*") {
            $pathsToDelete.Add($script:AppConfigDir)
        }

        if ($currentScriptPath -and $currentScriptPath -match '\.exe$') {
            $exeDir = Split-Path $currentScriptPath -Parent
            $adjacentDefaults = Join-Path $exeDir "defaults.json"
            if (Test-Path -LiteralPath $adjacentDefaults) { $pathsToDelete.Add($adjacentDefaults) }
            $adjacentExample = Join-Path $exeDir "defaults.example.json"
            if (Test-Path -LiteralPath $adjacentExample) { $pathsToDelete.Add($adjacentExample) }
        }

        $uniquePaths = @($pathsToDelete | Sort-Object -Unique)

        # Write a manifest of what's about to be deleted — forensic recovery aid in case the
        # operator realizes mid-reboot they meant to disable on a different host. Also log to
        # the Application event log so an audit trail survives the file deletion.
        try {
            $manifestPath = Join-Path $env:TEMP "$toolName-cleanup-manifest.txt"
            $manifestLines = @("# $toolName self-destruct manifest", "# Host: $env:COMPUTERNAME", "# Scheduled at: $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')", "")
            $manifestLines += $uniquePaths
            $manifestLines | Out-File -LiteralPath $manifestPath -Encoding UTF8 -Force
            Write-OutputColor "  Deletion manifest saved to: $manifestPath" -color "Info"
        } catch {
            Write-OutputColor "  Could not write deletion manifest: $($_.Exception.Message)" -color "Warning"
        }
        try {
            $evtMsg = "$toolName self-destruct scheduled. Host=$env:COMPUTERNAME. $($uniquePaths.Count) path(s) queued for deletion on next boot."
            Write-EventLog -LogName Application -Source $toolName -EventId 9999 -EntryType Warning -Message $evtMsg -ErrorAction SilentlyContinue
        } catch {
            try { New-EventLog -LogName Application -Source $toolName -ErrorAction SilentlyContinue } catch { }
        }

        # Schedule deletion after reboot using a scheduled task
        try {
            $cleanupCommands = "Start-Sleep 60`n"
            foreach ($p in $uniquePaths) {
                $escapedPath = $p -replace "'", "''"
                $cleanupCommands += "Remove-Item -LiteralPath '$escapedPath' -Recurse -Force -ErrorAction SilentlyContinue`n"
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
            Write-OutputColor "  Could not schedule cleanup: $_" -color "Error"
        }

        Clear-Host
        Restart-Computer -Force
    }
    elseif ($rebootNeeded) {
        if ($windowsRebootPending -and -not $global:RebootNeeded) {
            Write-OutputColor "  Windows has a pending reboot (from previous changes)." -color "Warning"
        }
        else {
            Write-OutputColor "  Changes made during this session require a reboot." -color "Warning"
        }

        if (Confirm-UserAction -Message "Reboot now to apply changes?") {
            Write-OutputColor "  Rebooting the server..." -color "Warning"
            Start-Sleep -Seconds 3
            Restart-Computer -Force
        }
        else {
            Write-OutputColor "  Remember to reboot later to apply all changes!" -color "Warning"
            Start-Sleep -Seconds 3
            [Environment]::Exit(0)
        }
    }
    else {
        Write-OutputColor "  No reboot needed. Exiting script..." -color "Success"
        Start-Sleep -Seconds 2
        [Environment]::Exit(0)
    }
}
#endregion
