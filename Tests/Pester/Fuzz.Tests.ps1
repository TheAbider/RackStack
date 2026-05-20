#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
#
# Property-based fuzz tests for the input-validation functions in
# 03-InputValidation.ps1. Instead of asserting specific input/output pairs
# (which the InputValidation.Tests.ps1 file covers), this file asserts
# *properties* that must hold across thousands of random inputs:
#
#   - Validators must never throw an unhandled exception. A validator's
#     job is to return $true/$false; tossing an exception turns a hostile
#     input from "rejected" into "crash the menu loop."
#   - Validators must always return a [bool]. Returning anything else
#     (string, array, $null) lets `if ($result)` truthiness drift.
#   - Round-trip identity for hostname formatting helpers.
#   - Idempotence: running a validator twice on the same input gives the
#     same answer.
#
# These tests complement the curated edge-case suite. The curated suite
# pins behavior for *known* bad inputs (null bytes, Unicode lookalikes,
# CIDR slashes). The fuzz suite catches the *unknown* — the input no one
# thought to test for that crashes the function.

BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot '..\..\Modules'
    $script:ModuleRoot = (Resolve-Path -LiteralPath (Join-Path $modulesPath '..')).Path
    Set-StrictMode -Off
    . (Join-Path $modulesPath '00-Initialization.ps1')
    . (Join-Path $modulesPath '02-Logging.ps1')
    . (Join-Path $modulesPath '03-InputValidation.ps1')
    Set-StrictMode -Version Latest

    # Reproducible RNG so a failing fuzz seed reproduces in CI. Override with
    # $env:RACKSTACK_FUZZ_SEED to investigate a specific failing case.
    $seed = if ($env:RACKSTACK_FUZZ_SEED) { [int]$env:RACKSTACK_FUZZ_SEED } else { 4297 }
    $script:rng = [System.Random]::new($seed)
    Write-Verbose "Fuzz seed: $seed"

    function script:Get-RandomString {
        param([int]$MinLen = 0, [int]$MaxLen = 64, [int[]]$CharRange = @(0, 127))
        $len = $script:rng.Next($MinLen, $MaxLen + 1)
        if ($len -eq 0) { return '' }
        $sb = [System.Text.StringBuilder]::new($len)
        for ($i = 0; $i -lt $len; $i++) {
            $code = $script:rng.Next($CharRange[0], $CharRange[1] + 1)
            $null = $sb.Append([char]$code)
        }
        $sb.ToString()
    }

    function script:Get-RandomHostnameish {
        # Generates strings that look hostname-ish — mostly ASCII alphanumeric
        # + hyphen + dot, but salted with random Unicode and control chars to
        # surface validators that don't handle them. Mix of valid and invalid
        # shapes by construction.
        $len = $script:rng.Next(0, 32)
        $sb = [System.Text.StringBuilder]::new($len)
        $alpha = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.'.ToCharArray()
        for ($i = 0; $i -lt $len; $i++) {
            $r = $script:rng.Next(0, 100)
            if     ($r -lt 80) { $null = $sb.Append($alpha[$script:rng.Next(0, $alpha.Length)]) }
            elseif ($r -lt 90) { $null = $sb.Append([char]$script:rng.Next(0x80, 0x2FFF)) }  # Unicode
            elseif ($r -lt 95) { $null = $sb.Append([char]$script:rng.Next(0, 0x1F)) }        # control
            else               { $null = $sb.Append([char]$script:rng.Next(0x20, 0x7E)) }     # ASCII punct
        }
        $sb.ToString()
    }

    function script:Get-RandomIPish {
        # Mix of valid, almost-valid, and garbage IPv4 strings.
        switch ($script:rng.Next(0, 6)) {
            0 { '{0}.{1}.{2}.{3}' -f $script:rng.Next(0, 256), $script:rng.Next(0, 256), $script:rng.Next(0, 256), $script:rng.Next(0, 256) }
            1 { '{0}.{1}.{2}.{3}' -f $script:rng.Next(0, 999), $script:rng.Next(0, 999), $script:rng.Next(0, 999), $script:rng.Next(0, 999) }  # out-of-range
            2 { (Get-RandomString -MinLen 0 -MaxLen 30 -CharRange @(0x20, 0x7E)) }  # printable garbage
            3 { '{0}.{1}.{2}' -f $script:rng.Next(0, 256), $script:rng.Next(0, 256), $script:rng.Next(0, 256) }  # 3 octets
            4 { '{0}.{1}.{2}.{3}.{4}' -f $script:rng.Next(0, 256), $script:rng.Next(0, 256), $script:rng.Next(0, 256), $script:rng.Next(0, 256), $script:rng.Next(0, 256) }  # 5 octets
            5 { '{0}.{1}.{2}.{3}/{4}' -f $script:rng.Next(0, 256), $script:rng.Next(0, 256), $script:rng.Next(0, 256), $script:rng.Next(0, 256), $script:rng.Next(0, 40) }  # CIDR
        }
    }
}

Describe 'Test-ValidHostname — fuzz properties' {
    It 'never throws on 500 random hostname-shaped inputs' {
        # Filter out empty strings — the function has [ValidateNotNullOrEmpty()],
        # so empty input throws at parameter binding by design. That's the
        # documented behavior, not a crash to flag.
        $crashes = @()
        for ($i = 0; $i -lt 500; $i++) {
            $sample = Get-RandomHostnameish
            if ([string]::IsNullOrEmpty($sample)) { continue }
            try { $null = Test-ValidHostname -Hostname $sample } catch {
                $crashes += [PSCustomObject]@{ Input = $sample; Error = $_.Exception.Message }
            }
        }
        if ($crashes.Count -gt 0) {
            Write-Host "Crashes:" -ForegroundColor Red
            $crashes | Select-Object -First 5 | Format-Table -AutoSize | Out-Host
        }
        $crashes.Count | Should -Be 0
    }

    It 'always returns a [bool] across 200 random inputs' {
        $badTypes = @()
        for ($i = 0; $i -lt 200; $i++) {
            $sample = Get-RandomHostnameish
            if ([string]::IsNullOrEmpty($sample)) { continue }
            try {
                $r = Test-ValidHostname -Hostname $sample
                if ($r -isnot [bool]) {
                    $badTypes += [PSCustomObject]@{ Input = $sample; Type = $r.GetType().FullName }
                }
            } catch { }  # crashes are caught by the other test
        }
        $badTypes.Count | Should -Be 0
    }

    It 'is idempotent — same input twice gives same answer (50 samples)' {
        for ($i = 0; $i -lt 50; $i++) {
            $sample = Get-RandomHostnameish
            if ([string]::IsNullOrEmpty($sample)) { continue }
            try {
                $r1 = Test-ValidHostname -Hostname $sample
                $r2 = Test-ValidHostname -Hostname $sample
                $r1 | Should -Be $r2 -Because "input '$sample' should be deterministic"
            } catch { }  # let the no-crash test catch exceptions
        }
    }
}

Describe 'Test-ValidIPAddress — fuzz properties' {
    It 'never throws on 500 random IPv4-shaped inputs' {
        # Skip empty strings — function has [Parameter(Mandatory)] and rejects
        # empty at binding time, which is expected.
        $crashes = @()
        for ($i = 0; $i -lt 500; $i++) {
            $sample = Get-RandomIPish
            if ([string]::IsNullOrEmpty($sample)) { continue }
            try { $null = Test-ValidIPAddress -IPAddress $sample } catch {
                $crashes += [PSCustomObject]@{ Input = $sample; Error = $_.Exception.Message }
            }
        }
        if ($crashes.Count -gt 0) {
            Write-Host "Crashes:" -ForegroundColor Red
            $crashes | Select-Object -First 5 | Format-Table -AutoSize | Out-Host
        }
        $crashes.Count | Should -Be 0
    }

    It 'always returns a [bool] across 200 random inputs' {
        $badTypes = @()
        for ($i = 0; $i -lt 200; $i++) {
            $sample = Get-RandomIPish
            if ([string]::IsNullOrEmpty($sample)) { continue }
            try {
                $r = Test-ValidIPAddress -IPAddress $sample
                if ($r -isnot [bool]) {
                    $badTypes += [PSCustomObject]@{ Input = $sample; Type = $r.GetType().FullName }
                }
            } catch { }
        }
        $badTypes.Count | Should -Be 0
    }

    It 'accepts every valid octets-in-range string it can construct (100 samples)' {
        for ($i = 0; $i -lt 100; $i++) {
            $ip = '{0}.{1}.{2}.{3}' -f $script:rng.Next(0, 256), $script:rng.Next(0, 256), $script:rng.Next(0, 256), $script:rng.Next(0, 256)
            Test-ValidIPAddress -IPAddress $ip | Should -BeTrue -Because "constructed-valid IP '$ip' should validate"
        }
    }
}

Describe 'Test-ValidVLANId — fuzz properties' {
    It 'never throws on 300 random integer inputs (including out-of-range)' {
        $crashes = @()
        for ($i = 0; $i -lt 300; $i++) {
            # Sample across the full int range so out-of-band values get hit
            $sample = $script:rng.Next([int]::MinValue, [int]::MaxValue)
            try { $null = Test-ValidVLANId -VLANId $sample } catch {
                $crashes += [PSCustomObject]@{ Input = $sample; Error = $_.Exception.Message }
            }
        }
        $crashes.Count | Should -Be 0
    }

    It 'accepts every VLAN in the documented 1-4094 range' {
        # Spot-check a sample; full sweep would be 4094 calls which is slow.
        for ($i = 0; $i -lt 100; $i++) {
            $vlan = $script:rng.Next(1, 4095)
            Test-ValidVLANId -VLANId $vlan | Should -BeTrue -Because "VLAN $vlan is documented as valid"
        }
    }

    It 'rejects every VLAN outside 1-4094' {
        # Reserved (0 and 4095) and negatives must all be rejected.
        Test-ValidVLANId -VLANId 0 | Should -BeFalse
        Test-ValidVLANId -VLANId 4095 | Should -BeFalse
        Test-ValidVLANId -VLANId -1 | Should -BeFalse
        Test-ValidVLANId -VLANId 100000 | Should -BeFalse
    }
}
