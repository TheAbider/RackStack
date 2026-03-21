#region ===== INPUT VALIDATION FUNCTIONS =====
# Function to validate Windows hostname
function Test-ValidHostname {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Hostname
    )

    # Reject null bytes (injection prevention)
    if ($Hostname.Contains([char]0)) { return $false }

    # Check length (1-15 characters)
    if ($Hostname.Length -lt 1 -or $Hostname.Length -gt 15) {
        return $false
    }

    # Can contain letters, numbers, hyphens. Cannot start/end with hyphen
    # ASCII-only regex naturally rejects Unicode lookalike characters
    if ($Hostname -notmatch '^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$' -and $Hostname -notmatch '^[a-zA-Z0-9]$') {
        return $false
    }

    return $true
}

# Get specific rejection reason for an invalid hostname (for detailed error messages)
function Get-HostnameValidationError {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Hostname
    )

    if ($Hostname.Length -gt 15) { return "Too long: $($Hostname.Length) characters (max 15)" }
    if ($Hostname.Length -lt 1) { return "Hostname cannot be empty" }
    if ($Hostname -match '[^a-zA-Z0-9-]') { return "Invalid characters (letters, digits, and hyphens only)" }
    if ($Hostname.StartsWith('-')) { return "Cannot start with a hyphen" }
    if ($Hostname.EndsWith('-')) { return "Cannot end with a hyphen" }
    return $null
}

# Function to validate IPv4 address
function Test-ValidIPAddress {
    param (
        [Parameter(Mandatory=$true)]
        [string]$IPAddress
    )

    # Reject null bytes (injection prevention)
    if ($IPAddress.Contains([char]0)) { return $false }

    # Remove CIDR if present
    $ip = $IPAddress -replace '/\d+$', ''

    try {
        $parsed = [System.Net.IPAddress]::Parse($ip)

        # Must be IPv4
        if ($parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
            return $false
        }

        # Verify 4 octets, each 0-255
        $octets = $ip -split '\.'
        if ($octets.Count -ne 4) { return $false }

        foreach ($octet in $octets) {
            $num = [int]$octet
            if ($num -lt 0 -or $num -gt 255) { return $false }
        }

        return $true
    }
    catch {
        return $false
    }
}

# Function to validate VLAN ID (1-4094)
function Test-ValidVLANId {
    param (
        [Parameter(Mandatory=$true)]
        $VLANId
    )

    # Try to convert to int and validate range
    $id = $VLANId -as [int]
    if ($null -eq $id) { return $false }
    return ($id -ge 1 -and $id -le 4094)
}

# Function for yes/no confirmation with consistent handling
function Confirm-UserAction {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [switch]$DefaultYes
    )

    # In silent/headless mode, auto-confirm based on DefaultYes
    if ($script:CLISilent) {
        return $DefaultYes.IsPresent
    }

    $prompt = if ($DefaultYes) { "$Message [Y/n]" } else { "$Message [y/N]" }
    Write-OutputColor $prompt -color "Info"
    $response = Read-Host
    if ($response) { $response = $response.Trim() }

    if ([string]::IsNullOrWhiteSpace($response)) {
        return $DefaultYes.IsPresent
    }

    return $response -match '^(y|yes)$'
}

# Function to get validated input with retry logic
function Get-ValidatedInput {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Prompt,
        [Parameter(Mandatory=$true)]
        [scriptblock]$ValidationScript,
        [string]$ErrorMessage = "Invalid input. Please try again.",
        [int]$MaxAttempts = 3,
        [switch]$AllowEmpty
    )

    $attempts = 0

    while ($attempts -lt $MaxAttempts) {
        Write-OutputColor $Prompt -color "Info"
        $userResponse = Read-Host

        if ([string]::IsNullOrWhiteSpace($userResponse)) {
            if ($AllowEmpty) {
                return $null
            }
            $attempts++
            $remaining = $MaxAttempts - $attempts
            if ($remaining -gt 0) {
                Write-OutputColor "  Input cannot be empty. ($remaining attempt(s) remaining)" -color "Error"
            }
            continue
        }

        if (& $ValidationScript $userResponse) {
            return $userResponse
        }

        $attempts++
        $remaining = $MaxAttempts - $attempts
        if ($remaining -gt 0) {
            Write-OutputColor "  $ErrorMessage ($remaining attempt(s) remaining)" -color "Error"
        }
    }

    Write-OutputColor "  Maximum attempts reached." -color "Critical"
    return $null
}

# Function to validate UNC paths (\\server\share format)
function Test-ValidUNCPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    # Reject null bytes (injection prevention)
    if ($Path.Contains([char]0)) { return $false }
    # Strip surrounding quotes (drag-and-drop paths)
    $Path = $Path.Trim('"', "'")
    # Must start with \\ and have at least server\share
    return $Path -match '^\\\\[a-zA-Z0-9._-]+\\[a-zA-Z0-9$._-]+'
}

# Escape special characters for LDAP queries (RFC 4515)
function ConvertTo-SafeLDAPFilter {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    # RFC 4515: escape special LDAP filter characters
    $Value = $Value.Replace('\', '\5c')  # Must be first
    $Value = $Value.Replace('*', '\2a')
    $Value = $Value.Replace('(', '\28')
    $Value = $Value.Replace(')', '\29')
    $Value = $Value.Replace([string][char]0, '\00')
    return $Value
}

# Function to validate file path doesn't contain dangerous characters
function Test-ValidFilePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    # Reject null bytes (injection prevention)
    if ($Path.Contains([char]0)) { return $false }
    $Path = $Path.Trim('"', "'")
    # Check for path traversal attempts
    if ($Path -match '\.\.[/\\]') { return $false }
    # Check for invalid Windows filename characters in the leaf
    $leaf = Split-Path -Leaf $Path -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($leaf)) { return $false }
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($char in $invalidChars) {
        if ($leaf.Contains($char)) { return $false }
    }
    return $true
}
#endregion