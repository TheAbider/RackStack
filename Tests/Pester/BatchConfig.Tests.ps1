#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
#
# Pester 5.x tests for Test-BatchConfig — the unattended-install config validator.
# Lives in 50-EntryPoint.ps1 (depends on Test-ValidHostname / Test-ValidIPAddress
# from 03-InputValidation and on $script:PowerPlanGUID from 00-Initialization).

BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot '..\..\Modules'
    $script:ModuleRoot = (Resolve-Path -LiteralPath (Join-Path $modulesPath '..')).Path
    Set-StrictMode -Off
    . (Join-Path $modulesPath '00-Initialization.ps1')
    . (Join-Path $modulesPath '01-Console.ps1')
    . (Join-Path $modulesPath '02-Logging.ps1')
    . (Join-Path $modulesPath '03-InputValidation.ps1')
    . (Join-Path $modulesPath '50-EntryPoint.ps1')
    # Test-BatchConfig uses `if ($Config.ConfigType)` -style hashtable lookups that
    # throw under Set-StrictMode -Version Latest when the key is absent. Production
    # callers don't run under strict mode, and this is testing the function's runtime
    # behavior — so keep strict mode relaxed for the whole file. The other Pester
    # test files re-arm strict mode here because they exercise pure functions that
    # don't probe optional hashtable keys.
}

Describe 'Test-BatchConfig' {
    Context 'Result shape' {
        It 'returns an object with IsValid, Errors, Warnings keys' {
            $r = Test-BatchConfig -Config @{}
            $r.PSObject.Properties.Name -contains 'IsValid' -or $r.ContainsKey('IsValid') | Should -BeTrue
            # The function returns a hashtable; verify keys present
            $r.ContainsKey('IsValid') | Should -BeTrue
            $r.ContainsKey('Errors') | Should -BeTrue
            $r.ContainsKey('Warnings') | Should -BeTrue
        }

        It 'Errors is an enumerable (ArrayList)' {
            $r = Test-BatchConfig -Config @{}
            { foreach ($e in $r.Errors) { } } | Should -Not -Throw
        }
    }

    Context 'Empty / minimal config' {
        It 'an empty config has no errors (everything optional)' {
            $r = Test-BatchConfig -Config @{}
            @($r.Errors).Count | Should -Be 0
        }

        It 'an empty config emits a hostname-not-set warning' {
            $r = Test-BatchConfig -Config @{}
            @($r.Warnings) -join '|' | Should -Match 'Hostname'
        }
    }

    Context 'ConfigType validation' {
        It 'accepts ConfigType = "VM"' {
            $r = Test-BatchConfig -Config @{ ConfigType = 'VM' }
            @($r.Errors | Where-Object { $_ -match 'ConfigType' }).Count | Should -Be 0
        }

        It 'accepts ConfigType = "HOST" (case-insensitive)' {
            $r = Test-BatchConfig -Config @{ ConfigType = 'host' }
            @($r.Errors | Where-Object { $_ -match 'ConfigType' }).Count | Should -Be 0
        }

        It 'rejects an unknown ConfigType' {
            $r = Test-BatchConfig -Config @{ ConfigType = 'Cluster' }
            @($r.Errors | Where-Object { $_ -match 'ConfigType' }).Count | Should -Be 1
        }
    }

    Context 'Hostname validation' {
        It 'accepts a valid hostname' {
            $r = Test-BatchConfig -Config @{ Hostname = 'WEB-01' }
            @($r.Errors | Where-Object { $_ -match 'Hostname' }).Count | Should -Be 0
        }

        It 'rejects a hostname longer than 15 chars (NetBIOS limit)' {
            $r = Test-BatchConfig -Config @{ Hostname = 'this-name-is-way-too-long-for-netbios' }
            @($r.Errors | Where-Object { $_ -match 'Hostname' }).Count | Should -Be 1
        }

        It 'rejects a hostname with invalid characters' {
            $r = Test-BatchConfig -Config @{ Hostname = 'bad_host!' }
            @($r.Errors | Where-Object { $_ -match 'Hostname' }).Count | Should -Be 1
        }
    }

    Context 'IP address fields' {
        It 'accepts valid IPv4 in IPAddress' {
            $r = Test-BatchConfig -Config @{ IPAddress = '10.0.0.5'; Gateway = '10.0.0.1' }
            @($r.Errors | Where-Object { $_ -match 'IPAddress' }).Count | Should -Be 0
        }

        It 'rejects malformed IPAddress' {
            $r = Test-BatchConfig -Config @{ IPAddress = '999.999.999.999'; Gateway = '10.0.0.1' }
            @($r.Errors | Where-Object { $_ -match 'IPAddress' }).Count | Should -BeGreaterOrEqual 1
        }

        It 'rejects malformed Gateway' {
            $r = Test-BatchConfig -Config @{ IPAddress = '10.0.0.5'; Gateway = 'not-an-ip' }
            @($r.Errors | Where-Object { $_ -match 'Gateway' }).Count | Should -BeGreaterOrEqual 1
        }

        It 'rejects malformed DNS1' {
            $r = Test-BatchConfig -Config @{ DNS1 = '256.1.1.1' }
            @($r.Errors | Where-Object { $_ -match 'DNS1' }).Count | Should -BeGreaterOrEqual 1
        }
    }

    Context 'Network field interdependency' {
        It 'errors when IPAddress is set but Gateway missing' {
            $r = Test-BatchConfig -Config @{ IPAddress = '10.0.0.5' }
            @($r.Errors | Where-Object { $_ -match 'Gateway is missing' }).Count | Should -Be 1
        }

        It 'errors when Gateway is set but IPAddress missing' {
            $r = Test-BatchConfig -Config @{ Gateway = '10.0.0.1' }
            @($r.Errors | Where-Object { $_ -match 'IPAddress is missing' }).Count | Should -Be 1
        }

        It 'allows IPAddress + Gateway both set' {
            $r = Test-BatchConfig -Config @{ IPAddress = '10.0.0.5'; Gateway = '10.0.0.1' }
            @($r.Errors | Where-Object { $_ -match 'missing' }).Count | Should -Be 0
        }
    }

    Context 'SubnetCIDR validation' {
        It 'accepts /24' {
            $r = Test-BatchConfig -Config @{ SubnetCIDR = 24 }
            @($r.Errors | Where-Object { $_ -match 'SubnetCIDR' }).Count | Should -Be 0
        }

        It 'rejects /0 (out of range, the function requires >= 1)' {
            $r = Test-BatchConfig -Config @{ SubnetCIDR = 0 }
            @($r.Errors | Where-Object { $_ -match 'SubnetCIDR' }).Count | Should -Be 1
        }

        It 'rejects /33' {
            $r = Test-BatchConfig -Config @{ SubnetCIDR = 33 }
            @($r.Errors | Where-Object { $_ -match 'SubnetCIDR' }).Count | Should -Be 1
        }
    }

    Context 'Boolean field validation' {
        It 'accepts $true for EnableRDP' {
            $r = Test-BatchConfig -Config @{ EnableRDP = $true }
            @($r.Errors | Where-Object { $_ -match 'EnableRDP' }).Count | Should -Be 0
        }

        It 'accepts $false for EnableRDP' {
            $r = Test-BatchConfig -Config @{ EnableRDP = $false }
            @($r.Errors | Where-Object { $_ -match 'EnableRDP' }).Count | Should -Be 0
        }

        It 'rejects a string in a boolean field' {
            $r = Test-BatchConfig -Config @{ EnableRDP = 'yes' }
            @($r.Errors | Where-Object { $_ -match 'EnableRDP' }).Count | Should -Be 1
        }

        It 'rejects a number in a boolean field' {
            $r = Test-BatchConfig -Config @{ AutoReboot = 1 }
            @($r.Errors | Where-Object { $_ -match 'AutoReboot' }).Count | Should -Be 1
        }
    }

    Context 'Power plan validation' {
        It 'accepts "High Performance"' {
            $r = Test-BatchConfig -Config @{ SetPowerPlan = 'High Performance' }
            @($r.Errors | Where-Object { $_ -match 'SetPowerPlan' }).Count | Should -Be 0
        }

        It 'accepts "Balanced"' {
            $r = Test-BatchConfig -Config @{ SetPowerPlan = 'Balanced' }
            @($r.Errors | Where-Object { $_ -match 'SetPowerPlan' }).Count | Should -Be 0
        }

        It 'rejects "Ultra" (not a real plan)' {
            $r = Test-BatchConfig -Config @{ SetPowerPlan = 'Ultra' }
            @($r.Errors | Where-Object { $_ -match 'SetPowerPlan' }).Count | Should -Be 1
        }
    }

    Context 'VirtualSwitchType validation' {
        It 'accepts SET / External / Internal / Private' {
            foreach ($t in 'SET','External','Internal','Private') {
                $r = Test-BatchConfig -Config @{ VirtualSwitchType = $t }
                @($r.Errors | Where-Object { $_ -match 'VirtualSwitchType' }).Count | Should -Be 0
            }
        }

        It 'rejects an unknown switch type' {
            $r = Test-BatchConfig -Config @{ VirtualSwitchType = 'OpenVSwitch' }
            @($r.Errors | Where-Object { $_ -match 'VirtualSwitchType' }).Count | Should -Be 1
        }
    }
}
