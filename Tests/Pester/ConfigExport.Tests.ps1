#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
#
# Pester 5.x tests for pure helpers in 45-ConfigExport.ps1.

BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot '..\..\Modules'
    $script:ModuleRoot = (Resolve-Path -LiteralPath (Join-Path $modulesPath '..')).Path
    Set-StrictMode -Off
    . (Join-Path $modulesPath '00-Initialization.ps1')
    . (Join-Path $modulesPath '01-Console.ps1')
    . (Join-Path $modulesPath '02-Logging.ps1')
    . (Join-Path $modulesPath '45-ConfigExport.ps1')
    Set-StrictMode -Version Latest
}

Describe 'Get-DefaultWatchThresholds' {
    BeforeAll {
        $script:thresholds = Get-DefaultWatchThresholds
    }

    It 'returns a hashtable' {
        $script:thresholds | Should -BeOfType [hashtable]
    }

    Context 'Required threshold categories' {
        It 'includes CPU' { $script:thresholds.ContainsKey('CPU') | Should -BeTrue }
        It 'includes Memory' { $script:thresholds.ContainsKey('Memory') | Should -BeTrue }
        It 'includes Disk' { $script:thresholds.ContainsKey('Disk') | Should -BeTrue }
        It 'includes Uptime' { $script:thresholds.ContainsKey('Uptime') | Should -BeTrue }
        It 'includes Certificates' { $script:thresholds.ContainsKey('Certificates') | Should -BeTrue }
        It 'includes Services' { $script:thresholds.ContainsKey('Services') | Should -BeTrue }
        It 'includes Events' { $script:thresholds.ContainsKey('Events') | Should -BeTrue }
    }

    Context 'Documented threshold values' {
        # These defaults are part of the public ops contract — alerts based on them
        # depend on knowing what "default" means. Test pins them so a silent change
        # is visible.
        It 'CPU.MaxPercent = 90' { $script:thresholds.CPU.MaxPercent | Should -Be 90 }
        It 'Memory.MaxPercent = 90' { $script:thresholds.Memory.MaxPercent | Should -Be 90 }
        It 'Disk.MaxUsedPercent = 95' { $script:thresholds.Disk.MaxUsedPercent | Should -Be 95 }
        It 'Uptime.MaxDays = 60' { $script:thresholds.Uptime.MaxDays | Should -Be 60 }
        It 'Certificates.MinDaysToExpiry = 7' { $script:thresholds.Certificates.MinDaysToExpiry | Should -Be 7 }
        It 'Events.MaxCriticalCount = 0' { $script:thresholds.Events.MaxCriticalCount | Should -Be 0 }
        It 'Events.HoursBack = 24' { $script:thresholds.Events.HoursBack | Should -Be 24 }
    }

    Context 'Idempotence' {
        It 'returns equal-valued hashtables across calls' {
            $a = Get-DefaultWatchThresholds
            $b = Get-DefaultWatchThresholds
            $a.CPU.MaxPercent | Should -Be $b.CPU.MaxPercent
            $a.Disk.MaxUsedPercent | Should -Be $b.Disk.MaxUsedPercent
        }
    }
}
