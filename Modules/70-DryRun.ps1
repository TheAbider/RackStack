#region ===== INTERACTIVE DRY-RUN MODE =====
# Interactive Dry-Run is a session-wide mode where every configuration
# action is captured as a structured step instead of being applied
# immediately. Steps accumulate in a queue, each one is preflight-checked
# (green or red), and the operator commits the queue with one of two
# buttons:
#   * Apply All (atomic)   — rerun every preflight, then execute the
#                            whole queue sequentially. On any failure,
#                            roll back the steps that already succeeded
#                            (using each step's captured Undo scriptblock).
#   * Step-by-Step         — walk the queue interactively, confirm each
#                            step, apply, and continue. Failures stop
#                            advancement but already-applied steps stay
#                            applied (operator decides whether to revert).
#
# Some operations are inherently one-way (DC promo, BitLocker enable,
# disk format, AD CS CA config, Arc/MDE onboarding, Storage Migration
# cutover, password changes). Those carry the OneWay flag and surface
# a red "ONE-WAY" badge in the queue view so the operator sees up front
# which entries cannot be pulled back from after Commit.
#
# Re-entrancy: when Commit runs, $script:ApplyingDryRunQueue is set to
# $true so that the Apply scriptblocks (which call back into the same
# interactive functions) bypass the queueing gate and execute their
# real work. This is the pattern interactive callers use:
#
#   if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
#       Push-DryRunStep -Label "..." -Category "..." -OneWay $false `
#           -Preflight { ... } `
#           -Apply     { ... }.GetNewClosure() `
#           -Undo      { ... }.GetNewClosure()
#       return
#   }
#   # ...real apply code...

# Returns the current queue as an array (safe to iterate, doesn't expose
# the backing list directly).
function Get-DryRunQueue {
    if ($null -eq $script:DryRunQueue) { return @() }
    return @($script:DryRunQueue)
}

# Clear all queued steps. Used when the operator discards the queue or
# exits dry-run mode without committing.
function Clear-DryRunQueue {
    if ($null -ne $script:DryRunQueue) {
        $script:DryRunQueue.Clear()
    }
}

# Add a step to the dry-run queue. The Preflight scriptblock is invoked
# immediately to compute the green/red status that surfaces in the queue
# view; the Apply and Undo scriptblocks are stored for Commit.
function Push-DryRunStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Label,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Category,

        [Parameter(Mandatory=$true)]
        [scriptblock]$Apply,

        [scriptblock]$Preflight,
        [scriptblock]$Undo,
        [bool]$OneWay = $false,
        [hashtable]$Params = @{}
    )

    if ($null -eq $script:DryRunQueue) {
        $script:DryRunQueue = [System.Collections.Generic.List[object]]::new()
    }

    # Run preflight immediately so the operator sees green/red as soon as
    # the step is queued. Preflight is allowed to throw; we capture that
    # as a red status without bubbling the error out of Push-DryRunStep.
    $preflightOK = $true
    $preflightMsg = ""
    if ($Preflight) {
        try {
            $result = & $Preflight
            # Preflight conventions:
            #   * No return / $null / $true   => OK
            #   * $false                       => fail with no message
            #   * string                       => fail with that message
            #   * [PSCustomObject]@{OK=$bool;Message=$str} => structured
            if ($null -eq $result -or $result -eq $true) {
                $preflightOK = $true
            }
            elseif ($result -eq $false) {
                $preflightOK = $false
                $preflightMsg = "Preflight returned false"
            }
            elseif ($result -is [string]) {
                $preflightOK = $false
                $preflightMsg = $result
            }
            elseif ($result.PSObject -and $result.PSObject.Properties['OK']) {
                $preflightOK = [bool]$result.OK
                if ($result.PSObject.Properties['Message']) {
                    $preflightMsg = [string]$result.Message
                }
            }
        }
        catch {
            $preflightOK = $false
            $preflightMsg = $_.Exception.Message
        }
    }

    $step = [PSCustomObject]@{
        Id           = [Guid]::NewGuid().ToString('N').Substring(0, 8)
        Timestamp    = Get-Date -Format "HH:mm:ss"
        Category     = $Category
        Label        = $Label
        OneWay       = [bool]$OneWay
        PreflightOK  = $preflightOK
        PreflightMsg = $preflightMsg
        Status       = "Queued"
        AppliedAt    = $null
        ApplyError   = $null
        Preflight    = $Preflight
        Apply        = $Apply
        Undo         = $Undo
        Params       = $Params
    }
    $script:DryRunQueue.Add($step) | Out-Null
    return $step
}

# Re-run the preflight for a single step (used by Apply All before
# committing). Returns the updated step.
function Update-DryRunStepPreflight {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Step
    )
    if (-not $Step.Preflight) {
        $Step.PreflightOK = $true
        $Step.PreflightMsg = ""
        return $Step
    }
    try {
        $result = & $Step.Preflight
        if ($null -eq $result -or $result -eq $true) {
            $Step.PreflightOK = $true
            $Step.PreflightMsg = ""
        }
        elseif ($result -eq $false) {
            $Step.PreflightOK = $false
            $Step.PreflightMsg = "Preflight returned false"
        }
        elseif ($result -is [string]) {
            $Step.PreflightOK = $false
            $Step.PreflightMsg = $result
        }
        elseif ($result.PSObject -and $result.PSObject.Properties['OK']) {
            $Step.PreflightOK = [bool]$result.OK
            $Step.PreflightMsg = if ($result.PSObject.Properties['Message']) { [string]$result.Message } else { "" }
        }
    }
    catch {
        $Step.PreflightOK = $false
        $Step.PreflightMsg = $_.Exception.Message
    }
    return $Step
}

# Render a single-line banner shown at the top of every menu when
# Dry-Run mode is ON. Kept short so it doesn't dominate the menu chrome.
function Show-DryRunBanner {
    if (-not $script:DryRunMode) { return }
    $count = (Get-DryRunQueue).Count
    $oneWayCount = @(Get-DryRunQueue | Where-Object { $_.OneWay }).Count
    $badge = "  DRY-RUN MODE  "
    $detail = if ($count -eq 0) {
        "no changes queued — actions will be captured, not applied"
    } else {
        $oneWayLabel = if ($oneWayCount -gt 0) { ", $oneWayCount one-way" } else { "" }
        "$count step(s) queued$oneWayLabel — [Q]ueue [A]pply all [S]tep apply [X] discard"
    }
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Warning"
    $line = "$badge — $detail"
    if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
    Write-OutputColor "  │$($line.PadRight(72))│" -color "Warning"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Warning"
}

# Render the queue view: header box, then a row per step with its
# status color, one-way badge, and preflight message if red. Returns
# nothing — caller handles input after rendering.
function Show-DryRunQueue {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                          DRY-RUN QUEUE").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    $queue = Get-DryRunQueue
    if ($queue.Count -eq 0) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  Queue is empty.".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Enable Dry-Run from the main menu and pick configuration actions.".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Actions will be captured here instead of being applied.".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"
        return
    }

    $okCount = @($queue | Where-Object { $_.PreflightOK }).Count
    $redCount = @($queue | Where-Object { -not $_.PreflightOK }).Count
    $oneWayCount = @($queue | Where-Object { $_.OneWay }).Count

    $summaryColor = if ($redCount -gt 0) { "Error" } else { "Success" }
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    $summary = "  $($queue.Count) step(s):  $okCount green, $redCount red, $oneWayCount one-way"
    Write-OutputColor "  │$($summary.PadRight(72))│" -color $summaryColor
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  #   Time     Category    Step".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $i = 0
    foreach ($step in $queue) {
        $i++
        $statusGlyph = if ($step.Status -eq "Applied") { "[A]" }
                       elseif ($step.Status -eq "Failed") { "[!]" }
                       elseif ($step.PreflightOK) { "[+]" }
                       else { "[X]" }
        $rowColor = if ($step.Status -eq "Applied") { "Success" }
                    elseif ($step.Status -eq "Failed") { "Error" }
                    elseif ($step.PreflightOK) { "Success" }
                    else { "Error" }

        $cat = if ($step.Category.Length -gt 10) { $step.Category.Substring(0, 10) } else { $step.Category.PadRight(10) }
        $label = $step.Label
        # Visible row width budget: 72 inner chars minus "  N   HH:MM:SS  CATEGORY-10 " prefix (~28) = ~40 chars label.
        if ($label.Length -gt 40) { $label = $label.Substring(0, 37) + "..." }

        $row = "  $statusGlyph $($i.ToString().PadLeft(2)).  $($step.Timestamp)  $cat  $label"
        Write-OutputColor "  │$($row.PadRight(72))│" -color $rowColor

        if ($step.OneWay) {
            $oneWayRow = "          ONE-WAY — cannot be reverted after Commit"
            Write-OutputColor "  │$($oneWayRow.PadRight(72))│" -color "Warning"
        }
        if (-not $step.PreflightOK -and $step.PreflightMsg) {
            $msgRow = "          Preflight: $($step.PreflightMsg)"
            if ($msgRow.Length -gt 72) { $msgRow = $msgRow.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($msgRow.PadRight(72))│" -color "Error"
        }
        if ($step.Status -eq "Failed" -and $step.ApplyError) {
            $errRow = "          Error: $($step.ApplyError)"
            if ($errRow.Length -gt 72) { $errRow = $errRow.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($errRow.PadRight(72))│" -color "Error"
        }
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  COMMIT".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    if ($redCount -gt 0) {
        Write-MenuItem "[A]  Apply All (atomic)" -Status "BLOCKED — $redCount red step(s)" -StatusColor "Error"
    } else {
        Write-MenuItem "[A]  Apply All (atomic)" -Status "Run every step; rollback on failure" -StatusColor "Success"
    }
    Write-MenuItem "[S]  Step-by-Step Apply" -Status "Walk each step interactively" -StatusColor "Info"
    Write-MenuItem "[E]  Export Queue to JSON" -Status "Save as batch config template" -StatusColor "Info"
    Write-MenuItem "[X]  Discard Queue" -Status "Clear without applying" -StatusColor "Warning"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"
}

# Atomic Commit: rerun every preflight, fail fast if any are red, then
# execute every Apply sequentially. On any Apply failure, walk the
# already-applied steps in reverse and invoke their Undo (skipping
# OneWay steps with a warning), then halt.
function Invoke-DryRunCommitAtomic {
    $queue = Get-DryRunQueue
    if ($queue.Count -eq 0) {
        Write-OutputColor "  Queue is empty — nothing to apply." -color "Warning"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Re-running preflights..." -color "Info"
    foreach ($step in $queue) { Update-DryRunStepPreflight -Step $step | Out-Null }

    $red = @($queue | Where-Object { -not $_.PreflightOK })
    if ($red.Count -gt 0) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Cannot apply — $($red.Count) step(s) failed preflight:" -color "Error"
        foreach ($r in $red) {
            $msg = if ($r.PreflightMsg) { ": $($r.PreflightMsg)" } else { "" }
            Write-OutputColor "    [X] $($r.Label)$msg" -color "Error"
        }
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Re-open the queue, fix or remove the red entries, and try again." -color "Info"
        return
    }

    $oneWayCount = @($queue | Where-Object { $_.OneWay }).Count
    if ($oneWayCount -gt 0) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  WARNING: $oneWayCount step(s) are ONE-WAY and cannot be reverted after Commit." -color "Warning"
        if (-not (Confirm-UserAction -Message "Apply all $($queue.Count) step(s) (atomic)?")) {
            Write-OutputColor "  Commit cancelled." -color "Info"
            return
        }
    } else {
        if (-not (Confirm-UserAction -Message "Apply all $($queue.Count) step(s) (atomic)?")) {
            Write-OutputColor "  Commit cancelled." -color "Info"
            return
        }
    }

    $script:ApplyingDryRunQueue = $true
    $applied = [System.Collections.Generic.List[object]]::new()
    $failedStep = $null
    try {
        $i = 0
        foreach ($step in $queue) {
            $i++
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  [$i/$($queue.Count)] $($step.Label)" -color "Info"
            $step.Status = "Applying"
            try {
                & $step.Apply
                $step.Status = "Applied"
                $step.AppliedAt = Get-Date -Format "HH:mm:ss"
                $applied.Add($step) | Out-Null
                Write-OutputColor "        Applied." -color "Success"
            }
            catch {
                $step.Status = "Failed"
                $step.ApplyError = $_.Exception.Message
                $failedStep = $step
                Write-OutputColor "        FAILED: $($_.Exception.Message)" -color "Error"
                break
            }
        }
    }
    finally {
        $script:ApplyingDryRunQueue = $false
    }

    if ($failedStep) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Rolling back $($applied.Count) applied step(s)..." -color "Warning"
        # Walk in reverse so dependents undo before their dependencies.
        for ($j = $applied.Count - 1; $j -ge 0; $j--) {
            $s = $applied[$j]
            if ($s.OneWay) {
                Write-OutputColor "    [skip] $($s.Label) — ONE-WAY, manual cleanup required" -color "Warning"
                continue
            }
            if (-not $s.Undo) {
                Write-OutputColor "    [skip] $($s.Label) — no Undo captured" -color "Warning"
                continue
            }
            try {
                & $s.Undo
                Write-OutputColor "    [revert] $($s.Label)" -color "Success"
            }
            catch {
                Write-OutputColor "    [revert FAILED] $($s.Label): $($_.Exception.Message)" -color "Error"
            }
        }
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Commit halted. Failed step left in queue with [!] status." -color "Error"
        return
    }

    # All applied. Drain the queue.
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  All $($applied.Count) step(s) applied successfully." -color "Success"
    Clear-DryRunQueue
    Add-SessionChange -Category "DryRun" -Description "Atomic commit: $($applied.Count) step(s) applied"
    Clear-MenuCache
}

# Step-by-Step Commit: walk the queue, prompt per step, apply, advance.
# Failures stop advancement but don't roll back — operator decides via
# the session history view.
function Invoke-DryRunCommitStepByStep {
    $queue = Get-DryRunQueue
    if ($queue.Count -eq 0) {
        Write-OutputColor "  Queue is empty — nothing to apply." -color "Warning"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Step-by-Step Commit: walking $($queue.Count) step(s)." -color "Info"
    Write-OutputColor "  At each step you can: [Y]es apply, [N]o skip, [Q]uit." -color "Info"

    $script:ApplyingDryRunQueue = $true
    $appliedCount = 0
    $skippedCount = 0
    $failedCount = 0
    try {
        $i = 0
        foreach ($step in $queue) {
            $i++
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  [$i/$($queue.Count)] $($step.Label)" -color "Info"
            Write-OutputColor "        Category: $($step.Category)" -color "Info"
            if ($step.OneWay) {
                Write-OutputColor "        ONE-WAY: cannot be reverted after apply" -color "Warning"
            }
            # Re-check preflight at apply time in case state changed since queue.
            Update-DryRunStepPreflight -Step $step | Out-Null
            if (-not $step.PreflightOK) {
                $msg = if ($step.PreflightMsg) { ": $($step.PreflightMsg)" } else { "" }
                Write-OutputColor "        PREFLIGHT FAILED$msg" -color "Error"
                Write-OutputColor "        Skipping (preflight red)." -color "Warning"
                $step.Status = "Skipped"
                $skippedCount++
                continue
            }

            $choice = Read-Host "        Apply this step? [Y]es / [N]o / [Q]uit"
            switch -Regex ($choice) {
                '^(y|Y|yes)$' {
                    $step.Status = "Applying"
                    try {
                        & $step.Apply
                        $step.Status = "Applied"
                        $step.AppliedAt = Get-Date -Format "HH:mm:ss"
                        $appliedCount++
                        Write-OutputColor "        Applied." -color "Success"
                    }
                    catch {
                        $step.Status = "Failed"
                        $step.ApplyError = $_.Exception.Message
                        $failedCount++
                        Write-OutputColor "        FAILED: $($_.Exception.Message)" -color "Error"
                        Write-OutputColor "        Continuing — revert via Session History if needed." -color "Warning"
                    }
                }
                '^(q|Q|quit)$' {
                    Write-OutputColor "        Quit. Remaining $($queue.Count - $i) step(s) left in queue." -color "Warning"
                    return
                }
                default {
                    $step.Status = "Skipped"
                    $skippedCount++
                    Write-OutputColor "        Skipped." -color "Info"
                }
            }
        }
    }
    finally {
        $script:ApplyingDryRunQueue = $false
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Step Commit complete: $appliedCount applied, $skippedCount skipped, $failedCount failed." -color "Info"

    # Drop only the successfully applied steps from the queue; leave failed/skipped
    # so the operator can inspect or retry them.
    if ($appliedCount -gt 0) {
        $remaining = @(Get-DryRunQueue | Where-Object { $_.Status -ne "Applied" })
        Clear-DryRunQueue
        foreach ($r in $remaining) { $script:DryRunQueue.Add($r) | Out-Null }
        Add-SessionChange -Category "DryRun" -Description "Step commit: $appliedCount applied, $skippedCount skipped, $failedCount failed"
        Clear-MenuCache
    }
}

# Export the queue to a JSON file that can be re-imported as a batch
# config template. Only includes serializable fields (Params, Label,
# Category, OneWay) — scriptblocks are not portable across processes.
function Export-DryRunQueueToJson {
    $queue = Get-DryRunQueue
    if ($queue.Count -eq 0) {
        Write-OutputColor "  Queue is empty — nothing to export." -color "Warning"
        return
    }
    $outPath = Read-Host "  Output path (default: $env:USERPROFILE\dryrun-queue.json)"
    if ([string]::IsNullOrWhiteSpace($outPath)) {
        $outPath = "$env:USERPROFILE\dryrun-queue.json"
    }
    $serializable = $queue | ForEach-Object {
        [PSCustomObject]@{
            Timestamp = $_.Timestamp
            Category  = $_.Category
            Label     = $_.Label
            OneWay    = $_.OneWay
            Params    = $_.Params
        }
    }
    $payload = [PSCustomObject]@{
        _Note     = "Exported from $($script:ToolFullName) Dry-Run queue. Re-import via batch config if compatible."
        Exported  = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
        Version   = $script:ScriptVersion
        StepCount = $queue.Count
        Steps     = $serializable
    }
    try {
        # Atomic write-then-rename so a Ctrl+C mid-write doesn't leave a
        # half-formed JSON file at the operator-visible path.
        $tmp = "$outPath.tmp"
        $payload | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tmp -Encoding utf8
        Move-Item -LiteralPath $tmp -Destination $outPath -Force
        Write-OutputColor "  Exported $($queue.Count) step(s) to $outPath" -color "Success"
    }
    catch {
        Write-OutputColor "  Export failed: $($_.Exception.Message)" -color "Error"
    }
}

# Toggle Dry-Run mode on. Idempotent — calling when already on is a no-op
# (returns without warning).
function Enable-DryRunMode {
    if ($script:DryRunMode) { return }
    $script:DryRunMode = $true
    if ($null -eq $script:DryRunQueue) {
        $script:DryRunQueue = [System.Collections.Generic.List[object]]::new()
    }
    Write-OutputColor "  Dry-Run Mode: ON" -color "Warning"
    Write-OutputColor "  Configuration actions will be captured in a queue instead of applied." -color "Info"
    Write-OutputColor "  Use [Q]ueue to review, [A]pply All to commit atomically, [S]tep to commit interactively." -color "Info"
    Add-SessionChange -Category "DryRun" -Description "Enabled Dry-Run mode"
}

# Toggle Dry-Run mode off. If the queue is non-empty, prompt whether to
# discard or keep. Keeping leaves the queue for the next time the mode
# is re-enabled.
function Disable-DryRunMode {
    if (-not $script:DryRunMode) { return }
    $queue = Get-DryRunQueue
    if ($queue.Count -gt 0) {
        Write-OutputColor "  Dry-Run queue has $($queue.Count) un-committed step(s)." -color "Warning"
        $resp = Read-Host "  [D]iscard queue, [K]eep for later, or [C]ancel"
        switch -Regex ($resp) {
            '^(d|D|discard)$' {
                Clear-DryRunQueue
                Write-OutputColor "  Queue discarded." -color "Info"
            }
            '^(c|C|cancel)$' {
                Write-OutputColor "  Cancelled — Dry-Run remains ON." -color "Info"
                return
            }
            default {
                Write-OutputColor "  Queue kept for next session." -color "Info"
            }
        }
    }
    $script:DryRunMode = $false
    Write-OutputColor "  Dry-Run Mode: OFF" -color "Info"
    Add-SessionChange -Category "DryRun" -Description "Disabled Dry-Run mode"
}

# Top-level dispatcher for the queue screen. Returns when the operator
# backs out, so the caller can re-render its menu.
function Start-Show-DryRunQueue {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }
        Show-DryRunQueue
        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.Action -eq "exit") { Exit-Script; return }
        if ($navResult.Action -eq "home") { $script:ReturnToMainMenu = $true; return }
        switch -Regex ($choice) {
            '^(b|B|back)$' { return }
            '^(a|A|apply)$' {
                Invoke-DryRunCommitAtomic
                Write-PressEnter
            }
            '^(s|S|step)$' {
                Invoke-DryRunCommitStepByStep
                Write-PressEnter
            }
            '^(e|E|export)$' {
                Export-DryRunQueueToJson
                Write-PressEnter
            }
            '^(x|X|discard)$' {
                if ((Get-DryRunQueue).Count -eq 0) {
                    Write-OutputColor "  Queue already empty." -color "Info"
                    Start-Sleep -Milliseconds 600
                    continue
                }
                if (Confirm-UserAction -Message "Discard all queued steps?") {
                    Clear-DryRunQueue
                    Write-OutputColor "  Queue cleared." -color "Info"
                    Start-Sleep -Milliseconds 600
                }
            }
            default {
                Write-OutputColor "  Invalid choice. [A]pply, [S]tep, [E]xport, [X] discard, [B]ack." -color "Error"
                Start-Sleep -Milliseconds 600
            }
        }
    }
}
#endregion
