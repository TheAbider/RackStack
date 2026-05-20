#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
#
# Pester 5.x tests for pure validation functions (no side effects, no I/O).
# Covers Test-ValidHostname, Test-ValidIPAddress, Test-ValidVLANId.

BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot '..\..\Modules'
    $script:ModuleRoot = (Resolve-Path -LiteralPath (Join-Path $modulesPath '..')).Path
    Set-StrictMode -Off
    # 02-Logging is required for Write-OutputColor (used by Confirm-UserAction).
    . (Join-Path $modulesPath '00-Initialization.ps1')
    . (Join-Path $modulesPath '01-Console.ps1')
    . (Join-Path $modulesPath '02-Logging.ps1')
    . (Join-Path $modulesPath '03-InputValidation.ps1')
    Set-StrictMode -Version Latest
}

Describe 'Test-ValidHostname' {
    Context 'Valid hostnames' {
        It 'accepts a single letter' { Test-ValidHostname -Hostname 'A' | Should -BeTrue }
        It 'accepts a single digit' { Test-ValidHostname -Hostname '1' | Should -BeTrue }
        It 'accepts letters and digits' { Test-ValidHostname -Hostname 'HV01' | Should -BeTrue }
        It 'accepts hyphens in middle' { Test-ValidHostname -Hostname 'web-server-01' | Should -BeTrue }
        It 'accepts 15-character names (NetBIOS max)' { Test-ValidHostname -Hostname 'a23456789012345' | Should -BeTrue }
        It 'is case-insensitive in regex (works for upper)' { Test-ValidHostname -Hostname 'WEBSERVER01' | Should -BeTrue }
    }

    Context 'Invalid hostnames' {
        It 'rejects 16-character names (over NetBIOS limit)' { Test-ValidHostname -Hostname 'a234567890123456' | Should -BeFalse }
        It 'rejects leading hyphen' { Test-ValidHostname -Hostname '-web01' | Should -BeFalse }
        It 'rejects trailing hyphen' { Test-ValidHostname -Hostname 'web01-' | Should -BeFalse }
        It 'rejects underscore' { Test-ValidHostname -Hostname 'web_01' | Should -BeFalse }
        It 'rejects space' { Test-ValidHostname -Hostname 'web 01' | Should -BeFalse }
        It 'rejects period (FQDN form is invalid as NetBIOS name)' { Test-ValidHostname -Hostname 'web.local' | Should -BeFalse }
        It 'rejects null byte (injection prevention)' { Test-ValidHostname -Hostname "web`0evil" | Should -BeFalse }
        It 'rejects Unicode lookalike (Cyrillic а instead of Latin a)' {
            # The hostname starts with a Cyrillic 'а' (U+0430) which looks like Latin 'a' but isn't.
            $cyrillic = [char]0x0430 + 'b01'
            Test-ValidHostname -Hostname $cyrillic | Should -BeFalse
        }
    }
}

Describe 'Test-ValidIPAddress' {
    Context 'Valid IPv4' {
        It 'accepts 192.168.1.1' { Test-ValidIPAddress -IPAddress '192.168.1.1' | Should -BeTrue }
        It 'accepts 0.0.0.0' { Test-ValidIPAddress -IPAddress '0.0.0.0' | Should -BeTrue }
        It 'accepts 255.255.255.255' { Test-ValidIPAddress -IPAddress '255.255.255.255' | Should -BeTrue }
        It 'accepts with CIDR suffix' { Test-ValidIPAddress -IPAddress '10.0.0.1/24' | Should -BeTrue }
    }

    Context 'Invalid IPv4' {
        It 'rejects 256 octet' { Test-ValidIPAddress -IPAddress '192.168.1.256' | Should -BeFalse }
        It 'rejects 3-octet form' { Test-ValidIPAddress -IPAddress '192.168.1' | Should -BeFalse }
        It 'rejects 5-octet form' { Test-ValidIPAddress -IPAddress '192.168.1.1.1' | Should -BeFalse }
        It 'rejects bare text' { Test-ValidIPAddress -IPAddress 'not.an.ip.addr' | Should -BeFalse }
        It 'rejects IPv6 address' { Test-ValidIPAddress -IPAddress '::1' | Should -BeFalse }
        It 'rejects null byte (injection prevention)' { Test-ValidIPAddress -IPAddress "10.0.0.1`0; evil" | Should -BeFalse }
    }
}

Describe 'Test-ValidVLANId' {
    Context 'Valid VLAN IDs' {
        It 'accepts 1 (lowest valid)' { Test-ValidVLANId -VLANId 1 | Should -BeTrue }
        It 'accepts 4094 (highest valid)' { Test-ValidVLANId -VLANId 4094 | Should -BeTrue }
        It 'accepts string "100" (coerced to int)' { Test-ValidVLANId -VLANId '100' | Should -BeTrue }
    }

    Context 'Invalid VLAN IDs' {
        It 'rejects 0 (reserved)' { Test-ValidVLANId -VLANId 0 | Should -BeFalse }
        It 'rejects 4095 (reserved)' { Test-ValidVLANId -VLANId 4095 | Should -BeFalse }
        It 'rejects negative' { Test-ValidVLANId -VLANId -1 | Should -BeFalse }
        It 'rejects non-numeric string' { Test-ValidVLANId -VLANId 'abc' | Should -BeFalse }
    }
}

Describe 'Get-HostnameValidationError' {
    It 'returns null for valid hostname' { Get-HostnameValidationError -Hostname 'web01' | Should -BeNullOrEmpty }
    It 'reports length for too-long name' {
        $msg = Get-HostnameValidationError -Hostname 'a234567890123456'
        $msg | Should -Match 'Too long'
    }
    It 'reports leading hyphen' {
        $msg = Get-HostnameValidationError -Hostname '-web'
        $msg | Should -Match 'start with a hyphen'
    }
    It 'reports trailing hyphen' {
        $msg = Get-HostnameValidationError -Hostname 'web-'
        $msg | Should -Match 'end with a hyphen'
    }
    It 'reports invalid characters' {
        $msg = Get-HostnameValidationError -Hostname 'web@01'
        $msg | Should -Match 'Invalid characters'
    }
}

Describe 'Confirm-UserAction (silent-mode branches)' {
    # Confirm-UserAction has a Read-Host branch (interactive) and a $script:CLISilent
    # branch (returns $DefaultYes.IsPresent immediately). The silent branch is the
    # one batch / scheduled callers exercise and is fully testable.
    BeforeEach {
        $script:CLISilent = $true
    }
    AfterEach {
        $script:CLISilent = $false
    }

    It 'returns $true when -DefaultYes set and silent mode is on' {
        Confirm-UserAction -Message 'proceed?' -DefaultYes | Should -BeTrue
    }

    It 'returns $false when -DefaultYes NOT set and silent mode is on' {
        Confirm-UserAction -Message 'proceed?' | Should -BeFalse
    }

    It 'is deterministic in silent mode (no Read-Host hang)' {
        # If the Read-Host path were taken accidentally, this test would hang.
        # Pester would time out and kill the test, which is the failure signal.
        $r1 = Confirm-UserAction -Message 'a' -DefaultYes
        $r2 = Confirm-UserAction -Message 'b' -DefaultYes
        $r3 = Confirm-UserAction -Message 'c' -DefaultYes
        $r1 | Should -BeTrue
        $r2 | Should -BeTrue
        $r3 | Should -BeTrue
    }
}

Describe 'Confirm-UserAction (interactive Read-Host branches, via Mock)' {
    # Exercise the Read-Host path by mocking Read-Host to return canned responses.
    # Pester Mock intercepts the cmdlet inside the dot-sourced module's scope.
    BeforeEach {
        $script:CLISilent = $false
    }

    It 'returns $true when user types "y"' {
        Mock Read-Host { 'y' }
        Confirm-UserAction -Message 'proceed?' | Should -BeTrue
    }

    It 'returns $true when user types "yes"' {
        Mock Read-Host { 'yes' }
        Confirm-UserAction -Message 'proceed?' | Should -BeTrue
    }

    It 'returns $true case-insensitively for "Y"' {
        Mock Read-Host { 'Y' }
        Confirm-UserAction -Message 'proceed?' | Should -BeTrue
    }

    It 'returns $false for empty input when -DefaultYes is NOT set' {
        Mock Read-Host { '' }
        Confirm-UserAction -Message 'proceed?' | Should -BeFalse
    }

    It 'returns $true for empty input when -DefaultYes IS set (default-honoring)' {
        Mock Read-Host { '' }
        Confirm-UserAction -Message 'proceed?' -DefaultYes | Should -BeTrue
    }

    It 'returns $false for any non-yes input ("n", "no", "x")' {
        Mock Read-Host { 'n' }
        Confirm-UserAction -Message 'a' | Should -BeFalse
        Mock Read-Host { 'no' }
        Confirm-UserAction -Message 'b' | Should -BeFalse
        Mock Read-Host { 'maybe' }
        Confirm-UserAction -Message 'c' | Should -BeFalse
    }

    It 'trims whitespace around the response' {
        Mock Read-Host { '   yes  ' }
        Confirm-UserAction -Message 'proceed?' | Should -BeTrue
    }
}

Describe 'Get-ValidatedInput (interactive, via Mock)' {
    It 'returns the value when validation passes on first try' {
        Mock Read-Host { '10.0.0.5' }
        $result = Get-ValidatedInput -Prompt 'IP' -ValidationScript { param($v) Test-ValidIPAddress $v }
        $result | Should -Be '10.0.0.5'
    }

    It 'retries up to MaxAttempts on invalid input, then returns $null' {
        Mock Read-Host { 'not-an-ip' }
        $result = Get-ValidatedInput -Prompt 'IP' -ValidationScript { param($v) Test-ValidIPAddress $v } -MaxAttempts 2
        $result | Should -BeNullOrEmpty
    }

    It 'rejects empty when -AllowEmpty is not set' {
        Mock Read-Host { '' }
        $result = Get-ValidatedInput -Prompt 'thing' -ValidationScript { $true } -MaxAttempts 2
        $result | Should -BeNullOrEmpty
    }

    It 'returns $null on empty when -AllowEmpty is set (intentional skip)' {
        Mock Read-Host { '' }
        $result = Get-ValidatedInput -Prompt 'optional' -ValidationScript { $true } -AllowEmpty
        $result | Should -BeNullOrEmpty
    }

    It 'allows a custom validation scriptblock' {
        Mock Read-Host { '4567' }
        $result = Get-ValidatedInput -Prompt 'port' -ValidationScript { param($v) ($v -as [int]) -gt 1024 }
        $result | Should -Be '4567'
    }
}
