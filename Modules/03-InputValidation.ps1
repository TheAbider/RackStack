#region ===== INPUT VALIDATION FUNCTIONS =====
# Function to validate Windows hostname
function Test-ValidHostname {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Hostname
    )

    # Check length (1-15 characters)
    if ($Hostname.Length -lt 1 -or $Hostname.Length -gt 15) {
        return $false
    }

    # Can contain letters, numbers, hyphens. Cannot start/end with hyphen
    if ($Hostname -notmatch '^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$' -and $Hostname -notmatch '^[a-zA-Z0-9]$') {
        return $false
    }

    return $true
}

# Function to validate IPv4 address
function Test-ValidIPAddress {
    param (
        [Parameter(Mandatory=$true)]
        [string]$IPAddress
    )

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

    $prompt = if ($DefaultYes) { "$Message [Y/n]" } else { "$Message [y/N]" }
    Write-OutputColor $prompt -color "Info"
    $response = Read-Host

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
                Write-OutputColor "Input cannot be empty. ($remaining attempt(s) remaining)" -color "Error"
            }
            continue
        }

        if (& $ValidationScript $userResponse) {
            return $userResponse
        }

        $attempts++
        $remaining = $MaxAttempts - $attempts
        if ($remaining -gt 0) {
            Write-OutputColor "$ErrorMessage ($remaining attempt(s) remaining)" -color "Error"
        }
    }

    Write-OutputColor "Maximum attempts reached." -color "Critical"
    return $null
}
#endregion