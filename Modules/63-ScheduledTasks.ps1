#region ===== SCHEDULED TASK MANAGER =====
# Functions for viewing, managing, and exporting Windows Scheduled Tasks

function Show-TaskHealthStatus {
    try {
        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notlike '\Microsoft\*' }

        if ($null -eq $tasks -or @($tasks).Count -eq 0) {
            Write-OutputColor "  No custom scheduled tasks found" -color "Info"
            return
        }

        Write-OutputColor "`n  Scheduled Task Health:" -color "Info"

        $failedCount = 0
        foreach ($task in $tasks) {
            $info = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
            $lastResult = if ($null -ne $info) { $info.LastTaskResult } else { -1 }
            $lastRun = if ($null -ne $info -and $null -ne $info.LastRunTime -and $info.LastRunTime -ne [datetime]::MinValue) {
                $info.LastRunTime.ToString('yyyy-MM-dd HH:mm')
            } else { "Never" }
            $nextRun = if ($null -ne $info -and $null -ne $info.NextRunTime -and $info.NextRunTime -gt (Get-Date)) {
                $info.NextRunTime.ToString('yyyy-MM-dd HH:mm')
            } else { "" }

            $taskName = if ($task.TaskName.Length -gt 30) { $task.TaskName.Substring(0, 27) + "..." } else { $task.TaskName }

            $color = "Success"
            $status = "OK"
            if ($lastResult -ne 0 -and $lastResult -ne 267009) {  # 267009 = task is running
                $color = "Error"
                $status = "FAILED (0x$($lastResult.ToString('X')))"
                $failedCount++
            } elseif ($lastResult -eq 267009) {
                $color = "Warning"
                $status = "Running"
            }

            Write-OutputColor "  $taskName  Last: $lastRun  $status" -color $color
        }

        Write-OutputColor "`n  Total: $(@($tasks).Count) active tasks, $failedCount failed" -color "Info"
    } catch {
        Write-OutputColor "  Could not check scheduled tasks: $($_.Exception.Message)" -color "Error"
    }
}

function Show-ScheduledTaskManager {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                     SCHEDULED TASK MANAGER").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-MenuItem "[1]  View All Scheduled Tasks"
        Write-MenuItem "[2]  View Running Tasks"
        Write-MenuItem "[3]  View Failed Tasks (Last Run Result ≠ 0)"
        Write-MenuItem "[4]  Search Tasks by Name"
        Write-MenuItem "[5]  Enable / Disable Task"
        Write-MenuItem "[6]  Run Task Now"
        Write-MenuItem "[7]  Export Task to XML"
        Write-MenuItem "[8]  Import Task from XML"
        Write-MenuItem "[9]  Task Health Status"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) {
            if (Invoke-NavigationAction -NavResult $navResult) { return }
            return
        }

        switch ($choice) {
            "1" { Show-AllScheduledTasks; Write-PressEnter }
            "2" { Show-RunningTasks; Write-PressEnter }
            "3" { Show-FailedTasks; Write-PressEnter }
            "4" { Search-ScheduledTasks; Write-PressEnter }
            "5" { Set-ScheduledTaskState; Write-PressEnter }
            "6" { Invoke-ScheduledTaskNow; Write-PressEnter }
            "7" { Export-ScheduledTaskXML; Write-PressEnter }
            "8" { Import-ScheduledTaskXML; Write-PressEnter }
            "9" {
                Clear-Host
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
                Write-OutputColor "  ║$(("                      TASK HEALTH STATUS").PadRight(72))║" -color "Info"
                Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
                Write-OutputColor "" -color "Info"
                Show-TaskHealthStatus
                Write-PressEnter
            }
            { $_ -eq "B" -or $_ -eq "b" } { return }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-9 or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Helper: Get all tasks with error handling
function Get-ScheduledTaskSafe {
    param([string]$TaskPath = "\*")
    try {
        @(Get-ScheduledTask -TaskPath $TaskPath -ErrorAction Stop | Where-Object {
            # Exclude Microsoft system tasks by default for cleaner display
            $_.TaskPath -notmatch '^\\Microsoft\\'
        } | Sort-Object TaskName)
    }
    catch {
        Write-OutputColor "  Error retrieving scheduled tasks: $_" -color "Error"
        @()
    }
}

# Helper: Format last run result code to friendly message
function Format-TaskResult {
    param([int]$ResultCode)
    switch ($ResultCode) {
        0          { "Success" }
        1          { "Incorrect function" }
        2          { "File not found" }
        10         { "Environment incorrect" }
        0x00041300 { "Ready (never run)" }
        0x00041301 { "Currently running" }
        0x00041302 { "Disabled" }
        0x00041303 { "Not yet run" }
        0x00041304 { "No more runs" }
        0x00041306 { "Terminated by user" }
        0x8004130F { "Credentials required" }
        0x80070005 { "Access denied" }
        0x800710E0 { "Operator/user rejected" }
        default    { "0x{0:X8}" -f $ResultCode }
    }
}

# View all scheduled tasks (excluding Microsoft system tasks)
function Show-AllScheduledTasks {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     ALL SCHEDULED TASKS").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Include Microsoft system tasks? [Y/N] (default: N):" -color "Info"
    $includeMs = Read-Host "  "
    $navResult = Test-NavigationCommand -UserInput $includeMs
    if ($navResult.ShouldReturn) { return }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Loading tasks..." -color "Info"

    try {
        $allTasks = @(Get-ScheduledTask -ErrorAction Stop)
        if ($includeMs -ne "Y" -and $includeMs -ne "y") {
            $allTasks = @($allTasks | Where-Object { $_.TaskPath -notmatch '^\\Microsoft\\' })
        }
        $allTasks = @($allTasks | Sort-Object TaskPath, TaskName)
    }
    catch {
        Write-OutputColor "  Error retrieving tasks: $_" -color "Error"
        return
    }

    if ($allTasks.Count -eq 0) {
        Write-OutputColor "  No scheduled tasks found." -color "Warning"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    $header = "  Task Name".PadRight(38) + "State".PadRight(12) + "Last Result"
    Write-OutputColor "  │$($header.PadRight(72))│" -color "Warning"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $currentPath = ""
    foreach ($task in $allTasks) {
        # Show path header when it changes
        if ($task.TaskPath -ne $currentPath) {
            $currentPath = $task.TaskPath
            $pathLine = "  $currentPath"
            if ($pathLine.Length -gt 70) { $pathLine = $pathLine.Substring(0, 67) + "..." }
            Write-OutputColor "  │$($pathLine.PadRight(72))│" -color "Info"
        }

        try {
            $info = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
            $lastResult = if ($null -ne $info) { Format-TaskResult -ResultCode $info.LastTaskResult } else { "N/A" }
            $nextRunStr = if ($null -ne $info -and $null -ne $info.NextRunTime -and $info.NextRunTime -gt (Get-Date)) {
                $info.NextRunTime.ToString('MM/dd HH:mm')
            } else { "" }
        }
        catch { $lastResult = "N/A"; $nextRunStr = "" }

        $name = $task.TaskName
        if ($name.Length -gt 34) { $name = $name.Substring(0, 31) + "..." }
        $state = if ($null -ne $task.State) { $task.State.ToString() } else { "Unknown" }

        $stateColor = switch ($state) {
            "Ready"    { "Success" }
            "Running"  { "Warning" }
            "Disabled" { "Error" }
            default    { "Info" }
        }

        $resultColor = if ($lastResult -eq "Success" -or $lastResult -eq "Ready (never run)" -or $lastResult -eq "Currently running" -or $lastResult -eq "Not yet run") { "Success" } else { "Error" }
        if ($lastResult -eq "N/A") { $resultColor = "Info" }

        $line = "    $($name.PadRight(34))$($state.PadRight(12))$lastResult"
        if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($line.PadRight(72))│" -color $stateColor
    }

    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Total: $($allTasks.Count) tasks".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

# View currently running tasks
function Show-RunningTasks {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                      RUNNING TASKS").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $running = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.State -eq 'Running' } | Sort-Object TaskName)
    }
    catch {
        Write-OutputColor "  Error retrieving tasks: $_" -color "Error"
        return
    }

    if ($running.Count -eq 0) {
        Write-OutputColor "  No tasks are currently running." -color "Success"
        return
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    $header = "  Task Name".PadRight(42) + "Path"
    Write-OutputColor "  │$($header.PadRight(72))│" -color "Warning"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    foreach ($task in $running) {
        $name = $task.TaskName
        if ($name.Length -gt 38) { $name = $name.Substring(0, 35) + "..." }
        $path = $task.TaskPath
        if ($path.Length -gt 28) { $path = $path.Substring(0, 25) + "..." }
        $line = "  $($name.PadRight(40))$path"
        Write-OutputColor "  │$($line.PadRight(72))│" -color "Warning"
    }

    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  $($running.Count) task(s) running".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

# View tasks with non-zero last run result
function Show-FailedTasks {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                   TASKS WITH NON-ZERO RESULT").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Loading tasks..." -color "Info"

    try {
        $allTasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
            $_.TaskPath -notmatch '^\\Microsoft\\' -and $_.State -ne 'Disabled'
        })
    }
    catch {
        Write-OutputColor "  Error retrieving tasks: $_" -color "Error"
        return
    }

    $failed = [System.Collections.Generic.List[object]]::new()
    foreach ($task in $allTasks) {
        try {
            $info = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
            if ($null -ne $info -and $info.LastTaskResult -ne 0 -and $info.LastTaskResult -ne 0x00041300 -and $info.LastTaskResult -ne 0x00041303) {
                $failed.Add(@{
                    Name = $task.TaskName
                    Path = $task.TaskPath
                    Result = $info.LastTaskResult
                    LastRun = $info.LastRunTime
                })
            }
        } catch { $null = $_ }
    }

    Write-OutputColor "" -color "Info"

    if ($failed.Count -eq 0) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Success"
        Write-OutputColor "  │$("  All enabled non-system tasks have clean results.".PadRight(72))│" -color "Success"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Success"
        return
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    $header = "  Task Name".PadRight(32) + "Last Run".PadRight(18) + "Result"
    Write-OutputColor "  │$($header.PadRight(72))│" -color "Warning"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    foreach ($f in $failed) {
        $name = $f.Name
        if ($name.Length -gt 28) { $name = $name.Substring(0, 25) + "..." }
        $lastRun = if ($null -ne $f.LastRun -and $f.LastRun -gt [datetime]::MinValue) { $f.LastRun.ToString("MM/dd/yy HH:mm") } else { "Never" }
        $result = Format-TaskResult -ResultCode $f.Result
        if ($result.Length -gt 20) { $result = $result.Substring(0, 17) + "..." }
        $line = "  $($name.PadRight(30))$($lastRun.PadRight(18))$result"
        Write-OutputColor "  │$($line.PadRight(72))│" -color "Error"
    }

    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  $($failed.Count) task(s) with non-zero results".PadRight(72))│" -color "Error"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

# Search tasks by name keyword
function Search-ScheduledTasks {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                      SEARCH TASKS").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Enter search keyword:" -color "Info"
    $keyword = Read-Host "  "
    $navResult = Test-NavigationCommand -UserInput $keyword
    if ($navResult.ShouldReturn) { return }

    if ([string]::IsNullOrWhiteSpace($keyword)) {
        Write-OutputColor "  No keyword entered." -color "Error"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Searching..." -color "Info"

    try {
        $matches_ = @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
            $_.TaskName -like "*$keyword*" -or $_.TaskPath -like "*$keyword*"
        } | Sort-Object TaskPath, TaskName)
    }
    catch {
        Write-OutputColor "  Error searching tasks: $_" -color "Error"
        return
    }

    if ($matches_.Count -eq 0) {
        Write-OutputColor "  No tasks found matching '$keyword'." -color "Warning"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  RESULTS FOR: $keyword".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    foreach ($task in $matches_) {
        $name = $task.TaskName
        if ($name.Length -gt 34) { $name = $name.Substring(0, 31) + "..." }
        $state = if ($null -ne $task.State) { $task.State.ToString() } else { "Unknown" }
        $path = $task.TaskPath
        if ($path.Length -gt 24) { $path = $path.Substring(0, 21) + "..." }
        $line = "  $($name.PadRight(34))$($state.PadRight(12))$path"
        $stateColor = if ($state -eq "Ready") { "Success" } elseif ($state -eq "Running") { "Warning" } else { "Error" }
        Write-OutputColor "  │$($line.PadRight(72))│" -color $stateColor
    }

    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  $($matches_.Count) task(s) found".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

# Enable or disable a scheduled task
function Set-ScheduledTaskState {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                   ENABLE / DISABLE TASK").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $tasks = @(Get-ScheduledTaskSafe)
    if ($tasks.Count -eq 0) {
        Write-OutputColor "  No non-system tasks found." -color "Warning"
        return
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    $header = "  #".PadRight(6) + "Task Name".PadRight(40) + "State"
    Write-OutputColor "  │$($header.PadRight(72))│" -color "Warning"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $taskMap = @{}
    $idx = 1
    foreach ($task in $tasks) {
        $name = $task.TaskName
        if ($name.Length -gt 36) { $name = $name.Substring(0, 33) + "..." }
        $state = if ($null -ne $task.State) { $task.State.ToString() } else { "Unknown" }
        $stateColor = if ($state -eq "Ready") { "Success" } elseif ($state -eq "Running") { "Warning" } else { "Error" }
        $line = "  [$idx]".PadRight(6) + "$($name.PadRight(40))$state"
        Write-OutputColor "  │$($line.PadRight(72))│" -color $stateColor
        $taskMap["$idx"] = $task
        $idx++
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $taskChoice = Read-Host "  Enter task number"
    $navResult = Test-NavigationCommand -UserInput $taskChoice
    if ($navResult.ShouldReturn) { return }

    if (-not $taskMap.ContainsKey($taskChoice)) {
        Write-OutputColor "  Invalid selection. Enter 1-$($idx - 1)." -color "Error"
        return
    }

    $selected = $taskMap[$taskChoice]
    $currentState = $selected.State.ToString()
    $action = if ($currentState -eq "Disabled") { "Enable" } else { "Disable" }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Task: $($selected.TaskName)" -color "Info"
    Write-OutputColor "  Current state: $currentState" -color "Info"
    Write-OutputColor "  Action: $action" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "$action this task?")) { return }

    try {
        if ($action -eq "Enable") {
            $selected | Enable-ScheduledTask -ErrorAction Stop | Out-Null
        } else {
            $selected | Disable-ScheduledTask -ErrorAction Stop | Out-Null
        }
        Write-OutputColor "  Task ${action}d successfully." -color "Success"
        Add-SessionChange -Category "System" -Description "${action}d scheduled task '$($selected.TaskName)'"
        Clear-MenuCache
        $reverseAction = if ($action -eq "Enable") { "Disable" } else { "Enable" }
        Add-UndoAction -Category "System" -Description "${action}d scheduled task '$($selected.TaskName)'" -UndoScript {
            param($TaskPath, $TaskName, $Reverse)
            if ($Reverse -eq "Disable") {
                Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue
            } else {
                Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue | Enable-ScheduledTask -ErrorAction SilentlyContinue
            }
        }.GetNewClosure() -UndoParams @{ TaskPath = $selected.TaskPath; TaskName = $selected.TaskName; Reverse = $reverseAction }
    }
    catch {
        Write-OutputColor "  Error: $_" -color "Error"
    }
}

# Run a task immediately
function Invoke-ScheduledTaskNow {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                       RUN TASK NOW").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $tasks = @(Get-ScheduledTaskSafe)
    $readyTasks = @($tasks | Where-Object { $_.State -eq 'Ready' })

    if ($readyTasks.Count -eq 0) {
        Write-OutputColor "  No ready tasks available to run." -color "Warning"
        return
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT TASK TO RUN".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $taskMap = @{}
    $idx = 1
    foreach ($task in $readyTasks) {
        $name = $task.TaskName
        if ($name.Length -gt 60) { $name = $name.Substring(0, 57) + "..." }
        Write-OutputColor "  │$("  [$idx]  $name".PadRight(72))│" -color "Info"
        $taskMap["$idx"] = $task
        $idx++
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $taskChoice = Read-Host "  Enter task number"
    $navResult = Test-NavigationCommand -UserInput $taskChoice
    if ($navResult.ShouldReturn) { return }

    if (-not $taskMap.ContainsKey($taskChoice)) {
        Write-OutputColor "  Invalid selection. Enter 1-$($idx - 1)." -color "Error"
        return
    }

    $selected = $taskMap[$taskChoice]
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Task: $($selected.TaskName)" -color "Info"
    Write-OutputColor "  Path: $($selected.TaskPath)" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Run this task now?")) { return }

    try {
        $selected | Start-ScheduledTask -ErrorAction Stop
        Write-OutputColor "  Task started successfully." -color "Success"
        Add-SessionChange -Category "System" -Description "Ran scheduled task '$($selected.TaskName)'"
        Clear-MenuCache
    }
    catch {
        Write-OutputColor "  Error starting task: $_" -color "Error"
    }
}

# Export a task to XML
function Export-ScheduledTaskXML {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     EXPORT TASK TO XML").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $tasks = @(Get-ScheduledTaskSafe)
    if ($tasks.Count -eq 0) {
        Write-OutputColor "  No non-system tasks found." -color "Warning"
        return
    }

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT TASK TO EXPORT".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $taskMap = @{}
    $idx = 1
    foreach ($task in $tasks) {
        $name = $task.TaskName
        if ($name.Length -gt 60) { $name = $name.Substring(0, 57) + "..." }
        Write-OutputColor "  │$("  [$idx]  $name".PadRight(72))│" -color "Info"
        $taskMap["$idx"] = $task
        $idx++
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $taskChoice = Read-Host "  Enter task number"
    $navResult = Test-NavigationCommand -UserInput $taskChoice
    if ($navResult.ShouldReturn) { return }

    if (-not $taskMap.ContainsKey($taskChoice)) {
        Write-OutputColor "  Invalid selection. Enter 1-$($idx - 1)." -color "Error"
        return
    }

    $selected = $taskMap[$taskChoice]

    # Default export path
    $defaultPath = if ($script:AppConfigDir) { $script:AppConfigDir } else { Join-Path $env:USERPROFILE "Desktop" }
    $safeName = $selected.TaskName -replace '[\\/:*?"<>|]', '_'
    $defaultFile = Join-Path $defaultPath "${safeName}.xml"

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Export path (Enter for default: $defaultFile):" -color "Info"
    $exportPath = Read-Host "  "
    $navResult = Test-NavigationCommand -UserInput $exportPath
    if ($navResult.ShouldReturn) { return }
    if (-not [string]::IsNullOrWhiteSpace($exportPath)) { $exportPath = $exportPath.Trim('"') }
    if ([string]::IsNullOrWhiteSpace($exportPath)) { $exportPath = $defaultFile }

    # Ensure parent directory exists
    $parentDir = Split-Path $exportPath -Parent
    if (-not (Test-Path -LiteralPath $parentDir)) {
        try {
            $null = New-Item -Path $parentDir -ItemType Directory -Force -ErrorAction Stop
        }
        catch {
            Write-OutputColor "  Failed to create directory: $_" -color "Error"
            return
        }
    }

    try {
        $xml = Export-ScheduledTask -TaskName $selected.TaskName -TaskPath $selected.TaskPath -ErrorAction Stop
        # Atomic write-then-rename. A direct WriteAllText could leave a partial XML if the
        # process was killed mid-write; the operator might then re-import the corrupt file
        # and register a half-defined scheduled task (or fail with a cryptic XML parse error).
        $tmpExport = "$exportPath.tmp"
        try {
            [System.IO.File]::WriteAllText($tmpExport, $xml, [System.Text.UTF8Encoding]::new($true))
            Move-Item -LiteralPath $tmpExport -Destination $exportPath -Force -ErrorAction Stop
        } catch {
            if (Test-Path -LiteralPath $tmpExport) { Remove-Item -LiteralPath $tmpExport -Force -ErrorAction SilentlyContinue }
            throw
        }
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Task exported successfully!" -color "Success"
        Write-OutputColor "  File: $exportPath" -color "Info"
        Add-SessionChange -Category "System" -Description "Exported scheduled task '$($selected.TaskName)' to $exportPath"
    }
    catch {
        Write-OutputColor "  Error exporting task: $_" -color "Error"
    }
}

# Import a task from XML
function Import-ScheduledTaskXML {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    IMPORT TASK FROM XML").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Enter path to XML file:" -color "Info"
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
        Write-OutputColor "  File not found: $importPath" -color "Error"
        return
    }

    try {
        $xml = [System.IO.File]::ReadAllText($importPath)
    }
    catch {
        Write-OutputColor "  Error reading file: $_" -color "Error"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enter task name (or Enter to use filename):" -color "Info"
    $taskName = Read-Host "  "
    $navResult = Test-NavigationCommand -UserInput $taskName
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($taskName)) {
        $taskName = [System.IO.Path]::GetFileNameWithoutExtension($importPath)
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Task folder path (Enter for root '\'):" -color "Info"
    $taskPath = Read-Host "  "
    $navResult = Test-NavigationCommand -UserInput $taskPath
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($taskPath)) { $taskPath = "\" }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Task name: $taskName" -color "Info"
    Write-OutputColor "  Task path: $taskPath" -color "Info"
    Write-OutputColor "  Source: $importPath" -color "Info"
    Write-OutputColor "" -color "Info"

    # Pre-flight: surface what the task is actually going to do before the operator
    # commits. Task XML can name LocalSystem as Principal and run arbitrary commands,
    # so display the Actions and Principal blocks (parsed with XmlResolver disabled to
    # block external-entity expansion) and require explicit confirmation.
    try {
        $xmlDoc = New-Object System.Xml.XmlDocument
        $xmlDoc.XmlResolver = $null
        $xmlDoc.LoadXml($xml)
        $ns = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
        $ns.AddNamespace('t', 'http://schemas.microsoft.com/windows/2004/02/mit/task')
        $principalNodes = @($xmlDoc.SelectNodes('//t:Principal', $ns))
        $actionNodes    = @($xmlDoc.SelectNodes('//t:Actions/*', $ns))
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Task will run as:" -color "Warning"
        if ($principalNodes.Count -eq 0) {
            Write-OutputColor "    (no <Principal> block — defaults to the current user context)" -color "Info"
        } else {
            foreach ($p in $principalNodes) {
                $userId  = $p.SelectSingleNode('t:UserId',  $ns)
                $groupId = $p.SelectSingleNode('t:GroupId', $ns)
                $runLvl  = $p.SelectSingleNode('t:RunLevel', $ns)
                $who = if ($userId) { $userId.InnerText } elseif ($groupId) { $groupId.InnerText } else { '(unknown)' }
                $lvl = if ($runLvl) { $runLvl.InnerText } else { 'LeastPrivilege' }
                Write-OutputColor "    Identity: $who   RunLevel: $lvl" -color "Warning"
            }
        }
        Write-OutputColor "  Actions:" -color "Warning"
        if ($actionNodes.Count -eq 0) {
            Write-OutputColor "    (no <Actions> declared — task will not do anything)" -color "Info"
        } else {
            foreach ($a in $actionNodes) {
                $cmd      = $a.SelectSingleNode('t:Command',   $ns)
                $taskArgs = $a.SelectSingleNode('t:Arguments', $ns)
                $line = "    $($a.LocalName): $(if ($cmd) { $cmd.InnerText } else { '' }) $(if ($taskArgs) { $taskArgs.InnerText } else { '' })"
                if ($line.Length -gt 100) { $line = $line.Substring(0, 97) + "..." }
                Write-OutputColor $line -color "Warning"
            }
        }
        Write-OutputColor "" -color "Info"
    } catch {
        Write-OutputColor "  Could not parse task XML for review: $($_.Exception.Message)" -color "Error"
        Write-OutputColor "  Refusing to import an XML file that won't parse." -color "Error"
        return
    }

    if (-not (Confirm-UserAction -Message "Import this task?")) { return }

    try {
        # Check if task already exists and offer overwrite
        $existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
        if ($null -ne $existingTask) {
            Write-OutputColor "  A task named '$taskName' already exists at $taskPath." -color "Warning"
            if (Confirm-UserAction -Message "Overwrite existing task?") {
                Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Xml $xml -Force -ErrorAction Stop | Out-Null
            } else {
                Write-OutputColor "  Import cancelled." -color "Info"
                return
            }
        } else {
            Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Xml $xml -ErrorAction Stop | Out-Null
        }
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Task imported successfully!" -color "Success"
        Write-OutputColor "  Name: $taskName" -color "Info"
        Write-OutputColor "  Path: $taskPath" -color "Info"
        Add-SessionChange -Category "System" -Description "Imported scheduled task '$taskName' from $importPath"
        Clear-MenuCache
    }
    catch {
        Write-RackStackError -Code "RS-7006" -Detail "Scheduled task registration failed for '$taskName': $($_.Exception.Message)"
        Write-OutputColor "  Error importing task: $_" -color "Error"
    }
}
#endregion
