#region ===== NAVIGATION AND SESSION FUNCTIONS =====
# Function to check if user wants to go back, cancel, or exit
function Test-NavigationCommand {
    param (
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$UserInput
    )

    $backCommands = @("back", "b", "cancel", "c", "0")
    $exitCommands = @("exit", "quit", "q")

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

    # Also log to file if logging is enabled
    if ($logFilePath) {
        Write-LogMessage -message "[$Category] $Description" -logFilePath $logFilePath
    }

    # Persist to session log on disk
    $logDir = $script:AppConfigDir
    if (-not (Test-Path $logDir)) {
        $null = New-Item -Path $logDir -ItemType Directory -Force -ErrorAction SilentlyContinue
    }
    $logFile = Join-Path $logDir "session-log.txt"
    $datestamp = Get-Date -Format "yyyy-MM-dd"
    $line = "$datestamp $timestamp [$Category] $Description"
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue

    # JSON audit log (one JSON object per line for easy parsing)
    $auditFile = Join-Path $logDir "audit-log.jsonl"
    $auditEntry = @{
        ts       = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
        host     = $env:COMPUTERNAME
        user     = $env:USERNAME
        category = $Category
        action   = $Description
    } | ConvertTo-Json -Compress
    Add-Content -Path $auditFile -Value $auditEntry -ErrorAction SilentlyContinue

    # Rotate audit log if over 10MB
    $auditInfo = Get-Item $auditFile -ErrorAction SilentlyContinue
    if ($auditInfo -and $auditInfo.Length -gt 10MB) {
        $archiveName = "audit-log-$(Get-Date -Format 'yyyyMMdd-HHmmss').jsonl"
        $archivePath = Join-Path $logDir $archiveName
        Move-Item -Path $auditFile -Destination $archivePath -Force -ErrorAction SilentlyContinue
    }
}

# Display recent audit log entries
function Show-AuditLog {
    Clear-Host
    Write-CenteredOutput "Audit Log" -color "Info"

    $auditFile = "$script:AppConfigDir\audit-log.jsonl"

    if (-not (Test-Path $auditFile)) {
        Write-OutputColor "  No audit log found." -color "Warning"
        Write-OutputColor "  Log entries are created as you make changes." -color "Info"
        return
    }

    # Read last 50 entries
    $lines = @(Get-Content $auditFile -Tail 50 -ErrorAction SilentlyContinue)

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
        Write-OutputColor "No changes available to undo." -color "Warning"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Note: Only certain operations support undo:" -color "Info"
        Write-OutputColor "  - DNS configuration changes" -color "Info"
        Write-OutputColor "  - IP address changes" -color "Info"
        Write-OutputColor "  - Adapter renames" -color "Info"
        return
    }

    # Get the last action
    $lastAction = $script:UndoStack[-1]

    Write-OutputColor "Last undoable change:" -color "Info"
    Write-OutputColor "  Time: $($lastAction.Timestamp)" -color "Info"
    Write-OutputColor "  Category: $($lastAction.Category)" -color "Info"
    Write-OutputColor "  Action: $($lastAction.Description)" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Undo this change?")) {
        Write-OutputColor "Undo cancelled." -color "Info"
        return
    }

    try {
        Write-OutputColor "Undoing change..." -color "Info"

        # Execute the undo script with parameters
        if ($lastAction.UndoParams.Count -gt 0) {
            & $lastAction.UndoScript @($lastAction.UndoParams.Values)
        }
        else {
            & $lastAction.UndoScript
        }

        Write-OutputColor "Change undone successfully!" -color "Success"

        # Remove from undo stack
        $script:UndoStack = $script:UndoStack[0..($script:UndoStack.Count - 2)]

        # Add to session changes
        Add-SessionChange -Category "Undo" -Description "Undid: $($lastAction.Description)"
    }
    catch {
        Write-OutputColor "Failed to undo change: $_" -color "Error"
    }
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
            $etaSec = [math]::Ceiling($remaining / $SpeedBytesPerSec)
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

    $hashJob = Start-Job -ScriptBlock {
        param($path)
        (Get-FileHash -Path $path -Algorithm SHA256).Hash
    } -ArgumentList $FilePath

    $spinChars = @('|', '/', '-', '\')
    $spinIndex = 0

    while ($hashJob.State -eq "Running") {
        $spin = $spinChars[$spinIndex % 4]
        $spinIndex++
        Write-Host "`r  [$spin] Computing SHA256 hash...    " -NoNewline
        Start-Sleep -Milliseconds 500
    }
    Write-Host ""

    $hash = Receive-Job $hashJob
    Remove-Job $hashJob -Force -ErrorAction SilentlyContinue
    return $hash
}
#endregion