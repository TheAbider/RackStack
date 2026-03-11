#region ===== LOGGING AND OUTPUT FUNCTIONS =====
# Function to log messages to a file
function Write-LogMessage {
    param (
        [string]$message,
        [string]$logFilePath
    )
    if ($logFilePath) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "$timestamp - $message"
        Add-Content -LiteralPath $logFilePath -Value $logMessage -Encoding UTF8 -ErrorAction SilentlyContinue
    }
}

# Write a structured log entry with category, level, and optional key-value data
# Useful for machine-parseable logging alongside the human-readable transcript
function Write-StructuredLog {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DEBUG")]
        [string]$Level = "INFO",

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$Category = "General",

        [Parameter(Mandatory=$false)]
        [hashtable]$Data,

        [Parameter(Mandatory=$false)]
        [string]$LogFilePath
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $hostname = $env:COMPUTERNAME

    # Build structured line: TIMESTAMP | LEVEL | CATEGORY | HOSTNAME | MESSAGE | KEY=VALUE pairs
    $entry = "${timestamp} | ${Level} | ${Category} | ${hostname} | ${Message}"

    if ($null -ne $Data -and $Data.Count -gt 0) {
        $kvPairs = @()
        foreach ($key in $Data.Keys) {
            $val = $Data[$key]
            if ($null -eq $val) { $val = "(null)" }
            $kvPairs += "${key}=$val"
        }
        $entry += " | $($kvPairs -join '; ')"
    }

    # Write to specified log file, or fall back to transcript path
    $targetPath = $LogFilePath
    if (-not $targetPath) {
        $targetPath = $script:TranscriptPath
    }

    if ($targetPath) {
        Add-Content -LiteralPath $targetPath -Value $entry -Encoding UTF8 -ErrorAction SilentlyContinue
    }
}

# Rotate transcript logs: archive old transcripts into a compressed zip
# Called during startup to keep the transcript directory tidy
function Invoke-LogRotation {
    param(
        [int]$DaysToArchive = 7,
        [int]$MaxArchivesMB = 200
    )

    $tempPath = $script:TempPath
    if (-not (Test-Path -LiteralPath $tempPath)) { return }

    try {
        $logFilter = "$($script:ToolName)Config_*.log"
        $allLogs = @(Get-ChildItem -LiteralPath $tempPath -Filter $logFilter -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime)

        if ($allLogs.Count -eq 0) { return }

        # Find logs older than DaysToArchive that are eligible for archiving
        $cutoffDate = (Get-Date).AddDays(-$DaysToArchive)
        $archivable = @($allLogs | Where-Object { $_.LastWriteTime -lt $cutoffDate })

        if ($archivable.Count -eq 0) { return }

        # Create archive subdirectory
        $archivePath = Join-Path $tempPath "transcript_archive"
        if (-not (Test-Path -LiteralPath $archivePath)) {
            New-Item -Path $archivePath -ItemType Directory -Force | Out-Null
        }

        # Load compression assembly (required for PS 5.1)
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop

        # Group archivable logs by month for organized zip files
        $grouped = $archivable | Group-Object { $_.LastWriteTime.ToString("yyyy-MM") }

        foreach ($group in $grouped) {
            $zipName = "$($script:ToolName)_transcripts_$($group.Name).zip"
            $zipPath = Join-Path $archivePath $zipName

            try {
                # Add files to zip (append if zip already exists)
                if (Test-Path -LiteralPath $zipPath) {
                    # Open existing zip and add new entries
                    $zip = [System.IO.Compression.ZipFile]::Open($zipPath, 'Update')
                }
                else {
                    $zip = [System.IO.Compression.ZipFile]::Open($zipPath, 'Create')
                }

                foreach ($logFile in $group.Group) {
                    # Skip if entry already exists in the archive
                    $existingEntry = $zip.GetEntry($logFile.Name)
                    if ($null -eq $existingEntry) {
                        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                            $zip, $logFile.FullName, $logFile.Name, [System.IO.Compression.CompressionLevel]::Optimal)
                    }
                }

                $zip.Dispose()

                # Remove archived source files
                foreach ($logFile in $group.Group) {
                    Remove-Item -LiteralPath $logFile.FullName -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                # If zip operations fail, leave the files in place
                if ($null -ne $zip) { $zip.Dispose() }
            }
        }

        # Enforce archive size limit
        $archives = @(Get-ChildItem -LiteralPath $archivePath -Filter "*.zip" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime)
        if ($archives.Count -gt 0) {
            $totalSize = ($archives | Measure-Object -Property Length -Sum).Sum
            $maxBytes = $MaxArchivesMB * 1MB
            if ($totalSize -gt $maxBytes) {
                foreach ($oldZip in $archives) {
                    if ($totalSize -le $maxBytes) { break }
                    $totalSize -= $oldZip.Length
                    Remove-Item -LiteralPath $oldZip.FullName -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    catch {
        # Silently ignore rotation errors - this is a maintenance task
    }
}

# Function to output messages with color and optional logging
function Write-OutputColor {
    param (
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$message,

        [Parameter(Mandatory=$false)]
        [ValidateSet("Success", "Warning", "Error", "Info", "Debug", "Critical", "Verbose")]
        [string]$color = "Info",

        [Parameter(Mandatory=$false)]
        [switch]$NoNewline
    )

    # Handle empty messages - just output a blank line
    if ([string]::IsNullOrEmpty($message)) {
        if (-not $NoNewline) {
            Write-Host ""
        }
        return
    }

    # Get color map from current theme
    $colorMap = $script:ColorThemes[$script:ColorTheme]
    if (-not $colorMap) {
        $colorMap = $script:ColorThemes["Default"]
    }

    $fgColor = if ($colorMap.ContainsKey($color)) { $colorMap[$color] } else { "Gray" }

    # Auto-detect box content lines: if color is not Info and line has 2+ │ chars,
    # split rendering so borders are Cyan and content uses the specified color
    $pipe = [char]0x2502  # │
    if ($color -ne "Info" -and $message.Length -gt 4) {
        $firstPipe = $message.IndexOf($pipe)
        $lastPipe = $message.LastIndexOf($pipe)
        if ($firstPipe -ge 0 -and $lastPipe -gt $firstPipe) {
            $borderColor = if ($colorMap.ContainsKey("Info")) { $colorMap["Info"] } else { "Cyan" }
            Write-Host $message.Substring(0, $firstPipe + 1) -NoNewline -ForegroundColor $borderColor
            Write-Host $message.Substring($firstPipe + 1, $lastPipe - $firstPipe - 1) -NoNewline -ForegroundColor $fgColor
            if ($NoNewline) {
                Write-Host $message.Substring($lastPipe) -NoNewline -ForegroundColor $borderColor
            } else {
                Write-Host $message.Substring($lastPipe) -ForegroundColor $borderColor
            }
            if ($logFilePath) { Write-LogMessage -message "[$color] $message" -logFilePath $logFilePath }
            return
        }
    }

    if ($NoNewline) {
        Write-Host $message -ForegroundColor $fgColor -NoNewline
    }
    else {
        Write-Host $message -ForegroundColor $fgColor
    }

    # Log to file if enabled
    if ($logFilePath) {
        Write-LogMessage -message "[$color] $message" -logFilePath $logFilePath
    }
}

# Function to display centered output with a border
function Write-CenteredOutput {
    param (
        [string]$text,
        [string]$color = "Info",
        [int]$width = 50
    )

    $textLength = $text.Length
    $padding = [math]::Max(0, [math]::Floor(($width - $textLength) / 2))
    $paddedText = (" " * $padding) + $text

    $border = "=" * $width
    Write-OutputColor $border -color $color
    Write-OutputColor $paddedText -color $color
    Write-OutputColor $border -color $color
}

# Helper to write a menu item line inside a box (72-char inner width, 70-char content)
# Usage: Write-MenuItem "[1]  Configure Server"
#        Write-MenuItem "[1]  Hyper-V" -Status "Installed" -StatusColor "Success"
function Write-MenuItem {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Text,

        [string]$Status = "",

        [ValidateSet("Success", "Warning", "Error", "Info", "Debug", "Critical", "Verbose", "")]
        [string]$StatusColor = "",

        [string]$Color = "Green"
    )

    $colorMap = $script:ColorThemes[$script:ColorTheme]
    if (-not $colorMap) { $colorMap = $script:ColorThemes["Default"] }
    $borderFg = if ($colorMap.ContainsKey("Info")) { $colorMap["Info"] } else { "Cyan" }
    $textFg = if ($colorMap.ContainsKey($Color)) { $colorMap[$Color] } else { "Green" }

    if ($Status) {
        $statusFg = if ($StatusColor -and $colorMap.ContainsKey($StatusColor)) { $colorMap[$StatusColor] } else { $textFg }
        $leftWidth = 34
        $rightWidth = 36
        Write-Host "  │  " -NoNewline -ForegroundColor $borderFg
        Write-Host $Text.PadRight($leftWidth) -NoNewline -ForegroundColor $textFg
        Write-Host $Status.PadRight($rightWidth) -NoNewline -ForegroundColor $statusFg
        Write-Host "│" -ForegroundColor $borderFg
    }
    else {
        Write-Host "  │  " -NoNewline -ForegroundColor $borderFg
        Write-Host $Text.PadRight(70) -NoNewline -ForegroundColor $textFg
        Write-Host "│" -ForegroundColor $borderFg
    }
}

#endregion