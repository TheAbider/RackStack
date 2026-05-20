#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
#
# Pester 5.x tests for the remaining pure helper functions scattered across
# the module set. Coverage focus — these are the functions where a Pester
# isolation test gives the most signal per line:
#
#   06-NetworkAdapters: Format-LinkSpeed
#   07-IPConfiguration: Convert-SubnetMaskToPrefix
#   10-iSCSI:           Get-HostNumberFromHostname, Get-iSCSIAutoIP
#   13-Timezone:        Get-TimezoneOffsetString
#   21-Licensing:       Test-ValidLicenseKey
#   01-Console:         Get-ConsoleCapabilities
#
# The big interactive Show- functions in those modules are deliberately
# *not* covered here — they require heavy mocking of CIM/registry/Read-Host
# and the resulting tests would be more theatre than signal.

BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot '..\..\Modules'
    $script:ModuleRoot = (Resolve-Path -LiteralPath (Join-Path $modulesPath '..')).Path
    Set-StrictMode -Off
    . (Join-Path $modulesPath '00-Initialization.ps1')
    . (Join-Path $modulesPath '01-Console.ps1')
    . (Join-Path $modulesPath '02-Logging.ps1')
    . (Join-Path $modulesPath '03-InputValidation.ps1')
    . (Join-Path $modulesPath '06-NetworkAdapters.ps1')
    . (Join-Path $modulesPath '07-IPConfiguration.ps1')
    . (Join-Path $modulesPath '10-iSCSI.ps1')
    . (Join-Path $modulesPath '13-Timezone.ps1')
    . (Join-Path $modulesPath '21-Licensing.ps1')
    Set-StrictMode -Version Latest
}

Describe 'Format-LinkSpeed (06-NetworkAdapters)' {
    Context 'Null / zero handling' {
        # -SpeedBps is [Parameter(Mandatory)] so $null trips parameter binding,
        # not the function body. Skip the $null case — Mandatory blocks it earlier
        # in the pipeline than the body's null guard can run.
        It 'returns "N/A" for 0' { Format-LinkSpeed -SpeedBps 0 | Should -Be 'N/A' }
        It 'returns "N/A" for empty string' { Format-LinkSpeed -SpeedBps "" | Should -Be 'N/A' }
    }

    Context 'Scale conversion' {
        It 'formats 1 Gbps as "1 Gbps"' { Format-LinkSpeed -SpeedBps 1000000000 | Should -Match '^\s*1\s*Gbps$' }
        It 'formats 10 Gbps' { Format-LinkSpeed -SpeedBps 10000000000 | Should -Match 'Gbps' }
        It 'formats 100 Mbps' { Format-LinkSpeed -SpeedBps 100000000 | Should -Match 'Mbps' }
        It 'formats 1 Tbps' { Format-LinkSpeed -SpeedBps 1000000000000 | Should -Match 'Tbps' }
        It 'formats sub-Mbps as Kbps' { Format-LinkSpeed -SpeedBps 100000 | Should -Match 'Kbps' }
    }

    Context 'String input acceptance' {
        # Real-world callers pass either int or string; the function uses [decimal] cast.
        It 'accepts a numeric string' { Format-LinkSpeed -SpeedBps '1000000000' | Should -Match 'Gbps' }
    }
}

Describe 'Convert-SubnetMaskToPrefix (07-IPConfiguration)' {
    Context 'Common /N prefixes' {
        It '/8 = 255.0.0.0' { Convert-SubnetMaskToPrefix -SubnetMask '255.0.0.0' | Should -Be 8 }
        It '/16 = 255.255.0.0' { Convert-SubnetMaskToPrefix -SubnetMask '255.255.0.0' | Should -Be 16 }
        It '/24 = 255.255.255.0' { Convert-SubnetMaskToPrefix -SubnetMask '255.255.255.0' | Should -Be 24 }
        It '/25 = 255.255.255.128' { Convert-SubnetMaskToPrefix -SubnetMask '255.255.255.128' | Should -Be 25 }
        It '/30 = 255.255.255.252' { Convert-SubnetMaskToPrefix -SubnetMask '255.255.255.252' | Should -Be 30 }
        It '/32 = 255.255.255.255' { Convert-SubnetMaskToPrefix -SubnetMask '255.255.255.255' | Should -Be 32 }
        It '/0  = 0.0.0.0'         { Convert-SubnetMaskToPrefix -SubnetMask '0.0.0.0' | Should -Be 0 }
    }

    Context 'Invalid input' {
        It 'returns $null for non-contiguous mask' {
            # 255.255.0.255 has a hole in the 1-bits — invalid.
            Convert-SubnetMaskToPrefix -SubnetMask '255.255.0.255' | Should -BeNullOrEmpty
        }
        It 'returns $null for 3-octet input' { Convert-SubnetMaskToPrefix -SubnetMask '255.255.255' | Should -BeNullOrEmpty }
        It 'returns $null for garbage' { Convert-SubnetMaskToPrefix -SubnetMask 'not.a.mask.0' | Should -BeNullOrEmpty }
    }
}

Describe 'Get-HostNumberFromHostname (10-iSCSI)' {
    Context 'Documented -HV pattern' {
        It 'parses HOST-HV1' { Get-HostNumberFromHostname -Hostname 'HOST-HV1' | Should -Be 1 }
        It 'parses CONTOSO-HV24' { Get-HostNumberFromHostname -Hostname 'CONTOSO-HV24' | Should -Be 24 }
        It 'parses lone HV5 (HV mid-name)' { Get-HostNumberFromHostname -Hostname 'BLUE-HV5' | Should -Be 5 }
    }

    Context '-H number pattern' {
        It 'parses ACME-H7' { Get-HostNumberFromHostname -Hostname 'ACME-H7' | Should -Be 7 }
    }

    Context 'Rejection cases' {
        It 'returns $null for plain hostname' { Get-HostNumberFromHostname -Hostname 'WEB-SERVER' | Should -BeNullOrEmpty }
        # NOTE: PROD-HV24ABC backtracks to HV2 (because `2` is followed by `4`, a
        # digit, which the negative-lookahead `(?![A-Za-z])` permits). This is a
        # quirk of the regex's greedy/backtracking behavior — documenting the
        # actual behavior here so a future tightening of the regex catches the
        # change. If the function changes to truly reject trailing-letter forms,
        # this test will fail and that's the cue to update it to BeNullOrEmpty.
        It 'returns *some* number for trailing-letter form (current regex quirk)' {
            $r = Get-HostNumberFromHostname -Hostname 'PROD-HV24ABC'
            $r | Should -BeOfType [int]
        }
    }
}

Describe 'Get-iSCSIAutoIP (10-iSCSI)' {
    BeforeAll {
        $script:iSCSISubnet = '172.16.1'
    }

    Context 'Formula correctness (172.16.1.{(host+1)*10 + port})' {
        It 'Host 1, Port 1 -> 172.16.1.21' { Get-iSCSIAutoIP -HostNumber 1 -PortNumber 1 | Should -Be '172.16.1.21' }
        It 'Host 1, Port 2 -> 172.16.1.22' { Get-iSCSIAutoIP -HostNumber 1 -PortNumber 2 | Should -Be '172.16.1.22' }
        It 'Host 24, Port 1 -> 172.16.1.251' { Get-iSCSIAutoIP -HostNumber 24 -PortNumber 1 | Should -Be '172.16.1.251' }
        It 'Host 24, Port 2 -> 172.16.1.252' { Get-iSCSIAutoIP -HostNumber 24 -PortNumber 2 | Should -Be '172.16.1.252' }
        It 'Host 5, Port 1 -> 172.16.1.61' { Get-iSCSIAutoIP -HostNumber 5 -PortNumber 1 | Should -Be '172.16.1.61' }
    }

    Context 'Range validation' {
        It 'returns $null for host 0' { Get-iSCSIAutoIP -HostNumber 0 -PortNumber 1 | Should -BeNullOrEmpty }
        It 'returns $null for host 25' { Get-iSCSIAutoIP -HostNumber 25 -PortNumber 1 | Should -BeNullOrEmpty }
        It 'returns $null for port 0' { Get-iSCSIAutoIP -HostNumber 1 -PortNumber 0 | Should -BeNullOrEmpty }
        It 'returns $null for port 3' { Get-iSCSIAutoIP -HostNumber 1 -PortNumber 3 | Should -BeNullOrEmpty }
    }
}

Describe 'Get-TimezoneOffsetString (13-Timezone)' {
    Context 'Format guarantees' {
        It 'emits UTC+00:00 for UTC' {
            $utc = [System.TimeZoneInfo]::Utc
            Get-TimezoneOffsetString -TimeZoneInfo $utc | Should -Be 'UTC+00:00'
        }

        It 'emits a UTC+/-HH:MM string for any timezone' {
            # Loop through a sample of system zones — every result should match the
            # documented format. This catches any future bug that drifts off the
            # zero-padded HH:MM shape.
            $zones = [System.TimeZoneInfo]::GetSystemTimeZones() | Select-Object -First 30
            foreach ($z in $zones) {
                Get-TimezoneOffsetString -TimeZoneInfo $z | Should -Match '^UTC[+-]\d{2}:\d{2}$'
            }
        }

        It 'uses + for positive offsets' {
            $east = [System.TimeZoneInfo]::GetSystemTimeZones() | Where-Object { $_.BaseUtcOffset -gt [TimeSpan]::Zero } | Select-Object -First 1
            if ($east) {
                Get-TimezoneOffsetString -TimeZoneInfo $east | Should -Match '^UTC\+'
            } else {
                Set-ItResult -Skipped -Because "no positive-offset timezone found on this host"
            }
        }

        It 'uses - for negative offsets' {
            $west = [System.TimeZoneInfo]::GetSystemTimeZones() | Where-Object { $_.BaseUtcOffset -lt [TimeSpan]::Zero } | Select-Object -First 1
            if ($west) {
                Get-TimezoneOffsetString -TimeZoneInfo $west | Should -Match '^UTC-'
            } else {
                Set-ItResult -Skipped -Because "no negative-offset timezone found on this host"
            }
        }
    }
}

Describe 'Test-ValidLicenseKey (21-Licensing)' {
    Context 'Valid keys (XXXXX-XXXXX-XXXXX-XXXXX-XXXXX)' {
        It 'accepts a typical GVLK shape' { Test-ValidLicenseKey 'WMDGN-G9PQG-XVVXX-R3X43-63DFG' | Should -BeTrue }
        It 'accepts all-digit segments' { Test-ValidLicenseKey '12345-67890-12345-67890-12345' | Should -BeTrue }
        It 'accepts all-letter segments' { Test-ValidLicenseKey 'ABCDE-FGHIJ-KLMNO-PQRST-UVWXY' | Should -BeTrue }
        It 'accepts mixed' { Test-ValidLicenseKey 'A1B2C-D3E4F-G5H6I-J7K8L-M9N0P' | Should -BeTrue }
    }

    Context 'Invalid keys' {
        # NOTE: PowerShell's -match operator is case-insensitive by default, so the
        # function's [A-Z0-9] regex actually accepts lowercase too. Documenting the
        # actual behavior — if you want strict-uppercase, the function would need -cmatch.
        It 'accepts lowercase segments (case-insensitive -match)' { Test-ValidLicenseKey 'abcde-fghij-klmno-pqrst-uvwxy' | Should -BeTrue }
        It 'rejects 4 groups' { Test-ValidLicenseKey 'WMDGN-G9PQG-XVVXX-R3X43' | Should -BeFalse }
        It 'rejects 6 groups' { Test-ValidLicenseKey 'WMDGN-G9PQG-XVVXX-R3X43-63DFG-EXTRA' | Should -BeFalse }
        It 'rejects 4-char groups' { Test-ValidLicenseKey 'WMDG-G9PQ-XVVX-R3X4-63DF' | Should -BeFalse }
        It 'rejects with special chars' { Test-ValidLicenseKey 'WMDGN-G9PQG-XVVXX-R3X43-63DF!' | Should -BeFalse }
        It 'rejects empty string' { Test-ValidLicenseKey '' | Should -BeFalse }
        It 'rejects garbage' { Test-ValidLicenseKey 'not a license key' | Should -BeFalse }
    }
}

Describe 'Get-ConsoleCapabilities (01-Console)' {
    BeforeAll {
        $script:caps = Get-ConsoleCapabilities
    }

    Context 'Result shape' {
        It 'returns a hashtable' { $script:caps | Should -BeOfType [hashtable] }
        It 'has SupportsUnicode bool' { $script:caps.SupportsUnicode | Should -BeOfType [bool] }
        It 'has SupportsVT bool' { $script:caps.SupportsVT | Should -BeOfType [bool] }
        It 'has IsRedirected bool' { $script:caps.IsRedirected | Should -BeOfType [bool] }
        It 'has BufferWidth int' { $script:caps.BufferWidth | Should -BeOfType [int] }
        It 'has BufferHeight int' { $script:caps.BufferHeight | Should -BeOfType [int] }
        It 'has HostName string' { $script:caps.HostName | Should -BeOfType [string] }
        It 'has ColorDepth int' { $script:caps.ColorDepth | Should -BeOfType [int] }
    }

    Context 'Sane defaults' {
        It 'BufferWidth >= 80' { $script:caps.BufferWidth | Should -BeGreaterOrEqual 80 }
        It 'BufferHeight >= 25' { $script:caps.BufferHeight | Should -BeGreaterOrEqual 25 }
        It 'ColorDepth in {16, 256, 16777216}' {
            $script:caps.ColorDepth | Should -BeIn @(16, 256, 16777216)
        }
        It 'HostName is non-empty' { [string]::IsNullOrEmpty($script:caps.HostName) | Should -BeFalse }
    }
}
