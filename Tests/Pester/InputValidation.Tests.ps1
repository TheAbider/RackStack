#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
#
# Pester 5.x tests for pure validation functions (no side effects, no I/O).
# Covers Test-ValidHostname, Test-ValidIPAddress, Test-ValidVLANId.

BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot '..\..\Modules'
    . (Join-Path $modulesPath '03-InputValidation.ps1')
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
