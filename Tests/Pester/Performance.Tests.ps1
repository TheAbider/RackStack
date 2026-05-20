#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
#
# Performance regression tests. Each test pins a measured operation to an
# upper bound; a regression that pushes startup, parse, or validation time
# above the bound fails the build instead of silently shipping a 10x
# slowdown.
#
# Bounds are deliberately loose (~3x typical measured time) so CI runner
# variance + cold-cache disk reads don't cause flapping. Tighten them if
# we see consistent headroom.

BeforeAll {
    $script:repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $script:modulesPath = Join-Path $script:repoRoot 'Modules'
}

Describe 'Parse performance' {
    It 'parses the monolithic builds artifact (if present) in under 30s' {
        $mono = Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'builds') -Filter 'RackStack v*.ps1' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if (-not $mono) {
            Set-ItResult -Skipped -Because "no monolithic build present in builds/"
            return
        }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $errs = $null; $tokens = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($mono.FullName, [ref]$tokens, [ref]$errs)
        $sw.Stop()
        Write-Verbose "Monolithic parse: $($sw.ElapsedMilliseconds) ms"
        $errs.Count | Should -Be 0 -Because "monolithic must parse cleanly"
        $sw.ElapsedMilliseconds | Should -BeLessThan 30000 -Because "monolithic parse should stay under 30s on CI hardware"
    }

    It 'parses every individual module in under 5s combined' {
        $mods = Get-ChildItem -LiteralPath $script:modulesPath -Filter '*.ps1'
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $totalErrors = 0
        foreach ($m in $mods) {
            $errs = $null; $tokens = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($m.FullName, [ref]$tokens, [ref]$errs)
            $totalErrors += $errs.Count
        }
        $sw.Stop()
        Write-Verbose "65-module parse: $($sw.ElapsedMilliseconds) ms across $($mods.Count) files"
        $totalErrors | Should -Be 0
        $sw.ElapsedMilliseconds | Should -BeLessThan 5000 -Because "65-module modular parse should stay under 5s"
    }
}

Describe 'Validator throughput' {
    BeforeAll {
        Set-StrictMode -Off
        . (Join-Path $script:modulesPath '00-Initialization.ps1')
        . (Join-Path $script:modulesPath '02-Logging.ps1')
        . (Join-Path $script:modulesPath '03-InputValidation.ps1')
        Set-StrictMode -Version Latest
    }

    # Throughput bounds are set ~3x the measured time on the self-hosted CI runner
    # to absorb noise; the goal is to catch ORDER-of-magnitude regressions (e.g.
    # someone adding a Get-CimInstance to a validator), not to police small drifts.

    It 'Test-ValidHostname handles 10000 calls under 6s' {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        for ($i = 0; $i -lt 10000; $i++) {
            $null = Test-ValidHostname -Hostname "host-$i"
        }
        $sw.Stop()
        Write-Verbose "Test-ValidHostname x10000: $($sw.ElapsedMilliseconds) ms ($([math]::Round(10000 / ($sw.ElapsedMilliseconds / 1000), 0)) calls/sec)"
        $sw.ElapsedMilliseconds | Should -BeLessThan 6000 -Because "hostname validation is hot-path; large regressions should fail CI"
    }

    It 'Test-ValidIPAddress handles 10000 calls under 12s' {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        for ($i = 0; $i -lt 10000; $i++) {
            $a = $i % 256; $b = ($i * 7) % 256; $c = ($i * 13) % 256; $d = ($i * 19) % 256
            $null = Test-ValidIPAddress -IPAddress "$a.$b.$c.$d"
        }
        $sw.Stop()
        Write-Verbose "Test-ValidIPAddress x10000: $($sw.ElapsedMilliseconds) ms"
        $sw.ElapsedMilliseconds | Should -BeLessThan 12000
    }

    It 'Test-ValidVLANId handles 50000 calls under 10s' {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        for ($i = 1; $i -le 50000; $i++) {
            $vlan = ($i % 4094) + 1
            $null = Test-ValidVLANId -VLANId $vlan
        }
        $sw.Stop()
        Write-Verbose "Test-ValidVLANId x50000: $($sw.ElapsedMilliseconds) ms"
        $sw.ElapsedMilliseconds | Should -BeLessThan 10000 -Because "integer range check is trivial; large regressions should fail CI"
    }
}
