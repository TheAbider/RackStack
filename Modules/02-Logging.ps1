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
        Add-Content -Path $logFilePath -Value $logMessage -Encoding UTF8 -ErrorAction SilentlyContinue
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