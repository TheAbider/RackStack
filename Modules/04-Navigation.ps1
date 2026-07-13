#region ===== NAVIGATION AND SESSION FUNCTIONS =====
# Function to check if user wants to go back, cancel, or exit
function Test-NavigationCommand {
    param (
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$UserInput
    )

    # NOTE: "c" is deliberately NOT a back/cancel token. Menus use [C] as an AFFIRMATIVE key
    # (Continue / Create / Clear / Copy / ADD TO QUEUE), and treating "c" as cancel silently
    # aborted those actions — e.g. a custom VM could never be added to the deployment queue.
    # Cancel is [X] (handled locally) or the word "cancel"; back is [B]/[0]/"back".
    $backCommands = @("back", "b", "cancel", "0")
    $exitCommands = @("exit", "quit")
    $homeCommands = @("home", "main", "m")

    if ([string]::IsNullOrWhiteSpace($UserInput)) {
        return @{ Action = "empty"; ShouldReturn = $false }
    }

    $lowerInput = $UserInput.ToLower().Trim()

    if ($lowerInput -in $backCommands) {
        return @{ Action = "back"; ShouldReturn = $true }
    }

    if ($lowerInput -in $exitCommands) {
        return @{ Action = "exit"; ShouldReturn = $true }
    }

    if ($lowerInput -in $homeCommands) {
        return @{ Action = "home"; ShouldReturn = $true }
    }

    return @{ Action = "continue"; ShouldReturn = $false }
}

# Function to handle navigation result
function Invoke-NavigationAction {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$NavResult
    )

    if ($NavResult.Action -eq "exit") {
        Exit-Script
    }

    if ($NavResult.Action -eq "home") {
        $script:ReturnToMainMenu = $true
        return $true
    }

    # For "back", the calling function should handle the return
    return $NavResult.ShouldReturn
}

# Function to add a change to session tracking
function Add-SessionChange {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Category,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Description
    )

    $timestamp = Get-Date -Format "HH:mm:ss"

    $script:SessionChanges.Add([PSCustomObject]@{
        Timestamp = $timestamp
        Category = $Category
        Description = $Description
    })

    # Cap session changes to prevent unbounded growth in long sessions
    if ($script:SessionChanges.Count -gt 500) {
        $script:SessionChanges.RemoveAt(0)
    }

    # Also log to file if logging is enabled
    if ($script:logFilePath) {
        Write-LogMessage -message "[$Category] $Description" -logFilePath $script:logFilePath
    }

    # Persist to session log on disk
    $logDir = $script:AppConfigDir
    if ([string]::IsNullOrWhiteSpace($logDir)) { return }
    if (-not (Test-Path -LiteralPath $logDir)) {
        $null = New-Item -Path $logDir -ItemType Directory -Force -ErrorAction SilentlyContinue
    }
    $logFile = Join-Path $logDir "session-log.txt"
    $datestamp = Get-Date -Format "yyyy-MM-dd"
    $line = "$datestamp $timestamp [$Category] $Description"
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue

    # JSON audit log (one JSON object per line for easy parsing). Explicit -Depth 5
    # so a nested change description (passed by some callers as a sub-hashtable) doesn't
    # truncate to "..." at the default depth-2 boundary.
    $auditFile = Join-Path $logDir "audit-log.jsonl"
    $auditEntry = @{
        ts       = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
        host     = $env:COMPUTERNAME
        user     = $env:USERNAME
        category = $Category
        action   = $Description
    } | ConvertTo-Json -Compress -Depth 5
    Add-Content -LiteralPath $auditFile -Value $auditEntry -Encoding UTF8 -ErrorAction SilentlyContinue

    # Rotate audit log if over 10MB
    $auditInfo = Get-Item -LiteralPath $auditFile -ErrorAction SilentlyContinue
    if ($auditInfo -and $auditInfo.Length -gt 10MB) {
        $archiveName = "audit-log-$(Get-Date -Format 'yyyyMMdd-HHmmss').jsonl"
        $archivePath = Join-Path $logDir $archiveName
        try {
            Move-Item -LiteralPath $auditFile -Destination $archivePath -Force -ErrorAction Stop
        }
        catch {
            Write-LogMessage -message "Failed to rotate audit log: $_" -logFilePath $script:logFilePath
        }
    }

    # Auto-save session state after each change (function always exists after module load)
    Save-SessionState -Description $Description
}

# Display recent audit log entries
function Show-AuditLog {
    Clear-Host
    Write-CenteredOutput "Audit Log" -color "Info"

    $auditFile = "$script:AppConfigDir\audit-log.jsonl"

    if (-not (Test-Path -LiteralPath $auditFile)) {
        Write-OutputColor "  No audit log found." -color "Warning"
        Write-OutputColor "  Log entries are created as you make changes." -color "Info"
        return
    }

    # Read last 50 entries
    $lines = @(Get-Content -LiteralPath $auditFile -Tail 50 -ErrorAction SilentlyContinue)

    if ($lines.Count -eq 0) {
        Write-OutputColor "  Audit log is empty." -color "Info"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Showing last $($lines.Count) entries (newest first):" -color "Info"
    Write-OutputColor "  $('-' * 60)" -color "Info"

    # Reverse to show newest first
    [array]::Reverse($lines)

    foreach ($line in $lines) {
        try {
            $entry = $line | ConvertFrom-Json
            $ts = $entry.ts
            $cat = $entry.category
            $act = $entry.action
            $color = switch ($cat) {
                "System"   { "Info" }
                "Network"  { "Info" }
                "Security" { "Warning" }
                "Software" { "Success" }
                default    { "Info" }
            }
            Write-OutputColor "  $ts [$cat] $act" -color $color
        }
        catch {
            Write-OutputColor "  $line" -color "Info"
        }
    }

    Write-OutputColor "  $('-' * 60)" -color "Info"
    Write-OutputColor "  Log file: $auditFile" -color "Info"
}

# Helper function for consistent "Press Enter to continue" prompts
function Write-PressEnter {
    param (
        [string]$Message = "Press Enter to continue..."
    )
    Write-OutputColor $Message -color "Info"
    Read-Host | Out-Null
}

# Function to add an undo action to the stack
function Add-UndoAction {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Category,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Description,
        [Parameter(Mandatory=$true)]
        [scriptblock]$UndoScript,
        [hashtable]$UndoParams = @{}
    )

    $script:UndoStack.Add([PSCustomObject]@{
        Timestamp = Get-Date -Format "HH:mm:ss"
        Category = $Category
        Description = $Description
        UndoScript = $UndoScript
        UndoParams = $UndoParams
    })
}

# Function to undo the last change
function Undo-LastChange {
    Clear-Host
    Write-CenteredOutput "Undo Last Change" -color "Info"

    if ($script:UndoStack.Count -eq 0) {
        Write-OutputColor "  No changes available to undo." -color "Warning"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Note: Supported undo operations include:" -color "Info"
        Write-OutputColor "  - IP address, DNS, and VLAN changes" -color "Info"
        Write-OutputColor "  - Adapter renames" -color "Info"
        Write-OutputColor "  - Hostname, timezone, and power plan changes" -color "Info"
        Write-OutputColor "  - Firewall profile toggles" -color "Info"
        Write-OutputColor "  - RDP and WinRM enable" -color "Info"
        Write-OutputColor "  - Defender exclusion add/remove" -color "Info"
        Write-OutputColor "  - Service start/stop and startup type" -color "Info"
        Write-OutputColor "  - Disk online/offline, Hyper-V paths" -color "Info"
        Write-OutputColor "  - Live Migration settings" -color "Info"
        Write-OutputColor "  - Scheduled task enable/disable" -color "Info"
        Write-OutputColor "  - Color theme changes" -color "Info"
        return
    }

    # Get the last action
    $lastAction = $script:UndoStack[-1]

    Write-OutputColor "  Last undoable change:" -color "Info"
    Write-OutputColor "  Time: $($lastAction.Timestamp)" -color "Info"
    Write-OutputColor "  Category: $($lastAction.Category)" -color "Info"
    Write-OutputColor "  Action: $($lastAction.Description)" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Undo this change?")) {
        Write-OutputColor "  Undo cancelled." -color "Info"
        return
    }

    try {
        Write-OutputColor "  Undoing change..." -color "Info"

        # Execute the undo script with parameters
        if ($lastAction.UndoParams.Count -gt 0) {
            $undoParams = $lastAction.UndoParams
            & $lastAction.UndoScript @undoParams
        }
        else {
            & $lastAction.UndoScript
        }

        Write-OutputColor "  Change undone successfully!" -color "Success"

        # Remove from undo stack
        $script:UndoStack.RemoveAt($script:UndoStack.Count - 1)

        # Add to session changes
        Add-SessionChange -Category "Undo" -Description "Undid: $($lastAction.Description)"
        Clear-MenuCache
    }
    catch {
        Write-OutputColor "  Failed to undo change: $_" -color "Error"
    }
}

# Extended (multi-step) undo. Shows the full undo history newest-first and reverts
# the last N changes in reverse order, reusing each entry's captured UndoScript.
# Single-step undo is just N=1 (the default), so this supersedes Undo-LastChange in
# the Settings menu while that function stays for any direct callers.
function Invoke-ExtendedUndo {
    Clear-Host
    Write-CenteredOutput "Undo Changes" -color "Info"

    if ($script:UndoStack.Count -eq 0) {
        Write-OutputColor "  No changes available to undo." -color "Warning"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Note: undoable operations include IP/DNS/VLAN, adapter renames," -color "Info"
        Write-OutputColor "  hostname/timezone/power plan, firewall toggles, RDP/WinRM, Defender" -color "Info"
        Write-OutputColor "  exclusions, service changes, disk online/offline, scheduled tasks, themes." -color "Info"
        return
    }

    $count = $script:UndoStack.Count
    Write-OutputColor "  Undoable changes (most recent first):" -color "Info"
    Write-OutputColor "" -color "Info"
    for ($i = 0; $i -lt $count; $i++) {
        $entry = $script:UndoStack[$count - 1 - $i]
        $line = ("  [{0,2}] {1}  {2}: {3}" -f ($i + 1), $entry.Timestamp, $entry.Category, $entry.Description)
        if ($line.Length -gt 74) { $line = $line.Substring(0, 71) + "..." }
        Write-OutputColor $line -color "Info"
    }
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Undo how many of the most recent changes? [1-$count], [A]ll, [B]ack (default 1)" -color "Info"
    $choice = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    $choiceUpper = "$choice".Trim().ToUpper()
    if ($choiceUpper -eq "B") { return }
    $toUndo = 1
    if ([string]::IsNullOrWhiteSpace($choice)) {
        $toUndo = 1
    }
    elseif ($choiceUpper -eq "A") {
        $toUndo = $count
    }
    elseif ($choice -match '^\d+$') {
        $toUndo = [int]$choice
        if ($toUndo -lt 1 -or $toUndo -gt $count) {
            Write-OutputColor "  Enter a number between 1 and $count." -color "Error"
            Start-Sleep -Seconds 1
            return
        }
    }
    else {
        Write-OutputColor "  Invalid choice." -color "Error"
        Start-Sleep -Seconds 1
        return
    }

    $plural = if ($toUndo -eq 1) { "change" } else { "changes" }
    if (-not (Confirm-UserAction -Message "Undo the $toUndo most recent $plural (newest first)?")) {
        Write-OutputColor "  Undo cancelled." -color "Info"
        return
    }

    $undone = 0
    $failed = 0
    for ($k = 0; $k -lt $toUndo; $k++) {
        if ($script:UndoStack.Count -eq 0) { break }
        $action = $script:UndoStack[$script:UndoStack.Count - 1]
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Undoing: $($action.Category) — $($action.Description)" -color "Info"
        try {
            if ($action.UndoParams.Count -gt 0) {
                $undoParams = $action.UndoParams
                & $action.UndoScript @undoParams
            }
            else {
                & $action.UndoScript
            }
            # Only drop the entry once its undo succeeded, so a failure leaves it
            # (and everything older) intact for inspection.
            $script:UndoStack.RemoveAt($script:UndoStack.Count - 1)
            $undone++
            Write-OutputColor "    Reverted." -color "Success"
            Add-SessionChange -Category "Undo" -Description "Undid: $($action.Description)"
        }
        catch {
            $failed++
            Write-OutputColor "    Failed to undo: $_" -color "Error"
            Write-OutputColor "    Stopping — the remaining changes are left intact." -color "Warning"
            break
        }
    }

    Clear-MenuCache
    Write-OutputColor "" -color "Info"
    $resultColor = if ($failed -eq 0) { "Success" } else { "Warning" }
    Write-OutputColor "  Undo complete: $undone reverted, $failed failed." -color $resultColor
}

# Execute batch undo stack in reverse order (called from Start-BatchMode on failure)
function Invoke-BatchUndo {
    if (-not $script:BatchUndoStack -or $script:BatchUndoStack.Count -eq 0) {
        Write-OutputColor "  No batch changes to undo." -color "Warning"
        return
    }

    $reversible = @($script:BatchUndoStack | Where-Object { $_.Reversible })
    if ($reversible.Count -eq 0) {
        Write-OutputColor "  No reversible batch changes found." -color "Warning"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Undoing $($reversible.Count) batch change(s) in reverse order..." -color "Warning"
    Write-OutputColor "" -color "Info"

    $undone = 0
    $undoFailed = 0

    # Reverse order
    for ($i = $reversible.Count - 1; $i -ge 0; $i--) {
        $action = $reversible[$i]
        Write-OutputColor "  [UNDO] Step $($action.Step): $($action.Description)" -color "Info"
        try {
            & $action.UndoScript
            Write-OutputColor "         Reverted." -color "Success"
            $undone++
            Add-SessionChange -Category "Undo" -Description "Batch undo: $($action.Description)"
            Clear-MenuCache
        }
        catch {
            Write-OutputColor "         Failed to undo: $_" -color "Error"
            $undoFailed++
        }
    }

    Write-OutputColor "" -color "Info"
    $resultColor = if ($undoFailed -eq 0) { "Success" } else { "Warning" }
    Write-OutputColor "  BATCH UNDO: $undone reverted, $undoFailed failed" -color $resultColor

    # Clear the batch undo stack
    $script:BatchUndoStack = [System.Collections.Generic.List[object]]::new()
}

# Caching system for main menu status display
$script:MenuCache = @{
    HyperVInstalled = $null
    RDPState = $null
    FirewallState = $null
    AdminEnabled = $null
    PowerPlan = $null
    LastUpdate = $null
}

# Function to get cached or fresh value
function Get-CachedValue {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Key,
        [Parameter(Mandatory=$true)]
        [scriptblock]$FetchScript,
        [int]$CacheSeconds = 30
    )

    $now = Get-Date

    # Check if cache is valid (per-key timestamp)
    $keyTimestamp = $script:MenuCache["${Key}_LastUpdate"]
    if ($keyTimestamp -and
        $null -ne $script:MenuCache[$Key] -and
        ($now - $keyTimestamp).TotalSeconds -lt $CacheSeconds) {
        return $script:MenuCache[$Key]
    }

    # Fetch fresh value
    $value = & $FetchScript
    $script:MenuCache[$Key] = $value
    $script:MenuCache["${Key}_LastUpdate"] = $now

    return $value
}

# Function to invalidate cache (call after making changes)
function Clear-MenuCache {
    $script:MenuCache.HyperVInstalled = $null
    $script:MenuCache.HyperVReady = $null
    $script:MenuCache.RDPState = $null
    $script:MenuCache.FirewallState = $null
    $script:MenuCache.AdminEnabled = $null
    $script:MenuCache.PowerPlan = $null
    # Clear per-key timestamps
    $keysToRemove = @($script:MenuCache.Keys | Where-Object { $_ -like "*_LastUpdate" })
    foreach ($k in $keysToRemove) { $script:MenuCache.Remove($k) }
}

# Function to show progress for long operations (uses \r overwrite)
function Show-ProgressMessage {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Activity,
        [string]$Status = "Working...",
        [int]$SecondsElapsed = 0
    )

    $spinChars = @('|', '/', '-', '\')
    $spin = $spinChars[$SecondsElapsed % 4]
    $min = [math]::Floor($SecondsElapsed / 60)
    $sec = $SecondsElapsed % 60
    Write-Host "`r  [$spin] $Activity - $Status ${min}m $("{0:D2}" -f $sec)s    " -NoNewline
}

# Function to complete progress display
function Complete-ProgressMessage {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Activity,
        [string]$Status = "Complete",
        [switch]$Success,
        [switch]$Failed
    )

    Write-Host ""  # Clear any \r line
    $color = if ($Failed) { "Red" } elseif ($Success) { "Green" } else { "Cyan" }
    $symbol = if ($Failed) { "X" } elseif ($Success) { "√" } else { "-" }

    Write-Host "  [$symbol] $Activity - $Status" -ForegroundColor $color
}

# Format byte count to human-readable size string
function Format-TransferSize {
    param([long]$Bytes)

    if ($Bytes -ge 1TB) { return "{0:N2} TB" -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N0} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N0} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

# Rich progress bar renderer with two modes:
# Known-total: [=================---------] 65%  3.39/5.21 GB  14.2 MB/s  ETA 2m 08s
# Unknown-total: [/] Converting...  2,345 MB  45.2 MB/s  1m 12s
function Write-ProgressBar {
    param(
        [long]$CurrentBytes = 0,
        [long]$TotalBytes = 0,
        [string]$Activity = "",
        [double]$SpeedBytesPerSec = 0,
        [int]$ElapsedSeconds = 0,
        [string]$SpinChar = "|"
    )

    if ($TotalBytes -gt 0) {
        # Known-total mode: bar with percentage
        $barWidth = 25
        $pct = [math]::Min(100, [math]::Floor(($CurrentBytes / $TotalBytes) * 100))
        $filled = [math]::Floor(($pct / 100) * $barWidth)
        $empty = $barWidth - $filled

        $barFill = [string]::new([char]0x2588, $filled)
        $barEmpty = [string]::new([char]0x2591, $empty)

        $currentStr = Format-TransferSize $CurrentBytes
        $totalStr = Format-TransferSize $TotalBytes
        $sizeStr = "$currentStr/$totalStr"

        $speedStr = ""
        if ($SpeedBytesPerSec -gt 0) {
            if ($SpeedBytesPerSec -ge 1GB) { $speedStr = "  {0:N1} GB/s" -f ($SpeedBytesPerSec / 1GB) }
            elseif ($SpeedBytesPerSec -ge 1MB) { $speedStr = "  {0:N1} MB/s" -f ($SpeedBytesPerSec / 1MB) }
            elseif ($SpeedBytesPerSec -ge 1KB) { $speedStr = "  {0:N0} KB/s" -f ($SpeedBytesPerSec / 1KB) }
            else { $speedStr = "  $([int]$SpeedBytesPerSec) B/s" }
        }

        $etaStr = ""
        if ($SpeedBytesPerSec -gt 0 -and $CurrentBytes -lt $TotalBytes) {
            $remaining = $TotalBytes - $CurrentBytes
            $etaSec = [int][math]::Ceiling($remaining / $SpeedBytesPerSec)
            $etaMin = [math]::Floor($etaSec / 60)
            $etaSecRem = $etaSec % 60
            $etaStr = "  ETA ${etaMin}m $("{0:D2}" -f $etaSecRem)s"
        }

        Write-Host "`r  [$barFill$barEmpty] $pct%  $sizeStr$speedStr$etaStr    " -NoNewline
    }
    else {
        # Unknown-total mode: spinner with size
        $sizeStr = Format-TransferSize $CurrentBytes

        $speedStr = ""
        if ($SpeedBytesPerSec -gt 0) {
            if ($SpeedBytesPerSec -ge 1GB) { $speedStr = "  {0:N1} GB/s" -f ($SpeedBytesPerSec / 1GB) }
            elseif ($SpeedBytesPerSec -ge 1MB) { $speedStr = "  {0:N1} MB/s" -f ($SpeedBytesPerSec / 1MB) }
            elseif ($SpeedBytesPerSec -ge 1KB) { $speedStr = "  {0:N0} KB/s" -f ($SpeedBytesPerSec / 1KB) }
            else { $speedStr = "  $([int]$SpeedBytesPerSec) B/s" }
        }

        $timeStr = ""
        if ($ElapsedSeconds -gt 0) {
            $min = [math]::Floor($ElapsedSeconds / 60)
            $sec = $ElapsedSeconds % 60
            $timeStr = "  ${min}m $("{0:D2}" -f $sec)s"
        }

        $actLabel = if ($Activity) { "$Activity  " } else { "" }
        Write-Host "`r  [$SpinChar] $actLabel$sizeStr$speedStr$timeStr    " -NoNewline
    }
}

# Display transfer completion summary with size, time, speed, and optional hash
function Write-TransferComplete {
    param(
        [long]$TotalBytes,
        [int]$ElapsedSeconds,
        [string]$Activity = "Download",
        [string]$Hash = "",
        $HashMatch = $null
    )

    $sizeStr = Format-TransferSize $TotalBytes
    $min = [math]::Floor($ElapsedSeconds / 60)
    $sec = $ElapsedSeconds % 60
    $timeStr = "${min}m $("{0:D2}" -f $sec)s"

    $avgSpeed = if ($ElapsedSeconds -gt 0) { $TotalBytes / $ElapsedSeconds } else { 0 }
    $speedStr = if ($avgSpeed -ge 1GB) { "{0:N1} GB/s" -f ($avgSpeed / 1GB) }
                elseif ($avgSpeed -ge 1MB) { "{0:N1} MB/s" -f ($avgSpeed / 1MB) }
                elseif ($avgSpeed -ge 1KB) { "{0:N0} KB/s" -f ($avgSpeed / 1KB) }
                else { "$([int]$avgSpeed) B/s" }

    Write-OutputColor "  $Activity complete! $sizeStr in $timeStr ($speedStr avg)" -color "Success"

    if ($Hash) {
        $hashDisplay = if ($Hash.Length -gt 16) { $Hash.Substring(0, 16) + "..." } else { $Hash }
        Write-OutputColor "  SHA256: $hashDisplay" -color "Info"

        if ($null -ne $HashMatch) {
            if ($HashMatch) {
                Write-OutputColor "  Integrity: Verified" -color "Success"
            } else {
                Write-OutputColor "  Integrity: FAILED - hash mismatch!" -color "Error"
            }
        } else {
            Write-OutputColor "  Integrity: Size verified (no remote hash available)" -color "Info"
        }
    }
}

# Compute SHA256 hash of a file in a background job with spinner
function Get-FileHashBackground {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        Write-OutputColor "  File not found: $FilePath" -color "Error"
        return $null
    }

    $hashJob = Start-Job -ScriptBlock {
        param($path)
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    } -ArgumentList $FilePath

    $spinChars = @('|', '/', '-', '\')
    $spinIndex = 0

    # Cap at 30 minutes wall-clock so a wedged storage path (network drive, AV scan blocking
    # read, RAID rebuild stall) doesn't pin the menu indefinitely. SHA256 on a 60 GB VHDX over
    # a healthy NVMe takes ~3-4 minutes; 30 min covers worst-case multi-TB exports on SATA.
    # Operator can Ctrl-C earlier; this is the hard ceiling.
    $maxHashSeconds = 1800
    $hashElapsed = 0
    try {
        while ($hashJob.State -eq "Running" -and $hashElapsed -lt $maxHashSeconds) {
            $spin = $spinChars[$spinIndex % 4]
            $spinIndex++
            Write-Host "`r  [$spin] Computing SHA256 hash...    " -NoNewline
            Start-Sleep -Milliseconds 500
            $hashElapsed += 0.5
        }
        Write-OutputColor ""

        if ($hashJob.State -eq "Running") {
            Write-OutputColor "  Hash computation exceeded 30-minute cap. Aborting." -color "Warning"
            return $null
        }

        $hash = Receive-Job $hashJob -ErrorAction SilentlyContinue
        return $hash
    }
    finally {
        # Always clean up the job, even if the loop exited via exception (e.g., Ctrl-C
        # propagated as a PipelineStoppedException). Prior code only cleaned up on the
        # success path — a Ctrl-C left the background runspace alive.
        try { Stop-Job $hashJob -ErrorAction SilentlyContinue } catch { }
        try { Remove-Job $hashJob -Force -ErrorAction SilentlyContinue } catch { }
    }
}

# Run a scriptblock with a timeout using a background runspace (faster than Start-Job)
function Invoke-WithTimeout {
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$ScriptBlock,
        [int]$TimeoutSeconds = 30,
        [string]$Activity = "Operation",
        # Values forwarded to a param() block in the script body. The helper runs the
        # block in a fresh [powershell]::Create() runspace, so closure variables from
        # the caller are NOT visible. Callers that reference outer values must declare
        # them via param() inside the block and pass them here positionally.
        [object[]]$ArgumentList = @()
    )

    try {
        $ps = [powershell]::Create()
        [void]$ps.AddScript($ScriptBlock.ToString())
        foreach ($arg in $ArgumentList) { [void]$ps.AddArgument($arg) }
        $handle = $ps.BeginInvoke()
    } catch {
        if ($null -ne $ps) { $ps.Dispose() }
        return @{ TimedOut = $false; Result = $null; Failed = $true; Error = $_.Exception.Message }
    }

    $spinChars = @('|', '/', '-', '\')
    $elapsed = 0

    while (-not $handle.IsCompleted -and $elapsed -lt $TimeoutSeconds) {
        $spin = $spinChars[$elapsed % 4]
        Write-Host "`r  [$spin] $Activity... ${elapsed}s    " -NoNewline
        Start-Sleep -Seconds 1
        $elapsed++
    }
    Write-OutputColor ""

    if (-not $handle.IsCompleted) {
        # Non-blocking stop — BeginStop sends cancellation without waiting for completion.
        # If the underlying CIM/WMI call ignores cancellation (Server 2025 cold WMI),
        # the runspace stays alive briefly but doesn't block this thread.
        try { $null = $ps.BeginStop($null, $null) } catch { }
        # Dispose on a background thread to avoid blocking if Stop hangs
        try {
            $null = [System.Threading.Tasks.Task]::Run([Action]{ $ps.Dispose() })
        }
        catch {
            # Fallback: just dispose synchronously (may block briefly)
            try { $ps.Dispose() } catch { }
        }
        return @{ TimedOut = $true; Result = $null; Failed = $false; Error = "Timed out after $TimeoutSeconds seconds" }
    }

    try {
        $result = $ps.EndInvoke($handle)
    } catch {
        $ps.Dispose()
        return @{ TimedOut = $false; Result = $null; Failed = $true; Error = $_.Exception.Message }
    }

    if ($ps.InvocationStateInfo.State -eq 'Failed') {
        $errorMsg = if ($null -ne $ps.InvocationStateInfo.Reason) { $ps.InvocationStateInfo.Reason.Message } else { "Operation failed" }
        $ps.Dispose()
        return @{ TimedOut = $false; Result = $null; Failed = $true; Error = $errorMsg }
    }

    $output = if ($result.Count -eq 1) { $result[0] } elseif ($result.Count -eq 0) { $null } else { @($result) }
    $ps.Dispose()
    return @{ TimedOut = $false; Result = $output; Failed = $false; Error = $null }
}
#endregion
