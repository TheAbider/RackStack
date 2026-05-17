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
        # Auto-redact values whose KEY looks like a secret — defense-in-depth so a future caller
        # that accidentally routes a credential through Write-StructuredLog can't leak it to disk.
        # Matches the name, not the value; value-pattern matching would have too many false positives.
        $secretKeyPattern = '(?i)(password|passwd|pwd|secret|token|apikey|api[-_]?key|credential|clientsecret|authorization|bearer)'
        $kvPairs = @()
        foreach ($key in $Data.Keys) {
            $val = $Data[$key]
            if ($null -eq $val) {
                $val = "(null)"
            } elseif ($key -match $secretKeyPattern) {
                $val = "[REDACTED]"
            }
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
            if ($script:logFilePath) { Write-LogMessage -message "[$color] $message" -logFilePath $script:logFilePath }
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
    if ($script:logFilePath) {
        Write-LogMessage -message "[$color] $message" -logFilePath $script:logFilePath
    }
}

# Function to display centered output with a box-drawing border
function Write-CenteredOutput {
    param (
        [string]$text,
        [string]$color = "Info",
        [int]$width = 72
    )

    $innerWidth = $width
    $textLength = $text.Length
    $padding = [math]::Max(0, [math]::Floor(($innerWidth - $textLength) / 2))
    $paddedText = (" " * $padding) + $text

    Write-OutputColor "" -color $color
    Write-OutputColor "  $([char]0x2554)$("$([char]0x2550)" * $innerWidth)$([char]0x2557)" -color $color
    Write-OutputColor "  $([char]0x2551)$($paddedText.PadRight($innerWidth))$([char]0x2551)" -color $color
    Write-OutputColor "  $([char]0x255A)$("$([char]0x2550)" * $innerWidth)$([char]0x255D)" -color $color
    Write-OutputColor "" -color $color
}

# ── Error Code Registry ──────────────────────────────────────────────
# Structured error codes with categories for wiki-linked troubleshooting
# Ranges: 1xxx=Core, 2xxx=Network, 3xxx=Security, 4xxx=Roles, 5xxx=VM, 6xxx=Storage, 7xxx=Config, 8xxx=Agent
$script:ErrorCodes = @{
    # Core / System (1000-1999)
    "RS-1001" = @{ Message = "Script requires administrative privileges"; Category = "Core" }
    "RS-1002" = @{ Message = "defaults.json parse error"; Category = "Core" }
    "RS-1003" = @{ Message = "Module load failure"; Category = "Core" }
    "RS-1004" = @{ Message = "PowerShell version unsupported"; Category = "Core" }
    "RS-1005" = @{ Message = "Transcript start failed"; Category = "Core" }
    "RS-1006" = @{ Message = "Configuration directory inaccessible"; Category = "Core" }
    "RS-1007" = @{ Message = "Invalid CLI parameter"; Category = "Core" }
    "RS-1008" = @{ Message = "Batch config profile parse error"; Category = "Core" }
    "RS-1009" = @{ Message = "Windows Update operation failed"; Category = "Core" }

    # Networking (2000-2999)
    "RS-2001" = @{ Message = "No physical network adapters found"; Category = "Network" }
    "RS-2002" = @{ Message = "Invalid IP address format"; Category = "Network" }
    "RS-2003" = @{ Message = "Invalid subnet mask or CIDR prefix"; Category = "Network" }
    "RS-2004" = @{ Message = "VLAN creation failed"; Category = "Network" }
    "RS-2005" = @{ Message = "SET team creation failed"; Category = "Network" }
    "RS-2006" = @{ Message = "iSCSI target unreachable"; Category = "Network" }
    "RS-2007" = @{ Message = "DNS configuration failed"; Category = "Network" }
    "RS-2008" = @{ Message = "Hostname change failed"; Category = "Network" }
    "RS-2009" = @{ Message = "Domain join failed"; Category = "Network" }
    "RS-2010" = @{ Message = "NTP synchronization failed"; Category = "Network" }
    "RS-2011" = @{ Message = "Network connectivity test failed"; Category = "Network" }
    "RS-2012" = @{ Message = "Remote Desktop configuration failed"; Category = "Network" }
    "RS-2013" = @{ Message = "Network diagnostic port test failed"; Category = "Network" }
    "RS-2014" = @{ Message = "Network trace route failed"; Category = "Network" }

    # Security (3000-3999)
    "RS-3001" = @{ Message = "Firewall profile configuration failed"; Category = "Security" }
    "RS-3002" = @{ Message = "Password does not meet complexity requirements"; Category = "Security" }
    "RS-3003" = @{ Message = "Local admin account creation failed"; Category = "Security" }
    "RS-3004" = @{ Message = "Defender exclusion path not found"; Category = "Security" }
    "RS-3005" = @{ Message = "BitLocker encryption failed"; Category = "Security" }
    "RS-3006" = @{ Message = "Credential validation failed"; Category = "Security" }
    "RS-3007" = @{ Message = "Defender exclusion operation failed"; Category = "Security" }
    "RS-3008" = @{ Message = "BitLocker recovery key backup failed"; Category = "Security" }

    # Roles / Features (4000-4999)
    "RS-4001" = @{ Message = "Hyper-V role not installed"; Category = "Roles" }
    "RS-4002" = @{ Message = "Windows feature installation failed"; Category = "Roles" }
    "RS-4003" = @{ Message = "MPIO feature not available"; Category = "Roles" }
    "RS-4004" = @{ Message = "Failover Clustering validation failed"; Category = "Roles" }
    "RS-4005" = @{ Message = "Deduplication not supported on this OS"; Category = "Roles" }
    "RS-4006" = @{ Message = "Storage Replica requires Server 2016+"; Category = "Roles" }
    "RS-4007" = @{ Message = "Cluster creation failed"; Category = "Roles" }
    "RS-4008" = @{ Message = "Cluster node operation failed"; Category = "Roles" }
    "RS-4009" = @{ Message = "Cluster dashboard query failed"; Category = "Roles" }

    # VM Pipeline (5000-5999)
    "RS-5001" = @{ Message = "VHD download or copy failed"; Category = "VM" }
    "RS-5002" = @{ Message = "VM creation failed"; Category = "VM" }
    "RS-5003" = @{ Message = "ISO download timeout"; Category = "VM" }
    "RS-5004" = @{ Message = "Offline VHD servicing failed"; Category = "VM" }
    "RS-5005" = @{ Message = "VM checkpoint operation failed"; Category = "VM" }
    "RS-5006" = @{ Message = "VM export or import failed"; Category = "VM" }
    "RS-5007" = @{ Message = "Host storage path not found"; Category = "VM" }
    "RS-5008" = @{ Message = "Hyper-V Replica operation failed"; Category = "VM" }
    "RS-5009" = @{ Message = "VHD mount or creation failed"; Category = "VM" }
    "RS-5010" = @{ Message = "Offline VHD registry hive operation failed"; Category = "VM" }

    # Storage / Cluster (6000-6999)
    "RS-6001" = @{ Message = "No iSCSI sessions found"; Category = "Storage" }
    "RS-6002" = @{ Message = "Cluster validation failed"; Category = "Storage" }
    "RS-6003" = @{ Message = "Storage backend initialization failed"; Category = "Storage" }
    "RS-6004" = @{ Message = "Disk initialization failed"; Category = "Storage" }
    "RS-6005" = @{ Message = "Cluster shared volume unavailable"; Category = "Storage" }
    "RS-6006" = @{ Message = "Disk operation failed"; Category = "Storage" }
    "RS-6007" = @{ Message = "Partition operation failed"; Category = "Storage" }
    "RS-6008" = @{ Message = "Disk cleanup operation failed"; Category = "Storage" }
    "RS-6009" = @{ Message = "Storage backend detection failed"; Category = "Storage" }
    "RS-6010" = @{ Message = "Disk rescan operation failed"; Category = "Storage" }
    "RS-6011" = @{ Message = "Volume format operation failed"; Category = "Storage" }

    # Configuration / Export (7000-7999)
    "RS-7001" = @{ Message = "Configuration export failed"; Category = "Config" }
    "RS-7002" = @{ Message = "DC promotion failed"; Category = "Config" }
    "RS-7003" = @{ Message = "Server role template apply failed"; Category = "Config" }
    "RS-7004" = @{ Message = "Scheduled task creation failed"; Category = "Config" }
    "RS-7005" = @{ Message = "Hyper-V Replica configuration failed"; Category = "Config" }
    "RS-7006" = @{ Message = "Scheduled task operation failed"; Category = "Config" }
    "RS-7007" = @{ Message = "Active Directory prerequisite check failed"; Category = "Config" }

    # Agent / External (8000-8999)
    "RS-8001" = @{ Message = "Agent installer not found"; Category = "Agent" }
    "RS-8002" = @{ Message = "File server unreachable"; Category = "Agent" }
    "RS-8003" = @{ Message = "Agent installation failed"; Category = "Agent" }
    "RS-8004" = @{ Message = "Download failed after max retries"; Category = "Agent" }
}

# Wiki base URL for error code lookups
$script:ErrorCodeWikiUrl = "https://github.com/TheAbider/RackStack/wiki/Error-Codes"

# Display a structured error with code, message, and wiki link
# Usage: Write-RackStackError -Code "RS-2001"
#        Write-RackStackError -Code "RS-2001" -Detail "Adapter enumeration returned 0 results"
function Write-RackStackError {
    param (
        [Parameter(Mandatory=$true)]
        [ValidatePattern('^RS-\d{4}$')]
        [string]$Code,

        [Parameter(Mandatory=$false)]
        [string]$Detail
    )

    # Look up the error code
    $entry = $script:ErrorCodes[$Code]
    if ($null -eq $entry) {
        $message = "Unknown error"
        $category = "General"
    }
    else {
        $message = $entry.Message
        $category = $entry.Category
    }

    # Display the error line
    Write-OutputColor "  [$Code] $message" -color "Error"

    # Show detail if provided
    if ($Detail) {
        Write-OutputColor "    $Detail" -color "Error"
    }

    # Build wiki URL
    $anchor = $Code.ToLower()
    $url = "$($script:ErrorCodeWikiUrl)#$anchor"

    # Render the help link — use OSC 8 hyperlink if terminal supports it
    $useHyperlink = $false
    if ($null -ne $script:ConsoleCapabilities) {
        # OSC 8 clickable hyperlinks require Windows Terminal (WT_SESSION) or build 18362+
        if ($script:ConsoleCapabilities.SupportsVT -and -not $script:ConsoleCapabilities.IsRedirected) {
            if ($env:WT_SESSION -or $script:OSBuildNumber -ge 18362) {
                $useHyperlink = $true
            }
        }
    }

    if ($useHyperlink) {
        $esc = [char]27
        $bel = [char]7
        # OSC 8 format: ESC]8;;URL BEL linktext ESC]8;; BEL
        Write-Host "    Help: $esc]8;;${url}${bel}${url}$esc]8;;${bel}" -ForegroundColor DarkCyan
    }
    else {
        Write-OutputColor "    Help: $url" -color "Debug"
    }

    # Structured log entry
    $logData = @{ Code = $Code; Category = $category }
    if ($Detail) { $logData.Detail = $Detail }
    Write-StructuredLog -Message "[$Code] $message" -Level "ERROR" -Category $category -Data $logData

    # File log if enabled
    if ($script:logFilePath) {
        Write-LogMessage -message "[$Code] $message$(if ($Detail) { " - $Detail" })" -logFilePath $script:logFilePath
    }
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